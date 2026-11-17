@tool
extends EditorPlugin
## Adds the reminder plugin's entries to the Android manifest at export.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/village_reminders/export_plugin.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
