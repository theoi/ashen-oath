extends SceneTree
## Builds ui/theme/ashen_theme.tres, the project-wide UI theme (ember and ash palette).
##
##   godot --headless --path . -s "$PWD/tools/gen_theme.gd"
##
## Colors live in ui/theme/palette.gd so HUD code can share them. Edit either file and rerun.

const OUT := "res://ui/theme/ashen_theme.tres"


func _init() -> void:
	var p: GDScript = load("res://ui/theme/palette.gd")
	var body: FontFile = load("res://assets/alegreya-sans-font/AlegreyaSans-Regular.ttf")
	var body_bold: FontFile = load("res://assets/alegreya-sans-font/AlegreyaSans-Bold.ttf")
	var cinzel: FontFile = load("res://assets/cinzel-font/Cinzel.ttf")
	var display := _weight(cinzel, 600)
	var display_heavy := _weight(cinzel, 800)

	var theme := Theme.new()
	theme.default_font = body
	theme.default_font_size = 22

	theme.set_color("font_color", "Label", p.BONE)
	theme.set_color("font_outline_color", "Label", p.SHADOW)

	_variation(theme, "TitleLabel", "Label", display_heavy, 96, p.BONE, 10)
	_variation(theme, "HeaderLabel", "Label", display, 40, p.EMBER, 6)
	_variation(theme, "SubheaderLabel", "Label", display, 26, p.BONE, 4)
	_variation(theme, "BodyLabel", "Label", body, 22, p.BONE, 0)
	_variation(theme, "StrongLabel", "Label", body_bold, 22, p.BONE, 0)
	_variation(theme, "SubtleLabel", "Label", body, 19, p.ASH_TEXT, 0)
	_variation(theme, "HudNumberLabel", "Label", body_bold, 26, p.BONE, 5)

	# Buttons: dark slabs with an ember edge when focused or hovered.
	theme.set_font("font", "Button", display)
	theme.set_font_size("font_size", "Button", 24)
	theme.set_color("font_color", "Button", p.BONE)
	theme.set_color("font_hover_color", "Button", p.EMBER_BRIGHT)
	theme.set_color("font_focus_color", "Button", p.EMBER_BRIGHT)
	theme.set_color("font_hover_pressed_color", "Button", p.EMBER_BRIGHT)
	theme.set_color("font_pressed_color", "Button", p.EMBER)
	theme.set_color("font_disabled_color", "Button", p.ASH_TEXT.darkened(0.3))
	theme.set_color("font_outline_color", "Button", p.SHADOW)
	theme.set_constant("outline_size", "Button", 3)
	theme.set_constant("h_separation", "Button", 12)
	theme.set_stylebox("normal", "Button", _box(p.SLAB, p.ASH_EDGE, 1, 14, 8))
	theme.set_stylebox("hover", "Button", _box(p.SLAB_LIT, p.EMBER_DIM, 1, 14, 8))
	theme.set_stylebox("pressed", "Button", _box(p.EMBER_DEEP, p.EMBER, 2, 14, 8))
	theme.set_stylebox("hover_pressed", "Button", _box(p.EMBER_DEEP, p.EMBER, 2, 14, 8))
	theme.set_stylebox("disabled", "Button", _box(p.SLAB.darkened(0.4), p.ASH_EDGE.darkened(0.4), 1, 14, 8))
	theme.set_stylebox("focus", "Button", _focus_ring(p.EMBER))

	# Main-menu entries: no slab, an ember bar on the left when selected.
	theme.set_type_variation("MenuEntryButton", "Button")
	theme.set_font("font", "MenuEntryButton", display)
	theme.set_font_size("font_size", "MenuEntryButton", 34)
	theme.set_color("font_color", "MenuEntryButton", p.BONE.darkened(0.15))
	var entry := _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 26, 6)
	entry.content_margin_left = 30.0
	var entry_lit := _box(Color(p.EMBER.r, p.EMBER.g, p.EMBER.b, 0.13), p.EMBER, 0, 26, 6)
	entry_lit.content_margin_left = 30.0
	entry_lit.border_width_left = 4
	theme.set_stylebox("normal", "MenuEntryButton", entry)
	theme.set_stylebox("hover", "MenuEntryButton", entry_lit)
	theme.set_stylebox("pressed", "MenuEntryButton", entry_lit)
	theme.set_stylebox("hover_pressed", "MenuEntryButton", entry_lit)
	theme.set_stylebox("disabled", "MenuEntryButton", entry)
	var entry_focus := entry_lit.duplicate() as StyleBoxFlat
	entry_focus.draw_center = true
	theme.set_stylebox("focus", "MenuEntryButton", entry_focus)

	# Panels.
	var panel := _box(p.PANEL, p.ASH_EDGE, 1, 28, 22)
	panel.corner_radius_top_left = 3
	panel.corner_radius_top_right = 3
	panel.corner_radius_bottom_left = 3
	panel.corner_radius_bottom_right = 3
	panel.shadow_color = Color(0, 0, 0, 0.55)
	panel.shadow_size = 18
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	var row := _box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 0, 12, 4)
	theme.set_type_variation("RowPanel", "PanelContainer")
	theme.set_stylebox("panel", "RowPanel", row)

	# Sliders.
	var track := _box(p.SLAB.darkened(0.3), p.ASH_EDGE, 1, 0, 0)
	track.content_margin_top = 4.0
	track.content_margin_bottom = 4.0
	theme.set_stylebox("slider", "HSlider", track)
	var fill := _box(p.EMBER_DIM, Color(0, 0, 0, 0), 0, 0, 0)
	fill.content_margin_top = 4.0
	fill.content_margin_bottom = 4.0
	theme.set_stylebox("grabber_area", "HSlider", fill)
	var fill_lit := fill.duplicate() as StyleBoxFlat
	fill_lit.bg_color = p.EMBER
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill_lit)
	theme.set_stylebox("focus", "HSlider", _focus_ring(p.EMBER))

	# Toggles.
	theme.set_font("font", "CheckButton", body_bold)
	theme.set_color("font_color", "CheckButton", p.BONE)
	theme.set_color("font_hover_color", "CheckButton", p.EMBER_BRIGHT)
	theme.set_color("font_focus_color", "CheckButton", p.EMBER_BRIGHT)
	theme.set_color("font_pressed_color", "CheckButton", p.BONE)
	theme.set_color("font_hover_pressed_color", "CheckButton", p.EMBER_BRIGHT)
	theme.set_stylebox("normal", "CheckButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 4))
	theme.set_stylebox("hover", "CheckButton", _box(p.SLAB_LIT, Color(0, 0, 0, 0), 0, 8, 4))
	theme.set_stylebox("pressed", "CheckButton", _box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 4))
	theme.set_stylebox("hover_pressed", "CheckButton", _box(p.SLAB_LIT, Color(0, 0, 0, 0), 0, 8, 4))
	theme.set_stylebox("focus", "CheckButton", _focus_ring(p.EMBER))

	# Bars (HUD code overrides the fill per meter).
	theme.set_stylebox("background", "ProgressBar", _box(Color(0.02, 0.015, 0.02, 0.85), p.ASH_EDGE, 1, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(p.EMBER, Color(0, 0, 0, 0), 0, 0, 0))
	theme.set_constant("outline_size", "ProgressBar", 0)

	theme.set_stylebox("panel", "TooltipPanel", _box(p.PANEL, p.ASH_EDGE, 1, 10, 6))
	theme.set_stylebox("separator", "HSeparator", _line(p.ASH_EDGE))
	theme.set_constant("separation", "HSeparator", 14)

	var error := ResourceSaver.save(theme, OUT)
	print("%s %s" % [OUT, "written" if error == OK else "NOT written: %s" % error_string(error)])
	quit(0 if error == OK else 1)


func _weight(font: FontFile, weight: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = font
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return variation


func _variation(theme: Theme, name: StringName, base: StringName, font: Font, size: int, color: Color, outline: int) -> void:
	theme.set_type_variation(name, base)
	theme.set_font("font", name, font)
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)
	theme.set_constant("outline_size", name, outline)


func _box(bg: Color, border: Color, border_width: int, margin_h: float, margin_v: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	box.anti_aliasing = false
	return box


func _focus_ring(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = color
	box.set_border_width_all(2)
	box.set_expand_margin_all(2.0)
	return box


func _line(color: Color) -> StyleBoxLine:
	var line := StyleBoxLine.new()
	line.color = color
	line.thickness = 1
	return line
