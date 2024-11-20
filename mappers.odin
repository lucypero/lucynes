package main

import "core:os"
import "core:fmt"

Mapper :: enum {
	M0, // NROM128, NROM256
	M1, // ??? 
	M2, // UXROM
	M3, // CNROM
	M66, // GxROM
}

MapperData :: union {
	M0Data,
	M1Data,
	M2Data,
	M3Data,
	M66Data,
}

mapper_init :: proc(using nes: ^NES, mapper_number: u8, byte_4: u8) {
	switch mapper_number {
	case 0:
		rom_info.mapper = .M0
		data: M0Data
		if byte_4 == 1 {
			data.is_128 = true
		} else {
			data.is_128 = false
		}
		nes.mapper_data = data
		m_cpu_read = m0_cpu_read
		m_cpu_write = m0_cpu_write
		m_ppu_read = m_dummy_read
		m_ppu_write = m_dummy_write
	case 1:
		rom_info.mapper = .M1
		nes.mapper_data = M1Data{}
		m_cpu_read = m1_cpu_read
		m_cpu_write = m1_cpu_write
		m_ppu_read = m_dummy_read
		m_ppu_write = m_dummy_write
	case 2:
		rom_info.mapper = .M2
		nes.mapper_data = M2Data{}
		m_cpu_read = m2_cpu_read
		m_cpu_write = m2_cpu_write
		m_ppu_read = m_dummy_read
		m_ppu_write = m_dummy_write
	case 3:
		rom_info.mapper = .M3
		nes.mapper_data = M3Data{}
		m_cpu_read = m3_cpu_read
		m_cpu_write = m3_cpu_write
		m_ppu_read = m3_ppu_read
		m_ppu_write = m3_ppu_write
	case 66:
		rom_info.mapper = .M66
		nes.mapper_data = M66Data{}
		m_cpu_read = m66_cpu_read
		m_cpu_write = m66_cpu_write
		m_ppu_read = m66_ppu_read
		m_ppu_write = m66_ppu_write
	case:
		fmt.eprintfln("mapper not supported: %v. exiting", mapper_number)
		os.exit(1)
	}

	fmt.printfln("rom mapper n: %v", mapper_number)
}

// does the write depending on the current mapper.
// returns true if it did anything. returns false if it should do a normal NES read.
cart_cpu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	data_read: u8
	ok: bool

	data_read, ok = m_cpu_read(nes, addr)

	return data_read, ok
}

// does the write depending on the current mapper.
// returns true if it did anything. returns false if it should do a normal NES write.
cart_cpu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	ok: bool
	ok = m_cpu_write(nes, addr, val)
	return ok
}

cart_ppu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	data_read: u8
	ok: bool
	data_read, ok = m_ppu_read(nes, addr)
	return data_read, ok
}

cart_ppu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	ok: bool
	ok = m_ppu_write(nes, addr, val)
	return ok

}

m_dummy_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	return 0, false
}

m_dummy_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	return false
}

// Mapper 0

M0Data :: struct {
	is_128: bool, // true: 128, false: 256
	// refactor to number of banks
}

m0_cpu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M0Data)

	if m_data.is_128 {
		switch addr {
		case 0x8000 ..< 0xC000:
			return prg_rom[addr - 0x8000], true
		case 0xC000 ..= 0xFFFF:
			return prg_rom[addr - 0xC000], true
		}
	} else {
		switch addr {
		case 0x8000 ..= 0xFFFF:
			return prg_rom[addr - 0x8000], true
		}
	}
	return 0, false
}

m0_cpu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	return false
}

// Mapper 1

M1Data :: struct {}

m1_cpu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {


	return 0, false
}

m1_cpu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	return true
}

// Mapper 2

M2Data :: struct {
	bank: uint,
}

m2_cpu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M2Data)
	switch addr {
	case 0x8000 ..< 0xC000:
		// use the bank i guess
		// data.bank <- use that
		// fmt.printfln("reading switchable memory. bank is %v", data.bank)
		return prg_rom[uint(addr) - 0x8000 + (m_data.bank * 0x4000)], true
	case 0xC000 ..= 0xFFFF:
		// it's the last bank
		// fmt.printfln("reading last bank")
		offset: uint = uint(addr) - 0xC000
		bank_count: uint = len(prg_rom) / 0x4000
		bank_offset := (uint(bank_count) - 1) * 0x4000
		return prg_rom[bank_offset + offset], true
	}

	return 0, false
}

m2_cpu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	m_data := &nes.mapper_data.(M2Data)
	switch addr {
	case 0x8000 ..= 0xFFFF:
		// here u do the bank switch
		m_data.bank = uint(val) & 0x0F
		return true
	}

	return false
}

// Mapper 3

M3Data :: struct {
	is_128:              bool, // refactor to number of banks
	prg_rom_bank_select: uint,
}

m3_cpu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M3Data)

	// same as mapper 0
	if m_data.is_128 {
		switch addr {
		case 0x8000 ..< 0xC000:
			return prg_rom[addr - 0x8000], true
		case 0xC000 ..= 0xFFFF:
			return prg_rom[addr - 0xC000], true
		}
	} else {
		switch addr {
		case 0x8000 ..= 0xFFFF:
			return prg_rom[addr - 0x8000], true
		}
	}
	return 0, false
}

m3_cpu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	m_data := &nes.mapper_data.(M3Data)

	// same as mapper 2
	switch addr {
	case 0x8000 ..= 0xFFFF:
		// here u do the bank switch
		m_data.prg_rom_bank_select = uint(val) & 0x03
		return true
	}

	return false
}

m3_ppu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M3Data)

	if addr < 0x2000 {
		return chr_rom[u16(m_data.prg_rom_bank_select) * 0x2000 + addr], true
	}

	return 0, false
}

m3_ppu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	return false
}

// Mapper 66 (Untested. test some games using this mapper)
// TODO test
M66Data :: struct {
	chr_bank_select: u16,
	prg_bank_select: u16,
}

m66_cpu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M66Data)

	if addr >= 0x8000 && addr <= 0xFFFF {
		// this is the best way to do it so far i think
		// 0x8000 = 32 KiB window
		// you add the offset
		prg_addr := m_data.prg_bank_select * 0x8000 + (addr & 0x7FFF)
		return prg_rom[prg_addr], true
	}

	return 0, false
}

m66_cpu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	m_data := &nes.mapper_data.(M66Data)

	if addr >= 0x8000 && addr <= 0xFFFF {
		m_data.chr_bank_select = u16(val & 0x03)
		m_data.prg_bank_select = u16((val & 0x30) >> 4)
		return true
	}

	return false
}

m66_ppu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M66Data)

	if addr < 0x2000 {
		// 0x2000 = 8 KiB bank window
		chr_addr := m_data.chr_bank_select * 0x2000 + addr 
		return chr_rom[chr_addr], true
	}

	return 0, false
}

m66_ppu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	m_data := &nes.mapper_data.(M66Data)

	return false
}
