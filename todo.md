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


# Mapper code

read your discord general for more information

the cart can dictate everything.

so when you for example do cpu read, first of all check the mapper if it wants to do something
if not then proceed to do the read normally.

## Mapper 1: fixing dragon quest

(it's still broken)

dragon quest is setting prg_bank_select_16lo to index 4. more than the total amount of banks (4)


i tried wrapping the bank select. it still doesn't boot

idk what to do.

here's the cart info:

https://nescartdb.com/profile/view/54/dragon-warrior

PCB Class 	NES-SAROM

Mirroring 	Mapper Ctrl
Battery present 	Yes
WRAM 	8 KB
VRAM 	0 KB
CIC Type 	6113B1
Hardware 	MMC1B2

## Fixing batman:

(it's still broken)


## fixing battletoads

it freezes when loading the first level.

- print logs, the ones you did.
- force sprite 0 hit and see what happens.
	- game works fine if u force sprite 0 hit.

after debugging in Mesen, i see the entire screen is palette index 3 in mesen, so sprite 0 is hit.
in lucynes, background is at 0, so the hit is never done. i don't know why this happens.
might be a mapper bug.

sprite 0 hit happens in 255, 30
background tile:
id $61
addr: $1610
pattern: all 3, not 0. that's why it hits.



maybe u have to do this.. this is from mesen

```cpp
	//Rendering enabled flag is apparently set with a 1 cycle delay (i.e setting it at cycle 5 will render cycle 6 like cycle 5 and then take the new settings for cycle 7)
	if(_prevRenderingEnabled != _renderingEnabled) {
		_emu->AddDebugEvent<CpuType::Nes>(DebugEventType::BgColorChange);
		_prevRenderingEnabled = _renderingEnabled;
		if(_scanline < 240) {
			if(_prevRenderingEnabled) {
				//Rendering was just enabled, perform oam corruption if any is pending
				ProcessOamCorruption();
			} else if(!_prevRenderingEnabled) {
				//Rendering was just disabled by a write to $2001, check for oam row corruption glitch
				SetOamCorruptionFlags();

				//When rendering is disabled midscreen, set the vram bus back to the value of 'v'
				SetBusAddress(_videoRamAddr & 0x3FFF);
				
				if(_cycle >= 65 && _cycle <= 256) {
					//Disabling rendering during OAM evaluation will trigger a glitch causing the current address to be incremented by 1
					//The increment can be "delayed" by 1 PPU cycle depending on whether or not rendering is disabled on an even/odd cycle
					//e.g, if rendering is disabled on an even cycle, the following PPU cycle will increment the address by 5 (instead of 4)
					//     if rendering is disabled on an odd cycle, the increment will wait until the next odd cycle (at which point it will be incremented by 1)
					//In practice, there is no way to see the difference, so we just increment by 1 at the end of the next cycle after rendering was disabled
					_spriteRamAddr++;

					//Also corrupt H/L to replicate a bug found in oam_flicker_test_reenable when rendering is disabled around scanlines 128-136
					//Reenabling the causes the OAM evaluation to restart misaligned, and ends up generating a single sprite that's offset by 1
					//such that it's Y=tile index, index = attributes, attributes = x, and X = the next sprite's Y value
					_spriteAddrH = (_spriteRamAddr >> 2) & 0x3F;
					_spriteAddrL = _spriteRamAddr & 0x03;
				}
			}
		}
	}
```

loopy explained better:

https://forums.nesdev.org/viewtopic.php?p=5578#p5578


- no matter what i do, i cannot make battletoads work without forcing a sprite 0 hit.



- good debugging ideas:
	- draw only bg
	- draw only fg
	- draw with debug palette
	- make these toggleables in a menu.
	- implement save states to disk so u can get to the bug fast.
