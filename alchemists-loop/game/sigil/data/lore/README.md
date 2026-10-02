# Lore-данные «Аркана Сигилов» (подпроект C)

Закоммиченные артефакты детерминированного lore-генератора описаний карт.
Данные читаются движком `game/sigil/lore.gd` по требованию через
`SigilAssets.json_file("data/lore/<файл>.json")` — без прелоадов.

Генерация/сверка — `tools/gen_sigil_lore.py` (паттерн `gen_sigil_catalog.py`):

    python tools/gen_sigil_lore.py elements --check    # падежная таблица
    python tools/gen_sigil_lore.py fragments --check   # семь слотов фрагментов
    python tools/gen_sigil_lore.py elements            # записать таблицу
    python tools/gen_sigil_lore.py fragments           # записать слоты

## Файлы

- `elements.json` — падежная таблица: `{"version": 1, "elements": {<id>: {name, gen, dat, acc, ins, prep, adj}}}`.
  Ключи — ровно все 100 `card_id` каталога (`discovery-server/server/data/sigil_catalog.json`)
  + алхимические `mercury`, `sulfur`, `salt`, `lead` (104 записи).
- `actions.json`, `conditions.json`, `results.json`, `symbols.json`,
  `warnings.json`, `titles.json`, `effects.json` — 7 слотов фрагментов,
  в каждом `{"version": 1, "fragments": [{id, slot, text, tags, weight}]}`,
  ≥100 фрагментов на слот.

## Формат фрагмента

    {
      "id": "action_001",
      "slot": "action",
      "text": "Помести {source:acc} в тигель",
      "tags": {
        "process": ["calcinatio", "putrefactio"],
        "stage": ["nigredo"],
        "elements": ["lead", "sulfur"],
        "vessel": ["тигель"],
        "safety": "volatile"
      },
      "weight": 10
    }

Плейсхолдеры двух форм:
- ролевые `{source:<case>}` / `{target:<case>}` — источник = первый ингредиент
  рецепта, цель = сама карта (спека §5);
- именованные `{<element_id>:<case>}` — элемент из `elements.json`.

`case` ∈ {gen, dat, acc, ins, prep}. Подстановка — через падежную таблицу.

## Ruling C1 — стадии и процессы

Совместимость (спека §6 + генератор каталога):
- nigredo ↔ calcinatio / putrefactio / distillatio;
- albedo ↔ sublimatio / distillatio / coniunctio;
- rubedo ↔ coniunctio / calcinatio;
- citrinitas — средняя стадия, берём PROCESS_BY_STAGE генератора каталога:
  sublimatio / coniunctio / distillatio.

## Ruling C2 — сосуды, время, прочие слова

Сосуды и время — уже склонёнными фразами ВНУТРИ самих фрагментов
(«в тигель», «в реторте», «под луной»), а НЕ плейсхолдерами. Плейсхолдеры —
только элементы из `elements.json` в падежах; именительный доступен
литеральным словом во фрагменте или падежом `acc`.

Совместимость текста:
- если фрагмент упоминает mercury — warning обязан выбираться из фрагментов
  с `safety` ∈ {volatile, poison} (летучесть/яд);
- «тигель» и «алембик» не встречаются в одном описании;
- в текстах нет символьной пыли `✦`/`⚡` (шрифт Manrope без этих глифов).