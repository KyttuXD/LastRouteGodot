class_name PorcelleGimmick
extends HunterGimmick

## Porcelle's radar-only visibility (hunterAbilities.porcelle.radarOnly). Ported
## from porcelle.js's hunterVisibleOnlyOnRadar and renderer.js, which skips
## drawing any hunter whose abilities carry radarOnly.
##
## Her AI is completely ordinary — she is Dovelle's brain in an unlit room. The
## whole hunter is the visibility rule, and the whole counterplay is the map:
## she is drawn there like everyone else, so tracking her means holding the map
## open, which means not looking at the room she is walking through. That trade
## is the design. It is also why she could not be ported until the map was a
## real map instead of a rectangle with a caption on it — an invisible hunter
## with no way to find her is not a hard hunter, she is a broken one.


## Read by HunterView3D, which hides the model rather than the node: she still
## moves, still perceives, still grabs you. You just cannot see her coming.
func hidden_from_view() -> bool:
	return true
