# Alchemist's Loop

Алхимический idle-луп на Godot (Android) с сетевым discovery-сервером на FastAPI.

![CI](https://github.com/RedRad1sh/alchemists-loop/actions/workflows/ci.yml/badge.svg)
[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyFormNoncommercial1.0.0-blue)](LICENSE.md)
![Godot 4.7.2](https://img.shields.io/badge/Godot-4.7.2-478CBF?logo=godotengine&logoColor=white)
![Python 3.11](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![FastAPI 0.104](https://img.shields.io/badge/FastAPI-0.104-009485?logo=fastapi&logoColor=white)
![Android](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=black)
![Top language](https://img.shields.io/github/languages/top/RedRad1sh/alchemists-loop)
![Last commit](https://img.shields.io/github/last-commit/RedRad1sh/alchemists-loop)
![Repo size](https://img.shields.io/github/repo-size/RedRad1sh/alchemists-loop)

[![CodeRabbit Pull Request Reviews](https://img.shields.io/coderabbit/prs/github/RedRad1sh/alchemists-loop?utm_source=oss&utm_medium=github&utm_campaign=RedRad1sh%2Falchemists-loop&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews)](https://coderabbit.ai/RedRad1sh/alchemists-loop)

## UI/UX: итерация-2 (блоки 1–5) — ОТКАЧЕНА 2026-10-04

> Приёмка шла по мок-кадрам `tools/ui-preview/`, не связанным с кодом игры:
> в реальном коде накопились parse-ошибка (`home.gd`, тип `GridContainer` в
> `VBoxContainer`), молчаливые no-op чипы (styleBox на `Label`) и глобальные
> побочные эффекты (safe-area, `UiStateTick`). Игровые файлы откачены к чистой
> точке `f0b31fc` (сет иконок + меню вкладок), поверх оставлены только иконки
> шапки и фикс пузырька Светика. Детали, новые правила приёмки (реальные кадры
> через `tools/shots.py` + selftest в CI) и бэклог: `docs/ui-ux/2026-10-04-ui-revert-notes.md`.

<details>
<summary>Как было (история мок-согласований, код откачен)</summary>

Процесс: мок-кадр блока коммитится в `docs/ui-ux/screenshots/` → согласование →
изолированный коммит в коде игры → синхронизация превью (`tools/ui-preview/`).

| Блок | Что изменилось (в коде больше НЕТ) | Коммит |
|---|---|---|
| 1 · Шапка | иконки сета вместо глифов ✦▲♪Ж, тач 44×44, бейдж-пилюля счётчика, пузырь Светика ниже компаньона | `4010036` (иконки шапки и пузырь ОСТАВЛЕНЫ) |
| 2 · BrewBar | пилюли счётчиков внутри орбов, порядок ряда Все/орбы/↻/✕/ВАРИТЬ справа, «Стоп» видна всегда (disabled) | `71ab518` |
| 3 · Попапы | одна кнопка по центру, без крестика (закрытие тапом по фону/карточке), рецептная строка A+B→C, чипы редкости/награды, поля 24 px | `48603da` |
| 4 · Дом | категории обстановки карточками 2×N без ценников (ценники в магазине вариантов), чип «куплено: N» | `31db2d6` (содержал parse-ошибку) |
| 5 · Мир/Рейтинг | списки карточками, медаль топ-3, чип очков, своя строка закрепом, «Обновить» иконкой 44, цель дня карточкой | `e23ef6a` |

Эксперимент (ячейки 4×N) и меню вкладок/сет иконок итерации-1 — без изменений.
Мок-борды согласований: `docs/ui-ux/screenshots/block*_variants.png`.
</details>

