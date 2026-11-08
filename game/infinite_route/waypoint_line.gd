extends RefCounted

## The floor line to the waypoint (Settings.waypoint_guidance == "line"): one continuous flat ribbon along the whole route, as the
## original waypoint design drew it (75e921ca^ src/infinite_route_test.gd, _update_waypoint_ground_trail). Pure helpers with no scene
## access, so tests/validate_waypoints.gd can check them headlessly. Used by infinite_route_test.gd; see docs/WAYPOINTS.md.
## Preloaded (no class_name) so no global class cache entry is needed.

## Half the ribbon width in metres (the original .075: a 15 cm strip).
const HALF_WIDTH := .075
## Lift above the floor in metres (the original .035), so the strip clears floor decals and rugs.
const LIFT := .035
## When no route over discovered floor exists, draw one straight segment from the player to the waypoint. It ignores walls, so it
## shows only the direction. false draws nothing in that case instead.
const STRAIGHT_FALLBACK := true


## The route points (cell centres) for a waypoint. `discovered` is the discovered-floor cell path (Array of Vector2i, possibly
## empty: the original discovery rule, so the line never reveals unexplored floor). When it ends short of the waypoint, a straight
## segment runs on from its last cell to the waypoint. Without a discovered route, a straight segment from the player when
## STRAIGHT_FALLBACK, otherwise nothing.
static func choose_route(discovered: Array, from_cell: Vector2i, to_cell: Vector2i) -> Array:
	var points := []
	if discovered.size() >= 2:
		for cell_value in discovered:
			var cell: Vector2i = cell_value
			points.append(Vector2(cell) + Vector2(.5, .5))
		# a discovered route that stops short (the waypoint is on unexplored floor) runs straight on from its last cell
		var last: Vector2i = discovered.back()
		if last != to_cell and STRAIGHT_FALLBACK:
			points.append(Vector2(to_cell) + Vector2(.5, .5))
		return points
	if not STRAIGHT_FALLBACK or from_cell == to_cell:
		return points
	points.append(Vector2(from_cell) + Vector2(.5, .5))
	points.append(Vector2(to_cell) + Vector2(.5, .5))
	return points


## The ribbon at `height` (the floor level) over `route` (Vector2 points in x/z), or null when no segment has any length.
static func build_mesh(route: Array, height: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 0
	for index in route.size() - 1:
		var from_2d: Vector2 = route[index]
		var to_2d: Vector2 = route[index + 1]
		var direction := to_2d - from_2d
		if direction.length_squared() <= .0001:
			continue
		var side := Vector2(-direction.y, direction.x).normalized() * HALF_WIDTH
		for point in [from_2d - side, to_2d - side, to_2d + side,
				from_2d - side, to_2d + side, from_2d + side]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(point.x, height, point.y))
		segments += 1
	if segments == 0:
		return null
	return surface.commit()
