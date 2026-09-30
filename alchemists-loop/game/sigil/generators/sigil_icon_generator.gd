class_name SigilIconGenerator
extends RefCounted

## Базовый класс генератора центрального объекта карточки.
##
## Контракт минимальный и осознанный:
##   * детерминирован — весь случай берётся из переданного [SigilRng];
##   * рисует ТОЛЬКО внутри rect;
##   * не знает ни о карточке, ни о круге, ни об окне.
## Новый тип объекта = новый файл + одна строка в реестре. Ядро не меняется.

## Тип, который вернёт этот генератор (для UI и логов).
func type_name() -> StringName:
	return &"object"

## Короткое описание для панели стенда.
func description() -> String:
	return ""

## Основная точка входа.
func draw_icon(ci: CanvasItem, rect: Rect2, rng: SigilRng, ctx: Dictionary) -> void:
	pass


# ------------------------------------------------------------------ утилиты

func grid_for(rect: Rect2, ctx: Dictionary, fallback: int = 32) -> int:
	var g := int(ctx.get("pixel_grid", 0))
	if g <= 0:
		var fit := int(floorf(minf(rect.size.x, rect.size.y) / 2.0))
		g = clampi(fit, 12, fallback)
	return clampi(g, 8, 96)


func new_canvas(rect: Rect2, ctx: Dictionary, fallback: int = 32) -> SigilPixelCanvas:
	return SigilPixelCanvas.new(grid_for(rect, ctx, fallback))


## Симметричная оттенённая пара «тёплый/холодный» из seed и базового тона.
func duo(rng: SigilRng, base: Color, spread: float = 0.10) -> Color:
	var h := base.h
	return Color.from_hsv(fposmod(h + rng.randf_range(-spread, spread), 1.0),
		clampf(base.s * rng.randf_range(0.88, 1.12), 0.0, 1.0),
		clampf(base.v * rng.randf_range(0.88, 1.12), 0.0, 1.0))


func palette(ctx: Dictionary, key: String, fallback: Color) -> Color:
	var p: Dictionary = ctx.get("icon_palette", {})
	return p.get(key, fallback) if p.has(key) else fallback
