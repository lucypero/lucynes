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
PREFERRED_BUFFER_SIZE :: 512 * 2

SAMPLE_PACKET_SIZE :: PREFERRED_BUFFER_SIZE
CHANNEL_BUFFER_SIZE :: 10

effective_cpu_clockrate :: 1789773 * target_fps / 60.0988
ppu_ticks_between_samples :: (effective_cpu_clockrate * 3 / OUTPUT_SAMPLE_RATE)

SampleChannel :: chan.Chan([SAMPLE_PACKET_SIZE]f32)
sample_channel: SampleChannel

record_wav :: true
wav_file_seconds :: 30

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
	sample_channel, err = chan.create_buffered(
		SampleChannel,
		CHANNEL_BUFFER_SIZE,
		context.allocator,
	)
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

	sample_packet, ok := chan.try_recv(sample_channel)
	if !ok {
		fmt.eprintfln("channel recv error")

		for i in 0 ..< frame_count {
			device_buffer[i] = 0
		}
		// os.exit(1)
	}

	for i in 0 ..< frame_count {
		device_buffer[i] = sample_packet[i]
	}
}

// nes stuff

APU :: struct {
	frame_clock_counter:         u32,
	clock_counter:               u32,
	pulse1:                      PulseChannel,
	pulse2:                      PulseChannel,
	triangle:                    TriangleChannel,
	global_time:                 f64,
	ppu_ticks_since_last_sample: int,
	channel_buffer:              [SAMPLE_PACKET_SIZE]f32,
	channel_buffer_i:            int,
	samples_for_wav:             []f32,
	samples_for_wav_i:           int,
}

apu_read :: proc(using nes: ^NES, addr: u16) -> u8 {

	// addr will be 0x4015
	// Status: DMC interrupt, frame interrupt, length counter status: noise, triangle, pulse 2, pulse 1 (read)
	// IF-D NT21

	return 1
}

apu_write :: proc(using nes: ^NES, addr: u16, val: u8) {
	using apu

	// ddLC.VVVV
	set_pulse_4000_4004 :: proc(val: u8, pulse: ^PulseChannel) {

		// Duty
		d := (val & 0xC0) >> 6

		switch d {
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

		// Envelope constant volume flag, and volume set
		c: bool = (val & 0x10) != 0
		v: u8 = val & 0x0F

		envelope_set(&pulse.envelope, c, v)
	}

	// EPPP.NSSS
	set_pulse_sweep :: proc(pulse: ^PulseChannel, val: u8) {
		e := (val & 0x80) != 0
		p := (val & 0x70) >> 4
		n := (val & 0x08) != 0
		s := (val & 0x07)

		pulse.sweep.enabled = e
		pulse.sweep.period = p + 1
		pulse.sweep.negate = n
		pulse.sweep.shift_count = s

		// Update target period
		pulse_update_target_period(pulse)

		// Side effects: Set the reload flag
		pulse.sweep.reload = true
	}

	// $4002 and $4006
	// LLLL.LLLL
	set_pulse_timer_low :: proc(val: u8, pulse: ^PulseChannel) {
		// pulse.seq.reload = (pulse.seq.reload & 0xFF00) | u16(val)
		pulse_set_period(pulse, (pulse.real_period & 0xFF00) | u16(val))
	}

	// $4003 and $4007
	// LLLL.Lttt
	set_pulse_timer_high :: proc(val: u8, pulse: ^PulseChannel) {
		// pulse1_seq.reload = (pulse1_seq.reload & 0xFF00) | u16(val)
		t := val & 0x07

		pulse_set_period(pulse, (u16(t) << 8) | (pulse.real_period & 0x00FF))

		// reload sequencer
		pulse.seq.timer = pulse.seq.reload

		l := (val & 0xF8) >> 3
		lc_load(&pulse.length_counter, l)

		envelope_reset(&pulse.envelope)
	}

	switch addr {
	/// PULSE channels

	// Pulse 1 Duty cycle
	case 0x4000:
		set_pulse_4000_4004(val, &pulse1)

	// Pulse 2 Duty cycle
	case 0x4004:
		set_pulse_4000_4004(val, &pulse2)

	// Pulse 1 APU Sweep
	case 0x4001:
		set_pulse_sweep(&pulse1, val)
	// Pulse 2 APU Sweep
	case 0x4005:
		set_pulse_sweep(&pulse1, val)

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
		lc_set_enabled(&pulse2.length_counter, (val & 0x02) != 0)
		lc_set_enabled(&triangle.length_counter, (val & 0x04) != 0)

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

	pulse_init(&pulse1, true)
	pulse_init(&pulse2, false)
	triangle_init(&triangle)

	samples_for_wav = make([]f32, OUTPUT_SAMPLE_RATE * wav_file_seconds)
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
			envelope_tick(&pulse1.envelope, pulse1.length_counter)
			envelope_tick(&pulse2.envelope, pulse2.length_counter)

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

			pulse_sweep_tick(&pulse1)
			pulse_sweep_tick(&pulse2)

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

		// sequencer_clock(&triangle.seq, triangle.length_counter.enabled, proc(seq: ^u32) {
		// 	seq^ = seq^ + 1
		// 	if seq^ >= 32 {
		// 		seq^ = 0
		// 	}
		// })
	}

	alala: int = int_from_float(ppu_ticks_between_samples)

	ppu_ticks_since_last_sample += 1
	if ppu_ticks_since_last_sample > alala {
		ppu_ticks_since_last_sample -= alala

		generate_sample(&apu)
	}

	clock_counter += 1
}

int_from_float :: proc(f: f64) -> int {
	return int(f)
}

generate_sample :: proc(using apu: ^APU) {
	sample: f64

	pulse1_s := pulse_sample(&pulse1)
	// pulse2_s := pulse_sample(&pulse2)
	pulse2_s: f64 = 0

	triangle_s := triangle_sample(&triangle)

	// formula for mixing
	pulse_out: f64 = 95.88 / ((8128 / (pulse1_s + pulse2_s)) + 100)

	if pulse1_s == 0 && pulse2_s == 0 {
		pulse_out = 0
	}

	tnd_out: f64 = 159.79 / ((1 / (triangle_s / 8227)) + 100)

	if triangle_s == 0 {
		tnd_out = 0
	}

	tnd_out = 0
	sample = pulse_out + tnd_out

	// sample = tnd_out

	// sample = (pulse1_s - 0.5) * 0.5 + (pulse2_s - 0.5) * 0.5

	// pulse1_osc.freq = 1789773.0 / (16.0 * f64(pulse1_seq.reload + 1))
	// pulse1_sample = osc_sample(&pulse1_osc, global_time)

	add_sample(apu, f32(sample))


	// filling wav buffer
	when record_wav {
		add_sample_to_wav_file(apu, f32(sample))
	}
}


add_sample_to_wav_file :: proc(using apu: ^APU, sample: f32) {

	if samples_for_wav_i >= len(samples_for_wav) do return

	samples_for_wav[samples_for_wav_i] = sample

	samples_for_wav_i += 1

	if samples_for_wav_i >= len(samples_for_wav) {
		// writing file
		write_sample_wav_file_w_lib(samples_for_wav)
		fmt.println("wrote wav file with apu samples.")
		os.exit(0)
	}
}

// adds sample to current buffer. if buffer is filled, send it to the channel
add_sample :: proc(using apu: ^APU, sample: f32) {

	channel_buffer[channel_buffer_i] = sample

	channel_buffer_i += 1

	if channel_buffer_i >= len(channel_buffer) {
		channel_buffer_i = 0

		ok := chan.try_send(sample_channel, channel_buffer)

		if !ok {
			fmt.printfln("send not ok. buffer full")
			os.exit(1)
		}
	}
}

/// Sequencer

Sequencer :: struct {
	sequence: u32,
	timer:    u16,
	reload:   u16,
	output:   u8,
}

/// / Sequencer

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

// -- / Length Counter

// -- Envelope

Envelope :: struct {
	use_constant_volume: bool,
	volume:              u8,
	start:               bool,
	divider:             i8,
	counter:             u8,
}

envelope_set :: proc(env: ^Envelope, c: bool, volume: u8) {
	env.use_constant_volume = c
	env.volume = volume
}

envelope_reset :: proc(env: ^Envelope) {
	env.start = true
}

envelope_get_volume :: proc(env: Envelope, lc: LengthCounter) -> u32 {
	if lc.counter > 0 {
		return env.use_constant_volume ? u32(env.volume) : u32(env.counter)
	} else {
		return 0
	}
}

envelope_tick :: proc(using env: ^Envelope, lc: LengthCounter) {
	if !start {
		divider -= 1
		if divider < 0 {
			divider = i8(volume)
			if counter > 0 {
				counter -= 1
			} else if lc.halt {
				counter = 15
			}
		}
	} else {
		start = false
		counter = 15
		divider = i8(volume)
	}
}

// -- Triangle channel

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

// -- / Triangle channel
