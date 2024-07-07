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


	// PPUSCROLL
	case 0x2005:
		// fmt.println("writing to ppuscroll")
	//

	// PPUADDR
	case 0x2006:
		// fmt.println("writing to ppuaddr")


		// writes a 16 bit VRAM address, 1 bytes at a time(games have to call this twice)

		// writes to upper byte first

		// TODO write to ppu_v based on ppu_w
		if ppu_w {
			ppu_v = (ppu_v & 0xFF00) | uint(val)
		} else {
			ppu_v = uint(val) << 8 | (ppu_v & 0x00FF)
		}

		ppu_w = !ppu_w

		// fmt.printfln(
		// 	"-- PPU interaction! call to PPUADDR!! writing: %X. ppu_v is now %X",
		// 	val,
		// 	ppu_v,
		// )
		return

	//PPUDATA
	case 0x2007:
		// this is what you use to read/write to PPU memory (VRAM)
		// this is what games use to fill nametables, change palettes, and more.

		// it will write to the set 16 bit VRAM address set by PPUADDR (u need to store this address somewhere)
		// fmt.printfln(
		// 	"-- PPU interaction! call to PPUDATA!! writing: %X to PPU ADDRESS: %X",
		// 	val,
		// 	ppu_v,
		// )
        ppu_write(nes, u16(ppu_v), val)
        increment_ppu_v(nes)
		return
	}

}

read_ppu_register :: proc(using nes: ^NES, ppu_reg: u16) -> u8 {
	switch ppu_reg {

	// PPUCTRL
	case 0x2000:
		// return garbage if they try to read this. "open bus"
		// https://forums.nesdev.org/viewtopic.php?t=6426

		fmt.eprintfln("should not read to ppuctrl. it's write only")
		return ppu_ctrl.reg

	// PPUMASK
	case 0x2001:

        // TODO


		fmt.eprintfln("should not read to ppumask. it's write only")
		return ram[ppu_reg]

	// PPUSTATUS
	case 0x2002:
		//TODO

		// return v blank as 1, rest 0

		// clear bit 7

		// clear address latch
		ppu_status: u8

		if ppu_on_vblank {
			ppu_status |= 0x80
		}

		ppu_on_vblank = false

		// fmt.printfln("reading ppu status. clearing latch")
		ppu_w = false
		return ppu_status

	// PPUDATA
	case 0x2007:
		// fmt.printfln("reading PPUDATA")
        val := ppu_read(nes, u16(ppu_v))
        increment_ppu_v(nes)
		return val

	// OAMADDR
	case 0x2003:
		// fmt.eprintfln("should not read to oamaddr. it's write only")
		return ram[ppu_reg]

	// OAMDATA
	case 0x2004:
		// fmt.printfln("reading oamdata")
		return ram[ppu_reg]

	case:
		return ram[ppu_reg]
	}
}

increment_ppu_v :: proc(using nes: ^NES) {
		goDown: bool = ppu_ctrl.i != 0

		if goDown {
			ppu_v += 32
		} else {
			ppu_v += 1
		}
}

ppu_read :: proc(using nes: ^NES, mem: u16) -> u8{
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
    the_val : ^u8 = &temp_val

    switch mem {

        // Pattern tables
        // it's in cartridge's CHR ROM
        case 0x0000..=0x0FFF:
            fmt.eprintln("u are trying to write to cartridge's ROM...")

        // nametable data (it's in ppu memory)
        // TODO: implement mirroring
        case 0x2000..=0x2FFF:

            index_in_vram := mem - 0x2000

            the_val = &ppu_memory[index_in_vram]
        case 0x3000..=0x3EFF:
            // unused addresses... return bus
            return 0

        // Palette RAM indexes
        case 0x3F00..=0x3FFF:

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