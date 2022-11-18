@tool
extends EditorPlugin

const AUTOLOAD_NAME = "BetterTerrain"
var dock : Control
var button : Button

func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, "res://addons/better-terrain/BetterTerrain.gd")
	
	dock = load("res://addons/better-terrain/editor/Dock.tscn").instantiate()
	dock.update_overlay.connect(self.update_overlays)
	get_editor_interface().get_editor_main_screen().mouse_exited.connect(dock.canvas_mouse_exit)
	dock.undo_manager = get_undo_redo()
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
	dock.tiles_about_to_change()
	if object is TileMap:
		dock.tilemap = object
		dock.tileset = object.tile_set
	if object is TileSet:
		dock.tileset = object
	dock.tiles_changed()


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if dock.visible:
		dock.canvas_draw(overlay)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if !dock.visible:
		return false
	
	return dock.canvas_input(event)
