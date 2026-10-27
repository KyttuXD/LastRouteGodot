// Writes the 2D game's The Facility reference numbers for scripts/validate_night_watch_story.gd.
//   node tools/nightwatch/gen_story_golden.mjs <path to games/night-watch> > scripts/data/nw_story_golden.json
import { pathToFileURL } from "node:url";
import path from "node:path";
const root = path.resolve(process.argv[2]);
const imp = (p) => import(pathToFileURL(path.join(root, p)).href);
const { createStoryGame } = await imp("src/modes/story/story-logic.js");
const { mulberry32 } = await imp("src/core/rng.js");

// A deterministic wanderer that also does its tasks: every 6 s it walks through the next door of L, R, C, every 0.7 s it does one action of the task in
// front of it, the beacon is held 1.5 s in every 10, it hides in Control for half of every 5 s and holds the call button in the lift.
const bot = (g, i) => {
  const s = g.state, ev = [];
  if (i % 60 === 0) g.move(["L", "R", "C"][(i / 60) % 3]);
  if (i % 7 === 0 && !s.moving) {
    const t = s.tasks[s.taskIdx], z = s.puzzle;
    if (t && z && t.room === s.room) {
      let p = null;
      if (z.kind === "code") p = { digit: z.code[z.entered.length] };
      else if (z.kind === "dials") { const k = z.pos.findIndex((x, j) => x !== z.target[j]); p = { i: k < 0 ? 0 : k }; }
      else if (z.kind === "collect") { const k = [...Array(z.n).keys()].find((j) => !z.taken.includes(j)); p = { i: k ?? 0 }; }
      else if (z.kind === "crank") p = {};
      else if (z.kind === "switches") p = { i: z.order[z.next] };
      if (p) ev.push(...g.interact(p));
    }
  }
  return { ev, input: { light: i % 100 < 15, hide: s.room === "control" && i % 50 < 25, work: s.room === "lift" } };
};
const out = { traces: [] };
const cases = [[1, 3], [2, 5], [3, 8], [4, 13], [5, 21], [6, 34], [6, 35], [3, 55], [5, 89]];
for (const [night, seed] of cases) for (const mode of ["normal", "keen"]) {
  const levels = mode === "keen" ? { opalie: 14, porcelle: 14, quenelle: 14 } : {};
  const g = createStoryGame({ night, rng: mulberry32(seed), levels }), s = g.state, log = [];
  const fmt = (i, e) => `${i}:${e.type}:${e.id || e.room || e.kind || e.index || ""}`;
  let i = 0;
  for (; i < 6000 && !s.over; i++) { const b = bot(g, i); for (const e of b.ev) log.push(fmt(i, e)); for (const e of g.step(100, b.input)) log.push(fmt(i, e)); }
  out.traces.push({ night, seed, mode, steps: i, over: s.over, by: s.by, order: s.order, events: log.join(","), taskIdx: s.taskIdx, noise: +s.noise.toFixed(6), charge: +s.charge.toFixed(6),
    opalie: s.opalie.dist, porcelle: s.porcelle.dist, elapsed: s.elapsed, room: s.room });
}
for (const [seed, lv] of [[1, 8], [2, 20]]) {
  const levels = { opalie: lv, porcelle: lv, quenelle: lv };
  const g = createStoryGame({ night: 5, rng: mulberry32(seed), custom: true, levels }), s = g.state, log = [];
  let i = 0;
  for (; i < 6000 && !s.over; i++) { const b = bot(g, i); for (const e of b.ev) log.push(`${i}:${e.type}:${e.id || e.room || e.kind || e.index || ""}`); for (const e of g.step(100, b.input)) log.push(`${i}:${e.type}:${e.id || e.room || e.kind || e.index || ""}`); }
  out.traces.push({ night: 5, seed, mode: "custom" + lv, steps: i, over: s.over, by: s.by, order: s.order, events: log.join(","), taskIdx: s.taskIdx, noise: +s.noise.toFixed(6), charge: +s.charge.toFixed(6),
    opalie: s.opalie.dist, porcelle: s.porcelle.dist, elapsed: s.elapsed, room: s.room });
}
console.log(JSON.stringify(out));
