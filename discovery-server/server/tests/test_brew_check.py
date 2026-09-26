"""
Тесты для /api/brew-check и /api/discover.
Покрывает: известные пары, новые пары, race-condition, авторство.

Интеграционный слой: live-HTTP против uvicorn-подпроцесса на ephemeral-порту
(фикстура `base_url` из conftest). Хардкод адреса/ENV запрещён (T09/U8).
"""

import pytest
import requests

# Известные рецепты (из клиентского кода main.gd)
KNOWN_RECIPES = [
    ("fire", "water", "steam"),
    ("earth", "fire", "stone"),
    ("earth", "water", "clay"),
    ("air", "earth", "dust"),
    ("air", "fire", "spark"),
    ("air", "water", "mist"),
    ("clay", "fire", "brick"),
    ("air", "stone", "sand"),
    ("fire", "sand", "glass"),
    ("clay", "water", "plant"),
]


def canonical_pair_key(a: str, b: str) -> str:
    return f"{min(a, b)}|{max(a, b)}"


def _brew_check(base, a: str, b: str, nick: str = "Игрок", device_id: str = "device-1"):
    """Вызов brew-check."""
    return requests.post(
        f"{base}/brew-check",
        json={"a": a, "b": b, "nick": nick, "device_id": device_id},
        timeout=5,
    )


def _discover(base, a: str, b: str, nick: str = "Игрок", device_id: str = "device-1"):
    """Вызов discover."""
    return requests.post(
        f"{base}/discover",
        json={"a": a, "b": b, "nick": nick, "device_id": device_id},
        timeout=5,
    )


def _world(base, page: int = 1):
    """Вызов world."""
    return requests.get(f"{base}/world?page={page}&per_page=50", timeout=5)


def _hall_of_fame(base):
    """Вызов hall-of-fame."""
    return requests.get(f"{base}/hall-of-fame", timeout=5)


# ---------------------------------------------------------------------------
# Тесты
# ---------------------------------------------------------------------------

class TestBrewCheck:
    """Тесты для brew-check."""

    def test_known_pair_returns_found(self, base_url):
        """Известная пара должна вернуть found=true."""
        resp = _brew_check(base_url, "fire", "water")
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["found"] is True
        assert data["out"]["slug"] == "steam"
        assert data["out"]["name"] == "Пар"

    def test_new_unknown_pair_to_discover(self, base_url):
        """Неизвестная пара (например fire+glass) должна быть кандидатом."""
        resp = _brew_check(base_url, "fire", "glass")
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["found"] is False
        assert data["pending"] is False
        assert "кандидат" in data["message"]

    def test_pair_key_canonical(self, base_url):
        """Проверка канонизации: fire+water и water+fire → один ключ."""
        r1 = _brew_check(base_url, "fire", "water")
        r2 = _brew_check(base_url, "water", "fire")
        assert r1.json()["pair_key"] == r2.json()["pair_key"]


class TestDiscover:
    """Тесты для discover."""

    def test_new_element_created(self, base_url):
        """Новая пара должна создать новый элемент."""
        resp = _discover(base_url, "fire", "glass", nick="Анна", device_id="device-ann")
        assert resp.status_code in (200, 201)
        data = resp.json()
        assert data["ok"] is True
        assert data["already_known"] is False
        assert data["discovery"]["a"] == "fire"
        assert data["discovery"]["b"] == "glass"
        assert data["discovery"]["author"] == "Анна"
        assert data["discovery"]["name"] is not None
        assert data["discovery"]["color"] is not None
        assert data["discovery"]["layer"] == 4  # fire(0)+glass(3)+1=4

    def test_same_pair_rediscovers_existing(self, base_url):
        """Повторное discover той же пары → тот же элемент."""
        r1 = _discover(base_url, "water", "sand", nick="Варг", device_id="device-varg")
        assert r1.status_code in (200, 201)
        d1 = r1.json()["discovery"]
        
        r2 = _discover(base_url, "water", "sand", nick="Иван", device_id="device-ivan")
        assert r2.status_code in (200, 201)
        d2 = r2.json()["discovery"]
        
        # Тот же slug, тот же author
        assert d1["slug"] == d2["slug"]
        assert d2["author"] == "Варг"  # Второй игрок получает того же автора

    def test_self_pair_valid(self, base_url):
        """Пара X+X допустима как кандидат."""
        resp = _brew_check(base_url, "fire", "fire")
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["found"] is False
        assert data["pending"] is False

    def test_self_pair_discover(self, base_url):
        """Дисклейм X+X должен создать элемент."""
        resp = _discover(base_url, "spark", "spark", nick="Лена", device_id="device-lena")
        assert resp.status_code in (200, 201)
        data = resp.json()
        assert data["ok"] is True
        assert data["discovery"]["a"] == "spark"
        assert data["discovery"]["b"] == "spark"


class TestUniqueness:
    """Тесты уникальности имен и слагов."""

    def test_unique_names(self, base_url):
        """Несколько новых элементов должны иметь уникальные имена."""
        discovered = []
        pairs = [
            ("fire", "glass"),
            ("fire", "sand"),
            ("earth", "mist"),
            ("air", "clay"),
            ("water", "brick"),
            ("earth", "glass"),
        ]
        
        for a, b in pairs:
            resp = _discover(base_url, a, b, nick="Тестер", device_id="device-test")
            if resp.status_code in (200, 201):
                d = resp.json()["discovery"]
                discovered.append((d["name"], d["slug"]))
        
        # Проверка уникальности имён и слагов
        names = [n for n, s in discovered]
        slugs = [s for n, s in discovered]
        assert len(set(names)) == len(names), f"Дубликат имени: {names}"
        assert len(set(slugs)) == len(slugs), f"Дубликат слага: {slugs}"

    def test_slug_uniqueness(self, base_url):
        """Слаги должны быть уникальными."""
        pairs = [
            ("fire", "clay"),
            ("fire", "mist"),
            ("earth", "spark"),
        ]
        
        slugs = []
        for a, b in pairs:
            resp = _discover(base_url, a, b, nick="Тестер", device_id="device-test")
            if resp.status_code in (200, 201):
                slugs.append(resp.json()["discovery"]["slug"])
        
        assert len(set(slugs)) == len(slugs)


class TestRaceCondition:
    """Тесты race-condition при параллельных запросах.

    Актуальная семантика (U5/U6, T09-ревизия ожиданий): проигравший гонку
    получает 409 («пара в обработке» — живая блокировка) либо 200 с уже
    существующим открытием, если победитель успел зафиксировать пару.
    Раньше тест требовал «оба 200» — до атомарной блокировки.
    """

    def test_parallel_requests_one_result(self, base_url):
        """
        Два параллельных запроса на одну новую пару → один элемент, один автор.
        """
        import concurrent.futures
        
        def make_discover(nick, device):
            return _discover(base_url, "fire", "brick", nick=nick, device_id=device)
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(make_discover, "Игрок1", "device-1"),
                executor.submit(make_discover, "Игрок2", "device-2"),
            ]
            results = [f.result() for f in futures]
        
        # Каждый запрос: успешный discovery или 409-«в обработке» (U5/U6)
        for r in results:
            assert r.status_code in (200, 201, 409), f"Неожиданный статус: {r.status_code}"
        
        ok = [r for r in results if r.status_code in (200, 201)]
        assert ok, "Хотя бы один запрос должен вернуть 200"
        
        # Все успешные видят один и тот же элемент и одного автора
        d1 = ok[0].json()["discovery"]
        for r in ok[1:]:
            d2 = r.json()["discovery"]
            assert d1["slug"] == d2["slug"], "Разные элементы при параллельных запросах"
            assert d1["name"] == d2["name"]
            assert d1["color"] == d2["color"]
            assert d2["author"] == d1["author"]


class TestHallOfFame:
    """Тесты для hall-of-fame."""

    def test_hall_has_players(self, base_url):
        """Hall-of-fame должен возвращать список с рангами."""
        resp = _hall_of_fame(base_url)
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert "hall" in data
        
        hall = data["hall"]
        # Если есть игроки с открытиями, проверяем структуру
        if hall:
            for entry in hall:
                assert "rank" in entry
                assert "nick" in entry
                assert "count" in entry


class TestWorldEndpoint:
    """Тесты для world endpoint."""

    def test_world_pagination(self, base_url):
        """World должен поддерживать пагинацию и возвращать name/color."""
        resp = _world(base_url, 1)
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert "elements" in data
        assert data["page"] == 1
        assert data["per_page"] == 50
        
        for elem in data["elements"]:
            assert "name" in elem and elem["name"] is not None
            assert "color" in elem and elem["color"] is not None

    def test_world_total_count(self, base_url):
        """Total должен быть >= количеству базовых элементов."""
        resp = _world(base_url, 1)
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] >= 14  # 4 стихии + производные


class TestPlayerRegistration:
    """Тесты для регистрации игрока."""

    def test_register_unique_device(self, base_url):
        """Регистрация игрока с уникальным device_id."""
        resp = requests.post(
            f"{base_url}/player/register",
            json={"a": "fire", "b": "water", "nick": "НовыйИгрок", "device_id": "device-new"},
            timeout=5,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["nick"] == "НовыйИгрок"

    def test_register_duplicate_device_keeps_nick(self, base_url):
        """T02: повторная регистрация того же device_id НЕ переименовывает —
        возвращается канонический ник; смена ника только через POST /api/me."""
        resp = requests.post(
            f"{base_url}/player/register",
            json={"a": "fire", "b": "water", "nick": "Игрок1", "device_id": "device-dup"},
            timeout=5,
        )
        assert resp.status_code == 200
        assert resp.json()["nick"] == "Игрок1"
        
        resp2 = requests.post(
            f"{base_url}/player/register",
            json={"a": "fire", "b": "water", "nick": "Игрок2", "device_id": "device-dup"},
            timeout=5,
        )
        assert resp2.status_code == 200
        # канонический ник устройства — первый, а не «заявка» из запроса
        assert resp2.json()["nick"] == "Игрок1"
        me = requests.get(f"{base_url}/me", params={"device_id": "device-dup"}, timeout=5).json()
        assert me["nick"] == "Игрок1"
