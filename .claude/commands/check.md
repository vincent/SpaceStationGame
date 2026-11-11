---
description: Lint, run all tests, and take a screenshot to verify the game still works
---
1. Run `tools/lint.sh` and fix any problems.
2. Run `tools/test.sh`. If tests fail, read the failure, fix the code (not the test, unless the test is wrong), rerun.
3. Run `tools/screenshot.sh build/check.png --delay=4 $ARGUMENTS` and look at the image. Report anything visually broken.
   Useful hooks: `--view=station`, `--focus=wreck_core --power=wreck_core`, `--explode`, `--time=23`, `--backfaces`.
4. For visual changes, run `tools/golden.sh`; if a difference is intended, use `/update-goldens`.
5. Summarise: lint status, tests passed/total, golden status, and what the screenshot shows.
