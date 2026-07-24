extends Node2D

@onready var music_player = $MusicPlayer

#add background music here
var music = {
	"main_menu": preload("res://Music/Clockwork Pulse.mp3"),
}

#add sound effects here
var sounds = {
	#"encounter": preload("res://Audio/sfx/MMBN Encounter.wav"),
	
}

func play_music(song_name, pitch = 1.0, volume = 0.0, start_time = 0.0):
	music_player.stream = music[song_name]
	music_player.pitch_scale = pitch
	music_player.volume_db = volume
	music_player.play(start_time)

func play_sfx(sound_name, pitch = 1.0, volume = 0.0, start_time = 0.0):
	for player in [$SFX1, $SFX2, $SFX3, $SFX4, $SFX5, $SFX6, $SFX7, $SFX8, $SFX9, $SFX10]:
		if !player.playing:
			player.stream = sounds[sound_name]
			player.pitch_scale = pitch
			player.volume_db = volume
			player.play(start_time)
			return player
	return null
