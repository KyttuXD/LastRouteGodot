class_name OfficeView
extends Control

## The office the player sits in: a wider-than-screen view that pans
## horizontally when the mouse approaches either edge, so you can look toward
## the left door, the desk, or the right door.
##
## Panning is adapted from the Cupcakes Framework's `office_scrolling.gd`
## (MIT, © Oplexitie — see third_party/cupcakes-framework/) — same
## accumulate-then-lerp approach and the same three tuning knobs. Changed
## from the original: it drives a Control child instead of a Sprite2D, and
## reads the viewport rect rather than `content_scale_size` off a
## Viewport-typed variable (which only worked because the root viewport
## happens to be a Window).

## Lower is smoother.
const SCROLL_SMOOTHING := 12.0
## Lower is faster.
const SCROLL_SPEED := 0.07
## Lower gives bigger scroll-trigger areas at the screen edges.
const SCROLL_SCREEN_FRACTION := 3.0

## How far the office may slide either way from centre, in pixels.
@export var scroll_clamp := 120.0

## Set false while the monitor is up — you can't look around the office with
## a tablet in your face (mirrors the framework's `can_move`).
var can_move := true

var _scroll_amount := 0.0
var _scroll_area_left := 0.0
var _scroll_area_right := 0.0

@onready var _pannable: Control = $Pannable


func _ready() -> void:
	_recalculate_scroll_areas()
	get_viewport().size_changed.connect(_recalculate_scroll_areas)


func _recalculate_scroll_areas() -> void:
	var view_width := get_viewport_rect().size.x
	var area_size := view_width / SCROLL_SCREEN_FRACTION
	_scroll_area_left = area_size
	_scroll_area_right = view_width - area_size


func _process(delta: float) -> void:
	if can_move:
		var mouse_x := get_viewport().get_mouse_position().x
		if mouse_x < _scroll_area_left:
			_scroll_amount += (_scroll_area_left - mouse_x) * SCROLL_SPEED
		elif mouse_x > _scroll_area_right:
			_scroll_amount += (_scroll_area_right - mouse_x) * SCROLL_SPEED

	_scroll_amount = clampf(_scroll_amount, -scroll_clamp, scroll_clamp)
	_pannable.position.x = lerpf(_pannable.position.x, _scroll_amount, SCROLL_SMOOTHING * delta)


## 0.0 centred, -1.0 fully left, 1.0 fully right — lets the controller show
## which door you're actually looking at.
func pan_ratio() -> float:
	return _pannable.position.x / scroll_clamp if scroll_clamp > 0.0 else 0.0
