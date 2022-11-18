# better-terrain
Terrain plugin for Godot 4's tilemap.

This plugin implements autotile-style terrain system with multiple connections. It works with the existing tilemaps and tilesets alongside Godot 4 features.

![Example of terrain system in use](https://user-images.githubusercontent.com/33663279/202700714-d4d78da4-3741-4d57-bc75-5c8f99d7543e.png)

### Why?

Godot 4 has a terrain system built-in to its tilemap node. This system has some tricky behaviors and is tailored towards a very specific usage of tilemaps, rather than a more general case. It's also quite slow, and the API is difficult to use at runtime. There are very large functional gaps caused by the replacement of the Godot 3 autotile system.

### Installation

To get started with `better-terrain`, follow these steps:
1. Clone or download the repo.
2. Copy the `addons` folder into your godot project.
3. In `Project setings` make sure the plugin is enabled in the `Plugins` tab.

Now when you select a tilemap node, a new dock tab called 'Terrains' will show up. In here, you can define terrains and paint with them.

### Usage in the editor

I'll write specific documentation in the coming weeks. Here are some rough notes.

The dock has terrain types on the left, and tiles on the right. At the bottom of the terrain types, there are buttons to add, modify, sort, or remove terrain types. A terrain type has a name, a color, and a type. The three types are:

* **Match tiles**: This terrain places tiles based on how well they match their neighboring tiles. It's a good replacement for '3x3' and '3x3 minimal' from Godot 3, and 'Match sides' and 'Match corners and sides' from Godot 4's built-in terrain system.
* **Match vertices**: This terrain analyses the vertices of each tile and chooses the highest neighboring terrain type (as in, highest in the terrain list, with empty/non-terrain being the highest overall). It's a replacement for '2x2' in Godot 3, or 'Match corners' in Godot 4.
* **Non-modifying**. This terrain type does not look at neighboring tiles and never modifies tiles. It's useful for getting terrain to connect with non-terrain tiles in a smart way, without modifying those tiles.

Along the top, you will find the following buttons:

* Pen, rectangle, and fill tools. These are for drawing in the scene. Right click will erase.
* Change type and change peering connecting types. Note that these are both unselected by default to prevent accidental alterations to the terrain settings. You can unselect them after using them.
* A zoom slider for the tiles.
* A layer selector for the scene. Unfortunately, the layer highlight option is not exposed to GDScript, so that is unavailable.

You may also see a "Clean data" button, which occurs when terrain has data that does not apply to the current tileset shape or offset axis (for example, you set up rectangle terrain then change the tileset to be hexagonal).

### Usage in code

The terrain system is usable via code via the `BetterTerrain` autoload, which the plugin handles. The editor dock is implemented entirely using this class, so it is fully featured.

To edit terrain at runtime, first you must set terrain into cells, and then you must run an update function for the cells to allow it to pick the best tile for each terrain.

To set or get terrain in cells, these functions are available. Terrain types are integer indexes into the list you see in the editor (e.g. the first terrain is 0, the second is 1, etc...)

* `func set_cell(tm: TileMap, layer: int, coord: Vector2i, type: int) -> bool`
* `func set_cells(tm: TileMap, layer: int, coords: Array, type: int) -> bool`
* `func get_cell(tm: TileMap, layer: int, coord: Vector2i) -> int`

Once cell(s) are set, they must be updated. Use one of these functions to run the updates. They also update the neighboring cells, though that can be switched off if desired.

* `func update_terrain_cells(tm: TileMap, layer: int, cells: Array, and_surrounding_cells := true) -> void`
* `func update_terrain_cell(tm: TileMap, layer: int, cell: Vector2i, and_surrounding_cells := true) -> void`
* `func update_terrain_area(tm: TileMap, layer: int, area: Rect2i, and_surrounding_cells := true) -> void`

### Contact

Feel free to report bugs here, or find me (Portponky) on the Godot official discord server. Have fun!
