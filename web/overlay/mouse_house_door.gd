extends Node3D

const WIDTH:=.900
const RADIUS:=WIDTH*.5
const OPEN_ANGLE:=deg_to_rad(88.0)
const SWING_SECONDS:=.62
var size_scale:=.5
var house:Node3D
var room:Node3D
var leaf:AnimatableBody3D
var opened:=false
var moving:=false
var angle:=0.0
var start_angle:=0.0
var target_angle:=0.0
var age:=0.0
var hinge:=Vector3.ZERO
var hint_layer:CanvasLayer
var hint:Label
var impact:AudioStreamPlayer3D

func _ready() -> void:
	name="LittleWoodenDoor";process_mode=Node.PROCESS_MODE_PAUSABLE
	size_scale=house.DOOR_SCALE
	# Mount the hinge outside the arch: an inward-swinging round-top leaf would
	# sweep through the deep curved tunnel above its hinge-side edge.
	hinge=Vector3(-RADIUS*size_scale,0,house.facade_front-.025)
	leaf=AnimatableBody3D.new();leaf.name="HingedWoodenLeaf";leaf.sync_to_physics=false
	leaf.collision_layer=1;leaf.collision_mask=6;leaf.physics_interpolation_mode=Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(leaf);leaf.position=hinge
	var wood:StandardMaterial3D=house.finishes.finish("walnut").duplicate();wood.uv1_scale=Vector3(.52,1.4,1)
	var iron=house.finishes.finish("dark_metal")
	for board in 5:
		var lo=-RADIUS+board*WIDTH/5.0+.0012;var hi=-RADIUS+(board+1)*WIDTH/5.0-.0012
		var outline=PackedVector2Array([Vector2(lo,.018),Vector2(hi,.018)])
		for j in 13:
			var x=lerpf(hi,lo,j/12.0);outline.append(Vector2(x,.57+sqrt(maxf(0,RADIUS*RADIUS-x*x))))
		var mesh=_extruded_board(outline,board)
		var mi=house._mesh("Carved wooden door board %d"%board,mesh,Vector3.ZERO,wood)
		_adopt(mi,Vector3(RADIUS,0,0))
	# The whole arched leaf is a single convex contact shape, generated once.
	var points=PackedVector3Array()
	for z in [-.030,.030]:
		points.append(Vector3(0,.018,z));points.append(Vector3(WIDTH,.018,z))
		for j in 33:
			var a=PI*j/32.0;points.append(Vector3(RADIUS+cos(a)*RADIUS,.57+sin(a)*RADIUS,z))
	for i in points.size():points[i]*=size_scale
	var shape=ConvexPolygonShape3D.new();shape.points=points;shape.margin=.001
	var cs=CollisionShape3D.new();cs.shape=shape;leaf.add_child(cs)
	for y in [.22,.65]:
		for side in [-1,1]:
			_adopt(house._box("Iron hinge strap",Vector3.ZERO,Vector3(.31,.043,.010),iron,false,.007),Vector3(.15,y,side*.035))
			for x in [.055,.265]:_rivet(Vector3(x,y,side*.043),house.brass)
		var barrel=house._cylinder("Hinge barrel",Vector3.ZERO,.019,.105,house.brass)
		_adopt(barrel,Vector3(.008,y,0))
	# A rounded brass knob and backplate on each side, reachable from inside.
	for side in [-1,1]:
		var plate=house._cylinder("Handle backplate",Vector3.ZERO,.041,.008,house.brass)
		_adopt(plate,Vector3(.745,.415,side*.036));plate.rotation.x=PI*.5
		var stalk=house._cylinder("Handle stem",Vector3.ZERO,.012,.027,house.brass)
		_adopt(stalk,Vector3(.745,.415,side*.052));stalk.rotation.x=PI*.5
		var knob=SphereMesh.new();knob.radius=.027;knob.height=.054;knob.radial_segments=24;knob.rings=12
		_adopt(house._mesh("Little brass doorknob",knob,Vector3.ZERO,house.brass),Vector3(.745,.415,side*.074))
	hint_layer=CanvasLayer.new();hint_layer.layer=10;add_child(hint_layer)
	hint=Label.new();hint_layer.add_child(hint);hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left=-400;hint.offset_right=400;hint.offset_top=-215;hint.offset_bottom=-165;hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size",24);hint.add_theme_color_override("font_color",Color(1,.90,.64));hint.add_theme_color_override("font_outline_color",Color(.06,.045,.03));hint.add_theme_constant_override("outline_size",5);hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;hint.hide()
	impact=AudioStreamPlayer3D.new();impact.position=hinge+Vector3(.4,.4,0)*size_scale;impact.volume_db=-24;impact.unit_size=1.0;add_child(impact)
	impact.stream=load("res://assets/playground/button_click.wav")

func _adopt(mi:MeshInstance3D,p:Vector3) -> MeshInstance3D:
	mi.reparent(leaf,false);mi.position=p*size_scale;mi.scale=Vector3.ONE*size_scale;return mi

func _rivet(p:Vector3,mat:Material) -> void:
	var sphere=SphereMesh.new();sphere.radius=.008;sphere.height=.016;sphere.radial_segments=12;sphere.rings=6
	_adopt(house._mesh("Small hinge rivet",sphere,Vector3.ZERO,mat),p)

func _uv(p:Vector2,index:int) -> Vector2:return Vector2(p.y*.76,p.x*1.2+index*.19)

func _extruded_board(poly:PackedVector2Array,index:int) -> ArrayMesh:
	var inner=PackedVector2Array();var middle=Vector2((poly[0].x+poly[1].x)*.5,.48)
	for p in poly:inner.append(p.move_toward(middle,.0035))
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices=Geometry2D.triangulate_polygon(inner)
	for side in [-1,1]:
		for i in range(0,indices.size(),3):
			var order=[indices[i],indices[i+1],indices[i+2]] if side<0 else [indices[i],indices[i+2],indices[i+1]]
			for k in order:st.set_normal(Vector3(0,0,side));st.set_uv(_uv(inner[k],index));st.add_vertex(Vector3(inner[k].x,inner[k].y,side*.030))
	for i in poly.size():
		var j=(i+1)%poly.size();var d=(poly[j]-poly[i]).normalized();var edge=Vector3(d.y,-d.x,0)
		for band in 3:
			var pa=inner[i] if band==0 else poly[i];var pb=inner[j] if band==0 else poly[j]
			var pc=inner[i] if band==2 else poly[i];var pd=inner[j] if band==2 else poly[j]
			var za=[-.030,-.025,.025][band];var zb=[-.025,.025,.030][band]
			var vertices=[Vector3(pa.x,pa.y,za),Vector3(pb.x,pb.y,za),Vector3(pd.x,pd.y,zb),Vector3(pc.x,pc.y,zb)]
			var normal=(edge+Vector3(0,0,-1 if band==0 else 1)).normalized() if band!=1 else edge
			for k in [0,2,1,0,3,2]:st.set_normal(normal);st.set_uv(_uv(Vector2(vertices[k].x,vertices[k].y),index));st.add_vertex(vertices[k])
	st.index();st.generate_tangents();return st.commit()

func near_door() -> bool:
	if not room.ready_to_play or room.actor==null or not room.actor.can_control:return false
	var p:Vector3=house.to_local(room.actor.global_position)
	return absf(p.x)<.9 and p.y<.85 and p.y>-.1 and absf(p.z-hinge.z)<1.15

func _clearance(point:Vector2,a:float) -> float:
	var direction=Vector2(cos(a),-sin(a))
	return point.distance_to(direction*clampf(point.dot(direction),0,WIDTH*size_scale))

func _motion_hits_actor(from:float,to:float) -> bool:
	for person in [room.actor,room.companion]:
		if person==null:continue
		var p:Vector3=house.to_local(person.global_position)-hinge
		if p.y>1.05*size_scale or p.y<-.15:continue
		var point=Vector2(p.x,p.z);var distance=_clearance(point,to)
		# Opening away from someone already touching the closed leaf is safe.
		if distance<.15 and distance<_clearance(point,from)-.00001:return true
	return false

func _sweep_blocked(from:float,to:float) -> bool:
	for i in range(1,17):
		if _motion_hits_actor(lerpf(from,to,(i-1)/16.0),lerpf(from,to,i/16.0)):return true
	return false

func toggle() -> bool:
	if moving:return false
	var desired=0.0
	if not opened:
		desired=OPEN_ANGLE
	if _sweep_blocked(angle,desired):room._show_toast("门边有人，先让开一点",2);return false
	start_angle=angle;target_angle=desired;age=0;moving=true;opened=not opened
	if impact.stream!=null and room.sounds_enabled:impact.pitch_scale=1.15 if opened else .9;impact.play()
	return true

func handle_input(event:InputEvent) -> bool:
	if room.paused or not near_door():return false
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E:
		toggle();get_viewport().set_input_as_handled();return true
	return false

func _physics_process(delta:float) -> void:
	if not room.ready_to_play:return
	hint.text="E 关门 · 小木门" if opened else "E 开门 · 小木门"
	hint.visible=near_door() and room.hud.visible and not room.paused and not moving
	if room.paused or not moving:return
	var next_age=minf(age+delta,SWING_SECONDS);var t=next_age/SWING_SECONDS
	var next_angle=lerpf(start_angle,target_angle,t*t*(3.0-2.0*t))
	# Stop the leaf before it can pass through a character entering its sweep.
	if _motion_hits_actor(angle,next_angle):
		moving=false;opened=absf(angle)>.05;room._show_toast("门边有人，先让开一点",2);return
	age=next_age;angle=next_angle;leaf.rotation.y=angle
	if age>=SWING_SECONDS:moving=false
