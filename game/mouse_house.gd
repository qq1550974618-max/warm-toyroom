extends Node3D
# A real room behind the east wall, between the desk and the north bookcase end.
# Existing wall UVs and
# UV2s are interpolated at the cut so the surrounding authored finish survives.
var room:Node3D
var cut_report:Array=[]
var arch:Array[Vector2]=[]
var planes:Array[Vector3]=[]
var bodies:StaticBody3D
var wood:Material
var cream:Material
var blue:Material
var brass:Material
var rug:Material
var finishes=preload("res://mini_finishes.gd").new()
const DOOR_SCALE:=.5
var door_world:=Vector3(8.4,0,-3.78)
var facade_front:float=-.36
var door:Node3D
var cut_half_width=.543*DOOR_SCALE
var cut_max_y=1.113*DOOR_SCALE

func _ready() -> void:
	name="MouseHouse";position=door_world;rotation.y=PI*.5
	wood=finishes.finish("walnut")
	cream=finishes.finish("ivory")
	blue=finishes.finish("cotton")
	brass=finishes.finish("alloy")
	rug=load("res://room_kit/materials/legacy_antique_woven_rug_matte.tres")
	# The wall cut extends slightly behind the arch trim to avoid coplanar
	# surfaces on the inner jamb and the floor seal.
	arch.assign([Vector2(-.541*DOOR_SCALE,-.15),Vector2(.541*DOOR_SCALE,-.15)])
	for i in 65:arch.append(Vector2(cos(PI*i/64.0)*.541,.57+sin(PI*i/64.0)*.541)*DOOR_SCALE)
	for i in arch.size():
		var a:Vector2=arch[i];var b:Vector2=arch[(i+1)%arch.size()];var d:=b-a
		var n:=Vector2(d.y,-d.x).normalized();var w:float=n.dot(a)
		if n.dot(Vector2(0,.4*DOOR_SCALE))-w>0:n=-n;w=-w
		planes.append(Vector3(n.x,n.y,w))
	# Bay04 stays untouched: the former misplaced entrance is restored by loading
	# the original scene. Only the marked north-side panel receives a doorway.
	_cut_wall(room.room.get_node("Architecture/EastWall/Bay01"))
	_cut_wall(room.room.get_node("Architecture/FloorSeals/EastSeal"))
	bodies=StaticBody3D.new();bodies.name="SmallRoomContact";bodies.collision_layer=1;bodies.collision_mask=6;add_child(bodies)
	_build_shell()
	var start=get_child_count();var contact_start=bodies.get_child_count()
	_build_furniture()
	# Scale each furniture assembly and move the layout back, keeping the aisle clear.
	for node in get_children().slice(start):
		if node is Node3D:
			node.position=_furniture_position(node.position);node.scale*=.90
	for shape in bodies.get_children().slice(contact_start):
		shape.position=_furniture_position(shape.position);shape.shape=shape.shape.duplicate();
		if shape.shape is BoxShape3D:shape.shape.size*=.90
		elif shape.shape is CylinderShape3D:shape.shape.radius*=.90;shape.shape.height*=.90
		elif shape.shape is ConvexPolygonShape3D:
			var vertices=shape.shape.points
			for i in vertices.size():vertices[i]*=.90
			shape.shape.points=vertices
	finishes.batch_details(self)
	door=preload("res://mouse_house_door.gd").new();door.house=self;door.room=room;add_child(door)
	print("MOUSE_HOUSE_READY ",JSON.stringify(cut_report))

func _vertex(a:Array,index:int,xf:Transform3D) -> Dictionary:
	var p:Vector3=a[Mesh.ARRAY_VERTEX][index]
	var result={"p":p,"q":xf*p,"n":a[Mesh.ARRAY_NORMAL][index] if a[Mesh.ARRAY_NORMAL]!=null else Vector3.UP}
	if a[Mesh.ARRAY_TEX_UV]!=null:result.uv=a[Mesh.ARRAY_TEX_UV][index]
	if a[Mesh.ARRAY_TEX_UV2]!=null:result.uv2=a[Mesh.ARRAY_TEX_UV2][index]
	if a[Mesh.ARRAY_TANGENT]!=null:
		var t=a[Mesh.ARRAY_TANGENT];result.t=Vector4(t[index*4],t[index*4+1],t[index*4+2],t[index*4+3])
	return result

func _mix(a:Dictionary,b:Dictionary,t:float) -> Dictionary:
	var v={}
	for k in a:v[k]=a[k].lerp(b[k],t)
	v.n=v.n.normalized();return v

func _distance(v:Dictionary,plane:Vector3) -> float:
	return v.q.x*plane.x+v.q.y*plane.y-plane.z

func _clip(poly:Array,plane:Vector3,keep_inside:bool) -> Array:
	var out=[]
	for i in poly.size():
		var a:Dictionary=poly[i];var b:Dictionary=poly[(i+1)%poly.size()]
		var da:=_distance(a,plane);var db:=_distance(b,plane)
		var ia:=da<=.000001 if keep_inside else da>=-.000001
		var ib:=db<=.000001 if keep_inside else db>=-.000001
		if ia:out.append(a)
		if ia!=ib and absf(da-db)>.000001:out.append(_mix(a,b,clampf(da/(da-db),0,1)))
	return out

func _emit(st:SurfaceTool,poly:Array) -> int:
	if poly.size()<3:return 0
	var count=0
	for i in range(1,poly.size()-1):
		if (poly[i].p-poly[0].p).cross(poly[i+1].p-poly[0].p).length_squared()<.000000000001:continue
		for v in [poly[0],poly[i],poly[i+1]]:
			st.set_normal(v.n)
			if v.has("uv"):st.set_uv(v.uv)
			if v.has("uv2"):st.set_uv2(v.uv2)
			if v.has("t"):st.set_tangent(Plane(v.t.x,v.t.y,v.t.z,v.t.w))
			st.add_vertex(v.p)
		count+=1
	return count

func _cut_wall(section:Node3D) -> void:
	for cs in section.find_children("*","CollisionShape3D",true,false):cs.disabled=true
	for m in section.find_children("*","MeshInstance3D",true,false):
		var output:=ArrayMesh.new();var xf:Transform3D=global_transform.affine_inverse()*m.global_transform
		var local_bounds:AABB=xf*m.mesh.get_aabb()
		facade_front=minf(facade_front,local_bounds.position.z-.018)
		var before=0;var after=0
		for si in m.mesh.get_surface_count():
			var a=m.mesh.surface_get_arrays(si);var indices=a[Mesh.ARRAY_INDEX]
			if indices==null or indices.size()==0:
				indices=PackedInt32Array();for j in a[Mesh.ARRAY_VERTEX].size():indices.append(j)
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(m.mesh.surface_get_material(si))
			for j in range(0,indices.size(),3):
				before+=1
				var poly=[_vertex(a,indices[j],xf),_vertex(a,indices[j+1],xf),_vertex(a,indices[j+2],xf)]
				if (poly[0].q.y>cut_max_y and poly[1].q.y>cut_max_y and poly[2].q.y>cut_max_y) or (poly[0].q.x< -cut_half_width and poly[1].q.x< -cut_half_width and poly[2].q.x< -cut_half_width) or (poly[0].q.x>cut_half_width and poly[1].q.x>cut_half_width and poly[2].q.x>cut_half_width):
					after+=_emit(st,poly);continue
				for plane in planes:
					if poly.size()<3:break
					after+=_emit(st,_clip(poly,plane,false));poly=_clip(poly,plane,true)
			st.index();st.commit(output)
		m.mesh=output
		# Perforated static wall contacts, generated once while loading.
		var body=StaticBody3D.new();body.name="PortalWallContact";body.collision_layer=1;body.collision_mask=6;m.add_child(body)
		var cs=CollisionShape3D.new();cs.shape=output.create_trimesh_shape();body.add_child(cs)
		cut_report.append({"mesh":str(m.name),"before":before,"after":after,"front_z":local_bounds.position.z})

func _material(color:Color,roughness:float=.75) -> StandardMaterial3D:
	var m=StandardMaterial3D.new();m.albedo_color=color;m.roughness=roughness;m.metallic_specular=.28;return m

func _mesh(label:String,mesh:Mesh,point:Vector3,mat:Material) -> MeshInstance3D:
	var mi=MeshInstance3D.new();mi.name=label;mi.mesh=mesh;mi.material_override=mat;mi.position=point;mi.layers=4;mi.gi_mode=GeometryInstance3D.GI_MODE_DYNAMIC;add_child(mi)
	mi.set_meta("authored_detail_label",label)
	if label in ["Pillow","Linen lampshade","Small ceramic plate"]:
		var cs=CollisionShape3D.new();cs.shape=mesh.create_convex_shape(true,false);cs.position=point;bodies.add_child(cs)
	if label in ["Thread winding","Rug fringe"] or label.begins_with("Fine "):mi.set_meta("mini_static_detail",true)
	return mi

func _contact(point:Vector3,size:Vector3) -> void:
	var cs=CollisionShape3D.new();var box=BoxShape3D.new();box.size=size;cs.shape=box;bodies.add_child(cs);cs.position=point

func _box(label:String,p:Vector3,s:Vector3,mat:Material,solid:bool=false,r:float=.015) -> MeshInstance3D:
	var mesh:=BoxMesh.new();mesh.size=s
	# Rounded edges carry real highlights, rather than a flat un-bevelled cuboid.
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	r=minf(r,minf(s.x,minf(s.y,s.z))*.24)
	var inner=s*.5-Vector3.ONE*r
	for axis in 3:
		for sign in [-1,1]:
			var normal=Vector3.ZERO;normal[axis]=sign
			var u=normal.cross(Vector3.UP if axis!=1 else Vector3.BACK).normalized();var v=normal.cross(u)
			var hu=absf(u.dot(s))*.5;var hv=absf(v.dot(s))*.5
			var us=[-hu,-hu+r,0,hu-r,hu];var vs=[-hv,-hv+r,0,hv-r,hv]
			for x in 4:
				for y in 4:
					for c in [Vector2i(x,y),Vector2i(x,y+1),Vector2i(x+1,y+1),Vector2i(x,y),Vector2i(x+1,y+1),Vector2i(x+1,y)]:
						var raw=normal*s[axis]*.5+u*us[c.x]+v*vs[c.y]
						var base=raw.clamp(-inner,inner);var n=(raw-base).normalized()
						st.set_normal(n);st.set_uv(Vector2(us[c.x]+hu,vs[c.y]+hv)*2);st.add_vertex(base+n*r)
	st.index();st.generate_tangents();var mi=_mesh(label,st.commit(),p,mat)
	if solid or label in ["Teal quilt","Piece of cheese","Wall shelf"] or label.begins_with("Pocket book "):_contact(p,s)
	return mi

func _cylinder(label:String,p:Vector3,r:float,h:float,mat:Material) -> MeshInstance3D:
	var mesh=CylinderMesh.new();mesh.top_radius=r;mesh.bottom_radius=r;mesh.height=h;mesh.radial_segments=32
	var mi=_mesh(label,mesh,p,mat)
	if label in ["Spool tabletop","Spool thread","Spool foot","Turned bed foot","Chair leg","Lamp brass base","Lamp stem"]:
		var cs=CollisionShape3D.new();var shape=CylinderShape3D.new();shape.radius=r;shape.height=h;cs.shape=shape;cs.position=p;bodies.add_child(cs)
	return mi

func _build_shell() -> void:
	var plaster=load("res://room_kit/materials/legacy_ivory_lime_plaster.tres")
	var ash=load("res://room_kit/materials/legacy_frame_pale_ash_wood.tres")
	# The arrow expands the table side of the original room, not the rear wall.
	_contact(Vector3(-.39,-.045,1.18),Vector3(3.48,.09,3.16))
	for i in 13:
		var plank=_box("Oak floorboard %02d"%i,Vector3(-1.98+i*.268,-.025,1.53),Vector3(.266,.05,2.46),finishes.finish("floor"),false,.003)
		plank.mesh=finishes.plank_uv(plank.mesh,.266,2.46)
		var grain=plank.material_override.duplicate();grain.uv1_offset=Vector3(i*.073,(i%11)*.076,0);plank.material_override=grain
	# House boards start behind the facade. Only a narrow threshold crosses the
	# portal; no coplanar strip may extend into the main room's authored floor.
	_box("Doorway oak threshold",Vector3(0,-.018,(facade_front+.30)*.5),Vector3(.448,.040,.30-facade_front),wood,false,.001)
	_box("Limewash right side wall",Vector3(-2.14,.85,1.48),Vector3(.12,1.70,2.5),plaster,true)
	_box("Tiny right skirting",Vector3(-2.07,.065,1.48),Vector3(.055,.13,2.5),ash)
	# Entering +Z, the player's left is local +X. Leave a small opening next
	# to the green entrance wall, before the bed foot. No bulky timber frame.
	for span in [Vector2(.23,.49),Vector2(1.01,2.73)]:
		_box("Left wall beside passage",Vector3(1.36,.85,(span.x+span.y)*.5),Vector3(.12,1.70,span.y-span.x),plaster,true)
		_box("Left skirting beside passage",Vector3(1.295,.065,(span.x+span.y)*.5),Vector3(.055,.13,span.y-span.x),ash)
	_box("Limewash above small passage",Vector3(1.36,1.125,.75),Vector3(.12,1.15,.52),plaster,true)
	var front=Node3D.new();front.name="Doorway backing wall";add_child(front)
	var lining=_box("Painted wall behind facade",Vector3(-.39,.85,.29),Vector3(3.58,1.70,.12),load("res://room_kit/materials/mk_sage_painted_wood.tres"),false,.002)
	lining.reparent(front);_cut_wall(front)
	_box("Limewash back wall",Vector3(-.39,.85,2.73),Vector3(3.58,1.70,.12),plaster,true)
	_box("Mouse house ceiling",Vector3(-.39,1.75,1.40),Vector3(3.58,.10,2.8),plaster,true)
	_box("Back skirting",Vector3(-.39,.065,2.64),Vector3(3.42,.13,.06),ash)
	# Portal lining and arch match the mousehole silhouette; no fake dark decal.
	for x in [-.505,.505]:_box("Arched doorway jamb",Vector3(x*DOOR_SCALE,.285*DOOR_SCALE,(facade_front+.30)*.5),Vector3(.07*DOOR_SCALE,.57*DOOR_SCALE,.30-facade_front),ash,false,.009*DOOR_SCALE)
	var st=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 64:
		var a=PI*i/64;var b=PI*(i+1)/64
		for face in 4:
			var ps=[];var ns=[]
			for corner in [Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(1,0)]:
				var angle=lerpf(a,b,corner.x);var r=(lerpf(.47,.54,corner.y) if face<2 else (.47 if face==2 else .54))*DOOR_SCALE
				var z=(facade_front if face==0 else .30) if face<2 else lerpf(facade_front,.30,corner.y)
				ps.append(Vector3(cos(angle)*r,.57*DOOR_SCALE+sin(angle)*r,z))
				ns.append(Vector3(0,0,-1 if face==0 else 1) if face<2 else Vector3(cos(angle),sin(angle),0)*(-1 if face==2 else 1))
			var order=[0,1,2,0,2,3] if face in [0,3] else [0,2,1,0,3,2]
			for c in order:st.set_normal(ns[c]);st.set_uv(Vector2(ps[c].x,ps[c].y));st.add_vertex(ps[c])
	st.index();st.generate_tangents();_mesh("Continuous smooth arch",st.commit(),Vector3.ZERO,ash)
	# The user requested a plain entrance: no lettering or sign above the arch.
	var lamp=OmniLight3D.new();lamp.name="Mouse room warm practical";lamp.position=Vector3(-.73,1.22,1.85);lamp.light_color=Color(1,.79,.51);lamp.light_energy=.52;lamp.omni_range=3.7;lamp.omni_attenuation=1.25;lamp.shadow_enabled=true;lamp.light_size=.22;lamp.light_bake_mode=Light3D.BAKE_DYNAMIC;lamp.light_cull_mask=6;add_child(lamp)
	var fill=OmniLight3D.new();fill.name="Mouse room bounced light";fill.position=Vector3(.7,.9,.8);fill.light_color=Color(.87,.88,1);fill.light_energy=.11;fill.omni_range=2.2;fill.light_specular=.1;fill.light_cull_mask=6;add_child(fill)

func _build_furniture() -> void:
	var red=finishes.finish("paint_rust")
	var cheese=finishes.finish("cheese")
	# Matchbox bed, quilt, pillow, bound seams and wooden head/foot boards.
	_box("Matchbox bed frame",Vector3(.77,.15,1.79),Vector3(.78,.28,1.24),wood,true,.026)
	_box("Ivory mattress",Vector3(.77,.325,1.79),Vector3(.74,.10,1.18),cream,true,.022)
	_box("Teal quilt",Vector3(.77,.39,1.58),Vector3(.72,.055,.77),blue,false,.012)
	for side in [-1,1]:_box("Quilt piping",Vector3(.77+side*.34,.415,1.58),Vector3(.009,.008,.73),cream,false,.002)
	_mesh("Pillow",finishes.cushion(Vector3(.58,.12,.29)),Vector3(.77,.423,2.19),cream)
	_box("Bed headboard",Vector3(.77,.34,2.44),Vector3(.80,.65,.07),wood,true)
	_box("Bed footboard",Vector3(.77,.22,1.15),Vector3(.80,.4,.06),wood,true)
	for x in [.47,1.07]:
		for z in [1.27,2.3]:_cylinder("Turned bed foot",Vector3(x,.07,z),.043,.14,wood)
	# Spool table and a small chair, with clean contact volumes.
	_cylinder("Spool tabletop",Vector3(-.65,.52,1.69),.37,.06,wood)
	_cylinder("Spool thread",Vector3(-.65,.28,1.69),.17,.43,blue)
	_cylinder("Spool foot",Vector3(-.65,.055,1.69),.29,.07,wood)

	for i in 25:
		var tor=TorusMesh.new();tor.inner_radius=.166;tor.outer_radius=.174;tor.rings=32;tor.ring_segments=4
		_mesh("Thread winding",tor,Vector3(-.65,.10+i*.014,1.69),finishes.finish("thread"))
	_box("Chair seat",Vector3(-.73,.23,.94),Vector3(.37,.06,.34),red,true)
	_box("Chair back",Vector3(-.73,.39,.79),Vector3(.36,.36,.045),red,true)
	for x in [-.88,-.58]:
		for z in [.81,1.07]:_cylinder("Chair leg",Vector3(x,.105,z),.022,.21,wood)
	_box("Woven miniature rug",Vector3(0,.008,.73),Vector3(1.1,.012,.70),rug,false,.002)
	for i in 28:
		for z in [.36,1.10]:_box("Rug fringe",Vector3(-.52+i*.039,.012,z),Vector3(.008,.006,.06),cream,false,.001)
	# Bottle-cap lamp and a tiny plate with cheese.
	_cylinder("Lamp brass base",Vector3(-.70,.574,1.93),.085,.025,brass)
	_cylinder("Lamp stem",Vector3(-.70,.75,1.93),.012,.34,brass)
	var shade=CylinderMesh.new();shade.top_radius=.072;shade.bottom_radius=.13;shade.height=.17;shade.radial_segments=32
	_mesh("Linen lampshade",shade,Vector3(-.70,.94,1.93),cream)
	_mesh("Small ceramic plate",finishes.lathe([Vector2(.001,0),Vector2(.08,0),Vector2(.112,.006),Vector2(.123,.014),Vector2(.122,.020),Vector2(.116,.022),Vector2(.102,.015),Vector2(.076,.008),Vector2(.001,.008)]),Vector3(-.57,.554,1.51),finishes.finish("porcelain"))
	_box("Piece of cheese",Vector3(-.58,.60,1.51),Vector3(.13,.06,.10),cheese,false,.012)
	# Framed mouse-height picture, shelving and books give the rear wall scale.
	_box("Picture frame",Vector3(-.18,1.13,2.635),Vector3(.54,.42,.045),wood)
	_box("Picture paper",Vector3(-.18,1.13,2.609),Vector3(.47,.35,.008),finishes.finish("paper"))
	var illustration=load("res://assets/puzzle_v27/whale_friends_painting.png") as Texture2D
	var ink=finishes.finish("paper").duplicate();ink.albedo_color=Color.WHITE;ink.uv1_scale=Vector3.ONE;ink.albedo_texture=illustration;ink.roughness=.84;ink.metallic_specular=.22
	var canvas=QuadMesh.new();canvas.size=Vector2(.465,.34875)
	var picture=_mesh("Three whale friends storybook painting",canvas,Vector3(-.18,1.13,2.603),ink);picture.rotation.y=PI
	_box("Wall shelf",Vector3(-.79,.92,2.53),Vector3(.70,.045,.22),wood)
	for i in 5:
		var x=-1.02+i*.095;var height=.26+sin(i)*.035;var cover=finishes.finish("book_rust" if i%2==0 else "book_teal")
		_box("Pocket book %d"%i,Vector3(x,1.07,2.53),Vector3(.078,height,.15),cover,false,.005)
		_box("Fine pocket book paper",Vector3(x,1.07+height*.5+.001,2.534),Vector3(.060,.003,.129),finishes.finish("paper"),false,.001)
		for y in [1.07-height*.34,1.07+height*.34]:_box("Fine book spine foil",Vector3(x,y,2.453),Vector3(.064,.007,.002),brass,false,.0004)
	_build_furniture_detail()

func _build_furniture_detail() -> void:
	# Recessed panels, joinery, stitching and turned profiles are separate
	# physical-scale details, merged once after the furniture layout is applied.
	var trim=finishes.finish("paint_cream")
	for z in [1.113,2.399]:
		_box("Fine bed inset field",Vector3(.77,.285,z),Vector3(.64,.22,.008),finishes.finish("paint_teal"),false,.005)
		for x in [.435,1.105]:_box("Fine bed panel stile",Vector3(x,.285,z-.005),Vector3(.022,.26,.015),wood,false,.003)
		for y in [.155,.415]:_box("Fine bed panel rail",Vector3(.77,y,z-.006),Vector3(.69,.023,.016),wood,false,.003)
	for x in [.435,1.105]:
		for z in [1.25,2.29]:_cylinder("Fine bed peg",Vector3(x,.294,z),.008,.006,brass)
	for side in [-1,1]:
		for i in 25:_box("Fine quilt running stitch",Vector3(.77+side*.33,.419,1.24+i*.028),Vector3(.003,.002,.009),cream,false,.0004)
	for z in [1.25,1.91]:
		for i in 20:_box("Fine quilt cross stitch",Vector3(.46+i*.032,.419,z),Vector3(.010,.002,.003),cream,false,.0004)
	# A curved welt follows the pillow edge, never a straight line through it.
	for j in 80:
		var a=TAU*j/80;var b=TAU*(j+1)/80
		var p=Vector3(.77,.423,2.19)+finishes._cushion_point(a,PI*.5,Vector3(.580,.12,.290));var q=Vector3(.77,.423,2.19)+finishes._cushion_point(b,PI*.5,Vector3(.580,.12,.290))
		var mesh=CylinderMesh.new();mesh.top_radius=.0025;mesh.bottom_radius=.0025;mesh.height=p.distance_to(q);mesh.radial_segments=8
		var mi=_mesh("Fine pillow welt",mesh,(p+q)*.5,cream);mi.quaternion=Quaternion(Vector3.UP,(q-p).normalized())
	# The spool's rims and lamp edge catch restrained highlights.
	for y in [.497,.543]:
		var t=TorusMesh.new();t.inner_radius=.359;t.outer_radius=.369;t.rings=64;t.ring_segments=10;_mesh("Fine spool rim",t,Vector3(-.65,y,1.69),wood)
	for row in [[.858,.125],[1.023,.072]]:
		var t=TorusMesh.new();t.inner_radius=row[1]-.003;t.outer_radius=row[1]+.003;t.rings=48;t.ring_segments=8;_mesh("Fine lampshade bound edge",t,Vector3(-.70,row[0],1.93),trim)
	for x in [-.879,-.581]:
		_box("Fine chair back stile",Vector3(x,.39,.763),Vector3(.018,.32,.012),wood,false,.003)
		_box("Fine chair stretcher",Vector3(x,.105,.94),Vector3(.014,.022,.27),wood,false,.003)
	for z in [.805,1.075]:_box("Fine chair seat edge",Vector3(-.73,.257,z),Vector3(.32,.010,.010),trim,false,.002)
	for x in [-1.04,-.55]:
		_box("Fine shelf bracket",Vector3(x,.86,2.57),Vector3(.028,.10,.12),brass,false,.004)

func contains(point:Vector3) -> bool:
	var p=to_local(point);return p.x> -2.08 and p.x<1.30 and p.z>.22 and p.z<2.70 and p.y<1.7

func _furniture_position(p:Vector3) -> Vector3:
	# Retain bed/table/chair arrangement, shrink assemblies by 10%, keep the
	# entrance cross-aisle at z=.75 clear for physical roll-out and rebound.
	if p.y>.8 and p.z>2.40:return Vector3(p.x*.90-.18,p.y*.90,p.z-.025)
	return p*.90+Vector3(-.45 if p.x<-.3 else (.15 if p.x>.3 else 0.0),0,.20)

func cut_flat_entrance(center_x:float,width:float,height:float) -> void:
	var saved_planes=planes.duplicate();var saved_transform=transform
	cut_half_width=width*.5+.01;cut_max_y=height+.01
	# Clip the outer architectural meshes and their physical seals identically.
	position=door_world+global_basis.x*center_x
	planes=[Vector3(1,0,width*.5),Vector3(-1,0,width*.5),Vector3(0,1,height),Vector3(0,-1,.15)]
	_cut_wall(room.room.get_node("Architecture/EastWall/Bay00"))
	_cut_wall(room.room.get_node("Architecture/FloorSeals/EastSeal"))
	transform=saved_transform;planes.assign(saved_planes);cut_half_width=.543*DOOR_SCALE;cut_max_y=1.113*DOOR_SCALE
