class_name GameCatalog
extends RefCounted

## Clean-room catalog of commodities, truck models, and pricing formulas
## reconstructed from REA static/Ghidra analysis and localized to Karesidenan Madiun.

const INFRA_PRICES := {
	"light": 1000,
	"roundabout": 10000,
	"roundabout2_upgrade": 16000,
	"lane_base": 500,
	"lane_per_px": 5,
	"pocket": 1125,
	"close_street": 3200,
}

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
const TIMETABLE_WAIT_FACTORS: Array[float] = [1.0, 0.6, 0.3, 0.05]

const GOODS := {
	"dot": {
		"id": "dot", "name": "Dot", "local": "Padi & Tebu",
		"tier": 1, "role": "raw", "op": "raw", "slots": 1, "value": 50,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"), "inputs": []
	},
	"wedge": {
		"id": "wedge", "name": "Wedge", "local": "Kayu Jati",
		"tier": 1, "role": "raw", "op": "raw", "slots": 1, "value": 50,
		"color": Color("#EFA42A"), "stroke": Color("#94600E"), "inputs": []
	},
	"block": {
		"id": "block", "name": "Block", "local": "Batu & Pasir",
		"tier": 1, "role": "raw", "op": "raw", "slots": 1, "value": 50,
		"color": Color("#2E6BB0"), "stroke": Color("#1B416E"), "inputs": []
	},
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
		"tier": 2, "role": "part", "op": "cut", "slots": 1, "value": 100,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "dot", "qty": 2}]
	},
	"chevron": {
		"id": "chevron", "name": "Chevron", "local": "Rangka Presisi",
		"tier": 2, "role": "part", "op": "cut", "slots": 1, "value": 100,
		"color": Color("#EFA42A"), "stroke": Color("#94600E"),
		"inputs": [{"good": "wedge", "qty": 2}]
	},
	"dome": {
		"id": "dome", "name": "Dome", "local": "Kubah Cor",
		"tier": 2, "role": "part", "op": "cut", "slots": 1, "value": 100,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "dot", "qty": 1}, {"good": "block", "qty": 1}]
	},
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
	"candle": {
		"id": "candle", "name": "Candle", "local": "Porselen Halus",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 150,
		"color": Color("#2E6BB0"), "stroke": Color("#1B416E"),
		"inputs": [{"good": "drop", "qty": 1}, {"good": "block", "qty": 1}]
	},
	"fish": {
		"id": "fish", "name": "Fish", "local": "Tuna Beku Tamperan",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#E0533D"), "stroke": Color("#8F2D1E"),
		"inputs": [{"good": "capsule", "qty": 1}, {"good": "chevron", "qty": 1}]
	},
	"paddle": {
		"id": "paddle", "name": "Paddle", "local": "Mesin Pertanian",
		"tier": 4, "role": "product", "op": "assemble", "slots": 2, "value": 200,
		"color": Color("#8B5A9C"), "stroke": Color("#53335E"),
		"inputs": [{"good": "bar", "qty": 1}, {"good": "pebble", "qty": 1}]
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
}

const TRUCK_ORDER: Array[String] = ["hauler", "freighter", "express", "lowloader", "bulker"]

const TRUCKS := {
	"hauler": {
		"id": "hauler", "name": "Hauler", "subtitle": "Truk Engkel Serbaguna",
		"speed_kmh": 100, "max_speed_px": 54.0, "accel": 34.0, "decel": 72.0,
		"cab_len": 8.0, "trailers": [2], "body_len": 20.0, "slot_cap": 2,
		"raw_only": false, "any_size_per_trailer": false, "express_bonus": false,
		"base_price": 60, "license_price": 0, "upkeep_min": 2,
		"color": Color("#3b82f6"), "accent": Color("#dbeafe")
	},
	"freighter": {
		"id": "freighter", "name": "Freighter", "subtitle": "Gandeng Ganda 4 Slot",
		"speed_kmh": 80, "max_speed_px": 44.0, "accel": 25.0, "decel": 58.0,
		"cab_len": 8.0, "trailers": [2, 2], "body_len": 32.0, "slot_cap": 4,
		"raw_only": false, "any_size_per_trailer": false, "express_bonus": false,
		"base_price": 250, "license_price": 1200, "upkeep_min": 20,
		"color": Color("#0ca678"), "accent": Color("#d3f9d8")
	},
	"express": {
		"id": "express", "name": "Express", "subtitle": "Kilat 150 km/j (Bayaran 2× Tepat Waktu)",
		"speed_kmh": 150, "max_speed_px": 80.0, "accel": 58.0, "decel": 115.0,
		"cab_len": 8.0, "trailers": [2], "body_len": 20.0, "slot_cap": 2,
		"raw_only": false, "any_size_per_trailer": false, "express_bonus": true,
		"base_price": 500, "license_price": 10000, "upkeep_min": 60,
		"color": Color("#f59f00"), "accent": Color("#fff3bf")
	},
	"lowloader": {
		"id": "lowloader", "name": "Lowloader", "subtitle": "3 Flatbed Kargo Berat (3 Produk Besar)",
		"speed_kmh": 70, "max_speed_px": 39.0, "accel": 20.0, "decel": 48.0,
		"cab_len": 9.5, "trailers": [1, 1, 1], "body_len": 36.0, "slot_cap": 6,
		"raw_only": false, "any_size_per_trailer": true, "express_bonus": false,
		"base_price": 500, "license_price": 100000, "upkeep_min": 30,
		"color": Color("#d9480f"), "accent": Color("#ffe8cc")
	},
	"bulker": {
		"id": "bulker", "name": "Bulker", "subtitle": "Hopper Curah 6 Bahan Baku Hulu",
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
	if v < 100.0:
		return int(round(v))
	var digits: int = int(floor(log(v) / log(10.0))) - 1
	var step: float = pow(10.0, float(digits))
	return int(round(v / step) * step)

static func compute_truck_buy_price(model_id: String, owned_of_model: int, total_fleet: int) -> int:
	var def: Dictionary = TRUCKS.get(model_id, TRUCKS["hauler"])
	var over_60: float = float(maxi(0, total_fleet - 60))
	var mult: float = 1.0 + 0.08 * float(owned_of_model) + 0.001 * over_60 * over_60
	return round_2sig(float(def["base_price"]) * mult)

static func compute_max_carry_units(model_id: String, good_id: String) -> int:
	if not GOODS.has(good_id):
		return 0
	var g: Dictionary = GOODS[good_id]
	var t: Dictionary = TRUCKS.get(model_id, TRUCKS["hauler"])
	if bool(t["raw_only"]) and String(g["role"]) != "raw":
		return 0
	if bool(t["any_size_per_trailer"]):
		return (t["trailers"] as Array).size()
	var g_slots: int = int(g["slots"])
	var units: int = 0
	for tr_slots in t["trailers"]:
		units += int(int(tr_slots) / g_slots)
	return units

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
			# Blend translucent region tint onto warm cartographic paper so region fills are opaque & vibrant
			var paper := Color("#f3ede0")
			return paper.lerp(Color(r, g, b, 1.0), clampf(a * 1.85, 0.08, 0.45))
	if s.begins_with("rgb(") and s.ends_with(")"):
		var inner3 := s.substr(4, s.length() - 5).split(",")
		if inner3.size() == 3:
			return Color(float(inner3[0]) / 255.0, float(inner3[1]) / 255.0, float(inner3[2]) / 255.0, 1.0)
	return Color.from_string(s, fallback)
