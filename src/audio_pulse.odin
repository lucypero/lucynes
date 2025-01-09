package main

// -- Sweep

Sweep :: struct {
	enabled:       bool,
	reload:        bool,
	negate:        bool,
	shift_count:   u8,
	period:        u8,
	target_period: u32,
	divider:       u8,
}
// -- / Sweep


// -- Pulse channel

PulseChannel :: struct {
	is_channel_one: bool,
	seq:            Sequencer,
	osc:            PulseOscilator,
	length_counter: LengthCounter,
	real_period:    u16,
	sweep:          Sweep,
	envelope:       Envelope,
}

pulse_set_period :: proc(using pulse: ^PulseChannel, new_period: u16) {
	real_period = new_period
	// seq.reload = (real_period * 2) + 1
	seq.reload = real_period
	// 	_timer.SetPeriod((_realPeriod * 2) + 1);
	pulse_update_target_period(pulse)
}

pulse_sweep_tick :: proc(using pulse: ^PulseChannel) {
	sweep.divider -= 1

	if sweep.divider == 0 {
		if sweep.shift_count > 0 &&
		   sweep.enabled &&
		   real_period >= 8 &&
		   sweep.target_period <= 0x7FF {
			pulse_set_period(pulse, u16(sweep.target_period))
		}
		sweep.divider = sweep.period
	}

	if sweep.reload {
		sweep.divider = sweep.period
		sweep.reload = false
	}
}

pulse_update_target_period :: proc(using pulse: ^PulseChannel) {
	shift_result: u16 = (real_period >> sweep.shift_count)
	if (sweep.negate) {
		sweep.target_period = u32(real_period) - u32(shift_result)
		if (is_channel_one) {
			// As a result, a negative sweep on pulse channel 1 will subtract the shifted period value minus 1
			sweep.target_period -= 1
		}
	} else {
		sweep.target_period = u32(real_period) + u32(shift_result)
	}
}

pulse_update :: proc(using pulse: ^PulseChannel) {
	if !length_counter.enabled do return

	// clocking sequence
	// when timer triggers, you rotate the sequence

	seq.timer -= 1
	if seq.timer == 0xFFFF {
		seq.timer = seq.reload
		seq.index = (seq.index - 1) & 0x7
		seq.output = u8((seq.sequence & (0x1 << seq.index)) >> seq.index)
	}
}

pulse_init :: proc(pulse: ^PulseChannel, is_channel_one: bool) {
	pulse.is_channel_one = is_channel_one
	pulse.osc.amp = 1
	pulse.osc.pi = 3.14159
	pulse.osc.harmonics = 20

	pulse.length_counter.enabled = true
}

pulse_is_muted :: proc(using pulse: ^PulseChannel) -> bool {
	// A period of t < 8, either set explicitly or via a sweep period update,
	//   silences the corresponding pulse channel.
	condition := (real_period < 8) || (!sweep.negate && sweep.target_period > 0x7FF)
	return condition
}

pulse_sample :: proc(using pulse: ^PulseChannel) -> f64 {
	if !length_counter.enabled {
		return 0
	}

	if length_counter.counter <= 0 {
		return 0
	}

	if pulse_is_muted(pulse) do return 0

	env_vol := envelope_get_volume(pulse.envelope, pulse.length_counter)
	return f64(pulse.seq.output) * f64(env_vol)
}

// -- / Pulse channel
