extends RefCounted
const MANIFEST="res://room_kit/quality/v20/manifest.json"
# Restore the V7 coating only on the five book-cover material groups.
# Current geometry, UVs, embossed titles and full-resolution texture maps remain.
const BOOK_FINISHES={
	"Room/Props/BookRoute/Model/Room Dust blue lacquer_001":preload("res://room_kit/quality/v21/book_floor_dust_blue.tres"),
	"Room/Props/BookRoute/Model/Room Moss green lacquer_002":preload("res://room_kit/quality/v21/book_floor_moss_green.tres"),
	"Room/Props/BookRoute/Model/Room Muted oxblood lacquer_002":preload("res://room_kit/quality/v21/book_floor_muted_oxblood.tres"),
	"Room/Props/WritingDesk/Model/Room Moss green lacquer_001":preload("res://room_kit/quality/v21/book_desk_moss_green.tres"),
	"Room/Props/WritingDesk/Model/Room Muted oxblood lacquer_001":preload("res://room_kit/quality/v21/book_desk_muted_oxblood.tres")
}
var bindings:Array=[]
var mesh_bindings:Array=[]
var materials:Dictionary={}
var meshes:Dictionary={}
var active_ultra=false
var ready=false
static func material_key(m:Material) -> String:
	if not m.resource_path.is_empty():return m.resource_path
	var tint=m.get_shader_parameter("tint") if m is ShaderMaterial else m.get("albedo_color")
	return m.resource_name+"|"+str(tint)
func bind(room:Node) -> void:
	if OS.get_cmdline_user_args().has("--v20-author"):return
	if not FileAccess.file_exists(MANIFEST):return
	var data=JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for mi in room.find_children("*","MeshInstance3D",true,false):
		if mi.get_meta("v12_pencil_style",false):continue
		if mi.mesh==null:continue
		var path=str(room.get_path_to(mi))
		if meshes.has(path):mesh_bindings.append({"node":mi,"standard":mi.mesh,"ultra":meshes[path]})
		if mi.material_override!=null:
			_add(mi,-1,mi.material_override,path);continue
		for i in mi.mesh.get_surface_count():_add(mi,i,mi.get_active_material(i),path)
	ready=true
func _add(mi:MeshInstance3D,surface:int,source:Material,path:String) -> void:
	if source==null:return
	var key=material_key(source)
	var restored:Material=BOOK_FINISHES.get(path,materials.get(key))
	if restored!=null:bindings.append({"node":mi,"surface":surface,"standard":source,"ultra":restored})
func apply(ultra:bool) -> void:
	if not ready:return
	for row in mesh_bindings:
		if is_instance_valid(row.node):row.node.mesh=row.ultra if ultra else row.standard
	for row in bindings:
		if not is_instance_valid(row.node):continue
		var m=row.ultra if ultra else row.standard
		if row.surface<0:row.node.material_override=m
		else:row.node.set_surface_override_material(row.surface,m)
	active_ultra=ultra
