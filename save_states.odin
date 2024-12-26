package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:encoding/cbor"

// In-memory save state:

@(private = "file")
save_states: []NES

// OLD: in-memory save states. don't use
@(deprecated = "this is old. we save everything to file now")
process_savestate_order_in_memory :: proc(nes: ^NES, savestate_order: SaveStateOrder) {
	context.allocator = mem.tracking_allocator(&nes_allocator)

	// load or save here
	switch savestate_order {
	case .Save:
		if len(save_states) > 0 {
			delete(save_states[0].chr_mem)
			// TODO: no need to copy/load prg rom. delete this later
			delete(save_states[0].prg_rom)
			delete(save_states[0].prg_ram)

			delete(save_states)
		}

		save_states = make([]NES, 1)

		save_states[0] = nes^
		save_states[0].chr_mem = slice.clone(nes.chr_mem)
		save_states[0].prg_rom = slice.clone(nes.prg_rom)
		save_states[0].prg_ram = slice.clone(nes.prg_ram)
	case .Load:
		if len(save_states) > 0 {
			delete(nes.chr_mem)
			delete(nes.prg_rom)
			delete(nes.prg_ram)

			nes^ = save_states[0]
			nes.chr_mem = slice.clone(save_states[0].chr_mem)
			nes.prg_rom = slice.clone(save_states[0].prg_rom)
			nes.prg_ram = slice.clone(save_states[0].prg_ram)
		}
	}
}


// The state needed to restore NES state (for serialization)
// NOTE: this needs to be synced to the NES struct. It needs to be the first few fields, in order.
//  otherwise it will crash.
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
	// apu:                            APU,

	// input
	port_0_register:                u8,
	port_1_register:                u8,
	poll_input:                     bool,

	// Mappers
	mapper_data:                    MapperData,
}

SaveStateOrder :: enum {
	Save,
	Load,
}

// Saves/Load Nes state into/from file
// TODO there are some memory leaks here.
process_savestate_order :: proc(nes: ^NES, savestate_order: SaveStateOrder) -> bool {
	context.allocator = mem.tracking_allocator(&nes_allocator)

	// load or save here
	switch savestate_order {
	case .Save:
		// Downcasting to only what we need to serialize
		nes_essential: ^NesSerialized = cast(^NesSerialized)nes

		nes_binary, err := cbor.marshal_into_bytes(nes_essential^)
		if err != nil {
			fmt.eprintfln("cbor error %v", err)
			return false
		}
		defer delete(nes_binary)

		fmt.println("save size:", len(nes_binary))
		fok := os.write_entire_file_or_err(nes.rom_info.hash, nes_binary)

		if fok != nil {
			fmt.eprintfln("file write error %v %v", fok, nes.rom_info.hash)
			return false
		}

	case .Load:
		// TODO: reset audio maybe? audio state isn't being serialized
		nes_binary, fok := os.read_entire_file(nes.rom_info.hash)

		if !fok {
			fmt.eprintln("file read error")
			return false
		}

		nes_state: NesSerialized
		derr := cbor.unmarshal(string(nes_binary), &nes_state)
		if derr != nil {
			fmt.eprintln("cbor decode error ", derr)
			return false
		}

		// load success.

		// pretending the nes is NesSerialized so we can copy that chunk of memory to it easily
		nes_as_serialized: ^NesSerialized = cast(^NesSerialized)nes
		nes_as_serialized^ = nes_state
	}

	return true
}
