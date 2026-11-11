extends Node

const GameScript = preload("res://main.gd")
var g: Game

func _ready() -> void:
	g = load("res://main.tscn").instantiate()
	add_child(g)
	await get_tree().process_frame
	g._online._net_enabled = false
	g._online._net_nick = "Варда"
	g._online._avatar_gender = "female"
	g._hub._refresh_own_avatar()
	await _capture("hud-approved-portraits-540x960")
	g._hub._open_profile()
	await _capture("avatar-filtered-profile-540x960")
	g._hub._close_profile()
	g._social._seed_demo()
	g._social_ui.open(0)
	await _capture("avatar-filtered-friends-spirit-540x960")
	var spirit := g.find_child("FriendRow_npc-spirit", true, false)
	if spirit != null:
		for child in spirit.get_children():
			if child is Avatar:
				print("SPIRIT_AVATAR ", child._spec, " texture=", child._texture.get_size(), " mipmaps=", child._texture.get_image().has_mipmaps())
	get_tree().quit()

func _capture(label: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "C:/Users/nkucherenko/agent-coding/captures/preview/" + label + ".png"
	print("ACCEPTANCE_CAPTURE ", label, " error=", image.save_png(path))
