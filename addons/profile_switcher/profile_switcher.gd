@tool
extends EditorPlugin

## A profile dropdown in the editor toolbar, so switching tuning is a click and
## then the ordinary play button.
##
## The alternative Godot hands you is Project Settings -> Editor -> Run -> Main
## Run Args, which is buried behind the Advanced Settings toggle, needs a bare
## `--` typed exactly right, and — the real problem — lives in project.godot,
## which git tracks. Committing it hands your debug profile to everyone who
## presses F5, which is a milder version of the accident this whole feature
## exists to prevent (issue #26).
##
## So the dropdown writes the selection to src/config/local.cfg, which .gitignore
## covers. Nothing tracked ever changes, no matter how carelessly you switch.
## GameConfig reads that file at startup and a `--profile=` command line
## argument still beats it, so scripted and CI runs are unaffected by whatever
## is selected here.

const PROFILE_DIR := "res://src/config/profiles"
const LOCAL_SELECTION := "res://src/config/local.cfg"

## Shown first and always present: there has to be a way back to the numbers
## that actually ship.
const NONE_LABEL := "no profile"

## Loud on purpose. A forgotten profile that looks like normal play is the one
## failure mode that would make this worse than typing run args by hand.
const ACTIVE_TINT := Color(1.0, 0.65, 0.2)

var _dropdown: OptionButton


func _enter_tree() -> void:
	_dropdown = OptionButton.new()
	_dropdown.focus_mode = Control.FOCUS_NONE
	_dropdown.item_selected.connect(_on_item_selected)
	_reload_items()
	add_control_to_container(CONTAINER_TOOLBAR, _dropdown)


func _exit_tree() -> void:
	if _dropdown == null:
		return
	remove_control_from_container(CONTAINER_TOOLBAR, _dropdown)
	_dropdown.queue_free()
	_dropdown = null


## Rebuild the list from whatever .cfg files are on disk, then restore the
## current selection. Adding a profile is dropping a file in the folder, so the
## list is derived rather than maintained.
func _reload_items() -> void:
	_dropdown.clear()
	_dropdown.add_item(NONE_LABEL)

	for profile_name in _profile_names():
		_dropdown.add_item(profile_name)

	_select(_saved_selection())


func _profile_names() -> PackedStringArray:
	var names := PackedStringArray()
	for file in DirAccess.get_files_at(PROFILE_DIR):
		if file.ends_with(".cfg"):
			names.append(file.get_basename())
	names.sort()
	return names


func _on_item_selected(index: int) -> void:
	var chosen := "" if index == 0 else _dropdown.get_item_text(index)

	var selection := ConfigFile.new()
	selection.set_value("local", "profile", chosen)
	var err := selection.save(LOCAL_SELECTION)
	if err != OK:
		push_error("Profile Switcher: could not write %s (error %d)" % [LOCAL_SELECTION, err])
		return

	_apply_tint(chosen)
	if chosen.is_empty():
		print_rich("[b]Profile cleared[/b] — the play button now runs the shipped values.")
	else:
		print_rich("[b][color=orange]Profile '%s' selected[/color][/b] — press play to run with it."
				% chosen)


## What the dropdown should be showing when the editor opens, which is whatever
## was picked last session.
func _saved_selection() -> String:
	var selection := ConfigFile.new()
	if selection.load(LOCAL_SELECTION) != OK:
		return ""
	return selection.get_value("local", "profile", "")


func _select(profile_name: String) -> void:
	for i in _dropdown.item_count:
		if _dropdown.get_item_text(i) == profile_name:
			_dropdown.select(i)
			_apply_tint(profile_name)
			return
	# The selected profile's file is gone, or nothing was ever selected.
	_dropdown.select(0)
	_apply_tint("")


func _apply_tint(profile_name: String) -> void:
	var active := not profile_name.is_empty()
	_dropdown.modulate = ACTIVE_TINT if active else Color.WHITE
	_dropdown.tooltip_text = ("Tuning profile '%s' is active — the play button will NOT use the shipped values." % profile_name) if active \
			else "No tuning profile: the play button runs the shipped values.\nPick one to test with different numbers."
