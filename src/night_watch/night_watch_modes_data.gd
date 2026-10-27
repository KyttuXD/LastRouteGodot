class_name NightWatchModesData
extends RefCounted

## The 2D Night Watch's mode table, copied verbatim from games/night-watch/src/modes/registry.js (mode ids, titles, taglines,
## blurbs, shift names, presets, casts, Custom Night sliders). The Godot menus, the Custom Night page and the mode framework
## all read this, so the 3D menus and the 2D menus cannot drift apart; scripts/validate_night_watch_menus.gd checks the screens
## against it. Regenerate from the 2D registry, do not hand-edit.

const MAX_AI := 20
const POINTS_PER_LEVEL := 10
## [minimum share of the top score, rating] from the 2D account/merge.js, best first.
const RATINGS := [[1.0, "Unbeatable!"], [0.8, "Perfect!"], [0.6, "Stupendous!"], [0.4, "Amazing!"], [0.2, "Fantastic!"], [0.0, "Great Job!"]]

const NAMES := {
 "aki": "Aki",
 "briselle": "Briselle",
 "ceryth": "Ceryth",
 "dovelle": "Dovelle",
 "elise": "Elise",
 "ferryn": "Ferryn",
 "glyra": "Glyra",
 "haelith": "Haelith",
 "ilyra": "Ilyra",
 "javelle": "Javelle",
 "kathy": "Kathy",
 "loxelle": "Loxelle",
 "mavrine": "Mavrine",
 "nyxie": "Nyxie",
 "opalie": "Opalie",
 "porcelle": "Porcelle",
 "quenelle": "Quenelle",
 "ravelle": "Ravelle",
 "solyth": "Solyth",
 "thessine": "Thessine",
 "umbriel": "Umbriel",
 "verrine": "Verrine",
 "wynelle": "Wynelle",
 "xivvy": "Xivvy",
 "ysolde": "Ysolde",
 "zellia": "Zellia"
}

const MODES := [
 {
  "id": "classic",
  "num": 1,
  "label": "1. CLASSIC",
  "title": "CLASSIC",
  "tag": "DOORS · LIGHTS · CAMERAS",
  "playable": true,
  "resumable": true,
  "office": "classic",
  "cast": [
   "dovelle",
   "nyxie",
   "ravelle",
   "ilyra",
   "aki"
  ],
  "art": [
   "dovelle",
   "nyxie"
  ],
  "custom": [
   {
    "id": "dovelle",
    "label": "Dovelle"
   },
   {
    "id": "nyxie",
    "label": "Nyxie"
   },
   {
    "id": "ravelle",
    "label": "Ravelle"
   },
   {
    "id": "ilyra",
    "label": "Ilyra"
   },
   {
    "id": "aki",
    "label": "Aki"
   }
  ],
  "presets": [
   {
    "id": "first-shift",
    "name": "First Shift",
    "ai": {
     "dovelle": 8,
     "nyxie": 0,
     "ravelle": 0,
     "ilyra": 0,
     "aki": 0
    }
   },
   {
    "id": "two-doors",
    "name": "Two Doors",
    "ai": {
     "dovelle": 10,
     "nyxie": 0,
     "ravelle": 10,
     "ilyra": 0,
     "aki": 0
    }
   },
   {
    "id": "quiet-halls",
    "name": "Quiet Halls",
    "ai": {
     "dovelle": 0,
     "nyxie": 0,
     "ravelle": 0,
     "ilyra": 15,
     "aki": 15
    }
   },
   {
    "id": "all-twenty",
    "name": "20/20/20/20",
    "ai": {
     "dovelle": 20,
     "nyxie": 20,
     "ravelle": 20,
     "ilyra": 20,
     "aki": 20
    }
   }
  ],
  "blurb": "Two doors, two lights, eight cameras and one power meter. Close a door on whoever is waiting and she goes. If the power dies, so do the doors.",
  "hint": "",
  "levels": [
   "NIGHT 1",
   "NIGHT 2",
   "NIGHT 3",
   "NIGHT 4",
   "NIGHT 5",
   "NIGHT 6",
   "NIGHT 7"
  ],
  "scored": 7,
  "open": false,
  "customLevel": null
 },
 {
  "id": "mask",
  "num": 2,
  "label": "2. MASKED HOURS",
  "title": "MASKED HOURS",
  "tag": "MASK · MUSIC BOX · VENTS",
  "playable": true,
  "resumable": true,
  "office": "mask",
  "cast": [
   "verrine",
   "thessine",
   "glyra",
   "nyxie",
   "umbriel",
   "haelith",
   "ilyra"
  ],
  "art": [
   "thessine",
   "nyxie"
  ],
  "custom": [
   {
    "id": "verrine",
    "label": "Verrine"
   },
   {
    "id": "thessine",
    "label": "Thessine"
   },
   {
    "id": "glyra",
    "label": "Glyra"
   },
   {
    "id": "nyxie",
    "label": "Nyxie"
   },
   {
    "id": "umbriel",
    "label": "Umbriel"
   },
   {
    "id": "haelith",
    "label": "Haelith"
   },
   {
    "id": "ilyra",
    "label": "Ilyra"
   }
  ],
  "presets": [
   {
    "id": "hall-pass",
    "name": "Hall Pass",
    "ai": {
     "verrine": 0,
     "thessine": 12,
     "glyra": 5,
     "nyxie": 0,
     "umbriel": 12,
     "haelith": 0,
     "ilyra": 0
    }
   },
   {
    "id": "vent-duty",
    "name": "Vent Duty",
    "ai": {
     "verrine": 15,
     "thessine": 0,
     "glyra": 8,
     "nyxie": 0,
     "umbriel": 0,
     "haelith": 0,
     "ilyra": 0
    }
   },
   {
    "id": "wound-tight",
    "name": "Wound Tight",
    "ai": {
     "verrine": 6,
     "thessine": 6,
     "glyra": 20,
     "nyxie": 6,
     "umbriel": 6,
     "haelith": 0,
     "ilyra": 0
    }
   },
   {
    "id": "all-twenty",
    "name": "20/20/20/20",
    "ai": {
     "verrine": 20,
     "thessine": 20,
     "glyra": 20,
     "nyxie": 20,
     "umbriel": 20,
     "haelith": 20,
     "ilyra": 20
    }
   }
  ],
  "blurb": "No doors. Watch the cameras for who is coming, wear the mask when the hall hunters walk in, wind the music box, light the vents, and keep the flashlight alive: when it dies, someone comes.",
  "hint": "",
  "levels": [
   "NIGHT 1",
   "NIGHT 2",
   "NIGHT 3",
   "NIGHT 4",
   "NIGHT 5",
   "NIGHT 6"
  ],
  "scored": 6,
  "open": false,
  "customLevel": null
 },
 {
  "id": "lure",
  "num": 3,
  "label": "3. DEAD AIR",
  "title": "DEAD AIR",
  "tag": "VENTS · REBOOTS · CLIMATE",
  "playable": true,
  "resumable": true,
  "office": "lure",
  "cast": [
   "wynelle",
   "xivvy",
   "mavrine",
   "briselle",
   "solyth",
   "ferryn"
  ],
  "art": [
   "ferryn",
   "wynelle"
  ],
  "custom": [
   {
    "id": "wynelle",
    "label": "Wynelle"
   },
   {
    "id": "xivvy",
    "label": "Xivvy"
   },
   {
    "id": "mavrine",
    "label": "Mavrine"
   },
   {
    "id": "briselle",
    "label": "Briselle"
   },
   {
    "id": "solyth",
    "label": "Solyth"
   },
   {
    "id": "ferryn",
    "label": "Ferryn"
   }
  ],
  "presets": [
   {
    "id": "maintenance-only",
    "name": "Maintenance Only",
    "ai": {
     "wynelle": 0,
     "xivvy": 0,
     "mavrine": 12,
     "briselle": 12,
     "solyth": 0,
     "ferryn": 12
    }
   },
   {
    "id": "the-real-one",
    "name": "The Real One",
    "ai": {
     "wynelle": 0,
     "xivvy": 15,
     "mavrine": 3,
     "briselle": 3,
     "solyth": 0,
     "ferryn": 3
    }
   },
   {
    "id": "climate-control",
    "name": "Climate Control",
    "ai": {
     "wynelle": 10,
     "xivvy": 0,
     "mavrine": 12,
     "briselle": 0,
     "solyth": 10,
     "ferryn": 0
    }
   },
   {
    "id": "all-twenty",
    "name": "20/20/20/20",
    "ai": {
     "wynelle": 20,
     "xivvy": 20,
     "mavrine": 20,
     "briselle": 20,
     "solyth": 20,
     "ferryn": 20
    }
   }
  ],
  "blurb": "One hunter crawling the vents (from night 2), phantoms that break your systems, and a building whose temperature swings between cold and heat. One more of them each night, never more than five at once. Lure, seal, reboot, and keep it livable.",
  "hint": "",
  "levels": [
   "NIGHT 1",
   "NIGHT 2",
   "NIGHT 3",
   "NIGHT 4",
   "NIGHT 5",
   "NIGHT 6"
  ],
  "scored": 6,
  "open": false,
  "customLevel": null
 },
 {
  "id": "bedroom",
  "num": 4,
  "label": "4. BEDTIME",
  "title": "BEDTIME",
  "tag": "LISTEN · NO CAMERAS",
  "playable": true,
  "resumable": true,
  "office": "bedroom",
  "cast": [
   "loxelle",
   "javelle",
   "haelith"
  ],
  "art": [
   "loxelle",
   "javelle"
  ],
  "custom": [
   {
    "id": "loxelle",
    "label": "Loxelle"
   },
   {
    "id": "javelle",
    "label": "Javelle"
   },
   {
    "id": "haelith",
    "label": "Haelith"
   }
  ],
  "presets": [
   {
    "id": "closet-door",
    "name": "Closet Door",
    "ai": {
     "loxelle": 15,
     "javelle": 0,
     "haelith": 0
    }
   },
   {
    "id": "hall-watch",
    "name": "Hall Watch",
    "ai": {
     "loxelle": 0,
     "javelle": 15,
     "haelith": 0
    }
   },
   {
    "id": "lights-out",
    "name": "Lights Out",
    "ai": {
     "loxelle": 6,
     "javelle": 6,
     "haelith": 15
    }
   },
   {
    "id": "all-twenty",
    "name": "20/20/20",
    "ai": {
     "loxelle": 20,
     "javelle": 20,
     "haelith": 20
    }
   }
  ],
  "blurb": "No cameras. Hold the closet door, light the hall, light the bed, one hand at a time, on a battery that never recharges.",
  "hint": "",
  "levels": [
   "NIGHT 1",
   "NIGHT 2",
   "NIGHT 3",
   "NIGHT 4",
   "NIGHT 5",
   "NIGHT 6"
  ],
  "scored": 6,
  "open": false,
  "customLevel": null
 },
 {
  "id": "story",
  "num": 5,
  "label": "5. THE FACILITY",
  "title": "THE FACILITY",
  "tag": "ROOMS · TASKS · NOISE",
  "playable": true,
  "resumable": true,
  "office": "story",
  "cast": [
   "porcelle",
   "quenelle",
   "opalie"
  ],
  "art": [
   "porcelle",
   "quenelle"
  ],
  "custom": [
   {
    "id": "porcelle",
    "label": "Porcelle"
   },
   {
    "id": "quenelle",
    "label": "Quenelle"
   },
   {
    "id": "opalie",
    "label": "Opalie"
   }
  ],
  "presets": [
   {
    "id": "quiet-gallery",
    "name": "Quiet Gallery",
    "ai": {
     "porcelle": 0,
     "quenelle": 0,
     "opalie": 15
    }
   },
   {
    "id": "behind-the-steel",
    "name": "Behind The Steel",
    "ai": {
     "porcelle": 15,
     "quenelle": 0,
     "opalie": 0
    }
   },
   {
    "id": "lift-schedule",
    "name": "Lift Schedule",
    "ai": {
     "porcelle": 5,
     "quenelle": 15,
     "opalie": 5
    }
   },
   {
    "id": "all-twenty",
    "name": "20/20/20",
    "ai": {
     "porcelle": 20,
     "quenelle": 20,
     "opalie": 20
    }
   }
  ],
  "blurb": "Six rooms, each with its own station. Finish the night's task list in order while the noise you make draws the others.",
  "hint": "",
  "levels": [
   "NIGHT 1",
   "NIGHT 2",
   "NIGHT 3",
   "NIGHT 4",
   "NIGHT 5",
   "NIGHT 6"
  ],
  "scored": 6,
  "open": false,
  "customLevel": null
 },
 {
  "id": "descent",
  "num": 6,
  "label": "6. THE DESCENT",
  "title": "THE DESCENT",
  "tag": "WIRES · SIGNALS · PIPES",
  "playable": true,
  "resumable": true,
  "office": "descent",
  "cast": [
   "elise"
  ],
  "art": [
   "elise"
  ],
  "custom": [
   {
    "id": "elise",
    "label": "Elise"
   }
  ],
  "presets": [
   {
    "id": "slow-ride",
    "name": "Slow Ride",
    "ai": {
     "elise": 5
    }
   },
   {
    "id": "service-run",
    "name": "Service Run",
    "ai": {
     "elise": 10
    }
   },
   {
    "id": "express",
    "name": "Express",
    "ai": {
     "elise": 15
    }
   },
   {
    "id": "free-fall",
    "name": "Free Fall",
    "ai": {
     "elise": 20
    }
   }
  ],
  "blurb": "An elevator ride down the shaft. Repair the wires, the signal panel and the pipes before she reaches the window.",
  "hint": "",
  "levels": [
   "DESCENT 1",
   "DESCENT 2",
   "DESCENT 3",
   "DESCENT 4",
   "DESCENT 5"
  ],
  "scored": 5,
  "open": false,
  "customLevel": null
 },
 {
  "id": "dayshift",
  "num": 7,
  "label": "7. SALVAGE RUN",
  "title": "SALVAGE RUN",
  "tag": "MANAGE · SALVAGE",
  "playable": true,
  "resumable": true,
  "office": "dayshift",
  "cast": [
   "ravelle",
   "ceryth",
   "ysolde"
  ],
  "art": [
   "ravelle",
   "ceryth"
  ],
  "custom": [
   {
    "id": "ravelle",
    "label": "Ravelle"
   },
   {
    "id": "ceryth",
    "label": "Ceryth"
   },
   {
    "id": "ysolde",
    "label": "Ysolde"
   }
  ],
  "presets": [
   {
    "id": "left-door",
    "name": "Left Door",
    "ai": {
     "ravelle": 15,
     "ceryth": 0,
     "ysolde": 0
    }
   },
   {
    "id": "right-door",
    "name": "Right Door",
    "ai": {
     "ravelle": 0,
     "ceryth": 15,
     "ysolde": 0
    }
   },
   {
    "id": "after-hours",
    "name": "After Hours",
    "ai": {
     "ravelle": 5,
     "ceryth": 5,
     "ysolde": 15
    }
   },
   {
    "id": "all-twenty",
    "name": "20/20/20",
    "ai": {
     "ravelle": 20,
     "ceryth": 20,
     "ysolde": 20
    }
   }
  ],
  "blurb": "Spend the day's budget on upgrades, then salvage pieces off the rack at night to make the quota while the doors and the window are watched.",
  "hint": "",
  "levels": [
   "WEEK 1",
   "WEEK 2",
   "WEEK 3",
   "WEEK 4",
   "WEEK 5"
  ],
  "scored": 5,
  "open": false,
  "customLevel": 3
 },
 {
  "id": "extra",
  "num": 8,
  "label": "8. OPEN AIR",
  "title": "OPEN AIR",
  "tag": "THREE WATCHES · OUTDOORS",
  "playable": true,
  "resumable": true,
  "office": "extra",
  "cast": [
   "ysolde",
   "verrine",
   "wynelle",
   "quenelle"
  ],
  "art": [
   "verrine",
   "ysolde"
  ],
  "custom": [
   {
    "id": "ysolde",
    "label": "Ysolde"
   },
   {
    "id": "verrine",
    "label": "Verrine"
   },
   {
    "id": "wynelle",
    "label": "Wynelle"
   },
   {
    "id": "quenelle",
    "label": "Quenelle"
   }
  ],
  "presets": [
   {
    "id": "high-ground",
    "name": "High Ground",
    "ai": {
     "ysolde": 0,
     "verrine": 15,
     "wynelle": 0,
     "quenelle": 0
    }
   },
   {
    "id": "cold-road",
    "name": "Cold Road",
    "ai": {
     "ysolde": 0,
     "verrine": 0,
     "wynelle": 15,
     "quenelle": 0
    }
   },
   {
    "id": "dusk-to-dawn",
    "name": "Dusk To Dawn",
    "ai": {
     "ysolde": 8,
     "verrine": 8,
     "wynelle": 0,
     "quenelle": 12
    }
   },
   {
    "id": "all-twenty",
    "name": "20/20/20/20",
    "ai": {
     "ysolde": 20,
     "verrine": 20,
     "wynelle": 20,
     "quenelle": 20
    }
   }
  ],
  "blurb": "Three watches under the open sky: a windy rooftop, a cold bus stop and a campfire at the edge of the dark.",
  "hint": "",
  "levels": [
   "ROOFTOP",
   "BUS STOP",
   "CAMPFIRE"
  ],
  "scored": 3,
  "open": false,
  "customLevel": 0
 },
 {
  "id": "mixed",
  "num": 9,
  "label": "9. MIXED SHIFT",
  "title": "MIXED SHIFT",
  "tag": "DRAWN THREATS · A DIRECTOR · TELLS",
  "playable": true,
  "resumable": true,
  "office": "mixed",
  "cast": [
   "haelith",
   "ilyra",
   "aki",
   "opalie",
   "dovelle",
   "ravelle",
   "verrine",
   "glyra"
  ],
  "art": [
   "haelith",
   "ilyra"
  ],
  "custom": null,
  "presets": [],
  "blurb": "Three to seven threats are drawn fresh each night, each with its own warning and its own answer, paced by a director. Five shifts: three paces, CHAOS with random events and ENDLESS with no dawn.",
  "hint": "Each night draws 3 to 7 threats from a pool of eight (QUIET, STEADY and RESTLESS set the pace, CHAOS draws the biggest roster and adds random events, ENDLESS has no dawn): a Counter (builds while you stay on one camera), two Watched (move only when no camera is on them), a Monitor-gated (steps closer as you change the monitor), two Path walkers (walk a route to a door), a Vent crawler (crawls the vent run to one of three office vents) and a Winder (a music box on one camera that must be wound). Every one gives a tell first, and has an answer.",
  "levels": [
   "QUIET",
   "STEADY",
   "RESTLESS",
   "CHAOS",
   "ENDLESS"
  ],
  "scored": 4,
  "open": true,
  "customLevel": null
 }
]


static func mode(id: String) -> Dictionary:
	for m in MODES:
		if String(m["id"]) == id:
			return m
	return {}


static func rating_of(score: int, max_score: int) -> String:
	var share := float(score) / float(max_score) if max_score > 0 else 0.0
	for r in RATINGS:
		if share >= float(r[0]):
			return String(r[1])
	return String(RATINGS[RATINGS.size() - 1][1])
