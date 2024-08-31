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

last_sample: f32

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

APU :: struct {
	frame_clock_counter: u32,
	clock_counter:       u32,
	pulse1:              PulseChannel,
	pulse2:              PulseChannel,
	triangle:            TriangleChannel,
	global_time:         f64,
}

apu_read :: proc(using nes: ^NES, addr: u16) -> u8 {

	// addr will be 0x4015
	// Status: DMC interrupt, frame interrupt, length counter status: noise, triangle, pulse 2, pulse 1 (read)
	// IF-D NT21

	return 1
}

apu_write :: proc(using nes: ^NES, addr: u16, val: u8) {
	using apu

	set_pulse_duty_cycle :: proc(val: u8, pulse: ^PulseChannel) {
		switch (val & 0xC0) >> 6 {
		// the 4 duty cycle modes.
		case 0x00:
			pulse.seq.sequence = 0b00000001
			pulse.osc.duty_cycle = 0.125
		case 0x01:
			pulse.seq.sequence = 0b00000011
			pulse.osc.duty_cycle = 0.250
		case 0x02:
			pulse.seq.sequence = 0b00001111
			pulse.osc.duty_cycle = 0.500
		case 0x03:
			pulse.seq.sequence = 0b11111100
			pulse.osc.duty_cycle = 0.750
		}

		// LC halt
		l: bool = (val & 0x20) != 0
		pulse.length_counter.halt = l
	}

	set_pulse_timer_low :: proc(val: u8, pulse: ^PulseChannel) {
		pulse.seq.reload = (pulse.seq.reload & 0xFF00) | u16(val)
	}

	set_pulse_timer_high :: proc(val: u8, pulse: ^PulseChannel) {
		// pulse1_seq.reload = (pulse1_seq.reload & 0xFF00) | u16(val)
		pulse.seq.reload = (u16(val) & 0x07) << 8 | (pulse.seq.reload & 0x00FF)
		pulse.seq.timer = pulse.seq.reload

		l := (val & 0xF8) >> 3
		lc_load(&pulse.length_counter, l)
	}

	switch addr {
	/// PULSE channels

	// Pulse 1 Duty cycle
	case 0x4000:
		set_pulse_duty_cycle(val, &pulse1)

	// Pulse 2 Duty cycle
	case 0x4004:
		set_pulse_duty_cycle(val, &pulse2)

	// Pulse 1 APU Sweep
	case 0x4001:
	// Pulse 2 APU Sweep
	case 0x4005:

	// Pulse 1 timer Low 8 bits
	case 0x4002:
		set_pulse_timer_low(val, &pulse1)

	// Pulse 2 timer Low 8 bits
	case 0x4006:
		set_pulse_timer_low(val, &pulse2)

	// Pulse 1 length counter load and timer High 3 bits 
	case 0x4003:
		set_pulse_timer_high(val, &pulse1)

	// Pulse 2 length counter load and timer High 3 bits 
	case 0x4007:
		set_pulse_timer_high(val, &pulse2)

	/// TRIANGLE channel

	// Triangle Length counter halt / linear counter control (C), linear counter load (R) 
	//    CRRR RRRR
	case 0x4008:
		// fmt.printfln("write to 40008: %X", val)
		// Getting R 
		r := val & 0x7F
		// Getting C
		c := val & 0x80

		triangle.length_counter.halt = c != 0
		triangle.linear_counter_reload = int(r)

	// Unused
	case 0x4009:

	// Triangle timer low
	case 0x400A:
		triangle.seq.reload = triangle.seq.reload & 0xFF00 | u16(val)

	// Length counter load (L), timer high (T), set linear counter reload flag 
	//   LLLL LTTT
	case 0x400B:
		triangle.seq.reload = (u16(val) & 0x07) << 8 | (triangle.seq.reload & 0x00FF)
		triangle.seq.timer = triangle.seq.reload
		triangle.linear_reload_flag = true

		l := (val & 0xF8) >> 3
		lc_load(&triangle.length_counter, l)

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
		lc_set_enabled(&pulse1.length_counter, (val & 0x01) != 0)
		lc_set_enabled(&pulse2.length_counter, (val & 0x01) != 0)

	// TODO the rest of lc
	// lc_set_enabled(&triangle.length_counter, (val & 0x04) != 0)

	/// APU Frame counter
	// 5-frame sequence, disable frame interrupt (write) 
	// SD-- ----
	case 0x4017:

	}
}

apu_init :: proc(using nes: ^NES) {
	using apu

	pulse_init(&pulse1)
	pulse_init(&pulse2)
	triangle_init(&triangle)
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
			lc_tick(&pulse1.length_counter)
			lc_tick(&pulse2.length_counter)
			lc_tick(&triangle.length_counter)

			// pulse1_lc.clock(pulse1_enable, pulse1_halt)
			// pulse2_lc.clock(pulse2_enable, pulse2_halt)
			// noise_lc.clock(noise_enable, noise_halt)
			// pulse1_sweep.clock(pulse1_seq.reload, 0)
			// pulse2_sweep.clock(pulse2_seq.reload, 1)
		}

		// Update Pulse 1 channel
		pulse_update(&pulse1)
		// Update Pulse 2 channel
		pulse_update(&pulse2)

		// for ring_buffer.written > len(ring_buffer.data) / 2 do sync.sema_wait(&sema)
		// sync.lock(&mutex)
		// // debug here
		// buffer_write_sample(&ring_buffer, f32(pulse1_sample), true)
		// sync.unlock(&mutex)
	}

	if clock_counter % 3 == 0 {
		// Update Triangle channel

		sequencer_clock(&triangle.seq, triangle.length_counter.enabled, proc(seq: ^u32) {
			seq^ = seq^ + 1
			if seq^ >= 32 {
				seq^ = 0
			}
		})
	}

	// generating sample (mixing everything)
	if (clock_counter % (6 * 20)) == 0 {

		// make the signal sound nice
		sample: f64

		pulse1_s := pulse_sample(&pulse1)
		pulse2_s := pulse_sample(&pulse2)

		triangle_s := triangle_sample(&triangle)

		// formula for mixing
		pulse_out: f64 = 95.88 / ((8128 / (pulse1_s * 5 + pulse2_s * 5)) + 100)

		if pulse1_s == 0 && pulse2_s == 0 {
			pulse_out = 0
		}

		tnd_out: f64 = (159.79 / ((1 / (triangle_s / 8227)) + 100))

		if triangle_s == 0 {
			tnd_out = 0
		}

		sample = pulse_out + tnd_out

		// sample = tnd_out

		// sample = (pulse1_s - 0.5) * 0.5 + (pulse2_s - 0.5) * 0.5

		// pulse1_osc.freq = 1789773.0 / (16.0 * f64(pulse1_seq.reload + 1))
		// pulse1_sample = osc_sample(&pulse1_osc, global_time)
		ok := chan.try_send(sample_channel, f32(sample))

		if !ok {
			fmt.printfln("not ok")
		}
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

// -- Length Counter

LengthCounter :: struct {
	// uint8_t _lcLookupTable[32] = { 10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14, 12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30 };
	new_halt_value: bool,
	counter:        u8,
	reload_value:   u8,
	previous_value: u8,
	enabled:        bool,
	halt:           bool,
}

lc_load :: proc(using lc: ^LengthCounter, index: u8) {

	if !lc.enabled do return

	lookuptable: [32]u8 =  {
		10,
		254,
		20,
		2,
		40,
		4,
		80,
		6,
		160,
		8,
		60,
		10,
		14,
		12,
		26,
		14,
		12,
		16,
		24,
		18,
		48,
		20,
		96,
		22,
		192,
		24,
		72,
		26,
		16,
		28,
		32,
		30,
	}

	lc.reload_value = lookuptable[index]
	lc.previous_value = lc.counter
	lc.counter = lc.reload_value
}

lc_set_enabled :: proc(using lc: ^LengthCounter, new_enable: bool) {
	if !new_enable {
		lc.counter = 0
	}
	lc.enabled = new_enable
}

lc_tick :: proc(using lc: ^LengthCounter) {

	if lc.halt do return

	if lc.counter > 0 {
		lc.counter -= 1
	}
}

// -- /Length Counter


PulseChannel :: struct {
	seq:            Sequencer,
	osc:            PulseOscilator,
	length_counter: LengthCounter,
}

pulse_update :: proc(pulse: ^PulseChannel) {
	sequencer_clock(
		&pulse.seq,
		pulse.length_counter.enabled,
		proc(seq: ^u32) {
			// Shift right by 1 bit, wrapping around
			seq^ = ((seq^ & 0x0001) << 7) | ((seq^ & 0x00FE) >> 1)
		},
	)

}

pulse_init :: proc(pulse: ^PulseChannel) {
	pulse.osc.amp = 1
	pulse.osc.pi = 3.14159
	pulse.osc.harmonics = 20

	pulse.length_counter.enabled = true
}

pulse_sample :: proc(using pulse: ^PulseChannel) -> f64 {
	if !length_counter.enabled {
		return 0
	}

	if length_counter.counter <= 0 {
		return 0
	}

	return f64(pulse.seq.output)
}

TriangleChannel :: struct {
	seq:                   Sequencer,
	seq_pos:               int,
	// length_counter:        int,
	// length_counter_halt:   bool,
	linear_counter:        int,
	linear_counter_reload: int,
	linear_reload_flag:    bool,
	linear_control_flag:   bool,
	length_counter:        LengthCounter,
}

triangle_init :: proc(using triangle: ^TriangleChannel) {
	length_counter.enabled = true
}

triangle_sample :: proc(using triangle: ^TriangleChannel) -> f64 {

	if !length_counter.enabled do return 0
	if length_counter.counter <= 0 do return 0

	triangle_s: f64

	switch seq.sequence {
	case 0:
		triangle_s = 15
	case 1:
		triangle_s = 14
	case 2:
		triangle_s = 13
	case 3:
		triangle_s = 12
	case 4:
		triangle_s = 11
	case 5:
		triangle_s = 10
	case 6:
		triangle_s = 9
	case 7:
		triangle_s = 8
	case 8:
		triangle_s = 7
	case 9:
		triangle_s = 6
	case 10:
		triangle_s = 5
	case 11:
		triangle_s = 4
	case 12:
		triangle_s = 3
	case 13:
		triangle_s = 2
	case 14:
		triangle_s = 1
	case 15:
		triangle_s = 0
	case 16:
		triangle_s = 0
	case 17:
		triangle_s = 1
	case 18:
		triangle_s = 2
	case 19:
		triangle_s = 3
	case 20:
		triangle_s = 4
	case 21:
		triangle_s = 5
	case 22:
		triangle_s = 6
	case 23:
		triangle_s = 7
	case 24:
		triangle_s = 8
	case 25:
		triangle_s = 9
	case 26:
		triangle_s = 10
	case 27:
		triangle_s = 11
	case 28:
		triangle_s = 12
	case 29:
		triangle_s = 13
	case 30:
		triangle_s = 14
	case 31:
		triangle_s = 15
	}

	return triangle_s
}
