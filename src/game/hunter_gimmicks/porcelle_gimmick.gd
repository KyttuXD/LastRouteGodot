class_name PorcelleGimmick
extends HunterGimmick

## Porcelle keeps her full-map tracking mechanic, but no longer suppresses her
## in-world model entirely. Players can still verify her route on the fullscreen
## facility map without the presentation collapsing into a pure ghost-only tell.
##
## Her AI is completely ordinary — she is Dovelle's brain in an unlit room. The
## full map remains her clearest counterplay.


## Porcelle now renders like an ordinary hunter; the map exposure is the gimmick.
func hidden_from_view() -> bool:
	return false
