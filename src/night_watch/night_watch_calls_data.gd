class_name NightWatchCallsData
extends RefCounted

## Zellia's headset calls, copied verbatim from the 2D game: each mode's `CALLS` in games/night-watch/src/modes/<mode>/<mode>-data.js
## ({"level": {at: seconds into the night she rings, lines: [...]}}), keyed by the 3D mode id (Open Air is `extra`). Mixed Shift and a
## Custom Night have no call (2D: `callForNight` is null / `opts.custom` gives no script). Regenerate from the 2D files; do not hand-edit.
## scripts/validate_night_watch_calls.gd extracts the same tables from the 2D source (when it is present) and compares them.
## The 2D wording is kept exactly, including its key names (the 2D keys are A/D doors, Q/E lights, Space cameras).

## Timings from the 2D core/callbox.js, ms.
const INCOMING_MS := 2200       # "Incoming call..." shows this long before the first line (the ring)
const WORD_MS := 250            # one more word every 250 ms
const LINE_BASE_MS := 1800      # a line stays up for this plus ...
const LINE_WORD_MS := 380       # ... this per word
const INCOMING_TEXT := "Incoming call…"

const CALLS := {
 "classic": {
  "1": {
   "at": 5,
   "lines": [
    "Zellia, on the headset. Can you hear me all right? Good.",
    "Doors are A and D. Lights are Q and E, held. The cameras are on Space. Your power is limited, so spend it carefully.",
    "Dovelle comes by the left door. A light on her holds her still. Keep it on her and she backs right off. Closing the door is quicker, but she won't go far.",
    "If the power goes, the doors open and the lights fail. You won't be alone in the dark for long.",
    "I'll check in again later. Try to stay calm. It makes the night shorter."
   ]
  },
  "2": {
   "at": 5,
   "lines": [
    "Zellia again. Ravelle is on the floor tonight, at the right-hand door. If a shut door turns her away she'll try the other one.",
    "If a camera loses its picture it's usually temporary. Check another room and come back."
   ]
  },
  "3": {
   "at": 5,
   "lines": [
    "Aki has started moving. She only moves while you aren't looking at a camera, so keep your checks short.",
    "Keep your hands steady. The building notices more than people think."
   ]
  },
  "4": {
   "at": 5,
   "lines": [
    "Ilyra is up. She stays where she is while you're watching her room, which tells you something about her.",
    "Footsteps carry. The louder they are, the closer they are. That's the whole rule."
   ]
  },
  "5": {
   "at": 5,
   "lines": [
    "Everyone is active tonight, and they move faster than before. Two of them at their doors at once is worse than one.",
    "Keep to a routine. It's easier to hold a pattern than to invent one at three in the morning."
   ]
  },
  "6": {
   "at": 5,
   "lines": [
    "You've reached the sixth night. Not many people do.",
    "There's nothing new to tell you. Be careful, and be patient."
   ]
  },
  "7": {
   "at": 5,
   "lines": [
    "Zellia. It's only Kathy tonight. She won't show up in the door lights, but when she reaches a door, its light stutters.",
    "Keep a light on her door, open or shut, and it dips now and then while she's there. That's all you get to see.",
    "Listen too. A breath means she's in a hall. Static means she's at that door, and she hums while she waits. A shut door muffles it.",
    "The cameras catch her in flickers. Catch one in a hall and meet her eyes, K, and she goes back. Miss, and you'll have to wait.",
    "When she gives up at a shut door she leaves without a sound. The hum stops and the light stops dipping. Check before you open."
   ]
  }
 },
 "mask": {
  "1": {
   "at": 6,
   "lines": [
    "Zellia. This wing has no doors, so the usual routine doesn't apply.",
    "Thessine will use the hall. If she walks into the office, put the mask on with S and keep it on until she leaves. F lights the hall.",
    "The cameras are on Space or W, and the music box is on camera 1. Hold R to wind it. It starts to run down at 2 AM tonight.",
    "Watch the ballroom. Whoever is standing there takes the hall next. Camera 8 is the hall itself, right outside your door.",
    "While you watch one of them on camera on her way here, she holds still. The cameras run off your battery, though, and so does the desk lamp on L.",
    "Your flashlight is limited, and it doesn't come back. If it dies, don't wait in the dark."
   ]
  },
  "2": {
   "at": 6,
   "lines": [
    "Verrine is out tonight. She stays in the vents, and it is dark in there, so she only shows in the light. Q lights the left one and E the right. A light on her usually settles things.",
    "Cameras 6 and 7 show the ducts, and the ducts are dark too. Hold Q on camera 6 or E on camera 7 to light the duct. If she's crawling down one, you know which vent to light."
   ]
  },
  "3": {
   "at": 6,
   "lines": [
    "Umbriel is out tonight, and she doesn't walk. She runs. When you hear her break into a run, she's coming down the hall.",
    "The mask does nothing to her. Flash the hall light at her, F, a few quick flashes, and she backs off to the gallery.",
    "If she's crouched by the hall doors on camera 4, she's about to go. Watching her there holds her, but once she runs, the cameras won't stop her.",
    "Each flash costs a little battery, so don't waste them."
   ]
  },
  "4": {
   "at": 6,
   "lines": [
    "The music box runs down faster now. Listen to the tune. When it slows, it needs winding.",
    "Haelith is out tonight. She runs the ducts fast, and a quick light sends her off. She doesn't go far: she comes back down the other duct."
   ]
  },
  "5": {
   "at": 6,
   "lines": [
    "Everyone in this wing is awake tonight. The routine hasn't changed.",
    "Ilyra is out tonight too. She creeps along the ducts while it is dark and freezes when the light is on her. Only one of them is ever in the vents at a time."
   ]
  },
  "6": {
   "at": 6,
   "lines": [
    "This is the last night in this wing, and the box runs down fastest of all. Keep to the routine, and keep the flashlight for when it counts."
   ]
  }
 },
 "lure": {
  "1": {
   "at": 6,
   "lines": [
    "Zellia. This is the attraction hall. Only one of them is active tonight, and she's harmless: she takes the cameras.",
    "When something goes dark, reboot it from the monitor with Q, W or E.",
    "A and D seal the vents. Space opens the monitor, and L plays a sound in the room you're watching.",
    "Sealed vents make the air heavy, so don't leave them closed for long."
   ]
  },
  "2": {
   "at": 6,
   "lines": [
    "Xivvy is awake now, and she's the real one. She picks a vent and keeps to it until something turns her away.",
    "Use the lure sparingly. The speakers don't like being asked twice in a row."
   ]
  },
  "3": {
   "at": 6,
   "lines": [
    "Briselle is in tonight. She takes the audio, and with no audio there's no lure. Reboot it on Q.",
    "They take more than their usual now. Check what is down, not only what you expect."
   ]
  },
  "4": {
   "at": 6,
   "lines": [
    "The building has a temperature tonight, and it is falling. That's Wynelle. There's a heater on H, and it reboots on R.",
    "Don't leave the heater running for long. It costs air."
   ]
  },
  "5": {
   "at": 6,
   "lines": [
    "Mavrine is in tonight. She takes the vents, and the heater with them. Keep an eye on the air.",
    "That's five of them. The routine is the same. Keep the reboots going."
   ]
  },
  "6": {
   "at": 6,
   "lines": [
    "Last night in the hall. Ferryn is resting, but the heat has someone of its own: Solyth. Too much heater and she cooks the office.",
    "There's a fan on F, and it reboots on T. The cold bites hardest tonight and the hunter is quickest. I'll be on the line if you need me."
   ]
  }
 },
 "bedroom": {
  "1": {
   "at": 6,
   "lines": [
    "Zellia. This room is quiet and there are no cameras. You'll hear things before you see them.",
    "Loxelle is in the closet. You won't see her, but you'll hear her breathing on the left, and her breath gets heavy when she's close. A holds it shut until it stops.",
    "D puts a light on the hall, F on the bed. You only have one free hand, so choose.",
    "The battery is limited, and it doesn't come back. Don't waste it."
   ]
  },
  "2": {
   "at": 6,
   "lines": [
    "Javelle is awake. She stays where the light ends. A little light on the hall is usually enough."
   ]
  },
  "3": {
   "at": 6,
   "lines": [
    "Haelith only moves when the room is dark, and a light on the bed pushes her back. Keep that in mind when you're saving the battery."
   ]
  },
  "4": {
   "at": 6,
   "lines": [
    "The house is louder tonight. Listen for which side it's coming from, and answer that side.",
    "It also notices stillness. If you lie there doing nothing for too long, they get restless. The closet door costs nothing to hold."
   ]
  },
  "5": {
   "at": 6,
   "lines": [
    "All three are awake. Listen first, then act, and save the battery for the side that needs it."
   ]
  },
  "6": {
   "at": 6,
   "lines": [
    "Last night in this room. The battery is the shortest it has been. Same as before: listen first, then act."
   ]
  }
 },
 "story": {
  "1": {
   "at": 5,
   "lines": [
    "Zellia. Tonight is orientation. I'll give you tasks and you'll carry them out in order.",
    "Your list is on the left. A and D take you through the side doors, and W through the lift door. Each room's task is done at its own station, so look around.",
    "Nothing is active tonight. Take your time and learn the layout."
   ]
  },
  "2": {
   "at": 5,
   "lines": [
    "The gallery has a resident, and the lamps there need you twice tonight. Opalie responds to noise, and everything you do at a station is a little loud, so work quietly there.",
    "C switches you to crawling, which is slower but quiet. The red line on your noise meter is what she can hear. Under it she still creeps in, slowly, so don't dawdle.",
    "If she gets to your door, leave. Getting through a door takes a moment, so go at one step, not at the last second."
   ]
  },
  "3": {
   "at": 5,
   "lines": [
    "The workshop and the auditorium are watched by Porcelle. She comes closer when it's dark.",
    "The beacon on F holds her still, and held long enough it pushes her back. It does run down, so don't leave it on. When Opalie hears something, Porcelle is warned.",
    "Leaving a room doesn't make them forget you. They wait near the door for you to come back. The list ends in the gallery again, so keep it quiet."
   ]
  },
  "4": {
   "at": 5,
   "lines": [
    "The lift runs between floors on a schedule, and Quenelle rides it. A bell sounds shortly before it opens at Control. The gallery lamps want checking again before you sign off.",
    "If you're in Control when it opens, hide with H until it leaves. Don't be in the lift itself when it opens; get out when the bell goes. The lamp under your list lights with it."
   ]
  },
  "5": {
   "at": 5,
   "lines": [
    "Everything is active tonight, and the list covers the whole building.",
    "Keep your routes short and keep the noise down."
   ]
  },
  "6": {
   "at": 5,
   "lines": [
    "This is the last list, and the longest. Every room is on it, and everyone is keener than before, and keener the longer you take.",
    "Do it in order and don't hurry. Hurrying is loud."
   ]
  }
 },
 "descent": {
  "1": {
   "at": 5,
   "lines": [
    "Zellia. The elevator needs its service run, and you'll be doing it from the car.",
    "Each stage has its own panel. The first is the fuse boxes: when one lights up, follow its wire to the button it ends at and press it.",
    "Nothing is out there tonight. Take your time."
   ]
  },
  "2": {
   "at": 5,
   "lines": [
    "There's something outside the car this time. She comes closer the longer you take, and every wrong attempt makes it quicker.",
    "A new stage this run: the signal panel. Four pads light up one at a time. When they stop, press them in the same order."
   ]
  },
  "3": {
   "at": 5,
   "lines": [
    "This run has pipes as well. Turn each piece until there's one clear line from IN to OUT. She slows down while you work the pipes, but she doesn't stop.",
    "Finish a stage and she drops back for a while. Get through them one at a time and don't linger."
   ]
  },
  "4": {
   "at": 5,
   "lines": [
    "At the bottom she may try to get on. Hold the door shut until the car stops.",
    "Keep your wrong attempts down. They count for more now."
   ]
  },
  "5": {
   "at": 5,
   "lines": [
    "This is the longest run. Everything's on it, and the wires have to be done twice.",
    "Stay steady. You've done each of these already."
   ]
  }
 },
 "dayshift": {
  "1": {
   "at": 5,
   "lines": [
    "Zellia. This is a work week, so the day comes first. Spend your budget in the shop, then start the shift.",
    "At night, pick a piece on the rack (1 to 4, or click it) and hold Space to take it. The quota is shown at the top. Noise is a cost, and you'll want to keep an eye on it.",
    "A and D are the side doors. Q and E are the lights, held. Ravelle comes to the left one, and if you close it she goes."
   ]
  },
  "2": {
   "at": 5,
   "lines": [
    "There's a second visitor this week: Ceryth, at the right-hand door. The same doors and lights apply, and when one of them is turned away she warns the other.",
    "A light on a doorway is enough to keep someone from moving. It uses power, so use it sparingly."
   ]
  },
  "3": {
   "at": 5,
   "lines": [
    "The window at the back is used after closing. When you hear a knock, Ysolde is there.",
    "Until she's gone, let go of the rack and keep the lights off. The doors make no sound, so shut one if someone's there."
   ]
  },
  "4": {
   "at": 5,
   "lines": [
    "Everyone is on this week and the quota is higher. Any surplus from last week carries over, up to a point.",
    "Choose the pieces you take. Not all of them are worth the noise."
   ]
  },
  "5": {
   "at": 5,
   "lines": [
    "This is the last week of the schedule, and the highest quota. A prize is the quickest way there, if you can afford the noise."
   ]
  }
 },
 "extra": {
  "1": {
   "at": 6,
   "lines": [
    "Zellia. Tonight's watch is on the roof. The wind keeps taking the lantern, so relight it when it goes.",
    "A is the stair door and D is the hatch. Q and E hold the torch toward each side.",
    "Close one when she's at it, and keep the torch on her while she approaches. The lantern's oil works the winches as well as the light, so don't hold them shut for longer than you have to."
   ]
  },
  "2": {
   "at": 6,
   "lines": [
    "The bus stop. It's colder than it looks out there.",
    "The heat lamp is on H and it burns fuel. There are canisters left around the shelter. Pick them up when you see them.",
    "Snow comes through in squalls, and the cold bites harder while one lasts. The first bus is due at dawn."
   ]
  },
  "3": {
   "at": 6,
   "lines": [
    "Last watch is the campfire. Logs go in on Space, and G fetches more from the dark. Your back is to the trees while you do.",
    "Verrine comes out of the trees on the left, Quenelle on the right. Q and E hold the torch on a side, and that holds her still.",
    "Keep the torch on Verrine once she reaches the light, and she goes back. It only holds Quenelle: get in the tent with T while she's there and she loses the trail.",
    "The tent only hides you from Quenelle. Verrine keeps coming, and Ysolde goes for the logs. Stay in too long and she looks in.",
    "Rain comes and goes, and the fire goes down faster in it. When it burns low, they get bolder."
   ]
  }
 }
}


## {at, lines} for a level of a mode, or {} when it is a quiet night.
static func for_level(mode_id: String, level: int) -> Dictionary:
	var table: Dictionary = CALLS.get(mode_id, {})
	return table.get(str(level), {})
