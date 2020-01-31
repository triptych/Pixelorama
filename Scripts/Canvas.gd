extends Node2D
class_name Canvas

var layers := []
var current_layer_index := 0
var location := Vector2.ZERO
var size := Vector2(64, 64)
var fill_color := Color(0, 0, 0, 0)
var frame := 0 setget frame_changed
var frame_button : VBoxContainer
var frame_texture_rect : TextureRect

var current_pixel := Vector2.ZERO # pretty much same as mouse_pos, but can be accessed externally
var previous_mouse_pos := Vector2.ZERO
var previous_mouse_pos_for_lines := Vector2.ZERO
var can_undo := true
var cursor_inside_canvas := false
var previous_action := "None"
var west_limit := location.x
var east_limit := location.x + size.x
var north_limit := location.y
var south_limit := location.y + size.y
var mouse_inside_canvas := false # used for undo
var sprite_changed_this_frame := false # for optimization purposes
var lighten_darken_pixels := [] # Cleared after mouse release
var is_making_line := false
var made_line := false
var is_making_selection := "None"
var line_2d : Line2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# The sprite itself
	if layers.empty():
		var sprite := Image.new()
		if Global.is_default_image:
			if Global.config_cache.has_section_key("preferences", "default_width"):
				size.x = Global.config_cache.get_value("preferences", "default_width")
			if Global.config_cache.has_section_key("preferences", "default_height"):
				size.y = Global.config_cache.get_value("preferences", "default_height")
			if Global.config_cache.has_section_key("preferences", "default_fill_color"):
				fill_color = Global.config_cache.get_value("preferences", "default_fill_color")
			Global.is_default_image = !Global.is_default_image

		sprite.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		sprite.fill(fill_color)
		sprite.lock()

		var tex := ImageTexture.new()
		tex.create_from_image(sprite, 0)

		# Store [Image, ImageTexture, Layer Name, Visibity boolean, Opacity]
		layers.append([sprite, tex, tr("Layer") + " 0", true, 1])

	generate_layer_panels()

	frame_button = load("res://Prefabs/FrameButton.tscn").instance()
	frame_button.name = "Frame_%s" % frame
	frame_button.get_node("FrameButton").frame = frame
	frame_button.get_node("FrameButton").pressed = true
	frame_button.get_node("FrameID").text = str(frame + 1)
	frame_button.get_node("FrameID").add_color_override("font_color", Color("#3c5d75"))
	Global.frame_container.add_child(frame_button)

	frame_texture_rect = Global.find_node_by_name(frame_button, "FrameTexture")
	frame_texture_rect.texture = layers[0][1] #ImageTexture current_layer_index

	# Only handle camera zoom settings & offset on the first frame
	if Global.canvases[0] == self:
		camera_zoom()

	line_2d = Line2D.new()
	line_2d.width = 0.5
	line_2d.default_color = Color.darkgray
	line_2d.add_point(previous_mouse_pos_for_lines)
	line_2d.add_point(previous_mouse_pos_for_lines)
	add_child(line_2d)

func camera_zoom() -> void:
	# Set camera zoom based on the sprite size
	var bigger = max(size.x, size.y)
	var zoom_max := Vector2(bigger, bigger) * 0.01
	if zoom_max > Vector2.ONE:
		Global.camera.zoom_max = zoom_max
		Global.camera2.zoom_max = zoom_max
		Global.camera_preview.zoom_max = zoom_max
	else:
		Global.camera.zoom_max = Vector2.ONE
		Global.camera2.zoom_max = Vector2.ONE
		Global.camera_preview.zoom_max = Vector2.ONE

	Global.camera.zoom = Vector2(bigger, bigger) * 0.002
	Global.camera2.zoom = Vector2(bigger, bigger) * 0.002
	Global.camera_preview.zoom = Vector2(bigger, bigger) * 0.007
	Global.zoom_level_label.text = str(round(100 / Global.camera.zoom.x)) + " %"

	# Set camera offset to the center of canvas
	Global.camera.offset = size / 2
	Global.camera2.offset = size / 2
	Global.camera_preview.offset = size / 2

func _input(event : InputEvent) -> void:
	# Don't process anything below if the input isn't a mouse event, or Shift/Ctrl.
	# This decreases CPU/GPU usage slightly.
	if not event is InputEventMouse:
		if event is InputEventKey:
			if event.scancode != KEY_SHIFT && event.scancode != KEY_CONTROL:
				return
		else:
			return

	current_pixel = get_local_mouse_position() + location
	if Global.current_frame != frame:
		previous_mouse_pos = current_pixel
		previous_mouse_pos.x = clamp(previous_mouse_pos.x, location.x, location.x + size.x)
		previous_mouse_pos.y = clamp(previous_mouse_pos.y, location.y, location.y + size.y)
		return

	if Global.has_focus:
		update()

	sprite_changed_this_frame = false
	var mouse_pos := current_pixel
	var mouse_pos_floored := mouse_pos.floor()
	var mouse_pos_ceiled := mouse_pos.ceil()
	var mouse_in_canvas := point_in_rectangle(mouse_pos, location, location + size)
	var current_mouse_button := "None"
	var current_action := "None"
	var current_color : Color
	var fill_area := 0 # For the bucket tool
	# For the LightenDarken tool
	var ld := 0
	var ld_amount := 0.1
	var color_picker_for := 0

	west_limit = location.x
	east_limit = location.x + size.x
	north_limit = location.y
	south_limit = location.y + size.y
	if Global.selected_pixels.size() != 0:
		west_limit = max(west_limit, Global.selection_rectangle.polygon[0].x)
		east_limit = min(east_limit, Global.selection_rectangle.polygon[2].x)
		north_limit = max(north_limit, Global.selection_rectangle.polygon[0].y)
		south_limit = min(south_limit, Global.selection_rectangle.polygon[2].y)

	if Input.is_mouse_button_pressed(BUTTON_LEFT):
		current_mouse_button = "left_mouse"
		current_action = Global.current_left_tool
		current_color = Global.left_color_picker.color
		fill_area = Global.left_fill_area
		ld = Global.left_ld
		ld_amount = Global.left_ld_amount
		color_picker_for = Global.left_color_picker_for
	elif Input.is_mouse_button_pressed(BUTTON_RIGHT):
		current_mouse_button = "right_mouse"
		current_action = Global.current_right_tool
		current_color = Global.right_color_picker.color
		fill_area = Global.right_fill_area
		ld = Global.right_ld
		ld_amount = Global.right_ld_amount
		color_picker_for = Global.right_color_picker_for

	if mouse_in_canvas && Global.has_focus:
		Global.cursor_position_label.text = "[%s×%s]    %s, %s" % [size.x, size.y, mouse_pos_floored.x, mouse_pos_floored.y]
		if !cursor_inside_canvas:
			cursor_inside_canvas = true
			Input.set_custom_mouse_cursor(load("res://Assets/Graphics/Cursor.png"), 0, Vector2(15, 15))
			if Global.show_left_tool_icon:
				Global.left_cursor.visible = true
			if Global.show_right_tool_icon:
				Global.right_cursor.visible = true
	else:
		if !Input.is_mouse_button_pressed(BUTTON_LEFT) && !Input.is_mouse_button_pressed(BUTTON_RIGHT):
			if mouse_inside_canvas:
				mouse_inside_canvas = false
		Global.cursor_position_label.text = "[%s×%s]" % [size.x, size.y]
		if cursor_inside_canvas:
			cursor_inside_canvas = false
			Global.left_cursor.visible = false
			Global.right_cursor.visible = false
			Input.set_custom_mouse_cursor(null)

	# Handle Undo/Redo
	var can_handle : bool = mouse_in_canvas && Global.can_draw && Global.has_focus && !made_line
	var mouse_pressed : bool = (Input.is_action_just_pressed("left_mouse") && !Input.is_action_pressed("right_mouse")) || (Input.is_action_just_pressed("right_mouse") && !Input.is_action_pressed("left_mouse"))

	# If we're already pressing a mouse button and we haven't handled undo yet,...
	#. .. it means that the cursor was outside the canvas. Then, ...
	# simulate "just pressed" logic the moment the cursor gets inside the canvas

	# Or, if we're making a line. This is used for handling undo/redo for lines...
	# ...that go outside the canvas
	if Input.is_action_pressed("left_mouse") || Input.is_action_pressed("right_mouse"):
		if (mouse_in_canvas && Global.undos < Global.undo_redo.get_version()) || is_making_line:
			mouse_pressed = true

	if mouse_pressed:
		if can_handle || is_making_line:
			if current_action != "None" && current_action != "ColorPicker":
				if current_action == "RectSelect":
					handle_undo("Rectangle Select")
				else:
					handle_undo("Draw")
	elif (Input.is_action_just_released("left_mouse") && !Input.is_action_pressed("right_mouse")) || (Input.is_action_just_released("right_mouse") && !Input.is_action_pressed("left_mouse")):
		made_line = false
		lighten_darken_pixels.clear()
		if can_handle || Global.undos == Global.undo_redo.get_version():
			if previous_action != "None" && previous_action != "RectSelect" && current_action != "ColorPicker":
				handle_redo("Draw")

	match current_action: # Handle current tool
		"Pencil":
			pencil_and_eraser(mouse_pos, current_color, current_mouse_button)
		"Eraser":
			pencil_and_eraser(mouse_pos, Color(0, 0, 0, 0), current_mouse_button)
		"Bucket":
			if can_handle:
				if fill_area == 0: # Paint the specific area of the same color
					var horizontal_mirror := false
					var vertical_mirror := false
					var mirror_x := east_limit + west_limit - mouse_pos_floored.x - 1
					var mirror_y := south_limit + north_limit - mouse_pos_floored.y - 1
					if current_mouse_button == "left_mouse":
						horizontal_mirror = Global.left_horizontal_mirror
						vertical_mirror = Global.left_vertical_mirror
					elif current_mouse_button == "right_mouse":
						horizontal_mirror = Global.right_horizontal_mirror
						vertical_mirror = Global.right_vertical_mirror

					flood_fill(mouse_pos, layers[current_layer_index][0].get_pixelv(mouse_pos), current_color)
					if horizontal_mirror:
						var pos := Vector2(mirror_x, mouse_pos.y)
						flood_fill(pos, layers[current_layer_index][0].get_pixelv(pos), current_color)
					if vertical_mirror:
						var pos := Vector2(mouse_pos.x, mirror_y)
						flood_fill(pos, layers[current_layer_index][0].get_pixelv(pos), current_color)
					if horizontal_mirror && vertical_mirror:
						var pos := Vector2(mirror_x, mirror_y)
						flood_fill(pos, layers[current_layer_index][0].get_pixelv(pos), current_color)

				else: # Paint all pixels of the same color
					var pixel_color : Color = layers[current_layer_index][0].get_pixelv(mouse_pos)
					for xx in range(west_limit, east_limit):
						for yy in range(north_limit, south_limit):
							var c : Color = layers[current_layer_index][0].get_pixel(xx, yy)
							if c == pixel_color:
								layers[current_layer_index][0].set_pixel(xx, yy, current_color)
					sprite_changed_this_frame = true
		"LightenDarken":
			if can_handle:
				var pixel_color : Color = layers[current_layer_index][0].get_pixelv(mouse_pos)
				var color_changed : Color
				if ld == 0: # Lighten
					color_changed = pixel_color.lightened(ld_amount)
				else: # Darken
					color_changed = pixel_color.darkened(ld_amount)
				pencil_and_eraser(mouse_pos, color_changed, current_mouse_button, current_action)
		"RectSelect":
			# Check SelectionRectangle.gd for more code on Rectangle Selection
			if Global.can_draw && Global.has_focus:
				# If we're creating a new selection
				if Global.selected_pixels.size() == 0 || !point_in_rectangle(mouse_pos_floored, Global.selection_rectangle.polygon[0] - Vector2.ONE, Global.selection_rectangle.polygon[2]):
					if Input.is_action_just_pressed(current_mouse_button):
						Global.selection_rectangle.polygon[0] = mouse_pos_floored
						Global.selection_rectangle.polygon[1] = mouse_pos_floored
						Global.selection_rectangle.polygon[2] = mouse_pos_floored
						Global.selection_rectangle.polygon[3] = mouse_pos_floored
						is_making_selection = current_mouse_button
						Global.selected_pixels.clear()
					else:
						if is_making_selection != "None": # If we're making a new selection...
							var start_pos = Global.selection_rectangle.polygon[0]
							if start_pos != mouse_pos_floored:
								var end_pos := Vector2(mouse_pos_ceiled.x, mouse_pos_ceiled.y)
								if mouse_pos.x < start_pos.x:
									end_pos.x = mouse_pos_ceiled.x - 1
								if mouse_pos.y < start_pos.y:
									end_pos.y = mouse_pos_ceiled.y - 1
								Global.selection_rectangle.polygon[1] = Vector2(end_pos.x, start_pos.y)
								Global.selection_rectangle.polygon[2] = end_pos
								Global.selection_rectangle.polygon[3] = Vector2(start_pos.x, end_pos.y)
		"ColorPicker":
			if can_handle:
				var pixel_color : Color = layers[current_layer_index][0].get_pixelv(mouse_pos)
				if color_picker_for == 0: # Pick for the left color
					Global.left_color_picker.color = pixel_color
					Global.update_left_custom_brush()
				elif color_picker_for == 1: # Pick for the left color
					Global.right_color_picker.color = pixel_color
					Global.update_right_custom_brush()

	if Global.can_draw && Global.has_focus && Input.is_action_just_pressed("shift") && (["Pencil", "Eraser", "LightenDarken"].has(Global.current_left_tool) || ["Pencil", "Eraser", "LightenDarken"].has(Global.current_right_tool)):
		is_making_line = true
		line_2d.set_point_position(0, previous_mouse_pos_for_lines)
	elif Input.is_action_just_released("shift"):
		is_making_line = false
		line_2d.set_point_position(1, line_2d.points[0])

	if is_making_line:
		var point0 : Vector2 = line_2d.points[0]
		var angle := stepify(rad2deg(mouse_pos.angle_to_point(point0)), 0.01)
		if Input.is_action_pressed("ctrl"):
			angle = round(angle / 15) * 15
			var distance : float = point0.distance_to(mouse_pos)
			line_2d.set_point_position(1, point0 + Vector2.RIGHT.rotated(deg2rad(angle)) * distance)
		else:
			line_2d.set_point_position(1, mouse_pos)

		if angle < 0:
			angle = 360 + angle
		Global.cursor_position_label.text += "    %s°" % str(angle)

	if is_making_selection != "None": # If we're making a selection
		if Input.is_action_just_released(is_making_selection): # Finish selection when button is released
			var start_pos = Global.selection_rectangle.polygon[0]
			var end_pos = Global.selection_rectangle.polygon[2]
			if start_pos.x > end_pos.x:
				var temp = end_pos.x
				end_pos.x = start_pos.x
				start_pos.x = temp

			if start_pos.y > end_pos.y:
				var temp = end_pos.y
				end_pos.y = start_pos.y
				start_pos.y = temp

			Global.selection_rectangle.polygon[0] = start_pos
			Global.selection_rectangle.polygon[1] = Vector2(end_pos.x, start_pos.y)
			Global.selection_rectangle.polygon[2] = end_pos
			Global.selection_rectangle.polygon[3] = Vector2(start_pos.x, end_pos.y)

			for xx in range(start_pos.x, end_pos.x):
				for yy in range(start_pos.y, end_pos.y):
					Global.selected_pixels.append(Vector2(xx, yy))
			is_making_selection = "None"
			handle_redo("Rectangle Select")

	previous_action = current_action
	previous_mouse_pos = current_pixel
	previous_mouse_pos.x = clamp(previous_mouse_pos.x, location.x, location.x + size.x)
	previous_mouse_pos.y = clamp(previous_mouse_pos.y, location.y, location.y + size.y)
	if sprite_changed_this_frame:
		update_texture(current_layer_index, (Input.is_action_just_released("left_mouse") || Input.is_action_just_released("right_mouse")))

func handle_undo(action : String) -> void:
	if !can_undo:
		return
	var canvases := []
	var layer_index := -1
	if Global.animation_timer.is_stopped(): # if we're not animating, store only the current canvas
		canvases = [self]
		layer_index = current_layer_index
	else: # If we're animating, store all canvases
		canvases = Global.canvases
	Global.undos += 1
	Global.undo_redo.create_action(action)
	for c in canvases:
		# I'm not sure why I have to unlock it, but...
		# ...if I don't, it doesn't work properly
		c.layers[c.current_layer_index][0].unlock()
		var data = c.layers[c.current_layer_index][0].data
		c.layers[c.current_layer_index][0].lock()
		Global.undo_redo.add_undo_property(c.layers[c.current_layer_index][0], "data", data)
	if action == "Rectangle Select":
		var selected_pixels = Global.selected_pixels.duplicate()
		Global.undo_redo.add_undo_property(Global.selection_rectangle, "polygon", Global.selection_rectangle.polygon)
		Global.undo_redo.add_undo_property(Global, "selected_pixels", selected_pixels)
	Global.undo_redo.add_undo_method(Global, "undo", canvases, layer_index)

	can_undo = false

func handle_redo(action : String) -> void:
	if Global.undos < Global.undo_redo.get_version():
		return
	var canvases := []
	var layer_index := -1
	if Global.animation_timer.is_stopped():
		canvases = [self]
		layer_index = current_layer_index
	else:
		canvases = Global.canvases
	for c in canvases:
		Global.undo_redo.add_do_property(c.layers[c.current_layer_index][0], "data", c.layers[c.current_layer_index][0].data)
	if action == "Rectangle Select":
		Global.undo_redo.add_do_property(Global.selection_rectangle, "polygon", Global.selection_rectangle.polygon)
		Global.undo_redo.add_do_property(Global, "selected_pixels", Global.selected_pixels)
	Global.undo_redo.add_do_method(Global, "redo", canvases, layer_index)
	Global.undo_redo.commit_action()

	can_undo = true

func update_texture(layer_index : int, update_frame_tex := true) -> void:
	layers[layer_index][1].create_from_image(layers[layer_index][0], 0)
	var layer_container := get_layer_container(layer_index)
	if layer_container:
		layer_container.get_child(1).get_child(0).texture = layers[layer_index][1]

	if update_frame_tex:
		# This code is used to update the texture in the animation timeline frame button
		# but blend_rect causes major performance issues on large images
		var whole_image := Image.new()
		whole_image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		for layer in layers:
			whole_image.blend_rect(layer[0], Rect2(position, size), Vector2.ZERO)
			layer[0].lock()
		var whole_image_texture := ImageTexture.new()
		whole_image_texture.create_from_image(whole_image, 0)
		frame_texture_rect.texture = whole_image_texture

func frame_changed(value : int) -> void:
	frame = value
	if frame_button:
		frame_button.get_node("FrameButton").frame = frame
		frame_button.get_node("FrameID").text = str(frame + 1)

func get_layer_container(layer_index : int) -> LayerContainer:
	for container in Global.vbox_layer_container.get_children():
		if container is LayerContainer && container.i == layer_index:
			return container
	return null

func _draw() -> void:
	draw_texture_rect(Global.transparent_background, Rect2(location, size), true) #Draw transparent background
	#Onion Skinning
	#Past
	if Global.onion_skinning_past_rate > 0:
		var color : Color
		if Global.onion_skinning_blue_red:
			color = Color.blue
		else:
			color = Color.white
		for i in range(1, Global.onion_skinning_past_rate + 1):
			if Global.current_frame >= i:
				for texture in Global.canvases[Global.current_frame - i].layers:
					color.a = 0.6/i
					draw_texture(texture[1], location, color)

	#Future
	if Global.onion_skinning_future_rate > 0:
		var color : Color
		if Global.onion_skinning_blue_red:
			color = Color.red
		else:
			color = Color.white
		for i in range(1, Global.onion_skinning_future_rate + 1):
			if Global.current_frame < Global.canvases.size() - i:
				for texture in Global.canvases[Global.current_frame + i].layers:
					color.a = 0.6/i
					draw_texture(texture[1], location, color)

	#Draw current frame layers
	for texture in layers:
		var modulate_color := Color(1, 1, 1, texture[4])
		if texture[3]: #if it's visible
			draw_texture(texture[1], location, modulate_color)

			if Global.tile_mode:
				draw_texture(texture[1], Vector2(location.x, location.y + size.y), modulate_color) #Down
				draw_texture(texture[1], Vector2(location.x - size.x, location.y + size.y), modulate_color) #Down Left
				draw_texture(texture[1], Vector2(location.x - size.x, location.y), modulate_color) #Left
				draw_texture(texture[1], location - size, modulate_color) #Up left
				draw_texture(texture[1], Vector2(location.x, location.y - size.y), modulate_color) #Up
				draw_texture(texture[1], Vector2(location.x + size.x, location.y - size.y), modulate_color) #Up right
				draw_texture(texture[1], Vector2(location.x + size.x, location.y), modulate_color) #Right
				draw_texture(texture[1], location + size, modulate_color) #Down right

	#Idea taken from flurick (on GitHub)
	if Global.draw_grid:
		for x in range(0, size.x, Global.grid_width):
			draw_line(Vector2(x, location.y), Vector2(x, size.y), Global.grid_color, true)
		for y in range(0, size.y, Global.grid_height):
			draw_line(Vector2(location.x, y), Vector2(size.x, y), Global.grid_color, true)

	#Draw rectangle to indicate the pixel currently being hovered on
	var mouse_pos := current_pixel
	if point_in_rectangle(mouse_pos, location, location + size):
		mouse_pos = mouse_pos.floor()
		if Global.left_square_indicator_visible && Global.can_draw:
			if Global.current_left_brush_type == Global.BRUSH_TYPES.PIXEL || Global.current_left_tool == "LightenDarken":
				if Global.current_left_tool == "Pencil" || Global.current_left_tool == "Eraser" || Global.current_left_tool == "LightenDarken":
					var start_pos_x = mouse_pos.x - (Global.left_brush_size >> 1)
					var start_pos_y = mouse_pos.y - (Global.left_brush_size >> 1)
					draw_rect(Rect2(start_pos_x, start_pos_y, Global.left_brush_size, Global.left_brush_size), Color.blue, false)
			elif Global.current_left_brush_type == Global.BRUSH_TYPES.CIRCLE || Global.current_left_brush_type == Global.BRUSH_TYPES.FILLED_CIRCLE:
				if Global.current_left_tool == "Pencil" || Global.current_left_tool == "Eraser":
					draw_set_transform(mouse_pos, rotation, scale)
					for rect in Global.left_circle_points:
						draw_rect(Rect2(rect, Vector2.ONE), Color.blue, false)
					draw_set_transform(position, rotation, scale)
			else:
				if Global.current_left_tool == "Pencil" || Global.current_left_tool == "Eraser":
					var custom_brush_size = Global.custom_left_brush_image.get_size()  - Vector2.ONE
					var dst := rectangle_center(mouse_pos, custom_brush_size)
					draw_texture(Global.custom_left_brush_texture, dst)

		if Global.right_square_indicator_visible && Global.can_draw:
			if Global.current_right_brush_type == Global.BRUSH_TYPES.PIXEL || Global.current_right_tool == "LightenDarken":
				if Global.current_right_tool == "Pencil" || Global.current_right_tool == "Eraser" || Global.current_right_tool == "LightenDarken":
					var start_pos_x = mouse_pos.x - (Global.right_brush_size >> 1)
					var start_pos_y = mouse_pos.y - (Global.right_brush_size >> 1)
					draw_rect(Rect2(start_pos_x, start_pos_y, Global.right_brush_size, Global.right_brush_size), Color.red, false)
			elif Global.current_right_brush_type == Global.BRUSH_TYPES.CIRCLE || Global.current_right_brush_type == Global.BRUSH_TYPES.FILLED_CIRCLE:
				if Global.current_right_tool == "Pencil" || Global.current_right_tool == "Eraser":
					draw_set_transform(mouse_pos, rotation, scale)
					for rect in Global.right_circle_points:
						draw_rect(Rect2(rect, Vector2.ONE), Color.red, false)
					draw_set_transform(position, rotation, scale)
			else:
				if Global.current_right_tool == "Pencil" || Global.current_right_tool == "Eraser":
					var custom_brush_size = Global.custom_right_brush_image.get_size()  - Vector2.ONE
					var dst := rectangle_center(mouse_pos, custom_brush_size)
					draw_texture(Global.custom_right_brush_texture, dst)

func generate_layer_panels() -> void:
	for child in Global.vbox_layer_container.get_children():
		if child is LayerContainer:
			child.queue_free()

	current_layer_index = layers.size() - 1
	if layers.size() == 1:
		Global.remove_layer_button.disabled = true
		Global.remove_layer_button.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
	else:
		Global.remove_layer_button.disabled = false
		Global.remove_layer_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	for i in range(layers.size() -1, -1, -1):
		var layer_container = load("res://Prefabs/LayerContainer.tscn").instance()
		if !layers[i][2]:
			layers[i][2] = tr("Layer") + " %s" % i
		layer_container.i = i
		layer_container.get_child(1).get_child(0).texture = layers[i][1]
		layer_container.get_child(1).get_child(1).text = layers[i][2]
		layer_container.get_child(1).get_child(2).text = layers[i][2]
		Global.vbox_layer_container.add_child(layer_container)

func pencil_and_eraser(mouse_pos : Vector2, color : Color, current_mouse_button : String, current_action := "None") -> void:
	if made_line:
		return
	if is_making_line:
		fill_gaps(line_2d.points[1], previous_mouse_pos_for_lines, color, current_mouse_button, current_action)
		draw_pixel(line_2d.points[1], color, current_mouse_button, current_action)
		made_line = true
	else:
		if point_in_rectangle(mouse_pos, location, location + size):
			mouse_inside_canvas = true
			# Draw
			draw_pixel(mouse_pos, color, current_mouse_button, current_action)
			fill_gaps(mouse_pos, previous_mouse_pos, color, current_mouse_button, current_action) #Fill the gaps
		# If mouse is not inside bounds but it used to be, fill the gaps
		elif point_in_rectangle(previous_mouse_pos, location, location + size):
			fill_gaps(mouse_pos, previous_mouse_pos, color, current_mouse_button, current_action)

func draw_pixel(pos : Vector2, color : Color, current_mouse_button : String, current_action := "None") -> void:
	if Global.can_draw && Global.has_focus:
		var brush_size := 1
		var brush_type = Global.BRUSH_TYPES.PIXEL
		var brush_index := -1
		var custom_brush_image : Image
		var horizontal_mirror := false
		var vertical_mirror := false
		var ld := 0
		var ld_amount := 0.1
		if current_mouse_button == "left_mouse":
			brush_size = Global.left_brush_size
			brush_type = Global.current_left_brush_type
			brush_index = Global.custom_left_brush_index
			if brush_type != Global.BRUSH_TYPES.RANDOM_FILE:
				custom_brush_image = Global.custom_left_brush_image
			else: # Handle random brush
				var brush_button = Global.file_brush_container.get_child(brush_index + 3)
				var random_index = randi() % brush_button.random_brushes.size()
				custom_brush_image = Image.new()
				custom_brush_image.copy_from(brush_button.random_brushes[random_index])
				var custom_brush_size = custom_brush_image.get_size()
				custom_brush_image.resize(custom_brush_size.x * brush_size, custom_brush_size.y * brush_size, Image.INTERPOLATE_NEAREST)
				custom_brush_image = Global.blend_image_with_color(custom_brush_image, color, Global.left_interpolate_spinbox.value / 100)
				custom_brush_image.lock()

			horizontal_mirror = Global.left_horizontal_mirror
			vertical_mirror = Global.left_vertical_mirror
			ld = Global.left_ld
			ld_amount = Global.left_ld_amount
		elif current_mouse_button == "right_mouse":
			brush_size = Global.right_brush_size
			brush_type = Global.current_right_brush_type
			brush_index = Global.custom_right_brush_index
			if brush_type != Global.BRUSH_TYPES.RANDOM_FILE:
				custom_brush_image = Global.custom_right_brush_image
			else: # Handle random brush
				var brush_button = Global.file_brush_container.get_child(brush_index + 3)
				var random_index = randi() % brush_button.random_brushes.size()
				custom_brush_image = Image.new()
				custom_brush_image.copy_from(brush_button.random_brushes[random_index])
				var custom_brush_size = custom_brush_image.get_size()
				custom_brush_image.resize(custom_brush_size.x * brush_size, custom_brush_size.y * brush_size, Image.INTERPOLATE_NEAREST)
				custom_brush_image = Global.blend_image_with_color(custom_brush_image, color, Global.right_interpolate_spinbox.value / 100)
				custom_brush_image.lock()

			horizontal_mirror = Global.right_horizontal_mirror
			vertical_mirror = Global.right_vertical_mirror
			ld = Global.right_ld
			ld_amount = Global.right_ld_amount

		var start_pos_x
		var start_pos_y
		var end_pos_x
		var end_pos_y

		if brush_type == Global.BRUSH_TYPES.PIXEL || current_action == "LightenDarken":
			start_pos_x = pos.x - (brush_size >> 1)
			start_pos_y = pos.y - (brush_size >> 1)
			end_pos_x = start_pos_x + brush_size
			end_pos_y = start_pos_y + brush_size
			for cur_pos_x in range(start_pos_x, end_pos_x):
				for cur_pos_y in range(start_pos_y, end_pos_y):
					if point_in_rectangle(Vector2(cur_pos_x, cur_pos_y), Vector2(west_limit - 1, north_limit - 1), Vector2(east_limit, south_limit)):
						var pos_floored := Vector2(cur_pos_x, cur_pos_y).floor()
						# Don't draw the same pixel over and over and don't re-lighten/darken it
						var current_pixel_color : Color = layers[current_layer_index][0].get_pixel(cur_pos_x, cur_pos_y)
						if current_pixel_color != color && !(pos_floored in lighten_darken_pixels):
							if current_action == "LightenDarken":
								color = current_pixel_color
								if color.a > 0:
									if ld == 0: # Lighten
										color = current_pixel_color.lightened(ld_amount)
									else: # Darken
										color = current_pixel_color.darkened(ld_amount)
								lighten_darken_pixels.append(pos_floored)

							layers[current_layer_index][0].set_pixel(cur_pos_x, cur_pos_y, color)
							sprite_changed_this_frame = true

							# Handle mirroring
							var mirror_x := east_limit + west_limit - cur_pos_x - 1
							var mirror_y := south_limit + north_limit - cur_pos_y - 1
							if horizontal_mirror:
								current_pixel_color = layers[current_layer_index][0].get_pixel(mirror_x, cur_pos_y)
								if current_pixel_color != color: # don't draw the same pixel over and over
									if current_action == "LightenDarken":
										if ld == 0: # Lighten
											color = current_pixel_color.lightened(ld_amount)
										else:
											color = current_pixel_color.darkened(ld_amount)
										lighten_darken_pixels.append(pos_floored)

									layers[current_layer_index][0].set_pixel(mirror_x, cur_pos_y, color)
									sprite_changed_this_frame = true
							if vertical_mirror:
								current_pixel_color = layers[current_layer_index][0].get_pixel(cur_pos_x, mirror_y)
								if current_pixel_color != color: # don't draw the same pixel over and over
									if current_action == "LightenDarken":
										if ld == 0: # Lighten
											color = current_pixel_color.lightened(ld_amount)
										else:
											color = current_pixel_color.darkened(ld_amount)
										lighten_darken_pixels.append(pos_floored)

									layers[current_layer_index][0].set_pixel(cur_pos_x, mirror_y, color)
									sprite_changed_this_frame = true
							if horizontal_mirror && vertical_mirror:
								current_pixel_color = layers[current_layer_index][0].get_pixel(mirror_x, mirror_y)
								if current_pixel_color != color: # don't draw the same pixel over and over
									if current_action == "LightenDarken":
										if ld == 0: # Lighten
											color = current_pixel_color.lightened(ld_amount)
										else:
											color = current_pixel_color.darkened(ld_amount)
										lighten_darken_pixels.append(pos_floored)

									layers[current_layer_index][0].set_pixel(mirror_x, mirror_y, color)
									sprite_changed_this_frame = true

		elif brush_type == Global.BRUSH_TYPES.CIRCLE || brush_type == Global.BRUSH_TYPES.FILLED_CIRCLE:
			plot_circle(layers[current_layer_index][0], pos.x, pos.y, brush_size, color, brush_type == Global.BRUSH_TYPES.FILLED_CIRCLE)

			# Handle mirroring
			var mirror_x := east_limit + west_limit - pos.x
			var mirror_y := south_limit + north_limit - pos.y
			if horizontal_mirror:
				plot_circle(layers[current_layer_index][0], mirror_x, pos.y, brush_size, color, brush_type == Global.BRUSH_TYPES.FILLED_CIRCLE)
			if vertical_mirror:
				plot_circle(layers[current_layer_index][0], pos.x, mirror_y, brush_size, color, brush_type == Global.BRUSH_TYPES.FILLED_CIRCLE)
			if horizontal_mirror && vertical_mirror:
				plot_circle(layers[current_layer_index][0], mirror_x, mirror_y, brush_size, color, brush_type == Global.BRUSH_TYPES.FILLED_CIRCLE)

			sprite_changed_this_frame = true

		else:
			var custom_brush_size := custom_brush_image.get_size() - Vector2.ONE
			pos = pos.floor()
			var dst := rectangle_center(pos, custom_brush_size)
			var src_rect := Rect2(Vector2.ZERO, custom_brush_size + Vector2.ONE)
			# Rectangle with the same size as the brush, but at cursor's position
			var pos_rect := Rect2(dst, custom_brush_size + Vector2.ONE)

			# The selection rectangle
			# If there's no rectangle, the whole canvas is considered a selection
			var selection_rect := Rect2()
			selection_rect.position = Vector2(west_limit, north_limit)
			selection_rect.end = Vector2(east_limit, south_limit)
			# Intersection of the position rectangle and selection
			var pos_rect_clipped := pos_rect.clip(selection_rect)
			# If the size is 0, that means that the brush wasn't positioned inside the selection
			if pos_rect_clipped.size == Vector2.ZERO:
				return

			# Re-position src_rect and dst based on the clipped position
			var pos_difference := (pos_rect.position - pos_rect_clipped.position).abs()
			# Obviously, if pos_rect and pos_rect_clipped are the same, pos_difference is Vector2.ZERO
			src_rect.position = pos_difference
			dst += pos_difference
			src_rect.end -= pos_rect.end - pos_rect_clipped.end
			# If the selection rectangle is smaller than the brush, ...
			# ... make sure pixels aren't being drawn outside the selection by adjusting src_rect's size
			src_rect.size.x = min(src_rect.size.x, selection_rect.size.x)
			src_rect.size.y = min(src_rect.size.y, selection_rect.size.y)

			# Handle mirroring
			var mirror_x := east_limit + west_limit - pos.x - (pos.x - dst.x)
			var mirror_y := south_limit + north_limit - pos.y - (pos.y - dst.y)
			if int(pos_rect_clipped.size.x) % 2 != 0:
				mirror_x -= 1
			if int(pos_rect_clipped.size.y) % 2 != 0:
				mirror_y -= 1
			# Use custom blend function cause of godot's issue  #31124
			if color.a > 0: # If it's the pencil
				blend_rect(layers[current_layer_index][0], custom_brush_image, src_rect, dst)
				if horizontal_mirror:
					blend_rect(layers[current_layer_index][0], custom_brush_image, src_rect, Vector2(mirror_x, dst.y))
				if vertical_mirror:
					blend_rect(layers[current_layer_index][0], custom_brush_image, src_rect, Vector2(dst.x, mirror_y))
				if horizontal_mirror && vertical_mirror:
					blend_rect(layers[current_layer_index][0], custom_brush_image, src_rect, Vector2(mirror_x, mirror_y))

			else: # if it's transparent - if it's the eraser
				var custom_brush := Image.new()
				custom_brush.copy_from(Global.custom_brushes[brush_index])
				custom_brush_size = custom_brush.get_size()
				custom_brush.resize(custom_brush_size.x * brush_size, custom_brush_size.y * brush_size, Image.INTERPOLATE_NEAREST)
				var custom_brush_blended = Global.blend_image_with_color(custom_brush, color, 1)

				layers[current_layer_index][0].blit_rect_mask(custom_brush_blended, custom_brush, src_rect, dst)
				if horizontal_mirror:
					layers[current_layer_index][0].blit_rect_mask(custom_brush_blended, custom_brush, src_rect, Vector2(mirror_x, dst.y))
				if vertical_mirror:
					layers[current_layer_index][0].blit_rect_mask(custom_brush_blended, custom_brush, src_rect, Vector2(dst.x, mirror_y))
				if horizontal_mirror && vertical_mirror:
					layers[current_layer_index][0].blit_rect_mask(custom_brush_blended, custom_brush, src_rect, Vector2(mirror_x, mirror_y))

			layers[current_layer_index][0].lock()
			sprite_changed_this_frame = true

		previous_mouse_pos_for_lines = pos.floor() + Vector2(0.5, 0.5)
		previous_mouse_pos_for_lines.x = clamp(previous_mouse_pos_for_lines.x, location.x, location.x + size.x)
		previous_mouse_pos_for_lines.y = clamp(previous_mouse_pos_for_lines.y, location.y, location.y + size.y)
		if is_making_line:
			line_2d.set_point_position(0, previous_mouse_pos_for_lines)

# Bresenham's Algorithm
# Thanks to https://godotengine.org/qa/35276/tile-based-line-drawing-algorithm-efficiency
func fill_gaps(mouse_pos : Vector2, prev_mouse_pos : Vector2, color : Color, current_mouse_button : String, current_action := "None") -> void:
	var previous_mouse_pos_floored = prev_mouse_pos.floor()
	var mouse_pos_floored = mouse_pos.floor()
	mouse_pos_floored.x = clamp(mouse_pos_floored.x, location.x - 1, location.x + size.x)
	mouse_pos_floored.y = clamp(mouse_pos_floored.y, location.y - 1, location.y + size.y)
	var dx := int(abs(mouse_pos_floored.x - previous_mouse_pos_floored.x))
	var dy := int(-abs(mouse_pos_floored.y - previous_mouse_pos_floored.y))
	var err := dx + dy
	var e2 := err << 1 #err * 2
	var sx = 1 if previous_mouse_pos_floored.x < mouse_pos_floored.x else -1
	var sy = 1 if previous_mouse_pos_floored.y < mouse_pos_floored.y else -1
	var x = previous_mouse_pos_floored.x
	var y = previous_mouse_pos_floored.y
	while !(x == mouse_pos_floored.x && y == mouse_pos_floored.y):
		draw_pixel(Vector2(x, y), color, current_mouse_button, current_action)
		e2 = err << 1
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

# Thanks to https://en.wikipedia.org/wiki/Flood_fill
func flood_fill(pos : Vector2, target_color : Color, replace_color : Color) -> void:
	pos = pos.floor()
	var pixel = layers[current_layer_index][0].get_pixelv(pos)
	if target_color == replace_color:
		return
	elif pixel != target_color:
		return
	else:

		if !point_in_rectangle(pos, Vector2(west_limit - 1, north_limit - 1), Vector2(east_limit, south_limit)):
			return

		var q = [pos]
		for n in q:
			# If the difference in colors is very small, break the loop (thanks @azagaya on GitHub!)
			if target_color == replace_color:
				break
			var west : Vector2 = n
			var east : Vector2 = n
			while west.x >= west_limit && layers[current_layer_index][0].get_pixelv(west) == target_color:
				west += Vector2.LEFT
			while east.x < east_limit && layers[current_layer_index][0].get_pixelv(east) == target_color:
				east += Vector2.RIGHT
			for px in range(west.x + 1, east.x):
				var p := Vector2(px, n.y)
				# Draw
				layers[current_layer_index][0].set_pixelv(p, replace_color)
				replace_color = layers[current_layer_index][0].get_pixelv(p)
				var north := p + Vector2.UP
				var south := p + Vector2.DOWN
				if north.y >= north_limit && layers[current_layer_index][0].get_pixelv(north) == target_color:
					q.append(north)
				if south.y < south_limit && layers[current_layer_index][0].get_pixelv(south) == target_color:
					q.append(south)
		sprite_changed_this_frame = true

# Algorithm based on http://members.chello.at/easyfilter/bresenham.html
func plot_circle(sprite : Image, xm : int, ym : int, r : int, color : Color, fill := false) -> void:
	var radius := r # Used later for filling
	var x := -r
	var y := 0
	var err := 2 - r * 2 # II. Quadrant
	while x < 0:
		var quadrant_1 := Vector2(xm - x, ym + y)
		var quadrant_2 := Vector2(xm - y, ym - x)
		var quadrant_3 := Vector2(xm + x, ym - y)
		var quadrant_4 := Vector2(xm + y, ym + x)
		if point_in_rectangle(quadrant_1, Vector2(west_limit - 1, north_limit - 1), Vector2(east_limit, south_limit)):
			sprite.set_pixelv(quadrant_1, color)
		if point_in_rectangle(quadrant_2, Vector2(west_limit - 1, north_limit - 1), Vector2(east_limit, south_limit)):
			sprite.set_pixelv(quadrant_2, color)
		if point_in_rectangle(quadrant_3, Vector2(west_limit - 1, north_limit - 1), Vector2(east_limit, south_limit)):
			sprite.set_pixelv(quadrant_3, color)
		if point_in_rectangle(quadrant_4, Vector2(west_limit - 1, north_limit - 1), Vector2(east_limit, south_limit)):
			sprite.set_pixelv(quadrant_4, color)
		r = err
		if r <= y:
			y += 1
			err += y * 2 + 1
		if r > x || err > y:
			x += 1
			err += x * 2 + 1

	if fill:
		for j in range (-radius, radius + 1):
			for i in range (-radius, radius + 1):
				if i * i + j * j <= radius * radius:
					var draw_pos := Vector2(i + xm, j + ym)
					if point_in_rectangle(draw_pos, Vector2(west_limit - 1, north_limit - 1), Vector2(east_limit, south_limit)):
						sprite.set_pixelv(draw_pos, color)

# Checks if a point is inside a rectangle
func point_in_rectangle(p : Vector2, coord1 : Vector2, coord2 : Vector2) -> bool:
	return p.x > coord1.x && p.y > coord1.y && p.x < coord2.x && p.y < coord2.y

# Returns the position in the middle of a rectangle
func rectangle_center(rect_position : Vector2, rect_size : Vector2) -> Vector2:
	return (rect_position - rect_size / 2).floor()

# Custom blend rect function, needed because Godot's issue #31124
func blend_rect(bg : Image, brush : Image, src_rect : Rect2, dst : Vector2) -> void:
	var brush_size := brush.get_size()
	var clipped_src_rect := Rect2(Vector2.ZERO, brush_size).clip(src_rect)
	if clipped_src_rect.size.x <= 0 || clipped_src_rect.size.y <= 0:
		return
	var src_underscan := Vector2(min(0, src_rect.position.x), min(0, src_rect.position.y))
	var dest_rect := Rect2(0, 0, bg.get_width(), bg.get_height()).clip(Rect2(dst - src_underscan, clipped_src_rect.size))

	for x in range(0, dest_rect.size.x):
		for y in range(0, dest_rect.size.y):
			var src_x := clipped_src_rect.position.x + x;
			var src_y := clipped_src_rect.position.y + y;

			var dst_x := dest_rect.position.x + x;
			var dst_y := dest_rect.position.y + y;

			var out_color := Color()
			var brush_color := brush.get_pixel(src_x, src_y)
			var bg_color := bg.get_pixel(dst_x, dst_y)
			out_color.a = brush_color.a + bg_color.a * (1 - brush_color.a)
			# Blend the colors
			if out_color.a != 0:
				out_color.r = (brush_color.r * brush_color.a + bg_color.r * bg_color.a * (1 - brush_color.a)) / out_color.a
				out_color.g = (brush_color.g * brush_color.a + bg_color.g * bg_color.a * (1 - brush_color.a)) / out_color.a
				out_color.b = (brush_color.b * brush_color.a + bg_color.b * bg_color.a * (1 - brush_color.a)) / out_color.a
				bg.set_pixel(dst_x, dst_y, out_color)
