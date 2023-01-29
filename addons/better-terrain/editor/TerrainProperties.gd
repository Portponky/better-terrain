@tool
extends ConfirmationDialog

@onready var name_edit := $GridContainer/NameEdit
@onready var color_picker := $GridContainer/ColorPicker
@onready var type_option := $GridContainer/TypeOption
@onready var group_edit := $GridContainer/GroupEdit

var accepted := false

var terrain_name : String:
	set(value): name_edit.text = value
	get: return name_edit.text

var terrain_color : Color:
	set(value): color_picker.color = value
	get: return color_picker.color
	
var terrain_type : int:
	set(value): type_option.selected = value
	get: return type_option.selected

var terrain_group : StringName:
	set(value): group_edit.text = value
	get: return group_edit.text

func _on_confirmed() -> void:
	# confirm valid name
	if terrain_name.is_empty():
		var dialog = AcceptDialog.new()
		dialog.dialog_text = "Name cannot be empty"
		add_child(dialog)
		dialog.popup_centered()
		await dialog.visibility_changed
		dialog.queue_free()
		return
	
	accepted = true
	hide()
