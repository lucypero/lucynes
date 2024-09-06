// Lib name    : WAV tools in Odin
// Description : A library to read and write WAV files, in Mono or Stereo,
//               in 8 bit's or 16 bit's, for any sample rate in the Odin
//               programming language.
//
//               Super simple to use.
//
//               To read the []f32 Mono buffer or Stereo buffer from the file
//                 wav_load_file( )
//                   get_buffer_d32_normalized( )
//                   print_wav_info( )
//                 wav_info_destroy( )
//
//               To write the []f32 Mono buffer or Stereo buffer to the file
//                 wav_info_create( )
//                   set_buffer_d32_normalized( )
//                   wav_write_file( )
//                   print_wav_info( )
//                 wav_info_destroy( )
//
//              See the main.odin file for several examples of using the library.
//
// License     : MIT Open Source License
// Author      : João Nuno Carvalho
// Date        : 2023.12.26
//

package wav_tools

import "core:fmt"
import "core:strings"
import "core:os"
import "core:mem"
import "core:slice"
import "core:math"
import "core:math/bits"

NumChannels :: enum {
    Not_Defined = 0,
    Mono        = 1,
    Stereo      = 2,
};

BitsPerSample :: enum {
    Not_Defined = 0,
    BPS_8_Bits  = 8,
    BPS_16_Bits = 16,
}

C_HEADER_BYTE_SIZE : int = 44

// WAV file header fields.
// Note: I believe that the fields are in little endian order and they area packed.
WavHeader :: struct #packed {
    chunk_id       : [4]u8,  // This are char[] in the C sense, one byte each.
    chunk_size     : u32,
    format         : [4]u8,  //    "
    fmtchunk_id    : [4]u8,  //    "
    fmtchunk_size  : u32,
    audio_format   : u16,
    num_channels   : u16,
    sample_rate    : u32,
    byte_rate      : u32,
    block_align    : u16,
    bps            : u16,      // Bits per sample. 
    datachunk_id   : [4]u8,  // This are char[] in the C sense, one byte each.
    datachunk_size : u32,
}

WavFile :: struct {
    header : WavHeader,
    data   : []byte,
}

WavInfo :: struct {
    file_name         : string,
    path              : string,
    wav_file          : WavFile,

    sample_rate       : u32,
    num_channels      : u16,
    bits_per_sample   : u16,
     
    number_of_samples : u32,
    file_buf_start    : []u8, // Just to free the memory in the end.
    buf_internal_u8   : []u8,
    buf_internal_i16  : []i16,
}

Error :: struct {
    type        : ErrorType,
    description : string,
}

ErrorType :: enum {
    No_Error,
    File_Not_Found,
    File_Not_Wav,
    File_Not_Supported,
    File_Corrupted,
    File_Invalid,
    File_Invalid_BPS,
    File_Invalid_Num_Channels,
    File_Invalid_Sample_Rate,
    File_Invalid_Data_Size,
    File_Invalid_Data,
    File_Invalid_Data_Size_Mismatch,
}

WAVError :: union {
    bool,
    Error,
}

print_header :: proc ( header : ^WavHeader ) {
    fmt.printf( "----> WavInfo...\n" )
    fmt.printf( "  chunk_id: %s\n", string( header.chunk_id[ : ] ) )
    fmt.printf( "  chunk_size: %d\n", header.chunk_size )
    fmt.printf( "  format: %s\n", string( header.format[ : ] ) )
    fmt.printf( "  fmtchunk_id: %s\n", string( header.fmtchunk_id[ : ] ) )
    fmt.printf( "  fmtchunk_size: %d\n", header.fmtchunk_size )
    fmt.printf( "  audio_format: %d\n", header.audio_format )
    fmt.printf( "  num_channels: %d\n", header.num_channels )
    fmt.printf( "  sample_rate: %d\n", header.sample_rate )
    fmt.printf( "  byte_rate: %d\n", header.byte_rate )
    fmt.printf( "  block_align: %d\n", header.block_align )
    fmt.printf( "  bps: %d\n", header.bps )
    fmt.printf( "  datachunk_id: %s\n", string( header.datachunk_id[ : ] ) )
    fmt.printf( "  datachunk_size: %d\n", header.datachunk_size )
}

print_wav_info :: proc ( wav_info : ^WavInfo ) {
    fmt.printf( "==> WavInfo...\n" )
    fmt.printf( "  file_name: %s\n", wav_info.file_name )
    fmt.printf( "  path: %s\n", wav_info.path )

    fmt.printf( "  sample_rate: %v\n", wav_info.sample_rate )
    fmt.printf( "  num_channels: %v\n", wav_info.num_channels )
    fmt.printf( "  bits_per_sample: %v\n", wav_info.bits_per_sample )
        
    fmt.printf( "  number_of_samples: %d\n", wav_info.number_of_samples )
    if wav_info.buf_internal_u8 == nil {
        fmt.printf( "  buf_internal_u8: nil\n" )
    } else {
        fmt.printf( "  buf_internal_u8 len : %d\n", len( wav_info.buf_internal_u8 ) )
    }
    if wav_info.buf_internal_i16 == nil {
        fmt.printf( "  buf_internal_i16: nil\n" )
    } else {
        fmt.printf( "  buf_internal_i16 len : %d\n", len( wav_info.buf_internal_i16 ) )
    }

    fmt.printf("\n")
    print_header( & wav_info.wav_file.header )
    fmt.printf("\n")
}

// Loads a wav file from disk.
wav_load_file :: proc ( file_name, path : string ) ->
        ( wav_info : WavInfo, wav_error: WAVError ) {

    wav_info = WavInfo{}
    
    // Checks if the filename ends with a .wav extension.
    if !( strings.has_suffix( file_name, ".wav" )  ||
          strings.has_suffix( file_name, ".WAV" )  ) {
        wav_error = Error{ ErrorType.File_Not_Wav, "File does not terminate with the .wav extension." }
        return wav_info, wav_error
    }

    // Joins the path and the filename.
    file_path := fmt.aprintf( "%s%s", path, file_name ); 

    // Reads the entire file in binary mode.
    file_data , success := os.read_entire_file_from_filename( file_path )
    if !success {
        wav_error = Error{ ErrorType.File_Not_Found, "File not found." }
        return wav_info, wav_error
    }

    // Sets the file_info struct file_buf_start pointer to the start of the file data
    // returned when the file is entairelly read.
    wav_info.file_buf_start = file_data
    
    // Checks if the file is big enough to contain a wav header.
    assert( size_of(WavHeader) == C_HEADER_BYTE_SIZE )
    if len( file_data ) < C_HEADER_BYTE_SIZE {
        wav_error = Error{ ErrorType.File_Corrupted, "File is too small to contain a wav file header." }
        return wav_info, wav_error
    }

    // Copies and converts the file data to a WavHeader struct.
    mem.copy( & wav_info.wav_file.header,
              rawptr( raw_data( file_data ) ), size_of(WavHeader) )

    wave_file_header := & wav_info.wav_file.header

    // Checks if the file is a wav file looking into the header.
    if !( mem.compare( wave_file_header.chunk_id[:], []byte{'R', 'I', 'F', 'F'} ) == 0 ||
          mem.compare( wave_file_header.format[:], []byte{ 'W', 'A', 'V', 'E' } ) == 0    ) {
        wav_error = Error{ ErrorType.File_Not_Wav, "File is not a wav file, it's intenal structure is different." }
        return wav_info, wav_error
    }

    // Fills in the file info outer struct wiht the inner struct values.
    wav_info.sample_rate     = wave_file_header.sample_rate
    wav_info.num_channels    = wave_file_header.num_channels
    wav_info.bits_per_sample = wave_file_header.bps
    
    // Validate the size of the file data read.
    if len( file_data ) != C_HEADER_BYTE_SIZE + int( wave_file_header.datachunk_size ) {
        wav_error = Error{ ErrorType.File_Invalid_Data_Size, "File has an invalid data size." }
        return wav_info, wav_error
    }

    // Calculates the number os samples and fills the internal struct with the data.
    switch ( wave_file_header.bps ) {
        case u16( BitsPerSample.BPS_8_Bits ) :
            wav_info.number_of_samples = wave_file_header.datachunk_size / u32( wave_file_header.num_channels )
            wav_info.buf_internal_u8   = transmute( []u8 )( file_data[ C_HEADER_BYTE_SIZE : ] )
        case u16( BitsPerSample.BPS_16_Bits ) :
            wav_info.number_of_samples = ( wave_file_header.datachunk_size / 2 ) / u32( wave_file_header.num_channels )
            wav_info.buf_internal_i16  = transmute( []i16 )( file_data[ C_HEADER_BYTE_SIZE : ] )
        case:
            wav_error = Error{ ErrorType.File_Invalid_BPS, "File has an invalid number of bits per sample." }
            return wav_info, wav_error
    }

    // Fill the fields.
    wav_info.file_name = file_name
    wav_info.path      = path

    wav_error = Error{ ErrorType.No_Error, "File correctly loaded." }
    
    return wav_info, wav_error
}

// Creates a wav info from nothing.
// That will allow then to write a Wave file to disk
wav_info_create :: proc ( file_name, path : string,
                            num_channels  : u16,
                            sample_rate   : u32,
                            bps           : u16 ) -> 
                           ( wav_info : WavInfo, wav_error: WAVError ) {

    wav_info = WavInfo{}

    // Checks if the filename ends with a .wav extension.
    if !( strings.has_suffix( file_name, ".wav" )  ||
          strings.has_suffix( file_name, ".WAV" )  ) {

        wav_error = Error{ ErrorType.File_Not_Wav, "File does not terminate with the .wav extension." }
        return wav_info, wav_error
    }

    // Joins the path and the filename.
    file_path := fmt.aprintf( "%s/%s", path, file_name ); 

    // Fill the fields.
    wav_info.file_name = file_name
    wav_info.path      = path

    // Fill the header.
    header_tmp := & wav_info.wav_file.header
    header_tmp^.chunk_id       = [4]u8{ 'R', 'I', 'F', 'F' }
    header_tmp^.chunk_size     = 0                           // This will be filled later.
    header_tmp^.format         = [4]u8{ 'W', 'A', 'V', 'E' }
    header_tmp^.fmtchunk_id    = [4]u8{ 'f', 'm', 't', ' ' }
    header_tmp^.fmtchunk_size  = 16
    header_tmp^.audio_format   = 1
    header_tmp^.num_channels   = u16( num_channels )
    header_tmp^.sample_rate    = sample_rate
    header_tmp^.byte_rate      = sample_rate * u32( num_channels ) * u32( bps ) / 8
    header_tmp^.block_align    = u16( num_channels ) * u16( bps ) / 8
    header_tmp^.bps            = u16( bps )
    header_tmp^.datachunk_id   = [4]u8{ 'd', 'a', 't', 'a' }
    header_tmp^.datachunk_size = 0                          // This will be filled later. 

    // Fills in the file info outer struct wiht the inner struct values.
    wav_info.sample_rate     = header_tmp^.sample_rate
    wav_info.num_channels    = header_tmp^.num_channels
    wav_info.bits_per_sample = header_tmp^.bps

    // Success.
    wav_error = Error{ ErrorType.No_Error, "File correctly created." }
    return wav_info, wav_error
}

// Creates a wav info from nothing whit enum types.
wav_info_create_enum :: proc ( file_name, path : string,
                               num_channels    : NumChannels,   /* u16 */
                               sample_rate     : u32,
                               bps             : BitsPerSample  /* u16 */  ) -> 
                               ( wav_info : WavInfo, wav_error: WAVError ) {

    return wav_info_create( file_name,
                            path,
                            u16( num_channels ),
                            sample_rate,
                            u16( bps ) )
}

// Free the memory allocated by the wav info, while reading.
wav_info_destroy :: proc ( wav_info : ^WavInfo ) {
    delete( wav_info.file_buf_start )
    wav_info.file_buf_start = nil
    wav_info.buf_internal_u8 = nil
    wav_info.buf_internal_i16 = nil

    // Zero the struct.
    mem.zero( wav_info, size_of(WavInfo) )
}

get_buffer_d32_normalized :: proc ( wav_info : ^WavInfo) ->
         ( num_channels : int , buf_left, buf_right : []f32 ) {

    num_channels = int( wav_info.wav_file.header.num_channels )
    
    // Allocate the return buffers.
    if num_channels == int( NumChannels.Mono ) {
        buf_left  = make( []f32, wav_info.number_of_samples )
        buf_right = nil
    } else {
        buf_left  = make( []f32, wav_info.number_of_samples )
        buf_right = make( []f32, wav_info.number_of_samples )
    }
    
    // Reads from the 8 bit buffer or from the 16 bit buffer.
    switch ( wav_info.wav_file.header.bps ) {
        case u16( BitsPerSample.BPS_8_Bits ) :
            u8_half_max := f32( bits.U8_MAX / 2 )
            if num_channels == int( NumChannels.Mono ) {
                for i in 0 ..< wav_info.number_of_samples {
                    buf_left[i] = ( f32( wav_info.buf_internal_u8[i] ) - u8_half_max ) / u8_half_max
                    buf_left[i] = clamp_value( buf_left[i], -1.0, 1.0 )
                }
                buf_right = nil
            } else {
                for i in 0 ..< wav_info.number_of_samples {
                    buf_left[i]  = ( f32( wav_info.buf_internal_u8[ 2 * i ] ) - u8_half_max ) / u8_half_max
                    buf_left[i]  = clamp_value( buf_left[i], -1.0, 1.0 )
                    buf_right[i] = ( f32( wav_info.buf_internal_u8[ 2 * i + 1 ] ) - u8_half_max ) / u8_half_max
                    buf_right[i] = clamp_value( buf_right[i], -1.0, 1.0 )
                }
            }

        case u16( BitsPerSample.BPS_16_Bits ) :

            if num_channels == int( NumChannels.Mono ) {
                for i in 0 ..< wav_info.number_of_samples {
                    buf_left[i] = f32( wav_info.buf_internal_i16[i] ) / f32( bits.I16_MAX )
                }
                buf_right = nil
            } else {
                for i in 0 ..< wav_info.number_of_samples {
                    buf_left[i]  = f32( wav_info.buf_internal_i16[ 2 * i ] )     / f32( bits.I16_MAX )
                    buf_right[i] = f32( wav_info.buf_internal_i16[ 2 * i + 1 ] ) / f32( bits.I16_MAX )
                }
            }

        case:
            panic( "Invalid number of bits per sample." )
    }

    return num_channels, buf_left, buf_right
}

// If there is only one channel Mono, the right buffer has to be nil.
// The buffers have to be normalized between -1.0 and 1.0  .
set_buffer_d32_normalized :: proc ( wav_info            : ^WavInfo,
                                    buf_left, buf_right : []f32 ) ->
                                    ( wav_error : WAVError ) {
    
    // Get the number of channels.
    num_channels := int( wav_info.wav_file.header.num_channels )

    // Fill the num of samples.
    wav_info.number_of_samples = u32( len( buf_left ) )

    // Checks the number of buffers not nil against the number of channels.
    if num_channels == int( NumChannels.Mono ) {
        if buf_right != nil {
            wav_error = Error{ ErrorType.File_Invalid_Num_Channels,
                "File has only one channel, the left channel is nil, and only the right channel should be nil." }
            return wav_error
        }
    } else {
        if len( buf_right ) != int( wav_info.number_of_samples ) {
            wav_error = Error{ ErrorType.File_Invalid_Data_Size_Mismatch,
                "Buffer size mismatch. Both buffers (left and right) need to have the some size" }
            return wav_error
        }
    }

    // Checks if the samples are normalized.
    for i in 0 ..< wav_info.number_of_samples {
        if math.abs( buf_left[i] ) > 1.0 {
            err_message := fmt.aprintf( "Left buffer contains values outside the normalized range. buf_left[ %v ] = %f", i,  buf_left[i] )
            wav_error = Error{ ErrorType.File_Invalid_Data, err_message }
            return wav_error

            // fmt.printf( "%v\n", err_message )
        }
        if num_channels == int( NumChannels.Stereo ) {
            if math.abs( buf_right[i] ) > 1.0 {
                err_message := fmt.aprintf( "Left buffer contains values outside the normalized range. buf_right[ %v ] = %f", i, buf_right[i] )
                wav_error = Error{ ErrorType.File_Invalid_Data, err_message }
                return wav_error
            }
        }
    }

    // Allocate the internal buffer.
    switch ( wav_info.wav_file.header.bps ) {
        case u16( BitsPerSample.BPS_8_Bits ) :
            wav_info.file_buf_start = make( []u8, C_HEADER_BYTE_SIZE + 
                int( wav_info.number_of_samples ) * int( num_channels ) )
            wav_info.buf_internal_u8 = wav_info.file_buf_start[ C_HEADER_BYTE_SIZE : ]
        case u16( BitsPerSample.BPS_16_Bits ) :
            wav_info.file_buf_start = make( []u8, C_HEADER_BYTE_SIZE + 
                int( wav_info.number_of_samples ) * 2 * int( num_channels ) )
            wav_info.buf_internal_i16 = transmute( []i16 )( wav_info.file_buf_start[ C_HEADER_BYTE_SIZE : ] )
        case:
            wav_error = Error{ ErrorType.File_Invalid_BPS,
                "Invalid number of bits per sample." }
            return wav_error
    }

    // Fill the header.
    header_tmp := & wav_info.wav_file.header
    // header_tmp^.header.chunk_size = 0
    header_tmp^.fmtchunk_size  = 16
    header_tmp^.audio_format   = 1
    header_tmp^.datachunk_size = wav_info.number_of_samples *
             u32( num_channels ) * u32( wav_info.wav_file.header.bps ) / 8
    // Fill of the the first chunck size. It has to be made out of order.
    header_tmp^.chunk_size = 36 + header_tmp^.datachunk_size;
             
    // Writes the header to the internal buffer.
    mem.copy( rawptr( raw_data( wav_info.file_buf_start ) ),
            & wav_info.wav_file.header, size_of(WavHeader) )

    // Writes the data to the internal buffer.
    switch ( wav_info.wav_file.header.bps ) {

        case u16( BitsPerSample.BPS_8_Bits ) :

            u8_half_max := bits.U8_MAX / 2
            if num_channels == int( NumChannels.Mono ) {
                for i in 0 ..< int( wav_info.number_of_samples ) {
                    wav_info.buf_internal_u8[ i ] = 
                        u8( ( buf_left[i] * f32( u8_half_max ) ) + f32( u8_half_max ) )
                }
            } else {
                for i in 0 ..< int( wav_info.number_of_samples ) {
                    wav_info.buf_internal_u8[ 2 * i ]     = 
                        u8( ( buf_left[i] * f32( u8_half_max ) ) + f32( u8_half_max ) )
                    wav_info.buf_internal_u8[ 2 * i + 1 ] = 
                        u8( ( buf_right[i] * f32( u8_half_max ) ) + f32( u8_half_max ) )
                }
            }

        case u16( BitsPerSample.BPS_16_Bits ) :

            if num_channels == int( NumChannels.Mono ) {
                for i in 0 ..< int( wav_info.number_of_samples ) {
                    wav_info.buf_internal_i16[ i ] = 
                        i16( buf_left[i] * f32( bits.I16_MAX ) )
                }
            } else {
                for i in 0 ..< int( wav_info.number_of_samples ) {
                    wav_info.buf_internal_i16[ 2 * i ]     = 
                        i16( buf_left[i] * f32( bits.I16_MAX ) )
                    wav_info.buf_internal_i16[ 2 * i + 1 ] = 
                        i16( buf_right[i] * f32( bits.I16_MAX ) )
                }
            }

        case:

            wav_error = Error{ ErrorType.File_Invalid_BPS,
                "Invalid number of bits per sample." }
            return wav_error
    }
        
    wav_error = Error{ ErrorType.No_Error, "Buffer filled correctly." }                                
    return wav_error                                    
}

// Writes the wav file to disk.
wav_write_file :: proc ( wav_info : ^WavInfo ) -> ( wav_error : WAVError ) {

    // Checks if the filename ends with a .wav extension.
    if !( strings.has_suffix( wav_info.file_name, ".wav" )  ||
          strings.has_suffix( wav_info.file_name, ".WAV" )  ) {
        wav_error = Error{ ErrorType.File_Not_Wav, "File does not terminate with the .wav extension." }
        return wav_error
    }

    // Joins the path and the filename.
    file_path := fmt.aprintf( "%s%s", wav_info.path, wav_info.file_name );

    // Writes the file to disk.
    success := os.write_entire_file( file_path, wav_info.file_buf_start )
    if !success {
        wav_error = Error{ ErrorType.File_Not_Found, "File error, while writting file to disk." }
        return wav_error
    }

    // Success.
    wav_error = Error{ ErrorType.No_Error, "File correctly written." }
    return wav_error
}

clamp_value :: proc ( value : f32, min_value, max_value : f32 ) -> ( clamped_value : f32 ) {
    if value < min_value {
        clamped_value = min_value
    } else if value > max_value {
        clamped_value = max_value
    } else {
        clamped_value = value
    }
    return clamped_value
}
