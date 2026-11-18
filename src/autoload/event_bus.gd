extends Node
## Global signal hub. Systems that should not know about each other talk through
## here (e.g. the player tapping an object -> the HUD flashing its card).
## Rule: declare signals only. Never store state in this file.

@warning_ignore_start("unused_signal")

## The player reached an interactable to use it (story "interacted" trigger).
signal interaction_requested(interactable: Interactable)
## The player tapped an object in the room (the HUD shows its card).
signal interactable_tapped(interactable: Interactable)
## Short message to show the player ("Not enough food").
signal toast(message: String)
## Like `toast`, with a style: &"info", &"success" (something got done) or
## &"warning".
signal notice(message: String, kind: StringName)
## Items arrived (salvage, trade, production, rewards). `source` is the object
## or module they came from when known (the HUD flies them from there).
signal reward(items: Dictionary, source: Node3D)
## The HUD's opaque panels moved: `free_rect` is the screen area (UI pixels)
## still showing the world. The camera frames the focused room inside it.
signal hud_insets_changed(free_rect: Rect2)
## A save was loaded or a new game started; UI should refresh everything.
signal game_reset
## A module got the camera's focus (room view target).
signal module_focused(module: Module)
## UI asks to focus a module (room view) / to zoom out to the whole station.
signal module_focus_requested(module: Module)
signal station_view_requested
## The camera zoom moved: 0 = station view, 1 = room view.
signal view_changed(t: float)
## The camera crossed the station/room threshold (main.ROOM_VIEW_T). Starts in
## station view. Room view shows the object cards, station view the build ghosts.
signal room_view_changed(room: bool)
## The player tapped an empty slot's ghost outline in station view.
signal ghost_slot_tapped(parent_uid: int, slot: StringName)
## Build menu: outline where `module_id` would go (attached by `by_slot`);
## an empty `module_id` clears the preview.
signal build_preview(module_id: StringName, parent_uid: int, slot: StringName, by_slot: StringName)
## Open / close the exploded-view upgrade screen of a module.
signal upgrade_view_requested(module: Module)
signal upgrade_view_closed
## A module started its power-on sequence (lights, strips, screens).
signal power_on_started(module: Module)
## A part snapped into place in the exploded view.
signal part_snapped(module: Module, part: StringName)
## A trade with a visitor went through.
signal trade_completed
## One-shot sound request (see AudioDirector.SOUNDS).
signal sfx(sound: StringName)
## An encounter needs the screen (dialog / radio channel) / was answered or closed.
signal encounter_started(encounter: EncounterDef)
signal encounter_finished(encounter: EncounterDef)
## An encounter outcome asks for a trader ship (VisitorDirector answers).
signal visitor_requested
