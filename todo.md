# Fixing spelunker

PC:

BC50
BC52


# Todo

- do a proper OAMDMA implementation.

- figure out what to do on the NES init reads (should u tick the PPU?)

- don't allocate memory for the whole bus.
 the bus is a fake thing. it's not ram
 put actual ram in separate fields. it's easier.

- an article on 6502 interrupts
	http://wilsonminesco.com/6502interrupts/

- Wrap up audio
	- Make Mario sound normal
	- DMC channel

- save states

- PPUMASK
	- greyscale, modification of colors, and all that
	- test with color_test.nes

- Debugger:
	- do something special for ppu and apu registers
	- have some indication to when it got NMI'd. Maybe also when it jumped normally.
	- PPU state display

- Support controllers

# Input

write 1 -> $4016: signal controller to poll its input
write 0 -> $4016: signal controller to finish its poll

read $4016 or $4017: reads controller input (port 0 or 1), one bit at a time
	reads highest bit only. then it left shifts by one bit
	reads right shifts bits by one

order of inputs:

(highest bit) -> lowest bit

A B Select Start Up Down Left Right

# possible bug

when i was playing mario and i went rainbow mode, this happened:

edit: it happens at other times too.

idk what u read/writing here at ppu bus FFF6
idk what u read/writing here at ppu bus FFFE
idk what u read/writing here at ppu bus FFF6
idk what u read/writing here at ppu bus FFFE
idk what u read/writing here at ppu bus FFF3
idk what u read/writing here at ppu bus FFFB
idk what u read/writing here at ppu bus FFF3
idk what u read/writing here at ppu bus FFFB
idk what u read/writing here at ppu bus FFF0
idk what u read/writing here at ppu bus FFF8
idk what u read/writing here at ppu bus FFF0
idk what u read/writing here at ppu bus FFF8
idk what u read/writing here at ppu bus FFF5
idk what u read/writing here at ppu bus FFFD
idk what u read/writing here at ppu bus FFF5
idk what u read/writing here at ppu bus FFFD
idk what u read/writing here at ppu bus FFF2
idk what u read/writing here at ppu bus FFFA
idk what u read/writing here at ppu bus FFF2
idk what u read/writing here at ppu bus FFFA

# notes compared to javidx

it seems he has the same sprite misalignment as me.
sprites are one pixel to the left. or more.
also they are one pixel up. i checked

see this for reference
https://www.youtube.com/watch?v=7qirrV8w5SQ&t=344s



# odin stuff

default_allocator :: heap_allocator
default_allocator_proc :: heap_allocator_proc

heap allocator has no data of what is storing so u can't know what was allocated, and how many bytes were allocated


	Default_Temp_Allocator :: struct {
		arena: Arena,
	}

temp allocator is an arena
core/mem/allocators.odin


- figure out how to figure out how much allocators are allocating
- does the temp allocator even exist if u don't init it?



# Playable games list:

SMB1
Megaman 1
Contra
Duck Tales
Castlevania
Metal Gear
Ice Climber
Donkey Kong
Kung Fu
Bomberman
