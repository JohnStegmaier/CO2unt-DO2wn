extends Node2D

#add background music here
var music = {
	"main_menu": preload("res://assets/audio/music/clockwork_pulse.mp3"),
	"60000 light years": preload("res://assets/audio/music/60000 light years.mp3")
}

#add sound effects here
var sounds = {
	"clock_tick": preload("res://assets/audio/sfx/clock_tick_01.mp3"),
	"tick_trim": preload("res://assets/audio/sfx/tick_trim.mp3")
	
}

var _fade_tweens = {}

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
	for player in [$SFX1, $SFX2, $SFX3, $SFX4, $SFX5, $SFX6, $SFX7, $SFX8, $SFX9, $SFX10]:
		if !player.playing:
			player.stream = sounds[sound_name]
			player.pitch_scale = pitch
			player.volume_db = volume
			player.play(start_time)
			return player
	return null
