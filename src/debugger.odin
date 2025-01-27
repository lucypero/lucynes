package main
import rl "vendor:raylib"
import "core:strings"
import "core:c"

// draw_debugger_view :: true
draw_debugger_view :: false

draw_pattern_tables_view :: false
// draw_pattern_tables_view :: true

instructions_y_start :: 200

// how many previous instructions to log
prev_instructions_log_count :: 10000

// how many previous instructions to display
prev_instructions_count :: 10

// how many future instructions to display
next_instructions_count :: 20

debug_x_start :: nes_width * scale_factor + 5
debug_text_color := rl.WHITE
debug_text_active_color := rl.SKYBLUE
vertical_spacing := font.baseSize - 5

PaddingType :: enum {
	ShowTwo,
	ShowFour,
}

// Assuming base 16
write_with_padding :: proc(b: ^strings.Builder, thing_value: int, digits_count: PaddingType) {

	switch digits_count {
	case .ShowTwo:
		if thing_value <= 0xF {
			strings.write_string(b, "0")
		}
	case .ShowFour:
		if thing_value <= 0xF {
			strings.write_string(b, "000")
		} else if thing_value <= 0xFF {
			strings.write_string(b, "00")
		} else if thing_value <= 0xFFF {
			strings.write_string(b, "0")
		}
	}

	strings.write_int(b, thing_value, 16)
}

NumberDisplay :: enum {
	Base10,
	Base16,
	Base16With10,
}

draw_text :: proc(b: ^strings.Builder, ypos: f32, name: string, x_offset: f32 = 0) {
	strings.builder_reset(b)
	strings.write_string(b, name)
	the_str := strings.to_string(b^)
	the_str = strings.to_upper(the_str)
	the_cstr := strings.clone_to_cstring(the_str)
	rl.DrawTextEx(font, the_cstr, {debug_x_start + x_offset, ypos}, f32(font.baseSize), 0, debug_text_color)
}

draw_cpu_thing :: proc(
	b: ^strings.Builder,
	ypos: f32,
	name: string,
	thing_value: int,
	number_display: NumberDisplay,
	digits_count: PaddingType = .ShowTwo,
	x_offset: f32 = 0,
) {
	strings.builder_reset(b)
	strings.write_string(b, name)
	strings.write_string(b, ": ")

	switch number_display {
	case .Base10:
		strings.write_int(b, thing_value)
	case .Base16:
		strings.write_string(b, "$")
		write_with_padding(b, thing_value, digits_count)
	case .Base16With10:
		strings.write_string(b, "$")
		write_with_padding(b, thing_value, digits_count)
		strings.write_string(b, " [")
		strings.write_int(b, thing_value)
		strings.write_string(b, "]")
	}

	the_str := strings.to_string(b^)
	the_str = strings.to_upper(the_str)
	the_cstr := strings.clone_to_cstring(the_str)
	rl.DrawTextEx(font, the_cstr, {debug_x_start + x_offset, ypos}, f32(font.baseSize), 0, debug_text_color)
}

draw_ppu_state :: proc(nes: NES, ypos: f32) -> f32 {
	ypos := ypos

	using nes.ppu

	// rl.DrawTextEx(font, "CYCLE: ", {debug_x_start, ypos}, f32(font.baseSize), 0, debug_text_color)

	b := strings.builder_make_len_cap(0, 10)
	draw_cpu_thing(&b, ypos, "CYC", cycle_x, .Base10, x_offset = 0)
	draw_cpu_thing(&b, ypos, "SCN", scanline, .Base10, x_offset = 150)
	ypos += f32(vertical_spacing)
	draw_cpu_thing(&b, ypos, "PPUCTRL", int(ppu_ctrl.reg), .Base16, x_offset = 0)
	ypos += f32(vertical_spacing)
	draw_cpu_thing(&b, ypos, "PPUMASK", int(ppu_mask.reg), .Base16, x_offset = 0)
	ypos += f32(vertical_spacing)
	draw_cpu_thing(&b, ypos, "PPUSTATUS", int(ppu_status.reg), .Base16, x_offset = 0)
	ypos += f32(vertical_spacing)

	return ypos
}

draw_cpu_state :: proc(ypos: f32, nes: NES, is_paused: bool) -> f32 {

	ypos := ypos

	// Status

	rl.DrawTextEx(font, "STATUS: ", {debug_x_start, ypos}, f32(font.baseSize), 0, debug_text_color)

	flag_color := debug_text_color

	if .Negative in nes.registers.flags {
		flag_color = debug_text_active_color
	} else {
		flag_color = debug_text_color
	}

	rl.DrawTextEx(font, "N", {debug_x_start + 100, ypos}, f32(font.baseSize), 0, flag_color)

	if .Overflow in nes.registers.flags {
		flag_color = debug_text_active_color
	} else {
		flag_color = debug_text_color
	}

	rl.DrawTextEx(font, "V", {debug_x_start + 120, ypos}, f32(font.baseSize), 0, flag_color)

	if .NoEffect1 in nes.registers.flags {
		flag_color = debug_text_active_color
	} else {
		flag_color = debug_text_color
	}

	rl.DrawTextEx(font, "-", {debug_x_start + 140, ypos}, f32(font.baseSize), 0, flag_color)

	if .NoEffectB in nes.registers.flags {
		flag_color = debug_text_active_color
	} else {
		flag_color = debug_text_color
	}

	rl.DrawTextEx(font, "-", {debug_x_start + 160, ypos}, f32(font.baseSize), 0, flag_color)

	if .Decimal in nes.registers.flags {
		flag_color = debug_text_active_color
	} else {
		flag_color = debug_text_color
	}

	rl.DrawTextEx(font, "D", {debug_x_start + 180, ypos}, f32(font.baseSize), 0, flag_color)

	if .InterruptDisable in nes.registers.flags {
		flag_color = debug_text_active_color
	} else {
		flag_color = debug_text_color
	}

	rl.DrawTextEx(font, "I", {debug_x_start + 200, ypos}, f32(font.baseSize), 0, flag_color)

	if .Zero in nes.registers.flags {
		flag_color = debug_text_active_color
	} else {
		flag_color = debug_text_color
	}

	rl.DrawTextEx(font, "Z", {debug_x_start + 220, ypos}, f32(font.baseSize), 0, flag_color)

	if .Carry in nes.registers.flags {
		flag_color = debug_text_active_color
	} else {
		flag_color = debug_text_color
	}

	rl.DrawTextEx(font, "C", {debug_x_start + 240, ypos}, f32(font.baseSize), 0, flag_color)

	b := strings.builder_make_len_cap(0, 10)
	strings.write_string(&b, " ($")
	strings.write_uint(&b, uint(transmute(u8)(nes.registers.flags)), 16)
	strings.write_string(&b, ")")
	the_str := strings.to_string(b)
	the_str = strings.to_upper(the_str)
	the_cstr := strings.clone_to_cstring(the_str)
	rl.DrawTextEx(font, the_cstr, {debug_x_start + 260, ypos}, f32(font.baseSize), 0, debug_text_color)
	ypos += f32(vertical_spacing)

	// PC
	draw_cpu_thing(&b, ypos, "PC", int(nes.program_counter), .Base16, digits_count = .ShowFour)
	ypos += f32(vertical_spacing)

	// A
	draw_cpu_thing(&b, ypos, "A", int(nes.accumulator), .Base16With10)
	ypos += f32(vertical_spacing)

	// X
	draw_cpu_thing(&b, ypos, "X", int(nes.index_x), .Base16With10)
	ypos += f32(vertical_spacing)

	// Y
	draw_cpu_thing(&b, ypos, "Y", int(nes.index_y), .Base16With10)
	ypos += f32(vertical_spacing)

	// Stack P
	draw_cpu_thing(&b, ypos, "SP", int(nes.stack_pointer), .Base16)

	if is_paused {
		draw_text(&b, ypos, "PAUSED", x_offset = 200)
	}
	ypos += f32(vertical_spacing)


	return ypos
}

draw_debugger :: proc(nes: NES, is_paused: bool) {

	vertical_spacing = font.baseSize - 5
	when !draw_debugger_view {
		return
	}

	context.allocator = context.temp_allocator

	ypos: f32 = 1

	// Drawing CPU State
	ypos = draw_cpu_state(ypos, nes, is_paused)

	// Line

	rl.DrawLine(
		debug_x_start,
		c.int(ypos + (f32(vertical_spacing) / 2)),
		debug_x_start + debug_width - 10,
		c.int(ypos + (f32(vertical_spacing) / 2)),
		debug_text_color,
	)
	ypos += f32(vertical_spacing)

	// Draw PPU State
	ypos = draw_ppu_state(nes, ypos)

	// Line

	rl.DrawLine(
		debug_x_start,
		c.int(ypos + (f32(vertical_spacing) / 2)),
		debug_x_start + debug_width - 10,
		c.int(ypos + (f32(vertical_spacing) / 2)),
		debug_text_color,
	)

	ypos += f32(vertical_spacing)

	// Drawing instructions
	the_indx := nes.instr_history.next_placed
	the_buf_len := len(nes.instr_history.buf)

	// retrace it back
	for _ in 0 ..< the_buf_len - 1 {
		the_indx -= 1
		if the_indx < 0 {
			the_indx = the_buf_len - 1
		}
	}

	instr_info: InstructionInfo
	builder: strings.Builder
	next_pc: u16

	for i in 0 ..< the_buf_len + next_instructions_count {
		// are we in the future?
		if i >= the_buf_len {
			// We're in the future.
			builder, next_pc = get_instr_str_builder(nes, next_pc)
		} else {
			// We're in the past or present, looking at instructions already ran.
			instr_info = nes.instr_history.buf[the_indx]
			builder, _ = get_instr_str_builder(nes, instr_info.pc)

			if instr_info.triggered_nmi {
				strings.write_string(&builder, " - [NMI!]")
			}

			next_pc = instr_info.next_pc

			the_indx += 1

			if the_indx >= the_buf_len {
				the_indx = 0
			}
		}

		the_str := strings.to_string(builder)
		the_str = strings.to_upper(the_str)

		c_str := strings.clone_to_cstring(the_str)

		col := debug_text_color

		if i == the_buf_len {
			col = debug_text_active_color
		}

		rl.DrawTextEx(font, c_str, {debug_x_start, ypos}, f32(font.baseSize), 0, col)

		ypos += f32(vertical_spacing)
	}
}

get_instr_str_builder :: proc(nes: NES, pc: u16) -> (b: strings.Builder, next_pc: u16) {

	get_ppu_register_name :: proc(mem : u16) -> string {

		// PPU registers address range
		ppu_reg := get_mirrored(mem, 0x2000, 0x2007)

		switch ppu_reg {
			case 0x2000: return "PPUCTRL"
			case 0x2001: return "PPUMASK"
			case 0x2002: return "PPUSTATUS"
			case 0x2003: return "OAMADDR"
			case 0x2004: return "OAMDATA"
			case 0x2005: return "PPUSCROLL"
			case 0x2006: return "PPUADDR"
			case 0x2007: return "PPUDATA"
			case 0x4014: return "OAMDMA"
			case: return "NOTAPPUREGISTER"
		}
	}

	b = strings.builder_make_len_cap(0, 10)
	strings.write_string(&b, "$")
	write_with_padding(&b, int(pc), .ShowFour)
	strings.write_string(&b, ": ")
	was_written := true

	// fake read

	opcode := fake_read(nes, pc)

	write_instr :: proc(
		nes: NES,
		pc: u16,
		instr_name: string,
		addr_mode: AddressMode,
		b: ^strings.Builder,
	) -> (
		pc_advance: u16,
	) {
		strings.write_string(b, instr_name)
		switch addr_mode {
		case .Implicit:
			pc_advance += 1
		case .Accumulator:
			pc_advance += 1
			strings.write_string(b, " A")
		case .Immediate:
			pc_advance += 2
			// Immediate
			strings.write_string(b, " #")
			immediate_val := fake_read(nes, pc + 1)
			write_with_padding(b, int(immediate_val), .ShowTwo)
		case .ZeroPage:
			pc_advance += 2
			// zp
			strings.write_string(b, " $")
			immediate_val := fake_read(nes, pc + 1)
			write_with_padding(b, int(immediate_val), .ShowTwo)
		case .ZeroPageX:
			pc_advance += 2
			// zpx
			strings.write_string(b, " $")
			immediate_val := fake_read(nes, pc + 1)
			write_with_padding(b, int(immediate_val), .ShowTwo)
			strings.write_string(b, ",X")
		case .ZeroPageY:
			pc_advance += 2
			// zpx
			strings.write_string(b, " $")
			immediate_val := fake_read(nes, pc + 1)
			write_with_padding(b, int(immediate_val), .ShowTwo)
			strings.write_string(b, ",Y")
		case .Relative:
			pc_advance += 2
			strings.write_string(b, " -> $")
			addr_1 := i8(fake_read(nes, pc + 1))
			jumped_to_pc := pc + u16(addr_1) + 2
			write_with_padding(b, int(jumped_to_pc), .ShowFour)
		case .Absolute:
			pc_advance += 3
			strings.write_string(b, " $")
			addr_1 := fake_read(nes, pc + 1)
			addr_2 := fake_read(nes, pc + 2)
			addr : u16 = (u16(addr_2) << 8) | u16(addr_1)
			if is_ppu_register(addr) {
				strings.write_string(b, get_ppu_register_name(addr))
				strings.write_string(b, "_")
			}
			write_with_padding(b, int(addr), .ShowFour)
		case .AbsoluteX:
			pc_advance += 3
			// absolute, x
			strings.write_string(b, " $")
			addr_1 := fake_read(nes, pc + 1)
			addr_2 := fake_read(nes, pc + 2)
			addr : u16 = (u16(addr_2) << 8) | u16(addr_1)
			if is_ppu_register(addr) {
				strings.write_string(b, get_ppu_register_name(addr))
				strings.write_string(b, "_")
			}
			write_with_padding(b, int(addr), .ShowFour)
			strings.write_string(b, ",X")
		case .AbsoluteY:
			pc_advance += 3
			strings.write_string(b, " $")
			addr_1 := fake_read(nes, pc + 1)
			addr_2 := fake_read(nes, pc + 2)
			addr : u16 = (u16(addr_2) << 8) | u16(addr_1)
			if is_ppu_register(addr) {
				strings.write_string(b, get_ppu_register_name(addr))
				strings.write_string(b, "_")
			}
			write_with_padding(b, int(addr), .ShowFour)
			strings.write_string(b, ",Y")
		case .Indirect:
			pc_advance += 3
			strings.write_string(b, " -> ($")
			addr_1 := fake_read(nes, pc + 1)
			addr_2 := fake_read(nes, pc + 2)
			addr : u16 = (u16(addr_2) << 4) | u16(addr_1)
			if is_ppu_register(addr) {
				strings.write_string(b, get_ppu_register_name(addr))
				strings.write_string(b, "_")
				write_with_padding(b, int(addr), .ShowFour)
			}
			write_with_padding(b, int(addr), .ShowFour)
			strings.write_string(b, ")")
		case .IndirectX:
			pc_advance += 2
			strings.write_string(b, " ($")
			addr_1 := fake_read(nes, pc + 1)
			write_with_padding(b, int(addr_1), .ShowTwo)
			strings.write_string(b, ",X)")
		case .IndirectY:
			pc_advance += 2
			strings.write_string(b, " ($")
			addr_1 := fake_read(nes, pc + 1)
			write_with_padding(b, int(addr_1), .ShowTwo)
			strings.write_string(b, "),Y")
		}

		return
	}

	instr_name := "AND"
	pc_advance: u16

	switch opcode {


	// AND

	case 0x29:
		pc_advance = write_instr(nes, pc, "AND", .Immediate, &b)
	case 0x25:
		pc_advance = write_instr(nes, pc, "AND", .ZeroPage, &b)
	case 0x35:
		pc_advance = write_instr(nes, pc, "AND", .ZeroPageX, &b)
	case 0x2D:
		pc_advance = write_instr(nes, pc, "AND", .Absolute, &b)
	case 0x3D:
		pc_advance = write_instr(nes, pc, "AND", .AbsoluteX, &b)
	case 0x39:
		pc_advance = write_instr(nes, pc, "AND", .AbsoluteY, &b)
	case 0x21:
		pc_advance = write_instr(nes, pc, "AND", .IndirectX, &b)
	case 0x31:
		pc_advance = write_instr(nes, pc, "AND", .IndirectY, &b)

	// ASL

	case 0x0A:
		pc_advance = write_instr(nes, pc, "ASL", .Accumulator, &b)
	case 0x06:
		pc_advance = write_instr(nes, pc, "ASL", .ZeroPage, &b)
	case 0x16:
		pc_advance = write_instr(nes, pc, "ASL", .ZeroPageX, &b)
	case 0x0E:
		pc_advance = write_instr(nes, pc, "ASL", .Absolute, &b)
	case 0x1E:
		pc_advance = write_instr(nes, pc, "ASL", .AbsoluteX, &b)

	// ADC
	case 0x69:
		pc_advance = write_instr(nes, pc, "ADC", .Immediate, &b)
	case 0x65:
		pc_advance = write_instr(nes, pc, "ADC", .ZeroPage, &b)
	case 0x75:
		pc_advance = write_instr(nes, pc, "ADC", .ZeroPageX, &b)
	case 0x6D:
		pc_advance = write_instr(nes, pc, "ADC", .Absolute, &b)
	case 0x7D:
		pc_advance = write_instr(nes, pc, "ADC", .AbsoluteX, &b)
	case 0x79:
		pc_advance = write_instr(nes, pc, "ADC", .AbsoluteY, &b)
	case 0x61:
		pc_advance = write_instr(nes, pc, "ADC", .IndirectX, &b)
	case 0x71:
		pc_advance = write_instr(nes, pc, "ADC", .IndirectY, &b)

	// BCC
	case 0x90:
		pc_advance = write_instr(nes, pc, "BCC", .Relative, &b)

	// BCS
	case 0xB0:
		pc_advance = write_instr(nes, pc, "BCS", .Relative, &b)

	// BEQ
	case 0xF0:
		pc_advance = write_instr(nes, pc, "BEQ", .Relative, &b)

	// BIT
	case 0x24:
		pc_advance = write_instr(nes, pc, "BIT", .ZeroPage, &b)
	case 0x2C:
		pc_advance = write_instr(nes, pc, "BIT", .Absolute, &b)

	// BMI
	case 0x30:
		pc_advance = write_instr(nes, pc, "BMI", .Relative, &b)

	// BNE
	case 0xD0:
		pc_advance = write_instr(nes, pc, "BNE", .Relative, &b)

	// BPL
	case 0x10:
		pc_advance = write_instr(nes, pc, "BPL", .Relative, &b)

	// BRK
	case 0x00:
		pc_advance = write_instr(nes, pc, "BRK", .Implicit, &b)

	// BVC
	case 0x50:
		pc_advance = write_instr(nes, pc, "BVC", .Relative, &b)

	// BVS
	case 0x70:
		pc_advance = write_instr(nes, pc, "BVS", .Relative, &b)

	// CLC
	case 0x18:
		pc_advance = write_instr(nes, pc, "CLC", .Implicit, &b)

	// CLD
	case 0xD8:
		pc_advance = write_instr(nes, pc, "CLD", .Implicit, &b)

	// CLI
	case 0x58:
		pc_advance = write_instr(nes, pc, "CLI", .Implicit, &b)

	// CLV
	case 0xB8:
		pc_advance = write_instr(nes, pc, "CLV", .Implicit, &b)

	// CMP
	case 0xC9:
		pc_advance = write_instr(nes, pc, "CMP", .Immediate, &b)
	case 0xC5:
		pc_advance = write_instr(nes, pc, "CMP", .ZeroPage, &b)
	case 0xD5:
		pc_advance = write_instr(nes, pc, "CMP", .ZeroPageX, &b)
	case 0xCD:
		pc_advance = write_instr(nes, pc, "CMP", .Absolute, &b)
	case 0xDD:
		pc_advance = write_instr(nes, pc, "CMP", .AbsoluteX, &b)
	case 0xD9:
		pc_advance = write_instr(nes, pc, "CMP", .AbsoluteY, &b)
	case 0xC1:
		pc_advance = write_instr(nes, pc, "CMP", .IndirectX, &b)
	case 0xD1:
		pc_advance = write_instr(nes, pc, "CMP", .IndirectY, &b)

	// CPX

	case 0xE0:
		pc_advance = write_instr(nes, pc, "CPX", .Immediate, &b)
	case 0xE4:
		pc_advance = write_instr(nes, pc, "CPX", .ZeroPage, &b)
	case 0xEC:
		pc_advance = write_instr(nes, pc, "CPX", .Absolute, &b)

	// CPY

	case 0xC0:
		pc_advance = write_instr(nes, pc, "CPY", .Immediate, &b)
	case 0xC4:
		pc_advance = write_instr(nes, pc, "CPY", .ZeroPage, &b)
	case 0xCC:
		pc_advance = write_instr(nes, pc, "CPY", .Absolute, &b)


	// DEC
	case 0xC6:
		pc_advance = write_instr(nes, pc, "DEC", .ZeroPage, &b)
	case 0xD6:
		pc_advance = write_instr(nes, pc, "DEC", .ZeroPageX, &b)
	case 0xCE:
		pc_advance = write_instr(nes, pc, "DEC", .Absolute, &b)
	case 0xDE:
		pc_advance = write_instr(nes, pc, "DEC", .AbsoluteX, &b)

	// DEX

	case 0xCA:
		pc_advance = write_instr(nes, pc, "DEX", .Implicit, &b)


	// DEY

	case 0x88:
		pc_advance = write_instr(nes, pc, "DEY", .Implicit, &b)

	// EOR

	case 0x49:
		pc_advance = write_instr(nes, pc, "EOR", .Immediate, &b)
	case 0x45:
		pc_advance = write_instr(nes, pc, "EOR", .ZeroPage, &b)
	case 0x55:
		pc_advance = write_instr(nes, pc, "EOR", .ZeroPageX, &b)
	case 0x4D:
		pc_advance = write_instr(nes, pc, "EOR", .Absolute, &b)
	case 0x5D:
		pc_advance = write_instr(nes, pc, "EOR", .AbsoluteX, &b)
	case 0x59:
		pc_advance = write_instr(nes, pc, "EOR", .AbsoluteY, &b)
	case 0x41:
		pc_advance = write_instr(nes, pc, "EOR", .IndirectX, &b)
	case 0x51:
		pc_advance = write_instr(nes, pc, "EOR", .IndirectY, &b)

	// INC

	case 0xE6:
		pc_advance = write_instr(nes, pc, "INC", .ZeroPage, &b)
	case 0xF6:
		pc_advance = write_instr(nes, pc, "INC", .ZeroPageX, &b)
	case 0xEE:
		pc_advance = write_instr(nes, pc, "INC", .Absolute, &b)
	case 0xFE:
		pc_advance = write_instr(nes, pc, "INC", .AbsoluteX, &b)

	// INX

	case 0xE8:
		pc_advance = write_instr(nes, pc, "INX", .Implicit, &b)

	// INY

	case 0xC8:
		pc_advance = write_instr(nes, pc, "INY", .Implicit, &b)

	// JMP
	case 0x4C:
		pc_advance = write_instr(nes, pc, "JMP", .Absolute, &b)
	case 0x6C:
		pc_advance = write_instr(nes, pc, "JMP", .Indirect, &b)


	// JSR

	case 0x20:
		pc_advance = write_instr(nes, pc, "JSR", .Absolute, &b)


	// LDA

	case 0xA9:
		pc_advance = write_instr(nes, pc, "LDA", .Immediate, &b)
	case 0xA5:
		pc_advance = write_instr(nes, pc, "LDA", .ZeroPage, &b)
	case 0xB5:
		pc_advance = write_instr(nes, pc, "LDA", .ZeroPageX, &b)
	case 0xAD:
		pc_advance = write_instr(nes, pc, "LDA", .Absolute, &b)
	case 0xBD:
		pc_advance = write_instr(nes, pc, "LDA", .AbsoluteX, &b)
	case 0xB9:
		pc_advance = write_instr(nes, pc, "LDA", .AbsoluteY, &b)
	case 0xA1:
		pc_advance = write_instr(nes, pc, "LDA", .IndirectX, &b)
	case 0xB1:
		pc_advance = write_instr(nes, pc, "LDA", .IndirectY, &b)


	// LDX

	case 0xA2:
		pc_advance = write_instr(nes, pc, "LDX", .Immediate, &b)
	case 0xA6:
		pc_advance = write_instr(nes, pc, "LDX", .ZeroPage, &b)
	case 0xB6:
		pc_advance = write_instr(nes, pc, "LDX", .ZeroPageY, &b)
	case 0xAE:
		pc_advance = write_instr(nes, pc, "LDX", .Absolute, &b)
	case 0xBE:
		pc_advance = write_instr(nes, pc, "LDX", .AbsoluteY, &b)

	// LDY

	case 0xA0:
		pc_advance = write_instr(nes, pc, "LDY", .Immediate, &b)
	case 0xA4:
		pc_advance = write_instr(nes, pc, "LDY", .ZeroPage, &b)
	case 0xB4:
		pc_advance = write_instr(nes, pc, "LDY", .ZeroPageX, &b)
	case 0xAC:
		pc_advance = write_instr(nes, pc, "LDY", .Absolute, &b)
	case 0xBC:
		pc_advance = write_instr(nes, pc, "LDY", .AbsoluteX, &b)


	// LSR

	case 0x4A:
		pc_advance = write_instr(nes, pc, "LSR", .Accumulator, &b)
	case 0x46:
		pc_advance = write_instr(nes, pc, "LSR", .ZeroPage, &b)
	case 0x56:
		pc_advance = write_instr(nes, pc, "LSR", .ZeroPageX, &b)
	case 0x4E:
		pc_advance = write_instr(nes, pc, "LSR", .Absolute, &b)
	case 0x5E:
		pc_advance = write_instr(nes, pc, "LSR", .AbsoluteX, &b)


	// NOP

	case 0xEA:
		pc_advance = write_instr(nes, pc, "NOP", .Implicit, &b)

	// ORA

	case 0x09:
		pc_advance = write_instr(nes, pc, "ORA", .Immediate, &b)
	case 0x05:
		pc_advance = write_instr(nes, pc, "ORA", .ZeroPage, &b)
	case 0x15:
		pc_advance = write_instr(nes, pc, "ORA", .ZeroPageX, &b)
	case 0x0D:
		pc_advance = write_instr(nes, pc, "ORA", .Absolute, &b)
	case 0x1D:
		pc_advance = write_instr(nes, pc, "ORA", .AbsoluteX, &b)
	case 0x19:
		pc_advance = write_instr(nes, pc, "ORA", .AbsoluteY, &b)
	case 0x01:
		pc_advance = write_instr(nes, pc, "ORA", .IndirectX, &b)
	case 0x11:
		pc_advance = write_instr(nes, pc, "ORA", .IndirectY, &b)

	// PHA

	case 0x48:
		pc_advance = write_instr(nes, pc, "PHA", .Implicit, &b)

	// PHP

	case 0x08:
		pc_advance = write_instr(nes, pc, "PHP", .Implicit, &b)


	// PLA

	case 0x68:
		pc_advance = write_instr(nes, pc, "PLA", .Implicit, &b)

	// PLP
	case 0x28:
		pc_advance = write_instr(nes, pc, "PLP", .Implicit, &b)

	// ROL

	case 0x2A:
		pc_advance = write_instr(nes, pc, "ROL", .Accumulator, &b)
	case 0x26:
		pc_advance = write_instr(nes, pc, "ROL", .ZeroPage, &b)
	case 0x36:
		pc_advance = write_instr(nes, pc, "ROL", .ZeroPageX, &b)
	case 0x2E:
		pc_advance = write_instr(nes, pc, "ROL", .Absolute, &b)
	case 0x3E:
		pc_advance = write_instr(nes, pc, "ROL", .AbsoluteX, &b)

	// ROR

	case 0x6A:
		pc_advance = write_instr(nes, pc, "ROR", .Accumulator, &b)
	case 0x66:
		pc_advance = write_instr(nes, pc, "ROR", .ZeroPage, &b)
	case 0x76:
		pc_advance = write_instr(nes, pc, "ROR", .ZeroPageX, &b)
	case 0x6E:
		pc_advance = write_instr(nes, pc, "ROR", .Absolute, &b)
	case 0x7E:
		pc_advance = write_instr(nes, pc, "ROR", .AbsoluteX, &b)


	// RTI

	case 0x40:
		pc_advance = write_instr(nes, pc, "RTI", .Implicit, &b)

	// RTS

	case 0x60:
		pc_advance = write_instr(nes, pc, "RTS", .Implicit, &b)

	// SBC

	case 0xE9:
		pc_advance = write_instr(nes, pc, "SBC", .Immediate, &b)
	case 0xE5:
		pc_advance = write_instr(nes, pc, "SBC", .ZeroPage, &b)
	case 0xF5:
		pc_advance = write_instr(nes, pc, "SBC", .ZeroPageX, &b)
	case 0xED:
		pc_advance = write_instr(nes, pc, "SBC", .Absolute, &b)
	case 0xFD:
		pc_advance = write_instr(nes, pc, "SBC", .AbsoluteX, &b)
	case 0xF9:
		pc_advance = write_instr(nes, pc, "SBC", .AbsoluteY, &b)
	case 0xE1:
		pc_advance = write_instr(nes, pc, "SBC", .IndirectX, &b)
	case 0xF1:
		pc_advance = write_instr(nes, pc, "SBC", .IndirectY, &b)


	// SEC

	case 0x38:
		pc_advance = write_instr(nes, pc, "SEC", .Implicit, &b)

	// SED

	case 0xF8:
		pc_advance = write_instr(nes, pc, "SED", .Implicit, &b)

	// SEI

	case 0x78:
		pc_advance = write_instr(nes, pc, "SEI", .Implicit, &b)

	// STA

	case 0x85:
		pc_advance = write_instr(nes, pc, "STA", .ZeroPage, &b)
	case 0x95:
		pc_advance = write_instr(nes, pc, "STA", .ZeroPageX, &b)
	case 0x8D:
		pc_advance = write_instr(nes, pc, "STA", .Absolute, &b)
	case 0x9D:
		pc_advance = write_instr(nes, pc, "STA", .AbsoluteX, &b)
	case 0x99:
		pc_advance = write_instr(nes, pc, "STA", .AbsoluteY, &b)
	case 0x81:
		pc_advance = write_instr(nes, pc, "STA", .IndirectX, &b)
	case 0x91:
		pc_advance = write_instr(nes, pc, "STA", .IndirectY, &b)

	// STX

	case 0x86:
		pc_advance = write_instr(nes, pc, "STX", .ZeroPage, &b)
	case 0x96:
		pc_advance = write_instr(nes, pc, "STX", .ZeroPageY, &b)
	case 0x8E:
		pc_advance = write_instr(nes, pc, "STX", .Absolute, &b)

	// STY

	case 0x84:
		pc_advance = write_instr(nes, pc, "STY", .ZeroPage, &b)
	case 0x94:
		pc_advance = write_instr(nes, pc, "STY", .ZeroPageX, &b)
	case 0x8C:
		pc_advance = write_instr(nes, pc, "STY", .Absolute, &b)


	// TAX

	case 0xAA:
		pc_advance = write_instr(nes, pc, "TAX", .Implicit, &b)

	// TAY
	case 0xA8:
		pc_advance = write_instr(nes, pc, "TAY", .Implicit, &b)

	// TSX
	case 0xBA:
		pc_advance = write_instr(nes, pc, "TSX", .Implicit, &b)

	// TXA
	case 0x8A:
		pc_advance = write_instr(nes, pc, "TXA", .Implicit, &b)

	// TXS
	case 0x9A:
		pc_advance = write_instr(nes, pc, "TXS", .Implicit, &b)

	// TYA
	case 0x98:
		pc_advance = write_instr(nes, pc, "TYA", .Implicit, &b)


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
		pc_advance = write_instr(nes, pc, "ASO", .Absolute, &b)
	case 0x1F:
		pc_advance = write_instr(nes, pc, "ASO", .AbsoluteX, &b)
	case 0x1B:
		pc_advance = write_instr(nes, pc, "ASO", .AbsoluteY, &b)
	case 0x07:
		pc_advance = write_instr(nes, pc, "ASO", .ZeroPage, &b)
	case 0x17:
		pc_advance = write_instr(nes, pc, "ASO", .ZeroPageX, &b)
	case 0x03:
		pc_advance = write_instr(nes, pc, "ASO", .IndirectX, &b)
	case 0x13:
		pc_advance = write_instr(nes, pc, "ASO", .IndirectY, &b)

	// RLA

	case 0x2F:
		pc_advance = write_instr(nes, pc, "RLA", .Absolute, &b)
	case 0x3F:
		pc_advance = write_instr(nes, pc, "RLA", .AbsoluteX, &b)
	case 0x3B:
		pc_advance = write_instr(nes, pc, "RLA", .AbsoluteY, &b)
	case 0x27:
		pc_advance = write_instr(nes, pc, "RLA", .ZeroPage, &b)
	case 0x37:
		pc_advance = write_instr(nes, pc, "RLA", .ZeroPageX, &b)
	case 0x23:
		pc_advance = write_instr(nes, pc, "RLA", .IndirectX, &b)
	case 0x33:
		pc_advance = write_instr(nes, pc, "RLA", .IndirectY, &b)

	// LSE
	case 0x4F:
		pc_advance = write_instr(nes, pc, "LSE", .Absolute, &b)
	case 0x5F:
		pc_advance = write_instr(nes, pc, "LSE", .AbsoluteX, &b)
	case 0x5B:
		pc_advance = write_instr(nes, pc, "LSE", .AbsoluteY, &b)
	case 0x47:
		pc_advance = write_instr(nes, pc, "LSE", .ZeroPage, &b)
	case 0x57:
		pc_advance = write_instr(nes, pc, "LSE", .ZeroPageX, &b)
	case 0x43:
		pc_advance = write_instr(nes, pc, "LSE", .IndirectX, &b)
	case 0x53:
		pc_advance = write_instr(nes, pc, "LSE", .IndirectY, &b)

	// RRA

	case 0x6F:
		pc_advance = write_instr(nes, pc, "RRA", .Absolute, &b)
	case 0x7F:
		pc_advance = write_instr(nes, pc, "RRA", .AbsoluteX, &b)
	case 0x7B:
		pc_advance = write_instr(nes, pc, "RRA", .AbsoluteY, &b)
	case 0x67:
		pc_advance = write_instr(nes, pc, "RRA", .ZeroPage, &b)
	case 0x77:
		pc_advance = write_instr(nes, pc, "RRA", .ZeroPageX, &b)
	case 0x63:
		pc_advance = write_instr(nes, pc, "RRA", .IndirectX, &b)
	case 0x73:
		pc_advance = write_instr(nes, pc, "RRA", .IndirectY, &b)

	// AXS

	case 0x8F:
		pc_advance = write_instr(nes, pc, "AXS", .Absolute, &b)
	case 0x87:
		pc_advance = write_instr(nes, pc, "AXS", .ZeroPage, &b)
	case 0x97:
		pc_advance = write_instr(nes, pc, "AXS", .ZeroPageY, &b)
	case 0x83:
		pc_advance = write_instr(nes, pc, "AXS", .IndirectX, &b)


	// LAX

	case 0xAF:
		pc_advance = write_instr(nes, pc, "LAX", .Absolute, &b)
	case 0xBF:
		pc_advance = write_instr(nes, pc, "LAX", .AbsoluteY, &b)
	case 0xA7:
		pc_advance = write_instr(nes, pc, "LAX", .ZeroPage, &b)
	case 0xB7:
		pc_advance = write_instr(nes, pc, "LAX", .ZeroPageY, &b)
	case 0xA3:
		pc_advance = write_instr(nes, pc, "LAX", .IndirectX, &b)
	case 0xB3:
		pc_advance = write_instr(nes, pc, "LAX", .IndirectY, &b)

	// DCM

	case 0xCF:
		pc_advance = write_instr(nes, pc, "DCM", .Absolute, &b)
	case 0xDF:
		pc_advance = write_instr(nes, pc, "DCM", .AbsoluteX, &b)
	case 0xDB:
		pc_advance = write_instr(nes, pc, "DCM", .AbsoluteY, &b)
	case 0xC7:
		pc_advance = write_instr(nes, pc, "DCM", .ZeroPage, &b)
	case 0xD7:
		pc_advance = write_instr(nes, pc, "DCM", .ZeroPageX, &b)
	case 0xC3:
		pc_advance = write_instr(nes, pc, "DCM", .IndirectX, &b)
	case 0xD3:
		pc_advance = write_instr(nes, pc, "DCM", .IndirectY, &b)

	// INS

	case 0xEF:
		pc_advance = write_instr(nes, pc, "INS", .Absolute, &b)
	case 0xFF:
		pc_advance = write_instr(nes, pc, "INS", .AbsoluteX, &b)
	case 0xFB:
		pc_advance = write_instr(nes, pc, "INS", .AbsoluteY, &b)
	case 0xE7:
		pc_advance = write_instr(nes, pc, "INS", .ZeroPage, &b)
	case 0xF7:
		pc_advance = write_instr(nes, pc, "INS", .ZeroPageX, &b)
	case 0xE3:
		pc_advance = write_instr(nes, pc, "INS", .IndirectX, &b)
	case 0xF3:
		pc_advance = write_instr(nes, pc, "INS", .IndirectY, &b)

	// ALR

	case 0x4B:
		pc_advance = write_instr(nes, pc, "ALR", .Immediate, &b)

	// ARR

	case 0x6B:
		pc_advance = write_instr(nes, pc, "ARR", .Immediate, &b)

	// XAA

	case 0x8B:
		pc_advance = write_instr(nes, pc, "XAA", .Immediate, &b)

	// OAL

	case 0xAB:
		pc_advance = write_instr(nes, pc, "OAL", .Immediate, &b)

	// SAX
	case 0xCB:
		pc_advance = write_instr(nes, pc, "SAX", .Immediate, &b)

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
		pc_advance = write_instr(nes, pc, "NOP*", .Implicit, &b)

	case 0x80:
		fallthrough
	case 0x82:
		fallthrough
	case 0x89:
		fallthrough
	case 0xC2:
		fallthrough
	case 0xE2:
		pc_advance = write_instr(nes, pc, "NOP*", .Immediate, &b)

	case 0x04:
		fallthrough
	case 0x44:
		fallthrough
	case 0x64:
		pc_advance = write_instr(nes, pc, "NOP*", .ZeroPage, &b)

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
		pc_advance = write_instr(nes, pc, "NOP*", .ZeroPageX, &b)

	case 0x0C:
		pc_advance = write_instr(nes, pc, "NOP*", .Absolute, &b)

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
		pc_advance = write_instr(nes, pc, "NOP*", .AbsoluteX, &b)

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
		pc_advance = write_instr(nes, pc, "HLT", .Implicit, &b)

	// TAS

	case 0x9B:
		pc_advance = write_instr(nes, pc, "TAS", .AbsoluteY, &b)

	// SAY

	case 0x9C:
		pc_advance = write_instr(nes, pc, "SAY", .AbsoluteX, &b)

	// XAS

	case 0x9E:
		pc_advance = write_instr(nes, pc, "XAS", .AbsoluteY, &b)

	// AXA

	case 0x9F:
		pc_advance = write_instr(nes, pc, "AXA", .AbsoluteY, &b)
	case 0x93:
		pc_advance = write_instr(nes, pc, "AXA", .IndirectY, &b)

	// ANC
	case 0x2B:
		fallthrough
	case 0x0B:
		pc_advance = write_instr(nes, pc, "ANC", .Immediate, &b)


	// LAS
	case 0xBB:
		pc_advance = write_instr(nes, pc, "LAS", .IndirectY, &b)

	// OPCODE EB
	case 0xEB:
		pc_advance = write_instr(nes, pc, "SBC", .Immediate, &b)

	case:
		was_written = false
		instr_name := ""
	}

	// if was_written {
	// 	fmt.println(strings.to_string(b))
	// }

	next_pc = pc + pc_advance

	return
}
