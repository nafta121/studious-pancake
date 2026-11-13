#!/usr/bin/env python3
"""
Fetches real-world WGS84 road centerlines for all Karesidenan Madiun road edges
from OSRM (OpenStreetMap driving router) with fallback to routing.openstreetmap.de,
and saves a deterministic offline cache to geodata/madiun_osrm_roads_cache.json.
"""

import json
import math
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_PATH = os.path.join(ROOT, "geodata", "madiun_osrm_roads_cache.json")
MAP_DATA_PATH = os.path.join(ROOT, "data", "madiun_maps.json")

# Real intermediate via-waypoints (lat, lon) for actual Trans-Java Toll Roads & specific corridors
# so OSRM snaps onto the true highway/tollway alignment rather than parallel urban streets.
EDGE_VIA_HINTS = {
    # Trans-Java Toll Roads (Solo - Ngawi - Madiun - Caruban)
    "e_offer_tol_caruban": [(-7.5395, 111.6060)],
    "cm_off1": [(-7.5395, 111.6060)],
    "e_offer_tol_ngawi": [(-7.4480, 111.4720), (-7.5180, 111.5220)],
    "nw_off1": [(-7.3920, 111.2450), (-7.4120, 111.3550), (-7.4270, 111.4280)],
    # JLS Pantai Selatan Pacitan coastal cliff road (Donorojo - Klayar - Pringkuku coast - Tamperan)
    "e_offer_jls_barat": [(-8.2120, 110.9920), (-8.2290, 111.0480)],
    "pc_off1": [(-8.2120, 110.9920), (-8.2290, 111.0480)],
    # Proposed outer ring/bypass corridors (keep clean bypass alignment around downtown)
    "e_offer_ringtimur_1": [(-7.6305, 111.5585)],
    "km_off2": [(-7.6295, 111.5565)],
    "km_off1": [(-7.6145, 111.5255)],
    "e_offer_bypass_mgt": [(-7.6460, 111.4320)],
    "mg_off1": [(-7.6020, 111.3320)],
    "po_off1": [(-7.9220, 111.4380)],
}

ENDPOINTS = [
    "https://router.project-osrm.org/route/v1/driving",
    "https://routing.openstreetmap.de/routed-car/route/v1/driving",
]


def rdp_latlon(points, epsilon_deg=0.00018):
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
    if max_d > epsilon_deg:
        left = rdp_latlon(points[: idx + 1], epsilon_deg)
        right = rdp_latlon(points[idx:], epsilon_deg)
        return left[:-1] + right
    return [points[0], points[-1]]


def fetch_single_osrm(coord_chain):
    """coord_chain is list of (lat, lon). Returns list of [lat, lon] or None."""
    coord_str = ";".join(f"{lon:.5f},{lat:.5f}" for lat, lon in coord_chain)
    for base in ENDPOINTS:
        url = f"{base}/{coord_str}?overview=full&geometries=geojson&continue_straight=true"
        for attempt in range(2):
            try:
                req = urllib.request.Request(
                    url,
                    headers={"User-Agent": "IncrementalTrafficMadiunGeodata/1.2"},
                )
                with urllib.request.urlopen(req, timeout=12) as resp:
                    if resp.status == 200:
                        data = json.loads(resp.read().decode("utf-8"))
                        routes = data.get("routes") or []
                        if routes:
                            coords = routes[0]["geometry"]["coordinates"]
                            # Convert GeoJSON [lon, lat] -> [lat, lon]
                            pts = [[round(c[1], 5), round(c[0], 5)] for c in coords]
                            # Light simplification in WGS84 (~18m) to keep cache compact while preserving all curves
                            pts = rdp_latlon(pts, 0.00016)
                            # Pin exact endpoints
                            pts[0] = [round(coord_chain[0][0], 5), round(coord_chain[0][1], 5)]
                            pts[-1] = [round(coord_chain[-1][0], 5), round(coord_chain[-1][1], 5)]
                            return pts
            except Exception:
                time.sleep(0.25 * (attempt + 1))
    return None


def main():
    if not os.path.exists(MAP_DATA_PATH):
        print(f"Missing {MAP_DATA_PATH}", file=sys.stderr)
        sys.exit(1)

    existing_cache = {}
    if os.path.exists(CACHE_PATH):
        try:
            existing_cache = json.load(open(CACHE_PATH, "r", encoding="utf-8")).get("edges", {})
        except Exception:
            existing_cache = {}

    bundle = json.load(open(MAP_DATA_PATH, "r", encoding="utf-8"))
    tasks = {}
    for m in bundle["maps"]:
        map_id = m["id"]
        j_lookup = {j["id"]: (j["lat"], j["lon"]) for j in m["junctions"]}
        for r in m["roads"]:
            eid = r["id"]
            key = f"{map_id}:{eid}"
            u_ll = j_lookup[r["from"]]
            v_ll = j_lookup[r["to"]]
            vias = EDGE_VIA_HINTS.get(eid, [])
            chain = [u_ll] + list(vias) + [v_ll]
            if key in existing_cache and len(existing_cache[key]) >= 2:
                continue
            tasks[key] = chain

    print(f"Cached edges: {len(existing_cache)}, to fetch from OSRM: {len(tasks)}")
    results = dict(existing_cache)
    failed = []

    if tasks:
        with ThreadPoolExecutor(max_workers=6) as pool:
            futs = {pool.submit(fetch_single_osrm, chain): key for key, chain in tasks.items()}
            done_n = 0
            for fut in as_completed(futs):
                key = futs[fut]
                done_n += 1
                pts = fut.result()
                if pts and len(pts) >= 2:
                    results[key] = pts
                else:
                    failed.append(key)
                if done_n % 20 == 0 or done_n == len(tasks):
                    print(f"  [{done_n}/{len(tasks)}] fetched (ok={len(results)}, failed={len(failed)})")

    os.makedirs(os.path.dirname(CACHE_PATH), exist_ok=True)
    out = {
        "source": "OpenStreetMap ODbL via OSRM driving router",
        "edgeCount": len(results),
        "edges": {k: results[k] for k in sorted(results.keys())},
    }
    with open(CACHE_PATH, "w", encoding="utf-8") as fp:
        json.dump(out, fp, separators=(",", ":"))
    print(f"Saved {len(results)} real-world road polylines to {CACHE_PATH} ({os.path.getsize(CACHE_PATH)//1024} KB). Failed: {len(failed)}")
    if failed:
        print("Failed keys:", failed)


if __name__ == "__main__":
    main()
