# Events: how the rules talk to the screen and speakers

The rules (`GameState`) resolve every action **instantly and deterministically**. Each atomic thing
that happens is also emitted as an **event**, in order, on `GameState.game_event`:

```
input → GameState (rules, instant) ──game_event──► Presenter (timing) ──played──► AudioDirector
                                    └─changed────► HUD, MapView.refresh()          (and later: rumble, UI)
```

- **Presenter** (`scripts/view/presenter.gd`) queues events and plays them back over time:
  tokens slide, attackers lunge, hits flash, damage floats up, the camera shakes on a crit, and
  dead monsters fade out. When more than 6 events are waiting, playback speeds up so the screen
  never falls behind. When nothing is queued, every token snaps to the true state.
- **Input never waits.** A key press changes the rules at once; its animation queues after
  whatever is still playing (the input buffer). Nothing is dropped.
- **AudioDirector** (`scripts/view/audio_director.gd`) plays sounds when an event *finishes playing*,
  so the sound lines up with the picture.
- **Network:** snapshots carry the events a client hasn't seen, so clients animate the same way.
- A test rebuilds every token's position from the events alone and checks it matches the rules
  exactly, so the presentation can't drift from the game.

## Event types

Every event has `seq` (gapless, counting up across games) and `type`.

| type | fields | when |
|---|---|---|
| `reset` | | a new game starts |
| `spawned` | `actor, pos, key?` | a hero joins, or a monster is placed |
| `moved` | `actor, from, to` | one step by a hero or monster |
| `door_open` | `actor, pos, room, kind` | an unexplored door opens onto a new room |
| `door_blocked` | `actor, pos` | the door turns out to be rubble |
| `woke` | `actor` | a monster notices the party |
| `lost_track` | `actor` | a monster gives up and goes back to sleep |
| `combat_start` / `combat_end` | | |
| `turn_start` | `actor, round` | a hero's turn begins |
| `attack` | `attacker, attacker_key?, target, hit, crit, damage, natural` | any attack roll |
| `monster_die` | `actor, key, name, pos` | |
| `hero_down` | `actor` | a hero drops to 0 HP |
| `death_save` | `actor, natural, success` | |
| `stabilized` | `actor` | 3 death-save successes, or an ally's Medicine check |
| `hero_die` | `actor` | 3 death-save failures |
| `revived` | `actor` | back to 1+ HP |
| `check_success` / `check_fail` | `actor, ability, target?` | an ability check (GM-requested, or Medicine) |
| `pickup` | `actor, item, pos` | |
| `party_fallen` | | no hero is conscious |

## Adding an event

1. `_emit("<type>", {...})` in `GameState`, right where the state changes. Positions as `Vector2i`.
2. If it should take screen time, add it to `Presenter.DURATIONS` and animate it in `_begin`, `_animate` and `_finish`.
3. If it should make a sound, map it in `AudioDirector.sound_for()`.
4. Add it to the table above. If it moves or removes a token, `_test_event_stream_complete` must still pass.
