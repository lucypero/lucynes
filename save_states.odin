package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:encoding/cbor"
import mv "core:mem/virtual"
import "core:strings"
import "core:bytes"
import "core:io"

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
		// Fast testing. marshalls and unmarshalls.
		// with these flags, it crashes way less.
		// now it only crashes (sometimes) like this:
		// cbor decode error  Unsupported_Type_Error{id = PPU, hdr = %!(BAD ENUM VALUE=0), add = %!(BAD ENUM VALUE=0)}

		nes_binary, err := cbor.marshal_into_bytes(nes.nes_serialized, flags = {.Self_Described_CBOR})
		if err != nil {
			fmt.eprintfln("cbor error %v", err)
			return false
		}
		defer delete(nes_binary)

		//save_diagnosis
		save_diagnosis(nes_binary) or_return

		reader: bytes.Reader
		stream := bytes.reader_init(&reader, nes_binary)

		nes_serialized_temp: NesSerialized

		decoder_flags: cbor.Decoder_Flags = {.Disallow_Streaming, .Trusted_Input}

		derr2 := cbor.unmarshal_from_reader(
			stream,
			&nes_serialized_temp,
			flags = decoder_flags,
			allocator = context.temp_allocator,
		)
		if derr2 != nil {
			fmt.eprintln("cbor decode error ", derr2)
			return false
		}

		// fok := os.write_entire_file_or_err(nes.rom_info.hash, nes_binary)

		// if fok != nil {
		// 	fmt.eprintfln("file write error %v %v", fok, nes.rom_info.hash)
		// 	return false
		// }


		fmt.printfln("Saved save state to %v", nes.rom_info.hash)

	case .Load:
	}

	return true
}

save_diagnosis :: proc(nes_binary: []u8) -> bool {
	// debugging
	decoded, derr := cbor.decode(string(nes_binary), allocator = context.temp_allocator)
	if derr != nil {
		fmt.eprintln("errrrrr")
		return false
	}

	diagnosis, eerr := cbor.to_diagnostic_format_string(decoded, allocator = context.temp_allocator)
	if eerr != nil {
		fmt.eprintln("d errrr")
		return false
	}

	os.write_entire_file("diagnosis", transmute([]u8)(diagnosis)) or_return

	return true
}
