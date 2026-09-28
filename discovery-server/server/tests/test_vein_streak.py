"""Task 10: streak cap (VEIN_STREAK_CAP=5) и пост-cap поведение прожилок цикла.

Паттерн тестов: fresh_unit_db (module-scoped, подменяет srv.DB_PATH) +
srv.init_db(); conn без commit — строки откатываются на close (как в
test_vein_find.py).
"""
import sqlite3
import server as srv


def test_streak_cap_reached_after_five(fresh_unit_db):
    """After 5 successful streak rolls, cap_reached=True and cap_claimed set."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    # Force 5 world-first hits (guaranteed streak)
    result = None
    for i in range(5):
        result = srv._score_vein_cycle(
            conn, cycle, cycle["tag1"], f"pair_{i}|water", "dev-cap", "alice",
            is_world_first=True,
        )
        assert result is not None
    # 5th should trigger cap
    assert result["cap_reached"] is True
    assert result["streak_added"] is True
    # Verify cap_claimed in DB
    streak = conn.execute(
        "SELECT cap_claimed, count FROM vein_streaks WHERE device_id='dev-cap' AND cycle_id=?",
        (cycle["cycle_id"],),
    ).fetchone()
    assert streak["cap_claimed"] == 1
    assert streak["count"] == 0  # reset after cap
    conn.close()


def test_no_streak_after_cap_claimed(fresh_unit_db):
    """After cap_claimed, further world-firsts don't add streak."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    # Set cap_claimed manually
    conn.execute(
        "INSERT INTO vein_streaks (device_id, cycle_id, count, cap_claimed) VALUES (?, ?, 0, 1)",
        ("dev-postcap", cycle["cycle_id"]),
    )
    conn.commit()
    result = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|postcap", "dev-postcap", "alice",
        is_world_first=True,
    )
    assert result is not None
    assert result["streak_added"] is False
    assert result["cap_reached"] is False
    assert result["streak_count"] == 0  # count stays at 0, no roll attempted
    conn.close()


# ---------------------------------------------------------------------------
# Финальное ревью (F1): проигрышный roll личного зачёта сбрасывает streak в 0
# (спека §3.1.2 «При неудачном roll streak сбрасывается в 0», §6 п.4 — reset
# ТОЛЬКО на failed roll scoring hit; wrong-tag/anti-farm ранние выходы
# streak не трогают).
# ---------------------------------------------------------------------------

def test_streak_reset_on_failed_personal_roll(fresh_unit_db, monkeypatch):
    """Выигрыши копят streak, проигрышный roll обнуляет count (в памяти и в БД)."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)

    monkeypatch.setattr(srv.random, "random", lambda: 0.0)  # roll-win
    r1 = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|roll1", "dev-roll", "alice",
        is_world_first=False,
    )
    assert r1["streak_added"] is True
    assert r1["streak_count"] == 1
    r2 = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|roll2", "dev-roll", "alice",
        is_world_first=False,
    )
    assert r2["streak_added"] is True
    assert r2["streak_count"] == 2

    monkeypatch.setattr(srv.random, "random", lambda: 1.0)  # roll-lose
    r3 = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|roll3", "dev-roll", "alice",
        is_world_first=False,
    )
    assert r3["streak_added"] is False
    assert r3["streak_count"] == 0
    streak = conn.execute(
        "SELECT count FROM vein_streaks WHERE device_id='dev-roll' AND cycle_id=?",
        (cycle["cycle_id"],),
    ).fetchone()
    assert streak["count"] == 0  # сброс и в БД, не только в ответе
    conn.close()


def test_nonscoring_returns_do_not_reset_streak(fresh_unit_db, monkeypatch):
    """§6 п.4: wrong-tag и anti-farm выходы (None) не обязаны сбрасывать streak."""
    srv.init_db()
    conn = sqlite3.connect(srv.DB_PATH)
    conn.row_factory = sqlite3.Row
    cycle = srv._ensure_active_cycle(conn)
    monkeypatch.setattr(srv.random, "random", lambda: 0.0)  # roll-win
    r = srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|keep1", "dev-keep", "alice",
        is_world_first=False,
    )
    assert r["streak_count"] == 1

    # wrong tag → None, streak не тронут
    assert srv._score_vein_cycle(
        conn, cycle, "tag-вне-цикла", "fire|keep2", "dev-keep", "alice",
        is_world_first=False,
    ) is None
    # anti-farm (пара уже засчитана) → None, streak не тронут
    assert srv._score_vein_cycle(
        conn, cycle, cycle["tag1"], "fire|keep1", "dev-keep", "alice",
        is_world_first=False,
    ) is None

    streak = conn.execute(
        "SELECT count FROM vein_streaks WHERE device_id='dev-keep' AND cycle_id=?",
        (cycle["cycle_id"],),
    ).fetchone()
    assert streak["count"] == 1  # non-reset invariant
    conn.close()
