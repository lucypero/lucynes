package main

import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:mem"
import "core:strings"
import rl "vendor:raylib"

scale_factor :: 5

nes_width :: 256
nes_height :: 240

// screen_width :: nes_width * scale_factor
// screen_height :: nes_height * scale_factor // ntsc might only show 224 scan lines

debug_width :: 300
screen_width :: nes_width * scale_factor + debug_width
screen_height :: nes_height * scale_factor

framebuffer_width :: nes_width
framebuffer_height :: nes_height

target_fps :: 60

// the CPU clockrate for NTSC systems is 1789773 Hz
//    https://www.nesdev.org/wiki/Cycle_reference_chart


// palette_file :: "palettes/ntscpalette.pal"
palette_file :: "palettes/Composite_wiki.pal"

/// FULLY WORKING GAMES:

// rom_in_nes :: "roms/SuperMarioBros.nes"
rom_in_nes :: "roms/Mega Man.nes"
// rom_in_nes :: "roms/Contra.nes"
// rom_in_nes :: "roms/Duck Tales.nes"
// rom_in_nes :: "roms/Castlevania.nes"
// rom_in_nes :: "roms/Metal Gear.nes"
// rom_in_nes :: "roms/IceClimber.nes"
// rom_in_nes :: "roms/DonkeyKong.nes"
// rom_in_nes :: "roms/Kung Fu.nes"
// rom_in_nes :: "roms/Bomberman.nes"

/// NON-WORKING GAMES: 

// rom_in_nes :: "roms/Adventures of Lolo II , The.nes"
// rom_in_nes :: "roms/Ms. Pac Man (Tengen).nes"
// rom_in_nes :: "roms/Spelunker.nes"
// rom_in_nes :: "roms/Silver Surfer.nes"


/// TEST ROMS:

// rom_in_nes :: "tests/cpu_timing_test6/cpu_timing_test.nes"
// rom_in_nes :: "tests/branch_timing_tests/1.Branch_Basics.nes"
// rom_in_nes :: "tests/full_nes_palette.nes"
// rom_in_nes :: "tests/nmi_sync/demo_pal.nes"
// rom_in_nes :: "tests/240pee.nes"
// rom_in_nes :: "tests/full_palette.nes"
// rom_in_nes :: "tests/color_test.nes"
// rom_in_nes :: "nestest/nestest.nes"

// NMI tests

// rom_in_nes :: "tests/nmi_sync/demo_ntsc.nes"
// rom_in_nes :: "tests/cpu_interrupts_v2/cpu_interrupts.nes"
// rom_in_nes :: "tests/cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes"
// rom_in_nes :: "tests/cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes"


// Audio tests

// rom_in_nes :: "tests/audio/clip_5b_nrom.nes"
// rom_in_nes :: "tests/audio/sweep_5b_nrom.nes"

PixelGrid :: struct {
	pixels: []rl.Color,
	width:  int,
	height: int,
}

send_samples := true

pixel_grid : PixelGrid

window_main :: proc() {

	rl.SetTraceLogLevel(.ERROR)
	rl.InitWindow(screen_width, screen_height, "lucynes")
	rl.SetWindowPosition(20, 50)
	rl.SetTargetFPS(target_fps)

	pixels := make([]rl.Color, framebuffer_width * framebuffer_height)

	checkedIm := rl.Image {
		data    = raw_data(pixels),
		width   = framebuffer_width,
		height  = framebuffer_height,
		format  = .UNCOMPRESSED_R8G8B8A8,
		mipmaps = 1,
	}

	checked := rl.LoadTextureFromImage(checkedIm)

	pixel_grid = PixelGrid {
		pixels = pixels,
		width  = framebuffer_width,
		height = framebuffer_height,
	}

	// rl.UnloadImage(checkedIm) // Unload CPU (RAM) image data (pixels)

	// initting audio
	audio_demo: AudioDemo
	audio_demo_init(&audio_demo)

	run_nestest_test()

	ok: bool
	palette, ok = get_palette(palette_file)
	if !ok {
		fmt.eprintln("could not get palette")
		os.exit(1)
	}

	// initializing nes
	nes: NES
	nes_reset(&nes, rom_in_nes)

	paused := false

	for !rl.WindowShouldClose() {

		rl.BeginDrawing()

		rl.ClearBackground(rl.BLACK)

		// clear_pixels(pixels, rl.BLACK)

		// doing input

		if rl.IsKeyDown(.ENTER) {
			// reset nes
			nes_reset(&nes, rom_in_nes)
		}

		if rl.IsKeyPressed(.P) {
			// send_samples = !send_samples
			paused = !paused
		}

		if rl.IsKeyPressed(.F1) {
			// save

			if len(save_states) > 0 {
				delete(save_states[0].chr_rom)
				delete(save_states[0].prg_rom)
				delete(save_states[0].prg_ram)

				delete(save_states)
			}

			save_states = make([]NES, 1)
			save_states[0] = nes

			save_states[0].chr_rom = make([]u8, len(nes.chr_rom))
			copy(save_states[0].chr_rom, nes.chr_rom)

			save_states[0].prg_rom = make([]u8, len(nes.prg_rom))
			copy(save_states[0].prg_rom, nes.prg_rom)

			save_states[0].prg_ram = make([]u8, len(nes.prg_ram))
			copy(save_states[0].prg_ram, nes.prg_ram)
		}

		if rl.IsKeyPressed(.F4) {
			// load
			// free_all(mem.tracking_allocator(&nes_allocator))

			if len(save_states) > 0 {
				nes = save_states[0]
			}
		}

		port_0_input: u8
		port_1_input: u8
		fill_input_port(&port_0_input)

		// run nes till vblank
		if !paused {
			tick_nes_till_vblank(&nes, port_0_input, port_1_input, &pixel_grid)
		}

		// here you modify the pixels (draw the frame)
		// draw_frame(nes, &pixel_grid)

		rl.UpdateTexture(checked, raw_data(pixels))
		rl.DrawTextureEx(checked, {0, 0}, 0, scale_factor, rl.WHITE)
		draw_debugger(nes)

		rl.EndDrawing()
	}

	print_faulty_ops(&nes)
}

draw_debugger :: proc(nes : NES) {



	the_indx := nes.instr_pointer

	for i in 0..<20 {

		pos := 20 - i

		c_str := strings.clone_to_cstring(nes.instr_history[the_indx])
		rl.DrawText(c_str, nes_width * scale_factor + 1, 1 + i32(pos) * 21, 20, rl.WHITE)
		free(&c_str)

		the_indx -= 1

		if the_indx < 0 {
			the_indx = 19 
		}
	}

	// b, next_pc := print_instr(nes)
	// fmt.println(strings.to_string(b))
	
	// the_str := strings.to_string(b)

	// c_str := strings.clone_to_cstring(the_str)
	// rl.DrawText(c_str, nes_width * scale_factor + 1, 20, 25, rl.WHITE)
	// rl.DrawText("hello how are u", nes_width * scale_factor + 1, 100, 25, rl.WHITE)

	// free(&b)
}

clear_pixels :: proc(pixels: []rl.Color, color: rl.Color) {
	for p, i in pixels {
		pixels[i] = color
	}
}

fill_input_port :: proc(port_input: ^u8) {

	// A button
	if rl.IsKeyDown(.H) {
		port_input^ |= 0b10000000
	}

	// B button
	if rl.IsKeyDown(.J) {
		port_input^ |= 0b01000000
	}

	// Select button
	if rl.IsKeyDown(.Y) {
		port_input^ |= 0b00100000
	}

	// Start button
	if rl.IsKeyDown(.U) {
		port_input^ |= 0b00010000
	}

	// Up button
	if rl.IsKeyDown(.W) {
		port_input^ |= 0b00001000
	}

	// Down button
	if rl.IsKeyDown(.S) {
		port_input^ |= 0b00000100
	}

	// Left button
	if rl.IsKeyDown(.A) {
		port_input^ |= 0b00000010
	}

	// Right button
	if rl.IsKeyDown(.D) {
		port_input^ |= 0b00000001
	}
}

color_map_from_nes_to_real :: proc(color_in_nes: u8) -> rl.Color {
	return palette[color_in_nes & 0x3F]
}
