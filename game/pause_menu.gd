extends CanvasLayer
var room
var overlay:Control
var prior_modes={}
var prior_control=true
func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS;layer=40
	overlay=Control.new();overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(overlay)
	var shade=ColorRect.new();shade.color=Color(.025,.032,.029,.78);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.add_child(shade)
	var center=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);overlay.add_child(center)
	var panel=PanelContainer.new();panel.name="PausePanel";center.add_child(panel)
	var style=StyleBoxFlat.new();style.bg_color=Color(.08,.105,.10,.98);style.border_color=Color(.66,.54,.31);style.set_border_width_all(2);style.set_corner_radius_all(20);style.content_margin_left=68;style.content_margin_right=68;style.content_margin_top=42;style.content_margin_bottom=48;panel.add_theme_stylebox_override("panel",style)
	var rows=VBoxContainer.new();rows.add_theme_constant_override("separation",25);panel.add_child(rows)
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"]);rows.add_theme_font_override("font",font)
	var title=Label.new();title.text="稍作休息";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",44);title.modulate=Color(1,.88,.64);rows.add_child(title)
	for i in 2:
		var b=Button.new();b.text="继续游戏  [Esc]" if i==0 else "退出游戏";b.name="Resume" if i==0 else "Exit";rows.add_child(b)
		b.custom_minimum_size=Vector2(390,78);b.add_theme_font_size_override("font_size",29);b.focus_mode=Control.FOCUS_NONE
		if i==0:b.pressed.connect(resume)
		else:b.pressed.connect(func():get_tree().quit())
	overlay.hide()
func show_pause() -> void:
	if overlay.visible:return
	if room.light_controls!=null:room.light_controls.close_panel()
	if room.companion_controls!=null:room.companion_controls.close_panel()
	prior_control=room.actor.can_control;prior_modes.clear()
	for child in room.get_children():
		if child==self:continue
		prior_modes[child]=child.process_mode;child.process_mode=Node.PROCESS_MODE_PAUSABLE
	room.paused=true;get_tree().paused=true;room.actor.can_control=false;overlay.show();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
func resume() -> void:
	if not overlay.visible:return
	for child in prior_modes:
		if is_instance_valid(child):child.process_mode=prior_modes[child]
	prior_modes.clear();overlay.hide();room.paused=false;get_tree().paused=false;room.actor.can_control=prior_control;room.toast.text=""
	if not room.automated:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
