package main

import "core:fmt"

stack_push :: proc(using nes: ^NES, value: u8) {
	ram[0x0100 + u16(stack_pointer)] = value
	stack_pointer -= 1
}

stack_pop :: proc(using nes: ^NES) -> u8 {
	stack_pointer += 1
	popped_val := ram[0x0100 + u16(stack_pointer)]
	return popped_val
}

// sets the N flag given a value.
// it is set to 1 if bit 7 of value is set
set_n :: proc(flags: ^RegisterFlags, value: u8) {
	set_flag(flags, .Negative, (value & 0x80) != 0)
}

set_z :: proc(flags: ^RegisterFlags, value: u8) {
	set_flag(flags, .Zero, value == 0)
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

	temp := u16(value^) << 1

	set_flag(&flags, .Carry, (value^ & 0x80) != 0)
	set_flag(&flags, .Zero, (temp & 0xFF) == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	value^ = u8(temp & 0x00FF)
}

instr_asl_accum :: proc(using nes: ^NES, _mem: u16) {
	instr_asl_inner(nes, &accumulator)
}

instr_asl :: proc(using nes: ^NES, mem: u16) {
	instr_asl_inner(nes, &ram[mem])
}

instr_adc_value :: proc(using nes: ^NES, mem: u16) {
	instr_adc_inner(nes, u8(mem))
}

instr_adc :: proc(using nes: ^NES, mem: u16) {
	instr_adc_inner(nes, ram[mem])
}

instr_adc_inner :: proc(using nes: ^NES, value: u8) {
	val: u16 = u16(value)
	temp: u16 = u16(nes.accumulator) + val

	if .Carry in nes.flags {
		temp += 1
	}

	did_overflow := ((~(u16(accumulator) ~ val) & (u16(accumulator) ~ u16(temp))) & 0x0080) != 0
	accumulator = u8(temp & 0x00FF)

	set_flag(&flags, .Carry, temp > 255)
	set_flag(&flags, .Overflow, did_overflow)
	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
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

instr_cmp_value :: proc(using nes: ^NES, mem: u16) {
	val := u8(mem)

	if accumulator >= val {
		flags += {.Carry}
	}

	set_flag(&flags, .Carry, accumulator >= val)
	set_flag(&flags, .Zero, accumulator == val)
	set_flag(&flags, .Negative, ((accumulator - val) & 0x80) != 0)
}

instr_cmp :: proc(using nes: ^NES, mem: u16) {
	instr_compare_helper(nes, accumulator, mem)
}

instr_cpx_value :: proc(using nes: ^NES, mem: u16) {
	val := u8(mem)

	if index_x >= val {
		flags += {.Carry}
	}

	set_flag(&flags, .Carry, index_x >= val)
	set_flag(&flags, .Zero, index_x == val)
	set_flag(&flags, .Negative, ((index_x - val) & 0x80) != 0)
}

instr_cpx :: proc(using nes: ^NES, mem: u16) {
	instr_compare_helper(nes, index_x, mem)
}

instr_cpy_value :: proc(using nes: ^NES, mem: u16) {
	val := u8(mem)

	if index_y >= val {
		flags += {.Carry}
	}

	set_flag(&flags, .Carry, index_y >= val)
	set_flag(&flags, .Zero, index_y == val)
	set_flag(&flags, .Negative, ((index_y - val) & 0x80) != 0)
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

instr_eor_value :: proc(using nes: ^NES, mem: u16) {
	accumulator = accumulator ~ u8(mem)
	set_flag(&flags, .Zero, accumulator == 0)
	set_n(&flags, accumulator)
}

instr_eor :: proc(using nes: ^NES, mem: u16) {
	accumulator = accumulator ~ ram[mem]
	set_flag(&flags, .Zero, accumulator == 0)
	set_n(&flags, accumulator)
}

instr_inc :: proc(using nes: ^NES, mem: u16) {
	ram[mem] += 1
	set_z(&flags, ram[mem])
	set_n(&flags, ram[mem])
}

instr_inx :: proc(using nes: ^NES, mem: u16) {
	index_x += 1

	set_z(&flags, index_x)
	set_n(&flags, index_x)
}

instr_iny :: proc(using nes: ^NES, mem: u16) {
	index_y += 1

	set_z(&flags, index_y)
	set_n(&flags, index_y)
}

instr_jmp :: proc(using nes: ^NES, mem: u16) {
	// todo: implement jmp bug

	program_counter = mem
}

instr_jsr :: proc(using nes: ^NES, mem: u16) {
	program_counter -= 1

	byte: u8 = u8((program_counter >> 8) & 0x00FF)
	stack_push(nes, byte)

	byte = u8(program_counter & 0x00FF)
	stack_push(nes, byte)

	program_counter = mem
}

instr_lda_value :: proc(using nes: ^NES, val: u16) {
	accumulator = u8(val)

	// flags
	set_flag(&flags, .Zero, accumulator == 0)
	set_flag(&flags, .Negative, (accumulator & 0x80) != 0)
}

instr_lda :: proc(using nes: ^NES, mem: u16) {
	accumulator = ram[mem]

	// flags
	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_ldx_value :: proc(using nes: ^NES, mem: u16) {
	index_x = u8(mem)

	// flags
	set_z(&flags, index_x)
	set_n(&flags, index_x)
}

instr_ldx :: proc(using nes: ^NES, mem: u16) {
	index_x = ram[mem]

	// flags
	set_z(&flags, index_x)
	set_n(&flags, index_x)
}

instr_ldy_value :: proc(using nes: ^NES, mem: u16) {
	index_y = u8(mem)

	// flags
	set_z(&flags, index_y)
	set_n(&flags, index_y)
}

instr_ldy :: proc(using nes: ^NES, mem: u16) {
	index_y = ram[mem]

	// flags
	set_z(&flags, index_y)
	set_n(&flags, index_y)
}

instr_lsr_inner :: proc(using nes: ^NES, val: ^u8) {
	temp := val^

	val^ = val^ >> 1

	set_flag(&flags, .Carry, (temp & 0x1) == 1)

	set_z(&flags, val^)
	set_n(&flags, val^)
}

instr_lsr_accumulator :: proc(using nes: ^NES, mem: u16) {
	instr_lsr_inner(nes, &accumulator)
}

instr_lsr :: proc(using nes: ^NES, mem: u16) {
	instr_lsr_inner(nes, &ram[mem])
}

instr_nop :: proc(using nes: ^NES, mem: u16) {
}

instr_ora_value :: proc(using nes: ^NES, mem: u16) {
	accumulator |= u8(mem)

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_ora :: proc(using nes: ^NES, mem: u16) {
	accumulator |= ram[mem]

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_pha :: proc(using nes: ^NES, mem: u16) {
	stack_push(nes, accumulator)
}

instr_php :: proc(using nes: ^NES, mem: u16) {
	// you set B to the flags you push to the stack
	//  but you do not modify the flags themselves.
	//  this is odd...
	pushed_flags := flags
	pushed_flags += {.NoEffectB}
	stack_push(nes, transmute(u8)pushed_flags)
}

instr_pla :: proc(using nes: ^NES, mem: u16) {
	accum := stack_pop(nes)

	accumulator = accum

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_plp :: proc(using nes: ^NES, mem: u16) {
	// void PLP(arg_t& src) { flags = cpu_pop8() | D5; }
	// why are u ORing with D5...
	new_flags := stack_pop(nes)
	flags = transmute(RegisterFlags)new_flags
	flags -= {.NoEffectB}
}

instr_rol_inner :: proc(using nes: ^NES, val: ^u8) {
	temp := val^

	val^ = val^ << 1

	if (.Carry in flags) {
		val^ += 1
	}

	set_flag(&flags, .Carry, (temp & 0x80) != 0)

	set_z(&flags, val^)
	set_n(&flags, val^)
}

instr_rol_accumulator :: proc(using nes: ^NES, mem: u16) {
	instr_rol_inner(nes, &accumulator)
}

instr_rol :: proc(using nes: ^NES, mem: u16) {
	instr_rol_inner(nes, &ram[mem])
}

instr_ror_inner :: proc(using nes: ^NES, val: ^u8) {
	temp := val^

	val^ = val^ >> 1

	if (.Carry in flags) {
		val^ = val^ | 0x80
	}

	set_flag(&flags, .Carry, (temp & 0x01) == 1)

	set_z(&flags, val^)
	set_n(&flags, val^)
}

instr_ror_accumulator :: proc(using nes: ^NES, mem: u16) {
	instr_ror_inner(nes, &accumulator)
}

instr_ror :: proc(using nes: ^NES, mem: u16) {
	instr_ror_inner(nes, &ram[mem])
}

instr_rti :: proc(using nes: ^NES, mem: u16) {
	new_flags := stack_pop(nes)

	flags = transmute(RegisterFlags)new_flags

	pc_low := stack_pop(nes)
	pc_high := stack_pop(nes)

	program_counter = u16(pc_high) << 8 + u16(pc_low)
}

instr_rts :: proc(using nes: ^NES, mem: u16) {

	pc_low := stack_pop(nes)
	pc_high := stack_pop(nes)

	program_counter = u16(pc_high) << 8 | u16(pc_low)
	program_counter += 1
}

instr_sbc_inner :: proc(using nes: ^NES, mem: u8) {
	instr_adc_inner(nes, ~mem)
}

instr_sbc :: proc(using nes: ^NES, mem: u16) {
	instr_sbc_inner(nes, ram[mem])
}

instr_sbc_value :: proc(using nes: ^NES, mem: u16) {
	instr_sbc_inner(nes, u8(mem))
}

instr_sec :: proc(using nes: ^NES, mem: u16) {
	flags += {.Carry}
}

instr_sed :: proc(using nes: ^NES, mem: u16) {
	flags += {.Decimal}
}

instr_sei :: proc(using nes: ^NES, mem: u16) {
	flags += {.InterruptDisable}
}

instr_sta :: proc(using nes: ^NES, mem: u16) {
	ram[mem] = accumulator
}

instr_stx :: proc(using nes: ^NES, mem: u16) {
	ram[mem] = index_x
}

instr_sty :: proc(using nes: ^NES, mem: u16) {
	ram[mem] = index_y
}

instr_tax :: proc(using nes: ^NES, mem: u16) {
	index_x = accumulator

	set_z(&flags, index_x)
	set_n(&flags, index_x)
}

instr_tay :: proc(using nes: ^NES, mem: u16) {
	index_y = accumulator

	set_z(&flags, index_y)
	set_n(&flags, index_y)
}

instr_tsx :: proc(using nes: ^NES, mem: u16) {
	index_x = stack_pointer

	set_z(&flags, index_x)
	set_n(&flags, index_x)
}

instr_txa :: proc(using nes: ^NES, mem: u16) {
	accumulator = index_x
	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_txs :: proc(using nes: ^NES, mem: u16) {
	stack_pointer = index_x
}

instr_tya :: proc(using nes: ^NES, mem: u16) {
	accumulator = index_y
	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}


// undocumented instructions

instr_aso :: proc(using nes: ^NES, mem: u16) {
	instr_asl(nes, mem)
	instr_ora(nes, mem)
}

instr_rla :: proc(using nes: ^NES, mem: u16) {
	instr_rol(nes, mem)
	instr_and(nes, mem)
}

instr_lse :: proc(using nes: ^NES, mem: u16) {
	instr_lsr(nes, mem)
	instr_eor(nes, mem)
}

instr_rra :: proc(using nes: ^NES, mem: u16) {
	instr_ror(nes, mem)
	instr_adc(nes, mem)
}

instr_axs :: proc(using nes: ^NES, mem: u16) {
	ram[mem] = accumulator & index_x
}

instr_lax :: proc(using nes: ^NES, mem: u16) {
	instr_lda(nes, mem)
	instr_ldx(nes, mem)
}

instr_dcm :: proc(using nes: ^NES, mem: u16) {
	instr_dec(nes, mem)
	instr_cmp(nes, mem)
}

instr_ins :: proc(using nes: ^NES, mem: u16) {
	instr_inc(nes, mem)
	instr_sbc(nes, mem)
}

instr_alr :: proc(using nes: ^NES, mem: u16) {
	instr_and_value(nes, mem)
	instr_lsr_accumulator(nes, mem)
}

instr_arr :: proc(using nes: ^NES, mem: u16) {
	instr_and_value(nes, mem)
	instr_ror_accumulator(nes, mem)
}

instr_xaa :: proc(using nes: ^NES, mem: u16) {
	instr_txa(nes, mem)
	instr_and_value(nes, mem)
}

instr_oal :: proc(using nes: ^NES, mem: u16) {
	instr_ora_value(nes, 0x00EE)
	instr_and_value(nes, mem)
	instr_tax(nes, mem)
}

instr_sax :: proc(using nes: ^NES, mem: u16) {
	// TODO
	fmt.eprintln("running SAC. not implemented!")
}

instr_hlt :: proc(using nes: ^NES, mem: u16) {
	fmt.eprintln("HLT opcode hit. the CPU should crash here!")
}

instr_tas :: proc(using nes: ^NES, mem: u16) {
	// TODO
	fmt.eprintln("running TAS. not implemented!")
}

instr_say :: proc(using nes: ^NES, mem: u16) {
	// TODO
	fmt.eprintln("running SAY. not implemented!")
}

instr_xas :: proc(using nes: ^NES, mem: u16) {
	// TODO
	fmt.eprintln("running XAS. not implemented!")
}

instr_axa :: proc(using nes: ^NES, mem: u16) {
	// TODO
	fmt.eprintln("running AXA. not implemented!")
}

instr_anc :: proc(using nes: ^NES, mem: u16) {
	// TODO
	fmt.eprintln("running ANC. not implemented!")
}

instr_las :: proc(using nes: ^NES, mem: u16) {
	// TODO
	fmt.eprintln("running LAS. not implemented!")
}
