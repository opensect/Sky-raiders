class_name GameData
extends RefCounted

# Shared lobby / settings state passed from the menu to the game scene.
# No personal info is stored here - just a display name the player types.

const SAVE_PATH := "user://settings.cfg"
const BUILD_VERSION := "3.4" # GAP-61: join handshake rejects mismatched builds

static var player_name: String = "Player"
static var color_index: int = 0
static var helmet: int = 1
static var map_id: int = 0
static var game_mode: int = 0 # 0 = Free-for-All, 1 = Team Deathmatch
static var kill_limit: int = 10
static var match_minutes: int = 5
static var sfx_volume: float = 0.8
static var music_volume: float = 0.5
static var music_enabled: bool = true # Phase 6: music on/off (settings)
static var sensitivity: float = 1.0
static var show_fps: bool = false # Phase 4: FPS counter in the HUD
static var invert_aim: bool = false # Phase 4: flip the aim stick vertically
# v3.2: the FIRE button is gone (right stick aims and shoots), so its
# size/side settings are removed. Old save files carry the stale keys
# harmlessly — the loader never reads them any more.
static var host_ip: String = ""
static var portrait: int = 0
# Room settings (v2.4): configured when creating a room, shared with
# everyone in the lobby, and applied when the match starts.
static var room_name: String = "Room"
static var max_players: int = 8 # 2-12, set at room creation
static var friendly_fire: bool = false # Team Deathmatch only
static var room_private: bool = false
static var room_password: String = ""
static var last_host_ip: String = "" # prefilled after a disconnect, for reconnect
static var last_room_name: String = ""
# Full-flow check (--flow-test, v2.4): survives the scene change so
# the menu side can hand the check to the game side and back again.
# flow_phase: 0 = off, 1 = in the match, 2 = back at the menu.
static var flow_test: bool = false
static var flow_phase: int = 0

const PLAYER_COLORS: Array[Color] = [
	Color(0.95, 0.3, 0.25),
	Color(0.25, 0.55, 0.95),
	Color(0.3, 0.85, 0.4),
	Color(0.95, 0.8, 0.2),
	Color(0.75, 0.4, 0.9),
	Color(0.95, 0.5, 0.2),
]

const COLOR_NAMES: Array[String] = ["Red", "Blue", "Green", "Yellow", "Purple", "Orange"]
const HELMET_NAMES: Array[String] = ["No helmet", "Helmet", "Cap", "Black helmet"]
const MAP_NAMES: Array[String] = ["Catacombs", "Military Base", "Desert Outpost", "Industrial Factory", "Frozen Fortress", "Jungle Ruins", "Space Station", "City Underground", "Volcanic Cavern", "Pirate Island", "Neon City", "Ancient Temple", "Airship Fleet"] # Phase 5: 13 maps; the vote ballot in main.gd already uses MAP_NAMES.size() for its mod arithmetic
const MODE_NAMES: Array[String] = ["Free-for-All", "Team Deathmatch", "Survival", "Last Man Standing"]
# Music attribution (Phase 6, CC BY 4.0 — must appear in-game, settings/credits).
# Exact text from gen_assets_v3/music/LICENCE.md.
const MUSIC_CREDITS := "\"At Rest\" Kevin MacLeod (incompetech.com)\n\"Five Armies\" Kevin MacLeod (incompetech.com)\nLicensed under Creative Commons: By Attribution 4.0 License\nhttp://creativecommons.org/licenses/by/4.0/"
const MUSIC_CREDITS_SHORT := "Music: \"At Rest\" + \"Five Armies\" — Kevin MacLeod (incompetech.com), CC BY 4.0"
# Mode ids: 0 FFA (first to kill limit), 1 TDM (team kills), 2 Survival
# (round-based: one life per round, last alive wins the round, first
# to the round limit wins the match), 3 Last Man Standing (one life
# for the whole match, last alive wins; no respawns).


static func player_color() -> Color:
	return PLAYER_COLORS[clampi(color_index, 0, PLAYER_COLORS.size() - 1)]


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "color", color_index)
	cfg.set_value("player", "helmet", helmet)
	cfg.set_value("player", "portrait", portrait)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "music_enabled", music_enabled)
	cfg.set_value("controls", "sensitivity", sensitivity)
	cfg.set_value("controls", "show_fps", show_fps)
	cfg.set_value("controls", "invert_aim", invert_aim)
	cfg.save(SAVE_PATH)


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	player_name = str(cfg.get_value("player", "name", player_name))
	color_index = int(cfg.get_value("player", "color", color_index))
	helmet = int(cfg.get_value("player", "helmet", helmet))
	portrait = int(cfg.get_value("player", "portrait", portrait))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	music_enabled = bool(cfg.get_value("audio", "music_enabled", music_enabled))
	sensitivity = float(cfg.get_value("controls", "sensitivity", sensitivity))
	show_fps = bool(cfg.get_value("controls", "show_fps", show_fps))
	invert_aim = bool(cfg.get_value("controls", "invert_aim", invert_aim))


# Phase 4 — map vote tally (pure function, tested by --features-test).
# votes: peer id -> voted map id. candidates: the 2-3 maps on the
# ballot. default_map: the host's pick, used when nobody voted or on
# a tie (the earliest candidate wins ties, so the host's pick — always
# candidates[0] — wins a tie).
static func tally_map_vote(votes: Dictionary, candidates: Array, default_map: int) -> int:
	if candidates.is_empty():
		return default_map
	var counts := {}
	for c in candidates:
		counts[int(c)] = 0
	for id in votes.keys():
		var v := int(votes[id])
		if counts.has(v):
			counts[v] = int(counts[v]) + 1
	var best_map: int = int(candidates[0])
	var best_count: int = -1
	for c in candidates:
		var n := int(counts[int(c)])
		if n > best_count:
			best_count = n
			best_map = int(c)
	if best_count <= 0:
		return default_map
	return best_map


# Phase 4 — end-of-match stat math (pure function, tested by
# --features-test). kd is kills/deaths (deaths 0 counts as kills/1 so
# a flawless match reads as the kill count, never infinity).
# accuracy is hits/shots as a 0-100 percentage, capped at 100.
static func compute_stats(kills: int, deaths: int, shots: int, hits: int) -> Dictionary:
	var kd := float(kills) / float(maxi(deaths, 1))
	var acc := 0.0
	if shots > 0:
		acc = clampf(float(hits) / float(shots) * 100.0, 0.0, 100.0)
	return {"kd": kd, "accuracy": acc}
