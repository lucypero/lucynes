package main

import "core:encoding/cbor"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:os"

// Sets up the cbor library so it can handle the types I have that it doesn't know how to serialize.
set_up_cbor :: proc() {
	// set up cbor
	RAW_TAG_NR_LUCYREG8 :: 200

	reg8_tag_impl := cbor.Tag_Implementation {
		marshal = proc(_: ^cbor.Tag_Implementation, e: cbor.Encoder, v: any) -> cbor.Marshal_Error {
			// encoding the tag
			cbor._encode_u8(e.writer, RAW_TAG_NR_LUCYREG8, .Tag) or_return
			// encoding the value as a u8
			the_val: u8 = (cast(^u8)v.data)^
			err := cbor._encode_u8(e.writer, the_val, .Unsigned)
			return err
		},
		unmarshal = proc(
			_: ^cbor.Tag_Implementation,
			d: cbor.Decoder,
			_: cbor.Tag_Number,
			v: any,
		) -> cbor.Unmarshal_Error {
			hdr := cbor._decode_header(d.reader) or_return
			maj, add := cbor._header_split(hdr)
			if maj != .Unsigned {
				return .Bad_Tag_Value
			}

			val: u8

			// Check if the u8 is inside the header (tiny int optimization)
			// This has cost me 5 hours of debugging. thanks.
			// https://github.com/odin-lang/Odin/issues/4661
			if add != .One_Byte {
				val = cbor._decode_tiny_u8(add) or_return
			} else {
				val = cbor._decode_u8(d.reader) or_return
			}

			intrinsics.mem_copy_non_overlapping(v.data, &val, 1)
			return nil
		},
	}

	cbor.tag_register_type(reg8_tag_impl, RAW_TAG_NR_LUCYREG8, PpuCtrl)
	cbor.tag_register_type(reg8_tag_impl, RAW_TAG_NR_LUCYREG8, PpuMask)
	cbor.tag_register_type(reg8_tag_impl, RAW_TAG_NR_LUCYREG8, PpuStatus)

	// 16 bit registers
	RAW_TAG_NR_LUCYREG16 :: 201

	reg16_tag_impl := cbor.Tag_Implementation {
		marshal = proc(_: ^cbor.Tag_Implementation, e: cbor.Encoder, v: any) -> cbor.Marshal_Error {
			// encoding the header (tag)
			cbor._encode_u8(e.writer, RAW_TAG_NR_LUCYREG16, .Tag) or_return
			the_val: u16 = (cast(^u16)v.data)^
			err := cbor._encode_u16(e, the_val, .Unsigned)
			return cbor.err_conv(err)
		},
		unmarshal = proc(
			_: ^cbor.Tag_Implementation,
			d: cbor.Decoder,
			_: cbor.Tag_Number,
			v: any,
		) -> cbor.Unmarshal_Error {
			hdr := cbor._decode_header(d.reader) or_return
			maj, add := cbor._header_split(hdr)
			if maj != .Unsigned {
				return .Bad_Tag_Value
			}

			val, err := cbor._decode_u16(d.reader)
			if err != .None {
				fmt.eprintln("err heree")
				return err
			}
			intrinsics.mem_copy_non_overlapping(v.data, &val, 2)
			return nil
		},
	}

	cbor.tag_register_type(reg16_tag_impl, RAW_TAG_NR_LUCYREG16, LoopyRegister)
}

save_thing :: proc(thing: $T, filename: string) -> bool {
	bin, err := cbor.marshal_into_bytes(
		thing,
		flags = {.Self_Described_CBOR},
		allocator = context.temp_allocator,
	)
	if err != nil {
		fmt.eprintfln("cbor error %v", err)
		return false
	}
	os.write_entire_file(filename, bin) or_return
	return true
}

load_thing :: proc(filename: string, thing: ^$T, allocator: runtime.Allocator) -> bool {

	bin := os.read_entire_file_from_filename(filename, allocator = context.temp_allocator) or_return
	nes_serialized_temp: NesSerialized
	decoder_flags: cbor.Decoder_Flags = {.Disallow_Streaming, .Trusted_Input, .Shrink_Excess}

	derr2 := cbor.unmarshal_from_string(
		string(bin),
		thing,
		flags = decoder_flags,
		allocator = allocator
	)
	if derr2 != nil {
		fmt.eprintln("cbor decode error ", derr2)
		return false
	}

    return true
}
