package main

instr_lda_value :: proc(using nes: ^NES, val: u16) {
	accumulator = u8(val)

	// flags
	set_flag(&flags, .Zero, accumulator == 0)
	set_flag(&flags, .Negative, (accumulator & 0x80) != 0)
}

instr_lda :: proc(using nes: ^NES, mem: u16) {
	accumulator = ram[mem]

	// flags
	set_flag(&flags, .Zero, accumulator == 0)
	set_flag(&flags, .Negative, (accumulator & 0x80) != 0)
}

instr_and_value :: proc(using nes: ^NES, value: u16) {
	// A, Z, N = A&M

	temp: u16 = u16(nes.accumulator) & value

	set_flag(&flags, .Zero, temp == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	accumulator = u8(temp)
}

instr_and :: proc(using nes: ^NES, mem: u16) {
	instr_and_value(nes, u16(ram[mem]))
}

instr_asl_inner :: proc(using nes: ^NES, value: ^u8) {
	// A,Z,C,N = M*2 or M,Z,C,N = M*2

	temp := value^ << 1

	set_flag(&flags, .Carry, (value^ & 0x80) == 1)
	set_flag(&flags, .Zero, temp == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	value^ = temp
}

instr_asl_accum :: proc(using nes: ^NES, _mem: u16) {
	instr_asl_inner(nes, &accumulator)
}

instr_asl :: proc(using nes: ^NES, mem: u16) {
	instr_asl_inner(nes, &ram[mem])
}

instr_adc :: proc(using nes: ^NES, mem: u16) {

	val: u16 = u16(ram[mem])


	temp: u16 = u16(nes.accumulator) + val

	if .Carry in nes.flags {
		temp += 1
	}

	set_flag(&flags, .Carry, temp > 255)
	set_flag(&flags, .Zero, (temp & 0x00FF) == 0)
	set_flag(&flags, .Negative, (temp & 0x0080) != 0)
	set_flag(
		&flags,
		.Overflow,
		((~(u16(accumulator) ~ val) & (u16(accumulator) ~ u16(temp))) & 0x0080) != 0,
	)

	accumulator = u8(temp & 0x00FF)
}

instr_bcc :: proc(using nes: ^NES, mem: u16) {
	if .Carry not_in flags {
		program_counter = mem
	}
}

instr_bcs :: proc(using nes: ^NES, mem: u16) {
	if .Carry in flags {
		program_counter = mem
	}
}

instr_beq :: proc(using nes: ^NES, mem: u16) {
	if .Zero in flags {
		program_counter = mem
	}
}

instr_bit :: proc(using nes: ^NES, mem: u16) {

	// A & M, N = M7, V = M6

	set_flag(&flags, .Zero, (accumulator & ram[mem]) == 0)
	set_flag(&flags, .Overflow, (ram[mem] & 0x40) != 0)
	set_flag(&flags, .Negative, (ram[mem] & 0x80) != 0)
}

instr_bmi :: proc(using nes: ^NES, mem: u16) {
	if .Negative in flags {
		program_counter = mem
	}
}

instr_bne :: proc(using nes: ^NES, mem: u16) {
	if .Zero not_in flags {
		program_counter = mem
	}
}

instr_bpl :: proc(using nes: ^NES, mem: u16) {
	if .Negative not_in flags {
		program_counter = mem
	}
}

// TODO it does an interrupt. idk how to do this yet
instr_brk :: proc(using nes: ^NES, mem: u16) {
    flags += {.NoEffectB}
}

instr_bvc :: proc(using nes: ^NES, mem: u16) {
    if .Overflow not_in flags {
        program_counter = mem
    }
}


instr_bvs :: proc(using nes: ^NES, mem: u16) {
    if .Overflow in flags {
        program_counter = mem
    }
}

instr_clc :: proc(using nes: ^NES, mem: u16) {
    flags -= {.Carry}
}

instr_cld :: proc(using nes: ^NES, mem: u16) {
    flags -= {.Decimal}
}

instr_cli :: proc(using nes: ^NES, mem: u16) {
    flags -= {.InterruptDisable}
}

instr_clv :: proc(using nes: ^NES, mem: u16) {
    flags -= {.Overflow}
}

instr_compare_helper :: proc(using nes: ^NES, register: u8, mem: u16) {
    val := ram[mem]

    if register >= val {
        flags += {.Carry}
    }

	set_flag(&flags, .Carry, register >= val)
	set_flag(&flags, .Zero, register == val)
	set_flag(&flags, .Negative, ((register - val) & 0x80) != 0)
}

instr_cmp :: proc(using nes: ^NES, mem: u16) {
    instr_compare_helper(nes, accumulator, mem)
}

instr_cpx :: proc(using nes: ^NES, mem: u16) {
    instr_compare_helper(nes, index_x, mem)
}

instr_cpy :: proc(using nes: ^NES, mem: u16) {
    instr_compare_helper(nes, index_y, mem)
}

// TODO maybe do a decrement helper
instr_dec :: proc(using nes: ^NES, mem: u16) {
    ram[mem] -= 1

	set_flag(&flags, .Zero, ram[mem] == 0)
	set_flag(&flags, .Negative, (ram[mem] & 0x80) != 0)
}

instr_dex :: proc(using nes: ^NES, mem: u16) {
    index_x -= 1

	set_flag(&flags, .Zero, index_x == 0)
	set_flag(&flags, .Negative, (index_x & 0x80) != 0)
}

instr_dey :: proc(using nes: ^NES, mem: u16) {
    index_y -= 1

	set_flag(&flags, .Zero, index_y == 0)
	set_flag(&flags, .Negative, (index_y & 0x80) != 0)
}




