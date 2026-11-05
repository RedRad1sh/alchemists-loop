class_name ReflectionBlur
extends Node3D
## Prototype frosted floor: one quad just under the room floor that paints a
## blurred copy of the below-floor mirror world instead of the sharp one.
##
## A SubViewport camera shares the main World3D but has its cull mask set to the
## reflection layer only, so it renders the mirrored room copy plus every item's
## Reflection box into a reduced-resolution texture. That camera clones the main
## one every frame, which makes the texture screen-aligned, so the plane can
## read it through SCREEN_UV and blur it with nine taps.
##
## hint_screen_texture cannot do this job: the screen copy is taken after the
## opaque pass, and every reflection in this scene is transparent geometry, so
## none of it would be in the copy.
##
## With enabled = false nothing is built, the reflection nodes keep their own
## layers and the main camera keeps its mask, so the render path is exactly the
## one the project shipped with.

## Layer the mirror world lives on while this is running.
const REFLECTION_LAYER := 4
## Layer of the blur plane itself - deliberately outside REFLECTION_LAYER, or the
## viewport would render the plane into its own texture and feed back.
const PLANE_LAYER := 8
const SHADER_PATH := "res://assets/house/shaders/reflection_blur_plane.gdshader"

@export var enabled := true
@export var camera_path: NodePath = NodePath("../IsoCamera")
## MirroredRoom3D is built at runtime by room_reflection_3d.gd, so it can be
## missing on the first frames; the periodic scan just retries.
@export var room_reflection_path: NodePath = NodePath("../RoomReflection3D/MirroredRoom3D")
@export var furniture_group := "furniture"
## Mirror texture size as a fraction of the window. Half resolution is already a
## softening blur of its own, because the plane upsamples it with linear filters.
@export_range(0.2, 1.0, 0.05) var resolution_scale := 0.5
## Blur radius in main-viewport pixels. 0 reproduces the sharp mirror almost
## exactly (measured within 0.2% mean colour); 3.5 is a light frost, 8-12 heavy.
## A nine-tap box starts to ghost at the largest radii - raise
## resolution_scale rather than blur_pixels if the edges look doubled.
@export_range(0.0, 24.0, 0.1) var blur_pixels := 6.0
## 1 = render the mirror every frame, 2 = every other frame at half the cost.
## The window is static unless the camera pans or an item moves, so 2 is usually
## indistinguishable.
@export_range(1, 8, 1) var update_interval := 1
## Fallback quad size, used when `clip_to_floor` is off. Deliberately far bigger
## than the room: the mirror then also paints below the room's near edges and
## beside it, which is the pre-clipping look.
@export var plane_size := Vector2(60.0, 60.0)
## Clip the mirror to the room's own floor footprint, so nothing of it can reach
## outside the room silhouette. Off restores the oversized `plane_size` quad.
@export var clip_to_floor := true
## Publishes the measured floor footprint (`RoomReflection3D`).
@export var floor_source_path: NodePath = NodePath("../RoomReflection3D")
@export var plane_offset_y := -0.002
## The blur quad is 2 mm under the floor, and the isometric camera looks down at
## about 35 deg, so a point that far below the floor plane lands a little further
## DOWN on the screen: the whole quad projects about 0.18 px lower than the floor
## at the default framing and about 0.9 px lower fully zoomed in. Its far edges are
## hidden by the two walls that stand there, but the two near floor edges are the
## ones whose walls the camera culls, so the extra strip of blurred mirror it paints
## past the floor's own silhouette is a bright speckled line on the black background.
## The floor map never reaches alpha 1.0 (measured: 65536 of 65536 sampled pixels
## below 254, border mean 176/255), so that strip is the only place the mirror can
## be seen at full strength - which is why it only reads as garbage once the floor
## brightness is taken to 0 and the floor itself goes black.
##
## On (the default) the quad's XZ position is nudged by exactly the amount that
## offset moves it on screen, so its projected outline coincides with the floor's
## own projected outline: nothing of it can reach past the floor edge, and nothing
## of the mirror is lost under the floor either. Off restores the plain
## `pivot + plane_offset_y` placement, pixel for pixel the pre-fix picture.
@export var screen_edge_match := true
## Extra room kept between the quad's clipped edge and the floor's own edge, in
## metres: at 0 the matched edge coincides with the floor, so this is the escalation
## knob if a residual sub-pixel dot still bothers a given framing. One pixel at the
## default framing is the camera's `size` divided by the window height, so
## 9.81456/1080 = 0.00909 m; at the closest zoom (size 2.0) it is 0.00185 m.
## Note the trade-off: the floor map is only about 69 % opaque, so shrinking the quad
## by N pixels does take the mirror away from the innermost N pixels of the floor,
## which shows there as a slightly darker rim instead of a brighter one.
@export_range(0.0, 0.2, 0.001) var screen_edge_margin := 0.0
## The second half of the same seam. The nine taps reach `blur_pixels` (6 by
## default) in every direction, and nothing stops them leaving the floor's own
## projected footprint: the innermost 6 px of the floor along its four edges
## therefore averages in what the mirror texture holds *outside* the room - the
## black scene background above the far edges and the black `MissingWall` masks
## under the near ones. That is a band, not a hairline, and it is the other thing
## that only reads as garbage once the floor goes dark: at brightness 1 the graded
## texture swamps it, at 0 the floor is 31 % mirror and the band shows as a line
## along the edge. On (the default) every tap is folded back to the nearest point of
## the projected footprint first, so the kernel is clamped and the blur stays inside
## the room. Off hands the taps to the screen texture exactly as before this existed.
@export var clamp_blur_to_floor := true
## Where the footprint clamp above folds a tap back to. On (the default) folds to
## the floor's own edge, which is what `clamp_blur_to_floor`'s comment describes.
## Off restores the border this shipped with before the switch existed: half the
## span. Because the fold is applied to the fragment's own UV as well as to its
## taps, that half-span fold rewrites every pixel beyond the middle of the floor
## onto the mid-line, so the mirror content sitting there is replicated outward
## across the whole outer half - the reflection reads as a sheet stretched from
## the object's mirror box to the sides of the plane, and the four corner floor
## patches lose their mirror detail entirely. Only a fragment whose footprint
## coordinate passes 0.5 moves, so an item dead centre is unaffected either way.
@export var clamp_at_room_edge := true
## The third half of the same seam, and the one that actually removes the visible
## line. `clamp_blur_to_floor` keeps the nine taps inside the room and
## `screen_edge_match` lands the quad on the floor's outline, but the floor map is
## only ~69 % opaque, so its own anti-aliased edge pixels still let the film through
## at nearly full strength: a thin bright ring along the two near edges (whose walls
## the camera culls, meeting at the bottom corner) that only reads as garbage once
## the floor goes black. On (the default) the film's alpha ramps to 0 across the
## outer `edge_fade_pixels` of the footprint, so those edge pixels reveal the black
## void behind the floor instead of the mirror and the ring blends into the void.
## Off leaves the film's edge hard - pixel for pixel the pre-fix picture.
@export var edge_fade := true
## Width of that ramp in main-viewport pixels. One pixel already takes the ring out;
## raise it only if a given framing still shows a residual dot. Too large and it
## starts to darken the floor's innermost edge instead, because the film is what the
## semi-transparent floor is showing there.
@export_range(0.0, 8.0, 0.1) var edge_fade_pixels := 3.0
## Mirror opacity. The sharp mirror geometry is moved to a layer the main camera
## no longer sees, so below this plane there is only the scene background:
## 1.0 = full blurred mirror, 0.0 = mirror gone, background visible.
@export_range(0.0, 1.0, 0.01) var intensity := 1.0

var _camera: Camera3D
var _viewport: SubViewport
var _vp_camera: Camera3D
var _plane: MeshInstance3D
var _material: ShaderMaterial
var _saved_mask := 0
var _patched_meshes: Dictionary = {}
var _patched_items: Dictionary = {}
var _scan_left := 0.0
var _frame := 0


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D
	if _camera == null:
		push_warning("ReflectionBlur: no Camera3D at %s" % camera_path)


func _process(delta: float) -> void:
	if not enabled:
		_teardown()
		return
	if _camera == null or not is_instance_valid(_camera):
		return
	if _plane == null:
		_build()
		if _plane == null:
			return
	_sync_camera()
	_scan_left -= delta
	if _scan_left <= 0.0:
		_rescan()
	var pivot := _floor_pivot()
	var floor_bounds := _measured_floor_bounds()
	var clipped := clip_to_floor and floor_bounds.size.x > 0.001
	if clipped:
		pivot = floor_bounds.get_center()
	_plane.position = Vector3(pivot.x, plane_offset_y, pivot.z) + _screen_edge_nudge(plane_offset_y)
	var quad: QuadMesh = _plane.mesh as QuadMesh
	var want_size := Vector2(floor_bounds.size.x, floor_bounds.size.z) if clipped else plane_size
	if clipped:
		# The margin is a two-sided inset, so it comes off the span twice.
		want_size -= Vector2(screen_edge_margin, screen_edge_margin) * 2.0
		want_size.x = maxf(0.001, want_size.x)
		want_size.y = maxf(0.001, want_size.y)
	if quad.size != want_size:
		quad.size = want_size
	_material.set_shader_parameter("blur_pixels", blur_pixels)
	_material.set_shader_parameter("intensity", intensity)
	var height: float = _camera.get_viewport().get_visible_rect().size.y
	_material.set_shader_parameter("texel", 1.0 / maxf(1.0, height))
	_push_footprint_uniforms(quad)
	_frame += 1
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ONCE if _frame % update_interval == 0
		else SubViewport.UPDATE_DISABLED)


func _build() -> void:
	var shader := load(SHADER_PATH) as Shader
	if shader == null:
		push_warning("ReflectionBlur: %s missing" % SHADER_PATH)
		enabled = false
		return
	_saved_mask = _camera.cull_mask

	_viewport = SubViewport.new()
	_viewport.name = "ReflectionViewport"
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_vp_camera = Camera3D.new()
	_vp_camera.name = "ReflectionCamera"
	# keep_aspect has to match the main camera (Godot 4 only offers Keep Width /
	# Keep Height, there is no "off"), and _sync_camera() resizes this viewport to
	# the window aspect, so the two projections stay identical and the texture
	# stays screen-aligned for SCREEN_UV sampling.
	_vp_camera.cull_mask = REFLECTION_LAYER
	_viewport.add_child(_vp_camera)

	_material = ShaderMaterial.new()
	_material.shader = shader
	# The mirror itself is rendered by the SubViewport camera now, so in the main
	# pass this only has to be the first transparent draw: -3 stays ahead of the
	# floor (0), whose alpha still veils the blurred image, and of the sprites (5+).
	_material.render_priority = -3
	_material.set_shader_parameter("refl_tex", _viewport.get_texture())

	var quad := QuadMesh.new()
	quad.size = plane_size
	_plane = MeshInstance3D.new()
	_plane.name = "ReflectionBlurPlane"
	_plane.mesh = quad
	# QuadMesh builds in its local XY plane, so lay the node flat: local +Y then
	# runs along world -Z, which only matters for a non-square plane_size.
	# (QuadMesh.orientation is a Plane enum value and GDScript 4.7 cannot name it.)
	_plane.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_plane.layers = PLANE_LAYER
	_plane.material_override = _material
	_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_plane)


func _teardown() -> void:
	if _plane == null and _patched_meshes.is_empty() and _patched_items.is_empty():
		return
	for mesh in _patched_meshes:
		if is_instance_valid(mesh):
			mesh.layers = _patched_meshes[mesh]
	_patched_meshes.clear()
	for item in _patched_items:
		if is_instance_valid(item):
			item.reflection_layers = _patched_items[item]
	_patched_items.clear()
	if _camera != null and is_instance_valid(_camera):
		_camera.cull_mask = _saved_mask
	if is_instance_valid(_viewport):
		_viewport.queue_free()
	if is_instance_valid(_plane):
		_plane.queue_free()
	_viewport = null
	_vp_camera = null
	_plane = null
	_material = null


func _sync_camera() -> void:
	_vp_camera.global_transform = _camera.global_transform
	_vp_camera.projection = _camera.projection
	_vp_camera.keep_aspect = _camera.keep_aspect
	_vp_camera.size = _camera.size
	_vp_camera.near = _camera.near
	_vp_camera.far = _camera.far
	var window: Vector2 = _camera.get_viewport().get_visible_rect().size
	var want := Vector2i(maxi(2, int(window.x * resolution_scale)), maxi(2, int(window.y * resolution_scale)))
	if _viewport.size != want:
		_viewport.size = want


## Пересканировать сразу: новый отражающий узел до ближайшего таймерного прохода
## рисуется резким зеркалом во втором проходе основной камеры, и на четверть секунды
## под полом появляется двойное отражение.
func rescan_now() -> void:
	if _plane == null or _camera == null or not is_instance_valid(_camera):
		return
	_rescan()


## Re-run on a timer: the mirrored room is built deferred, and items are placed
## and deleted while the game runs.
func _rescan() -> void:
	_scan_left = 0.25
	_prune_dead()
	var root := get_node_or_null(room_reflection_path)
	if root != null:
		for node in root.find_children("*", "VisualInstance3D", true, false):
			_patch_mesh(node as VisualInstance3D)
	for node in get_tree().get_nodes_in_group(furniture_group):
		var item := node as FurnitureItem
		if item == null or not get_parent().is_ancestor_of(item):
			continue
		if not _patched_items.has(item):
			_patched_items[item] = item.reflection_layers
		item.reflection_layers = REFLECTION_LAYER
		_patch_mesh(item.get_node_or_null("Reflection") as MeshInstance3D)
	if _camera != null and is_instance_valid(_camera):
		_camera.cull_mask = (_saved_mask | PLANE_LAYER) & ~REFLECTION_LAYER


func _patch_mesh(mesh: VisualInstance3D) -> void:
	if mesh == null or _patched_meshes.has(mesh):
		return
	_patched_meshes[mesh] = mesh.layers
	mesh.layers = REFLECTION_LAYER


## Items are deleted while the game runs, so the dictionaries that remember the
## original layers have to drop those keys or they would grow forever.
func _prune_dead() -> void:
	var dead_meshes: Array = []
	for mesh in _patched_meshes:
		if not is_instance_valid(mesh):
			dead_meshes.append(mesh)
	for mesh in dead_meshes:
		_patched_meshes.erase(mesh)
	var dead_items: Array = []
	for item in _patched_items:
		if not is_instance_valid(item):
			dead_items.append(item)
	for item in dead_items:
		_patched_items.erase(item)


## The mirrored room root is positioned at the measured floor pivot, which is the
## centre the plane has to sit on.
func _floor_pivot() -> Vector3:
	var root := get_node_or_null(room_reflection_path)
	return root.global_position if root != null else Vector3.ZERO


## Empty AABB until RoomReflection3D has measured the room.
func _measured_floor_bounds() -> AABB:
	var host := get_node_or_null(floor_source_path) as RoomReflection3D
	return host.measured_floor_bounds if host != null else AABB()


## The projected footprint, in the same SCREEN_UV space the shader taps in.
##
## The quad is laid flat, so its two half-axes are its own local X and local Y
## turned into world space by its global basis - no assumption about the rotation
## or about the room's placement. Their projected difference from the projected
## centre is the parallelogram the floor actually draws, and the two weight vectors
## are the rows of that 2x2 basis' inverse, which turns a screen offset into
## "how far along each floor axis" with two dot products in the shader.
##
## All-zero weights are the shader's own signal that there is nothing to clamp to,
## so a first frame without a camera or a measurement cannot punch the taps to the
## middle of the screen.
func _push_footprint_uniforms(quad: QuadMesh) -> void:
	_material.set_shader_parameter("footprint_border", 1.0 if clamp_at_room_edge else 0.5)
	if not clamp_blur_to_floor or _camera == null or not is_instance_valid(_plane):
		_material.set_shader_parameter("clamp_to_footprint", false)
		_material.set_shader_parameter("axis_weights_x", Vector2.ZERO)
		_material.set_shader_parameter("axis_weights_z", Vector2.ZERO)
		_material.set_shader_parameter("edge_fade", false)
		return
	var vs: Vector2 = _camera.get_viewport().get_visible_rect().size
	if vs.x < 2.0 or vs.y < 2.0:
		_material.set_shader_parameter("clamp_to_footprint", false)
		_material.set_shader_parameter("edge_fade", false)
		return
	var c := _plane.global_position
	var basis := _plane.global_transform.basis
	var a1: Vector3 = basis.x * quad.size.x * 0.5
	var a2: Vector3 = basis.y * quad.size.y * 0.5
	var pc := _camera.unproject_position(c) / vs
	var ax := (_camera.unproject_position(c + a1) / vs) - pc
	var az := (_camera.unproject_position(c + a2) / vs) - pc
	var det := ax.x * az.y - ax.y * az.x
	if absf(det) < 1.0e-9:
		# Degenerate: the floor projects to a line, so there is no footprint to keep
		# the taps inside. Leave the taps as they were.
		_material.set_shader_parameter("clamp_to_footprint", false)
		_material.set_shader_parameter("edge_fade", false)
		return
	_material.set_shader_parameter("clamp_to_footprint", true)
	_material.set_shader_parameter("quad_center_uv", pc)
	_material.set_shader_parameter("quad_axis_x_uv", ax)
	_material.set_shader_parameter("quad_axis_z_uv", az)
	_material.set_shader_parameter("axis_weights_x", Vector2(az.y, -az.x) / det)
	_material.set_shader_parameter("axis_weights_z", Vector2(-ax.y, ax.x) / det)
	# Convert the pixel-wide ramp into footprint (st) units. `ax`/`az` are the UV
	# vectors from the quad centre to one edge, and a unit st offset lands exactly on
	# that edge (st = +/-1 there), so the footprint's half-extent along each axis is
	# that UV turned into pixels; `edge_fade_pixels` divided by it is the st width of
	# the ramp.
	var half_px_x := Vector2(ax.x * vs.x, ax.y * vs.y).length()
	var half_px_z := Vector2(az.x * vs.x, az.y * vs.y).length()
	_material.set_shader_parameter("edge_fade", edge_fade)
	_material.set_shader_parameter("edge_fade_st", Vector2(
			edge_fade_pixels / maxf(half_px_x, 1.0),
			edge_fade_pixels / maxf(half_px_z, 1.0)))


## The in-plane shift that makes a quad at `offset_y` project onto exactly the same
## screen pixels as the same quad at floor level.
##
## Under an orthographic camera a world point moves on screen by its dot product
## with the camera's axes, so the screen-up component of a displacement (dx, dy, dz)
## is `up.x*dx + up.y*dy + up.z*dz` (metres of screen height). Solving that for 0
## along the shortest in-plane direction - the projection of `up` onto the floor -
## gives the nudge. For this room's fixed isometric basis it works out to the offset
## itself along -X and -Z: 2 mm under the floor is answered by 2 mm back from the
## near corner. `offset_y * 2.0` is the general answer, so the knob follows the user
## if `plane_offset_y` is ever raised.
func _screen_edge_nudge(offset_y: float) -> Vector3:
	if not screen_edge_match:
		return Vector3.ZERO
	var cam: Camera3D = _camera if (_camera != null and is_instance_valid(_camera)) \
			else get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var up: Vector3 = cam.global_transform.basis.y
	var along_plane := up.x * up.x + up.z * up.z
	if along_plane < 0.0001:
		# A camera looking straight down projects the floor without any screen-depth
		# tilt, so a Y offset cannot leak an edge there.
		return Vector3.ZERO
	var reach := -up.y * offset_y / along_plane
	return Vector3(reach * up.x, 0.0, reach * up.z)
