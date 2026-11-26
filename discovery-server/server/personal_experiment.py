"""Чистые контракты персональной цели Experiment."""

from __future__ import annotations

import hashlib
from collections.abc import Mapping

from seed import norm_name


_TARGET_KINDS = frozenset({"world", "llm"})
_TARGET_STATUSES = frozenset({"active", "completed", "waiting_next_slot", "conflict"})


def target_bucket(device_id: str, cycle_week: str, sequence: int) -> int:
    value = f"{device_id}|{cycle_week}|{sequence}".encode("utf-8")
    return int(hashlib.sha256(value).hexdigest(), 16) % 100


def choose_target_kind(
    device_id: str,
    cycle_week: str,
    sequence: int,
    world_available: bool,
) -> str:
    if not world_available:
        return "llm"
    return "world" if target_bucket(device_id, cycle_week, sequence) < 80 else "llm"


def normalize_target_name(value: str) -> str:
    return norm_name(value)


def target_snapshot(row: Mapping[str, object]) -> dict[str, object]:
    kind = str(row.get("kind", ""))
    status = str(row.get("status", ""))
    if kind not in _TARGET_KINDS:
        raise ValueError("invalid personal target kind")
    if status not in _TARGET_STATUSES:
        raise ValueError("invalid personal target status")
    return {
        "id": str(row.get("id", "")),
        "kind": kind,
        "slug": str(row.get("target_slug") or ""),
        "name": str(row.get("target_name", "")),
        "hint": str(row.get("target_hint", "")),
        "status": status,
        "cycle_week": str(row.get("cycle_week", "")),
        "attempts": int(row.get("attempts", 0)),
        "successful_steps": int(row.get("successful_steps", 0)),
        "spent_ether": int(row.get("spent_ether", 0)),
        "next_eligible_week": str(row.get("next_eligible_week") or ""),
        "completed": status == "completed",
    }
