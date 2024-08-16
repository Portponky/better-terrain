@tool
extends ConfirmationDialog

var category_icon := load("res://addons/better-terrain/icons/NonModifying.svg")

const CATEGORY_CHECK_ID = &"category_check_id"

var accepted := false

var terrain_name : String:
	set(value): %NameEdit.text = value
	get: return %NameEdit.text

var terrain_color : Color:
	set(value): %ColorPicker.color = value
	get: return %ColorPicker.color

var terrain_icon : String:
	set(value): %IconEdit.text = value
	get: return %IconEdit.text

var terrain_type : int:
	set(value):
		%TypeOption.selected = value
		_on_type_option_item_selected(value)
	get: return %TypeOption.selected

var terrain_categories : Array: set = set_categories, get = get_categories


# category is name, color, id
func set_category_data(options: Array) -> void:
	if !options.is_empty():
		%CategoryLabel.show()
		%CategoryContainer.show()
	
	for o in options:
		var c = CheckBox.new()
		c.text = o.name
		c.icon = category_icon
		c.add_theme_color_override(&"icon_normal_color", o.color)
		c.add_theme_color_override(&"icon_disabled_color", Color(o.color, 0.4))
		c.add_theme_color_override(&"icon_focus_color", o.color)
		c.add_theme_color_override(&"icon_hover_color", o.color)
		c.add_theme_color_override(&"icon_hover_pressed_color", o.color)
		c.add_theme_color_override(&"icon_normal_color", o.color)
		c.add_theme_color_override(&"icon_pressed_color", o.color)
		
		c.set_meta(CATEGORY_CHECK_ID, o.id)
		%CategoryLayout.add_child(c)


func set_categories(ids : Array):
	for c in %CategoryLayout.get_children():
		c.button_pressed = c.get_meta(CATEGORY_CHECK_ID) in ids


func get_categories() -> Array:
	var result := []
	if terrain_type == BetterTerrain.TerrainType.CATEGORY:
		return result
	for c in %CategoryLayout.get_children():
		if c.button_pressed:
			result.push_back(c.get_meta(CATEGORY_CHECK_ID))
	return result


func _on_confirmed() -> void:
	# confirm valid name
	if terrain_name.is_empty():
		var dialog := AcceptDialog.new()
		dialog.dialog_text = "Name cannot be empty"
		EditorInterface.popup_dialog_centered(dialog)
		await dialog.visibility_changed
		dialog.queue_free()
		return
	
	accepted = true
	hide()


func _on_type_option_item_selected(index: int) -> void:
	var categories_available = (index != BetterTerrain.TerrainType.CATEGORY)
	for c in %CategoryLayout.get_children():
		c.disabled = !categories_available
