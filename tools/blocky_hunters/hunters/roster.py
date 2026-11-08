"""The A-Z roster in order (letter -> HunterRoster id). Each hunter without her own module in hunters/
is built generically from skins/<id>_source.png: vanilla Alex cubes + the skin's second layer + the shared
expression cells and clips. Hunters that need extras (wings, ponytail) have their own module."""
IDS = "aki briselle ceryth dovelle elise ferryn glyra haelith ilyra javelle kathy loxelle mavrine nyxie opalie porcelle quenelle ravelle solyth thessine umbriel verrine wynelle xivvy ysolde zellia".split()

# Last Route 2D (HUNTER_CANON_RENAMES in games/last-route): four hunters were renamed to their lore names and the
# internal ids now match (game/config/hunter_id_aliases.gd maps the old ids for old saves).
DISPLAY = {"elise": "Elise", "javelle": "Javelle", "quenelle": "Quenelle", "zellia": "Zellia"}
