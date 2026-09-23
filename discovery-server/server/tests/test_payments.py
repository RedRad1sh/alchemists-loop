"""Регрессии T22: серверная валидация платёжных чеков (/api/receipt/verify).

Что здесь проверяется и почему именно так:

1. Выключенный по умолчанию гейт НЕ пропускает выдачу: и ворендор, и эндпоинт
   отвечают «не проверено» (vendor_validation_disabled), никогда verified=True.
2. Включённый гейт без реального вызова магазина — тоже отказ
   (vendor_validation_not_implemented): «включили, но не настроили» не должно
   выглядеть как подтверждённый чек.
3. Идемпотентность журнала: первый подтверждённый чек → processed, повтор тем же
   устройством → байт-в-байт тот же ответ и БЕЗ нового обращения в магазин;
   тот же чек с другого устройства → 409 и новая строка не появляется; тот же
   токен с другим sku → 409 (receipt_hash — единственный PK, echo чужого товара).
4. Отказ магазина («чека нет») — это НЕ unavailable: 200 ok=False, а не 503,
   иначе клиент в отладочной сборке начал бы начислять по настоящему отказу.
5. Сырой токен в БД не хранится (только SHA-256) и белый список SKU не разъезжается
   с клиентским каталогом data/monetization.json.
6. Очистка журнала при startup: протухшие pending удаляются, processed — никогда
   (потеря processed = повторная выдача уже закрытого чека).

NOTE: тесты написаны в стиле tests/test_quota.py (import server as srv +
TestClient). На машине разработки НЕ запускались: нет fastapi/httpx, а server.py
требует Python >= 3.10 (conftest.py, pin окружения). Проверены статически;
первый прогон — на коробке с зависимостями.
"""

import asyncio
import hashlib
import json
import os
import sys
import time
from pathlib import Path


def _client(tmp_path, monkeypatch):
    """ srv + TestClient на свежей БД в tmp_path (как в test_quota.py). """
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    from fastapi.testclient import TestClient

    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "payments.db"))
    # get_llm подменён, как в соседних сюитах: чеками он не пользуется, а
    # lifespan-`startup()` его дёргает — тестам платёжных чеков живой генератор
    # не нужен и не должен всплывать в ошибке, если его окружение не задано.
    monkeypatch.setattr(srv, "get_llm", lambda: _NoLLM())
    srv.init_db()
    return srv, TestClient(srv.app)


class _NoLLM:
    provider = "local"
    models = []


# Один SKU из клиентского каталога; токен — произвольная строка «как из магазина».
SKU = "al_loop_ether_500"
TOKEN = "gross-token-value-1234567890"
DEVICE = "device-1"


def _receipts(srv):
    conn = srv.get_db()
    try:
        return conn.execute("SELECT * FROM receipts ORDER BY first_seen_at").fetchall()
    finally:
        conn.close()


def _sha(token):
    """Ровно тот отпечаток, что сервер кладёт в receipt_hash."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _gate_on(srv, monkeypatch):
    """Гейт включён: заданы И URL, И сервисный ключ (conftest пинит их пустыми)."""
    monkeypatch.setattr(srv, "RECEIPT_VALIDATION_URL", "https://validator.invalid/receipt")
    monkeypatch.setattr(srv, "RECEIPT_SERVICE_KEY", "test-service-key")


class _FakeVendor:
    """Замена «вызова магазина»: считает обращения и отдаёт фиксированный вердикт.

    Нужен ровно потому, что реального ворендора в репозитории нет: проверить
    ветку processed больше нечем. Сам факт «без реальной проверки ничего не
    verified» закрыт классом TestGateOffByDefault ниже, где ворендор не
    подменяется."""

    def __init__(self, verdict):
        self.calls = []
        self._verdict = verdict

    def __call__(self, provider, sku, receipt_token):
        self.calls.append((provider, sku, receipt_token))
        return dict(self._verdict)


def _vendor(srv, monkeypatch, verdict=None):
    fake = _FakeVendor(dict(verdict or {"verified": True, "reason": "verified"}))
    monkeypatch.setattr(srv, "_validate_receipt_with_vendor", fake)
    return fake


def _verify(client, device_id=DEVICE, token=TOKEN, provider="google_play", sku=SKU):
    return client.post("/api/receipt/verify", json={
        "device_id": device_id, "provider": provider, "sku": sku, "receipt_token": token,
    })


class TestGateOffByDefault:
    def test_endpoint_refuses_and_never_verifies(self, tmp_path, monkeypatch):
        srv, client = _client(tmp_path, monkeypatch)
        assert srv._receipt_validation_enabled() is False
        with client:
            r = _verify(client)
        assert r.status_code == 503
        body = r.json()["detail"]
        assert body["ok"] is False
        assert body["verified"] is False
        assert body["reason"] == "vendor_validation_disabled"
        # Нечего и записывать: неподтверждённые чеки в журнал не пишутся.
        assert _receipts(srv) == []

    def test_vendor_function_cannot_answer_verified_without_config(self):
        """Прямая проверка единственной точки verified=True: без конфигурации —
        только vendor_validation_disabled (инверсия этой ветки красит тест)."""
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        import server as srv

        assert srv._receipt_validation_enabled() is False
        assert srv._validate_receipt_with_vendor("google_play", SKU, TOKEN) == {
            "verified": False, "reason": "vendor_validation_disabled",
        }

    def test_enabled_gate_without_vendor_call_still_refuses(self, tmp_path, monkeypatch):
        """URL+ключ заданы, но вызова магазина нет → отказ, и чек НЕ processed."""
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        with client:
            r = _verify(client)
            assert r.status_code == 503
            assert r.json()["detail"]["reason"] == "vendor_validation_not_implemented"
            assert r.json()["detail"]["verified"] is False
            rows = _receipts(srv)
        assert [row["status"] for row in rows] == ["pending"]
        assert all(row["processed_at"] is None for row in rows)


class TestVerifiedFlow:
    def test_first_verification_marks_processed(self, tmp_path, monkeypatch):
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        vendor = _vendor(srv, monkeypatch)
        with client:
            r = _verify(client)
            assert r.status_code == 200
            body = r.json()
            rows = _receipts(srv)
        assert body == {
            "ok": True, "verified": True, "status": "processed",
            "reason": "verified",
            "receipt_hash": hashlib.sha256(TOKEN.encode("utf-8")).hexdigest(),
        }
        assert vendor.calls == [("google_play", SKU, TOKEN)]
        assert len(rows) == 1
        assert rows[0]["status"] == "processed"
        assert rows[0]["device_id"] == DEVICE
        assert rows[0]["processed_at"] is not None

    def test_repeat_same_device_replays_answer_without_vendor_call(self, tmp_path, monkeypatch):
        """«повтор после processed → тот же ответ»: тело идентично, магазин молчит."""
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        vendor = _vendor(srv, monkeypatch)
        with client:
            first = _verify(client)
            again = _verify(client)
            rows = _receipts(srv)
        assert first.status_code == again.status_code == 200
        assert again.json() == first.json()
        assert again.json()["verified"] is True
        assert len(vendor.calls) == 1
        assert len(rows) == 1

    def test_same_receipt_from_other_device_is_rejected(self, tmp_path, monkeypatch):
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        _vendor(srv, monkeypatch)
        with client:
            ok = _verify(client, device_id=DEVICE)
            steal = _verify(client, device_id="device-2")
            rows = _receipts(srv)
        assert ok.status_code == 200
        assert steal.status_code == 409
        body = steal.json()["detail"]
        assert body["ok"] is False and body["verified"] is False
        assert body["reason"] == "receipt_device_mismatch"
        # Чужое устройство не получило своей строки в журнале.
        assert len(rows) == 1 and rows[0]["device_id"] == DEVICE

    def test_same_token_with_other_sku_is_rejected(self, tmp_path, monkeypatch):
        """M-3: receipt_hash — единственный PRIMARY KEY, поэтому тот же токен с
        другим sku иначе нашёл бы processed-строку первого товара и получил
        verified=True без вердикта. Обязаны отдать 409 и НЕ заводить новую строку."""
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        vendor = _vendor(srv, monkeypatch)
        other_sku = "al_loop_ether_1500"
        assert other_sku in srv.RECEIPT_SKUS and other_sku != SKU
        with client:
            first = _verify(client)                       # processed для SKU
            clash = _verify(client, sku=other_sku)        # тот же токен, другой sku
            rows = _receipts(srv)
        assert first.status_code == 200
        assert clash.status_code == 409
        body = clash.json()["detail"]
        assert body["ok"] is False and body["verified"] is False
        assert body["reason"] == "receipt_sku_mismatch"
        # receipt_hash в detail — тот же формат, что у device-mismatch.
        assert body["receipt_hash"] == _sha(TOKEN)
        # Новой строки нет: чек остаётся привязан к исходному SKU и не process-ится
        # заново под другим товаром.
        assert len(rows) == 1 and rows[0]["sku"] == SKU
        # Магазин не дёргался повторно (отсечка раньше вердикта).
        assert len(vendor.calls) == 1

    def test_same_token_with_other_provider_is_rejected(self, tmp_path, monkeypatch):
        """R-3: receipt_hash — единственный PRIMARY KEY, поэтому тот же токен с
        другим provider иначе нашёл бы processed-строку первого провайдера и
        получил verified=True без вердикта (или вердикт по чужому провайдеру).
        Обязаны отдать 409 и НЕ заводить новую строку. SKU оставляем исходным:
        ветки сверок (provider/sku) не должны перекрываться в одном кейсе."""
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        vendor = _vendor(srv, monkeypatch)
        # Второй provider — из белого списка сервера, не строкой-догадкой
        # (сюита ниже пинит состав: google_play + rustore).
        other_provider = next(
            (p for p in srv.RECEIPT_PROVIDERS if p != "google_play"), ""
        )
        assert other_provider != ""
        with client:
            first = _verify(client)                                # processed как google_play
            clash = _verify(client, provider=other_provider)       # тот же токен, другой provider
            rows = _receipts(srv)
        assert first.status_code == 200
        assert clash.status_code == 409
        body = clash.json()["detail"]
        assert body["ok"] is False and body["verified"] is False
        assert body["reason"] == "receipt_provider_mismatch"
        # receipt_hash в detail — тот же формат, что у device/sku-mismatch.
        assert body["receipt_hash"] == _sha(TOKEN)
        # Новой строки нет: чек остаётся привязан к исходному провайдеру и SKU.
        assert len(rows) == 1 and rows[0]["provider"] == "google_play"
        assert rows[0]["sku"] == SKU
        # Магазин не дёргался повторно (отсечка раньше вердикта и раньше echo).
        assert len(vendor.calls) == 1

    def test_raw_token_never_reaches_the_database(self, tmp_path, monkeypatch):
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        _vendor(srv, monkeypatch)
        with client:
            _verify(client)
            rows = _receipts(srv)
        values = [str(v) for row in rows for v in tuple(row)]
        assert values and all(TOKEN not in v for v in values)
        assert hashlib.sha256(TOKEN.encode("utf-8")).hexdigest() in values

    def test_vendor_rejection_is_a_refusal_not_an_outage(self, tmp_path, monkeypatch):
        """Отказ магазина («чека нет») обязан быть 200 ok=False: 503 клиент читает
        как «валидатор недоступен» и в отладке начисляет."""
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        _vendor(srv, monkeypatch, {"verified": False, "reason": "receipt_not_found"})
        with client:
            r = _verify(client)
            rows = _receipts(srv)
        assert r.status_code == 200
        assert r.json()["ok"] is False and r.json()["verified"] is False
        assert r.json()["reason"] == "receipt_not_found"
        assert [row["status"] for row in rows] == ["pending"]

    def test_startup_purges_stale_pending_but_never_processed(self, tmp_path, monkeypatch):
        """Очистка журнала при startup: протухшие pending — мусор забытых/
        удалённых установок; processed удалять нельзя — это ответ «чек уже
        подтверждали», его потеря разрешает повторную выдачу."""
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        _vendor(srv, monkeypatch, {"verified": False, "reason": "receipt_not_found"})
        month_ago = time.time() - 31 * 86400
        with client:
            _verify(client)                      # pending, «увиден только что»
            _verify(client, token="fresh-token-2")
        conn = srv.get_db()
        try:
            conn.execute("UPDATE receipts SET last_seen_at = ? WHERE receipt_hash = ?",
                         (_sha(TOKEN), month_ago))
            conn.execute(
                "INSERT INTO receipts (receipt_hash, device_id, provider, sku, status,"
                " first_seen_at, processed_at, last_seen_at) VALUES (?, ?, ?, ?, 'processed', ?, ?, ?)",
                (_sha("processed-long-ago"), DEVICE, "google_play", SKU, month_ago, month_ago, month_ago),
            )
            conn.commit()
        finally:
            conn.close()
        # Тот же код, что исполняет lifespan: on_event('startup') возвращает
        # исходную async-функцию, поэтому вызываем её напрямую.
        asyncio.run(srv.startup())
        hashes = {row["receipt_hash"] for row in _receipts(srv)}
        assert _sha(TOKEN) not in hashes
        assert _sha("fresh-token-2") in hashes
        assert _sha("processed-long-ago") in hashes


class TestInputWhitelists:
    def test_unknown_provider_and_sku_rejected(self, tmp_path, monkeypatch):
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        _vendor(srv, monkeypatch)
        with client:
            provider = _verify(client, provider="app_store")
            sku = _verify(client, sku="not_in_catalog")
            rows = _receipts(srv)
        assert provider.status_code == 400
        assert provider.json()["detail"]["reason"] == "unknown_provider"
        assert sku.status_code == 400
        assert sku.json()["detail"]["reason"] == "unknown_sku"
        assert rows == []

    def test_provider_and_sku_are_normalized_before_matching(self, tmp_path, monkeypatch):
        srv, client = _client(tmp_path, monkeypatch)
        _gate_on(srv, monkeypatch)
        vendor = _vendor(srv, monkeypatch)
        with client:
            r = _verify(client, provider="  Google_Play ", sku="  " + SKU + " ")
        assert r.status_code == 200
        # в журнал и в ворендор уходит нормализованная пара
        assert vendor.calls == [("google_play", SKU, TOKEN)]

    def test_server_sku_whitelist_matches_client_catalog(self):
        """Белый список сервера обязан совпадать со store_sku клиента: расхождение
        означало бы «валидатор честно отказывает реальному SKU»."""
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
        import server as srv

        catalog_path = (
            Path(__file__).resolve().parents[3]
            / "alchemists-loop" / "data" / "monetization.json"
        )
        with open(catalog_path, encoding="utf-8") as f:
            catalog = json.load(f)
        from_catalog = set()
        for product in catalog.get("products", []):
            for store_sku in product.get("store_sku", {}).values():
                from_catalog.add(store_sku)
        assert set(srv.RECEIPT_SKUS) == from_catalog
        assert set(srv.RECEIPT_PROVIDERS) == {"google_play", "rustore"}
