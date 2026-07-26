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
	"laser_gun_01": preload("res://assets/audio/sfx/laser_gun_01.mp3")
	
}

## Endgame sounds the artists have not delivered yet. They are loaded at runtime
## rather than preloaded so a missing file is silence, not a parse error — drop
## the mp3 in at the path below and it wires itself up on the next run.
const HEARTBEAT_PATH := "res://assets/audio/sfx/heartbeat.mp3"
const POWER_DOWN_PATH := "res://assets/audio/sfx/power_down.mp3"

## The shopkeeper's greeting and the shop's calmer track, on the same terms:
## drop the files in at these paths and they wire themselves up on the next run.
## Until then engaging him is silent and the shop plays nothing, which is the
## whole point of loading them at runtime rather than preloading.
const SHOPKEEPER_GREET_PATH := "res://assets/audio/sfx/hurrrrr.mp3"
const SHOP_MUSIC_PATH := "res://assets/audio/music/shop_calm.mp3"

## Volume the heartbeat fades up to. Under the music on purpose — it is meant to
## be felt before it is noticed.
const HEARTBEAT_VOLUME := -6.0
const SILENT_DB := -40.0

var _fade_tweens = {}

## Players frozen for a reason that outlives a pause — currently the run's music
## while the player is in a shop. Kept separate from the pause menu's freeze so
## the two compose: see [method set_all_paused].
var _suspended = {}

@onready var _heartbeat: AudioStreamPlayer = $HeartbeatPlayer


func _ready() -> void:
	if ResourceLoader.exists(POWER_DOWN_PATH):
		sounds["power_down"] = load(POWER_DOWN_PATH)
	if ResourceLoader.exists(SHOPKEEPER_GREET_PATH):
		sounds["shopkeeper_greet"] = load(SHOPKEEPER_GREET_PATH)
	if ResourceLoader.exists(SHOP_MUSIC_PATH):
		music["shop_calm"] = load(SHOP_MUSIC_PATH)
	# The purchase and refusal sounds shipped in PR #48 and are registered by
	# name here so the shop is not the only place that knows the filenames.
	_register_sfx("money_jingle_1", "res://assets/audio/sfx/money_jingle_1.mp3")
	_register_sfx("wall_collision_1", "res://assets/audio/sfx/wall_collision_1.mp3")
	if ResourceLoader.exists(HEARTBEAT_PATH):
		var stream: AudioStream = load(HEARTBEAT_PATH)
		# Forced here rather than trusted to the .import flag, because a heartbeat
		# that quietly plays once is indistinguishable from one that never started.
		if "loop" in stream:
			stream.loop = true
		_heartbeat.stream = stream


## Returns the player it claimed, so a caller that started a track can later stop
## just that one — see [method stop_player]. Nothing needed the handle before, so
## returning it costs existing callers nothing.
func play_music(song_name, pitch = 1.0, volume = 0.0, start_time = 0.0):
	# Some tracks are wired up before their asset exists, same as play_sfx below.
	# Silence beats a crash — and the lookup below reads the dictionary before
	# either loop, so an unknown name has to be turned away here.
	if not music.has(song_name):
		return null

	# Already playing? Hand back the player that has it rather than starting a
	# second copy on the other one.
	#
	# Game._start_music is connected to GlobalTimer.tick and re-fires every
	# second for the whole run, relying on this call being a no-op once the track
	# is going. It was not: the first tick claimed MusicPlayer, and the next one
	# found MusicPlayer2 free and layered a second copy a second out of phase.
	# That is the exact failure the comment above _start_music says it exists to
	# avoid, so the fix belongs here rather than in another guard up there.
	var stream: AudioStream = music[song_name]
	for music_player in [$MusicPlayer, $MusicPlayer2]:
		if music_player.playing and music_player.stream == stream:
			return music_player

	for music_player in [$MusicPlayer, $MusicPlayer2]:
		# A suspended player still reports playing, so a frozen track is skipped
		# here rather than being torn out from under whoever froze it.
		if !music_player.playing:
			_cancel_fade(music_player)
			music_player.stream = music[song_name]
			music_player.pitch_scale = pitch
			music_player.volume_db = volume
			music_player.play(start_time)
			return music_player
	return null

func stop_music(fade_duration = 1.0):
	for music_player in [$MusicPlayer, $MusicPlayer2]:
		# Suspended players are skipped: something is deliberately holding that
		# track frozen mid-phrase and fading it out would lose its playhead.
		if music_player.playing and not _suspended.has(music_player):
			stop_player(music_player, fade_duration)


## Fade one player out and stop it, leaving any others alone.
##
## Split out of [method stop_music] so a caller holding the handle
## [method play_music] gave it can end its own track without touching a second
## one playing underneath.
func stop_player(player, fade_duration = 1.0):
	if player == null or not player.playing:
		return
	_cancel_fade(player)
	var original_volume = player.volume_db
	var tween = create_tween()
	_fade_tweens[player] = tween
	tween.tween_property(player, "volume_db", -40.0, fade_duration)
	tween.tween_callback(player.stop)
	tween.tween_callback(func(): player.volume_db = original_volume)

func _cancel_fade(player):
	if _fade_tweens.has(player) and _fade_tweens[player].is_valid():
		_fade_tweens[player].kill()
	_fade_tweens.erase(player)

## Register a sound only if its file is actually there, and never clobber an
## entry someone else already made. Additive on purpose: the audio branch is
## filling these dictionaries wholesale, and this must not fight it.
func _register_sfx(sound_name: String, path: String) -> void:
	if sounds.has(sound_name) or not ResourceLoader.exists(path):
		return
	sounds[sound_name] = load(path)


func play_sfx(sound_name, pitch = 1.0, volume = 0.0, start_time = 0.0):
	# Some sounds are wired up before their asset exists. Silence beats a crash.
	if not sounds.has(sound_name):
		return null
	for player in [$SFX1, $SFX2, $SFX3, $SFX4, $SFX5, $SFX6, $SFX7, $SFX8, $SFX9, $SFX10]:
		if !player.playing:
			player.stream = sounds[sound_name]
			player.pitch_scale = pitch
			player.volume_db = volume
			player.play(start_time)
			return player
	return null


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
## Unpausing must not thaw a stream something else is deliberately holding
## frozen. Without the second term, opening and closing the pause menu inside a
## shop would restart the run's music while GlobalTimer's beat grid was still
## stopped, and the two would be out of phase for the rest of the run.
func set_all_paused(paused: bool) -> void:
	for player in _all_players():
		player.stream_paused = paused or _suspended.has(player)


## Freeze the music that is playing right now, or thaw whatever this froze.
##
## stream_paused rather than stop: the playhead stays where it is, so resuming
## puts the track back exactly where it left off and its offset against
## GlobalTimer's beat grid is preserved. Stopping and replaying would restart the
## track from zero while the grid had moved on. Freeze both on the same frame and
## the hand-tuned quarter-beat in Game._start_music survives untouched.
##
## Only music players, and only ones already playing — SFX are short enough that
## freezing them mid-shop would be a bug rather than a feature.
func suspend_music(suspended: bool) -> void:
	if suspended:
		for music_player in [$MusicPlayer, $MusicPlayer2]:
			if music_player.playing and not _suspended.has(music_player):
				_suspended[music_player] = true
				music_player.stream_paused = true
		return

	# Handed back to the pause menu's freeze rather than cleared outright. The two
	# holds are independent, and thawing a track into a paused game would be the
	# same phase bug in the other direction.
	var still_paused: bool = get_tree().paused
	for player in _suspended.keys():
		if is_instance_valid(player):
			player.stream_paused = still_paused
	_suspended.clear()


func is_music_suspended() -> bool:
	return not _suspended.is_empty()


func _all_players() -> Array:
	return [$MusicPlayer, $MusicPlayer2, _heartbeat,
			$SFX1, $SFX2, $SFX3, $SFX4, $SFX5, $SFX6, $SFX7, $SFX8, $SFX9, $SFX10]
