package main

import "base:runtime"
import "core:bufio"
import "core:bytes"
import "core:encoding/endian"
import "core:fmt"
import "core:io"
import "core:math"
import "core:mem"
import mv "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sync"
import "core:sync/chan"
import hash "core:crypto/hash"
import base64 "core:encoding/base64"
import rl "vendor:raylib"
import wt "wav_tools"
import "base:intrinsics"
import "core:encoding/cbor"

// NES emulation arena emulator.
// allocates all NES emulation memory
// when resetting a game or loading a save state, create a new one and destroy the old one.
nes_arena: mv.Arena

/// GLOBAL STATE
palette: []rl.Color

// sync stuff for passing data to audio thread
mutex: sync.Mutex
ring_buffer: Buffer
sema: sync.Sema

// nametable mirror mode
// for mappers with dynamic mirror mode
// for hardwired mappers, look at rominfo.is_horizontal_arrangement
MirrorMode :: enum {
	Horizontal,
	Vertical,
	ScreenAOnly,
	ScreenBOnly,
}

RomFormat :: enum {
	NES20,
	iNES,
}

RomInfo :: struct {
	hash:                  string,
	rom_loaded:            bool,
	rom_format:            RomFormat,
	prg_unit_count:        u8, // Size of PRG ROM in 16 KiB Units (16 kib == 0x4000). Aka "PRG Bank Count"
	chr_unit_count:        u8, // Size od CHR ROM in 8 KiB Units (8kib == 0x2000). AKA "CHR Bank Count"
	prg_rom_size:          int,
	chr_rom_size:          int,
	mirror_mode_hardwired: MirrorMode,
	contains_ram:          bool, // bit 2 in flags 6. true if it contains battery packed PRG RAM
	contains_trainer:      bool,
	alt_nametable_layout:  bool,
	mapper:                Mapper,
}

RegisterFlagEnum :: enum {
	Carry, // C 
	Zero, // Z
	InterruptDisable, // I
	Decimal, // D
	NoEffectB, // No CPU Effect, see the B flag
	NoEffect1, // No CPU Effect, always pushed as 1
	Overflow, // V
	Negative, // N
}

RegisterFlags :: bit_set[RegisterFlagEnum;u8]

/*
Memory layout:

Internal RAM:

$0000-$00FF: The zero page, which can be accessed with fewer bytes and cycles than other addresses
$0100–$01FF: The page containing the stack, which can be located anywhere here, but typically starts at $01FF and grows downward
$0200-$07FF: General use RAM

Rest...

TODO


*/

/*

Instructions:

to emulate an instruction, you need to know:

- function (which instruction it is)
- address mode
- how many cycles it takes

you can know all this from the first byte of the instruction.

How to run instructions:

- Read byte at PC
- With that info, u know the addressing mode and 
    the number of cycles needed to run the instruction (all in a big switch statement maybe)
- based on the addressing mode, read additional bytes you need to run the instruction
- execute the instruction
- wait, count cycles, complete

*/

NesTestLog :: struct {
	cpu_registers: Registers,
	cpu_cycles:    uint,
}

Registers :: struct {
	program_counter: u16, // Program Counter Register
	stack_pointer:   u8, // Stack Pointer Register
	accumulator:     u8, // Accumulator Register
	index_x:         u8, // Index Register X
	index_y:         u8, // Index Register Y
	flags:           RegisterFlags, // Processor Status Register (Processor Flags)
}

FaultyOp :: struct {
	supposed_cycles: int,
	nmi_ran:         bool,
	oam_ran:         bool,
	// cycles taken in reality (read/writes)
	// which is when u tick the PPU * 3
	cycles_taken:    int,
}

InstructionInfo :: struct {
	pc:               u16,
	next_pc:          u16, // The next position of the PC like, for real
	triggered_nmi:    bool,
	cpu_status:       Registers,
	// ppu info is when AFTER the instruction ran
	ppu_scanline:     int,
	ppu_cycle:        int,
	ppu_vblank_count: uint,
	// you can find out the rest from the PC.
	// you can add other state later.
}

RingThing :: struct($ring_size: uint, $T: typeid) {
	buf:         [ring_size]T,
	last_placed: int,
}

ringthing_add :: proc(using ringthing: ^RingThing($N, $T), data: T) {
	last_placed += 1
	if last_placed >= len(buf) {
		last_placed = 0
	}

	buf[last_placed] = data
}

// Mapper read operation. Returns true if the mapper handled the read.
mread_op :: proc(nes: ^NES, addr: u16) -> (u8, bool)

// Mapper write operation. Returns true if the mapper handled the write.
mwrite_op :: proc(nes: ^NES, addr: u16, val: u8) -> bool

// The state needed to restore NES state (for serialization)
NesSerialized :: struct {
	using registers:                Registers, // CPU Registers
	ram:                            [0x800]u8, // 2 KiB of memory
	ignore_extra_addressing_cycles: bool,
	instruction_type:               InstructionType,
	prg_ram:                        []u8,
	// This is CHR RAM if rom_info.chr_rom_size == 0, otherwise it's CHR ROM
	chr_mem:                        []u8,
	nmi_triggered:                  int,
	ppu:                            PPU,

	// input
	port_0_register:                u8,
	port_1_register:                u8,
	poll_input:                     bool,

	// Mappers
	mapper_data:                    MapperData,
}

NES :: struct {
	using nes_serialized: NesSerialized,
	apu:                  APU,
	prg_rom:              []u8,
	rom_info:             RomInfo,
	m_cpu_read:           mread_op,
	m_cpu_write:          mwrite_op,
	m_ppu_read:           mread_op,
	m_ppu_write:          mwrite_op,
	m_scanline_hit:       proc(nes: ^NES),
	m_get_irq_state:      proc(nes: ^NES) -> bool,
	m_irq_clear:          proc(nes: ^NES),

	// INSTRUMENTING FOR THE OUTSIDE WORLD
	vblank_hit:           bool,

	// DEBUGGING

	// history for display in debugger
	instr_history:        RingThing(prev_instructions_count, InstructionInfo),
	// history for log dump
	instr_history_log:    RingThing(prev_instructions_log_count, InstructionInfo),
	faulty_ops:           map[u8]FaultyOp,
	read_writes:          uint,
	last_write_addr:      u16,
	last_write_val:       u8,
}


set_flag :: proc(flags: ^RegisterFlags, flag: RegisterFlagEnum, predicate: bool) {
	if predicate {
		flags^ += {flag}
	} else {
		flags^ -= {flag}
	}
}

parse_log_file :: proc(log_file: string) -> (res: [dynamic]NesTestLog, ok: bool) {

	ok = false

	log_bytes := os.read_entire_file(log_file) or_return

	log_string := string(log_bytes)

	for line in strings.split_lines_iterator(&log_string) {
		reg: NesTestLog
		reg.cpu_registers.program_counter = u16(strconv.parse_int(line[:4], 16) or_return)
		reg.cpu_registers.accumulator = u8(strconv.parse_int(line[50:][:2], 16) or_return)
		reg.cpu_registers.index_x = u8(strconv.parse_int(line[55:][:2], 16) or_return)
		reg.cpu_registers.index_y = u8(strconv.parse_int(line[60:][:2], 16) or_return)
		reg.cpu_registers.flags = transmute(RegisterFlags)u8(strconv.parse_int(line[65:][:2], 16) or_return)
		reg.cpu_registers.stack_pointer = u8(strconv.parse_int(line[71:][:2], 16) or_return)
		reg.cpu_cycles = uint(strconv.parse_uint(line[90:], 10) or_return)
		append(&res, reg)
	}

	ok = true

	return
}

// register_logs: [dynamic]Registers

run_nestest :: proc(using nes: ^NES, program_file: string, log_file: string) -> bool {
	// processing log file

	register_logs, ok := parse_log_file(log_file)

	if !ok {
		fmt.eprintln("could not parse log file")
		return false
	}

	nes.registers = register_logs[0].cpu_registers

	nes_reset(nes, program_file)

	test_rom, ok_2 := os.read_entire_file(program_file)

	if !ok_2 {
		fmt.eprintln("could not read program file")
		return false
	}

	program_counter = 0xC000
	stack_pointer = 0xFD
	flags = transmute(RegisterFlags)u8(0x24)

	instructions_ran := 0

	reset_debugging_vars(nes)
	read_writes = 6
	total_read_writes: uint = read_writes + 1

	for read(nes, program_counter) != 0x00 {

		state_before_instr: NesTestLog
		state_before_instr.cpu_registers = registers
		reset_debugging_vars(nes)

		// fmt.printfln("running line %v", instructions_ran + 1)
		// print_cpu_state(state_before_instr)

		// run_instruction(nes)
		instruction_tick(nes, 0, 0, &pixel_grid)
		total_read_writes += read_writes

		instructions_ran += 1

		if instructions_ran >= len(register_logs) {
			return true
		}

		if res := compare_reg(nes.registers, total_read_writes, register_logs[instructions_ran]); res != 0 {
			// test fail

			logs_reg := register_logs[instructions_ran]

			fmt.printfln("------------------")

			fmt.eprintfln("Test failed after instruction: %v (starts at 1)", instructions_ran)

			switch res {
			case 1:
				fmt.printfln("PC: %X, TEST PC: %X", program_counter, logs_reg.cpu_registers.program_counter)
			case 2:
				fmt.printfln("A: %X, TEST A: %X", accumulator, logs_reg.cpu_registers.accumulator)
			case 3:
				fmt.printfln("X: %X, TEST X: %X", index_x, logs_reg.cpu_registers.index_x)
			case 4:
				fmt.printfln("Y: %X, TEST Y: %X", index_y, logs_reg.cpu_registers.index_y)
			case 5:
				fmt.printfln("P: %X, TEST P: %X", flags, logs_reg.cpu_registers.flags)
			case 6:
				fmt.printfln("SP: %X, TEST SP: %X", stack_pointer, logs_reg.cpu_registers.stack_pointer)
			case 8:
				fmt.printfln("REAL CYCLES: %v, TEST CYCLES: %v", total_read_writes, logs_reg.cpu_cycles)
			}

			fmt.println("state before instr:")
			print_cpu_state(state_before_instr)


			fmt.println("state after instruction:")
			state_before_instr.cpu_registers = registers
			print_cpu_state(state_before_instr)
			return false
		}

	}

	return true
}

compare_reg :: proc(current_register: Registers, real_cpu_cycles: uint, log_register: NesTestLog) -> int {

	if current_register.program_counter != log_register.cpu_registers.program_counter {
		return 1
	}

	if current_register.accumulator != log_register.cpu_registers.accumulator {
		return 2
	}

	if current_register.index_x != log_register.cpu_registers.index_x {
		return 3
	}

	if current_register.index_y != log_register.cpu_registers.index_y {
		return 4
	}

	if current_register.flags != log_register.cpu_registers.flags {
		return 5
	}

	if current_register.stack_pointer != log_register.cpu_registers.stack_pointer {
		return 6
	}

	if real_cpu_cycles != log_register.cpu_cycles {
		return 8
	}


	return 0
}

print_cpu_state :: proc(regs: NesTestLog) {
	fmt.printfln(
		"PC: %X A: %X X: %X Y: %X P: %X SP: %X CYC: %v",
		regs.cpu_registers.program_counter,
		regs.cpu_registers.accumulator,
		regs.cpu_registers.index_x,
		regs.cpu_registers.index_y,
		transmute(u8)regs.cpu_registers.flags,
		regs.cpu_registers.stack_pointer,
		regs.cpu_cycles,
	)
}

report_track_allocations :: proc(allocator: ^mem.Tracking_Allocator, allocator_name: string) {
	fmt.printfln(
		`--- %v allocator: ---
Current memory allocated: %v KB
Peak memory allocated: %v KB
Total allocation count: %v`,
		allocator_name,
		f32(allocator.current_memory_allocated) / 1000,
		f32(allocator.peak_memory_allocated) / 1000,
		allocator.total_allocation_count,
	)
}

report_arena_allocations :: proc(arena: mv.Arena, arena_name: string) {
	fmt.printfln(
		`--- %v allocator: ---
Total reserved: %v KB
Total used: %v KB`,
		arena_name,
		f32(arena.total_reserved) / 1000,
		f32(arena.total_used) / 1000,
	)
}

warn_leaks :: proc(allocator: ^mem.Tracking_Allocator, allocator_name: string) {
	if len(allocator.allocation_map) > 0 {
		fmt.eprintf(
			"=== %v allocations not freed from %v allocator: ===\n",
			len(allocator.allocation_map),
			allocator_name,
		)
		for _, entry in allocator.allocation_map {
			fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
		}
	}
	if len(allocator.bad_free_array) > 0 {
		fmt.eprintf("=== %v incorrect frees from %v allocator: ===\n", len(allocator.bad_free_array), allocator_name)
		for entry in allocator.bad_free_array {
			fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
		}
	}
}

main :: proc() {
	// initializing default allocator (wrapping it in a trackign allocator)
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	temp_arena: mv.Arena
	assert(mv.arena_init_growing(&temp_arena) == .None)
	context.temp_allocator = mv.arena_allocator(&temp_arena)

	// initializing nes arena
	assert(mv.arena_init_growing(&nes_arena) == .None)

	_main()

	// Allocations report
	fmt.printfln(`-------- Allocations report: -----------`)
	report_track_allocations(&track, "Forever")
	report_arena_allocations(nes_arena, "NES")

	warn_leaks(&track, "Forever")
	print_allocated_temp()
}

_main :: proc() {
	set_up_cbor()
	window_main()

	// Audio sync report

	// fmt.printfln("--- Audio sync report ---")
	// // fmt.printfln(" Times that the channel buffer was over %v: %v", CHANNEL_BUFFER_SOFT_CAP, times_it_went_over)
	// fmt.printfln(" Times that the audio thread starved: %v", times_it_starved)
	// fmt.printfln(" Times that the main thread got blocked: %v", times_main_thread_got_blocked)
	// fmt.printfln("--- / Audio sync report ---")
}

write_sample_wav_file_w_lib :: proc(the_samples: []f32) {

	// Fill in the data.
	file_name := "nes_apu_sample.wav"
	path := "./"

	wav_info, wav_error := wt.wav_info_create(file_name, path, 1, OUTPUT_SAMPLE_RATE, 16)

	if wav_error.(wt.Error).type != .No_Error {
		fmt.eprintln("err")
		os.exit(1)
	}

	// Print the WavInfo struct.
	wt.print_wav_info(&wav_info)

	defer wt.wav_info_destroy(&wav_info)
	// TODO: KEEP DOING THIS. WAKE UP AT 6 AM
	// wt.set_buffer_d32_normalized()

	wav_error = wt.set_buffer_d32_normalized(&wav_info, the_samples, nil)

	if wav_error.(wt.Error).type != .No_Error {
		fmt.eprintfln("err writing %v", wav_error.(wt.Error))

		os.exit(1)
	}

	wav_error = wt.wav_write_file(&wav_info)
	if wav_error.(wt.Error).type != .No_Error {
		fmt.eprintln("err writing file")
		os.exit(1)
	}
}

write_sample_wav_file :: proc() -> bool {

	write_u32 :: proc(buf: ^bytes.Buffer, val: u32) {
		val_bytes: [4]u8
		endian.put_u32(val_bytes[:], .Little, val)
		bytes.buffer_write(buf, val_bytes[:])
	}

	write_u16 :: proc(buf: ^bytes.Buffer, val: u16) {
		val_bytes: [2]u8
		endian.put_u16(val_bytes[:], .Little, val)
		bytes.buffer_write(buf, val_bytes[:])
	}

	buf: bytes.Buffer

	bytes.buffer_init(&buf, {})
	bits_per_sample :: 32
	number_channels :: 1
	header_size :: 44

	data_size: u32 = 400
	file_size: u32 = data_size + header_size - 8


	// write wave header 

	// bytes.buffer_write(&buf, {1,2,3})
	bytes.buffer_write_string(&buf, "RIFF")

	// write file size as a u32
	write_u32(&buf, file_size)

	bytes.buffer_write_string(&buf, "WAVEfmt")
	bytes.buffer_write(&buf, {0x20})

	// BlocSize        (4 bytes) : Chunk size minus 8 bytes, which is 16 bytes here  (0x10)
	write_u32(&buf, bits_per_sample)

	// AudioFormat
	bytes.buffer_write(&buf, {0x00, 0x03}) // float

	// NbrChannels (number of channels)
	write_u16(&buf, number_channels)

	// Frequence       (4 bytes) : Sample rate (in hertz)
	write_u32(&buf, OUTPUT_SAMPLE_RATE)

	// BytePerSec      (4 bytes) : Number of bytes to read per second (Frequence * BytePerBloc).
	write_u32(&buf, OUTPUT_SAMPLE_RATE * (bits_per_sample / 8))

	// BytePerBloc     (2 bytes) : Number of bytes per block (NbrChannels * BitsPerSample / 8).
	write_u16(&buf, number_channels * bits_per_sample / 8)

	// BitsPerSample   (2 bytes) : Number of bits per sample
	write_u16(&buf, bits_per_sample)

	// DataBlocID      (4 bytes) : Identifier « data »  (0x64, 0x61, 0x74, 0x61)
	bytes.buffer_write_string(&buf, "data")

	// DataSize        (4 bytes) : SampledData size
	write_u32(&buf, data_size)


	bytes.buffer_write(&buf, {1, 2, 3})
	bytes.buffer_write(&buf, {1, 2, 3})
	bytes.buffer_write(&buf, {1, 2, 3})
	bytes.buffer_write(&buf, {1, 2, 3})
	bytes.buffer_write(&buf, {1, 2, 3})

	ok := os.write_entire_file("hello.txt", buf.buf[:])
	if !ok {
		fmt.eprintfln("could not write file")
		os.exit(1)
	}

	// w: bufio.Writer
	// bufio.writer_init(&w)


	return true
}

// reads a pal file and converts it to [64]rl.Color
get_palette :: proc(pal_file: string) -> (p_palette: []rl.Color, ok: bool) {

	palette := make([]rl.Color, 64)

	log_bytes := os.read_entire_file(pal_file) or_return
	defer delete(log_bytes)

	if len(log_bytes) < 64 {
		return palette, false
	}

	for i in 0 ..< 64 {
		palette[i].r = log_bytes[i * 3 + 0]
		palette[i].g = log_bytes[i * 3 + 1]
		palette[i].b = log_bytes[i * 3 + 2]
		palette[i].w = 255
	}

	return palette, true
}

union_test :: proc() {

	// TODO: do this for storing things like registers

	ppu_ctrl: struct #raw_union {
		// VPHB SINN
		using flags: bit_field u8 {
			n: u8 | 2,
			i: u8 | 1,
			s: u8 | 1,
			b: u8 | 1,
			h: u8 | 1,
			p: u8 | 1,
			v: u8 | 1,
		},
		reg:         u8,
	}

	ppu_ctrl.v = 1
	ppu_ctrl.b = 1
	ppu_ctrl.reg = 0x20

	fmt.printfln("%b", transmute(u8)ppu_ctrl)
}

print_patterntable :: proc(nes: NES) {

	// pattern tables:
	// 1: $0000 - $0FFF
	// 2: $1000 - $1FFF

	// each tile is 16 bytes made of 2 bit planes
	// tile is 8x8 pixels (pixels being 2 bits long)

	// pattern table is divided into two 256 tile sections (left and right pattern tables)


	// it is stored tiled by tile

	// how each tile is stored:

	// bit plane 0 - then - bitplane 1


	// tiles


	// looping tile
	for i in 0 ..< 256 {

		tile: [8 * 8]int // pixels of tiles (contains [0-3])

		// first bit plane
		for t in 0 ..< 16 {

			row := nes.chr_mem[(i * 16) + t]

			// looping row of pixels
			for p in 0 ..< 8 {
				is_on := (row >> uint(p)) & 0b00000001

				if is_on != 0 {

					// if we're on first bit plane, add one
					if (t < 8) {
						tile[(t * 8) + p] += 1
					} else {
						// if we're on second bit plane, add two
						tile[((t - 8) * 8) + p] += 2
					}
				}
			}
		}


		// print tile

		for p, p_i in tile {
			fmt.printf("%v", p)

			if (p_i % 8) == 7 {
				fmt.printf("\n")
			}
		}

		fmt.printf("\n")
	}
}

get_mirrored :: proc(val, from, to: $T) -> T {
	range := to - from + 1
	return ((val - from) % range) + from
}

mirror_test :: proc() {

	// PPU I/O registers at $2000-$2007 are mirrored at $2008-$200F, $2010-$2017, $2018-$201F, and so forth, all the way up to $3FF8-$3FFF.
	// For example, a write to $3456 is the same as a write to $2006. 

	assert(get_mirrored(0x3456, 0x2000, 0x2007) == 0x2006) // returns $2006

}

ENC_TABLE := [64]byte {
	'A',
	'B',
	'C',
	'D',
	'E',
	'F',
	'G',
	'H',
	'I',
	'J',
	'K',
	'L',
	'M',
	'N',
	'O',
	'P',
	'Q',
	'R',
	'S',
	'T',
	'U',
	'V',
	'W',
	'X',
	'Y',
	'Z',
	'a',
	'b',
	'c',
	'd',
	'e',
	'f',
	'g',
	'h',
	'i',
	'j',
	'k',
	'l',
	'm',
	'n',
	'o',
	'p',
	'q',
	'r',
	's',
	't',
	'u',
	'v',
	'w',
	'x',
	'y',
	'z',
	'0',
	'1',
	'2',
	'3',
	'4',
	'5',
	'6',
	'7',
	'8',
	'9',
	'+',
	'_',
}

// TODO: this proc does too much. mixes up a bunch of stuff
// it should just load RomInfo struct.
// then after that, do the following operations that will take in Rom Info.
// Like: initializing the mapper and allocating cart ROM and RAM data.
load_rom_from_file :: proc(nes: ^NES, filename: string, allocator: runtime.Allocator) -> bool {

	context.allocator = allocator

	rom_info: RomInfo

	test_rom, ok := os.read_entire_file(filename, allocator = context.temp_allocator)

	if !ok {
		fmt.eprintln("could not read rom file")
		return false
	}

	rom_string := string(test_rom)

	nes_str := rom_string[0:3]

	// checking if it's a nes rom

	if nes_str != "NES" {
		fmt.eprintfln("(filename: %v) this is not a nes rom file.", filename)
		return false
	}

	// checking if it's nes 2.0 or ines

	if (rom_string[7] & 0x0C) == 0x08 {
		rom_info.rom_format = .NES20
	} else {
		rom_info.rom_format = .iNES
	}

	// size of prg ROM

	// PRG ROM data (16384 * x bytes) (but later on it just says 16kb units)
	// CHR ROM data, if present (8192 * y bytes) (but later on it just says 8kb units)

	// fmt.printfln("byte 4 in rom string: %X", rom_string[4])
	rom_info.prg_unit_count = u8(rom_string[4])
	rom_info.chr_unit_count = u8(rom_string[5])

	rom_info.prg_rom_size = int(rom_string[4]) * 16384
	rom_info.chr_rom_size = int(rom_string[5]) * 8192

	// fmt.printfln("prg rom size: %v bytes", rom_info.prg_rom_size)
	// fmt.printfln("chr rom size: %v bytes", rom_info.chr_mem_size)

	// Flags 6

	flags_6 := rom_string[6]

	if flags_6 & 0x01 != 0 {
		rom_info.mirror_mode_hardwired = .Horizontal
	} else {
		rom_info.mirror_mode_hardwired = .Vertical
	}

	if flags_6 & 0x02 != 0 {
		rom_info.contains_ram = true
	} else {
		rom_info.contains_ram = false
	}

	if flags_6 & 0x04 != 0 {
		rom_info.contains_trainer = true
	} else {
		rom_info.contains_trainer = false
	}

	if flags_6 & 0x08 != 0 {
		rom_info.alt_nametable_layout = true
	} else {
		rom_info.alt_nametable_layout = false
	}

	mapper_lower := (flags_6 & 0xF0) >> 4

	// flags 7
	flags_7 := rom_string[7]
	mapper_higher := (flags_7 & 0xF0) >> 4
	mapper_number := mapper_higher << 4 | mapper_lower
	mapper := mapper_init(nes, mapper_number, rom_info.prg_unit_count, rom_info.chr_unit_count)
	rom_info.mapper = mapper

	// flags 8

	prg_ram_size: u8 = rom_string[8]

	// fmt.printfln("prg ram size according to flags 8: %v", prg_ram_size)

	// where is all the rom data
	header_size :: 16
	trainer_size :: 512

	prg_rom_start := header_size

	if rom_info.contains_trainer {
		prg_rom_start += trainer_size
	}

	chr_mem_start := prg_rom_start + rom_info.prg_rom_size

	prg_rom := make([]u8, rom_info.prg_rom_size)

	chr_mem: []u8

	if rom_info.chr_rom_size == 0 {
		// This means CHR ROM is actually CHR RAM
		// 8KiB
		chr_mem = make([]u8, 0x2000)
	} else {
		chr_mem = make([]u8, rom_info.chr_rom_size)
		copy(chr_mem[:], rom_string[chr_mem_start:])
	}

	copy(prg_rom[:], rom_string[prg_rom_start:])
	rom_info.rom_loaded = true

	nes.prg_rom = prg_rom
	nes.chr_mem = chr_mem

	// allocating prg ram
	// assuming it is always 32kib
	// All other SxROM variants are denoted by their functional PRG/CHR-ROM/RAM sizes in the NES 2.0 header. 
	// Without NES 2.0, the PRG-RAM size has to be assumed; 32 KiB are sufficient for compatibility with all known titles. 
	nes.prg_ram = make([]u8, 0x8000)

	// I'm not relying on contains_ram or ram size because some roms will be ines format.
	// To be safe, always allocate 32 KiB to prg ram.
	// fmt.printfln("rom info: %v", rom_info)
	// if rom_info.contains_ram {
	// 	fmt.printfln("prg ram size %v", prg_ram_size)
	// }

	// hash file

	the_hash := hash.hash_bytes(.SHA256, test_rom, allocator = context.temp_allocator)
	hash_str, ok_3 := base64.encode(the_hash, ENC_TABLE)
	if ok_3 != .None {
		return false
	}

	rom_info.hash = hash_str

	nes.rom_info = rom_info
	return true
}

casting_test :: proc() {
	hello: i8 = -4
	positive: i8 = 4
	fmt.printfln("-4 is %8b. -4 in u16 is %16b, 4 as i8 in u16 is %16b", hello, u16(hello), u16(positive)) // 46
}

run_nestest_test :: proc() {
	nes: NES


	context.allocator = context.temp_allocator
	ok := run_nestest(&nes, "nestest/nestest.nes", "nestest/nestest.log")

	print_faulty_ops(&nes)

	free_all(context.temp_allocator)


	fmt.printfln("")

	if !ok {
		fmt.eprintln("nes test failed somewhere. look into it!")
		os.exit(1)
	} else {
		fmt.println("Ran nestest. All OK!")
	}
}

strong_type_test :: proc() {
	a: u8 = 0xFF
	b: u8 = 0x01

	res: u16 = u16(a << 8 | b)
	fmt.printfln("res is %X", res)
}

// address modes?

flags_test :: proc() {
	flags: RegisterFlags

	flags = {.Carry, .Zero, .Negative}

	fmt.printf("%v, %#b\n", flags, transmute(u8)flags)

	fmt.println(.Carry in flags)
	fmt.println(.Overflow in flags)
	flags += {.Decimal}
	fmt.println(flags)

	fmt.printf("%v, %#b\n", flags, transmute(u8)flags)

	// how to flip the bits?
	flags = ~flags
	fmt.printf("flipped: %v, %#b\n", flags, transmute(u8)flags)

	flags = {.NoEffect1}
	fmt.printf("noeffect1: %v, %#b\n", flags, transmute(u8)flags)

	flags = {.NoEffectB}
	fmt.printf("noeffectb: %v, %#b\n", flags, transmute(u8)flags)

}

///  memory / allocator / context things

get_total_allocated :: proc() -> int {
	alloc := (^mem.Tracking_Allocator)(context.allocator.data)

	total_used := 0

	for _, entry in alloc.allocation_map {
		total_used += entry.size
	}

	return total_used
}

print_allocated :: proc() {
	fmt.printfln("total allocated in tracking allocator: %v bytes", get_total_allocated())
}

print_allocated_temp :: proc() {
	alloc := (^runtime.Arena)(context.temp_allocator.data)
	fmt.printfln(`--- Temp allocator: ---
Total memory allocated: %v KB`, f32(alloc.total_used) / 1000)
}

print_allocator_features :: proc() {
	fmt.printfln("context.allocator features: %v", mem.query_features(context.allocator))
	fmt.printfln("context.temp_allocator features: %v", mem.query_features(context.temp_allocator))
}

flip_byte :: proc(b: u8) -> u8 {
	b := b
	b = (b & 0xF0) >> 4 | (b & 0x0F) << 4
	b = (b & 0xCC) >> 2 | (b & 0x33) << 2
	b = (b & 0xAA) >> 1 | (b & 0x55) << 1
	return b
}
