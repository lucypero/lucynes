package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

PPU :: struct {
	memory:                     [2 * 1024]u8, // stores 2 nametables
	palette:                    [32]u8, // internal memory inside the PPU, stores palette data
	oam:                        [256]u8, // OAM data, inside the PPU
	oam_address:                u8,
	cycle_x:                    int, // current ppu cycle horizontally in the scanline (0..=340)
	scanline:                   int, // current ppu scanline (-1..=260)

	//NOTE: if everything is stored in loopy, then this is all redundant state, no?
	// consider deleting all this
	ppu_ctrl:                   struct #raw_union {
		// VPHB SINN
		using flags: bit_field u8 {
			n: u8 | 2,
			i: u8 | 1,
			s: u8 | 1, // sprite pattern table address for 8x8 sprites (0: $0000, 1: $1000)
			b: u8 | 1, // bg pattern table address (0: $0000, 1: $1000)
			h: u8 | 1, // sprite size (0: 8x8, 1: 8x16)
			p: u8 | 1,
			v: u8 | 1,
		},
		reg:         u8,
	},
	ppu_mask:                   struct #raw_union {
		// BGRs bMmG
		using flags: bit_field u8 {
			greyscale:            u8 | 1,
			// Show background in leftmost 8 pixels of screen, 0: Hide
			show_left_background: u8 | 1,
			// Show sprites in leftmost 8 pixels of screen, 0: Hide
			show_left_sprites:    u8 | 1,
			show_background:      u8 | 1,
			show_sprites:         u8 | 1,
			emphasize_red:        u8 | 1,
			emphasize_green:      u8 | 1,
			emphasize_blue:       u8 | 1,
		},
		reg:         u8,
	},
	ppu_status:                 struct #raw_union {
		// VSO. ....
		using flags: bit_field u8 {
			open_bus:        u8 | 5,
			sprite_overflow: u8 | 1,
			sprite_zero_hit: u8 | 1,
			vertical_blank:  u8 | 1,
		},
		reg:         u8,
	},
	ppu_buffer_read:            u8,

	// ppu internals: new model: the ppu loopy model
	current_loopy:              LoopyRegister,
	temp_loopy:                 LoopyRegister,
	ppu_x:                      u8, // fine x scroll (3 bits)
	ppu_w:                      bool, // First or second write toggle (1 bit)


	// data for rendering the next pixel
	// TODO: what is this? i thought all the state required was the 4 variables above.
	// idk look into it.
	bg_next_tile_id:            u8,
	bg_next_tile_attrib:        u8,
	bg_next_tile_lsb:           u8, // bitplane of pattern tile
	bg_next_tile_msb:           u8, // bitplane 2 of pattern tile

	// background shift registers
	bg_shifter_pattern_lo:      u16,
	bg_shifter_pattern_hi:      u16,
	bg_shifter_attrib_lo:       u16,
	bg_shifter_attrib_hi:       u16,
	sprite_scanline:            [8]OAMEntry, // the 8 possible sprites in a scanline
	sprite_count:               u8, // to track how many sprites are in the next scanline

	// sprite shift registers
	sprite_shifter_pattern_lo:  [8]u8,
	sprite_shifter_pattern_hi:  [8]u8,

	// sprite zero collision flags
	sprite_zero_hit_possible:   bool, // if a SZH is possible in the next scanline
	sprite_zero_being_rendered: bool,
}

ppu_init :: proc(using ppu: ^PPU) {
	ppu_status.vertical_blank = 1
}

write_ppu_register :: proc(nes: ^NES, ppu_reg: u16, val: u8) {

	using nes.ppu

	switch ppu_reg {

	// PPUCTRL
	case 0x2000:
		// writing to ppuctrl
		// fmt.printfln("writing to PPUCTRL %b", val)

		// if vblank is set, and you change nmi flag from 0 to 1, trigger nmi now
		if (ppu_status.vertical_blank == 1) && val & 0x80 != 0 && ppu_ctrl.v == 0 {
			// trigger NMI immediately
			nes.nmi_triggered = 2
			// nmi(nes,true)
		}

		if val == 0x10 {
			// fmt.printfln("set to 10")
			//
			// nes.log_dump_scheudled = true
		}

		ppu_ctrl.reg = val
		// fmt.printfln("set to %X", val)
		temp_loopy.nametable_x = u16(ppu_ctrl.n & 0b1) != 0 ? 1 : 0
		temp_loopy.nametable_y = u16(ppu_ctrl.n & 0b10) != 0 ? 1 : 0

	// PPUMASK
	case 0x2001:
		ppu_mask.reg = val

	// PPUSTATUS
	case 0x2002:
	// do nothing

	// OAMADDR
	case 0x2003:
		oam_address = val


	// OAMDATA
	case 0x2004:
		// TODO:  For emulation purposes, it is probably best to completely ignore writes during rendering.

		// TODO: what do i do against possible out of bounds writes?
		oam[oam_address] = val
		oam_address += 1

	// PPUSCROLL
	case 0x2005:
		// note: Changes made to the vertical scroll during rendering will only take effect on the next frame. 

		// First write
		if !ppu_w {
			ppu_x = val & 0x07
			temp_loopy.coarse_x = u16(val) >> 3
			// fmt.printfln("changing coarse x. at scanline %v cycle %v", scanline, cycle_x)
		} else // Second write
		{
			temp_loopy.fine_y = u16(val) & 0x07
			temp_loopy.coarse_y = u16(val) >> 3
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
		increment_current_loopy(&nes.ppu)
	}
}

read_ppu_register :: proc(nes: ^NES, ppu_reg: u16) -> u8 {

	using nes.ppu

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
		returned_status := ppu_status
		ppu_status.vertical_blank = 0
		ppu_w = false
		// fmt.printfln("reading ppu status. %X", ppu_status.reg)
		return returned_status.reg

	// OAMADDR
	case 0x2003:
		// it should never read here.. return open bus
		return 0

	// OAMDATA
	case 0x2004:
		// TODO: what do i do against possible out of bounds writes?
		return oam[oam_address]

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

		increment_current_loopy(&nes.ppu)

		return val

	case:
		return 0
	}
}

increment_current_loopy :: proc(using ppu: ^PPU) {
	goDown: bool = ppu_ctrl.i != 0

	if goDown {
		current_loopy.reg += 32
	} else {
		current_loopy.reg += 1
	}
}

ppu_read :: proc(nes: ^NES, mem: u16) -> u8 {
	return ppu_readwrite(nes, mem, 0, false)
}

ppu_write :: proc(nes: ^NES, mem: u16, val: u8) {
	ppu_readwrite(nes, mem, val, true)
}

// this implements the PPU address space, or bus, or whatever
// read PPU memory map in nesdev wiki
// write == true then it will write
// write == false then it will read
ppu_readwrite :: proc(nes: ^NES, mem: u16, val: u8, write: bool) -> u8 {
	using nes.ppu

	temp_val: u8
	the_val: ^u8 = &temp_val

	// ignoring top 2 bits (it's a 14 bit bus)
	mem := mem & 0x3FFF

	if write {
		if cart_ppu_write(nes, mem, val) {
			// Cartridge took care of the ppu write. return.
			return 0
		}
	} else {
		if val_read, ok := cart_ppu_read(nes, mem); ok {
			// Cartridge took care of the ppu read. return.
			return val_read
		}
	}

	switch mem {

	// Pattern tables
	// it's in cartridge's CHR ROM
	case 0x0000 ..= 0x1FFF:
		// if write {
		// 	fmt.eprintfln("u are trying to write to cartridge's ROM...")
		// 	return 0
		// }

		the_val = &nes.chr_mem[mem]
	// nametable data (it's in ppu memory)
	case 0x2000 ..< 0x3000:
		index_in_vram := mem - 0x2000

		// is_horizontal_arrengement = false -> horizontal mirroring (ice climber)
		// is_horizontal_arrengement = true -> vertical mirroring (super mario bros)

		// the part of mem into each nametable
		mem_modulo := index_in_vram % 0x400

		mirror_mode := get_mirror_mode(nes^)

		switch mem {
		// First virtual nametable slot
		case 0x2000 ..< 0x2400:
			switch mirror_mode {
				case .ScreenAOnly, .Vertical, .Horizontal:
				// write to first slot
				index_in_vram = mem_modulo
				case .ScreenBOnly:
				index_in_vram = mem_modulo + 0x400
			}
		// Second virtual nametable slot
		case 0x2400 ..< 0x2800:
			switch mirror_mode {
				case .Vertical, .ScreenAOnly:
				// write to first slot
				index_in_vram = mem_modulo
				case .Horizontal, .ScreenBOnly:
				// write to second slot
				index_in_vram = mem_modulo + 0x400
			}
		// Third virtual nametable slot
		case 0x2800 ..< 0x2C00:
			switch mirror_mode {
				case .Vertical, .ScreenBOnly:
				// write to second slot
				index_in_vram = mem_modulo + 0x400
				case .Horizontal, .ScreenAOnly:
				// write to first slot
				index_in_vram = mem_modulo
			}
		// Fourth virtual nametable slot
		case 0x2C00 ..< 0x3000:
			switch mirror_mode {
				case .Vertical, .ScreenBOnly, .Horizontal:
				// write to second slot
				index_in_vram = mem_modulo + 0x400
				case .ScreenAOnly:
				// write to first slot
				index_in_vram = mem_modulo
			}
		}

		// fmt.printfln("is horizontal arrangement %v. %X -> %X", nes.rom_info.is_horizontal_arrangement, mem, index_in_vram + 0x2000)

		the_val = &memory[index_in_vram]
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

		the_val = &palette[palette_mem]
	case:
		if write {
			fmt.eprintfln("idk what u writing here at ppu bus %X", mem)

		} else {
			fmt.eprintfln("idk what u reading here at ppu bus %X", mem)
		}
	}

	if write {
		the_val^ = val
	}

	return the_val^
}


// loads the background shifters with data of the next tile, on the least significant byte
load_bg_shifters :: proc(using ppu: ^PPU) {

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

// shifts the bg shifter registers by 1 bit to the left
shift_bg_shifters :: proc(using ppu: ^PPU) {
	if ppu_mask.show_background != 0 {
		bg_shifter_pattern_lo <<= 1
		bg_shifter_pattern_hi <<= 1
		bg_shifter_attrib_lo <<= 1
		bg_shifter_attrib_hi <<= 1
	}
}

// shifts the fg shifter registers by 1 bit to the left
//  when some conditions are hit
shift_fg_shifters :: proc(using ppu: ^PPU) {
	// shifting sprite shifters (only when they hit the cycle)
	if ppu_mask.show_sprites != 0 && cycle_x >= 0 && cycle_x < 258 {
		for i in 0 ..< sprite_count {
			if int(sprite_scanline[i].x) < cycle_x - 1 {
				sprite_shifter_pattern_lo[i] <<= 1
				sprite_shifter_pattern_hi[i] <<= 1
			}
		}
	}
}

increment_scroll_x :: proc(using ppu: ^PPU) {
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

increment_scroll_y :: proc(using ppu: ^PPU) {
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
		// flipping nametable y
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
transfer_address_x :: proc(using ppu: ^PPU) {

	if !(ppu_mask.show_background != 0 || ppu_mask.show_sprites != 0) {
		return
	}

	current_loopy.nametable_x = temp_loopy.nametable_x
	current_loopy.coarse_x = temp_loopy.coarse_x
}

transfer_address_y :: proc(using ppu: ^PPU) {
	if !(ppu_mask.show_background != 0 || ppu_mask.show_sprites != 0) {
		return
	}

	current_loopy.fine_y = temp_loopy.fine_y
	current_loopy.nametable_y = temp_loopy.nametable_y
	current_loopy.coarse_y = temp_loopy.coarse_y
}

// returns true if it hit a vblank
ppu_tick :: proc(nes: ^NES, framebuffer: ^PixelGrid) {

	using nes.ppu

	// read "PPU Rendering"

	// 262 scanlines

	// scanline guide:
	// -1: pre-render scanline
	// 0..= 239: visible scanlines
	// 240: post render scanline (it idles)
	// 241..=260: vertical blanking lines

	// cycle_x guide:
	// 0: idle cycle
	// 1..=256: fetching data
	// 257..=320: fetching tile data for sprites on next scanline
	// 321..=336: fetching two tiles for next scanline
	// 337..=340: fetching nametable bytes but it is unused

	// pre-render scanline
	if scanline == -1 {
		if cycle_x == 1 {
			ppu_status.vertical_blank = 0
			ppu_status.sprite_overflow = 0
			ppu_status.sprite_zero_hit = 0

			for i in 0 ..< 8 {
				sprite_shifter_pattern_hi[i] = 0
				sprite_shifter_pattern_lo[i] = 0
			}
		}

		if cycle_x >= 280 && cycle_x < 305 {
			transfer_address_y(&nes.ppu)
		}
	}

	// doing all the background data loading
	if scanline >= -1 && scanline < 240 {
		if (cycle_x > 0 && cycle_x < 258) || (cycle_x >= 321 && cycle_x <= 336) {
			shift_bg_shifters(&nes.ppu)
			switch (cycle_x - 1) % 8 {
			case 0:
				load_bg_shifters(&nes.ppu)

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

				addr: u16 = (u16(ppu_ctrl.b) << 12) + (u16(bg_next_tile_id) << 4) + current_loopy.fine_y + 0

				bg_next_tile_lsb = ppu_read(nes, addr)
				// if cycle_x == 141 && scanline == 220 {
				// 	fmt.printfln("cx: %v, bg next tile lsb %X", cycle_x, bg_next_tile_lsb)
				// }
			case 6:
				addr: u16 = (u16(ppu_ctrl.b) << 12) + (u16(bg_next_tile_id) << 4) + current_loopy.fine_y + 8

				// fetch the next background tile bitplane 2 (msb)
				bg_next_tile_msb = ppu_read(nes, addr)

				// if cycle_x == 143 && scanline == 220 {
				// 	fmt.printfln("cx: %v, bg next tile msb %X", cycle_x, bg_next_tile_msb)
				// }
			case 7:
				// increment scroll x
				increment_scroll_x(&nes.ppu)
			}
		}

		if cycle_x == 256 {
			increment_scroll_y(&nes.ppu)
		}

		if cycle_x == 257 {
			load_bg_shifters(&nes.ppu)
			transfer_address_x(&nes.ppu)
		}

		// Superfluous reads of tile id at end of scanline
		if (cycle_x == 338 || cycle_x == 340) {
			addr: u16 = 0x2000 | (current_loopy.reg & 0x0FFF)
			bg_next_tile_id = ppu_read(nes, addr)
		}

		if (scanline == -1 && cycle_x >= 280 && cycle_x < 305) {
			// End of vertical blank period so reset the Y address ready for rendering
			transfer_address_y(&nes.ppu)
		}

		// Foreground rendering

		shift_fg_shifters(&nes.ppu)

		// doing it at all visible scanlines, at cycle 257 (non visible)
		// evaluating sprites at next scanline

		// This is the correct way to do it but it doesn't work

		// well it seems like it works except
		// the scroll split in smb is done 1 pixel too early

		if scanline < 239 && cycle_x == 257 {
			evaluate_sprites(&nes.ppu, scanline + 1)
		}

		if scanline < 239 && cycle_x == 340 {
			update_sprite_shift_registers(nes, scanline + 1)
		}

		// this is javidx's way and it's wrong. it's evaluating the current scanline 
		//   but that one is already rendered!
		// if scanline >= 0 && cycle_x == 257 {
		// 	evaluate_sprites(nes, scanline)
		// }

		// if scanline <= 239 && cycle_x == 340 {
		// 	update_sprite_shift_registers(nes, scanline)
		// }
	}

	// Setting vblank
	if scanline == 241 && cycle_x == 1 {
		ppu_status.vertical_blank = 1
		nes.vblank_hit = true
		if ppu_ctrl.v != 0 {
			// nmi(nes, false)
			nes.nmi_triggered = 1
		}
	}

	if (ppu_mask.show_background != 0 || ppu_mask.show_sprites != 0) && cycle_x == 260 && scanline < 240 {
		nes.m_scanline_hit(nes)
	}

	/// Rendering the current pixel
	draw_pixel(&nes.ppu, framebuffer)

	cycle_x += 1
	if cycle_x >= 341 {
		cycle_x = 0
		scanline += 1
		if scanline >= 261 {
			scanline = -1
		}
	}
}

// Does the sprite evaluation for the next scanline
evaluate_sprites :: proc(using ppu: ^PPU, current_scanline: int) {
	// clear sprite scanline array to 0xFF
	slice.fill(slice.to_bytes(sprite_scanline[:]), 0xFF)
	sprite_count = 0

	oam_entry: u8
	sprite_zero_hit_possible = false

	oam_entries := slice.reinterpret([]OAMEntry, oam[:])

	for oam_entry < 64 && sprite_count < 9 {

		// figuring out if the sprite is going to be visible on the next scanline
		//  by looking at the Y position and the height of the sprite

		// TODO: this is like evaluating the current scanline
		// .  but u should evaluate the next one. what's going on?

		diff: u16 = u16(current_scanline) - (u16(oam_entries[oam_entry].y) + 1)

		if diff >= 0 && diff < (ppu_ctrl.h != 0 ? 16 : 8) {
			if sprite_count < 8 {

				// is this sprite zero?
				if oam_entry == 0 {
					sprite_zero_hit_possible = true
				}

				// copy sprite to sprite scanline array
				sprite_scanline[sprite_count] = oam_entries[oam_entry]
				sprite_scanline[sprite_count].y += 1
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

update_sprite_shift_registers :: proc(nes: ^NES, current_scanline: int) {

	using nes.ppu

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
draw_pixel :: proc(using ppu: ^PPU, pixel_grid: ^PixelGrid) {
	// checks before bothering to draw a pixel

	// checks if it's on a visible pixel
	if !(scanline >= 0 && scanline <= 239 && cycle_x > 0 && cycle_x <= 256) {
		return
	}

	// Background pixel
	bg_pixel: u8
	bg_palette: u8

	bit_mux: u16 = 0x8000 >> ppu_x

	p0_pixel: u8 = (bg_shifter_pattern_lo & bit_mux) > 0 ? 1 : 0
	p1_pixel: u8 = (bg_shifter_pattern_hi & bit_mux) > 0 ? 1 : 0
	bg_pixel = (p1_pixel << 1) | p0_pixel

	bg_pal0: u8 = (bg_shifter_attrib_lo & bit_mux) > 0 ? 1 : 0
	bg_pal1: u8 = (bg_shifter_attrib_hi & bit_mux) > 0 ? 1 : 0
	bg_palette = (bg_pal1 << 1) | bg_pal0

	if ppu_mask.show_background == 0 || (cycle_x <= 8 && ppu_mask.show_left_background == 0) {
		bg_pixel = 0
	}

	// foreground pixel

	fg_pixel: u8
	fg_palette: u8
	fg_priority: u8

	if ppu_mask.show_sprites != 0 {

		sprite_zero_being_rendered = false

		for i in 0 ..< sprite_count {

			if int(sprite_scanline[i].x) > cycle_x - 1 {
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

	if ppu_mask.show_sprites == 0 || (cycle_x <= 8 && ppu_mask.show_left_sprites == 0) {
		fg_pixel = 0
	}

	// combining background pixel and foreground pixel

	pixel: u8
	palette_final: u8

	if bg_pixel == 0 && fg_pixel == 0 {
		pixel = 0
		palette_final = 0
	} else if bg_pixel == 0 && fg_pixel > 0 {
		pixel = fg_pixel
		palette_final = fg_palette
	} else if bg_pixel > 0 && fg_pixel == 0 {
		pixel = bg_pixel
		palette_final = bg_palette
	} else if bg_pixel > 0 && fg_pixel > 0 {

		// both bg and fg are visible.

		if fg_priority != 0 {
			pixel = fg_pixel
			palette_final = fg_palette
		} else {
			pixel = bg_pixel
			palette_final = bg_palette
		}

		// sprite zero hit detection
		if sprite_zero_being_rendered && sprite_zero_hit_possible {
			if ppu_mask.show_background != 0 && ppu_mask.show_sprites != 0 {

				if ~(ppu_mask.show_left_background | ppu_mask.show_left_sprites) != 0 {
					if cycle_x >= 9 && cycle_x <= 255 {
						ppu_status.sprite_zero_hit = 1
					}

				} else {
					if cycle_x >= 1 && cycle_x <= 255 {
						ppu_status.sprite_zero_hit = 1
					}
				}
			}
		}
	}

	nes_color := get_color_from_palettes(ppu^, pixel, palette_final)
	real_color := color_map_from_nes_to_real(nes_color)

	// position of pixel
	pos_x := cycle_x - 1
	pos_y := scanline

	pixel_grid.pixels[pos_y * 256 + pos_x] = real_color
}

// Gets color byte in palette, given a bg palette and a color inside the palette
get_color_from_palettes :: proc(using ppu: PPU, pixel: u8, palette_idx: u8) -> u8 {

	palette_start: u16

	switch palette_idx {
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
		return palette[0]
	case:
		return palette[palette_start + u16(pixel) - 1]
	}
}
