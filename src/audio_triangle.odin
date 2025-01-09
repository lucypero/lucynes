package main

// -- Triangle channel

LinearCounter :: struct {
	counter:      u8,
	reload:       u8,
	reload_flag:  bool,
	control_flag: bool,
}

linear_counter_tick :: proc(using lc: ^LinearCounter) {
	if reload_flag {
		counter = reload
	} else if counter > 0 {
		counter -= 1
	}

	if !control_flag {
		reload_flag = false
	}
}

TriangleChannel :: struct {
	seq:            Sequencer,
	seq_pos:        int,
	length_counter: LengthCounter,
	lin_c:          LinearCounter,
}

triangle_init :: proc(using triangle: ^TriangleChannel) {
	length_counter.enabled = true
}

triangle_update :: proc(using triangle: ^TriangleChannel) {
	seq.timer -= 1
	if seq.timer == 0xFFFF {
		seq.timer = seq.reload

		if length_counter.counter > 0 && lin_c.counter > 0 {
			seq.sequence = seq.sequence + 1
			if seq.sequence >= 32 {
				seq.sequence = 0
			}
			seq.output = u8(seq.sequence & 0x01)
		}
	}
}


triangle_sample :: proc(using triangle: ^TriangleChannel) -> u8 {
	
	//odinfmt:disable
	tri_sequence: [32]u8 =  { 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
	//odinfmt:enable

	if !length_counter.enabled do return 0
	if length_counter.counter <= 0 do return 0
	if seq.reload < 2 do return 0

	return tri_sequence[seq.sequence]
}

triangle_cpu_write :: proc(using triangle: ^TriangleChannel, addr: u16, val: u8) {
	switch addr {
	// Triangle Length counter halt / linear counter control (C), linear counter load (R) 
	//    CRRR RRRR
	case 0x4008:
		r := val & 0x7F
		c := (val & 0x80) != 0

		lin_c.control_flag = c
		lin_c.reload = r
		length_counter.halt = c

	// Triangle timer low
	case 0x400A:
		seq.reload = seq.reload & 0xFF00 | u16(val)
	// fmt.printfln("write 400A %v (seq reload) (low)", val)

	// Length counter load (L), timer high (T), set linear counter reload flag 
	//   LLLL LTTT
	case 0x400B:
		l := (val & 0xF8) >> 3
		t := (val & 0x07)

		lc_load(&length_counter, l)
		seq.reload = (u16(t) << 8) | (seq.reload & 0x00FF)
		lin_c.reload_flag = true
	}
}

// -- / Triangle channel
