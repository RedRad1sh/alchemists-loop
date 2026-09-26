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
