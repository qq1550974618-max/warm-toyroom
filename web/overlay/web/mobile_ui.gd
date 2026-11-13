extends RefCounted

static func fit_panel(panel:PanelContainer, tall:bool=true) -> void:
	panel.offset_left=-1220;panel.offset_right=-45
	panel.offset_top=65;panel.offset_bottom=1380 if tall else 990
	_enlarge(panel)

static func _enlarge(node:Node) -> void:
	if node is Control:
		var size=node.get_theme_font_size("font_size")
		node.add_theme_font_size_override("font_size",maxi(38,roundi(size*1.4)))
	if node is BaseButton:
		node.custom_minimum_size.y=100
	if node is OptionButton:
		node.get_popup().add_theme_font_size_override("font_size",44)
	if node is HSlider:
		node.custom_minimum_size.y=62
	for child in node.get_children():_enlarge(child)
