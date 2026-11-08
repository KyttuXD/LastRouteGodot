# Quick start

One page for a Last Route run. Defaults are the fresh `[input]` map in `project.godot`, plus the keys
`PlayerController3D` and `HUD` read directly. The settings panel can rebind keyboard and mouse. Gamepad buttons stay
fixed. Tab ownership and the Night Watch office keys are in [CONTROLS.md](CONTROLS.md).

## Keyboard and mouse

The mouse looks while the cursor is captured. **I J K L** and the arrow keys look when capture is off.

| Action | Default |
| --- | --- |
| Move | W A S D |
| Sprint | Shift (hold) |
| Crouch | C (hold) |
| Jump | Space |
| Interact | E or right click |
| Use the held item | Left click |
| Flashlight | F |
| Taser | G |
| Inventory | Tab |
| Hotbar | 1 2 3 4 5, or the mouse wheel |
| Drop the held item | Q |
| Map | M |
| Player list | O (hold) |
| Room chat | T or / |
| Quick chat | backtick (QuoteLeft) |
| Pause | Escape or P |
| Gameplay HUD | F1 |
| Fullscreen | F11 |

**1–5**, the mouse wheel, and **F1** are not rows in Settings. **F11** toggles fullscreen everywhere and is not
rebindable. Hold **W** / **S** on a ladder to climb. **Space** lets go near the bottom.

## Gamepad

Names match the on-screen Xbox glyphs.

| Action | Button |
| --- | --- |
| Move / look | Left stick / right stick |
| Sprint | Left-stick click (L3) |
| Jump / crouch | A / B |
| Interact | X |
| Inventory | Y |
| Use the held item | Right trigger |
| Flashlight / taser | RB / LB |
| Hotbar | D-pad left / right |
| Drop the held item | D-pad down |
| Quick chat | D-pad up |
| Map / pause | View / Menu |

## Touch

Phones draw buttons that press the same actions. Desktop does not.

Movement is a D-pad. Double-tap an arrow and hold it to sprint. Settings can switch that to a floating stick; push
past the ring to sprint. Drag on empty screen to look.

| Button | Action |
| --- | --- |
| USE | Interact |
| JUMP | Jump |
| DUCK | Crouch |
| LIGHT | Flashlight |
| TOOL | Use the held item |
| `<` `>` | Hotbar |
| BAG | Inventory |
| MAP | Map |
| CHAT | Room chat |
| QUICK | Quick chat |
| II | Pause |

While the inventory is open, only BAG and II stay on screen.

## Hiding

Aim at a locker, a bed, or a wardrobe. The prompt is **[E] HIDE** on a keyboard, **[X] HIDE** on a pad, and
**[USE] HIDE** on a phone (whatever interact is bound to). The same control leaves: **LEAVE**. A full spot reads
**SPOT TAKEN**. Lockers and beds hold one runner. `bedroomWardrobe`, `gothicWardrobe`, and `bedroomWardrobeMansion`
hold two. A locked spot counts down as **LOCKED IN** and then accepts LEAVE.

## Flashlight

Slot 1 starts with a flashlight that is off. **F** (RB, LIGHT) selects that slot and toggles the beam. Charge drains
while the light is on, and faster while sprinting. An empty flashlight clicks and stays off. Select a battery and use
it (left click, right trigger, or TOOL) to recharge. A full lamp ignores the battery. The flashlight stays in its slot.

## Inventory

**Tab** (Y, BAG) opens the inventory. Drag an item onto another slot, including a blank one, to swap. **1–5** select
the five hotbar slots. The wheel, D-pad left/right, and the touch `<` `>` buttons cycle those five. A small, medium,
or large backpack adds 5, 10, or 15 storage slots. The hotbar stays five slots.

**Q** (D-pad down) drops the held item. One item drops on the press. A stack of two or more drops one on a tap and the
whole stack after a half-second hold. **E** or right click picks a dropped item back up with its remaining durability.
An empty hand does not drop.

## Chat

**T** or **/** opens room chat. Enter sends. Escape closes. **Tab**, while the field is focused, switches the channel
between **TEAM** and **NEARBY**. TEAM reaches the room. NEARBY reaches players within 25 m on the same level. The
channel opens on TEAM.

The backtick (D-pad up, QUICK) opens quick chat. A short press leaves the wheel up for a click. Holding it sends the
preset under the pointer on release. A sent line is spoken aloud and makes a noise. The pause menu keeps a short history.

## Saves

One automatic save per run. It writes on a new level, an activated checkpoint, a collected relay, and when you leave
from the pause menu. Pause shows the save line and the current-run statistics.

**CONTINUE** on the title screen resumes it. In the lobby, **CONTINUE RUN** does the same for a solo player or a host
who is still alone. Death clears the save. In co-op the save stays until the whole party is down.

The solo player writes the save. In an online room the host writes it. The public route does not save. A debug run
does not save. A signed-in account also keeps the save; the newer copy wins.

## Co-op rooms

**CREATE ROOM** opens a room. The dialog starts as an online room. **OFFLINE (SOLO, NO SERVER)** makes a solo room
on this device; that lasts until you leave the room. If the server cannot be reached, offline turns on by itself.
**GO ONLINE** tries the server again.

**JOIN ROOM** takes the five-character code shown next to ROOM in the lobby. Generated codes use
`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. A reserved private code may also use I, O, 0, and 1.

The lobby seats 16 players. The host picks the difficulty and presses **ENTER ROUTE**. Guests wait on
**WAITING FOR HOST**. The host can **REROLL ROUTE** before the run starts. One runner can take a given world pickup.

From pause, the host's **LEAVE ROUTE** ends the route for everyone and returns the room to staging. A guest's leave
disconnects that player, and the host's route continues. A solo leave writes the save. **CONTINUE** on the title
screen resumes it.
