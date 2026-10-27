// Writes the 2D game's Dead Air reference numbers that scripts/validate_night_watch_lure.gd compares the 3D port against.
//   node tools/nightwatch/gen_lure_golden.mjs <path to games/night-watch> > scripts/data/nw_lure_golden.json
import { pathToFileURL } from "node:url";
import path from "node:path";
const root = path.resolve(process.argv[2]);
const imp = (p) => import(pathToFileURL(path.join(root, p)).href);
const { createLureGame, NIGHT_MS } = await imp("src/modes/lure/lure-logic.js");
const { mulberry32 } = await imp("src/core/rng.js");

const bot = (g, i) => {
  const s = g.state;
  if (i % 10 === 0) {
    for (const [name, sys] of Object.entries(s.systems)) if (sys.state === "broken") g.reboot(name);
    g.seal("L", s.killer.room === "officeL"); g.seal("R", s.killer.room === "officeR");
    if (s.climate) { if (s.temp < 63 && !s.heaterOn) g.toggle("heater"); if (s.temp >= 69 && s.heaterOn) g.toggle("heater"); if (s.temp > 88 && !s.fanOn) g.toggle("fan"); if (s.temp <= 78 && s.fanOn) g.toggle("fan"); }
  }
  if (i % 900 === 450) g.lure("ballpit");
  return { watch: i % 200 < 70 && ["storage", "ventl", "ventr"].includes(s.killer.room) ? s.killer.room : null };
};
const out = { rng: {}, traces: [], custom: {} };
for (const seed of [1, 12345, 50001]) { const r = mulberry32(seed); out.rng[seed] = Array.from({ length: 6 }, () => r()); }
for (const [night, seed] of [[1, 7], [2, 11], [3, 21], [4, 31], [5, 41], [6, 51], [6, 52], [4, 99]]) {
  const g = createLureGame({ night, rng: mulberry32(seed) }), s = g.state, ev = [];
  let i = 0;
  for (; i < NIGHT_MS / 100 && !s.over; i++) for (const e of g.step(100, bot(g, i))) ev.push(`${i}:${e.type}:${e.room || e.system || e.id || e.side || e.by || ""}`);
  out.traces.push({ night, seed, steps: i, over: s.over, by: s.by, events: ev.join(","), stress: +s.stress.toFixed(6), temp: +s.temp.toFixed(6), elapsed: s.elapsed });
}
// the 20/20/20/20 Custom Night, QA's sharp lure bot (play loop from validate-lure-air.mjs), seeds 50001..50000+N
const ai = { wynelle: 20, xivvy: 20, mavrine: 20, briselle: 20, solyth: 20, ferryn: 20 };
const play = (seed, botName) => {
  const g = createLureGame({ night: 5, rng: mulberry32(seed), custom: true, level: ai.xivvy, phantomLevels: ai, climateLevels: ai }), s = g.state, k = s.killer;
  const LAG = { sharp: 300, sharpnl: 300, human: 800, ear: 800 }[botName] / 50, hist = [];
  const band = botName === "sharp" || botName === "sharpnl" ? [62, 66, 91, 86] : [61, 68, 92, 84];
  while (!s.over) {
    hist.push({ room: k.room, broken: Object.keys(s.systems).filter((n) => s.systems[n].state === "broken"), temp: s.temp });
    if (hist.length > LAG + 1) hist.shift();
    const p = hist[0];
    for (const n of p.broken) if (s.systems[n].state === "broken") g.reboot(n);
    for (const side of ["L", "R"]) { const at = p.room === "office" + side; if (at && !s.seals[side]) g.seal(side, true); else if (!at && s.seals[side]) g.seal(side, false); }
    if (botName === "sharp" && (p.room === "storage" || p.room.startsWith("vent")) && g.online("audio") && s.lureCool <= 0) g.lure("lobby");
    if (p.temp < band[0] && !s.heaterOn && g.online("heater")) g.toggle("heater");
    if (s.heaterOn && p.temp > band[1]) g.toggle("heater");
    if (s.fan && p.temp > band[2] && !s.fanOn && g.online("fan")) g.toggle("fan");
    if (s.fanOn && p.temp < band[3]) g.toggle("fan");
    g.step(50, { watch: botName !== "ear" && g.online("cams") && /^(storage|vent)/.test(p.room) ? p.room : null });
  }
  return s.over === "win";
};
const N = 60;
out.custom = { first: 50001, count: N, wins: {} };
for (const b of ["sharp", "sharpnl", "human", "ear"]) { let w = 0; for (let seed = 50001; seed < 50001 + N; seed++) if (play(seed, b)) w++; out.custom.wins[b] = w; }
console.log(JSON.stringify(out));
