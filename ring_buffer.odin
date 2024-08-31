package main

// simple ring buffer
Buffer :: struct {
	data:      []f32,
	written:   int,
	write_pos: int,
	read_pos:  int,
}

buffer_init :: proc(b: ^Buffer, size: int) {
	b.data = make([]f32, size)
}

// this writes a single sample of data to the buffer, overwriting what was previously there
buffer_write_sample :: proc(b: ^Buffer, sample: f32, advance_pos: bool) {
	buffer_write_slice(b, {sample}, advance_pos)
}

// this writes a slice data to the buffer, overwriting what was previously there
buffer_write_slice :: proc(b: ^Buffer, data: []f32, advance_pos: bool) {
	assert(len(b.data) - b.written > len(data))
	write_pos := b.write_pos
	for di in 0 ..< len(data) {
		write_pos += 1
		if write_pos >= len(b.data) do write_pos = 0
		b.data[write_pos] = data[di]
	}

	if advance_pos {
		b.written += len(data)
		b.write_pos = write_pos
	}
}

// this reads data from the buffer and copies it into the dst slice
buffer_read :: proc(dst: []f32, b: ^Buffer, advance_index: bool = true) {
	read_pos := b.read_pos
	for di in 0 ..< len(dst) {
		read_pos += 1
		if read_pos >= len(b.data) do read_pos = 0
		dst[di] = b.data[read_pos]
		b.data[read_pos] = 0
	}

	if advance_index {
		b.written -= len(dst)
		b.read_pos = read_pos
	}
}
