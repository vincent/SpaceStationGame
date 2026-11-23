extends SceneTree
## Compares two images (PNG / WebP): godot --headless -s res://tools/image_diff.gd -- <expected> <actual> [diff_out]
## Fails (exit 1) when the mean per-channel difference exceeds MAX_MEAN or
## more than MAX_BAD_RATIO of the pixels differ by more than PIXEL_THRESHOLD.
## Tolerances absorb shader-TIME animation (stars, steam) between runs.

const MAX_MEAN := 0.015
const PIXEL_THRESHOLD := 0.12
const MAX_BAD_RATIO := 0.02


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <expected.png> <actual.png> [diff.png]")
		quit(2)
		return
	var expected := Image.load_from_file(args[0])
	var actual := Image.load_from_file(args[1])
	if expected == null or actual == null:
		printerr("could not load images")
		quit(2)
		return
	if expected.get_size() != actual.get_size():
		printerr("size mismatch: %s vs %s" % [expected.get_size(), actual.get_size()])
		quit(1)
		return
	expected.convert(Image.FORMAT_RGB8)
	actual.convert(Image.FORMAT_RGB8)
	var diff := Image.create(expected.get_width(), expected.get_height(), false, Image.FORMAT_RGB8)
	var total := 0.0
	var bad := 0
	for y in expected.get_height():
		for x in expected.get_width():
			var a := expected.get_pixel(x, y)
			var b := actual.get_pixel(x, y)
			var d := (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			total += d
			if d > PIXEL_THRESHOLD:
				bad += 1
				diff.set_pixel(x, y, Color(1, 0, 1))
			else:
				diff.set_pixel(x, y, a.darkened(0.7))
	var n := float(expected.get_width() * expected.get_height())
	var mean := total / n
	var ratio := bad / n
	var ok := mean <= MAX_MEAN and ratio <= MAX_BAD_RATIO
	if args.size() > 2:
		if args[2].get_extension() == "webp":
			diff.save_webp(args[2], false)
		else:
			diff.save_png(args[2])
	print("%s mean=%.4f bad=%.2f%%" % ["OK  " if ok else "FAIL", mean, ratio * 100.0])
	quit(0 if ok else 1)
