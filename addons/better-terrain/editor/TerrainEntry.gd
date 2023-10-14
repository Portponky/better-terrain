@tool
extends PanelContainer

signal select(index)

@onready var color_panel := %Color
@onready var terrain_icon_slot := %TerrainIcon
@onready var type_icon_slot := %TypeIcon
@onready var type_icon_panel := %TerrainIconPanel
@onready var name_label := %Name
@onready var layout_container := %Layout
@onready var icon_layout_container := %IconLayout

var selected := false

var tileset:TileSet
var terrain:Dictionary

var grid_mode := false
var color_style_list:StyleBoxFlat
var color_style_grid:StyleBoxFlat
var color_style_decoration:StyleBoxFlat

var _terrain_texture:Texture2D
var _terrain_texture_rect:Rect2i
var _icon_draw_connected := false

@onready var terrain_icons := [
	load("res://addons/better-terrain/icons/MatchTiles.svg"),
	load("res://addons/better-terrain/icons/MatchVertices.svg"),
	load("res://addons/better-terrain/icons/NonModifying.svg"),
	load("res://addons/better-terrain/icons/Decoration.svg"),
]

func _ready():
	update()

func update():
	if !terrain or !terrain.valid:
		return
	if !tileset:
		return
	
	name_label.text = terrain.name
	tooltip_text = "%s (%d)" % [terrain.name, terrain.id]
	
	color_style_list = color_panel.get_theme_stylebox("panel").duplicate()
	color_style_grid = color_panel.get_theme_stylebox("panel").duplicate()
	color_style_decoration = color_panel.get_theme_stylebox("panel").duplicate()
	
	color_style_list.bg_color = terrain.color
	color_style_list.corner_radius_top_left = 8
	color_style_list.corner_radius_bottom_left = 8
	color_style_list.corner_radius_top_right = 0
	color_style_list.corner_radius_bottom_right = 0
	color_style_list.content_margin_left = -1
	color_style_list.content_margin_right = -1
	color_style_list.border_width_left = 0
	color_style_list.border_width_right = 0
	color_style_list.border_width_top = 0
	color_style_list.border_width_bottom = 0
	
	color_style_grid.bg_color = terrain.color
	color_style_grid.corner_radius_top_left = 6
	color_style_grid.corner_radius_bottom_left = 6
	color_style_grid.corner_radius_top_right = 6
	color_style_grid.corner_radius_bottom_right = 6
	color_style_grid.content_margin_left = -1
	color_style_grid.content_margin_right = -1
	color_style_grid.border_width_left = 0
	color_style_grid.border_width_right = 0
	color_style_grid.border_width_top = 0
	color_style_grid.border_width_bottom = 0
	
	color_style_decoration.bg_color = terrain.color
	color_style_decoration.corner_radius_top_left = 8
	color_style_decoration.corner_radius_bottom_left = 8
	color_style_decoration.corner_radius_top_right = 8
	color_style_decoration.corner_radius_bottom_right = 8
	color_style_decoration.content_margin_left = -1
	color_style_decoration.content_margin_right = -1
	color_style_decoration.border_width_left = 4
	color_style_decoration.border_width_right = 4
	color_style_decoration.border_width_top = 4
	color_style_decoration.border_width_bottom = 4
	
	type_icon_slot.texture = terrain_icons[terrain.type]
	
	var has_icon = false
	if terrain.has("icon"):
		if terrain.icon.has("path") and not terrain.icon.path.is_empty():
			terrain_icon_slot.texture = load(terrain.icon.path)
			_terrain_texture = null
			terrain_icon_slot.queue_redraw()
			has_icon = true
		elif terrain.icon.has("source_id"):
			var source := tileset.get_source(terrain.icon.source_id) as TileSetAtlasSource
			var coord := terrain.icon.coord as Vector2i
			var rect := source.get_tile_texture_region(coord, 0)
			_terrain_texture = source.texture
			_terrain_texture_rect = rect
			terrain_icon_slot.queue_redraw()
			has_icon = true
	
	if not has_icon:
		var tiles = BetterTerrain.get_tile_sources_in_terrain(tileset, get_index())
		if tiles.size() > 0:
			var source := tiles[0].source as TileSetAtlasSource
			var coord := tiles[0].coord as Vector2i
			var rect := source.get_tile_texture_region(coord, 0)
			_terrain_texture = source.texture
			_terrain_texture_rect = rect
			terrain_icon_slot.queue_redraw()
	
	if _terrain_texture:
		terrain_icon_slot.texture = null
	
	if not _icon_draw_connected:
		terrain_icon_slot.connect("draw", func():
			if _terrain_texture:
				terrain_icon_slot.draw_texture_rect_region(_terrain_texture, Rect2i(0,0, 44, 44), _terrain_texture_rect)
		)
		_icon_draw_connected = true
	
	update_style()


func update_style():
	if terrain.type == BetterTerrain.TerrainType.DECORATION:
		type_icon_panel.visible = false
		color_panel.custom_minimum_size = Vector2i(52,52)
	else:
		type_icon_panel.visible = true
		color_panel.custom_minimum_size = Vector2i(24,24)
			
	if grid_mode:
		if terrain.type == BetterTerrain.TerrainType.DECORATION:
			color_panel.add_theme_stylebox_override("panel", color_style_decoration)
			color_panel.size_flags_vertical = Control.SIZE_FILL
			icon_layout_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		else:
			color_panel.add_theme_stylebox_override("panel", color_style_grid)
			color_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			icon_layout_container.size_flags_vertical = Control.SIZE_FILL
		custom_minimum_size = Vector2(0, 60)
		size_flags_horizontal = Control.SIZE_FILL
		layout_container.vertical = true
		name_label.visible = false
		icon_layout_container.add_theme_constant_override("separation", -24)
	else:
		if terrain.type == BetterTerrain.TerrainType.DECORATION:
			color_panel.add_theme_stylebox_override("panel", color_style_decoration)
		else:
			color_panel.add_theme_stylebox_override("panel", color_style_list)
		icon_layout_container.size_flags_vertical = Control.SIZE_FILL
		custom_minimum_size = Vector2(2000, 60)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		layout_container.vertical = false
		name_label.visible = true
		color_panel.size_flags_vertical = Control.SIZE_FILL
		icon_layout_container.add_theme_constant_override("separation", 4)


func set_selected(value:bool = true):
	selected = value
	if value:
		select.emit(get_index())
	queue_redraw()


func _draw():
	if selected:
		draw_rect(Rect2(Vector2.ZERO, get_rect().size), Color(0.15, 0.70, 1, 0.3))


func _on_focus_entered():
	queue_redraw()
	selected = true
	select.emit(get_index())


func _on_focus_exited():
	queue_redraw()
