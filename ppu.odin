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
