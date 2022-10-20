@tool
extends EditorPlugin

const AUTOLOAD_NAME = "BetterTerrain"
var dock : Control
var button : Button

func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/better-terrain/BetterTerrain.gd")
	
	dock = load("res://addons/better-terrain/Dock.tscn").instantiate()
	button = add_control_to_bottom_panel(dock, "Terrain")
	button.visible = false


func _exit_tree() -> void:
	remove_control_from_bottom_panel(dock)
	dock.queue_free()
	
	remove_autoload_singleton(AUTOLOAD_NAME)


func _handles(object) -> bool:
	return object is TileMap or object is TileSet


func _make_visible(visible) -> void:
	button.visible = visible


func _edit(object) -> void:
	if object is TileMap:
		dock.tilemap = object
		if object.tile_set:
			dock.tileset = object.tile_set
	if object is TileSet:
		dock.tileset = object
	dock.reload()


func _forward_canvas_gui_input(event) -> bool:
	# handle tilemap editing
	return false
