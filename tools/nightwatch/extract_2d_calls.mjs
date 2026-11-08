// Extracts Zellia's call tables from the 2D Night Watch source into tests/data/night_watch_2d_calls.json (the golden file the 3D
// validator compares NightWatchCallsData against). Run where the 2D repo is checked out:
//   node tools/nightwatch/extract_2d_calls.mjs /path/to/LastRoute/games/night-watch > tests/data/night_watch_2d_calls.json
// Also records the 2D call timings from core/callbox.js (read as text: 2200 ms ring, 250 ms word, 1800 + 380 per word).
import { readFileSync } from "node:fs";
const root = process.argv[2];
if (!root) { console.error("usage: node tools/nightwatch/extract_2d_calls.mjs /path/to/LastRoute/games/night-watch"); process.exit(2); }
const mods = { classic: "classic/classic-data.js", mask: "mask/mask-data.js", lure: "lure/lure-data.js", bedroom: "bedroom/bedroom-data.js", story: "data/story/story-data.js", descent: "descent/descent-data.js", dayshift: "dayshift/dayshift-data.js", extra: "openair/openair-data.js" };
const calls = {};
for (const [id, f] of Object.entries(mods)) calls[id] = (await import(`${root}/src/modes/${f}`)).CALLS;
const box = readFileSync(`${root}/src/core/callbox.js`, "utf8");
const timing = { ring: +/cs\.t = -(\d+)/.exec(box)[1], word: +/Math\.floor\(cs\.t \/ (\d+)\)/.exec(box)[1], base: +/cs\.dur = (\d+) \+/.exec(box)[1], perWord: +/words\.length \* (\d+)/.exec(box)[1] };
console.log(JSON.stringify({ timing, calls }, null, 1));
