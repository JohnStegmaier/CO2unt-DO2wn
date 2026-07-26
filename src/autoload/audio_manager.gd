extends Node2D

#add background music here
var music = {
	"main_menu": preload("res://assets/audio/music/clockwork_pulse.mp3"),
	"60000 light years": preload("res://assets/audio/music/60000 light years.mp3")
}

#add sound effects here
var sounds = {
	"clock_tick": preload("res://assets/audio/sfx/clock_tick_01.mp3"),
	"tick_trim": preload("res://assets/audio/sfx/tick_trim.mp3"),
	"laser_gun_01": preload("res://assets/audio/sfx/laser_gun_01.mp3"),
	"bomb_air_burst": preload("res://assets/audio/sfx/bomb_air_burst.mp3"),
	"warp": preload("res://assets/audio/sfx/Enemy_warp_in.mp3"),
	"pulse_01": preload("res://assets/audio/sfx/edr_pulse.mp3"),
	"pulse_02": preload("res://assets/audio/sfx/pulse_02.mp3"),
	"explosion_01": preload("res://assets/audio/sfx/explosion_01.mp3"),
	"player_grunt_01": preload("res://assets/audio/sfx/roll_2.mp3"),
	"damage_taken_01": preload("res://assets/audio/sfx/damage_taken_1.mp3"),
	"damage_taken_02": preload("res://assets/audio/sfx/damage_taken_2.mp3"),
	"money_jingle_1": preload("res://assets/audio/sfx/money_jingle_1.mp3"),
	"money_drop_2": preload("res://assets/audio/sfx/money_drop_2.mp3")
}

## Endgame sounds the artists have not delivered yet. They are loaded at runtime
## rather than preloaded so a missing file is silence, not a parse error — drop
## the mp3 in at the path below and it wires itself up on the next run.
const HEARTBEAT_PATH := "res://assets/audio/sfx/heartbeat.mp3"
const POWER_DOWN_PATH := "res://assets/audio/sfx/power_down.mp3"

## Volume the heartbeat fades up to. Under the music on purpose — it is meant to
## be felt before it is noticed.
const HEARTBEAT_VOLUME := -6.0
const SILENT_DB := -40.0

var _fade_tweens = {}

@onready var _heartbeat: AudioStreamPlayer = $HeartbeatPlayer


func _ready() -> void:
	if ResourceLoader.exists(POWER_DOWN_PATH):
		sounds["power_down"] = load(POWER_DOWN_PATH)
	if ResourceLoader.exists(HEARTBEAT_PATH):
		var stream: AudioStream = load(HEARTBEAT_PATH)
		# Forced here rather than trusted to the .import flag, because a heartbeat
		# that quietly plays once is indistinguishable from one that never started.
		if "loop" in stream:
			stream.loop = true
		_heartbeat.stream = stream


func play_music(song_name, pitch = 1.0, volume = 0.0, start_time = 0.0):
	for music_player in [$MusicPlayer, $MusicPlayer2]:
		if !music_player.playing:
			_cancel_fade(music_player)
			music_player.stream = music[song_name]
			music_player.pitch_scale = pitch
			music_player.volume_db = volume
			music_player.play(start_time)
			return
	return null

func stop_music(fade_duration = 1.0):
	for music_player in [$MusicPlayer, $MusicPlayer2]:
		if music_player.playing:
			_cancel_fade(music_player)
			var original_volume = music_player.volume_db
			var tween = create_tween()
			_fade_tweens[music_player] = tween
			tween.tween_property(music_player, "volume_db", -40.0, fade_duration)
			tween.tween_callback(music_player.stop)
			tween.tween_callback(func(): music_player.volume_db = original_volume)

func _cancel_fade(player):
	if _fade_tweens.has(player) and _fade_tweens[player].is_valid():
		_fade_tweens[player].kill()
	_fade_tweens.erase(player)

func play_sfx(sound_name, pitch = 1.0, volume = 0.0, start_time = 0.0):
	# Some sounds are wired up before their asset exists. Silence beats a crash.
	if not sounds.has(sound_name):
		return null
	var players := [$SFX1, $SFX2, $SFX3, $SFX4, $SFX5, $SFX6, $SFX7, $SFX8, $SFX9, $SFX10]
	var chosen: AudioStreamPlayer = null
	for player in players:
		if !player.playing:
			chosen = player
			break
	# Busy combat can overlap more than 10 sounds at once — every slot taken used
	# to mean the new sound just never played, silently thinning out the mix
	# instead of actually changing volume. Stealing the first slot instead means
	# play_sfx always plays something, at the cost of cutting off whatever that
	# slot was playing.
	if chosen == null:
		chosen = players[0]
	chosen.stream = sounds[sound_name]
	chosen.pitch_scale = pitch
	chosen.volume_db = volume
	chosen.play(start_time)
	return chosen


## The player's own pulse, rising as the air runs out. It gets a dedicated player
## rather than an SFX slot: it loops for the rest of the run, and a busy room
## would otherwise evict it or starve everything else out of the pool of ten.
func start_heartbeat(fade_duration = 2.0):
	if _heartbeat.stream == null or _heartbeat.playing:
		return
	_cancel_fade(_heartbeat)
	_heartbeat.volume_db = SILENT_DB
	_heartbeat.play()
	var tween = create_tween()
	_fade_tweens[_heartbeat] = tween
	tween.tween_property(_heartbeat, "volume_db", HEARTBEAT_VOLUME, fade_duration)


func stop_heartbeat(fade_duration = 1.0):
	if not _heartbeat.playing:
		return
	_cancel_fade(_heartbeat)
	var tween = create_tween()
	_fade_tweens[_heartbeat] = tween
	tween.tween_property(_heartbeat, "volume_db", SILENT_DB, fade_duration)
	tween.tween_callback(_heartbeat.stop)


## Freeze every stream where it stands, for the pause menu.
##
## The engine already does this for us when the tree pauses, because we sit at
## PROCESS_MODE_INHERIT — but the O2 countdown is glued to the music by a hand
## of magic offsets from GlobalTimer, so it is worth saying out loud rather than
## relying on a notification. Either way the playhead resumes where it stopped,
## which is what keeps the track in phase with the tick grid across a pause.
func set_all_paused(paused: bool) -> void:
	for player in _all_players():
		player.stream_paused = paused


func _all_players() -> Array:
	return [$MusicPlayer, $MusicPlayer2, _heartbeat,
			$SFX1, $SFX2, $SFX3, $SFX4, $SFX5, $SFX6, $SFX7, $SFX8, $SFX9, $SFX10]
