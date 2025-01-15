@tool
extends Panel

## TEST
var dragging : bool
var drag_offset = Vector2()

@onready var tile_view: Control = $TileView

func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				dragging = true
				drag_offset = get_global_mouse_position() - tile_view.position
			else:
				dragging = false

	if event is InputEventMouseButton:
		#if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.ctrl_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			accept_event()
			tile_view.change_zoom_level.emit(tile_view.zoom_level * 1.1)
			if tile_view.zoom_level < 8:
				var mouse_local_pos = tile_view.get_global_transform().affine_inverse() * get_global_mouse_position()
				tile_view.position += mouse_local_pos * -0.1

		## TEST
		#if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.ctrl_pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			accept_event()
			tile_view.change_zoom_level.emit(tile_view.zoom_level / 1.1)
			if tile_view.zoom_level > 1:
				var mouse_local_pos = tile_view.get_global_transform().affine_inverse() * get_global_mouse_position()
				tile_view.position += mouse_local_pos * 0.1

func _process(delta):
	if dragging:
		var mouse_pos = get_global_mouse_position()
		tile_view.position = mouse_pos - drag_offset
