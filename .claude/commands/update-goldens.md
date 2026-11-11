---
description: Re-render the golden images after an intended visual change and review them
---
Only run this when a visual change is intended — goldens are the reference
for `tools/golden.sh` (and CI).

1. Run `tools/golden.sh $ARGUMENTS` first and note which scenes differ.
2. Run `tools/golden.sh --update $ARGUMENTS` (no arguments = all scenes).
3. Look at every updated image in `tests/goldens/` and describe what changed
   compared to before. If anything looks broken (z-fighting, magenta back
   faces, missing hull, clipped character), stop and report instead.
4. Run `tools/golden.sh` again: everything must pass.
5. Summarise which goldens changed and why, so it can go in the PR.
