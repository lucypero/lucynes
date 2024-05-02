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

instr_lda :: proc(using nes: ^NES, mem: u8) {
	accumulator = mem

	// flags
	set_flag(&flags, .Zero, accumulator == 0)
	set_flag(&flags, .Negative, (accumulator & 0x80) != 0)
}

instr_and :: proc(using nes: ^NES, mem: u8) {

	// A, Z, N = A&M

	temp: u16 = u16(nes.accumulator) & u16(mem)

	set_flag(&flags, .Zero, temp == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	accumulator = u8(temp)
}

instr_asl :: proc(using nes: ^NES, mem: ^u8) {

	// A,Z,C,N = M*2 or M,Z,C,N = M*2

	// u screwed up. sometimes instructions need to write to the address.
	// now u are just taking a number as a value, not a pointer u can write to.

	// "mem" should be the address to the thing, always.

	// if you want to read mem /write to mem, then you do nes.ram[mem]

	// well in this case, mem can be A so this just takes a pointer to a u8

	temp := mem^ << 1

	set_flag(&flags, .Carry, (mem^ & 0x80) == 1)
	set_flag(&flags, .Zero, temp == 0)
	set_flag(&flags, .Negative, (temp & 0x80) != 0)

	mem^ = temp
}

instr_adc :: proc(using nes: ^NES, mem: u8) {
	temp: u16 = u16(nes.accumulator) + u16(mem)

	if .Carry in nes.flags {
		temp += 1
	}

	set_flag(&flags, .Carry, temp > 255)
	set_flag(&flags, .Zero, (temp & 0x00FF) == 0)
	set_flag(&flags, .Negative, (temp & 0x0080) != 0)
	set_flag(
		&flags,
		.Overflow,
		((~(u16(accumulator) ~ u16(mem)) & (u16(accumulator) ~ u16(temp))) & 0x0080) != 0,
	)

	accumulator = u8(temp & 0x00FF)
}


run_instruction :: proc(using nes: ^NES) {
	// get first byte of instruction
	instr := ram[program_counter]
	program_counter += 1

	switch instr {

	// LDA

	case 0xA9:
		mem := do_addrmode_immediate(nes)
		instr_lda(nes, u8(mem))
		cycles += 2
	case 0xA5:
		fmt.println("lda zp instruction")
		mem := do_addrmode_zp(nes)
		instr_lda(nes, ram[mem])
		cycles += 3
	case 0xB5:
		mem := do_addrmode_zpx(nes)
		instr_lda(nes, ram[mem])
		cycles += 4
	case 0xAD:
		mem := do_addrmode_absolute(nes)
		instr_lda(nes, ram[mem])
		cycles += 4
	case 0xBD:
		mem, extra_cycles := do_addrmode_absolute_x(nes)
		instr_lda(nes, ram[mem])
		cycles += 4 + extra_cycles // TODO +1 if page crossed
	case 0xB9:
		mem, extra_cycles := do_addrmode_absolute_y(nes)
		instr_lda(nes, ram[mem])
		cycles += 4 + extra_cycles // TODO +1 if page crossed
	case 0xA1:
		mem := do_addrmode_ind_x(nes)
		instr_lda(nes, ram[mem])
		cycles += 6
	case 0xB1:
		mem, extra_cycles := do_addrmode_ind_y(nes)
		instr_lda(nes, ram[mem])
		cycles += 5 + extra_cycles

	// AND

	case 0x29:
		val := do_addrmode_immediate(nes)
		instr_and(nes, val)
		cycles += 2
	case 0x25:
		mem := do_addrmode_zp(nes)
		instr_and(nes, ram[mem])
		cycles += 3
	case 0x35:
		mem := do_addrmode_zpx(nes)
		instr_and(nes, ram[mem])
		cycles += 4
	case 0x2D:
		mem := do_addrmode_absolute(nes)
		instr_and(nes, ram[mem])
		cycles += 4
	case 0x3D:
		mem, extra_cycles := do_addrmode_absolute_x(nes)
		instr_and(nes, ram[mem])
		cycles += 4 + extra_cycles
	case 0x39:
		mem, extra_cycles := do_addrmode_absolute_y(nes)
		instr_and(nes, ram[mem])
		cycles += 4 + extra_cycles
	case 0x21:
		mem := do_addrmode_ind_x(nes)
		instr_and(nes, ram[mem])
		cycles += 6
	case 0x31:
		mem, extra_cycles := do_addrmode_ind_y(nes)
		instr_and(nes, ram[mem])
		cycles += 5 + extra_cycles

	// ASL

	case 0x0A:
		instr_asl(nes, &nes.accumulator)
		cycles += 2
	case 0x06:
		mem := do_addrmode_zp(nes)
		instr_asl(nes, &ram[mem])
		cycles += 5
	case 0x16:
		mem := do_addrmode_zpx(nes)
		instr_asl(nes, &ram[mem])
		cycles += 6
	case 0x0E:
		mem := do_addrmode_absolute(nes)
		instr_asl(nes, &ram[mem])
		cycles += 6
	case 0x1E:
		mem, _ := do_addrmode_absolute_x(nes)
		instr_asl(nes, &ram[mem])
		cycles += 7

	// ADC
	case 0x69:
		mem := do_addrmode_immediate(nes)
		instr_adc(nes, mem)
		cycles += 2
	case 0x65:
		mem := do_addrmode_zp(nes)
		instr_adc(nes, ram[mem])
		cycles += 3
	case 0x75:
		mem := do_addrmode_zpx(nes)
		instr_adc(nes, ram[mem])
		cycles += 4
	case 0x6D:
		mem := do_addrmode_absolute(nes)
		instr_adc(nes, ram[mem])
		cycles += 4
	case 0x7D:
		mem, extra_cycles := do_addrmode_absolute_x(nes)
		instr_adc(nes, ram[mem])
		cycles += 4 + extra_cycles
	case 0x79:
		mem, extra_cycles := do_addrmode_absolute_y(nes)
		instr_adc(nes, ram[mem])
		cycles += 4 + extra_cycles
	case 0x61:
		mem := do_addrmode_ind_x(nes)
		instr_adc(nes, ram[mem])
		cycles += 6
	case 0x71:
		mem, extra_cycles := do_addrmode_ind_y(nes)
		instr_adc(nes, ram[mem])
		cycles += 5 + extra_cycles


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
