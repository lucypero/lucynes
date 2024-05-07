package main

// TODO: make sure these addr functions return
//  the address of the things. never just the value.
//  so the caller can either write or read to these addresses.
//  via nes.ram[addr]

// there are cases where there are no addresses, so
// just return the argument (like in immediate mode)

// everything except immediate will return an address (index to nes.ram)

AddressMode :: enum {
	Implicit,
	Accumulator,
	Immediate,
	ZeroPage,
	ZeroPageX,
	ZeroPageY,
	Relative,
	Absolute,
	AbsoluteX,
	AbsoluteY,
	Indirect,
	IndirectX, // Indexed Indirect, aka (IND, X)
	IndirectY, // Indirect Indexed, aka (IND), Y
}

// do not use this
get_mem :: proc(nes: ^NES, addr_mode: AddressMode) -> (u16, uint) {

	mem: u16
	extra_cycles: uint

	switch addr_mode {
		case .Implicit:
			return 0, 0
		case .Accumulator:
			mem = u16(nes.accumulator)
		case .Immediate:
			mem = u16(do_addrmode_immediate(nes))
		case .ZeroPage:
			mem = do_addrmode_zp(nes)
		case .ZeroPageX:
			mem = do_addrmode_zpx(nes)
		case .ZeroPageY:
			mem = do_addrmode_zpy(nes)
		case .Relative:
			mem = do_addrmode_relative(nes)
		case .Absolute:
			mem = do_addrmode_absolute(nes)
		case .AbsoluteX:
			mem, extra_cycles = do_addrmode_absolute_x(nes)
		case .AbsoluteY:
			mem, extra_cycles = do_addrmode_absolute_y(nes)
		case .Indirect:
			mem = do_addrmode_indirect(nes)
		case .IndirectX:
			mem = do_addrmode_ind_x(nes)
		case .IndirectY:
			mem, extra_cycles = do_addrmode_ind_y(nes)
	}

	return mem, extra_cycles
}

// do not use this (yet)
do_opcode :: proc(nes: ^NES, addr_mode: AddressMode, instruction: proc(^NES, u16), cycles: uint) {
	mem, extra_cycles := get_mem(nes, addr_mode)
	instruction(nes, mem)
	nes.cycles += cycles + extra_cycles
}

// it just returns what's in A

// there is no address involved here so it just returns the value.
do_addrmode_immediate :: proc(using nes: ^NES) -> u8 {
	res := ram[program_counter]
	program_counter += 1
	return res
}

// offset from the first page of ram ($0000 to $00FF)
do_addrmode_zp :: proc(using nes: ^NES) -> u16 {

	addr_offset := ram[program_counter]

	res: u16 = 0x00
	res += u16(addr_offset)

	program_counter += 1

	return res
}

// does ZPX and ZPY depending which index value u pass
do_addrmode_zp_index :: proc(using nes: ^NES, index: u8) -> u16 {
	addr_offset := u16(ram[program_counter]) + u16(index)
	if addr_offset > 0xFF {
		addr_offset -= 0xFF
	}

	program_counter += 1

	res: u16 = 0x00
	res += u16(addr_offset)

	return res
}

do_addrmode_zpx :: proc(using nes: ^NES) -> u16 {
	return do_addrmode_zp_index(nes, index_x)
}

do_addrmode_zpy :: proc(using nes: ^NES) -> u16 {
	return do_addrmode_zp_index(nes, index_y)
}

// it returns the absolute address that the instruction will jump to.
// todo: look into where it should offset from. i am not sure.
// maybe at the point before the cpu reads the whole instruction?
do_addrmode_relative :: proc(using nes: ^NES) -> u16 {
	// todo
	res := ram[program_counter]
	program_counter += 1
	return program_counter + u16(res)
}

do_addrmode_absolute :: proc(using nes: ^NES) -> u16 {

	// TODO: this might be backwards. NES is little endian.
	res_msb: u8 = ram[program_counter]
	res_lsb: u8 = ram[program_counter + 1]

	res: u16 = u16(res_msb << 2) + u16(res_lsb)

	program_counter += 2

	return res
}

do_addrmode_absolute_index :: proc(using nes: ^NES, index_register: u8) -> u16 {
	res_msb: u8 = ram[program_counter]
	res_lsb: u8 = ram[program_counter + 1]

	res: u16 = u16(res_msb << 2) + u16(res_lsb) + u16(index_register)

	program_counter += 2

	return res
}

// TODO extra cycles
do_addrmode_absolute_x :: proc(using nes: ^NES) -> (u16, uint) {
	return do_addrmode_absolute_index(nes, index_x), 0
}

// TODO extra cycles
do_addrmode_absolute_y :: proc(using nes: ^NES) -> (u16, uint) {
	return do_addrmode_absolute_index(nes, index_y), 0
}

// returns the address to jump to
do_addrmode_indirect :: proc(using nes: ^NES) -> u16 {
	// only used by JMP

	// read u16 value at address given. just return the value but the bytes flipped (little endian)

	// read the address in the argument:
	res_addr := read_u16_be(ram[:], program_counter) // TODO: u might have to read it as LE too.

	// read the value at the address
	res := read_u16_le(ram[:], res_addr)

	program_counter += 2

	return res
}

// indexed indirect address mode
// aka (IND, X)
// returns the address
do_addrmode_ind_x :: proc(using nes: ^NES) -> u16 {
	// get 16 bit value in arg + x (wrap around)

	addr_1 := u16(ram[program_counter]) + u16(index_x)

	if addr_1 > 0xFF {
		addr_1 -= 0xFF
	}

	// treat it as an address

	addr_2 := read_u16_le(ram[:], addr_1)

	// increment pc
	program_counter += 1

	// return the address
	return addr_2
}

// indexed indirect address mode
// aka (IND), Y
// TODO extra cycles
// returns the address
do_addrmode_ind_y :: proc(using nes: ^NES) -> (u16, uint) {
	// get 16 bit value in arg
	addr_1 := u16(ram[program_counter])

	// treat it as an address
	addr_2 := read_u16_le(ram[:], addr_1)

	// add y register
	addr_2 += u16(index_y)

	// increment pc
	program_counter += 1

	// return the address
	return addr_2, 0
}
