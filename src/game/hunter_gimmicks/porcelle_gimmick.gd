class_name PorcelleGimmick
extends HunterGimmick

## Porcelle's radar-only visibility (hunterAbilities.porcelle.radarOnly). Ported
## from porcelle.js's hunterVisibleOnlyOnRadar and renderer.js, which skips
## drawing any hunter whose abilities carry radarOnly.
##
## Her AI is completely ordinary — she is Dovelle's brain in an unlit room. The
## full map remains her clearest counterplay, while HunterView3D interprets this
## flag as a very faint ghost silhouette so close encounters remain readable.


## Read by HunterView3D, which applies Porcelle's translucent presentation while
## preserving the same stealth classification used by discovery and AI systems.
func hidden_from_view() -> bool:
	return true
