#!/usr/bin/env node
/* Alchemist's Loop — 60s vertical teaser renderer.
 * Atelier composition: 1080x1920@30, deterministic, ffmpeg runtime.
 *
 * Usage:
 *   node src/render.js --still <time> <out.png>   render one probe frame
 *   node src/render.js <start> <end> <outdir>     render frames [start,end)
 */
const fs = require("fs");
const path = require("path");
const { createCanvas, GlobalFonts, loadImage, Path2D } = require("@napi-rs/canvas");
const { Resvg } = require("@resvg/resvg-js");

const ROOT = __dirname + "/..";
const W = 1080, H = 1920, FPS = 30, DUR = 60, TOTAL = FPS * DUR;

/* ---------- fonts ---------- */
GlobalFonts.registerFromPath(ROOT + "/assets/fonts/Manrope-Regular.ttf", "ManropeR");
GlobalFonts.registerFromPath(ROOT + "/assets/fonts/Manrope-Medium.ttf", "ManropeM");
GlobalFonts.registerFromPath(ROOT + "/assets/fonts/Manrope-SemiBold.ttf", "ManropeSB");
GlobalFonts.registerFromPath(ROOT + "/assets/fonts/Manrope-Bold.ttf", "ManropeB");
GlobalFonts.registerFromPath(ROOT + "/assets/fonts/Manrope-ExtraBold.ttf", "ManropeXB");
GlobalFonts.registerFromPath(ROOT + "/assets/fonts/Alchemist-Runic.ttf", "AlchRunic");

/* ---------- palette (from the game UI) ---------- */
const C = {
  bg0: "#0d0b14", bg1: "#141126", bg2: "#1a1730",
  panel: "#101724", panel2: "#141c2e",
  teal: "#35d0ba", tealDim: "#1f6e64",
  amber: "#ffb347", gold: "#ffc94d", ember: "#ff8a3c",
  text: "#e8ecf4", dim: "#8a94a8", dimmer: "#5a6376",
  water: "#58a6ff", fire: "#ff7043", earth: "#c98d5a", wind: "#9be8dd",
  grey: "#9aa4b2", blue: "#4da3ff", violet: "#b06cff",
};

/* ---------- math ---------- */
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const seg = (t, a, b) => clamp((t - a) / (b - a || 1e-9), 0, 1);
const eoc = t => 1 - Math.pow(1 - t, 3);
const eic = t => t * t * t;
const eio = t => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
const eoe = t => (t >= 1 ? 1 : 1 - Math.pow(2, -10 * t));
const eob = t => { const c = 1.70158, c3 = c + 1; return 1 + c3 * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2); };
const osc = (t, p = 1, ph = 0) => Math.sin(t * p * Math.PI * 2 + ph);
const rnd = i => { const x = Math.sin(i * 127.1 + 311.7) * 43758.5453; return x - Math.floor(x); };

/* ---------- text ---------- */
function fontStr(size, alias) { return `${size}px ${alias}`; }
function measure(str, size, alias, spacing = 0) {
  const cv = createCanvas(8, 8); const x = cv.getContext("2d");
  x.font = fontStr(size, alias);
  if (!spacing) return x.measureText(str).width;
  const chars = [...str];
  let w = 0; for (const c of chars) w += x.measureText(c).width + spacing;
  return w - spacing;
}
function T(ctx, str, x, y, o = {}) {
  const size = o.size ?? 48, alias = o.alias ?? "ManropeSB";
  const align = o.align ?? "center";
  ctx.save();
  ctx.font = fontStr(size, alias);
  ctx.textBaseline = o.base ?? "middle";
  ctx.textAlign = align;
  ctx.globalAlpha *= (o.alpha ?? 1);
  if (o.glow) { ctx.shadowColor = o.glow; ctx.shadowBlur = o.glowBlur ?? 22; }
  ctx.fillStyle = o.color ?? C.text;
  if (o.stroke) { ctx.strokeStyle = o.stroke; ctx.lineWidth = o.strokeW ?? 2; }
  if (o.spacing) {
    const chars = [...str];
    const widths = chars.map(c => ctx.measureText(c).width);
    const total = widths.reduce((a, b) => a + b, 0) + o.spacing * (chars.length - 1);
    let cx = align === "center" ? x - total / 2 : (align === "right" ? x - total : x);
    ctx.textAlign = "left";
    for (let i = 0; i < chars.length; i++) {
      if (o.stroke) ctx.strokeText(chars[i], cx, y);
      ctx.fillText(chars[i], cx, y);
      cx += widths[i] + o.spacing;
    }
  } else {
    if (o.stroke) ctx.strokeText(str, x, y);
    ctx.fillText(str, x, y);
  }
  ctx.restore();
}
/* rich line: parts [[text, color, glow?], ...] drawn as one centered line */
function TR(ctx, parts, x, y, o = {}) {
  const size = o.size ?? 48, alias = o.alias ?? "ManropeSB", sp = o.spacing ?? 0;
  const cv = createCanvas(8, 8); const m = cv.getContext("2d");
  m.font = fontStr(size, alias);
  let total = 0;
  const pw = parts.map(([s]) => {
    let w = 0; for (const c of [...s]) w += m.measureText(c).width + sp;
    return w - sp;
  });
  total = pw.reduce((a, b) => a + b, 0) + sp * (parts.length - 1);
  let cx = x - total / 2;
  parts.forEach(([s, col, glow], i) => {
    T(ctx, s, cx + pw[i] / 2, y, { ...o, align: "center", color: col, glow: glow ?? null, spacing: sp, alpha: (o.alpha ?? 1) });
    cx += pw[i] + sp;
  });
}

/* ---------- shapes ---------- */
function rrect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}
function glowDot(ctx, x, y, r, color, a = 1) {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, `rgba(${color},${0.9 * a})`);
  g.addColorStop(0.4, `rgba(${color},${0.35 * a})`);
  g.addColorStop(1, `rgba(${color},0)`);
  ctx.save(); ctx.globalAlpha = 1; ctx.fillStyle = g;
  ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill(); ctx.restore();
}

/* ---------- assets (prefetched, sync access after initAssets) ---------- */
const imgCache = new Map();
const imgKey = (rel, widthPx, tint) => rel + "|" + widthPx + "|" + (tint || "");
async function preloadSvg(rel, widthPx, tint) {
  const key = imgKey(rel, widthPx, tint);
  if (imgCache.has(key)) return;
  let svg = fs.readFileSync(ROOT + "/assets/" + rel, "utf8");
  if (tint) svg = svg.replace(/#FFFFFF|currentColor/g, tint);
  const r = new Resvg(Buffer.from(svg), { fitTo: { mode: "width", value: widthPx } });
  imgCache.set(key, await loadImage(r.render().asPng()));
}
function svgImg(rel, widthPx, tint) {
  const img = imgCache.get(imgKey(rel, widthPx, tint));
  if (!img) throw new Error("svg not prefetched: " + rel + " " + widthPx + " " + tint);
  return img;
}
async function preloadPng(rel) {
  const key = rel;
  if (imgCache.has(key)) return;
  imgCache.set(key, await loadImage(fs.readFileSync(ROOT + "/assets/" + rel)));
}
function pngImg(rel) {
  const img = imgCache.get(rel);
  if (!img) throw new Error("png not prefetched: " + rel);
  return img;
}

async function initAssets() {
  await Promise.all([
    preloadSvg("icons/drop.svg", 81),
    preloadSvg("icons/fire.svg", 81),
    preloadSvg("icons/flask.svg", 34),
    preloadSvg("icons/bolt.svg", 30),
    preloadSvg("icons/bolt.svg", 96),
    preloadSvg("icons/play.svg", 40),
    
    preloadPng("stickers/hi.png"),
    preloadPng("stickers/celebrate.png"),
    preloadPng("stickers/think.png"),
    preloadPng("stickers/look.png"),
    preloadPng("stickers/star.png"),
  ]);
}

/* alchemist glyph paths (from tools/alchemist-glyphs.svg) */
const glyphSvg = fs.readFileSync(ROOT + "/assets/glyphs.svg", "utf8");
function glyphPath(letter) {
  const id = letter.length === 1 ? `glyph-${letter}"` : `glyph-${letter}`;
  const m = glyphSvg.match(new RegExp(`<symbol id="${id.replace('"', '')}"[^>]*>([\\s\\S]*?)</symbol>`));
  if (!m) return null;
  const ds = [...m[1].matchAll(/ d="([^"]+)"/g)].map(x => x[1]);
  return ds;
}
const ringWord = "ALCHEMISTSLOOP";

/* pre-rendered: rune ring */
function renderRing(px, color, glyphScale = 0.30, lw = 3) {
  const S = px, cv = createCanvas(S, S), ctx = cv.getContext("2d");
  const cx = S / 2, cy = S / 2, R = S * 0.46;
  ctx.strokeStyle = color; ctx.lineWidth = lw;
  ctx.globalAlpha = 0.9;
  ctx.beginPath(); ctx.arc(cx, cy, R, 0, 7); ctx.stroke();
  ctx.globalAlpha = 0.45;
  ctx.beginPath(); ctx.arc(cx, cy, R * 0.90, 0, 7); ctx.stroke();
  ctx.beginPath(); ctx.arc(cx, cy, R * 1.06, 0, 7); ctx.stroke();
  const n = ringWord.length;
  for (let i = 0; i < n; i++) {
    const ds = glyphPath(ringWord[i]);
    if (!ds) continue;
    const a = (i / n) * Math.PI * 2 - Math.PI / 2;
    const gx = cx + Math.cos(a) * R, gy = cy + Math.sin(a) * R;
    const gsz = S * glyphScale;
    ctx.save();
    ctx.translate(gx, gy);
    ctx.rotate(a + Math.PI / 2);
    ctx.globalAlpha = 0.55;
    ctx.strokeStyle = color; ctx.lineWidth = lw * 1.1;
    ctx.beginPath(); ctx.arc(0, 0, gsz * 0.72, 0, 7); ctx.stroke();
    ctx.globalAlpha = 0.9;
    for (const d of ds) {
      const p = new Path2D(d);
      ctx.save();
      ctx.translate(-gsz / 2, -gsz / 2);
      ctx.scale(gsz / 100, gsz / 100);
      ctx.stroke(p);
      ctx.restore();
    }
    ctx.restore();
  }
  return cv;
}
const RING_MAKER = (px, color) => renderRing(px, color, 0.155, 2.4);
let RING_AMBER, RING_TEAL, STARS, WINDOW, REVEAL, SIGILS, APPICON;

/* pre-rendered: starfield */
function makeSTARS() {
  const cv = createCanvas(W, H), ctx = cv.getContext("2d");
  for (let i = 0; i < 130; i++) {
    const x = rnd(i * 3 + 1) * W, y = rnd(i * 3 + 2) * H, r = 0.6 + rnd(i * 3 + 3) * 1.6;
    ctx.globalAlpha = 0.25 + rnd(i * 7) * 0.5;
    ctx.fillStyle = i % 7 === 0 ? C.amber : "#cfd8ea";
    ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill();
  }
  return cv;
}

/* pre-rendered: night window with moon */
function makeWINDOW() {
  const w = 380, h = 470, cv = createCanvas(w, h), ctx = cv.getContext("2d");
  ctx.fillStyle = "#0a0912";
  rrect(ctx, 10, 10, w - 20, h - 20, 60); ctx.fill();
  ctx.save(); rrect(ctx, 10, 10, w - 20, h - 20, 60); ctx.clip();
  const sky = ctx.createLinearGradient(0, 0, 0, h);
  sky.addColorStop(0, "#1b2140"); sky.addColorStop(1, "#101426");
  ctx.fillStyle = sky; ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < 26; i++) {
    ctx.globalAlpha = 0.3 + rnd(i * 5) * 0.6;
    ctx.fillStyle = "#dfe8ff";
    ctx.beginPath(); ctx.arc(rnd(i * 9) * w, rnd(i * 11) * h * 0.7, 0.8 + rnd(i * 13) * 1.4, 0, 7); ctx.fill();
  }
  ctx.globalAlpha = 1;
  const mx = w * 0.62, my = h * 0.34, mr = 56;
  glowDot(ctx, mx, my, mr * 3.2, "190,210,255", 0.5);
  ctx.fillStyle = "#e9efff"; ctx.beginPath(); ctx.arc(mx, my, mr, 0, 7); ctx.fill();
  ctx.fillStyle = "#cdd8f2"; ctx.beginPath(); ctx.arc(mx - 18, my - 10, 9, 0, 7); ctx.fill();
  ctx.beginPath(); ctx.arc(mx + 14, my + 18, 6, 0, 7); ctx.fill();
  ctx.beginPath(); ctx.arc(mx + 20, my - 22, 4.5, 0, 7); ctx.fill();
  ctx.restore();
  ctx.strokeStyle = "#3a3552"; ctx.lineWidth = 12;
  rrect(ctx, 10, 10, w - 20, h - 20, 60); ctx.stroke();
  ctx.lineWidth = 7;
  ctx.beginPath(); ctx.moveTo(w / 2, 12); ctx.lineTo(w / 2, h - 12); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(12, h / 2); ctx.lineTo(w - 12, h / 2); ctx.stroke();
  return cv;
}

/* pre-rendered: reveal card (ПАР) */
function makeREVEAL() {
  const w = 780, h = 500, cv = createCanvas(w, h), ctx = cv.getContext("2d");
  ctx.fillStyle = "rgba(13,16,28,0.96)";
  rrect(ctx, 8, 8, w - 16, h - 16, 34); ctx.fill();
  ctx.strokeStyle = C.teal; ctx.lineWidth = 3;
  ctx.shadowColor = "rgba(53,208,186,0.8)"; ctx.shadowBlur = 26;
  rrect(ctx, 8, 8, w - 16, h - 16, 34); ctx.stroke();
  ctx.shadowBlur = 0;
  // corner runes
  ctx.strokeStyle = "rgba(53,208,186,0.55)"; ctx.lineWidth = 2.5;
  const L = 26, r = 20;
  [[28, 28, 1, 1], [w - 28, 28, -1, 1], [28, h - 28, 1, -1], [w - 28, h - 28, -1, -1]].forEach(([x, y, sx, sy]) => {
    ctx.beginPath();
    ctx.moveTo(x + sx * L, y); ctx.lineTo(x, y); ctx.lineTo(x, y + sy * L);
    ctx.stroke();
    ctx.beginPath(); ctx.arc(x + sx * 12, y + sy * 12, 3.4, 0, 7);
    ctx.fillStyle = C.teal; ctx.fill();
  });
  T(ctx, "НОВОЕ ВЕЩЕСТВО", w / 2, 78, { size: 30, alias: "ManropeB", color: C.teal, spacing: 8 });
  T(ctx, "ПАР", w / 2, 190, { size: 128, alias: "ManropeXB", color: "#ffffff", glow: "rgba(120,220,255,0.85)", glowBlur: 34 });
  // rarity chip
  const chip = "ОБЫЧНОЕ · СЛОЙ 1";
  ctx.font = "26px ManropeB";
  const cw = ctx.measureText(chip).width + 56;
  rrect(ctx, w / 2 - cw / 2, 268, cw, 48, 24);
  ctx.fillStyle = "rgba(154,164,178,0.14)"; ctx.fill();
  ctx.strokeStyle = "rgba(154,164,178,0.5)"; ctx.lineWidth = 1.6; ctx.stroke();
  T(ctx, chip, w / 2, 293, { size: 26, alias: "ManropeB", color: C.grey, spacing: 2 });
  T(ctx, "«Тёплый, лёгкий и немного мятежный»", w / 2, 372, { size: 30, alias: "ManropeM", color: C.dim });
  // reward row
  const bolt = svgImg("icons/bolt.svg", 30);
  ctx.save();
  const rw = 470, rx = w / 2 - rw / 2, ry = 414;
  rrect(ctx, rx, ry, rw, 54, 27); ctx.fillStyle = "rgba(255,179,71,0.12)"; ctx.fill();
  ctx.strokeStyle = "rgba(255,179,71,0.65)"; ctx.lineWidth = 1.8; ctx.stroke();
  ctx.drawImage(bolt, rx + 34, ry + 12, 30, 30);
  T(ctx, "+6 эфира за первооткрытие", rx + rw / 2 + 22, ry + 27, { size: 26, alias: "ManropeB", color: C.amber });
  ctx.restore();
  return cv;
}

/* pre-rendered: rarity sigil cards */
function sigilCard(rarity) {
  const { name, col, reward, glyphLetter } = rarity;
  const w = 330, h = 430, cv = createCanvas(w, h), ctx = cv.getContext("2d");
  ctx.fillStyle = "rgba(12,14,24,0.97)";
  rrect(ctx, 6, 6, w - 12, h - 12, 30); ctx.fill();
  ctx.strokeStyle = col; ctx.lineWidth = 3;
  ctx.shadowColor = col; ctx.shadowBlur = 24;
  rrect(ctx, 6, 6, w - 12, h - 12, 30); ctx.stroke();
  ctx.shadowBlur = 0;
  // aura behind sigil circle
  const cx = w / 2, cy = 172;
  glowDot(ctx, cx, cy, 110, hex2rgb(col), 0.5);
  ctx.strokeStyle = col; ctx.lineWidth = 2.6; ctx.globalAlpha = 0.9;
  ctx.beginPath(); ctx.arc(cx, cy, 96, 0, 7); ctx.stroke();
  ctx.globalAlpha = 0.45;
  ctx.beginPath(); ctx.arc(cx, cy, 82, 0, 7); ctx.stroke();
  ctx.globalAlpha = 1;
  // glyph letter inside circle (alchemist font)
  const ds = glyphPath(glyphLetter);
  if (ds) {
    const gsz = 96;
    ctx.strokeStyle = "#fff"; ctx.lineWidth = 3.4;
    for (const d of ds) {
      const p = new Path2D(d);
      ctx.save();
      ctx.translate(cx - gsz / 2, cy - gsz / 2);
      ctx.scale(gsz / 100, gsz / 100);
      ctx.stroke(p);
      ctx.restore();
    }
  }
  T(ctx, name, w / 2, 322, { size: 34, alias: "ManropeXB", color: col, spacing: 5 });
  T(ctx, reward, w / 2, 372, { size: 26, alias: "ManropeB", color: C.dim });
  return cv;
}
function hex2rgb(hex) {
  const n = parseInt(hex.slice(1), 16);
  return `${(n >> 16) & 255},${(n >> 8) & 255},${n & 255}`;
}
const RARITIES = [
  { name: "ОБЫЧНОЕ", col: "#9aa4b2", reward: "+6 эфира", glyphLetter: "O" },
  { name: "РЕДКОЕ", col: "#4da3ff", reward: "+12 эфира", glyphLetter: "R" },
  { name: "ЭПИЧЕСКОЕ", col: "#b06cff", reward: "+25 эфира", glyphLetter: "E" },
  { name: "ЛЕГЕНДАРНОЕ", col: "#ffb347", reward: "+45 эфира", glyphLetter: "L" },
];
const SIGILS_MAKER = RARITIES;

/* ---------- app icon (rounded square + Светик) ---------- */
function makeAPPICON() {
  const s = 220, cv = createCanvas(s, s), ctx = cv.getContext("2d");
  const g = ctx.createLinearGradient(0, 0, s, s);
  g.addColorStop(0, "#191531"); g.addColorStop(1, "#0d0b18");
  rrect(ctx, 6, 6, s - 12, s - 12, 52); ctx.fillStyle = g; ctx.fill();
  ctx.strokeStyle = "rgba(255,179,71,0.8)"; ctx.lineWidth = 5;
  rrect(ctx, 6, 6, s - 12, s - 12, 52); ctx.stroke();
  const idle = pngImg("stickers/hi.png");
  ctx.save();
  rrect(ctx, 6, 6, s - 12, s - 12, 52); ctx.clip();
  ctx.drawImage(idle, s * 0.5 - 92, s * 0.5 - 86, 184, 184);
  ctx.restore();
  return cv;
}

async function initStatics() {
  RING_AMBER = RING_MAKER(1400, "#ffb347");
  RING_TEAL = RING_MAKER(1400, "#35d0ba");
  STARS = makeSTARS();
  WINDOW = makeWINDOW();
  REVEAL = makeREVEAL();
  SIGILS = RARITIES.map(sigilCard);
  APPICON = makeAPPICON();
}

/* ---------- background ---------- */
function bgBase(ctx, t, o = {}) {
  const night = o.night ?? 0;
  const g = ctx.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, mixHex(C.bg1, "#0c1024", night));
  g.addColorStop(0.55, mixHex(C.bg0, "#0a0c1e", night));
  g.addColorStop(1, "#0a0912");
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  // nebula blobs
  const nb = (x, y, r, rgb, a) => glowDot(ctx, x, y, r, rgb, a);
  nb(W * 0.25 + osc(t, 0.05) * 40, H * 0.3, 420, "53,120,150", 0.10 + night * 0.05);
  nb(W * 0.8, H * 0.75 + osc(t, 0.04, 2) * 50, 460, "255,140,60", 0.07 + night * 0.03);
  nb(W * 0.6, H * 0.15, 300, "120,80,200", 0.06);
  // stars
  ctx.globalAlpha = 0.5 + night * 0.5;
  ctx.drawImage(STARS, 0, 0);
  ctx.globalAlpha = 1;
}
function mixHex(a, b, t) {
  if (t <= 0) return a;
  const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
  const r = Math.round(lerp((pa >> 16) & 255, (pb >> 16) & 255, t));
  const g = Math.round(lerp((pa >> 8) & 255, (pb >> 8) & 255, t));
  const bl = Math.round(lerp(pa & 255, pb & 255, t));
  return `#${((r << 16) | (g << 8) | bl).toString(16).padStart(6, "0")}`;
}
function vignette(ctx, a = 0.42) {
  const g = ctx.createRadialGradient(W / 2, H / 2, H * 0.28, W / 2, H / 2, H * 0.72);
  g.addColorStop(0, "rgba(0,0,0,0)");
  g.addColorStop(1, `rgba(0,0,0,${a})`);
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
}

/* ember particles (deterministic) */
function embers(ctx, t, o = {}) {
  const n = o.n ?? 26, heat = o.heat ?? 1;
  for (let i = 0; i < n; i++) {
    const sp = 26 + rnd(i) * 46;
    const y = H + 40 - ((t * sp + rnd(i * 3) * H * 1.4) % (H + 160));
    const x = (rnd(i * 7) * W) + Math.sin(t * (0.4 + rnd(i * 5)) + i) * 36;
    const r = (1.2 + rnd(i * 11) * 2.4) * heat;
    const tw = 0.45 + 0.55 * Math.abs(Math.sin(t * (1.2 + rnd(i * 13)) + i * 2));
    ctx.globalAlpha = 0.5 * tw;
    ctx.fillStyle = i % 4 === 0 ? C.gold : C.ember;
    ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill();
  }
  ctx.globalAlpha = 1;
}

/* glyph rain (matrix-style, runic) */
function glyphRain(ctx, t, intensity = 1) {
  const cols = 9, colW = W / cols;
  ctx.save();
  ctx.font = "44px AlchRunic";
  ctx.textAlign = "center";
  for (let c = 0; c < cols; c++) {
    const speed = 60 + rnd(c * 17) * 90;
    const off = (t * speed + rnd(c * 31) * H) % (H + 400);
    for (let k = 0; k < 7; k++) {
      const y = ((off + k * 120) % (H + 400)) - 200;
      const a = Math.max(0, 0.16 - k * 0.018) * intensity;
      if (a <= 0.01) continue;
      ctx.globalAlpha = a;
      ctx.fillStyle = C.teal;
      const gi = (c * 7 + k + Math.floor(t * 2)) % ringWord.length;
      ctx.fillText(ringWord[gi], c * colW + colW / 2, y);
    }
  }
  ctx.restore();
}

/* Светик with bob + glow */
function spirit(ctx, imgName, x, y, size, t, o = {}) {
  const img = pngImg("stickers/" + imgName + ".png");
  const bob = Math.sin(t * 1.6) * (o.bob ?? 10);
  ctx.save();
  if (o.alpha !== undefined) ctx.globalAlpha = o.alpha;
  glowDot(ctx, x, y + bob + size * 0.05, size * 0.75, "255,160,60", 0.4);
  ctx.drawImage(img, x - size / 2, y - size / 2 + bob, size, size);
  ctx.restore();
  return y + bob;
}
function sparkleBurst(ctx, t, t0, x, y, o = {}) {
  const p = seg(t, t0, t0 + (o.dur ?? 0.9));
  if (p <= 0 || p >= 1) return;
  const n = o.n ?? 14;
  for (let i = 0; i < n; i++) {
    const a = rnd(i * 3) * Math.PI * 2;
    const dist = eoc(p) * (o.dist ?? 190) * (0.55 + rnd(i * 7) * 0.45);
    const px = x + Math.cos(a) * dist, py = y + Math.sin(a) * dist * 0.8;
    const s = (1 - p) * (2.2 + rnd(i) * 2.6);
    ctx.globalAlpha = (1 - p) * 0.9;
    ctx.fillStyle = i % 3 === 0 ? "#fff" : (i % 3 === 1 ? C.gold : C.teal);
    ctx.beginPath(); ctx.arc(px, py, s, 0, 7); ctx.fill();
  }
  ctx.globalAlpha = 1;
  // ring
  ctx.strokeStyle = `rgba(255,200,120,${(1 - p) * 0.8})`;
  ctx.lineWidth = 3 * (1 - p) + 0.5;
  ctx.beginPath(); ctx.arc(x, y, eoc(p) * (o.ring ?? 240), 0, 7); ctx.stroke();
}

/* ---------- cauldron ---------- */
function cauldron(ctx, t, x, y, w, o = {}) {
  const boil = o.boil ?? 0.3;
  const dark = o.dark ?? false;
  ctx.save();
  // glow under
  if (!dark) glowDot(ctx, x, y + w * 0.1, w * 0.75, "80,200,190", 0.16 + boil * 0.22);
  else glowDot(ctx, x, y + w * 0.1, w * 0.6, "120,140,220", 0.10);
  const body = dark ? "#141221" : "#1d2433";
  const body2 = dark ? "#0c0b16" : "#131826";
  // body
  const g = ctx.createLinearGradient(x - w / 2, y, x + w / 2, y + w * 0.6);
  g.addColorStop(0, body); g.addColorStop(1, body2);
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.moveTo(x - w * 0.46, y - w * 0.10);
  ctx.bezierCurveTo(x - w * 0.52, y + w * 0.38, x - w * 0.22, y + w * 0.52, x, y + w * 0.52);
  ctx.bezierCurveTo(x + w * 0.22, y + w * 0.52, x + w * 0.52, y + w * 0.38, x + w * 0.46, y - w * 0.10);
  ctx.closePath(); ctx.fill();
  // rim + liquid
  ctx.fillStyle = dark ? "#1a1830" : "#232c40";
  ctx.beginPath(); ctx.ellipse(x, y - w * 0.10, w * 0.48, w * 0.115, 0, 0, 7); ctx.fill();
  const liquidCol = dark ? "#2c2a4a" : mixHex("#3f7fd4", "#37d0ba", clamp(boil, 0, 1) * 0.8);
  ctx.fillStyle = liquidCol;
  ctx.beginPath(); ctx.ellipse(x, y - w * 0.10, w * 0.42, w * 0.092, 0, 0, 7); ctx.fill();
  if (!dark) {
    // liquid shimmer
    ctx.globalAlpha = 0.5;
    ctx.fillStyle = "#bfefff";
    ctx.beginPath();
    ctx.ellipse(x - w * 0.12 + Math.sin(t * 1.4) * 8, y - w * 0.115, w * 0.12, w * 0.02, -0.2, 0, 7);
    ctx.fill();
    ctx.globalAlpha = 1;
  }
  // bubbles
  for (let i = 0; i < 8; i++) {
    const bt = ((t * (0.5 + rnd(i) * 0.7) + rnd(i * 3)) % 1);
    const bx = x + (rnd(i * 7) - 0.5) * w * 0.6;
    const by = y - w * 0.10 + w * 0.05 - bt * w * 0.14;
    ctx.globalAlpha = (0.5 - bt * 0.4) * (0.4 + boil * 0.6);
    ctx.fillStyle = "#cfeeff";
    ctx.beginPath(); ctx.arc(bx, by, (1.6 + rnd(i * 5) * 2.6) * (0.6 + boil), 0, 7); ctx.fill();
  }
  ctx.globalAlpha = 1;
  // steam
  for (let i = 0; i < 4; i++) {
    const st = ((t * 0.35 + i * 0.23) % 1);
    const sx = x + Math.sin(t * 0.8 + i * 2.1) * w * 0.14;
    const sy = y - w * 0.18 - st * w * 0.5;
    ctx.globalAlpha = (1 - st) * 0.08 * (0.5 + boil);
    ctx.fillStyle = "#b8ffe9";
    ctx.beginPath(); ctx.arc(sx, sy, w * (0.035 + st * 0.08), 0, 7); ctx.fill();
  }
  ctx.globalAlpha = 1;
  // legs
  ctx.strokeStyle = dark ? "#191727" : "#171d2b";
  ctx.lineWidth = w * 0.05; ctx.lineCap = "round";
  [[-0.26, 0.52, -0.34, 0.64], [0.26, 0.52, 0.34, 0.64]].forEach(([a, b, c, d]) => {
    ctx.beginPath(); ctx.moveTo(x + w * a, y + w * b); ctx.lineTo(x + w * c, y + w * d); ctx.stroke();
  });
  ctx.restore();
}

/* orb (reagent) */
function orb(ctx, t, x, y, r, iconFile, colRGB, o = {}) {
  const pop = o.pop ?? 1;
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(pop, pop);
  glowDot(ctx, 0, 0, r * 2.1, colRGB, 0.5);
  const g = ctx.createRadialGradient(-r * 0.3, -r * 0.35, r * 0.1, 0, 0, r);
  g.addColorStop(0, `rgba(${colRGB},0.95)`);
  g.addColorStop(1, `rgba(${colRGB},0.55)`);
  ctx.fillStyle = g;
  ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill();
  ctx.strokeStyle = "rgba(255,255,255,0.5)"; ctx.lineWidth = 2.5;
  ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.stroke();
  const ic = svgImg("icons/" + iconFile, Math.round(r * 1.1));
  ctx.drawImage(ic, -r * 0.55, -r * 0.55, r * 1.1, r * 1.1);
  ctx.restore();
}

/* pill chip */
function chip(ctx, text, x, y, o = {}) {
  ctx.font = `${o.size ?? 30}px ${o.alias ?? "ManropeB"}`;
  const tw = ctx.measureText(text).width;
  const padX = o.padX ?? 30, h = o.h ?? 56;
  const w = tw + padX * 2;
  const a = o.alpha ?? 1;
  if (a <= 0.01) return w;
  ctx.save();
  ctx.globalAlpha *= a;
  rrect(ctx, x - w / 2, y - h / 2, w, h, h / 2);
  ctx.fillStyle = o.bg ?? "rgba(53,208,186,0.10)";
  ctx.fill();
  ctx.strokeStyle = o.border ?? "rgba(53,208,186,0.55)";
  ctx.lineWidth = 2; ctx.stroke();
  ctx.restore();
  T(ctx, text, x, y + 1, { size: o.size ?? 30, alias: o.alias ?? "ManropeB", color: o.color ?? C.teal, alpha: a });
  return w;
}

/* flash / fade / shake events */
const FLASHES = [
  { t: 5.2, rgb: "120,220,205", a: 0.30, d: 0.32 },
  { t: 9.55, rgb: "255,190,120", a: 0.60, d: 0.38 },
  { t: 13.5, rgb: "120,220,205", a: 0.30, d: 0.32 },
  { t: 22.0, rgb: "255,200,120", a: 0.42, d: 0.42 },
  { t: 30.2, rgb: "255,220,150", a: 0.25, d: 0.35 },
  { t: 32.0, rgb: "120,160,255", a: 0.28, d: 0.34 },
  { t: 41.4, rgb: "180,140,255", a: 0.30, d: 0.32 },
  { t: 50.0, rgb: "255,235,200", a: 0.75, d: 0.55 },
  { t: 57.6, rgb: "255,220,160", a: 0.30, d: 0.45 },
];
const CUTS = [5.2, 13.5, 22.0, 32.0, 41.4];
const SHAKES = [
  { t: 8.42, a: 5 }, { t: 8.92, a: 7 },
  { t: 50.0, a: 15 }, { t: 57.6, a: 6 },
];

function overlays(ctx, t) {
  // crossfade cuts
  for (const cut of CUTS) {
    const p = 1 - clamp(Math.abs(t - cut) / 0.16, 0, 1);
    if (p > 0) { ctx.fillStyle = `rgba(5,4,10,${p})`; ctx.fillRect(0, 0, W, H); }
  }
  // flashes
  for (const f of FLASHES) {
    const p = 1 - clamp((t - f.t) / f.d, 0, 1);
    if (p > 0 && t >= f.t) {
      ctx.fillStyle = `rgba(${f.rgb},${f.a * Math.pow(p, 1.6)})`;
      ctx.fillRect(0, 0, W, H);
    }
  }
  // progress line
  ctx.fillStyle = "rgba(255,179,71,0.55)";
  ctx.fillRect(0, 0, (t / DUR) * W, 6);
}

function shakeOffset(t) {
  let x = 0, y = 0;
  for (const s of SHAKES) {
    const dt = t - s.t;
    if (dt >= 0 && dt < 0.5) {
      const k = s.a * Math.exp(-dt * 9);
      x += k * (rnd(Math.floor(t * 90) * 3) - 0.5) * 2;
      y += k * (rnd(Math.floor(t * 90) * 7) - 0.5) * 2;
    }
  }
  return [x, y];
}

/* punch-in zoom on impacts */
function zoomAt(t) {
  let z = 0;
  for (const s of [{ t: 50.0, a: 0.05 }, { t: 9.6, a: 0.025 }, { t: 22.05, a: 0.03 }]) {
    const dt = t - s.t;
    if (dt >= 0 && dt < 0.8) z += s.a * Math.exp(-dt * 4.2);
  }
  return z;
}

/* =====================================================================
 * SCENES
 * ===================================================================== */

/* S1 — hook (0 – 5.2) */
function s1(ctx, t) {
  bgBase(ctx, t);
  embers(ctx, t, { n: 14, heat: 0.8 });
  // rune ring materializes
  const rp = seg(t, 1.1, 2.8);
  if (rp > 0) {
    ctx.save();
    ctx.globalAlpha = 0.30 * rp;
    ctx.translate(W / 2, 800);
    ctx.rotate(t * 0.10);
    ctx.drawImage(RING_AMBER, -490, -490, 980, 980);
    ctx.restore();
  }
  // spark ignites
  const sp = seg(t, 0.25, 1.1);
  const flick = 0.85 + 0.15 * osc(t * 6);
  glowDot(ctx, W / 2, 800, (60 + 140 * eoc(sp)) * flick, "255,170,60", 0.8 * sp);
  ctx.fillStyle = "#ffd9a0";
  ctx.globalAlpha = sp;
  ctx.beginPath(); ctx.arc(W / 2, 800, 10 + 16 * eoc(sp), 0, 7); ctx.fill();
  ctx.globalAlpha = 1;
  // spark trail
  for (let i = 0; i < 8; i++) {
    const tt = t - i * 0.05;
    if (tt < 0.25) continue;
    ctx.globalAlpha = 0.25 * (1 - i / 8);
    ctx.fillStyle = C.amber;
    ctx.beginPath(); ctx.arc(W / 2 + Math.sin(tt * 3 + i) * 14, 800 - i * 22, 3 - i * 0.25, 0, 7); ctx.fill();
  }
  ctx.globalAlpha = 1;

  // beat 1
  const a1 = seg(t, 0.9, 1.5) * (1 - seg(t, 2.8, 3.25));
  if (a1 > 0) {
    T(ctx, "Тысячи игр про зелья…", W / 2, 1180 + (1 - eoc(seg(t, 0.9, 1.5))) * 34,
      { size: 54, alias: "ManropeSB", color: C.dim, alpha: a1 });
  }
  // beat 2
  const in2 = seg(t, 3.1, 3.7);
  const out2 = 1 - seg(t, 4.85, 5.15);
  if (in2 > 0 && out2 > 0) {
    const yy = 1120 + (1 - eoc(in2)) * 44;
    T(ctx, "но здесь", W / 2, yy - 116, { size: 44, alias: "ManropeM", color: C.dim, alpha: in2 * out2 });
    T(ctx, "РЕЦЕПТЫ ПРИДУМАЕТ", W / 2, yy + 4, { size: 76, alias: "ManropeXB", color: "#fff", alpha: in2 * out2, glow: "rgba(255,255,255,0.25)" });
    T(ctx, "ИСКУССТВЕННЫЙ ИНТЕЛЛЕКТ", W / 2, yy + 104, { size: 58, alias: "ManropeXB", color: C.amber, alpha: in2 * out2, glow: "rgba(255,170,60,0.75)", glowBlur: 30 });
  }
  vignette(ctx);
}

/* S2 — brew experiment (5.2 – 13.5) */
function s2(ctx, t) {
  bgBase(ctx, t, { night: 0 });
  embers(ctx, t, { n: 16 });
  const tl = t - 5.2;
  // panel
  const pn = eoc(seg(tl, 0.05, 0.6));
  ctx.save();
  ctx.globalAlpha = pn;
  ctx.fillStyle = "rgba(13,16,28,0.55)";
  rrect(ctx, 60, 240, W - 120, 1250, 44); ctx.fill();
  ctx.strokeStyle = "rgba(53,208,186,0.5)"; ctx.lineWidth = 2.5;
  rrect(ctx, 60, 240, W - 120, 1250, 44); ctx.stroke();
  ctx.restore();
  // header chip
  const hp = eoc(seg(tl, 0.25, 0.8));
  if (hp > 0) {
    ctx.save(); ctx.globalAlpha = hp;
    const fl = svgImg("icons/flask.svg", 34);
    ctx.drawImage(fl, 118, 296, 34, 34);
    T(ctx, "ЭКСПЕРИМЕНТ", 172, 314, { size: 36, alias: "ManropeXB", color: C.teal, align: "left", spacing: 3, base: "middle" });
    ctx.restore();
  }
  const cx = W / 2, cyC = 1210, cw = 430;
  cauldron(ctx, t, cx, cyC, cw, { boil: seg(t, 8.4, 9.2) * 0.85 + 0.15 });

  // orbs
  const orbY = 700, orbR = 74;
  // water
  const wPop = eob(seg(t, 5.9, 6.35));
  let wPos = { x: 295, y: orbY };
  const wThrow = seg(t, 8.05, 8.45);
  if (wThrow > 0) {
    const p = eio(wThrow);
    wPos = { x: lerp(295, cx - 60, p), y: orbY - Math.sin(p * Math.PI) * 180 + lerp(0, cyC - orbY + 40, p) };
  }
  if (wPop > 0 && wThrow < 1) {
    orb(ctx, t, wPos.x, wPos.y, orbR, "drop.svg", "88,166,255", { pop: clamp(wPop, 0.001, 1.12) });
    const la = (1 - seg(t, 7.5, 7.95)) * (wThrow < 0.15 ? 1 : 1 - wThrow);
    if (la > 0) T(ctx, "ВОДА", wPos.x, wPos.y + orbR + 44, { size: 32, alias: "ManropeB", color: C.water, alpha: la });
  }
  // fire
  const fPop = eob(seg(t, 6.6, 7.05));
  let fPos = { x: 785, y: orbY };
  const fThrow = seg(t, 8.55, 8.95);
  if (fThrow > 0) {
    const p = eio(fThrow);
    fPos = { x: lerp(785, cx + 60, p), y: orbY - Math.sin(p * Math.PI) * 180 + lerp(0, cyC - orbY + 40, p) };
  }
  if (fPop > 0 && fThrow < 1) {
    orb(ctx, t, fPos.x, fPos.y, orbR, "fire.svg", "255,112,67", { pop: clamp(fPop, 0.001, 1.12) });
    const la = (1 - seg(t, 7.5, 7.95)) * (fThrow < 0.15 ? 1 : 1 - fThrow);
    if (la > 0) T(ctx, "ОГОНЬ", fPos.x, fPos.y + orbR + 44, { size: 32, alias: "ManropeB", color: C.fire, alpha: la });
  }
  // splash rings into cauldron
  [[8.45, "88,166,255"], [8.95, "255,112,67"]].forEach(([st, rgb]) => {
    const p = seg(t, st, st + 0.5);
    if (p > 0 && p < 1) {
      ctx.strokeStyle = `rgba(${rgb},${(1 - p) * 0.8})`;
      ctx.lineWidth = 3.5 * (1 - p);
      ctx.beginPath(); ctx.ellipse(cx, cyC - cw * 0.10, 60 + p * 190, (60 + p * 190) * 0.3, 0, 0, 7); ctx.stroke();
    }
  });

  // question line
  const qa = seg(t, 6.3, 6.9) * (1 - seg(t, 9.2, 9.7));
  if (qa > 0) {
    T(ctx, "ВОДА  +  ОГОНЬ  =  ?", cx, 520, { size: 60, alias: "ManropeXB", color: "#fff", alpha: qa, spacing: 2 });
  }

  // reveal card
  const cardP = seg(t, 9.95, 10.75);
  const cardOut = 1 - seg(t, 12.55, 13.15);
  if (cardP > 0 && cardOut > 0) {
    const cy = lerp(cyC - 80, 830, eoc(cardP));
    ctx.save();
    ctx.globalAlpha = cardOut;
    const sc = lerp(0.86, 1, eob(cardP)) * lerp(1, 0.94, 1 - cardOut);
    ctx.translate(cx, cy);
    ctx.scale(sc, sc);
    ctx.drawImage(REVEAL, -REVEAL.width / 2, -REVEAL.height / 2);
    // Светик peeks from corner
    const cel = pngImg("stickers/celebrate.png");
    ctx.drawImage(cel, REVEAL.width / 2 - 110, -REVEAL.height / 2 - 66, 148, 148);
    ctx.restore();
    sparkleBurst(ctx, t, 10.0, cx, cy, { n: 18, dur: 1.0 });
  }
  vignette(ctx);
}

/* S3 — world feed (13.5 – 22) */
function s3(ctx, t) {
  bgBase(ctx, t);
  glyphRain(ctx, t, 1);
  embers(ctx, t, { n: 10, heat: 0.7 });
  const tl = t - 13.5;
  const cx = W / 2;

  const h1 = eoc(seg(tl, 0.15, 0.75)) * (1 - seg(tl, 5.6, 6.1));
  if (h1 > 0) {
    T(ctx, "Каждая пара —", cx, 400 + (1 - eoc(seg(tl, 0.15, 0.75))) * 30, { size: 62, alias: "ManropeSB", color: "#fff", alpha: h1 });
    T(ctx, "вопрос всему миру", cx, 486, { size: 62, alias: "ManropeXB", color: C.teal, alpha: h1, glow: "rgba(53,208,186,0.6)" });
    T(ctx, "ИИ решает: сочетаются — или нет", cx, 574, { size: 40, alias: "ManropeM", color: C.dim, alpha: h1 * 0.95 });
  }

  // feed rows
  const rows = [
    { t0: 1.55, user: "@мира", col: "255,179,71", act: "открыла", thing: "РТУТЬ", tag: "впервые в мире", tagCol: C.amber },
    { t0: 2.85, user: "@keks", col: "53,208,186", act: "сварил", thing: "ГЛИНУ", tag: "слой 2", tagCol: C.blue },
    { t0: 4.15, user: "@лиса", col: "176,108,255", act: "открыла", thing: "СТЕКЛО", tag: "слой 3", tagCol: C.violet },
  ];
  rows.forEach((r, i) => {
    const p = seg(tl, r.t0, r.t0 + 0.55);
    const out = 1 - seg(tl, 5.5 + i * 0.08, 5.95 + i * 0.08);
    if (p <= 0 || out <= 0) return;
    const y = 760 + i * 150;
    const x = lerp(W + 500, cx, eoc(p));
    ctx.save();
    ctx.globalAlpha = out;
    ctx.fillStyle = "rgba(13,16,28,0.9)";
    rrect(ctx, x - 460, y - 58, 920, 116, 30); ctx.fill();
    ctx.strokeStyle = "rgba(90,100,125,0.45)"; ctx.lineWidth = 2;
    rrect(ctx, x - 460, y - 58, 920, 116, 30); ctx.stroke();
    // avatar
    const ag = ctx.createLinearGradient(x - 400, y - 36, x - 330, y + 36);
    ag.addColorStop(0, `rgba(${r.col},0.95)`); ag.addColorStop(1, `rgba(${r.col},0.55)`);
    ctx.fillStyle = ag;
    ctx.beginPath(); ctx.arc(x - 366, y, 37, 0, 7); ctx.fill();
    T(ctx, r.user[1].toUpperCase(), x - 366, y + 1, { size: 34, alias: "ManropeXB", color: "#10131f" });
    // text
    T(ctx, r.user, x - 302, y - 24, { size: 32, alias: "ManropeB", color: C.dim, align: "left" });
    T(ctx, r.thing, x - 302, y + 22, { size: 40, alias: "ManropeXB", color: "#fff", align: "left" });
    // tag
    ctx.font = "24px ManropeB";
    const tw = ctx.measureText(r.tag).width + 36;
    rrect(ctx, x + 448 - tw, y - 24, tw, 46, 23);
    ctx.fillStyle = r.tag === "впервые в мире" ? "rgba(255,179,71,0.16)" : "rgba(77,163,255,0.13)";
    ctx.fill();
    ctx.strokeStyle = r.tag === "впервые в мире" ? "rgba(255,179,71,0.7)" : "rgba(77,163,255,0.6)";
    ctx.lineWidth = 1.6; ctx.stroke();
    T(ctx, r.tag, x + 448 - tw / 2, y + 1, { size: 24, alias: "ManropeB", color: r.tag === "впервые в мире" ? C.amber : C.blue });
    ctx.restore();
    if (i === 0) sparkleBurst(ctx, t, 13.5 + r.t0 + 0.4, x + 300, y, { n: 8, dur: 0.7, dist: 90, ring: 90 });
  });

  // 57 counter
  const nP = seg(tl, 5.9, 6.7);
  if (nP > 0) {
    const out = 1 - seg(tl, 7.9, 8.45);
    const k = eoe(nP);
    ctx.save();
    ctx.globalAlpha = out;
    T(ctx, "57", cx, 940 - (1 - k) * 60, { size: 210, alias: "ManropeXB", color: C.amber, glow: "rgba(255,170,60,0.8)", glowBlur: 44 });
    T(ctx, "веществ в Атласе", cx, 1090, { size: 44, alias: "ManropeSB", color: C.dim, alpha: out });
    const l2 = seg(tl, 6.9, 7.4);
    T(ctx, "58-е может открыть ТЫ", cx, 1210, {
      size: 56, alias: "ManropeXB", color: "#fff",
      alpha: eoc(l2) * out, glow: "rgba(255,255,255,0.35)",
    });
    ctx.restore();
    sparkleBurst(ctx, t, 19.6, cx, 940, { n: 20, dur: 1.1, dist: 260 });
  }
  vignette(ctx);
}

/* S4 — Светик (22 – 32) */
function s4(ctx, t) {
  bgBase(ctx, t, { night: 0.25 });
  embers(ctx, t, { n: 18 });
  const tl = t - 22;
  const cx = W / 2;

  // backdrop ring
  ctx.save();
  ctx.globalAlpha = 0.16;
  ctx.translate(cx, 800);
  ctx.rotate(-t * 0.06);
  ctx.drawImage(RING_TEAL, -520, -520, 1040, 1040);
  ctx.restore();

  const pop = eob(seg(tl, 0.1, 0.75));
  if (pop > 0) {
    const switched = t >= 30.2;
    spirit(ctx, switched ? "celebrate" : "hi", cx, 760, 400 * clamp(pop, 0.001, 1.06), t, { alpha: 1, bob: 12 });
    sparkleBurst(ctx, t, 22.15, cx, 760, { n: 22, dur: 1.2, dist: 300, ring: 300 });
    if (switched) sparkleBurst(ctx, t, 30.25, cx, 760, { n: 16, dur: 1.0, dist: 220, ring: 220 });
  }
  const t1 = seg(tl, 0.75, 1.25), o1 = 1 - seg(tl, 9.0, 9.6);
  if (t1 > 0) {
    T(ctx, "ЗНАКОМЬСЯ:", cx, 1052, { size: 42, alias: "ManropeB", color: C.teal, spacing: 10, alpha: eoc(t1) * o1 });
    T(ctx, "СВЕТИК", cx, 1150, { size: 118, alias: "ManropeXB", color: C.amber, glow: "rgba(255,170,60,0.85)", glowBlur: 36, alpha: eoc(t1) * o1 });
    T(ctx, "дух котла · твой соучастник", cx, 1240, { size: 40, alias: "ManropeM", color: C.dim, alpha: eoc(seg(tl, 1.35, 1.8)) * o1 });
  }

  // chat bubbles
  const bub = [
    { t0: 2.5, side: -1, st: "think", txt: "Подскажет сильную пару", tag: "подсказка · 10 эфира" },
    { t0: 4.5, side: 1, st: "look", txt: "Посудачит о чужих открытиях", tag: "лента мира" },
    { t0: 6.5, side: -1, st: "star", txt: "Празднует каждое «впервые»", tag: "дружба растёт" },
  ];
  bub.forEach((b, i) => {
    const p = seg(tl, b.t0, b.t0 + 0.5);
    const out = 1 - seg(tl, 8.6, 9.3);
    if (p <= 0 || out <= 0) return;
    const e = eob(p);
    const y = 1360 + i * 130;
    const x = cx + b.side * 40;
    ctx.save();
    ctx.globalAlpha = out;
    ctx.translate(x, y);
    ctx.scale(clamp(e, 0.001, 1), clamp(e, 0.001, 1));
    // bubble
    const bw = 760, bh = 100;
    const bx = -bw / 2 - b.side * 90, by = -bh / 2;
    rrect(ctx, bx, by, bw, bh, 34);
    ctx.fillStyle = "rgba(16,23,36,0.95)"; ctx.fill();
    ctx.strokeStyle = "rgba(53,208,186,0.4)"; ctx.lineWidth = 2; ctx.stroke();
    // mini sticker
    const st = pngImg("stickers/" + b.st + ".png");
    const sx = b.side < 0 ? bx + 66 : bx + bw - 66;
    ctx.drawImage(st, sx - 40, -44, 80, 80);
    T(ctx, b.txt, -b.side * 60, -10, { size: 34, alias: "ManropeSB", color: C.text });
    T(ctx, b.tag, -b.side * 60, 28, { size: 25, alias: "ManropeB", color: C.teal });
    ctx.restore();
  });
  vignette(ctx, 0.38);
}

/* S5 — offline loop (32 – 41.4) */
function s5(ctx, t) {
  bgBase(ctx, t, { night: 1 });
  embers(ctx, t, { n: 10, heat: 0.6 });
  const tl = t - 32;
  const cx = W / 2;
  // window
  ctx.save();
  ctx.globalAlpha = 0.95;
  ctx.translate(830, 250);
  ctx.drawImage(WINDOW, -190, -235);
  ctx.restore();
  // floor + cauldron silhouette
  ctx.fillStyle = "rgba(10,9,18,0.9)";
  ctx.fillRect(0, 1430, W, H - 1430);
  cauldron(ctx, t, cx - 20, 1360, 360, { dark: true, boil: 0.25 });
  // moonbeam
  ctx.save();
  ctx.globalAlpha = 0.06;
  ctx.fillStyle = "#b8ccff";
  ctx.beginPath();
  ctx.moveTo(900, 380); ctx.lineTo(1010, 380); ctx.lineTo(620, 1430); ctx.lineTo(330, 1430);
  ctx.closePath(); ctx.fill();
  ctx.restore();

  const h1 = eoc(seg(tl, 0.15, 0.75));
  if (h1 > 0) {
    T(ctx, "Закроешь игру — петля", cx, 420, { size: 58, alias: "ManropeSB", color: "#fff", alpha: h1 });
    T(ctx, "НЕ остановится", cx, 506, { size: 66, alias: "ManropeXB", color: C.amber, alpha: h1, glow: "rgba(255,170,60,0.7)" });
  }

  // counter
  const cP = seg(tl, 0.9, 6.4);
  if (cP > 0) {
    const val = Math.round(342 * eoe(cP));
    const pulse = 1 + 0.04 * Math.abs(Math.sin(t * 6)) * (cP < 1 ? 1 : 0);
    ctx.save();
    ctx.translate(cx, 850);
    ctx.scale(pulse, pulse);
    const bolt = svgImg("icons/bolt.svg", 96);
    ctx.globalAlpha = 0.95;
    ctx.drawImage(bolt, -48, -230, 96, 96);
    T(ctx, "+" + val, 0, 0, { size: 172, alias: "ManropeXB", color: C.gold, glow: "rgba(255,200,77,0.8)", glowBlur: 40 });
    T(ctx, "эфира накопил котёл", 0, 128, { size: 44, alias: "ManropeSB", color: C.dim });
    ctx.restore();
    // milestone rings
    [35.0, 36.5, 38.0].forEach((ms, i) => {
      const p = seg(t, ms, ms + 0.6);
      if (p > 0 && p < 1) {
        ctx.strokeStyle = `rgba(255,200,77,${(1 - p) * 0.6})`;
        ctx.lineWidth = 3 * (1 - p);
        ctx.beginPath(); ctx.arc(cx, 850, 120 + p * 200, 0, 7); ctx.stroke();
      }
    });
  }
  // bottom lines
  const b1 = seg(tl, 6.6, 7.1), b2 = seg(tl, 7.3, 7.8);
  if (b1 > 0 && b2 <= 0) {
    T(ctx, "до 8 часов офлайна — всё твоё", cx, 1080, { size: 44, alias: "ManropeM", color: C.dim, alpha: eoc(b1) * (1 - seg(tl, 7.0, 7.4)) });
  }
  if (b2 > 0) {
    T(ctx, "Вернёшься — заберёшь ВСЁ", cx, 1080 + (1 - eoc(b2)) * 30, { size: 58, alias: "ManropeXB", color: "#fff", alpha: eoc(b2), glow: "rgba(255,255,255,0.3)" });
  }
  vignette(ctx, 0.5);
}

/* S6 — depth & rarity (41.4 – 50) */
function s6(ctx, t) {
  bgBase(ctx, t, { night: 0.15 });
  embers(ctx, t, { n: 16 });
  const tl = t - 41.4;
  const cx = W / 2;
  // faint ring backdrop
  ctx.save();
  ctx.globalAlpha = 0.10;
  ctx.translate(cx, 900);
  ctx.rotate(t * 0.05);
  ctx.drawImage(RING_AMBER, -560, -560, 1120, 1120);
  ctx.restore();

  const h1 = eoc(seg(tl, 0.15, 0.7));
  if (h1 > 0) {
    T(ctx, "Чем страннее пара —", cx, 330, { size: 56, alias: "ManropeSB", color: "#fff", alpha: h1 });
    T(ctx, "тем ценнее вещество", cx, 416, { size: 62, alias: "ManropeXB", color: C.violet, alpha: h1, glow: "rgba(176,108,255,0.6)" });
  }

  // sigil cards sweep
  const starts = [0.85, 2.45, 4.05, 5.65];
  SIGILS.forEach((card, i) => {
    const st = starts[i];
    const inP = seg(tl, st, st + 0.5);
    const outP = seg(tl, st + 1.42, st + 1.92);
    if (inP <= 0 || inP >= 1 && outP >= 1) return;
    const legend = i === 3;
    const exitLast = i === 3 ? 1 - seg(tl, 8.0, 8.5) : 1 - outP;
    if (exitLast <= 0) return;
    const x = i === 3 ? cx : lerp(cx + 700, cx, eoc(inP)) - (outP > 0 ? eic(outP) * 700 : 0);
    const y = 900 + Math.sin(t * 1.2 + i) * 8;
    const rot = lerp(0.18, 0, eoc(inP)) + (outP > 0 ? eic(outP) * -0.12 : 0);
    const sc = lerp(0.7, 1, eob(inP)) * (i === 3 ? 1 + 0.03 * Math.sin(t * 3) : 1);
    ctx.save();
    ctx.globalAlpha = clamp(inP * 1.4, 0, 1) * clamp(exitLast * 1.4, 0, 1);
    ctx.translate(x, y);
    ctx.rotate(rot);
    ctx.scale(sc, sc);
    ctx.drawImage(card, -card.width / 2, -card.height / 2);
    if (legend) {
      // foil sweep (per sigil spec: moving foil band)
      rrect(ctx, -card.width / 2 + 6, -card.height / 2 + 6, card.width - 12, card.height - 12, 30);
      ctx.clip();
      const fx = ((t * 0.45) % 1.4) * (card.width + 300) - card.width / 2 - 150;
      const fg = ctx.createLinearGradient(fx - 90, -card.height / 2, fx + 90, card.height / 2);
      fg.addColorStop(0, "rgba(255,255,255,0)");
      fg.addColorStop(0.5, "rgba(255,236,190,0.30)");
      fg.addColorStop(1, "rgba(255,255,255,0)");
      ctx.fillStyle = fg;
      ctx.fillRect(-card.width / 2, -card.height / 2, card.width, card.height);
    }
    ctx.restore();
    if (legend) {
      // sparkles around legendary (sigil spec)
      for (let k = 0; k < 7; k++) {
        const ph = (t * (0.8 + rnd(k) * 0.7) + rnd(k * 5)) % 1;
        const ang = rnd(k * 3) * Math.PI * 2;
        const rr = 190 + rnd(k * 7) * 60;
        const px = x + Math.cos(ang + ph * 2) * rr;
        const py = y + Math.sin(ang + ph * 2) * rr * 0.9;
        ctx.globalAlpha = Math.sin(ph * Math.PI) * 0.9;
        ctx.fillStyle = k % 2 ? C.gold : "#fff";
        ctx.beginPath(); ctx.arc(px, py, 2 + rnd(k * 11) * 2.4, 0, 7); ctx.fill();
      }
      ctx.globalAlpha = 1;
      sparkleBurst(ctx, t, 47.25, x, y, { n: 18, dur: 1.1, dist: 260, ring: 260 });
    }
  });

  // header dim when cards fly
  // chips
  const chips = [
    { txt: "25 достижений", t0: 7.0 }, { txt: "престиж ×1.6", t0: 7.18 },
    { txt: "заказы гильдии", t0: 7.36 }, { txt: "живой рейтинг", t0: 7.54 },
  ];
  const chipOut = 1 - seg(tl, 8.15, 8.55);
  chips.forEach((c, i) => {
    const p = eob(seg(tl, c.t0, c.t0 + 0.4));
    if (p <= 0 || chipOut <= 0) return;
    const col = i % 2, row = Math.floor(i / 2);
    const x = cx + (col - 0.5) * 420;
    const y = 1500 + row * 110;
    ctx.save();
    ctx.globalAlpha = chipOut;
    ctx.translate(x, y);
    ctx.scale(clamp(p, 0.001, 1), clamp(p, 0.001, 1));
    ctx.translate(-x, -y);
    chip(ctx, c.txt, x, y, { size: 32, color: C.text, bg: "rgba(30,26,52,0.85)", border: "rgba(176,108,255,0.5)" });
    ctx.restore();
  });
  vignette(ctx, 0.42);
}

/* S7 — finale (50 – 60) */
function s7(ctx, t) {
  bgBase(ctx, t, { night: 0.35 });
  embers(ctx, t, { n: 24, heat: 1.1 });
  const tl = t - 50;
  const cx = W / 2;

  // expanding rune ring at impact
  const rp = seg(tl, 0, 0.8);
  const settle = eoe(rp);
  ctx.save();
  ctx.globalAlpha = 0.4 * settle;
  ctx.translate(cx, 870);
  ctx.rotate(t * 0.08);
  const RS = 300 + 660 * eoc(rp);
  ctx.drawImage(RING_AMBER, -RS / 2, -RS / 2, RS, RS);
  ctx.restore();
  // shock ring
  const sp = seg(tl, 0, 0.7);
  if (sp > 0 && sp < 1) {
    ctx.strokeStyle = `rgba(255,220,160,${(1 - sp) * 0.8})`;
    ctx.lineWidth = 8 * (1 - sp) + 1;
    ctx.beginPath(); ctx.arc(cx, 870, eoc(sp) * 900, 0, 7); ctx.stroke();
  }

  // app icon drop
  const ip = seg(tl, 0.45, 1.15);
  if (ip > 0) {
    const e = eob(ip);
    const iy = lerp(-200, 560, e);
    ctx.save();
    ctx.translate(cx, iy);
    ctx.rotate(Math.sin(t * 1.2) * 0.03);
    glowDot(ctx, 0, 0, 190, "255,170,60", 0.35);
    ctx.drawImage(APPICON, -110, -110, 220, 220);
    ctx.restore();
    sparkleBurst(ctx, t, 50.8, cx, 560, { n: 12, dur: 0.9, dist: 200, ring: 210 });
  }

  // runic decorative line
  const r1 = seg(tl, 1.15, 1.6);
  if (r1 > 0) {
    T(ctx, "ALCHEMISTS LOOP", cx, 800, { size: 44, alias: "AlchRunic", color: C.amber, alpha: 0.85 * eoc(r1), spacing: 6 });
  }
  // title
  const t1 = seg(tl, 1.35, 1.9);
  if (t1 > 0) {
    T(ctx, "ПЕТЛЯ АЛХИМИКА", cx, 918 + (1 - eoc(t1)) * 36, { size: 104, alias: "ManropeXB", color: "#fff", glow: "rgba(255,255,255,0.4)", glowBlur: 30, alpha: eoc(t1), spacing: 2 });
  }
  // tagline
  const t2 = seg(tl, 2.2, 2.7);
  if (t2 > 0) {
    T(ctx, "варь · открывай · замыкай петлю", cx, 1030, { size: 44, alias: "ManropeSB", color: C.dim, alpha: eoc(t2) });
  }

  // Светик celebrate
  const cp = seg(tl, 2.9, 3.6);
  if (cp > 0) {
    const sy = spirit(ctx, "celebrate", cx, 1330, 320 * clamp(eob(cp), 0.001, 1.05), t, { bob: 10 });
    // periodic mini sparks
    const k = Math.floor((t - 53.2) * 1.2);
    if (k >= 0 && t > 53.2) sparkleBurst(ctx, t, 53.2 + k / 1.2, cx + (rnd(k) - 0.5) * 300, sy + (rnd(k * 3) - 0.5) * 200, { n: 5, dur: 0.6, dist: 60, ring: 40 });
  }

  // CTA pill
  const cta = seg(tl, 4.1, 4.7);
  const ctaOut = 1 - seg(tl, 9.2, 9.8);
  if (cta > 0 && ctaOut > 0) {
    const bounce = 1 + 0.06 * Math.abs(Math.sin((t - 57.4) * 9)) * (t > 57.4 && t < 58.2 ? 1 : 0);
    ctx.save();
    ctx.globalAlpha = ctaOut;
    ctx.translate(cx, 1560);
    ctx.scale(clamp(eob(cta), 0.001, 1) * bounce, clamp(eob(cta), 0.001, 1) * bounce);
    const play = svgImg("icons/play.svg", 40);
    ctx.font = "40px ManropeXB";
    const label = "Бесплатно · Android";
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

  // closing dim
  const dim = seg(tl, 9.3, 10);
  if (dim > 0) {
    ctx.fillStyle = `rgba(5,4,10,${dim * 0.6})`;
    ctx.fillRect(0, 0, W, H);
  }
  vignette(ctx, 0.45);
}

/* ---------- frame ---------- */
const SCENES = [
  [0, 5.2, s1], [5.2, 13.5, s2], [13.5, 22.0, s3], [22.0, 32.0, s4],
  [32.0, 41.4, s5], [41.4, 50.0, s6], [50.0, 60.01, s7],
];

function renderFrame(idx) {
  const t = idx / FPS;
  const canvas = createCanvas(W, H);
  const ctx = canvas.getContext("2d");
  ctx.fillStyle = C.bg0;
  ctx.fillRect(0, 0, W, H);

  // camera: slow per-scene zoom + impact punch
  const scene = SCENES.find(([a, b]) => t >= a && t < b) || SCENES[SCENES.length - 1];
  const tl = (t - scene[0]) / (scene[1] - scene[0]);
  const zoom = 1 + 0.035 * tl + zoomAt(t);
  const [sx, sy] = shakeOffset(t);

  ctx.save();
  ctx.translate(W / 2 + sx, H / 2 + sy);
  ctx.scale(zoom, zoom);
  ctx.translate(-W / 2, -H / 2);
  scene[2](ctx, t);
  ctx.restore();

  overlays(ctx, t);
  return canvas;
}

/* ---------- CLI ---------- */
async function main() {
  await initAssets();
  await initStatics();
  const args = process.argv.slice(2);
  if (args[0] === "--still") {
    const t = parseFloat(args[1]);
    const out = args[2];
    const canvas = renderFrame(Math.round(t * FPS));
    fs.writeFileSync(out, canvas.toBuffer("image/png"));
    console.log("still", t, "->", out);
    return;
  }
  const start = parseInt(args[0] || "0"), end = parseInt(args[1] || String(TOTAL));
  const outdir = args[2] || (ROOT + "/work/frames");
  fs.mkdirSync(outdir, { recursive: true });
  for (let i = start; i < end; i++) {
    const canvas = renderFrame(i);
    fs.writeFileSync(path.join(outdir, `f${String(i).padStart(5, "0")}.png`), await canvas.encode("png"));
    if ((i - start) % 60 === 0) console.log(`frame ${i}/${end}`);
  }
  console.log(`done ${start}..${end - 1}`);
}
if (require.main === module) {
  main().catch(e => { console.error(e); process.exit(1); });
}

/* exports for cut variants (render_v2) */
module.exports = {
  C, W, H, FPS, DUR, createCanvas,
  clamp, lerp, seg, eoc, eic, eio, eoe, eob, osc, rnd,
  T, TR, rrect, glowDot, chip, svgImg, pngImg, glyphPath, ringWord,
  initAssets, initStatics, preloadSvg, preloadPng, bgBase, mixHex, vignette, embers, glyphRain,
  spirit, sparkleBurst, cauldron, orb,
  statics: () => ({ RING_AMBER, RING_TEAL, STARS, WINDOW, REVEAL, SIGILS, APPICON }),
};
