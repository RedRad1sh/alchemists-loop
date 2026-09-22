extends Node
# Единый источник правды MVP: энергия, деления, геном (порядок генов), сейвы.
# Вся «генетика» и визуал — детерминированная функция от genome_ids (см. phenotype_engine.gd).

const SAVE_VERSION := 1
const STAGE_THRESHOLDS := [2, 4, 7, 10, 14, 19, 25]

var save_path := "user://qb_save_v1.json"

var energy := 0.0
var divisions := 0
var genome_ids: Array[String] = []
var pending_offline_gain := 0.0
var pending_offline_sec := 0

var _genes_cache: Array = []
var _drafts_since_legendary := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	load_game()

# ---------- данные генов ----------

func gene_list() -> Array:
	if _genes_cache.is_empty():
		var f := FileAccess.open("res://data/genes.json", FileAccess.READ)
		if f:
			_genes_cache = JSON.parse_string(f.get_as_text())
	return _genes_cache

func gene_by_id(id: String) -> Dictionary:
	for g in gene_list():
		if g.id == id:
			return g
	return {}

# ---------- экономика ----------

func divide_cost() -> float:
	return 40.0 * pow(1.5, float(divisions))

func passive_energy_per_sec() -> float:
	var total := 0.3   # крошечный базовый метаболизм
	for id in genome_ids:
		var g := gene_by_id(id)
		if not g.is_empty():
			total += float(g.get("passive", 0.0))
	return total

func can_divide() -> bool:
	return energy >= divide_cost()

func add_energy(v: float) -> void:
	if v <= 0.0:
		return
	energy += v
	EventBus.energy_changed.emit(energy)

func do_divide() -> bool:
	if not can_divide():
		return false
	var old_stage := stage_index()
	energy -= divide_cost()
	divisions += 1
	save_game()
	EventBus.energy_changed.emit(energy)
	var new_stage := stage_index()
	if new_stage != old_stage:
		EventBus.stage_changed.emit(old_stage, new_stage)
	return true

# ---------- геном ----------

func stage_index() -> int:
	var st := 0
	for t in STAGE_THRESHOLDS:
		if divisions >= t:
			st += 1
	return st

func add_gene(id: String) -> void:
	var old_stage := stage_index()
	genome_ids.append(id)
	var g := gene_by_id(id)
	if not g.is_empty() and int(g.get("rarity", 0)) >= 3:
		_drafts_since_legendary = 0
	save_game()
	EventBus.genome_changed.emit(genome_ids.duplicate())
	var new_stage := stage_index()
	if new_stage != old_stage:
		EventBus.stage_changed.emit(old_stage, new_stage)

func move_gene(idx: int, dir: int) -> bool:
	var j := idx + dir
	if idx < 0 or j < 0 or idx >= genome_ids.size() or j >= genome_ids.size():
		return false
	var t: String = genome_ids[idx]
	genome_ids[idx] = genome_ids[j]
	genome_ids[j] = t
	save_game()
	EventBus.genome_changed.emit(genome_ids.duplicate())
	return true

func shuffle_genome() -> void:
	# В Godot 4 у RandomNumberGenerator НЕТ метода shuffle() — свой Fisher-Yates на _rng.
	var n := genome_ids.size()
	for i in range(n - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp: String = genome_ids[i]
		genome_ids[i] = genome_ids[j]
		genome_ids[j] = tmp
	save_game()
	EventBus.genome_changed.emit(genome_ids.duplicate())

# ---------- черновик мутаций (драбл 1 из 3) ----------

func unlocked_genes() -> Array:
	# Пул генов, доступных для драбла при текущем геноме (проверка requires).
	var out: Array = []
	for g in gene_list():
		var req: String = g.get("requires", "")
		if req == "" or genome_ids.has(req):
			out.append(g)
	return out

func make_candidates(count: int = 3) -> Array:
	_drafts_since_legendary += 1
	var pool: Array = unlocked_genes()
	# если новых генов мало — в пул добавляются уже купленные («повторная экспрессия»),
	# чтобы прогресс и стадии 6–7 были достижимы (дубликаты гена усиливают фенотип)
	if pool.size() < count:
		for g in gene_list():
			if pool.size() >= count:
				break
			if genome_ids.has(g.id) and not pool.has(g):
				pool.append(g)
	if pool.is_empty():
		return []
	var chosen: Array = []
	var weights: Array = []
	while chosen.size() < count and not pool.is_empty():
		weights.clear()
		var total_w := 0.0
		for g in pool:
			var w := 0.0
			match int(g.get("rarity", 0)):
				0: w = 50.0
				1: w = 27.0
				2: w = 15.0
				3: w = 6.0
			if int(g.get("rarity", 0)) >= 3:
				w += float(maxi(_drafts_since_legendary - 7, 0)) * 6.0   # жалость-гарант
			weights.append(w)
			total_w += w
		var roll := _rng.randf_range(0.0, total_w)
		var acc := 0.0
		var pick := -1
		for i in pool.size():
			acc += weights[i]
			if roll <= acc:
				pick = i
				break
		if pick < 0:
			pick = pool.size() - 1
		chosen.append(pool[pick])
		pool.remove_at(pick)
	return chosen

# ---------- код ДНК (детерминированный, для шаринга) ----------

func dna_code() -> String:
	const ALPH := "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ"
	var chars: Array = []
	for id in genome_ids:
		var idx := 0
		var i := 0
		for g in gene_list():
			if g.id == id:
				idx = i
				break
			i += 1
		chars.append(ALPH[idx])
	var body := "".join(chars)
	return "QB-" + body + "-" + str(divisions)

# ---------- сохранение ----------

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION,
		"energy": energy,
		"divisions": divisions,
		"genome": genome_ids.duplicate(),
		"last_seen": int(Time.get_unix_time_from_system())
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if not f:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data == null or typeof(data) != TYPE_DICTIONARY:
		# битый сейв — не роняем игру
		DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path),
			ProjectSettings.globalize_path(save_path) + ".corrupt")
		return
	var d: Dictionary = data
	energy = float(d.get("energy", 0.0))
	divisions = int(d.get("divisions", 0))
	var g: Array = d.get("genome", [])
	genome_ids.clear()
	for id in g:
		if typeof(id) == TYPE_STRING:
			genome_ids.append(id)
	# оффлайн-споры: пассивный доход за время отсутствия (кап 8 ч, коэфф. 0.7)
	var last: int = int(d.get("last_seen", 0))
	var now := int(Time.get_unix_time_from_system())
	var secs := now - last
	if secs > 120 and last > 0:
		var capped := minf(float(secs), 8.0 * 3600.0)
		var gain := passive_energy_per_sec() * capped * 0.7
		if gain > 0.0:
			energy += gain
			pending_offline_gain = gain
			pending_offline_sec = secs
