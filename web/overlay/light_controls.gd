extends CanvasLayer

const PRESETS=[
	{"name":"微缩暖光","exposure":1.03,"sun":1.0,"fill":1.0,"bounce":1.0,"rays":1.0,"warmth":.72,"dof":.08},
	{"name":"强窗光 · 深阴影","exposure":.82,"sun":1.28,"fill":.24,"bounce":.32,"rays":1.8,"warmth":.62,"dof":.10},
	{"name":"玩具房 · 柔和日光","exposure":1.12,"sun":.76,"fill":1.65,"bounce":1.22,"rays":.48,"warmth":.48,"dof":.08}
]
var room:Node3D
var values:Dictionary=PRESETS[0].duplicate()
var preset_index:=0
var panel:PanelContainer
var open_button:Button
var selector:OptionButton
var quality_selector:OptionButton
var reference_selector:OptionButton
var reference_index:=0
var soft_lighting=preload("res://soft_room_lighting.gd").new()
var slider_captions:Dictionary={}
var history=preload("res://lighting_history.gd").new()

var tabs:TabContainer
var quality_index:=1
const QUALITY_IDS=["high","standard","smooth"]
var v24_reference:=false
var v24_button:CheckButton
var profile_note:Label
var reset_button:Button
var v24_lighting=preload("res://lighting_v24_reference.gd").new()
var effective_quality:Dictionary={}
var sliders:Dictionary={}
var value_labels:Dictionary={}
var prior_paused:=false
var prior_control:=true
var updating:=false
var refresh_remaining:=-1.0
var save_remaining:=-1.0
var base_exposure:=1.0
var captured_lightmap:=false
var refresh_flip:=false
var base_energies:Dictionary={}
var base_light_colors:Dictionary={}
var base_light_specular:Dictionary={}
var save_path:="user://lighting_v30_web.cfg"

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS;layer=15
	for lamp in room.get_children():
		if lamp is Light3D:
			base_energies[str(lamp.name)]=lamp.light_energy
			base_light_colors[str(lamp.name)]=lamp.light_color
			base_light_specular[str(lamp.name)]=lamp.light_specular
	history.bind(room)
	soft_lighting.bind(room)
	_build_panel()
	if room.web_touch_mode:preload("res://web/mobile_ui.gd").fit_panel(panel)
	if not room.automated:load_preferences()
	set_quality(quality_index);_sync_widgets();apply_values()

func _style(color:Color,border:Color) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new();s.bg_color=color;s.border_color=border;s.set_border_width_all(1);s.set_corner_radius_all(14)
	s.content_margin_left=22;s.content_margin_right=22;s.content_margin_top=14;s.content_margin_bottom=14
	return s

func _build_panel() -> void:
	var font:=preload("res://web/noto_sans_sc.ttf")
	var theme:=Theme.new();theme.default_font=font;theme.default_font_size=25
	theme.set_stylebox("normal","Button",_style(Color(.12,.15,.14,.96),Color(.48,.43,.31,.8)))
	theme.set_stylebox("hover","Button",_style(Color(.24,.26,.21,.98),Color(.85,.70,.40)))
	theme.set_stylebox("pressed","Button",_style(Color(.31,.29,.20),Color(.96,.80,.45)))
	var ui:=Control.new();ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.mouse_filter=Control.MOUSE_FILTER_IGNORE;ui.theme=theme;add_child(ui)
	open_button=Button.new();open_button.focus_mode=Control.FOCUS_NONE;open_button.text="光线调节  [L]";open_button.tooltip_text="按 L 打开光线面板；Esc 释放鼠标后也可点击"
	ui.add_child(open_button);open_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	open_button.offset_left=-290;open_button.offset_right=-38;open_button.offset_top=38;open_button.offset_bottom=104;open_button.pressed.connect(toggle)
	panel=PanelContainer.new();panel.name="LightingPanel";ui.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left=-650;panel.offset_right=-38;panel.offset_top=126;panel.offset_bottom=1236;panel.add_theme_stylebox_override("panel",_style(Color(.055,.072,.067,.97),Color(.46,.43,.33,.9)))
	panel.theme=theme
	var outer:=VBoxContainer.new();outer.add_theme_constant_override("separation",12);panel.add_child(outer)
	
	var scroll:=ScrollContainer.new();scroll.name="光影对比";scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;outer.add_child(scroll)
	var rows:=VBoxContainer.new();rows.add_theme_constant_override("separation",12);rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	var heading:=Label.new();heading.text="窗边的光";heading.add_theme_font_size_override("font_size",34);heading.modulate=Color(1,.88,.64);rows.add_child(heading)
	var sub:=Label.new();sub.text="切换光影版本，保留当前光线类型与调节值";sub.add_theme_font_size_override("font_size",22);sub.modulate=Color(.76,.80,.74);rows.add_child(sub)
	reference_selector=OptionButton.new();reference_selector.custom_minimum_size.y=58;reference_selector.focus_mode=Control.FOCUS_NONE
	reference_selector.clip_text=true
	for label in ["当前版本 · 微缩暖光","V24.1 · 微缩暖光"]:reference_selector.add_item(label)
	reference_selector.item_selected.connect(set_reference);rows.add_child(reference_selector)
	selector=OptionButton.new();selector.custom_minimum_size.y=58;selector.focus_mode=Control.FOCUS_NONE
	selector.clip_text=true
	for p in PRESETS:selector.add_item(p.name)
	selector.item_selected.connect(func(i:int):set_preset(i));rows.add_child(selector);selector.hide()
	v24_button=CheckButton.new();v24_button.text="V24.1 微缩暖光";v24_button.focus_mode=Control.FOCUS_NONE
	v24_button.tooltip_text="单独对照 V24.1 原始暖光；关闭后恢复原有选择与调节值"
	v24_button.toggled.connect(set_v24_reference);rows.add_child(v24_button);v24_button.hide()
	_add_slider(rows,"exposure","画面亮度",.45,1.65,.01)
	_add_slider(rows,"sun","窗外阳光",.40,1.70,.01)
	_add_slider(rows,"bounce","阴影填充",.12,1.6,.01)
	_add_slider(rows,"warmth","暖色程度",0,1,.01)
	quality_selector=OptionButton.new();quality_selector.focus_mode=Control.FOCUS_NONE
	for label in ["高画质","标准画质","流畅画质"]:quality_selector.add_item(label)
	quality_selector.custom_minimum_size.y=48;rows.add_child(quality_selector)
	quality_selector.item_selected.connect(func(i:int):set_quality(i);save_remaining=.45)
	var note:=Label.new();note.text="窗外暖阳，屋内柔光。\n不同光影版本共用当前调节值。";note.add_theme_font_size_override("font_size",21);note.modulate=Color(.69,.76,.70);rows.add_child(note);profile_note=note
	var reset:=Button.new();reset.text="恢复当前预设";reset.pressed.connect(func():set_preset(preset_index));reset.focus_mode=Control.FOCUS_NONE;rows.add_child(reset);reset_button=reset
	var close:=Button.new();close.text="继续游戏  [L / Esc]";close.pressed.connect(close_panel);close.focus_mode=Control.FOCUS_NONE;outer.add_child(close)
	panel.hide()

func _add_slider(parent:VBoxContainer,key:String,label:String,minimum:float,maximum:float,step:float) -> void:
	var row:=HBoxContainer.new();parent.add_child(row)
	var caption:=Label.new();caption.text=label;caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(caption);slider_captions[key]=caption
	var number:=Label.new();number.modulate=Color(.89,.78,.54);row.add_child(number);value_labels[key]=number
	var slider:=HSlider.new();slider.min_value=minimum;slider.max_value=maximum;slider.step=step;slider.custom_minimum_size.y=28
	slider.focus_mode=Control.FOCUS_ALL;parent.add_child(slider);sliders[key]=slider
	slider.value_changed.connect(func(v:float):
		if updating:return
		values[key]=v;value_labels[key].text="%d%%"%roundi(v*100)
		apply_values();save_remaining=.45)

func _sync_widgets() -> void:
	updating=true;selector.select(preset_index);quality_selector.select(quality_index);reference_selector.select(1 if v24_reference else 0)
	quality_selector.disabled=reference_index>0 and not v24_reference
	v24_button.set_pressed_no_signal(v24_reference)
	reset_button.disabled=v24_reference
	profile_note.text="V24.1 原始微缩暖光。\n关闭开关，恢复之前的选择和调节。" if v24_reference else "窗外暖阳，屋内柔光。\n不同光影版本共用当前调节值。"
	reference_selector.disabled=false;selector.disabled=v24_reference
	slider_captions.sun.text="窗外阳光"
	for key in sliders:
		sliders[key].editable=not v24_reference
		var shown:float=PRESETS[0][key] if v24_reference else values[key]
		sliders[key].value=shown;value_labels[key].text="%d%%"%roundi(shown*100)
	updating=false

func set_preset(index:int) -> void:
	preset_index=clampi(index,0,PRESETS.size()-1);values=preset_values(preset_index,quality_index);_sync_widgets();apply_values();save_remaining=.45

func preset_values(preset:int,_quality:int) -> Dictionary:
	# One tone definition for every rig and quality; no per-version override.
	return PRESETS[clampi(preset,0,PRESETS.size()-1)].duplicate()

func set_reference(index:int) -> void:
	reference_index=0;set_v24_reference(index==1)

func set_v24_reference(enabled:bool) -> void:
	v24_reference=enabled;_sync_widgets();apply_values();save_remaining=.45

func is_ultra() -> bool:return false

func effective_dof() -> float:return 0.0

func set_quality(index:int) -> void:
	quality_index=clampi(index,0,QUALITY_IDS.size()-1)
	if room.quality_surfaces!=null:room.quality_surfaces.apply(is_ultra())
	_sync_widgets();apply_values()

func apply_render_quality() -> void:
	var heights=[1080,720,540]
	# The wide room needs a minimum 2K shadow map even at low canvas resolution.
	# 1K plus desktop-sized bias causes alternating self-shadow cells on the floor.
	var shadow_size=2048
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(shadow_size,false)
	get_viewport().positional_shadow_atlas_size=1024
	if OS.has_feature("web"):JavaScriptBridge.eval("window.setToyroomRenderHeight?.(%d)"%heights[quality_index])
	effective_quality={"id":QUALITY_IDS[quality_index],"shadow_size":shadow_size,"height":heights[quality_index]}
	_enforce_browser_features()

func _enforce_browser_features() -> void:
	var e=room.environment
	e.ssao_enabled=false;e.ssil_enabled=false;e.ssr_enabled=false;e.volumetric_fog_enabled=false;e.glow_enabled=false
	e.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	room.attributes.dof_blur_far_enabled=false;room.attributes.dof_blur_near_enabled=false
	room.sun.shadow_bias=.20;room.sun.shadow_normal_bias=2.0;room.sun.directional_shadow_max_distance=23
	room.sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	room.get_node("RoomReflections").hide();room.gi.hide()
	for lamp in room.get_children():
		if lamp is Light3D and lamp!=room.sun:lamp.shadow_enabled=false

func apply_values() -> void:
	history.restore()
	apply_render_quality()
	if v24_reference:
		v24_lighting.apply(self);_enforce_browser_features();return
	var e:Environment=room.environment
	e.tonemap_exposure=values.exposure
	var warmth:float=values.warmth
	room.sun.light_color=Color(1,.96,.88).lerp(Color(1,.81,.56),warmth)
	room.sun.light_energy=5.2*float(values.sun);room.sun.light_volumetric_fog_energy=6.5*float(values.rays)
	room.sun.light_angular_distance=.52 if preset_index==1 else .85
	for lamp in room.get_children():
		if not lamp is Light3D or str(lamp.name) not in base_energies or lamp==room.sun:continue
		var multiplier:float=values.fill
		if lamp.name=="Desk lamp":multiplier=1.0
		lamp.light_energy=float(base_energies[str(lamp.name)])*multiplier
	e.ambient_light_energy=.025*float(values.fill)
	e.ssil_intensity=.32*minf(1.0,values.bounce)
	e.glow_intensity=.18 if preset_index!=1 else .24
	e.volumetric_fog_density=.00042 if float(values.rays)>.001 else 0.0
	history.apply(reference_index,values)
	soft_lighting.apply(self)
	room.attributes.dof_blur_amount=values.dof
	# Grade the already baked indirect field; direct sun remains independently adjustable.
	# The inverse exposure normalization scales both lightmap texels and probe lighting.
	if room.lightmap.light_data!=null:
		var data:LightmapGIData=room.lightmap.light_data
		if not captured_lightmap:
			base_exposure=float(data.get("probe_data").get("baked_exposure",1.0));captured_lightmap=true
		RenderingServer.lightmap_set_baked_exposure_normalization(data.get_rid(),base_exposure/maxf(.05,values.bounce))
	_enforce_browser_features()

func _process(delta:float) -> void:
	if save_remaining>=0:
		save_remaining-=delta
		if save_remaining<0:save_preferences()

func save_preferences() -> Error:
	var file:=ConfigFile.new()
	file.set_value("lighting","schema",5)
	file.set_value("lighting","v24_reference",v24_reference)
	file.set_value("lighting","quality_id",QUALITY_IDS[quality_index])
	file.set_value("lighting","reference_id",history.IDS[reference_index])
	file.set_value("lighting","preset",preset_index)
	for key in values:
		if key!="name":file.set_value("tone",key,values[key])
	return file.save(save_path)

func load_preferences() -> bool:
	var file:=ConfigFile.new()
	var loaded=file.load(save_path)
	if loaded!=OK or int(file.get_value("lighting","schema",0)) not in [3,4,5]:
		# New screenshot defaults supersede inconsistent V22 per-rig settings.
		# Older files remain untouched. Removed version indices cannot migrate.
		quality_index=1;reference_index=0;preset_index=0;v24_reference=false
		values=preset_values(0,0);return false
	quality_index=maxi(0,QUALITY_IDS.find(str(file.get_value("lighting","quality_id","standard"))))
	reference_index=maxi(0,history.IDS.find(str(file.get_value("lighting","reference_id","current"))))
	v24_reference=bool(file.get_value("lighting","v24_reference",false))
	# V7 photo mode was removed. Its old flag is deliberately ignored.
	preset_index=int(file.get_value("lighting","preset",0))
	if preset_index<0 or preset_index>=PRESETS.size():preset_index=0
	values=preset_values(preset_index,quality_index)
	for key in sliders:
		values[key]=clampf(float(file.get_value("tone",key,values[key])),sliders[key].min_value,sliders[key].max_value)
	return true

func toggle() -> void:
	if panel.visible:close_panel()
	else:open_panel()

func open_panel() -> void:
	if panel.visible:return
	# End the other modal first: never save its temporary pause as our return state.
	if room.companion_controls!=null:room.companion_controls.close_panel()
	if room.pause_menu!=null and room.pause_menu.overlay.visible:room.pause_menu.resume()
	show()
	if room.prop_interaction!=null:room.prop_interaction.cancel_charge()
	prior_paused=room.paused;prior_control=room.actor.can_control
	room.paused=true;room.actor.can_control=false;get_tree().paused=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	panel.show();get_viewport().gui_release_focus()

func close_panel() -> void:
	if not panel.visible:return
	get_viewport().gui_release_focus()
	panel.hide();room.paused=prior_paused;get_tree().paused=prior_paused;room.actor.can_control=prior_control
	visible=room.hud.visible
	if not room.automated:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if prior_paused or room.web_touch_mode else Input.MOUSE_MODE_CAPTURED
	if not room.automated:save_preferences()

func handle_key(event:InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_L:
			toggle();get_viewport().set_input_as_handled();return true
		if panel.visible and event.physical_keycode==KEY_ESCAPE:
			close_panel();get_viewport().set_input_as_handled();return true
	return panel.visible
