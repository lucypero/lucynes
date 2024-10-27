/// This file is about:
///  NES CPU and higher level NES stuff (ticking the entire NES, initializing it, etc)

package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"

readwrite_things :: proc(using nes: ^NES, addr: u16, val: u8, is_write: bool, is_dummy: bool) {

	if instr_info.wrote_oamdma {
		return
	}

	advance_ppu(nes)
	read_writes += 1

	// if instr_info.opcode == 0x8D && read_writes > 4 {
	// 	fmt.println("here.")
	// }

}

dummy_read :: proc(using nes: ^NES) {
	readwrite_things(nes, 0, 0, false, true)
}


// fake read (no side effects at all)
fake_read :: proc(using nes: NES, addr: u16) -> u8 {

	switch addr {

	// PPU registers
	case 0x2000 ..= 0x3FFF:
		return 0

	// APU STATUS
	case 0x4015:
		// apu status
		return 0

	// Input
	case 0x4016:
		// read input from port 0
		// val := port_0_register & 0x80
		val := (port_0_register & 0x80) >> 7

		return val

	case 0x4017:
		// read input from port 1
		// read input from port 0
		val := (port_1_register & 0x80) >> 7

		return val
	}

	// CPU memory
	if !rom_info.rom_loaded {
		return ram[addr]
	}

	// ROM mapped memory

	switch rom_info.mapper {
	case .NROM128:
		switch addr {
		case 0x8000 ..< 0xC000:
			return prg_rom[addr - 0x8000]
		case 0xC000 ..= 0xFFFF:
			return prg_rom[addr - 0xC000]
		}
	case .NROM256:
		switch addr {
		case 0x8000 ..= 0xFFFF:
			return prg_rom[addr - 0x8000]
		}
	case .UXROM:
		switch addr {
		case 0x8000 ..< 0xC000:
			// use the bank i guess
			// data.bank <- use that
			// fmt.printfln("reading switchable memory. bank is %v", data.bank)
			data := mapper_data.(UXROMData)
			return prg_rom[uint(addr) - 0x8000 + (data.bank * 0x4000)]
		case 0xC000 ..= 0xFFFF:
			// it's the last bank
			// fmt.printfln("reading last bank")
			offset: uint = uint(addr) - 0xC000
			bank_count: uint = len(prg_rom) / 0x4000
			bank_offset := (uint(bank_count) - 1) * 0x4000
			return prg_rom[bank_offset + offset]
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

// cpu bus read
read :: proc(using nes: ^NES, addr: u16) -> u8 {

	readwrite_things(nes, addr, 0, false, false)

	switch addr {

	// PPU registers
	case 0x2000 ..= 0x3FFF:
		ppu_reg := get_mirrored(int(addr), 0x2000, 0x2007)
		// fmt.printfln("reading to a ppu register %X", ppu_reg)

		return read_ppu_register(nes, u16(ppu_reg))

	// APU STATUS
	case 0x4015:
		// apu status
		return apu_read(nes, addr)

	// Input
	case 0x4016:
		// read input from port 0
		// val := port_0_register & 0x80
		val := (port_0_register & 0x80) >> 7
		port_0_register <<= 1

		return val

	case 0x4017:
		// read input from port 1
		// read input from port 0
		val := (port_1_register & 0x80) >> 7
		port_1_register <<= 1

		return val
	}

	// CPU memory
	if !rom_info.rom_loaded {
		return ram[addr]
	}

	// ROM mapped memory

	switch rom_info.mapper {
	case .NROM128:
		switch addr {
		case 0x8000 ..< 0xC000:
			return prg_rom[addr - 0x8000]
		case 0xC000 ..= 0xFFFF:
			return prg_rom[addr - 0xC000]
		}
	case .NROM256:
		switch addr {
		case 0x8000 ..= 0xFFFF:
			return prg_rom[addr - 0x8000]
		}
	case .UXROM:
		switch addr {
		case 0x8000 ..< 0xC000:
			// use the bank i guess
			// data.bank <- use that
			// fmt.printfln("reading switchable memory. bank is %v", data.bank)
			data := mapper_data.(UXROMData)
			return prg_rom[uint(addr) - 0x8000 + (data.bank * 0x4000)]
		case 0xC000 ..= 0xFFFF:
			// it's the last bank
			// fmt.printfln("reading last bank")
			offset: uint = uint(addr) - 0xC000
			bank_count: uint = len(prg_rom) / 0x4000
			bank_offset := (uint(bank_count) - 1) * 0x4000
			return prg_rom[bank_offset + offset]
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

	readwrite_things(nes, addr, val, true, false)

	switch addr {
	// PPU registers
	case 0x2000 ..= 0x3FFF:
		ppu_reg := get_mirrored(int(addr), 0x2000, 0x2007)
		// fmt.printfln("writing to a ppu register %X", ppu_reg)
		write_ppu_register(nes, u16(ppu_reg), val)
		return

	// APU Registers
	case 0x4000 ..= 0x4013, 0x4015, 0x4017:
		apu_write(nes, addr, val)
		return

	// Input
	case 0x4016:
		poll_input = (val & 0x01) != 0
		return

	//OAMDMA
	case 0x4014:
		// fmt.printfln("writing to OAMDMA")
		instr_info.wrote_oamdma = true


		start_addr: u16 = u16(val) << 8

		for i in 0x0000 ..= 0x00FF {
			v := read(nes, u16(i) + start_addr)
			ppu_oam[i] = v
		}

		return
	}

	if !rom_info.rom_loaded {
		// fmt.printfln("unsafe write to ram: %X", addr)
		ram[addr] = val
		return
	}

	switch rom_info.mapper {
	case .NROM128:
		switch addr {
		case 0x8000 ..= 0xBFFF:
			// prg_rom[addr - 0x8000] = val
			return
		case 0xC000 ..= 0xFFFF:
			// prg_rom[addr - 0xC000] = val
			return
		}
	case .NROM256:
		switch addr {
		case 0x8000 ..= 0xFFFF:
			// prg_rom[addr - 0x8000] = val
			return
		}
	case .UXROM:
		switch addr {
		case 0x8000 ..= 0xFFFF:
			data := &mapper_data.(UXROMData)
			data.bank = uint(val) & 0x0F
		// fmt.printfln("bank switching! to %v", data.bank)
		// here u do the bank switch
		}
	}

	if rom_info.contains_ram {
		switch addr {
		case 0x6000 ..= 0x7FFF:
			// wrote to prg ram! it's ok i think
			// fmt.println("wrote to prg ram! probably ok")
			prg_ram[addr - 0x6000] = val
			return
		}
	}

	// if it didn't return by now, just write to addr.
	ram[addr] = val
}

nmi :: proc(using nes: ^NES, nmi_type: int) {

	// from_2000 == true: from writing to 2000
	// from_2000 == false: from ppu tick when hitting vblank

	stack_push_u16(nes, program_counter)
	flags += {.InterruptDisable, .NoEffect1}
	flags -= {.NoEffectB}
	stack_push(nes, transmute(u8)flags)

	// read u16 memory value at 0xFFFA
	nmi_mem: u16

	low_byte := u16(read(nes, 0xFFFA))
	high_byte := u16(read(nes, 0xFFFA + 1))

	nmi_mem = high_byte << 8 | low_byte

	old_pc := program_counter

	program_counter = nmi_mem

	dummy_read(nes)
	dummy_read(nes)

	// fmt.printfln(
	// 	"nmi triggered! %v, jumping from %X to %X. ppu_cycle: %v scanline: %v",
	// 	nmi_type,
	// 	old_pc,
	// 	program_counter,
	// 	ppu_cycle_x,
	// 	ppu_scanline,
	// )

	cycles += 7
}

// resets all NES state. loads cartridge again
nes_reset :: proc(nes: ^NES, rom_file: string) {
	context.allocator = mem.tracking_allocator(&nes_allocator)
	free_all(context.allocator)
	nes^ = {}
	res := load_rom_from_file(nes, rom_file)
	if !res {
		fmt.eprintln("could not load rom")
		os.exit(1)
	}
	nes_init(nes)
}

nes_init :: proc(using nes: ^NES) {
	// TODO: look into these reads, what should the PPU do?
	low_byte := u16(read(nes, 0xFFFC))
	high_byte := u16(read(nes, 0xFFFC + 1))
	program_counter = high_byte << 8 | low_byte
	ppu_status.vertical_blank = 1

	stack_pointer = 0xFD
	cycles = 7
	flags = transmute(RegisterFlags)u8(0x24)
	apu_init(nes)
}

// reads from byte slice a u16 in little endian mode
read_u16_le :: proc(nes: ^NES, addr: u16) -> u16 {
	low_b := read(nes, addr)
	high_b := read(nes, addr + 1)
	return u16(high_b) << 8 | u16(low_b)
}

print_instr :: proc(using nes: NES) {

	b := strings.builder_make()
	strings.builder_init_len(&b, 40)
	was_written := true

	// fake read

	opcode := fake_read(nes, program_counter)

	write_instr :: proc(using nes: NES, instr_name: string, addr_mode: AddressMode, b: ^strings.Builder) {

		strings.write_string(b, instr_name)
		switch addr_mode {
		case .Implicit:
		case .Accumulator:
			strings.write_string(b, " A")
		case .Immediate:
			// Immediate
			strings.write_string(b, " #")
			immediate_val := fake_read(nes, program_counter + 1)
			strings.write_int(b, int(immediate_val), 16)
		case .ZeroPage:
			// zp
			strings.write_string(b, " $")
			immediate_val := fake_read(nes, program_counter + 1)
			strings.write_int(b, int(immediate_val), 16)
		case .ZeroPageX:
			// zpx
			strings.write_string(b, " $")
			immediate_val := fake_read(nes, program_counter + 1)
			strings.write_int(b, int(immediate_val), 16)
			strings.write_string(b, ",X")
		case .ZeroPageY:
			// zpx
			strings.write_string(b, " $")
			immediate_val := fake_read(nes, program_counter + 1)
			strings.write_int(b, int(immediate_val), 16)
			strings.write_string(b, ",Y")
		case .Relative:
			strings.write_string(b, " ")
			addr_1 := fake_read(nes, program_counter + 1)
			strings.write_int(b, int(addr_1), 16)
		case .Absolute:
			strings.write_string(b, " $")
			addr_1 := fake_read(nes, program_counter + 1)
			addr_2 := fake_read(nes, program_counter + 2)
			strings.write_int(b, int(addr_2), 16)
			strings.write_int(b, int(addr_1), 16)
		case .AbsoluteX:
			// absolute, x
			strings.write_string(b, " $")
			addr_1 := fake_read(nes, program_counter + 1)
			addr_2 := fake_read(nes, program_counter + 2)
			strings.write_int(b, int(addr_2), 16)
			strings.write_int(b, int(addr_1), 16)
			strings.write_string(b, ",X")
		case .AbsoluteY:
			strings.write_string(b, " $")
			addr_1 := fake_read(nes, program_counter + 1)
			addr_2 := fake_read(nes, program_counter + 2)
			strings.write_int(b, int(addr_2), 16)
			strings.write_int(b, int(addr_1), 16)
			strings.write_string(b, ",Y")
		case .Indirect:
			strings.write_string(b, " ($")
			addr_1 := fake_read(nes, program_counter + 1)
			addr_2 := fake_read(nes, program_counter + 2)
			strings.write_int(b, int(addr_2), 16)
			strings.write_int(b, int(addr_1), 16)
			strings.write_string(b, ")")
		case .IndirectX:
			strings.write_string(b, " ($")
			addr_1 := fake_read(nes, program_counter + 1)
			strings.write_int(b, int(addr_1), 16)
			strings.write_string(b, ",X)")
		case .IndirectY:
			strings.write_string(b, " ($")
			addr_1 := fake_read(nes, program_counter + 1)
			strings.write_int(b, int(addr_1), 16)
			strings.write_string(b, "),Y")
		}
	}

	instr_name := "AND"

	switch opcode {


	// AND

	case 0x29:
		write_instr(nes, "AND", .Immediate, &b)
	case 0x25:
		write_instr(nes, "AND", .ZeroPage, &b)
	case 0x35:
		write_instr(nes, "AND", .ZeroPageX, &b)
	case 0x2D:
		write_instr(nes, "AND", .Absolute, &b)
	case 0x3D:
		write_instr(nes, "AND", .AbsoluteX, &b)
	case 0x39:
		write_instr(nes, "AND", .AbsoluteY, &b)
	case 0x21:
		write_instr(nes, "AND", .IndirectX, &b)
	case 0x31:
		write_instr(nes, "AND", .IndirectY, &b)

	// ASL

	case 0x0A:
		write_instr(nes, "ASL", .Accumulator, &b)
	case 0x06:
		write_instr(nes, "ASL", .ZeroPage, &b)
	case 0x16:
		write_instr(nes, "ASL", .ZeroPageX, &b)
	case 0x0E:
		write_instr(nes, "ASL", .Absolute, &b)
	case 0x1E:
		write_instr(nes, "ASL", .AbsoluteX, &b)

	// ADC
	case 0x69:
		write_instr(nes, "ADC", .Immediate, &b)
	case 0x65:
		write_instr(nes, "ADC", .ZeroPage, &b)
	case 0x75:
		write_instr(nes, "ADC", .ZeroPageX, &b)
	case 0x6D:
		write_instr(nes, "ADC", .Absolute, &b)
	case 0x7D:
		write_instr(nes, "ADC", .AbsoluteX, &b)
	case 0x79:
		write_instr(nes, "ADC", .AbsoluteY, &b)
	case 0x61:
		write_instr(nes, "ADC", .IndirectX, &b)
	case 0x71:
		write_instr(nes, "ADC", .IndirectY, &b)

	// BCC
	case 0x90:
		write_instr(nes, "BCC", .Relative, &b)

	// BCS
	case 0xB0:
		write_instr(nes, "BCS", .Relative, &b)

	// BEQ
	case 0xF0:
		write_instr(nes, "BEQ", .Relative, &b)

	// BIT
	case 0x24:
		write_instr(nes, "BIT", .ZeroPage, &b)
	case 0x2C:
		write_instr(nes, "BIT", .Absolute, &b)

	// BMI
	case 0x30:
		write_instr(nes, "BMI", .Relative, &b)

	// BNE
	case 0xD0:
		write_instr(nes, "BNE", .Relative, &b)

	// BPL
	case 0x10:
		write_instr(nes, "BPL", .Relative, &b)

	// BRK
	case 0x00:
		write_instr(nes, "BRK", .Implicit, &b)

	// BVC
	case 0x50:
		write_instr(nes, "BVC", .Relative, &b)

	// BVS
	case 0x70:
		write_instr(nes, "BVS", .Relative, &b)

	// CLC
	case 0x18:
		write_instr(nes, "CLC", .Implicit, &b)

	// CLD
	case 0xD8:
		write_instr(nes, "CLD", .Implicit, &b)

	// CLI
	case 0x58:
		write_instr(nes, "CLI", .Implicit, &b)

	// CLV
	case 0xB8:
		write_instr(nes, "CLV", .Implicit, &b)

	// CMP
	case 0xC9:
		write_instr(nes, "CMP", .Immediate, &b)
	case 0xC5:
		write_instr(nes, "CMP", .ZeroPage, &b)
	case 0xD5:
		write_instr(nes, "CMP", .ZeroPageX, &b)
	case 0xCD:
		write_instr(nes, "CMP", .Absolute, &b)
	case 0xDD:
		write_instr(nes, "CMP", .AbsoluteX, &b)
	case 0xD9:
		write_instr(nes, "CMP", .AbsoluteY, &b)
	case 0xC1:
		write_instr(nes, "CMP", .IndirectX, &b)
	case 0xD1:
		write_instr(nes, "CMP", .IndirectY, &b)

	// CPX

	case 0xE0:
		write_instr(nes, "CPX", .Immediate, &b)
	case 0xE4:
		write_instr(nes, "CPX", .ZeroPage, &b)
	case 0xEC:
		write_instr(nes, "CPX", .Absolute, &b)

	// CPY

	case 0xC0:
		write_instr(nes, "CPY", .Immediate, &b)
	case 0xC4:
		write_instr(nes, "CPY", .ZeroPage, &b)
	case 0xCC:
		write_instr(nes, "CPY", .Absolute, &b)


	// DEC
	case 0xC6:
		write_instr(nes, "DEC", .ZeroPage, &b)
	case 0xD6:
		write_instr(nes, "DEC", .ZeroPageX, &b)
	case 0xCE:
		write_instr(nes, "DEC", .Absolute, &b)
	case 0xDE:
		write_instr(nes, "DEC", .AbsoluteX, &b)

	// DEX

	case 0xCA:
		write_instr(nes, "DEX", .Implicit, &b)


	// DEY

	case 0x88:
		write_instr(nes, "DEY", .Implicit, &b)

	// EOR

	case 0x49:
		write_instr(nes, "EOR", .Immediate, &b)
	case 0x45:
		write_instr(nes, "EOR", .ZeroPage, &b)
	case 0x55:
		write_instr(nes, "EOR", .ZeroPageX, &b)
	case 0x4D:
		write_instr(nes, "EOR", .Absolute, &b)
	case 0x5D:
		write_instr(nes, "EOR", .AbsoluteX, &b)
	case 0x59:
		write_instr(nes, "EOR", .AbsoluteY, &b)
	case 0x41:
		write_instr(nes, "EOR", .IndirectX, &b)
	case 0x51:
		write_instr(nes, "EOR", .IndirectY, &b)

	// INC

	case 0xE6:
		write_instr(nes, "INC", .ZeroPage, &b)
	case 0xF6:
		write_instr(nes, "INC", .ZeroPageX, &b)
	case 0xEE:
		write_instr(nes, "INC", .Absolute, &b)
	case 0xFE:
		write_instr(nes, "INC", .AbsoluteX, &b)

	// INX

	case 0xE8:
		write_instr(nes, "INX", .Implicit, &b)

	// INY

	case 0xC8:
		write_instr(nes, "INY", .Implicit, &b)

	// JMP
	case 0x4C:
		write_instr(nes, "JMP", .Absolute, &b)
	case 0x6C:
		write_instr(nes, "JMP", .Indirect, &b)


	// JSR

	case 0x20:
		write_instr(nes, "JSR", .Absolute, &b)


	// LDA

	case 0xA9:
		write_instr(nes, "LDA", .Immediate, &b)
	case 0xA5:
		write_instr(nes, "LDA", .ZeroPage, &b)
	case 0xB5:
		write_instr(nes, "LDA", .ZeroPageX, &b)
	case 0xAD:
		write_instr(nes, "LDA", .Absolute, &b)
	case 0xBD:
		write_instr(nes, "LDA", .AbsoluteX, &b)
	case 0xB9:
		write_instr(nes, "LDA", .AbsoluteY, &b)
	case 0xA1:
		write_instr(nes, "LDA", .IndirectX, &b)
	case 0xB1:
		write_instr(nes, "LDA", .IndirectY, &b)


	// LDX

	case 0xA2:
		write_instr(nes, "LDX", .Immediate, &b)
	case 0xA6:
		write_instr(nes, "LDX", .ZeroPage, &b)
	case 0xB6:
		write_instr(nes, "LDX", .ZeroPageY, &b)
	case 0xAE:
		write_instr(nes, "LDX", .Absolute, &b)
	case 0xBE:
		write_instr(nes, "LDX", .AbsoluteY, &b)

	// LDY

	case 0xA0:
		write_instr(nes, "LDY", .Immediate, &b)
	case 0xA4:
		write_instr(nes, "LDY", .ZeroPage, &b)
	case 0xB4:
		write_instr(nes, "LDY", .ZeroPageX, &b)
	case 0xAC:
		write_instr(nes, "LDY", .Absolute, &b)
	case 0xBC:
		write_instr(nes, "LDY", .AbsoluteX, &b)


	// LSR

	case 0x4A:
		write_instr(nes, "LSR", .Accumulator, &b)
	case 0x46:
		write_instr(nes, "LSR", .ZeroPage, &b)
	case 0x56:
		write_instr(nes, "LSR", .ZeroPageX, &b)
	case 0x4E:
		write_instr(nes, "LSR", .Absolute, &b)
	case 0x5E:
		write_instr(nes, "LSR", .AbsoluteX, &b)


	// NOP

	case 0xEA:
		write_instr(nes, "NOP", .Implicit, &b)

	// ORA

	case 0x09:
		write_instr(nes, "ORA", .Immediate, &b)
	case 0x05:
		write_instr(nes, "ORA", .ZeroPage, &b)
	case 0x15:
		write_instr(nes, "ORA", .ZeroPageX, &b)
	case 0x0D:
		write_instr(nes, "ORA", .Absolute, &b)
	case 0x1D:
		write_instr(nes, "ORA", .AbsoluteX, &b)
	case 0x19:
		write_instr(nes, "ORA", .AbsoluteY, &b)
	case 0x01:
		write_instr(nes, "ORA", .IndirectX, &b)
	case 0x11:
		write_instr(nes, "ORA", .IndirectY, &b)

	// PHA

	case 0x48:
		write_instr(nes, "PHA", .Implicit, &b)

	// PHP

	case 0x08:
		write_instr(nes, "PHP", .Implicit, &b)


	// PLA

	case 0x68:
		write_instr(nes, "PLA", .Implicit, &b)

	// PLP
	case 0x28:
		write_instr(nes, "PLP", .Implicit, &b)

	// ROL

	case 0x2A:
		write_instr(nes, "ROL", .Accumulator, &b)
	case 0x26:
		write_instr(nes, "ROL", .ZeroPage, &b)
	case 0x36:
		write_instr(nes, "ROL", .ZeroPageX, &b)
	case 0x2E:
		write_instr(nes, "ROL", .Absolute, &b)
	case 0x3E:
		write_instr(nes, "ROL", .AbsoluteX, &b)

	// ROR

	case 0x6A:
		write_instr(nes, "ROR", .Accumulator, &b)
	case 0x66:
		write_instr(nes, "ROR", .ZeroPage, &b)
	case 0x76:
		write_instr(nes, "ROR", .ZeroPageX, &b)
	case 0x6E:
		write_instr(nes, "ROR", .Absolute, &b)
	case 0x7E:
		write_instr(nes, "ROR", .AbsoluteX, &b)


	// RTI

	case 0x40:
		write_instr(nes, "RTI", .Implicit, &b)

	// RTS

	case 0x60:
		write_instr(nes, "RTS", .Implicit, &b)

	// SBC

	case 0xE9:
		write_instr(nes, "SBC", .Immediate, &b)
	case 0xE5:
		write_instr(nes, "SBC", .ZeroPage, &b)
	case 0xF5:
		write_instr(nes, "SBC", .ZeroPageX, &b)
	case 0xED:
		write_instr(nes, "SBC", .Absolute, &b)
	case 0xFD:
		write_instr(nes, "SBC", .AbsoluteX, &b)
	case 0xF9:
		write_instr(nes, "SBC", .AbsoluteY, &b)
	case 0xE1:
		write_instr(nes, "SBC", .IndirectX, &b)
	case 0xF1:
		write_instr(nes, "SBC", .IndirectY, &b)


	// SEC

	case 0x38:
		write_instr(nes, "SEC", .Implicit, &b)

	// SED

	case 0xF8:
		write_instr(nes, "SED", .Implicit, &b)

	// SEI

	case 0x78:
		write_instr(nes, "SEI", .Implicit, &b)

	// STA

	case 0x85:
		write_instr(nes, "STA", .ZeroPage, &b)
	case 0x95:
		write_instr(nes, "STA", .ZeroPageX, &b)
	case 0x8D:
		write_instr(nes, "STA", .Absolute, &b)
	case 0x9D:
		write_instr(nes, "STA", .AbsoluteX, &b)
	case 0x99:
		write_instr(nes, "STA", .AbsoluteY, &b)
	case 0x81:
		write_instr(nes, "STA", .IndirectX, &b)
	case 0x91:
		write_instr(nes, "STA", .IndirectY, &b)

	// STX

	case 0x86:
		write_instr(nes, "STX", .ZeroPage, &b)
	case 0x96:
		write_instr(nes, "STX", .ZeroPageY, &b)
	case 0x8E:
		write_instr(nes, "STX", .Absolute, &b)

	// STY

	case 0x84:
		write_instr(nes, "STY", .ZeroPage, &b)
	case 0x94:
		write_instr(nes, "STY", .ZeroPageX, &b)
	case 0x8C:
		write_instr(nes, "STY", .Absolute, &b)


	// TAX

	case 0xAA:
		write_instr(nes, "TAX", .Implicit, &b)

	// TAY
	case 0xA8:
		write_instr(nes, "TAY", .Implicit, &b)

	// TSX
	case 0xBA:
		write_instr(nes, "TSX", .Implicit, &b)

	// TXA
	case 0x8A:
		write_instr(nes, "TXA", .Implicit, &b)

	// TXS
	case 0x9A:
		write_instr(nes, "TXS", .Implicit, &b)

	// TYA
	case 0x98:
		write_instr(nes, "TYA", .Implicit, &b)


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
		write_instr(nes, "ASO", .Absolute, &b)
	case 0x1F:
		write_instr(nes, "ASO", .AbsoluteX, &b)
	case 0x1B:
		write_instr(nes, "ASO", .AbsoluteY, &b)
	case 0x07:
		write_instr(nes, "ASO", .ZeroPage, &b)
	case 0x17:
		write_instr(nes, "ASO", .ZeroPageX, &b)
	case 0x03:
		write_instr(nes, "ASO", .IndirectX, &b)
	case 0x13:
		write_instr(nes, "ASO", .IndirectY, &b)

	// RLA

	case 0x2F:
		write_instr(nes, "RLA", .Absolute, &b)
	case 0x3F:
		write_instr(nes, "RLA", .AbsoluteX, &b)
	case 0x3B:
		write_instr(nes, "RLA", .AbsoluteY, &b)
	case 0x27:
		write_instr(nes, "RLA", .ZeroPage, &b)
	case 0x37:
		write_instr(nes, "RLA", .ZeroPageX, &b)
	case 0x23:
		write_instr(nes, "RLA", .IndirectX, &b)
	case 0x33:
		write_instr(nes, "RLA", .IndirectY, &b)

	// LSE
	case 0x4F:
		write_instr(nes, "LSE", .Absolute, &b)
	case 0x5F:
		write_instr(nes, "LSE", .AbsoluteX, &b)
	case 0x5B:
		write_instr(nes, "LSE", .AbsoluteY, &b)
	case 0x47:
		write_instr(nes, "LSE", .ZeroPage, &b)
	case 0x57:
		write_instr(nes, "LSE", .ZeroPageX, &b)
	case 0x43:
		write_instr(nes, "LSE", .IndirectX, &b)
	case 0x53:
		write_instr(nes, "LSE", .IndirectY, &b)

	// RRA

	case 0x6F:
		write_instr(nes, "RRA", .Absolute, &b)
	case 0x7F:
		write_instr(nes, "RRA", .AbsoluteX, &b)
	case 0x7B:
		write_instr(nes, "RRA", .AbsoluteY, &b)
	case 0x67:
		write_instr(nes, "RRA", .ZeroPage, &b)
	case 0x77:
		write_instr(nes, "RRA", .ZeroPageX, &b)
	case 0x63:
		write_instr(nes, "RRA", .IndirectX, &b)
	case 0x73:
		write_instr(nes, "RRA", .IndirectY, &b)

	// AXS

	case 0x8F:
		write_instr(nes, "AXS", .Absolute, &b)
	case 0x87:
		write_instr(nes, "AXS", .ZeroPage, &b)
	case 0x97:
		write_instr(nes, "AXS", .ZeroPageY, &b)
	case 0x83:
		write_instr(nes, "AXS", .IndirectX, &b)


	// LAX

	case 0xAF:
		write_instr(nes, "LAX", .Absolute, &b)
	case 0xBF:
		write_instr(nes, "LAX", .AbsoluteY, &b)
	case 0xA7:
		write_instr(nes, "LAX", .ZeroPage, &b)
	case 0xB7:
		write_instr(nes, "LAX", .ZeroPageY, &b)
	case 0xA3:
		write_instr(nes, "LAX", .IndirectX, &b)
	case 0xB3:
		write_instr(nes, "LAX", .IndirectY, &b)

	// DCM

	case 0xCF:
		write_instr(nes, "DCM", .Absolute, &b)
	case 0xDF:
		write_instr(nes, "DCM", .AbsoluteX, &b)
	case 0xDB:
		write_instr(nes, "DCM", .AbsoluteY, &b)
	case 0xC7:
		write_instr(nes, "DCM", .ZeroPage, &b)
	case 0xD7:
		write_instr(nes, "DCM", .ZeroPageX, &b)
	case 0xC3:
		write_instr(nes, "DCM", .IndirectX, &b)
	case 0xD3:
		write_instr(nes, "DCM", .IndirectY, &b)

	// INS

	case 0xEF:
		write_instr(nes, "INS", .Absolute, &b)
	case 0xFF:
		write_instr(nes, "INS", .AbsoluteX, &b)
	case 0xFB:
		write_instr(nes, "INS", .AbsoluteY, &b)
	case 0xE7:
		write_instr(nes, "INS", .ZeroPage, &b)
	case 0xF7:
		write_instr(nes, "INS", .ZeroPageX, &b)
	case 0xE3:
		write_instr(nes, "INS", .IndirectX, &b)
	case 0xF3:
		write_instr(nes, "INS", .IndirectY, &b)

	// ALR

	case 0x4B:
		write_instr(nes, "ALR", .Immediate, &b)

	// ARR

	case 0x6B:
		write_instr(nes, "ARR", .Immediate, &b)

	// XAA

	case 0x8B:
		write_instr(nes, "XAA", .Immediate, &b)

	// OAL

	case 0xAB:
		write_instr(nes, "OAL", .Immediate, &b)

	// SAX
	case 0xCB:
		write_instr(nes, "SAX", .Immediate, &b)

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
		write_instr(nes, "NOP*", .Implicit, &b)

	case 0x80:
		fallthrough
	case 0x82:
		fallthrough
	case 0x89:
		fallthrough
	case 0xC2:
		fallthrough
	case 0xE2:
		write_instr(nes, "NOP*", .Immediate, &b)

	case 0x04:
		fallthrough
	case 0x44:
		fallthrough
	case 0x64:
		write_instr(nes, "NOP*", .ZeroPage, &b)

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
		write_instr(nes, "NOP*", .ZeroPageX, &b)

	case 0x0C:
		write_instr(nes, "NOP*", .Absolute, &b)

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
		write_instr(nes, "NOP*", .AbsoluteX, &b)

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
		write_instr(nes, "HLT", .Implicit, &b)

	// TAS

	case 0x9B:
		write_instr(nes, "TAS", .AbsoluteY, &b)

	// SAY

	case 0x9C:
		write_instr(nes, "SAY", .AbsoluteX, &b)

	// XAS

	case 0x9E:
		write_instr(nes, "XAS", .AbsoluteY, &b)

	// AXA

	case 0x9F:
		write_instr(nes, "AXA", .AbsoluteY, &b)
	case 0x93:
		write_instr(nes, "AXA", .IndirectY, &b)

	// ANC
	case 0x2B:
		fallthrough
	case 0x0B:
		write_instr(nes, "ANC", .Immediate, &b)


	// LAS
	case 0xBB:
		write_instr(nes, "LAS", .IndirectY, &b)

	// OPCODE EB
	case 0xEB:
		write_instr(nes, "SBC", .Immediate, &b)


	case:
		was_written = false
		instr_name := ""
	}

	if was_written {
		fmt.println(strings.to_string(b))
	}

}

run_instruction :: proc(using nes: ^NES) {

	// get first byte of instruction
	instr_info.reading_opcode = true
	instr := read(nes, program_counter)
	instr_info.reading_opcode = false
	instr_info.opcode = instr
	instr_info.running = true

	// nmi subroutine in bomberman
	// if program_counter == 0xc01a {
	// 	fmt.printfln("starting nmi subroutine. ppu cycle: %v, scanline: %v", ppu_cycle_x, ppu_scanline)
	// }

	// if program_counter != 0xc290 && program_counter != 0xc293 {
	// fmt.printfln("PC: %X OPCODE: %X A: %X", program_counter, instr, accumulator)
	// }

	print_instr(nes^)


	if program_counter == 0xBC50 {
		os.exit(1)
	}

	program_counter += 1
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
		do_opcode(nes, .Accumulator, instr_rol_accumulator, 2)
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
		do_opcode(nes, .ZeroPage, instr_nop_zp, 3)

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
		do_opcode(nes, .ZeroPageX, instr_nop_zpx, 4)

	case 0x0C:
		do_opcode(nes, .Absolute, instr_nop_absolute, 4)

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
		do_opcode(nes, .AbsoluteX, instr_nop_absx, 4)

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

reset_debugging_vars :: proc(using nes: ^NES) {
	ppu_ran_ahead = 0
	read_writes = 0
	nmi_was_triggered = false
	instr_info = {}
}

instruction_tick :: proc(using nes: ^NES, port_0_input: u8, port_1_input: u8, pixel_grid: ^PixelGrid) {
	// main NES loop
	// catchup method

	past_cycles := cycles

	run_instruction(nes)

	// If you run NMI after running the instruction normally,
	//  then bomberman start screen works. it's weird.

	if nmi_triggered != 0 {
		nmi(nes, nmi_triggered)
		nmi_triggered = 0
		nmi_was_triggered = true
	}

	// Input
	if poll_input {
		// fill the registers with input
		port_0_register = port_0_input
		port_1_register = port_1_input
	}

	cpu_cycles_dt := cycles - past_cycles

	// ignoring oam bad impl for now
	// if u wanna not ignore it, remove the oam check
	if cpu_cycles_dt != read_writes {

		faulty_op: FaultyOp

		faulty_op.nmi_ran = nmi_was_triggered
		faulty_op.oam_ran = instr_info.wrote_oamdma

		faulty_op.supposed_cycles = int(cpu_cycles_dt)
		faulty_op.cycles_taken = int(read_writes)

		faulty_ops[instr_info.opcode] = faulty_op
	}

	// if cpu_cycles_dt * 3 < ppu_ran_ahead {
	// 	fmt.printfln(
	// 		"here ppu run ahead is more. what the fuck. %X ppu ran ahead: %v times, cycles dt: %v, nmi: %v, readwrites: %v",
	// 		instr_info.opcode,
	// 		ppu_ran_ahead / 3,
	// 		cpu_cycles_dt,
	// 		nmi_was_triggered,
	// 		read_writes
	// 	)
	// }

	// ppu_left_to_do := math.max(0, int(cpu_cycles_dt) * 3 - int(ppu_ran_ahead))

	// for i in 0 ..< ppu_left_to_do {
	// 	fmt.println("u still had ppu left to do. fix.")
	// 	ppu_tick(nes, pixel_grid)
	// }

	for i in 0 ..< cpu_cycles_dt * 3 {
		apu_tick(nes)
	}

}

tick_nes_till_vblank :: proc(using nes: ^NES, port_0_input: u8, port_1_input: u8, pixel_grid: ^PixelGrid) {

	reset_debugging_vars(nes)

	// running instructions forever
	for true {
		instruction_tick(nes, port_0_input, port_1_input, pixel_grid)
		reset_debugging_vars(nes)

		if vblank_hit {
			vblank_hit = false
			return
		}
	}
}

print_faulty_ops :: proc(nes: ^NES) {
	if len(nes.faulty_ops) == 0 {
		return
	}

	fmt.printfln("Faulty ops:")
	for i, val in nes.faulty_ops {
		// diff is ppu_ran_ahead_ticks - (cpu_cycles_dt * 3)
		fmt.printf(
			"$%X: CS: %v, CR: %v, DIFF: %v. RAN OAM: %v, RAN NMI: %v",
			i,
			val.supposed_cycles,
			val.cycles_taken,
			val.cycles_taken - val.supposed_cycles,
			val.oam_ran,
			val.nmi_ran,
		)
		fmt.printfln("")
	}
	fmt.printfln("")
}
