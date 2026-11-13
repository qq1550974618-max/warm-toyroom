extends CanvasLayer

var room:Node3D
var panel:PanelContainer
var open_button:Button
var status:Label
var placement_tip:Label
var marker:MeshInstance3D
var marker_material:StandardMaterial3D
var choosing:=false
var candidate_valid:=false
var candidate:=Vector3.ZERO
var pending_click:=false
var prior_paused:=false
var prior_control:=true
var placement_count:=0
var place_button:Button
var hold_button:Button
var note:Label

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS;layer=16
	var ui=Control.new();ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);ui.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var theme=Theme.new();var font=preload("res://web/noto_sans_sc.ttf")
	theme.default_font=font;theme.default_font_size=24;ui.theme=theme;add_child(ui)
	for kind in ["normal","hover","pressed"]:
		var style=StyleBoxFlat.new();style.bg_color=Color(.12,.15,.14,.97) if kind=="normal" else Color(.25,.28,.22,.98)
		style.border_color=Color(.56,.49,.33);style.set_border_width_all(1);style.set_corner_radius_all(12)
		style.content_margin_left=20;style.content_margin_right=20;style.content_margin_top=12;style.content_margin_bottom=12
		theme.set_stylebox(kind,"Button",style)
	open_button=Button.new();open_button.text="同伴设置  [N]";open_button.focus_mode=Control.FOCUS_NONE;ui.add_child(open_button)
	open_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);open_button.offset_left=-290;open_button.offset_right=-38;open_button.offset_top=116;open_button.offset_bottom=174
	open_button.pressed.connect(toggle)
	panel=PanelContainer.new();ui.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left=-650;panel.offset_right=-38;panel.offset_top=188
	var box=StyleBoxFlat.new();box.bg_color=Color(.055,.072,.067,.98);box.set_corner_radius_all(14);box.content_margin_left=24;box.content_margin_right=24;box.content_margin_top=20;box.content_margin_bottom=20;panel.add_theme_stylebox_override("panel",box)
	var rows=VBoxContainer.new();rows.add_theme_constant_override("separation",14);panel.add_child(rows)
	status=Label.new();status.text="同伴";status.add_theme_font_size_override("font_size",29);status.modulate=Color(1,.88,.64);rows.add_child(status)
	place_button=button(rows,"指挥同伴走到…",begin_placement)
	hold_button=button(rows,"固定当前位置",func():hold_current();close_panel());hold_button.hide()
	button(rows,"恢复自由活动",func():release_hold();close_panel())
	button(rows,"让同伴举飞机送我到对面",func():close_panel();room.plane_assist.begin())
	button(rows,"继续游戏  [N / Esc]",close_panel)
	if room.web_touch_mode:preload("res://web/mobile_ui.gd").fit_panel(panel,false)
	panel.hide()
	placement_tip=Label.new();placement_tip.text="移动鼠标选择站立面，左键放置并固定 · Esc 取消";placement_tip.add_theme_font_size_override("font_size",28);placement_tip.modulate=Color(1,.88,.63);ui.add_child(placement_tip)
	placement_tip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP);placement_tip.offset_top=170;placement_tip.offset_left=-440;placement_tip.offset_right=440;placement_tip.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;placement_tip.hide()
	marker=MeshInstance3D.new();marker.name="CompanionPlacementFootprint";room.add_child(marker)
	var ring=TorusMesh.new();ring.inner_radius=.12;ring.outer_radius=.14;ring.rings=24;ring.ring_segments=8;marker.mesh=ring
	marker_material=StandardMaterial3D.new();marker_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;marker_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;marker_material.albedo_color=Color(.45,.91,.65,.8)
	marker.material_override=marker_material;marker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;marker.hide()

func button(parent:Node,text:String,callback:Callable) -> Button:
	var b=Button.new();b.text=text;b.focus_mode=Control.FOCUS_NONE;b.pressed.connect(callback);parent.add_child(b);return b

func mind():return room.companion.get_node("WanderMind")

func hold_current() -> void:
	room.playground.release_board_wait()
	if room.collected>=5:mind().command_cancel();mind().set_manual_hold(true)
	else:mind().command_stop(12)
	room.playground.ai_mode="manual"
	room._show_toast("同伴已固定" if room.collected>=5 else "同伴在原地等你 12 秒",3)

func release_hold(notify:bool=true) -> void:
	room.playground.release_board_wait()
	mind().command_cancel();mind().set_manual_hold(false);room.playground.ai_mode="wander"
	if notify:room._show_toast("同伴恢复活动，走动间隔已延长",3)

func toggle() -> void:
	if panel.visible or choosing:close_panel()
	else:open_panel()

func open_panel() -> void:
	if panel.visible or choosing:return
	if room.light_controls.panel.visible:room.light_controls.close_panel()
	if room.pause_menu!=null and room.pause_menu.overlay.visible:room.pause_menu.resume()
	room.prop_interaction.cancel_charge();prior_paused=room.paused;prior_control=room.actor.can_control
	room.paused=true;room.actor.can_control=false;get_tree().paused=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	status.text="同伴"
	place_button.text="选择位置并固定" if room.collected>=5 else "指挥同伴走到…"
	hold_button.visible=room.collected>=5
	show();panel.show()

func close_panel() -> void:
	if not panel.visible and not choosing:return
	choosing=false;pending_click=false;panel.hide();placement_tip.hide();marker.hide();get_viewport().gui_release_focus()
	room.paused=prior_paused;get_tree().paused=prior_paused;room.actor.can_control=prior_control
	if not room.automated:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if prior_paused or room.web_touch_mode else Input.MOUSE_MODE_CAPTURED
	visible=room.hud.visible

func begin_placement() -> void:
	choosing=true;candidate_valid=false;pending_click=false;panel.hide();placement_tip.text="左键选择站立面 · 抵达后等你 12 秒" if room.collected<5 else "左键放置并固定 · Esc 取消";placement_tip.show()

func position_is_clear(point:Vector3,normal:Vector3=Vector3.UP) -> bool:
	if normal.y<.72:return false
	var body=room.companion
	for cs in body.get_children():
		if cs is CollisionShape3D and cs.shape is CapsuleShape3D and not cs.disabled:
			var q=PhysicsShapeQueryParameters3D.new();q.shape=cs.shape;q.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*.018+cs.position);q.collision_mask=71;q.exclude=[body.get_rid()];q.margin=.001
			if not room.get_world_3d().direct_space_state.intersect_shape(q,1).is_empty():return false
	return true

func place_and_hold(point:Vector3) -> bool:
	if not position_is_clear(point):return false
	if room.collected<5:
		if absf(point.y-room.companion.position.y)>.30:
			placement_tip.text="请选择同伴能走到的同层地面";return false
		room.playground.release_board_wait()
		mind().command_walk(point,12);room.playground.ai_mode="manual";placement_count+=1;room._show_toast("同伴正在走过去，抵达后等你 12 秒",3);return true
	var body=room.companion;body.reset_position();body.position=point+Vector3.UP*.018;body.velocity=Vector3.ZERO;body.reset_physics_interpolation()
	var face=room.actor.position-body.position;face.y=0
	if face.length()>.05:body.heading_yaw=atan2(-face.z,face.x);body.visual.rotation.y=body.heading_yaw
	hold_current();placement_count+=1;return true

func _physics_process(_delta:float) -> void:
	if not choosing or not room.ready_to_play:return
	var cursor=get_viewport().get_mouse_position();var origin=room.camera.project_ray_origin(cursor)
	var ray=PhysicsRayQueryParameters3D.create(origin,origin+room.camera.project_ray_normal(cursor)*35,65)
	ray.exclude=[room.actor.get_rid(),room.companion.get_rid()]
	var hit=room.get_world_3d().direct_space_state.intersect_ray(ray)
	candidate_valid=false;marker.visible=not hit.is_empty()
	if not hit.is_empty():
		candidate=hit.position;candidate_valid=position_is_clear(candidate,hit.normal);marker.position=candidate+Vector3.UP*.016
		marker_material.albedo_color=Color(.45,.91,.65,.85) if candidate_valid else Color(.96,.28,.21,.8)
	if pending_click:
		pending_click=false
		if candidate_valid and place_and_hold(candidate):close_panel()
		else:placement_tip.text="这里空间不足，请选择宽一些的站立面 · Esc 取消"

func _process(_delta:float) -> void:
	open_button.visible=not choosing and not room.light_controls.panel.visible

func handle_key(event:InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_N:toggle();get_viewport().set_input_as_handled();return true
		if (panel.visible or choosing) and event.physical_keycode==KEY_ESCAPE:close_panel();get_viewport().set_input_as_handled();return true
		if (panel.visible or choosing) and event.physical_keycode==KEY_L:close_panel();return false
	if choosing and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		pending_click=true;get_viewport().set_input_as_handled();return true
	return panel.visible or choosing
