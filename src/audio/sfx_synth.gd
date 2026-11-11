class_name SfxSynth
## Placeholder sound effects synthesised at startup (no audio assets yet):
## short tones, sweeps and filtered noise as 16-bit mono AudioStreamWAVs.

enum Wave { SINE, SQUARE, SAW, NOISE }

const MIX_RATE := 22050


## A tone sweeping from `f0` to `f1` Hz with a linear attack/release envelope.
static func tone(f0: float, f1: float, seconds: float, wave: Wave = Wave.SINE, volume: float = 0.5,
		attack: float = 0.005, release: float = 0.05) -> AudioStreamWAV:
	var n := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in n:
		var t := float(i) / MIX_RATE
		var f := lerpf(f0, f1, t / seconds)
		phase = fmod(phase + f / MIX_RATE, 1.0)
		var v := 0.0
		match wave:
			Wave.SINE:
				v = sin(phase * TAU)
			Wave.SQUARE:
				v = 1.0 if phase < 0.5 else -1.0
			Wave.SAW:
				v = phase * 2.0 - 1.0
			Wave.NOISE:
				v = rng.randf_range(-1.0, 1.0)
		samples[i] = v * volume * envelope(t, seconds, attack, release)
	return to_wav(samples)


## Sum of several tones (chords, layered stings), each [f0, f1, wave, volume].
static func layered(layers: Array, seconds: float, attack: float = 0.01, release: float = 0.3) -> AudioStreamWAV:
	var mix := PackedFloat32Array()
	mix.resize(int(seconds * MIX_RATE))
	for layer: Array in layers:
		var data := _floats(tone(layer[0], layer[1], seconds, layer[2], layer[3], attack, release))
		for i in mini(mix.size(), data.size()):
			mix[i] += data[i]
	return to_wav(mix)


## Looping low rumble (brown noise): room tone.
static func room_tone(seconds: float = 4.0, volume: float = 0.35) -> AudioStreamWAV:
	var n := int(seconds * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var last := 0.0
	for i in n:
		last = clampf(last + rng.randf_range(-0.02, 0.02), -1.0, 1.0) * 0.998
		samples[i] = last * volume * 4.0
	# Crossfade the ends so the loop is seamless.
	var fade := int(0.2 * MIX_RATE)
	for i in fade:
		var k := float(i) / fade
		samples[i] = samples[i] * k + samples[n - fade + i] * (1.0 - k)
	var wav := to_wav(samples.slice(0, n - fade))
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_end = n - fade
	return wav


static func envelope(t: float, seconds: float, attack: float, release: float) -> float:
	var a := clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	var r := clampf((seconds - t) / maxf(release, 0.0001), 0.0, 1.0)
	return minf(a, r)


static func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav


static func _floats(wav: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(wav.data.size() / 2)
	for i in out.size():
		out[i] = wav.data.decode_s16(i * 2) / 32767.0
	return out
