"""Регрессионные тесты LLM-генератора без сети (monkeypatch requests.post).

Покрывают инциденты v21:
- HTTP 400 с текстом json_validate_failed → повтор без response_format;
- HTTP 400 с текстом про response_format/json_object → повтор без response_format;
- HTTP 403 (модель недоступна ключу) → LLMError, генерация переходит к другой модели.
"""
import copy
import os
import sys

import pytest

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_here, ".."))

import gen_llm  # noqa: E402


class _FakeResp:
    def __init__(self, status_code: int, text: str = "", content: str = ""):
        self.status_code = status_code
        self.text = text
        self._content = content

    def json(self):
        import json as _json
        return _json.loads(self._content)


def _ok_resp(content: str):
    return _FakeResp(200, "", '{"choices": [{"message": {"content": %s}}]}' % _ok(content))


def _ok(s: str):
    import json as _json
    return _json.dumps(s, ensure_ascii=False)


def _make_gen(models: str = "m1,m2"):
    return gen_llm.LLMGenerator(provider="openrouter", api_key="k", models=models)


def test_call_once_retries_json_validate_failed_without_response_format(monkeypatch):
    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append({"json": copy.deepcopy(json)})
        if "response_format" in json:
            return _FakeResp(400, '{"error": {"message": "json_validate_failed: ..."}}')
        return _ok_resp('{"combinable": true, "name": "Дом"}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    gen = _make_gen()
    raw = gen._call_once("m1", "Стена", "Стена", "")
    assert raw == '{"combinable": true, "name": "Дом"}'
    assert len(calls) == 2
    assert "response_format" in calls[0]["json"]
    assert "response_format" not in calls[1]["json"]


def test_call_once_retries_response_format_error(monkeypatch):
    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append({"json": copy.deepcopy(json)})
        if "response_format" in json:
            return _FakeResp(400, "response_format is not supported")
        return _ok_resp('{"combinable": false}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    raw = _make_gen()._call_once("m1", "Огонь", "Вода", "")
    assert raw == '{"combinable": false}'
    assert len(calls) == 2
    assert "response_format" not in calls[1]["json"]


def test_call_once_403_raises_llm_error(monkeypatch):
    def fake_post(url, json=None, headers=None, timeout=None):
        return _FakeResp(403, '{"error": {"message": "model_not_found"}}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    with pytest.raises(gen_llm.LLMError) as ei:
        _make_gen()._call_once("m1", "A", "B", "")
    assert "403" in str(ei.value)


def test_generate_rotates_to_next_model_after_403(monkeypatch):
    """403 на первой модели не должен убивать генерацию: переходим ко второй."""
    seen = []

    def fake_post(url, json=None, headers=None, timeout=None):
        seen.append(json["model"])
        if json["model"] == "m1":
            return _FakeResp(403, "model_not_found")
        return _ok_resp('{"combinable": true, "name": "Дом"}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    gen = _make_gen("m1,m2")
    result = gen.generate("wall", "wall", "Стена", "Стена", "wall|wall")
    assert result == {"combinable": True, "name": "Дом"}
    assert seen[:2] == ["m1", "m2"]


def test_generate_chain_starts_at_primary_model(monkeypatch):
    """Цепочка обязана начинаться с models[0]: роль генератора закреплена за
    первой моделью (так обещает .env.example), запасные идут только после неё."""
    seen = []

    def fake_post(url, json=None, headers=None, timeout=None):
        seen.append(json["model"])
        return _FakeResp(403, "model_not_found")

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    gen = _make_gen("m1,m2,m3")
    with pytest.raises(gen_llm.LLMError):
        gen.generate("a", "b", "A", "B", "a|b")
    assert seen == ["m1", "m2", "m3"][:gen_llm.MAX_ATTEMPTS], seen


def test_hint_falls_back_to_backup_model(monkeypatch):
    """generate_hint страдал тем же: все попытки бились в основную модель."""
    seen = []

    def fake_post(url, json=None, headers=None, timeout=None):
        seen.append(json["model"])
        if json["model"] == "m1":
            return _FakeResp(429, "rate limit")
        return _ok_resp('{"hint": "Тёплый намёк"}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    assert _make_gen("m1,m2").generate_hint("Огонь", "Вода") == {"hint": "Тёплый намёк"}
    assert seen[:2] == ["m1", "m2"], seen


def test_identity_uses_backup_model_after_primary_fails(monkeypatch):
    seen = []

    def fake_post(url, json=None, headers=None, timeout=None):
        seen.append(json["model"])
        if json["model"] == "m1":
            return _FakeResp(403, "model_not_found")
        return _ok_resp('{"name": "Пепельный знак", "lore": "Лор про пепел."}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    res = _make_gen("m1,m2").generate_card_identity(["Огонь", "Пепел"], "rare")
    assert res["name"] == "Пепельный знак", res
    assert seen == ["m1", "m2"], seen


def test_identity_budget_stays_two_calls(monkeypatch):
    """Ритуал крафта не должен ждать полный MAX_ATTEMPTS: потолок попыток
    identity меньше — основная модель + одна запасная, дальше шаблон."""
    seen = []

    def fake_post(url, json=None, headers=None, timeout=None):
        seen.append(json["model"])
        return _FakeResp(403, "model_not_found")

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    res = _make_gen("m1,m2,m3").generate_card_identity(["Огонь"], "rare")
    assert seen == ["m1", "m2"], seen
    assert res["name"].startswith("Сигил"), res


def test_unanimous_refusal_is_a_decision_not_an_outage(monkeypatch):
    """combinable:false во всех попытках = решение, а не технический сбой.

    До фикса последний отказ превращался в LLMError, сервер отвечал
    status="unavailable", возвращал квоту и оставлял пару кандидатом — каждый
    следующий вызов снова платил за те же MAX_ATTEMPTS. Ретрай по
    COMBINABLE_FEEDBACK при этом сохраняется: отказ перепроверяется, а не
    принимается с первого слова.
    """
    seen = []

    def fake_post(url, json=None, headers=None, timeout=None):
        seen.append(json["model"])
        return _ok_resp('{"combinable": false}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    res = _make_gen("m1,m2").generate("a", "b", "Огонь", "Абстракция", "a|b")
    assert res == {"combinable": False}, res
    assert len(seen) == gen_llm.MAX_ATTEMPTS, seen


def test_refusal_survives_later_outage(monkeypatch):
    """Отказ получен — последующие 403 его не отменяют: ответ модели был."""
    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append(json["model"])
        if len(calls) == 1:
            return _ok_resp('{"combinable": false}')
        return _FakeResp(403, "model_not_found")

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    assert _make_gen("m1,m2").generate("a", "b", "A", "B", "a|b") == {"combinable": False}


def test_pure_outage_still_raises(monkeypatch):
    """Вторая половина того же контракта: ни одного валидного ответа — это
    unavailable, пара остаётся кандидатом и отказ в БД не пишется."""
    def fake_post(url, json=None, headers=None, timeout=None):
        return _FakeResp(503, "No available providers after filtering parameters")

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    with pytest.raises(gen_llm.LLMError):
        _make_gen("m1,m2").generate("a", "b", "A", "B", "a|b")


def test_compat_retry_drops_both_limit_fields(monkeypatch):
    """503 про max_tokens: ретрай обязан снять и max_tokens тоже.

    Снятие только max_completion_tokens оставляло в ретрае ровно то поле, на
    которое пожаловался провайдер, и повтор падал по той же причине.
    """
    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append({"json": copy.deepcopy(json)})
        if "max_tokens" in json:
            return _FakeResp(503, '{"error": {"message": "Unsupported parameter: max_tokens"}}')
        return _ok_resp('{"combinable": false}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    raw = _make_gen()._call_once("m1", "Огонь", "Вода", "")
    assert raw == '{"combinable": false}'
    assert len(calls) == 2, calls
    assert "max_tokens" in calls[0]["json"]
    assert "max_tokens" not in calls[1]["json"], calls[1]["json"]
    assert "max_completion_tokens" not in calls[1]["json"], calls[1]["json"]


def test_english_routing_503_gets_compat_retry(monkeypatch):
    """Формулировка отказа провайдера приходит и по-английски: «no providers
    available after filtering» без ключей этого языка не распознавалась, и
    совместимый повтор не запускался вовсе."""
    calls = []

    def fake_post(url, json=None, headers=None, timeout=None):
        calls.append({"json": copy.deepcopy(json)})
        if "response_format" in json:
            return _FakeResp(503, "No providers are available after filtering the "
                                  "requested parameters for this endpoint")
        return _ok_resp('{"combinable": true, "name": "Пар"}')

    monkeypatch.setattr(gen_llm.requests, "post", fake_post)
    raw = _make_gen()._call_once("m1", "Огонь", "Вода", "")
    assert len(calls) == 2, calls
    assert "response_format" not in calls[1]["json"]
    assert raw == '{"combinable": true, "name": "Пар"}'
