package main

NoiseChannel :: struct {
	envelope:       Envelope,
	seq:            Sequencer,
	shift_register: u16,
	mode_flag:      bool,
	lc:             LengthCounter,
}

noise_init :: proc(using noise: ^NoiseChannel) {
	shift_register = 1
	lc.enabled = true
}

noise_cpu_write :: proc(using noise: ^NoiseChannel, addr: u16, val: u8) {
	
	//odinfmt:disable
    noise_period_lookup_table: [16]u16 = {4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068}
	//odinfmt:enable

	switch addr {
	// NOISE Envelope loop / length counter halt (L), constant volume (C), volume/envelope (V) 
	//   --LC VVVV
	case 0x400C:
		l := (val & 0x20) != 0
		c := (val & 0x10) != 0
		v := (val & 0x0F)

		lc.halt = l
		envelope_set(&envelope, c, v)

	// NOISE Loop noise (L), noise period (P) 
	//   L--- PPPP
	case 0x400E:
		l := (val & 0x80) != 0
		p := (val & 0x0F)

		seq.reload = noise_period_lookup_table[p] - 1
		mode_flag = l

	// NOISE Length counter load (L) 
	//   LLLL L---
	case 0x400F:
		l := (val & 0xF8) >> 3
		lc_load(&lc, l)
		envelope_reset(&envelope)
	}
}

noise_update :: proc(using noise: ^NoiseChannel) {
	if !lc.enabled do return

	seq.timer -= 1
	if seq.timer == 0xFFFF {
		seq.timer = seq.reload

		// Feedback is calculated as the exclusive-OR of bit 0 and one other 
		//  bit: bit 6 if Mode flag is set, otherwise bit 1.
		feedback: u16 = (shift_register & 0x01) ~ ((shift_register >> (mode_flag ? 6 : 1)) & 0x01)
		shift_register >>= 1
		shift_register |= (feedback << 14)
	}
}

noise_sample :: proc(using noise: ^NoiseChannel) -> u8 {
	if !lc.enabled do return 0
    if lc.counter <= 0 do return 0
    if (shift_register & 0x01) != 0 do return 0

    return envelope_get_volume(envelope, lc)
}
