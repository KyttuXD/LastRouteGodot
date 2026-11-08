// Writes the 2D game's Bedtime reference numbers for tests/validate_night_watch_bedroom.gd.
//   node tools/nightwatch/gen_bedroom_golden.mjs <path to games/night-watch> > tests/data/nw_bedroom_golden.json
import { pathToFileURL } from "node:url";
import path from "node:path";
const root = path.resolve(process.argv[2]);
const imp = (p) => import(pathToFileURL(path.join(root, p)).href);
const { createBedroomGame, NIGHT_MS } = await imp("src/modes/bedroom/bedroom-logic.js");
const { mulberry32 } = await imp("src/core/rng.js");
const input = (i) => ({ hold: i % 40 < 12, light: i % 40 > 30 ? "bed" : i % 40 > 20 ? "hall" : null });
const out = { traces: [] };
const cases = [[1, 3], [2, 5], [3, 8], [4, 13], [5, 21], [6, 34], [6, 35], [4, 55]];
for (const [night, seed] of cases) for (const mode of ["busy", "idle"]) {
  const g = createBedroomGame({ night, rng: mulberry32(seed) }), s = g.state, ev = [];
  let i = 0;
  for (; i < NIGHT_MS / 100 && !s.over; i++) for (const e of g.step(100, mode === "busy" ? input(i) : {})) ev.push(`${i}:${e.type}:${e.id || e.by || ""}`);
  out.traces.push({ night, seed, mode, steps: i, over: s.over, by: s.by, events: ev.join(","), battery: +s.battery.toFixed(6), p: +s.haelith.p.toFixed(6), idle: s.idle, swapped: s.swapped });
}
// Custom Night, every slider at 20 and at 8, the closet-and-hall bot
for (const lv of [8, 20]) for (const seed of [1, 2, 3]) {
  const g = createBedroomGame({ night: 5, rng: mulberry32(seed), custom: true, levels: { loxelle: lv, javelle: lv, haelith: lv } }), s = g.state, ev = [];
  let i = 0;
  for (; i < NIGHT_MS / 100 && !s.over; i++) for (const e of g.step(100, input(i))) ev.push(`${i}:${e.type}:${e.id || e.by || ""}`);
  out.traces.push({ night: 5, seed, mode: "custom" + lv, steps: i, over: s.over, by: s.by, events: ev.join(","), battery: +s.battery.toFixed(6), p: +s.haelith.p.toFixed(6), idle: s.idle, swapped: s.swapped });
}
console.log(JSON.stringify(out));
