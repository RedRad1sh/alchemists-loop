/* render_v2.js — CLI for the 5 creative cuts.
 *   node src/render_v2.js v1 --still 12.5 out.png
 *   node src/render_v2.js v1 0 1800 work/frames_v1
 */
const fs = require("fs");
const path = require("path");
const R = require("./render.js");
const { CUTS, makeEvents, frameFor, init } = require("./cuts_v2.js");

(async () => {
  await R.initAssets();
  await R.initStatics();
  await init();
  const args = process.argv.slice(2);
  const cut = CUTS[args[0]];
  if (!cut) { console.error("unknown cut:", args[0], "(v1..v5)"); process.exit(1); }
  const ev = makeEvents(cut);
  if (args[1] === "--still") {
    const t = parseFloat(args[2]);
    const out = args[3];
    fs.writeFileSync(out, frameFor(cut, ev, Math.round(t * R.FPS)).toBuffer("image/png"));
    console.log("still", t, "->", out);
    return;
  }
  const start = parseInt(args[1] || "0"), end = parseInt(args[2] || String(R.FPS * R.DUR));
  const outdir = args[3] || ("work/frames_" + args[0]);
  fs.mkdirSync(outdir, { recursive: true });
  for (let i = start; i < end; i++) {
    const canvas = frameFor(cut, ev, i);
    fs.writeFileSync(path.join(outdir, `f${String(i).padStart(5, "0")}.png`), await canvas.encode("png"));
    if ((i - start) % 120 === 0) console.log(`frame ${i}/${end}`);
  }
  console.log(`done ${start}..${end - 1}`);
})().catch(e => { console.error(e); process.exit(1); });
