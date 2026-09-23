"""
Дополнительные тесты для discover и генераторов (имёна, цвета, слаги, авторство).

Интеграционный слой: live-HTTP против uvicorn-подпроцесса на ephemeral-порту.
Адрес — только из фикстуры `base_url` (conftest); хардкод порта/ENV запрещён.
"""

import pytest
import requests


def _discover(base, a: str, b: str, nick: str = "Игрок", device_id: str = "device-1"):
    return requests.post(
        f"{base}/discover",
        json={"a": a, "b": b, "nick": nick, "device_id": device_id},
        timeout=5,
    )


def _brew_check(base, a: str, b: str, nick: str = "Игрок", device_id: str = "device-1"):
    return requests.post(
        f"{base}/brew-check",
        json={"a": a, "b": b, "nick": nick, "device_id": device_id},
        timeout=5,
    )


def _world(base, page: int = 1):
    return requests.get(f"{base}/world?page={page}&per_page=50", timeout=5)


def _hall_of_fame(base):
    return requests.get(f"{base}/hall-of-fame", timeout=5)


class TestDiscoverNamesAndColors:
    """Тесты генерации имён и цветов."""

    def test_generated_name_is_russian(self, base_url):
        """Сгенерированное имя должно быть на русском."""
        resp = _discover(base_url, "fire", "glass", nick="Тестер", device_id="device-test")
        assert resp.status_code in (200, 201)
        name = resp.json()["discovery"]["name"]
        assert name is not None
        assert len(name) > 0
        # Проверка, что имя содержит кириллицу
        assert any(ord(c) > 1072 for c in name), f"Имя '{name}' не содержит кириллицу"

    def test_layer_calculation(self, base_url):
        """Слой должен быть max(a_layer, b_layer) + 1."""
        tests = [
            ("fire", "glass", 4),       # fire(0) + glass(3) + 1 = 4
            ("stone", "plant", 3),      # stone(1) + plant(2) + 1 = 3
            ("fire", "fire", 1),        # fire(0) + fire(0) + 1 = 1
            ("water", "water", 1),      # water(0) + water(0) + 1 = 1
            ("plant", "glass", 4),      # plant(2) + glass(3) + 1 = 4
            ("stone", "stone", 2),      # stone(1) + stone(1) + 1 = 2
            ("earth", "mountain", 3),   # earth(0) + mountain(2) + 1 = 3
        ]
        
        for a, b, expected_layer in tests:
            resp = _discover(base_url, a, b, nick="Тестер", device_id="device-test")
            assert resp.status_code in (200, 201), f"Ошибка для {a}+{b}: {resp.status_code}"
            actual_layer = resp.json()["discovery"]["layer"]
            assert actual_layer == expected_layer, f"{a}+{b}: ожидался слой {expected_layer}, получен {actual_layer}"

    def test_color_is_valid_hex(self, base_url):
        """Сгенерированный цвет должен быть валидным #RRGGBB."""
        resp = _discover(base_url, "fire", "glass", nick="Тестер", device_id="device-test")
        assert resp.status_code in (200, 201)
        color = resp.json()["discovery"]["color"]
        assert color.startswith("#")
        assert len(color) == 7
        # Валидация hex
        int(color[1:], 16)

    def test_color_is_different_from_parents(self, base_url):
        """Цвет нового элемента должен отличаться от цветов родителей."""
        parent_colors = {
            "fire": "#ff936b",
            "glass": "#93e2d3",
        }
        
        resp = _discover(base_url, "fire", "glass", nick="Тестер", device_id="device-test")
        assert resp.status_code in (200, 201)
        color = resp.json()["discovery"]["color"]
        assert color != parent_colors["fire"]
        assert color != parent_colors["glass"]

    def test_slag_format(self, base_url):
        """Слаг должен быть валидным латинским идентификатором."""
        resp = _discover(base_url, "earth", "mist", nick="Тестер", device_id="device-test")
        assert resp.status_code in (200, 201)
        slug = resp.json()["discovery"]["slug"]
        assert slug is not None
        assert len(slug) > 0
        assert slug.replace("-", "").isalnum()


class TestPlayerAuthorShip:
    """Тесты авторства."""

    def test_author_is_set(self, base_url):
        """Первооткрытие должно иметь автора."""
        resp = _discover(base_url, "air", "brick", nick="Автор", device_id="device-author")
        assert resp.status_code in (200, 201)
        assert resp.json()["discovery"]["author"] == "Автор"

    def test_second_player_gets_same_author(self, base_url):
        """Второй игрок, открывающий ту же пару, получает того же автора."""
        r1 = _discover(base_url, "water", "dust", nick="Первый", device_id="device-1")
        assert r1.status_code in (200, 201)
        author1 = r1.json()["discovery"]["author"]
        
        r2 = _discover(base_url, "water", "dust", nick="Второй", device_id="device-2")
        assert r2.status_code in (200, 201)
        author2 = r2.json()["discovery"]["author"]
        
        assert author2 == author1
        assert author2 == "Первый"


class TestWorldElements:
    """Тесты элементов в world."""

    def test_world_has_all_base_elements(self, base_url):
        """World должен содержать все базовые элементы."""
        resp = _world(base_url, 1)
        assert resp.status_code == 200
        
        elements = {e["slug"]: e for e in resp.json()["elements"]}
        
        base_slugs = ["fire", "water", "earth", "air", "steam", "stone", "clay", 
                      "dust", "spark", "mist", "brick", "sand", "glass", "plant"]
        
        for slug in base_slugs:
            assert slug in elements, f"Элемент {slug} не найден в world"

    def test_world_elements_have_name_and_color(self, base_url):
        """Все элементы в world должны иметь name и color."""
        resp = _world(base_url, 1)
        assert resp.status_code == 200
        
        for elem in resp.json()["elements"]:
            assert "name" in elem and elem["name"]
            assert "color" in elem and elem["color"]


class TestHallOfFameFormat:
    """Тесты формата hall-of-fame."""

    def test_hall_rank_order(self, base_url):
        """Ранги в hall-of-fame должны начинаться с 1."""
        resp = _hall_of_fame(base_url)
        assert resp.status_code == 200
        
        hall = resp.json()["hall"]
        if hall:
            ranks = [e["rank"] for e in hall]
            assert ranks[0] == 1
            assert ranks == list(range(1, len(ranks) + 1))

    def test_hall_count_monotonic(self, base_url):
        """Количество открытий в hall-of-fame должно быть монотонным по рангу."""
        resp = _hall_of_fame(base_url)
        assert resp.status_code == 200
        
        hall = resp.json()["hall"]
        if len(hall) > 1:
            counts = [e["count"] for e in hall]
            assert counts == sorted(counts, reverse=True)


class TestGenerationQuality:
    """Качество генерации: осмысленные русские имена без «мусорной» склейки."""

    def test_names_have_no_dashes_or_junk(self, base_url):
        pairs = [
            ("fire", "clay"), ("air", "glass"), ("water", "stone"),
            ("earth", "spark"), ("brick", "plant"), ("glass", "clay"),
            ("plant", "mountain"), ("mud", "mist"),
        ]
        for a, b in pairs:
            resp = _discover(base_url, a, b, nick="Генератор", device_id="device-gen")
            assert resp.status_code in (200, 201), f"{a}+{b}: {resp.status_code}"
            name = resp.json()["discovery"]["name"]
            assert "-" not in name, name
            assert "_" not in name, name
            assert name.strip() != "", name
            # имя — кириллическое слово (никаких «этому» и латиницы)
            assert all(ord(c) > 1039 for c in name), name

    def test_names_are_deterministic_and_order_independent(self, base_url):
        r1 = _discover(base_url, "stone", "mist", nick="А", device_id="d-a")
        r2 = _discover(base_url, "mist", "stone", nick="Б", device_id="d-b")
        assert r1.json()["discovery"]["name"] == r2.json()["discovery"]["name"]
        assert r2.json()["discovery"]["author"] == "А"

    def test_known_game_pair_resolves_without_generation(self, base_url):
        resp = _discover(base_url, "fire", "sand", nick="Кто-то", device_id="d-sand")
        assert resp.status_code in (200, 201)
        d = resp.json()["discovery"]
        assert d["slug"] == "glass"
        assert d["name"] == "Стекло"

    def test_world_contains_full_game_graph(self, base_url):
        resp = requests.get(f"{base_url}/world?page=1&per_page=100", timeout=5)
        assert resp.status_code == 200
        data = resp.json()
        assert data["total"] >= 54
        slugs = {e["slug"] for e in data["elements"]}
        for deep in ("coal", "boat", "rainbow", "person", "crystal", "desert"):
            assert deep in slugs, f"нет {deep} в world"
