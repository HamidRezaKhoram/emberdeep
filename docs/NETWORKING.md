# Networking: local, LAN and Steam

The game runs **locally or over a LAN/Steam**; there is no central server. One machine is the
**host**: it owns `GameState`, runs the dungeon generator and the AI GM. Everyone else is a
client that sends intents and draws snapshots.

## Ways to play

| Mode | Status | How |
|---|---|---|
| Solo | works | "Play on this computer", 1 hero |
| Hot-seat | works | "Play on this computer", 2-4 heroes. Tab switches hero while exploring; in combat the game hands control to whoever's turn it is. |
| Steam Remote Play Together | works with hot-seat (needs the game on Steam) | Host runs a hot-seat game; Steam streams it to friends, who need not own the game. No netcode involved. |
| LAN (direct) | in the skeleton | Host: "Host a LAN game". Others see it in "Games on your network" (UDP broadcast) or type the host's IP. |
| Steam lobbies (P2P) | roadmap | GodotSteam lobby + Steam networking `MultiplayerPeer`; same intents and snapshots. |

## Protocol

- Transport: Godot high-level multiplayer over `ENetMultiplayerPeer`, UDP port **24565**.
- Discovery: host broadcasts `{"proto":"emberdeep/1","name","port","players"}` once a second to
  `255.255.255.255:24566`; the menu listens on 24566.
- Client → host RPCs (`any_peer`, reliable):
  - `_rpc_hello(name)`: adds a hero owned by the sender; host replies with a full snapshot.
  - `_rpc_intent(intent)`: forwarded to `GameState.handle_intent(sender_id, intent)`.
- Host → clients (`authority`, reliable): `_rpc_snapshot(snapshot)`; at most once per frame, and
  the map is included only when `map_version` changed. A client counts as joined once it has the map.
- Security: the host checks that the sender owns the hero in every intent. Object decoding stays
  off (Godot default). Text is trimmed; the UI escapes BBCode.

Firewall: open UDP 24565 (game) and 24566 (discovery) on the host for LAN play.

## Steam integration plan

1. Add **GodotSteam** (GDExtension build matching Godot 4.6; pin the version, since its
   networking APIs changed to Steam IDs in later releases).
2. `SteamInit` at startup with the app id (480 "Spacewar" for development).
3. Host: create a lobby (friends-only), set lobby data `proto=emberdeep/1`. Clients: join from
   the friend list / invite overlay.
4. Create a Steam `MultiplayerPeer` (from GodotSteam) instead of ENet, and assign it to
   `multiplayer.multiplayer_peer`. Nothing else in `Net` or `GameState` changes, because all
   game traffic is already RPCs over the high-level API.
5. Use Steam persona names for hero names; Steam rich presence "Exploring depth 4".
6. Test matrix: Linux↔Linux, Linux↔Windows (Proton), Steam Deck.

## Later

- Delta snapshots (or `MultiplayerSynchronizer`) once state grows.
- Reconnect: keep a disconnected hero for N minutes and reattach by Steam id / name.
- Spectators (no hero).
- Host migration is out of scope: the host owns the GM and the model.
