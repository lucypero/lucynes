package main

import "core:fmt"

stack_push :: proc(using nes: ^NES, value: u8) {
	write(nes, 0x0100 + u16(stack_pointer), value)
	// fmt.printfln("pushing to stack %X, SP is %X", value, stack_pointer)
	stack_pointer -= 1
}

stack_pop :: proc(using nes: ^NES) -> u8 {
	stack_pointer += 1
	popped_val := read(nes, 0x0100 + u16(stack_pointer))
	// fmt.printfln("pulling from stack %X, SP is now %X", popped_val, stack_pointer)
	return popped_val
}

// TODO: use this instead of the manual way in the instructions
stack_push_u16 :: proc(using nes: ^NES, value: u16) {

	// fmt.println("pushing u16")

	byte: u8 = u8((value >> 8) & 0x00FF)
	stack_push(nes, byte)

	byte = u8(value & 0x00FF)
	stack_push(nes, byte)
}

stack_pop_u16 :: proc(using nes: ^NES) -> u16 {
	low := stack_pop(nes)
	high := stack_pop(nes)
	return u16(high) << 8 | u16(low)
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
	instruction_type = .Read
	// A, Z, N = A&M

	temp: u16 = u16(nes.accumulator) & value

	set_flag(&flags, .Zero, temp == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	accumulator = u8(temp)
}

instr_and :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	instr_and_value(nes, u16(read(nes, mem)))
}

instr_asl_accum :: proc(using nes: ^NES, _mem: u16) {
	instruction_type = .ReadModifyWrite
	temp := u16(accumulator) << 1

	set_flag(&flags, .Carry, (accumulator & 0x80) != 0)
	set_flag(&flags, .Zero, (temp & 0xFF) == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	accumulator = u8(temp & 0x00FF)
}

instr_asl :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .ReadModifyWrite
	ignore_extra_addressing_cycles = true
	val := read(nes, mem)

	temp := u16(val) << 1

	set_flag(&flags, .Carry, (val & 0x80) != 0)
	set_flag(&flags, .Zero, (temp & 0xFF) == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	dummy_read(nes)
	write(nes, mem, u8(temp & 0x00FF))
}

instr_adc_value :: proc(using nes: ^NES, mem: u16) {
	instr_adc_inner(nes, u8(mem))
}

instr_adc :: proc(using nes: ^NES, mem: u16) {
	instr_adc_inner(nes, read(nes, mem))
}

instr_adc_inner :: proc(using nes: ^NES, value: u8) {
	instruction_type = .Read
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

/// Branching instructions

instr_bcc :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Branch
	if .Carry not_in flags {
		extra_instr_cycles += 1
		dummy_read(nes)
		if (program_counter & 0xFF00) != (mem & 0xFF00) {
			// crossed pages
			extra_instr_cycles += 1
			dummy_read(nes)
		}
		program_counter = mem
	}
}

instr_bcs :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Branch
	if .Carry in flags {
		extra_instr_cycles += 1
		dummy_read(nes)
		if (program_counter & 0xFF00) != (mem & 0xFF00) {
			// crossed pages
			extra_instr_cycles += 1
			dummy_read(nes)
		}
		program_counter = mem
	}
}

instr_beq :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Branch
	if .Zero in flags {
		extra_instr_cycles += 1
		dummy_read(nes)
		if (program_counter & 0xFF00) != (mem & 0xFF00) {
			// crossed pages
			extra_instr_cycles += 1
			dummy_read(nes)
		}
		program_counter = mem
	}
}

instr_bmi :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Branch
	if .Negative in flags {
		extra_instr_cycles += 1
		dummy_read(nes)
		if (program_counter & 0xFF00) != (mem & 0xFF00) {
			// crossed pages
			extra_instr_cycles += 1
			dummy_read(nes)
		}
		program_counter = mem
	}
}

instr_bne :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Branch
	if .Zero not_in flags {
		extra_instr_cycles += 1
		dummy_read(nes)
		if (program_counter & 0xFF00) != (mem & 0xFF00) {
			// crossed pages
			extra_instr_cycles += 1
			dummy_read(nes)
		}
		program_counter = mem
	}
}

instr_bpl :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Branch
	if .Negative not_in flags {
		extra_instr_cycles += 1
		dummy_read(nes)
		if (program_counter & 0xFF00) != (mem & 0xFF00) {
			// crossed pages
			extra_instr_cycles += 1
			dummy_read(nes)
		}
		program_counter = mem
	}
}

instr_bvc :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Branch
	if .Overflow not_in flags {
		extra_instr_cycles += 1
		dummy_read(nes)
		if (program_counter & 0xFF00) != (mem & 0xFF00) {
			// crossed pages
			extra_instr_cycles += 1
			dummy_read(nes)
		}
		program_counter = mem
	}
}

instr_bvs :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Branch
	if .Overflow in flags {
		extra_instr_cycles += 1
		dummy_read(nes)
		if (program_counter & 0xFF00) != (mem & 0xFF00) {
			// crossed pages
			extra_instr_cycles += 1
			dummy_read(nes)
		}
		program_counter = mem
	}
}

/// End - Branching instructions


instr_bit :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	// A & M, N = M7, V = M6
	// fmt.printfln("accum %X, mem is %X", accumulator, mem)

	val := read(nes, mem)

	set_flag(&flags, .Zero, (accumulator & val) == 0)
	set_flag(&flags, .Overflow, (val & 0x40) != 0)
	set_flag(&flags, .Negative, (val & 0x80) != 0)
}


// TODO it does an interrupt. idk how to do this yet
instr_brk :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Other
	fmt.printfln("calling BRK. pc is %X", program_counter)
	flags += {.NoEffectB}
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
	val := read(nes, mem)

	if register >= val {
		flags += {.Carry}
	}

	set_flag(&flags, .Carry, register >= val)
	set_flag(&flags, .Zero, register == val)
	set_flag(&flags, .Negative, ((register - val) & 0x80) != 0)
}

instr_cmp_value :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	val := u8(mem)

	if accumulator >= val {
		flags += {.Carry}
	}

	set_flag(&flags, .Carry, accumulator >= val)
	set_flag(&flags, .Zero, accumulator == val)
	set_flag(&flags, .Negative, ((accumulator - val) & 0x80) != 0)
}

instr_cmp :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
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
	instruction_type = .ReadModifyWrite
	ignore_extra_addressing_cycles = true
	val := read(nes, mem)
	val -= 1
	dummy_read(nes)
	write(nes, mem, val)

	set_flag(&flags, .Zero, val == 0)
	set_flag(&flags, .Negative, (val & 0x80) != 0)
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
	instruction_type = .Read
	accumulator = accumulator ~ u8(mem)
	set_flag(&flags, .Zero, accumulator == 0)
	set_n(&flags, accumulator)
}

instr_eor :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	accumulator = accumulator ~ read(nes, mem)
	set_flag(&flags, .Zero, accumulator == 0)
	set_n(&flags, accumulator)
}

instr_inc :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .ReadModifyWrite
	ignore_extra_addressing_cycles = true
	val := read(nes, mem)
	val += 1
	dummy_read(nes)
	write(nes, mem, val)
	set_z(&flags, val)
	set_n(&flags, val)
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
	instruction_type = .Other
	// todo: implement jmp bug

	program_counter = mem
}

instr_jsr :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Other
	program_counter -= 1

	dummy_read(nes)

	byte: u8 = u8((program_counter >> 8) & 0x00FF)
	stack_push(nes, byte)

	byte = u8(program_counter & 0x00FF)
	stack_push(nes, byte)

	program_counter = mem
}

instr_lda_value :: proc(using nes: ^NES, val: u16) {
	instruction_type = .Read
	accumulator = u8(val)

	// flags
	set_flag(&flags, .Zero, accumulator == 0)
	set_flag(&flags, .Negative, (accumulator & 0x80) != 0)
}

instr_lda :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read

	accumulator = read(nes, mem)

	// flags
	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_ldx_value :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	index_x = u8(mem)

	// flags
	set_z(&flags, index_x)
	set_n(&flags, index_x)
}

instr_ldx :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	index_x = read(nes, mem)

	// flags
	set_z(&flags, index_x)
	set_n(&flags, index_x)
}

instr_ldy_value :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	index_y = u8(mem)

	// flags
	set_z(&flags, index_y)
	set_n(&flags, index_y)
}

instr_ldy :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	index_y = read(nes, mem)

	// flags
	set_z(&flags, index_y)
	set_n(&flags, index_y)
}

instr_lsr_accumulator :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .ReadModifyWrite
	temp := accumulator

	accumulator = accumulator >> 1

	set_flag(&flags, .Carry, (temp & 0x1) == 1)

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_lsr :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .ReadModifyWrite
	ignore_extra_addressing_cycles = true
	val := read(nes, mem)

	res := val >> 1
	dummy_read(nes)
	write(nes, mem, res)

	set_flag(&flags, .Carry, (val & 0x1) == 1)

	set_z(&flags, res)
	set_n(&flags, res)
}

instr_nop :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
}

// undocumented NOP $64, $04, $44
instr_nop_zp :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	dummy_read(nes)
}

// undocumented NOP $0C
instr_nop_absolute :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	dummy_read(nes)
}

// undocumented NOP $14 $34 $54 $74 $D4 $F4
instr_nop_zpx :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	dummy_read(nes)
}

// undocumented NOP $1C $3C $5C $7C $DC $FC
instr_nop_absx :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	dummy_read(nes)
}

instr_ora_value :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	accumulator |= u8(mem)

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_ora :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read
	accumulator |= read(nes, mem)

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_pha :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Other
	stack_push(nes, accumulator)
}

instr_php :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Other
	// you set B to the flags you push to the stack
	//  but you do not modify the flags themselves.
	//  this is odd...
	pushed_flags := flags
	pushed_flags += {.NoEffectB}
	stack_push(nes, transmute(u8)pushed_flags)
}

instr_pla :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Other
	dummy_read(nes)
	accum := stack_pop(nes)

	accumulator = accum

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_plp :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Other
	dummy_read(nes)
	// void PLP(arg_t& src) { flags = cpu_pop8() | D5; }
	// why are u ORing with D5...
	new_flags := stack_pop(nes)
	flags = transmute(RegisterFlags)new_flags
	flags -= {.NoEffectB}
}

instr_rol_accumulator :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .ReadModifyWrite
	temp := accumulator

	accumulator = accumulator << 1

	if (.Carry in flags) {
		accumulator += 1
	}

	set_flag(&flags, .Carry, (temp & 0x80) != 0)

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_rol :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .ReadModifyWrite
	temp := read(nes, mem)

	res := temp << 1

	if (.Carry in flags) {
		res += 1
	}

	ignore_extra_addressing_cycles = true

	// there's another write here according to cpu.txt. i'm not sure why. i'll do a dummy read here.
	dummy_read(nes)
	write(nes, mem, res)

	set_flag(&flags, .Carry, (temp & 0x80) != 0)

	set_z(&flags, res)
	set_n(&flags, res)
}

instr_ror_accumulator :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .ReadModifyWrite
	temp := accumulator

	accumulator = accumulator >> 1

	if (.Carry in flags) {
		accumulator = accumulator | 0x80
	}

	set_flag(&flags, .Carry, (temp & 0x01) == 1)

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_ror :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .ReadModifyWrite
	temp := read(nes, mem)

	res := temp >> 1

	if (.Carry in flags) {
		res = res | 0x80
	}

	ignore_extra_addressing_cycles = true
	dummy_read(nes)
	write(nes, mem, res)

	set_flag(&flags, .Carry, (temp & 0x01) == 1)

	set_z(&flags, res)
	set_n(&flags, res)
}

instr_rti :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Other
	dummy_read(nes)
	new_flags := stack_pop(nes)

	flags = transmute(RegisterFlags)new_flags

	pc_low := stack_pop(nes)
	pc_high := stack_pop(nes)

	program_counter = u16(pc_high) << 8 | u16(pc_low)
}

instr_rts :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Other
	dummy_read(nes)
	dummy_read(nes)
	pc_low := stack_pop(nes)
	pc_high := stack_pop(nes)

	program_counter = u16(pc_high) << 8 | u16(pc_low)
	program_counter += 1
}

instr_sbc_inner :: proc(using nes: ^NES, mem: u8) {
	instruction_type = .Read
	instr_adc_inner(nes, ~mem)
}

instr_sbc :: proc(using nes: ^NES, mem: u16) {
	instr_sbc_inner(nes, read(nes, mem))
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
	instruction_type = .Write
	ignore_extra_addressing_cycles = true
	instruction_type = .Write
	write(nes, mem, accumulator)
}

instr_stx :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Write
	ignore_extra_addressing_cycles = true
	instruction_type = .Write
	write(nes, mem, index_x)
}

instr_sty :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Write
	ignore_extra_addressing_cycles = true
	instruction_type = .Write
	write(nes, mem, index_y)
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

	// ASL

	instruction_type = .ReadModifyWrite
	ignore_extra_addressing_cycles = true
	val := read(nes, mem)

	temp := u16(val) << 1

	set_flag(&flags, .Carry, (val & 0x80) != 0)
	set_flag(&flags, .Zero, (temp & 0xFF) == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	write(nes, mem, u8(temp & 0x00FF))

	// ORA

	accumulator |= read(nes, mem)

	set_z(&flags, accumulator)
	set_n(&flags, accumulator)
}

instr_rla :: proc(using nes: ^NES, mem: u16) {
	// ROL
	// instr_rol(nes, mem)

	instruction_type = .ReadModifyWrite

	{
		temp := read(nes, mem)

		res := temp << 1

		if (.Carry in flags) {
			res += 1
		}

		ignore_extra_addressing_cycles = true

		// there's another write here according to cpu.txt. i'm not sure why. i'll do a dummy read here.
		write(nes, mem, res)

		set_flag(&flags, .Carry, (temp & 0x80) != 0)

		set_z(&flags, res)
		set_n(&flags, res)
	}
	
	// AND

	// A, Z, N = A&M

	{
		value := u16(read(nes, mem))

		temp: u16 = u16(nes.accumulator) & value

		set_flag(&flags, .Zero, temp == 0)
		set_flag(&flags, .Negative, (temp & 0x80) != 0)

		accumulator = u8(temp)
	}
}

instr_lse :: proc(using nes: ^NES, mem: u16) {
	// instr_lsr(nes, mem)
	// LSR


	instruction_type = .ReadModifyWrite
	ignore_extra_addressing_cycles = true
	val := read(nes, mem)

	res := val >> 1
	write(nes, mem, res)

	set_flag(&flags, .Carry, (val & 0x1) == 1)

	set_z(&flags, res)
	set_n(&flags, res)

	// EOR

	// instr_eor(nes, mem)

	accumulator = accumulator ~ read(nes, mem)
	set_flag(&flags, .Zero, accumulator == 0)
	set_n(&flags, accumulator)
}

instr_rra :: proc(using nes: ^NES, mem: u16) {
	// ROR
	instruction_type = .ReadModifyWrite
	{
		temp := read(nes, mem)

		res := temp >> 1

		if (.Carry in flags) {
			res = res | 0x80
		}

		ignore_extra_addressing_cycles = true
		write(nes, mem, res)

		set_flag(&flags, .Carry, (temp & 0x01) == 1)

		set_z(&flags, res)
		set_n(&flags, res)
	}

	// ADC
	{
		val: u16 = u16(read(nes, mem))
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
}

instr_axs :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Write
	ignore_extra_addressing_cycles = true
	write(nes, mem, accumulator & index_x)
}

instr_lax :: proc(using nes: ^NES, mem: u16) {
	instruction_type = .Read

	// LDA and LDX
	val := read(nes, mem)

	accumulator = val
	index_x = val

	// flags
	set_z(&flags, index_x)
	set_n(&flags, index_x)
}

// also known as DCP
instr_dcm :: proc(using nes: ^NES, mem: u16) {

	// DEC and CMP
	instruction_type = .ReadModifyWrite

	ignore_extra_addressing_cycles = true
	val := read(nes, mem)
	val -= 1
	dummy_read(nes)
	write(nes, mem, val)

	if accumulator >= val {
		flags += {.Carry}
	}

	set_flag(&flags, .Carry, accumulator >= val)
	set_flag(&flags, .Zero, accumulator == val)
	set_flag(&flags, .Negative, ((accumulator - val) & 0x80) != 0)
}

// Also known as ISB
instr_ins :: proc(using nes: ^NES, mem: u16) {

	// INC and SBC

	instruction_type = .ReadModifyWrite
	ignore_extra_addressing_cycles = true

	val_keep := read(nes, mem)

	{
		val: = val_keep
		val += 1
		write(nes, mem, val)
		set_z(&flags, val)
		set_n(&flags, val)
	}

	// SBC

	val_keep = read(nes, mem)

	val: u16 = u16(~val_keep)
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
	instruction_type = .Write
	fmt.eprintln("running SAX. not implemented!")
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
