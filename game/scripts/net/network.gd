extends Node
## Networking (autoload "Net"). See docs/NETWORKING.md.
##
## Host-authoritative: clients send intents, the host runs GameState (and the AI GM)
## and broadcasts snapshots. Everything goes through Godot's high-level multiplayer
## API, so the transport is swappable: ENet for LAN today; a Steam lobby peer
## (GodotSteam) later means changing only how `multiplayer.multiplayer_peer` is made.
## Local hot-seat play needs no networking and also works over Steam Remote Play Together.

signal status(text: String)
signal joined                       # client: first snapshot received, game can be shown
signal lan_game_found(info: Dictionary)

const GAME_PORT := 24565
const DISCOVERY_PORT := 24566
const MAX_CLIENTS := 5
const PROTOCOL := "emberdeep/1"

var _dirty := false
var _last_map_sent := -1
var _last_event_sent := 0
var _beacon: PacketPeerUDP
var _listener: PacketPeerUDP
var _beacon_clock := 0.0
var _host_name := ""
var _join_name := ""
var _has_joined := false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): status.emit("Could not connect."))
	multiplayer.server_disconnected.connect(func(): status.emit("The host closed the game."))
	GameState.changed.connect(func(): _dirty = true)


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


## True when this machine owns the game state (single-player, hot-seat, or LAN host).
func is_authority() -> bool:
	return not is_online() or multiplayer.is_server()


func local_peer_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func host(host_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, MAX_CLIENTS)
	if err != OK:
		status.emit("Could not host on port %d (error %d)." % [GAME_PORT, err])
		return err
	multiplayer.multiplayer_peer = peer
	_host_name = host_name
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	_beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	status.emit("Hosting on port %d. Friends on your network will see this game in their list." % GAME_PORT)
	return OK


func join(address: String, player_name: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, GAME_PORT)
	if err != OK:
		status.emit("Could not start connecting (error %d)." % err)
		return err
	multiplayer.multiplayer_peer = peer
	_join_name = player_name
	_has_joined = false
	status.emit("Connecting to %s..." % address)
	return OK


func leave() -> void:
	if is_online():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_beacon = null


## Every player input goes through here, wherever the player is sitting.
func send_intent(intent: Dictionary) -> void:
	if is_authority():
		GameState.handle_intent(local_peer_id(), intent)
	else:
		_rpc_intent.rpc_id(1, intent)


func start_discovery() -> void:
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		_listener = null  # another copy on this machine already listens; fine


func _process(delta: float) -> void:
	if _dirty and is_online() and multiplayer.is_server():
		var include_map := GameState.map_version != _last_map_sent
		_rpc_snapshot.rpc(GameState.to_snapshot(include_map, _last_event_sent))
		_last_map_sent = GameState.map_version
		_last_event_sent = GameState.event_seq
	_dirty = false
	if _beacon:
		_beacon_clock += delta
		if _beacon_clock >= 1.0:
			_beacon_clock = 0.0
			var info := {"proto": PROTOCOL, "name": _host_name, "port": GAME_PORT, "players": GameState.player_order.size()}
			_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener:
		while _listener.get_available_packet_count() > 0:
			var pkt := _listener.get_packet()
			var ip := _listener.get_packet_ip()
			var info = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(info) == TYPE_DICTIONARY and info.get("proto") == PROTOCOL:
				info["ip"] = ip
				lan_game_found.emit(info)


func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		status.emit("Peer %d connected." % id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		GameState.remove_players_of(id)


func _on_connected_to_server() -> void:
	status.emit("Connected. Joining the party...")
	_rpc_hello.rpc_id(1, _join_name)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	GameState.add_player(str(player_name), sender)
	_rpc_snapshot.rpc_id(sender, GameState.to_snapshot(true))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_intent(intent: Dictionary) -> void:
	if multiplayer.is_server():
		GameState.handle_intent(multiplayer.get_remote_sender_id(), intent)


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snapshot: Dictionary) -> void:
	GameState.apply_snapshot(snapshot)
	if not _has_joined and snapshot.has("map"):
		_has_joined = true
		joined.emit()
