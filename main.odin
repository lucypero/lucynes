package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

// Emulator authors may wish to emulate the NTSC NES/Famicom CPU at 21441960 Hz ((341×262−0.5)×4×60) to ensure a synchronised/stable 60 frames per second.[2]

// Stack: The processor supports a 256 byte stack located between $0100 and $01FF.
// The processor is little endian and expects addresses to be stored in memory least significant byte first.

// flags

Mapper :: enum {
	NROM128, // 00
	NROM256, // 00 
}

RomFormat :: enum {
	NES20,
	iNES,
}

RomInfo :: struct {
	// TODO: u can group a lot of this into a bitset
	rom_loaded:                bool,
	rom_format:                RomFormat,
	prg_rom_size:              int,
	chr_rom_size:              int,
	is_horizontal_arrangement: bool, // true for horizontal, false for vertical
	contains_ram:              bool, // bit 2 in flags 6. true if it contains battery packed PRG RAM
	contains_trainer:          bool,
	alt_nametable_layout:      bool,
	mapper:                    Mapper,
}

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
	rom_info:        RomInfo,
	prg_rom:         []u8,
	chr_rom:         []u8,
	prg_ram:         []u8,

	// PPU stuff
	ppu_bus:         [16 * 1024]u8, // PPU bus (separate from cpu bus/ram)
	ppu_v:           uint, // current vram address (15 bits)
	ppu_t:           uint, // Temporary VRAM address (15 bits)
	ppu_x:           uint, // fine x scroll (3 bits)
	ppu_w:           bool, // First or second write toggle (1 bit)
	ppu_on_vblank:   bool,
	ppu_cycles:      int,
}

nmi :: proc(using nes: ^NES) {

	fmt.println("nmi triggered!")

	stack_push_u16(nes, program_counter)
	flags += {.InterruptDisable, .NoEffect1}
	flags -= {.NoEffectB}
	stack_push(nes, transmute(u8)flags)

	// read u16 memmory value at 0xFFFA
	nmi_mem: u16

	low_byte := u16(read(nes, 0xFFFA))
	high_byte := u16(read(nes, 0xFFFA + 1))

	nmi_mem = high_byte << 8 | low_byte

	fmt.printfln("setting pc to %X, from low byte %X, high byte %X", nmi_mem, low_byte, high_byte)
	program_counter = nmi_mem

	cycles += 7
}

write_ppu_register :: proc(using nes: ^NES, ppu_reg: u16, val: u8) {
	switch ppu_reg {

	// PPUCTRL
	case 0x2000:
		// writing to ppuctrl
		fmt.printfln("writing to PPUCTRL %X", val)

		// if vblank is set, and you change nmi flag from 0 to 1, trigger nmi now
		if ppu_on_vblank && val & 0x80 != 0 && ram[ppu_reg] & 0x80 == 0 {
			// trigger NMI immediately
			nmi(nes)
		}

		fmt.printfln("unsafe write to ram: %X", ppu_reg)
		ram[ppu_reg] = val


	// PPUSCROLL
	case 0x2005:
		fmt.println("writing to ppuscroll")
	//

	// PPUADDR
	case 0x2006:
		fmt.println("writing to ppuaddr")


		// writes a 16 bit VRAM address, 1 bytes at a time(games have to call this twice)

		// writes to upper byte first

		// TODO write to ppu_v based on ppu_w
		if ppu_w {
			ppu_v = (ppu_v & 0xFF00) | uint(val)
		} else {
			ppu_v = uint(val) << 8 | (ppu_v & 0x00FF)
		}

		ppu_w = !ppu_w

		fmt.printfln(
			"-- PPU interaction! call to PPUADDR!! writing: %X. ppu_v is now %X",
			val,
			ppu_v,
		)
		return

	//PPUDATA
	case 0x2007:
		// this is what you use to read/write to PPU memory (VRAM)
		// this is what games use to fill nametables, change palettes, and more.

		// it will write to the set 16 bit VRAM address set by PPUADDR (u need to store this address somewhere)
		fmt.printfln(
			"-- PPU interaction! call to PPUDATA!! writing: %X to PPU ADDRESS: %X",
			val,
			ppu_v,
		)

		ppu_bus[ppu_v] = val

		// (after writing, increment)

		// go down or go across?
		goDown: bool = ram[0x2000] & 0x04 != 0

		if goDown {
			ppu_v += 32
		} else {
			ppu_v += 1
		}

		return
	}

}

read_ppu_register :: proc(using nes: ^NES, ppu_reg: u16) -> u8 {
	switch ppu_reg {

	// PPUCTRL
	case 0x2000:
		// return garbage if they try to read this. "open bus"
		// https://forums.nesdev.org/viewtopic.php?t=6426

		// fmt.eprintfln("should not read to ppuctrl. it's write only")
		return ram[ppu_reg]

	// PPUMASK
	case 0x2001:
		// fmt.eprintfln("should not read to ppumask. it's write only")
		return ram[ppu_reg]

	// PPUSTATUS
	case 0x2002:
		//TODO

		// return v blank as 1, rest 0

		// clear bit 7

		// clear address latch
		ppu_status: u8

		if ppu_on_vblank {
			ppu_status |= 0x80
		}

		ppu_on_vblank = false

		// fmt.printfln("reading ppu status. clearing latch")
		ppu_w = false
		return ppu_status

	// PPUDATA
	case 0x2007:
		// fmt.printfln("reading PPUDATA")

		val := ppu_bus[ppu_v]

		goDown: bool = ram[0x2000] & 0x04 != 0

		if goDown {
			ppu_v += 32
		} else {
			ppu_v += 1
		}

		return val

	// OAMADDR
	case 0x2003:
		// fmt.eprintfln("should not read to oamaddr. it's write only")
		return ram[ppu_reg]

	// OAMDATA
	case 0x2004:
		// fmt.printfln("reading oamdata")
		return ram[ppu_reg]

	case:
		return ram[ppu_reg]
	}
}

// cpu bus read
read :: proc(using nes: ^NES, addr: u16) -> u8 {

	switch addr {

	// PPU registers
	case 0x2000 ..= 0x3FFF:
		ppu_reg := get_mirrored(int(addr), 0x2000, 0x2007)
		// fmt.printfln("reading to a ppu register %X", ppu_reg)
		return read_ppu_register(nes, u16(ppu_reg))
	}

	// CPU memory

	if !rom_info.rom_loaded {
		return ram[addr]
	}

	// ROM mapped memory

	switch rom_info.mapper {
	case .NROM128:
		switch addr {
		case 0x8000 ..= 0xBFFF:
			return prg_rom[addr - 0x8000]
		case 0xC000 ..= 0xFFFF:
			return prg_rom[addr - 0xC000]
		}
	case .NROM256:
		switch addr {
		case 0x8000 ..= 0xFFFF:
			return prg_rom[addr - 0x8000]
		}
	}

	if rom_info.contains_ram {
		switch addr {
		case 0x6000 ..= 0x7FFF:
			return prg_ram[addr - 0x6000]
		}
	}

	// CPU $6000-$7FFF: Family Basic only: PRG RAM, mirrored as necessary to fill entire 8 KiB window, write protectable with an external switch
	// CPU $8000-$BFFF: First 16 KB of ROM.
	// CPU $C000-$FFFF: Last 16 KB of ROM (NROM-256) or mirror of $8000-$BFFF (NROM-128).

	return ram[addr]
}

write :: proc(using nes: ^NES, addr: u16, val: u8) {

	wrote_to_rom := false

	defer {
		if wrote_to_rom {
			fmt.eprintfln("tried to write to read only memory!! that is bad i think: %v", addr)
		}
	}

	switch addr {
	// PPU registers
	case 0x2000 ..= 0x3FFF:
		ppu_reg := get_mirrored(int(addr), 0x2000, 0x2007)
		fmt.printfln("writing to a ppu register %X", ppu_reg)
		write_ppu_register(nes, u16(ppu_reg), val)
		return
	}

	//OAMDMA
	if addr == 0x4014 {
		// todo
		fmt.printfln("writing to OAMDMA")
		fmt.printfln("unsafe write to ram: %X", addr)
		ram[addr] = val
	}

	if !rom_info.rom_loaded {
		fmt.printfln("unsafe write to ram: %X", addr)
		ram[addr] = val
		return
	}

	switch rom_info.mapper {
	case .NROM128:
		switch addr {
		case 0x8000 ..= 0xBFFF:
			wrote_to_rom = true
			// prg_rom[addr - 0x8000] = val
			return
		case 0xC000 ..= 0xFFFF:
			wrote_to_rom = true
			// prg_rom[addr - 0xC000] = val
			return
		}
	case .NROM256:
		switch addr {
		case 0x8000 ..= 0xFFFF:
			wrote_to_rom = true
			// prg_rom[addr - 0x8000] = val
			return
		}
	}

	if rom_info.contains_ram {
		switch addr {
		case 0x6000 ..= 0x7FFF:
			// wrote to prg ram! it's ok i think
			fmt.println("wrote to prg ram! probably ok")
			prg_ram[addr - 0x6000] = val
			return
		}
	}

	// if it didn't return by now, just write to addr.
	ram[addr] = val
}

set_flag :: proc(flags: ^RegisterFlags, flag: RegisterFlagEnum, predicate: bool) {
	if predicate {
		flags^ += {flag}
	} else {
		flags^ -= {flag}
	}
}

parse_log_file :: proc(log_file: string) -> (res: [dynamic]Registers, ok: bool) {

	ok = false

	log_bytes := os.read_entire_file(log_file) or_return

	log_string := string(log_bytes)

	for line in strings.split_lines_iterator(&log_string) {
		reg: Registers
		reg.program_counter = u16(strconv.parse_int(line[:4], 16) or_return)
		reg.accumulator = u8(strconv.parse_int(line[50:][:2], 16) or_return)
		reg.index_x = u8(strconv.parse_int(line[55:][:2], 16) or_return)
		reg.index_y = u8(strconv.parse_int(line[60:][:2], 16) or_return)
		reg.flags = transmute(RegisterFlags)u8(strconv.parse_int(line[65:][:2], 16) or_return)
		reg.stack_pointer = u8(strconv.parse_int(line[71:][:2], 16) or_return)
		append(&res, reg)
	}

	ok = true

	return
}

// register_logs: [dynamic]Registers

run_nestest :: proc(using nes: ^NES, program_file: string, log_file: string) -> bool {
	// processing log file

	register_logs, ok := parse_log_file(log_file)

	if !ok {
		fmt.eprintln("could not parse log file")
		return false
	}

	nes.registers = register_logs[0]

	test_rom, ok_2 := os.read_entire_file(program_file)

	if !ok_2 {
		fmt.eprintln("could not read program file")
		return false
	}

	// read it from 0x10 because that's how the ROM format works.
	copy(ram[0x8000:], test_rom[0x10:])
	copy(ram[0xC000:], test_rom[0x10:])

	program_counter = 0xC000
	stack_pointer = 0xFD
	flags = transmute(RegisterFlags)u8(0x24)

	instructions_ran := 0

	for read(nes, program_counter) != 0x00 {

		state_before_instr := registers

		// fmt.printfln("running line %v", instructions_ran + 1)
		// print_cpu_state(state_before_instr)

		run_instruction(nes)
		instructions_ran += 1

		if instructions_ran >= len(register_logs) {
			return true
		}

		if res := compare_reg(nes.registers, register_logs[instructions_ran]); res != 0 {
			// test fail

			logs_reg := register_logs[instructions_ran]

			fmt.printfln("------------------")

			fmt.printfln("Test failed after instruction: %v (starts at 1)", instructions_ran)

			switch res {
			case 1:
				fmt.printfln("PC: %X, TEST PC: %X", program_counter, logs_reg.program_counter)
			case 2:
				fmt.printfln("A: %X, TEST A: %X", accumulator, logs_reg.accumulator)
			case 3:
				fmt.printfln("X: %X, TEST X: %X", index_x, logs_reg.index_x)
			case 4:
				fmt.printfln("Y: %X, TEST Y: %X", index_y, logs_reg.index_y)
			case 5:
				fmt.printfln("P: %X, TEST P: %X", flags, logs_reg.flags)
			case 6:
				fmt.printfln("SP: %X, TEST SP: %X", stack_pointer, logs_reg.stack_pointer)
			}

			fmt.println("state before instr:")
			print_cpu_state(state_before_instr)


			fmt.println("state after instruction:")
			print_cpu_state(registers)
			return false
		}
	}

	return true
}

compare_reg :: proc(current_register: Registers, log_register: Registers) -> int {

	if current_register.program_counter != log_register.program_counter {
		return 1
	}

	if current_register.accumulator != log_register.accumulator {
		return 2
	}

	if current_register.index_x != log_register.index_x {
		return 3
	}

	if current_register.index_y != log_register.index_y {
		return 4
	}

	if current_register.flags != log_register.flags {
		return 5
	}

	if current_register.stack_pointer != log_register.stack_pointer {
		return 6
	}


	return 0
}

print_cpu_state :: proc(regs: Registers) {
	fmt.printfln(
		"PC: %X A: %X X: %X Y: %X P: %X SP: %X",
		regs.program_counter,
		regs.accumulator,
		regs.index_x,
		regs.index_y,
		transmute(u8)regs.flags,
		regs.stack_pointer,
	)
}

run_program :: proc(using nes: ^NES, rom: []u8) {

	fmt.println("Running program...")

	copy(ram[0x8000:], rom)
	copy(ram[0xC000:], rom)

	program_counter = 0xC000

	for read(nes, program_counter) != 0x00 {
		run_instruction(nes)
	}

	fmt.println("Program terminated successfully.")
}

// reads from byte slice a u16 in little endian mode
read_u16_le :: proc(nes: ^NES, addr: u16) -> u16 {
	low_b := read(nes, addr)
	high_b := read(nes, addr + 1)
	return u16(high_b) << 8 | u16(low_b)
}

run_instruction :: proc(using nes: ^NES) {
	// get first byte of instruction
	instr := read(nes, program_counter)
	// fmt.printfln("PC: %X OPCODE: %X", program_counter, instr)
	program_counter += 1
	// fmt.printfln("running op %X", instr)
	switch instr {

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
		do_opcode(nes, .Immediate, instr_adc_value, 2)
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

	// CPX

	case 0xE0:
		do_opcode(nes, .Immediate, instr_cpx_value, 2)
	case 0xE4:
		do_opcode(nes, .ZeroPage, instr_cpx, 3)
	case 0xEC:
		do_opcode(nes, .Absolute, instr_cpx, 4)

	// CPY

	case 0xC0:
		do_opcode(nes, .Immediate, instr_cpy_value, 2)
	case 0xC4:
		do_opcode(nes, .ZeroPage, instr_cpy, 3)
	case 0xCC:
		do_opcode(nes, .Absolute, instr_cpy, 4)


	// DEC
	case 0xC6:
		do_opcode(nes, .ZeroPage, instr_dec, 5)
	case 0xD6:
		do_opcode(nes, .ZeroPageX, instr_dec, 6)
	case 0xCE:
		do_opcode(nes, .Absolute, instr_dec, 6)
	case 0xDE:
		do_opcode(nes, .AbsoluteX, instr_dec, 7)

	// DEX

	case 0xCA:
		do_opcode(nes, .Implicit, instr_dex, 2)


	// DEY

	case 0x88:
		do_opcode(nes, .Implicit, instr_dey, 2)

	// EOR

	case 0x49:
		do_opcode(nes, .Immediate, instr_eor_value, 2)
	case 0x45:
		do_opcode(nes, .ZeroPage, instr_eor, 3)
	case 0x55:
		do_opcode(nes, .ZeroPageX, instr_eor, 4)
	case 0x4D:
		do_opcode(nes, .Absolute, instr_eor, 4)
	case 0x5D:
		do_opcode(nes, .AbsoluteX, instr_eor, 4)
	case 0x59:
		do_opcode(nes, .AbsoluteY, instr_eor, 4)
	case 0x41:
		do_opcode(nes, .IndirectX, instr_eor, 6)
	case 0x51:
		do_opcode(nes, .IndirectY, instr_eor, 5)

	// INC

	case 0xE6:
		do_opcode(nes, .ZeroPage, instr_inc, 5)
	case 0xF6:
		do_opcode(nes, .ZeroPageX, instr_inc, 6)
	case 0xEE:
		do_opcode(nes, .Absolute, instr_inc, 6)
	case 0xFE:
		do_opcode(nes, .AbsoluteX, instr_inc, 7)

	// INX

	case 0xE8:
		do_opcode(nes, .Implicit, instr_inx, 2)

	// INY

	case 0xC8:
		do_opcode(nes, .Implicit, instr_iny, 2)

	// JMP
	case 0x4C:
		do_opcode(nes, .Absolute, instr_jmp, 3)
	case 0x6C:
		do_opcode(nes, .Indirect, instr_jmp, 5)


	// JSR

	case 0x20:
		do_opcode(nes, .Absolute, instr_jsr, 6)


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


	// LDX

	case 0xA2:
		do_opcode(nes, .Immediate, instr_ldx_value, 2)
	case 0xA6:
		do_opcode(nes, .ZeroPage, instr_ldx, 3)
	case 0xB6:
		do_opcode(nes, .ZeroPageY, instr_ldx, 4)
	case 0xAE:
		do_opcode(nes, .Absolute, instr_ldx, 4)
	case 0xBE:
		do_opcode(nes, .AbsoluteY, instr_ldx, 4)

	// LDY

	case 0xA0:
		do_opcode(nes, .Immediate, instr_ldy_value, 2)
	case 0xA4:
		do_opcode(nes, .ZeroPage, instr_ldy, 3)
	case 0xB4:
		do_opcode(nes, .ZeroPageX, instr_ldy, 4)
	case 0xAC:
		do_opcode(nes, .Absolute, instr_ldy, 4)
	case 0xBC:
		do_opcode(nes, .AbsoluteX, instr_ldy, 4)


	// LSR

	case 0x4A:
		do_opcode(nes, .Accumulator, instr_lsr_accumulator, 2)
	case 0x46:
		do_opcode(nes, .ZeroPage, instr_lsr, 5)
	case 0x56:
		do_opcode(nes, .ZeroPageX, instr_lsr, 6)
	case 0x4E:
		do_opcode(nes, .Absolute, instr_lsr, 6)
	case 0x5E:
		do_opcode(nes, .AbsoluteX, instr_lsr, 7)


	// NOP

	case 0xEA:
		do_opcode(nes, .Implicit, instr_nop, 2)

	// ORA

	case 0x09:
		do_opcode(nes, .Immediate, instr_ora_value, 2)
	case 0x05:
		do_opcode(nes, .ZeroPage, instr_ora, 3)
	case 0x15:
		do_opcode(nes, .ZeroPageX, instr_ora, 4)
	case 0x0D:
		do_opcode(nes, .Absolute, instr_ora, 4)
	case 0x1D:
		do_opcode(nes, .AbsoluteX, instr_ora, 4)
	case 0x19:
		do_opcode(nes, .AbsoluteY, instr_ora, 4)
	case 0x01:
		do_opcode(nes, .IndirectX, instr_ora, 6)
	case 0x11:
		do_opcode(nes, .IndirectY, instr_ora, 5)

	// PHA

	case 0x48:
		do_opcode(nes, .Implicit, instr_pha, 3)

	// PHP

	case 0x08:
		do_opcode(nes, .Implicit, instr_php, 3)


	// PLA

	case 0x68:
		do_opcode(nes, .Implicit, instr_pla, 4)

	// PLP
	case 0x28:
		do_opcode(nes, .Implicit, instr_plp, 4)

	// ROL

	case 0x2A:
		do_opcode(nes, .Accumulator, instr_rol_accumulator, 4)
	case 0x26:
		do_opcode(nes, .ZeroPage, instr_rol, 5)
	case 0x36:
		do_opcode(nes, .ZeroPageX, instr_rol, 6)
	case 0x2E:
		do_opcode(nes, .Absolute, instr_rol, 6)
	case 0x3E:
		do_opcode(nes, .AbsoluteX, instr_rol, 7)

	// ROR

	case 0x6A:
		do_opcode(nes, .Accumulator, instr_ror_accumulator, 2)
	case 0x66:
		do_opcode(nes, .ZeroPage, instr_ror, 5)
	case 0x76:
		do_opcode(nes, .ZeroPageX, instr_ror, 6)
	case 0x6E:
		do_opcode(nes, .Absolute, instr_ror, 6)
	case 0x7E:
		do_opcode(nes, .AbsoluteX, instr_ror, 7)


	// RTI

	case 0x40:
		do_opcode(nes, .Implicit, instr_rti, 6)

	// RTS

	case 0x60:
		do_opcode(nes, .Implicit, instr_rts, 6)

	// SBC

	case 0xE9:
		do_opcode(nes, .Immediate, instr_sbc_value, 2)
	case 0xE5:
		do_opcode(nes, .ZeroPage, instr_sbc, 3)
	case 0xF5:
		do_opcode(nes, .ZeroPageX, instr_sbc, 4)
	case 0xED:
		do_opcode(nes, .Absolute, instr_sbc, 4)
	case 0xFD:
		do_opcode(nes, .AbsoluteX, instr_sbc, 4)
	case 0xF9:
		do_opcode(nes, .AbsoluteY, instr_sbc, 4)
	case 0xE1:
		do_opcode(nes, .IndirectX, instr_sbc, 6)
	case 0xF1:
		do_opcode(nes, .IndirectY, instr_sbc, 5)


	// SEC

	case 0x38:
		do_opcode(nes, .Implicit, instr_sec, 2)

	// SED

	case 0xF8:
		do_opcode(nes, .Implicit, instr_sed, 2)

	// SEI

	case 0x78:
		do_opcode(nes, .Implicit, instr_sei, 2)

	// STA

	case 0x85:
		do_opcode(nes, .ZeroPage, instr_sta, 3)
	case 0x95:
		do_opcode(nes, .ZeroPageX, instr_sta, 4)
	case 0x8D:
		do_opcode(nes, .Absolute, instr_sta, 4)
	case 0x9D:
		do_opcode(nes, .AbsoluteX, instr_sta, 5)
	case 0x99:
		do_opcode(nes, .AbsoluteY, instr_sta, 5)
	case 0x81:
		do_opcode(nes, .IndirectX, instr_sta, 6)
	case 0x91:
		do_opcode(nes, .IndirectY, instr_sta, 6)

	// STX

	case 0x86:
		do_opcode(nes, .ZeroPage, instr_stx, 3)
	case 0x96:
		do_opcode(nes, .ZeroPageY, instr_stx, 4)
	case 0x8E:
		do_opcode(nes, .Absolute, instr_stx, 4)

	// STY

	case 0x84:
		do_opcode(nes, .ZeroPage, instr_sty, 3)
	case 0x94:
		do_opcode(nes, .ZeroPageX, instr_sty, 4)
	case 0x8C:
		do_opcode(nes, .Absolute, instr_sty, 4)


	// TAX

	case 0xAA:
		do_opcode(nes, .Implicit, instr_tax, 2)

	// TAY
	case 0xA8:
		do_opcode(nes, .Implicit, instr_tay, 2)

	// TSX
	case 0xBA:
		do_opcode(nes, .Implicit, instr_tsx, 2)

	// TXA
	case 0x8A:
		do_opcode(nes, .Implicit, instr_txa, 2)

	// TXS
	case 0x9A:
		do_opcode(nes, .Implicit, instr_txs, 2)

	// TYA
	case 0x98:
		do_opcode(nes, .Implicit, instr_tya, 2)


	/// Unofficial opcodes

	/*

	// reference for addr mode and the asterisk

	abcd        // absolute
	abcd,X      // absolute x
	abcd,Y      // absolute y
	ab          // ZP
	ab,X        // ZP x
	(ab,X)      // indexed indirect, indirect x
	(ab),Y      // indirect indexed, indirect y
	// * means +1 cycle if page crossed

	*/

	// ASO (ASL + ORA)
	case 0x0F:
		do_opcode(nes, .Absolute, instr_aso, 6)
	case 0x1F:
		do_opcode(nes, .AbsoluteX, instr_aso, 7)
	case 0x1B:
		do_opcode(nes, .AbsoluteY, instr_aso, 7)
	case 0x07:
		do_opcode(nes, .ZeroPage, instr_aso, 5)
	case 0x17:
		do_opcode(nes, .ZeroPageX, instr_aso, 6)
	case 0x03:
		do_opcode(nes, .IndirectX, instr_aso, 8)
	case 0x13:
		do_opcode(nes, .IndirectY, instr_aso, 8)

	// RLA

	case 0x2F:
		do_opcode(nes, .Absolute, instr_rla, 6)
	case 0x3F:
		do_opcode(nes, .AbsoluteX, instr_rla, 7)
	case 0x3B:
		do_opcode(nes, .AbsoluteY, instr_rla, 7)
	case 0x27:
		do_opcode(nes, .ZeroPage, instr_rla, 5)
	case 0x37:
		do_opcode(nes, .ZeroPageX, instr_rla, 6)
	case 0x23:
		do_opcode(nes, .IndirectX, instr_rla, 8)
	case 0x33:
		do_opcode(nes, .IndirectY, instr_rla, 8)

	// LSE
	case 0x4F:
		do_opcode(nes, .Absolute, instr_lse, 6)
	case 0x5F:
		do_opcode(nes, .AbsoluteX, instr_lse, 7)
	case 0x5B:
		do_opcode(nes, .AbsoluteY, instr_lse, 7)
	case 0x47:
		do_opcode(nes, .ZeroPage, instr_lse, 5)
	case 0x57:
		do_opcode(nes, .ZeroPageX, instr_lse, 6)
	case 0x43:
		do_opcode(nes, .IndirectX, instr_lse, 8)
	case 0x53:
		do_opcode(nes, .IndirectY, instr_lse, 8)

	// RRA

	case 0x6F:
		do_opcode(nes, .Absolute, instr_rra, 6)
	case 0x7F:
		do_opcode(nes, .AbsoluteX, instr_rra, 7)
	case 0x7B:
		do_opcode(nes, .AbsoluteY, instr_rra, 7)
	case 0x67:
		do_opcode(nes, .ZeroPage, instr_rra, 5)
	case 0x77:
		do_opcode(nes, .ZeroPageX, instr_rra, 6)
	case 0x63:
		do_opcode(nes, .IndirectX, instr_rra, 8)
	case 0x73:
		do_opcode(nes, .IndirectY, instr_rra, 8)

	// AXS

	case 0x8F:
		do_opcode(nes, .Absolute, instr_axs, 4)
	case 0x87:
		do_opcode(nes, .ZeroPage, instr_axs, 3)
	case 0x97:
		do_opcode(nes, .ZeroPageY, instr_axs, 4)
	case 0x83:
		do_opcode(nes, .IndirectX, instr_axs, 6)


	// LAX

	case 0xAF:
		do_opcode(nes, .Absolute, instr_lax, 4)
	case 0xBF:
		do_opcode(nes, .AbsoluteY, instr_lax, 4)
	case 0xA7:
		do_opcode(nes, .ZeroPage, instr_lax, 3)
	case 0xB7:
		do_opcode(nes, .ZeroPageY, instr_lax, 4)
	case 0xA3:
		do_opcode(nes, .IndirectX, instr_lax, 6)
	case 0xB3:
		do_opcode(nes, .IndirectY, instr_lax, 5)

	// DCM

	case 0xCF:
		do_opcode(nes, .Absolute, instr_dcm, 6)
	case 0xDF:
		do_opcode(nes, .AbsoluteX, instr_dcm, 7)
	case 0xDB:
		do_opcode(nes, .AbsoluteY, instr_dcm, 7)
	case 0xC7:
		do_opcode(nes, .ZeroPage, instr_dcm, 5)
	case 0xD7:
		do_opcode(nes, .ZeroPageX, instr_dcm, 6)
	case 0xC3:
		do_opcode(nes, .IndirectX, instr_dcm, 8)
	case 0xD3:
		do_opcode(nes, .IndirectY, instr_dcm, 8)

	// INS

	case 0xEF:
		do_opcode(nes, .Absolute, instr_ins, 6)
	case 0xFF:
		do_opcode(nes, .AbsoluteX, instr_ins, 7)
	case 0xFB:
		do_opcode(nes, .AbsoluteY, instr_ins, 7)
	case 0xE7:
		do_opcode(nes, .ZeroPage, instr_ins, 5)
	case 0xF7:
		do_opcode(nes, .ZeroPageX, instr_ins, 6)
	case 0xE3:
		do_opcode(nes, .IndirectX, instr_ins, 8)
	case 0xF3:
		do_opcode(nes, .IndirectY, instr_ins, 8)

	// ALR

	case 0x4B:
		do_opcode(nes, .Immediate, instr_alr, 2)

	// ARR

	case 0x6B:
		do_opcode(nes, .Immediate, instr_arr, 2)

	// XAA

	case 0x8B:
		do_opcode(nes, .Immediate, instr_xaa, 2)

	// OAL

	case 0xAB:
		do_opcode(nes, .Immediate, instr_oal, 2)

	// SAX
	case 0xCB:
		do_opcode(nes, .Immediate, instr_sax, 2)

	// NOP

	case 0x1A:
		fallthrough
	case 0x3A:
		fallthrough
	case 0x5A:
		fallthrough
	case 0x7A:
		fallthrough
	case 0xDA:
		fallthrough
	case 0xFA:
		do_opcode(nes, .Implicit, instr_nop, 2)

	case 0x80:
		fallthrough
	case 0x82:
		fallthrough
	case 0x89:
		fallthrough
	case 0xC2:
		fallthrough
	case 0xE2:
		do_opcode(nes, .Immediate, instr_nop, 2)

	case 0x04:
		fallthrough
	case 0x44:
		fallthrough
	case 0x64:
		do_opcode(nes, .ZeroPage, instr_nop, 3)

	case 0x14:
		fallthrough
	case 0x34:
		fallthrough
	case 0x54:
		fallthrough
	case 0x74:
		fallthrough
	case 0xD4:
		fallthrough
	case 0xF4:
		do_opcode(nes, .ZeroPageX, instr_nop, 4)

	case 0x0C:
		do_opcode(nes, .Absolute, instr_nop, 4)

	case 0x1C:
		fallthrough
	case 0x3C:
		fallthrough
	case 0x5C:
		fallthrough
	case 0x7C:
		fallthrough
	case 0xDC:
		fallthrough
	case 0xFC:
		do_opcode(nes, .AbsoluteX, instr_nop, 4)

	/// The really weird undocumented opcodes

	// HLT

	case 0x02:
		fallthrough
	case 0x12:
		fallthrough
	case 0x22:
		fallthrough
	case 0x32:
		fallthrough
	case 0x42:
		fallthrough
	case 0x52:
		fallthrough
	case 0x62:
		fallthrough
	case 0x72:
		fallthrough
	case 0x92:
		fallthrough
	case 0xB2:
		fallthrough
	case 0xD2:
		fallthrough
	case 0xF2:
		do_opcode(nes, .Implicit, instr_hlt, 1)

	// TAS

	case 0x9B:
		do_opcode(nes, .AbsoluteY, instr_tas, 5)

	// SAY

	case 0x9C:
		do_opcode(nes, .AbsoluteX, instr_say, 5)

	// XAS

	case 0x9E:
		do_opcode(nes, .AbsoluteY, instr_xas, 5)

	// AXA

	case 0x9F:
		do_opcode(nes, .AbsoluteY, instr_axa, 5)
	case 0x93:
		do_opcode(nes, .IndirectY, instr_axa, 6)

	// ANC
	case 0x2B:
		fallthrough
	case 0x0B:
		do_opcode(nes, .Immediate, instr_anc, 2)


	// LAS
	case 0xBB:
		do_opcode(nes, .IndirectY, instr_las, 4)

	// OPCODE EB
	case 0xEB:
		do_opcode(nes, .Immediate, instr_sbc_value, 2)

	case:
		fmt.eprintfln("opcode not covered!!! warning!: %X", instr)

	}

	flags += {.NoEffect1}
}


main :: proc() {

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	_main()

	if len(track.allocation_map) > 0 {
		fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
		for _, entry in track.allocation_map {
			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		}
	}
	if len(track.bad_free_array) > 0 {
		fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
		for entry in track.bad_free_array {
			fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
		}
	}
	mem.tracking_allocator_destroy(&track)
}

_main :: proc() {
	// flags_test()
	// strong_type_test()
	// casting_test()

	// print_patterntable(nes)
	// mirror_test()
	// nes_test_without_render()
	// union_test()
	raylib_test()
}

union_test :: proc() {

	// TODO: do this for storing things like registers

	ppu_ctrl: struct #raw_union {
		// VPHB SINN
		using flags: bit_field u8 {
			n: u8 | 2,
			i: u8 | 1,
			s: u8 | 1,
			b: u8 | 1,
			h: u8 | 1,
			p: u8 | 1,
			v: u8 | 1,
		},
		reg:         u8,
	}

	ppu_ctrl.v = 1
	ppu_ctrl.b = 1
	ppu_ctrl.reg = 0x20

	fmt.printfln("%b", transmute(u8)ppu_ctrl)

}

nes_test_without_render :: proc() {
	run_nestest_test()

	nes: NES
	res := load_rom_from_file(&nes, "roms/DonkeyKong.nes")
	// res := load_rom_from_file(&nes, "nestest/nestest.nes")

	if !res {
		return
	}

	run_nes(&nes)
}


// returns true if it hit a vblank
ppu_tick :: proc(using nes: ^NES) -> bool {

	// 262 scanlines

	hit_vblank := false

	scanline := ppu_cycles / 341

	// pretend that u do some scanlines here
	// and set vblank as appropriate
	// and call nmi when appropriate

	// Vertical blanking lines (241-260)
	// The VBlank flag of the PPU is set at tick 1 (the second tick) of scanline 241, where the VBlank NMI also occurs. The PPU makes no memory accesses during these scanlines, so PPU memory can be freely accessed by the program. 


	// cycle 0
	switch scanline {
	case 0:
	// ?

	case 1 ..= 240:
	// ???
	// visible scanlines
	case 241:
		// setting vblank and nmi
		if ppu_cycles % 341 == 1 {
			ppu_on_vblank = true
			hit_vblank = true
			if ram[0x2000] & 0x80 != 0 {
				nmi(nes)
			}
		}
	case 261:
		if ppu_cycles % 341 == 1 {
			ppu_on_vblank = false
		}

	case:
	// vblank scanlines
	}

	ppu_cycles += 1

	if ppu_cycles > 341 * 262 {
		ppu_cycles = 0
	}

	return hit_vblank
}

run_nes :: proc(using nes: ^NES) {

	// initializing nes

	// do this in a reset too
	low_byte := u16(read(nes, 0xFFFC))
	high_byte := u16(read(nes, 0xFFFC + 1))
	program_counter = high_byte << 8 | low_byte

	stack_pointer = 0xFD
	flags = transmute(RegisterFlags)u8(0x24)

	// running instructions forever
	for true {
		// main NES loop
		// catchup method
		past_cycles := cycles
		run_instruction(nes)
		cpu_cycles_dt := cycles - past_cycles

		for i in 0 ..< cpu_cycles_dt * 3 {
			ppu_tick(nes)
		}
	}
}

tick_nes_till_vblank :: proc(using nes: ^NES) {

	vblank_hit := false

	// running instructions forever
	for true {
		// main NES loop
		// catchup method
		past_cycles := cycles
		run_instruction(nes)
		cpu_cycles_dt := cycles - past_cycles

		for i in 0 ..< cpu_cycles_dt * 3 {
			if ppu_tick(nes) == true {
				vblank_hit = true
			}
		}

		if vblank_hit {
			return
		}
	}
}

nes_init :: proc(using nes: ^NES) {
	low_byte := u16(read(nes, 0xFFFC))
	high_byte := u16(read(nes, 0xFFFC + 1))
	program_counter = high_byte << 8 | low_byte

	stack_pointer = 0xFD
	flags = transmute(RegisterFlags)u8(0x24)
}

print_patterntable :: proc(nes: NES) {

	// pattern tables:
	// 1: $0000 - $0FFF
	// 2: $1000 - $1FFF

	// each tile is 16 bytes made of 2 bit planes
	// tile is 8x8 pixels (pixels being 2 bits long)

	// pattern table is divided into two 256 tile sections (left and right pattern tables)


	// it is stored tiled by tile

	// how each tile is stored:

	// bit plane 0 - then - bitplane 1


	// tiles


	// looping tile
	for i in 0 ..< 256 {

		tile: [8 * 8]int // pixels of tiles (contains [0-3])

		// first bit plane
		for t in 0 ..< 16 {

			row := nes.chr_rom[(i * 16) + t]

			// looping row of pixels
			for p in 0 ..< 8 {
				is_on := (row >> uint(p)) & 0b00000001

				if is_on != 0 {

					// if we're on first bit plane, add one
					if (t < 8) {
						tile[(t * 8) + p] += 1
					} else {
						// if we're on second bit plane, add two
						tile[((t - 8) * 8) + p] += 2
					}
				}
			}
		}


		// print tile

		for p, p_i in tile {
			fmt.printf("%v", p)

			if (p_i % 8) == 7 {
				fmt.printf("\n")
			}
		}

		fmt.printf("\n")
	}
}

get_mirrored :: proc(val, from, to: int) -> int {
	range := to - from + 1
	return ((val - from) % range) + from
}

mirror_test :: proc() {

	// PPU I/O registers at $2000-$2007 are mirrored at $2008-$200F, $2010-$2017, $2018-$201F, and so forth, all the way up to $3FF8-$3FFF.
	// For example, a write to $3456 is the same as a write to $2006. 

	assert(get_mirrored(0x3456, 0x2000, 0x2007) == 0x2006) // returns $2006

}

load_rom_from_file :: proc(nes: ^NES, filename: string) -> bool {

	rom_info: RomInfo

	test_rom, ok := os.read_entire_file(filename)

	if !ok {
		fmt.eprintln("could not read rom file")
		return false
	}

	defer {
		delete(test_rom)
	}

	rom_string := string(test_rom)

	nes_str := rom_string[0:3]

	// checking if it's a nes rom

	if nes_str != "NES" {
		fmt.eprintfln("(filename: %v) this is not a nes rom file.", filename)
		return false
	}

	// checking if it's nes 2.0 or ines

	if (rom_string[7] & 0x0C) == 0x08 {
		rom_info.rom_format = .NES20
	} else {
		rom_info.rom_format = .iNES
	}

	// size of prg ROM

	// PRG ROM data (16384 * x bytes) (but later on it just says 16kb units)
	// CHR ROM data, if present (8192 * y bytes) (but later on it just says 8kb units)

	fmt.printfln("byte 4 in rom string: %X", rom_string[4])

	rom_info.prg_rom_size = int(rom_string[4]) * 16384
	rom_info.chr_rom_size = int(rom_string[5]) * 8192

	fmt.printfln("prg rom size: %v bytes", rom_info.prg_rom_size)
	fmt.printfln("chr rom size: %v bytes", rom_info.chr_rom_size)

	// Flags 6

	flags_6 := rom_string[6]

	if flags_6 & 0x01 != 0 {
		rom_info.is_horizontal_arrangement = true
	} else {
		rom_info.is_horizontal_arrangement = false
	}

	if flags_6 & 0x02 != 0 {
		rom_info.contains_ram = true
	} else {
		rom_info.contains_ram = false
	}

	if flags_6 & 0x04 != 0 {
		rom_info.contains_trainer = true
	} else {
		rom_info.contains_trainer = false
	}

	if flags_6 & 0x08 != 0 {
		rom_info.alt_nametable_layout = true
	} else {
		rom_info.alt_nametable_layout = false
	}

	mapper_lower := (flags_6 & 0xF0) >> 4

	// flags 7

	flags_7 := rom_string[7]

	mapper_higher := (flags_7 & 0xF0) >> 4

	mapper_number := mapper_higher << 4 | mapper_lower

	switch mapper_number {
	case 0:
		if rom_string[4] == 1 {
			rom_info.mapper = .NROM128
		} else {
			rom_info.mapper = .NROM256
		}
	}

	// flags 8

	prg_ram_size: u8 = rom_string[8]

	fmt.printfln("prg ram size according to flags 8: %v", prg_ram_size)

	// where is all the rom data
	header_size :: 16
	trainer_size :: 512

	prg_rom_start := header_size

	if rom_info.contains_trainer {
		prg_rom_start += trainer_size
	}

	chr_rom_start := prg_rom_start + rom_info.prg_rom_size

	prg_rom := make([]u8, rom_info.prg_rom_size)
	chr_rom := make([]u8, rom_info.chr_rom_size)

	copy(prg_rom[:], rom_string[prg_rom_start:])
	copy(chr_rom[:], rom_string[chr_rom_start:])

	fmt.printfln("rom info: %v", rom_info)

	rom_info.rom_loaded = true


	nes.rom_info = rom_info
	nes.prg_rom = prg_rom
	nes.chr_rom = chr_rom

	// allocating prg ram
	// assuming it is always 8kib
	nes.prg_ram = make([]u8, 1024 * 8)

	return true
}

casting_test :: proc() {
	hello: i8 = -4
	positive: i8 = 4
	fmt.printfln(
		"-4 is %8b. -4 in u16 is %16b, 4 as i8 in u16 is %16b",
		hello,
		u16(hello),
		u16(positive),
	) // 46
}

run_nestest_test :: proc() {
	nes: NES

	context.allocator = context.temp_allocator
	ok := run_nestest(&nes, "nestest/nestest.nes", "nestest/nestest.log")
	free_all(context.temp_allocator)

	if !ok {
		fmt.eprintln("nes test failed somewhere. look into it!")
		os.exit(1)
	}
}

strong_type_test :: proc() {
	a: u8 = 0xFF
	b: u8 = 0x01

	res: u16 = u16(a << 8 | b)
	fmt.printfln("res is %X", res)
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

	flags = {.NoEffect1}
	fmt.printf("noeffect1: %v, %#b\n", flags, transmute(u8)flags)

	flags = {.NoEffectB}
	fmt.printf("noeffectb: %v, %#b\n", flags, transmute(u8)flags)

}


///  memory / allocator / context things

get_total_allocated :: proc() -> int {
	alloc := (^mem.Tracking_Allocator)(context.allocator.data)

	total_used := 0

	for _, entry in alloc.allocation_map {
		total_used += entry.size
	}

	return total_used
}

print_allocated :: proc() {
	fmt.printfln("total allocated in tracking allocator: %v bytes", get_total_allocated())
}

print_allocated_temp :: proc() {
	alloc := (^runtime.Arena)(context.temp_allocator.data)
	fmt.printfln("total allocated on temp allocator: %v bytes", alloc.total_used)
}

print_allocator_features :: proc() {
	fmt.printfln("context.allocator features: %v", mem.query_features(context.allocator))
	fmt.printfln("context.temp_allocator features: %v", mem.query_features(context.temp_allocator))
}
