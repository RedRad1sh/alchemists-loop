extends RefCounted
class_name SpringBalance

const VERSION := 1
const SPEED := [
	{"ether": 30,  "materials": {"stone": 12}},
	{"ether": 45,  "materials": {"brick": 20}},
	{"ether": 65,  "materials": {"metal": 16}},
	{"ether": 85,  "materials": {"glass": 20, "obsidian": 8}},
	{"ether": 105, "materials": {"crystal": 14}},
	{"ether": 125, "materials": {"gold": 12}},
	{"ether": 140, "materials": {"tool": 10, "crystal": 12}},
]
const VOLUME := [
	{"ether": 30,  "materials": {"stone": 12}},
	{"ether": 45,  "materials": {"clay": 18}},
	{"ether": 60,  "materials": {"stone": 40}},
	{"ether": 80,  "materials": {"metal": 18}},
	{"ether": 100, "materials": {"glass": 22}},
	{"ether": 120, "materials": {"crystal": 16}},
	{"ether": 150, "materials": {"gold": 12, "tool": 10}},
]
const VOLUME_CAP := [100, 250, 600, 1500, 4000, 10000, 25000, 60000]
const SOURCES := [
	{"ether": 90,  "materials": {"metal": 25, "glass": 12},    "req": {"speed": 3}},
	{"ether": 130, "materials": {"crystal": 20, "gold": 12},   "req": {"speed": 5}},
	{"ether": 170, "materials": {"tool": 18, "crystal": 22},   "req": {"speed": 6}},
]
const OFFLINE := [
	{"ether": 60,  "materials": {"brick": 30},                 "req": {"volume": 3}},
	{"ether": 90,  "materials": {"metal": 20, "glass": 14},    "req": {"volume": 4}},
	{"ether": 120, "materials": {"crystal": 18, "gold": 12},   "req": {"volume": 5}},
]
const OFFLINE_WINDOW_SEC := [300.0, 3600.0, 14400.0, 43200.0]
const MIN_INTERVAL := 0.5
const SPEED_FACTOR := 0.85
const PRESTIGE_KEEP_LEVEL := 3
const MATERIAL_TIER := {
	"stone": 0, "clay": 0, "brick": 0, "metal": 1, "glass": 1,
	"obsidian": 2, "crystal": 3, "gold": 3, "tool": 4,
}
