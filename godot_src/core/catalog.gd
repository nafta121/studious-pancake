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

const TRUCK_ORDER: Array[String] = ["hauler", "freighter", "lowloader", "express", "bulker"]

## Authentic Incremental Traffic v1.4.1 `Goods` & `TruckModel` physical proportions:
## Original 20px-wide TruckView coordinates scaled by `TRUCK_VIEW_SCALE` onto 4.6px-lane Madiun cartography.
const TRUCK_ORIG_WIDTH := 20.0
const TRUCK_ORIG_CAB_LEN := 22.0
const TRUCK_ORIG_SLOT_LEN := 18.0
const TRUCK_ORIG_COUPLING := 3.0
const TRUCK_VIEW_SCALE := 0.24
const EXPRESS_BONUS_FACTOR := 2.0
const EXPRESS_DEADLINE_MULT := 1.3
const EXPRESS_DEADLINE_PAD_SEC := 3.0

const TRUCKS := {
	"hauler": {
		"id": "hauler", "name": "Hauler", "role": "Cheap starter",
		"subtitle": "Cheap starter · Truk Engkel Serbaguna",
		"agility_label": "Agility: high",
		"speed_kmh": 100, "max_speed_px": 50.0, "accel": 28.0, "decel": 68.0,
		"orig_cab_len": 22.0, "orig_bed_len": 0.0, "beds": false,
		"cab_len": 5.28, "trailers": [2], "body_len": 14.64, "slot_cap": 2,
		"raw_only": false, "any_size_per_trailer": false, "express_bonus": false,
		"base_price": 60, "license_price": 0, "upkeep_min": 2,
		"color": Color("#3b82f6"), "accent": Color("#dbeafe")
	},
	"freighter": {
		"id": "freighter", "name": "Freighter", "role": "Double trailer",
		"subtitle": "Double trailer · Gandeng Ganda 4 Slot",
		"agility_label": "Agility: medium",
		"speed_kmh": 80, "max_speed_px": 40.0, "accel": 22.4, "decel": 54.5,
		"orig_cab_len": 22.0, "orig_bed_len": 0.0, "beds": false,
		"cab_len": 5.28, "trailers": [2, 2], "body_len": 24.0, "slot_cap": 4,
		"raw_only": false, "any_size_per_trailer": false, "express_bonus": false,
		"base_price": 250, "license_price": 1200, "upkeep_min": 20,
		"color": Color("#0ca678"), "accent": Color("#d3f9d8")
	},
	"lowloader": {
		"id": "lowloader", "name": "Lowloader", "role": "Three of anything, large goods too",
		"subtitle": "Three of anything, large goods too · 3 Flatbed Berat",
		"agility_label": "Agility: low",
		"speed_kmh": 70, "max_speed_px": 35.0, "accel": 16.8, "decel": 41.2,
		"orig_cab_len": 28.0, "orig_bed_len": 22.0, "beds": true,
		"cab_len": 6.72, "trailers": [1, 1, 1], "body_len": 24.72, "slot_cap": 3,
		"raw_only": false, "any_size_per_trailer": true, "express_bonus": false,
		"base_price": 500, "license_price": 100000, "upkeep_min": 30,
		"color": Color("#d9480f"), "accent": Color("#ffe8cc")
	},
	"express": {
		"id": "express", "name": "Express", "role": "Paid double when on time",
		"subtitle": "Paid double when on time · Kilat 150 km/j (2× Bonus)",
		"agility_label": "Agility: extreme",
		"speed_kmh": 150, "max_speed_px": 75.0, "accel": 56.0, "decel": 133.0,
		"orig_cab_len": 22.0, "orig_bed_len": 0.0, "beds": false,
		"cab_len": 5.28, "trailers": [2], "body_len": 14.64, "slot_cap": 2,
		"raw_only": false, "any_size_per_trailer": false, "express_bonus": true,
		"base_price": 500, "license_price": 10000, "upkeep_min": 60,
		"color": Color("#f59f00"), "accent": Color("#fff3bf")
	},
	"bulker": {
		"id": "bulker", "name": "Bulker", "role": "Six raw shapes, nothing else",
		"subtitle": "Six raw shapes, nothing else · Hopper Curah 6 Bahan Hulu",
		"agility_label": "Agility: low",
		"speed_kmh": 70, "max_speed_px": 35.0, "accel": 16.8, "decel": 41.2,
		"orig_cab_len": 22.0, "orig_bed_len": 36.0, "beds": true,
		"cab_len": 5.28, "trailers": [3, 3], "body_len": 24.0, "slot_cap": 6,
		"raw_only": true, "any_size_per_trailer": false, "express_bonus": false,
		"base_price": 500, "license_price": 200000, "upkeep_min": 30,
		"color": Color("#495057"), "accent": Color("#dee2e6")
	},
}

static var _truck_units_cache: Dictionary = {}

static func is_raw_good(good_id: String) -> bool:
	return GOODS.has(good_id) and String(GOODS[good_id]["role"]) == "raw"

## Authentic `TruckModel.units(model)` in original 20px-wide TruckView coordinates!
static func get_truck_units(model_id: String) -> Array[Dictionary]:
	if _truck_units_cache.has(model_id):
		return _truck_units_cache[model_id]
	var m: Dictionary = TRUCKS.get(model_id, TRUCKS["hauler"])
	var at: float = float(m.get("orig_cab_len", TRUCK_ORIG_CAB_LEN))
	var out: Array[Dictionary] = [{"front": 0.0, "rear": at, "first_slot": 0, "slots": 0, "cab": true, "bed": false}]
	var slot: int = 0
	var beds: bool = bool(m.get("beds", false))
	var bed_len: float = float(m.get("orig_bed_len", 22.0))
	for n_raw in m["trailers"]:
		var n: int = int(n_raw)
		var front: float = at + TRUCK_ORIG_COUPLING
		at = front + (bed_len if beds else float(n) * TRUCK_ORIG_SLOT_LEN)
		out.append({"front": front, "rear": at, "first_slot": slot, "slots": n, "cab": false, "bed": beds})
		slot += n
	_truck_units_cache[model_id] = out
	return out

static func get_truck_world_length(model_id: String) -> float:
	var u: Array[Dictionary] = get_truck_units(model_id)
	return float(u[u.size() - 1]["rear"]) * TRUCK_VIEW_SCALE

static func describe_truck_capacity(model_id: String) -> String:
	var m: Dictionary = TRUCKS.get(model_id, TRUCKS["hauler"])
	var s: int = int(m["slot_cap"])
	if bool(m["raw_only"]):
		return "%d raw shapes" % s
	if bool(m["beds"]):
		return "%d of any size" % s
	return "%d small or %d large" % [s, s / 2]

## Authentic `TruckModel.drive_time` (`_6gyOzneQRV9n`): exact trapezoid/triangle kinematic travel time!
static func compute_truck_drive_time(model_id: String, length_px: float, v0: float = 0.0, v1: float = 0.0, speed_mult: float = 1.0) -> float:
	if length_px <= 0.0:
		return 0.0
	var m: Dictionary = TRUCKS.get(model_id, TRUCKS["hauler"])
	var a: float = maxf(1.0, float(m["accel"]))
	var d: float = maxf(1.0, float(m["decel"]))
	var top: float = maxf(8.0, float(m["max_speed_px"]) * speed_mult)
	var peak: float = minf(top, sqrt((2.0 * a * d * length_px + d * v0 * v0 + a * v1 * v1) / (a + d)))
	var v_in: float = minf(v0, peak)
	var v_out: float = minf(v1, peak)
	var d_acc: float = (peak * peak - v_in * v_in) / (2.0 * a)
	var d_dec: float = (peak * peak - v_out * v_out) / (2.0 * d)
	var cruise: float = maxf(0.0, length_px - d_acc - d_dec)
	return (peak - v_in) / a + (peak - v_out) / d + cruise / maxf(0.1, peak)

## Authentic `Ledger.round_price`: rounds prices >= 10 to 2 significant digits!
static func round_2sig(v: float) -> int:
	if v <= 0.0:
		return 0
	if v < 10.0:
		return int(round(v))
	var digits: int = int(floor(log(v) / log(10.0) + 1e-9)) - 1
	var step: float = pow(10.0, float(digits))
	return int(round(v / step) * step)

## Authentic `Ledger.truck_price(model, owned_of_model, total_fleet)`
static func compute_truck_buy_price(model_id: String, owned_of_model: int, total_fleet: int) -> int:
	var def: Dictionary = TRUCKS.get(model_id, TRUCKS["hauler"])
	var over_60: float = float(maxi(0, total_fleet - 60))
	var mult: float = 1.0 + 0.08 * float(maxi(0, owned_of_model)) + 0.001 * over_60 * over_60
	return round_2sig(float(def["base_price"]) * mult)

## Authentic `Ledger.resale_value`: 50% of the marginal scaled purchase price of the last truck bought!
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
	if bool(t["beds"]):
		return int(t["slot_cap"])
	var g_slots: int = maxi(1, int(g["slots"]))
	return int(t["slot_cap"]) / g_slots

## Authentic `RouteColors.pick(rng, taken, base)`: OKHSL/OKLab perceptual harmonizer within ±44° of good color!
static func pick_route_color(rng: RandomNumberGenerator, taken_colors: Array, good_id: String = "") -> Color:
	var base: Color = Color("8B5A9C")
	if good_id != "" and GOODS.has(good_id):
		base = ShapeGlyphs.color_of(good_id)
	var best := base
	var best_dist: float = -1.0
	for _i in range(24):
		var h: float = fposmod(base.ok_hsl_h + rng.randf_range(-44.0, 44.0) / 360.0, 1.0)
		var peak_l: float = _okhsl_peak_lightness(h)
		var l: float = clampf(peak_l + rng.randf_range(-0.08, 0.03), 0.62, 0.86)
		var s: float = rng.randf_range(0.85, 1.0)
		var c: Color = Color.from_ok_hsl(h, s, l)
		while _srgb_luminance(c) < 0.16 and l < 0.86:
			l += 0.02
			c = Color.from_ok_hsl(h, s, l)
		var min_d: float = 10.0
		for t_col in taken_colors:
			min_d = minf(min_d, _oklab_route_distance(c, t_col))
		if min_d > best_dist:
			best_dist = min_d
			best = c
	return best

static func _okhsl_peak_lightness(h: float) -> float:
	var best_l: float = 0.5
	var best_c: float = -1.0
	for i in range(31):
		var l: float = 0.35 + float(i) * 0.02
		var lab: Vector3 = _to_oklab(Color.from_ok_hsl(h, 1.0, l))
		var chr: float = Vector2(lab.y, lab.z).length()
		if chr > best_c:
			best_c = chr
			best_l = l
	return best_l

static func _oklab_route_distance(a: Color, b: Color) -> float:
	var d: Vector3 = _to_oklab(a) - _to_oklab(b)
	return Vector3(d.x * 0.5, d.y, d.z).length() / 0.08

static func _to_oklab(c: Color) -> Vector3:
	var lin: Color = c.srgb_to_linear()
	var l: float = pow(maxf(0.0, 0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b), 1.0 / 3.0)
	var m: float = pow(maxf(0.0, 0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b), 1.0 / 3.0)
	var s: float = pow(maxf(0.0, 0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b), 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	)

static func _srgb_luminance(c: Color) -> float:
	var lin: Color = c.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b

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
