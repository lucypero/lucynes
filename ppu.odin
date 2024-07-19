package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
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
		} else { 	// Second write
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
	case 0x0000 ..= 0x0FFF:
		if write {
			fmt.eprintln("u are trying to write to cartridge's ROM...")
		}

		the_val = &chr_rom[mem]

	// nametable data (it's in ppu memory)
	// TODO: implement mirroring
	case 0x2000 ..= 0x2FFF:
		index_in_vram := mem - 0x2000

		// the part of mem into each nametable
		mem_modulo := index_in_vram % 0x400

		switch mem {
		case 0x2000 ..= 0x23FF:
			if nes.rom_info.is_horizontal_arrangement {
				// write to first slot
				index_in_vram = mem_modulo
			} else {
				// write to first slot
				index_in_vram = mem_modulo
			}
		case 0x2400 ..= 0x27FF:
			if nes.rom_info.is_horizontal_arrangement {
				// write to first slot
				index_in_vram = mem_modulo
			} else {
				// write to second slot
				index_in_vram = mem_modulo + 0x400
			}
		case 0x2800 ..= 0x2BFF:
			if nes.rom_info.is_horizontal_arrangement {
				// write to second slot
				index_in_vram = mem_modulo + 0x400
			} else {
				// write to first slot
				index_in_vram = mem_modulo
			}
		case 0x2C00 ..= 0x2FFF:
			if nes.rom_info.is_horizontal_arrangement {
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
		fmt.eprintfln("idk what u writing here at ppu bus %X", mem)

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
shift_shifters :: proc(using nes: ^NES) {
	if (ppu_mask.show_background != 0) {
		bg_shifter_pattern_lo <<= 1
		bg_shifter_pattern_hi <<= 1
		bg_shifter_attrib_lo <<= 1
		bg_shifter_attrib_hi <<= 1
	}
}


increment_scroll_x :: proc(using nes: ^NES) {
	// TODO
}


// returns true if it hit a vblank
ppu_tick :: proc(using nes: ^NES) -> bool {

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

	// Vertical blanking lines (241-260)
	// The VBlank flag of the PPU is set at tick 1 (the second tick) of scanline 241, where the VBlank NMI also occurs. The PPU makes no memory accesses during these scanlines, so PPU memory can be freely accessed by the program. 


	// cycle 0
	switch scanline {
	// visible scanlines
	case 0 ..= 239:
		shift_shifters(nes)

		switch cycle_x % 8 {
		case 0:
			load_bg_shifters(nes)

			// fetch the next background tile ID
			bg_next_tile_id = ppu_read(nes, 0x2000 | current_loopy.reg & 0x0FFF)
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

			if (current_loopy.coarse_y & 0x02 != 0) {bg_next_tile_attrib >>= 4}
			if (current_loopy.coarse_x & 0x02 != 0) {bg_next_tile_attrib >>= 2}

			// you need only 2 bits
			bg_next_tile_attrib &= 0x03

		case 4:

			// fetch the next background tile bitplane 1 (lsb)
			bg_next_tile_lsb = ppu_read(nes, u16(ppu_ctrl.b << 12) +
										 u16(bg_next_tile_id << 4) +
										 current_loopy.fine_y) + 0

		case 6:

			// fetch the next background tile bitplane 2 (msb)
			bg_next_tile_msb = ppu_read(nes, u16(ppu_ctrl.b << 12) +
										 u16(bg_next_tile_id << 4) +
										 current_loopy.fine_y) + 8

	    case 7:
			// increment scroll x
			increment_scroll_x(nes)
		}

	// you gotta do certain things...


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

	case:
	// vblank scanlines
	}

	ppu_cycles += 1

	if ppu_cycles > 341 * 262 {
		ppu_cycles = 0
	}

	return hit_vblank
}
