package main

import "core:fmt"
import rl "vendor:raylib"

// u might need this one
//    void UpdateTexture(Texture2D texture, const void *pixels);                                         // Update GPU texture with new data

scale_factor :: 4

nes_width :: 256
nes_height :: 240

// screen_width :: nes_width * scale_factor
// screen_height :: nes_height * scale_factor // ntsc might only show 224 scan lines

screen_width :: 2000
screen_height :: 1200

framebuffer_width :: screen_width / scale_factor
framebuffer_height :: screen_height / scale_factor

PixelGrid :: struct {
	pixels: []rl.Color,
	width:  int,
	height: int,
}

raylib_test :: proc(nes: NES) {

	rl.InitWindow(screen_width, screen_height, "lucynes")
	rl.SetWindowPosition(20, 50)
	rl.SetTargetFPS(144)

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


	for !rl.WindowShouldClose() {

		rl.BeginDrawing()

		// rl.ClearBackground(rl.RAYWHITE)

		clear_pixels(pixels, rl.YELLOW)

		// here you modify the pixels (draw the frame)
		draw_frame(nes, &pixel_grid)

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

draw_frame :: proc(nes: NES, pixel_grid: ^PixelGrid) {

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
		draw_tile(pixel_grid, tile, x_pos, y_pos)
	}
}

draw_tile :: proc(pixel_grid: ^PixelGrid, tile: [8 * 8]int, x_pos, y_pos: int) {

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
