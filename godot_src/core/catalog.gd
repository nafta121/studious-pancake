class_name GameCatalog
extends RefCounted

## Authentic Incremental Traffic commodity, fleet, color, and ledger catalog
## reconstructed from original Goods / TruckModel / Industry / Ledger / CONST
## and localized to Karesidenan Madiun.

const PACE := 2.0
const GAME_MINUTE_SEC := 60.0 * PACE

# Authentic CONST cartographic palette (const.gd)
const COLOR_BACKGROUND := Color("#F2F0E5")
const COLOR_ROAD := Color("#3C3F4A")
const COLOR_LANE_MARKING := Color("#F2F0E5")
const COLOR_SIDEWALK := Color("#E2DED2")
const COLOR_CURB := Color("#A9A59B")
const COLOR_WATER := Color("#A9CDD8")
const COLOR_WATER_DEEP := Color("#86B5C6")
const COLOR_GRASS := Color("#C9D8A6")
const COLOR_PARK_DEEP := Color("#6F9A52")
const COLOR_SHADOW := Color("#363D55")

const INFRA_PRICES := {
	"light": 1000,
	"roundabout": 10000,
	"roundabout2_upgrade": 16000,
	"lane_base": 500,
	"lane_per_px": 5,
	"pocket": 1125,
	"close_street": 3200,
}

const POCKET_SIZES_ORIG: Array[float] = [0.0, 130.0, 260.0, 410.0]
const POCKET_LABELS: Array[String] = ["None", "Short", "Medium", "Long"]

const ROUTE_PALETTE: Array[Color] = [
	Color("#2c7be5"),
	Color("#00a878"),
	Color("#e67e22"),
	Color("#d6336c"),
	Color("#15aabf"),
	Color("#c92a2a"),
	Color("#5c940d"),
	Color("#d9480f"),
]

const FACTORY_SPEED_SHAPES_PER_MIN: Array[int] = [8, 10, 12, 14, 16, 18, 22, 26, 30, 36, 42, 50, 60]
const BUFFER_CAPACITIES: Array[int] = [4, 8, 15, 30, 60]
# Authentic Industry._BRil6kGd1pA5 timetable wait factors (Lv.3 = 0.0 wait!)
const TIMETABLE_WAIT_FACTORS: Array[float] = [1.0, 0.6, 0.3, 0.0]

## Complete 44 commodities from original Goods.RAW + Goods.RECIPES (3 raw + 41 crafted = 44 total)
## Every recipe conserves $50 per raw equivalent (Goods.value).
const GOODS := {
	# --- Tier 1: Raw Materials (3) ---
	"dot": {
		"id": "dot", "name": "Dot", "local": "Padi & Tebu",
		"tier": 1, "role": "raw", "op": "raw", "slots": 1, "value": 50, "weight": 40,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"), "inputs": []
	},
	"wedge": {
		"id": "wedge", "name": "Wedge", "local": "Kayu Jati",
		"tier": 1, "role": "raw", "op": "raw", "slots": 1, "value": 50, "weight": 50,
		"color": Color("#EFA42A"), "stroke": Color("#94600E"), "inputs": []
	},
	"block": {
		"id": "block", "name": "Block", "local": "Batu & Pasir",
		"tier": 1, "role": "raw", "op": "raw", "slots": 1, "value": 50, "weight": 60,
		"color": Color("#2E6BB0"), "stroke": Color("#1B416E"), "inputs": []
	},

	# --- Tier 2: Basic Parts — Press & Cut (9) ---
	"capsule": {
		"id": "capsule", "name": "Capsule", "local": "Gula Kristal",
		"tier": 2, "role": "part", "op": "press", "slots": 1, "value": 100,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "dot", "qty": 2}]
	},
	"diamond": {
		"id": "diamond", "name": "Diamond", "local": "Panel Jati",
		"tier": 2, "role": "part", "op": "press", "slots": 1, "value": 100,
		"color": Color("#EFA42A"), "stroke": Color("#94600E"),
		"inputs": [{"good": "wedge", "qty": 2}]
	},
	"bar": {
		"id": "bar", "name": "Bar", "local": "Baja Rel",
		"tier": 2, "role": "part", "op": "press", "slots": 1, "value": 100,
		"color": Color("#2E6BB0"), "stroke": Color("#1B416E"),
		"inputs": [{"good": "block", "qty": 2}]
	},
	"drop": {
		"id": "drop", "name": "Drop", "local": "Minyak Atsiri",
		"tier": 2, "role": "part", "op": "press", "slots": 1, "value": 100,
		"color": Color("#E8792F"), "stroke": Color("#8F4312"),
		"inputs": [{"good": "dot", "qty": 1}, {"good": "wedge", "qty": 1}]
	},
	"pebble": {
		"id": "pebble", "name": "Pebble", "local": "Keramik & Marmer",
		"tier": 2, "role": "part", "op": "press", "slots": 1, "value": 100,
		"color": Color("#8B5A9C"), "stroke": Color("#53335E"),
		"inputs": [{"good": "dot", "qty": 1}, {"good": "block", "qty": 1}]
	},
	"shield": {
		"id": "shield", "name": "Shield", "local": "Pelat Komposit",
		"tier": 2, "role": "part", "op": "press", "slots": 1, "value": 100,
		"color": Color("#5F9B52"), "stroke": Color("#365E2D"),
		"inputs": [{"good": "wedge", "qty": 1}, {"good": "block", "qty": 1}]
	},
	"moon": {
		"id": "moon", "name": "Moon", "local": "Kulit Samak",
		"tier": 2, "role": "part", "op": "cut", "slots": 1, "value": 100, "base": "dot",
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "dot", "qty": 2}]
	},
	"chevron": {
		"id": "chevron", "name": "Chevron", "local": "Rangka Presisi",
		"tier": 2, "role": "part", "op": "cut", "slots": 1, "value": 100, "base": "wedge",
		"color": Color("#EFA42A"), "stroke": Color("#94600E"),
		"inputs": [{"good": "wedge", "qty": 2}]
	},
	"dome": {
		"id": "dome", "name": "Dome", "local": "Kubah Cor",
		"tier": 2, "role": "part", "op": "cut", "slots": 1, "value": 100, "base": "dot",
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "dot", "qty": 1}, {"good": "block", "qty": 1}]
	},

	# --- Tier 3: Refined Parts — Press (11) ---
	"heart": {
		"id": "heart", "name": "Heart", "local": "Olahan Brem",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 150,
		"color": Color("#E8792F"), "stroke": Color("#8F4312"),
		"inputs": [{"good": "capsule", "qty": 1}, {"good": "wedge", "qty": 1}]
	},
	"star": {
		"id": "star", "name": "Star", "local": "Kriya Anyam",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 200,
		"color": Color("#EFA42A"), "stroke": Color("#94600E"),
		"inputs": [{"good": "diamond", "qty": 2}]
	},
	"leaf": {
		"id": "leaf", "name": "Leaf", "local": "Teh Lereng Lawu",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 150,
		"color": Color("#E8792F"), "stroke": Color("#8F4312"),
		"inputs": [{"good": "diamond", "qty": 1}, {"good": "dot", "qty": 1}]
	},
	"bullet": {
		"id": "bullet", "name": "Bullet", "local": "Baut Tempa",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 150,
		"color": Color("#8B5A9C"), "stroke": Color("#53335E"),
		"inputs": [{"good": "bar", "qty": 1}, {"good": "dot", "qty": 1}]
	},
	"trefoil": {
		"id": "trefoil", "name": "Trefoil", "local": "Rempah Cengkeh",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 150,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "capsule", "qty": 1}, {"good": "dot", "qty": 1}]
	},
	"acorn": {
		"id": "acorn", "name": "Acorn", "local": "Kopi Kare Wilis",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 200,
		"color": Color("#139E99"), "stroke": Color("#0B5E5B"),
		"inputs": [{"good": "capsule", "qty": 1}, {"good": "shield", "qty": 1}]
	},
	"gem": {
		"id": "gem", "name": "Gem", "local": "Permata Donorojo",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 200,
		"color": Color("#5F9B52"), "stroke": Color("#365E2D"),
		"inputs": [{"good": "diamond", "qty": 1}, {"good": "shield", "qty": 1}]
	},
	"arrow": {
		"id": "arrow", "name": "Arrow", "local": "Poros Bogie",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 200,
		"color": Color("#5F9B52"), "stroke": Color("#365E2D"),
		"inputs": [{"good": "bar", "qty": 1}, {"good": "chevron", "qty": 1}]
	},
	"wave": {
		"id": "wave", "name": "Wave", "local": "Batik Tulis",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 200,
		"color": Color("#E8792F"), "stroke": Color("#8F4312"),
		"inputs": [{"good": "drop", "qty": 1}, {"good": "moon", "qty": 1}]
	},
	"helmet": {
		"id": "helmet", "name": "Helmet", "local": "Helm Proyek",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 200,
		"color": Color("#E0533D"), "stroke": Color("#2B2F3A"),
		"inputs": [{"good": "shield", "qty": 1}, {"good": "moon", "qty": 1}]
	},
	"swirl": {
		"id": "swirl", "name": "Swirl", "local": "Anyaman Bambu",
		"tier": 3, "role": "part", "op": "press", "slots": 1, "value": 200,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "moon", "qty": 2}]
	},

	# --- Tier 4: Assembled Products — 2-Part Assembly, 2 Slots (9) ---
	"fish": {
		"id": "fish", "name": "Fish", "local": "Tuna Beku Tamperan",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "capsule", "qty": 1}, {"good": "chevron", "qty": 1}]
	},
	"mushroom": {
		"id": "mushroom", "name": "Mushroom", "local": "Jamur Tiram Segar",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#E0533D"), "stroke": Color("#1B416E"),
		"inputs": [{"good": "dome", "qty": 1}, {"good": "bar", "qty": 1}]
	},
	"paddle": {
		"id": "paddle", "name": "Paddle", "local": "Mesin Pertanian",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#8B5A9C"), "stroke": Color("#53335E"),
		"inputs": [{"good": "bar", "qty": 1}, {"good": "pebble", "qty": 1}]
	},
	"standard": {
		"id": "standard", "name": "Standard", "local": "Rambu Sinyal Rel",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#5F9B52"), "stroke": Color("#1B416E"),
		"inputs": [{"good": "bar", "qty": 1}, {"good": "shield", "qty": 1}]
	},
	"kite": {
		"id": "kite", "name": "Kite", "local": "Layang Hias",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#EFA42A"), "stroke": Color("#94600E"),
		"inputs": [{"good": "diamond", "qty": 1}, {"good": "chevron", "qty": 1}]
	},
	"bull": {
		"id": "bull", "name": "Bull", "local": "Topeng Reog",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "moon", "qty": 1}, {"good": "dome", "qty": 1}]
	},
	"imp": {
		"id": "imp", "name": "Imp", "local": "Wayang Krucil",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#8B5A9C"), "stroke": Color("#53335E"),
		"inputs": [{"good": "pebble", "qty": 1}, {"good": "chevron", "qty": 1}]
	},
	"candle": {
		"id": "candle", "name": "Candle", "local": "Porselen Halus",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 150,
		"color": Color("#2E6BB0"), "stroke": Color("#1B416E"),
		"inputs": [{"good": "drop", "qty": 1}, {"good": "block", "qty": 1}]
	},
	"eclipse": {
		"id": "eclipse", "name": "Eclipse", "local": "Roda Gigi Presisi",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 150,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "moon", "qty": 1}, {"good": "dot", "qty": 1}]
	},

	# --- Tier 5: Complex Products — 3..4-Part Assembly, 2 Slots (12) ---
	"propeller": {
		"id": "propeller", "name": "Propeller", "local": "Turbin Air",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 300,
		"color": Color("#E8792F"), "stroke": Color("#8F4312"),
		"inputs": [{"good": "drop", "qty": 3}]
	},
	"cart": {
		"id": "cart", "name": "Cart", "local": "Gerbong Kargo",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#2E6BB0"), "stroke": Color("#1B416E"),
		"inputs": [{"good": "bar", "qty": 1}, {"good": "dot", "qty": 2}]
	},
	"bus": {
		"id": "bus", "name": "Bus", "local": "Bus & Kereta INKA",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "capsule", "qty": 1}, {"good": "dot", "qty": 2}]
	},
	"rocket": {
		"id": "rocket", "name": "Rocket", "local": "Lokomotif Ekspor",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 250,
		"color": Color("#2E6BB0"), "stroke": Color("#1B416E"),
		"inputs": [{"good": "bar", "qty": 1}, {"good": "chevron", "qty": 1}, {"good": "wedge", "qty": 1}]
	},
	"lighthouse": {
		"id": "lighthouse", "name": "Lighthouse", "local": "Menara Suar Pantai",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#2E6BB0"), "stroke": Color("#1B416E"),
		"inputs": [{"good": "bar", "qty": 1}, {"good": "dot", "qty": 1}, {"good": "wedge", "qty": 1}]
	},
	"bird": {
		"id": "bird", "name": "Bird", "local": "Kerajinan Merak",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 250,
		"color": Color("#5F9B52"), "stroke": Color("#365E2D"),
		"inputs": [{"good": "dot", "qty": 1}, {"good": "drop", "qty": 1}, {"good": "shield", "qty": 1}]
	},
	"turtle": {
		"id": "turtle", "name": "Turtle", "local": "Kapal Pesisir",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 250,
		"color": Color("#5F9B52"), "stroke": Color("#365E2D"),
		"inputs": [{"good": "dome", "qty": 1}, {"good": "capsule", "qty": 1}, {"good": "dot", "qty": 1}]
	},
	"crab": {
		"id": "crab", "name": "Crab", "local": "Olahan Laut Pacitan",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 300,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "dome", "qty": 1}, {"good": "moon", "qty": 2}]
	},
	"fir": {
		"id": "fir", "name": "Fir", "local": "Mebel Pinus Sarangan",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 250,
		"color": Color("#EFA42A"), "stroke": Color("#94600E"),
		"inputs": [{"good": "wedge", "qty": 1}, {"good": "chevron", "qty": 1}, {"good": "bar", "qty": 1}]
	},
	"owl": {
		"id": "owl", "name": "Owl", "local": "Instrumen Presisi",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 300,
		"color": Color("#8B5A9C"), "stroke": Color("#53335E"),
		"inputs": [{"good": "pebble", "qty": 1}, {"good": "dot", "qty": 2}, {"good": "diamond", "qty": 1}]
	},
	"rabbit": {
		"id": "rabbit", "name": "Rabbit", "local": "Paket Kuliner Sarangan",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 350,
		"color": Color("#8B5A9C"), "stroke": Color("#53335E"),
		"inputs": [{"good": "pebble", "qty": 1}, {"good": "capsule", "qty": 2}, {"good": "dot", "qty": 1}]
	},
	"cat": {
		"id": "cat", "name": "Cat", "local": "Ukiran Kayu Jati",
		"tier": 5, "role": "product", "op": "assemble", "slots": 2, "value": 250,
		"color": Color("#EFA42A"), "stroke": Color("#94600E"),
		"inputs": [{"good": "pebble", "qty": 1}, {"good": "wedge", "qty": 3}]
	},
}

const TRUCK_ORDER: Array[String] = ["hauler", "freighter", "express", "lowloader", "bulker"]

const TRUCKS := {
	"hauler": {
		"id": "hauler", "name": "Hauler", "subtitle": "Truk Engkel Serbaguna",
		"agility_label": "Tinggi",
		"speed_kmh": 100, "max_speed_px": 54.0, "accel": 34.0, "decel": 72.0,
		"cab_len": 8.0, "trailers": [2], "body_len": 20.0, "slot_cap": 2,
		"raw_only": false, "any_size_per_trailer": false, "express_bonus": false,
		"base_price": 60, "license_price": 0, "upkeep_min": 2,
		"color": Color("#3b82f6"), "accent": Color("#dbeafe")
	},
	"freighter": {
		"id": "freighter", "name": "Freighter", "subtitle": "Gandeng Ganda 4 Slot",
		"agility_label": "Sedang",
		"speed_kmh": 80, "max_speed_px": 44.0, "accel": 25.0, "decel": 58.0,
		"cab_len": 8.0, "trailers": [2, 2], "body_len": 32.0, "slot_cap": 4,
		"raw_only": false, "any_size_per_trailer": false, "express_bonus": false,
		"base_price": 250, "license_price": 1200, "upkeep_min": 20,
		"color": Color("#0ca678"), "accent": Color("#d3f9d8")
	},
	"express": {
		"id": "express", "name": "Express", "subtitle": "Kilat 150 km/j (Bayaran 2× Tepat Waktu)",
		"agility_label": "Ekstrem",
		"speed_kmh": 150, "max_speed_px": 80.0, "accel": 58.0, "decel": 115.0,
		"cab_len": 8.0, "trailers": [2], "body_len": 20.0, "slot_cap": 2,
		"raw_only": false, "any_size_per_trailer": false, "express_bonus": true,
		"base_price": 500, "license_price": 10000, "upkeep_min": 60,
		"color": Color("#f59f00"), "accent": Color("#fff3bf")
	},
	"lowloader": {
		"id": "lowloader", "name": "Lowloader", "subtitle": "3 Flatbed Kargo Berat (3 Ukuran Apa Saja)",
		"agility_label": "Rendah",
		"speed_kmh": 70, "max_speed_px": 39.0, "accel": 20.0, "decel": 48.0,
		"cab_len": 9.5, "trailers": [1, 1, 1], "body_len": 36.0, "slot_cap": 3,
		"raw_only": false, "any_size_per_trailer": true, "express_bonus": false,
		"base_price": 500, "license_price": 100000, "upkeep_min": 30,
		"color": Color("#d9480f"), "accent": Color("#ffe8cc")
	},
	"bulker": {
		"id": "bulker", "name": "Bulker", "subtitle": "Hopper Curah 6 Bahan Baku Hulu",
		"agility_label": "Rendah",
		"speed_kmh": 70, "max_speed_px": 39.0, "accel": 20.0, "decel": 48.0,
		"cab_len": 8.5, "trailers": [3, 3], "body_len": 33.0, "slot_cap": 6,
		"raw_only": true, "any_size_per_trailer": false, "express_bonus": false,
		"base_price": 500, "license_price": 200000, "upkeep_min": 30,
		"color": Color("#495057"), "accent": Color("#dee2e6")
	},
}

static func round_2sig(v: float) -> int:
	if v <= 0.0:
		return 0
	if v < 10.0:
		return int(round(v))
	if v < 100.0:
		return int(round(v))
	var digits: int = int(floor(log(v) / log(10.0) + 1e-9)) - 1
	var step: float = pow(10.0, float(digits))
	return int(round(v / step) * step)

## Authentic Ledger.truck_price(model, owned_of_model, total_fleet)
static func compute_truck_buy_price(model_id: String, owned_of_model: int, total_fleet: int) -> int:
	var def: Dictionary = TRUCKS.get(model_id, TRUCKS["hauler"])
	var over_60: float = float(maxi(0, total_fleet - 60))
	var mult: float = 1.0 + 0.08 * float(maxi(0, owned_of_model)) + 0.001 * over_60 * over_60
	return round_2sig(float(def["base_price"]) * mult)

## Authentic Ledger.resale_value: 50% of the marginal scaled purchase price of the last truck bought!
static func compute_truck_resale_price(model_id: String, owned_of_model: int, total_fleet: int) -> int:
	var prev_buy: int = compute_truck_buy_price(model_id, maxi(0, owned_of_model - 1), maxi(0, total_fleet - 1))
	return int(round(float(prev_buy) * 0.5))

static func compute_max_carry_units(model_id: String, good_id: String) -> int:
	if not GOODS.has(good_id):
		return 0
	var g: Dictionary = GOODS[good_id]
	var t: Dictionary = TRUCKS.get(model_id, TRUCKS["hauler"])
	if bool(t["raw_only"]) and String(g["role"]) != "raw":
		return 0
	if bool(t["any_size_per_trailer"]):
		return (t["trailers"] as Array).size()
	var g_slots: int = maxi(1, int(g["slots"]))
	var units: int = 0
	for tr_slots in t["trailers"]:
		units += int(int(tr_slots) / g_slots)
	return units

static func factory_title_for(good_id: String) -> String:
	if not GOODS.has(good_id):
		return good_id.capitalize()
	var g: Dictionary = GOODS[good_id]
	var op := String(g.get("op", "raw"))
	match op:
		"press":
			return "%s Press" % String(g["name"])
		"cut":
			return "%s Cut" % String(g["name"])
		"assemble":
			return "%s Assembly" % String(g["name"])
	return String(g["name"])

## Accessible traffic congestion band color (standard green-amber-red vs Okabe-Ito blue-amber-magenta)
static func traffic_band_color(cong: float, colorblind: bool = false, alpha: float = 0.88) -> Color:
	var t: float = clampf(cong, 0.0, 1.0)
	var c0: Color = Color("#2b8a3e") if not colorblind else Color("#1c7ed6")
	var c1: Color = Color("#f08c00") if not colorblind else Color("#f59f00")
	var c2: Color = Color("#c92a2a") if not colorblind else Color("#ae3ec9")
	var col: Color = c0.lerp(c1, t * 2.0) if t < 0.5 else c1.lerp(c2, (t - 0.5) * 2.0)
	col.a = alpha
	return col

static func status_color(level: String, colorblind: bool = false) -> Color:
	match level:
		"good":
			return Color("#1c7ed6") if colorblind else Color("#2f9e44")
		"warn":
			return Color("#f59f00") if colorblind else Color("#e67700")
		"bad":
			return Color("#ae3ec9") if colorblind else Color("#c92a2a")
	return Color("#495057")

static func validate_catalog() -> Array[String]:
	var errs: Array[String] = []
	if GOODS.size() != 44:
		errs.append("Expected 44 goods, got %d" % GOODS.size())
	for gid in GOODS.keys():
		var g: Dictionary = GOODS[gid]
		var ins: Array = g.get("inputs", [])
		if String(g["role"]) == "raw":
			if int(g["value"]) != 50:
				errs.append("Raw good %s value != 50" % gid)
		else:
			var expected_val: int = 0
			for inp in ins:
				var ig := String(inp["good"])
				if not GOODS.has(ig):
					errs.append("Recipe %s references missing input %s" % [gid, ig])
				else:
					expected_val += int(GOODS[ig]["value"]) * int(inp["qty"])
			if expected_val != int(g["value"]):
				errs.append("Good %s value %d != conserved %d" % [gid, int(g["value"]), expected_val])
	return errs

static func fmt_cash(amount: int) -> String:
	var neg: bool = amount < 0
	var a: int = absi(amount)
	var s: String = str(a)
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = s[i] + out
		count += 1
	return ("-$" if neg else "$") + out

static func parse_color(raw: String, fallback: Color = Color("#ebe4d5")) -> Color:
	var s := raw.strip_edges()
	if s == "":
		return fallback
	if s.begins_with("rgba(") and s.ends_with(")"):
		var inner := s.substr(5, s.length() - 6).split(",")
		if inner.size() == 4:
			var r: float = float(inner[0].strip_edges()) / 255.0
			var g: float = float(inner[1].strip_edges()) / 255.0
			var b: float = float(inner[2].strip_edges()) / 255.0
			var a: float = float(inner[3].strip_edges())
			var paper := Color("#f3ede0")
			return paper.lerp(Color(r, g, b, 1.0), clampf(a * 1.85, 0.08, 0.45))
	if s.begins_with("rgb(") and s.ends_with(")"):
		var inner3 := s.substr(4, s.length() - 5).split(",")
		if inner3.size() == 3:
			return Color(float(inner3[0]) / 255.0, float(inner3[1]) / 255.0, float(inner3[2]) / 255.0, 1.0)
	return Color.from_string(s, fallback)
