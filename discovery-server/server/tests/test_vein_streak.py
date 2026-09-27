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
