extends Node

## Launch-time tuning overrides, so a test value never has to be typed into a
## script that then gets committed.
##
## Godot has no profile system of its own — there is no equivalent of Spring's
## application-<env>.yml, and the two things that sound like one both miss:
## feature tags resolve per export preset rather than per launch, and
## override.cfg only reaches ProjectSettings in an exported build, never an
## @export on a node. What Godot does give us is ConfigFile, user command-line
## arguments and an editor Run Args field, which is enough to build the real
## thing in one small script.
##
## A profile is a .cfg under res://src/config/profiles/. Select one with
## `--profile=<name>` after a bare `--`:
##
##     godot -- --profile=die_quickly
##
## To get it from the editor's play button instead, set Project Settings ->
## Editor -> Run -> Main Run Args to `-- --profile=die_quickly`.
##
## THAT FIELD LIVES IN project.godot AND IS TRACKED BY GIT. Committing it hands
## your profile to everyone who presses F5, which is a milder version of the
## very accident this exists to stop. Hence the banner in _load: an active
## profile should be impossible to miss in the Output panel. It cannot reach a
## shipped build — main_run_args is read by the editor when it launches the
## game, so an exported binary never sees it, and _ready refuses to load a
## profile outside a debug build regardless.

const PROFILE_DIR := "res://src/config/profiles"
const PROFILE_ARG := "--profile="

## Bookkeeping for humans, not values for the game: where the profile sits in the
## toolbar dropdown and a one-line summary of what it is for. No game code reads
## it, and it is left out of the banner below — a section of overrides should
## list only things that were actually overridden.
const META_SECTION := "meta"

## Written by the editor toolbar dropdown (addons/profile_switcher). Gitignored,
## so a switch made while testing cannot follow anyone into a pull request.
const LOCAL_SELECTION := "res://src/config/local.cfg"

## Name of the profile in force, or "" when running on the shipped defaults.
var active_profile := ""

var _values := ConfigFile.new()


func _ready() -> void:
	var requested := _requested_profile()
	if requested.is_empty():
		return
	if not OS.is_debug_build():
		push_warning("GameConfig: ignoring profile '%s' — profiles are debug builds only." % requested)
		return
	_load(requested)


## Hand back what the profile says, or the value the caller already had. The
## defaults deliberately live at the call site rather than in some base profile,
## so the numbers that ship stay the ones written in the scripts and a missing
## profile file can never change the game.
func get_value(section: String, key: String, default: Variant) -> Variant:
	return _values.get_value(section, key, default)


## An explicit --profile= wins over the dropdown, so a scripted or CI run gets
## what it asked for no matter what someone left selected in their editor.
func _requested_profile() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PROFILE_ARG):
			return arg.trim_prefix(PROFILE_ARG)

	var selection := ConfigFile.new()
	if selection.load(LOCAL_SELECTION) == OK:
		return selection.get_value("local", "profile", "")
	return ""


func _load(profile_name: String) -> void:
	var path := "%s/%s.cfg" % [PROFILE_DIR, profile_name]
	var err := _values.load(path)
	if err != OK:
		# Loudly, and without falling back to anything: a typo in a profile name
		# that silently ran the real values would waste a whole test session.
		push_error("GameConfig: cannot load profile '%s' at %s (error %d)" % [profile_name, path, err])
		return

	active_profile = profile_name
	print_rich("[b][color=orange]=== PROFILE '%s' ACTIVE — these are NOT the shipped values ===[/color][/b]"
			% profile_name)
	var summary: String = _values.get_value(META_SECTION, "summary", "")
	if not summary.is_empty():
		print_rich("[color=orange]    %s[/color]" % summary)
	for section in _values.get_sections():
		if section == META_SECTION:
			continue
		for key in _values.get_section_keys(section):
			print_rich("[color=orange]    %s/%s = %s[/color]"
					% [section, key, _values.get_value(section, key)])
