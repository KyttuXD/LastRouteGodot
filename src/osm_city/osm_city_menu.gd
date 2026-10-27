extends RefCounted

## The City menu's REAL PLACES panel (the menu calls `open(menu)` when this file exists). Online only: without the
## server or a signed-in account it explains why and lists nothing. Left: search box, tag filter and the catalog grouped
## by region; right: the chosen place's minimap preview (real outline drawn in yellow), facts, blurb and PLAY. Playing
## downloads the place into memory (OsmCityMap), builds an OsmCityLayout and starts a solo City run (OsmCityRun).

const PANEL_NAME := "OsmRealPlaces"
const REGIONS := ["Northeast", "South", "Midwest", "West"]
const ALL_TAGS := "ALL KINDS"


static func open(menu: Control) -> void:
	var old := menu.get_node_or_null(PANEL_NAME)
	if old != null:
		old.queue_free()
	var shade := ColorRect.new()
	shade.name = PANEL_NAME
	shade.color = Color(0, 0, 0, .7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_top = 30
	panel.offset_right = -40
	panel.offset_bottom = -30
	shade.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	var title := Label.new()
	title.text = "REAL PLACES // ONLINE ONLY"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "BACK"
	close.pressed.connect(shade.queue_free)
	header.add_child(close)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	outer.add_child(body)
	# left: filters + grouped list
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.2
	body.add_child(left)
	var filters := HBoxContainer.new()
	left.add_child(filters)
	var search := LineEdit.new()
	search.name = "Search"
	search.placeholder_text = "Search city, state or place"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.clear_button_enabled = true
	filters.add_child(search)
	var tag_pick := OptionButton.new()
	tag_pick.name = "TagFilter"
	tag_pick.add_item(ALL_TAGS)
	filters.add_child(tag_pick)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "Maps"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	# right: preview + details
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	var preview := TextureRect.new()
	preview.name = "Preview"
	preview.custom_minimum_size = Vector2(240, 240)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	right.add_child(preview)
	var place := Label.new()
	place.name = "Place"
	right.add_child(place)
	var facts := Label.new()
	facts.name = "Facts"
	facts.add_theme_font_size_override("font_size", 13)
	right.add_child(facts)
	var blurb := Label.new()
	blurb.name = "Blurb"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(blurb)
	var play := Button.new()
	play.name = "PlayButton"
	play.text = "PLAY SOLO"
	play.theme_type_variation = &"PrimaryButton"
	play.disabled = true
	right.add_child(play)
	var status := Label.new()
	status.name = "Status"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.text = "Asking the map server..."
	outer.add_child(status)
	close.grab_focus()

	var state := {"maps": [], "chosen": {}}
	var map := OsmCityMap.new()
	shade.add_child(map)
	var choose := func(entry: Dictionary) -> void:
		state["chosen"] = entry
		var meta: Dictionary = entry.get("meta", {})
		var stats: Dictionary = entry.get("stats", {})
		preview.texture = _preview_texture(String(entry.get("preview", "")))
		place.text = "%s // %s, %s" % [String(entry["name"]).to_upper(), String(meta.get("city", "")), String(meta.get("state", ""))]
		facts.text = "%s  |  %.2f km²  |  %d buildings  |  %d shops  |  %s  |  %s" % [
			"real outline" if String(entry.get("shape", "")) == "boundary" else "map square",
			float(stats.get("area_km2", 0.0)), int(stats.get("buildings", 0)), int(stats.get("shops", 0)),
			_difficulty(stats), ", ".join(PackedStringArray(meta.get("tags", [])))]
		blurb.text = String(meta.get("blurb", ""))
		play.disabled = false
	var rebuild := func() -> void:
		for child in list.get_children():
			child.queue_free()
		var needle := search.text.strip_edges().to_lower()
		var tag := tag_pick.get_item_text(tag_pick.selected) if tag_pick.selected >= 0 else ALL_TAGS
		var shown := 0
		for region in REGIONS + ["Other"]:
			var rows := []
			for entry in state["maps"]:
				var meta: Dictionary = entry.get("meta", {})
				var entry_region := String(meta.get("region", "Other"))
				if (entry_region if REGIONS.has(entry_region) else "Other") != region:
					continue
				var text := "%s %s %s %s" % [entry["name"], meta.get("city", ""), meta.get("state", ""), " ".join(PackedStringArray(meta.get("tags", [])))]
				if not needle.is_empty() and text.to_lower().find(needle) < 0:
					continue
				if tag != ALL_TAGS and not (meta.get("tags", []) as Array).has(tag):
					continue
				rows.append(entry)
			if rows.is_empty():
				continue
			var heading := Label.new()
			heading.text = region.to_upper()
			heading.add_theme_font_size_override("font_size", 13)
			list.add_child(heading)
			for entry in rows:
				var meta: Dictionary = entry.get("meta", {})
				var button := Button.new()
				button.name = "Map_%s" % String(entry["id"])
				button.alignment = HORIZONTAL_ALIGNMENT_LEFT
				button.text = "%s  —  %s, %s" % [String(entry["name"]), String(meta.get("city", "")), String(meta.get("state", ""))]
				button.pressed.connect(func() -> void: choose.call(entry))
				list.add_child(button)
				shown += 1
		status.text = "" if shown > 0 else "No place matches."
	search.text_changed.connect(func(_text: String) -> void: rebuild.call())
	tag_pick.item_selected.connect(func(_index: int) -> void: rebuild.call())
	play.pressed.connect(func() -> void: _play(menu, map, [play, list], status, state["chosen"]))
	map.listed.connect(func(ok: bool, maps: Array, message: String) -> void:
		if not ok:
			status.text = message
			return
		state["maps"] = maps
		var tags := {}
		for entry in maps:
			for tag in entry.get("meta", {}).get("tags", []):
				tags[String(tag)] = true
		var names := tags.keys()
		names.sort()
		for tag in names:
			tag_pick.add_item(tag)
		rebuild.call()
		if maps.is_empty():
			status.text = "No real places are published on this server yet.")
	map.progress.connect(func(done: int, total: int) -> void:
		status.text = "Downloading %d / %d" % [done, total])
	map.fetch_list()


static func _difficulty(stats: Dictionary) -> String:
	var density := float(stats.get("buildings", 0)) / maxf(0.1, float(stats.get("area_km2", 1.0)))
	if density >= 600.0:
		return "dense: tight streets, short sightlines"
	if density >= 250.0:
		return "mixed blocks"
	return "open: long sightlines"


static func _preview_texture(base64: String) -> Texture2D:
	if base64.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(base64)) != OK:
		return null
	return ImageTexture.create_from_image(image)


static func _play(menu: Control, map: OsmCityMap, controls: Array, status: Label, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	(controls[0] as Button).disabled = true
	for button in (controls[1] as Control).get_children():
		if button is Button:
			(button as Button).disabled = true
	status.text = "Downloading %s..." % String(entry["name"])
	map.downloaded.connect(func(ok: bool, message: String) -> void:
		if not ok:
			status.text = message
			(controls[0] as Button).disabled = false
			for button in (controls[1] as Control).get_children():
				if button is Button:
					(button as Button).disabled = false
			return
		status.text = "Building the city..."
		var seed_text := "OSM-%s-%d" % [String(entry["id"]), int(entry["version"])]
		var layout := OsmCityLayout.from_map(map, seed_text)
		map.files = {}
		OsmCityRun.start(menu.get_tree(), layout), CONNECT_ONE_SHOT)
	map.download(String(entry["id"]), int(entry["version"]))
