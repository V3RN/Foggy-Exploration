# warning-ignore-all:return_value_discarded
extends KinematicBody

export(float) var SPEED = 4
export(float) var ORBIT_SPEED = 2
export(float) var LIGHT_MAX_TIME = 30

export(float) var light_time = LIGHT_MAX_TIME
export(NodePath) var last_lamp_post

export(float) var DEBUG_SPRINT_SPEED = 10

var prev_objects_hidden = []

func _ready():
	$sfx/footstep/timer.connect("timeout", self, "footstep_timeout")
	$sfx/Lantern.play()

func _process(delta):
	# Decay lantern light
	light_time -= delta
	var light_ratio = light_time/LIGHT_MAX_TIME
#	$visuals/light.light_energy = light_time/LIGHT_MAX_TIME
	$visuals/light.omni_range = 9 * light_ratio + 1
	$fog.process_material.set_shader_param("innerRadius", 2 * light_ratio + 1)
	$fog.process_material.set_shader_param("outerRadius", 5 * light_ratio + 2)
	$hud.set_fuel(light_ratio)
	# Lantern gets quieter
	$sfx/Lantern.set_volume_db(light_ratio*20-40)
	if light_time <= 0:
		if last_lamp_post:
			# Spooky Death Sound, also restart fire sound because that stops for some reason
			$sfx/Death.play()
			$sfx/Lantern.play()
			# Respawn
			translation = get_node(last_lamp_post).get_node("respawn_point")\
				.global_transform.origin
			light_time = LIGHT_MAX_TIME
			# Snap to floor
			move_and_collide(Vector3(0, -3, 0))
			# Drop exposure for fade-in
			$camera.environment.tonemap_exposure = 0
		else:
			# Quit to title if no checkpoint (shouldn't ever happen)
			get_tree().change_scene("res://scenes/title_screen/TitleScreen.tscn")
	# Ramp exposure back up for respawn
	$camera.environment.tonemap_exposure = lerp(
		$camera.environment.tonemap_exposure, 1, 0.01)
	## HUD stuff
	# Set zone name
	for zone in get_tree().get_nodes_in_group("named_zone"):
		if zone.overlaps_body(self):
			$hud.set_location(zone.zone_name)
			break
	# Update arrow direction
	# Find nearest puzzle (or the gate if they're all solved)
	var nearest_puzzle: Spatial
	for puzzle in get_tree().get_nodes_in_group("puzzle"):
		if not puzzle in get_tree().get_nodes_in_group("solved"):
			if not nearest_puzzle:
				nearest_puzzle = puzzle
			elif global_transform.origin.distance_to(puzzle.global_transform.origin) \
				< global_transform.origin.distance_to(nearest_puzzle.global_transform.origin):
				nearest_puzzle = puzzle
	# Default to gate if all puzzles solved
	if not nearest_puzzle:
		nearest_puzzle = get_tree().get_nodes_in_group("gate")[0]
	# Hide if close to target
	$hud/arrow.visible = global_transform.origin.distance_to(nearest_puzzle.global_transform.origin) > 10
	# Find rotation
	var vec_to = (global_transform.origin - nearest_puzzle.global_transform.origin).normalized()
	var facing = $camera.global_transform.basis.z
	facing.y = 0
	facing = facing.normalized()
	var direction = sign(vec_to.dot(facing.rotated(Vector3.UP, -PI/2)))
	# Set rotation
	$hud.rotate_arrow(direction * vec_to.angle_to(facing) * 180/PI + 180)
	# Debug controls for testing
	if OS.is_debug_build():
		if Input.is_action_just_pressed("debug_refill_lantern"):
			light_time = LIGHT_MAX_TIME
		if Input.is_action_just_pressed("debug_respawn"):
			light_time = 0
		if Input.is_action_just_pressed("debug_solve_all"):
			var fake_puzzle = Node.new()
			fake_puzzle.add_to_group("solved")
			add_child(fake_puzzle)
			add_child(fake_puzzle.duplicate())
			add_child(fake_puzzle.duplicate())
			add_child(fake_puzzle.duplicate())
	# Rotate through fog quality settings
	if Input.is_action_just_pressed("fog_scroll"):
		if $fog.quality <= 0.5:
			$fog.quality = 2.0
		$fog.set_quality($fog.quality - 0.5)

func _physics_process(delta):
	## Camera movement ##
	# Original camera position
	var cam_pos = $camera.translation
	# Rotate the position about the origin
	if Input.is_action_pressed("orbit_left"):
		cam_pos = cam_pos.rotated(Vector3.UP, ORBIT_SPEED*delta)
	if Input.is_action_pressed("orbit_right"):
		cam_pos = cam_pos.rotated(Vector3.UP, -ORBIT_SPEED*delta)
	# Set new position
	$camera.translation = cam_pos
	# Point at character
	$camera.look_at(self.global_transform.origin, Vector3.UP)
	## Character movement ##
	# Direction camera is pointing, without Y
	var facing = -$camera.global_transform.basis.z
	facing.y = 0
	facing = facing.normalized()
	# Movement direction vector
	var dir = Vector3.ZERO
	# Add movement directions to direction vector
	# Movement directions calculated from direction camera is pointing
	if Input.is_action_pressed("move_up"):
		dir += facing
	if Input.is_action_pressed("move_down"):
		dir += facing.rotated(Vector3.UP, PI)
	if Input.is_action_pressed("move_left"):
		dir += facing.rotated(Vector3.UP, PI/2)
	if Input.is_action_pressed("move_right"):
		dir += facing.rotated(Vector3.UP, -PI/2)
	# Round vector to 0 if small to account for rounding error in rotation
	if dir.length() < 0.01:
		dir = Vector3.ZERO
	# Normalize vector to get pure direction
	dir = dir.normalized()
	# Select speed based on if sprinting (DEBUG)
	var speed = SPEED
	if OS.is_debug_build() and Input.is_action_pressed("debug_sprint"):
		speed = DEBUG_SPRINT_SPEED
	# Only move if actively moving to avoid sliding down slopes
	if dir != Vector3.ZERO:
		# Move kinematic body and slide against other colliders
		var velocity = self.move_and_slide_with_snap(
			dir*speed,
			Vector3(0, -3, 0), # snap
			Vector3.UP, # up_direction
			true, # stop_on_slope
			4, # max_slides
			PI/3 # floor_max_angle
		)
		# Move upward at full speed on slopes
		if get_slide_count() > 0:
			var collision = get_slide_collision(0)
			# Only move if slope is less than 60°
			if collision.normal.angle_to(Vector3.UP) <= PI/3:
				# Get distance left on move
				var remain_distance = speed*delta - velocity.length()*delta
				var new_move = dir.slide(collision.normal).normalized()*remain_distance
				move_and_collide(new_move)
	# Only do "gravity" of not on floor to prevent sliding down slopes
	if not is_on_floor():
		# Make character fall (not realistic gravity)
		self.move_and_collide(Vector3.DOWN*0.1)
	# Rotate character visuals to point in direction moved
	# Smoothed with quaternions
	if dir != Vector3.ZERO:
		# Starting basis quaternion
		var current_quat = Quat($visuals.global_transform.basis)
		# Target basis quaternion
		var target_quat = Quat(
			$visuals.transform.looking_at(-dir, Vector3.UP).basis)
		# Spherical linear interpolate between start and target
		$visuals.global_transform.basis = Basis(current_quat.slerp(target_quat, 0.5))
	# Update fog hole position to character position
	$fog.process_material.set_shader_param("holePos", translation)
	# Hide objects in path of camera
	raycast_hide()

func _input(event: InputEvent):
	if event.is_action_pressed("interact"):
		for obj in get_tree().get_nodes_in_group("interactable"):
			if obj.overlaps_body(self):
				# Emit a signal on the interacted object that can be handled
				obj.emit_signal("interact")
				break

func footstep_timeout():
	# Play footstep sound when walking and timout occurs
	if Input.is_action_pressed("move_up") \
		or Input.is_action_pressed("move_down") \
		or Input.is_action_pressed("move_left") \
		or Input.is_action_pressed("move_right"):
		$sfx/footstep.play()

func raycast_hide():
	var space_state = get_world().direct_space_state
	var colls = []
	# Continually cast rays until all objects are found
	while true:
		# Cast ray, ignoring objects already found
		var coll = space_state.intersect_ray(
			$camera.global_transform.origin,
			global_transform.origin,
			colls
		)
		# Ignore if object is player or has "nohide" tag
		if coll.has("collider") \
			and coll.collider != self \
			and not coll.collider.is_in_group("nohide"):
			colls.append(coll.collider)
		# No more objects found, exit
		else:
			break
	# Remove transparency
	for obj in prev_objects_hidden:
		for surface in range(obj.get_surface_material_count()):
			var mat: SpatialMaterial = obj.get_surface_material(surface)
	#		mat.distance_fade_mode = SpatialMaterial.DISTANCE_FADE_DISABLED
			mat.albedo_color.a = 1
			mat.flags_transparent = false
			obj.set_surface_material(surface, mat)
	# Collect objects to hide
	var obj_to_hide = []
	for coll in colls:
		var obj: MeshInstance
		if coll.get_parent() is MeshInstance:
			obj = coll.get_parent()
		else:
			for child in coll.get_children():
				if child is MeshInstance:
					obj = child
					break
		if not obj:
			continue
		# Set transparency
		for surface in range(obj.get_surface_material_count()):
			var mat: SpatialMaterial = obj.get_surface_material(surface)
			if not mat:
				mat = obj.mesh.surface_get_material(surface)
			if not mat:
				mat = SpatialMaterial.new()
			else:
				mat = mat.duplicate()
			mat.albedo_color.a = 0.5
			mat.flags_transparent = true
	#		mat.distance_fade_mode = SpatialMaterial.DISTANCE_FADE_OBJECT_DITHER
	#		mat.distance_fade_max_distance = 20
			obj.set_surface_material(surface, mat)
		# Store for later
		obj_to_hide.append(obj)
	# Store hidden objects to be unhidden
	prev_objects_hidden = obj_to_hide

func refill(amount):
	# Refill the lantern by the time given by the lamppost, capped by the max
	light_time = min(light_time + amount, LIGHT_MAX_TIME)

# Tutorial stuff
func show_movement_controls(body):
	if body == self:
		$tutorial_messages/movement.show()

func hide_movement_controls(body):
	if body == self:
		$tutorial_messages/movement.hide()

func show_camera_controls(body):
	if body == self:
		$tutorial_messages/camera.show()

func hide_camera_controls(body):
	if body == self:
		$tutorial_messages/camera.hide()
