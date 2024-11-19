package main

Mapper :: enum {
	M0, // NROM128, NROM256
	M1, // ??? 
	M2, // UXROM
    M3, // CNROM
}

MapperData :: union {
	M0Data,
	M1Data,
	M2Data,
    M3Data,
}

// does the write depending on the current mapper.
// returns true if it did anything. returns false if it should do a normal NES read.
cart_cpu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	data_read: u8
	ok: bool

	// Dispatches to mapper
	switch rom_info.mapper {
	case .M0:
		data := mapper_data.(M0Data)
		data_read, ok = m0_cpu_read(nes, addr, data)
	case .M1:
		data := mapper_data.(M1Data)
		data_read, ok = m1_cpu_read(nes, addr, data)
	case .M2:
		data := mapper_data.(M2Data)
		data_read, ok = m2_cpu_read(nes, addr, data)
	case .M3:
		data := mapper_data.(M3Data)
		data_read, ok = m3_cpu_read(nes, addr, data)
	}

	return data_read, ok
}

// does the write depending on the current mapper.
// returns true if it did anything. returns false if it should do a normal NES write.
cart_cpu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {

	ok: bool

	// Dispatches to mapper
	switch rom_info.mapper {
	case .M0:
		data := &mapper_data.(M0Data)
		ok = m0_cpu_write(nes, data, addr, val)
	case .M1:
		data := &mapper_data.(M1Data)
		ok = m1_cpu_write(nes, data, addr, val)
	case .M2:
		data := &mapper_data.(M2Data)
		ok = m2_cpu_write(nes, data, addr, val)
	case .M3:
		data := &mapper_data.(M3Data)
		ok = m3_cpu_write(nes, data, addr, val)
	}

	return ok
}

cart_ppu_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {

    data_read: u8
    ok: bool

    #partial switch rom_info.mapper {
        case .M3:
            data := mapper_data.(M3Data)
            data_read, ok = m3_ppu_read(nes, addr, data)
        case:
    }

    return data_read, ok
}

cart_ppu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
    ok: bool

    #partial switch rom_info.mapper {
        case .M3:
            data := &mapper_data.(M3Data)
            ok = m3_ppu_write(nes, data, addr, val)
    }

    return ok
}

// Mapper 0

M0Data :: struct {
	is_128: bool, // true: 128, false: 256
    // refactor to number of banks
}

m0_cpu_read :: proc(using nes: ^NES, addr: u16, data: M0Data) -> (u8, bool) {
	if data.is_128 {
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

m0_cpu_write :: proc(using nes: ^NES, data: ^M0Data, addr: u16, val: u8) -> bool {
	return false
}

// Mapper 1

M1Data :: struct {}

m1_cpu_read :: proc(using nes: ^NES, addr: u16, data: M1Data) -> (u8, bool) {


	return 0, false
}

m1_cpu_write :: proc(using nes: ^NES, data: ^M1Data, addr: u16, val: u8) -> bool {
	return true
}

// Mapper 2

M2Data :: struct {
	bank: uint,
}

m2_cpu_read :: proc(using nes: ^NES, addr: u16, data: M2Data) -> (u8, bool) {
	switch addr {
	case 0x8000 ..< 0xC000:
		// use the bank i guess
		// data.bank <- use that
		// fmt.printfln("reading switchable memory. bank is %v", data.bank)
		return prg_rom[uint(addr) - 0x8000 + (data.bank * 0x4000)], true
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

m2_cpu_write :: proc(using nes: ^NES, data: ^M2Data, addr: u16, val: u8) -> bool {
	switch addr {
	case 0x8000 ..= 0xFFFF:
        // here u do the bank switch
		data.bank = uint(val) & 0x0F
        return true
	}

	return false
}

// Mapper 3

M3Data :: struct {
    is_128: bool, // refactor to number of banks
	bank: uint,
}

// todo
m3_cpu_read :: proc(using nes: ^NES, addr: u16, data: M3Data) -> (u8, bool) {
    // same as mapper 0
	if data.is_128 {
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

m3_cpu_write :: proc(using nes: ^NES, data: ^M3Data, addr: u16, val: u8) -> bool {
    // same as mapper 2
	switch addr {
	case 0x8000 ..= 0xFFFF:
        // here u do the bank switch
		data.bank = uint(val) & 0x03
        return true
	}

	return false
}

m3_ppu_read :: proc(using nes: ^NES, addr: u16, data: M3Data) -> (u8, bool) {

    if addr < 0x2000 {
        return chr_rom[u16(data.bank) * 0x2000 + addr], true
    }

    return 0, false
}

m3_ppu_write :: proc(using nes: ^NES, data: ^M3Data, addr: u16, val: u8) -> bool {
    return false
}
