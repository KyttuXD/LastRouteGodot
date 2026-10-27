# Ravelle's traps

Audit of what existed: Ravelle (the 2D tripwire trapper) already laid two invisible wires across full 3-wide halls at
pinch points (doorway-shaped cells), refreshed every 30 s unless one fired; tripping one locked her into a chase and
permanently raised her speed. Nothing stunned the runner, nothing was visible, there was no counter, and guests had no trap
state.

Now:

* **Stun**: walking into a live wire stuns that runner for `RAVELLE_TRAP_STUN` (1.6 s, the existing stun: movement
  locked, same recovery as Ilyra's pounce), sent only to the runner who tripped it.
* **Bells**: the trip rings out (`facility_alert`): hunters near the spot come to investigate and Ravelle is locked on
  as before (chase + permanent speed bonus).
* **Tell**: every live wire is drawn on every peer as a thin, faintly shimmering line across the hall at shin height with
  a little bell at each end: easy to miss when running, easy to spot in a torch beam. Spent and cut wires disappear.
* **Counter**: hold INTERACT within `RAVELLE_CUT_REACH` (1.3 m) for `RAVELLE_CUT_SECONDS` (1.2 s) to cut a wire. It is
  noisy: hunters within 14 m come to look. Crouching or stepping over a full-hall wire does not work.
* **Fair**: at most `RAVELLE_TRIPWIRE_COUNT` (2) live wires per Ravelle; a wire is never a collider, so a hall is never
  blocked (a stun is the worst case).
* **Multiplayer**: host-authoritative. The trap state rides in her replicated gimmick state, so guests, spectators and
  late joiners see the same wires; a guest's cut goes to the host (`ravelle_disarm`).
* **Admin**: SHOW TRAPS (brighter, thicker wires), SPAWN RAVELLE TRAP HERE.
* **Validator** `ravelle_traps`: budget, hall-wide span on the floor, trip -> stun + alert, spent once, cut, state
  round-trip.

Not done yet: a pressure-plate variant and a coop_test scenario for the replicated cut.
