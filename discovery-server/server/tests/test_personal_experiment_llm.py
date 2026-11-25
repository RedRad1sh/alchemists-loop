"""Семантический контракт LLM-пути персонального Experiment."""

import os

import pytest

import gen_llm


class _FakeResp:
    def __init__(self, content):
        self.status_code = 200
        self.text = ""
        self._content = content

    def json(self):
        import json
        return {"choices": [{"message": {"content": self._content}}]}


def _ok_resp(content):
    return _FakeResp(content)


def test_semantic_check_accepts_meaningful_morphology_but_rejects_raw_join():
    from gen_llm import semantic_check

    ok, _ = semantic_check("Безумие", "Без", "Ум")
    assert ok
    ok, reason = semantic_check("БезУм", "Без", "Ум")
    assert not ok and "склейк" in reason


def test_semantic_check_rejects_single_input_and_category_only_result():
    from gen_llm import semantic_check

    assert not semantic_check("Камень", "Камень", "Камень")[0]
    assert not semantic_check("Красное", "Яблоко", "Кровь")[0]


def test_target_result_requires_known_outcome_and_relation():
    from gen_llm import validate_target_result

    valid = validate_target_result({
        "outcome": "target",
        "name": "Рассвет",
        "relation": "metaphor",
        "description": "Оба входа ведут к образу рассвета.",
    })
    assert valid["outcome"] == "target"
    assert valid["relation"] == "metaphor"
    assert validate_target_result({
        "outcome": "random",
        "name": "Мусор",
        "relation": "metaphor",
    }) is None
    assert validate_target_result({
        "outcome": "intermediate",
        "name": "ПыльСтекло",
        "relation": "compound",
    }) is None


def test_mock_personal_target_generation_and_evaluation_are_structured():
    from gen_llm import LLMGenerator

    generator = LLMGenerator(provider="mock")
    target = generator.generate_personal_target("device-a|2026-W48|1")
    assert target["name"] == "Рассвет"
    assert target["hint"]

    accepted = generator.evaluate_personal_target("Рассвет", "Огонь", "Воздух")
    assert accepted["outcome"] == "target"
    assert accepted["relation"] == "metaphor"
    assert accepted["name"] == "Рассвет"

    rejected = generator.evaluate_personal_target("Рассвет", "Пыль", "Золото")
    assert rejected == {"outcome": "invalid"}


def test_local_personal_targets_are_distinct_and_have_matching_evaluators():
    from gen_llm import LLMGenerator

    generator = LLMGenerator(provider="local")
    targets = [
        generator.generate_personal_target(f"device-{index}|2026-W48|1")
        for index in range(12)
    ]
    assert len({target["name"] for target in targets}) > 1

    solutions = {
        "Рассвет": ("Огонь", "Воздух"),
        "Стеклянный дождь": ("Вода", "Песок"),
        "Память ветра": ("Воздух", "Пыль"),
    }
    for target in targets:
        a, b = solutions[target["name"]]
        accepted = generator.evaluate_personal_target(target["name"], a, b)
        assert accepted["outcome"] == "target"
        assert accepted["name"] == target["name"]


def test_external_personal_target_generation_returns_validated_json(monkeypatch):
    from gen_llm import LLMGenerator

    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append(json)
        return _ok_resp('{"name": "Рассвет", "hint": "Найди свет после тьмы."}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    target = LLMGenerator(provider="openrouter", api_key="k", models="m1").generate_personal_target(
        "device-a|2026-W48|1"
    )

    assert target == {"name": "Рассвет", "hint": "Найди свет после тьмы."}
    assert calls[0]["model"] == "m1"
    assert "device-a|2026-W48|1" in calls[0]["messages"][-1]["content"]


def test_external_personal_target_evaluator_returns_validated_outcome(monkeypatch):
    from gen_llm import LLMGenerator

    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append(json)
        return _ok_resp(
            '{"outcome":"target","name":"Рассвет","relation":"metaphor",'
            '"description":"Огонь и воздух складываются в образ рассвета."}'
        )

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    result = LLMGenerator(provider="openrouter", api_key="k", models="m1").evaluate_personal_target(
        "Рассвет", "Огонь", "Воздух"
    )

    assert result["outcome"] == "target"
    assert result["relation"] == "metaphor"
    assert all(value in calls[0]["messages"][-1]["content"] for value in ("Рассвет", "Огонь", "Воздух"))


def test_external_personal_target_malformed_response_is_unavailable(monkeypatch):
    from gen_llm import LLMError, LLMGenerator

    def fake_post(url, json=None, headers=None, timeout=None):
        return _ok_resp('{"outcome":"target","name":"Cat","relation":"metaphor"}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    generator = LLMGenerator(provider="openrouter", api_key="k", models="m1")

    with pytest.raises(LLMError):
        generator.evaluate_personal_target("Рассвет", "Огонь", "Воздух")


@pytest.mark.parametrize(("relation", "a", "b", "name"), [
    ("physical", "Огонь", "Вода", "Пар"),
    ("бытовая", "Чай", "Сахар", "Сладкий чай"),
    ("metaphor", "Надежда", "Свет", "Рассвет"),
    ("compound", "Снег", "Человек", "Снеговик"),
    ("morphology", "Без", "Ум", "Безумие"),
    ("prefix_suffix", "Лес", "Волк", "Лесовик"),
    ("group", "Звезда", "Звезда", "Созвездие"),
    ("abstract", "Время", "Память", "Ностальгия"),
    ("cultural", "Дракон", "Рыцарь", "Легенда"),
    ("poetic_ironic", "Зима", "Лето", "Зимнее лето"),
    ("recursive", "Пар", "Воздух", "Туман"),
])
def test_target_semantic_matrix_accepts_all_dungen_classes(relation, a, b, name):
    from gen_llm import semantic_check, validate_target_result

    valid = validate_target_result({
        "outcome": "intermediate", "name": name, "relation": relation,
        "description": "Оба входа необходимы для этого одного понятного шага.",
    })

    assert valid is not None
    assert valid["relation"] == relation
    assert semantic_check(name, a, b)[0]


@pytest.mark.parametrize(("relation", "a", "b", "name"), [
    ("physical", "Огонь", "Вода", "ОгоньВода"),
    ("бытовая", "Чай", "Сахар", "ЧайСахар"),
    ("metaphor", "Надежда", "Свет", "НадеждаСвет"),
    ("compound", "Снег", "Человек", "СнегЧеловек"),
    ("morphology", "Без", "Ум", "БезУм"),
    ("prefix_suffix", "Лес", "Волк", "ЛесВолк"),
    ("group", "Звезда", "Звезда", "ЗвездаЗвезда"),
    ("abstract", "Время", "Память", "ВремяПамять"),
    ("cultural", "Дракон", "Рыцарь", "ДраконРыцарь"),
    ("poetic_ironic", "Зима", "Лето", "ЗимаЛето"),
    ("recursive", "Пар", "Воздух", "ПарВоздух"),
])
def test_target_semantic_matrix_rejects_raw_join_for_every_class(relation, a, b, name):
    from gen_llm import semantic_check, validate_target_result

    valid = validate_target_result({
        "outcome": "intermediate", "name": name, "relation": relation,
        "description": "Механическая склейка без отдельного лексического смысла.",
    })

    assert valid is not None
    ok, reason = semantic_check(name, a, b)
    assert not ok and "склейк" in reason


@pytest.mark.parametrize("name", [
    "РассветA", "Рассвет!", "Рассвет\tЛуч", "Рассвет-Луч",
    "Рассвет_Луч", "Рассвет1", "Р" * 41,
])
def test_target_names_are_strict_cyrillic_and_bounded(monkeypatch, name):
    import json as jsonlib

    from gen_llm import LLMError, LLMGenerator, validate_target_result

    monkeypatch.setattr(
        gen_llm.requests, "post",
        lambda url, json=None, headers=None, timeout=None: _ok_resp(
            jsonlib.dumps({"name": name, "hint": "Короткая подсказка."}, ensure_ascii=False)
        ),
    )
    generator = LLMGenerator(provider="openrouter", api_key="k", models="m1")

    with pytest.raises(LLMError):
        generator.generate_personal_target("device-a|2026-W48|1")
    assert validate_target_result({
        "outcome": "intermediate", "name": name, "relation": "physical",
        "description": "Оба входа участвуют в результате.",
    }) is None


def test_target_generation_falls_back_after_malformed_metadata(monkeypatch):
    from gen_llm import LLMGenerator

    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append(json["model"])
        if json["model"] == "m1":
            return _ok_resp('{"name":"Cat","hint":"Hidden seed."}')
        return _ok_resp('{"name":"Рассвет","hint":"Найди свет после тьмы."}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    target = LLMGenerator(provider="openrouter", api_key="k", models="m1,m2").generate_personal_target(
        "device-a|2026-W48|1"
    )

    assert target["name"] == "Рассвет"
    assert calls == ["m1", "m2"]


def test_target_generation_rejects_internal_seed_echo(monkeypatch):
    from gen_llm import LLMGenerator

    calls = []
    seed = "device-a|2026-W48|1"

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append(json["model"])
        if json["model"] == "m1":
            return _ok_resp('{"name":"Рассвет","hint":"Внутренний seed: device-a|2026-W48|1."}')
        return _ok_resp('{"name":"Рассвет","hint":"Найди свет после тьмы."}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    target = LLMGenerator(provider="openrouter", api_key="k", models="m1,m2").generate_personal_target(
        seed
    )

    assert target == {"name": "Рассвет", "hint": "Найди свет после тьмы."}
    assert seed not in target["hint"]
    assert calls == ["m1", "m2"]


def test_target_evaluator_falls_back_after_unsupported_metadata(monkeypatch):
    from gen_llm import LLMGenerator

    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append(json["model"])
        if json["model"] == "m1":
            return _ok_resp(
                '{"outcome":"intermediate","name":"Пар","relation":"random",'
                '"description":"Неподдерживаемая метаинформация."}'
            )
        return _ok_resp(
            '{"outcome":"intermediate","name":"Пар","relation":"physical",'
            '"description":"Огонь и вода образуют пар."}'
        )

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    result = LLMGenerator(provider="openrouter", api_key="k", models="m1,m2").evaluate_personal_target(
        "Рассвет", "Огонь", "Вода"
    )

    assert result["relation"] == "physical"
    assert calls == ["m1", "m2"]


@pytest.mark.skipif(
    os.environ.get("PERSONAL_TARGET_LLM_SMOKE") != "1",
    reason="opt-in real-provider smoke: set PERSONAL_TARGET_LLM_SMOKE=1",
)
def test_real_provider_personal_target_smoke_is_not_mock():
    import json

    from gen_llm import LLMError, LLMGenerator
    from personal_experiment import normalize_target_name

    generator = LLMGenerator()
    if generator.provider in ("mock", "local", "off", "") or not generator.available():
        pytest.fail("real-provider smoke requires an configured external provider")
    report = {"provider": generator.provider, "fixtures": []}
    try:
        target = generator.generate_personal_target("smoke|2026-W48|1")
        report["target"] = {"name": target["name"], "hint": target["hint"]}
        for a, b in (("Огонь", "Вода"), ("Надежда", "Свет"), ("Без", "Ум")):
            result = generator.evaluate_personal_target(target["name"], a, b)
            if result["outcome"] == "target":
                assert normalize_target_name(result["name"]) == normalize_target_name(target["name"])
            report["fixtures"].append({"a": a, "b": b, "outcome": result["outcome"]})
    except LLMError as exc:
        report["status"] = "unavailable"
        print("PERSONAL_TARGET_LLM_SMOKE " + json.dumps(report, ensure_ascii=False))
        pytest.skip("real provider unavailable: %s" % exc)
    report["status"] = "ok"
    print("PERSONAL_TARGET_LLM_SMOKE " + json.dumps(report, ensure_ascii=False))
