extends "res://iron_ball.gd"
var playground:Node3D
var track_mode="ready"
var roll_age=0.0
var first_contact_time=-1.0
var start_z=-6.13
var guided_fall=false
func _ready() -> void:
	super._ready();name="DeskIronBall";freeze=true
func _physics_process(delta:float) -> void:
	if track_mode=="ready":return
	if track_mode=="rolling":
		roll_age+=delta
		var target_z=lerpf(start_z,-4.10,minf(roll_age/3.0,1))
		var target_speed=clampf((target_z-global_position.z)*9.0+.68,0,.95)
		var force=Vector3((playground.BALL_HOME.x-global_position.x)*45-linear_velocity.x*10,0,(target_speed-linear_velocity.z)*16)
		apply_central_force(force*mass)
		if roll_age>=3.0:
			playground.open_gate()
			track_mode="falling";guided_fall=false
	elif track_mode=="falling":
		roll_age+=delta
		if not guided_fall and global_position.y<playground.TABLE_Y-.75:
			# Keep the desk fixed. A longer ballistic arc reaches the relocated
			# orange end, and ordinary rigid-body collision delivers the impact.
			var target=playground.seat_point(1)+Vector3.UP*radius
			var gravity=float(ProjectSettings.get_setting("physics/3d/default_gravity",9.8))
			var duration=(linear_velocity.y+sqrt(linear_velocity.y*linear_velocity.y+2*gravity*maxf(.1,global_position.y-target.y)))/gravity
			var damping=linear_damp+.1;var gain=(1-exp(-damping*duration))/damping
			linear_velocity.x=(target.x-global_position.x)/gain;linear_velocity.z=(target.z-global_position.z)/gain;guided_fall=true
		elif not guided_fall:apply_central_force(Vector3(0,0,.55-linear_velocity.z)*mass*10)
	super._physics_process(delta)
func _contact(body:Node) -> void:
	if playground!=null and body==playground.beam and track_mode=="falling":
		first_contact_time=roll_age;track_mode="spent"
		playground.ball_hit.call_deferred(previous_velocity)
	else:super._contact(body)
func can_grip() -> bool:
	return track_mode=="spent" and super.can_grip()
