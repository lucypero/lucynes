package main

import "core:fmt"
import "core:os"
import rl "vendor:raylib"

scale_factor :: 3

nes_width :: 256
nes_height :: 240

// screen_width :: nes_width * scale_factor
// screen_height :: nes_height * scale_factor // ntsc might only show 224 scan lines

screen_width :: nes_width * scale_factor
screen_height :: nes_height * scale_factor

framebuffer_width :: nes_width
framebuffer_height :: nes_height

PixelGrid :: struct {
	pixels: []rl.Color,
	width:  int,
	height: int,
}

raylib_test :: proc() {

	rl.InitWindow(screen_width, screen_height, "lucynes")
	rl.SetWindowPosition(20, 50)
	rl.SetTargetFPS(60)

	// Generate a checked texture by code
	// Dynamic memory allocation to store pixels data (Color type)
	pixels := make([]rl.Color, framebuffer_width * framebuffer_height)

	// Load pixels data into an image structure and create texture
	checkedIm := rl.Image {
		data    = raw_data(pixels), // We can assign pixels directly to data
		width   = framebuffer_width,
		height  = framebuffer_height,
		format  = .UNCOMPRESSED_R8G8B8A8,
		mipmaps = 1,
	}

	checked := rl.LoadTextureFromImage(checkedIm)

	pixel_grid := PixelGrid {
		pixels = pixels,
		width  = framebuffer_width,
		height = framebuffer_height,
	}

	// rl.UnloadImage(checkedIm) // Unload CPU (RAM) image data (pixels)

	run_nestest_test()

	// initializing nes
	nes: NES

	// res := load_rom_from_file(&nes, "roms/DonkeyKong.nes")
	// res := load_rom_from_file(&nes, "roms/SuperMarioBros.nes")
	res := load_rom_from_file(&nes, "roms/Kung Fu.nes")
	// res := load_rom_from_file(&nes, "roms/Bomberman.nes")
	// res := load_rom_from_file(&nes, "roms/PacMan.nes")
	// res := load_rom_from_file(&nes, "roms/IceClimber.nes")
	// res := load_rom_from_file(&nes, "nestest/nestest.nes")

	if !res {
		fmt.eprintln("could not load rom")
		os.exit(1)
	}

	// initializing nes

	// do this in a reset too

	nes_init(&nes)

	for !rl.WindowShouldClose() {

		rl.BeginDrawing()

		// rl.ClearBackground(rl.RAYWHITE)

		clear_pixels(pixels, rl.BLACK)

		// doing input

		port_0_input: u8
		port_1_input: u8
		fill_input_port(&port_0_input)

		// run nes till vblank
		tick_nes_till_vblank(&nes, port_0_input, port_1_input, &pixel_grid)

		// here you modify the pixels (draw the frame)
		// draw_frame(nes, &pixel_grid)

		rl.UpdateTexture(checked, raw_data(pixels))
		rl.DrawTextureEx(checked, {0, 0}, 0, scale_factor, rl.WHITE)

		rl.EndDrawing()
	}

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


// debug thing. it just displays the 2 pattern tables on the screen
draw_patterntables :: proc(nes: NES, pixel_grid: ^PixelGrid) {

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
	padding := 1

	// looping tile
	for i in 0 ..< 256 * 2 {

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
		draw_pattern_tile(pixel_grid, tile, x_pos, y_pos)
	}
}

draw_nametable :: proc(nes: NES, pixel_grid: ^PixelGrid) {

	// nametables:


	// 1024 byte area of memory
	// each byte controls a 8x8 pixel tile
	// contains 30 rows of 32 tiles (32 x 30)
	// the 64 remaining bytes are used by each nametable's attribute table


	// nametable 1

	// $2000 - $2000 + 1 KiB
	// $2000 - $23C0 (rest is 64 bytes of attribute table)

	for row in 0 ..< 30 {
		for tile_i in 0 ..< 32 {
			// get byte

			the_index := (row * 32) + tile_i
			nametable_byte := int(nes.ppu_memory[the_index])

			// what attribute byte is being used for this nametable byte?

			// attribute table of first nametable is at $23C0 - $2423
			// there's one attribute entry per 4x4 tile blocks
			attr_x := tile_i / 4
			attr_y := row / 4
			attr_indx := (attr_y * 8) + attr_x

			attr_entry := nes.ppu_memory[30 * 32 + attr_indx]

			// which quadrant are you? (you are in a tile out of 4x4 tiles)

			quadrant: uint

			switch tile_i % 4 {
			case 0, 1:
				// quadrant 0 or 2
				switch row % 4 {
				case 0, 1:
					quadrant = 0
				case 2, 3:
					quadrant = 2
				}
			case 2, 3:
				// quadrant 1 or 3
				switch row % 4 {
				case 0, 1:
					quadrant = 1
				case 2, 3:
					quadrant = 3
				}
			}

			palette_index: u8 = (attr_entry >> (quadrant * 2)) & 0b00000011

			// if B in PPU ctrl is on, add one
			if nes.ppu_ctrl.b != 0 {
				nametable_byte += 0x100
			}

			tile := get_pattern_tile(nes, int(nametable_byte))
			draw_tile(nes, pixel_grid, tile, palette_index, tile_i * 8, row * 8)
			// fmt.println("palette data:", nes.ppu_palette)
		}
	}
}

Tile :: [8 * 8]int

get_pattern_tile :: proc(nes: NES, location: int) -> Tile {

	// 

	i := location

	tile: Tile // pixels of tiles (contains [0-3])

	// first bit plane
	for t in 0 ..< 16 {

		row := nes.chr_rom[(i * 16) + t]

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

	return tile
}

draw_frame :: proc(nes: NES, pixel_grid: ^PixelGrid) {
	// draw_patterntables(nes, pixel_grid)

	draw_nametable(nes, pixel_grid)
	// draw sprites
	draw_sprites(nes, pixel_grid)
}


draw_sprites :: proc(using nes: NES, pixel_grid: ^PixelGrid) {

	OAMAddress :: struct {
		y:          u8,
		index:      u8,
		attributes: u8,
		x:          u8,
	}

	for i in 0 ..< 64 {

		sprite_start := i * 4


		sprite_0: OAMAddress
		sprite_0.y = ppu_oam[sprite_start]
		sprite_0.index = ppu_oam[sprite_start + 1]
		sprite_0.attributes = ppu_oam[sprite_start + 2]
		sprite_0.x = ppu_oam[sprite_start + 3]

		nametable_byte := int(sprite_0.index)

		if nes.ppu_ctrl.s != 0 {
			nametable_byte += 0x100
		}

		// get palette
		palette_offset := sprite_0.attributes & 0x03
		tile := get_pattern_tile(nes, nametable_byte)
		flip_x := sprite_0.attributes & 0x40
		flip_y := sprite_0.attributes & 0x80

		draw_sprite_tile(
			nes,
			pixel_grid,
			tile,
			palette_offset,
			flip_x != 0,
			flip_y != 0,
			int(sprite_0.x),
			int(sprite_0.y + 1),
		)
	}


}

// draws a sprite tile in the pixel grid given a pattern tile and a palette index
draw_sprite_tile :: proc(
	nes: NES,
	pixel_grid: ^PixelGrid,
	tile: [8 * 8]int,
	palette_offset: u8,
	flip_x, flip_y: bool,
	x_pos, y_pos: int,
) {

	// get palette

	palette_start: u16

	switch palette_offset {
	case 0:
		palette_start = 0x3F11
	case 1:
		palette_start = 0x3F15
	case 2:
		palette_start = 0x3F19
	case 3:
		palette_start = 0x3F1D
	}

	palette_start -= 0x3F00

	// nes.palette_mem

	for p, i in tile {
		color_in_nes: u8

		switch p {
		case 0:
			continue
		case 1, 2, 3:
			color_in_nes = nes.ppu_palette[palette_start + u16(p) - 1]
		}

		// fmt.printf("%X, ", color_in_nes)

		col: rl.Color = color_map_from_nes_to_real(color_in_nes)

		x_add := flip_x ? 7 - (i % 8) : i % 8
		y_add := flip_y ? 7 - (i / 8) : i / 8

		the_p_i := ((y_pos + y_add) * pixel_grid.width) + x_pos + x_add

		// bounds check
		if the_p_i >= pixel_grid.width * pixel_grid.height || the_p_i < 0 {
			fmt.printfln("tried to draw tile out of bounds, x: %v, y: %v", x_pos, y_pos)
			continue
		}

		pixel_grid.pixels[the_p_i] = col
	}

}

// draws a background tile in the pixel grid given a pattern tile and a palette index
draw_tile :: proc(
	nes: NES,
	pixel_grid: ^PixelGrid,
	tile: [8 * 8]int,
	palette_index: u8,
	x_pos, y_pos: int,
) {

	// get palette

	palette_start: u16

	switch palette_index {
	case 0:
		palette_start = 0x3F01
	case 1:
		palette_start = 0x3F05
	case 2:
		palette_start = 0x3F09
	case 3:
		palette_start = 0x3F0D
	}

	palette_start -= 0x3F00

	// nes.palette_mem

	for p, i in tile {
		color_in_nes: u8

		switch p {
		case 0:
			color_in_nes = nes.ppu_palette[0]
		case 1, 2, 3:
			color_in_nes = nes.ppu_palette[palette_start + u16(p) - 1]
		}

		// fmt.printf("%X, ", color_in_nes)

		col: rl.Color = color_map_from_nes_to_real(color_in_nes)

		x_add := i % 8
		y_add := i / 8

		the_p_i := ((y_pos + y_add) * pixel_grid.width) + x_pos + x_add

		// bounds check
		if the_p_i >= pixel_grid.width * pixel_grid.height || the_p_i < 0 {
			fmt.printfln("tried to draw tile out of bounds, x: %v, y: %v", x_pos, y_pos)
			continue
		}

		pixel_grid.pixels[the_p_i] = col
	}

}

color_map_from_nes_to_real :: proc(color_in_nes: u8) -> rl.Color {

	// TODO find a better palette. this one is too saturated
	// learn how to read .pal files
	console_palette: [][3]u8 =  {
		{0x80, 0x80, 0x80},
		{0x00, 0x3D, 0xA6},
		{0x00, 0x12, 0xB0},
		{0x44, 0x00, 0x96},
		{0xA1, 0x00, 0x5E},
		{0xC7, 0x00, 0x28},
		{0xBA, 0x06, 0x00},
		{0x8C, 0x17, 0x00},
		{0x5C, 0x2F, 0x00},
		{0x10, 0x45, 0x00},
		{0x05, 0x4A, 0x00},
		{0x00, 0x47, 0x2E},
		{0x00, 0x41, 0x66},
		{0x00, 0x00, 0x00},
		{0x05, 0x05, 0x05},
		{0x05, 0x05, 0x05},
		{0xC7, 0xC7, 0xC7},
		{0x00, 0x77, 0xFF},
		{0x21, 0x55, 0xFF},
		{0x82, 0x37, 0xFA},
		{0xEB, 0x2F, 0xB5},
		{0xFF, 0x29, 0x50},
		{0xFF, 0x22, 0x00},
		{0xD6, 0x32, 0x00},
		{0xC4, 0x62, 0x00},
		{0x35, 0x80, 0x00},
		{0x05, 0x8F, 0x00},
		{0x00, 0x8A, 0x55},
		{0x00, 0x99, 0xCC},
		{0x21, 0x21, 0x21},
		{0x09, 0x09, 0x09},
		{0x09, 0x09, 0x09},
		{0xFF, 0xFF, 0xFF},
		{0x0F, 0xD7, 0xFF},
		{0x69, 0xA2, 0xFF},
		{0xD4, 0x80, 0xFF},
		{0xFF, 0x45, 0xF3},
		{0xFF, 0x61, 0x8B},
		{0xFF, 0x88, 0x33},
		{0xFF, 0x9C, 0x12},
		{0xFA, 0xBC, 0x20},
		{0x9F, 0xE3, 0x0E},
		{0x2B, 0xF0, 0x35},
		{0x0C, 0xF0, 0xA4},
		{0x05, 0xFB, 0xFF},
		{0x5E, 0x5E, 0x5E},
		{0x0D, 0x0D, 0x0D},
		{0x0D, 0x0D, 0x0D},
		{0xFF, 0xFF, 0xFF},
		{0xA6, 0xFC, 0xFF},
		{0xB3, 0xEC, 0xFF},
		{0xDA, 0xAB, 0xEB},
		{0xFF, 0xA8, 0xF9},
		{0xFF, 0xAB, 0xB3},
		{0xFF, 0xD2, 0xB0},
		{0xFF, 0xEF, 0xA6},
		{0xFF, 0xF7, 0x9C},
		{0xD7, 0xE8, 0x95},
		{0xA6, 0xED, 0xAF},
		{0xA2, 0xF2, 0xDA},
		{0x99, 0xFF, 0xFC},
		{0xDD, 0xDD, 0xDD},
		{0x11, 0x11, 0x11},
		{0x11, 0x11, 0x11},
	}

	color_in_nes := color_in_nes & 0x3F

	color: rl.Color
	color.xyz = console_palette[color_in_nes]

	// making it darker
	// factor:f32= 0.5
	// color.x = u8(f32(color.x) * factor)
	// color.y = u8(f32(color.y) * factor)
	// color.z = u8(f32(color.z) * factor)

	color.w = 255


	return color_map_from_nes_to_real_manual(color_in_nes)
	// return color

	// return color.R << 24 | color.G << 16 | color.B << 8 | 0xFF;
	// return rl.BLACK
}

// manual way i did it. 
color_map_from_nes_to_real_manual :: proc(color_in_nes: u8) -> rl.Color {

	col: rl.Color = rl.BLACK

	// this will take a long time

	switch color_in_nes {

	case 0x00:
		col.xyz = {101, 102, 102}
	case 0x0F:
		col.xyz = {0, 0, 0}
	case 0x12:
		col.xyz = {64, 81, 208}
	case 0x2C:
		col.xyz = {62, 194, 205}
	case 0x27:
		col.xyz = {239, 154, 73}
	case 0x30:
		col.xyz = {254, 254, 255}
	case 0x15:
		col.xyz = {192, 52, 112}
	case 0x33:
		col.xyz = {232, 209, 255}
	case 0x36:
		col.xyz = {255, 207, 202}
	case 0x06:
		col.xyz = {113, 15, 7}
	case 0x17:
		col.xyz = {159, 74, 0}
	case 0x02:
		col.xyz = {121, 31, 127}
	case 0x05:
		col.xyz = {115, 10, 55}
	case 0x28:
		col.xyz = {180, 172, 44}
	case 0x19:
		col.xyz = {54, 109, 0}
	case 0x11:
		col.xyz = {15, 99, 179}
	case 0x16:
		col.xyz = {189, 60, 48}
	case 0x20:
		col.xyz = {254, 254, 255}
	case 0x26:
		col.xyz = {255, 139, 127}
	case 0x21:
		col.xyz = {93, 179, 255}
	case 0x25:
		col.xyz = {255, 131, 192}
	case 0x37:
		col.xyz = {248, 213, 180}
	case 0x24:
		col.xyz = {247, 133, 250}
	case 0x22:
		col.xyz = {143, 161, 255}
	case 0x29:
		col.xyz = {133, 188, 47}
	case 0x3A:
		col.xyz = {185, 232, 184}
	case 0x01:
		col.xyz = {0, 45, 105}
	case 0x38:
		col.xyz = {233, 226, 183}
	case 0x1A:
		col.xyz = {7, 119, 4}
	case 0x07:
		col.xyz = {90, 26, 0}
	case 0x18:
		col.xyz = {109, 92, 0}
	case 0x1C:
		col.xyz = {0, 114, 125}
	case 0x3C:
		col.xyz = {175, 229, 234}
	case 0x09:
		col.xyz = {11, 52, 0}
	case 0x0C:
		col.xyz = {1, 56, 64}
	case 0x10:
		col.xyz = {174, 174, 174}

	case:
		fmt.printf("%X, ", color_in_nes)
	}


	return col


}

draw_pattern_tile :: proc(pixel_grid: ^PixelGrid, tile: [8 * 8]int, x_pos, y_pos: int) {

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

		the_p_i := ((y_pos + y_add) * pixel_grid.width) + x_pos + x_add

		// bounds check
		if the_p_i >= pixel_grid.width * pixel_grid.height || the_p_i < 0 {
			fmt.printfln("tried to draw tile out of bounds, x: %v, y: %v", x_pos, y_pos)
			continue
		}

		pixel_grid.pixels[the_p_i] = col
	}
}
