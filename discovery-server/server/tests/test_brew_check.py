"""
Тесты для /api/brew-check и /api/discover.
Покрывает: известные пары, новые пары, race-condition, авторство.
"""

import pytest
import requests

# API-константы — берутся из conftest.py
BASE_URL = "http://localhost:8080/api"

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


def _brew_check(a: str, b: str, nick: str = "Игрок", device_id: str = "device-1"):
    """Вызов brew-check."""
    return requests.post(
        f"{BASE_URL}/brew-check",
        json={"a": a, "b": b, "nick": nick, "device_id": device_id},
        timeout=5,
    )


def _discover(a: str, b: str, nick: str = "Игрок", device_id: str = "device-1"):
    """Вызов discover."""
    return requests.post(
        f"{BASE_URL}/discover",
        json={"a": a, "b": b, "nick": nick, "device_id": device_id},
        timeout=5,
    )


def _world(page: int = 1):
    """Вызов world."""
    return requests.get(f"{BASE_URL}/world?page={page}&per_page=50", timeout=5)


def _hall_of_fame():
    """Вызов hall-of-fame."""
    return requests.get(f"{BASE_URL}/hall-of-fame", timeout=5)


# ---------------------------------------------------------------------------
# Тесты
# ---------------------------------------------------------------------------

class TestBrewCheck:
    """Тесты для brew-check."""

    def test_known_pair_returns_found(self, server):
        """Известная пара должна вернуть found=true."""
        resp = _brew_check("fire", "water")
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["found"] is True
        assert data["out"]["slug"] == "steam"
        assert data["out"]["name"] == "Пар"

    def test_new_unknown_pair_to_discover(self, server):
        """Неизвестная пара (например fire+glass) должна быть кандидатом."""
        resp = _brew_check("fire", "glass")
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["found"] is False
        assert data["pending"] is False
        assert "кандидат" in data["message"]

    def test_pair_key_canonical(self, server):
        """Проверка канонизации: fire+water и water+fire → один ключ."""
        r1 = _brew_check("fire", "water")
        r2 = _brew_check("water", "fire")
        assert r1.json()["pair_key"] == r2.json()["pair_key"]


class TestDiscover:
    """Тесты для discover."""

    def test_new_element_created(self, server):
        """Новая пара должна создать новый элемент."""
        resp = _discover("fire", "glass", nick="Анна", device_id="device-ann")
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

    def test_same_pair_rediscovers_existing(self, server):
        """Повторное discover той же пары → тот же элемент."""
        r1 = _discover("water", "sand", nick="Варг", device_id="device-varg")
        assert r1.status_code in (200, 201)
        d1 = r1.json()["discovery"]
        
        r2 = _discover("water", "sand", nick="Иван", device_id="device-ivan")
        assert r2.status_code in (200, 201)
        d2 = r2.json()["discovery"]
        
        # Тот же slug, тот же author
        assert d1["slug"] == d2["slug"]
        assert d2["author"] == "Варг"  # Второй игрок получает того же автора

    def test_self_pair_valid(self, server):
        """Пара X+X допустима как кандидат."""
        resp = _brew_check("fire", "fire")
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["found"] is False
        assert data["pending"] is False

    def test_self_pair_discover(self, server):
        """Дисклейм X+X должен создать элемент."""
        resp = _discover("spark", "spark", nick="Лена", device_id="device-lena")
        assert resp.status_code in (200, 201)
        data = resp.json()
        assert data["ok"] is True
        assert data["discovery"]["a"] == "spark"
        assert data["discovery"]["b"] == "spark"


class TestUniqueness:
    """Тесты уникальности имен и слагов."""

    def test_unique_names(self, server):
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
            resp = _discover(a, b, nick="Тестер", device_id="device-test")
            if resp.status_code in (200, 201):
                d = resp.json()["discovery"]
                discovered.append((d["name"], d["slug"]))
        
        # Проверка уникальности имён и слагов
        names = [n for n, s in discovered]
        slugs = [s for n, s in discovered]
        assert len(set(names)) == len(names), f"Дубликат имени: {names}"
        assert len(set(slugs)) == len(slugs), f"Дубликат слага: {slugs}"

    def test_slug_uniqueness(self, server):
        """Слаги должны быть уникальными."""
        pairs = [
            ("fire", "clay"),
            ("fire", "mist"),
            ("earth", "spark"),
        ]
        
        slugs = []
        for a, b in pairs:
            resp = _discover(a, b, nick="Тестер", device_id="device-test")
            if resp.status_code in (200, 201):
                slugs.append(resp.json()["discovery"]["slug"])
        
        assert len(set(slugs)) == len(slugs)


class TestRaceCondition:
    """Тесты race-condition при параллельных запросах."""

    def test_parallel_requests_one_result(self, server):
        """
        Два параллельных запроса на одну новую пару → один элемент, один автор.
        """
        import concurrent.futures
        
        def make_discover(nick, device):
            return _discover("fire", "brick", nick=nick, device_id=device)
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(make_discover, "Игрок1", "device-1"),
                executor.submit(make_discover, "Игрок2", "device-2"),
            ]
            results = [f.result() for f in futures]
        
        # Оба запроса должны завершиться успешно
        for r in results:
            assert r.status_code in (200, 201), f"Ошибка: {r.status_code}"
        
        # Оба должны иметь одинаковый discovery (один элемент)
        d1 = results[0].json()["discovery"]
        d2 = results[1].json()["discovery"]
        
        assert d1["slug"] == d2["slug"], "Разные элементы при параллельных запросах"
        assert d1["name"] == d2["name"]
        assert d1["color"] == d2["color"]
        assert d2["author"] == d1["author"]


class TestHallOfFame:
    """Тесты для hall-of-fame."""

    def test_hall_has_players(self, server):
        """Hall-of-fame должен возвращать список с рангами."""
        resp = _hall_of_fame()
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

    def test_world_pagination(self, server):
        """World должен поддерживать пагинацию и возвращать name/color."""
        resp = _world(1)
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert "elements" in data
        assert data["page"] == 1
        assert data["per_page"] == 50
        
        for elem in data["elements"]:
            assert "name" in elem and elem["name"] is not None
            assert "color" in elem and elem["color"] is not None

    def test_world_total_count(self, server):
        """Total должен быть >= количеству базовых элементов."""
        resp = _world(1)
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] >= 14  # 4 стихии + производные


class TestPlayerRegistration:
    """Тесты для регистрации игрока."""

    def test_register_unique_device(self, server):
        """Регистрация игрока с уникальным device_id."""
        resp = requests.post(
            f"{BASE_URL}/player/register",
            json={"a": "fire", "b": "water", "nick": "НовыйИгрок", "device_id": "device-new"},
            timeout=5,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["ok"] is True
        assert data["nick"] == "НовыйИгрок"

    def test_register_duplicate_device_updates_nick(self, server):
        """Повторная регистрация с тем же device_id обновляет ник."""
        resp = requests.post(
            f"{BASE_URL}/player/register",
            json={"a": "fire", "b": "water", "nick": "Игрок1", "device_id": "device-dup"},
            timeout=5,
        )
        assert resp.status_code == 200
        
        resp2 = requests.post(
            f"{BASE_URL}/player/register",
            json={"a": "fire", "b": "water", "nick": "Игрок2", "device_id": "device-dup"},
            timeout=5,
        )
        assert resp2.status_code == 200
        assert resp2.json()["nick"] == "Игрок2"
