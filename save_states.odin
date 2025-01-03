package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:encoding/cbor"
import mv "core:mem/virtual"
import "core:strings"

// In-memory save state:

@(private = "file")
save_states: []NES

// OLD: in-memory save states. don't use
@(deprecated = "this is old. we save everything to file now")
process_savestate_order_in_memory :: proc(nes: ^NES, savestate_order: SaveStateOrder) {
	// TODO mem leaks

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


SaveStateOrder :: enum {
	Save,
	Load,
}

// Saves/Load Nes state into/from file
// TODO there's still some bugs. I saved and loaded and it crashed.
// cbor decode error  Unsupported_Type_Error{id = PPU, hdr = %!(BAD ENUM VALUE=0), add = %!(BAD ENUM VALUE=0)}
// file read error
process_savestate_order :: proc(nes: ^NES, savestate_order: SaveStateOrder) -> bool {
	switch savestate_order {
	case .Save:
		nes_binary, err := cbor.marshal_into_bytes(nes.nes_serialized, allocator = context.temp_allocator)
		if err != nil {
			fmt.eprintfln("cbor error %v", err)
			return false
		}

		fok := os.write_entire_file_or_err(nes.rom_info.hash, nes_binary)

		if fok != nil {
			fmt.eprintfln("file write error %v %v", fok, nes.rom_info.hash)
			return false
		}

		fmt.printfln("Saved save state to %v", nes.rom_info.hash)

	case .Load:
		// TODO: reset audio maybe? audio state isn't being serialized

		fmt.printfln("Loading save state from %v", nes.rom_info.hash)

		nes_binary, fok := os.read_entire_file(nes.rom_info.hash, allocator = context.temp_allocator)

		if !fok {
			fmt.eprintln("file read error")
			return false
		}

		nes_serialized_temp: NesSerialized
		derr := cbor.unmarshal(string(nes_binary), &nes_serialized_temp, allocator = context.temp_allocator)
		if derr != nil {
			fmt.eprintln("cbor decode error ", derr)
			return false
		}

		// backup things you want from current NES before wiping NES allocator.
		prg_rom_backup := slice.clone(nes.prg_rom, allocator = context.temp_allocator)
		hash_str_backup := strings.clone(nes.rom_info.hash, allocator = context.temp_allocator)

		// TODO maybe save state data should be in another allocator bc it's another lifetime. we're doing unnecessary copying here.
		nes_arena_alloc := mv.arena_allocator(&nes_arena)
		free_all(nes_arena_alloc)

		nes.nes_serialized = nes_serialized_temp
		nes.chr_mem = slice.clone(nes_serialized_temp.chr_mem, allocator = nes_arena_alloc)
		nes.prg_ram = slice.clone(nes_serialized_temp.prg_ram, allocator = nes_arena_alloc)
		nes.prg_rom = slice.clone(prg_rom_backup, allocator = nes_arena_alloc)
		nes.rom_info.hash = strings.clone(hash_str_backup, allocator = nes_arena_alloc)
	}

	return true
}
