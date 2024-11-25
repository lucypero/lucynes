/// This file is about:
///  NES CPU and higher level NES stuff (ticking the entire NES, initializing it, etc)

package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"

readwrite_things :: proc(using nes: ^NES, addr: u16, val: u8, is_write: bool, is_dummy: bool) {
	advance_ppu(nes)
	read_writes += 1
}

dummy_read :: proc(using nes: ^NES) {
	readwrite_things(nes, 0, 0, false, true)
}

// fake read (no side effects at all)
fake_read :: proc(using nes: NES, addr: u16) -> u8 {
	// makes a copy of nes to do the read, to make this an immutable read
	// well it won't be immutable unless you do a deep copy...
	// TODO...
	nes_fake := nes
	return read(&nes_fake, addr)
}

// cpu bus read
read :: proc(using nes: ^NES, addr: u16) -> u8 {

	readwrite_things(nes, addr, 0, false, false)

	data: u8
	ok: bool

	if data, ok = cart_cpu_read(nes, addr); ok {
		// Cart dictates the cpu read, above everything else
		return data
	} else if addr >= 0x0000 && addr <= 0x1FFF {
		// Internal RAM address range
		return ram[addr & 0x07FF]
	} else if addr >= 0x2000 && addr <= 0x3FFF {
		// PPU registers address range
		ppu_reg := get_mirrored(addr, 0x2000, 0x2007)
		return read_ppu_register(nes, ppu_reg)
	} else if addr == 0x4015 {
		// APU Read status
		return apu_read(nes, addr)
	} else if addr == 0x4016 {
		// Reading controller input
		// read input from port 0
		val := (port_0_register & 0x80) >> 7
		port_0_register <<= 1
		return val
	} else if addr == 0x4017 {
		// Reading controller input
		// read input from port 1
		val := (port_1_register & 0x80) >> 7
		port_1_register <<= 1
		return val
	}

	// open bus here?
	// fmt.eprintfln("should never come here - cpu read, addr %X", addr)
	return 0
}

write :: proc(using nes: ^NES, addr: u16, val: u8) {

	last_write_addr = addr
	last_write_val = val
	readwrite_things(nes, addr, val, true, false)

	if cart_cpu_write(nes, addr, val) {
		// Cart dictates the cpu write, above everything else
		return
	} else if addr >= 0x0000 && addr <= 0x1FFF {
		// Internal RAM Address range
		ram[addr & 0x7FF] = val
		return
	} else if addr >= 0x2000 && addr <= 0x3FFF {
		// PPU registers address range
		ppu_reg := get_mirrored(int(addr), 0x2000, 0x2007)
		write_ppu_register(nes, u16(ppu_reg), val)
		return
	} else if (addr >= 0x4000 && addr <= 0x4013) || addr == 0x4013 || addr == 0x4015 || addr == 0x4017 {
		// APU registers address range
		apu_write(nes, addr, val)
		return
	} else if addr == 0x4014 {
		// OAM DMA 
		start_addr: u16 = u16(val) << 8

		for i in 0x0000 ..= 0x00FF {
			v := read(nes, u16(i) + start_addr)
			ppu.oam[i] = v
		}

		return
	} else if addr == 0x4016 {
		// Controller Input
		poll_input = (val & 0x01) != 0
		return
	}

}

nmi :: proc(using nes: ^NES, nmi_type: int) {

	// from_2000 == true: from writing to 2000
	// from_2000 == false: from ppu tick when hitting vblank

	stack_push_u16(nes, program_counter)

	flags_to_push := flags + {.NoEffect1}
	stack_push(nes, transmute(u8)flags_to_push)
	flags += {.InterruptDisable}

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
	// 	cycle_x,
	// 	scanline,
	// )

	cycles += 7
}

// Interrupt Request - Executes an instruction at a specific location
irq :: proc(using nes: ^NES) {

	// If interrupts are disabled, return
	if .InterruptDisable in flags {
		return
	}

	// TODO: This is the exact same as NMI except for the PC address. maybe unify code

	stack_push_u16(nes, program_counter)

	flags_to_push := flags + {.NoEffect1}
	stack_push(nes, transmute(u8)flags_to_push)
	flags += {.InterruptDisable}

	// read u16 memory value at 0xFFFE
	nmi_mem: u16
	low_byte := u16(read(nes, 0xFFFE))
	high_byte := u16(read(nes, 0xFFFE + 1))
	nmi_mem = high_byte << 8 | low_byte
	old_pc := program_counter
	program_counter = nmi_mem
	dummy_read(nes)
	dummy_read(nes)
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

	ppu_init(&nes.ppu)

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

run_instruction :: proc(using nes: ^NES) {

	// get first byte of instruction
	instr := read(nes, program_counter)

	instr_inf: InstructionInfo
	instr_inf.pc = program_counter

	// if program_counter == 0xBC50 {
	// 	os.exit(1)
	// }

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

	instr_inf.next_pc = program_counter
	instr_inf.triggered_nmi = nmi_triggered != 0
	instr_inf.cpu_status = nes.registers
	ringthing_add(&instr_history, instr_inf)
	ringthing_add(&instr_history_log, instr_inf)
	flags += {.NoEffect1}
}

reset_debugging_vars :: proc(using nes: ^NES) {
	read_writes = 0
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
	}

	// Check if cartridge is requesting IRQ
	if m_get_irq_state(nes) {
		m_irq_clear(nes)
		irq(nes)
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

		// faulty_op: FaultyOp

		// faulty_op.nmi_ran = nmi_was_triggered
		// faulty_op.supposed_cycles = int(cpu_cycles_dt)
		// faulty_op.cycles_taken = int(read_writes)

		// faulty_ops[instr_info.opcode] = faulty_op
	}

	for i in 0 ..< cpu_cycles_dt * 3 {
		apu_tick(nes)
	}

}

dump_log :: proc(using nes: ^NES) {

	context.allocator = context.temp_allocator

	b := strings.builder_make_len_cap(0, 10000)

	// Drawing instructions
	the_indx := nes.instr_history_log.last_placed
	the_buf_len := len(nes.instr_history_log.buf)

	the_indx += 1

	if the_indx >= the_buf_len {
		the_indx = 0
	}

	for i in 0 ..< the_buf_len {
		instr := nes.instr_history_log.buf[the_indx]

		the_indx += 1

		if the_indx >= the_buf_len {
			the_indx = 0
		}

		tb, np := get_instr_str_builder(nes^, instr.pc)
		strings.write_string(&b, strings.to_upper(strings.to_string(tb)))
		if instr.triggered_nmi {
			strings.write_string(&b, " - [NMI!]")
		}

		// if i == instr_history_log.last_placed {
		// 	strings.write_string(&b, " - the last one ")
		// }

		fmt.sbprintf(
			&b,
			" // A:$%X, X:$%X, Y:$%X",
			instr.cpu_status.accumulator,
			instr.cpu_status.index_x,
			instr.cpu_status.index_y,
		)

		strings.write_string(&b, "\n")

	}

	ok := os.write_entire_file("dump.log", b.buf[:])
	if !ok {
		fmt.eprintfln("could not write dump")
		os.exit(1)
	}
	fmt.printfln("Log Dumped")
}

// It stops at breakpoints
// if it stops at breakpoints, returns true
tick_nes_till_vblank :: proc(
	using nes: ^NES,
	tick_force: bool, // force running at least one tick, ignoring breakpoints
	port_0_input: u8,
	port_1_input: u8,
	pixel_grid: ^PixelGrid,
) -> (
	broke: bool,
) {

	reset_debugging_vars(nes)

	// running instructions forever
	for true {

		// break at given PC
		if !tick_force && app_state.break_on_given_pc && app_state.given_pc == program_counter {
			return true
		}

		instruction_tick(nes, port_0_input, port_1_input, pixel_grid)
		reset_debugging_vars(nes)

		// dump
		if program_counter == 0xBC52 {
			// dump_log(nes)
			// os.exit(0)
			// log_dump_scheudled = false
		}

		instr_info := instr_history.buf[instr_history.last_placed]

		if !tick_force && app_state.break_on_nmi && instr_info.triggered_nmi {
			return true
		}

		if last_write_addr == 0x2000 && (last_write_val | 0x80) == 0 {
			return true
		}

		// breaking at NMI. 
		// if instr_info.triggered_nmi {
		// 	return true;
		// }

		if vblank_hit {
			vblank_hit = false
			return false
		}
	}

	return false
}

print_faulty_ops :: proc(nes: ^NES) {
	if len(nes.faulty_ops) == 0 {
		return
	}

	fmt.printfln("Faulty ops:")
	for i, val in nes.faulty_ops {
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
