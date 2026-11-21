class_name NetTestSteps
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)


func _init(owner) -> void:
	g = owner


func _nettest_build_steps() -> void:
	# QA-141: the steps live on the NetTest module (QA-140 moved the
	# net-test harness out of game.gd), not on the game node — the
	# old `g._net_steps` target no longer exists (SCRIPT ERROR:
	# "Invalid assignment of property '_net_steps'"), so the whole
	# net suite built 0 steps and reported 0/0. A QA-140 regression,
	# not a QA-141 change.
	g.net_test._net_steps = [
		{"name": "PAYLOAD-ROUNDTRIP", "wait": 0.3, "setup": g.net_test._nt_s_noop, "check": g.net_test._nt_c_payload},
		{"name": "SUBNET-BROADCAST", "wait": 0.3, "setup": g.net_test._nt_s_noop, "check": g.net_test._nt_c_subnet},
		{"name": "DISCOVERY-BIND", "wait": 0.3, "setup": g.net_test._nt_s_noop, "check": g.net_test._nt_c_discovery_bind},
		{"name": "SPAWN-IDEMPOTENT", "wait": 0.3, "setup": g.net_test._nt_s_spawn_idem, "check": g.net_test._nt_c_spawn_idem},
		{"name": "COMBAT-HIT", "wait": 0.6, "setup": g.net_test._nt_s_combat_hit, "check": g.net_test._nt_c_combat_hit},
		{"name": "DOUBLE-CREDIT-SHOT1", "wait": 0.6, "setup": g.net_test._nt_s_dc_shot1, "check": g.net_test._nt_c_dc_shot1},
		{"name": "DOUBLE-CREDIT-SHOT2", "wait": 0.6, "setup": g.net_test._nt_s_dc_shot2, "check": g.net_test._nt_c_dc_shot2},
		{"name": "DAMAGE-DEATH-RESPAWN", "wait": 0.3, "setup": g.net_test._nt_s_damage, "check": g.net_test._nt_c_damage},
		{"name": "DAMAGE-RESPAWNED", "wait": 3.5, "setup": g.net_test._nt_s_noop, "check": g.net_test._nt_c_respawned},
		{"name": "MODE-SURVIVAL", "wait": 0.8, "setup": g.net_test._nt_s_survival, "check": g.net_test._nt_c_survival},
		{"name": "MODE-LMS", "wait": 0.8, "setup": g.net_test._nt_s_lms, "check": g.net_test._nt_c_lms},
		{"name": "DISCONNECT-CLEANUP", "wait": 0.5, "setup": g.net_test._nt_s_disconnect, "check": g.net_test._nt_c_disconnect},
		{"name": "HOST-LEFT-SAFE-EXIT", "wait": 0.3, "setup": g.net_test._nt_s_host_left, "check": g.net_test._nt_c_host_left},
		{"name": "DOUBLE-CREDIT", "wait": 0.3, "setup": g.net_test._nt_s_double_credit, "check": g.net_test._nt_c_double_credit},
		{"name": "DOUBLE-CREDIT-EXPIRE", "wait": 1.2, "setup": g.net_test._nt_s_double_credit_expire, "check": g.net_test._nt_c_double_credit_expire},
	]

