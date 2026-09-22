class_name PhenotypeEngine
# Чистый детерминированный движок: упорядоченный список генов -> фенотип.
# Правила:
#  1) гены применяются ПОСЛЕДОВАТЕЛЬНО (порядок влияет на промежуточные значения);
#  2) соседние пары генов дают «эпистаз»-бонусы;
#  3) результат зависит только от genome_ids -> одинаковый геном = одинаковое существо.
# Без UI и без состояния: покрывается golden-тестами (см. selftest в main.gd).

const STAGE_THRESHOLDS := [2, 4, 7, 10, 14, 19, 25]

static func default_pheno() -> Dictionary:
	return {
		"size": 1.0,          # множитель размера (0.55..3.2)
		"segments": 1,        # число сегментов тела (1..26)
		"color1": Color8(86, 226, 178),   # голова/верх
		"color2": Color8(26, 108, 96),    # хвост/низ
		"pattern": 0,         # 0..3 узор пятен
		"eyes": 0,            # 0..6
		"tail": 0,            # 0..2 жгутика-хвоста
		"spikes": 0,          # 0..18 шипов
		"glow": 0.0,          # 0..2.5 свечение
		"pulse": 1.0,         # скорость пульса
		"seed": 0,            # сид узора (из генома)
		"stage": 0,           # индекс стадии (0..7)
		"gene_count": 0
	}

static func compute(genome_ids: Array, seed: int = 0) -> Dictionary:
	var p := default_pheno()
	for id in genome_ids:
		_apply(p, String(id))
	_epistasis(p, genome_ids)
	if seed != 0:
		p["seed"] = seed
	else:
		p["seed"] = _hash_ids(genome_ids)
	p["stage"] = stage_of(genome_ids.size())
	p["gene_count"] = genome_ids.size()
	return p

static func stage_of(gene_count: int) -> int:
	var st := 0
	for t in STAGE_THRESHOLDS:
		if gene_count >= t:
			st += 1
	return st

# ---------- применение гена (вызывается в порядке генома) ----------

static func _apply(p: Dictionary, id: String) -> void:
	match id:
		"fast_mitosis":
			p["pulse"] = minf(p["pulse"] + 0.2, 2.6)
		"chlorophyll":
			p["color1"] = p["color1"].lerp(Color8(70, 220, 110), 0.5)
			p["color2"] = p["color2"].lerp(Color8(30, 120, 60), 0.4)
		"chemosynthesis":
			p["color1"] = p["color1"].lerp(Color8(126, 87, 220), 0.55)
			p["color2"] = p["color2"].lerp(Color8(60, 30, 110), 0.5)
			p["glow"] = minf(p["glow"] + 0.15, 2.5)
		"gigantism":
			p["size"] = minf(p["size"] * 1.55, 3.2)
		"segmentation":
			p["segments"] = mini(p["segments"] + 2, 26)
		"pigmentation":
			p["pattern"] = mini(p["pattern"] + 1, 3)
			p["color1"] = _hue_shift(p["color1"], 0.14)
			p["color2"] = _hue_shift(p["color2"], 0.10)
		"eyes":
			p["eyes"] = mini(p["eyes"] + 2, 6)
		"flagella":
			p["tail"] = mini(p["tail"] + 1, 2)
		"chitin_armor":
			p["spikes"] = mini(p["spikes"] + 6, 14)
			p["color2"] = p["color2"].lerp(Color8(120, 88, 40), 0.55)
			p["color1"] = p["color1"].lerp(Color8(150, 130, 90), 0.25)
		"bioluminescence":
			p["glow"] = minf(p["glow"] + 0.6, 1.7)
		"quantum_aura":
			p["glow"] = maxf(p["glow"], 2.1)
			p["color2"] = p["color2"].lerp(Color8(220, 130, 255), 0.7)
			p["color1"] = p["color1"].lerp(Color8(190, 140, 255), 0.4)

static func _hue_shift(c: Color, dr: float) -> Color:
	var h := fmod(c.h + dr, 1.0)
	return Color.from_hsv(h, clampf(c.s, 0.0, 1.0), clampf(c.v, 0.0, 1.0))

# ---------- эпистаз: бонусы соседних пар ----------

static func _epistasis(p: Dictionary, ids: Array) -> void:
	for i in ids.size() - 1:
		var pair := String(ids[i]) + "|" + String(ids[i + 1])
		match pair:
			"gigantism|chitin_armor":
				p["spikes"] = mini(p["spikes"] + 4, 18)
				p["size"] = minf(p["size"] * 1.12, 3.4)
			"bioluminescence|quantum_aura":
				p["glow"] = minf(p["glow"] * 1.3, 2.8)
			"pigmentation|bioluminescence":
				p["color1"] = _hue_shift(p["color1"], 0.08)

static func _hash_ids(ids: Array) -> int:
	var h := 2166136261
	for id in ids:
		h = (h * 16777619) ^ String(id).hash()
	return h & 0x7FFFFFFF
