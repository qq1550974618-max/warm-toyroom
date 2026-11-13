extends Node3D

var sounds:Dictionary={}
var counts:Dictionary={"marble":0,"pencil":0,"reel":0}
var last_events:Array=[]
var bursts:Array=[]
var dot:GradientTexture2D
var rng:=RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed=1204
	var gradient:=Gradient.new();gradient.offsets=PackedFloat32Array([0,.2,.65,1]);gradient.colors=PackedColorArray([Color.WHITE,Color(1,1,1,.8),Color(1,1,1,.15),Color(1,1,1,0)])
	dot=GradientTexture2D.new();dot.gradient=gradient;dot.width=64;dot.height=64;dot.fill=GradientTexture2D.FILL_RADIAL;dot.fill_from=Vector2(.5,.5);dot.fill_to=Vector2(1,.5)
	for kind in ["marble","pencil","reel","chicken"]:sounds[kind]=_make_sound(kind)

func _make_sound(kind:String) -> AudioStreamWAV:
	var rate:=22050;var duration:=.20 if kind=="marble" else (.24 if kind=="pencil" else .32)
	var data:=PackedByteArray();var count:=int(rate*duration);data.resize(count*2);var low:=0.0
	for i in count:
		var t:=float(i)/rate;var noise:=rng.randf_range(-1,1);low=lerpf(low,noise,.16);var value:=0.0
		if kind=="marble":value=(sin(t*TAU*2350)+.4*sin(t*TAU*3910))*exp(-t*52)*.36+noise*exp(-t*300)*.3
		elif kind=="pencil":
			value=noise*exp(-t*75)*.5+sin(t*TAU*760)*exp(-t*42)*.25
			if t>.035:value+=(noise*.28+sin((t-.035)*TAU*1050)*.18)*exp(-(t-.035)*70)
		else:value=low*exp(-t*23)*.8+sin(t*TAU*170)*exp(-t*28)*.42+sin(t*TAU*405)*exp(-t*47)*.16
		value*=minf(t*1800,1);data.encode_s16(i*2,int(clampf(value,-.95,.95)*24000))
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=rate;stream.data=data;return stream

func burst(kind:String,point:Vector3,normal:Vector3,speed:float) -> void:
	if bursts.size()>=10:return
	counts[kind]=int(counts.get(kind,0))+1
	last_events.append({"kind":kind,"point":str(point),"normal":str(normal),"speed":speed,"frame":Engine.get_physics_frames()})
	if last_events.size()>32:last_events.pop_front()
	var root:=Node3D.new();root.position=point+normal*.006;add_child(root)
	var bright:bool=kind=="marble";var lifetime:=.18 if bright else (.32 if kind=="pencil" else .44)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED;material.albedo_texture=dot
	material.albedo_color=Color(.82,.91,1,.72) if bright else Color(.65,.52,.36,.35)
	var quad:=QuadMesh.new();quad.size=Vector2.ONE*(.018 if bright else (.025 if kind=="pencil" else .043))
	var pieces:Array=[]
	var side:Vector3=normal.cross(Vector3.FORWARD).normalized()
	if side.length()<.1:side=Vector3.RIGHT
	var forward:Vector3=normal.cross(side).normalized()
	for i in (4 if bright else (5 if kind=="pencil" else 7)):
		var mesh:=MeshInstance3D.new();mesh.mesh=quad;mesh.material_override=material;mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;mesh.gi_mode=GeometryInstance3D.GI_MODE_DISABLED;root.add_child(mesh)
		var angle:=rng.randf_range(0,TAU);var velocity:Vector3=(side*cos(angle)+forward*sin(angle))*rng.randf_range(.06,.18)+normal*rng.randf_range(.08,.22)
		pieces.append({"mesh":mesh,"velocity":velocity*clampf(speed/2,.65,1.5)})
	bursts.append({"root":root,"age":0.0,"life":lifetime,"material":material,"alpha":material.albedo_color.a,"pieces":pieces,"bright":bright})

func _process(delta:float) -> void:
	for index in range(bursts.size()-1,-1,-1):
		var effect:Dictionary=bursts[index];effect.age+=delta
		if effect.age>=effect.life:effect.root.queue_free();bursts.remove_at(index);continue
		var ratio:float=effect.age/effect.life
		effect.material.albedo_color.a=effect.alpha*(1-ratio)*(1-ratio)
		for piece in effect.pieces:
			piece.mesh.position+=piece.velocity*delta
			piece.mesh.scale=Vector3.ONE*(1.0-ratio*.45 if effect.bright else 1.0+ratio*1.4)
			piece.velocity*=exp(-delta*3.0)
