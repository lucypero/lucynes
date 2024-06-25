package main

import rl "vendor:raylib"

// u might need this one
//    void UpdateTexture(Texture2D texture, const void *pixels);                                         // Update GPU texture with new data

scale_factor :: 4

screen_width :: 256 * scale_factor
screen_height :: 240 * scale_factor // ntsc might only show 224 scan lines

raylib_test :: proc() {

	rl.InitWindow(screen_width, screen_height, "lucynes")
	rl.SetTargetFPS(144)


	// Generate a checked texture by code
	width: i32 = 960
	height: i32 = 480

	// Dynamic memory allocation to store pixels data (Color type)
	pixels := make([]rl.Color, width * height)

	for y in 0 ..< height {
		for x in 0 ..< width {
			if ((x / 32 + y / 32) / 1) % 2 == 0 {
				pixels[y * width + x] = rl.ORANGE
			} else {
				pixels[y * width + x] = rl.GOLD
			}
		}
	}

	// Load pixels data into an image structure and create texture
	checkedIm := rl.Image {
		data    = raw_data(pixels), // We can assign pixels directly to data
		width   = width,
		height  = height,
		format  = .UNCOMPRESSED_R8G8B8A8,
		mipmaps = 1,
	}

	checked := rl.LoadTextureFromImage(checkedIm)
	// rl.UnloadImage(checkedIm) // Unload CPU (RAM) image data (pixels)

	switch_counter := 0
	is_orange := false

	for !rl.WindowShouldClose() {

		rl.BeginDrawing()

		rl.ClearBackground(rl.RAYWHITE)

		switch_counter += 1
		if switch_counter >= 144 {
			switch_counter = 0
			is_orange = !is_orange

			// swapping pixels
			for y in 0 ..< height {
				for x in 0 ..< width {
					if ((x / 32 + y / 32) / 1) % 2 == 0 {
						pixels[y * width + x] = is_orange ? rl.ORANGE : rl.GOLD
					} else {
						pixels[y * width + x] = is_orange ? rl.GOLD : rl.ORANGE
					}
				}
			}

			rl.UpdateTexture(checked, raw_data(pixels))
		}

		rl.DrawTexture(
			checked,
			screen_width / 2 - checked.width / 2,
			screen_height / 2 - checked.height / 2,
			rl.Fade(rl.WHITE, 0.5),
		)

		rl.EndDrawing()
	}

}
