/* cuts_v2.js — 5 creative cuts + new scene library for the Alchemist's Loop teaser.
 *
 * Scenes: hookWorld, hookCozy, hookRace, hookSvetik, mysteryHook, baseJoke,
 *         worldExperiment, svetikShow, workshop, spring, sigilOpen, house,
 *         race, feed, offline, finale
 * Cuts:   v1 «Мир варит» · v2 «Светик-шоу» · v3 «58-е вещество»
 *         v4 «Дом алхимика» · v5 «Гонка»
 */
"use strict";

const R = require("./render.js");
const {
  C, W, H, clamp, lerp, seg, eoc, eic, eio, eoe, eob, osc, rnd,
  T, rrect, glowDot, chip, svgImg, pngImg, glyphPath, ringWord,
  bgBase, vignette, embers, glyphRain, spirit, sparkleBurst, cauldron, orb,
} = R;

const S = {}; // statics filled by init()

async function init() {
  Object.assign(S, R.statics());
  // extra icon sizes used by v2 scenes (orb r 44/66/70/72/74 -> w*1.1)
  const jobs = [];
  for (const ic of ["drop", "fire", "wind", "bolt", "gem", "flask", "trophy", "play", "star"]) {
    for (const w of [30, 34, 40, 48, 64, 73, 77, 79, 81, 96]) jobs.push(R.preloadSvg(`icons/${ic}.svg`, w));
  }
  for (const st of ["sleep", "cheer", "wave", "mist", "star", "look", "hi", "think", "celebrate", "gift"]) {
    jobs.push(R.preloadPng(`stickers/${st}.png`));
  }
  await Promise.all(jobs);
}

/* small helpers ------------------------------------------------------- */
function bg(ctx, t, night = 0) { bgBase(ctx, t, { night }); }
function headChip(ctx, iconFile, text, col = C.teal) {
  const ic = svgImg("icons/" + iconFile, 34);
  ctx.drawImage(ic, 96, 296, 34, 34);
  T(ctx, text, 146, 314, { size: 36, alias: "ManropeXB", color: col, align: "left", spacing: 3 });
}
function panel(ctx, x, y, w, h, border = "rgba(53,208,186,0.5)") {
  ctx.fillStyle = "rgba(13,16,28,0.62)";
  rrect(ctx, x, y, w, h, 40); ctx.fill();
  ctx.strokeStyle = border; ctx.lineWidth = 2.5;
  rrect(ctx, x, y, w, h, 40); ctx.stroke();
}
/* speech bubble with tail */
function bubble(ctx, x, y, w, h, tailSide = -1, border = "rgba(53,208,186,0.5)") {
  rrect(ctx, x - w / 2, y - h / 2, w, h, 30);
  ctx.fillStyle = "rgba(16,23,36,0.96)"; ctx.fill();
  ctx.strokeStyle = border; ctx.lineWidth = 2.2; ctx.stroke();
  const tx = x + tailSide * (w / 2 - 10);
  ctx.beginPath();
  ctx.moveTo(tx, y - 12);
  ctx.lineTo(tx + tailSide * 26, y + 14);
  ctx.lineTo(tx - tailSide * 6, y + 12);
  ctx.closePath();
  ctx.fillStyle = "rgba(16,23,36,0.96)"; ctx.fill();
  ctx.strokeStyle = border; ctx.lineWidth = 2; ctx.stroke();
  ctx.fillStyle = "rgba(16,23,36,1)";
  ctx.fillRect(tx - tailSide * 6 + (tailSide < 0 ? -8 : 0), y + 6, 8, 6);
}

/* =====================================================================
 * SCENES
 * ===================================================================== */

/* --- hooks --- */
function hookWorld(ctx, t) { // 0-5.2: мир варит без тебя
  bg(ctx, t, 0.15);
  glyphRain(ctx, t, 0.7);
  embers(ctx, t, { n: 12, heat: 0.7 });
  const tl = t;
  const a1 = seg(tl, 0.35, 0.9) * (1 - seg(tl, 2.35, 2.8));
  if (a1 > 0) T(ctx, "Пока ты смотрел этот ролик…", W / 2, 700 + (1 - eoc(seg(tl, 0.35, 0.9))) * 34,
    { size: 58, alias: "ManropeSB", color: "#fff", alpha: a1 });
  // ticker of world discoveries
  const rows = [
    { t0: 2.2, who: "@мира", thing: "РТУТЬ", col: "255,179,71", tag: "впервые в мире" },
    { t0: 3.0, who: "@keks", thing: "ГЛИНА", col: "53,208,186", tag: "слой 2" },
    { t0: 3.8, who: "@лиса", thing: "СТЕКЛО", col: "176,108,255", tag: "слой 3" },
  ];
  rows.forEach((r, i) => {
    const p = seg(tl, r.t0, r.t0 + 0.5);
    if (p <= 0 || p >= 1) return;
    const y = 900 + i * 130;
    const x = lerp(W + 500, W / 2, eoc(p)) - eic(seg(tl, 4.6 + i * 0.1, 5.05 + i * 0.1)) * 700;
    ctx.save();
    ctx.globalAlpha = clamp(p * 1.6, 0, 1);
    feedRow(ctx, x, y, r.who, r.thing, r.col, r.tag);
    ctx.restore();
  });
  const a2 = eoc(seg(tl, 4.35, 4.9));
  if (a2 > 0) T(ctx, "МИР ВАРИТ БЕЗ ТЕБЯ", W / 2, 1420, { size: 72, alias: "ManropeXB", color: C.amber, alpha: a2, glow: "rgba(255,170,60,0.8)", glowBlur: 30 });
  vignette(ctx);
}

function hookCozy(ctx, t) { // 0-5: он варит, пока ты спишь
  bg(ctx, t, 1);
  embers(ctx, t, { n: 8, heat: 0.5 });
  ctx.save(); ctx.globalAlpha = 0.95;
  ctx.translate(760, 330); ctx.drawImage(S.WINDOW, -190, -235); ctx.restore();
  cauldron(ctx, t, W / 2 - 40, 1300, 340, { dark: true, boil: 0.3 });
  ctx.save(); ctx.globalAlpha = 0.05; ctx.fillStyle = "#b8ccff";
  ctx.beginPath(); ctx.moveTo(880, 400); ctx.lineTo(1000, 400); ctx.lineTo(600, 1440); ctx.lineTo(320, 1440);
  ctx.closePath(); ctx.fill(); ctx.restore();
  const pop = eob(seg(t, 0.4, 1.1));
  if (pop > 0) spirit(ctx, "sleep", W / 2 + 250, 1120, 240 * clamp(pop, 0.001, 1.05), t, { bob: 4 });
  const a1 = seg(t, 0.7, 1.3);
  if (a1 > 0) {
    T(ctx, "Он варит,", W / 2, 470, { size: 72, alias: "ManropeXB", color: "#fff", alpha: eoc(a1), glow: "rgba(255,255,255,0.25)" });
    T(ctx, "пока ты спишь", W / 2, 570, { size: 66, alias: "ManropeXB", color: C.gold, alpha: eoc(seg(t, 1.15, 1.75)), glow: "rgba(255,200,77,0.7)", glowBlur: 30 });
  }
  vignette(ctx, 0.55);
}

function hookRace(ctx, t) { // 0-4.5: гонка
  bg(ctx, t, 0.2);
  glyphRain(ctx, t, 0.5);
  embers(ctx, t, { n: 16, heat: 0.9 });
  const a1 = seg(t, 0.3, 0.85);
  if (a1 > 0) T(ctx, "Ты — второй.", W / 2, 620, { size: 76, alias: "ManropeXB", color: "#fff", alpha: eoc(a1) });
  const a2 = seg(t, 1.15, 1.7);
  if (a2 > 0) T(ctx, "Пока", W / 2, 740, { size: 54, alias: "ManropeM", color: C.dim, alpha: eoc(a2) });
  feedRow(ctx, W / 2, 880, "@мира", "РТУТЬ", "255,179,71", "первая в мире",
    eoc(seg(t, 1.7, 2.2)) * (1 - seg(t, 4.0, 4.4)), eoc(seg(t, 1.7, 2.2)));
  const a3 = seg(t, 2.6, 3.15);
  if (a3 > 0) T(ctx, "Стань первым.", W / 2, 1120, { size: 70, alias: "ManropeXB", color: C.amber, alpha: eoc(a3), glow: "rgba(255,170,60,0.8)", glowBlur: 30 });
  vignette(ctx);
}

function hookSvetik(ctx, t) { // 0-4.5: Светик-хук
  bg(ctx, t, 0.2);
  embers(ctx, t, { n: 18 });
  ctx.save(); ctx.globalAlpha = 0.14;
  ctx.translate(W / 2, 760); ctx.rotate(-t * 0.06);
  ctx.drawImage(S.RING_TEAL, -520, -520, 1040, 1040); ctx.restore();
  const pop = eob(seg(t, 0.15, 0.8));
  if (pop > 0) spirit(ctx, "hi", W / 2, 720, 430 * clamp(pop, 0.001, 1.06), t, { bob: 12 });
  sparkleBurst(ctx, t, 0.25, W / 2, 720, { n: 18, dur: 1.0 });
  const a1 = seg(t, 0.85, 1.4);
  if (a1 > 0) {
    T(ctx, "Варю тут.", W / 2, 1030, { size: 74, alias: "ManropeXB", color: "#fff", alpha: eoc(a1), glow: "rgba(255,255,255,0.3)" });
    T(ctx, "Один. Скучно.", W / 2, 1130, { size: 58, alias: "ManropeSB", color: C.amber, alpha: eoc(seg(t, 1.5, 2.05)) });
  }
  vignette(ctx, 0.4);
}

function mysteryHook(ctx, t) { // 0-5: 58-го нет ни у кого
  bg(ctx, t, 0.45);
  glyphRain(ctx, t, 0.35);
  embers(ctx, t, { n: 10, heat: 0.6 });
  const a1 = eoc(seg(t, 0.3, 0.9));
  if (a1 > 0) T(ctx, "57", W / 2, 800, { size: 230, alias: "ManropeXB", color: C.amber, alpha: a1, glow: "rgba(255,170,60,0.75)", glowBlur: 44 });
  const a2 = eoc(seg(t, 1.1, 1.7));
  if (a2 > 0) T(ctx, "веществ открыл весь мир", W / 2, 960, { size: 46, alias: "ManropeSB", color: C.dim, alpha: a2 });
  const a3 = eoc(seg(t, 2.3, 2.9));
  if (a3 > 0) {
    T(ctx, "58-го нет", W / 2, 1120, { size: 78, alias: "ManropeXB", color: "#fff", alpha: a3, glow: "rgba(255,255,255,0.35)" });
    T(ctx, "НИ У КОГО", W / 2, 1222, { size: 60, alias: "ManropeXB", color: C.violet, alpha: eoc(seg(t, 2.9, 3.5)), glow: "rgba(176,108,255,0.7)" });
  }
  vignette(ctx, 0.5);
}

/* --- «это база» --- */
function baseJoke(ctx, t) { // ~6s
  bg(ctx, t, 0);
  embers(ctx, t, { n: 14 });
  const tl = t;
  headChip(ctx, "flask.svg", "УРОК ПЕРВЫЙ");
  const cx = W / 2, cy = 1130, cw = 360;
  cauldron(ctx, t, cx, cy, cw, { boil: seg(tl, 1.4, 2.1) * 0.8 + 0.15 });
  const wP = eob(seg(tl, 0.35, 0.8)), fP = eob(seg(tl, 0.75, 1.2));
  let wThrow = seg(tl, 1.5, 1.9), fThrow = seg(tl, 1.9, 2.3);
  const wPos = wThrow > 0 && wThrow < 1
    ? { x: lerp(300, cx - 55, eio(wThrow)), y: 760 - Math.sin(eio(wThrow) * Math.PI) * 150 + lerp(0, cy - 760 + 30, eio(wThrow)) }
    : { x: 300, y: 760 };
  const fPos = fThrow > 0 && fThrow < 1
    ? { x: lerp(780, cx + 55, eio(fThrow)), y: 760 - Math.sin(eio(fThrow) * Math.PI) * 150 + lerp(0, cy - 760 + 30, eio(fThrow)) }
    : { x: 780, y: 760 };
  if (wP > 0 && wThrow < 1) orb(ctx, t, wPos.x, wPos.y, 66, "drop.svg", "88,166,255", { pop: clamp(wP, 0.001, 1.1) });
  if (fP > 0 && fThrow < 1) orb(ctx, t, fPos.x, fPos.y, 66, "fire.svg", "255,112,67", { pop: clamp(fP, 0.001, 1.1) });
  const qa = seg(tl, 1.1, 1.55) * (1 - seg(tl, 2.75, 3.15));
  if (qa > 0) T(ctx, "ВОДА + ОГОНЬ = ?", cx, 520, { size: 58, alias: "ManropeXB", color: "#fff", alpha: qa });
  // mini reveal: ПАР
  const cardP = seg(tl, 3.0, 3.6), cardOut = 1 - seg(tl, 5.35, 5.9);
  if (cardP > 0 && cardOut > 0) {
    ctx.save();
    ctx.globalAlpha = cardOut;
    const sc = lerp(0.8, 0.56, eob(cardP));
    ctx.translate(cx, 800);
    ctx.scale(sc, sc);
    ctx.drawImage(S.REVEAL, -S.REVEAL.width / 2, -S.REVEAL.height / 2);
    ctx.restore();
    sparkleBurst(ctx, t, 3.05, cx, 800, { n: 10, dur: 0.8, dist: 150, ring: 160 });
  }
  // Светик: «…это база»
  const jP = seg(tl, 3.9, 4.4), jOut = 1 - seg(tl, 5.35, 5.85);
  if (jP > 0 && jOut > 0) {
    spirit(ctx, "look", 840, 1480, 190 * clamp(eob(jP), 0.001, 1.05), t, { bob: 8 });
    ctx.save();
    ctx.globalAlpha = jOut;
    bubble(ctx, 470, 1420, 470, 110, 1);
    T(ctx, "…это база.", 470, 1420, { size: 44, alias: "ManropeXB", color: C.text });
    T(ctx, "дальше — интереснее", 470, 1486, { size: 27, alias: "ManropeB", color: C.teal });
    ctx.restore();
  }
  vignette(ctx, 0.4);
}

/* --- мир ставит эксперимент: рождение нового вещества --- */
function worldExperiment(ctx, t, o = {}) { // ~8s
  bg(ctx, t, 0.1);
  embers(ctx, t, { n: 16 });
  glyphRain(ctx, t, 0.4);
  const tl = t;
  const cx = W / 2, cy = 1150, cw = 430;
  const h1 = eoc(seg(tl, 0.15, 0.7)) * (1 - seg(tl, 2.9, 3.4));
  if (h1 > 0) {
    T(ctx, "МИР СТАВИТ ЭКСПЕРИМЕНТ", cx, 330, { size: 54, alias: "ManropeXB", color: C.teal, alpha: h1, spacing: 2, glow: "rgba(53,208,186,0.5)" });
  }
  const h1b = eoc(seg(tl, 0.3, 0.8)) * (1 - seg(tl, 2.9, 3.4));
  if (h1b > 0) T(ctx, "пары, которой нет ни в одном гайде", cx, 412, { size: 38, alias: "ManropeM", color: C.dim, alpha: h1b });

  // two unknown orbs
  const unk = [
    { x: 300, t0: 0.5, throwAt: 2.0 }, { x: 780, t0: 0.85, throwAt: 2.35 },
  ];
  unk.forEach((u, i) => {
    const pop = eob(seg(tl, u.t0, u.t0 + 0.45));
    const th = seg(tl, u.throwAt, u.throwAt + 0.4);
    let x = u.x, y = 740;
    if (th > 0) {
      x = lerp(u.x, cx + (i ? 55 : -55), eio(th));
      y = 740 - Math.sin(eio(th) * Math.PI) * 170 + lerp(0, cy - 740 + 30, eio(th));
    }
    if (pop > 0 && th < 1) {
      orb(ctx, t, x, y, 70, "bolt.svg", "120,110,180", { pop: clamp(pop, 0.001, 1.1) });
      const la = (1 - seg(tl, 1.7, 2.0)) * (th < 0.1 ? 1 : 1 - th);
      if (la > 0) T(ctx, "???", x, y + 104, { size: 40, alias: "ManropeXB", color: "#b9aaff", alpha: la });
    }
  });
  cauldron(ctx, t, cx, cy, cw, { boil: seg(tl, 2.4, 3.2) });
  // charge rings
  [3.2, 3.5, 3.8].forEach((st) => {
    const p = seg(tl, st, st + 0.45);
    if (p > 0 && p < 1) {
      ctx.strokeStyle = `rgba(180,160,255,${(1 - p) * 0.75})`;
      ctx.lineWidth = 3 * (1 - p);
      ctx.beginPath(); ctx.ellipse(cx, cy - cw * 0.1, 40 + p * 200, (40 + p * 200) * 0.3, 0, 0, 7); ctx.stroke();
    }
  });
  // new substance card
  const name = o.name || "ЗВЁЗДНАЯ ПЫЛЬ";
  const cardP = seg(tl, 4.35, 5.1), cardOut = 1 - seg(tl, 7.3, 7.85);
  if (cardP > 0 && cardOut > 0) {
    const cy2 = lerp(cy - 60, 800, eoc(cardP));
    ctx.save();
    ctx.globalAlpha = cardOut;
    ctx.translate(cx, cy2);
    ctx.scale(lerp(0.85, 1, eob(cardP)), lerp(0.85, 1, eob(cardP)));
    const w = 800, h = 520;
    ctx.fillStyle = "rgba(13,16,28,0.97)";
    rrect(ctx, -w / 2, -h / 2, w, h, 36); ctx.fill();
    ctx.strokeStyle = C.violet; ctx.lineWidth = 3;
    ctx.shadowColor = "rgba(176,108,255,0.8)"; ctx.shadowBlur = 30;
    rrect(ctx, -w / 2, -h / 2, w, h, 36); ctx.stroke();
    ctx.shadowBlur = 0;
    // procedural glyph circle
    ctx.save();
    ctx.globalAlpha = 0.5;
    ctx.translate(0, -66);
    ctx.rotate(t * 0.12);
    ctx.drawImage(S.RING_AMBER, -130, -130, 260, 260);
    ctx.restore();
    T(ctx, "НОВОЕ ВЕЩЕСТВО", 0, -h / 2 + 64, { size: 30, alias: "ManropeB", color: C.violet, spacing: 8 });
    T(ctx, name, 0, -6, { size: 92, alias: "ManropeXB", color: "#fff", glow: "rgba(200,160,255,0.8)", glowBlur: 36 });
    T(ctx, "имя придумала нейросеть", 0, 82, { size: 34, alias: "ManropeM", color: C.dim });
    // chips
    chip(ctx, "первое в мире · @kcir", -190, 152, { size: 27, color: C.amber, bg: "rgba(255,179,71,0.12)", border: "rgba(255,179,71,0.6)" });
    chip(ctx, "+25 эфира", 120, 152, { size: 27, color: C.violet, bg: "rgba(176,108,255,0.12)", border: "rgba(176,108,255,0.55)" });
    ctx.restore();
    sparkleBurst(ctx, t, 4.45, cx, cy2, { n: 24, dur: 1.2, dist: 300, ring: 300 });
  }
  const a2 = seg(tl, 6.4, 7.0) * (1 - seg(tl, 7.4, 7.8));
  if (a2 > 0) T(ctx, "такого раньше не было НИ У КОГО", cx, 1560, { size: 46, alias: "ManropeXB", color: "#fff", alpha: a2 });
  vignette(ctx, 0.42);
}

/* --- Светик-шоу: реплики --- */
function svetikShow(ctx, t, o = {}) { // ~7s
  bg(ctx, t, 0.15);
  embers(ctx, t, { n: 14 });
  const tl = t;
  const cx = W / 2;
  ctx.save(); ctx.globalAlpha = 0.12;
  ctx.translate(cx, 700); ctx.rotate(-t * 0.05);
  ctx.drawImage(S.RING_TEAL, -500, -500, 1000, 1000); ctx.restore();

  const st = o.startSticker || "think";
  const pop = eob(seg(tl, 0.1, 0.7));
  if (pop > 0) spirit(ctx, st, 300, 700, 300 * clamp(pop, 0.001, 1.05), t, { bob: 10 });
  const head = eoc(seg(tl, 0.4, 0.9));
  if (head > 0 && !o.noHead) T(ctx, "СВЕТИК ЗНАЕТ ТОН", cx, 300, { size: 52, alias: "ManropeXB", color: C.amber, alpha: head, glow: "rgba(255,170,60,0.6)" });

  const jokes = [
    { t0: 1.2, dur: 1.9, quest: "Свари Человека: Жизнь + Глина", txt: "…без комментариев.", st2: "look" },
    { t0: 3.1, dur: 1.9, fail: "Туман. Не сочетаются.", txt: "бывает. даже у лучших.", st2: "mist" },
    { t0: 5.0, dur: 1.9, news: "Мир нашёл „Ртуть“!", txt: "успеем своё. летим.", st2: "star" },
  ];
  jokes.forEach((j, i) => {
    const p = seg(tl, j.t0, j.t0 + 0.45);
    const out = 1 - seg(tl, j.t0 + j.dur - 0.35, j.t0 + j.dur);
    if (p <= 0 || out <= 0) return;
    const y = 1080 + i * 0; // single bubble area
    // swap Светик sticker
    if (eoc(p) > 0.5) spirit(ctx, j.st2, 300, 700, 300, t, { bob: 10 });
    ctx.save();
    ctx.globalAlpha = out;
    const e = eob(p);
    ctx.translate(cx + 120, 860);
    ctx.scale(clamp(e, 0.001, 1), clamp(e, 0.001, 1));
    if (j.quest) {
      bubble(ctx, 0, 0, 640, 120, -1, "rgba(255,179,71,0.55)");
      T(ctx, "КВЕСТ: " + j.quest, 0, -10, { size: 30, alias: "ManropeB", color: C.gold });
      T(ctx, j.txt, 0, 34, { size: 36, alias: "ManropeXB", color: C.text });
    } else if (j.fail) {
      bubble(ctx, 0, 0, 640, 120, -1, "rgba(150,160,190,0.55)");
      T(ctx, j.fail, 0, -10, { size: 30, alias: "ManropeB", color: C.grey });
      T(ctx, j.txt, 0, 34, { size: 36, alias: "ManropeXB", color: C.text });
    } else {
      bubble(ctx, 0, 0, 640, 120, -1, "rgba(53,208,186,0.6)");
      T(ctx, j.news, 0, -10, { size: 30, alias: "ManropeB", color: C.teal });
      T(ctx, j.txt, 0, 34, { size: 36, alias: "ManropeXB", color: C.text });
    }
    ctx.restore();
  });
  vignette(ctx, 0.4);
}

/* --- мастерская: маршрут Облако --- */
function workshop(ctx, t) { // ~6s
  bg(ctx, t, 0);
  embers(ctx, t, { n: 20, heat: 1.1 });
  const tl = t;
  headChip(ctx, "flask.svg", "МАСТЕРСКАЯ", C.amber);
  const h1 = eoc(seg(tl, 0.2, 0.7));
  if (h1 > 0) T(ctx, "освоенный маршрут варит сам", W / 2, 412, { size: 40, alias: "ManropeM", color: C.dim, alpha: h1 });

  // conveyor: Пар -> +Воздух -> Облако
  const nodes = [
    { label: "ПАР", icon: "fire.svg", rgb: "255,140,80", x: 240 },
    { label: "+ ВОЗДУХ", icon: "wind.svg", rgb: "155,232,221", x: 540 },
    { label: "ОБЛАКО", icon: "gem.svg", rgb: "140,190,255", x: 840 },
  ];
  // links
  const pLink = eoc(seg(tl, 0.9, 1.4));
  if (pLink > 0) {
    ctx.strokeStyle = `rgba(255,179,71,${0.6 * pLink})`;
    ctx.lineWidth = 3;
    ctx.setLineDash([12, 10]);
    ctx.beginPath(); ctx.moveTo(nodes[0].x + 80, 700); ctx.lineTo(nodes[1].x - 84, 700); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(nodes[1].x + 120, 700); ctx.lineTo(nodes[2].x - 84, 700); ctx.stroke();
    ctx.setLineDash([]);
  }
  nodes.forEach((n, i) => {
    const p = eob(seg(tl, 0.4 + i * 0.28, 0.85 + i * 0.28));
    if (p <= 0) return;
    const y = 700 + Math.sin(t * 1.4 + i) * 8;
    orb(ctx, t, n.x, y, 72, n.icon, n.rgb, { pop: clamp(p, 0.001, 1.08) });
    T(ctx, n.label, n.x, y + 108, { size: 30, alias: "ManropeXB", color: "#fff", alpha: clamp(p, 0, 1) });
  });
  // progress bar этапа
  const barP = seg(tl, 1.6, 4.6);
  const bx = 190, bw = W - 380, by = 920;
  panel(ctx, bx - 30, by - 46, bw + 60, 132, "rgba(255,179,71,0.5)");
  const bp = eoc(seg(tl, 0.8, 1.3));
  if (bp > 0) {
    T(ctx, "ЭТАП 1 ИЗ 3", bx, by - 12, { size: 28, alias: "ManropeB", color: C.dim, align: "left" });
    T(ctx, "10 СЕК", bx + bw, by - 12, { size: 28, alias: "ManropeB", color: C.amber, align: "right" });
    rrect(ctx, bx, by + 10, bw, 40, 20);
    ctx.fillStyle = "rgba(255,255,255,0.08)"; ctx.fill();
    rrect(ctx, bx, by + 10, bw * barP, 40, 20);
    ctx.fillStyle = "rgba(255,179,71,0.75)"; ctx.fill();
  }
  // items produced
  [3.0, 4.3].forEach((st, i) => {
    const p = seg(tl, st, st + 0.5);
    if (p <= 0 || p >= 1) return;
    const y = 1180 + i * 0;
    ctx.save();
    ctx.globalAlpha = (1 - seg(tl, st + 1.1, st + 1.5));
    ctx.translate(W / 2 + (i ? 120 : -120), y);
    ctx.scale(eob(p), eob(p));
    chip(ctx, i ? "+1 ОБЛАКО" : "+1 ПАР", 0, 0, { size: 34, color: "#fff", bg: "rgba(53,208,186,0.14)", border: "rgba(53,208,186,0.6)" });
    ctx.restore();
    sparkleBurst(ctx, t, st + 0.1, W / 2 + (i ? 120 : -120), y, { n: 8, dur: 0.7, dist: 100, ring: 90 });
  });
  const ch = eob(seg(tl, 4.7, 5.2));
  if (ch > 0) {
    chip(ctx, "чертёж маршрута: −10% эфира", W / 2, 1400, { size: 32, color: C.gold, bg: "rgba(255,179,71,0.12)", border: "rgba(255,179,71,0.6)", alpha: clamp(ch, 0, 1) * (1 - seg(tl, 5.6, 6.0)) });
  }
  vignette(ctx, 0.4);
}

/* --- родник --- */
function spring(ctx, t, o = {}) { // ~5s
  bg(ctx, t, 0.25);
  embers(ctx, t, { n: 10, heat: 0.6 });
  const tl = t;
  headChip(ctx, "drop.svg", "РОДНИК", C.water);
  const h1 = eoc(seg(tl, 0.2, 0.7));
  if (h1 > 0) T(ctx, "базовая стихия — каждые 6 секунд", W / 2, 412, { size: 40, alias: "ManropeM", color: C.dim, alpha: h1 });
  // stone bowl
  const cx = W / 2, cy = 1150;
  ctx.save();
  const g = ctx.createLinearGradient(0, cy - 120, 0, cy + 140);
  g.addColorStop(0, "#39415a"); g.addColorStop(1, "#232a3d");
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.moveTo(cx - 260, cy - 90);
  ctx.bezierCurveTo(cx - 250, cy + 130, cx + 250, cy + 130, cx + 260, cy - 90);
  ctx.closePath(); ctx.fill();
  ctx.strokeStyle = "#4a5570"; ctx.lineWidth = 6; ctx.stroke();
  // water
  ctx.fillStyle = "#3f7fd4";
  ctx.beginPath(); ctx.ellipse(cx, cy - 84, 232, 44, 0, 0, 7); ctx.fill();
  ctx.fillStyle = "rgba(191,239,255,0.5)";
  ctx.beginPath(); ctx.ellipse(cx - 60 + Math.sin(t * 1.3) * 14, cy - 94, 70, 12, -0.1, 0, 7); ctx.fill();
  ctx.restore();
  // falling drops of elements
  const els = [
    { icon: "drop.svg", rgb: "88,166,255", t0: 0.5 },
    { icon: "fire.svg", rgb: "255,112,67", t0: 1.8 },
    { icon: "wind.svg", rgb: "155,232,221", t0: 3.1 },
  ];
  els.forEach((e, i) => {
    const p = seg(tl, e.t0, e.t0 + 0.9);
    if (p <= 0 || p >= 1) return;
    const y = lerp(560, cy - 100, eic(p));
    orb(ctx, t, cx, y, 44, e.icon, e.rgb, { pop: 1 });
    if (p > 0.92) {
      const rp = seg(tl, e.t0 + 0.83, e.t0 + 1.4);
      if (rp > 0 && rp < 1) {
        ctx.strokeStyle = `rgba(191,239,255,${(1 - rp) * 0.8})`;
        ctx.lineWidth = 3 * (1 - rp);
        ctx.beginPath(); ctx.ellipse(cx, cy - 84, 60 + rp * 160, (60 + rp * 160) * 0.22, 0, 0, 7); ctx.stroke();
      }
    }
  });
  // counter chip
  const c1 = eob(seg(tl, 1.0, 1.5));
  if (c1 > 0) chip(ctx, "+1 стихия / 6 сек", cx, 1520, { size: 34, color: "#fff", bg: "rgba(88,166,255,0.12)", border: "rgba(88,166,255,0.6)", alpha: clamp(c1, 0, 1) * (1 - seg(tl, 4.4, 4.8)) });
  if (o.svetik) {
    const sp = eob(seg(tl, 2.2, 2.8));
    if (sp > 0) {
      spirit(ctx, "gift", 180, 1400, 200 * clamp(sp, 0.001, 1.05), t, { bob: 8 });
      bubble(ctx, 620, 1360, 520, 100, 1);
      T(ctx, "водичку? держи.", 620, 1360, { size: 40, alias: "ManropeXB", color: C.text });
    }
  }
  vignette(ctx, 0.42);
}

/* --- открытие карточки (таро-переворот) --- */
function sigilOpen(ctx, t) { // ~6s
  bg(ctx, t, 0.2);
  embers(ctx, t, { n: 16 });
  const tl = t;
  const cx = W / 2, cy = 950;
  const h1 = eoc(seg(tl, 0.15, 0.65));
  if (h1 > 0) T(ctx, "КАЖДОЕ ВЕЩЕСТВО — КАРТА", cx, 320, { size: 50, alias: "ManropeXB", color: C.teal, alpha: h1, spacing: 2 });
  const h2 = eoc(seg(tl, 0.55, 1.05));
  if (h2 > 0) T(ctx, "со своей редкостью, глифом и лором", cx, 402, { size: 38, alias: "ManropeM", color: C.dim, alpha: h2 });

  const flip = seg(tl, 1.7, 2.5);           // 0..1
  const backP = seg(tl, 0.5, 1.5);
  const cardW = 360, cardH = 470;
  const endOut = 1 - seg(tl, 4.9, 5.4);
  const y = cy + Math.sin(t * 1.2) * 8;
  if (endOut > 0) {
    ctx.save();
    ctx.globalAlpha = endOut;
    ctx.translate(cx, y);
    if (flip < 0.5) {
      const sx = Math.max(0.02, Math.cos(flip * Math.PI)); // 1 -> 0
      ctx.scale(sx * lerp(0.92, 1, eob(backP)), 1);
      ctx.fillStyle = "rgba(15,17,30,0.98)";
      rrect(ctx, -cardW / 2, -cardH / 2, cardW, cardH, 28); ctx.fill();
      ctx.strokeStyle = "rgba(90,100,125,0.8)"; ctx.lineWidth = 3;
      rrect(ctx, -cardW / 2, -cardH / 2, cardW, cardH, 28); ctx.stroke();
      ctx.save();
      ctx.globalAlpha = 0.5 * endOut;
      ctx.rotate(t * 0.1);
      ctx.drawImage(S.RING_AMBER, -150, -150, 300, 300);
      ctx.restore();
      T(ctx, "?", 0, 10, { size: 130, alias: "ManropeXB", color: C.dim, alpha: 1 - flip * 1.2 });
    } else {
      const sx = Math.max(0.02, -Math.cos(flip * Math.PI)); // 0 -> 1
      const e = eob(seg(tl, 2.5, 3.1));
      ctx.scale(sx * lerp(1, 1.06, e), 1);
      const card = S.SIGILS[2]; // ЭПИЧЕСКОЕ
      ctx.drawImage(card, -card.width / 2, -card.height / 2);
      rrect(ctx, -card.width / 2, -card.height / 2, card.width, card.height, 30); ctx.clip();
      const fx = ((t * 0.5) % 1.4) * (card.width + 300) - card.width / 2 - 150;
      const fg = ctx.createLinearGradient(fx - 80, -card.height / 2, fx + 80, card.height / 2);
      fg.addColorStop(0, "rgba(255,255,255,0)");
      fg.addColorStop(0.5, "rgba(216,180,255,0.35)");
      fg.addColorStop(1, "rgba(255,255,255,0)");
      ctx.fillStyle = fg; ctx.fillRect(-card.width / 2, -card.height / 2, card.width, card.height);
    }
    ctx.restore();
  }
  sparkleBurst(ctx, tl, 2.52, cx, cy, { n: 16, dur: 0.9, dist: 240, ring: 240 });
  const la = eoc(seg(tl, 3.3, 3.8));
  if (la > 0) T(ctx, "ЭПИК? ЛЕГЕНДА? открой и увидишь", cx, 1330, { size: 44, alias: "ManropeXB", color: "#fff", alpha: la * (1 - seg(tl, 4.9, 5.35)) });
  vignette(ctx, 0.42);
}

/* --- дом Светика --- */
function house(ctx, t, o = {}) { // ~6.5s
  bg(ctx, t, 0.5);
  const tl = t;
  // wall + floor
  ctx.fillStyle = "#171326";
  ctx.fillRect(0, 300, W, 1130);
  ctx.fillStyle = "#241d33";
  ctx.fillRect(0, 1430, W, 490);
  ctx.strokeStyle = "rgba(255,255,255,0.05)"; ctx.lineWidth = 2;
  for (let i = 0; i < 6; i++) { ctx.beginPath(); ctx.moveTo(0, 320 + i * 190); ctx.lineTo(W, 320 + i * 190); ctx.stroke(); }
  // window
  ctx.save(); ctx.globalAlpha = 0.95; ctx.translate(190, 560); ctx.scale(0.8, 0.8);
  ctx.drawImage(S.WINDOW, -190, -235); ctx.restore();
  // fireplace
  const fx = 810, fy = 1140;
  ctx.fillStyle = "#2c2340";
  ctx.beginPath();
  ctx.moveTo(fx - 170, fy); ctx.lineTo(fx - 150, fy - 330);
  ctx.lineTo(fx + 150, fy - 330); ctx.lineTo(fx + 170, fy);
  ctx.closePath(); ctx.fill();
  ctx.fillStyle = "#120e1e";
  ctx.beginPath();
  ctx.moveTo(fx - 90, fy); ctx.lineTo(fx - 78, fy - 190);
  ctx.quadraticCurveTo(fx, fy - 230, fx + 78, fy - 190);
  ctx.lineTo(fx + 90, fy);
  ctx.closePath(); ctx.fill();
  // fire
  const fl = 0.7 + 0.3 * osc(t, 2.2);
  glowDot(ctx, fx, fy - 90, 130 * fl, "255,150,50", 0.5);
  ctx.fillStyle = "#ffb347";
  ctx.beginPath();
  ctx.moveTo(fx - 26, fy - 20);
  ctx.quadraticCurveTo(fx - 40, fy - 90 * fl, fx, fy - 130 * fl);
  ctx.quadraticCurveTo(fx + 40, fy - 90 * fl, fx + 26, fy - 20);
  ctx.closePath(); ctx.fill();
  ctx.fillStyle = "#ffe9a8";
  ctx.beginPath();
  ctx.moveTo(fx - 12, fy - 18);
  ctx.quadraticCurveTo(fx - 18, fy - 55 * fl, fx, fy - 80 * fl);
  ctx.quadraticCurveTo(fx + 18, fy - 55 * fl, fx + 12, fy - 18);
  ctx.closePath(); ctx.fill();
  // rug
  ctx.fillStyle = "rgba(176,108,255,0.25)";
  ctx.beginPath(); ctx.ellipse(W / 2, 1520, 300, 60, 0, 0, 7); ctx.fill();
  ctx.strokeStyle = "rgba(255,179,71,0.4)"; ctx.lineWidth = 4;
  ctx.beginPath(); ctx.ellipse(W / 2, 1520, 230, 42, 0, 0, 7); ctx.stroke();
  // table + lamp
  ctx.fillStyle = "#3a3050";
  rrect(ctx, 560, 1280, 200, 16, 8); ctx.fill();
  rrect(ctx, 580, 1296, 14, 110, 6); ctx.fill();
  rrect(ctx, 726, 1296, 14, 110, 6); ctx.fill();
  glowDot(ctx, 180, 1000, 150, "255,190,90", 0.25);
  ctx.fillStyle = "#3a3050"; rrect(ctx, 120, 1010, 120, 12, 6); ctx.fill();
  rrect(ctx, 172, 1022, 12, 90, 5); ctx.fill();
  // Светик floats by the fire
  const pop = eob(seg(tl, 0.3, 0.95));
  if (pop > 0) spirit(ctx, o.st || "hi", fx - 20, 900, 260 * clamp(pop, 0.001, 1.05), t, { bob: 14 });
  const h1 = eoc(seg(tl, 0.7, 1.25));
  if (h1 > 0) {
    T(ctx, "ДОМ СВЕТИКА", W / 2, 380, { size: 56, alias: "ManropeXB", color: C.amber, alpha: h1, glow: "rgba(255,170,60,0.6)" });
    T(ctx, "построй · обставь · смени тему и ауру", W / 2, 458, { size: 36, alias: "ManropeM", color: C.dim, alpha: eoc(seg(tl, 1.15, 1.65)) });
  }
  // furniture chips
  const chips = ["ковёр", "камин", "стол", "кровать", "окно", "аура"];
  chips.forEach((c, i) => {
    const p = eob(seg(tl, 1.7 + i * 0.22, 2.1 + i * 0.22));
    if (p <= 0) return;
    const col = i % 3, row = Math.floor(i / 3);
    const x = W / 2 + (col - 1) * 300, y = 1600 + row * 110;
    chip(ctx, c, x, y, { size: 32, color: C.text, bg: "rgba(30,26,52,0.85)", border: "rgba(255,179,71,0.45)", alpha: clamp(p, 0, 1) });
  });
  if (o.joke) {
    const jp = seg(tl, 4.2, 4.7), jOut = 1 - seg(tl, 6.0, 6.45);
    if (jp > 0 && jOut > 0) {
      ctx.save(); ctx.globalAlpha = jOut;
      bubble(ctx, 420, 1210, 560, 104, 1);
      T(ctx, "только не трогай камин.", 420, 1210, { size: 38, alias: "ManropeXB", color: C.text });
      ctx.restore();
    }
  }
  vignette(ctx, 0.45);
}

/* --- гонка/рейтинг --- */
function race(ctx, t) { // ~5.5s
  bg(ctx, t, 0.15);
  glyphRain(ctx, t, 0.4);
  embers(ctx, t, { n: 14, heat: 0.9 });
  const tl = t;
  headChip(ctx, "trophy.svg", "РЕЙТИНГ МИРА", C.gold);
  const h1 = eoc(seg(tl, 0.2, 0.7));
  if (h1 > 0) T(ctx, "кто назовёт вещество первым?", W / 2, 412, { size: 40, alias: "ManropeM", color: C.dim, alpha: h1 });
  // goal chip
  const g1 = eob(seg(tl, 0.7, 1.2));
  if (g1 > 0) chip(ctx, "цель дня: вещество из «Жизни»", W / 2, 520, { size: 32, color: C.teal, bg: "rgba(53,208,186,0.1)", border: "rgba(53,208,186,0.55)", alpha: clamp(g1, 0, 1) });
  // leaderboard rows
  const rows = [
    { t0: 1.3, who: "@мира", pts: "142", col: "255,179,71", me: false, mark: "первая в мире" },
    { t0: 1.7, who: "@ты", pts: "138", col: "53,208,186", me: true, mark: "уже близко" },
    { t0: 2.1, who: "@keks", pts: "120", col: "176,108,255", me: false, mark: "" },
  ];
  rows.forEach((r, i) => {
    const p = seg(tl, r.t0, r.t0 + 0.5);
    if (p <= 0) return;
    const y = 700 + i * 150;
    const x = lerp(W + 500, W / 2, eoc(p));
    ctx.save();
    ctx.globalAlpha = eoc(p);
    ctx.fillStyle = r.me ? "rgba(53,208,186,0.10)" : "rgba(13,16,28,0.9)";
    rrect(ctx, x - 470, y - 60, 940, 120, 30); ctx.fill();
    ctx.strokeStyle = r.me ? "rgba(53,208,186,0.8)" : "rgba(90,100,125,0.45)";
    ctx.lineWidth = r.me ? 3 : 2;
    rrect(ctx, x - 470, y - 60, 940, 120, 30); ctx.stroke();
    const ag = ctx.createLinearGradient(x - 410, y - 36, x - 340, y + 36);
    ag.addColorStop(0, `rgba(${r.col},0.95)`); ag.addColorStop(1, `rgba(${r.col},0.55)`);
    ctx.fillStyle = ag;
    ctx.beginPath(); ctx.arc(x - 375, y, 38, 0, 7); ctx.fill();
    T(ctx, r.who[1].toUpperCase(), x - 375, y + 1, { size: 36, alias: "ManropeXB", color: "#10131f" });
    T(ctx, r.who, x - 310, y - 26, { size: 34, alias: "ManropeB", color: C.dim, align: "left" });
    T(ctx, r.pts + " очков", x - 310, y + 24, { size: 42, alias: "ManropeXB", color: r.me ? C.teal : "#fff", align: "left" });
    if (r.mark) {
      chip(ctx, r.mark, x + 300, y, { size: 25, color: r.me ? C.teal : C.amber, bg: "rgba(255,255,255,0.05)", border: r.me ? "rgba(53,208,186,0.6)" : "rgba(255,179,71,0.6)" });
    }
    ctx.restore();
  });
  // you fly up
  const up = seg(tl, 3.6, 4.4);
  if (up > 0 && up < 1) {
    const y0 = 850, y1 = 700;
    const yy = lerp(y0, y1, eoc(up));
    ctx.strokeStyle = `rgba(53,208,186,${(1 - up) * 0.7})`;
    ctx.lineWidth = 4;
    ctx.beginPath(); ctx.moveTo(W / 2 - 470, yy + 80); ctx.lineTo(W / 2 - 470, yy - 90); ctx.stroke();
    T(ctx, "↑", W / 2 - 510, yy - 120, { size: 60, alias: "ManropeXB", color: C.teal, alpha: (1 - up) });
  }
  const a2 = eoc(seg(tl, 4.3, 4.9));
  if (a2 > 0) T(ctx, "слава закрепляется за первым", W / 2, 1280, { size: 42, alias: "ManropeXB", color: "#fff", alpha: a2 * (1 - seg(tl, 5.1, 5.5)) });
  vignette(ctx, 0.42);
}

/* --- лента (mini) --- */
function feed(ctx, t, o = {}) { // ~6.5s
  bg(ctx, t, 0.1);
  glyphRain(ctx, t, 0.8);
  embers(ctx, t, { n: 10, heat: 0.7 });
  const tl = t;
  const h1 = eoc(seg(tl, 0.15, 0.7)) * (1 - seg(tl, 5.7, 6.2));
  if (h1 > 0) {
    T(ctx, "Каждая пара —", W / 2, 400, { size: 60, alias: "ManropeSB", color: "#fff", alpha: h1 });
    T(ctx, "вопрос всему миру", W / 2, 486, { size: 60, alias: "ManropeXB", color: C.teal, alpha: h1, glow: "rgba(53,208,186,0.6)" });
  }
  const rows = [
    { t0: 1.3, user: "@мира", col: "255,179,71", thing: "РТУТЬ", tag: "впервые в мире" },
    { t0: 2.5, user: "@keks", col: "53,208,186", thing: "ГЛИНА", tag: "слой 2" },
    { t0: 3.7, user: "@ты", col: "176,108,255", thing: "СТЕКЛО", tag: "твоё первое" },
  ];
  rows.forEach((r, i) => {
    const p = seg(tl, r.t0, r.t0 + 0.5);
    const out = 1 - seg(tl, 5.4 + i * 0.08, 5.85 + i * 0.08);
    if (p <= 0 || out <= 0) return;
    feedRow(ctx, W / 2, 760 + i * 150, r.user, r.thing, r.col, r.tag, out, eoc(p), r.user === "@ты");
  });
  const nP = seg(tl, 4.9, 5.6);
  if (nP > 0) {
    T(ctx, "57 веществ. 58-е может открыть ТЫ", W / 2, 1330, { size: 50, alias: "ManropeXB", color: C.amber, alpha: eoc(nP) * (1 - seg(tl, 5.9, 6.4)), glow: "rgba(255,170,60,0.7)" });
  }
  vignette(ctx);
}

function feedRow(ctx, x, y, who, thing, rgb, tag, alpha = 1, slide = 1, mine = false) {
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.fillStyle = mine ? "rgba(53,208,186,0.10)" : "rgba(13,16,28,0.9)";
  rrect(ctx, x - 460, y - 58, 920, 116, 30); ctx.fill();
  ctx.strokeStyle = mine ? "rgba(53,208,186,0.8)" : "rgba(90,100,125,0.45)";
  ctx.lineWidth = mine ? 3 : 2;
  rrect(ctx, x - 460, y - 58, 920, 116, 30); ctx.stroke();
  const ag = ctx.createLinearGradient(x - 400, y - 36, x - 330, y + 36);
  ag.addColorStop(0, `rgba(${rgb},0.95)`); ag.addColorStop(1, `rgba(${rgb},0.55)`);
  ctx.fillStyle = ag;
  ctx.beginPath(); ctx.arc(x - 366, y, 37, 0, 7); ctx.fill();
  T(ctx, who[1].toUpperCase(), x - 366, y + 1, { size: 34, alias: "ManropeXB", color: "#10131f" });
  T(ctx, who, x - 302, y - 24, { size: 32, alias: "ManropeB", color: C.dim, align: "left" });
  T(ctx, thing, x - 302, y + 22, { size: 40, alias: "ManropeXB", color: "#fff", align: "left" });
  ctx.font = "24px ManropeB";
  const tw = ctx.measureText(tag).width + 36;
  rrect(ctx, x + 448 - tw, y - 24, tw, 46, 23);
  ctx.fillStyle = tag.includes("впервые") ? "rgba(255,179,71,0.16)" : "rgba(77,163,255,0.13)"; ctx.fill();
  ctx.strokeStyle = tag.includes("впервые") ? "rgba(255,179,71,0.7)" : (mine ? "rgba(53,208,186,0.7)" : "rgba(77,163,255,0.6)");
  ctx.lineWidth = 1.6; ctx.stroke();
  T(ctx, tag, x + 448 - tw / 2, y + 1, { size: 24, alias: "ManropeB", color: tag.includes("впервые") ? C.amber : (mine ? C.teal : C.blue) });
  ctx.restore();
}

/* --- офлайн (v1, переиспользование) --- */
function offline(ctx, t) {
  bg(ctx, t, 1);
  embers(ctx, t, { n: 10, heat: 0.6 });
  const tl = t;
  ctx.save(); ctx.globalAlpha = 0.95; ctx.translate(830, 250); ctx.drawImage(S.WINDOW, -190, -235); ctx.restore();
  ctx.fillStyle = "rgba(10,9,18,0.9)"; ctx.fillRect(0, 1430, W, H - 1430);
  cauldron(ctx, t, W / 2 - 20, 1360, 360, { dark: true, boil: 0.25 });
  ctx.save(); ctx.globalAlpha = 0.06; ctx.fillStyle = "#b8ccff";
  ctx.beginPath(); ctx.moveTo(900, 380); ctx.lineTo(1010, 380); ctx.lineTo(620, 1430); ctx.lineTo(330, 1430);
  ctx.closePath(); ctx.fill(); ctx.restore();
  const h1 = eoc(seg(tl, 0.15, 0.75));
  if (h1 > 0) {
    T(ctx, "Закроешь игру — петля", W / 2, 420, { size: 58, alias: "ManropeSB", color: "#fff", alpha: h1 });
    T(ctx, "НЕ остановится", W / 2, 506, { size: 66, alias: "ManropeXB", color: C.amber, alpha: h1, glow: "rgba(255,170,60,0.7)" });
  }
  const cP = seg(tl, 0.9, 6.4);
  if (cP > 0) {
    const val = Math.round(342 * eoe(cP));
    ctx.save(); ctx.translate(W / 2, 850);
    const bolt = svgImg("icons/bolt.svg", 96);
    ctx.drawImage(bolt, -48, -230, 96, 96);
    T(ctx, "+" + val, 0, 0, { size: 172, alias: "ManropeXB", color: C.gold, glow: "rgba(255,200,77,0.8)", glowBlur: 40 });
    T(ctx, "эфира накопил котёл", 0, 128, { size: 44, alias: "ManropeSB", color: C.dim });
    ctx.restore();
  }
  const b2 = seg(tl, 5.5, 6.0);
  if (b2 > 0) T(ctx, "Вернёшься — заберёшь ВСЁ", W / 2, 1080, { size: 56, alias: "ManropeXB", color: "#fff", alpha: eoc(b2), glow: "rgba(255,255,255,0.3)" });
  vignette(ctx, 0.5);
}

/* --- финал (параметризованный) --- */
function finale(ctx, t, o = {}) { // 50-60 (tl 0-10)
  bg(ctx, t, 0.35);
  embers(ctx, t, { n: 24, heat: 1.1 });
  const tl = t;
  const cx = W / 2;
  const rp = seg(tl, 0, 0.8);
  ctx.save();
  ctx.globalAlpha = 0.4 * eoe(rp);
  ctx.translate(cx, 870); ctx.rotate(t * 0.08);
  const RS = 300 + 660 * eoc(rp);
  ctx.drawImage(S.RING_AMBER, -RS / 2, -RS / 2, RS, RS);
  ctx.restore();
  const sp = seg(tl, 0, 0.7);
  if (sp > 0 && sp < 1) {
    ctx.strokeStyle = `rgba(255,220,160,${(1 - sp) * 0.8})`;
    ctx.lineWidth = 8 * (1 - sp) + 1;
    ctx.beginPath(); ctx.arc(cx, 870, eoc(sp) * 900, 0, 7); ctx.stroke();
  }
  const ip = seg(tl, 0.45, 1.15);
  if (ip > 0) {
    ctx.save();
    ctx.translate(cx, lerp(-200, 520, eob(ip)));
    ctx.rotate(Math.sin(t * 1.2) * 0.03);
    glowDot(ctx, 0, 0, 190, "255,170,60", 0.35);
    ctx.drawImage(S.APPICON, -110, -110, 220, 220);
    ctx.restore();
    sparkleBurst(ctx, tl, 0.8, cx, 520, { n: 12, dur: 0.9, dist: 200, ring: 210 });
  }
  const r1 = seg(tl, 1.15, 1.6);
  if (r1 > 0) T(ctx, "ALCHEMISTS LOOP", cx, 758, { size: 42, alias: "AlchRunic", color: C.amber, alpha: 0.85 * eoc(r1), spacing: 6 });
  const t1 = seg(tl, 1.35, 1.9);
  if (t1 > 0) T(ctx, "ПЕТЛЯ АЛХИМИКА", cx, 872 + (1 - eoc(t1)) * 36, { size: 100, alias: "ManropeXB", color: "#fff", glow: "rgba(255,255,255,0.4)", glowBlur: 30, alpha: eoc(t1), spacing: 2 });
  const t2 = seg(tl, 2.1, 2.6);
  if (t2 > 0) T(ctx, o.tagline || "варь · открывай · замыкай петлю", cx, 980, { size: 42, alias: "ManropeSB", color: C.dim, alpha: eoc(t2) });
  const cp = seg(tl, 2.8, 3.5);
  let sy = 1400;
  if (cp > 0) {
    sy = spirit(ctx, o.sticker || "celebrate", cx, 1300, 300 * clamp(eob(cp), 0.001, 1.05), t, { bob: 10 });
    const k = Math.floor((tl - 3.2) * 1.2);
    if (k >= 0 && tl > 3.2) sparkleBurst(ctx, tl, 3.2 + k / 1.2, cx + (rnd(k) - 0.5) * 300, sy + (rnd(k * 3) - 0.5) * 200, { n: 5, dur: 0.6, dist: 60, ring: 40 });
  }
  const cta = seg(tl, 3.9, 4.5);
  const ctaOut = 1 - seg(tl, 9.2, 9.8);
  if (cta > 0 && ctaOut > 0) {
    const bounce = 1 + 0.06 * Math.abs(Math.sin((t - 57.4) * 9)) * (t > 57.4 && t < 58.2 ? 1 : 0);
    ctx.save();
    ctx.globalAlpha = ctaOut;
    ctx.translate(cx, 1580);
    ctx.scale(clamp(eob(cta), 0.001, 1) * bounce, clamp(eob(cta), 0.001, 1) * bounce);
    const play = svgImg("icons/play.svg", 40);
    ctx.font = "40px ManropeXB";
    const label = o.cta || "Бесплатно · Android";
    const tw = ctx.measureText(label).width;
    const bw = tw + 150;
    rrect(ctx, -bw / 2, -58, bw, 116, 58);
    ctx.fillStyle = "rgba(53,208,186,0.12)"; ctx.fill();
    ctx.strokeStyle = C.teal; ctx.lineWidth = 3;
    ctx.shadowColor = "rgba(53,208,186,0.8)"; ctx.shadowBlur = 24;
    rrect(ctx, -bw / 2, -58, bw, 116, 58); ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.drawImage(play, -bw / 2 + 46, -20, 40, 40);
    T(ctx, label, 24, 2, { size: 40, alias: "ManropeXB", color: "#fff" });
    ctx.restore();
  }
  const dim = seg(tl, 9.3, 10);
  if (dim > 0) { ctx.fillStyle = `rgba(5,4,10,${dim * 0.6})`; ctx.fillRect(0, 0, W, H); }
  vignette(ctx, 0.45);
}

/* =====================================================================
 * CUTS
 * ===================================================================== */
const CUTS = {
  v1: {
    name: "Мир варит",
    out: "teaser-v1-mir-varit.mp4",
    accent: C.amber,
    scenes: [
      [0.0, 5.2, (c, t) => hookWorld(c, t)],
      [5.2, 11.4, (c, t) => baseJoke(c, t - 5.2)],
      [11.4, 19.4, (c, t) => worldExperiment(c, t - 11.4)],
      [19.4, 26.6, (c, t) => svetikShow(c, t - 19.4)],
      [26.6, 32.8, (c, t) => workshop(c, t - 26.6)],
      [32.8, 37.8, (c, t) => spring(c, t - 32.8)],
      [37.8, 44.2, (c, t) => sigilOpen(c, t - 37.8)],
      [44.2, 50.0, (c, t) => house(c, t - 44.2)],
      [50.0, 60.01, (c, t) => finale(c, t - 50.0, { cta: "Бесплатно · Android" })],
    ],
    flashes: [[9.4, "255,190,120", 0.5], [15.8, "200,160,255", 0.55], [39.9, "216,180,255", 0.4], [50.0, "255,235,200", 0.75], [57.6, "255,220,160", 0.3]],
    shakes: [[8.6, 5], [50.0, 15], [57.6, 6]],
    zooms: [[50.0, 0.05], [15.85, 0.03]],
  },
  v2: {
    name: "Светик-шоу",
    out: "teaser-v2-svetik-shou.mp4",
    accent: C.teal,
    scenes: [
      [0.0, 4.5, (c, t) => hookSvetik(c, t)],
      [4.5, 10.7, (c, t) => baseJoke(c, t - 4.5)],
      [10.7, 17.9, (c, t) => svetikShow(c, t - 10.7)],
      [17.9, 25.9, (c, t) => worldExperiment(c, t - 17.9)],
      [25.9, 30.9, (c, t) => spring(c, t - 25.9, { svetik: true })],
      [30.9, 37.6, (c, t) => house(c, t - 30.9, { joke: true })],
      [37.6, 43.8, (c, t) => workshop(c, t - 37.6)],
      [43.8, 50.0, (c, t) => sigilOpen(c, t - 43.8)],
      [50.0, 60.01, (c, t) => finale(c, t - 50.0, { cta: "Завари своего Светика", tagline: "он уже ждёт у котла" })],
    ],
    flashes: [[8.0, "255,190,120", 0.5], [22.3, "200,160,255", 0.55], [46.2, "216,180,255", 0.4], [50.0, "255,235,200", 0.75], [57.6, "255,220,160", 0.3]],
    shakes: [[7.6, 5], [50.0, 15], [57.6, 6]],
    zooms: [[50.0, 0.05], [22.35, 0.03]],
  },
  v3: {
    name: "58-е вещество",
    out: "teaser-v3-58e-veshestvo.mp4",
    accent: C.violet,
    scenes: [
      [0.0, 5.0, (c, t) => mysteryHook(c, t)],
      [5.0, 11.5, (c, t) => feed(c, t - 5.0)],
      [11.5, 19.5, (c, t) => worldExperiment(c, t - 11.5)],
      [19.5, 25.5, (c, t) => sigilOpen(c, t - 19.5)],
      [25.5, 32.5, (c, t) => svetikShow(c, t - 25.5, { noHead: true })],
      [32.5, 37.5, (c, t) => spring(c, t - 32.5)],
      [37.5, 43.2, (c, t) => race(c, t - 37.5)],
      [43.2, 50.0, (c, t) => offline(c, t - 43.2)],
      [50.0, 60.01, (c, t) => finale(c, t - 50.0, { cta: "Назови 58-е первым", tagline: "57 открыли. 58-е — свободно." })],
    ],
    flashes: [[9.8, "255,190,120", 0.5], [15.9, "200,160,255", 0.55], [21.6, "216,180,255", 0.4], [50.0, "255,235,200", 0.75], [57.6, "255,220,160", 0.3]],
    shakes: [[9.1, 5], [50.0, 15], [57.6, 6]],
    zooms: [[50.0, 0.05], [15.95, 0.03]],
  },
  v4: {
    name: "Дом алхимика",
    out: "teaser-v4-dom-alhimika.mp4",
    accent: C.gold,
    scenes: [
      [0.0, 5.0, (c, t) => hookCozy(c, t)],
      [5.0, 11.0, (c, t) => baseJoke(c, t - 5.0)],
      [11.0, 17.7, (c, t) => house(c, t - 11.0)],
      [17.7, 22.7, (c, t) => spring(c, t - 17.7)],
      [22.7, 29.7, (c, t) => offline(c, t - 22.7)],
      [29.7, 35.9, (c, t) => workshop(c, t - 29.7)],
      [35.9, 41.9, (c, t) => sigilOpen(c, t - 35.9)],
      [41.9, 50.0, (c, t) => svetikShow(c, t - 41.9)],
      [50.0, 60.01, (c, t) => finale(c, t - 50.0, { cta: "Он уже ждёт", tagline: "тёплый котёл · живой мир · петля", sticker: "wave" })],
    ],
    flashes: [[7.7, "255,190,120", 0.45], [15.65, "200,160,255", 0.5], [38.2, "216,180,255", 0.4], [50.0, "255,235,200", 0.7], [57.6, "255,220,160", 0.3]],
    shakes: [[7.2, 5], [50.0, 12], [57.6, 5]],
    zooms: [[50.0, 0.045], [15.7, 0.03]],
  },
  v5: {
    name: "Гонка",
    out: "teaser-v5-gonka.mp4",
    accent: "rgb(255,120,90)",
    scenes: [
      [0.0, 4.5, (c, t) => hookRace(c, t)],
      [4.5, 11.0, (c, t) => feed(c, t - 4.5)],
      [11.0, 16.6, (c, t) => baseJoke(c, t - 11.0)],
      [16.6, 24.6, (c, t) => worldExperiment(c, t - 16.6)],
      [24.6, 30.3, (c, t) => race(c, t - 24.6)],
      [30.3, 36.5, (c, t) => workshop(c, t - 30.3)],
      [36.5, 42.5, (c, t) => sigilOpen(c, t - 36.5)],
      [42.5, 47.6, (c, t) => svetikShow(c, t - 42.5, { startSticker: "cheer" })],
      [47.6, 50.0, (c, t) => spring(c, t - 47.6)],
      [50.0, 60.01, (c, t) => finale(c, t - 50.0, { cta: "Обгони мир", tagline: "первые в мире получают славу" })],
    ],
    flashes: [[9.35, "255,190,120", 0.5], [21.0, "200,160,255", 0.55], [39.0, "216,180,255", 0.4], [50.0, "255,235,200", 0.75], [57.6, "255,220,160", 0.3]],
    shakes: [[8.6, 5], [21.05, 7], [50.0, 16], [57.6, 6]],
    zooms: [[50.0, 0.055], [21.05, 0.035]],
  },
};

/* per-cut overlays/shake/zoom ---------------------------------------- */
function makeEvents(cut) {
  const boundaries = cut.scenes.slice(1).map(([t0]) => t0);
  const flashes = cut.flashes.map(([t, rgb, a]) => ({ t, rgb, a, d: 0.4 }));
  const shakes = cut.shakes.map(([t, a]) => ({ t, a }));
  const zooms = cut.zooms.map(([t, a]) => ({ t, a }));
  return { boundaries, flashes, shakes, zooms };
}

function frameFor(cut, ev, idx) {
  const t = idx / R.FPS;
  const canvas = R.createCanvas(R.W, R.H);
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = C.bg0;
  ctx.fillRect(0, 0, R.W, R.H);
  const sc = cut.scenes.find(([a, b]) => t >= a && t < b) || cut.scenes[cut.scenes.length - 1];
  const tl = (t - sc[0]) / (sc[1] - sc[0]);
  let zoom = 1 + 0.03 * tl;
  for (const z of ev.zooms) {
    const dt = t - z.t;
    if (dt >= 0 && dt < 0.8) zoom += z.a * Math.exp(-dt * 4.2);
  }
  let sx = 0, sy = 0;
  for (const s of ev.shakes) {
    const dt = t - s.t;
    if (dt >= 0 && dt < 0.5) {
      const k = s.a * Math.exp(-dt * 9);
      sx += k * (rnd(Math.floor(t * 90) * 3) - 0.5) * 2;
      sy += k * (rnd(Math.floor(t * 90) * 7) - 0.5) * 2;
    }
  }
  ctx.save();
  ctx.translate(R.W / 2 + sx, R.H / 2 + sy);
  ctx.scale(zoom, zoom);
  ctx.translate(-R.W / 2, -R.H / 2);
  sc[2](ctx, t);
  ctx.restore();
  // crossfades at boundaries
  for (const b of ev.boundaries) {
    const p = 1 - clamp(Math.abs(t - b) / 0.16, 0, 1);
    if (p > 0) { ctx.fillStyle = `rgba(5,4,10,${p})`; ctx.fillRect(0, 0, R.W, R.H); }
  }
  // flashes
  for (const f of ev.flashes) {
    const p = 1 - clamp((t - f.t) / f.d, 0, 1);
    if (p > 0 && t >= f.t) {
      ctx.fillStyle = `rgba(${f.rgb},${f.a * Math.pow(p, 1.6)})`;
      ctx.fillRect(0, 0, R.W, R.H);
    }
  }
  // progress line
  ctx.fillStyle = "rgba(255,179,71,0.55)";
  ctx.fillRect(0, 0, (t / R.DUR) * R.W, 6);
  return canvas;
}

module.exports = { CUTS, makeEvents, frameFor, init };

/* =====================================================================
 * v6 additions — hybrid of v2 + v3 with corrected game facts
 * ===================================================================== */

/* Хук: Светик + мост «мир варит без тебя» (6.5s) */
function hookSvetikBridge(ctx, t) {
  bg(ctx, t, 0.2);
  embers(ctx, t, { n: 18 });
  ctx.save(); ctx.globalAlpha = 0.14;
  ctx.translate(W / 2, 700); ctx.rotate(-t * 0.06);
  ctx.drawImage(S.RING_TEAL, -520, -520, 1040, 1040); ctx.restore();
  const pop = eob(seg(t, 0.15, 0.8));
  if (pop > 0) spirit(ctx, "hi", W / 2, 660, 400 * clamp(pop, 0.001, 1.06), t, { bob: 12 });
  sparkleBurst(ctx, t, 0.25, W / 2, 660, { n: 18, dur: 1.0 });
  const a1 = seg(t, 0.85, 1.4), a2 = seg(t, 1.6, 2.15), fade1 = 1 - seg(t, 3.1, 3.6);
  if (a1 > 0) {
    T(ctx, "Варю тут.", W / 2, 1010, { size: 72, alias: "ManropeXB", color: "#fff", alpha: eoc(a1) * fade1, glow: "rgba(255,255,255,0.3)" });
  }
  if (a2 > 0) {
    T(ctx, "Один. Скучно.", W / 2, 1110, { size: 56, alias: "ManropeSB", color: C.amber, alpha: eoc(a2) * fade1 });
  }
  // мост
  const b1 = eoc(seg(t, 3.5, 4.05));
  if (b1 > 0) {
    spirit(ctx, "look", W / 2, 660, 400, t, { bob: 12 });
    T(ctx, "Зато МИР — не скучает", W / 2, 1050, { size: 60, alias: "ManropeXB", color: C.teal, alpha: b1, glow: "rgba(53,208,186,0.6)" });
  }
  feedRow(ctx, W / 2, 1250, "@мира", "РТУТЬ", "255,179,71", "впервые в мире",
    eoc(seg(t, 4.3, 4.85)) * (1 - seg(t, 6.0, 6.45)), eoc(seg(t, 4.3, 4.85)));
  vignette(ctx, 0.4);
}

/* 500+ веществ и растёт (6s) */
function worldCount(ctx, t) {
  bg(ctx, t, 0.35);
  glyphRain(ctx, t, 0.4);
  embers(ctx, t, { n: 12, heat: 0.8 });
  const tl = t;
  const a1 = seg(tl, 0.25, 0.9);
  if (a1 > 0) {
    const pulse = 1 + 0.03 * Math.sin(t * 3);
    ctx.save();
    ctx.translate(W / 2, 720);
    ctx.scale(pulse, pulse);
    T(ctx, "500+", 0, 0, { size: 210, alias: "ManropeXB", color: C.amber, alpha: eoc(a1), glow: "rgba(255,170,60,0.8)", glowBlur: 46 });
    ctx.restore();
    T(ctx, "веществ уже создал мир", W / 2, 880, { size: 46, alias: "ManropeSB", color: C.dim, alpha: eoc(a1) });
  }
  feedRow(ctx, W / 2, 1080, "@kcir", "ЗВЁЗДНАЯ ПЫЛЬ", "176,108,255", "слой 6",
    eoc(seg(tl, 1.8, 2.35)), eoc(seg(tl, 1.8, 2.35)));
  feedRow(ctx, W / 2, 1220, "@лиса", "ЛУННЫЙ УКСУС", "53,208,186", "эпическое",
    eoc(seg(tl, 2.6, 3.15)), eoc(seg(tl, 2.6, 3.15)));
  const a2 = eoc(seg(tl, 3.7, 4.25));
  if (a2 > 0) T(ctx, "следующее вещество ещё не существует", W / 2, 1400, { size: 46, alias: "ManropeSB", color: "#fff", alpha: a2 * (1 - seg(tl, 5.1, 5.5)) });
  const a3 = eoc(seg(tl, 4.6, 5.15));
  if (a3 > 0) T(ctx, "имя ему придумает ИИ", W / 2, 1500, { size: 56, alias: "ManropeXB", color: C.amber, alpha: a3, glow: "rgba(255,170,60,0.75)" });
  vignette(ctx, 0.5);
}

/* Офлайн v2: эфир + вещества + мастерство, и всё прокачивается (6.5s) */
function offline2(ctx, t) {
  bg(ctx, t, 1);
  embers(ctx, t, { n: 10, heat: 0.6 });
  const tl = t;
  ctx.save(); ctx.globalAlpha = 0.95; ctx.translate(830, 250); ctx.drawImage(S.WINDOW, -190, -235); ctx.restore();
  ctx.fillStyle = "rgba(10,9,18,0.9)"; ctx.fillRect(0, 1430, W, H - 1430);
  cauldron(ctx, t, W / 2 - 20, 1400, 330, { dark: true, boil: 0.25 });
  ctx.save(); ctx.globalAlpha = 0.06; ctx.fillStyle = "#b8ccff";
  ctx.beginPath(); ctx.moveTo(900, 380); ctx.lineTo(1010, 380); ctx.lineTo(620, 1430); ctx.lineTo(330, 1430);
  ctx.closePath(); ctx.fill(); ctx.restore();
  const h1 = eoc(seg(tl, 0.15, 0.7));
  if (h1 > 0) {
    T(ctx, "Закроешь игру — петля", W / 2, 420, { size: 56, alias: "ManropeSB", color: "#fff", alpha: h1 });
    T(ctx, "НЕ остановится", W / 2, 504, { size: 64, alias: "ManropeXB", color: C.amber, alpha: h1, glow: "rgba(255,170,60,0.7)" });
  }
  // три счётчика: эфир / вещества / мастерство
  const rows = [
    { t0: 0.9, t1: 3.0, val: 342, label: "эфира", icon: "bolt.svg", col: C.gold, y: 720 },
    { t0: 2.6, t1: 4.2, val: 12, label: "веществ варит мастерская", icon: "flask.svg", col: C.teal, y: 950 },
    { t0: 3.7, t1: 5.0, val: 3, label: "мастерства", icon: "star.svg", col: C.violet, y: 1150 },
  ];
  rows.forEach((r) => {
    const p = seg(tl, r.t0, r.t1);
    if (p <= 0) return;
    const out = 1 - seg(tl, 5.6, 6.1);
    const val = Math.round(r.val * eoe(p));
    const e = eob(seg(tl, r.t0, r.t0 + 0.4));
    ctx.save();
    ctx.globalAlpha = out;
    ctx.translate(W / 2, r.y);
    ctx.scale(clamp(e, 0.001, 1), clamp(e, 0.001, 1));
    const ic = svgImg("icons/" + r.icon, 64);
    ctx.drawImage(ic, -32, -160, 64, 64);
    T(ctx, "+" + val, 0, 0, { size: 108, alias: "ManropeXB", color: r.col, glow: null });
    T(ctx, r.label, 0, 84, { size: 36, alias: "ManropeSB", color: C.dim });
    ctx.restore();
  });
  // прокачка
  const u1 = eoc(seg(tl, 5.0, 5.5));
  if (u1 > 0) {
    T(ctx, "и всё это прокачивается", W / 2, 1330, { size: 46, alias: "ManropeXB", color: "#fff", alpha: u1 * (1 - seg(tl, 6.0, 6.4)), glow: "rgba(255,255,255,0.3)" });
  }
  vignette(ctx, 0.5);
}

/* Ритуал артефакта (6.5s) */
function artifactRitual(ctx, t) {
  bg(ctx, t, 0.25);
  embers(ctx, t, { n: 16 });
  const tl = t;
  const cx = W / 2, cy = 930;
  ctx.save(); ctx.globalAlpha = 0.14;
  ctx.translate(cx, cy); ctx.rotate(t * 0.07);
  ctx.drawImage(S.RING_AMBER, -540, -540, 1080, 1080); ctx.restore();
  const h1 = eoc(seg(tl, 0.15, 0.65));
  if (h1 > 0) T(ctx, "ТРАНСМУТАЦИОННЫЙ РИТУАЛ", cx, 320, { size: 50, alias: "ManropeXB", color: C.violet, alpha: h1, spacing: 2, glow: "rgba(176,108,255,0.6)" });
  const h2 = eoc(seg(tl, 0.55, 1.05));
  if (h2 > 0) T(ctx, "рецепт превращается в артефакт твоей лаборатории", cx, 402, { size: 36, alias: "ManropeM", color: C.dim, alpha: h2 });

  const flip = seg(tl, 1.6, 2.4);
  const backP = seg(tl, 0.4, 1.4);
  const endOut = 1 - seg(tl, 5.9, 6.4);
  const y = cy + Math.sin(t * 1.2) * 8;
  if (endOut > 0) {
    ctx.save();
    ctx.globalAlpha = endOut;
    ctx.translate(cx, y);
    if (flip < 0.5) {
      const sx = Math.max(0.02, Math.cos(flip * Math.PI));
      ctx.scale(sx * lerp(0.92, 1, eob(backP)), 1);
      ctx.fillStyle = "rgba(15,17,30,0.98)";
      rrect(ctx, -180, -235, 360, 470, 28); ctx.fill();
      ctx.strokeStyle = "rgba(150,110,220,0.8)"; ctx.lineWidth = 3;
      rrect(ctx, -180, -235, 360, 470, 28); ctx.stroke();
      ctx.save();
      ctx.globalAlpha = 0.55 * endOut;
      ctx.rotate(t * 0.1);
      ctx.drawImage(S.RING_AMBER, -150, -150, 300, 300);
      ctx.restore();
      T(ctx, "?", 0, 10, { size: 130, alias: "ManropeXB", color: C.dim, alpha: 1 - flip * 1.2 });
    } else {
      const sx = Math.max(0.02, -Math.cos(flip * Math.PI));
      const e = eob(seg(tl, 2.4, 3.0));
      ctx.scale(sx * lerp(1, 1.07, e), 1);
      const card = S.SIGILS[2];
      ctx.drawImage(card, -card.width / 2, -card.height / 2);
      rrect(ctx, -card.width / 2, -card.height / 2, card.width, card.height, 30); ctx.clip();
      const fx = ((t * 0.5) % 1.4) * (card.width + 300) - card.width / 2 - 150;
      const fg = ctx.createLinearGradient(fx - 80, -card.height / 2, fx + 80, card.height / 2);
      fg.addColorStop(0, "rgba(255,255,255,0)");
      fg.addColorStop(0.5, "rgba(216,180,255,0.38)");
      fg.addColorStop(1, "rgba(255,255,255,0)");
      ctx.fillStyle = fg; ctx.fillRect(-card.width / 2, -card.height / 2, card.width, card.height);
    }
    ctx.restore();
  }
  sparkleBurst(ctx, tl, 2.42, cx, cy, { n: 18, dur: 1.0, dist: 260, ring: 260 });
  // прокачка лаборатории
  const c1 = eob(seg(tl, 3.0, 3.5)), cOut = 1 - seg(tl, 5.9, 6.35);
  if (c1 > 0 && cOut > 0) {
    ctx.save();
    ctx.globalAlpha = cOut;
    chip(ctx, "+40 к капу эфира за комплект", cx, 1330, { size: 34, color: C.gold, bg: "rgba(255,179,71,0.12)", border: "rgba(255,179,71,0.6)", alpha: clamp(c1, 0, 1) });
    const c2 = eob(seg(tl, 3.6, 4.1));
    if (c2 > 0) chip(ctx, "артефакты уникальны для тебя", cx, 1450, { size: 32, color: "#e6d6ff", bg: "rgba(176,108,255,0.12)", border: "rgba(176,108,255,0.6)", alpha: clamp(c2, 0, 1) });
    ctx.restore();
  }
  vignette(ctx, 0.42);
}

/* Дом: игрок обставляет комнату (6.5s) */
function houseDecor(ctx, t) {
  bg(ctx, t, 0.45);
  const tl = t;
  // стены и пол
  ctx.fillStyle = "#171326";
  ctx.fillRect(0, 320, W, 1110);
  ctx.fillStyle = "#241d33";
  ctx.fillRect(0, 1430, W, 490);
  const h1 = eoc(seg(tl, 0.15, 0.65));
  if (h1 > 0) {
    T(ctx, "ДОМ СВЕТИКА", W / 2, 250, { size: 56, alias: "ManropeXB", color: C.amber, alpha: h1, glow: "rgba(255,170,60,0.6)" });
    T(ctx, "построй и обставь — вещь за вещью", W / 2, 328, { size: 34, alias: "ManropeM", color: C.dim, alpha: eoc(seg(tl, 0.5, 1.0)) });
  }
  //-flyIn helper: p=0..1
  const fly = (p) => { const e = eob(clamp(p, 0, 1)); const y = (1 - e) * -260; const s = clamp(e, 0.001, 1); return { y, s }; };
  const price = (x, y2, txt, p) => {
    if (p <= 0 || p >= 1) return;
    chip(ctx, txt, x, y2, { size: 24, color: C.gold, bg: "rgba(255,179,71,0.10)", border: "rgba(255,179,71,0.5)", alpha: clamp(p, 0, 1) * (1 - seg(tl, p * 0.999 + 0.6, p * 0.999 + 0.95)) });
  };
  // окно (влетает слева) 0.8
  {
    const p = seg(tl, 0.8, 1.3);
    if (p > 0) {
      const e = eoc(p);
      ctx.save(); ctx.globalAlpha = e;
      ctx.translate(lerp(-400, 185, e), 640); ctx.scale(0.72, 0.72);
      ctx.drawImage(S.WINDOW, -190, -235); ctx.restore();
      price(185, 850, "120 ⚡", p);
    }
  }
  // ковёр (падает) 1.5
  {
    const p = seg(tl, 1.5, 2.0);
    if (p > 0) {
      const f = fly(p);
      ctx.save(); ctx.globalAlpha = clamp(p * 2, 0, 1);
      ctx.translate(W / 2, 1560 + f.y * 0.4); ctx.scale(f.s, f.s * 0.9);
      ctx.fillStyle = "rgba(176,108,255,0.28)";
      ctx.beginPath(); ctx.ellipse(0, 0, 300, 58, 0, 0, 7); ctx.fill();
      ctx.strokeStyle = "rgba(255,179,71,0.45)"; ctx.lineWidth = 4;
      ctx.beginPath(); ctx.ellipse(0, 0, 225, 40, 0, 0, 7); ctx.stroke();
      ctx.restore();
      price(W / 2, 1650, "80 ⚡", p);
    }
  }
  // стол 2.2
  {
    const p = seg(tl, 2.2, 2.7);
    if (p > 0) {
      const f = fly(p);
      ctx.save(); ctx.globalAlpha = clamp(p * 2, 0, 1);
      ctx.translate(660, 1285 + f.y); ctx.scale(f.s, f.s);
      ctx.fillStyle = "#3a3050";
      rrect(ctx, -100, -8, 200, 16, 8); ctx.fill();
      rrect(ctx, -80, 8, 14, 110, 6); ctx.fill();
      rrect(ctx, 66, 8, 14, 110, 6); ctx.fill();
      ctx.restore();
      price(660, 1150, "60 ⚡", p);
    }
  }
  // кровать 2.9
  {
    const p = seg(tl, 2.9, 3.4);
    if (p > 0) {
      const f = fly(p);
      ctx.save(); ctx.globalAlpha = clamp(p * 2, 0, 1);
      ctx.translate(200, 1300 + f.y); ctx.scale(f.s, f.s);
      ctx.fillStyle = "#3a3050";
      rrect(ctx, -130, -30, 260, 70, 16); ctx.fill();
      ctx.fillStyle = "#4a3d66";
      rrect(ctx, -130, -52, 70, 46, 12); ctx.fill();
      ctx.fillStyle = "rgba(176,108,255,0.5)";
      rrect(ctx, -118, -24, 236, 34, 10); ctx.fill();
      ctx.restore();
      price(200, 1190, "150 ⚡", p);
    }
  }
  // камин 3.6 + огонь
  {
    const p = seg(tl, 3.6, 4.1);
    if (p > 0) {
      const f = fly(p);
      ctx.save(); ctx.globalAlpha = clamp(p * 2, 0, 1);
      ctx.translate(830, 1200 + f.y); ctx.scale(f.s, f.s);
      ctx.fillStyle = "#2c2340";
      ctx.beginPath();
      ctx.moveTo(-170, 240); ctx.lineTo(-150, -90);
      ctx.lineTo(150, -90); ctx.lineTo(170, 240);
      ctx.closePath(); ctx.fill();
      ctx.fillStyle = "#120e1e";
      ctx.beginPath();
      ctx.moveTo(-90, 240); ctx.lineTo(-78, 50);
      ctx.quadraticCurveTo(0, 10, 78, 50);
      ctx.lineTo(90, 240);
      ctx.closePath(); ctx.fill();
      ctx.restore();
      // огонь появляется после
      const fp = seg(tl, 4.15, 4.55);
      if (fp > 0) {
        const fl = clamp(fp, 0, 1) * (0.75 + 0.25 * osc(t, 2.2));
        const fy = 1395, fx2 = 830;
        glowDot(ctx, fx2, fy - 40, 120, "255,150,50", 0.5 * fl);
        ctx.fillStyle = "#ffb347";
        ctx.beginPath();
        ctx.moveTo(fx2 - 26, fy);
        ctx.quadraticCurveTo(fx2 - 42, fy - 70 * fl, fx2, fy - 115 * fl);
        ctx.quadraticCurveTo(fx2 + 42, fy - 70 * fl, fx2 + 26, fy);
        ctx.closePath(); ctx.fill();
        ctx.fillStyle = "#ffe9a8";
        ctx.beginPath();
        ctx.moveTo(fx2 - 12, fy - 2);
        ctx.quadraticCurveTo(fx2 - 18, fy - 50 * fl, fx2, fy - 78 * fl);
        ctx.quadraticCurveTo(fx2 + 18, fy - 50 * fl, fx2 + 12, fy - 2);
        ctx.closePath(); ctx.fill();
      }
      price(830, 940, "200 ⚡", p);
    }
  }
  // Светик появляется 4.5
  {
    const p = eob(seg(tl, 4.5, 5.1));
    if (p > 0) {
      spirit(ctx, "celebrate", 500, 1050, 230 * clamp(p, 0.001, 1.05), t, { bob: 12 });
      sparkleBurst(ctx, tl, 4.6, 500, 1050, { n: 12, dur: 0.8, dist: 140, ring: 150 });
    }
  }
  const a2 = eoc(seg(tl, 5.3, 5.85));
  if (a2 > 0) T(ctx, "каждая вещь — своя. каждый дом — твой.", W / 2, 1720, { size: 40, alias: "ManropeXB", color: "#fff", alpha: a2 * (1 - seg(tl, 6.0, 6.4)) });
  vignette(ctx, 0.45);
}

/* v6 — финальный гибрид: Светик-хук + 500+ + эксперимент мира */
CUTS.v6 = {
  name: "Гибрид",
  out: "teaser-v6-hybrid.mp4",
  accent: C.amber,
  scenes: [
    [0.0, 6.5, (c, t) => hookSvetikBridge(c, t)],
    [6.5, 12.5, (c, t) => worldCount(c, t - 6.5)],
    [12.5, 19.5, (c, t) => worldExperiment(c, t - 12.5)],
    [19.5, 24.5, (c, t) => baseJoke(c, t - 19.5)],
    [24.5, 30.5, (c, t) => svetikShow(c, t - 24.5)],
    [30.5, 37.0, (c, t) => offline2(c, t - 30.5)],
    [37.0, 43.5, (c, t) => artifactRitual(c, t - 37.0)],
    [43.5, 50.0, (c, t) => houseDecor(c, t - 43.5)],
    [50.0, 60.01, (c, t) => finale(c, t - 50.0, { cta: "Назови следующее вещество", tagline: "мир уже варит — не опоздай" })],
  ],
  flashes: [[15.9, "200,160,255", 0.55], [21.3, "255,190,120", 0.45], [32.5, "255,200,120", 0.3], [39.2, "216,180,255", 0.45], [47.3, "255,190,120", 0.3], [50.0, "255,235,200", 0.75], [57.6, "255,220,160", 0.3]],
  shakes: [[14.5, 6], [50.0, 15], [57.6, 6]],
  zooms: [[50.0, 0.05], [15.95, 0.035], [39.25, 0.03]],
};
