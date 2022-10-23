@tool
extends Control

# Buttons
@onready var draw_button := $VBoxContainer/Toolbar/Draw
@onready var rectangle_button := $VBoxContainer/Toolbar/Rectangle
@onready var fill_button := $VBoxContainer/Toolbar/Fill
@onready var add_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/AddTerrain
@onready var edit_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/EditTerrain
@onready var move_up_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/MoveUp
@onready var move_down_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/MoveDown
@onready var remove_terrain_button := $VBoxContainer/HSplitContainer/VBoxContainer/LowerToolbar/RemoveTerrain

@onready var terrain_tree := $VBoxContainer/HSplitContainer/VBoxContainer/Panel/Tree
@onready var tile_view := $VBoxContainer/HSplitContainer/Panel2/TileView

@onready var terrain_icons = [
	load("res://addons/better-terrain/icons/MatchSides.svg"),
	load("res://addons/better-terrain/icons/MatchCorners.svg"),
	load("res://addons/better-terrain/icons/MatchSidesAndCorners.svg"),
	load("res://addons/better-terrain/icons/NonModifying.svg"),
]

const TERRAIN_PROPERTIES_SCENE = preload("res://addons/better-terrain/TerrainProperties.tscn")

var tilemap : TileMap
var tileset : TileSet


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	draw_button.icon = get_theme_icon("Edit", "EditorIcons")
	rectangle_button.icon = get_theme_icon("Rectangle", "EditorIcons")
	fill_button.icon = get_theme_icon("Bucket", "EditorIcons")
	add_terrain_button.icon = get_theme_icon("Add", "EditorIcons")
	edit_terrain_button.icon = get_theme_icon("Tools", "EditorIcons")
	move_up_button.icon = get_theme_icon("ArrowUp", "EditorIcons")
	move_down_button.icon = get_theme_icon("ArrowDown", "EditorIcons")
	remove_terrain_button.icon = get_theme_icon("Remove", "EditorIcons")
	
	# Make a root node for the terrain tree
	terrain_tree.create_item()


func reload() -> void:
	# clear terrains
	var root = terrain_tree.get_root()
	var children = root.get_children()
	for child in children:
		root.remove_child(child)
	
	# load terrains from tileset
	for i in BetterTerrain.terrain_count(tileset):
		var terrain = BetterTerrain.get_terrain(tileset, i)
		var new_terrain = terrain_tree.create_item(root)
		new_terrain.set_text(0, terrain.name)
		new_terrain.set_icon(0, terrain_icons[terrain.type])
		new_terrain.set_icon_modulate(0, terrain.color)
	
	tile_view.tileset = tileset
	tile_view.queue_redraw()


func generate_popup() -> ConfirmationDialog:
	var popup = TERRAIN_PROPERTIES_SCENE.instantiate()
	add_child(popup)
	return popup


func _on_add_terrain_pressed() -> void:
	if !tileset:
		return
	
	var popup = generate_popup()
	popup.terrain_name = "New terrain"
	popup.terrain_color = Color.AQUAMARINE
	popup.terrain_type = 0
	popup.popup_centered()
	await popup.visibility_changed
	if popup.accepted and BetterTerrain.add_terrain(tileset, popup.terrain_name, popup.terrain_color, popup.terrain_type):
		var new_terrain = terrain_tree.create_item(terrain_tree.get_root())
		new_terrain.set_text(0, popup.terrain_name)
		new_terrain.set_icon(0, terrain_icons[popup.terrain_type])
		new_terrain.set_icon_modulate(0, popup.terrain_color)
	popup.queue_free()


func _on_edit_terrain_pressed() -> void:
	if !tileset:
		return
	
	var item = terrain_tree.get_selected()
	if !item:
		return
		
	var t = BetterTerrain.get_terrain(tileset, item.get_index())
	
	var popup = generate_popup()
	popup.terrain_name = t.name
	popup.terrain_type = t.type
	popup.terrain_color = t.color
	popup.popup_centered()
	await popup.visibility_changed
	if popup.accepted and BetterTerrain.set_terrain(tileset, item.get_index(), popup.terrain_name, popup.terrain_color, popup.terrain_type):
		item.set_text(0, popup.terrain_name)
		item.set_icon(0, terrain_icons[popup.terrain_type])
		item.set_icon_modulate(0, popup.terrain_color)
	popup.queue_free()


func _on_move_pressed(down: bool) -> void:
	if !tileset:
		return
	
	var item = terrain_tree.get_selected()
	if !item:
		return
	
	var index1 = item.get_index()
	var index2 = index1 + (1 if down else -1)
	if index2 < 0 or index2 >= terrain_tree.get_root().get_child_count():
		return
	
	if BetterTerrain.swap_terrains(tileset, index1, index2):
		var item2 = terrain_tree.get_root().get_child(index2)
		if down:
			item.move_after(item2)
		else:
			item.move_before(item2)


func _on_remove_terrain_pressed() -> void:
	if !tileset:
		return
	
	# Confirmation dialog
	var item = terrain_tree.get_selected()
	if !item:
		return
	
	if BetterTerrain.remove_terrain(tileset, item.get_index()):
		item.free()


func _on_draw_pressed():
	pass


func _on_tree_cell_selected():
	var selected = terrain_tree.get_selected()
	if !selected:
		return
	
	tile_view.paint = selected.get_index()
	tile_view.queue_redraw()
