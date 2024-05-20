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
	return u16(buffer[index]) + (u16(buffer[index + 1]) << 8)
}

// reads from byte slice a u16 in big endian mode
read_u16_be :: proc(buffer: []u8, index: u16) -> u16 {
	return u16(buffer[index + 1]) + (u16(buffer[index]) << 8)
}


run_instruction :: proc(using nes: ^NES) {
	// get first byte of instruction
	instr := ram[program_counter]
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
