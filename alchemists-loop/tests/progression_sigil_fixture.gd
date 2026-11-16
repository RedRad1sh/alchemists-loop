extends RefCounted
class_name ProgressionSigilFixture

# Local catalog contract, deliberately limited to four measurable rarity targets.
# This is a transport peer, not a resource or collection grant adapter.
var manager: SigilManager
var cards: Array = []
var crafts: Array = []
var collection := {}
var requests: Array = []
var mode := "success"

func install(game: Game) -> void:
	manager = game._sigil
	if game._online._device_id.is_empty():
		game._online._device_id = "progression-local" # Transport identity, not player resources.
	var rarities := ["common", "rare", "epic", "legendary"]
	var costs := [50, 150, 300, 450]
	for i in range(4):
		var id := "local-" + String(rarities[i])
		var ingredients := [{"item_id": String(Game.BASE_IDS[i]), "qty": 5}]
		cards.append({"id": id, "set": "local", "rarity": rarities[i],
			"ether_cost": costs[i], "recipe": ingredients, "seed": i + 1,
			"fallback_name": id, "object_type": "object"})
		crafts.append({"id": "craft-" + id, "card_id": id, "set": "local",
			"rarity": rarities[i], "ether_cost": costs[i], "ingredients": ingredients,
			"seed": i + 1, "fallback_name": id})
	manager.transport = request
	manager.request_catalog()
	manager.request_daily("progression-local")

func request(kind: String, payload: Dictionary) -> void:
	requests.append({"kind": kind, "payload": payload.duplicate(true)})
	match kind:
		"catalog":
			manager._on_catalog_result({"ok": true, "version": "progression-local-v1", "cards": cards, "sets": []})
		"daily":
			manager._on_daily_result({"ok": true, "catalog_version": "progression-local-v1",
				"day": "local", "offer_hash": "local-v1", "crafts": crafts})
		"collection":
			manager._on_collection_result({"ok": true, "cards": collection.duplicate(true), "extras": [], "milestones": {}})
		"craft":
			if mode == "pending":
				return
			var id := String(payload.get("craft_id", ""))
			for craft in crafts:
				if craft.id != id:
					continue
				if mode == "refusal":
					manager._on_craft_result({"ok": false, "error": "fixture_refusal"})
					return
				collection[craft.card_id] = {"copies": int(collection.get(craft.card_id, {}).get("copies", 0)) + 1, "first_at": "local"}
				manager._on_craft_result({"ok": true, "craft_id": id, "card_id": craft.card_id,
					"rarity": craft.rarity, "llm_name": craft.fallback_name, "seed": craft.seed})
				return
			manager._on_craft_result({"ok": false, "error": "catalog_missing"})
