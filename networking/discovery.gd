class_name LanDiscovery
extends Node

# LAN discovery: find rooms on the local network, and announce ours.
#
# Two problems with the old code: it broadcast ONLY to the limited
# broadcast address 255.255.255.255 (many routers and mobile hotspots
# block or never forward that), and the room list showed only an IP.
# This module broadcasts to every subnet broadcast address derived
# from the host's own local IPs (e.g. 192.168.1.255) as well as
# 255.255.255.255, and every announcement carries the full room card
# (room name, host name, players/max, map, mode, status, port, whether
# the room is private). Clients list rooms automatically, drop ones
# that stop announcing, and can always fall back to manual IP entry.
#
# Packet format (pipe-separated, versioned so old builds are ignored):
#   LANARENA|1|room_name|host_name|players|max|map|mode|status|port|private
# status is "lobby" or "playing". Room/host names are sanitised on
# build (no pipes, max 24 chars) so parsing can never break.

signal room_found(room: Dictionary)
signal room_expired(ip: String)

const DISCOVERY_PORT := 7778
const DISCOVERY_MAGIC := "LANARENA"
const PACKET_VERSION := 1
const EXPIRE_AFTER := 5.0

var _udp_listen: PacketPeerUDP
var _udp_sends: Array[PacketPeerUDP] = []
var _rooms: Dictionary = {} # ip -> room dict (with last_seen)


func _ready() -> void:
	set_process(true)


func _exit_tree() -> void:
	# QA-060: the menu scene is freed on every match start — the
	# discovery listen socket (UDP 7778) must be closed now, not
	# when the RefCounted socket happens to drop, or the next menu
	# cannot bind it.
	stop()


func start_listening() -> bool:
	if _udp_listen != null:
		return true
	_udp_listen = PacketPeerUDP.new()
	var err := _udp_listen.bind(DISCOVERY_PORT)
	if err != OK:
		push_warning("LanDiscovery: could not bind discovery port: %s" % err)
		_udp_listen = null
		return false
	return true


func start_broadcasting() -> void:
	stop_broadcasting()
	for addr in broadcast_addresses():
		var s := PacketPeerUDP.new()
		s.set_broadcast_enabled(true)
		s.set_dest_address(addr, DISCOVERY_PORT)
		_udp_sends.append(s)


func stop_broadcasting() -> void:
	for s in _udp_sends:
		s.close()
	_udp_sends.clear()


func stop() -> void:
	stop_broadcasting()
	if _udp_listen != null:
		_udp_listen.close()
		_udp_listen = null
	_rooms.clear()


func broadcast_room(room: Dictionary) -> void:
	if _udp_sends.is_empty():
		start_broadcasting()
	var pkt := build_room_packet(room)
	for s in _udp_sends:
		s.put_packet(pkt)


func get_rooms() -> Array:
	var out: Array = []
	for ip in _rooms.keys():
		out.append(_rooms[ip])
	return out


func forget_room(ip: String) -> void:
	_rooms.erase(ip)


func forget_all_rooms() -> void:
	_rooms.clear()


func _process(delta: float) -> void:
	if _udp_listen != null:
		while _udp_listen.get_available_packet_count() > 0:
			var data := _udp_listen.get_packet()
			var ip := _udp_listen.get_packet_ip()
			# Never list our own announcements.
			if ip in local_ipv4_addresses():
				continue
			var room := parse_room_packet(data.get_string_from_utf8(), ip)
			if room.is_empty():
				continue
			room["last_seen"] = Time.get_ticks_msec() / 1000.0
			_rooms[ip] = room
			room_found.emit(room)
	# Expire rooms that stopped announcing.
	var now := Time.get_ticks_msec() / 1000.0
	var stale: Array = []
	for ip in _rooms.keys():
		if now - float(_rooms[ip]["last_seen"]) > EXPIRE_AFTER:
			stale.append(ip)
	for ip in stale:
		_rooms.erase(ip)
		room_expired.emit(ip)


# --- Address helpers (static so the game scene can reuse them) ---

static func local_ipv4_addresses() -> Array[String]:
	var out: Array[String] = []
	for ip in IP.get_local_addresses():
		if _is_ipv4(ip):
			out.append(ip)
	return out


static func lan_ip() -> String:
	# The address friends should type: prefer a private LAN address
	# (192.168/10/172.16-31), fall back to any non-loopback IPv4.
	var fallback := ""
	for ip in local_ipv4_addresses():
		if ip == "127.0.0.1":
			continue
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
		if fallback == "":
			fallback = ip
	return fallback


static func broadcast_addresses() -> Array[String]:
	var out: Array[String] = ["255.255.255.255"]
	for ip in local_ipv4_addresses():
		if ip == "127.0.0.1":
			continue
		var parts := ip.split(".")
		if parts.size() == 4:
			var bcast := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
			if not out.has(bcast):
				out.append(bcast)
	return out


static func _is_ipv4(ip: String) -> bool:
	# IPv6 contains ':'; IPv4 does not.
	return not ip.contains(":") and ip.split(".").size() == 4


# --- Packet build / parse (static so tests can use them directly) ---

static func sanitise(text: String) -> String:
	return text.replace("|", "").replace("\n", " ").strip_edges().left(24)


static func build_room_packet(room: Dictionary) -> PackedByteArray:
	var fields: Array[String] = [
		DISCOVERY_MAGIC,
		str(PACKET_VERSION),
		sanitise(str(room.get("room_name", "Room"))),
		sanitise(str(room.get("host_name", "Host"))),
		str(int(room.get("players", 1))),
		str(int(room.get("max_players", 8))),
		str(int(room.get("map_id", 0))),
		str(int(room.get("mode", 0))),
		str(room.get("status", "lobby")),
		str(int(room.get("port", 7777))),
		"1" if bool(room.get("private", false)) else "0",
	]
	return "|".join(fields).to_utf8_buffer()


static func parse_room_packet(text: String, from_ip: String) -> Dictionary:
	var parts := text.strip_edges().split("|")
	if parts.size() != 11:
		return {}
	if parts[0] != DISCOVERY_MAGIC or parts[1] != str(PACKET_VERSION):
		return {}
	return {
		"ip": from_ip,
		"room_name": parts[2],
		"host_name": parts[3],
		"players": int(parts[4]),
		"max_players": int(parts[5]),
		"map_id": int(parts[6]),
		"mode": int(parts[7]),
		"status": parts[8],
		"port": int(parts[9]),
		"private": parts[10] == "1",
	}
