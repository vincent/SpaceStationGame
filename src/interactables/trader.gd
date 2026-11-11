extends Interactable
## Merchant aboard a docked visitor ship. Trades are simple item swaps.

## [label, give, get]
const OFFERS: Array = [
	["2 rations for 3 scrap", {&"scrap_metal": 3}, {&"ration": 2}],
	["2 water for 2 scrap", {&"scrap_metal": 2}, {&"water": 2}],
	["Power cell for 5 scrap", {&"scrap_metal": 5}, {&"power_cell": 1}],
	["4 scrap for 1 ration", {&"ration": 1}, {&"scrap_metal": 4}],
]


func get_actions() -> Array[InteractionAction]:
	var actions: Array[InteractionAction] = []
	for offer: Array in OFFERS:
		var give: Dictionary = offer[1]
		actions.append(InteractionAction.new(offer[0], _trade.bind(give, offer[2]),
			GameState.inventory.has_all(give), "Can't afford"))
	return actions


func _trade(give: Dictionary, get_items: Dictionary) -> void:
	if GameState.trade(give, get_items):
		EventBus.toast.emit("Pleasure doing business.")
		EventBus.trade_completed.emit()
