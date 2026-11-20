#!/usr/bin/env python3
import argparse
import html
import json
import math
from pathlib import Path


PHASE_LABELS = {
    "bootstrap/catalog": "Каталог",
    "discovery": "Discovery",
    "idle": "Idle-экономика",
    "retort": "Retort",
    "sigil": "Сигилы",
    "prestige": "Prestige",
    "post_prestige_discovery": "После prestige",
    "proof": "Финальные proofs",
}


def esc(value):
    return html.escape(str(value), quote=True)


def number(value, digits=0):
    try:
        value = float(value)
    except (TypeError, ValueError):
        return "—"
    if not math.isfinite(value):
        return "—"
    if digits == 0:
        return f"{value:,.0f}".replace(",", " ")
    return f"{value:,.{digits}f}".replace(",", " ")


def seconds(value):
    try:
        value = max(0.0, float(value))
    except (TypeError, ValueError):
        return "—"
    if value < 60:
        return f"{number(value, 1)} с"
    if value < 3600:
        return f"{number(value / 60, 1)} мин"
    if value < 86400:
        return f"{number(value / 3600, 1)} ч"
    return f"{number(value / 86400, 1)} дн"


def percent(value, total):
    try:
        value = float(value)
        total = float(total)
        if total <= 0:
            return 0.0
        return max(0.0, min(100.0, value / total * 100.0))
    except (TypeError, ValueError):
        return 0.0


def state_class(state):
    return {
        "pass": "pass",
        "fail": "fail",
        "incomplete": "warn",
    }.get(str(state), "muted")


def state_label(state):
    return {
        "pass": "PASS",
        "fail": "FAIL",
        "incomplete": "INCOMPLETE",
    }.get(str(state), str(state or "нет данных").upper())


def metric(report, key, default="—"):
    return report.get("metrics", {}).get(key, default)


def phase_rows(report):
    phases = report.get("phases", {})
    rows = []
    for key, label in PHASE_LABELS.items():
        phase = phases.get(key, {})
        completed = phase.get("completed")
        total = phase.get("total")
        ratio = percent(completed, total) if completed is not None and total else (100.0 if phase.get("state") == "pass" else 0.0)
        rows.append({
            "key": key,
            "label": label,
            "state": phase.get("state", "unknown"),
            "reason": phase.get("reason", ""),
            "ratio": ratio,
            "completed": completed,
            "total": total,
        })
    return rows


def kpi(title, value, detail, accent="violet"):
    return f'''<article class="kpi {accent}">
      <div class="kpi-label">{esc(title)}</div>
      <div class="kpi-value">{value}</div>
      <div class="kpi-detail">{esc(detail)}</div>
    </article>'''


def render_phase_rows(report):
    rows = []
    for row in phase_rows(report):
        detail = row["reason"] or (f'{number(row["completed"])} / {number(row["total"])}' if row["completed"] is not None and row["total"] is not None else "проверено")
        rows.append(f'''<div class="phase-row">
          <div class="phase-name"><span class="status-dot {state_class(row["state"])}"></span><strong>{esc(row["label"])}</strong><small>{esc(detail)}</small></div>
          <div class="phase-track"><span class="phase-fill {state_class(row["state"])}" style="width:{row["ratio"]:.2f}%"></span></div>
          <div class="phase-state {state_class(row["state"])}">{esc(state_label(row["state"]))}</div>
        </div>''')
    return "\n".join(rows)


def render_proof_rows(report):
    metrics = report.get("metrics", {})
    proofs = [
        ("Prestige reset и награда", "prestige_proof"),
        ("Save / load", "reload_proof"),
        ("Replay idempotence", "replay_proof"),
        ("Retort queue", "retort_queue_proof"),
    ]
    rows = []
    for label, key in proofs:
        value = metrics.get(key) is True
        rows.append(f'''<div class="proof-row"><span class="proof-icon {"ok" if value else "bad"}">{"✓" if value else "×"}</span><span>{esc(label)}</span><strong>{"подтверждено" if value else "не подтверждено"}</strong></div>''')
    return "\n".join(rows)


def render_calibration(summary):
    if not summary:
        return '<div class="empty">Для этого запуска calibration summary не приложен.</div>'
    trials = summary.get("trials", [])
    trial_rows = []
    for trial in trials:
        objective = " · ".join(number(item, 2) for item in trial.get("objective", [])) or "—"
        trial_rows.append(f'''<tr><td>Trial {esc(trial.get("trial", "—"))}</td><td><span class="pill {"pass" if trial.get("accepted") else "fail"}">{"accepted" if trial.get("accepted") else "rejected"}</span></td><td class="mono">{esc(objective)}</td><td>{esc(trial.get("reason", "—"))}</td></tr>''')
    parameters = summary.get("changed_parameters", {})
    parameter_rows = "".join(f'<span class="parameter"><b>{esc(key)}</b><em>{esc(number(value, 2))}</em></span>' for key, value in parameters.items()) or '<span class="muted">Параметры не изменялись</span>'
    return f'''<div class="calibration-grid">
      <div class="calibration-score"><div class="eyebrow">Результат поиска</div><strong>{esc(summary.get("stop_reason", "—"))}</strong><p>{number(summary.get("accepted_trials", 0))} accepted · {number(summary.get("rejected_trials", 0))} rejected</p></div>
      <div><div class="eyebrow">Изменённые параметры</div><div class="parameters">{parameter_rows}</div></div>
    </div>
    <div class="table-wrap"><table><thead><tr><th>Trial</th><th>Статус</th><th>Objective</th><th>Причина</th></tr></thead><tbody>{"".join(trial_rows) or '<tr><td colspan="4">Нет trial-данных</td></tr>'}</tbody></table></div>'''


def render_report(report, summary=None):
    if isinstance(report, dict) and report.get("comparison") == 1 and isinstance(report.get("reports"), list):
        return render_comparison(report)
    if isinstance(report, dict) and report.get("scenario") == 1 and isinstance(report.get("segments"), list):
        return render_scenario(report)
    summary = summary or {}
    verdict = report.get("verdict", report.get("state", "unknown"))
    metrics = report.get("metrics", {})
    time_data = report.get("time", {})
    ledger = report.get("ledger", {})
    counters = ledger.get("counters", {})
    total_time = time_data.get("simulated_real_seconds", metrics.get("simulated_real_seconds", 0))
    active = time_data.get("active_seconds", 0)
    offline = time_data.get("offline_seconds", max(0, float(total_time or 0) - float(active or 0)))
    offline_share = percent(offline, total_time)
    local = metrics.get("local_elements", {})
    recipes = metrics.get("recipes", {})
    profile = report.get("profile", {})
    scope = report.get("scope", {})
    ether = ledger.get("resources", {})
    generated = report.get("generated_at", report.get("updated_at", "локальный отчёт"))

    html_doc = f'''<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Alchemist’s Loop — progression report</title>
<style>
:root{{--ink:#f5f1e8;--muted:#aaa49b;--paper:#17151d;--paper-2:#211d2a;--line:#3b3345;--violet:#b994ff;--violet-2:#7651b8;--mint:#65d7b0;--gold:#e9bd70;--red:#ff747e;--shadow:0 24px 80px #08070d99}}
*{{box-sizing:border-box}}body{{margin:0;background:#0e0c12;color:var(--ink);font:14px/1.5 Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}}body:before{{content:"";position:fixed;inset:0;pointer-events:none;background:radial-gradient(circle at 15% 0%,#6c48a522,transparent 35%),radial-gradient(circle at 100% 10%,#bd7b2d14,transparent 30%);z-index:-1}}main{{max-width:1240px;margin:0 auto;padding:42px 26px 70px}}.hero{{display:flex;justify-content:space-between;gap:30px;align-items:flex-end;margin-bottom:28px}}.eyebrow{{font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--muted);font-weight:700}}h1{{font:600 clamp(32px,5vw,58px)/1.02 Georgia,serif;letter-spacing:-.045em;margin:8px 0 12px}}h1 span{{color:var(--violet)}}.sub{{color:var(--muted);max-width:670px;margin:0;font-size:15px}}.verdict{{min-width:190px;border:1px solid var(--line);background:linear-gradient(145deg,#272032,#18141f);padding:18px 20px;border-radius:18px;box-shadow:var(--shadow)}}.verdict strong{{display:block;font-size:24px;color:var(--mint);letter-spacing:.08em}}.verdict.fail strong{{color:var(--red)}}.verdict.warn strong{{color:var(--gold)}}.verdict small{{color:var(--muted)}}.kpis{{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:12px}}.kpi,.panel{{background:linear-gradient(145deg,#201b29ee,#15131bee);border:1px solid var(--line);border-radius:18px;box-shadow:var(--shadow)}}.kpi{{padding:18px 19px;min-height:142px;position:relative;overflow:hidden}}.kpi:after{{content:"";position:absolute;width:100px;height:100px;border-radius:50%;right:-34px;bottom:-48px;background:var(--violet);opacity:.12;filter:blur(2px)}}.kpi.mint:after{{background:var(--mint)}}.kpi.gold:after{{background:var(--gold)}}.kpi-label{{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.08em}}.kpi-value{{font:600 30px/1.1 Georgia,serif;margin:20px 0 5px;color:var(--violet)}}.mint .kpi-value{{color:var(--mint)}}.gold .kpi-value{{color:var(--gold)}}.kpi-detail{{color:var(--muted);font-size:12px}}.layout{{display:grid;grid-template-columns:1.35fr .65fr;gap:12px;margin-top:12px}}.panel{{padding:22px}}.panel h2{{font:600 24px/1.1 Georgia,serif;margin:0 0 5px}}.panel-intro{{color:var(--muted);margin:0 0 18px;font-size:13px}}.section-head{{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:16px}}.section-head .eyebrow{{color:var(--violet)}}.phase-row{{display:grid;grid-template-columns:190px 1fr 90px;gap:14px;align-items:center;padding:12px 0;border-bottom:1px solid #332d3b}}.phase-row:last-child{{border-bottom:0}}.phase-name{{display:grid;grid-template-columns:10px 1fr;column-gap:8px;align-items:center}}.phase-name small{{grid-column:2;color:var(--muted);font-size:11px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}}.status-dot{{width:8px;height:8px;border-radius:50%;background:var(--muted)}}.status-dot.pass{{background:var(--mint);box-shadow:0 0 12px #65d7b099}}.status-dot.fail{{background:var(--red)}}.phase-track{{height:8px;border-radius:20px;background:#332c3c;overflow:hidden}}.phase-fill{{display:block;height:100%;border-radius:20px;background:var(--violet)}}.phase-fill.pass{{background:linear-gradient(90deg,var(--violet-2),var(--violet))}}.phase-fill.fail{{background:var(--red)}}.phase-state{{font-size:11px;text-align:right;color:var(--muted);letter-spacing:.08em}}.phase-state.pass{{color:var(--mint)}}.phase-state.fail{{color:var(--red)}}.phase-state.warn{{color:var(--gold)}}.time-card{{display:flex;gap:20px;align-items:center}}.donut{{width:148px;height:148px;border-radius:50%;background:conic-gradient(var(--violet) 0 {offline_share:.2f}%,#393143 {offline_share:.2f}% 100%);display:grid;place-items:center;flex:0 0 auto}}.donut:after{{content:"";width:98px;height:98px;border-radius:50%;background:var(--paper);box-shadow:inset 0 0 20px #0006}}.donut-label{{position:absolute;text-align:center;z-index:1;font:600 23px Georgia,serif;color:var(--violet)}}.donut-wrap{{position:relative}}.legend{{display:grid;gap:13px;flex:1}}.legend-row{{display:flex;justify-content:space-between;gap:12px;border-bottom:1px solid #332d3b;padding-bottom:8px}}.legend-row span:first-child:before{{content:"";display:inline-block;width:8px;height:8px;border-radius:50%;background:var(--violet);margin-right:8px}}.legend-row.offline span:first-child:before{{background:#393143}}.legend-row span:last-child{{font-weight:700}}.metrics-grid{{display:grid;grid-template-columns:repeat(2,1fr);gap:10px}}.metric-line{{padding:12px 13px;background:#16131d;border:1px solid #342d3d;border-radius:12px}}.metric-line span{{display:block;color:var(--muted);font-size:12px}}.metric-line strong{{display:block;font-size:17px;margin-top:4px}}.proofs{{display:grid;gap:2px}}.proof-row{{display:grid;grid-template-columns:28px 1fr auto;gap:10px;align-items:center;padding:12px 0;border-bottom:1px solid #332d3b}}.proof-row:last-child{{border:0}}.proof-row strong{{font-size:11px;color:var(--mint);font-weight:600}}.proof-icon{{width:22px;height:22px;border-radius:50%;display:grid;place-items:center;font-weight:800}}.proof-icon.ok{{background:#65d7b01c;color:var(--mint)}}.proof-icon.bad{{background:#ff747e1c;color:var(--red)}}.table-wrap{{overflow:auto;margin-top:18px}}table{{width:100%;border-collapse:collapse;font-size:13px}}th{{text-align:left;color:var(--muted);font-size:11px;letter-spacing:.08em;text-transform:uppercase;font-weight:600;border-bottom:1px solid var(--line);padding:10px}}td{{border-bottom:1px solid #332d3b;padding:11px 10px}}.mono,.parameter b{{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12px}}.pill{{padding:3px 8px;border-radius:20px;font-size:11px;font-weight:700;letter-spacing:.05em}}.pill.pass{{background:#65d7b01c;color:var(--mint)}}.pill.fail{{background:#ff747e1c;color:var(--red)}}.calibration-grid{{display:grid;grid-template-columns:.6fr 1.4fr;gap:24px;border-bottom:1px solid var(--line);padding-bottom:18px}}.calibration-score strong{{display:block;color:var(--gold);font:600 26px Georgia,serif;margin-top:8px}}.calibration-score p{{color:var(--muted);margin:6px 0 0}}.parameters{{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}}.parameter{{display:inline-flex;gap:8px;align-items:center;padding:8px 10px;background:#16131d;border:1px solid #3d334a;border-radius:10px}}.parameter em{{font-style:normal;color:var(--gold);font-family:ui-monospace,monospace;font-size:12px}}.empty,.muted{{color:var(--muted)}}.scope{{color:var(--muted);font-size:13px;margin:0}}.footer{{display:flex;justify-content:space-between;gap:20px;color:#77727b;font-size:11px;margin-top:18px;padding:0 4px}}@media(max-width:900px){{.kpis{{grid-template-columns:repeat(2,1fr)}}.layout{{grid-template-columns:1fr}}}}@media(max-width:620px){{main{{padding:24px 14px 50px}}.hero{{display:block}}.verdict{{margin-top:20px}}.kpis{{grid-template-columns:1fr 1fr}}.kpi{{min-height:125px;padding:14px}}.kpi-value{{font-size:23px;margin-top:14px}}.phase-row{{grid-template-columns:1fr 70px;gap:8px}}.phase-track{{grid-column:1 / -1;grid-row:2}}.phase-state{{grid-column:2;grid-row:1}}.time-card{{display:block}}.donut-wrap{{width:148px;margin:0 auto 20px}}.calibration-grid{{grid-template-columns:1fr}}.footer{{display:block}}}}
</style>
</head>
<body><main>
<header class="hero"><div><div class="eyebrow">ПОЛНЫЙ ПРОГОН · local deterministic run</div><h1>Alchemist’s <span>Loop</span></h1><p class="sub">Полный отчёт idle-прогрессии: каталог, discovery, экономика, Retort, сигилы, prestige и доказательства сохранения состояния.</p></div><div class="verdict {state_class(verdict)}"><div class="eyebrow">Итог прогона</div><strong>{esc(state_label(verdict))}</strong><small>profile: {esc(profile.get("name", "—"))}</small></div></header>
<section class="kpis">
{kpi("Виртуальное время", seconds(total_time), f'{number(total_time)} секунд · {number(offline_share, 1)}% offline', "violet")}
{kpi("Активное время игрока", seconds(metrics.get("active_player_seconds", time_data.get("active_player_seconds", 0))), "не включая idle-ожидание", "mint")}
{kpi("Локальный каталог", f'{number(local.get("completed", 0))} / {number(local.get("total", 0))}', "достижимые вещества", "gold")}
{kpi("Рецепты", f'{number(recipes.get("completed", 0))} / {number(recipes.get("total", 0))}', "локальная production-сетка", "violet")}
</section>
<div class="layout"><section class="panel"><div class="section-head"><div><div class="eyebrow">Pipeline</div><h2>Фазы прогрессии</h2></div><span class="eyebrow">{number(sum(1 for r in phase_rows(report) if r["state"] == "pass"))} / {number(len(PHASE_LABELS))} pass</span></div><p class="panel-intro">Каждая фаза проходит через production API и фиксирует собственное состояние, а не только общий exit code.</p>{render_phase_rows(report)}</section>
<section class="panel"><div class="section-head"><div><div class="eyebrow">Idle split</div><h2>Где прошло время</h2></div></div><div class="time-card"><div class="donut-wrap"><div class="donut"></div><div class="donut-label">{number(offline_share, 0)}%</div></div><div class="legend"><div class="legend-row"><span>Active simulation</span><span>{seconds(active)}</span></div><div class="legend-row offline"><span>Offline idle</span><span>{seconds(offline)}</span></div><div class="legend-row"><span>Всего</span><span>{seconds(total_time)}</span></div></div></div><div class="section-head" style="margin-top:28px"><div><div class="eyebrow">Proof gates</div><h2>Доказательства</h2></div></div><div class="proofs">{render_proof_rows(report)}</div></section></div>
<div class="layout"><section class="panel"><div class="section-head"><div><div class="eyebrow">Economy</div><h2>Баланс и прогресс</h2><p class="panel-intro">Покрытие каталога и ключевые точки idle-экономики</p></div></div><div class="metrics-grid"><div class="metric-line"><span>Ether earned</span><strong>{number(ether.get("ether_earned", 0))}</strong></div><div class="metric-line"><span>Ether spent</span><strong>{number(ether.get("ether_spent", 0))}</strong></div><div class="metric-line"><span>First Workshop</span><strong>{seconds(metric(report, "first_workshop_seconds"))}</strong></div><div class="metric-line"><span>First Retort</span><strong>{seconds(metric(report, "first_retort_seconds"))}</strong></div><div class="metric-line"><span>Brews / distillations</span><strong>{number(counters.get("brews", 0))} / {number(counters.get("distillations", 0))}</strong></div><div class="metric-line"><span>Blends / sigils</span><strong>{number(counters.get("blends", 0))} / {number(counters.get("sigils_crafted", 0))}</strong></div><div class="metric-line"><span>Ether deficit</span><strong>{number(metric(report, "ether_deficit_at_completion", 0))}</strong></div><div class="metric-line"><span>Unexplained resources</span><strong>{number(metric(report, "unexplained_resources", 0))}</strong></div></div></section>
<section class="panel"><div class="section-head"><div><div class="eyebrow">Run identity</div><h2>Контракт</h2></div></div><div class="metric-line"><span>Profile</span><strong>{esc(profile.get("name", "—"))}</strong></div><div class="metric-line" style="margin-top:10px"><span>Seed</span><strong class="mono">{esc(report.get("seed", "—"))}</strong></div><div class="metric-line" style="margin-top:10px"><span>Operations</span><strong>{number(ledger.get("operation_count", 0))}</strong></div><p class="scope" style="margin-top:15px">{esc(scope.get("balance_timing", "Отчёт построен из переданного JSON-артефакта."))}</p></section></div>
<section class="panel" style="margin-top:12px"><div class="section-head"><div><div class="eyebrow">Calibration</div><h2>Калибровка</h2></div><span class="eyebrow">{esc(summary.get("best_profile_hash", "нет summary"))}</span></div>{render_calibration(summary)}</section>
<details class="panel" style="margin-top:12px"><summary>Технические идентификаторы</summary><div class="metrics-grid" style="margin-top:16px"><div class="metric-line"><span>Catalog hash</span><strong class="mono">{esc(report.get("catalog_hash", "—"))}</strong></div><div class="metric-line"><span>Profile hash</span><strong class="mono">{esc(profile.get("hash", "—"))}</strong></div><div class="metric-line"><span>Runner commit</span><strong class="mono">{esc(report.get("runner_commit", "—"))}</strong></div><div class="metric-line"><span>Generated</span><strong>{esc(generated)}</strong></div></div></details>
<footer class="footer"><span>Generated locally from progression JSON · no external assets</span><span>Alchemist’s Loop · report schema {esc(report.get("schema", "—"))}</span></footer>
</main></body></html>'''
    return html_doc


SCENARIO_CSS = """
:root{--ink:#f5f1e8;--muted:#aaa49b;--paper:#17151d;--line:#3b3345;--violet:#b994ff;--violet-2:#7651b8;--mint:#65d7b0;--gold:#e9bd70;--red:#ff747e;--shadow:0 24px 80px #08070d99}
*{box-sizing:border-box}body{margin:0;background:#0e0c12;color:var(--ink);font:14px/1.5 Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}body:before{content:"";position:fixed;inset:0;pointer-events:none;background:radial-gradient(circle at 15% 0%,#6c48a522,transparent 35%),radial-gradient(circle at 100% 10%,#bd7b2d14,transparent 30%);z-index:-1}main{max-width:1240px;margin:0 auto;padding:42px 26px 70px}
.hero{display:flex;justify-content:space-between;gap:30px;align-items:flex-end;margin-bottom:28px}.eyebrow{font-size:11px;letter-spacing:.16em;text-transform:uppercase;color:var(--muted);font-weight:700}h1{font:600 clamp(32px,5vw,58px)/1.02 Georgia,serif;letter-spacing:-.045em;margin:8px 0 12px}h1 span{color:var(--violet)}.sub{color:var(--muted);max-width:670px;margin:0;font-size:15px}
.verdict{min-width:190px;border:1px solid var(--line);background:linear-gradient(145deg,#272032,#18141f);padding:18px 20px;border-radius:18px;box-shadow:var(--shadow)}.verdict strong{display:block;font-size:24px;color:var(--mint);letter-spacing:.08em}.verdict.fail strong{color:var(--red)}.verdict.warn strong{color:var(--gold)}.verdict small{color:var(--muted)}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-bottom:12px}.kpi,.panel{background:linear-gradient(145deg,#201b29ee,#15131bee);border:1px solid var(--line);border-radius:18px;box-shadow:var(--shadow)}.kpi{padding:18px 19px;min-height:132px}.kpi-label{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.08em}.kpi-value{font:600 28px/1.1 Georgia,serif;margin:18px 0 5px;color:var(--violet)}.kpi.mint .kpi-value{color:var(--mint)}.kpi.gold .kpi-value{color:var(--gold)}.kpi-detail{color:var(--muted);font-size:12px}
.panel{padding:22px;margin-top:12px}.panel h2{font:600 24px/1.1 Georgia,serif;margin:0 0 5px}.panel-intro{color:var(--muted);margin:0 0 18px;font-size:13px}.section-head{display:flex;justify-content:space-between;align-items:baseline;margin-bottom:16px}.section-head .eyebrow{color:var(--violet)}
.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;font-size:13px}th{text-align:left;color:var(--muted);font-size:11px;letter-spacing:.08em;text-transform:uppercase;font-weight:600;border-bottom:1px solid var(--line);padding:10px}td{border-bottom:1px solid #332d3b;padding:10px}td.num,th.num{text-align:right;font-variant-numeric:tabular-nums}.mono{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12px}
.pill{padding:3px 8px;border-radius:20px;font-size:11px;font-weight:700;letter-spacing:.05em;white-space:nowrap}.pill.pass{background:#65d7b01c;color:var(--mint)}.pill.fail{background:#ff747e1c;color:var(--red)}.pill.warn{background:#e9bd701c;color:var(--gold)}.pill.muted{background:#aaa49b1c;color:var(--muted)}
.timeline{display:grid;gap:10px}.timeline-row{display:grid;grid-template-columns:170px 110px 1fr;gap:14px;align-items:center;padding:13px 14px;background:#16131d;border:1px solid #342d3d;border-radius:12px}.timeline-kind{font-weight:700}.timeline-kind small{display:block;color:var(--muted);font-weight:400;font-size:11px}.timeline-yield{font:600 18px Georgia,serif;color:var(--mint)}.timeline-yield.neg{color:var(--red)}.timeline-meta{color:var(--muted);font-size:12px}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:10px}.chip{padding:6px 11px;background:#16131d;border:1px solid #3d334a;border-radius:10px;font-size:12px}.chip b{color:var(--gold);font-weight:600}.chip.new{border-color:#65d7b055}.chip.new b{color:var(--mint)}
.goal-row{display:grid;grid-template-columns:1fr 150px 1fr;gap:12px;align-items:center;padding:11px 0;border-bottom:1px solid #332d3b}.goal-row:last-child{border-bottom:0}.goal-id{font-family:ui-monospace,monospace;font-size:12px}.goal-id small{display:block;color:var(--muted);font-family:Inter,sans-serif}.goal-missing{color:var(--muted);font-size:12px}
.diff{color:var(--muted);font-size:11px;margin-left:6px}.diff.up{color:var(--mint)}.diff.down{color:var(--red)}.empty,.muted{color:var(--muted)}.scope{color:var(--muted);font-size:13px;margin:6px 0 0}.footer{display:flex;justify-content:space-between;gap:20px;color:#77727b;font-size:11px;margin-top:18px;padding:0 4px}.error-list{color:var(--red);font-size:13px;margin:8px 0 0;padding-left:18px}.metric-line{padding:12px 13px;background:#16131d;border:1px solid #342d3d;border-radius:12px}.metric-line span{display:block;color:var(--muted);font-size:12px}.metric-line strong{display:block;font-size:17px;margin-top:4px}
@media(max-width:900px){.kpis{grid-template-columns:repeat(2,1fr)}.timeline-row{grid-template-columns:1fr 100px}.timeline-meta{grid-column:1 / -1}.goal-row{grid-template-columns:1fr 120px}.goal-missing{grid-column:1 / -1}}@media(max-width:620px){main{padding:24px 14px 50px}.hero{display:block}.verdict{margin-top:20px}.kpis{grid-template-columns:1fr 1fr}.footer{display:block}}
"""

REASON_LABELS = {
    "available": "доступно",
    "ether": "не хватает эфира",
    "ingredients": "не хватает ингредиентов",
    "cooldown": "нужно подождать",
    "not_unlocked": "ещё не открыто",
    "mastery": "не хватает мастерства",
    "autonomy": "не хватает автономности",
    "rank": "не хватает ранга",
}

KIND_LABELS = {"active": "Активная игра", "offline": "Offline-сессия"}


def signed(value, digits=0):
    try:
        value = float(value)
    except (TypeError, ValueError):
        return "—"
    if not math.isfinite(value):
        return "—"
    text = number(abs(value), digits)
    if value > 0:
        return "+" + text
    if value < 0:
        return "-" + text
    return text


def item_name(report, item_id):
    return report.get("item_names", {}).get(item_id, item_id)


def reason_label(reason):
    return REASON_LABELS.get(str(reason), str(reason or "—"))


def missing_text(missing):
    if not isinstance(missing, dict) or not missing:
        return ""
    parts = []
    for key, value in missing.items():
        if key == "seconds":
            parts.append("ждать " + seconds(value))
        elif key == "ether":
            parts.append("эфир: " + number(value))
        elif isinstance(value, bool):
            parts.append(str(key))
        else:
            parts.append(f"{key}: {number(value)}")
    return " · ".join(parts)


def scenario_page(eyebrow, subtitle, verdict, verdict_detail, body, schema):
    return f'''<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Alchemist’s Loop — player session report</title>
<style>
{SCENARIO_CSS}
</style>
</head>
<body><main>
<header class="hero"><div><div class="eyebrow">{esc(eyebrow)}</div><h1>Alchemist’s <span>Loop</span></h1><p class="sub">{subtitle}</p></div><div class="verdict {state_class(verdict)}"><div class="eyebrow">Итог</div><strong>{esc(state_label(verdict))}</strong><small>{esc(verdict_detail)}</small></div></header>
{body}
<footer class="footer"><span>Generated locally from scenario JSON · no external assets</span><span>Alchemist’s Loop · report schema {esc(schema)}</span></footer>
</main></body></html>'''


def delta_table(before, after, delta):
    workshop_before = before.get("workshop", {})
    workshop_after = after.get("workshop", {})
    workshop_delta = delta.get("workshop", {})
    rows = [
        ("Эфир (доступно)", before.get("ether_available", 0), after.get("ether_available", 0), delta.get("ether_available", 0)),
        ("Ёмкость эфира", before.get("ether_cap", 0), after.get("ether_cap", 0), delta.get("ether_cap", 0)),
        ("Открыто элементов", before.get("local_discovered_count", 0), after.get("local_discovered_count", 0), delta.get("local_discovered_count", 0)),
        ("Известно рецептов", before.get("known_recipe_count", 0), after.get("known_recipe_count", 0), delta.get("known_recipe_count", 0)),
        ("Золото prestige", before.get("gold", 0), after.get("gold", 0), delta.get("gold", 0)),
        ("Ранг мастерской", workshop_before.get("rank", 0), workshop_after.get("rank", 0), workshop_delta.get("rank", 0)),
        ("Автономность", workshop_before.get("autonomy", 0), workshop_after.get("autonomy", 0), workshop_delta.get("autonomy", 0)),
        ("Опыт мастерской", workshop_before.get("xp", 0), workshop_after.get("xp", 0), workshop_delta.get("xp", 0)),
    ]
    body = "".join(
        f'<tr><td>{esc(label)}</td><td class="num">{number(b)}</td><td class="num">{number(a)}</td><td class="num">{signed(d)}</td></tr>'
        for label, b, a, d in rows)
    return f'''<div class="table-wrap"><table><thead><tr><th>Показатель</th><th class="num">Было</th><th class="num">Стало</th><th class="num">Δ</th></tr></thead><tbody>{body}</tbody></table></div>'''


def inventory_delta_table(report, delta):
    changes = {k: v for k, v in delta.get("inventory", {}).items() if isinstance(v, (int, float)) and v}
    if not changes:
        return '<p class="empty">Инвентарь не изменился.</p>'
    body = "".join(
        f'<tr><td>{esc(item_name(report, key))} <span class="muted mono">{esc(key)}</span></td><td class="num">{signed(value)}</td></tr>'
        for key, value in sorted(changes.items()))
    return f'''<div class="table-wrap"><table><thead><tr><th>Предмет</th><th class="num">Δ</th></tr></thead><tbody>{body}</tbody></table></div>'''


def goals_table(report, goals):
    if not goals:
        return '<p class="empty">Целей не осталось.</p>'
    rows = []
    for goal in goals:
        available = bool(goal.get("available", False))
        pill = '<span class="pill pass">доступно</span>' if available else '<span class="pill warn">заблокировано</span>'
        rows.append(f'''<div class="goal-row"><div class="goal-id">{esc(goal.get("id", "—"))}<small>{esc(goal.get("kind", ""))}</small></div><div>{pill}</div><div class="goal-missing">{esc(reason_label(goal.get("reason")))}{(" · " + esc(missing_text(goal.get("missing")))) if missing_text(goal.get("missing")) else ""}</div></div>''')
    return "".join(rows)


def upgrade_events(report, events):
    origin = report.get("before", {}).get("clock", {}).get("now", 0)
    rows = []
    for event in events:
        if event.get("kind") != "upgrade":
            continue
        at = event.get("at", origin) - origin
        rows.append(f'<span class="chip"><b>{esc(event.get("upgrade", "—"))}</b> ур. {number(event.get("level", 0))} · через {seconds(at)}</span>')
    return "".join(rows)


def offline_production_block(segment):
    production = segment.get("production", {})
    if not production:
        return ""
    granted = segment.get("offline_granted", {})
    spent = segment.get("offline_spent", {})
    retort = production.get("retort", {})
    saved = production.get("saved")
    saved_pill = '<span class="pill pass">сохранено</span>' if saved is True else ('<span class="pill fail">не сохранено</span>' if saved is False else '<span class="pill muted">нет данных</span>')
    lines = [
        ("Эфир начислен", signed(granted.get("ether", production.get("ether_gained", 0)))),
        ("Эфир потрачен", signed(-float(spent.get("ether", production.get("ether_spent", 0)) or 0))),
        ("Предметы Родника", number(granted.get("spring_items", production.get("spring_items", 0)))),
        ("Реторта: собрано", number(retort.get("collected", 0))),
        ("Обрезано окном offline", seconds(production.get("skipped_seconds", 0))),
    ]
    body = "".join(f'<div class="metric-line"><span>{esc(label)}</span><strong>{value}</strong></div>' for label, value in lines)
    return f'''<div class="section-head" style="margin-top:20px"><div><div class="eyebrow">Offline</div><h2>Offline-производство</h2></div>{saved_pill}</div><div class="kpis" style="grid-template-columns:repeat(5,1fr)">{body}</div>'''


def segment_panel(report, segment, index):
    kind = segment.get("kind", "")
    label = KIND_LABELS.get(kind, kind)
    delta = segment.get("delta", {})
    ether_delta = delta.get("ether_available", 0)
    yield_class = "neg" if isinstance(ether_delta, (int, float)) and ether_delta < 0 else ""
    new_elements = segment.get("new_elements", [])
    chips = "".join(f'<span class="chip new"><b>{esc(item_name(report, item))}</b> {esc(item)}</span>' for item in new_elements)
    unlocks = segment.get("new_unlocks", [])
    unlock_chips = "".join(f'<span class="chip new"><b>{esc(mode)}</b> открыт</span>' for mode in unlocks)
    upgrades = upgrade_events(report, segment.get("events", []))
    stalls = segment.get("stalls", [])
    stall_text = ""
    if stalls:
        stall_text = '<p class="scope">Остановки: ' + esc(", ".join(str(s.get("reason", s)) if isinstance(s, dict) else str(s) for s in stalls)) + "</p>"
    reason = segment.get("reason", "")
    reason_text = f'<p class="scope">Причина завершения: {esc(reason)}</p>' if reason else ""
    events_count = len(segment.get("events", []))
    return f'''<section class="panel"><div class="section-head"><div><div class="eyebrow">Сегмент {number(index + 1)}</div><h2>{esc(label)} · {seconds(segment.get("seconds", 0))}</h2></div><span class="timeline-yield {yield_class}">{signed(ether_delta)} эфира</span></div>
{delta_table(segment.get("before", {}), segment.get("after", {}), delta)}
{('<div class="section-head" style="margin-top:20px"><div><div class="eyebrow">Discovery</div><h2>Новые элементы</h2></div></div><div class="chips">' + chips + unlock_chips + '</div>') if (chips or unlock_chips) else ''}
{('<div class="section-head" style="margin-top:20px"><div><div class="eyebrow">Upgrades</div><h2>Купленные улучшения</h2></div></div><div class="chips">' + upgrades + '</div>') if upgrades else ''}
{offline_production_block(segment) if kind == "offline" else ''}
{stall_text}{reason_text}
<p class="scope">Событий: {number(events_count)} · необъяснённых ресурсов: {number(len(segment.get("ledger", {}).get("unexplained_resources", [])))}</p>
</section>'''


def render_scenario(report):
    profile = report.get("profile", {})
    time_data = report.get("time", {})
    total = time_data.get("simulated_real_seconds", 0)
    active = time_data.get("active_seconds", 0)
    offline = time_data.get("offline_seconds", 0)
    before = report.get("before", {})
    after = report.get("after", {})
    delta = report.get("delta", {})
    counters = report.get("session", {}).get("counters", {})
    new_total = len(set(after.get("local_discovered_ids", [])) - set(before.get("local_discovered_ids", [])))
    subtitle = (f'Сценарий: {esc(report.get("scenario_name", "custom"))} · профиль {esc(profile.get("name", "—"))} · '
                f'seed {esc(report.get("seed", "—"))} · ускоренное виртуальное время, не реальное')
    timeline = []
    for index, segment in enumerate(report.get("segments", [])):
        ether_delta = segment.get("delta", {}).get("ether_available", 0)
        yield_class = "neg" if isinstance(ether_delta, (int, float)) and ether_delta < 0 else ""
        meta = (f'новых элементов: {number(len(segment.get("new_elements", [])))} · '
                f'событий: {number(len(segment.get("events", [])))} · '
                f'улучшений: {number(segment.get("counters", {}).get("upgrade_purchases", 0))}')
        timeline.append(f'''<div class="timeline-row"><div class="timeline-kind">{esc(KIND_LABELS.get(segment.get("kind", ""), segment.get("kind", "")))}<small>сегмент {number(index + 1)}</small></div><div class="timeline-yield {yield_class}">{signed(ether_delta)}</div><div class="timeline-meta">{seconds(segment.get("seconds", 0))} · {esc(meta)}</div></div>''')
    segments_html = "".join(segment_panel(report, segment, index) for index, segment in enumerate(report.get("segments", [])))
    errors = report.get("errors", [])
    errors_html = ('<ul class="error-list">' + "".join(f"<li>{esc(e)}</li>" for e in errors) + "</ul>") if errors else ""
    scope = report.get("scope", {})
    scope_html = "".join(f'<p class="scope"><b>{esc(key)}:</b> {esc(value)}</p>' for key, value in scope.items())
    body = f'''<section class="kpis">
{kpi("Виртуальное время", seconds(total), f'{number(active)} с active · {number(offline)} с offline', "violet")}
{kpi("Открыто элементов", number(after.get("local_discovered_count", 0)), f'+{number(new_total)} за сессию', "mint")}
{kpi("Эфир в конце", number(after.get("ether_available", 0)), f'ёмкость {number(after.get("ether_cap", 0))}', "gold")}
{kpi("Куплено улучшений", number(counters.get("upgrade_purchases", 0)), f'открытий: {number(counters.get("discoveries", 0))} · варок: {number(counters.get("brews", 0))}', "violet")}
</section>
<section class="panel"><div class="section-head"><div><div class="eyebrow">Timeline</div><h2>Хронология сессии</h2></div><span class="eyebrow">{number(len(report.get("segments", [])))} сегмента</span></div><p class="panel-intro">Что игрок заработал в каждом отрезке: активная игра и offline-простой считаются отдельно.</p><div class="timeline">{"".join(timeline)}</div></section>
{segments_html}
<section class="panel"><div class="section-head"><div><div class="eyebrow">Session result</div><h2>Что изменилось за сессию</h2></div></div>{delta_table(before, after, delta)}<div class="section-head" style="margin-top:20px"><div><div class="eyebrow">Inventory</div><h2>Инвентарь</h2></div></div>{inventory_delta_table(report, delta)}</section>
<section class="panel"><div class="section-head"><div><div class="eyebrow">Next steps</div><h2>Доступные следующие шаги</h2></div><span class="eyebrow">{number(len(report.get("blocked_goals", [])))} заблокировано</span></div><p class="panel-intro">Ближайшие цели production-экономики и причины, по которым они пока недоступны.</p>{goals_table(report, report.get("available_goals", []))}</section>
<section class="panel"><div class="section-head"><div><div class="eyebrow">Scope</div><h2>Ограничения модели</h2></div></div>{scope_html}{errors_html}</section>
<details class="panel"><summary>Технические идентификаторы</summary><div class="kpis" style="grid-template-columns:repeat(2,1fr);margin-top:16px"><div class="metric-line"><span>Catalog hash</span><strong class="mono">{esc(report.get("catalog_hash", "—"))}</strong></div><div class="metric-line"><span>Profile hash</span><strong class="mono">{esc(profile.get("hash", "—"))}</strong></div><div class="metric-line"><span>Runner commit</span><strong class="mono">{esc(report.get("runner_commit", "—"))}</strong></div><div class="metric-line"><span>Seed</span><strong class="mono">{esc(report.get("seed", "—"))}</strong></div></div></details>'''
    return scenario_page("СЕССИЯ ИГРОКА · ускоренная симуляция", subtitle, report.get("verdict", "unknown"),
                         f'profile: {profile.get("name", "—")}', body, report.get("schema", "—"))


def render_comparison(comparison):
    reports = comparison.get("reports", [])
    metrics = comparison.get("metrics", [])
    names = [row.get("profile", report.get("profile", {}).get("name", f"run {i + 1}")) for i, (row, report) in enumerate(zip(metrics, reports))]
    scenario_name = reports[0].get("scenario_name", "custom") if reports else "custom"
    seed = reports[0].get("seed", "—") if reports else "—"
    subtitle = f'Сценарий: {esc(scenario_name)} · seed {esc(seed)} · {number(len(reports))} профиля последовательно, одинаковый seed и каталог'
    header = "".join(f"<th class='num'>{esc(name)}</th>" for name in names)

    def metric_row(label, key, fmt=number, diff=True):
        cells = []
        for index, row in enumerate(metrics):
            value = fmt(row.get(key, 0))
            delta_html = ""
            if diff and index > 0:
                difference = row.get("vs_first", {}).get(key, 0)
                cls = "up" if isinstance(difference, (int, float)) and difference > 0 else ("down" if isinstance(difference, (int, float)) and difference < 0 else "")
                delta_html = f'<span class="diff {cls}">{signed(difference)}</span>'
            cells.append(f'<td class="num">{value}{delta_html}</td>')
        return f"<tr><td>{esc(label)}</td>{''.join(cells)}</tr>"

    verdict_cells = "".join(f'<td class="num"><span class="pill {state_class(r.get("verdict", "unknown"))}">{esc(state_label(r.get("verdict", "unknown")))}</span></td>' for r in reports)
    rows = [
        f"<tr><td>Вердикт</td>{verdict_cells}</tr>",
        metric_row("Открыто элементов", "local_elements"),
        metric_row("Новые элементы", "new_elements"),
        metric_row("Эфир в конце", "ether_available"),
        metric_row("Куплено улучшений", "upgrade_purchases"),
        metric_row("Эфир за offline", "offline_ether_earned"),
        metric_row("Эфир потрачен за offline", "offline_ether_spent", diff=False),
        metric_row("Предметы Родника за offline", "offline_spring_items", diff=False),
    ]
    first_times = []
    for row in metrics:
        unlocks = row.get("first_unlock_seconds", {})
        upgrades = row.get("first_upgrade_seconds", {})
        first_unlock = seconds(min(unlocks.values())) if unlocks else "—"
        first_upgrade = seconds(min(upgrades.values())) if upgrades else "—"
        first_times.append(f"<tr><td>{esc(row.get('profile', '—'))}</td><td class='num'>{first_unlock}</td><td class='num'>{first_upgrade}</td><td class='num'>{number(len(row.get('blockers', [])))}</td></tr>")
    segment_rows = []
    for row in metrics:
        cells = []
        for segment in row.get("segments", []):
            ether_delta = segment.get("delta", {}).get("ether_available", 0)
            cells.append(f'<td class="num">{esc(KIND_LABELS.get(segment.get("kind", ""), segment.get("kind", "")))}<br>{signed(ether_delta)}</td>')
        segment_rows.append(f"<tr><td>{esc(row.get('profile', '—'))}</td>{''.join(cells)}</tr>")
    segment_header = "".join(f"<th class='num'>{esc(KIND_LABELS.get(s.get('kind', ''), s.get('kind', '')))} {number(i + 1)}</th>" for i, s in enumerate(metrics[0].get("segments", []))) if metrics else ""
    blocker_blocks = []
    for row, report in zip(metrics, reports):
        blocked = report.get("blocked_goals", [])
        top = blocked[:6]
        blocker_blocks.append(f'''<div class="metric-line"><span>{esc(row.get("profile", "—"))} · заблокировано {number(len(blocked))}</span><strong style="font-size:13px;font-weight:400">{esc(", ".join(reason_label(g.get("reason")) for g in top)) or "нет"}</strong></div>''')
    body = f'''<section class="panel"><div class="section-head"><div><div class="eyebrow">Profiles</div><h2>Сравнение балансов</h2></div><span class="eyebrow">Δ относительно первого профиля</span></div><p class="panel-intro">Один и тот же сценарий и seed на разных профилях баланса: что игрок получает в конце и по дороге.</p><div class="table-wrap"><table><thead><tr><th>Показатель</th>{header}</tr></thead><tbody>{"".join(rows)}</tbody></table></div></section>
<section class="panel"><div class="section-head"><div><div class="eyebrow">Pacing</div><h2>Темп открытий</h2></div></div><div class="table-wrap"><table><thead><tr><th>Профиль</th><th class="num">Первое открытие</th><th class="num">Первое улучшение</th><th class="num">Заблокированных целей</th></tr></thead><tbody>{"".join(first_times)}</tbody></table></div></section>
<section class="panel"><div class="section-head"><div><div class="eyebrow">Segments</div><h2>Эфир по сегментам</h2></div></div><div class="table-wrap"><table><thead><tr><th>Профиль</th>{segment_header}</tr></thead><tbody>{"".join(segment_rows)}</tbody></table></div></section>
<section class="panel"><div class="section-head"><div><div class="eyebrow">Blockers</div><h2>Что мешает игроку</h2></div></div><div class="kpis" style="grid-template-columns:repeat({max(1, len(metrics))},1fr)">{"".join(blocker_blocks)}</div></section>'''
    return scenario_page("СРАВНЕНИЕ БАЛАНСОВ · ускоренная симуляция", subtitle, comparison.get("verdict", "unknown"),
                         f'{number(len(reports))} профиля', body, comparison.get("schema", "—"))


def write_report(output, report, summary=None):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render_report(report, summary), encoding="utf-8")
    return output


def main():
    parser = argparse.ArgumentParser(description="Render a standalone progression HTML report")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = json.loads(args.report.read_text(encoding="utf-8"))
    summary = json.loads(args.summary.read_text(encoding="utf-8")) if args.summary else None
    write_report(args.output, report, summary)
    print(str(args.output.resolve()))


if __name__ == "__main__":
    main()
