---
description: Add a new inventory item (e.g. "coffee: usable, +10 energy, stacks to 5")
---
Add this item: $ARGUMENTS

1. Create `data/items/<id>.tres` by copying an existing item file; set `id`, `display_name`,
   `description`, `max_stack`, `color` (prefer a `Palette` color), `usable`, `use_effects`, `tags`.
2. If it should be in the starting kit, add it to `GameState.STARTING_ITEMS`.
3. Run `tools/test.sh -gselect=test_item_db` (it validates every item), then `/check --inventory`.
