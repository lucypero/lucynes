package main
import rl "vendor:raylib"
import "core:strings"
import "core:c"

instructions_y_start :: 200

// how many previous instructions to display
prev_instructions_count :: 20

// how many future instructions to display
next_instructions_count :: 20

debug_x_start :: nes_width * scale_factor + 5
debug_text_color := rl.WHITE
debug_text_active_color := rl.SKYBLUE
vertical_spacing := font.baseSize - 5

draw_cpu_thing :: proc(nes: NES, b: ^strings.Builder, ypos: f32, name: string, thing_value: u16, draw_base_10: bool) {
	strings.builder_reset(b)
	strings.write_string(b, name)
	strings.write_string(b, ": $")
	strings.write_uint(b, uint(thing_value), 16)
	if draw_base_10 {
		strings.write_string(b, " [")
		strings.write_uint(b, uint(thing_value))
		strings.write_string(b, "]")
	}
	the_str := strings.to_string(b^)
	the_str = strings.to_upper(the_str)
	the_cstr := strings.clone_to_cstring(the_str)
	rl.DrawTextEx(font, the_cstr, {debug_x_start, ypos}, f32(font.baseSize), 0, debug_text_color)
}

draw_cpu_state :: proc(nes: NES) -> f32 {

	// Status

	ypos: f32 = 1

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
	draw_cpu_thing(nes, &b, ypos, "PC", nes.program_counter, false)
	ypos += f32(vertical_spacing)

	// A
	draw_cpu_thing(nes, &b, ypos, "A", u16(nes.accumulator), true)
	ypos += f32(vertical_spacing)

	// X
	draw_cpu_thing(nes, &b, ypos, "X", u16(nes.index_x), true)
	ypos += f32(vertical_spacing)

	// Y
	draw_cpu_thing(nes, &b, ypos, "Y", u16(nes.index_y), true)
	ypos += f32(vertical_spacing)

	// Stack P
	draw_cpu_thing(nes, &b, ypos, "Stack P", u16(nes.stack_pointer), false)
	ypos += f32(vertical_spacing)


	return ypos
}

draw_debugger :: proc(nes: NES) {

	context.allocator = context.temp_allocator
	vertical_spacing = font.baseSize - 5

	ypos: f32

	// Drawing CPU State
	ypos = draw_cpu_state(nes)

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
	the_indx := nes.instr_history.last_placed
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

		rl.DrawTextEx(
			font,
			c_str,
			{debug_x_start, ypos},
			f32(font.baseSize),
			0,
			col,
		)

		ypos += f32(vertical_spacing)
	}
}
