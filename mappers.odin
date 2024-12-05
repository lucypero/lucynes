package main

import "core:os"
import "core:fmt"
import "core:time"

Mapper :: enum {
	M0, // NROM128, NROM256
	M1, // MMC1
	M2, // UXROM
	M3, // CNROM
	M4, // MMC3
	M66, // GxROM
	M7, // AxROM
}

MapperData :: union {
	M0Data,
	M1Data,
	M2Data,
	M3Data,
	M4Data,
	M66Data,
	M7Data,
}

mapper_init :: proc(using nes: ^NES, mapper_number: u8, prg_unit_count: u8, chr_unit_count: u8) -> (mapper: Mapper) {
	m_scanline_hit = m_scanline_hit_dummy
	m_get_irq_state = m_get_irq_state_dummy
	m_irq_clear = m_irq_clear_dummy
	m_ppu_read = m_dummy_read
	m_ppu_write = m_dummy_write
	switch mapper_number {
	case 0:
		mapper = .M0
		data: M0Data
		if prg_unit_count == 1 {
			data.is_128 = true
		} else {
			data.is_128 = false
		}
		nes.mapper_data = data
		m_cpu_read = m0_cpu_read
		m_cpu_write = m0_cpu_write
	case 1:
		mapper = .M1
		m1_data := M1Data{}
		m1_data.prg_bank_count = prg_unit_count
		m1_data.chr_bank_count = chr_unit_count
		m1_data.control_register = 0x1C
		m1_data.prg_bank_select_16hi = prg_unit_count - 1
		nes.mapper_data = m1_data
		m_cpu_read = m1_cpu_read
		m_cpu_write = m1_cpu_write
		m_ppu_read = m1_ppu_read
		m_ppu_write = m1_ppu_write
	case 2:
		mapper = .M2
		nes.mapper_data = M2Data{}
		m_cpu_read = m2_cpu_read
		m_cpu_write = m2_cpu_write
	case 3:
		mapper = .M3
		nes.mapper_data = M3Data{}
		m_cpu_read = m3_cpu_read
		m_cpu_write = m3_cpu_write
		m_ppu_read = m3_ppu_read
		m_ppu_write = m3_ppu_write
	case 4:
		mapper = .M4
		// Resetting m4 data
		m4_data := M4Data{}
		m4_data.prg_bank_count = prg_unit_count
		m4_data.chr_bank_count = chr_unit_count
		m4_data.mirror_mode = .Horizontal
		m4_data.prg_banks[0] = 0 * 0x2000
		m4_data.prg_banks[1] = 1 * 0x2000
		m4_data.prg_banks[2] = (u32(m4_data.prg_bank_count) * 2 - 2) * 0x2000
		m4_data.prg_banks[3] = (u32(m4_data.prg_bank_count) * 2 - 1) * 0x2000

		nes.mapper_data = m4_data
		m_cpu_read = m4_cpu_read
		m_cpu_write = m4_cpu_write
		m_ppu_read = m4_ppu_read
		m_ppu_write = m4_ppu_write
		m_scanline_hit = m4_scanline_hit
		m_get_irq_state = m4_get_irq_state
		m_irq_clear = m4_irq_clear
	case 7:
		mapper = .M7
		m7_data := M7Data{}
		m7_data.prg_bank_count = prg_unit_count
		m7_data.mirror_mode = .ScreenAOnly
		nes.mapper_data = m7_data
		m_cpu_read = m7_cpu_read
		m_cpu_write = m7_cpu_write
	case 66:
		mapper = .M66
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

	return mapper
}

get_mirror_mode :: proc(nes: NES) -> MirrorMode {
	#partial switch nes.rom_info.mapper {
	case .M1:
		m1_data := nes.mapper_data.(M1Data)
		return m1_data.mirror_mode
	case .M4:
		m4_data := nes.mapper_data.(M4Data)
		return m4_data.mirror_mode
	case .M7:
		m7_data := nes.mapper_data.(M7Data)
		return m7_data.mirror_mode
	}

	return nes.rom_info.mirror_mode_hardwired
}

// Dummy functions
// This is used when the mapper doesn't have this functionality.
m_dummy_read :: proc(using nes: ^NES, addr: u16) -> (u8, bool) {
	return 0, false
}

m_dummy_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	return false
}

m_scanline_hit_dummy :: proc(nes: ^NES) {
}

m_get_irq_state_dummy :: proc(nes: ^NES) -> bool {
	return false
}

m_irq_clear_dummy :: proc(nes: ^NES) {

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

M1Data :: struct {
	chr_bank_select_4lo:  u8, // 0x1000 sized banks
	chr_bank_select_4hi:  u8, // 0x1000 sized banks
	chr_bank_select_8:    u8, // 0x2000 sized banks
	prg_bank_select_16lo: u8, // 0x4000 sized banks
	prg_bank_select_16hi: u8, // 0x4000 sized banks
	prg_bank_select_32:   u8, // 0x8000 sized banks
	load_register:        u8,
	load_register_count:  u8,
	control_register:     u8,
	mirror_mode:          MirrorMode,

	// how many 16kb chunks of prg data in the cart
	prg_bank_count:       u8,
	// how many 8kb chunks of chr data in the cart
	chr_bank_count:       u8,
}

m1_cpu_read :: proc(nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M1Data)
	using m_data

	switch addr {
	case 0x6000 ..= 0x7FFF:
		// read cart RAM
		// fmt.println("reading prg ram")
		val := nes.prg_ram[addr & 0x1FFF]
		return val, true
	case 0x8000 ..= 0xFFFF:
		if (control_register & 0x08) != 0 {

			// 16K Mode
			switch addr {
			case 0x8000 ..= 0xBFFF:
				// fmt.printfln("bank select 16 lo: %v", prg_bank_select_16lo)
				val_i := uint(prg_bank_select_16lo) * 0x4000 + (uint(addr) & 0x3FFF)
				// val_i %= (0xC000 - 0x8000)
				val := nes.prg_rom[val_i]
				return val, true
			case 0xC000 ..= 0xFFFF:
				// fmt.printfln("bank select 16 lo: %v", prg_bank_select_16hi)
				val_i := uint(prg_bank_select_16hi) * 0x4000 + (uint(addr) & 0x3FFF)
				// val_i %= (0xC000 - 0x8000)
				val := nes.prg_rom[val_i]
				return val, true
			}
		} else {

			// 32K Mode
			// fmt.printfln("bank select 32: %v", prg_bank_select_32)
			val_i := uint(prg_bank_select_32) * 0x8000 + (uint(addr) & 0x7FFF)
			// val_i %= len(nes.prg_rom)
			val := nes.prg_rom[val_i]
			return val, true
		}

	}

	return 0, false
}

m1_register_write :: proc(using m_data: ^M1Data, target_register: u16) {
	switch target_register {
	case 0:
		// 0x8000 - 0x9FFF

		// Set control register
		control_register = load_register & 0x1F

		// Set mirror mode

		switch control_register & 0x03 {
		case 0:
			mirror_mode = .ScreenAOnly
		case 1:
			mirror_mode = .ScreenBOnly
		case 2:
			mirror_mode = .Horizontal
		case 3:
			mirror_mode = .Vertical
		}
	case 1:
		// 0xA000 - 0xBFFF
		// Set CHR Bank Lo

		if (control_register & 0x10) != 0 {
			// 4K CHR Bank at PPU 0x0000
			chr_bank_select_4lo = (load_register & 0x1F)
			// chr_bank_select_4lo &= (chr_bank_count * 2) - 1

		} else {
			// 8K CHR Bank at PPU 0x0000
			chr_bank_select_8 = (load_register & 0x1E)
			// chr_bank_select_8 &= chr_bank_count - 1

		}
	case 2:
		// 0xC000 - 0xDFFF

		// Set CHR Bank Hi
		if (control_register & 0x10) != 0 {
			// 4K CHR Bank at PPU 0x1000
			chr_bank_select_4hi = (load_register & 0x1F)
			// chr_bank_select_4hi &= chr_bank_count * 2 - 1
		}
	case 3:
		// 0xE000 - 0xFFFF
		// Configure PRG Banks
		prg_mode: u8 = (control_register >> 2) & 0x03

		switch prg_mode {
		case 0, 1:
			// Set 32K PRG Bank at CPU 0x8000
			prg_bank_select_32 = (load_register & 0x0E) >> 1
			fmt.println("prg mode 0 or 1")
		// prg_bank_select_32 &= prg_bank_count / 2 - 1
		case 2:
			// Fix 16KB PRG Bank at CPU 0x8000 to First Bank
			prg_bank_select_16lo = 0
			fmt.println("prg mode 2")

			// Set 16KB PRG Bank at CPU 0xC000
			prg_bank_select_16hi = (load_register & 0x0F) % prg_bank_count
		// prg_bank_select_16hi &= prg_bank_count - 1
		case 3:
			// Set 16KB PRG Bank at CPU 0x8000
			prg_bank_select_16lo = (load_register & 0x0F)
			// fmt.printfln("setting bank select 16 lo: %v", prg_bank_select_16lo)
			prg_bank_select_16lo %= prg_bank_count
			// fmt.printfln("setting bank select 16 lo, after mask: %v", prg_bank_select_16lo)
			// Fix 16KB PRG Bank at CPU 0xC000 to Last Bank
			prg_bank_select_16hi = prg_bank_count - 1
		}
	}

}


m1_cpu_write :: proc(nes: ^NES, addr: u16, val: u8) -> bool {
	m_data := &nes.mapper_data.(M1Data)
	using m_data

	switch addr {

	case 0x6000 ..= 0x7FFF:
		// write to cart RAM


		// fmt.printfln("%v: writing to prg ram", time.now())
		nes.prg_ram[addr & 0x1FFF] = val
		// os.write_entire_file("ram-bup", nes.prg_ram)
		return true

	case 0x8000 ..= 0xFFFF:
		if (val & 0x80) != 0 {
			// bit 7 set. clear shift register
			load_register = 0
			load_register_count = 0
			control_register = control_register | 0x0C
		} else {
			// write to shift register with bit 0 of val
			load_register >>= 1
			load_register |= (val & 0x01) << 4
			load_register_count += 1

			if load_register_count == 5 {
				// fifth write. copy value to register
				// destination of copy is determined by addr
				target_register := (addr >> 13) & 0x03
				m1_register_write(m_data, target_register)
				load_register_count = 0
				load_register = 0
			}
		}

		return true
	}

	return false
}

m1_ppu_read :: proc(nes: ^NES, addr: u16) -> (u8, bool) {

	m_data := nes.mapper_data.(M1Data)
	using m_data

	if addr >= 0x2000 {
		return 0, false
	}

	if chr_bank_count == 0 {
		return nes.chr_mem[addr], true
	} else {
		if (control_register & 0x10) != 0 {
			// 4K CHR Bank mode
			switch addr {
			case 0x0000 ..= 0x0FFF:
				val_i := uint(chr_bank_select_4lo) * 0x1000 + (uint(addr) & 0x0FFF)
				val := nes.chr_mem[val_i]
				return val, true
			case 0x1000 ..= 0x1FFF:
				val_i := uint(chr_bank_select_4hi) * 0x1000 + (uint(addr) & 0x0FFF)
				val := nes.chr_mem[val_i]
				return val, true
			}
		} else {
			// 8K CHR Bank Mode
			val_i := uint(chr_bank_select_8) * 0x2000 + (uint(addr) & 0x1FFF)
			val := nes.chr_mem[val_i]
			return val, true
		}
	}

	return 0, false
}

m1_ppu_write :: proc(nes: ^NES, addr: u16, val: u8) -> bool {
	// m_data := nes.mapper_data.(M1Data)
	// using m_data

	// if addr < 0x2000 {
	// 	if chr_bank_count == 0 {
	// 		nes.chr_mem[addr] = val
	// 		return true
	// 	}
	// }

	return false
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
		return chr_mem[uint(m_data.prg_rom_bank_select) * 0x2000 + uint(addr)], true
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
		prg_addr := uint(m_data.prg_bank_select) * 0x8000 + (uint(addr) & 0x7FFF)
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
		chr_addr := uint(m_data.chr_bank_select) * 0x2000 + uint(addr)
		return chr_mem[chr_addr], true
	}

	return 0, false
}

m66_ppu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	m_data := &nes.mapper_data.(M66Data)

	return false
}

// Mapper 4

M4Data :: struct {
	// how many 16kb chunks of prg data in the cart
	prg_bank_count:  u8,
	// how many 8kb chunks of chr data in the cart
	chr_bank_count:  u8,

	// Control variables
	target_register: u8,
	prg_bank_mode:   bool,
	chr_inversion:   bool,
	mirror_mode:     MirrorMode,
	registers:       [8]u32,
	chr_banks:       [8]u32,
	prg_banks:       [4]u32,

	// IRQ
	irq_active:      bool,
	irq_enable:      bool,
	irq_update:      bool,
	irq_counter:     u16,
	irq_reload:      u16,
}

m4_cpu_read :: proc(nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M4Data)
	using m_data

	addr_uint := uint(addr)

	switch addr {
	case 0x6000 ..= 0x7FFF:
		// read cart RAM
		// fmt.println("reading prg ram")
		val := nes.prg_ram[addr & 0x1FFF]
		return val, true
	case 0x8000 ..= 0x9FFF:
		val_i := uint(prg_banks[0]) + (addr_uint & 0x1FFF)
		val := nes.prg_rom[val_i]
		return val, true
	case 0xA000 ..= 0xBFFF:
		val_i := uint(prg_banks[1]) + (addr_uint & 0x1FFF)
		val := nes.prg_rom[val_i]
		return val, true
	case 0xC000 ..= 0xDFFF:
		val_i := uint(prg_banks[2]) + (addr_uint & 0x1FFF)
		val := nes.prg_rom[val_i]
		return val, true
	case 0xE000 ..= 0xFFFF:
		val_i := uint(prg_banks[3]) + (addr_uint & 0x1FFF)
		val := nes.prg_rom[val_i]
		return val, true
	}

	return 0, false
}

m4_ppu_read :: proc(nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M4Data)
	using m_data

	chr_bank_no: u8

	switch addr {
	case 0x0000 ..= 0x03FF:
		chr_bank_no = 0
	case 0x0400 ..= 0x07FF:
		chr_bank_no = 1
	case 0x0800 ..= 0x0BFF:
		chr_bank_no = 2
	case 0x0C00 ..= 0x0FFF:
		chr_bank_no = 3
	case 0x1000 ..= 0x13FF:
		chr_bank_no = 4
	case 0x1400 ..= 0x17FF:
		chr_bank_no = 5
	case 0x1800 ..= 0x1BFF:
		chr_bank_no = 6
	case 0x1C00 ..= 0x1FFF:
		chr_bank_no = 7
	case:
		return 0, false
	}

	val_i := uint(chr_banks[chr_bank_no]) + (uint(addr) & 0x03FF)
	val := nes.chr_mem[val_i]
	return val, true
}

m4_cpu_write :: proc(nes: ^NES, addr: u16, val: u8) -> bool {
	m_data := &nes.mapper_data.(M4Data)
	using m_data

	switch addr {
	case 0x6000 ..= 0x7FFF:
		// write to cart RAM

		// fmt.println("writing to prg ram")
		nes.prg_ram[addr & 0x1FFF] = val
		return true
	case 0x8000 ..= 0x9FFF:
		// Configuring mapper

		// Bank Select
		if (addr & 0x1) == 0 {
			// If it's even...
			target_register = val & 0x07
			prg_bank_mode = (val & 0x40) != 0
			chr_inversion = (val & 0x80) != 0
		} else {
			// If it's odd...

			// Update target register
			registers[target_register] = u32(val)

			// Update pointer table

			if chr_inversion {
				chr_banks[0] = registers[2] * 0x0400
				chr_banks[1] = registers[3] * 0x0400
				chr_banks[2] = registers[4] * 0x0400
				chr_banks[3] = registers[5] * 0x0400
				chr_banks[4] = (registers[0] & 0xFE) * 0x0400
				chr_banks[5] = registers[0] * 0x0400 + 0x0400
				chr_banks[6] = (registers[1] & 0xFE) * 0x0400
				chr_banks[7] = registers[1] * 0x0400 + 0x0400
			} else {

				// smb3 is always here. not in the above block.
				chr_banks[0] = (registers[0] & 0xFE) * 0x0400
				chr_banks[1] = registers[0] * 0x0400 + 0x0400
				chr_banks[2] = (registers[1] & 0xFE) * 0x0400
				chr_banks[3] = registers[1] * 0x0400 + 0x0400
				chr_banks[4] = registers[2] * 0x0400
				chr_banks[5] = registers[3] * 0x0400
				chr_banks[6] = registers[4] * 0x0400
				chr_banks[7] = registers[5] * 0x0400
			}

			if prg_bank_mode {
				prg_banks[2] = (registers[6] & 0x3F) * 0x2000
				prg_banks[0] = (u32(prg_bank_count) * 2 - 2) * 0x2000
			} else {
				prg_banks[0] = (registers[6] & 0x3F) * 0x2000
				prg_banks[2] = (u32(prg_bank_count) * 2 - 2) * 0x2000
			}

			prg_banks[1] = (registers[7] & 0x3F) * 0x2000
			prg_banks[3] = (u32(prg_bank_count) * 2 - 1) * 0x2000
		}

		return true
	case 0xA000 ..= 0xBFFF:
		if (addr & 0x1) == 0 {
			// If it's even

			// Mirroring
			if (val & 0x1) != 0 {
				mirror_mode = .Vertical
			} else {
				mirror_mode = .Horizontal
			}
		} else {
			// PRG Ram Protect
			// TODO
		}
		return true
	case 0xC000 ..= 0xDFFF:
		if (addr & 0x1) == 0 {
			irq_reload = u16(val)
		} else {
			irq_counter = 0
		}
		return true
	case 0xE000 ..= 0xFFFF:
		if (addr & 0x1) == 0 {
			irq_enable = false
			irq_active = false
		} else {
			irq_enable = true
		}
		return true
	}

	return false
}

m4_ppu_write :: proc(nes: ^NES, addr: u16, val: u8) -> bool {
	return false
}

m4_scanline_hit :: proc(nes: ^NES) {
	m_data := &nes.mapper_data.(M4Data)
	using m_data

	if irq_counter == 0 {
		irq_counter = irq_reload
	} else {
		irq_counter -= 1
	}

	if irq_counter == 0 && irq_enable {
		irq_active = true
	}
}

m4_get_irq_state :: proc(nes: ^NES) -> bool {
	m_data := &nes.mapper_data.(M4Data)
	using m_data
	return irq_active
}

m4_irq_clear :: proc(nes: ^NES) {
	m_data := &nes.mapper_data.(M4Data)
	using m_data
	irq_active = false
}

// Mapper 7

M7Data :: struct {
	prg_bank_count:  u8,
	prg_bank_select: u8,
	mirror_mode : MirrorMode
}

m7_cpu_read :: proc(nes: ^NES, addr: u16) -> (u8, bool) {
	m_data := nes.mapper_data.(M7Data)
	using m_data

	addr_uint := uint(addr)

	switch addr {
		case 0x8000 ..= 0xFFFF:
			val_i := uint(prg_bank_select) * 0x8000 + ((addr_uint - 0x8000) & 0x7FFF)
			val := nes.prg_rom[val_i]
			return val, true
	}

	return 0, false
}

m7_cpu_write :: proc(using nes: ^NES, addr: u16, val: u8) -> bool {
	m_data := &nes.mapper_data.(M7Data)
	using m_data

	// 7  bit  0
	// ---- ----
	// xxxM xPPP
	//    |  |||
	//    |  +++- Select 32 KB PRG ROM bank for CPU $8000-$FFFF
	//    +------ Select 1 KB VRAM page for all 4 nametables

	switch addr {
	case 0x8000 ..= 0xFFFF:
		p := val & 0x07
		m := (val & 0x10) != 0

		prg_bank_select = p

		// SetMirroringType(((value & 0x10) == 0x10) ? MirroringType::ScreenBOnly : MirroringType::ScreenAOnly);
		if m {
			mirror_mode = .ScreenBOnly
		} else {
			mirror_mode = .ScreenAOnly
		}

		return true
	}

	return false
}
