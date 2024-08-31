package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:sync"
import "core:sync/chan"
import "core:thread"
import ma "vendor:miniaudio"

// audio demo
// ported from
// https://github.com/raysan5/raylib/blob/master/examples/audio/audio_raw_stream.c

OUTPUT_SAMPLE_RATE :: 44100

OUTPUT_NUM_CHANNELS :: 1
PREFERRED_BUFFER_SIZE :: 512
OUTPUT_BUFFER_SIZE :: OUTPUT_SAMPLE_RATE * size_of(f32) * OUTPUT_NUM_CHANNELS

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
	wave_length:  int,
	device:       ma.device,
	buffer_size:  int,
	ring_buffer:  Buffer,
	mutex:        sync.Mutex,
	sema:         sync.Sema,
	time:         f64,
}

audio_demo_init :: proc(audio_demo: ^AudioDemo) {

	err: runtime.Allocator_Error
	sample_channel, err = chan.create_buffered(chan.Chan(f32), 100000, context.allocator)
	if err != .None {
		os.exit(1)
	}

	result: ma.result

	// set audio device settings
	device_config := ma.device_config_init(ma.device_type.playback)
	device_config.playback.format = ma.format.f32
	device_config.playback.channels = 1
	device_config.sampleRate = OUTPUT_SAMPLE_RATE
	device_config.dataCallback = ma.device_data_proc(audio_callback)
	device_config.periodSizeInFrames = PREFERRED_BUFFER_SIZE
	device_config.pUserData = audio_demo

	fmt.println("Configuring MiniAudio Device")
	if (ma.device_init(nil, &device_config, &audio_demo.device) != .SUCCESS) {
		fmt.println("Failed to open playback device.")
		return
	}

	// get audio device info just so we can get the real device buffer size
	info: ma.device_info
	ma.device_get_info(&audio_demo.device, ma.device_type.playback, &info)
	audio_demo.buffer_size = int(audio_demo.device.playback.internalPeriodSizeInFrames)

	// initialize ring buffer to be 8 times the size of the audio device buffer...
	buffer_init(&ring_buffer, audio_demo.buffer_size * 8)

	// starts the audio device and the audio callback thread
	fmt.println("Starting MiniAudio Device:", runtime.cstring_to_string(cstring(&info.name[0])))
	if (ma.device_start(&audio_demo.device) != .SUCCESS) {
		fmt.println("Failed to start playback device.")
		ma.device_uninit(&audio_demo.device)
		os.exit(1)
	}

	// start separate thread for generating audio samples
	// pass in a pointer to "app" as the data
	// thread.run_with_data(audio_demo, sample_generator_thread_proc)
}

sample_generator_thread_proc :: proc(data: rawptr) {
	// cast the "data" we passed into the thread to an ^App
	a := (^AudioDemo)(data)

	// loop infinitely in this new thread
	for {

		// we only want write new samples if there is enough "free" space in the ring buffer
		// so stall the thread if we've filled over half the buffer
		// and wait until the audio callback calls sema_post()
		for a.ring_buffer.written > len(a.ring_buffer.data) / 2 do sync.sema_wait(&sema)

		sync.lock(&a.mutex)
		for i in 0 ..< a.buffer_size {
			sample: f64 = math.sin_f64(math.PI * 2 * f64(220) * a.time)
			buffer_write_sample(&a.ring_buffer, f32(sample), true)
			// advance the time
			a.time += 1 / f64(OUTPUT_SAMPLE_RATE)
		}
		sync.unlock(&a.mutex)
	}
}

apu_read :: proc(using nes: ^NES, addr: u16) -> u8 {

	// addr will be 0x4015
	// Status: DMC interrupt, frame interrupt, length counter status: noise, triangle, pulse 2, pulse 1 (read)
	// IF-D NT21

	return 1
}

apu_write :: proc(using nes: ^NES, addr: u16, val: u8) {
	using apu

	switch addr {
	/// PULSE channels

	// Pulse 1 Duty cycle
	case 0x4000:
		switch (val & 0xC0) >> 6 {
		// the 4 duty cycle modes.
		case 0x00:
			pulse1_seq.sequence = 0b00000001
			pulse1_osc.duty_cycle = 0.125
		case 0x01:
			pulse1_seq.sequence = 0b00000011
			pulse1_osc.duty_cycle = 0.250
		case 0x02:
			pulse1_seq.sequence = 0b00001111
			pulse1_osc.duty_cycle = 0.500
		case 0x03:
			pulse1_seq.sequence = 0b11111100
			pulse1_osc.duty_cycle = 0.750
		}
	// Pulse 2 Duty cycle
	case 0x4004:

	// Pulse 1 APU Sweep
	case 0x4001:
	// Pulse 2 APU Sweep
	case 0x4005:

	// Pulse 1 timer Low 8 bits
	case 0x4002:
		pulse1_seq.reload = (pulse1_seq.reload & 0xFF00) | u16(val)

	// Pulse 2 timer Low 8 bits
	case 0x4006:

	// Pulse 1 length counter load and timer High 3 bits 
	case 0x4003:
		// pulse1_seq.reload = (pulse1_seq.reload & 0xFF00) | u16(val)
		pulse1_seq.reload = (u16(val) & 0x07) << 8 | (pulse1_seq.reload & 0x00FF)
		pulse1_seq.timer = pulse1_seq.reload

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
		pulse1_enable = (val & 0x01) != 0

	/// APU Frame counter
	// 5-frame sequence, disable frame interrupt (write) 
	// SD-- ----
	case 0x4017:

	}
}

last_sample : f32

audio_callback :: proc(device: ^ma.device, output, input: rawptr, frame_count: u32) {

	app := (^AudioDemo)(device.pUserData)

	// get device buffer
	device_buffer := mem.slice_ptr((^f32)(output), int(frame_count))

	for i in 0 ..< frame_count {
		sample, ok := chan.try_recv(sample_channel)
		if ok {
			// fmt.println("got sample")
			device_buffer[i] = sample * 0.1
			last_sample = device_buffer[i]
		} else {
			// fmt.println("did not got sample")
			device_buffer[i] = last_sample
		}
	}
}

// nes stuff

apu_init :: proc(using nes: ^NES) {
	using apu

	pulse1_osc.amp = 1
	pulse1_osc.pi = 3.14159
	pulse1_osc.harmonics = 20
}

apu_tick :: proc(using nes: ^NES) {
	using apu

	quarter_frame_clock: bool
	half_frame_clock: bool

	global_time += 0.333333333333 / 1789773

	if clock_counter % 6 == 0 {
		frame_clock_counter += 1

		// 4-Step Sequence Mode
		if frame_clock_counter == 3729 {
			quarter_frame_clock = true
		}

		if frame_clock_counter == 7457 {
			quarter_frame_clock = true
			half_frame_clock = true
		}

		if frame_clock_counter == 11186 {
			quarter_frame_clock = true
		}

		if frame_clock_counter == 14916 {
			quarter_frame_clock = true
			half_frame_clock = true
			frame_clock_counter = 0
		}

		// Update functional units

		// Quater frame "beats" adjust the volume envelope
		if quarter_frame_clock {
			// pulse1_env.clock(pulse1_halt);
			// pulse2_env.clock(pulse2_halt);
			// noise_env.clock(noise_halt);
		}

		// Half frame "beats" adjust the note length and
		// frequency sweepers
		if half_frame_clock {
			// pulse1_lc.clock(pulse1_enable, pulse1_halt)
			// pulse2_lc.clock(pulse2_enable, pulse2_halt)
			// noise_lc.clock(noise_enable, noise_halt)
			// pulse1_sweep.clock(pulse1_seq.reload, 0)
			// pulse2_sweep.clock(pulse2_seq.reload, 1)
		}

		// Update Pulse 1 channel
		sequencer_clock(
			&pulse1_seq,
			pulse1_enable,
			proc(seq: ^u32) {
				// Shift right by 1 bit, wrapping around
				seq^ = ((seq^ & 0x0001) << 7) | ((seq^ & 0x00FE) >> 1)
			},
		)
		pulse1_sample = f64(pulse1_seq.output)


		if (clock_counter % (6 * 20)) == 0 && pulse1_enable {

			// make the signal sound nice

			// pulse1_osc.freq = 1789773.0 / (16.0 * f64(pulse1_seq.reload + 1))
			// pulse1_sample = osc_sample(&pulse1_osc, global_time)
			ok := chan.try_send(sample_channel, f32(pulse1_sample))

			if !ok {
				fmt.printfln("not ok")
			}
		}

		// for ring_buffer.written > len(ring_buffer.data) / 2 do sync.sema_wait(&sema)
		// sync.lock(&mutex)
		// // debug here
		// buffer_write_sample(&ring_buffer, f32(pulse1_sample), true)
		// sync.unlock(&mutex)
	}

	clock_counter += 1
}

Sequencer :: struct {
	sequence: u32,
	timer:    u16,
	reload:   u16,
	output:   u8,
}

SequencerProc :: proc(sequence: ^u32)

PulseOscilator :: struct {
	freq:       f64,
	duty_cycle: f64,
	amp:        f64,
	pi:         f64,
	harmonics:  f32,
}

osc_sample :: proc(using pulse_osc: ^PulseOscilator, t: f64) -> f64 {

	a: f64 = 0
	b: f64 = 0
	p: f64 = duty_cycle * 2.0 * pi

	approx_sin :: proc(t: f64) -> f64 {
		j: f64 = t * 0.15915
		j = j - math.floor(j)
		return 20.785 * j * (j - 0.5) * (j - 1.0)
	}

	for n in 1 ..< harmonics {
		n_f := f64(n)
		c: f64 = n_f * freq * 2.0 * pi * t
		a += -approx_sin(c) / n_f
		b += -approx_sin(c - p * n_f) / n_f
	}

	return (2.0 * amp / pi) * (a - b)
}

sequencer_clock :: proc(using seq: ^Sequencer, enable: bool, seq_proc: SequencerProc) -> u8 {
	if !enable do return output

	timer -= 1
	if timer == 0xFFFF {
		timer = reload
		seq_proc(&sequence)
		output = u8(sequence) & 0x01
	}

	return output
}

APU :: struct {
	frame_clock_counter: u32,
	clock_counter:       u32,

	// Pulse 1
	pulse1_seq:          Sequencer,
	pulse1_enable:       bool,
	pulse1_sample:       f64,
	pulse1_osc:          PulseOscilator,
	global_time:         f64,
}
