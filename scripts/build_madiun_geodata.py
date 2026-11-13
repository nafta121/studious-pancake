#!/usr/bin/env python3
"""
Builds real-world WGS84 projected maps, administrative boundaries, rivers, railways,
road graphs, road offers, and industrial facilities for Karesidenan Madiun:
  1. karisidenan_madiun (Integrated 6-Region Campaign: Kota Madiun -> Kab. Madiun ->
     Kab. Magetan -> Kab. Ngawi -> Kab. Ponorogo -> Kab. Pacitan + Boomtown)
  2. kota_madiun   (27 Kelurahan urban grid, Kali Madiun seam, PT INKA & Ring Road Barat)
  3. kab_madiun    (15 Kecamatan: Caruban/Mejayan, Dumpil, Saradan, Dolopo, Kare)
  4. kab_magetan   (18 Kecamatan: Magetan, Maospati, Barat, Plaosan/Sarangan, Kawedanan)
  5. kab_ngawi     (19 Kecamatan: Ngawi Kartonyono, Tempuran Bengawan Solo, Paron, Walikukun)
  6. kab_ponorogo  (21 Kecamatan + real OSM arterial geometry: Alun-Alun, Sumoroto, Slahung, Ngebel)
  7. kab_pacitan   (12 Kecamatan + Indian Ocean Teluk Pacitan, Pelabuhan Tamperan Harbour & JLS)
"""

import json
import math
import os
import random
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW_CACHE = os.path.join(ROOT, "geodata", "karisidenan_madiun_wgs84.json")
OSRM_CACHE_PATH = os.path.join(ROOT, "geodata", "madiun_osrm_roads_cache.json")
OUT_JSON = os.path.join(ROOT, "data", "madiun_maps.json")
TMP_GIS = "/tmp/madiun_gis"

PROPOSED_BYPASS_OFFERS = {
    "offer_ring_timur",
    "offer_km_flyover",
    "offer_km_ringtimur",
    "offer_bypass_magetan",
    "off_mg_ring",
    "off_po_ring",
}


def load_osrm_cache():
    if os.path.exists(OSRM_CACHE_PATH):
        try:
            return json.load(open(OSRM_CACHE_PATH, "r", encoding="utf-8")).get("edges", {})
        except Exception:
            return {}
    return {}


OSRM_EDGES = load_osrm_cache()


def rdp(points, epsilon):
    """Ramer-Douglas-Peucker polyline simplification."""
    if len(points) < 3:
        return points
    x1, y1 = points[0]
    x2, y2 = points[-1]
    dx, dy = x2 - x1, y2 - y1
    norm = math.hypot(dx, dy)
    max_d = -1.0
    idx = 0
    for i in range(1, len(points) - 1):
        px, py = points[i]
        if norm < 1e-12:
            d = math.hypot(px - x1, py - y1)
        else:
            d = abs(dy * px - dx * py + x2 * y1 - y2 * x1) / norm
        if d > max_d:
            max_d = d
            idx = i
    if max_d > epsilon:
        left = rdp(points[: idx + 1], epsilon)
        right = rdp(points[idx:], epsilon)
        return left[:-1] + right
    return [points[0], points[-1]]


def extract_rings(geom):
    coords = geom["coordinates"]
    if geom["type"] == "Polygon":
        return [coords[0]]
    elif geom["type"] == "MultiPolygon":
        return [poly[0] for poly in coords]
    return []


def dissolve_outer_polygons(features, group_fn, simplify_deg=0.0045):
    """
    Exact topological half-edge cancelation on GeoJSON village polygons to recover
    clean outer boundaries per group (Regency or Kecamatan) without external C libs.
    """
    groups = defaultdict(list)
    centroids = defaultdict(list)
    for f in features:
        key = group_fn(f["properties"])
        for ring in extract_rings(f["geometry"]):
            groups[key].append(ring)
            for pt in ring:
                centroids[key].append((pt[1], pt[0]))  # (lat, lon)

    out_polys = {}
    out_centers = {}
    for key, rings in groups.items():
        pts = centroids[key]
        out_centers[key] = [
            round(sum(p[0] for p in pts) / len(pts), 5),
            round(sum(p[1] for p in pts) / len(pts), 5),
        ]
        edge_counts = defaultdict(int)
        pt_lookup = {}
        for ring in rings:
            snapped = [(round(p[0], 5), round(p[1], 5)) for p in ring]
            for i in range(len(snapped) - 1):
                a, b = snapped[i], snapped[i + 1]
                if a == b:
                    continue
                pt_lookup[a] = a
                pt_lookup[b] = b
                if edge_counts[(b, a)] > 0:
                    edge_counts[(b, a)] -= 1
                else:
                    edge_counts[(a, b)] += 1

        adj = defaultdict(list)
        for (a, b), c in edge_counts.items():
            for _ in range(c):
                adj[a].append(b)

        loops = []
        while adj:
            start = next(iter(adj))
            loop = [start]
            curr = start
            guard = 0
            while guard < 50000:
                guard += 1
                nxt_list = adj.get(curr)
                if not nxt_list:
                    break
                nxt = nxt_list.pop()
                if not nxt_list:
                    del adj[curr]
                if nxt == start:
                    loop.append(nxt)
                    break
                loop.append(nxt)
                curr = nxt
            if len(loop) >= 6:
                simp = rdp(loop, simplify_deg)
                if len(simp) >= 4:
                    # Compute approximate signed area to keep major rings
                    area = 0.0
                    for i in range(len(simp) - 1):
                        area += simp[i][0] * simp[i + 1][1] - simp[i + 1][0] * simp[i][1]
                    loops.append((abs(area) * 0.5, [[round(p[1], 5), round(p[0], 5)] for p in simp]))

        loops.sort(key=lambda x: x[0], reverse=True)
        # Keep main landmass ring(s)
        kept = [lp for ar, lp in loops[:2] if ar > 1e-6]
        if not kept and loops:
            kept = [loops[0][1]]
        out_polys[key] = kept

    return out_polys, out_centers


def extract_shared_seam(features, group_a_set, group_b_set):
    """Extracts shared boundary vertices between two sets of districts (e.g., Kali Madiun river seam!)."""
    pts_a = set()
    pts_b = []
    for f in features:
        d = f["properties"]["district"]
        for ring in extract_rings(f["geometry"]):
            for p in ring:
                sp = (round(p[1], 5), round(p[0], 5))
                if d in group_a_set:
                    pts_a.add(sp)
                elif d in group_b_set:
                    pts_b.append(sp)
    shared = sorted(set(p for p in pts_b if p in pts_a), key=lambda x: x[0])  # south to north
    if len(shared) < 2:
        return []
    simp = rdp(shared, 0.0008)
    return [[round(p[0], 5), round(p[1], 5)] for p in simp]


def build_or_load_raw_wgs84():
    if os.path.exists(RAW_CACHE) and not os.path.exists(os.path.join(TMP_GIS, "id3577_kota_madiun.geojson")):
        return json.load(open(RAW_CACHE))

    regency_files = {
        "kota_madiun": ("id3577_kota_madiun.geojson", "Kota Madiun", "id3577"),
        "kab_madiun": ("id3519_madiun.geojson", "Kabupaten Madiun", "id3519"),
        "kab_magetan": ("id3520_magetan.geojson", "Kabupaten Magetan", "id3520"),
        "kab_ngawi": ("id3521_ngawi.geojson", "Kabupaten Ngawi", "id3521"),
        "kab_ponorogo": ("id3502_ponorogo.geojson", "Kabupaten Ponorogo", "id3502"),
        "kab_pacitan": ("id3501_pacitan.geojson", "Kabupaten Pacitan", "id3501"),
    }

    regencies = {}
    kota_madiun_kali_seam = []

    for key, (fname, title, code) in regency_files.items():
        fpath = os.path.join(TMP_GIS, fname)
        data = json.load(open(fpath))
        feats = data["features"]
        outer_polys, outer_center = dissolve_outer_polygons(
            feats,
            lambda pr: key,
            simplify_deg=0.0012 if key == "kota_madiun" else 0.0055,
        )
        sub_fn = (lambda pr: pr["village"]) if key == "kota_madiun" else (lambda pr: pr["district"])
        sub_polys, sub_centers = dissolve_outer_polygons(
            feats,
            sub_fn,
            simplify_deg=0.0009 if key == "kota_madiun" else 0.0042,
        )
        if key == "kota_madiun":
            kota_madiun_kali_seam = extract_shared_seam(feats, {"Mangu Harjo"}, {"Kartoharjo", "Taman"})

        regencies[key] = {
            "title": title,
            "code": code,
            "center": outer_center[key],
            "polygons": outer_polys[key],
            "subunits": {
                k: {"center": sub_centers[k], "polygons": sub_polys[k]}
                for k in sorted(sub_centers.keys())
            },
        }

    # Extract real rivers in Karesidenan Madiun bbox
    bs_data = json.load(open(os.path.join(TMP_GIS, "bengawan_solo.geojson")))
    rivers_wgs = {}
    for f in bs_data["features"]:
        rid = f["properties"]["id"]
        if rid in {"RIV-MAINSTEM", "RIV-MADIUN", "RIV-GANDONG", "RIV-GRINDULU"}:
            pts = [[round(c[1], 5), round(c[0], 5)] for c in f["geometry"]["coordinates"]]
            rivers_wgs[rid] = {"name": f["properties"]["name"], "points": pts}

    # Extract real railway LineString clipped to Karesidenan Madiun (111.10..111.82E, -7.75..-7.34S)
    rail_data = json.load(open(os.path.join(TMP_GIS, "rail_malabar.geojson")))
    rail_pts = []
    for f in rail_data["features"]:
        geom = f["geometry"]
        if geom["type"] == "LineString":
            lines = [geom["coordinates"]]
        elif geom["type"] == "MultiLineString":
            lines = geom["coordinates"]
        else:
            continue
        for ln in lines:
            for c in ln:
                if 111.10 <= c[0] <= 111.82 and -7.70 <= c[1] <= -7.35:
                    rail_pts.append((round(c[1], 5), round(c[0], 5)))
    # Sort west-to-east along the Walikukun -> Paron -> Madiun -> Caruban -> Saradan corridor
    rail_pts_unique = sorted(set(rail_pts), key=lambda p: p[1])
    rail_simplified = [[p[0], p[1]] for p in rdp(rail_pts_unique, 0.0035)]

    # Extract major OSM trunk/primary/secondary roads from Ponorogo kenmap_jalan.geojson
    pon_osm = json.load(open(os.path.join(TMP_GIS, "kenmap_jalan.geojson")))
    pon_major = []
    for f in pon_osm["features"]:
        if f["geometry"]["type"] != "LineString":
            continue
        hw = f["properties"].get("highway", "")
        nm = f["properties"].get("name") or ""
        if hw in {"trunk", "primary", "secondary"} and len(f["geometry"]["coordinates"]) >= 2:
            pts = [[round(c[1], 5), round(c[0], 5)] for c in rdp(f["geometry"]["coordinates"], 0.0015)]
            pon_major.append({"name": nm, "highway": hw, "points": pts})

    bundle = {
        "attribution": "HDX-BPS-2020 Indonesia Administrative Boundaries + OpenStreetMap ODbL + BBWS Bengawan Solo",
        "regencies": regencies,
        "kota_madiun_kali_seam": kota_madiun_kali_seam,
        "rivers": rivers_wgs,
        "railway_mainline": rail_simplified,
        "ponorogo_osm_arterials_count": len(pon_major),
    }
    os.makedirs(os.path.dirname(RAW_CACHE), exist_ok=True)
    with open(RAW_CACHE, "w", encoding="utf-8") as fp:
        json.dump(bundle, fp, separators=(",", ":"))
    return bundle


class Projector:
    """Equirectangular metric-preserving projector centered on a map's WGS84 origin."""

    def __init__(self, center_lat: float, center_lon: float, scale: float):
        self.lat0 = center_lat
        self.lon0 = center_lon
        self.scale = scale
        self.cos_lat = math.cos(math.radians(center_lat))

    def proj(self, lat: float, lon: float):
        x = (lon - self.lon0) * self.cos_lat * self.scale
        y = -(lat - self.lat0) * self.scale
        return [round(x, 1), round(y, 1)]


def round2sig(val: float) -> int:
    if val <= 0:
        return 0
    if val < 100:
        return int(round(val))
    mag = 10 ** (int(math.floor(math.log10(val))) - 1)
    return int(round(val / mag) * mag)


def polyline_len(pts):
    total = 0.0
    for i in range(len(pts) - 1):
        total += math.hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
    return round(total, 1)


def curved_mid_points(p1, p2, bend=0.0):
    if abs(bend) < 1e-4:
        return [p1, p2]
    mx = (p1[0] + p2[0]) * 0.5
    my = (p1[1] + p2[1]) * 0.5
    dx = p2[0] - p1[0]
    dy = p2[1] - p1[1]
    nx, ny = -dy, dx
    p_mid = [mx + nx * bend, my + ny * bend]
    out = [p1]
    for k in range(1, 8):
        t = k / 8.0
        u = 1.0 - t
        bx = u * u * p1[0] + 2 * u * t * p_mid[0] + t * t * p2[0]
        by = u * u * p1[1] + 2 * u * t * p_mid[1] + t * t * p2[1]
        out.append([round(bx, 1), round(by, 1)])
    out.append(p2)
    return out


def point_to_seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    l2 = vx * vx + vy * vy
    if l2 < 1e-8:
        return math.hypot(px - ax, py - ay)
    t = max(0.0, min(1.0, ((px - ax) * vx + (py - ay) * vy) / l2))
    return math.hypot(px - (ax + t * vx), py - (ay + t * vy))


def chaikin_smooth(pts, passes=2):
    """Convex-hull-preserving corner-cutting B-spline subdivision keeping exact endpoints."""
    if len(pts) < 3:
        return pts
    cur = [[float(p[0]), float(p[1])] for p in pts]
    for _ in range(passes):
        if len(cur) < 3:
            break
        nxt = [cur[0]]
        for i in range(len(cur) - 1):
            a, b = cur[i], cur[i + 1]
            if i > 0:
                nxt.append([0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]])
            else:
                nxt.append([0.82 * a[0] + 0.18 * b[0], 0.82 * a[1] + 0.18 * b[1]])
            if i < len(cur) - 2:
                nxt.append([0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]])
            else:
                nxt.append([0.18 * a[0] + 0.82 * b[0], 0.18 * a[1] + 0.82 * b[1]])
        nxt.append(cur[-1])
        cur = nxt
    simp = rdp(cur, 0.42)
    return [[round(p[0], 1), round(p[1], 1)] for p in simp]


def sanitize_control_polyline(pts, max_deg=56.0, passes=6):
    """Relaxes sharp interior jogs (> max_deg) and collapses micro-segments before B-spline smoothing."""
    if len(pts) < 3:
        return pts
    cur = [[float(p[0]), float(p[1])] for p in pts]
    for _ in range(passes):
        if len(cur) < 3:
            break
        # Merge interior vertices closer than 10px to neighbors
        merged = [cur[0]]
        for p in cur[1:-1]:
            if math.hypot(p[0] - merged[-1][0], p[1] - merged[-1][1]) >= 10.0:
                merged.append(p)
        if len(merged) > 1 and math.hypot(cur[-1][0] - merged[-1][0], cur[-1][1] - merged[-1][1]) < 10.0:
            merged.pop()
        merged.append(cur[-1])
        cur = merged
        if len(cur) < 3:
            break

        changed = False
        nxt = [cur[0]]
        for i in range(1, len(cur) - 1):
            ax, ay = cur[i - 1]
            bx, by = cur[i]
            cx, cy = cur[i + 1]
            v1x, v1y = bx - ax, by - ay
            v2x, v2y = cx - bx, cy - by
            l1 = math.hypot(v1x, v1y)
            l2 = math.hypot(v2x, v2y)
            if l1 > 0.1 and l2 > 0.1:
                cos_a = max(-1.0, min(1.0, (v1x * v2x + v1y * v2y) / (l1 * l2)))
                ang = math.degrees(math.acos(cos_a))
                if ang > max_deg:
                    nxt.append([0.28 * ax + 0.44 * bx + 0.28 * cx, 0.28 * ay + 0.44 * by + 0.28 * cy])
                    changed = True
                    continue
            nxt.append([bx, by])
        nxt.append(cur[-1])
        cur = nxt
        if not changed:
            break
    return [[round(p[0], 1), round(p[1], 1)] for p in cur]


def condition_osrm_polyline(raw_latlon, p1, p2, u_id, v_id, j_map, proj: Projector, bend: float, offer_id):
    """Projects OSRM WGS84 road geometry, strips one-way hooks, guards unrelated junctions, and prepares control points."""
    if offer_id in PROPOSED_BYPASS_OFFERS or not raw_latlon or len(raw_latlon) < 2:
        return curved_mid_points(p1, p2, bend if abs(bend) > 0.02 else 0.06)

    straight_d = math.hypot(p2[0] - p1[0], p2[1] - p1[1])
    if straight_d < 16.0:
        return [p1, p2]

    ux = (p2[0] - p1[0]) / straight_d
    uy = (p2[1] - p1[1]) / straight_d

    proj_pts = [proj.proj(ll[0], ll[1]) for ll in raw_latlon]
    proj_pts[0] = [p1[0], p1[1]]
    proj_pts[-1] = [p2[0], p2[1]]

    # 1. Strip GPS approach micro-hooks and one-way street overshoots near endpoints
    stub_r = min(32.0, max(16.0, straight_d * 0.16))
    filtered = [proj_pts[0]]
    for pt in proj_pts[1:-1]:
        d1 = math.hypot(pt[0] - p1[0], pt[1] - p1[1])
        d2 = math.hypot(pt[0] - p2[0], pt[1] - p2[1])
        if d1 < stub_r or d2 < stub_r:
            continue
        # Reject one-way U-turn overshoots behind p1 or past p2 on short/medium roads
        along = (pt[0] - p1[0]) * ux + (pt[1] - p1[1]) * uy
        if straight_d < 260.0 and (along < 6.0 or along > straight_d - 6.0):
            continue
        if math.hypot(pt[0] - filtered[-1][0], pt[1] - filtered[-1][1]) >= 11.0:
            filtered.append(pt)
    filtered.append(proj_pts[-1])

    simp = rdp(filtered, 5.2)
    raw_len = polyline_len(simp)

    # 2. Guard excessive one-way block detours or routing directly over an unrelated junction
    max_detour = 1.48 if straight_d < 165.0 else 2.05
    if raw_len > straight_d * max_detour:
        return curved_mid_points(p1, p2, bend)

    # Reject paths that backtrack sharply against the chord on urban links
    if straight_d < 220.0:
        for i in range(len(simp) - 1):
            seg_dx = simp[i + 1][0] - simp[i][0]
            seg_dy = simp[i + 1][1] - simp[i][1]
            seg_l = math.hypot(seg_dx, seg_dy)
            if seg_l > 4.0 and (seg_dx * ux + seg_dy * uy) / seg_l < -0.25:
                return curved_mid_points(p1, p2, bend)

    other_js = [(j["x"], j["y"]) for jid, j in j_map.items() if jid != u_id and jid != v_id]
    for i in range(len(simp) - 1):
        ax, ay = simp[i]
        bx, by = simp[i + 1]
        for jx, jy in other_js:
            d = point_to_seg_dist(jx, jy, ax, ay, bx, by)
            if d < 12.5:
                # OSRM routed right through another graph node; use clean direct/bent arc instead
                return curved_mid_points(p1, p2, bend)

    # Gently push interior points away if within 25px of an unrelated junction
    adjusted = [simp[0]]
    for pt in simp[1:-1]:
        px, py = float(pt[0]), float(pt[1])
        for jx, jy in other_js:
            dx, dy = px - jx, py - jy
            dist = math.hypot(dx, dy)
            if 0.1 < dist < 25.0:
                push = 25.5 - dist
                px += (dx / dist) * push
                py += (dy / dist) * push
        adjusted.append([px, py])
    adjusted.append(simp[-1])

    return sanitize_control_polyline(adjusted, max_deg=56.0, passes=6)


def separate_junction_arm_tangents(junctions, e_map):
    """Ensures no two roads leave a junction along nearly identical tangents, then applies Chaikin smoothing."""
    min_sep_rad = math.radians(25.0)
    for j in junctions:
        jid = j["id"]
        jx, jy = float(j["x"]), float(j["y"])
        eids = j["connectedEdgeIds"]
        if len(eids) < 2:
            continue
        arms = []
        for eid in eids:
            r = e_map[eid]
            pts = r["points"]
            is_start = (r["from"] == jid)
            other_pt = pts[1] if is_start else pts[-2]
            ang = math.atan2(other_pt[1] - jy, other_pt[0] - jx)
            arms.append([ang, eid, is_start])
        arms.sort(key=lambda x: x[0])

        # Iterative angular relaxation if two adjacent arms are < 25 deg apart
        for _pass in range(4):
            changed = False
            n = len(arms)
            for i in range(n):
                a1 = arms[i]
                a2 = arms[(i + 1) % n]
                diff = a2[0] - a1[0]
                if i == n - 1:
                    diff += math.tau
                if diff < min_sep_rad:
                    nudge = (min_sep_rad - diff) * 0.52
                    a1[0] -= nudge
                    a2[0] += nudge
                    changed = True
            if not changed:
                break

        for ang, eid, is_start in arms:
            r = e_map[eid]
            pts = r["points"]
            straight_d = math.hypot(pts[-1][0] - pts[0][0], pts[-1][1] - pts[0][1])
            other_pt = pts[1] if is_start else pts[-2]
            cur_ang = math.atan2(other_pt[1] - jy, other_pt[0] - jx)
            delta = (ang - cur_ang + math.pi) % math.tau - math.pi
            if abs(delta) > math.radians(2.5) and straight_d >= 44.0:
                ctrl_d = min(28.0, straight_d * 0.25)
                clear_r = ctrl_d * 1.45
                cx = round(jx + math.cos(ang) * ctrl_d, 1)
                cy = round(jy + math.sin(ang) * ctrl_d, 1)
                # Strip ALL interior points within clear_r of (jx, jy) so inserting [cx, cy] NEVER creates a Z-fold!
                if is_start:
                    rem = [p for p in pts[1:-1] if math.hypot(p[0] - jx, p[1] - jy) >= clear_r]
                    pts = [pts[0], [cx, cy]] + rem + [pts[-1]]
                else:
                    rem = [p for p in pts[1:-1] if math.hypot(p[0] - jx, p[1] - jy) >= clear_r]
                    pts = [pts[0]] + rem + [[cx, cy], pts[-1]]
                r["points"] = pts

    # Final global pass: relax any sharp control corners and generate silky-smooth C1 Chaikin polylines!
    for r in e_map.values():
        ctrl_pts = sanitize_control_polyline(r["points"], max_deg=54.0, passes=6)
        r["points"] = chaikin_smooth(ctrl_pts, passes=3)
        r["lengthPx"] = polyline_len(r["points"])



def populate_city_blocks(junctions, roads, facilities, seed=4242):
    """Generates clean 2.5D Javanese town architecture & agricultural patches around real junctions/streets."""
    rng = random.Random(seed)
    buildings = []
    patches = []

    fac_positions = [(f["x"], f["y"]) for f in facilities]

    def clear_of_roads_and_facs(px, py, min_road=24.0, min_fac=46.0):
        for fx, fy in fac_positions:
            if math.hypot(px - fx, py - fy) < min_fac:
                return False
        for r in roads:
            pts = r["points"]
            for i in range(len(pts) - 1):
                ax, ay = pts[i]
                bx, by = pts[i + 1]
                vx, vy = bx - ax, by - ay
                wx, wy = px - ax, py - ay
                l2 = vx * vx + vy * vy
                t = max(0.0, min(1.0, (wx * vx + wy * vy) / l2)) if l2 > 1e-6 else 0.0
                cx, cy = ax + t * vx, ay + t * vy
                if math.hypot(px - cx, py - cy) < min_road:
                    return False
        return True

    terracotta_palette = ["#c96d4b", "#b85d3d", "#d47c57", "#a8563a", "#8c6249", "#6e7885"]
    wall_palette = ["#f2eadf", "#ebe1d3", "#e6dccb", "#dfe3e8"]

    # Place Alun-Alun green squares & Pendopo landmarks near named town junctions
    for j in junctions:
        jname = (j.get("name") or "").lower()
        reg_idx = j["regionIndex"]
        if "alun" in jname or "tugu" in jname or "pusat" in jname or "caruban" in jname or "kartonyono" in jname:
            for dx, dy in [(38, -38), (-38, 38), (42, 36)]:
                bx, by = j["x"] + dx, j["y"] + dy
                if clear_of_roads_and_facs(bx, by, 20.0, 42.0):
                    patches.append({
                        "x": round(bx, 1),
                        "y": round(by, 1),
                        "w": 34,
                        "h": 34,
                        "angle": 0.0,
                        "kind": "alun_alun",
                        "regionIndex": reg_idx,
                    })
                    buildings.append({
                        "x": round(bx, 1),
                        "y": round(by - 6, 1),
                        "w": 20,
                        "d": 16,
                        "angle": 0.0,
                        "h": 22,
                        "roofColor": "#9e472a",
                        "wallColor": "#f5efe4",
                        "kind": "pendopo",
                        "regionIndex": reg_idx,
                        "nightOn": round(rng.uniform(0.15, 0.35), 2),
                        "nightOff": round(rng.uniform(0.80, 0.98), 2),
                    })
                    break

    # Place buildings along built roads
    for r in roads:
        if not r["isBuilt"] or r["isBridge"]:
            continue
        pts = r["points"]
        reg_idx = r["regionIndex"]
        total_len = r["lengthPx"]
        steps = max(2, min(10, int(total_len // 68)))
        for s in range(1, steps):
            frac = s / steps
            idx = min(len(pts) - 2, int(frac * (len(pts) - 1)))
            ax, ay = pts[idx]
            bx, by = pts[idx + 1]
            ang = math.atan2(by - ay, bx - ax)
            nx, ny = -math.sin(ang), math.cos(ang)
            mx = (ax + bx) * 0.5
            my = (ay + by) * 0.5
            for side in (-1, 1):
                if rng.random() > 0.68:
                    continue
                dist = rng.uniform(28.0, 46.0) * side
                px = mx + nx * dist
                py = my + ny * dist
                if not clear_of_roads_and_facs(px, py, 21.0, 42.0):
                    continue
                is_urban = r["roadClass"] in ("municipal", "national")
                w = round(rng.uniform(13, 22 if is_urban else 17), 1)
                d = round(rng.uniform(11, 17), 1)
                h = round(rng.uniform(11, 24 if is_urban else 15), 1)
                buildings.append({
                    "x": round(px, 1),
                    "y": round(py, 1),
                    "w": w,
                    "d": d,
                    "angle": round(ang + (0 if side > 0 else math.pi), 2),
                    "h": h,
                    "roofColor": rng.choice(terracotta_palette),
                    "wallColor": rng.choice(wall_palette),
                    "kind": "shophouse" if is_urban and h > 16 else "house",
                    "regionIndex": reg_idx,
                    "nightOn": round(rng.uniform(0.12, 0.50), 2),
                    "nightOff": round(rng.uniform(0.65, 0.98), 2),
                })

        # Add regional landscape patches (sawah, jati forest, karst) further off-road
        if total_len > 110 and rng.random() < 0.65:
            ax, ay = pts[0]
            bx, by = pts[-1]
            ang = math.atan2(by - ay, bx - ax)
            nx, ny = -math.sin(ang), math.cos(ang)
            side = rng.choice([-1, 1])
            px = (ax + bx) * 0.5 + nx * side * rng.uniform(70, 115)
            py = (ay + by) * 0.5 + ny * side * rng.uniform(70, 115)
            if clear_of_roads_and_facs(px, py, 36.0, 56.0):
                p_kind = "sawah"
                if reg_idx in (2, 1) and rng.random() < 0.45:
                    p_kind = "jati"
                elif reg_idx == 5 and rng.random() < 0.55:
                    p_kind = "karst"
                patches.append({
                    "x": round(px, 1),
                    "y": round(py, 1),
                    "w": round(rng.uniform(48, 82), 1),
                    "h": round(rng.uniform(34, 58), 1),
                    "angle": round(ang * 0.5, 2),
                    "kind": p_kind,
                    "regionIndex": reg_idx,
                })

    return buildings[:420], patches[:90]


def make_facility(
    fid, name, local_ctx, kind, op, lat, lon, j_id, reg_idx, proj: Projector,
    output_good=None, accepted_goods=None, color="#3b78c2", roof="#b85d3d"
):
    px, py = proj.proj(lat, lon)
    return {
        "id": fid,
        "name": name,
        "localContext": local_ctx,
        "kind": kind,
        "op": op,
        "x": px,
        "y": py,
        "lat": round(lat, 5),
        "lon": round(lon, 5),
        "junctionId": j_id,
        "regionIndex": reg_idx,
        "outputGood": output_good,
        "acceptedGoods": accepted_goods or [],
        "color": color,
        "roofColor": roof,
        "upgrades": {
            "rate": 0,
            "expand": 0,
            "speed": 0,
            "buffer": 0,
            "bays": 1,
            "wideGate": 0,
            "exitRoad": 0,
            "trainLength": 0,
            "shipSize": 0,
            "timetable": 0,
        },
        "inputBuffers": {},
        "outputBuffer": 2 if kind == "supplier" else 0,
        "prodProgress": 0.0,
        "stalledReason": "none",
        "occupiedBays": 0,
        "vehicleTimer": 8.0,
        "vehiclePresent": True,
        "vehicleCapacityRemaining": 20 if kind == "station" else (40 if kind == "harbour" else 999),
        "deliveredWindow": {},
    }


def compile_graph(j_specs, e_specs, offer_specs, proj: Projector, map_id: str = ""):
    junctions = []
    j_map = {}
    for js in j_specs:
        jid, name, lat, lon, reg_idx, ctrl, landmark = js
        px, py = proj.proj(lat, lon)
        j_obj = {
            "id": jid,
            "name": name,
            "x": px,
            "y": py,
            "lat": round(lat, 5),
            "lon": round(lon, 5),
            "regionIndex": reg_idx,
            "control": ctrl,
            "yieldMinorEdgeIds": [],
            "connectedEdgeIds": [],
            "landmark": landmark,
        }
        if ctrl == "lights":
            j_obj["light"] = {
                "phaseAGreen": 10,
                "phaseBGreen": 10,
                "yellow": 1.0,
                "allRed": 1.0,
                "actuated": True,
                "sensorGap": 1.5,
                "currentPhase": 0,
                "stage": "green",
                "timer": 10.0,
                "greenElapsed": 0.0,
                "lastDetectorHit": 0.0,
            }
        junctions.append(j_obj)
        j_map[jid] = j_obj

    roads = []
    e_map = {}
    for es in e_specs:
        eid, name, u, v, rclass, reg_idx, lanes, bend, is_bridge, is_overpass, offer_id = es
        p1 = [j_map[u]["x"], j_map[u]["y"]]
        p2 = [j_map[v]["x"], j_map[v]["y"]]
        osrm_key = f"{map_id}:{eid}"
        raw_ll = OSRM_EDGES.get(osrm_key)
        pts = condition_osrm_polyline(raw_ll, p1, p2, u, v, j_map, proj, bend, offer_id)
        length = polyline_len(pts)
        r_obj = {
            "id": eid,
            "name": name,
            "from": u,
            "to": v,
            "points": pts,
            "lengthPx": length,
            "roadClass": rclass,
            "regionIndex": reg_idx,
            "lanesForward": lanes,
            "lanesBackward": lanes,
            "baseLanes": lanes,
            "pocketForward": 0,
            "pocketBackward": 0,
            "oneWay": 0,
            "closed": False,
            "isBridge": is_bridge,
            "isOverpass": is_overpass,
            "bridgeSpans": [],
            "overpassSpans": [],
            "isBuilt": offer_id is None,
            "offerId": offer_id,
            "congestionEMA": 0.0,
            "flowCountWindow": 0,
        }
        roads.append(r_obj)
        e_map[eid] = r_obj
        j_map[u]["connectedEdgeIds"].append(eid)
        j_map[v]["connectedEdgeIds"].append(eid)

    separate_junction_arm_tangents(junctions, e_map)

    offers = []
    for ospec in offer_specs:
        oid, name, sub, kind, edge_ids, reg_idx, houses, overpasses = ospec
        tot_len = sum(e_map[eid]["lengthPx"] for eid in edge_ids)
        bridge_len = sum(e_map[eid]["lengthPx"] * 0.45 for eid in edge_ids if e_map[eid]["isBridge"])
        raw_price = 0.88 * (100000 + 20 * tot_len + 60 * bridge_len + 3000 * houses + 60000 * overpasses)
        # Scale early-region bypasses reasonably so mobile sessions feel rewarding
        scaled_price = round2sig(raw_price * 0.22)
        offers.append({
            "id": oid,
            "name": name,
            "subtitle": sub,
            "kind": kind,
            "edgeIds": edge_ids,
            "regionIndex": reg_idx,
            "lengthPx": round(tot_len, 1),
            "bridgeSpanPx": round(bridge_len, 1),
            "housesDisplaced": houses,
            "overpasses": overpasses,
            "price": scaled_price,
            "purchased": False,
        })

    return junctions, roads, offers


def build_integrated_karisidenan_map(raw):
    """Map 1: Full 6-Region Karesidenan Madiun Progressive Campaign."""
    proj = Projector(center_lat=-7.74, center_lon=111.43, scale=2350.0)

    region_order = [
        ("kota_madiun", "Kota Madiun", "Wilayah 1 · Pusat Industri & Perkeretaapian", "#d96b43", "rgba(217,107,67,0.10)", True, [
            {"good": "capsule", "targetPerMin": 3.0, "currentPerMin": 0},
            {"good": "bar", "targetPerMin": 3.0, "currentPerMin": 0},
        ]),
        ("kab_madiun", "Kabupaten Madiun", "Wilayah 2 · Poros Caruban, Tol Dumpil & Wilis", "#4a9658", "rgba(74,150,88,0.10)", False, [
            {"good": "diamond", "targetPerMin": 3.0, "currentPerMin": 0},
            {"good": "drop", "targetPerMin": 3.0, "currentPerMin": 0},
        ]),
        ("kab_magetan", "Kabupaten Magetan", "Wilayah 3 · Simpang Maospati & Kaki Gunung Lawu", "#c98b32", "rgba(201,139,50,0.10)", False, [
            {"good": "moon", "targetPerMin": 3.0, "currentPerMin": 0},
            {"good": "star", "targetPerMin": 3.0, "currentPerMin": 0},
        ]),
        ("kab_ngawi", "Kabupaten Ngawi", "Wilayah 4 · Tempuran Bengawan Solo & Kartonyono", "#3c8da6", "rgba(60,141,166,0.10)", False, [
            {"good": "chevron", "targetPerMin": 3.0, "currentPerMin": 0},
            {"good": "candle", "targetPerMin": 3.0, "currentPerMin": 0},
        ]),
        ("kab_ponorogo", "Kabupaten Ponorogo", "Wilayah 5 · Bumi Reog, Sumoroto & Lembah Ngebel", "#9b5eb8", "rgba(155,94,184,0.10)", False, [
            {"good": "paddle", "targetPerMin": 3.0, "currentPerMin": 0},
            {"good": "cart", "targetPerMin": 3.0, "currentPerMin": 0},
        ]),
        ("kab_pacitan", "Kabupaten Pacitan", "Wilayah 6 · Teluk Pacitan, Pelabuhan Tamperan & JLS", "#2f74ba", "rgba(47,116,186,0.10)", False, [
            {"good": "gem", "targetPerMin": 3.0, "currentPerMin": 0},
            {"good": "fish", "targetPerMin": 3.0, "currentPerMin": 0},
            {"good": "bus", "targetPerMin": 3.0, "currentPerMin": 0},
        ]),
    ]

    regions = []
    for idx, (rkey, kab_name, sub, accent, fill, unlocked, goals) in enumerate(region_order):
        rinfo = raw["regencies"][rkey]
        polys = [[proj.proj(pt[0], pt[1]) for pt in ring] for ring in rinfo["polygons"]]
        regions.append({
            "index": idx,
            "id": rkey,
            "name": kab_name,
            "kabKota": kab_name,
            "subtitle": sub,
            "regencyCode": rinfo["code"],
            "accentColor": accent,
            "fillColor": fill,
            "unlocked": unlocked,
            "unlockedAtRealSec": 0 if unlocked else -1,
            "polygons": polys,
            "center": proj.proj(rinfo["center"][0], rinfo["center"][1]),
            "goals": goals,
            "holdSeconds": 0.0,
        })

    # Real water bodies: Samudra Hindia south of Pacitan + Telaga Sarangan + Telaga Ngebel
    ocean_latlon = [
        [-8.21, 110.82], [-8.22, 110.95], [-8.24, 111.06], [-8.225, 111.105],
        [-8.205, 111.115], [-8.23, 111.135], [-8.255, 111.22], [-8.26, 111.34],
        [-8.28, 111.46], [-8.42, 111.48], [-8.42, 110.82], [-8.21, 110.82],
    ]
    sarangan_latlon = [[-7.672, 111.213], [-7.672, 111.224], [-7.680, 111.224], [-7.680, 111.213]]
    ngebel_latlon = [[-7.785, 111.640], [-7.785, 111.656], [-7.798, 111.656], [-7.798, 111.640]]

    water_bodies = [
        {"id": "samudra_hindia", "name": "Samudra Hindia & Teluk Pacitan", "kind": "ocean", "polygon": [proj.proj(a, b) for a, b in ocean_latlon]},
        {"id": "telaga_sarangan", "name": "Telaga Sarangan (Lawu)", "kind": "lake", "polygon": [proj.proj(a, b) for a, b in sarangan_latlon]},
        {"id": "telaga_ngebel", "name": "Telaga Ngebel (Wilis)", "kind": "lake", "polygon": [proj.proj(a, b) for a, b in ngebel_latlon]},
    ]

    rivers = []
    for rid, width in [("RIV-MAINSTEM", 22), ("RIV-MADIUN", 16), ("RIV-GANDONG", 11), ("RIV-GRINDULU", 13)]:
        if rid in raw["rivers"]:
            pts = [proj.proj(p[0], p[1]) for p in raw["rivers"][rid]["points"] if -8.35 <= p[0] <= -7.22 and 110.85 <= p[1] <= 111.88]
            if len(pts) >= 2:
                rivers.append({"id": rid.lower(), "name": raw["rivers"][rid]["name"], "widthPx": width, "points": pts})

    railways = [{
        "id": "ka_lintas_selatan",
        "name": "Jalur KA Lintas Selatan Jawa (Walikukun–Madiun–Caruban)",
        "points": [proj.proj(p[0], p[1]) for p in raw["railway_mainline"]],
    }]

    # Real WGS84 Junctions across all 6 Regions of Karesidenan Madiun
    j_specs = [
        # Region 0: Kota Madiun (expanded slightly in urban core for clean touch selection while anchored to real GPS)
        ("mdn_tugu", "Tugu 0 KM Jl. Pahlawan", -7.6285, 111.5235, 0, "lights", "Pusat Kota Madiun"),
        ("mdn_stasiun", "Simpang Stasiun & PT INKA", -7.6145, 111.5260, 0, "none", "Stasiun Besar Madiun"),
        ("mdn_ringbarat", "Simpang Ring Road Barat (Winongo)", -7.6260, 111.5015, 0, "roundabout", "Ring Road Barat"),
        ("mdn_sogaten", "Simpang Sogaten–Manguharjo", -7.6015, 111.5120, 0, "none", None),
        ("mdn_rejoagung", "Simpang Rejo Agung & Pilangbango", -7.6120, 111.5495, 0, "yield", "PG Rejo Agung"),
        ("mdn_tean", "Simpang Te'an & Taman", -7.6485, 111.5255, 0, "lights", "Bundaran Taman"),
        ("mdn_manisrejo", "Simpang Kanigoro–Manisrejo", -7.6385, 111.5490, 0, "none", None),

        # Region 1: Kabupaten Madiun
        ("kbm_dumpil", "Simpang Dumpil (GT Madiun)", -7.5680, 111.5560, 1, "roundabout", "Gerbang Tol Madiun"),
        ("kbm_jiwan", "Simpang Jiwan", -7.6130, 111.4810, 1, "none", None),
        ("kbm_wonoasri", "Simpang Wonoasri–Balerejo", -7.5620, 111.6180, 1, "none", None),
        ("kbm_caruban", "Simpang Empat Caruban (Mejayan)", -7.5490, 111.6560, 1, "lights", "Pusat Kab. Madiun"),
        ("kbm_saradan", "Simpang Hutan Jati Saradan", -7.5470, 111.7380, 1, "none", "Alas Saradan"),
        ("kbm_wungu", "Simpang Dungus–Wungu", -7.6560, 111.5880, 1, "none", None),
        ("kbm_kare", "Lereng Wilis Kare", -7.7090, 111.6680, 1, "none", "Perkebunan Kare"),
        ("kbm_pagotan", "Simpang Pagotan–Geger", -7.6990, 111.5270, 1, "none", "PG Pagotan"),
        ("kbm_dolopo", "Simpang Dolopo", -7.7680, 111.5160, 1, "yield", "Pasar Dolopo"),

        # Region 2: Kabupaten Magetan
        ("mgt_maospati", "Simpang Tiga Maospati", -7.5965, 111.4440, 2, "lights", "Lanud Iswahjudi"),
        ("mgt_barat", "Simpang Stasiun Barat & Karangrejo", -7.5560, 111.4480, 2, "none", "Stasiun Barat"),
        ("mgt_sukomoro", "Simpang Sukomoro", -7.6240, 111.3850, 2, "none", None),
        ("mgt_kota", "Alun-Alun Kota Magetan", -7.6495, 111.3310, 2, "roundabout", "Pusat Kota Magetan"),
        ("mgt_plaosan", "Simpang Plaosan–Sarangan", -7.6740, 111.2490, 2, "none", "Gerbang Lawu"),
        ("mgt_kawedanan", "Simpang Kawedanan (Goranggareng)", -7.6930, 111.4090, 2, "none", None),
        ("mgt_lembeyan", "Simpang Lembeyan", -7.7550, 111.4040, 2, "none", None),

        # Region 3: Kabupaten Ngawi
        ("ngw_geneng", "Simpang Geneng", -7.4860, 111.4410, 3, "none", None),
        ("ngw_paron", "Simpang Stasiun Paron", -7.4540, 111.3750, 3, "none", "Stasiun Paron"),
        ("ngw_kartonyono", "Tugu Kartonyono Ngawi", -7.4055, 111.4445, 3, "lights", "Benteng Pendem & Tempuran"),
        ("ngw_karangjati", "Simpang Karangjati–Caruban", -7.4580, 111.6010, 3, "yield", None),
        ("ngw_kwadungan", "Simpang Kwadungan–Pangkur", -7.5060, 111.5180, 3, "none", None),
        ("ngw_walikukun", "Simpang Walikukun (Widodaren)", -7.4110, 111.2320, 3, "lights", "Stasiun Walikukun"),
        ("ngw_mantingan", "Gerbang Mantingan (Batas Jateng)", -7.3860, 111.1580, 3, "none", None),
        ("ngw_jogorogo", "Simpang Jogorogo–Ngrambe", -7.5260, 111.2480, 3, "none", "Kebun Teh Jamus"),

        # Region 4: Kabupaten Ponorogo
        ("png_babadan", "Simpang Babadan Ponorogo", -7.8220, 111.4810, 4, "none", None),
        ("png_kota", "Alun-Alun Kota Ponorogo", -7.8670, 111.4625, 4, "roundabout", "Patung Reog Ponorogo"),
        ("png_sumoroto", "Simpang Sumoroto (Kauman)", -7.8840, 111.4050, 4, "yield", None),
        ("png_badegan", "Simpang Badegan–Sampung", -7.8880, 111.3280, 4, "none", None),
        ("png_jetis", "Simpang Dengok–Jetis", -7.9340, 111.4720, 4, "lights", None),
        ("png_balong", "Simpang Balong", -7.9530, 111.4180, 4, "none", None),
        ("png_slahung", "Simpang Slahung", -8.0130, 111.4070, 4, "none", "Gerbang Selatan Ponorogo"),
        ("png_pulung", "Simpang Pulung–Ngebel", -7.8680, 111.6150, 4, "none", "Lereng Telaga Ngebel"),

        # Region 5: Kabupaten Pacitan
        ("pct_tegalombo", "Simpang Tegalombo", -8.0560, 111.3040, 5, "none", None),
        ("pct_arjosari", "Simpang Arjosari", -8.1110, 111.1590, 5, "yield", None),
        ("pct_kota", "Alun-Alun Kota Pacitan", -8.1945, 111.1045, 5, "lights", "Pusat Kota Pacitan"),
        ("pct_tamperan", "Kawasan Pelabuhan Tamperan", -8.2160, 111.0880, 5, "none", "Pelabuhan Samudra Tamperan"),
        ("pct_punung", "Simpang Punung (Goa Gong)", -8.1150, 111.0350, 5, "none", "Kawasan Kars Gunungsewu"),
        ("pct_donorojo", "Simpang Donorojo (JLS Barat)", -8.1510, 110.9490, 5, "none", None),
        ("pct_tulakan", "Simpang Tulakan (JLS Tengah)", -8.1720, 111.2680, 5, "none", None),
        ("pct_ngadirojo", "Simpang Lorok–Ngadirojo (JLS Timur)", -8.1960, 111.3350, 5, "none", None),
    ]

    e_specs = [
        # Region 0: Kota Madiun streets
        ("e_mdn_pahlawan", "Jl. Pahlawan – Jl. Cokroaminoto", "mdn_stasiun", "mdn_tugu", "municipal", 0, 2, 0.0, False, False, None),
        ("e_mdn_urip", "Jl. Urip Sumoharjo – Jl. S. Parman", "mdn_tugu", "mdn_tean", "municipal", 0, 2, 0.0, False, False, None),
        ("e_mdn_basuki", "Jl. Basuki Rahmat – Sukosari", "mdn_stasiun", "mdn_rejoagung", "municipal", 0, 1, -0.06, False, False, None),
        ("e_mdn_kanigoro", "Jl. Kapten Saputra – Kanigoro", "mdn_rejoagung", "mdn_manisrejo", "municipal", 0, 1, 0.05, False, False, None),
        ("e_mdn_setiabudi", "Jl. Setia Budi – Mojorejo", "mdn_tugu", "mdn_manisrejo", "municipal", 0, 1, 0.0, False, False, None),
        ("e_mdn_soekarno", "Jl. Soekarno-Hatta – Banjarejo", "mdn_tean", "mdn_manisrejo", "municipal", 0, 2, 0.04, False, False, None),
        ("e_mdn_manguharjo", "Jl. Hayam Wuruk & Jembatan Manguharjo", "mdn_tugu", "mdn_ringbarat", "national", 0, 2, 0.0, True, False, None),
        ("e_mdn_ringbarat_n", "Jl. Ring Road Barat (Winongo–Sogaten)", "mdn_ringbarat", "mdn_sogaten", "national", 0, 2, -0.08, False, False, None),
        ("e_mdn_sogaten_st", "Jl. Yos Sudarso & Jembatan Patihan", "mdn_sogaten", "mdn_stasiun", "municipal", 0, 1, 0.04, True, False, None),
        ("e_mdn_ringbarat_s", "Jl. Ring Road Barat Selatan – Jembatan Ngujang", "mdn_ringbarat", "mdn_tean", "national", 0, 2, 0.10, True, False, None),
        # Offer 0: Ring Road Timur Kota Madiun
        ("e_offer_ringtimur_1", "Jl. Ring Road Timur Madiun (Pilangbango–Demangan)", "mdn_rejoagung", "mdn_tean", "toll", 0, 2, 0.22, False, True, "offer_ring_timur"),

        # Region 1: Kabupaten Madiun roads
        ("e_kbm_nglames", "Jl. Raya Madiun–Surabaya (Nglames)", "mdn_rejoagung", "kbm_dumpil", "national", 1, 2, -0.04, False, False, None),
        ("e_kbm_sawahan", "Jl. Raya Sawahan–Madiun", "mdn_sogaten", "kbm_dumpil", "provincial", 1, 1, -0.06, False, False, None),
        ("e_kbm_jiwan", "Jl. Nasional Madiun–Maospati (Jiwan)", "mdn_ringbarat", "kbm_jiwan", "national", 1, 2, 0.0, False, False, None),
        ("e_kbm_balerejo", "Jl. Nasional Dumpil–Balerejo", "kbm_dumpil", "kbm_wonoasri", "national", 1, 2, 0.0, False, False, None),
        ("e_kbm_caruban", "Jl. Panglima Sudirman Caruban", "kbm_wonoasri", "kbm_caruban", "national", 1, 2, 0.0, False, False, None),
        ("e_kbm_saradan", "Jl. Nasional Caruban–Saradan", "kbm_caruban", "kbm_saradan", "national", 1, 2, 0.05, False, False, None),
        ("e_kbm_wungu", "Jl. Raya Dungus–Wungu", "mdn_manisrejo", "kbm_wungu", "provincial", 1, 1, 0.0, False, False, None),
        ("e_kbm_wungu_car", "Jl. Lereng Wilis (Wungu–Wonoasri)", "kbm_wungu", "kbm_wonoasri", "local", 1, 1, 0.08, False, False, None),
        ("e_kbm_kare", "Jl. Raya Dungus–Kare", "kbm_wungu", "kbm_kare", "local", 1, 1, 0.06, False, False, None),
        ("e_kbm_pagotan", "Jl. Nasional Madiun–Ponorogo (Pagotan)", "mdn_tean", "kbm_pagotan", "national", 1, 2, 0.0, False, False, None),
        ("e_kbm_dolopo", "Jl. Nasional Geger–Dolopo", "kbm_pagotan", "kbm_dolopo", "national", 1, 2, 0.0, False, False, None),
        # Offer 1: Jalan Tol Trans-Jawa Ruas Madiun–Caruban
        ("e_offer_tol_caruban", "Jalan Tol Trans-Jawa (GT Madiun – GT Caruban)", "kbm_dumpil", "kbm_caruban", "toll", 1, 2, -0.18, True, True, "offer_tol_madiun_caruban"),

        # Region 2: Kabupaten Magetan roads
        ("e_mgt_jiwan_mao", "Jl. Nasional Jiwan–Maospati", "kbm_jiwan", "mgt_maospati", "national", 2, 2, 0.0, False, False, None),
        ("e_mgt_mao_barat", "Jl. Raya Maospati–Barat", "mgt_maospati", "mgt_barat", "provincial", 2, 1, 0.0, False, False, None),
        ("e_mgt_mao_suko", "Jl. Raya Maospati–Sukomoro", "mgt_maospati", "mgt_sukomoro", "provincial", 2, 2, 0.0, False, False, None),
        ("e_mgt_suko_kota", "Jl. Raya Sukomoro–Kota Magetan", "mgt_sukomoro", "mgt_kota", "provincial", 2, 2, 0.0, True, False, None),
        ("e_mgt_plaosan", "Jl. Raya Magetan–Plaosan–Sarangan", "mgt_kota", "mgt_plaosan", "provincial", 2, 1, 0.07, False, False, None),
        ("e_mgt_kawedanan", "Jl. Raya Magetan–Kawedanan", "mgt_kota", "mgt_kawedanan", "provincial", 2, 1, -0.05, False, False, None),
        ("e_mgt_gorang_mdn", "Jl. Raya Goranggareng–Madiun (Takeran)", "mgt_kawedanan", "kbm_pagotan", "provincial", 2, 1, 0.0, True, False, None),
        ("e_mgt_lembeyan", "Jl. Raya Kawedanan–Lembeyan", "mgt_kawedanan", "mgt_lembeyan", "local", 2, 1, 0.0, False, False, None),
        # Offer 2: Jalan Lingkar Maospati–Kawedanan
        ("e_offer_bypass_mgt", "Bypass Selatan Maospati–Kawedanan", "mgt_maospati", "mgt_kawedanan", "toll", 2, 2, 0.10, False, True, "offer_bypass_magetan"),

        # Region 3: Kabupaten Ngawi roads
        ("e_ngw_barat_gen", "Jl. Nasional Maospati–Ngawi (Geneng)", "mgt_barat", "ngw_geneng", "national", 3, 2, 0.0, False, False, None),
        ("e_ngw_gen_karto", "Jl. Nasional Geneng–Kartonyono Ngawi", "ngw_geneng", "ngw_kartonyono", "national", 3, 2, 0.0, True, False, None),
        ("e_ngw_paron", "Jl. Raya Geneng–Paron", "ngw_geneng", "ngw_paron", "local", 3, 1, -0.05, False, False, None),
        ("e_ngw_paron_karto", "Jl. Siliwangi Paron–Ngawi", "ngw_paron", "ngw_kartonyono", "provincial", 3, 1, 0.04, False, False, None),
        ("e_ngw_walikukun", "Jl. Nasional Ngawi–Solo (Kedunggalar–Walikukun)", "ngw_kartonyono", "ngw_walikukun", "national", 3, 2, 0.05, True, False, None),
        ("e_ngw_mantingan", "Jl. Nasional Walikukun–Mantingan", "ngw_walikukun", "ngw_mantingan", "national", 3, 2, 0.0, False, False, None),
        ("e_ngw_jogorogo", "Jl. Raya Paron–Jogorogo–Lawu Utara", "ngw_paron", "ngw_jogorogo", "local", 3, 1, -0.06, False, False, None),
        ("e_ngw_jogo_wali", "Jl. Lereng Utara Ngrambe–Walikukun", "ngw_jogorogo", "ngw_walikukun", "local", 3, 1, 0.05, False, False, None),
        ("e_ngw_karangjati", "Jl. Nasional Ngawi–Caruban (Padas–Karangjati)", "ngw_kartonyono", "ngw_karangjati", "national", 3, 2, -0.04, True, False, None),
        ("e_ngw_krj_caruban", "Jl. Nasional Karangjati–Caruban", "ngw_karangjati", "kbm_caruban", "national", 3, 2, 0.0, False, False, None),
        ("e_ngw_kwadungan", "Jl. Poros Kwadungan–Sawahan", "ngw_geneng", "kbm_dumpil", "local", 3, 1, 0.04, True, False, None),
        # Offer 3: Jalan Tol Solo–Ngawi–Madiun
        ("e_offer_tol_ngawi", "Jalan Tol Trans-Jawa (GT Ngawi – GT Madiun)", "ngw_kartonyono", "kbm_dumpil", "toll", 3, 2, 0.14, True, True, "offer_tol_ngawi_madiun"),

        # Region 4: Kabupaten Ponorogo roads
        ("e_png_dol_bab", "Jl. Nasional Madiun–Ponorogo (Mlilir–Babadan)", "kbm_dolopo", "png_babadan", "national", 4, 2, 0.0, True, False, None),
        ("e_png_bab_kota", "Jl. Soekarno-Hatta Ponorogo", "png_babadan", "png_kota", "national", 4, 2, 0.0, False, False, None),
        ("e_png_lem_sumo", "Jl. Raya Lembeyan–Sumoroto", "mgt_lembeyan", "png_sumoroto", "provincial", 4, 1, 0.0, False, False, None),
        ("e_png_kota_sumo", "Jl. Jend. Sudirman – Sumoroto", "png_kota", "png_sumoroto", "national", 4, 2, 0.0, True, False, None),
        ("e_png_badegan", "Jl. Nasional Sumoroto–Badegan (Batas Wonogiri)", "png_sumoroto", "png_badegan", "national", 4, 2, 0.0, False, False, None),
        ("e_png_dengok", "Jl. HOS Cokroaminoto – Dengok Jetis", "png_kota", "png_jetis", "national", 4, 2, 0.0, False, False, None),
        ("e_png_balong", "Jl. Nasional Dengok–Balong", "png_jetis", "png_balong", "national", 4, 2, 0.04, True, False, None),
        ("e_png_sumo_bal", "Jl. Poros Jambon–Balong", "png_sumoroto", "png_balong", "local", 4, 1, -0.05, False, False, None),
        ("e_png_slahung", "Jl. Nasional Balong–Slahung", "png_balong", "png_slahung", "national", 4, 2, 0.0, False, False, None),
        ("e_png_pulung", "Jl. Raya Ponorogo–Pulung–Ngebel", "png_kota", "png_pulung", "provincial", 4, 1, -0.06, False, False, None),
        ("e_png_kare_pul", "Jl. Sabuk Wilis (Kare–Ngebel–Pulung)", "kbm_kare", "png_pulung", "local", 4, 1, 0.08, False, False, None),

        # Region 5: Kabupaten Pacitan roads
        ("e_pct_tegalombo", "Jl. Nasional Ponorogo–Pacitan (Slahung–Tegalombo)", "png_slahung", "pct_tegalombo", "national", 5, 2, 0.08, False, False, None),
        ("e_pct_arjosari", "Jl. Nasional Tegalombo–Arjosari (Kali Grindulu)", "pct_tegalombo", "pct_arjosari", "national", 5, 2, -0.06, True, False, None),
        ("e_pct_kota", "Jl. Nasional Arjosari–Kota Pacitan", "pct_arjosari", "pct_kota", "national", 5, 2, 0.0, True, False, None),
        ("e_pct_tamperan", "Jl. Raya Teluk Pacitan – Pelabuhan Tamperan", "pct_kota", "pct_tamperan", "municipal", 5, 2, 0.05, False, False, None),
        ("e_pct_punung", "Jl. Raya Pacitan–Pringkuku–Punung", "pct_kota", "pct_punung", "provincial", 5, 1, -0.08, False, False, None),
        ("e_pct_donorojo", "Jl. Raya Punung–Donorojo (Goa Gong)", "pct_punung", "pct_donorojo", "provincial", 5, 1, 0.0, False, False, None),
        ("e_pct_bad_pun", "Jl. Lintas Barat Badegan–Nawangan–Arjosari", "png_badegan", "pct_arjosari", "local", 5, 1, -0.09, False, False, None),
        ("e_pct_jls_1", "Jalur Lintas Selatan (JLS Kota Pacitan–Tulakan)", "pct_kota", "pct_tulakan", "national", 5, 2, 0.09, True, False, None),
        ("e_pct_jls_2", "Jalur Lintas Selatan (JLS Tulakan–Lorok Ngadirojo)", "pct_tulakan", "pct_ngadirojo", "national", 5, 2, 0.05, True, False, None),
        # Offer 4: JLS Barat Samudra (Donorojo – Pelabuhan Tamperan)
        ("e_offer_jls_barat", "Terusan JLS Pantai Selatan (Donorojo–Tamperan)", "pct_donorojo", "pct_tamperan", "toll", 5, 2, 0.14, True, False, "offer_jls_pacitan"),
    ]

    offer_specs = [
        ("offer_ring_timur", "Ring Road Timur Kota Madiun", "Memotong antrean Jl. Pahlawan & Basuki Rahmat dari Rejo Agung ke Bundaran Taman", "ring", ["e_offer_ringtimur_1"], 0, 8, 1),
        ("offer_tol_madiun_caruban", "Jalan Tol Madiun–Caruban", "Ruas bebas hambatan Dumpil ke Mejayan/Caruban melintasi sawah Balerejo", "toll", ["e_offer_tol_caruban"], 1, 5, 2),
        ("offer_bypass_magetan", "Bypass Maospati–Kawedanan", "Jalur cepat logistik selatan melewati kepadatan Sukomoro & Alun-Alun Magetan", "bypass", ["e_offer_bypass_mgt"], 2, 6, 1),
        ("offer_tol_ngawi_madiun", "Jalan Tol Ngawi–Madiun", "Poros kecepatan tinggi Trans-Jawa dari Kartonyono Ngawi langsung ke GT Dumpil", "toll", ["e_offer_tol_ngawi"], 3, 7, 2),
        ("offer_jls_pacitan", "Terusan JLS Pantai Barat Pacitan", "Jalur Lintas Selatan tepi tebing kars Donorojo langsung ke Pelabuhan Tamperan", "jls", ["e_offer_jls_barat"], 5, 4, 1),
    ]

    junctions, roads, offers = compile_graph(j_specs, e_specs, offer_specs, proj, "karisidenan_madiun")

    facilities = [
        # Region 0: Kota Madiun (self-sufficient starter economy: Dot, Wedge, Block -> Capsule, Bar -> Stasiun Madiun!)
        make_facility("f_mdn_tani", "Sentra Tebu & Padi Nambangan", "Supplier Hulu Manguharjo", "supplier", "raw", -7.6380, 111.4950, "mdn_ringbarat", 0, proj, output_good="dot", color="#4ea854", roof="#487d49"),
        make_facility("f_mdn_kayu", "Depo Kayu Jati Sogaten", "Supplier Hulu Sogaten", "supplier", "raw", -7.5940, 111.5080, "mdn_sogaten", 0, proj, output_good="wedge", color="#d9833b", roof="#965624"),
        make_facility("f_mdn_batu", "Depo Material & Batu Manisrejo", "Supplier Hulu Taman Timur", "supplier", "raw", -7.6460, 111.5560, "mdn_manisrejo", 0, proj, output_good="block", color="#5b82b8", roof="#3c5c87"),
        make_facility("f_mdn_rejoagung", "PG Rejo Agung Baru", "Pabrik Press Gula Kristal (2 Dot → Capsule)", "factory", "press", -7.6060, 111.5550, "mdn_rejoagung", 0, proj, output_good="capsule", accepted_goods=["dot"], color="#5ec269", roof="#b85d3d"),
        make_facility("f_mdn_baja", "Tempa Baja Banjarejo", "Pabrik Press Profil Baja (2 Block → Bar)", "factory", "press", -7.6560, 111.5290, "mdn_tean", 0, proj, output_good="bar", accepted_goods=["block"], color="#6b94cc", roof="#8a4b38"),
        make_facility("f_mdn_stasiun", "Stasiun Kargo Besar Madiun & INKA", "Hub Ekspor Kereta Api & Pasar Kota Madiun", "station", "export", -7.6115, 111.5230, "mdn_stasiun", 0, proj, accepted_goods=["capsule", "bar", "diamond", "drop", "moon", "star", "chevron", "candle", "paddle", "cart", "gem", "bus"], color="#d96b43", roof="#783d2b"),

        # Region 1: Kabupaten Madiun
        make_facility("f_kbm_saradan", "Perhutani Jati Saradan", "Supplier Kayu Jati Hutan Saradan", "supplier", "raw", -7.5420, 111.7480, "kbm_saradan", 1, proj, output_good="wedge", color="#d9833b", roof="#8f5122"),
        make_facility("f_kbm_dolopo", "Lumbung Pangan Dolopo", "Supplier Padi & Palawija Selatan", "supplier", "raw", -7.7750, 111.5240, "kbm_dolopo", 1, proj, output_good="dot", color="#4ea854", roof="#3f7342"),
        make_facility("f_kbm_caruban_ply", "Industri Kayu Lapis Caruban", "Pabrik Press Mejayan (2 Wedge → Diamond)", "factory", "press", -7.5420, 111.6620, "kbm_caruban", 1, proj, output_good="diamond", accepted_goods=["wedge"], color="#e69b45", roof="#ad5b39"),
        make_facility("f_kbm_kare_drop", "Penyulingan Atsiri Lereng Kare", "Pabrik Press Bio-Resin (1 Dot + 1 Wedge → Drop)", "factory", "press", -7.7160, 111.6760, "kbm_kare", 1, proj, output_good="drop", accepted_goods=["dot", "wedge"], color="#9eb846", roof="#786332"),
        make_facility("f_kbm_stasiun_crb", "Stasiun & Pasar Induk Caruban", "Terminal Kargo Kabupaten Madiun", "station", "export", -7.5560, 111.6520, "kbm_caruban", 1, proj, accepted_goods=["diamond", "drop", "capsule", "bar", "star", "candle", "cart", "bus"], color="#4a9658", roof="#356e40"),

        # Region 2: Kabupaten Magetan
        make_facility("f_mgt_sarangan", "Agrowisata Sayur & Tani Plaosan", "Supplier Hulu Lereng Lawu", "supplier", "raw", -7.6810, 111.2420, "mgt_plaosan", 2, proj, output_good="dot", color="#4ea854", roof="#3d7344"),
        make_facility("f_mgt_kulit", "Sentra Industri Kulit Magetan", "Pabrik Cut Presisi Jl. Sawo (2 Dot → Moon)", "factory", "cut", -7.6540, 111.3240, "mgt_kota", 2, proj, output_good="moon", accepted_goods=["dot"], color="#7ac74f", roof="#9c4e35"),
        make_facility("f_mgt_maospati_star", "Manufaktur Komponen Maospati", "Pabrik Press Presisi (2 Diamond → Star)", "factory", "press", -7.6020, 111.4380, "mgt_maospati", 2, proj, output_good="star", accepted_goods=["diamond"], color="#ebb838", roof="#8a5a24"),
        make_facility("f_mgt_stasiun_barat", "Stasiun Kargo Barat Magetan", "Hub Distribusi Magetan & Maospati", "station", "export", -7.5500, 111.4530, "mgt_barat", 2, proj, accepted_goods=["moon", "star", "diamond", "drop", "chevron", "candle"], color="#c98b32", roof="#7d5318"),

        # Region 3: Kabupaten Ngawi
        make_facility("f_ngw_padi", "Lumbung Padi Bengawan Mantingan", "Supplier Beras Utama Ngawi Barat", "supplier", "raw", -7.3790, 111.1520, "ngw_mantingan", 3, proj, output_good="dot", color="#4ea854", roof="#396e3d"),
        make_facility("f_ngw_jati", "Hutan Jati & Bambu Jogorogo", "Supplier Kayu Lereng Lawu Utara", "supplier", "raw", -7.5330, 111.2410, "ngw_jogorogo", 3, proj, output_good="wedge", color="#d9833b", roof="#874c1d"),
        make_facility("f_ngw_kriya", "Sentra Kriya Jati Walikukun", "Pabrik Cut Rangka Ukir (2 Wedge → Chevron)", "factory", "cut", -7.4170, 111.2280, "ngw_walikukun", 3, proj, output_good="chevron", accepted_goods=["wedge"], color="#eb7b4b", roof="#994220"),
        make_facility("f_ngw_candle", "Kawasan Industri Ngawi (Paron)", "Pabrik Perakitan Unit Energi (1 Drop + 1 Block → Candle)", "factory", "assemble", -7.4590, 111.3680, "ngw_paron", 3, proj, output_good="candle", accepted_goods=["drop", "block"], color="#f09546", roof="#8f4c14"),
        make_facility("f_ngw_pasar", "Terminal & Stasiun Kargo Ngawi", "Hub Perdagangan Tempuran Bengawan Solo", "station", "export", -7.4005, 111.4490, "ngw_kartonyono", 3, proj, accepted_goods=["chevron", "candle", "capsule", "moon", "star", "paddle", "bus"], color="#3c8da6", roof="#265d6e"),

        # Region 4: Kabupaten Ponorogo
        make_facility("f_png_tambang", "Tambang Batu & Kapur Sampung", "Supplier Mineral Ponorogo Barat", "supplier", "raw", -7.8940, 111.3200, "png_badegan", 4, proj, output_good="block", color="#5b82b8", roof="#355278"),
        make_facility("f_png_pebble", "Pengolahan Batu Halus Pulung", "Pabrik Press Granit (1 Dot + 1 Block → Pebble)", "factory", "press", -7.8740, 111.6220, "png_pulung", 4, proj, output_good="pebble", accepted_goods=["dot", "block"], color="#4eb3a8", roof="#296e66"),
        make_facility("f_png_paddle", "Perakitan Alsintan Jetis", "Pabrik Assemble Mesin Tani (1 Bar + 1 Pebble → Paddle)", "factory", "assemble", -7.9400, 111.4780, "png_jetis", 4, proj, output_good="paddle", accepted_goods=["bar", "pebble"], color="#88ab44", roof="#4d6320"),
        make_facility("f_png_cart", "Karoseri Niaga Kota Ponorogo", "Pabrik Assemble Sasis (1 Bar + 2 Dot → Cart)", "factory", "assemble", -7.8610, 111.4690, "png_kota", 4, proj, output_good="cart", accepted_goods=["bar", "dot"], color="#d9644a", roof="#7d301f"),
        make_facility("f_png_pasar", "Pasar Songgolangit Ponorogo", "Pusat Permintaan Niaga Bumi Reog", "market", "export", -7.8710, 111.4560, "png_kota", 4, proj, accepted_goods=["paddle", "cart", "moon", "candle", "gem", "fish"], color="#9b5eb8", roof="#5e3473"),

        # Region 5: Kabupaten Pacitan
        make_facility("f_pct_kars", "Kuari Kars Gunungsewu Punung", "Supplier Batu Kars Selatan", "supplier", "raw", -8.1210, 111.0290, "pct_punung", 5, proj, output_good="block", color="#5b82b8", roof="#324e73"),
        make_facility("f_pct_shield", "Komposit Mineral Tulakan", "Pabrik Press Pelat (1 Wedge + 1 Block → Shield)", "factory", "press", -8.1780, 111.2740, "pct_tulakan", 5, proj, output_good="shield", accepted_goods=["wedge", "block"], color="#9c78bd", roof="#583e70"),
        make_facility("f_pct_gem", "Sentra Batu Mulia & Optik Donorojo", "Pabrik Press Permata (1 Diamond + 1 Shield → Gem)", "factory", "press", -8.1560, 110.9430, "pct_donorojo", 5, proj, output_good="gem", accepted_goods=["diamond", "shield"], color="#3ec4b9", roof="#1d6e67"),
        make_facility("f_pct_fish", "Pengolahan Hasil Laut Pacitan", "Pabrik Assemble Bahari (1 Capsule + 1 Chevron → Fish)", "factory", "assemble", -8.1990, 111.1110, "pct_kota", 5, proj, output_good="fish", accepted_goods=["capsule", "chevron"], color="#43a9db", roof="#1f5c7a"),
        make_facility("f_pct_bus", "Karoseri Antarkota Arjosari–INKA", "Pabrik Assemble Bus & Gerbong (1 Capsule + 2 Dot → Bus)", "factory", "assemble", -8.1050, 111.1640, "pct_arjosari", 5, proj, output_good="bus", accepted_goods=["capsule", "dot"], color="#3d8bd9", roof="#1e4f80"),
        make_facility("f_pct_harbour", "Pelabuhan Samudra Tamperan Pacitan", "Harbour Ekspor Kapal Kargo Lintas Samudra Hindia", "harbour", "export", -8.2210, 111.0840, "pct_tamperan", 5, proj, accepted_goods=["gem", "fish", "bus", "paddle", "cart", "star", "candle"], color="#2f74ba", roof="#1b4875"),
    ]

    buildings, patches = populate_city_blocks(junctions, roads, facilities, seed=3577)

    all_x = [j["x"] for j in junctions] + [pt[0] for r in regions for ring in r["polygons"] for pt in ring]
    all_y = [j["y"] for j in junctions] + [pt[1] for r in regions for ring in r["polygons"] for pt in ring]
    init_x, init_y = proj.proj(-7.6285, 111.5235)

    return {
        "id": "karisidenan_madiun",
        "name": "Karesidenan Madiun Terpadu",
        "subtitle": "6 Wilayah Progresif · Kota Madiun, Kab. Madiun, Magetan, Ngawi, Ponorogo & Pacitan",
        "badge": "UTAMA · 6 WILAYAH ASLI",
        "description": "Kampanye penuh di atas koordinat asli eks-Karesidenan Madiun dari Tempuran Bengawan Solo (Ngawi) hingga Pelabuhan Tamperan di Teluk Pacitan.",
        "boundsWorld": {
            "minX": round(min(all_x) - 180, 1),
            "minY": round(min(all_y) - 180, 1),
            "maxX": round(max(all_x) + 180, 1),
            "maxY": round(max(all_y) + 180, 1),
        },
        "initialView": {"x": init_x, "y": init_y, "zoom": 1.38},
        "leftHandTrafficDefault": True,
        "regions": regions,
        "waterBodies": water_bodies,
        "rivers": rivers,
        "railways": railways,
        "junctions": junctions,
        "roads": roads,
        "roadOffers": offers,
        "facilities": facilities,
        "buildings": buildings,
        "patches": patches,
    }


def build_kota_madiun_detail_map(raw):
    """Map 2: High-resolution urban street grid of Kota Madiun (27 Kelurahan, 3 Kecamatan)."""
    proj = Projector(center_lat=-7.6300, center_lon=111.5260, scale=14500.0)
    rinfo = raw["regencies"]["kota_madiun"]

    # Group 27 kelurahan into the 3 real Kecamatan of Kota Madiun for progressive urban unlock!
    kec_groups = {
        "Kartoharjo": ("Kecamatan Kartoharjo", "Pusat Jl. Pahlawan, Stasiun Madiun, Klegen & PG Rejo Agung", "#d96b43", "rgba(217,107,67,0.11)", True, [
            {"good": "capsule", "targetPerMin": 3.5, "currentPerMin": 0},
            {"good": "bar", "targetPerMin": 3.5, "currentPerMin": 0},
        ], ["Kartoharjo", "Klegen", "Oro Oro Ombo", "Kanigoro", "Pilangbango", "Rejomulyo", "Sukosari", "Tawangrejo", "Kelun"]),
        "Taman": ("Kecamatan Taman", "Bundaran Taman, Pasar Besar, Mojorejo, Manisrejo & Banjarejo", "#4a9658", "rgba(74,150,88,0.11)", False, [
            {"good": "moon", "targetPerMin": 3.5, "currentPerMin": 0},
            {"good": "heart", "targetPerMin": 3.0, "currentPerMin": 0},
        ], ["Taman", "Banjarejo", "Demangan", "Josenan", "Kejuron", "Kuncen", "Manisrejo", "Mojorejo", "Pandean"]),
        "Mangu Harjo": ("Kecamatan Manguharjo", "Seberang Barat Kali Madiun, Ring Road Barat, Winongo & Sogaten", "#3c8da6", "rgba(60,141,166,0.11)", False, [
            {"good": "bus", "targetPerMin": 3.0, "currentPerMin": 0},
            {"good": "rocket", "targetPerMin": 2.5, "currentPerMin": 0},
        ], ["Madiun Lor", "Manguharjo", "Nambangan Kidul", "Nambangan Lor", "Ngegong", "Pangongangan", "Patihan", "Sogaten", "Winongo"]),
    }

    regions = []
    for idx, (kkey, (kname, sub, acc, fill, unl, goals, kel_list)) in enumerate(kec_groups.items()):
        polys = []
        cx_l, cy_l = [], []
        for kel in kel_list:
            if kel in rinfo["subunits"]:
                su = rinfo["subunits"][kel]
                cp = proj.proj(su["center"][0], su["center"][1])
                cx_l.append(cp[0]); cy_l.append(cp[1])
                for ring in su["polygons"]:
                    polys.append([proj.proj(p[0], p[1]) for p in ring])
        regions.append({
            "index": idx,
            "id": kkey.lower().replace(" ", "_"),
            "name": kname,
            "kabKota": "Kota Madiun",
            "subtitle": sub,
            "regencyCode": f"id3577_{idx+1}",
            "accentColor": acc,
            "fillColor": fill,
            "unlocked": unl,
            "unlockedAtRealSec": 0 if unl else -1,
            "polygons": polys,
            "center": [round(sum(cx_l)/max(1, len(cx_l)), 1), round(sum(cy_l)/max(1, len(cy_l)), 1)],
            "goals": goals,
            "holdSeconds": 0.0,
        })

    seam = raw.get("kota_madiun_kali_seam") or [[-7.665, 111.512], [-7.641, 111.514], [-7.626, 111.511], [-7.606, 111.528], [-7.594, 111.536]]
    rivers = [{
        "id": "kali_madiun_kota",
        "name": "Bengawan / Kali Madiun",
        "widthPx": 22,
        "points": [proj.proj(p[0], p[1]) for p in seam],
    }]

    rail_kota = [[-7.624, 111.496], [-7.619, 111.512], [-7.6165, 111.5245], [-7.6135, 111.539], [-7.606, 111.558]]
    railways = [{"id": "rel_kota_madiun", "name": "Jalur KA Stasiun Besar Madiun & Workshop INKA", "points": [proj.proj(a, b) for a, b in rail_kota]}]

    j_specs = [
        # Region 0: Kartoharjo
        ("km_tugu", "Tugu 0 KM (Jl. Pahlawan × Cokroaminoto)", -7.6278, 111.5230, 0, "lights", "Pahlawan Street Center"),
        ("km_stasiun", "Simpang Stasiun Besar Madiun", -7.6175, 111.5242, 0, "lights", "Stasiun Madiun & PT INKA"),
        ("km_sukosari", "Simpang Basuki Rahmat – Sukosari", -7.6152, 111.5335, 0, "none", None),
        ("km_rejoagung", "Simpang PG Rejo Agung", -7.6145, 111.5435, 0, "yield", "PG Rejo Agung"),
        ("km_pilangbango", "Simpang Pilangbango – Kelun", -7.6065, 111.5485, 0, "none", None),
        ("km_orooro", "Simpang Diponegoro – Oro-Oro Ombo", -7.6245, 111.5325, 0, "lights", None),
        ("km_klegen", "Simpang Thamrin – Klegen", -7.6285, 111.5380, 0, "none", "Stadion Wilis"),
        ("km_kanigoro", "Simpang Kanigoro Timur", -7.6308, 111.5475, 0, "none", None),

        # Region 1: Taman
        ("km_pasarbesar", "Simpang Pasar Besar (Jl. Panglima Sudirman)", -7.6345, 111.5222, 1, "lights", "Pasar Besar Madiun"),
        ("km_alun", "Alun-Alun Kota Madiun", -7.6362, 111.5168, 1, "yield", "Alun-Alun Madiun"),
        ("km_sleko", "Simpang Empat Sleko / Bundaran Taman", -7.6420, 111.5255, 1, "roundabout", "Monumen Taman"),
        ("km_mojorejo", "Simpang Setia Budi – Mojorejo", -7.6378, 111.5355, 1, "none", None),
        ("km_manisrejo", "Simpang Tanjung – Manisrejo", -7.6438, 111.5445, 1, "none", None),
        ("km_banjarejo", "Simpang DI Panjaitan – Banjarejo", -7.6528, 111.5350, 1, "none", "Graha Krida Praja"),
        ("km_tean", "Simpang Te'an Demangan (Batas Selatan)", -7.6575, 111.5232, 1, "lights", "Gerbang Selatan"),
        ("km_josenan", "Simpang Kuncen – Josenan", -7.6558, 111.5152, 1, "none", None),

        # Region 2: Manguharjo
        ("km_madiunlor", "Simpang Yos Sudarso – Madiun Lor", -7.6182, 111.5180, 2, "none", None),
        ("km_pangongangan", "Simpang Ahmad Yani – Pangongangan", -7.6269, 111.5162, 2, "lights", "Balai Kota"),
        ("km_manguharjo", "Jembatan Manguharjo (Jl. Hayam Wuruk)", -7.6272, 111.5072, 2, "lights", "Gerbang Barat"),
        ("km_winongo", "Simpang Ring Road Barat – Winongo", -7.6165, 111.5085, 2, "roundabout", "Ring Road Barat"),
        ("km_ngegong", "Simpang Ngegong Utara", -7.6085, 111.5112, 2, "none", None),
        ("km_sogaten", "Simpang Sogaten – Patihan", -7.6050, 111.5245, 2, "none", None),
        ("km_nambangan", "Simpang Ring Road Barat – Nambangan Kidul", -7.6415, 111.5095, 2, "none", None),
    ]

    e_specs = [
        # Kartoharjo
        ("km_e1", "Jl. Pahlawan", "km_stasiun", "km_tugu", "municipal", 0, 2, 0.0, False, False, None),
        ("km_e2", "Jl. Dr. Sutomo – Jl. Diponegoro", "km_tugu", "km_orooro", "municipal", 0, 2, 0.0, False, False, None),
        ("km_e3", "Jl. Diponegoro – Stadion Wilis", "km_orooro", "km_klegen", "municipal", 0, 2, 0.0, False, False, None),
        ("km_e4", "Jl. Kapten Saputra Kanigoro", "km_klegen", "km_kanigoro", "municipal", 0, 1, 0.0, False, False, None),
        ("km_e5", "Jl. Basuki Rahmat", "km_stasiun", "km_sukosari", "national", 0, 2, 0.0, False, False, None),
        ("km_e6", "Jl. S. Parman – Oro-Oro Ombo", "km_sukosari", "km_orooro", "municipal", 0, 2, 0.0, False, False, None),
        ("km_e7", "Jl. Yos Sudarso Timur (Rejo Agung)", "km_sukosari", "km_rejoagung", "national", 0, 2, 0.0, False, False, None),
        ("km_e8", "Jl. Tawangrejo – Pilangbango", "km_rejoagung", "km_pilangbango", "municipal", 0, 1, 0.0, False, False, None),
        ("km_e9", "Jl. Slamet Riyadi Klegen", "km_rejoagung", "km_klegen", "municipal", 0, 1, 0.0, False, False, None),

        # Taman
        ("km_e10", "Jl. Cokroaminoto", "km_tugu", "km_pasarbesar", "municipal", 1, 2, 0.0, False, False, None),
        ("km_e11", "Jl. Panglima Sudirman – Alun-Alun", "km_pasarbesar", "km_alun", "municipal", 1, 2, 0.0, False, False, None),
        ("km_e12", "Jl. Musi – Bundaran Sleko", "km_pasarbesar", "km_sleko", "municipal", 1, 2, 0.0, False, False, None),
        ("km_e13", "Jl. Agus Salim", "km_alun", "km_sleko", "municipal", 1, 1, 0.0, False, False, None),
        ("km_e14", "Jl. Thamrin", "km_orooro", "km_mojorejo", "municipal", 1, 2, 0.0, False, False, None),
        ("km_e15", "Jl. MT Haryono", "km_sleko", "km_mojorejo", "municipal", 1, 2, 0.0, False, False, None),
        ("km_e16", "Jl. Setia Budi Timur", "km_mojorejo", "km_manisrejo", "municipal", 1, 1, 0.0, False, False, None),
        ("km_e17", "Jl. Manisrejo – Kanigoro", "km_kanigoro", "km_manisrejo", "local", 1, 1, 0.0, False, False, None),
        ("km_e18", "Jl. DI Panjaitan", "km_mojorejo", "km_banjarejo", "municipal", 1, 2, 0.0, False, False, None),
        ("km_e19", "Jl. Tanjung Raya", "km_manisrejo", "km_banjarejo", "local", 1, 1, 0.0, False, False, None),
        ("km_e20", "Jl. Soekarno-Hatta Madiun", "km_sleko", "km_tean", "national", 1, 2, 0.0, False, False, None),
        ("km_e21", "Jl. Srikaya Banjarejo–Te'an", "km_banjarejo", "km_tean", "municipal", 1, 1, 0.0, False, False, None),
        ("km_e22", "Jl. Asahan Josenan", "km_tean", "km_josenan", "local", 1, 1, 0.0, False, False, None),

        # Manguharjo (crossing Kali Madiun via real bridges!)
        ("km_e23", "Jl. Yos Sudarso Barat (Depan INKA)", "km_stasiun", "km_madiunlor", "municipal", 2, 2, 0.0, False, False, None),
        ("km_e24", "Jl. Ahmad Yani", "km_madiunlor", "km_pangongangan", "municipal", 2, 2, 0.0, False, False, None),
        ("km_e25", "Jl. Jend. Sudirman Barat", "km_tugu", "km_pangongangan", "municipal", 2, 2, 0.0, False, False, None),
        ("km_e26", "Jl. Kolonel Marhadi (Alun-Alun)", "km_pangongangan", "km_alun", "municipal", 2, 1, 0.0, False, False, None),
        ("km_e27", "Jembatan Manguharjo & Jl. Hayam Wuruk", "km_pangongangan", "km_manguharjo", "national", 2, 2, 0.0, True, False, None),
        ("km_e28", "Jl. Urip Sumoharjo & Jembatan Patihan", "km_madiunlor", "km_winongo", "municipal", 2, 1, 0.0, True, False, None),
        ("km_e29", "Jl. Ring Road Barat (Manguharjo–Winongo)", "km_manguharjo", "km_winongo", "national", 2, 2, 0.0, False, False, None),
        ("km_e30", "Jl. Ring Road Barat Utara (Winongo–Ngegong)", "km_winongo", "km_ngegong", "national", 2, 2, 0.0, False, False, None),
        ("km_e31", "Jl. Campursari Sogaten & Jembatan Sogaten", "km_ngegong", "km_sogaten", "municipal", 2, 1, 0.0, True, False, None),
        ("km_e32", "Jl. Merpati Patihan–Sukosari", "km_sogaten", "km_sukosari", "local", 2, 1, 0.0, False, False, None),
        ("km_e33", "Jl. Ring Road Barat Selatan (Nambangan)", "km_manguharjo", "km_nambangan", "national", 2, 2, 0.0, False, False, None),
        ("km_e34", "Jembatan Ngujang / Nambangan–Alun-Alun", "km_nambangan", "km_alun", "municipal", 2, 1, 0.0, True, False, None),
        ("km_e35", "Jl. Ring Road Selatan (Nambangan–Josenan)", "km_nambangan", "km_josenan", "national", 2, 2, 0.05, True, False, None),

        # Road Offers in Kota Madiun
        ("km_off1", "Flyover Perlintasan KA Yos Sudarso–Sukosari", "km_madiunlor", "km_sukosari", "toll", 0, 2, -0.14, False, True, "offer_km_flyover"),
        ("km_off2", "Ring Road Timur Kota Madiun (Pilangbango–Banjarejo)", "km_pilangbango", "km_banjarejo", "toll", 1, 2, 0.16, False, True, "offer_km_ringtimur"),
    ]

    offer_specs = [
        ("offer_km_flyover", "Flyover Stasiun & INKA", "Jembatan layang melompati simpang padat Stasiun Madiun", "flyover", ["km_off1"], 0, 4, 1),
        ("offer_km_ringtimur", "Ring Road Timur Madiun", "Sabuk logistik timur menghubungkan Pilangbango langsung ke Banjarejo", "ring", ["km_off2"], 1, 6, 1),
    ]

    junctions, roads, offers = compile_graph(j_specs, e_specs, offer_specs, proj, "kota_madiun")

    facilities = [
        make_facility("km_f_tebu", "Kebun Tebu Pilangbango", "Supplier Hulu Kartoharjo Utara", "supplier", "raw", -7.6030, 111.5515, "km_pilangbango", 0, proj, output_good="dot", color="#4ea854"),
        make_facility("km_f_kayu", "Depo Kayu Kanigoro", "Supplier Hulu Kartoharjo Timur", "supplier", "raw", -7.6325, 111.5520, "km_kanigoro", 0, proj, output_good="wedge", color="#d9833b"),
        make_facility("km_f_batu", "Depo Material Klegen", "Supplier Konstruksi Klegen", "supplier", "raw", -7.6250, 111.5415, "km_klegen", 0, proj, output_good="block", color="#5b82b8"),
        make_facility("km_f_rejo", "Pabrik Gula Rejo Agung", "Press Gula Kristal (2 Dot → Capsule)", "factory", "press", -7.6118, 111.5448, "km_rejoagung", 0, proj, output_good="capsule", accepted_goods=["dot"], color="#5ec269"),
        make_facility("km_f_bar", "Tempa Baja Komponen Klegen", "Press Profil Baja (2 Block → Bar)", "factory", "press", -7.6210, 111.5350, "km_orooro", 0, proj, output_good="bar", accepted_goods=["block"], color="#6b94cc"),
        make_facility("km_f_stasiun", "Stasiun Besar Madiun", "Terminal Kargo Kereta Api Lintas Jawa", "station", "export", -7.6150, 111.5235, "km_stasiun", 0, proj, accepted_goods=["capsule", "bar", "moon", "heart", "bus", "rocket"], color="#d96b43"),

        # Taman
        make_facility("km_f_tani_sel", "Lumbung Padi Josenan", "Supplier Hulu Taman Selatan", "supplier", "raw", -7.6590, 111.5125, "km_josenan", 1, proj, output_good="dot", color="#4ea854"),
        make_facility("km_f_moon", "Kriya Kulit & Tekstil Mojorejo", "Cut Presisi (2 Dot → Moon)", "factory", "cut", -7.6395, 111.5385, "km_mojorejo", 1, proj, output_good="moon", accepted_goods=["dot"], color="#7ac74f"),
        make_facility("km_f_heart", "Sentra Pangan & Brem Banjarejo", "Press Pangan Olahan (1 Capsule + 1 Wedge → Heart)", "factory", "press", -7.6545, 111.5390, "km_banjarejo", 1, proj, output_good="heart", accepted_goods=["capsule", "wedge"], color="#e05a6d"),
        make_facility("km_f_pasar", "Pasar Besar Kota Madiun", "Pusat Perdagangan Kota Madiun", "market", "export", -7.6350, 111.5245, "km_pasarbesar", 1, proj, accepted_goods=["capsule", "moon", "heart", "bus"], color="#4a9658"),

        # Manguharjo
        make_facility("km_f_kayu_bar", "Depo Jati Sogaten", "Supplier Kayu Manguharjo", "supplier", "raw", -7.6020, 111.5210, "km_sogaten", 2, proj, output_good="wedge", color="#d9833b"),
        make_facility("km_f_chev", "Bengkel Rangka Winongo", "Cut Rangka (2 Wedge → Chevron)", "factory", "cut", -7.6145, 111.5045, "km_winongo", 2, proj, output_good="chevron", accepted_goods=["wedge"], color="#eb7b4b"),
        make_facility("km_f_bus", "Karoseri Ring Road Nambangan", "Assemble Bus (1 Capsule + 2 Dot → Bus)", "factory", "assemble", -7.6435, 111.5055, "km_nambangan", 2, proj, output_good="bus", accepted_goods=["capsule", "dot"], color="#3d8bd9"),
        make_facility("km_f_inka", "Pabrik Kereta Api PT INKA Madiun", "Assemble Lokomotif & Gerbong (1 Bar + 1 Chevron + 1 Wedge → Rocket)", "factory", "assemble", -7.6162, 111.5162, "km_madiunlor", 2, proj, output_good="rocket", accepted_goods=["bar", "chevron", "wedge"], color="#db4c5e"),
    ]

    buildings, patches = populate_city_blocks(junctions, roads, facilities, seed=357701)
    all_x = [j["x"] for j in junctions] + [pt[0] for r in regions for ring in r["polygons"] for pt in ring]
    all_y = [j["y"] for j in junctions] + [pt[1] for r in regions for ring in r["polygons"] for pt in ring]
    ix, iy = proj.proj(-7.6260, 111.5270)

    return {
        "id": "kota_madiun",
        "name": "Kota Madiun (27 Kelurahan)",
        "subtitle": "Jl. Pahlawan, Stasiun & PT INKA, Pasar Besar, Kali Madiun & Ring Road Barat",
        "badge": "KOTA MADIUN",
        "description": "Tata ruang jalan protokol asli Kota Madiun dengan batas kelurahan presisi, 4 jembatan Kali Madiun, dan perakitan lokomotif PT INKA.",
        "boundsWorld": {"minX": round(min(all_x)-120, 1), "minY": round(min(all_y)-120, 1), "maxX": round(max(all_x)+120, 1), "maxY": round(max(all_y)+120, 1)},
        "initialView": {"x": ix, "y": iy, "zoom": 1.22},
        "leftHandTrafficDefault": True,
        "regions": regions,
        "waterBodies": [],
        "rivers": rivers,
        "railways": railways,
        "junctions": junctions,
        "roads": roads,
        "roadOffers": offers,
        "facilities": facilities,
        "buildings": buildings,
        "patches": patches,
    }


def build_single_regency_map(raw, rkey, map_id, title, subtitle, badge, desc, scale, sector_defs, j_specs, e_specs, offer_specs, fac_specs, extra_water=None, river_ids=None, include_rail=False):
    rinfo = raw["regencies"][rkey]
    c_lat, c_lon = rinfo["center"]
    proj = Projector(center_lat=c_lat, center_lon=c_lon, scale=scale)

    regions = []
    for idx, (sname, ssub, acc, fill, unl, goals, dist_names) in enumerate(sector_defs):
        polys = []
        cx_l, cy_l = [], []
        for dn in dist_names:
            if dn in rinfo["subunits"]:
                su = rinfo["subunits"][dn]
                cp = proj.proj(su["center"][0], su["center"][1])
                cx_l.append(cp[0]); cy_l.append(cp[1])
                for ring in su["polygons"]:
                    polys.append([proj.proj(p[0], p[1]) for p in ring])
        if not polys:
            polys = [[proj.proj(p[0], p[1]) for p in ring] for ring in rinfo["polygons"]]
            cp = proj.proj(c_lat, c_lon)
            cx_l, cy_l = [cp[0]], [cp[1]]
        regions.append({
            "index": idx,
            "id": f"{rkey}_sec_{idx}",
            "name": sname,
            "kabKota": rinfo["title"],
            "subtitle": ssub,
            "regencyCode": f"{rinfo['code']}_{idx+1}",
            "accentColor": acc,
            "fillColor": fill,
            "unlocked": unl,
            "unlockedAtRealSec": 0 if unl else -1,
            "polygons": polys,
            "center": [round(sum(cx_l)/len(cx_l), 1), round(sum(cy_l)/len(cy_l), 1)],
            "goals": goals,
            "holdSeconds": 0.0,
        })

    junctions, roads, offers = compile_graph(j_specs, e_specs, offer_specs, proj, map_id)
    facilities = [
        make_facility(fs[0], fs[1], fs[2], fs[3], fs[4], fs[5], fs[6], fs[7], fs[8], proj, output_good=fs[9], accepted_goods=fs[10], color=fs[11])
        for fs in fac_specs
    ]
    buildings, patches = populate_city_blocks(junctions, roads, facilities, seed=hash(map_id) & 0xFFFF)

    water_bodies = []
    if extra_water:
        for wid, wname, wkind, wpoly in extra_water:
            water_bodies.append({"id": wid, "name": wname, "kind": wkind, "polygon": [proj.proj(a, b) for a, b in wpoly]})

    rivers = []
    for rid in (river_ids or []):
        if rid in raw["rivers"]:
            pts = [proj.proj(p[0], p[1]) for p in raw["rivers"][rid]["points"]]
            rivers.append({"id": f"{map_id}_{rid.lower()}", "name": raw["rivers"][rid]["name"], "widthPx": 18, "points": pts})

    railways = []
    if include_rail:
        railways.append({"id": f"{map_id}_rail", "name": "Jalur KA Lintas Selatan Jawa", "points": [proj.proj(p[0], p[1]) for p in raw["railway_mainline"]]})

    all_x = [j["x"] for j in junctions] + [pt[0] for r in regions for ring in r["polygons"] for pt in ring]
    all_y = [j["y"] for j in junctions] + [pt[1] for r in regions for ring in r["polygons"] for pt in ring]
    ix, iy = junctions[0]["x"], junctions[0]["y"]

    return {
        "id": map_id,
        "name": title,
        "subtitle": subtitle,
        "badge": badge,
        "description": desc,
        "boundsWorld": {"minX": round(min(all_x)-140, 1), "minY": round(min(all_y)-140, 1), "maxX": round(max(all_x)+140, 1), "maxY": round(max(all_y)+140, 1)},
        "initialView": {"x": ix, "y": iy, "zoom": 1.15},
        "leftHandTrafficDefault": True,
        "regions": regions,
        "waterBodies": water_bodies,
        "rivers": rivers,
        "railways": railways,
        "junctions": junctions,
        "roads": roads,
        "roadOffers": offers,
        "facilities": facilities,
        "buildings": buildings,
        "patches": patches,
    }


def build_all_maps():
    raw = build_or_load_raw_wgs84()
    maps = [
        build_integrated_karisidenan_map(raw),
        build_kota_madiun_detail_map(raw),
    ]

    # 3. Kabupaten Madiun Detail (15 Kecamatan)
    maps.append(build_single_regency_map(
        raw, "kab_madiun", "kab_madiun",
        "Kabupaten Madiun (Poros Caruban)",
        "15 Kecamatan · Caruban/Mejayan, Dumpil, Saradan, Dolopo & Lereng Wilis",
        "KAB. MADIUN",
        "Jaringan jalan nasional Surabaya–Madiun–Ponorogo melintasi ibu kota Caruban (Mejayan), Hutan Jati Saradan, dan perkebunan Kare.",
        scale=3600.0,
        sector_defs=[
            ("Poros Tengah Caruban–Nglames", "Mejayan, Wonoasri, Balerejo, Madiun, Sawahan & Jiwan", "#4a9658", "rgba(74,150,88,0.11)", True, [{"good": "capsule", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "diamond", "targetPerMin": 3.0, "currentPerMin": 0}], ["Mejayan", "Wonoasri", "Balerejo", "Madiun", "Sawahan", "Jiwan"]),
            ("Koridor Timur Hutan Saradan", "Pilangkenceng, Saradan & Gemarang", "#c98b32", "rgba(201,139,50,0.11)", False, [{"good": "bar", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "arrow", "targetPerMin": 2.5, "currentPerMin": 0}], ["Pilangkenceng", "Saradan", "Gemarang"]),
            ("Lembah Selatan Dolopo & Wilis", "Wungu, Kare, Dagangan, Geger, Dolopo & Kebonsari", "#d96b43", "rgba(217,107,67,0.11)", False, [{"good": "drop", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "cart", "targetPerMin": 2.5, "currentPerMin": 0}], ["Wungu", "Kare", "Dagangan", "Geger", "Dolopo", "Kebonsari"]),
        ],
        j_specs=[
            ("cm_caruban", "Simpang Empat Caruban (Mejayan)", -7.5520, 111.6580, 0, "lights", "Pusat Pemerintahan Caruban"),
            ("cm_wonoasri", "Simpang Wonoasri", -7.5750, 111.6280, 0, "none", None),
            ("cm_balerejo", "Simpang Balerejo", -7.5420, 111.5940, 0, "yield", None),
            ("cm_dumpil", "Bundaran Dumpil (Nglames)", -7.5880, 111.5680, 0, "roundabout", "GT Madiun"),
            ("cm_sawahan", "Simpang Sawahan", -7.5680, 111.5240, 0, "none", None),
            ("cm_jiwan", "Simpang Jiwan Barat", -7.6120, 111.4880, 0, "lights", None),
            ("cm_pilang", "Simpang Pilangkenceng", -7.4820, 111.6620, 1, "none", None),
            ("cm_saradan", "Simpang Alas Saradan", -7.5280, 111.7390, 1, "lights", "Hutan Jati Saradan"),
            ("cm_gemarang", "Simpang Gemarang", -7.6320, 111.7280, 1, "none", None),
            ("cm_wungu", "Simpang Dungus–Wungu", -7.6520, 111.5780, 2, "none", None),
            ("cm_kare", "Simpang Perkebunan Kare", -7.7090, 111.6750, 2, "none", "Lereng Wilis"),
            ("cm_geger", "Simpang Pagotan–Geger", -7.7020, 111.5300, 2, "lights", "PG Pagotan"),
            ("cm_dagangan", "Simpang Dagangan", -7.7210, 111.5840, 2, "none", None),
            ("cm_dolopo", "Simpang Pasar Dolopo", -7.7800, 111.5430, 2, "yield", None),
            ("cm_kebonsari", "Simpang Kebonsari Barat", -7.7410, 111.4890, 2, "none", None),
        ],
        e_specs=[
            ("cm_e1", "Jl. Panglima Sudirman Caruban", "cm_caruban", "cm_wonoasri", "national", 0, 2, 0.0, False, False, None),
            ("cm_e2", "Jl. Nasional Caruban–Madiun", "cm_wonoasri", "cm_balerejo", "national", 0, 2, 0.0, False, False, None),
            ("cm_e3", "Jl. Raya Balerejo–Dumpil", "cm_balerejo", "cm_dumpil", "national", 0, 2, 0.0, False, False, None),
            ("cm_e4", "Jl. Raya Sawahan", "cm_dumpil", "cm_sawahan", "provincial", 0, 1, 0.0, True, False, None),
            ("cm_e5", "Jl. Poros Sawahan–Jiwan", "cm_sawahan", "cm_jiwan", "provincial", 0, 2, 0.0, True, False, None),
            ("cm_e6", "Jl. Raya Caruban–Pilangkenceng", "cm_caruban", "cm_pilang", "provincial", 1, 1, 0.0, False, False, None),
            ("cm_e7", "Jl. Nasional Mejayan–Saradan", "cm_caruban", "cm_saradan", "national", 1, 2, 0.0, False, False, None),
            ("cm_e8", "Jl. Hutan Gemarang", "cm_saradan", "cm_gemarang", "local", 1, 1, 0.05, False, False, None),
            ("cm_e9", "Jl. Raya Gemarang–Caruban", "cm_gemarang", "cm_wonoasri", "local", 1, 1, 0.0, False, False, None),
            ("cm_e10", "Jl. Raya Nglames–Wungu", "cm_dumpil", "cm_wungu", "provincial", 2, 1, 0.0, False, False, None),
            ("cm_e11", "Jl. Raya Dungus–Kare", "cm_wungu", "cm_kare", "local", 2, 1, 0.06, False, False, None),
            ("cm_e12", "Jl. Lereng Kare–Gemarang", "cm_kare", "cm_gemarang", "local", 2, 1, 0.0, False, False, None),
            ("cm_e13", "Jl. Raya Wungu–Pagotan", "cm_wungu", "cm_geger", "provincial", 2, 2, 0.0, False, False, None),
            ("cm_e14", "Jl. Poros Jiwan–Geger", "cm_jiwan", "cm_geger", "national", 2, 2, 0.04, True, False, None),
            ("cm_e15", "Jl. Raya Geger–Dagangan", "cm_geger", "cm_dagangan", "local", 2, 1, 0.0, False, False, None),
            ("cm_e16", "Jl. Nasional Geger–Dolopo", "cm_geger", "cm_dolopo", "national", 2, 2, 0.0, False, False, None),
            ("cm_e17", "Jl. Raya Kebonsari–Dolopo", "cm_dolopo", "cm_kebonsari", "provincial", 2, 1, 0.0, True, False, None),
            ("cm_off1", "Jalan Tol Trans-Jawa (GT Dumpil – GT Caruban)", "cm_dumpil", "cm_caruban", "toll", 0, 2, -0.18, True, True, "off_cm_tol"),
        ],
        offer_specs=[("off_cm_tol", "Jalan Tol Dumpil–Caruban", "Jalur tol bebas hambatan sejajar koridor Balerejo", "toll", ["cm_off1"], 0, 5, 2)],
        fac_specs=[
            ("cm_f1", "Sawah Irigasi Balerejo", "Supplier Padi & Tebu", "supplier", "raw", -7.5350, 111.5980, "cm_balerejo", 0, "dot", [], "#4ea854"),
            ("cm_f2", "Hutan Rakyat Wonoasri", "Supplier Kayu Jati", "supplier", "raw", -7.5810, 111.6350, "cm_wonoasri", 0, "wedge", [], "#d9833b"),
            ("cm_f3", "PG Kanigoro / Sawahan", "Press Gula (2 Dot → Capsule)", "factory", "press", -7.5640, 111.5190, "cm_sawahan", 0, "capsule", ["dot"], "#5ec269"),
            ("cm_f4", "Kayu Lapis Mejayan", "Press Panel (2 Wedge → Diamond)", "factory", "press", -7.5470, 111.6660, "cm_caruban", 0, "diamond", ["wedge"], "#e69b45"),
            ("cm_f5", "Stasiun Kargo Caruban", "Terminal Kereta & Pasar Caruban", "station", "export", -7.5560, 111.6530, "cm_caruban", 0, None, ["capsule", "diamond", "bar", "arrow", "drop", "cart"], "#4a9658"),
            ("cm_f6", "Kuari Batu Saradan", "Supplier Batu Gunung", "supplier", "raw", -7.5210, 111.7450, "cm_saradan", 1, "block", [], "#5b82b8"),
            ("cm_f7", "Baja Profil Pilangkenceng", "Press Baja (2 Block → Bar)", "factory", "press", -7.4770, 111.6680, "cm_pilang", 1, "bar", ["block"], "#6b94cc"),
            ("cm_f8", "Bengkel Kriya Gemarang", "Cut Rangka (2 Wedge → Chevron)", "factory", "cut", -7.6380, 111.7340, "cm_gemarang", 1, "chevron", ["wedge"], "#eb7b4b"),
            ("cm_f9", "Pabrik Poros Baja Saradan", "Press As Roda (1 Bar + 1 Chevron → Arrow)", "factory", "press", -7.5340, 111.7320, "cm_saradan", 1, "arrow", ["bar", "chevron"], "#677ce0"),
            ("cm_f10", "Perkebunan Kakao & Kopi Kare", "Press Bio-Resin (1 Dot + 1 Wedge → Drop)", "factory", "press", -7.7140, 111.6810, "cm_kare", 2, "drop", ["dot", "wedge"], "#9eb846"),
            ("cm_f11", "Karoseri Niaga Pagotan–Dolopo", "Assemble Sasis (1 Bar + 2 Dot → Cart)", "factory", "assemble", -7.7750, 111.5490, "cm_dolopo", 2, "cart", ["bar", "dot"], "#d9644a"),
        ],
        river_ids=["RIV-MADIUN"],
        include_rail=True,
    ))

    # 4. Kabupaten Magetan Detail (18 Kecamatan)
    maps.append(build_single_regency_map(
        raw, "kab_magetan", "kab_magetan",
        "Kabupaten Magetan (Kaki Gunung Lawu)",
        "18 Kecamatan · Kota Magetan, Simpang Maospati, Barat, Plaosan & Telaga Sarangan",
        "KAB. MAGETAN",
        "Koridor timur–barat dari Simpang Tiga Maospati dan Stasiun Barat mendaki ke Alun-Alun Magetan hingga Telaga Sarangan di lereng Gunung Lawu.",
        scale=4200.0,
        sector_defs=[
            ("Gerbang Timur Maospati & Barat", "Maospati, Barat, Kartoharjo, Karangrejo, Karas & Sukomoro", "#c98b32", "rgba(201,139,50,0.11)", True, [{"good": "capsule", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "diamond", "targetPerMin": 3.0, "currentPerMin": 0}], ["Maospati", "Barat", "Kartoharjo", "Karangrejo", "Karas", "Sukomoro"]),
            ("Kota Magetan & Lereng Lawu", "Magetan, Panekan, Sidorejo, Plaosan, Ngariboyo & Poncol", "#d96b43", "rgba(217,107,67,0.11)", False, [{"good": "moon", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "star", "targetPerMin": 2.5, "currentPerMin": 0}], ["Magetan", "Panekan", "Sidorejo", "Plaosan", "Ngariboyo", "Poncol"]),
            ("Poros Selatan Kawedanan–Parang", "Bendo, Takeran, Kawedanan, Nguntoronadi, Lembeyan & Parang", "#4a9658", "rgba(74,150,88,0.11)", False, [{"good": "candle", "targetPerMin": 2.5, "currentPerMin": 0}, {"good": "bus", "targetPerMin": 2.5, "currentPerMin": 0}], ["Bendo", "Takeran", "Kawedanan", "Nguntoronadi", "Lembeyan", "Parang"]),
        ],
        j_specs=[
            ("mg_maospati", "Simpang Tiga Maospati", -7.5930, 111.4490, 0, "lights", "Lanud Iswahjudi"),
            ("mg_barat", "Simpang Stasiun Barat", -7.5570, 111.4600, 0, "none", "Stasiun Barat"),
            ("mg_karangrejo", "Simpang Karangrejo", -7.5590, 111.4210, 0, "yield", None),
            ("mg_karas", "Simpang Karas", -7.5780, 111.3780, 0, "none", None),
            ("mg_sukomoro", "Simpang Sukomoro", -7.6280, 111.3740, 0, "none", None),
            ("mg_kota", "Alun-Alun Kota Magetan", -7.6480, 111.3300, 1, "roundabout", "Pusat Kota Magetan"),
            ("mg_panekan", "Simpang Panekan", -7.6190, 111.2780, 1, "none", None),
            ("mg_plaosan", "Simpang Plaosan–Sarangan", -7.6760, 111.2470, 1, "lights", "Telaga Sarangan"),
            ("mg_poncol", "Simpang Poncol", -7.7230, 111.2550, 1, "none", None),
            ("mg_parang", "Simpang Parang", -7.7420, 111.3350, 2, "none", None),
            ("mg_bendo", "Simpang Bendo", -7.6420, 111.4300, 2, "none", None),
            ("mg_takeran", "Simpang Takeran", -7.6760, 111.4770, 2, "none", None),
            ("mg_kawedanan", "Simpang Kawedanan (Goranggareng)", -7.6930, 111.4070, 2, "lights", None),
            ("mg_lembeyan", "Simpang Lembeyan", -7.7530, 111.4040, 2, "none", None),
        ],
        e_specs=[
            ("mg_e1", "Jl. Raya Maospati–Barat", "mg_maospati", "mg_barat", "provincial", 0, 2, 0.0, False, False, None),
            ("mg_e2", "Jl. Raya Barat–Karangrejo", "mg_barat", "mg_karangrejo", "provincial", 0, 2, 0.0, False, False, None),
            ("mg_e3", "Jl. Raya Maospati–Karangrejo", "mg_maospati", "mg_karangrejo", "local", 0, 1, 0.0, False, False, None),
            ("mg_e4", "Jl. Raya Karangrejo–Karas", "mg_karangrejo", "mg_karas", "local", 0, 1, 0.0, False, False, None),
            ("mg_e5", "Jl. Raya Maospati–Sukomoro", "mg_maospati", "mg_sukomoro", "national", 0, 2, 0.0, False, False, None),
            ("mg_e6", "Jl. Poros Karas–Sukomoro", "mg_karas", "mg_sukomoro", "local", 0, 1, 0.0, False, False, None),
            ("mg_e7", "Jl. Raya Sukomoro–Kota Magetan", "mg_sukomoro", "mg_kota", "national", 1, 2, 0.0, True, False, None),
            ("mg_e8", "Jl. Raya Magetan–Panekan", "mg_kota", "mg_panekan", "provincial", 1, 1, 0.0, False, False, None),
            ("mg_e9", "Jl. Lereng Lawu Panekan–Plaosan", "mg_panekan", "mg_plaosan", "local", 1, 1, 0.05, False, False, None),
            ("mg_e10", "Jl. Raya Magetan–Plaosan–Sarangan", "mg_kota", "mg_plaosan", "provincial", 1, 2, 0.0, False, False, None),
            ("mg_e11", "Jl. Pegunungan Plaosan–Poncol", "mg_plaosan", "mg_poncol", "local", 1, 1, 0.06, False, False, None),
            ("mg_e12", "Jl. Raya Poncol–Parang", "mg_poncol", "mg_parang", "local", 2, 1, 0.0, False, False, None),
            ("mg_e13", "Jl. Raya Magetan–Parang", "mg_kota", "mg_parang", "provincial", 2, 1, 0.0, False, False, None),
            ("mg_e14", "Jl. Raya Maospati–Bendo", "mg_maospati", "mg_bendo", "provincial", 2, 1, 0.0, False, False, None),
            ("mg_e15", "Jl. Raya Bendo–Kawedanan", "mg_bendo", "mg_kawedanan", "provincial", 2, 1, 0.0, False, False, None),
            ("mg_e16", "Jl. Raya Bendo–Takeran", "mg_bendo", "mg_takeran", "local", 2, 1, 0.0, False, False, None),
            ("mg_e17", "Jl. Raya Kawedanan–Takeran", "mg_kawedanan", "mg_takeran", "provincial", 2, 2, 0.0, True, False, None),
            ("mg_e18", "Jl. Raya Parang–Kawedanan", "mg_parang", "mg_kawedanan", "provincial", 2, 1, 0.0, False, False, None),
            ("mg_e19", "Jl. Raya Kawedanan–Lembeyan", "mg_kawedanan", "mg_lembeyan", "provincial", 2, 2, 0.0, False, False, None),
            ("mg_off1", "Jalan Lingkar Utara Magetan (Sukomoro–Panekan–Plaosan)", "mg_sukomoro", "mg_panekan", "toll", 1, 2, -0.14, False, True, "off_mg_ring"),
        ],
        offer_specs=[("off_mg_ring", "Ring Road Utara Magetan", "Menghubungkan Sukomoro langsung ke Panekan & Plaosan tanpa menembus Alun-Alun", "ring", ["mg_off1"], 1, 6, 1)],
        fac_specs=[
            ("mg_f1", "Tebu & Padi Karangrejo", "Supplier Hulu Timur", "supplier", "raw", -7.5540, 111.4160, "mg_karangrejo", 0, "dot", [], "#4ea854"),
            ("mg_f2", "Kayu Pinus & Jati Karas", "Supplier Kayu Magetan", "supplier", "raw", -7.5740, 111.3720, "mg_karas", 0, "wedge", [], "#d9833b"),
            ("mg_f3", "PG Poerwodadie Karangrejo", "Press Gula (2 Dot → Capsule)", "factory", "press", -7.5620, 111.4270, "mg_karangrejo", 0, "capsule", ["dot"], "#5ec269"),
            ("mg_f4", "Panel Kayu Sukomoro", "Press Kayu (2 Wedge → Diamond)", "factory", "press", -7.6240, 111.3790, "mg_sukomoro", 0, "diamond", ["wedge"], "#e69b45"),
            ("mg_f5", "Stasiun Kargo Barat Magetan", "Hub Kereta Api Magetan", "station", "export", -7.5520, 111.4640, "mg_barat", 0, None, ["capsule", "diamond", "moon", "star", "candle", "bus"], "#c98b32"),
            ("mg_f6", "Sentra Kerajinan Kulit Jl. Sawo", "Cut Kulit Magetan (2 Dot → Moon)", "factory", "cut", -7.6530, 111.3260, "mg_kota", 1, "moon", ["dot"], "#7ac74f"),
            ("mg_f7", "Komponen Presisi Plaosan", "Press Bintang (2 Diamond → Star)", "factory", "press", -7.6720, 111.2420, "mg_plaosan", 1, "star", ["diamond"], "#ebb838"),
            ("mg_f8", "Kuari Batu Parang", "Supplier Batu Lereng Selatan", "supplier", "raw", -7.7470, 111.3310, "mg_parang", 2, "block", [], "#5b82b8"),
            ("mg_f9", "Bio-Resin Takeran", "Press Drop (1 Dot + 1 Wedge → Drop)", "factory", "press", -7.6800, 111.4820, "mg_takeran", 2, "drop", ["dot", "wedge"], "#9eb846"),
            ("mg_f10", "Unit Energi Kawedanan", "Assemble Lentera (1 Drop + 1 Block → Candle)", "factory", "assemble", -7.6970, 111.4120, "mg_kawedanan", 2, "candle", ["drop", "block"], "#f09546"),
            ("mg_f11", "Karoseri Lembeyan", "Assemble Bus (1 Capsule + 2 Dot → Bus)", "factory", "assemble", -7.7580, 111.4090, "mg_lembeyan", 2, "bus", ["capsule", "dot"], "#3d8bd9"),
        ],
        extra_water=[("sarangan_detail", "Telaga Sarangan", "lake", [[-7.672, 111.213], [-7.672, 111.225], [-7.681, 111.225], [-7.681, 111.213]])],
        river_ids=["RIV-GANDONG"],
        include_rail=True,
    ))

    # 5. Kabupaten Ngawi Detail (19 Kecamatan)
    maps.append(build_single_regency_map(
        raw, "kab_ngawi", "kab_ngawi",
        "Kabupaten Ngawi (Tempuran Bengawan Solo)",
        "19 Kecamatan · Tugu Kartonyono, Benteng Pendem, Paron, Walikukun & Karangjati",
        "KAB. NGAWI",
        "Pertemuan akbar Bengawan Solo dan Kali Madiun di Benteng Van Den Bosch, diapit jalur nasional Solo–Ngawi–Caruban dan sabuk hijau Gunung Lawu utara.",
        scale=3100.0,
        sector_defs=[
            ("Pusat Kota Ngawi, Paron & Geneng", "Ngawi, Paron, Geneng, Kasreman, Pitu, Kwadungan & Pangkur", "#3c8da6", "rgba(60,141,166,0.11)", True, [{"good": "capsule", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "chevron", "targetPerMin": 3.0, "currentPerMin": 0}], ["Ngawi", "Paron", "Geneng", "Kasreman", "Pitu", "Kwadungan", "Pangkur"]),
            ("Koridor Barat Walikukun & Mantingan", "Kedunggalar, Widodaren, Mantingan & Karanganyar", "#4a9658", "rgba(74,150,88,0.11)", False, [{"good": "diamond", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "bus", "targetPerMin": 2.5, "currentPerMin": 0}], ["Kedunggalar", "Widodaren", "Mantingan", "Karanganyar"]),
            ("Timur Waduk Pondok & Lereng Jamus", "Padas, Karangjati, Bringin, Gerih, Kendal, Jogorogo, Ngrambe & Sine", "#c98b32", "rgba(201,139,50,0.11)", False, [{"good": "candle", "targetPerMin": 2.5, "currentPerMin": 0}, {"good": "rocket", "targetPerMin": 2.5, "currentPerMin": 0}], ["Padas", "Karangjati", "Bringin", "Gerih", "Kendal", "Jogorogo", "Ngrambe", "Sine"]),
        ],
        j_specs=[
            ("nw_kartonyono", "Simpang Tugu Kartonyono Ngawi", -7.4055, 111.4450, 0, "lights", "Benteng Pendem"),
            ("nw_pitu", "Simpang Pitu Utara", -7.3650, 111.3700, 0, "none", None),
            ("nw_paron", "Simpang Stasiun Paron", -7.4580, 111.3690, 0, "yield", "Stasiun Paron"),
            ("nw_geneng", "Simpang Geneng", -7.4810, 111.4400, 0, "lights", None),
            ("nw_kwadungan", "Simpang Kwadungan–Pangkur", -7.5040, 111.5150, 0, "none", None),
            ("nw_kedunggalar", "Simpang Kedunggalar", -7.4220, 111.3120, 1, "none", None),
            ("nw_walikukun", "Simpang Walikukun (Widodaren)", -7.4100, 111.2320, 1, "lights", "Stasiun Walikukun"),
            ("nw_mantingan", "Gerbang Mantingan", -7.3860, 111.1580, 1, "none", None),
            ("nw_karanganyar", "Simpang Hutan Karanganyar", -7.3150, 111.2250, 1, "none", None),
            ("nw_padas", "Simpang Padas", -7.4500, 111.5320, 2, "none", None),
            ("nw_karangjati", "Simpang Karangjati", -7.4580, 111.6010, 2, "roundabout", None),
            ("nw_bringin", "Simpang Waduk Pondok (Bringin)", -7.4050, 111.5870, 2, "none", "Waduk Pondok"),
            ("nw_jogorogo", "Simpang Jogorogo", -7.5370, 111.2540, 2, "none", None),
            ("nw_ngrambe", "Simpang Ngrambe–Sine", -7.5050, 111.1950, 2, "none", "Kebun Teh Jamus"),
        ],
        e_specs=[
            ("nw_e1", "Jl. Nasional Ngawi–Geneng", "nw_kartonyono", "nw_geneng", "national", 0, 2, 0.0, True, False, None),
            ("nw_e2", "Jl. Siliwangi Ngawi–Paron", "nw_kartonyono", "nw_paron", "provincial", 0, 2, 0.0, False, False, None),
            ("nw_e3", "Jl. Raya Paron–Geneng", "nw_paron", "nw_geneng", "local", 0, 1, 0.0, False, False, None),
            ("nw_e4", "Jl. Hutan Pitu", "nw_kartonyono", "nw_pitu", "local", 0, 1, 0.0, True, False, None),
            ("nw_e5", "Jl. Raya Geneng–Kwadungan", "nw_geneng", "nw_kwadungan", "provincial", 0, 1, 0.0, True, False, None),
            ("nw_e6", "Jl. Nasional Ngawi–Kedunggalar", "nw_kartonyono", "nw_kedunggalar", "national", 1, 2, 0.0, False, False, None),
            ("nw_e7", "Jl. Poros Paron–Kedunggalar", "nw_paron", "nw_kedunggalar", "local", 1, 1, 0.0, False, False, None),
            ("nw_e8", "Jl. Nasional Kedunggalar–Walikukun", "nw_kedunggalar", "nw_walikukun", "national", 1, 2, 0.0, False, False, None),
            ("nw_e9", "Jl. Nasional Walikukun–Mantingan", "nw_walikukun", "nw_mantingan", "national", 1, 2, 0.0, False, False, None),
            ("nw_e10", "Jl. Poros Utara Karanganyar", "nw_walikukun", "nw_karanganyar", "local", 1, 1, 0.0, False, False, None),
            ("nw_e11", "Jl. Nasional Ngawi–Padas", "nw_kartonyono", "nw_padas", "national", 2, 2, 0.0, True, False, None),
            ("nw_e12", "Jl. Nasional Padas–Karangjati", "nw_padas", "nw_karangjati", "national", 2, 2, 0.0, False, False, None),
            ("nw_e13", "Jl. Raya Bringin–Waduk Pondok", "nw_karangjati", "nw_bringin", "local", 2, 1, 0.0, False, False, None),
            ("nw_e14", "Jl. Poros Padas–Kwadungan", "nw_padas", "nw_kwadungan", "local", 2, 1, 0.0, False, False, None),
            ("nw_e15", "Jl. Raya Paron–Jogorogo", "nw_paron", "nw_jogorogo", "provincial", 2, 1, 0.0, False, False, None),
            ("nw_e16", "Jl. Raya Jogorogo–Ngrambe", "nw_jogorogo", "nw_ngrambe", "provincial", 2, 1, 0.0, False, False, None),
            ("nw_e17", "Jl. Raya Ngrambe–Walikukun", "nw_ngrambe", "nw_walikukun", "provincial", 2, 1, 0.0, False, False, None),
            ("nw_off1", "Jalan Tol Solo–Ngawi (Mantingan–Kartonyono)", "nw_mantingan", "nw_kartonyono", "toll", 1, 2, -0.15, True, True, "off_nw_tol"),
        ],
        offer_specs=[("off_nw_tol", "Jalan Tol Solo–Ngawi", "Ruas tol lurus dari Mantingan menembus ke Selatan Kartonyono", "toll", ["nw_off1"], 1, 6, 2)],
        fac_specs=[
            ("nw_f1", "Lumbung Padi Geneng", "Supplier Gabah Utama", "supplier", "raw", -7.4860, 111.4450, "nw_geneng", 0, "dot", [], "#4ea854"),
            ("nw_f2", "Hutan Jati Pitu", "Supplier Kayu Jati Bengawan", "supplier", "raw", -7.3600, 111.3650, "nw_pitu", 0, "wedge", [], "#d9833b"),
            ("nw_f3", "PG Soedhono Geneng", "Press Gula (2 Dot → Capsule)", "factory", "press", -7.4760, 111.4340, "nw_geneng", 0, "capsule", ["dot"], "#5ec269"),
            ("nw_f4", "Kriya Jati Akar Paron", "Cut Ukir (2 Wedge → Chevron)", "factory", "cut", -7.4620, 111.3740, "nw_paron", 0, "chevron", ["wedge"], "#eb7b4b"),
            ("nw_f5", "Stasiun Kargo Paron–Ngawi", "Terminal Logistik Kereta Api Ngawi", "station", "export", -7.4020, 111.4490, "nw_kartonyono", 0, None, ["capsule", "chevron", "diamond", "bus", "candle", "rocket"], "#3c8da6"),
            ("nw_f6", "Kayu Lapis Kedunggalar", "Press Panel (2 Wedge → Diamond)", "factory", "press", -7.4260, 111.3080, "nw_kedunggalar", 1, "diamond", ["wedge"], "#e69b45"),
            ("nw_f7", "Karoseri Lintas Provinsi Walikukun", "Assemble Bus (1 Capsule + 2 Dot → Bus)", "factory", "assemble", -7.4140, 111.2270, "nw_walikukun", 1, "bus", ["capsule", "dot"], "#3d8bd9"),
            ("nw_f8", "Tambang Batu Karangjati", "Supplier Mineral Timur", "supplier", "raw", -7.4620, 111.6080, "nw_karangjati", 2, "block", [], "#5b82b8"),
            ("nw_f9", "Baja Profil Padas", "Press Baja (2 Block → Bar)", "factory", "press", -7.4460, 111.5360, "nw_padas", 2, "bar", ["block"], "#6b94cc"),
            ("nw_f10", "Kebun Teh & Atsiri Jamus", "Press Bio-Resin (1 Dot + 1 Wedge → Drop)", "factory", "press", -7.5090, 111.1900, "nw_ngrambe", 2, "drop", ["dot", "wedge"], "#9eb846"),
            ("nw_f11", "Unit Energi Karangjati", "Assemble Candle (1 Drop + 1 Block → Candle)", "factory", "assemble", -7.4530, 111.5960, "nw_karangjati", 2, "candle", ["drop", "block"], "#f09546"),
            ("nw_f12", "Manufaktur Berat Ngawi", "Assemble Rocket (1 Bar + 1 Chevron + 1 Wedge → Rocket)", "factory", "assemble", -7.4090, 111.5820, "nw_bringin", 2, "rocket", ["bar", "chevron", "wedge"], "#db4c5e"),
        ],
        river_ids=["RIV-MAINSTEM", "RIV-MADIUN"],
        include_rail=True,
    ))

    # 6. Kabupaten Ponorogo Detail (21 Kecamatan)
    maps.append(build_single_regency_map(
        raw, "kab_ponorogo", "kab_ponorogo",
        "Kabupaten Ponorogo (Bumi Reog)",
        "21 Kecamatan · Alun-Alun Ponorogo, Sumoroto, Jetis, Balong, Slahung & Telaga Ngebel",
        "KAB. PONOROGO",
        "Lembah subur Kali Sekayu/Madiun hulu dengan jaringan jalan arteri OSM asli dari Babadan ke Alun-Alun, Sumoroto, Slahung, dan lereng Telaga Ngebel.",
        scale=3300.0,
        sector_defs=[
            ("Kota Ponorogo, Babadan & Siman", "Ponorogo, Babadan, Jenangan, Siman, Sukorejo & Mlarak", "#9b5eb8", "rgba(155,94,184,0.11)", True, [{"good": "capsule", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "bar", "targetPerMin": 3.0, "currentPerMin": 0}], ["Ponorogo", "Babadan", "Jenangan", "Siman", "Sukorejo", "Mlarak"]),
            ("Poros Barat Sumoroto & Badegan", "Kauman, Badegan, Sampung & Jambon", "#d96b43", "rgba(217,107,67,0.11)", False, [{"good": "pebble", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "paddle", "targetPerMin": 2.5, "currentPerMin": 0}], ["Kauman", "Badegan", "Sampung", "Jambon"]),
            ("Selatan Slahung & Timur Ngebel", "Jetis, Balong, Slahung, Bungkal, Sambit, Sawoo, Ngrayun, Pulung, Sooko, Pudak & Ngebel", "#4a9658", "rgba(74,150,88,0.11)", False, [{"good": "cart", "targetPerMin": 2.5, "currentPerMin": 0}, {"good": "bus", "targetPerMin": 2.5, "currentPerMin": 0}], ["Jetis", "Balong", "Slahung", "Bungkal", "Sambit", "Sawoo", "Ngrayun", "Pulung", "Sooko", "Pudak", "Ngebel"]),
        ],
        j_specs=[
            ("po_alun", "Alun-Alun Kota Ponorogo", -7.8670, 111.4625, 0, "roundabout", "Pusat Bumi Reog"),
            ("po_babadan", "Simpang Babadan Utara", -7.8220, 111.4810, 0, "lights", None),
            ("po_jenangan", "Simpang Jenangan", -7.8290, 111.5450, 0, "none", None),
            ("po_siman", "Bundaran Siman", -7.8900, 111.4960, 0, "none", "Kampus & Siman"),
            ("po_sukorejo", "Simpang Sukorejo", -7.8360, 111.4250, 0, "none", None),
            ("po_sumoroto", "Simpang Lima Sumoroto (Kauman)", -7.8870, 111.4150, 1, "lights", "Pasar Sumoroto"),
            ("po_sampung", "Simpang Sampung", -7.8300, 111.3500, 1, "none", None),
            ("po_badegan", "Simpang Badegan", -7.8950, 111.3240, 1, "yield", None),
            ("po_jambon", "Simpang Jambon", -7.9240, 111.3750, 1, "none", None),
            ("po_jetis", "Simpang Dengok–Jetis", -7.9380, 111.4800, 2, "lights", None),
            ("po_balong", "Simpang Balong", -7.9520, 111.4170, 2, "none", None),
            ("po_slahung", "Simpang Slahung", -8.0130, 111.4080, 2, "yield", None),
            ("po_sambit", "Simpang Sambit–Sawoo", -7.9800, 111.5450, 2, "none", "Gerbang Trenggalek"),
            ("po_pulung", "Simpang Pulung", -7.8700, 111.6270, 2, "none", None),
            ("po_ngebel", "Kawasan Telaga Ngebel", -7.8020, 111.6310, 2, "none", "Telaga Ngebel"),
        ],
        e_specs=[
            ("po_e1", "Jl. Soekarno-Hatta Ponorogo", "po_babadan", "po_alun", "national", 0, 2, 0.0, False, False, None),
            ("po_e2", "Jl. Raya Babadan–Jenangan", "po_babadan", "po_jenangan", "provincial", 0, 1, 0.0, False, False, None),
            ("po_e3", "Jl. Pramuka – Siman", "po_alun", "po_siman", "municipal", 0, 2, 0.0, False, False, None),
            ("po_e4", "Jl. Raya Jenangan–Siman", "po_jenangan", "po_siman", "local", 0, 1, 0.0, False, False, None),
            ("po_e5", "Jl. Raya Ponorogo–Sukorejo", "po_alun", "po_sukorejo", "local", 0, 1, 0.0, True, False, None),
            ("po_e6", "Jl. Jend. Sudirman – Sumoroto", "po_alun", "po_sumoroto", "national", 1, 2, 0.0, True, False, None),
            ("po_e7", "Jl. Poros Sukorejo–Sumoroto", "po_sukorejo", "po_sumoroto", "local", 1, 1, 0.0, False, False, None),
            ("po_e8", "Jl. Raya Sumoroto–Sampung", "po_sumoroto", "po_sampung", "provincial", 1, 1, 0.0, False, False, None),
            ("po_e9", "Jl. Nasional Sumoroto–Badegan", "po_sumoroto", "po_badegan", "national", 1, 2, 0.0, False, False, None),
            ("po_e10", "Jl. Raya Sumoroto–Jambon", "po_sumoroto", "po_jambon", "local", 1, 1, 0.0, False, False, None),
            ("po_e11", "Jl. HOS Cokroaminoto – Jetis", "po_alun", "po_jetis", "national", 2, 2, 0.0, False, False, None),
            ("po_e12", "Jl. Raya Siman–Jetis", "po_siman", "po_jetis", "provincial", 2, 1, 0.0, False, False, None),
            ("po_e13", "Jl. Nasional Dengok–Balong", "po_jetis", "po_balong", "national", 2, 2, 0.0, True, False, None),
            ("po_e14", "Jl. Poros Jambon–Balong", "po_jambon", "po_balong", "local", 2, 1, 0.0, False, False, None),
            ("po_e15", "Jl. Nasional Balong–Slahung", "po_balong", "po_slahung", "national", 2, 2, 0.0, False, False, None),
            ("po_e16", "Jl. Nasional Jetis–Sambit–Sawoo", "po_jetis", "po_sambit", "national", 2, 2, 0.0, False, False, None),
            ("po_e17", "Jl. Raya Siman–Pulung", "po_siman", "po_pulung", "provincial", 2, 2, 0.0, False, False, None),
            ("po_e18", "Jl. Wisata Jenangan–Telaga Ngebel", "po_jenangan", "po_ngebel", "local", 2, 1, 0.05, False, False, None),
            ("po_e19", "Jl. Sabuk Ngebel–Pulung", "po_ngebel", "po_pulung", "local", 2, 1, 0.0, False, False, None),
            ("po_off1", "Jalan Lingkar Selatan Ponorogo (Sumoroto–Jetis)", "po_sumoroto", "po_jetis", "toll", 1, 2, 0.14, True, True, "off_po_ring"),
        ],
        offer_specs=[("off_po_ring", "Ring Road Selatan Ponorogo", "Sabuk cepat menghubungkan Sumoroto langsung ke Dengok–Jetis melewati Alun-Alun", "ring", ["po_off1"], 1, 6, 1)],
        fac_specs=[
            ("po_f1", "Sawah Lembah Babadan", "Supplier Padi Ponorogo", "supplier", "raw", -7.8180, 111.4860, "po_babadan", 0, "dot", [], "#4ea854"),
            ("po_f2", "Kuari Batu Sukorejo", "Supplier Batu Konstruksi", "supplier", "raw", -7.8320, 111.4200, "po_sukorejo", 0, "block", [], "#5b82b8"),
            ("po_f3", "Pabrik Gula & Tepung Siman", "Press Capsule (2 Dot → Capsule)", "factory", "press", -7.8940, 111.5010, "po_siman", 0, "capsule", ["dot"], "#5ec269"),
            ("po_f4", "Pandai Besi & Baja Jenangan", "Press Baja (2 Block → Bar)", "factory", "press", -7.8250, 111.5500, "po_jenangan", 0, "bar", ["block"], "#6b94cc"),
            ("po_f5", "Pasar Induk Songgolangit", "Pusat Niaga Kota Ponorogo", "market", "export", -7.8630, 111.4580, "po_alun", 0, None, ["capsule", "bar", "pebble", "paddle", "cart", "bus"], "#9b5eb8"),
            ("po_f6", "Tambang Kapur Sampung", "Supplier Batu Kapur", "supplier", "raw", -7.8260, 111.3450, "po_sampung", 1, "block", [], "#5b82b8"),
            ("po_f7", "Granit Halus Badegan", "Press Pebble (1 Dot + 1 Block → Pebble)", "factory", "press", -7.8990, 111.3190, "po_badegan", 1, "pebble", ["dot", "block"], "#4eb3a8"),
            ("po_f8", "Alsintan Terpadu Sumoroto", "Assemble Paddle (1 Bar + 1 Pebble → Paddle)", "factory", "assemble", -7.8910, 111.4110, "po_sumoroto", 1, "paddle", ["bar", "pebble"], "#88ab44"),
            ("po_f9", "Hutan Pinus Pulung–Pudak", "Supplier Kayu Timur", "supplier", "raw", -7.8740, 111.6330, "po_pulung", 2, "wedge", [], "#d9833b"),
            ("po_f10", "Karoseri Selatan Slahung", "Assemble Cart (1 Bar + 2 Dot → Cart)", "factory", "assemble", -8.0170, 111.4030, "po_slahung", 2, "cart", ["bar", "dot"], "#d9644a"),
            ("po_f11", "Perakitan Bus Sambit", "Assemble Bus (1 Capsule + 2 Dot → Bus)", "factory", "assemble", -7.9850, 111.5500, "po_sambit", 2, "bus", ["capsule", "dot"], "#3d8bd9"),
        ],
        extra_water=[("ngebel_detail", "Telaga Ngebel", "lake", [[-7.795, 111.635], [-7.795, 111.652], [-7.808, 111.652], [-7.808, 111.635]])],
        river_ids=["RIV-MADIUN"],
        include_rail=False,
    ))

    # 7. Kabupaten Pacitan Detail (12 Kecamatan + Teluk Pacitan & Harbour)
    maps.append(build_single_regency_map(
        raw, "kab_pacitan", "kab_pacitan",
        "Kabupaten Pacitan (Teluk & JLS Selatan)",
        "12 Kecamatan · Teluk Pacitan, Pelabuhan Tamperan, Kali Grindulu, Punung & JLS",
        "KAB. PACITAN",
        "Topografi pegunungan kars Seribu yang bermuara di Teluk Pacitan dan Pelabuhan Samudra Tamperan, dihubungkan oleh Jalur Lintas Selatan (JLS).",
        scale=3400.0,
        sector_defs=[
            ("Teluk Pacitan, Arjosari & Kebonagung", "Pacitan, Arjosari, Kebonagung & Pringkuku", "#2f74ba", "rgba(47,116,186,0.11)", True, [{"good": "capsule", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "pebble", "targetPerMin": 3.0, "currentPerMin": 0}], ["Pacitan", "Arjosari", "Kebonagung", "Pringkuku"]),
            ("Pegunungan Kars Barat Punung–Donorojo", "Punung, Donorojo, Nawangan & Bandar", "#c98b32", "rgba(201,139,50,0.11)", False, [{"good": "diamond", "targetPerMin": 3.0, "currentPerMin": 0}, {"good": "gem", "targetPerMin": 2.5, "currentPerMin": 0}], ["Punung", "Donorojo", "Nawangan", "Bandar"]),
            ("Pantai Timur JLS Tulakan–Lorok", "Tegalombo, Tulakan, Ngadirojo & Sudimoro", "#4a9658", "rgba(74,150,88,0.11)", False, [{"good": "fish", "targetPerMin": 2.5, "currentPerMin": 0}, {"good": "bus", "targetPerMin": 2.5, "currentPerMin": 0}], ["Tegalombo", "Tulakan", "Ngadirojo", "Sudimoro"]),
        ],
        j_specs=[
            ("pc_kota", "Alun-Alun Kota Pacitan", -8.1940, 111.1050, 0, "lights", "Teluk Pacitan"),
            ("pc_tamperan", "Pelabuhan Samudra Tamperan", -8.2150, 111.0880, 0, "none", "Harbour Ekspor"),
            ("pc_arjosari", "Simpang Arjosari (Kali Grindulu)", -8.1100, 111.1580, 0, "yield", None),
            ("pc_kebonagung", "Simpang Kebonagung", -8.2080, 111.1750, 0, "none", None),
            ("pc_pringkuku", "Simpang Pringkuku", -8.1880, 111.0320, 0, "none", None),
            ("pc_punung", "Simpang Punung (Goa Gong)", -8.1140, 111.0360, 1, "lights", "Kawasan Kars"),
            ("pc_donorojo", "Simpang Donorojo Barat", -8.1480, 110.9470, 1, "none", "Pantai Klayar"),
            ("pc_nawangan", "Simpang Nawangan", -7.9890, 111.1840, 1, "none", "Monumen Jenderal Sudirman"),
            ("pc_bandar", "Simpang Bandar", -7.9890, 111.2660, 1, "none", None),
            ("pc_tegalombo", "Simpang Tegalombo", -8.0550, 111.3040, 2, "none", None),
            ("pc_tulakan", "Simpang Tulakan (JLS)", -8.1650, 111.2750, 2, "lights", None),
            ("pc_ngadirojo", "Simpang Lorok (Ngadirojo)", -8.1920, 111.3290, 2, "none", None),
            ("pc_sudimoro", "Simpang Sudimoro Timur", -8.2250, 111.3810, 2, "none", "PLTU & JLS Timur"),
        ],
        e_specs=[
            ("pc_e1", "Jl. Teluk Pacitan – Tamperan", "pc_kota", "pc_tamperan", "municipal", 0, 2, 0.05, False, False, None),
            ("pc_e2", "Jl. Nasional Pacitan–Arjosari", "pc_kota", "pc_arjosari", "national", 0, 2, 0.0, True, False, None),
            ("pc_e3", "JLS Pacitan–Kebonagung", "pc_kota", "pc_kebonagung", "national", 0, 2, 0.06, True, False, None),
            ("pc_e4", "Jl. Raya Pacitan–Pringkuku", "pc_kota", "pc_pringkuku", "provincial", 0, 2, 0.0, False, False, None),
            ("pc_e5", "Jl. Kars Pringkuku–Punung", "pc_pringkuku", "pc_punung", "provincial", 1, 1, 0.0, False, False, None),
            ("pc_e6", "Jl. Poros Arjosari–Punung", "pc_arjosari", "pc_punung", "local", 1, 1, -0.05, False, False, None),
            ("pc_e7", "Jl. Nasional Punung–Donorojo", "pc_punung", "pc_donorojo", "national", 1, 2, 0.0, False, False, None),
            ("pc_e8", "Jl. Pegunungan Arjosari–Nawangan", "pc_arjosari", "pc_nawangan", "provincial", 1, 1, 0.0, False, False, None),
            ("pc_e9", "Jl. Pegunungan Nawangan–Bandar", "pc_nawangan", "pc_bandar", "local", 1, 1, 0.0, False, False, None),
            ("pc_e10", "Jl. Raya Bandar–Tegalombo", "pc_bandar", "pc_tegalombo", "local", 2, 1, 0.0, False, False, None),
            ("pc_e11", "Jl. Nasional Arjosari–Tegalombo", "pc_arjosari", "pc_tegalombo", "national", 2, 2, 0.0, True, False, None),
            ("pc_e12", "Jl. Poros Tegalombo–Tulakan", "pc_tegalombo", "pc_tulakan", "provincial", 2, 1, 0.0, False, False, None),
            ("pc_e13", "JLS Kebonagung–Tulakan", "pc_kebonagung", "pc_tulakan", "national", 2, 2, 0.05, False, False, None),
            ("pc_e14", "JLS Tulakan–Lorok Ngadirojo", "pc_tulakan", "pc_ngadirojo", "national", 2, 2, 0.0, True, False, None),
            ("pc_e15", "JLS Ngadirojo–Sudimoro", "pc_ngadirojo", "pc_sudimoro", "national", 2, 2, 0.04, False, False, None),
            ("pc_off1", "JLS Pantai Barat (Donorojo–Klayar–Tamperan)", "pc_donorojo", "pc_tamperan", "toll", 1, 2, 0.14, True, False, "off_pc_jls"),
        ],
        offer_specs=[("off_pc_jls", "Terusan JLS Pantai Klayar–Tamperan", "Jalur pesisir selatan menghubungkan Donorojo langsung ke Pelabuhan Tamperan", "jls", ["pc_off1"], 1, 4, 1)],
        fac_specs=[
            ("pc_f1", "Pertanian Lembah Grindulu Arjosari", "Supplier Pangan Pacitan", "supplier", "raw", -8.1050, 111.1630, "pc_arjosari", 0, "dot", [], "#4ea854"),
            ("pc_f2", "Kuari Batu Kars Pringkuku", "Supplier Kars Selatan", "supplier", "raw", -8.1930, 111.0260, "pc_pringkuku", 0, "block", [], "#5b82b8"),
            ("pc_f3", "Olahan Pangan Kebonagung", "Press Capsule (2 Dot → Capsule)", "factory", "press", -8.2130, 111.1800, "pc_kebonagung", 0, "capsule", ["dot"], "#5ec269"),
            ("pc_f4", "Batu Halus & Marmer Pacitan", "Press Pebble (1 Dot + 1 Block → Pebble)", "factory", "press", -8.1890, 111.1120, "pc_kota", 0, "pebble", ["dot", "block"], "#4eb3a8"),
            ("pc_f5", "Pelabuhan Samudra Tamperan", "Harbour Ekspor Kapal Kargo Samudra Hindia", "harbour", "export", -8.2190, 111.0840, "pc_tamperan", 0, None, ["capsule", "pebble", "diamond", "gem", "fish", "bus"], "#2f74ba"),
            ("pc_f6", "Hutan Pinus Nawangan", "Supplier Kayu Pegunungan", "supplier", "raw", -7.9840, 111.1790, "pc_nawangan", 1, "wedge", [], "#d9833b"),
            ("pc_f7", "Panel Kayu Punung", "Press Diamond (2 Wedge → Diamond)", "factory", "press", -8.1180, 111.0410, "pc_punung", 1, "diamond", ["wedge"], "#e69b45"),
            ("pc_f8", "Pelat Mineral Bandar", "Press Shield (1 Wedge + 1 Block → Shield)", "factory", "press", -7.9940, 111.2710, "pc_bandar", 1, "shield", ["wedge", "block"], "#9c78bd"),
            ("pc_f9", "Sentra Batu Aji & Permata Donorojo", "Press Gem (1 Diamond + 1 Shield → Gem)", "factory", "press", -8.1530, 110.9420, "pc_donorojo", 1, "gem", ["diamond", "shield"], "#3ec4b9"),
            ("pc_f10", "Kriya Kayu Tegalombo", "Cut Chevron (2 Wedge → Chevron)", "factory", "cut", -8.0590, 111.3090, "pc_tegalombo", 2, "chevron", ["wedge"], "#eb7b4b"),
            ("pc_f11", "Cold Storage Ikan Lorok–Tulakan", "Assemble Fish (1 Capsule + 1 Chevron → Fish)", "factory", "assemble", -8.1970, 111.3340, "pc_ngadirojo", 2, "fish", ["capsule", "chevron"], "#43a9db"),
            ("pc_f12", "Karoseri Pesisir Sudimoro", "Assemble Bus (1 Capsule + 2 Dot → Bus)", "factory", "assemble", -8.2290, 111.3860, "pc_sudimoro", 2, "bus", ["capsule", "dot"], "#3d8bd9"),
        ],
        extra_water=[("hindia_pct", "Samudra Hindia & Teluk Pacitan", "ocean", [
            [-8.208, 110.88], [-8.218, 110.98], [-8.232, 111.08], [-8.206, 111.108],
            [-8.228, 111.125], [-8.248, 111.24], [-8.262, 111.42], [-8.36, 111.44],
            [-8.36, 110.88], [-8.208, 110.88],
        ])],
        river_ids=["RIV-GRINDULU"],
        include_rail=False,
    ))

    def clean_ring(pts):
        cleaned = []
        for p in pts:
            if not cleaned or math.hypot(p[0] - cleaned[-1][0], p[1] - cleaned[-1][1]) > 0.5:
                cleaned.append(p)
        if len(cleaned) >= 2 and math.hypot(cleaned[0][0] - cleaned[-1][0], cleaned[0][1] - cleaned[-1][1]) <= 0.5:
            cleaned.pop()
        return cleaned

    def find_polyline_crossing_spans(road_pts, target_lines_with_halfwidth, end_margin=16.0, bank_pad=4.0, min_span=16.0):
        total_l = polyline_len(road_pts)
        if total_l < end_margin * 2.0 + 8.0 or not target_lines_with_halfwidth:
            return []
        # Build cumulative lengths
        cum = [0.0]
        for i in range(len(road_pts) - 1):
            cum.append(cum[-1] + math.hypot(road_pts[i + 1][0] - road_pts[i][0], road_pts[i + 1][1] - road_pts[i][1]))

        step = 2.0
        s = end_margin
        hits = []
        seg_idx = 0
        while s <= total_l - end_margin:
            while seg_idx < len(cum) - 2 and cum[seg_idx + 1] < s:
                seg_idx += 1
            seg_len = max(1e-6, cum[seg_idx + 1] - cum[seg_idx])
            t = (s - cum[seg_idx]) / seg_len
            px = road_pts[seg_idx][0] + t * (road_pts[seg_idx + 1][0] - road_pts[seg_idx][0])
            py = road_pts[seg_idx][1] + t * (road_pts[seg_idx + 1][1] - road_pts[seg_idx][1])
            crossed = False
            for t_pts, hw in target_lines_with_halfwidth:
                for k in range(len(t_pts) - 1):
                    if point_to_seg_dist(px, py, t_pts[k][0], t_pts[k][1], t_pts[k + 1][0], t_pts[k + 1][1]) <= hw:
                        crossed = True
                        break
                if crossed:
                    break
            if crossed:
                hits.append(s)
            s += step

        if not hits:
            return []
        raw_spans = [[hits[0], hits[0]]]
        for hs in hits[1:]:
            if hs - raw_spans[-1][1] <= 16.0:
                raw_spans[-1][1] = hs
            else:
                raw_spans.append([hs, hs])

        final_spans = []
        for a, b in raw_spans:
            s0 = max(end_margin, a - bank_pad)
            s1 = min(total_l - end_margin, b + bank_pad)
            if s1 - s0 < min_span:
                mid = 0.5 * (s0 + s1)
                s0 = max(end_margin, mid - min_span * 0.5)
                s1 = min(total_l - end_margin, mid + min_span * 0.5)
            if s1 - s0 >= 10.0:
                if final_spans and s0 - final_spans[-1][1] <= 12.0:
                    final_spans[-1][1] = round(s1, 1)
                else:
                    final_spans.append([round(s0, 1), round(s1, 1)])
        return final_spans

    total_bridges = 0
    total_overpasses = 0
    for m in maps:
        for reg in m["regions"]:
            reg["polygons"] = [r for r in (clean_ring(p) for p in reg["polygons"]) if len(r) >= 3]
        for wb in m["waterBodies"]:
            wb["polygon"] = clean_ring(wb["polygon"])
        for rv in m["rivers"]:
            rv["points"] = chaikin_smooth(rv["points"], passes=2)
        for rw in m["railways"]:
            rw["points"] = chaikin_smooth(rw["points"], passes=2)

        river_targets = [(rv["points"], float(rv.get("widthPx", 16)) * 0.5 + 5.5) for rv in m["rivers"] if len(rv["points"]) >= 2]
        rail_targets = [(rw["points"], 9.5) for rw in m["railways"] if len(rw["points"]) >= 2]

        e_lookup = {r["id"]: r for r in m["roads"]}
        for r in m["roads"]:
            bspans = find_polyline_crossing_spans(r["points"], river_targets, end_margin=15.0, bank_pad=4.5, min_span=16.0)
            r["bridgeSpans"] = bspans
            r["isBridge"] = len(bspans) > 0
            total_bridges += len(bspans)

            if r.get("isOverpass") or r.get("roadClass") == "toll":
                non_incident = list(rail_targets)
                ru, rv_id = r["from"], r["to"]
                for other in m["roads"]:
                    if other["id"] == r["id"]:
                        continue
                    if other["from"] in (ru, rv_id) or other["to"] in (ru, rv_id):
                        continue
                    if other.get("roadClass") == "toll" and r.get("roadClass") != "toll":
                        continue
                    non_incident.append((other["points"], 10.5))
                ospans = find_polyline_crossing_spans(r["points"], non_incident, end_margin=18.0, bank_pad=6.0, min_span=20.0)
                # Keep away from river bridge spans so bridge and overpass parapets don't overlap
                filtered_ospans = []
                for oa, ob in ospans:
                    if not any(not (ob < ba - 6.0 or oa > bb + 6.0) for ba, bb in bspans):
                        filtered_ospans.append([oa, ob])
                r["overpassSpans"] = filtered_ospans
                r["isOverpass"] = len(filtered_ospans) > 0
                total_overpasses += len(filtered_ospans)
            else:
                r["overpassSpans"] = []
                r["isOverpass"] = False

        for off in m["roadOffers"]:
            off["lengthPx"] = round(sum(e_lookup[eid]["lengthPx"] for eid in off["edgeIds"]), 1)
            b_px = sum((s1 - s0) for eid in off["edgeIds"] for s0, s1 in e_lookup[eid]["bridgeSpans"])
            off["bridgeSpanPx"] = round(b_px, 1)

    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    payload = json.dumps({"version": 1, "maps": maps}, separators=(",", ":"))
    with open(OUT_JSON, "w", encoding="utf-8") as fp:
        fp.write(payload)

    print(f"Generated {len(maps)} maps into {OUT_JSON} ({len(payload) // 1024} KB) [river_bridges={total_bridges}, overpasses={total_overpasses}]:")
    for m in maps:
        nb = sum(len(r["bridgeSpans"]) for r in m["roads"])
        no = sum(len(r["overpassSpans"]) for r in m["roads"])
        avg_pts = sum(len(r["points"]) for r in m["roads"]) / max(1, len(m["roads"]))
        print(f"  - {m['id']:20s}: {len(m['regions'])} regions, {len(m['junctions'])} junctions, {len(m['roads'])} roads (avg {avg_pts:.1f} pts, {nb} bridges, {no} overpasses), {len(m['facilities'])} facilities")


if __name__ == "__main__":
    build_all_maps()

