class_name SigilRng
extends RefCounted

## Детерминированный ГПСЧ для генерации карточек.
##
## Реализация — xorshift128 с 32-битными словами. Все операции помещаются в
## int64 без переполнения, поэтому результат идентичен в Godot, JS, Python и
## любом другом языке с 64-битным int. Это осознанный выбор вместо
## RandomNumberGenerator: его вывод может измениться между версиями движка,
## а нам нужна стабильность карточек у игроков спустя годы.
##
## Ключевая идея — [method fork]: каждый слой карточки получает СВОЙ поток из
## одного seed. Добавление нового слоя не сдвигает генерацию существующих,
## иначе все выпущенные карточки «поехали» бы после любого патча.

const MASK := 0xFFFFFFFF
const FNV_OFFSET := 2166136261
const FNV_PRIME := 16777619

var _x: int = 0x9E3779B9
var _y: int = 0x243F6A88
var _z: int = 0xB7E15162
var _w: int = 0xDEADBEEF
var _seed: int = 0
var _counter: int = 0


func _init(seed_value: int = 0) -> void:
	reseed(seed_value)


static func mix32(v: int) -> int:
	## Финализатор avalanche32 (lowbias32) — размазывает один вход в 32 бита.
	v &= MASK
	v ^= v >> 16
	v = (v * 0x7FEB352D) & MASK
	v ^= v >> 15
	v = (v * 0x846CA68B) & MASK
	v ^= v >> 16
	return v & MASK


static func fnv1a(text: String) -> int:
	var h := FNV_OFFSET
	for b in text.to_utf8_buffer():
		h = ((h ^ (b & 0xFF)) * FNV_PRIME) & MASK
	return h


static func combine(a: int, b: int) -> int:
	## Смешивает два 64-битных seed в один.
	return (mix32(a & MASK) ^ mix32((a >> 32) & MASK ^ 0x9E3779B9) ^ b) & MASK


static func seed_from_string(text: String) -> int:
	return (mix32(fnv1a(text)) << 16) ^ mix32(fnv1a(text + "#salt"))


static func seed_from_bytes(bytes: PackedByteArray) -> int:
	## Берёт 8 байт хеша (например SHA-256) и сворачивает в положительный int.
	var v := 0
	for i in range(mini(8, bytes.size())):
		v |= (bytes[i] & 0xFF) << (8 * i)
	v &= 0x7FFFFFFFFFFFFFFF
	return combine(v, mix32(bytes.size() * 2654435761))


func reseed(seed_value: int) -> void:
	_seed = seed_value & 0x7FFFFFFFFFFFFFFF
	_x = combine(_seed, 0x9E3779B9)
	_y = combine(_seed, 0x85EBCA6B)
	_z = combine(_seed, 0xC2B2AE35)
	_w = mix32(_seed ^ 0x27D4EB2F)
	for i in range(24):
		self.next_u32()
	_counter = 0


func get_seed() -> int:
	return _seed


func next_u32() -> int:
	var t := _x
	t = (t ^ ((t << 11) & MASK)) & MASK
	t = (t ^ (t >> 8)) & MASK
	_x = _y
	_y = _z
	_z = _w
	_w = (t ^ _w ^ (_w >> 19)) & MASK
	_counter += 1
	return _w


func next_u64() -> int:
	return (self.next_u32() << 32) | self.next_u32()


func randf() -> float:
	## [0, 1)
	return float(self.next_u32()) / 4294967296.0


func randf_range(a: float, b: float) -> float:
	return a + (b - a) * self.randf()


func randi_range(a: int, b: int) -> int:
	## Инклюзивно с обеих сторон. b < a даёт b.
	if b <= a:
		return a
	return a + int(self.randf() * float(b - a + 1))


func chance(p: float) -> bool:
	return self.randf() < p


func sign() -> float:
	return 1.0 if self.randf() < 0.5 else -1.0


func rand_sign() -> int:
	return 1 if self.randf() < 0.5 else -1


func pick(arr: Array):
	if arr.is_empty():
		return null
	return arr[self.randi_range(0, arr.size() - 1)]


func weighted_pick(weights: PackedFloat32Array) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return -1
	var r := self.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += maxf(weights[i], 0.0)
		if r <= acc:
			return i
	return weights.size() - 1


func shuffled(arr: Array) -> Array:
	var out := arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := self.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


func unit_vector() -> Vector2:
	var a := self.randf() * TAU
	return Vector2(cos(a), sin(a))


func gauss(mean: float = 0.0, sigma: float = 1.0) -> float:
	## Клэмп на [-4σ, 4σ]: карточка не должна уезжать за пределы композиции.
	var u1 := maxf(self.randf(), 1e-7)
	var u2 := self.randf()
	var z := sqrt(-2.0 * log(u1)) * cos(TAU * u2)
	return mean + sigma * clampf(z, -4.0, 4.0)


func fork(label: String) -> SigilRng:
	## Отдельный поток из того же seed. Порядок потребления в других слоях
	## на него не влияет.
	return new(combine(_seed, fnv1a(label)))


func fork2(label_a: String, label_b: String) -> SigilRng:
	return new(combine(combine(_seed, fnv1a(label_a)), fnv1a(label_b)))


func state_hash() -> String:
	return "%08x%08x%08x%08x" % [_x, _y, _z, _w]

