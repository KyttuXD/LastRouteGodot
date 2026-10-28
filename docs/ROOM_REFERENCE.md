# Room size reference (real world, then hunter scale)

Status: PROPOSAL for KT's approval. Nothing here changes a generator yet. Written for the props lane's 1.5x hunter scale
(97+ props scaled up) so that rooms grow with the props instead of dropping them.

References only: no images or text are copied into the repo; these are the sources the numbers come from.

## How to read the numbers

* One cell = 1 m of game space. Hunter scale: real size x 1.5 in each direction (area x 2.25).
* A room rect includes its walls: an 11 x 9 rect has a 9 x 7 interior (63 cells2, which is 28 m2 of real floor at 1.5x).
* Banks (StreamedRouteGenerator._dense_linear_layout) come in three modules: **S** 11x9, **W** 21x9 (two S merged, or one
  wide room), **L** 21x21 (the great-hall merge). Maze middle banks are 8 deep (5-wide centre hall).
* Hunter and player bodies collide with a ~0.7 m margin radius (CollisionWorld.MARGIN_RADIUS), so any strip a body cannot
  enter (narrower than about 1.4 m) counts as dead floor in the biomes suite. Real aisles of 0.9 m become 1.35 m at 1.5x:
  the same rule. **Design rule: every aisle, and every strip between a bed/counter/bench and a wall, is at least 1.4 m.**

## Sources

* FGI Guidelines (hospital patient rooms): 120 sq ft (11.1 m2) clear floor area per single patient room (older AIA text:
  100 sq ft); critical-care (ICU) single room 200 sq ft (18.6 m2) with a 13 ft headwall; about 3 ft (0.9 m) clear at the
  sides and foot of a bed in state rules.
  [FGI IA resident room](https://fgiguidelines.org/wp-content/uploads/2019/10/FGI-IA-resident-room_191017.pdf),
  [Maryland exhibit](https://mhcc.maryland.gov/sites/default/files/con/exhibit_CQ3.pdf),
  [MCD critical care revision](https://mcdmag.com/?p=19638).
* NIH laboratory module: about 11 ft (3.35 m) wide, 33 ft (10 m) long, 5 ft (1.5 m) aisle between 30 in benches / 36 in
  equipment; a 5 ft aisle is the turning-radius minimum.
  [NIH lab module bulletin 2013](https://orf.od.nih.gov/TechnicalResources/Documents/Technical%20Bulletins/13TB/Lab%20Module%20Design%20Considerations%20December%202013%20Bulletin_508.pdf),
  [NIH News to Use 2010](https://orf.od.nih.gov/TechnicalResources/Documents/News%20to%20Use%20PDF%20Files/2010%20NTU/April%202010%20News%20to%20Use_508.pdf).
* Restaurants: 15 to 18 sq ft (1.4 to 1.7 m2) per seat; main aisles 48 to 60 in, secondary 36 to 44 in (ADA 36 in).
  [Oak Street seating guide](https://www.oakstreetmfg.com/the-ultimate-restaurant-seating-layout-guide-with-real-numbers/),
  [Restaurant Furniture capacity guide](https://www.restaurant-furniture.com/resources/guides/restaurant-seating-capacity-guide).
* Dwellings (IRC): habitable room at least 70 sq ft (6.5 m2), 7 ft minimum dimension; one room of 120 sq ft.
  [IRC 2021 minimum room size](https://www.jaspector.com/codes/irc-2021/ch03-building-planning/minimum-bedroom-room-size/).
* Offices: about 100 sq ft per person planning figure; private office 10 x 10 to 10 x 12 ft; 8 x 8 ft cubicles
  (120 to 150 sq ft with circulation); small meeting room 100 sq ft, 8 people 150 to 220 sq ft.
  [Liberty University space standards](https://www.liberty.edu/facilities-management/wp-content/uploads/sites/138/2021/03/DR_Space-Allocation-Standards.pdf),
  [Workbox per-person guide](https://www.workboxcompany.com/workspace-guides/right-sizing-how-many-square-feet-per-person-for-office-space/).
* Greenhouses: primary aisles 1.2 to 1.8 m, secondary 0.6 to 0.9 m, 1.2 m where wheelchairs work; benches about 0.75 m
  deep, 66 to 75 % of floor usable on fixed benches.
  [Greenhouse planning notes (UPLB)](https://amtec.uplb.edu.ph/wp-content/uploads/2019/07/415.pdf).
* Not yet researched with a citable source: mall inline-unit sizes, morgue, imaging suites beyond FGI generalities, the
  mansion rooms. Those rows below are marked "estimate".

## Proposal

Real size is a typical single room of that kind; "x1.5" is the interior it needs at hunter scale; module is the bank
module that holds it with 1.4 m aisles. "Now" is the RoomSizeProfiles preferred size.

| Room type | Now | Real reference | x1.5 interior | Proposed | Source |
|---|---|---|---|---|---|
| icu (2 beds) | S 11x9 | 2 x 18.6 m2, headwall 4 m | about 84 cells2 + kit | **W 21x9** (4 beds or 2 + station) | FGI critical care |
| ward | W 21x9 (to L) | 100 sq ft per bed, 0.9 m sides | 3 to 4 beds per 19x7 | keep W; L for the long ward | FGI |
| operating_theatre | W 21x9 | 40 to 56 m2 (estimate) | 90 to 126 | keep W (19x7 = 133) | estimate |
| exam / infirmary / supply / pharmacy | S 11x9 | 9 to 11 m2 | 22 to 25 | keep S | FGI 120 sq ft |
| nurses_station | S | counter 5 to 6 m long + aisles | about 8 x 5 | **W** | estimate |
| imaging | S | 23 m2 + shielding (estimate) | 52 | **W** (machine plus control) | estimate |
| morgue | S | 25 to 30 m2 (estimate) | 56 to 68 | keep S, 2 tables | estimate |
| chem_lab / bio_lab | S | one 3.35 x 10 m module, 1.5 m aisle | 5.0 x 15 | **W 21x9** (19x7 holds one module) | NIH lab module |
| clean_room / server_hall / containment | W | module-based | 5 x 15 | keep W (L for containment) | NIH |
| control_room / lab_office | S | 12 to 14 m2 / desk bays | 28 to 32 | control_room **W**, lab_office S | Liberty / Workbox |
| office_reception / cubicle_room / office_job / private_office | 7x7 in a 17x17 suite | 8x8 ft cubicles 2.4 m, 1.5 m aisle, 10x12 ft private | cubicle row 4 x 3.7 + 2.3 aisle | **9x9 rooms in a 21x21 suite** | Liberty / Workbox |
| bedroom / guest_room | S | 3.4 x 3.7 m (IRC 70 to 120 sq ft) | 5.1 x 5.5 | keep S | IRC |
| bathroom (house/hotel/public) | S | 5 m2, 1.5 m turning circle | 3.6 x 3.2 | keep S (9x7 is roomy) | IRC / ADA |
| kitchen (home) | S to 13x13 | 3 x 4 m | 4.5 x 6 | keep S | IRC |
| kitchen (commercial) / restaurant back | S | 5 x 6 m (estimate) | 7.5 x 9 | **W** | estimate |
| restaurant_dining | W / L | 1.4 to 1.7 m2 per seat, aisles 0.9 to 1.3 m | 3.1 to 3.8 cells2 per seat | W only in 9-deep rows (not the maze's 8-deep banks); L for 24+ seats | restaurant guides |
| mall shops | W 20x9 | inline units 100+ m2 (estimate) | 56 m2 at 1.5x now | keep 20x9 (boutique scale); anchors (cinema, food court) L | estimate |
| glasshouse / palm_house | W | aisles 1.2 to 1.8 m, bench 0.75 m | aisle 1.8 to 2.7 | **L 21x21** for the main glasshouse | greenhouse notes |
| potting_shed / irrigation / cactus | S | small service rooms | n/a | keep S | estimate |
| drawing_room / dining_room (mansion) | W / L | 5 x 7 m, 4 x 5.5 m (estimate) | 7.5 x 10.5 | keep | estimate |
| prison_cell | S | 6 m2 | 3 x 4.5 | keep S (roomy by design) | estimate |

Net change: ICU, nurses station, imaging, chem/bio lab, control room and commercial kitchen move S to W; the main
glasshouse moves W to L; office suite rooms grow 7x7 to 9x9 in a 21x21 suite. Everything else already fits at 1.5x because
an S room's 63 cells2 interior is 28 m2 of real floor, more than any single-function dwelling room needs. The rooms that
fail at hunter scale are the ones with rows of big furniture (beds, counters, benches) where the 1.4 m aisle rule bites,
which is what the ICU and night_diner fixes already showed.

## Constraints kept

Chunk size 45, the three halls at 10 / 22 / 34 (maze: five-wide centre cross), doorways in the middle of a room's wall,
the great-hall merge, hall seams, hunter_nav and stream_perf are untouched; only which module a room type takes changes,
plus the office suite footprint.
