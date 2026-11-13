extends Node3D
# One physical layout in house coordinates. No teleport volumes or per-frame mesh builds.
const PASSAGE_LENGTH=3.34
const ROOM_SHIFT=1.44
const TRIGGER_Z=1.65
const PASSAGE_HALF=.19
const PASSAGE_CEILING=.58
const END_ROOM_CEILING=.78*1.30
const CUE_STRIKE_TIME=.065*2.0
# Compensate for the slower visible stroke so the two-pocket route still
# needs two baited shots, while keeping the tested reaction window to each pocket.
const CUE_RELOAD_TIME=1.58
const SAFE_Z=3.42
const ENTRY_Z=0.0
const ALCOVE_FRONT_Z=1.25
const ALCOVE_REAR_Z=2.12
const ALCOVE_X=.35
const BOARD_Z=-.58
const BOARD_CONTACT_Z=-.40
const ROLL_STOP_Z=-.90
const RETURN_STOP_Z=3.67
const CUE_HOME_Z=4.94
const CUE_HEIGHT=.24
const CUE_RETRACT_TIME=.12
const SLOT_X=.75
const SLOT_Z=1.93
const ROOM_BACK_Z=4.62
const BOARD_HANDLE=Vector3(-.67,0,4.12)
const COOP_A=Vector3(-.18,0,4.31)
const COOP_B=Vector3(.38,0,4.31)
const SLOT_HEIGHT=.084
const SLOT_WIDTH=.46
const BUTTON_SCALE=.70
const BUTTON_TOP=.082
const BUTTON_TRAVEL=.052
var room:Node3D
var house:Node3D
var wood:Material
var cream:Material
var brass:Material
var teal:Material
var red:Material
var felt:Material
var cue:AnimatableBody3D
var cue_shape:CollisionShape3D
var cue_query:PhysicsShapeQueryParameters3D
var cue_contact_z=0.0
var cue_hit_count=0
var cue_retract_start=Vector3.ZERO
var button_audio:AudioStreamPlayer3D
var button_press_count=0
var pressure_contacts:Array[CollisionShape3D]=[]
var cue_phase="armed"
var cue_age=0.0
var cue_target:CharacterBody3D
var cue_strikes=0
var board:Node3D
var board_weight=0.0
var board_compression=0.0
var board_handle:Node3D
var pullers:Dictionary={}
var pull_anchors:Dictionary={}
var pressure_caps:Array[Node3D]=[]
var pressure_weights=[0.0,0.0]
var pressure_occupants=[null,null]
var coop_weight=0.0
var coop_done=false
var pedestal:AnimatableBody3D
var reward:Node3D
var reward_index=-1
var black8:RigidBody3D
var book_point=Vector3(.843,.395,1.72)
var book_ui:CanvasLayer
var book_panel:Control
var book_open=false
var book_control=true
var prompt:Label
var lift:AnimatableBody3D
var lift_origin=Vector3(6.15,.028,6.65)
var lift_height=0.0
var lift_phase="waiting"
var lift_age=0.0
var lift_passengers:Array=[]
var lift_platform_layers:Dictionary={}
var lift_cycles=0
var lift_status:Label3D
var lift_display_weight=-1.0
var lift_control_collider:CollisionShape3D
var lift_control:Node3D
var lift_lever:Node3D
var lift_red:StandardMaterial3D
var lift_green:StandardMaterial3D
var lift_ready=false
var lift_ball_on=false
var lift_occupants:Array=[]
var lift_flat_count=0
var lift_operator:CharacterBody3D
var lift_use_age=9.0
var lift_denied_age=9.0
var lift_denials=0
var lift_audio:AudioStreamPlayer3D
var silhouette_texture:Texture2D
var silhouette_shader:Shader

var head_origins:Dictionary={}
var last_positions:Dictionary={}
var camera_mix=0.0
var book_glow:OmniLight3D
var in_action=false
var cue_sound:AudioStreamPlayer3D
var camera_query:PhysicsRayQueryParameters3D
var camera_clear_distance=1.0
var camera_cutaway_nodes:Array=[]
var camera_furniture_bounds:Array=[]
var camera_cutaway_age=0.0
var camera_was_inside=false

func _ready() -> void:
	name="LittleHousePuzzles";process_mode=Node.PROCESS_MODE_PAUSABLE;process_physics_priority=-22
	house=room.mouse_house;global_transform=house.global_transform*Transform3D(Basis(Vector3.UP,PI*.5),Vector3(1.36,0,.75))
	wood=house.wood;cream=house.finishes.finish("paper");brass=house.brass;teal=house.finishes.finish("paint_teal")
	red=house.finishes.finish("paint_rust").duplicate();red.albedo_color=Color(.70,.10,.065)
	felt=house.finishes.finish("felt").duplicate();felt.albedo_color=Color(.60,.51,.38)
	_build_passage();_build_flat_route();_build_handles();_build_lift();_build_book();_build_ui()
	preload("res://puzzle_detail.gd").apply(self)
	house.finishes.batch_details(self)
	# One continuous contact plane across the main room, doorway and paper slot.
	# Tiny overlapping floor lips trap a paper-thin collider at their shared edge.
	var floor_contact=room.room.get_node("ContinuousWalkingFloor").get_child(0)
	floor_contact.shape=floor_contact.shape.duplicate();floor_contact.shape.size.x=21;floor_contact.shape.size.z=18;floor_contact.position.x=2.5;floor_contact.position.z=-1.0
	for body in get_children():
		if body is StaticBody3D and "floor contact" in str(body.name).to_lower():body.collision_layer=0
	for person in [room.actor,room.companion]:
		if person.get_node_or_null("WanderMind")==null:
			var mind=preload("res://wander_companion.gd").new();mind.name="WanderMind";mind.actor=person;mind.room=room;person.add_child(mind)
		var pose=preload("res://puzzle_pull_pose.gd").new();pose.actor=person;pose.puzzles=self;person.skeleton.add_child(pose)
		_cloth_last(person)
	room.actor.input_override=false;room.actor.can_control=true
	# The paper plane remains a physical prop on the marked low wooden chest.
	room._teleport_prop(room.paper_plane,Transform3D(Basis(Vector3.UP,-.20),Vector3(-6.86,1.17,3.85)))
	room.paper_plane.set_meta("spawn_transform",room.paper_plane.transform)
	cue_sound=AudioStreamPlayer3D.new();cue_sound.stream=load("res://assets/audio/toy_impact.wav");cue_sound.unit_size=2;cue_sound.volume_db=-15;add_child(cue_sound)
	_prepare_camera_collision()

func box(label:String,p:Vector3,size:Vector3,mat:Material,solid:bool=true) -> MeshInstance3D:
	var mi=house._box(label,p,size,mat,false,.012);mi.reparent(self,false)
	mi.set_meta("authored_detail_label",label)
	if solid:
		var body=StaticBody3D.new();body.name=label+" contact";body.collision_layer=1;body.collision_mask=6;add_child(body)
		var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=size;cs.shape=shape;body.add_child(cs);cs.position=p
	return mi

func ball_mesh(parent:Node,p:Vector3,radius:float,mat:Material) -> MeshInstance3D:
	var mesh=SphereMesh.new();mesh.radius=radius;mesh.height=radius*2;mesh.radial_segments=40;mesh.rings=20
	var mi=MeshInstance3D.new();mi.mesh=mesh;mi.position=p;mi.material_override=mat;mi.layers=4;parent.add_child(mi);return mi

func cylinder_between(parent:Node,a:Vector3,b:Vector3,radius:float,mat:Material) -> MeshInstance3D:
	var mesh=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=a.distance_to(b);mesh.radial_segments=20
	var mi=MeshInstance3D.new();mi.mesh=mesh;mi.material_override=mat;mi.layers=4;parent.add_child(mi);mi.position=(a+b)*.5
	mi.quaternion=Quaternion(Vector3.UP,(b-a).normalized());return mi

func _build_passage() -> void:
	# Restore the original 3.34 m length, with intermediate single-file clearance.
	var plaster=load("res://room_kit/materials/legacy_ivory_lime_plaster.tres")
	preload("res://puzzle_floor.gd").build(self,wood)
	for side in [-1,1]:
		var recess_z=ALCOVE_FRONT_Z if side<0 else ALCOVE_REAR_Z
		var half=.215
		for span in [Vector2(.04,recess_z-half),Vector2(recess_z+half,PASSAGE_LENGTH)]:
			_passage_wall("Passage wall beside pocket",side*(PASSAGE_HALF+.04),span,.08,plaster,side>0)
		_passage_wall("Single doll pocket back",side*.555,Vector2(recess_z-half-.07,recess_z+half+.07),.07,plaster,side>0)
		for z in [recess_z-half-.035,recess_z+half+.035]:
			var floor_height=SLOT_HEIGHT if side>0 and absf(z-SLOT_Z)<SLOT_WIDTH*.5+.04 else 0.0
			box("Pocket return wall",Vector3(side*.375,(PASSAGE_CEILING+floor_height)*.5,z),Vector3(.44,PASSAGE_CEILING-floor_height,.07),plaster)
		box("Pocket felt",Vector3(side*ALCOVE_X,.004,recess_z),Vector3(.29,.007,.35),felt,false)
		for i in 2:box("Pocket brass inset",Vector3(side*.514,.16+i*.065,recess_z),Vector3(.006,.016,.10),brass,false)
	box("Corridor ceiling",Vector3(0,PASSAGE_CEILING+.04,PASSAGE_LENGTH*.5),Vector3(1.18,.08,PASSAGE_LENGTH),plaster)
	# A real small bore in the rear wall. The whole idle shaft now lives behind
	# the wall instead of hovering above the route inside the chamber.
	var bore=.045
	_build_socket_wall(plaster,bore)
	var socket=house.finishes.finish("dark_metal")
	for side in [-1,1]:
		box("Recessed cue sleeve side",Vector3(side*.0575,CUE_HEIGHT,ROOM_BACK_Z+.63),Vector3(.025,.14,1.26),socket,false)
		box("Recessed cue sleeve lip",Vector3(0,CUE_HEIGHT+side*.0575,ROOM_BACK_Z+.63),Vector3(.09,.025,1.26),socket,false)
	box("Recessed cue sleeve end",Vector3(0,CUE_HEIGHT,ROOM_BACK_Z+1.26),Vector3(.14,.14,.025),socket,false)
	var socket_ring=MeshInstance3D.new();socket_ring.name="Small bored brass cue socket"
	var socket_mesh=TorusMesh.new();socket_mesh.inner_radius=.045;socket_mesh.outer_radius=.062;socket_mesh.rings=48;socket_mesh.ring_segments=12;socket_ring.mesh=socket_mesh
	socket_ring.position=Vector3(0,CUE_HEIGHT,ROOM_BACK_Z-.041);socket_ring.rotation.x=PI*.5;socket_ring.material_override=brass;socket_ring.layers=4;add_child(socket_ring)
	box("End room left",Vector3(-1.09,END_ROOM_CEILING*.5,2.51+ROOM_SHIFT),Vector3(.08,END_ROOM_CEILING,1.42),plaster)
	box("End room front left",Vector3(-.67,END_ROOM_CEILING*.5,1.84+ROOM_SHIFT),Vector3(.90,END_ROOM_CEILING,.08),plaster)
	box("End room front right",Vector3(.46,END_ROOM_CEILING*.5,1.84+ROOM_SHIFT),Vector3(.48,END_ROOM_CEILING,.08),plaster)
	box("End side wall",Vector3(.69,END_ROOM_CEILING*.5,2.51+ROOM_SHIFT),Vector3(.08,END_ROOM_CEILING,1.42),plaster)
	box("End room entrance lintel",Vector3(0,(END_ROOM_CEILING+PASSAGE_CEILING)*.5,1.84+ROOM_SHIFT),Vector3(.44,END_ROOM_CEILING-PASSAGE_CEILING,.08),plaster)
	# A continuous real roof closes the chamber; the low security aisle stays unchanged.
	box("End room ceiling",Vector3(-.20,END_ROOM_CEILING+.04,2.51+ROOM_SHIFT),Vector3(1.86,.08,1.42),plaster)
	box("Safety landing pad",Vector3(0,.006,RETURN_STOP_Z),Vector3(.42,.012,.35),felt,false)
	var sign_root=Node3D.new();sign_root.name="Whale maid prohibited sign";sign_root.position=Vector3(0,.73,-.071);add_child(sign_root)
	var sign=box("Small security plaque",Vector3.ZERO,Vector3(.38,.30,.014),house.finishes.finish("hazard_yellow"),false);sign.reparent(sign_root,false)
	var hazard=MeshInstance3D.new();var face=QuadMesh.new();face.size=Vector2(.372,.292);hazard.mesh=face;hazard.position.z=-.008;hazard.rotation.y=PI;hazard.layers=4;sign_root.add_child(hazard)
	var hs=Shader.new();hs.code="shader_type spatial; render_mode cull_disabled; void fragment(){ vec2 e=min(UV,1.0-UV); float border=1.0-step(0.075,min(e.x,e.y)); float a=(UV.x+UV.y*0.78)*9.0; float edge=max(fwidth(a),0.003); float stripe=smoothstep(0.5-edge,0.5+edge,fract(a)); vec3 yellow=vec3(0.91,0.53,0.035); ALBEDO=mix(yellow,mix(yellow,vec3(0.012),stripe),border); ROUGHNESS=0.65; SPECULAR=0.24; }"
	var hm=ShaderMaterial.new();hm.shader=hs;hazard.material_override=hm
	_fish_icon(sign_root,Vector3(0,0,-.012),.105,Color(.015,.015,.015))
	cylinder_between(sign_root,Vector3(-.095,-.095,-.017),Vector3(.095,.095,-.017),.008,house.finishes.finish("dark_metal"))
	cue=AnimatableBody3D.new();cue.name="Spring billiard cue";cue.sync_to_physics=false;cue.collision_layer=1;cue.collision_mask=2;cue.position=Vector3(0,CUE_HEIGHT,CUE_HOME_Z);add_child(cue)
	cue_shape=CollisionShape3D.new();var shaft=CapsuleShape3D.new();shaft.radius=.024;shaft.height=1.16;cue_shape.shape=shaft;cue_shape.rotation.x=PI*.5;cue_shape.position.z=.255;cue.add_child(cue_shape)
	cue_query=PhysicsShapeQueryParameters3D.new();cue_query.shape=shaft;cue_query.collision_mask=3;cue_query.exclude=[cue.get_rid()];cue_query.margin=.001
	cylinder_between(cue,Vector3(0,0,.81),Vector3(0,0,-.20),.020,wood)
	cylinder_between(cue,Vector3(0,0,-.20),Vector3(0,0,-.27),.019,brass)
	cylinder_between(cue,Vector3(0,0,-.27),Vector3(0,0,-.30),.020,house.finishes.finish("chalk"))
	var ferrule=cylinder_between(cue,Vector3(0,0,-.245),Vector3(0,0,-.274),.0195,house.finishes.finish("porcelain"))
	for i in 18:
		var ring=cylinder_between(cue,Vector3(0,0,.45+i*.014),Vector3(0,0,.453+i*.014),.021,house.finishes.finish("thread"));ring.set_meta("mini_static_detail",true)
	house.finishes.batch_details(cue)
	for z in [.14,.32,.50,.68]:cylinder_between(cue,Vector3(0,0,z),Vector3(0,0,z+.024),.025,brass)
	for z in [TRIGGER_Z-.028,TRIGGER_Z+.028]:box("Security brass threshold",Vector3(0,.002,z),Vector3(PASSAGE_HALF*2,.003,.008),brass,false)
	board=Node3D.new();board.name="Elastic rebound board";board.position=Vector3(0,-.25,BOARD_Z);add_child(board)
	var rebound_rubber=house.finishes.finish("rubber").duplicate();rebound_rubber.albedo_color=Color(.12,.105,.085)
	var front=box("Rubber rebound pad",Vector3.ZERO,Vector3(.46,.30,.055),rebound_rubber,false);front.reparent(board,false)
	var plate=box("Rebound backplate",Vector3(0,0,-.035),Vector3(.47,.31,.018),brass,false);plate.reparent(board,false)
	for x in [-.207,.207]:
		for y in [-.126,.126]:ball_mesh(board,Vector3(x,y,.029),.007,brass)
	for side in [-1,1]:
		box("Rebound brass guide",Vector3(side*.255,.12,BOARD_Z-.02),Vector3(.022,.28,.030),brass,false)
		for i in 6:
			var coil=MeshInstance3D.new();var spring_mesh=TorusMesh.new();spring_mesh.inner_radius=.021;spring_mesh.outer_radius=.027;spring_mesh.rings=20;spring_mesh.ring_segments=6;coil.mesh=spring_mesh;coil.material_override=brass;coil.position=Vector3(side*.16,0,-.04-i*.012);coil.rotation.x=PI*.5;board.add_child(coil)
	for point in [Vector3(0,.48,.65),Vector3(0,.48,2.35),Vector3(-.3,.68,2.66+ROOM_SHIFT)]:
		var lamp=OmniLight3D.new();lamp.position=point;lamp.light_color=Color(1,.88,.70);lamp.light_energy=.30;lamp.omni_range=2.4;lamp.light_size=.16;lamp.shadow_enabled=false;lamp.light_cull_mask=6;add_child(lamp)

func _build_socket_wall(mat:Material,bore:float) -> void:
	# One UV-continuous wall with a true circular bore. Four separately bevelled
	# boxes would leave full-height grooves above and below this tiny socket.
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var angles:Array[float]=[]
	for i in 64:angles.append(float(i)*TAU/64.0)
	for corner in [Vector2(-1.13,-CUE_HEIGHT),Vector2(.73,-CUE_HEIGHT),Vector2(.73,END_ROOM_CEILING-CUE_HEIGHT),Vector2(-1.13,END_ROOM_CEILING-CUE_HEIGHT)]:
		angles.append(fposmod(corner.angle(),TAU))
	angles.sort()
	for i in angles.size():
		var a=Vector2.from_angle(angles[i]);var b=Vector2.from_angle(angles[(i+1)%angles.size()])
		var ends:Array[Vector2]=[]
		for d in [a,b]:
			var dx=(.73 if d.x>=0 else -1.13)/d.x if absf(d.x)>.00001 else INF
			var dy=(END_ROOM_CEILING-CUE_HEIGHT if d.y>=0 else -CUE_HEIGHT)/d.y if absf(d.y)>.00001 else INF
			ends.append(d*minf(dx,dy)+Vector2(0,CUE_HEIGHT))
		var ia=a*bore+Vector2(0,CUE_HEIGHT);var ib=b*bore+Vector2(0,CUE_HEIGHT)
		var front=ROOM_BACK_Z-.04;var back=ROOM_BACK_Z+.04
		_socket_quad(st,[Vector3(ia.x,ia.y,front),Vector3(ends[0].x,ends[0].y,front),Vector3(ends[1].x,ends[1].y,front),Vector3(ib.x,ib.y,front)],Vector3.FORWARD)
		_socket_quad(st,[Vector3(ib.x,ib.y,back),Vector3(ends[1].x,ends[1].y,back),Vector3(ends[0].x,ends[0].y,back),Vector3(ia.x,ia.y,back)],Vector3.BACK)
		var inward=-(a+b).normalized()
		_socket_quad(st,[Vector3(ia.x,ia.y,front),Vector3(ib.x,ib.y,front),Vector3(ib.x,ib.y,back),Vector3(ia.x,ia.y,back)],Vector3(inward.x,inward.y,0))
	st.index();st.generate_tangents()
	var wall=MeshInstance3D.new();wall.name="Continuous plaster wall with cue bore";wall.mesh=st.commit();wall.material_override=mat;wall.layers=4;add_child(wall)
	var body=StaticBody3D.new();body.name="Bored rear wall contact";body.collision_layer=1;body.collision_mask=6;add_child(body)
	for dims in [
		[Vector3((-1.13-bore)*.5,END_ROOM_CEILING*.5,ROOM_BACK_Z),Vector3(1.13-bore,END_ROOM_CEILING,.08)],
		[Vector3((.73+bore)*.5,END_ROOM_CEILING*.5,ROOM_BACK_Z),Vector3(.73-bore,END_ROOM_CEILING,.08)],
		[Vector3(0,(CUE_HEIGHT-bore)*.5,ROOM_BACK_Z),Vector3(bore*2,CUE_HEIGHT-bore,.08)],
		[Vector3(0,(END_ROOM_CEILING+CUE_HEIGHT+bore)*.5,ROOM_BACK_Z),Vector3(bore*2,END_ROOM_CEILING-CUE_HEIGHT-bore,.08)]]:
		var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=dims[1];cs.shape=shape;cs.position=dims[0];body.add_child(cs)

func _socket_quad(st:SurfaceTool,points:Array,normal:Vector3) -> void:
	for index in [0,1,2,0,2,3]:
		var v:Vector3=points[index];st.set_normal(normal);st.set_uv(Vector2(v.x,v.y)*2.0);st.add_vertex(v)

func _passage_wall(label:String,x:float,span:Vector2,thickness:float,mat:Material,slit:bool) -> void:
	# The outer paper opening stays at the user's marked corner. Its short
	# tunnel now joins the longer aisle through the second recess, without moving it.
	var cut=Vector2(SLOT_Z-SLOT_WIDTH*.5,SLOT_Z+SLOT_WIDTH*.5)
	if not slit or span.y<=cut.x or span.x>=cut.y:
		box(label,Vector3(x,PASSAGE_CEILING*.5,(span.x+span.y)*.5),Vector3(thickness,PASSAGE_CEILING,span.y-span.x),mat);return
	for part in [Vector2(span.x,minf(span.y,cut.x)),Vector2(maxf(span.x,cut.y),span.y)]:
		if part.y>part.x:box(label,Vector3(x,PASSAGE_CEILING*.5,(part.x+part.y)*.5),Vector3(thickness,PASSAGE_CEILING,part.y-part.x),mat)
	var l=maxf(span.x,cut.x);var r=minf(span.y,cut.y)
	box(label+" over paper slit",Vector3(x,(PASSAGE_CEILING+SLOT_HEIGHT)*.5,(l+r)*.5),Vector3(thickness,PASSAGE_CEILING-SLOT_HEIGHT,r-l),mat)

func _build_flat_route() -> void:
	house.cut_flat_entrance(1.36+SLOT_Z,SLOT_WIDTH,SLOT_HEIGHT)
	# Floor surface is below the existing floor, not a second coplanar shiny skin.
	box("Paper tunnel floor",Vector3(.61,-.055,SLOT_Z),Vector3(.78,.09,SLOT_WIDTH),wood,false)
	var mat=load("res://room_kit/materials/mk_sage_painted_wood.tres")
	# End the lining inside the original wall. Its outer face already provides
	# the lintel; an extra full-length bar would protrude through the skirting.
	box("Paper tunnel ceiling",Vector3(.62,SLOT_HEIGHT+.025,SLOT_Z),Vector3(.20,.05,SLOT_WIDTH),mat)
	for z in [SLOT_Z-SLOT_WIDTH*.5-.025,SLOT_Z+SLOT_WIDTH*.5+.025]:
		box("Paper tunnel cheek",Vector3(.62,.072,z),Vector3(.20,.144,.05),wood)

func _fish_icon(parent:Node,p:Vector3,r:float,ink:Color=Color(.96,.96,.93),front_positive:bool=false) -> void:
	# Shared transparent outline from the user's new reference, upright in all signs.
	if silhouette_texture==null:
		silhouette_texture=load("res://assets/puzzle_v27/whale_silhouette.png") as Texture2D
		silhouette_shader=Shader.new();silhouette_shader.code="shader_type spatial; render_mode cull_disabled, unshaded; uniform sampler2D source_art : source_color, filter_linear_mipmap; uniform vec4 ink : source_color; void fragment(){ ALBEDO=ink.rgb; ALPHA=texture(source_art,UV).a; ALPHA_SCISSOR_THRESHOLD=0.50; }"
	var q=QuadMesh.new();q.size=Vector2(r*2,r*2)
	var mi=MeshInstance3D.new();mi.name="Reference whale maid silhouette";mi.mesh=q;mi.position=p;mi.layers=4;mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation.y=0 if front_positive else PI
	var mat=ShaderMaterial.new()
	mat.shader=silhouette_shader;mat.set_shader_parameter("source_art",silhouette_texture);mat.set_shader_parameter("ink",ink);mi.material_override=mat;parent.add_child(mi)

func _build_handles() -> void:
	# Compact remote plunger. No rope or pulley crosses the house or corridor.
	board_handle=Node3D.new();board_handle.name="Remote rebound control";board_handle.position=BOARD_HANDLE+Vector3(0,.19,-.045);add_child(board_handle)
	cylinder_between(board_handle,Vector3(-.075,0,0),Vector3(.075,0,0),.018,wood)
	cylinder_between(board_handle,Vector3(0,-.12,.045),Vector3.ZERO,.012,brass)
	box("Remote control base",BOARD_HANDLE+Vector3.UP*.035,Vector3(.20,.07,.10),wood,true)
	for x in [-.075,.075]:
		for z in [-.033,.033]:ball_mesh(self,BOARD_HANDLE+Vector3(x,.071,z),.006,brass)
	for point in [COOP_A,COOP_B]:
		# A hollow bezel leaves the red cap visible at the bottom of its travel.
		# A solid base box would cover the depressed cap and the rider's feet.
		var outer=Vector2(.31,.29)*BUTTON_SCALE
		var opening=Vector2(.268,.248)*BUTTON_SCALE+Vector2.ONE*.004
		box("Twin pressure button floor",point+Vector3.UP*.005,Vector3(outer.x,.010,outer.y),brass,false)
		for side in [-1.0,1.0]:
			var wx=(outer.x-opening.x)*.5;var wz=(outer.y-opening.y)*.5
			box("Twin pressure button rim",point+Vector3(side*(outer.x-wx)*.5,.025,0),Vector3(wx,.05,outer.y),brass,false)
			box("Twin pressure button rim",point+Vector3(0,.025,side*(outer.y-wz)*.5),Vector3(opening.x,.05,wz),brass,false)
		var cap=box("Twin pressure button padded cap",point+Vector3.UP*(BUTTON_TOP-.016),Vector3(.268*BUTTON_SCALE,.032,.248*BUTTON_SCALE),red,false)
		pressure_caps.append(cap)
		# Low fixed contact hull prevents any step from trapping the small feet.
		var contact=StaticBody3D.new();contact.name="Pressure button contact";contact.collision_layer=1;contact.collision_mask=6;add_child(contact)
		var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3(.268*BUTTON_SCALE,BUTTON_TOP,.248*BUTTON_SCALE);cs.shape=shape;cs.position=point+Vector3.UP*(BUTTON_TOP*.5);contact.add_child(cs);pressure_contacts.append(cs)
		for x in [-.133*BUTTON_SCALE,.133*BUTTON_SCALE]:
			for z in [-.124*BUTTON_SCALE,.124*BUTTON_SCALE]:ball_mesh(self,point+Vector3(x,.051,z),.006,house.brass)
	# The viewer looks toward local +Z, so screen-left is positive local X.
	# Always read from inside the room as fish + fish = star, never mirrored.
	for x in [.43,-.11]:
		box("Paired pressure plaque",Vector3(x,.54,3.13+ROOM_SHIFT),Vector3(.24,.19,.015),wood,false)
		_fish_icon(self,Vector3(x,.54,3.115+ROOM_SHIFT),.082)
	for mark in [[.16,.54,.09,.015],[.16,.54,.015,.09],[-.38,.56,.09,.015],[-.38,.52,.09,.015]]:
		box("Pressure equation mark",Vector3(mark[0],mark[1],3.119+ROOM_SHIFT),Vector3(mark[2],mark[3],.007),cream,false)
	var star_points=PackedVector2Array()
	for i in 10:
		var angle=-PI*.5+i*PI/5;var radius=.105 if i%2==0 else .046
		star_points.append(Vector2(cos(angle),sin(angle))*radius)
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices=Geometry2D.triangulate_polygon(star_points)
	for i in range(0,indices.size(),3):
		for k in [indices[i],indices[i+2],indices[i+1]]:
			var point=star_points[k];st.set_normal(Vector3(0,0,-1));st.set_uv(point+Vector2(.5,.5));st.add_vertex(Vector3(-.71+point.x,.54-point.y,3.117+ROOM_SHIFT))
	var star=MeshInstance3D.new();star.name="Cooperative star hint";star.mesh=st.commit();star.material_override=house._material(Color(1.0,.72,.16),.62);star.layers=4;add_child(star)

	pedestal=AnimatableBody3D.new();pedestal.name="Cooperative rising pedestal";pedestal.sync_to_physics=false;pedestal.collision_layer=1;add_child(pedestal);pedestal.position=Vector3(.16,-.10,2.51+ROOM_SHIFT)
	var top=box("Pedestal polished cap",Vector3.ZERO,Vector3(.24,.14,.24),wood,false);top.reparent(pedestal,false)
	var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3(.24,.14,.24);cs.shape=shape;pedestal.add_child(cs)
	button_audio=AudioStreamPlayer3D.new();button_audio.name="Pressure button click";button_audio.stream=load("res://assets/audio/toy_impact.wav");button_audio.volume_db=-7;button_audio.unit_size=2;add_child(button_audio)
	reward=_add_star(to_global(Vector3(.16,.38,2.51+ROOM_SHIFT)),"Two fish star",false);reward_index=room.stars.size()-1

func _add_star(point:Vector3,label:String,enabled:bool=true) -> Node3D:
	var root=Node3D.new();root.name=label;room.add_child(root);root.position=point
	var mesh=MeshInstance3D.new();mesh.mesh=room._star_mesh();root.add_child(mesh)
	var mat=StandardMaterial3D.new();mat.albedo_color=Color(1,.70,.18);mat.emission_enabled=true;mat.emission=Color(1,.48,.05);mat.emission_energy_multiplier=1.1;mesh.material_override=mat;mesh.layers=4
	root.visible=enabled;room.stars.append(root);room.star_positions.append(point);return root

func _build_lift() -> void:
	# World-space shelf near the marked corner. Open deck allows the iron ball to roll across.
	var frame=Node3D.new();room.add_child(frame);frame.name="Two fish toy lift";frame.position=lift_origin;frame.rotation.y=PI
	for x in [-.66,.66]:
		var m=box("Lift upright",Vector3.ZERO,Vector3(.065,2.35,.065),wood,false);m.reparent(frame,false);m.position=Vector3(x,1.16,.20)
	# Wall moulding front measured at z=7.323: shelf ends at 7.320, a 3 mm
	# assembly clearance. Lift moves 20 cm towards it, shelf no longer embeds.
	var shelf=box("Eight ball wall shelf",Vector3.ZERO,Vector3(1.65,.12,.76),wood,false);shelf.reparent(frame,false);shelf.position=Vector3(0,1.94,-.29)
	for x in [-.57,.57]:
		var bracket=box("Fine shelf wall bracket",Vector3.ZERO,Vector3(.044,.27,.36),brass,false);bracket.reparent(frame,false);bracket.position=Vector3(x,1.76,-.49)
		for y in [1.72,1.86]:ball_mesh(frame,Vector3(x,y,-.304),.011,house.finishes.finish("dark_metal"))
	var shelf_body=StaticBody3D.new();frame.add_child(shelf_body);shelf_body.position=shelf.position;shelf_body.collision_layer=1
	var shelf_cs=CollisionShape3D.new();var shelf_shape=BoxShape3D.new();shelf_shape.size=Vector3(1.65,.12,.76);shelf_cs.shape=shelf_shape;shelf_body.add_child(shelf_cs)
	lift=AnimatableBody3D.new();lift.name="Open weigh platform";lift.collision_layer=64;lift.collision_mask=6;lift.sync_to_physics=false;frame.add_child(lift)
	# Keep the moving deck in front of the fixed shelf, with a 5 mm gap.
	# Their former overlapping footprints carried dolls through the shelf.
	lift.position.z=.57
	room.iron_ball.collision_mask|=64
	for prop in room.physics_props:prop.collision_mask|=64
	room.paper_plane.collision_mask|=64
	var platform=box("Elevator platform",Vector3.ZERO,Vector3(1.20,.055,.95),wood,false);platform.reparent(lift,false)
	# The veneer sits above the physics deck. Paper must follow its current
	# visual plane, including the tick before the moving body's contacts update.
	lift.set_meta("paper_surface_height",.032)
	var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3(1.20,.055,.95);cs.shape=shape;lift.add_child(cs)
	for side in [-1,1]:
		var stripe=box("Brass lift edge",Vector3.ZERO,Vector3(.026,.008,.89),brass,false);stripe.reparent(lift,false);stripe.position=Vector3(side*.56,.030,0)
	var sign=Node3D.new();frame.add_child(sign);sign.name="Lift information panel";sign.position=Vector3(0,.92,-.53)
	var backing=box("Lift instruction plaque",Vector3.ZERO,Vector3(1.14,.68,.025),teal,false);backing.reparent(sign,false)
	_fish_icon(sign,Vector3(-.29,.205,.016),.073,Color(.97,.94,.84),true)
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	_sign_label(sign,"= 100kg",Vector3(.10,.205,.022),38,.00235,font)
	_sign_label(sign,"负载 = 101kg",Vector3(0,.045,.022),36,.0023,font)
	_sign_label(sign,"启动条件",Vector3(-.24,-.112,.022),30,.00205,font)
	_fish_icon(sign,Vector3(.105,-.112,.016),.061,Color(.97,.94,.84),true)
	_sign_label(sign,"+",Vector3(.218,-.112,.022),24,.002,font)
	_fish_icon(sign,Vector3(.335,-.112,.016),.061,Color(.97,.94,.84),true)
	lift_status=_sign_label(sign,"当前负重  0 / 101 kg",Vector3(0,-.253,.023),25,.0018,font)
	lift_status.name="Current lift load"
	for x in [-.52,.52]:
		for y in [-.285,.285]:ball_mesh(sign,Vector3(x,y,.017),.010,brass)
	_beautify_lift(frame)
	_build_lift_control(frame)

	black8=RigidBody3D.new();black8.name="BlackEight";black8.collision_layer=4;black8.collision_mask=71;black8.mass=.32;black8.linear_damp=.6;black8.angular_damp=.4;black8.continuous_cd=true
	var pm=PhysicsMaterial.new();pm.friction=.6;pm.bounce=.18;black8.physics_material_override=pm
	room.add_child(black8);black8.position=frame.to_global(Vector3(-.35,2.10,-.43))
	var black=house.finishes.finish("resin")
	ball_mesh(black8,Vector3.ZERO,.10,black)
	var bcs=CollisionShape3D.new();var bs=SphereShape3D.new();bs.radius=.1;bcs.shape=bs;black8.add_child(bcs)
	for side in [-1,1]:
		var white=ball_mesh(black8,Vector3(0,0,side*.089),.046,house.finishes.finish("porcelain"));white.scale.z=.235
		var label8=Label3D.new();label8.text="8";label8.font_size=72;label8.pixel_size=.00094;label8.position=Vector3(0,0,side*.101);label8.rotation.y=0 if side>0 else PI;label8.modulate=Color(.012,.016,.018);label8.outline_size=0;black8.add_child(label8)
	black8.set_meta("kind","marble");black8.set_meta("black8",true);black8.set_meta("prop_size",Vector3.ONE*.20);black8.set_meta("display_name","黑 8 台球");black8.set_meta("spawn_transform",black8.transform);room.physics_props.append(black8)
	_add_star(frame.to_global(Vector3(.36,2.20,-.43)),"Shelf star")

func _lift_part(parent:Node3D,label:String,point:Vector3,size:Vector3,mat:Material,solid:bool=false) -> MeshInstance3D:
	var mi=box(label,point,size,mat,false);mi.reparent(parent,false)
	if solid:
		var body=StaticBody3D.new();body.name=label+" contact";body.collision_layer=1;body.collision_mask=6;parent.add_child(body)
		var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=size;cs.shape=shape;cs.position=point;body.add_child(cs)
	return mi

func _beautify_lift(frame:Node3D) -> void:
	# Fine painted slats, inset trim and visible guides. The open front and both
	# sides remain unobstructed; all ramp wedges travel with the platform.
	for i in 7:
		_lift_part(lift,"Inset walnut deck slat",Vector3(-.48+i*.16,.029,0),Vector3(.153,.003,.85),wood)
	for z in [-.432,.432]:_lift_part(lift,"Flush cream deck binding",Vector3(0,.030,z),Vector3(1.10,.003,.018),house.finishes.finish("paint_cream"))
	for x in [-.55,.55]:
		for z in [-.43,.43]:
			var screw=ball_mesh(lift,Vector3(x,.031,z),.008,brass);screw.scale.y=.25
	for x in [-.66,.66]:
		_lift_part(frame,"Teal guide housing",Vector3(x,1.16,.20),Vector3(.088,2.35,.080),teal,true)
		_lift_part(frame,"Inset brass guide",Vector3(x,1.16,.246),Vector3(.020,2.18,.010),brass)
		for y in [.10,1.15,2.25]:ball_mesh(frame,Vector3(x,y,.253),.009,brass)
		_lift_part(lift,"Platform guide shoe",Vector3(x,.02,-.37),Vector3(.10,.13,.12),house.finishes.finish("dark_metal"))
	_lift_part(frame,"Rounded top guide bridge",Vector3(0,2.33,.20),Vector3(1.42,.10,.11),wood,true)
	for row in [[0.0,.475,1.14],[PI*.5,.60,.87],[-PI*.5,.60,.87]]:
		var rotation=Basis(Vector3.UP,row[0]);var edge=float(row[1]);var half=float(row[2])*.5
		var vertices=PackedVector3Array()
		for x in [-half,half]:
			for yz in [Vector2(-.0275,edge),Vector2(.0275,edge),Vector2(-.0275,edge+.20)]:vertices.append(rotation*Vector3(x,yz.x,yz.y))
		var shape=ConvexPolygonShape3D.new();shape.points=vertices
		var collision=CollisionShape3D.new();collision.name="Shallow open access ramp";collision.shape=shape;lift.add_child(collision)
		var mesh=MeshInstance3D.new();mesh.name="Walnut access ramp";mesh.mesh=shape.get_debug_mesh();mesh.material_override=wood;mesh.layers=4
		# A triangulated wedge, not the physics debug wire rendering.
		var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for face in [[0,2,1],[3,4,5],[0,1,4,0,4,3],[1,2,5,1,5,4],[2,0,3,2,3,5]]:
			for idx in face:st.set_uv(Vector2(vertices[idx].x,vertices[idx].z)*2);st.add_vertex(vertices[idx])
		st.generate_normals();st.generate_tangents();mesh.mesh=st.commit();lift.add_child(mesh)

func _sign_label(parent:Node,text:String,point:Vector3,font_size:int,pixel_size:float,font:Font) -> Label3D:
	var label=Label3D.new();label.text=text;label.font=font;label.font_size=font_size;label.pixel_size=pixel_size;label.position=point;label.modulate=Color(1,.90,.72);label.outline_size=0;parent.add_child(label);return label

func _build_lift_control(frame:Node3D) -> void:
	lift_control=Node3D.new();lift_control.name="Lift lever pedestal";lift.add_child(lift_control);lift_control.position=Vector3(.36,.028,-.34)
	for item in [["Switch pedestal foot",Vector3(0,.018,0),Vector3(.18,.036,.15),wood],["Switch upright",Vector3(0,.12,0),Vector3(.075,.22,.075),teal],["Switch tabletop",Vector3(0,.238,0),Vector3(.25,.038,.18),wood],["Switch inset plate",Vector3(0,.259,.006),Vector3(.22,.006,.15),brass]]:
		var mesh=box(item[0],item[1],item[2],item[3],false);mesh.reparent(lift_control,false)
	# Single smooth contact hull; individual screws/lights do not trap feet.
	# Collision is on the moving body and resized with the folding stand.
	var cs=CollisionShape3D.new();var shape=BoxShape3D.new();shape.size=Vector3(.25,.265,.18);cs.shape=shape;cs.position=lift_control.position+Vector3.UP*.1325;lift.add_child(cs);lift_control_collider=cs
	for x in [-.10,.10]:
		for z in [-.06,.06]:ball_mesh(lift_control,Vector3(x,.265,z),.005,house.finishes.finish("dark_metal"))
	lift_lever=Node3D.new();lift_lever.name="Short sprung lever";lift_control.add_child(lift_lever);lift_lever.position=Vector3(0,.269,.040);lift_lever.rotation.x=-.35
	cylinder_between(lift_control,Vector3(-.026,.27,.04),Vector3(.026,.27,.04),.017,house.finishes.finish("dark_metal"))
	cylinder_between(lift_lever,Vector3.ZERO,Vector3(0,.066,0),.008,brass)
	ball_mesh(lift_lever,Vector3(0,.073,0),.022,house.finishes.finish("paint_cream"))
	lift_red=StandardMaterial3D.new();lift_green=StandardMaterial3D.new()
	for row in [[-.070,lift_red,Color(.78,.025,.012)],[.070,lift_green,Color(.03,.65,.16)]]:
		var m:StandardMaterial3D=row[1];m.albedo_color=row[2];m.roughness=.26;m.metallic_specular=.45;m.emission_enabled=true;m.emission=row[2];m.emission_energy_multiplier=0
		cylinder_between(lift_control,Vector3(row[0],.260,-.036),Vector3(row[0],.270,-.036),.023,brass)
		var lens=ball_mesh(lift_control,Vector3(row[0],.274,-.036),.019,m);lens.scale.y=.55
	lift_audio=AudioStreamPlayer3D.new();lift_audio.stream=load("res://assets/puzzle_v27/lift_denied.wav");lift_audio.unit_size=2;lift_audio.volume_db=-13;lift_control.add_child(lift_audio)

func _near_lift_lever(person:CharacterBody3D) -> bool:
	var p=lift_control.to_local(person.global_position)
	return Vector2(p.x,p.z).length()<.42 and absf(p.y)<.17

func is_using_lift(person:CharacterBody3D) -> bool:
	return person==lift_operator and lift_use_age<.52

func try_lift_lever(person:CharacterBody3D) -> bool:
	if not _near_lift_lever(person) or person.state in ["flattened","roll","stunned"]:return false
	# Re-evaluate real contacts at the instant of pulling, rather than trusting a UI lamp.
	_sense_lift()
	if lift_phase!="waiting" or not lift_ready:
		if lift_denied_age>.48:
			lift_denials+=1;lift_denied_age=0
			if room.sounds_enabled:lift_audio.play()
		return false
	lift_phase="starting";lift_age=0;lift_cycles+=1;lift_passengers=lift_occupants.duplicate()
	lift_operator=person;lift_use_age=0;person.velocity=Vector3.ZERO;person.override_direction=Vector3.ZERO
	person.heading_yaw=atan2(-(lift_control.global_position-person.global_position).z,(lift_control.global_position-person.global_position).x)
	return true

func _build_book() -> void:
	var book_start=get_child_count()
	box("Bedside glowing little book",to_local(house.to_global(book_point)),Vector3(.30,.035,.22),house.finishes.finish("book_rust"),false)
	box("Tiny book page edges",to_local(house.to_global(book_point+Vector3.UP*.019)),Vector3(.275,.019,.196),cream,false)
	box("Gilded little cover",to_local(house.to_global(book_point+Vector3.UP*.031)),Vector3(.30,.008,.22),house.finishes.finish("book_teal"),false)
	for x in [-.135,.135]:box("Book cover gold rule",to_local(house.to_global(book_point+Vector3(x,.037,0))),Vector3(.003,.003,.19),brass,false)
	for z in [-.094,.094]:box("Fine little book gold end",to_local(house.to_global(book_point+Vector3(0,.037,z))),Vector3(.270,.002,.003),brass,false)
	for i in 7:box("Fine layered paper edge",to_local(house.to_global(book_point+Vector3(0,.010+i*.0025,-.099))),Vector3(.272,.00065,.0015),house.finishes.finish("paper"),false)
	box("Little book ribbon",to_local(house.to_global(book_point+Vector3(.045,.013,-.119))),Vector3(.017,.002,.055),house.blue,false)
	# The passage is rotated relative to the house. Position AND orientation of
	# every book layer must share the house axes, including the very thin foil.
	for node in get_children().slice(book_start):
		if node is MeshInstance3D:node.rotation.y=-PI*.5
	book_glow=OmniLight3D.new();book_glow.position=to_local(house.to_global(book_point+Vector3.UP*.12));book_glow.light_energy=.13;book_glow.omni_range=.48;book_glow.light_color=Color(1,.83,.44);book_glow.light_specular=.1;add_child(book_glow)

func _build_ui() -> void:
	book_ui=CanvasLayer.new();book_ui.process_mode=Node.PROCESS_MODE_ALWAYS;book_ui.layer=22;add_child(book_ui)
	book_panel=Control.new();book_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);book_ui.add_child(book_panel)
	var shade=ColorRect.new();shade.color=Color(0,0,0,.55);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);book_panel.add_child(shade)
	var center=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);book_panel.add_child(center)
	var book=PanelContainer.new();book.custom_minimum_size=Vector2(1180,720)
	var cover=StyleBoxFlat.new();cover.bg_color=Color(.20,.105,.055);cover.border_color=Color(.57,.38,.17);cover.set_border_width_all(5);cover.set_corner_radius_all(12);cover.content_margin_left=24;cover.content_margin_right=24;cover.content_margin_top=20;cover.content_margin_bottom=20;cover.shadow_color=Color(0,0,0,.65);cover.shadow_size=22
	book.add_theme_stylebox_override("panel",cover);center.add_child(book)
	var rows=VBoxContainer.new();rows.add_theme_constant_override("separation",20);book.add_child(rows)
	var pages=HBoxContainer.new();pages.size_flags_vertical=Control.SIZE_EXPAND_FILL;rows.add_child(pages)
	for i in 2:
		var page=PanelContainer.new();page.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pages.add_child(page)
		var paper=GradientTexture2D.new();paper.width=512;paper.height=512;paper.fill_from=Vector2(0,0);paper.fill_to=Vector2(1,0)
		var grad=Gradient.new();grad.offsets=PackedFloat32Array([0,.04,.46,.93,1]);grad.colors=PackedColorArray([Color(.88,.79,.60),Color(.96,.90,.75),Color(.94,.87,.70),Color(.88,.77,.56),Color(.56,.42,.25)] if i==0 else [Color(.56,.42,.25),Color(.88,.77,.56),Color(.94,.87,.70),Color(.96,.90,.75),Color(.88,.79,.60)]);paper.gradient=grad
		var style=StyleBoxTexture.new();style.texture=paper;style.content_margin_left=42;style.content_margin_right=42;style.content_margin_top=70;style.content_margin_bottom=60;page.add_theme_stylebox_override("panel",style)
		var text=Label.new();text.text="世上本没有路，" if i==0 else "走的鱼多了，\n\n就变成了路。";text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		var font=SystemFont.new();font.font_names=PackedStringArray(["KaiTi","STKaiti","Noto Serif CJK SC","SimSun"]);text.add_theme_font_override("font",font);text.add_theme_font_size_override("font_size",38);text.add_theme_color_override("font_color",Color(.20,.13,.08));page.add_child(text)
	var close=Button.new();close.text="合上书本  [E / Esc]";close.add_theme_font_size_override("font_size",25);close.custom_minimum_size.y=56;close.pressed.connect(close_book);rows.add_child(close);book_panel.hide()
	prompt=Label.new();prompt.position=Vector2(480,1080);prompt.size=Vector2(1600,60);prompt.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;prompt.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var f=SystemFont.new();f.font_names=PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"]);prompt.add_theme_font_override("font",f);prompt.add_theme_font_size_override("font_size",28);prompt.add_theme_color_override("font_shadow_color",Color.BLACK);prompt.add_theme_constant_override("shadow_offset_x",2);prompt.add_theme_constant_override("shadow_offset_y",2);book_ui.add_child(prompt)

func open_book() -> void:
	book_control=room.actor.can_control;book_open=true;book_panel.show();prompt.hide();room.paused=true;room.actor.can_control=false;get_tree().paused=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func close_book() -> void:
	book_open=false;book_panel.hide();room.paused=false;get_tree().paused=false;room.actor.can_control=book_control;get_viewport().gui_release_focus()
	if not room.automated:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED

func handle_input(event:InputEvent) -> bool:
	if not event is InputEventKey or not event.pressed or event.echo:return false
	if book_open and event.physical_keycode in [KEY_E,KEY_ESCAPE]:close_book();return true
	if event.physical_keycode==KEY_ALT:switch_actor();return true
	if event.physical_keycode!=KEY_E:return false
	if _near_lift_lever(room.actor):try_lift_lever(room.actor);return true
	var p=to_local(room.actor.global_position)
	if house.to_local(room.actor.global_position).distance_to(book_point)<.62:open_book();return true
	if pullers.has(room.actor.get_instance_id()):stop_pull(room.actor);return true
	if p.distance_to(BOARD_HANDLE)<.40:start_pull(room.actor,"board");return true
	return false

func switch_actor() -> bool:
	if room.paused or not room.ready_to_play:return false
	if room.actor.stunt_mode!="" or room.companion.stunt_mode!="" or room.train.seated:
		room._show_toast("落稳或离开驾驶座后再换人",2);return false
	room.plane_assist.cancel()
	if room.iron_ball.pushing:room.iron_ball.stop_push()
	if room.prop_interaction.held!=null:room.prop_interaction.drop()
	var previous=room.actor;room.actor=room.companion;room.companion=previous
	previous.override_direction=Vector3.ZERO;previous.override_jump=false;previous.input_override=true;previous.can_control=false
	if is_pulling(previous):previous.get_node("WanderMind").set_manual_hold(true)
	else:previous.get_node("WanderMind").command_stop(12.0)
	room.actor.get_node("WanderMind").command_cancel();room.actor.get_node("WanderMind").set_physics_process(true)
	room.actor.input_override=is_pulling(room.actor);room.actor.can_control=not is_pulling(room.actor);room.actor.override_direction=Vector3.ZERO
	room.prop_interaction.actor=room.actor;room.prop_interaction.pose.reparent(room.actor.skeleton);room.prop_interaction.pose.actor=room.actor;room.prop_interaction.pose.reset_transient_pose()
	room.iron_ball.push_pose.reparent(room.actor.skeleton);room.iron_ball.push_pose.actor=room.actor;room.iron_ball.push_pose.weight=0
	room.plane_assist.npc=room.companion
	for skeleton in [room.actor.skeleton,room.companion.skeleton]:
		for modifier in skeleton.get_children():
			if modifier.get_script()==load("res://carry_pose.gd") and modifier.interaction==room.plane_assist:
				if modifier.get_parent()!=room.companion.skeleton:modifier.reparent(room.companion.skeleton)
				modifier.actor=room.companion;modifier.reset_transient_pose()
	room.playground.ai_mode="manual";room.overview=false;room.last_foot_events=room.actor.locomotion.plant_events.L+room.actor.locomotion.plant_events.R;room.last_land_count=room.actor.land_count
	_cloth_last(room.actor);_cloth_last(room.companion)
	room._show_toast("已切换大肥鱼 · Alt 再次换人",2);return true

func _cloth_last(person:CharacterBody3D) -> void:
	for modifier in person.skeleton.get_children():
		if modifier.get_script()==load("res://skirt_contact.gd"):person.skeleton.move_child(modifier,person.skeleton.get_child_count()-1)

func start_pull(person:CharacterBody3D,kind:String) -> void:
	if person.state in ["flattened","stunned","roll"]:return
	pullers[person.get_instance_id()]=kind;person.velocity=Vector3.ZERO;person.override_direction=Vector3.ZERO
	person.input_override=true;person.can_control=false;
	var local=to_local(person.global_position);local.x=BOARD_HANDLE.x;local.z=BOARD_HANDLE.z-.148
	var goal=to_global(local);var correction=goal-person.global_position
	if not person.test_move(person.global_transform,correction):person.move_and_collide(correction)
	pull_anchors[person.get_instance_id()]=person.global_position
	var face=board_handle.global_position-person.global_position;face.y=0
	person.heading_yaw=atan2(-face.z,face.x)
	person.get_node("WanderMind").command_cancel()
	person.get_node("WanderMind").set_manual_hold(true)

func stop_pull(person:CharacterBody3D) -> void:
	pullers.erase(person.get_instance_id());pull_anchors.erase(person.get_instance_id());person.get_node("WanderMind").command_stop(12)
	person.restore_action_pose()
	if person==room.actor:person.input_override=false;person.can_control=true

func is_pulling(person:CharacterBody3D) -> bool:return pullers.has(person.get_instance_id())

func _call_coop_partner(player_x:float) -> void:
	var npc=room.companion
	if to_local(npc.global_position).z<PASSAGE_LENGTH or npc.global_position.distance_to(room.actor.global_position)>2.6:return
	npc.get_node("WanderMind").command_walk(to_global((COOP_B if player_x<.1 else COOP_A)+Vector3.UP*BUTTON_TOP),12)
	npc.set_meta("join_coop",true)

func _holds_eight(person:CharacterBody3D) -> bool:
	# Use the carried item's identity rather than the spawn instance pointer;
	# this also covers a restored/reloaded eight ball with the same prop metadata.
	var carried=room.prop_interaction.held if room.prop_interaction.actor==person else null
	return is_instance_valid(carried) and carried.get_meta("black8",false)

func _physics_process(delta:float) -> void:
	if not room.ready_to_play:return
	_update_cue(delta);_update_pull(delta);_update_lift(delta)
	for person in [room.actor,room.companion]:last_positions[person.get_instance_id()]=to_local(person.global_position)

func _move_cue_to(target:Vector3,can_hit:bool) -> bool:
	var motion=global_basis*(target-cue.position)
	if motion.length_squared()<.00000001:return false
	cue_query.transform=cue_shape.global_transform;cue_query.motion=motion
	var result=get_world_3d().direct_space_state.cast_motion(cue_query)
	var fraction=float(result[0]) if result.size()>0 else 1.0
	var hit=false
	if fraction<1.0 and can_hit:
		# Test at the swept contact, not at the final extended position. Even a
		# fast shaft cannot tunnel through a head between physics ticks.
		cue_query.transform.origin+=motion*minf(1.0,float(result[1])+.003/maxf(motion.length(),.001))
		cue_query.motion=Vector3.ZERO
		for contact in get_world_3d().direct_space_state.intersect_shape(cue_query,8):
			var body=contact.collider
			if body is CharacterBody3D and body.has_method("begin_cue_roll") and body.state!="flattened" and not _holds_eight(body):
				if body.cue_mode=="":
					body.begin_cue_roll(self,true);cue_target=body;cue_strikes+=1;cue_hit_count+=1
					cue_sound.global_position=body.global_position;_sound(.90)
					body.set_meta("cue_contact_point",cue_query.transform.origin)
					hit=true
	cue.position=cue.position.lerp(target,maxf(0.0,fraction-.001)) if fraction<1 else target
	return hit

func _update_cue(delta:float) -> void:
	cue_age+=delta
	if cue_phase=="armed":
		for person in [room.actor,room.companion]:
			var p=to_local(person.global_position);var old:Vector3=last_positions.get(person.get_instance_id(),p)
			if person.state=="flattened" or person.cue_mode!="" or _holds_eight(person):continue
			var on_axis=absf(p.x)<PASSAGE_HALF+.045 and p.y<PASSAGE_CEILING
			if on_axis and ((p.z>=TRIGGER_Z and p.z<SAFE_Z) or (old.distance_to(p)<2 and old.z<TRIGGER_Z and p.z>=SAFE_Z)):
				cue_target=person;cue_phase="windup";cue_age=0;cue_contact_z=maxf(TRIGGER_Z-.20,p.z-.20);break
	elif cue_phase=="windup":
		_move_cue_to(Vector3(0,CUE_HEIGHT,CUE_HOME_Z+.06*smoothstep(0,.12,cue_age)),false)
		if cue_age>=.12:cue_phase="strike";cue_age=0
	elif cue_phase=="strike":
		var progress=clampf(cue_age/CUE_STRIKE_TIME,0,1)
		var target=Vector3(0,CUE_HEIGHT,lerpf(CUE_HOME_Z+.06,cue_contact_z+.30,progress))
		var touched=_move_cue_to(target,true)
		if touched or progress>=1:cue_retract_start=cue.position;cue_phase="retract";cue_age=0
	elif cue_phase=="retract":
		# Retraction time stays independent of the longer wall recess, so moving
		# the cue does not grant an extra shortcut between the two hiding slots.
		_move_cue_to(cue_retract_start.lerp(Vector3(0,CUE_HEIGHT,CUE_HOME_Z),clampf(cue_age/CUE_RETRACT_TIME,0,1)),false)
		if absf(cue.position.z-CUE_HOME_Z)<.002:cue_phase="reload";cue_age=0
	elif cue_phase=="reload":
		_move_cue_to(Vector3(0,CUE_HEIGHT,CUE_HOME_Z),false)
		if cue_age>CUE_RELOAD_TIME:cue_phase="armed";cue_age=0
	board_compression=move_toward(board_compression,0,delta*2.4)
	board.position.y=lerpf(-.25,.20,board_weight);board.position.z=BOARD_Z-board_compression*.14
	board.scale.z=1-board_compression*.48

func _sound(pitch:float) -> void:
	if room.sounds_enabled:cue_sound.pitch_scale=pitch;cue_sound.play()

func bounce_board() -> void:board_compression=1;_sound(1.45)

func _update_pull(delta:float) -> void:
	var board_held=false;var together=0
	for id in pullers.keys():
		var person=instance_from_id(id)
		if not is_instance_valid(person) or person.state in ["flattened","stunned","roll"]:pullers.erase(id);continue
		person.override_direction=Vector3.ZERO;person.override_jump=false;person.override_roll=false;person.velocity=Vector3.ZERO
		var anchor:Vector3=pull_anchors.get(id,person.global_position)
		person.move_and_collide(anchor-person.global_position)
		if pullers[id]=="board":board_held=true
		else:together+=1
	board_weight=move_toward(board_weight,1.0 if board_held else 0.0,delta*2.8)
	board_handle.position.y=.19-board_weight*.025;board_handle.position.z=BOARD_HANDLE.z-.045-board_weight*.012
	# Each separate pressure pad needs its own fish. Merely pressing E nearby
	# does nothing. The nearby companion walks onto the free pad automatically.
	together=0;pressure_occupants=[null,null]
	for i in 2:
		var point:Vector3=COOP_A if i==0 else COOP_B
		for person in [room.actor,room.companion]:
			var p=to_local(person.global_position)
			if absf(p.x-point.x)<.268*BUTTON_SCALE*.5+.048 and absf(p.z-point.z)<.248*BUTTON_SCALE*.5+.048 and p.y<.14 and p.y>-.02 and person.is_on_floor() and person.cue_mode=="" and person.state!="flattened":pressure_occupants[i]=person;break
		var was_down=pressure_weights[i]>.01
		pressure_weights[i]=move_toward(pressure_weights[i],1.0 if pressure_occupants[i]!=null else 0.0,delta*5)
		var top=BUTTON_TOP-pressure_weights[i]*BUTTON_TRAVEL
		pressure_caps[i].position.y=top-.016
		pressure_contacts[i].shape.size.y=top;pressure_contacts[i].position.y=top*.5
		if not was_down and pressure_occupants[i]!=null:
			button_press_count+=1;button_audio.global_position=pressure_caps[i].global_position
			if room.sounds_enabled:button_audio.pitch_scale=.85;button_audio.play()
		if pressure_occupants[i]!=null:together+=1
		if not coop_done and pressure_occupants[i]==room.actor and not room.companion.get_meta("join_coop",false):_call_coop_partner(point.x)
	if pressure_occupants.has(room.companion) and not coop_done:
		room.companion.get_node("WanderMind").command_stop(12)
	if not coop_done:
		coop_weight=move_toward(coop_weight,1.0 if together>=2 else 0.0,delta*(.60 if together>=2 else .30))
		pedestal.position.y=lerpf(-.10,.19,smoothstep(0,1,coop_weight))
		if coop_weight>=1:
			coop_done=true;reward.show();room._show_toast("两只大肥鱼一起踩下按钮，星光升起来了！",4)
			for id in pullers.keys():
				if pullers[id]=="coop":stop_pull(instance_from_id(id))

func _on_lift(person:CharacterBody3D) -> bool:
	var p=lift.to_local(person.global_position)
	return absf(p.x)<.58 and absf(p.z)<.45 and absf(p.y-.0275)<.07 and person.velocity.y<.2

func _sense_lift() -> void:
	lift_occupants.clear();lift_flat_count=0
	for person in [room.actor,room.companion]:
		if _on_lift(person):
			lift_occupants.append(person)
			if person.state=="flattened":lift_flat_count+=1
	var bp=lift.to_local(room.iron_ball.global_position)
	lift_ball_on=absf(bp.x)<.60+room.iron_ball.radius and absf(bp.z)<.475+room.iron_ball.radius and absf(bp.y-room.iron_ball.radius-.028)<.18
	lift_ready=lift_occupants.size()==2 and lift_flat_count==1 and not lift_ball_on
	# Restore the original display weights: fish 100 kg, paper .5 kg, ball 180 kg.
	# Show the live total, but never revalidate the already latched lift trip.
	var weight=(lift_occupants.size()-lift_flat_count)*100.0+lift_flat_count*.5+(180.0 if lift_ball_on else 0.0)
	if weight!=lift_display_weight and is_instance_valid(lift_status):
		lift_display_weight=weight
		var amount=str(roundi(weight)) if is_equal_approx(weight,roundf(weight)) else "%.1f"%weight
		lift_status.text="当前负重  "+amount+" / 101 kg"
		lift_status.modulate=Color(.96,.48,.30) if weight>101 else Color(1,.90,.72)

func _update_lift(delta:float) -> void:
	_sense_lift();lift_use_age+=delta;lift_denied_age+=delta
	for person in [room.actor,room.companion]:
		var id=person.get_instance_id()
		if person in lift_occupants and lift_phase in ["starting","up","down","top"]:
			if not lift_platform_layers.has(id):lift_platform_layers[id]=person.platform_floor_layers
			person.platform_floor_layers=0
		elif lift_platform_layers.has(id):
			person.platform_floor_layers=lift_platform_layers[id];lift_platform_layers.erase(id)
	var active=lift_phase in ["starting","up","top"]
	var green=lift_ready or active
	lift_red.emission_energy_multiplier=0 if green else .75
	lift_green.emission_energy_multiplier=.75 if green else 0
	# The toy control compresses into a thin plate near the upper landing.
	# Its collision follows the same thickness, without scaling a physics body.
	var fold=lerpf(1.0,.045,smoothstep(1.45,1.87,lift_height))
	lift_control.scale.y=fold
	lift_control_collider.shape.size.y=.265*fold
	lift_control_collider.position.y=lift_control.position.y+.1325*fold
	var pull=sin(clampf(lift_use_age/.52,0,1)*PI)
	var denied=sin(lift_denied_age*38)*exp(-lift_denied_age*12)*.12 if lift_denied_age<.5 else 0.0
	lift_lever.rotation.x=-.35+pull*.95+denied
	if is_instance_valid(lift_operator) and lift_use_age>=.52:
		lift_operator.restore_action_pose();lift_operator=null
	if lift_phase=="starting":
		lift_age+=delta
		if lift_age>=.52:lift_phase="up";lift_age=0
	elif lift_phase in ["up","down"]:
		# Start conditions are latched. Recovery, weight and ball contacts never reset a trip.
		var previous=lift.global_position;lift_height=move_toward(lift_height,1.94 if lift_phase=="up" else 0.0,delta*.85)
		lift.position.y=lift_height
		var motion=lift.global_position-previous
		for person in lift_occupants:
			person.global_position+=motion;person.velocity.y=minf(0,person.velocity.y)
		if lift_height>=1.94 and lift_phase=="up":lift_phase="top";lift_age=0
		if lift_height<=0 and lift_phase=="down":lift_phase="waiting";lift_age=0
	elif lift_phase=="top":
		lift_age+=delta
		if lift_age>1 and lift_occupants.is_empty():lift_phase="down";lift_passengers.clear()

func in_low_passage(point:Vector3) -> bool:
	var p=to_local(point)
	return p.y<PASSAGE_CEILING and p.z>-.10 and p.z<PASSAGE_LENGTH and absf(p.x)<.60

func navigation_path(start:Vector3,target:Vector3) -> Array[Vector3]:
	var path:Array[Vector3]=[];var a=to_local(start);var b=to_local(target)
	var ah=house.to_local(start);var bh=house.to_local(target)
	var target_inside=house.contains(target) or _in_puzzle(b)
	if not house.contains(start) and not _in_puzzle(a) and target_inside:
		path.append(house.to_global(Vector3(0,0,-.65)));path.append(house.to_global(Vector3(0,0,.75)))
	if a.z<0 and b.z>=0 and _in_puzzle(b):
		path.append(house.to_global(Vector3(0,0,.75)));path.append(to_global(Vector3(0,0,.20)))
	if a.z>=0 and _in_puzzle(a) and b.z<0:
		path.append(to_global(Vector3(0,0,minf(a.z,PASSAGE_LENGTH-.22))));path.append(to_global(Vector3(0,0,-.30)));path.append(house.to_global(Vector3(0,0,.75)))
	if b.z>=0 and b.z<PASSAGE_LENGTH and _in_puzzle(b):path.append(to_global(Vector3(0,0,b.z)))
	path.append(target);return path

func _in_puzzle(p:Vector3) -> bool:
	return p.y<1.2 and ((p.z>=0 and p.z<PASSAGE_LENGTH and absf(p.x)<.60) or (p.z>=PASSAGE_LENGTH-.12 and p.z<ROOM_BACK_Z+.04 and p.x> -1.13 and p.x<.74))

func patrol_target(point:Vector3,rng:RandomNumberGenerator) -> Vector3:
	var p=to_local(point)
	if house.contains(point):return house.to_global(Vector3(rng.randf_range(-.12,.12),0,rng.randf_range(.85,2.1)))
	if _in_puzzle(p):
		if p.z>=PASSAGE_LENGTH:return to_global(Vector3(rng.randf_range(-.65,.38),0,2.25+ROOM_SHIFT))
		if absf(p.x)>.23:return to_global(Vector3(signf(p.x)*ALCOVE_X,0,(ALCOVE_FRONT_Z if p.x<0 else ALCOVE_REAR_Z)))
		return to_global(Vector3(0,0,.18))
	return Vector3.INF

func _prepare_camera_collision() -> void:
	camera_query=PhysicsRayQueryParameters3D.new();camera_query.collision_mask=1|4
	camera_query.exclude=[room.actor.get_rid(),room.companion.get_rid()]

func _camera_clip(focus:Vector3,eye:Vector3) -> Vector3:
	camera_query.from=focus;camera_query.to=eye
	var hit=get_world_3d().direct_space_state.intersect_ray(camera_query)
	if not hit.is_empty():
		var d=focus.distance_to(hit.position)
		return focus+(eye-focus).normalized()*maxf(.025,d-.035)
	return eye

func update_camera(delta:float) -> bool:
	if room.actor==null:return false
	var point=room.actor.get_global_transform_interpolated().origin
	var inside=house.contains(point) or _in_puzzle(to_local(point))
	if not inside or room.overview:
		room.camera.near=.025
		return false
	var focus=point+Vector3.UP*(.055 if room.actor.state=="flattened" else .29)
	# No invisible walls, no roof cutaway, and no changes to input yaw/pitch.
	room.camera_focus=focus
	var distance=clampf(room.camera_distance*.43,.65,2.3)
	var offset=Vector3(sin(room.camera_yaw)*cos(room.camera_pitch),sin(room.camera_pitch),cos(room.camera_yaw)*cos(room.camera_pitch))*distance
	var clipped=_camera_clip(focus,focus+offset)
	var available=focus.distance_to(clipped)
	# Collapse immediately before penetrating a wall; ease only the outward recovery.
	camera_clear_distance=minf(available,lerpf(camera_clear_distance,available,1-exp(-delta*7)))
	var desired=focus+offset.normalized()*camera_clear_distance
	# In a tight alcove a normal wall pull-in puts the lens inside the hair.
	# Lift only the obstructed camera above the head, below the ceiling, while
	# retaining the user's orbit direction. No wall fading or preset viewpoint.
	var tight=0.0 if room.actor.state=="flattened" else 1.0-smoothstep(.19,.46,available)
	desired.y=maxf(desired.y,lerpf(desired.y,point.y+.52,tight))
	room.camera.position=_camera_clip(focus,room.camera.position.lerp(desired,1-exp(-delta*12)))
	var look_target=focus-Vector3.UP*(tight*.10)
	if room.camera.position.distance_squared_to(look_target)>.00001:room.camera.look_at(look_target)
	room.camera.fov=68;room.camera.near=.012
	room.attributes.dof_blur_far_enabled=false;room.attributes.dof_blur_near_enabled=false
	return true

func _process(_delta:float) -> void:
	if not room.ready_to_play:return
	prompt.visible=room.hud.visible and not room.paused
	var p=to_local(room.actor.position);prompt.text=""
	if _near_lift_lever(room.actor):prompt.text="E  拉动电梯开关"+(" · 条件满足" if lift_ready else " · 红灯：条件未满足")
	elif house.to_local(room.actor.global_position).distance_to(book_point)<.62:prompt.text="E  翻开小书"
	elif is_pulling(room.actor):prompt.text="正在拉住机关 · E 松手 · Alt 换人"
	elif p.distance_to(BOARD_HANDLE)<.40:prompt.text="E  拉动挡板机关"
	elif not coop_done and minf(p.distance_to(COOP_A),p.distance_to(COOP_B))<.36:prompt.text="两只大肥鱼分别踩住按钮"
	elif room.actor.state=="flattened":prompt.text="纸片状态 · 可以贴着地面移动"

func reset_actions() -> void:
	for id in pullers.keys():
		var person=instance_from_id(id)
		if is_instance_valid(person):stop_pull(person)
	pullers.clear();pull_anchors.clear();board_weight=0;cue_phase="armed";cue_age=0;cue.position=Vector3(0,CUE_HEIGHT,CUE_HOME_Z)
	for person in [room.actor,room.companion]:
		if person.cue_mode!="":person.end_cue_roll(false)
		person.get_node("WanderMind").command_cancel()
