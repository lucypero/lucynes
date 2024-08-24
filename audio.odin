package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import rl "vendor:raylib"

// audio demo
// ported from
// https://github.com/raysan5/raylib/blob/master/examples/audio/audio_raw_stream.c

MAX_SAMPLES :: 512
MAX_SAMPLES_PER_UPDATE :: 4096
// Cycles per second (hz)
frequency: f32 = 440

// Audio frequency, for smoothing
audio_frequency: f32 = 440

// Previous value, used to test if sine needs to be rewritten, and to smoothly modulate frequency
old_frequency: f32 = 1

// Index for audio rendering
sine_idx: f32 = 0

AudioDemo :: struct {
	audio_data:   []i16,
	write_buffer: []i16,
	stream:       rl.AudioStream,
	wave_length:  int,
}

audio_demo_init :: proc(using audio_demo: ^AudioDemo) {
	rl.InitAudioDevice()
	rl.SetAudioStreamBufferSizeDefault(MAX_SAMPLES_PER_UPDATE)

	// // Init raw audio stream (sample rate: 44100, sample size: 16bit-short, channels: 1-mono)
	stream = rl.LoadAudioStream(44100, 16, 1)

	rl.SetAudioStreamCallback(stream, audio_input_callback)

	// // Buffer for the single cycle waveform we are synthesizing
	audio_data = make([]i16, MAX_SAMPLES)

	// // Frame buffer, describing the waveform when repeated over the course of a frame
	write_buffer = make([]i16, MAX_SAMPLES_PER_UPDATE)

	rl.PlayAudioStream(stream)

	// Computed size in samples of the sine wave
	wave_length = 1
}

audio_input_callback :: proc "c" (buffer: rawptr, frames: c.uint) {

	audio_frequency = frequency + (audio_frequency - frequency) * 0.95

	incr := audio_frequency / 44100
	d: [^]i16 = cast(^i16)(buffer)

	for i in 0 ..< frames {
		d[i] = i16(32000 * math.sin(2 * math.PI * sine_idx))
		sine_idx += incr
		if sine_idx > 1 {
			sine_idx -= 1.0
		}
	}
}

apu_read :: proc(using nes: ^NES, addr: u16) -> u8 {

	// addr will be 0x4015
	// Status: DMC interrupt, frame interrupt, length counter status: noise, triangle, pulse 2, pulse 1 (read)
	// IF-D NT21

	return 1
}

apu_write :: proc(using nes: ^NES, addr: u16, val: u8) {

	switch addr {
	/// PULSE channels

	// Pulse 1 Duty cycle
	case 0x4000:
	// Pulse 2 Duty cycle
	case 0x4004:

	// Pulse 1 APU Sweep
	case 0x4001:
	// Pulse 2 APU Sweep
	case 0x4005:

	// Pulse 1 timer Low 8 bits
	case 0x4002:
	// Pulse 2 timer Low 8 bits
	case 0x4006:

	// Pulse 1 length counter load and timer High 3 bits 
	case 0x4003:

	// Pulse 2 length counter load and timer High 3 bits 
	case 0x4007:

	/// TRIANGLE channel

	// Triangle Length counter halt / linear counter control (C), linear counter load (R) 
	//    CRRR RRRR
	case 0x4008:

	// Unused
	case 0x4009:

	// Triangle timer low
	case 0x400A:

	// Length counter load (L), timer high (T), set linear counter reload flag 
	//   LLLL LTTT
	case 0x400B:

	/// NOISE channel

	// NOISE Envelope loop / length counter halt (L), constant volume (C), volume/envelope (V) 
	//   --LC VVVV
	case 0x400C:

	// Unused
	case 0x400D:

	// NOISE Loop noise (L), noise period (P) 
	//   L--- PPPP
	case 0x400E:

	// NOISE Length counter load (L) 
	//   LLLL L---
	case 0x400F:

	/// DMC Channel

	// DMC - IRQ enable (I), loop (L), frequency (R)
	//   IL-- RRRR
	case 0x4010:

	// DMC - Load counter (D) 
	//   -DDD DDDD
	case 0x4011:

	// DMC - Sample address (A) 
	//  AAAA AAAA
	case 0x4012:

	// DMC - Sample length (L) 
	//   LLLL LLLL
	case 0x4013:

	/// APU STATUS
	// Enable DMC (D), noise (N), triangle (T), and pulse channels (2/1)
	//  ---D NT21
	case 0x4015:

	/// APU Frame counter
	// 5-frame sequence, disable frame interrupt (write) 
	// SD-- ----
	case 0x4017:

	}
}
