"""Measured animation-root lifts which keep shipped feet on Godot floor y=0.

Values are metres in the exported glTF. The 16-sample floor audit in
``scripts/validate_body.gd`` measures them after Godot applies each model's
import scale. Rest poses already stand on y=0; only animation root tracks need
these small corrections.
"""

PLAYER_ANIMATION_GROUND_LIFTS = {
    "idle": 0.013,
    "walk": 0.061,
    "sprint": 0.092,
    "chase": 0.060,
    # The old generic 0.214 m crouch lift left the player hovering.
    "crouch": 0.069,
}

HUNTER_ANIMATION_GROUND_LIFTS = {
    "idle": 0.017,
    "walk": 0.056,
    "sprint": 0.059,
    "chase": 0.054,
    "crouch": 0.058,
}
