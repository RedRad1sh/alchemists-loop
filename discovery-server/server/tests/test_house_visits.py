"""
γ «Гостевая книга»: серверный учёт визитов в чужие домики.

- POST /api/house/visit: себе — 400, хост без домика — found=False,
  повтор гостя в тот же день не удваивает счётчик, 11-й хост — 429;
- GET /api/house отдаёт visits_week (0, а не null), GET /api/me — house_visits_week
  и ленту гостей (ник + аватар);
- публичный GET /api/house имён гостей НЕ отдаёт (спека §7.2 просит ленту
  «в своём доме», а не витрину чужих посетителей);
- /api/rating содержит house_guests за те же 7 дней;
- недельное окно считается в ЕДИНОЙ серверной шкале (U7): monkeypatch _now_dt.
"""

import os
import sys
from datetime import datetime, timedelta

from fastapi.testclient import TestClient


def _srv(tmp_path, monkeypatch):
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import server as srv
    monkeypatch.setattr(srv, "DB_PATH", str(tmp_path / "visits.db"))
    return srv


def _client(srv):
    # Тот же проверенный идиом, что в tests/test_t09_http_races.py: init_db()
    # явно, затем TestClient без контекстного менеджера. `with client:` дёргал
    # бы startup-хук (server.py:1292) и оставлял бы его висящим на весь модуль.
    srv.init_db()
    return TestClient(srv.app)


def _build_house(srv, nick, device_id):
    """Хост с домиком: только POST /api/house ставит players.house."""
    client = _client(srv)
    r = client.post("/api/house", json={
        "device_id": device_id, "nick": nick, "house": {"v": 1, "built": True}})
    assert r.status_code == 200, r.text
    return client


def _player(srv, nick, device_id):
    """Игрок БЕЗ домика: players-строка есть, house = NULL (для POST /api/me)."""
    client = _client(srv)
    r = client.post("/api/me", json={"device_id": device_id, "nick": nick})
    assert r.status_code == 200, r.text
    return client


class TestVisit:
    def test_self_visit_rejected(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _build_house(srv, "Варда", "dev-host")
        r = client.post("/api/house/visit",
                        json={"device_id": "dev-host", "host_nick": "Варда"})
        assert r.status_code == 400, r.text

    def test_host_without_house_not_found(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        r = client.post("/api/house/visit",
                        json={"device_id": "dev-guest", "host_nick": "Бездомика"})
        assert r.status_code == 200, r.text
        body = r.json()
        assert body["ok"] is False and body["found"] is False
        conn = srv.get_db()
        try:
            n = conn.execute("SELECT COUNT(*) AS c FROM house_visits").fetchone()["c"]
        finally:
            conn.close()
        assert n == 0, "визит без домика не должен оставлять запись"

    def test_repeat_same_day_counts_once(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _build_house(srv, "Варда", "dev-host")
        first = client.post("/api/house/visit",
                            json={"device_id": "dev-g", "host_nick": "Варда"}).json()
        again = client.post("/api/house/visit",
                            json={"device_id": "dev-g", "host_nick": "Варда"}).json()
        assert first["visits_week"] == 1, first
        assert again["visits_week"] == 1, "тот же гость в тот же день не удваивает счётчик"
        assert client.get("/api/house", params={"nick": "Варда"}).json()["visits_week"] == 1

    def test_visit_outside_week_window(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        clock = {"now": datetime(2026, 9, 20, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _build_house(srv, "Варда", "dev-host")
        assert client.post("/api/house/visit",
                           json={"device_id": "dev-g", "host_nick": "Варда"}).json()["visits_week"] == 1
        # три дня назад — всё ещё в окне 7 дней
        clock["now"] = datetime(2026, 9, 23, 12, 0)
        assert client.post("/api/house/visit",
                           json={"device_id": "dev-g2", "host_nick": "Варда"}).json()["visits_week"] == 2
        # восемь дней после первого — первый визит выпадает из окна
        clock["now"] = datetime(2026, 9, 28, 12, 0)
        body = client.post("/api/house/visit",
                           json={"device_id": "dev-g3", "host_nick": "Варда"}).json()
        assert body["visits_week"] == 2, \
            "окно должно быть 7 дней: %s" % body
        # без этого ассерта тест зелё и на «COUNT(*) WHERE day >= '1970-01-01'»
        assert client.get("/api/me", params={"device_id": "dev-host"}).json()["house_visits_week"] == 2

    def test_daily_cap_of_distinct_hosts(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _client(srv)
        for i in range(srv.VISITS_PER_VISITOR_DAY + 1):
            host = "host%d" % i
            r = client.post("/api/house", json={
                "device_id": "dev-%s" % host, "nick": host,
                "house": {"v": 1, "built": True}})
            assert r.status_code == 200, r.text
        for i in range(srv.VISITS_PER_VISITOR_DAY):
            r = client.post("/api/house/visit",
                            json={"device_id": "dev-guest", "host_nick": "host%d" % i})
            assert r.status_code == 200, (i, r.text)
        r = client.post("/api/house/visit",
                        json={"device_id": "dev-guest", "host_nick": "host%d" % srv.VISITS_PER_VISITOR_DAY})
        assert r.status_code == 429, r.text
        # повтор к уже засчитанному хосту лимит не превышает — гость не наказывается
        r2 = client.post("/api/house/visit",
                         json={"device_id": "dev-guest", "host_nick": "host0"})
        assert r2.status_code == 200, r2.text

    def test_house_without_visits_returns_zero(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        client = _build_house(srv, "Варда", "dev-host")
        body = client.get("/api/house", params={"nick": "Варда"}).json()
        assert body["visits_week"] == 0, body
        assert body["house"] is not None

    def test_rating_exposes_house_guests(self, tmp_path, monkeypatch):
        srv = _srv(tmp_path, monkeypatch)
        clock = {"now": datetime(2026, 9, 20, 12, 0)}
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _build_house(srv, "Варда", "dev-host")
        # визит вне окна (8 дней назад) не должен попадать в рейтинг:
        # без этого ассерта подзапрос «за те же 7 дней» можно было бы написать
        # без hv.day >= ? и тест остался бы зелёным
        clock["now"] = datetime(2026, 9, 12, 12, 0)
        client.post("/api/house/visit",
                    json={"device_id": "dev-gold", "host_nick": "Варда"}).json()
        clock["now"] = datetime(2026, 9, 20, 12, 0)
        client.post("/api/house/visit",
                    json={"device_id": "dev-g", "host_nick": "Варда"}).json()
        # второй игрок БЕЗ домика: /api/rating строит строки из players, и в
        # пустой базе их была бы одна — next(...) на пустом итераторе упал бы
        # StopIteration, а не честным ассертом
        _player(srv, "Сосед", "dev-other")
        rows = client.get("/api/rating").json()["rows"]
        host = next(r for r in rows if r["nick"] == "Варда")
        assert host["house_built"] is True and host["house_guests"] == 1, host
        other = next(r for r in rows if r["nick"] == "Сосед")
        assert other["house_guests"] == 0 and other["house_built"] is False, other

    def test_me_lists_recent_guests(self, tmp_path, monkeypatch):
        """Спека §7.2: «в своём доме — строка … и лента, кто именно».

        Лента мировых событий (world_events, schema.sql:124-133) — это
        первооткрытия, визитов там нет. Отдельный эндпоинт не заводим: ленту
        отдаёт уже опрашиваемый клиентом GET /api/me (там же, где
        house_visits_week), а публичный GET /api/house имён гостей не раскрывает.
        Порядок — последние визиты сверху.
        """
        clock = {"now": datetime(2026, 9, 20, 12, 0)}
        srv = _srv(tmp_path, monkeypatch)
        monkeypatch.setattr(srv, "_now_dt", lambda: clock["now"])
        client = _build_house(srv, "Варда", "dev-host")
        _player(srv, "ГостьПервый", "dev-g1")
        _player(srv, "ГостьВторой", "dev-g2")
        client.post("/api/house/visit",
                    json={"device_id": "dev-g1", "host_nick": "Варда"})
        clock["now"] = datetime(2026, 9, 21, 12, 0)
        client.post("/api/house/visit",
                    json={"device_id": "dev-g2", "host_nick": "Варда"})
        me = client.get("/api/me", params={"device_id": "dev-host"}).json()
        guests = me["house_visitors"]
        assert [g["nick"] for g in guests] == ["ГостьВторой", "ГостьПервый"], guests
        assert guests[0]["avatar"], guests[0]
        assert guests[0]["day"] == "2026-09-21", guests[0]
        assert me["house_visits_week"] == 2, me
        # счётчик считает уникальных гостей, лента — записи с ником; без этого
        # ассерта DISTINCT в первом запросе можно было бы молча потерять
        assert len(guests) == me["house_visits_week"], guests
        # имена гостей приватны: публичный ответ домика их не отдаёт
        pub = client.get("/api/house", params={"nick": "Варда"}).json()
        assert pub["visits_week"] == 2, pub
        assert "guests" not in pub and "house_visitors" not in pub, pub

    def test_rename_response_keeps_guest_line(self, tmp_path, monkeypatch):
        """POST /api/me отдаёт те же дом-поля, что и GET: rename не сбрасывает ленту гостей."""
        srv = _srv(tmp_path, monkeypatch)
        client = _build_house(srv, "Варда", "dev-host")
        _player(srv, "ГостьПервый", "dev-g1")
        client.post("/api/house/visit",
                    json={"device_id": "dev-g1", "host_nick": "Варда"})
        me = client.post("/api/me", json={"device_id": "dev-host", "nick": "Варда Вторая"})
        assert me.status_code == 200, me.text
        body = me.json()
        assert [g["nick"] for g in body["house_visitors"]] == ["ГостьПервый"], body
        assert body["house_visits_week"] == 1, body
