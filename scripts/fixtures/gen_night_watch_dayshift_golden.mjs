// Writes scripts/fixtures/night_watch_dayshift_golden.json from the 2D game's Salvage Run rules (games/night-watch/src/modes/dayshift/dayshift-logic.js):
// whole shifts played by a fixed, state-reading bot, as an event log and a final summary. scripts/validate_night_watch_dayshift.gd plays the same
// shifts with DayshiftLogic and demands the same logs.
//   node scripts/fixtures/gen_night_watch_dayshift_golden.mjs [path to games/night-watch]
import { pathToFileURL, fileURLToPath } from "node:url";
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const root = process.argv[2] || "/Users/kyttu/Developer/LastRoute/games/night-watch";
const { createDayGame } = await import(pathToFileURL(join(root, "src/modes/dayshift/dayshift-logic.js")).href);
const { mulberry32 } = await import(pathToFileURL(join(root, "src/core/rng.js")).href);

const bot = (kind, s) => {
  if (kind === "idle") return {};
  const quiet = s.ysolde.state === "knock" || s.ysolde.state === "here";
  const first = s.items[0];
  return {
    work: !quiet && !!first, target: first ? first.slot : -1,
    doorL: s.ravelle.dist === 0, doorR: s.ceryth.dist === 0,
    lightL: !quiet && s.ravelle.dist === 1, lightR: !quiet && s.ceryth.dist === 1,
  };
};
const ev2s = (e) => [e.type, e.id ?? "", e.slot ?? "", e.dist ?? "", e.value ?? "", e.by ?? "", e.money ?? "", e.quota ?? ""].join("|");
const f6 = (x) => Number(x.toFixed(6));
const ALL = ["hinges", "cell", "soles", "gloves", "bench"];

const cases = [];
for (let week = 1; week <= 5; week++) for (const seed of [11, 4242]) cases.push({ week, seed, kind: "bot", upgrades: [] });
for (let week = 1; week <= 5; week += 2) cases.push({ week, seed: 7, kind: "bot", upgrades: ALL });
for (const week of [1, 3, 5]) cases.push({ week, seed: 77, kind: "idle", upgrades: [] });
cases.push({ week: 4, seed: 5, kind: "bot", upgrades: ["gloves", "bench"], custom: true, levels: { ravelle: 15, ceryth: 0, ysolde: 0 } });
cases.push({ week: 4, seed: 6, kind: "bot", upgrades: [], custom: true, levels: { ravelle: 20, ceryth: 20, ysolde: 20 } });
cases.push({ week: 1, seed: 3, kind: "bot", upgrades: [], quota: 9999 });
cases.push({ week: 2, seed: 8, kind: "bot", upgrades: [], infinitePower: true });

const runs = [];
for (const c of cases) {
  const g = createDayGame({ week: c.week, rng: mulberry32(c.seed), upgrades: c.upgrades, levels: c.levels || {}, custom: !!c.custom, quota: c.quota, infinitePower: !!c.infinitePower });
  const events = [];
  let steps = 0;
  while (!g.state.over && steps < 4000) {
    for (const e of g.step(100, bot(c.kind, g.state))) events.push(`${steps}|${ev2s(e)}`);
    steps++;
  }
  const s = g.state;
  runs.push({ ...c, steps, events, summary: { elapsed: f6(s.elapsed), power: f6(s.power), noise: f6(s.noise), money: s.money, over: s.over || "", by: s.by || "", items: s.items.length, deck: s.deck.id, lead: s.lead || "", ysolde: s.ysolde.state } });
}
const here = dirname(fileURLToPath(import.meta.url));
writeFileSync(join(here, "night_watch_dayshift_golden.json"), JSON.stringify({ source: "games/night-watch/src/modes/dayshift/dayshift-logic.js", dt: 100, runs }, null, 1) + "\n");
console.log(runs.map((r) => `${r.week}/${r.seed}/${r.kind} ${r.summary.over}${r.summary.by ? ":" + r.summary.by : ""} $${r.summary.money} ${r.events.length} events`).join("\n"));
