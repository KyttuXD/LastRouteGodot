extends RefCounted

## Opt-in time-sliced route startup (StreamedFacilityView3D.sliced_startup, RouteStartGate).
##
## The sliced opening must end in the SAME world as the synchronous one it replaces: the same chunks loaded, built in the
## same order, with the same nodes / transforms / meshes / colliders / pickups (a pickup claimed before its chunk builds
## stays absent), however the opening ends -- left to finish by itself, completed by finish_startup() (the gate's stall
## or cap), after the runner crossed a chunk border, changed storey, or was teleported while it was still slicing.
## And it must do so in short frames: the wall time of every frame after begin() is measured against a FIXED bound.
##
## Timing numbers here are the headless PC's. Nothing in this suite says anything about the 2015 Air or a windowed run
## (needs windowed verification: dev/look/stream_bench.gd with and without LR_SLICED_STARTUP=1).
##
## Named exceptions to the frame bound, because they are indivisible and run inside one build step: the first-use tune
## renders (music box ~334 ms, carousel ~600 ms, glyra hum ~219 ms on the PC). The COLD pass below leaves the warm-up
## out on purpose and prints those frames; only the warm pass is asserted.

const StreamPerf := preload("res://tests/validate_stream_perf.gd")
const SEED := "SLICED-START"
## The bound for one frame after begin(): the 30 ms slice plus a fixed allowance for the largest indivisible build step
## (one GridMap/surface attach, one prop spawn; a few ms to ~12 ms headless) and for a busy test machine.
const FRAME_BOUND_MS := 30.0 + 60.0
const BLIPS_ALLOWED := 2
const MAX_FRAMES := 4000
var _unnumbered := RegEx.create_from_string("@(\\w+)@\\d+")

var _failures := 0
var _busy := -1
var _recorders := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## Timing misses count only on a quiet machine (the same rule as stream_perf).
func _expect_timing(condition: bool, message: String) -> void:
	if condition:
		return
	if _busy < 0:
		_busy = StreamPerf.other_godot_processes()
	if _busy > 0:
		print("  BUSY  %s -- machine busy (%d other Godot runs), retry on a quiet machine" % [message, _busy])
		return
	_expect(false, message)


func run(host: Node) -> int:
	Settings.set_admin_preferences(Settings.ADMIN_PREFERENCE_DEFAULTS)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_defaults_and_flag()
	var spawn := StreamedRouteGenerator.new(SEED).spawn_cell()
	var start := Vector3(spawn.x + .5, .04, spawn.y + .5)
	var size := float(StreamedRouteGenerator.CHUNK_SIZE)

	# --- COLD pass: nothing warmed, so first-use renders land in the frames (printed, not asserted) -------------------
	var cold := await _open(host, true, start, {})
	print("  sliced_startup  COLD  %s" % _timing_line(cold))
	await _free(host, cold)

	# --- warm-up: one throwaway synchronous view warms every process-wide cache for both measured views ------------
	var warm := await _open(host, false, start, {})
	var claim_id := _pickup_outside_centre(warm)
	_expect(not claim_id.is_empty() and warm["view"]._pickup_nodes.has(claim_id),
		"the warm-up window has no pickup outside the runner's chunk to pre-claim")
	var claims := {claim_id: true}
	await _free(host, warm)

	# --- 1. sync reference A and sliced B, the same seed, position and pre-claimed pickup -----------------------------
	var a := await _open(host, false, start, claims)
	var b := await _open(host, true, start, claims)
	var va: StreamedFacilityView3D = a["view"]
	var vb: StreamedFacilityView3D = b["view"]
	_expect(a["start_sync"] == 8 and not a["slicing_after_begin"],
		"the synchronous opening no longer queues eight startup chunks (%d)" % a["start_sync"])
	_expect(b["start_sync"] == 0 and b["slicing_after_begin"],
		"the sliced opening still fills the synchronous startup list (%d)" % b["start_sync"])
	_expect(a["loaded_after_begin"] == 1 and b["loaded_after_begin"] == 1,
		"begin() built %d / %d chunks, not just the runner's" % [a["loaded_after_begin"], b["loaded_after_begin"]])
	_expect(va.loaded_horizontal_coords().size() == 9 and vb.loaded_horizontal_coords().size() == 9,
		"the opening window is not the runner's 3x3 (%d sync, %d sliced)" % [
			va.loaded_horizontal_coords().size(), vb.loaded_horizontal_coords().size()])
	_expect(va.startup_window_complete() and vb.startup_window_complete(), "startup_window_complete() is false once settled")
	_expect(not vb.is_startup_slicing(), "the sliced opening never ended its slicing after the queue emptied")
	_expect(b["frames"].size() > 2, "the sliced opening finished in %d frames: it is not spread over frames" % b["frames"].size())
	_expect(_same_keys(va._loaded, vb._loaded), "the loaded chunk sets differ between the sync and the sliced opening")
	# ORDER: the chunks of the opening finish in the same order
	var level := va.current_level()
	var order_a: Array = a["order"].slice(0, 9)
	var order_b: Array = b["order"].slice(0, 9)
	_expect(order_a == order_b, "build order differs: sync %s, sliced %s" % [order_a, order_b])
	var same_storey := true
	for coord in order_b:
		same_storey = same_storey and (coord as Vector3i).y == level
	_expect(order_b.size() == 9 and same_storey, "the first nine builds of the sliced opening are not the runner's storey (%s)" % [order_b])
	# the claimed pickup is absent on both paths, present in the unclaimed warm-up (above)
	_expect(not va._pickup_nodes.has(claim_id) and not vb._pickup_nodes.has(claim_id),
		"a pickup claimed before its chunk built was spawned anyway")
	# progress is monotone and ends complete
	_expect(_monotone(b["progress"]), "the loading bar went backwards while slicing")
	_expect(vb.build_progress() >= 0.999, "build_progress() is %.2f with the window complete" % vb.build_progress())
	var sig_a := _signatures(va)
	var sig_b := _signatures(vb)
	_same_signatures(sig_a, sig_b, "sliced opening")
	# the reference is the headline: the longest frame of each opening
	print("  sliced_startup  SYNC    %s" % _timing_line(a))
	print("  sliced_startup  SLICED  %s" % _timing_line(b))
	var over := 0
	for ms in b["frames"]:
		if float(ms) > FRAME_BOUND_MS:
			over += 1
	_expect_timing(over <= BLIPS_ALLOWED, "%d sliced frames after begin() exceed %.0f ms (30 ms slice + 60 ms for the largest indivisible step; %d blips allowed), worst %.0f ms in %s" % [
		over, FRAME_BOUND_MS, BLIPS_ALLOWED, _max_of(b["frames"]), b["worst_label"]])
	_expect_timing(_max_of(b["frames"]) < _max_of(a["frames"]),
		"the longest sliced frame (%.0f ms) is not shorter than the longest synchronous one (%.0f ms)" % [
			_max_of(b["frames"]), _max_of(a["frames"])])
	await _free(host, b)

	# --- 2. FORCED FINISH: the gate gave up two frames in ------------------------------------------------------------
	var c := await _open(host, true, start, claims, 2, {"finish": true})
	var vc: StreamedFacilityView3D = c["view"]
	_expect(c["forced_coords"] == 9 and c["forced_complete"] and not c["forced_slicing"],
		"finish_startup() left %d of 9 same-storey chunks (complete %s, slicing %s)" % [
			c["forced_coords"], c["forced_complete"], c["forced_slicing"]])
	_expect(float(c["forced_progress"]) >= 0.999, "build_progress() was %.2f after finish_startup()" % float(c["forced_progress"]))
	_expect(c["emits_during"] >= 1 and c["emit_loaded_last"] == 9,
		"chunk_changed did not fire with the whole window loaded after finish_startup() (%d emits, last saw %d chunks)" % [
			c["emits_during"], c["emit_loaded_last"]])
	_expect(c["forced_ms"] > 0.0, "finish_startup() reported no work")
	_same_signatures(sig_a, _signatures(vc), "forced finish")
	# calling it again, or on a view that was never sliced, does nothing
	var emitted_before: int = c["emit_count"]
	vc.finish_startup()
	_expect(c["emit_count"] == emitted_before, "a second finish_startup() emitted chunk_changed again")
	await _free(host, c)
	await _free(host, a)

	# --- 3. BORDER CROSSING: the runner steps one chunk east one frame after begin() -----------------------------------
	var step := Vector3(size, 0, 0)
	var d := await _open(host, true, start, claims, 1, {"move": step})
	var e := await _open(host, false, start, claims, 1, {"move": step})
	_expect(_same_keys(d["view"]._loaded, e["view"]._loaded), "after a border crossing the sliced and sync opening loaded different chunks")
	_expect(d["view"].loaded_horizontal_coords().size() == 9 and d["view"].startup_window_complete(),
		"after a border crossing (natural completion) the new window is not complete")
	_same_signatures(_signatures(e["view"]), _signatures(d["view"]), "border crossing")
	await _free(host, d)
	await _free(host, e)
	var f := await _open(host, true, start, claims, 1, {"move": step, "finish": true})
	_expect(f["forced_complete"] and f["forced_coords"] == 9 and not f["forced_slicing"],
		"finish_startup() after a border crossing left the new window incomplete (%d of 9)" % f["forced_coords"])
	await _free(host, f)

	# --- 4. STOREY CHANGE and TELEPORT while still slicing -----------------------------------------------------------
	var down := Vector3(0, float(SewerRouteGenerator.LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT, 0)
	var g := await _open(host, true, start, claims, 1, {"move": down})
	var h := await _open(host, false, start, claims, 1, {"move": down})
	_expect(g["view"].current_level() == SewerRouteGenerator.LEVEL and g["view"].loaded_horizontal_coords().size() == 9,
		"after a storey change mid-slice the new storey's window is not the 3x3 (%d)" % g["view"].loaded_horizontal_coords().size())
	_expect(_same_keys(g["view"]._loaded, h["view"]._loaded), "after a storey change the sliced and sync opening loaded different chunks")
	_same_signatures(_signatures(h["view"]), _signatures(g["view"]), "storey change")
	await _free(host, g)
	await _free(host, h)
	var i := await _open(host, true, start, claims, 1, {"move": down, "finish": true})
	_expect(i["forced_complete"] and i["forced_coords"] == 9,
		"finish_startup() after a storey change left the new storey incomplete (%d of 9)" % i["forced_coords"])
	await _free(host, i)
	var far := Vector3(size * 6, 0, -size * 5)
	var j := await _open(host, true, start, claims, 1, {"move": far, "finish": true})
	_expect(j["forced_complete"] and j["forced_coords"] == 9 and not j["forced_slicing"],
		"finish_startup() after a teleport mid-slice left the new window incomplete (%d of 9)" % j["forced_coords"])
	await _free(host, j)

	# --- 5. finish_startup() does not rebuild a chunk the active build already holds ---------------------------------
	var k := await _open(host, true, start, claims, 3, {"finish": true})
	var rebuilt := 0
	for coord in k["view"].build_counts:
		if int(k["view"].build_counts[coord]) > 1:
			rebuilt += 1
	_expect(rebuilt == 0, "finish_startup() built %d chunks twice (an active build was not adopted)" % rebuilt)
	await _free(host, k)

	if _failures == 0:
		print("sliced_startup OK")
	return _failures


## The defaults that keep every other path synchronous.
func _defaults_and_flag() -> void:
	_expect(not StreamedFacilityView3D.new().sliced_startup, "a bare view slices its startup by default")
	_expect(not RouteStartGate.SLICED_ON_ENTRY, "the sliced opening is on by default (it must stay opt-in until measured)")
	var use := RouteStartGate.use_sliced_startup
	_expect(not use.call(true, false, false, ""), "a plain loading-screen entry slices without the flag")
	_expect(not use.call(false, false, false, ""), "a scene built directly slices without the flag")
	_expect(use.call(true, false, false, "1") and use.call(false, false, false, "1"), "LR_SLICED_STARTUP=1 does not turn it on")
	_expect(not use.call(true, true, false, "1"), "a dedicated host slices its startup")
	_expect(not use.call(true, false, true, "1"), "a guest waiting for the host snapshot slices its startup")
	_expect(not use.call(true, false, false, "0"), "LR_SLICED_STARTUP=0 does not turn it off")


## Builds a view (sliced or not) around the player at `at`, with `claims` already in its world state, and runs it frame by
## frame. `settle_after` is the number of frames to wait before the optional `plan`: "move" (a displacement of the
## runner) and "finish" (call finish_startup()). Without a plan it runs until the stream is idle.
func _open(host: Node, sliced: bool, at: Vector3, claims: Dictionary, settle_after := 0, plan := {}) -> Dictionary:
	var view := StreamedFacilityView3D.new()
	view.sliced_startup = sliced
	host.add_child(view)
	var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.set_physics_process(false)
	player.global_position = at
	var state := StreamedWorldState.new()
	for id in claims:
		state.claim_pickup(String(id))
	var out := {"view": view, "player": player, "frames": [], "progress": [], "order": [], "worst_label": "",
		"emit_count": 0, "emits_during": 0, "emit_loaded_last": -1}
	view.chunk_changed.connect(func(_coord: Vector3i, _data: Dictionary) -> void:
		out["emit_count"] += 1
		out["emit_loaded_last"] = view.loaded_horizontal_coords().size())
	var t0 := Time.get_ticks_usec()
	view.begin(SEED, player, state)
	out["begin_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	out["start_sync"] = view._startup_sync.size()
	out["slicing_after_begin"] = view._startup_slicing
	out["loaded_after_begin"] = view.loaded_chunk_count()
	var seen := 0
	var last := Time.get_ticks_usec()
	var worst := 0.0
	var frame := 0
	while frame < MAX_FRAMES:
		seen = _collect_order(view, out["order"], seen)
		if plan.is_empty() and frame > 0 and not view.is_streaming() and not view.is_startup_slicing():
			break
		if not plan.is_empty() and frame >= settle_after:
			if plan.has("move") and not out.has("moved"):
				out["moved"] = true   # the stream notices the new position on the next frame
				player.global_position += plan["move"]
				if not plan.has("finish"):
					plan = {}   # a move only: run it to idle from here
			elif plan.has("finish"):
				var emits_before: int = out["emit_count"]
				var tf := Time.get_ticks_usec()
				view.finish_startup()
				out["forced_ms"] = (Time.get_ticks_usec() - tf) / 1000.0
				out["emits_during"] = int(out["emit_count"]) - emits_before
				out["forced_coords"] = view.loaded_horizontal_coords().size()
				out["forced_complete"] = view.startup_window_complete()
				out["forced_slicing"] = view.is_startup_slicing()
				out["forced_progress"] = view.build_progress()
				seen = _collect_order(view, out["order"], seen)
				break
		await host.get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		out["frames"].append(ms)
		out["progress"].append(view.build_progress())
		var cost: Array = view.take_frame_stream_cost()
		if ms > worst:
			worst = ms
			out["worst_label"] = "%s (%.1f ms counted)" % [cost[1], cost[0]]
		frame += 1
	_expect(frame < MAX_FRAMES, "the opening never settled within %d frames" % MAX_FRAMES)
	if plan.has("finish"):
		# let the linked storeys finish on the ordinary budget so the whole loaded set is comparable
		for _n in MAX_FRAMES:
			if not view.is_streaming():
				break
			await host.get_tree().process_frame
	return out


## Appends the builds that finished since the last look (view.recent_builds keeps the last 32).
func _collect_order(view: StreamedFacilityView3D, order: Array, seen: int) -> int:
	var fresh := view.chunk_builds - seen
	if fresh > 0:
		var tail: Array = view.recent_builds.slice(maxi(0, view.recent_builds.size() - fresh))
		order.append_array(tail)
	return view.chunk_builds


func _free(host: Node, opened: Dictionary) -> void:
	var view := opened["view"] as Node
	var player := opened["player"] as Node
	if is_instance_valid(view):
		view.queue_free()
	if is_instance_valid(player):
		player.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame


func _pickup_outside_centre(opened: Dictionary) -> String:
	var view: StreamedFacilityView3D = opened["view"]
	var centre := view.current_chunk_coord()
	for coord_value in view._loaded.keys():
		var coord: Vector3i = coord_value
		if coord == centre or coord.y != centre.y:
			continue
		for pickup in view.generator.chunk(coord).get("pickups", []):
			var id := String((pickup as Dictionary).get("id", ""))
			if not id.is_empty() and view._pickup_nodes.has(id):
				return id
	return ""


func _same_keys(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key):
			return false
	return true


func _monotone(values: Array) -> bool:
	for index in range(1, values.size()):
		if float(values[index]) < float(values[index - 1]) - 0.000001:
			return false
	return true


func _max_of(values: Array) -> float:
	var out := 0.0
	for value in values:
		out = maxf(out, float(value))
	return out


func _p95(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))])


func _timing_line(opened: Dictionary) -> String:
	return "begin %.0f ms, then %d frames, max %.0f ms, p95 %.0f ms (longest step: %s)" % [
		float(opened["begin_ms"]), opened["frames"].size(), _max_of(opened["frames"]), _p95(opened["frames"]),
		opened["worst_label"]]


# --- signatures ---------------------------------------------------------------------------------------------------------

func _signatures(view: StreamedFacilityView3D) -> Dictionary:
	var out := {}
	var animated := {}
	for node in view._animated_activity_props:
		if node != null and is_instance_valid(node):
			animated[node.get_instance_id()] = true
	for coord_value in view._loaded.keys():
		var coord: Vector3i = coord_value
		var root := view._loaded[coord] as Node
		var lines: Array[String] = []
		_describe(root, root, lines, animated)
		out[coord] = lines
	return out


func _same_signatures(want: Dictionary, got: Dictionary, label: String) -> void:
	_expect(_same_keys(want, got), "%s: the signed chunk sets differ" % label)
	var bad := 0
	for key in want:
		if not got.has(key):
			continue
		var a: Array = want[key]
		var b: Array = got[key]
		if a == b:
			continue
		bad += 1
		if bad <= 3:
			var at := 0
			while at < mini(a.size(), b.size()) and a[at] == b[at]:
				at += 1
			print("  FAIL  %s: %s differs at node %d of %d/%d\n          sync   : %s\n          sliced : %s" % [
				label, key, at, a.size(), b.size(), a[at] if at < a.size() else "(end)", b[at] if at < b.size() else "(end)"])
	_expect(bad == 0, "%s: %d chunks differ node for node" % [label, bad])


static func _q(value: float) -> int:
	return int(roundf(value * 1000.0))


static func _xf(t: Transform3D) -> String:
	var b := t.basis
	return "%d,%d,%d|%d,%d,%d|%d,%d,%d|%d,%d,%d" % [
		_q(b.x.x), _q(b.x.y), _q(b.x.z), _q(b.y.x), _q(b.y.y), _q(b.y.z), _q(b.z.x), _q(b.z.y), _q(b.z.z),
		_q(t.origin.x), _q(t.origin.y), _q(t.origin.z)]


static func _material(material: Material) -> String:
	if material == null:
		return "-"
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		return "%s/%s/%s/%s/%s" % [base.get_class(), base.albedo_color.to_html(), base.albedo_texture.resource_path \
			if base.albedo_texture != null else "-", base.emission_enabled, base.transparency]
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		return "shader:%s" % (shader.resource_path if shader != null else "-")
	return "%s:%s" % [material.get_class(), material.resource_path]


static func _shape(shape: Shape3D) -> String:
	if shape == null:
		return "-"
	if shape is BoxShape3D:
		return "box %s" % (shape as BoxShape3D).size
	if shape is SphereShape3D:
		return "sphere %d" % _q((shape as SphereShape3D).radius)
	if shape is CapsuleShape3D:
		return "capsule %d %d" % [_q((shape as CapsuleShape3D).radius), _q((shape as CapsuleShape3D).height)]
	if shape is CylinderShape3D:
		return "cylinder %d %d" % [_q((shape as CylinderShape3D).radius), _q((shape as CylinderShape3D).height)]
	if shape is ConvexPolygonShape3D:
		return "convex %d" % (shape as ConvexPolygonShape3D).points.size()
	if shape is ConcavePolygonShape3D:
		return "concave %d" % (shape as ConcavePolygonShape3D).get_faces().size()
	return shape.get_class()


func _describe(node: Node, root: Node, lines: Array[String], animated: Dictionary) -> void:
	# Godot numbers unnamed nodes from a process-wide counter (@Node3D@6335): compare the names without the number
	var line := "%s|%s" % [_unnumbered.sub(String(root.get_path_to(node)), "@$1", true), node.get_class()]
	if node is Node3D and not animated.has(node.get_instance_id()):
		line += "|" + _xf((node as Node3D).transform)
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		line += "|vis%s|%s" % [instance.visible, instance.cast_shadow]
		if instance.mesh != null:
			line += "|%s %d" % [instance.mesh.get_class(), instance.mesh.get_surface_count()]
			for surface in instance.mesh.get_surface_count():
				var material := instance.get_surface_override_material(surface)
				if material == null:
					material = instance.mesh.surface_get_material(surface)
				var verts := (instance.mesh as ArrayMesh).surface_get_array_len(surface) if instance.mesh is ArrayMesh else 0
				line += "|%d:%s" % [verts, _material(material)]
	elif node is CollisionShape3D:
		line += "|" + _shape((node as CollisionShape3D).shape) + "|dis%s" % (node as CollisionShape3D).disabled
	elif node is MultiMeshInstance3D:
		var multi := (node as MultiMeshInstance3D).multimesh
		if multi != null:
			var sum := 0
			for index in multi.instance_count:
				sum += _xf(multi.get_instance_transform(index)).hash()
			line += "|multi %d %d" % [multi.instance_count, sum]
	elif node is GridMap:
		var grid := node as GridMap
		var sum := 0
		var cells := grid.get_used_cells()
		for cell in cells:
			sum += hash([cell, grid.get_cell_item(cell), grid.get_cell_item_orientation(cell)])
		line += "|grid %d %d" % [cells.size(), sum]
	elif node is Light3D:
		var light := node as Light3D
		line += "|light %s" % light.light_color.to_html()   # the energy twinkles with time (fairy lights): not build state
	elif node is Label3D:
		line += "|" + (node as Label3D).text
	if node.has_meta("streamed_entity_id"):
		line += "|entity " + String(node.get_meta("streamed_entity_id"))   # pickups, hunters, ... of the loaded chunk
	lines.append(line)
	for child in node.get_children():
		_describe(child, root, lines, animated)
