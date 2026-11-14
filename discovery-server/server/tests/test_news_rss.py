"""GET /api/news/rss — «Алхимический вестник» (RSS 2.0).

Юнит-слой: in-process TestClient, свежая БД из autouse fresh_unit_db.
Проверяем контент-тайп, структуру RSS, число item, сортировку по дате
убыв., экранирование XML (& < >) и форму pubDate (RFC822).
"""
import base64
import os
import sys
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import server as srv  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402


def _client() -> TestClient:
    srv.init_db()
    return TestClient(srv.app)


def test_content_type_and_channel():
    with _client() as c:
        r = c.get("/api/news/rss")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("application/rss+xml")
    root = ET.fromstring(r.text)
    assert root.tag == "rss" and root.get("version") == "2.0"
    ch = root.find("channel")
    assert ch is not None
    assert ch.findtext("title") == "Алхимический вестник"


def test_item_count_and_seed():
    with _client() as c:
        r = c.get("/api/news/rss")
    items = ET.fromstring(r.text).findall("./channel/item")
    assert 6 <= len(items) <= 8
    for it in items:
        assert (it.findtext("title") or "").strip() != ""
        assert (it.findtext("description") or "").strip() != ""
        assert (it.findtext("guid") or "").strip() != ""
        assert (it.findtext("category") or "").strip() != ""
        assert it.findtext("pubDate") is not None


def test_sorted_desc_and_rfc822():
    with _client() as c:
        r = c.get("/api/news/rss")
    items = ET.fromstring(r.text).findall("./channel/item")
    dates = [parsedate_to_datetime(it.findtext("pubDate")) for it in items]
    assert dates == sorted(dates, reverse=True)


def test_xml_escaping():
    srv.init_db()
    conn = srv.get_db()
    try:
        conn.execute(
            "INSERT INTO news_items (title, body, tag, published_at) VALUES (?,?,?,?)",
            ("Соль & <серная>", "Тело с <тегами> & амперсандом", "тест",
             "2026-11-13T10:00:00+00:00"))
        conn.commit()
    finally:
        conn.close()
    with TestClient(srv.app) as c:
        r = c.get("/api/news/rss")
    assert "&amp;" in r.text and "&lt;" in r.text and "&gt;" in r.text
    items = ET.fromstring(r.text).findall("./channel/item")
    first = items[0]  # самая свежая дата — наша тестовая строка
    assert first.findtext("title") == "Соль & <серная>"
    assert first.findtext("description") == "Тело с <тегами> & амперсандом"
    assert first.findtext("category") == "тест"


def test_guid_unique():
    with _client() as c:
        r = c.get("/api/news/rss")
    guids = [it.findtext("guid") for it in ET.fromstring(r.text).findall("./channel/item")]
    assert len(guids) == len(set(guids))


def test_summary_and_content_encoded():
    with _client() as c:
        r = c.get("/api/news/rss")
    ns = {"content": "http://purl.org/rss/1.0/modules/content/"}
    items = ET.fromstring(r.text).findall("./channel/item")
    # БД модульная: строки других тестов могут быть свежее сида — берём статью по заголовку.
    article = next(it for it in items
                   if it.findtext("title") == "Ротация печатей у родника")
    desc = article.findtext("description")
    encoded = article.findtext("content:encoded", namespaces=ns)
    assert desc and encoded
    assert len(desc) < len(encoded)
    assert "#" in encoded


def test_image_upload_and_serve():
    png = base64.b64decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    with _client() as c:
        r = c.post("/api/news/images", data={"news_id": "1"},
                   files={"file": ("p.png", png, "image/png")})
        assert r.status_code == 200
        img_id = r.json()["id"]
        assert r.json()["url"] == f"/api/news/images/{img_id}"
        g = c.get(f"/api/news/images/{img_id}")
        assert g.status_code == 200
        assert g.content == png
        assert g.headers["content-type"].startswith("image/png")
        assert c.get("/api/news/images/999999").status_code == 404
        bad = c.post("/api/news/images", data={"news_id": "1"},
                     files={"file": ("p.txt", b"hello", "text/plain")})
        assert bad.status_code == 400
        big = c.post("/api/news/images", data={"news_id": "1"},
                     files={"file": ("p.png", b"x" * 2_000_001, "image/png")})
        assert big.status_code == 400
        missing = c.post("/api/news/images", data={"news_id": "999999"},
                         files={"file": ("p.png", png, "image/png")})
        assert missing.status_code == 404