class_name VoiceCodec
extends RefCounted

## Voice packets for proximity chat: mono 16-bit samples are resampled to RATE (12 kHz) and packed with IMA ADPCM at 4 bits per
## sample, one block per packet of BLOCK_SAMPLES (40 ms): 5 header bytes + 240 payload = 245 bytes, about 6 KB/s while a player
## speaks and nothing while they are quiet. Godot ships no Opus encoder, and ADPCM costs a few thousand integer operations per
## packet, so a phone never spikes a frame. Packet layout: seq u16, predictor i16, step index u8, then BLOCK_SAMPLES / 2 bytes.
## Nothing here keeps audio: encode() and decode() are pure functions of the buffer they are handed.

const RATE := 12000
const BLOCK_SAMPLES := 480
const HEADER := 5
const PACKET_SIZE := HEADER + BLOCK_SAMPLES / 2
## The host never relays a packet larger than this, nor more than MAX_BYTES_PER_SECOND from one speaker.
const MAX_PACKET := 260
const MAX_BYTES_PER_SECOND := 8000

const _STEPS := [
	7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
	157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552,
	1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487,
	12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]
const _INDEX_DELTA := [-1, -1, -1, -1, 2, 4, 6, 8]


## Float samples (-1..1) at BLOCK_SAMPLES length, to a packet. Shorter blocks are padded with silence.
static func encode(samples: PackedFloat32Array, seq: int) -> PackedByteArray:
	var pcm := PackedInt32Array()
	pcm.resize(BLOCK_SAMPLES)
	for i in mini(samples.size(), BLOCK_SAMPLES):
		pcm[i] = clampi(int(roundf(samples[i] * 32767.0)), -32768, 32767)
	var out := PackedByteArray()
	out.resize(PACKET_SIZE)
	var predictor := pcm[0]
	var index := 0
	out.encode_u16(0, seq & 0xFFFF)
	out.encode_s16(2, predictor)
	out.encode_u8(4, index)
	var low := true
	var byte := 0
	var at := HEADER
	for i in range(1, BLOCK_SAMPLES):
		var step: int = _STEPS[index]
		var diff := pcm[i] - predictor
		var code := 0
		if diff < 0:
			code = 8
			diff = -diff
		var delta := step >> 3
		if diff >= step:
			code |= 4
			diff -= step
			delta += step
		if diff >= step >> 1:
			code |= 2
			diff -= step >> 1
			delta += step >> 1
		if diff >= step >> 2:
			code |= 1
			delta += step >> 2
		predictor = clampi(predictor + (-delta if code & 8 else delta), -32768, 32767)
		index = clampi(index + int(_INDEX_DELTA[code & 7]), 0, 88)
		if low:
			byte = code
		else:
			out[at] = byte | (code << 4)
			at += 1
		low = not low
	if not low:
		out[at] = byte
	return out


## A packet to float samples; an empty array if the packet is malformed.
static func decode(packet: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not valid(packet):
		return out
	var predictor := packet.decode_s16(2)
	var index := clampi(packet.decode_u8(4), 0, 88)
	out.resize(BLOCK_SAMPLES)
	out[0] = float(predictor) / 32768.0
	for i in range(1, BLOCK_SAMPLES):
		var byte := packet[HEADER + (i - 1) / 2]
		var code := (byte & 0x0F) if (i - 1) % 2 == 0 else (byte >> 4)
		var step: int = _STEPS[index]
		var delta := step >> 3
		if code & 4:
			delta += step
		if code & 2:
			delta += step >> 1
		if code & 1:
			delta += step >> 2
		predictor = clampi(predictor + (-delta if code & 8 else delta), -32768, 32767)
		index = clampi(index + int(_INDEX_DELTA[code & 7]), 0, 88)
		out[i] = float(predictor) / 32768.0
	return out


static func valid(packet: PackedByteArray) -> bool:
	return packet.size() == PACKET_SIZE and packet.decode_u8(4) <= 88


static func seq_of(packet: PackedByteArray) -> int:
	return packet.decode_u16(0) if packet.size() >= 2 else 0


## True if `b` is newer than `a` on the wrapping 16-bit sequence.
static func newer(a: int, b: int) -> bool:
	var gap := posmod(b - a, 65536)
	return gap >= 1 and gap < 32768


## Root-mean-square level of a block, 0..1.
static func level(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum := 0.0
	for value in samples:
		sum += value * value
	return sqrt(sum / float(samples.size()))


## Stereo capture frames at `mix_rate` to mono samples at RATE by averaging; `carry` is the fractional position and leftover
## input between calls so the stream stays continuous: {"phase": float, "acc": float, "n": int}.
static func downsample(frames: PackedVector2Array, mix_rate: float, carry: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var ratio := mix_rate / float(RATE)
	var phase: float = carry.get("phase", 0.0)
	var acc: float = carry.get("acc", 0.0)
	var count: int = carry.get("n", 0)
	for frame in frames:
		acc += (frame.x + frame.y) * 0.5
		count += 1
		phase += 1.0
		if phase >= ratio:
			phase -= ratio
			out.append(acc / float(maxi(count, 1)))
			acc = 0.0
			count = 0
	carry["phase"] = phase
	carry["acc"] = acc
	carry["n"] = count
	return out
