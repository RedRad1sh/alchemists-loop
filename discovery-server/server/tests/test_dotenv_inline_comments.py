"""Issue #16: _load_dotenv должен резать unquoted inline-комментарии и беречь кавычки."""
import os

from gen_llm import _load_dotenv


def test_inline_comment_stripped_from_numeric_value(tmp_path, monkeypatch):
    env_file = tmp_path / ".env"
    env_file.write_text(
        "U16_DAILY_LIMIT=12  # дневной лимит опытов\n", encoding="utf-8"
    )
    monkeypatch.delenv("U16_DAILY_LIMIT", raising=False)
    _load_dotenv(paths=[str(env_file)])
    assert os.environ["U16_DAILY_LIMIT"] == "12"
    # числовое значение должно проходить то же преобразование, что делает server.py
    assert int(os.environ["U16_DAILY_LIMIT"]) == 12


def test_quoted_hash_preserved(tmp_path, monkeypatch):
    env_file = tmp_path / ".env"
    env_file.write_text(
        'U16_PHRASE="соль # перец"  # trailing comment\n'
        "U16_PLAIN='одинарные'\n",
        encoding="utf-8",
    )
    monkeypatch.delenv("U16_PHRASE", raising=False)
    monkeypatch.delenv("U16_PLAIN", raising=False)
    _load_dotenv(paths=[str(env_file)])
    assert os.environ["U16_PHRASE"] == "соль # перец"
    assert os.environ["U16_PLAIN"] == "одинарные"


def test_bare_hash_without_space_not_split(tmp_path, monkeypatch):
    env_file = tmp_path / ".env"
    env_file.write_text("U16_TOKEN=abc#def\n", encoding="utf-8")
    monkeypatch.delenv("U16_TOKEN", raising=False)
    _load_dotenv(paths=[str(env_file)])
    assert os.environ["U16_TOKEN"] == "abc#def"
