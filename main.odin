package main

import "core:fmt"

// Emulator authors may wish to emulate the NTSC NES/Famicom CPU at 21441960 Hz ((341×262−0.5)×4×60) to ensure a synchronised/stable 60 frames per second.[2]

// Stack: The processor supports a 256 byte stack located between $0100 and $01FF.
// The processor is little endian and expects addresses to be stored in memory least significant byte first.

// flags

RegisterFlagEnum :: enum {
	Carry, // C 
	Zero, // Z
	InterruptDisable, // I
	Decimal, // D
	NoEffectB, // No CPU Effect, see the B flag
	NoEffect1, // No CPU Effect, always pushed as 1
	Overflow, // V
	Negative, // N
}

RegisterFlags :: bit_set[RegisterFlagEnum;u8]

/*
Memory layout:

Internal RAM:

$0000-$00FF: The zero page, which can be accessed with fewer bytes and cycles than other addresses
$0100–$01FF: The page containing the stack, which can be located anywhere here, but typically starts at $01FF and grows downward
$0200-$07FF: General use RAM

Rest...

TODO


*/

/*

Instructions:

to emulate an instruction, you need to know:

- function (which instruction it is)
- address mode
- how many cycles it takes

you can know all this from the first byte of the instruction.

How to run instructions:

- Read byte at PC
- With that info, u know the addressing mode and 
    the number of cycles needed to run the instruction (all in a big switch statement maybe)
- based on the addressing mode, read additional bytes you need to run the instruction
- execute the instruction
- wait, count cycles, complete

*/


Registers :: struct {
	program_counter: u16, // Program Counter Register
	stack_pointer:   u8, // Stack Pointer Register
	accumulator:     u8, // Accumulator Register
	index_x:         u8, // Index Register X
	index_y:         u8, // Index Register Y
	flags:           RegisterFlags, // Processor Status Register (Processor Flags)
}

NES :: struct {
	using registers: Registers, // CPU Registers
	ram:             [64 * 1024]u8, // 64 KB of memory
	cycles:          uint,
}

set_flag :: proc(flags: ^RegisterFlags, flag: RegisterFlagEnum, predicate: bool) {
	if predicate {
		flags^ += {flag}
	} else {
		flags^ -= {flag}
	}
}

run_program :: proc(using nes: ^NES, rom: []u8) {

	fmt.println("Running program...")

	// copy rom code to $8000
	copy(ram[0x8000:], rom)
	// equal to 
	// copy(ram[0x8000:0x8000 + len(rom)], rom)

	// set pc to $8000
	program_counter = 0x8000

	// run clocks
	for ram[program_counter] != 0x00 {
		run_instruction(nes)
	}

	fmt.println("Program terminated successfully.")
}

// reads from byte slice a u16 in little endian mode
read_u16_le :: proc(buffer: []u8, index: u16) -> u16 {
	return u16(buffer[index]) + (u16(buffer[index + 1]) << 2)
}

// reads from byte slice a u16 in big endian mode
read_u16_be :: proc(buffer: []u8, index: u16) -> u16 {
	return u16(buffer[index + 1]) + (u16(buffer[index]) << 2)
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
	set_flag(&flags, .Zero, accumulator == 0)
	set_flag(&flags, .Negative, (accumulator & 0x80) != 0)
}

// todo: code is duplicated
instr_and_value :: proc(using nes: ^NES, value: u16) {
	// A, Z, N = A&M

	temp: u16 = u16(nes.accumulator) & value

	set_flag(&flags, .Zero, temp == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	accumulator = u8(temp)
}

instr_and :: proc(using nes: ^NES, mem: u16) {

	// A, Z, N = A&M

	temp: u16 = u16(nes.accumulator) & u16(ram[mem])

	set_flag(&flags, .Zero, temp == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	accumulator = u8(temp)
}

// todo: code is duplicated
instr_asl_accum :: proc(using nes: ^NES, _mem: u16) {
	// A,Z,C,N = M*2 or M,Z,C,N = M*2

	temp := accumulator << 1

	set_flag(&flags, .Carry, (accumulator & 0x80) == 1)
	set_flag(&flags, .Zero, temp == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	accumulator = temp
}

instr_asl :: proc(using nes: ^NES, mem: u16) {

	// A,Z,C,N = M*2 or M,Z,C,N = M*2

	temp := ram[mem] << 1

	set_flag(&flags, .Carry, (ram[mem] & 0x80) == 1)
	set_flag(&flags, .Zero, temp == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	ram[mem] = temp
}

instr_adc :: proc(using nes: ^NES, mem: u16) {

	val :u16 = u16(ram[mem])


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
	if .Negative not_in flags {
		program_counter = mem
	}
}

run_instruction :: proc(using nes: ^NES) {
	// get first byte of instruction
	instr := ram[program_counter]
	program_counter += 1

	switch instr {

	// LDA

	case 0xA9:
		do_opcode(nes, .Immediate, instr_lda_value, 2)
	case 0xA5:
		do_opcode(nes, .ZeroPage, instr_lda, 3)
	case 0xB5:
		do_opcode(nes, .ZeroPageX, instr_lda, 4)
	case 0xAD:
		do_opcode(nes, .Absolute, instr_lda, 4)
	case 0xBD:
		do_opcode(nes, .AbsoluteX, instr_lda, 4)
	case 0xB9:
		do_opcode(nes, .AbsoluteY, instr_lda, 4)
	case 0xA1:
		do_opcode(nes, .IndirectX, instr_lda, 6)
	case 0xB1:
		do_opcode(nes, .IndirectY, instr_lda, 5)

	// AND

	case 0x29:
		do_opcode(nes, .Immediate, instr_and_value, 2)
	case 0x25:
		do_opcode(nes, .ZeroPage, instr_and, 3)
	case 0x35:
		do_opcode(nes, .ZeroPageX, instr_and, 4)
	case 0x2D:
		do_opcode(nes, .Absolute, instr_and, 4)
	case 0x3D:
		do_opcode(nes, .AbsoluteX, instr_and, 4)
	case 0x39:
		do_opcode(nes, .AbsoluteY, instr_and, 4)
	case 0x21:
		do_opcode(nes, .IndirectX, instr_and, 6)
	case 0x31:
		do_opcode(nes, .IndirectY, instr_and, 5)

	// ASL

	case 0x0A:
		do_opcode(nes, .Accumulator, instr_asl_accum, 2)
	case 0x06:
		do_opcode(nes, .ZeroPage, instr_asl, 5)
	case 0x16:
		do_opcode(nes, .ZeroPageX, instr_asl, 6)
	case 0x0E:
		do_opcode(nes, .Absolute, instr_asl, 6)
	case 0x1E:
		do_opcode(nes, .AbsoluteX, instr_asl, 7)

	// ADC
	case 0x69:
		do_opcode(nes, .Immediate, instr_adc, 2)
	case 0x65:
		do_opcode(nes, .ZeroPage, instr_adc, 3)
	case 0x75:
		do_opcode(nes, .ZeroPageX, instr_adc, 4)
	case 0x6D:
		do_opcode(nes, .Absolute, instr_adc, 4)
	case 0x7D:
		do_opcode(nes, .AbsoluteX, instr_adc, 4)
	case 0x79:
		do_opcode(nes, .AbsoluteY, instr_adc, 4)
	case 0x61:
		do_opcode(nes, .IndirectX, instr_adc, 6)
	case 0x71:
		do_opcode(nes, .IndirectY, instr_adc, 5)

	// BCC
	case 0x90:
		do_opcode(nes, .Relative, instr_bcc, 2)

	// BCS
	case 0xB0:
		do_opcode(nes, .Relative, instr_bcs, 2)

	// BEQ
	case 0xF0:
		do_opcode(nes, .Relative, instr_beq, 2)

	// BIT
	case 0x24:
		do_opcode(nes, .ZeroPage, instr_bit, 3)
	case 0x2C:
		do_opcode(nes, .Absolute, instr_bit, 4)

	// BMI
	case 0x30:
		do_opcode(nes, .Relative, instr_bmi, 2)

	// BNE
	case 0xD0:
		do_opcode(nes, .Relative, instr_bne, 2)

	// BPL
	case 0x10:
		do_opcode(nes, .Relative, instr_bpl, 2)

	// BRK
	case 0x00:
		do_opcode(nes, .Implicit, instr_brk, 7)

	// BVC
	case 0x50:
		do_opcode(nes, .Relative, instr_bvc, 2)

	// BVS
	case 0x70:
		do_opcode(nes, .Relative, instr_bvs, 2)

	// CLC
	case 0x18:
		do_opcode(nes, .Implicit, instr_clc, 2)

	// CLD
	case 0xD8:
		do_opcode(nes, .Implicit, instr_cld, 2)

	// CLI
	case 0x58:
		do_opcode(nes, .Implicit, instr_cli, 2)

	// CLV
	case 0xB8:
		do_opcode(nes, .Implicit, instr_clv, 2)

	// CMP
	case 0xC9:
		do_opcode(nes, .Immediate, instr_cmp_value, 2)
	case 0xC5:
		do_opcode(nes, .ZeroPage, instr_cmp, 3)
	case 0xD5:
		do_opcode(nes, .ZeroPageX, instr_cmp, 4)
	case 0xCD:
		do_opcode(nes, .Absolute, instr_cmp, 4)
	case 0xDD:
		do_opcode(nes, .AbsoluteX, instr_cmp, 4)
	case 0xD9:
		do_opcode(nes, .AbsoluteY, instr_cmp, 4)
	case 0xC1:
		do_opcode(nes, .IndirectX, instr_cmp, 6)
	case 0xD1:
		do_opcode(nes, .IndirectY, instr_cmp, 5)


	// TODO: this one is not done yet
	case 0x85:
		// STA, ZP, 2, 3
		fmt.println("STA zp instruction")
		mem := do_addrmode_zp(nes)
		cycles += 3
	}
}

main :: proc() {
	// flags_test()
	nes: NES


	// load a program and run it

	//   * = $0000
	//   LDA $60
	//   ADC $61
	//   STA $62
	//   .END

	program := [?]u8{0xA5, 0x60, 0x65, 0x61, 0x85, 0x62}

	run_program(&nes, program[:])
}

// address modes?

flags_test :: proc() {
	flags: RegisterFlags

	flags = {.Carry, .Zero, .Negative}

	fmt.printf("%v, %#b\n", flags, transmute(u8)flags)

	fmt.println(.Carry in flags)
	fmt.println(.Overflow in flags)
	flags += {.Decimal}
	fmt.println(flags)

	fmt.printf("%v, %#b\n", flags, transmute(u8)flags)

	// how to flip the bits?
	flags = ~flags
	fmt.printf("flipped: %v, %#b\n", flags, transmute(u8)flags)
}
