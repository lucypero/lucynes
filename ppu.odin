package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

write_ppu_register :: proc(using nes: ^NES, ppu_reg: u16, val: u8) {
	switch ppu_reg {

	// PPUCTRL
	case 0x2000:
		// writing to ppuctrl
		// fmt.printfln("writing to PPUCTRL %X", val)

		// if vblank is set, and you change nmi flag from 0 to 1, trigger nmi now
		if ppu_on_vblank && val & 0x80 != 0 && ppu_ctrl.v == 0 {
			// trigger NMI immediately
			nmi(nes)
		}

		ppu_ctrl.reg = val

		temp_loopy.nametable_x = u16(ppu_ctrl.n & 0b1)
		temp_loopy.nametable_y = u16(ppu_ctrl.n & 0b10)

	// PPUMASK
	case 0x2001:
		ppu_mask.reg = val

	// PPUSTATUS
	case 0x2002:
	// do nothing

	// OAMADDR
	case 0x2003:
		ppu_oam_address = val


	// OAMDATA
	case 0x2004:
		// TODO:  For emulation purposes, it is probably best to completely ignore writes during rendering.

		// TODO: what do i do against possible out of bounds writes?
		ppu_oam[ppu_oam_address] = val
		ppu_oam_address += 1

	// PPUSCROLL
	case 0x2005:
		// note: Changes made to the vertical scroll during rendering will only take effect on the next frame. 

		// First write
		if !ppu_w {
			ppu_x = val & 0x07
			temp_loopy.coarse_x = u16(val >> 3)
		} else // Second write
		{
			temp_loopy.fine_y = u16(val & 0x07)
			temp_loopy.coarse_y = u16(val >> 3)
		}

		ppu_w = !ppu_w

	// PPUADDR
	case 0x2006:
		// First write
		if !ppu_w {
			temp_loopy.reg = u16(val) << 8 | (temp_loopy.reg & 0x00FF)
		} else { 	// Second write
			temp_loopy.reg = (temp_loopy.reg & 0xFF00) | u16(val)
			// once you write the full address, the current loopy gets updated with temp loopy
			current_loopy.reg = temp_loopy.reg
		}

		ppu_w = !ppu_w

	//PPUDATA
	case 0x2007:
		ppu_write(nes, current_loopy.reg, val)
		increment_current_loopy(nes)
	}
}

read_ppu_register :: proc(using nes: ^NES, ppu_reg: u16) -> u8 {
	switch ppu_reg {

	// PPUCTRL
	case 0x2000:
		// return garbage if they try to read this. "open bus"
		// https://forums.nesdev.org/viewtopic.php?t=6426

		// fmt.eprintfln("should not read to ppuctrl. it's write only")
		return ppu_ctrl.reg

	// PPUMASK
	case 0x2001:
		// should never read to PPUMASK. just return the mask?
		// fmt.eprintfln("should not read to ppumask. it's write only")
		return ppu_mask.reg

	// PPUSTATUS
	case 0x2002:
		//TODO some of it

		// return v blank as 1, rest 0

		if ppu_on_vblank {
			ppu_status.vertical_blank = 1
		} else {
			ppu_status.vertical_blank = 0
		}

		ppu_on_vblank = false

		// fmt.printfln("reading ppu status. clearing latch")
		ppu_w = false
		return ppu_status.reg

	// OAMADDR
	case 0x2003:
		// it should never read here.. return open bus
		return 0

	// OAMDATA
	case 0x2004:
		// TODO: what do i do against possible out of bounds writes?
		return ppu_oam[ppu_oam_address]

	// PPUSCROLL
	case 0x2005:
		// it should never read here.. return open bus
		return 0

	// PPUDATA
	case 0x2007:
		// fmt.printfln("reading PPUDATA")

		// returns the buffered read except when reading internal palette memory
		val := ppu_buffer_read
		ppu_buffer_read = ppu_read(nes, current_loopy.reg)

		switch current_loopy.reg {
		case 0x3F00 ..= 0x3FFF:
			val = ppu_buffer_read
		}

		increment_current_loopy(nes)

		return val

	case:
		return ram[ppu_reg]
	}
}

increment_current_loopy :: proc(using nes: ^NES) {
	goDown: bool = ppu_ctrl.i != 0

	if goDown {
		current_loopy.reg += 32
	} else {
		current_loopy.reg += 1
	}
}

ppu_read :: proc(using nes: ^NES, mem: u16) -> u8 {
	return ppu_readwrite(nes, mem, 0, false)
}

ppu_write :: proc(using nes: ^NES, mem: u16, val: u8) {
	ppu_readwrite(nes, mem, val, true)
}

// this implements the PPU address space, or bus, or whatever
// read PPU memory map in nesdev wiki
// write == true then it will write
// write == false then it will read
ppu_readwrite :: proc(using nes: ^NES, mem: u16, val: u8, write: bool) -> u8 {
	temp_val: u8
	the_val: ^u8 = &temp_val

	switch mem {

	// Pattern tables
	// it's in cartridge's CHR ROM
	case 0x0000 ..= 0x1FFF:
		if write {
			fmt.eprintln("u are trying to write to cartridge's ROM...")
		}

		the_val = &chr_rom[mem]
	// nametable data (it's in ppu memory)
	case 0x2000 ..= 0x2FFF:
		index_in_vram := mem - 0x2000

		// the part of mem into each nametable
		mem_modulo := index_in_vram % 0x400

		switch mem {
		case 0x2000 ..= 0x23FF:
			if !nes.rom_info.is_horizontal_arrangement {
				// write to first slot
				index_in_vram = mem_modulo
			} else {
				// write to first slot
				index_in_vram = mem_modulo
			}
		case 0x2400 ..= 0x27FF:
			if !nes.rom_info.is_horizontal_arrangement {
				// write to first slot
				index_in_vram = mem_modulo
			} else {
				// write to second slot
				index_in_vram = mem_modulo + 0x400
			}
		case 0x2800 ..= 0x2BFF:
			if !nes.rom_info.is_horizontal_arrangement {
				// write to second slot
				index_in_vram = mem_modulo + 0x400
			} else {
				// write to first slot
				index_in_vram = mem_modulo
			}
		case 0x2C00 ..= 0x2FFF:
			if !nes.rom_info.is_horizontal_arrangement {
				// write to second slot
				index_in_vram = mem_modulo + 0x400
			} else {
				// write to second slot
				index_in_vram = mem_modulo + 0x400
			}
		}

		the_val = &ppu_memory[index_in_vram]
	case 0x3000 ..= 0x3EFF:
		// unused addresses... return bus
		return 0

	// Palette RAM indexes
	case 0x3F00 ..= 0x3FFF:
		// this is always the same. the cartridge doesn't have a say in this one.
		palette_mem := get_mirrored(int(mem), 0x3F00, 0x3F1F)

		// implementing palette mirrors
		switch palette_mem {
		case 0x3F10, 0x3F14, 0x3F18, 0x3F1C:
			palette_mem -= 0x10
		}

		palette_mem -= 0x3F00

		the_val = &ppu_palette[palette_mem]
	case:
		fmt.eprintfln("idk what u read/writing here at ppu bus %X", mem)
	}

	if write {
		the_val^ = val
	}

	return the_val^
}


// loads the background shifters with data of the next tile, on the least significant byte
load_bg_shifters :: proc(using nes: ^NES) {
	// patterns

	// loading first bitplane of pattern tile
	bg_shifter_pattern_lo = (bg_shifter_pattern_lo & 0xFF00) | u16(bg_next_tile_lsb)
	// loading second bitplane of pattern tile
	bg_shifter_pattern_hi = (bg_shifter_pattern_hi & 0xFF00) | u16(bg_next_tile_msb)

	// attributes

	// inflating the first bit of next tile attribute into the shifters
	new_attrib_lo: u16 = bg_next_tile_attrib & 0b01 != 0 ? 0xFF : 0x00
	bg_shifter_attrib_lo = (bg_shifter_attrib_lo & 0xFF00) | new_attrib_lo

	// inflating the second bit of next tile attribute into the shifters
	new_attrib_hi: u16 = bg_next_tile_attrib & 0b10 != 0 ? 0xFF : 0x00
	bg_shifter_attrib_hi = (bg_shifter_attrib_hi & 0xFF00) | new_attrib_hi
}

// shifts the shifter registers by 1 bit to the left
shift_shifters :: proc(using nes: ^NES, cycle_x: int) {
	if ppu_mask.show_background != 0 {
		bg_shifter_pattern_lo <<= 1
		bg_shifter_pattern_hi <<= 1
		bg_shifter_attrib_lo <<= 1
		bg_shifter_attrib_hi <<= 1
	}

	// shifting sprite shifters (only when they hit the cycle)
	if ppu_mask.show_sprites != 0 && cycle_x >= 1 && cycle_x < 258 {
		for i in 0 ..< sprite_count {
			if sprite_scanline[i].x > 0 {
				sprite_scanline[i].x -= 1
			} else {
				sprite_shifter_pattern_lo[i] <<= 1
				sprite_shifter_pattern_hi[i] <<= 1
			}
		}
	}
}


increment_scroll_x :: proc(using nes: ^NES) {
	if !(ppu_mask.show_background != 0 || ppu_mask.show_sprites != 0) {
		return
	}

	// When crossing over nametables
	if current_loopy.coarse_x == 31 {
		current_loopy.coarse_x = 0
		current_loopy.nametable_x = ~current_loopy.nametable_x
	} else {
		current_loopy.coarse_x += 1
	}
}

increment_scroll_y :: proc(using nes: ^NES) {
	if !(ppu_mask.show_background != 0 || ppu_mask.show_sprites != 0) {
		return
	}

	if current_loopy.fine_y < 7 {
		current_loopy.fine_y += 1
		return
	}

	current_loopy.fine_y = 0

	if current_loopy.coarse_y == 29 {
		current_loopy.coarse_y = 0
		current_loopy.nametable_y = ~current_loopy.nametable_y
	} else if current_loopy.coarse_y == 31 {
		// i don't understand this one. why would we be in attribute memory here?
		// this should never run i think...
		current_loopy.coarse_y = 0
	} else {
		current_loopy.coarse_y += 1
	}
}

// what does this do? when does this get called?
transfer_address_x :: proc(using nes: ^NES) {

	if !(ppu_mask.show_background != 0 || ppu_mask.show_sprites != 0) {
		return
	}

	current_loopy.nametable_x = temp_loopy.nametable_x
	current_loopy.coarse_x = temp_loopy.coarse_x
}

transfer_address_y :: proc(using nes: ^NES) {
	if !(ppu_mask.show_background != 0 || ppu_mask.show_sprites != 0) {
		return
	}

	current_loopy.fine_y = temp_loopy.fine_y
	current_loopy.nametable_y = temp_loopy.nametable_y
	current_loopy.coarse_y = temp_loopy.coarse_y
}

// returns true if it hit a vblank
ppu_tick :: proc(using nes: ^NES, framebuffer: ^PixelGrid) -> bool {

	// read "PPU Rendering"

	// 262 scanlines
	hit_vblank := false

	scanline := ppu_cycles / 341

	// how deep you are into the scanline
	cycle_x := ppu_cycles % 341

	// scanline guide:
	// 0..= 239: visible scanlines
	// 240: post render scanline (it idles)
	// 241..=260: vertical blanking lines
	// 261: pre-render scanline

	// cycle_x guide:
	// 0: idle cycle
	// 1..=256: fetching data
	// 257..=320: fetching tile data for sprites on next scanline
	// 321..=336: fetching two tiles for next scanline
	// 337..=340: fetching nametable bytes but it is unused


	// cycle 0
	switch scanline {
	// visible scanlines
	case 0 ..= 239:
		if (cycle_x > 0 && cycle_x < 258) || (cycle_x >= 321 && cycle_x < 338) {
			shift_shifters(nes, cycle_x)
			switch (cycle_x - 1) % 8 {
			case 0:
				load_bg_shifters(nes)

				// fetch the next background tile ID

				addr: u16 = 0x2000 | (current_loopy.reg & 0x0FFF)
				bg_next_tile_id = ppu_read(nes, addr)
			case 2:
				// fetch the next background tile attribute

				// All attribute memory begins at 0x03C0 within a nametable, so OR with
				// result to select target nametable, and attribute byte offset. Finally
				// OR with 0x2000 to offset into nametable address space on PPU bus.				
				bg_next_tile_attrib = ppu_read(
					nes,
					0x23C0 |
					(current_loopy.nametable_y << 11) |
					(current_loopy.nametable_x << 10) |
					((current_loopy.coarse_y >> 2) << 3) |
					(current_loopy.coarse_x >> 2),
				)

				// selecting the right 2x2 block out of the 4x4 attribute entry

				if current_loopy.coarse_y & 0x02 != 0 {bg_next_tile_attrib >>= 4}
				if current_loopy.coarse_x & 0x02 != 0 {bg_next_tile_attrib >>= 2}

				// you need only 2 bits
				bg_next_tile_attrib &= 0x03

			case 4:
				// fetch the next background tile bitplane 1 (lsb)

				addr: u16 =
					(u16(ppu_ctrl.b) << 12) +
					(u16(bg_next_tile_id) << 4) +
					current_loopy.fine_y +
					0

				bg_next_tile_lsb = ppu_read(nes, addr)
			case 6:
				addr: u16 =
					(u16(ppu_ctrl.b) << 12) +
					(u16(bg_next_tile_id) << 4) +
					current_loopy.fine_y +
					8

				// fetch the next background tile bitplane 2 (msb)
				bg_next_tile_msb = ppu_read(nes, addr)
			case 7:
				// increment scroll x
				increment_scroll_x(nes)
			}
		}

		if cycle_x == 256 {
			increment_scroll_y(nes)
		}

		if cycle_x == 257 {
			transfer_address_x(nes)

		}


	// First vertical blanking line
	case 241:
		// setting vblank and nmi
		if ppu_cycles % 341 == 1 {
			ppu_on_vblank = true
			hit_vblank = true
			if ppu_ctrl.v != 0 {
				nmi(nes)
			}
		}
	// pre-render scanline
	case 261:
		if ppu_cycles % 341 == 1 {
			ppu_on_vblank = false
		}

		if cycle_x >= 280 && cycle_x < 305 {
			transfer_address_y(nes)
		}

		if cycle_x == 1 {
			ppu_status.sprite_overflow = 0
			ppu_status.sprite_zero_hit = 0

			for i in 0 ..< 8 {
				sprite_shifter_pattern_hi[i] = 0
				sprite_shifter_pattern_lo[i] = 0
			}
		}
	case:
	// vblank scanlines
	}

	// Foreground rendering

	// doing it at all visible scanlines, at cycle 257 (non visible)
	// evaluating sprites at next scanline
	if scanline <= 239 && cycle_x == 257 {
		evaluate_sprites(nes, scanline)
	}

	if scanline <= 239 && cycle_x == 340 {
		update_sprite_shift_registers(nes, scanline)
	}

	ppu_cycles += 1

	if ppu_cycles > 341 * 262 {
		ppu_cycles = 0
	}

	/// Rendering the current pixel
	draw_pixel(nes, framebuffer, cycle_x, scanline)

	return hit_vblank
}

// Does the sprite evaluation for the next scanline
evaluate_sprites :: proc(using nes: ^NES, current_scanline: int) {
	// clear sprite scanline array to 0xFF
	slice.fill(slice.to_bytes(sprite_scanline[:]), 0xFF)
	sprite_count = 0

	oam_entry: u8
	sprite_zero_hit_possible = false

	oam_entries := slice.reinterpret([]OAMEntry, ppu_oam[:])

	for oam_entry < 64 && sprite_count < 9 {

		// figuring out if the sprite is going to be visible on the next scanline
		//  by looking at the Y position and the height of the sprite

		// TODO: this is like evaluating the current scanline
		// .  but u should evaluate the next one. what's going on?

		diff: u16 = u16(current_scanline) - u16(oam_entries[oam_entry].y)

		if diff >= 0 && diff < (ppu_ctrl.h != 0 ? 16 : 8) {
			if sprite_count < 8 {

				// is this sprite zero?
				if oam_entry == 0 {
					sprite_zero_hit_possible = true
				}

				// copy sprite to sprite scanline array
				sprite_scanline[sprite_count] = oam_entries[oam_entry]
			}
			sprite_count += 1
		}

		oam_entry += 1
	}

	// set sprite oveflow flag
	ppu_status.sprite_overflow = sprite_count > 8 ? 1 : 0

	if sprite_count > 8 {
		sprite_count = 8
	}
}

update_sprite_shift_registers :: proc(using nes: ^NES, current_scanline: int) {

	for i in 0 ..< sprite_count {

		sprite_pattern_bits_lo: u8
		sprite_pattern_bits_hi: u8

		sprite_pattern_addr_lo: u16
		sprite_pattern_addr_hi: u16

		if (ppu_ctrl.h == 0) {
			// 8x8 sprite mode
			// . the control register determines the pattern table

			if sprite_scanline[i].attribute & 0x80 == 0 {
				// sprite is not flipped vertically

				sprite_pattern_addr_lo =
					u16(ppu_ctrl.s) << 12 |
					u16(sprite_scanline[i].id) << 4 |
					u16((current_scanline - int(sprite_scanline[i].y)))
			} else {
				// sprite is flipped vertically


				sprite_pattern_addr_lo =
					u16(ppu_ctrl.s) << 12 |
					u16(sprite_scanline[i].id) << 4 |
					u16((7 - (current_scanline - int(sprite_scanline[i].y))))

			}
		} else {
			// 8x16 sprite mode. the sprite attributes determines the pattern table

			if sprite_scanline[i].attribute & 0x80 == 0 {
				// sprite is not flipped vertically

				if (current_scanline - int(sprite_scanline[i].y)) < 8 {
					// reading top half tile

					sprite_pattern_addr_lo =
						u16(sprite_scanline[i].id & 0x01) << 12 |
						u16(sprite_scanline[i].id & 0xFE) << 4 |
						u16(((current_scanline - int(sprite_scanline[i].y)) & 0x07))

				} else {
					// reading bottom half tile

					sprite_pattern_addr_lo =
						u16(sprite_scanline[i].id & 0x01) << 12 |
						u16(sprite_scanline[i].id & 0xFE + 1) << 4 |
						u16(((current_scanline - int(sprite_scanline[i].y)) & 0x07))
				}

			} else {
				// sprite is flipped vertically
				if (current_scanline - int(sprite_scanline[i].y)) < 8 {
					// reading top half tile
					sprite_pattern_addr_lo =
						u16(sprite_scanline[i].id & 0x01) << 12 |
						u16(sprite_scanline[i].id & 0xFE + 1) << 4 |
						u16(((7 - (current_scanline - int(sprite_scanline[i].y))) & 0x07))

				} else {
					// reading bottom half tile
					sprite_pattern_addr_lo =
						u16(sprite_scanline[i].id & 0x01) << 12 |
						u16(sprite_scanline[i].id & 0xFE) << 4 |
						u16(((7 - (current_scanline - int(sprite_scanline[i].y))) & 0x07))
				}
			}
		}


		sprite_pattern_addr_hi = sprite_pattern_addr_lo + 8

		sprite_pattern_bits_lo = ppu_read(nes, sprite_pattern_addr_lo)
		sprite_pattern_bits_hi = ppu_read(nes, sprite_pattern_addr_hi)

		// If the sprite is flipped horizontally
		if sprite_scanline[i].attribute & 0x40 != 0 {
			// Flip the pattern bytes
			sprite_pattern_bits_lo = flip_byte(sprite_pattern_bits_lo)
			sprite_pattern_bits_hi = flip_byte(sprite_pattern_bits_hi)
		}

		sprite_shifter_pattern_lo[i] = sprite_pattern_bits_lo
		sprite_shifter_pattern_hi[i] = sprite_pattern_bits_hi
	}
}

// Writes a pixel in the pixel grid if it's on a visible slot
draw_pixel :: proc(using nes: ^NES, pixel_grid: ^PixelGrid, cycle_x, scanline: int) {
	// checks before bothering to draw a pixel

	// checks if renderer is on
	if ppu_mask.show_background == 0 {
		return
	}

	// checks if it's on a visible pixel
	if !(scanline <= 239 && cycle_x > 0 && cycle_x <= 256) {
		return
	}

	bg_pixel: u8
	bg_palette: u8

	bit_mux: u16 = 0x8000 >> ppu_x

	p0_pixel: u8 = (bg_shifter_pattern_lo & bit_mux) > 0 ? 1 : 0
	p1_pixel: u8 = (bg_shifter_pattern_hi & bit_mux) > 0 ? 1 : 0
	bg_pixel = (p1_pixel << 1) | p0_pixel

	bg_pal0: u8 = (bg_shifter_attrib_lo & bit_mux) > 0 ? 1 : 0
	bg_pal1: u8 = (bg_shifter_attrib_hi & bit_mux) > 0 ? 1 : 0
	bg_palette = (bg_pal1 << 1) | bg_pal0


	// foreground pixel

	fg_pixel: u8
	fg_palette: u8
	fg_priority: u8

	if ppu_mask.show_sprites != 0 {

		sprite_zero_being_rendered = false

		for i in 0 ..< sprite_count {

			if sprite_scanline[i].x != 0 {
				continue
			}

			fg_pixel_lo: u8 = sprite_shifter_pattern_lo[i] & 0x80 > 0 ? 1 : 0
			fg_pixel_hi: u8 = sprite_shifter_pattern_hi[i] & 0x80 > 0 ? 1 : 0
			fg_pixel = (fg_pixel_hi << 1) | fg_pixel_lo

			fg_palette = (sprite_scanline[i].attribute & 0x03) + 0x04
			fg_priority = (sprite_scanline[i].attribute & 0x20) == 0 ? 1 : 0

			if fg_pixel != 0 {
				if i == 0 {
					sprite_zero_being_rendered = true
				}

				break
			}
		}
	}

	// combining background pixel and foreground pixel

	pixel: u8
	palette: u8

	if bg_pixel == 0 && fg_pixel == 0 {
		pixel = 0
		palette = 0
	} else if bg_pixel == 0 && fg_pixel > 0 {
		pixel = fg_pixel
		palette = fg_palette
	} else if bg_pixel > 0 && fg_pixel == 0 {
		pixel = bg_pixel
		palette = bg_palette
	} else if bg_pixel > 0 && fg_pixel > 0 {

		// both bg and fg are visible.

		if fg_priority != 0 {
			pixel = fg_pixel
			palette = fg_palette
		} else {
			pixel = bg_pixel
			palette = bg_palette
		}

		// sprite zero hit detection
		if sprite_zero_being_rendered && sprite_zero_hit_possible {
			if ppu_mask.show_background != 0 && ppu_mask.show_sprites != 0 {

				if ~(ppu_mask.show_left_background | ppu_mask.show_left_sprites) != 0 {
					if cycle_x >= 9 && cycle_x < 258 {
						ppu_status.sprite_zero_hit = 1
					}

				} else {
					if cycle_x >= 1 && cycle_x < 258 {
						ppu_status.sprite_zero_hit = 1
					}
				}
			}
		}
	}

	nes_color := get_color_from_palettes(nes^, pixel, palette)
	real_color := color_map_from_nes_to_real(nes_color)

	// position of pixel
	pos_x := cycle_x - 1
	pos_y := scanline

	pixel_grid.pixels[pos_y * 256 + pos_x] = real_color
}

// Gets color byte in palette, given a bg palette and a color inside the palette
get_color_from_palettes :: proc(using nes: NES, pixel: u8, palette: u8) -> u8 {

	palette_start: u16

	switch palette {
	case 0:
		palette_start = 0x3F01
	case 1:
		palette_start = 0x3F05
	case 2:
		palette_start = 0x3F09
	case 3:
		palette_start = 0x3F0D
	case 4:
		palette_start = 0x3F11
	case 5:
		palette_start = 0x3F15
	case 6:
		palette_start = 0x3F19
	case 7:
		palette_start = 0x3F1D
	}

	palette_start -= 0x3F00

	switch pixel {
	case 0:
		return nes.ppu_palette[0]
	case:
		return nes.ppu_palette[palette_start + u16(pixel) - 1]
	}
}
