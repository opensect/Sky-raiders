class_name SkyfallHelpers
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


func skyfall_route_of(x: float) -> int:
	if x < 1200.0:
		return 0
	if x <= 2400.0:
		return 1
	return 2


func _sf_level_of(y: float) -> int:
	# World y -> level 1-6 (each level is 1800 px tall; y grows
	# downward, so level 1 is the bottom). Used by pings and the
	# height bar labels.
	return clampi(6 - int(y / 1800.0), 1, 6)


func _sf_validate_powerup_target(activator: Node2D, target: Node2D, kind: int = 0) -> bool:
	return g.skyfall_powerups._sf_validate_powerup_target(activator, target, kind)


func show_thunder_strike_fx(pos: Vector2) -> void:
	g.skyfall_dynamics.show_thunder_strike_fx(pos)

