// Writes tests/fixtures/night_watch_mask_golden.json from the 2D game's Masked Hours rules (games/night-watch/src/modes/mask/mask-logic.js):
// whole shifts played by a fixed, state-reading bot, as an event log and a final summary. tests/validate_night_watch_mask.gd plays the same
// shifts with MaskLogic and demands the same logs, so the 3D port's numbers are the 2D game's.
//   node tests/fixtures/gen_night_watch_mask_golden.mjs [path to games/night-watch]
import { pathToFileURL } from "node:url";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = process.argv[2];
if (!root) { console.error("usage: node " + process.argv[1] + " <path to games/night-watch>"); process.exit(1); }
const { createMaskGame, LEVELS } = await import(pathToFileURL(join(root, "src/modes/mask/mask-logic.js")).href);
const { mulberry32 } = await import(pathToFileURL(join(root, "src/core/rng.js")).href);

const CAMS = ["music", "costume", "gallery", "ballroom", "crawl", "ductL", "ductR", "hall"];
const bot = (kind, s) => {
  const e = s.elapsed;
  if (kind === "idle") return {};
  const occ = ["verrine", "haelith", "ilyra"].map((id) => (id === "verrine" ? s.vent : s[id])).find((h) => h.state !== "away");
  const inp = {
    mask: s.hall.thessine.state === "office",
    monitor: Math.floor(e / 7000) % 3 === 0,
    cam: CAMS[Math.floor(e / 3500) % 8],
    lightH: s.rush.state === "run" && Math.floor(e / 200) % 2 === 0,
    lightL: !!occ && occ.state === "vent" && occ.side === "L",
    lightR: !!occ && occ.state === "vent" && occ.side === "R",
    winding: s.box < 60,
    lamp: Math.floor(e / 20000) % 2 === 1,
  };
  if (kind === "dark") { inp.lightL = false; inp.lightR = false; inp.lightH = true; }
  return inp;
};
const ev2s = (e) => [e.type, e.id ?? "", e.room ?? "", e.side ?? "", e.step ?? "", e.n ?? "", e.by ?? ""].join("|");
const f6 = (x) => Number(x.toFixed(6));

const runs = [];
const cases = [];
for (let night = 1; night <= 6; night++) for (const seed of [11, 4242]) cases.push({ night, seed, kind: "bot" });
for (const night of [1, 4, 6]) cases.push({ night, seed: 77, kind: "idle" });
cases.push({ night: 5, seed: 9, kind: "dark" });
cases.push({ night: 5, seed: 5, kind: "bot", levels: { thessine: 20, umbriel: 20, verrine: 20, haelith: 20, ilyra: 20, glyra: 20, nyxie: 20 }, custom: true });
cases.push({ night: 5, seed: 6, kind: "bot", levels: { thessine: 0, umbriel: 0, verrine: 0, haelith: 0, ilyra: 0, glyra: 8, nyxie: 0 }, custom: true });
cases.push({ night: 6, seed: 31, kind: "bot", infiniteBattery: true });
for (const c of cases) {
  const g = createMaskGame({ night: c.night, rng: mulberry32(c.seed), levels: c.levels || {}, custom: !!c.custom, infiniteBattery: !!c.infiniteBattery });
  const events = [];
  let steps = 0;
  while (!g.state.over && steps < 4000) {
    for (const e of g.step(100, bot(c.kind, g.state))) events.push(`${steps}|${ev2s(e)}`);
    steps++;
  }
  const s = g.state;
  runs.push({ ...c, steps, events, summary: { elapsed: f6(s.elapsed), battery: f6(s.battery), box: f6(s.box), over: s.over || "", by: s.by || "", flashCount: s.flashCount, ventFlashCount: s.ventFlashCount, rushRuns: s.rush.runs } });
}
const here = dirname(fileURLToPath(import.meta.url));
writeFileSync(join(here, "night_watch_mask_golden.json"), JSON.stringify({ source: "games/night-watch/src/modes/mask/mask-logic.js", dt: 100, runs }, null, 1) + "\n");
console.log(runs.map((r) => `${r.night}/${r.seed}/${r.kind} ${r.summary.over}${r.summary.by ? ":" + r.summary.by : ""} ${r.events.length} events`).join("\n"));
