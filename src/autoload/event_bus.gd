extends Node
## Global signal hub. Systems that should not know about each other talk through
## here (e.g. the player reaching an object -> the HUD opening its menu).
## Rule: declare signals only. Never store state in this file.

@warning_ignore_start("unused_signal")

## The player reached an interactable and wants its action menu.
signal interaction_requested(interactable: Interactable)
## The interaction menu was closed (action chosen or cancelled).
signal interaction_closed
## Short message to show the player ("Not enough rations").
signal toast(message: String)
## A save was loaded or a new game started; UI should refresh everything.
signal game_reset
