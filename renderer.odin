package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:mem"
import "core:strings"
import "core:strconv"
import "core:slice"
import rl "vendor:raylib"

scale_factor :: 4

nes_width :: 256
nes_height :: 240

// screen_width :: nes_width * scale_factor
// screen_height :: nes_height * scale_factor // ntsc might only show 224 scan lines

when draw_debugger_view {
	debug_width :: 400
} else {
	debug_width :: 0
}

screen_width :: nes_width * scale_factor + debug_width
screen_height :: nes_height * scale_factor

framebuffer_width :: nes_width
framebuffer_height :: nes_height

target_fps :: 60

// the CPU clockrate for NTSC systems is 1789773 Hz
//    https://www.nesdev.org/wiki/Cycle_reference_chart

// palette_file :: "palettes/ntscpalette.pal"
palette_file :: "palettes/Composite_wiki.pal"

// enable_shader :: false
enable_shader :: true
shader_file :: "shaders/easymode.fs"
// shader_file :: "shaders/scanlines.fs"

PixelGrid :: struct {
	pixels: []rl.Color,
	width:  int,
	height: int,
}

send_samples := true

pixel_grid: PixelGrid

font: rl.Font
font_size :: 30

AppState :: struct {
	paused:              bool, // Is NES emulation paused?
	in_menu:             bool, // Showing HUD?

	// Menu state
	item_selected:       int,
	item_count:          int,
	break_on_nmi:        bool,
	break_on_game_start: bool, // not used
	break_on_given_pc:   bool,
	given_pc_b:          strings.Builder,
	given_pc:            u16,
}

app_state: AppState

clear_color := rl.Color{36, 41, 46, 255}

SaveStateOrder :: enum {
	None,
	Save,
	Load,
}

savestate_order: SaveStateOrder = .None

window_main :: proc() {

	app_state = {}
	app_state.given_pc_b = strings.builder_make_len_cap(0, 10)
	app_state.item_count = 3

	rl.SetTraceLogLevel(.ERROR)
	rl.InitWindow(screen_width, screen_height, "lucynes")
	rl.SetWindowPosition(20, 50)
	rl.SetTargetFPS(target_fps)

	font = rl.LoadFontEx("fonts/JetBrainsMono-Bold.ttf", font_size, nil, 250)

	pixels := make([]rl.Color, framebuffer_width * framebuffer_height)

	nes_image := rl.Image {
		data    = raw_data(pixels),
		width   = framebuffer_width,
		height  = framebuffer_height,
		format  = .UNCOMPRESSED_R8G8B8A8,
		mipmaps = 1,
	}

	nes_texture := rl.LoadTextureFromImage(nes_image)

	pixel_grid = PixelGrid {
		pixels = pixels,
		width  = framebuffer_width,
		height = framebuffer_height,
	}

	scale_factor_f := f32(scale_factor)
	x_offset: f32 = 0

	// rl.UnloadImage(checkedIm) // Unload CPU (RAM) image data (pixels)

	// initting audio
	audio_demo: AudioDemo
	audio_demo_init(&audio_demo)

	ok: bool
	palette, ok = get_palette(palette_file)
	if !ok {
		fmt.eprintln("could not get palette")
		os.exit(1)
	}

	run_nestest_test()


	// shader

	when enable_shader {
		shader: rl.Shader = rl.LoadShader(nil, shader_file)
	}

	// u gotta set the values...
	// rl.SetShaderValue()

	the_rom: string = rom_in_nes

	if len(os.args) > 1 {
		// a := [?]string { "roms/", os.args[1]}
		// strrr := strings.concatenate(a[:])
		the_rom = os.args[1]
	}

	// initializing nes
	nes: NES
	nes_reset(&nes, the_rom)

	paused := false

	for !rl.WindowShouldClose() {

		rl.BeginDrawing()

		rl.ClearBackground(clear_color)

		// clear_pixels(pixels, rl.BLACK)

		// doing input
		if rl.IsKeyDown(.ENTER) {
			// reset nes
			nes_reset(&nes, the_rom)
		}

		tick_force := false

		if rl.IsKeyPressed(.P) {
			paused = !paused

			if !paused {
				// if unpausing, advance one instruction no matter what
				tick_force = true
			}

		}

		if rl.IsKeyPressed(.F) {
			rl.ToggleBorderlessWindowed()
			w := rl.GetScreenWidth()
			h := rl.GetScreenHeight()
			scale_factor_f = f32(h) / f32(framebuffer_height)

			nes_w := framebuffer_width * scale_factor_f
			x_offset = (f32(w) / 2) - (f32(nes_w) / 2)
		}

		if rl.IsKeyPressed(.F10) {
			// run one instruction
			if paused {
				instruction_tick(&nes, 0, 0, &pixel_grid)
				reset_debugging_vars(&nes)
			}
		}

		if rl.IsKeyPressed(.F1) {
			// save
			savestate_order = .Save
		}

		if rl.IsKeyPressed(.F4) {
			// load
			// free_all(mem.tracking_allocator(&nes_allocator))

			// if len(save_states) > 0 {
				savestate_order = .Load
			// }
		}

		port_0_input: u8
		port_1_input: u8
		fill_input_port(&port_0_input)

		// run nes till vblank
		if !paused {
			broke := tick_nes_till_vblank(&nes, tick_force, port_0_input, port_1_input, &pixel_grid)
			if broke {
				paused = true
			}
		}

		// here you modify the pixels (draw the frame)
		// draw_frame(nes, &pixel_grid)

		rl.UpdateTexture(nes_texture, raw_data(pixels))
		when enable_shader {
			rl.BeginShaderMode(shader)
		}
		rl.DrawTextureEx(nes_texture, {x_offset, 0}, 0, scale_factor_f, rl.WHITE)
		when enable_shader {
			rl.EndShaderMode()
		}
		draw_debugger(nes, paused)

		if rl.IsKeyPressed(.M) {
			// draw GUI
			app_state.in_menu = !app_state.in_menu
		}

		if app_state.in_menu {
			draw_menu()
		}

		when draw_debugger_view && draw_pattern_tables_view {
			draw_pattern_tables(&nes)
		}

		rl.EndDrawing()
		free_all(context.temp_allocator)
	}

	print_faulty_ops(&nes)
}

is_key_hex :: proc(key: rune) -> bool {
	switch key {
	case '0' ..= '9':
		return true
	case 'a' ..= 'f':
		return true
	}
	return false
}

draw_menu :: proc() {

	context.allocator = context.temp_allocator

	// Handle menu input

	if rl.IsKeyPressed(.UP) {
		app_state.item_selected -= 1
		if app_state.item_selected < 0 {
			app_state.item_selected = app_state.item_count - 1
		}
	}

	if rl.IsKeyPressed(.DOWN) {
		app_state.item_selected += 1
		if app_state.item_selected >= app_state.item_count {
			app_state.item_selected = 0
		}
	}

	if rl.IsKeyPressed(.SPACE) {
		switch app_state.item_selected {
		case 0:
			app_state.break_on_nmi = !app_state.break_on_nmi
		case 1:
			app_state.break_on_game_start = !app_state.break_on_game_start
		case 2:
			app_state.break_on_given_pc = !app_state.break_on_given_pc
		}
	}

	if app_state.item_selected == 2 {
		// handle_pc_input()
		key := rl.GetCharPressed()

		if is_key_hex(key) {
			if strings.builder_len(app_state.given_pc_b) >= 4 {
				temp := strings.to_string(app_state.given_pc_b)[1:]
				strings.builder_reset(&app_state.given_pc_b)
				strings.write_string(&app_state.given_pc_b, temp)
			}

			strings.write_rune(&app_state.given_pc_b, key)

			// update pc
			the_str := strings.to_string(app_state.given_pc_b)
			the_n, ok := strconv.parse_uint(the_str, 16)
			app_state.given_pc = u16(the_n)
		}
	}

	// Handle menu drawing

	menu_x_start: f32 = 3
	current_color := debug_text_color

	ypos: f32 = 1

	menu_bg := clear_color
	menu_bg.a = 220

	// draw menu
	rl.DrawRectangle(0, 0, nes_width * scale_factor, 300, menu_bg)

	if app_state.item_selected == 0 {
		current_color = debug_text_active_color
	} else {
		current_color = debug_text_color
	}

	b := strings.builder_make_len_cap(0, 40)

	for i in 0 ..< app_state.item_count {
		draw_menu_item(&b, i, menu_x_start, ypos)
		ypos += f32(vertical_spacing)
	}
}

draw_menu_item :: proc(b: ^strings.Builder, item_n: int, menu_x_start, ypos: f32) {

	strings.builder_reset(b)
	strings.write_string(b, "[")

	// is it ticked
	is_ticked := false

	switch item_n {
	case 0:
		is_ticked = app_state.break_on_nmi
	case 1:
		is_ticked = app_state.break_on_game_start
	case 2:
		is_ticked = app_state.break_on_given_pc
	}

	if is_ticked {
		strings.write_string(b, "X")
	} else {
		strings.write_string(b, " ")
	}

	strings.write_string(b, "] - ")

	switch item_n {
	case 0:
		strings.write_string(b, "Break on NMI")
	case 1:
		strings.write_string(b, "Break on Game Start")
	case 2:
		strings.write_string(b, "Break on PC: ")
		the_str := strings.to_string(app_state.given_pc_b)
		the_str = strings.to_upper(the_str)
		strings.write_string(b, the_str)
	}

	current_color := debug_text_color

	if app_state.item_selected == item_n {
		current_color = debug_text_active_color
	}

	the_str := strings.to_string(b^)
	the_cstr := strings.clone_to_cstring(the_str)

	rl.DrawTextEx(font, the_cstr, {menu_x_start, ypos}, f32(font.baseSize), 0, current_color)
}

clear_pixels :: proc(pixels: []rl.Color, color: rl.Color) {
	for p, i in pixels {
		pixels[i] = color
	}
}

fill_input_port :: proc(port_input: ^u8) {

	// A button
	if rl.IsKeyDown(.H) || rl.IsGamepadButtonDown(0, .RIGHT_FACE_DOWN) {
		port_input^ |= 0b10000000
	}

	// B button
	if rl.IsKeyDown(.J) || rl.IsGamepadButtonDown(0, .RIGHT_FACE_LEFT) {
		port_input^ |= 0b01000000
	}

	// Select button
	if rl.IsKeyDown(.Y) || rl.IsGamepadButtonDown(0, .MIDDLE_LEFT) {
		port_input^ |= 0b00100000
	}

	// Start button
	if rl.IsKeyDown(.U) || rl.IsGamepadButtonDown(0, .MIDDLE_RIGHT) {
		port_input^ |= 0b00010000
	}

	// Up button
	if rl.IsKeyDown(.W) || rl.IsGamepadButtonDown(0, .LEFT_FACE_UP) {
		port_input^ |= 0b00001000
	}

	// Down button
	if rl.IsKeyDown(.S) || rl.IsGamepadButtonDown(0, .LEFT_FACE_DOWN) {
		port_input^ |= 0b00000100
	}

	// Left button
	if rl.IsKeyDown(.A) || rl.IsGamepadButtonDown(0, .LEFT_FACE_LEFT) {
		port_input^ |= 0b00000010
	}

	// Right button
	if rl.IsKeyDown(.D) || rl.IsGamepadButtonDown(0, .LEFT_FACE_RIGHT) {
		port_input^ |= 0b00000001
	}
}

color_map_from_nes_to_real :: proc(color_in_nes: u8) -> rl.Color {
	return palette[color_in_nes & 0x3F]
}


// Render pattern table
// u did it in 8fb1aefb1a373b00b6eb223f73c22f00a59e61cb

draw_pattern_tables :: proc(nes: ^NES) {

	// draw some pattern table tiles


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

	// how many tiles we gon draw

	tiles_per_row := 16
	padding := 0

	// looping tile
	for i in 0 ..< 256 * 2 {

		tile: [8 * 8]int // pixels of tiles (contains [0-3])

		// first bit plane
		for t in 0 ..< 16 {

			addr := u16((i * 16) + t)
			// fmt.printfln("reading ppu addr %X", addr)
			row := nes.chr_mem[(i * 16) + t]
			// row := ppu_read(nes, addr)

			// looping row of pixels
			for p in 0 ..< 8 {
				is_on := (row >> uint(p)) & 0b00000001

				if is_on != 0 {

					// if we're on first bit plane, add one
					if (t < 8) {
						tile[(t * 8) + (7 - p)] += 1
					} else {
						// if we're on second bit plane, add two
						tile[((t - 8) * 8) + (7 - p)] += 2
					}
				}
			}
		}

		row_slot := i % tiles_per_row
		x_pos := (8 + padding) * row_slot + padding
		col_slot := i / tiles_per_row
		y_pos := (8 + padding) * col_slot + padding

		if i > 255 {
			y_pos -= (8 + padding) * 16
			x_pos += (8 + padding) * 16 + padding + 16
		}

		// we gonna draw
		draw_tile(tile, x_pos, y_pos)
	}
}

draw_tile :: proc(tile: [8 * 8]int, x_pos, y_pos: int) {

	for p, i in tile {
		col: rl.Color

		switch p {
		case 0:
			col = rl.BLACK
		case 1:
			col = rl.WHITE
		case 2:
			col = rl.MAGENTA
		case 3:
			col = rl.RED
		case:
			col = rl.BLUE // we should not get this
		}

		x_add := i % 8
		y_add := i / 8

		// the_p_i := ((y_pos + y_add) * pixel_grid.width) + x_pos + x_add
		// pixel_grid.pixels[the_p_i] = col

		rl.DrawPixel(i32(x_pos + x_add) + nes_width * scale_factor + 10, i32(y_pos + y_add), col)
	}
}
