extends Node

func import_brushes(path : String) -> void:
	var brushes_dir := Directory.new()
	brushes_dir.open(".")
	if !brushes_dir.dir_exists(path):
		brushes_dir.make_dir(path)

	var subdirectories := find_brushes(brushes_dir, path)
	for subdir_str in subdirectories:
		var subdir := Directory.new()
		find_brushes(subdir, "%s/%s" % [path, subdir_str])

	Global.brushes_from_files = Global.custom_brushes.size()

func find_brushes(brushes_dir : Directory, path : String) -> Array:
	var subdirectories := []
	var found_random_brush := 0
	brushes_dir.open(path)
	brushes_dir.list_dir_begin(true)
	var file := brushes_dir.get_next()
	while file != "":
		if file.get_extension().to_upper() == "PNG":
			var image := Image.new()
			var err := image.load(path.plus_file(file))
			if err == OK:
				if "%" in file:
					if found_random_brush == 0:
						found_random_brush = Global.file_brush_container.get_child_count()
						image.convert(Image.FORMAT_RGBA8)
						Global.custom_brushes.append(image)
						Global.create_brush_button(image, Global.BRUSH_TYPES.RANDOM_FILE, file.trim_suffix(".png"))
					else:
						var brush_button = Global.file_brush_container.get_child(found_random_brush)
						brush_button.random_brushes.append(image)
				else:
					image.convert(Image.FORMAT_RGBA8)
					Global.custom_brushes.append(image)
					Global.create_brush_button(image, Global.BRUSH_TYPES.FILE, file.trim_suffix(".png"))
		elif file.get_extension() == "": # Probably a directory
			var subdir := "./%s" % [file]
			if brushes_dir.dir_exists(subdir): # If it's an actual directory
				subdirectories.append(subdir)

		file = brushes_dir.get_next()
	brushes_dir.list_dir_end()
	return subdirectories

func import_gpl(path : String) -> Palette:
	var result : Palette = null
	var file = File.new()
	if file.file_exists(path):
		file.open(path, File.READ)
		var text = file.get_as_text()
		var lines = text.split('\n')
		var line_number := 0
		var comments := ""
		for line in lines:
			# Check if valid Gimp Palette Library file
			if line_number == 0:
				if line != "GIMP Palette":
					break
				else:
					result = Palette.new()
					var name_start = path.find_last('/') + 1
					var name_end = path.find_last('.')
					if name_end > name_start:
						result.name = path.substr(name_start, name_end - name_start)

			# Comments
			if line.begins_with('#'):
				comments += line.trim_prefix('#') + '\n'
				pass
			elif line_number > 0 && line.length() >= 12:
				line = line.replace("\t", " ")
				var color_data : PoolStringArray = line.split(" ", false, 4)
				var red : float = color_data[0].to_float() / 255.0
				var green : float = color_data[1].to_float() / 255.0
				var blue : float = color_data[2].to_float() / 255.0
				var color = Color(red, green, blue)
				result.add_color(color, color_data[3])
			line_number += 1

		if result:
			result.comments = comments
		file.close()

	return result
