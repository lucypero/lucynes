# Fixing spelunker

PC:

BC50
BC52


# Todo

- Wrap up audio
	- Make Mario sound normal
	- DMC channel

- PPUMASK
	- greyscale, modification of colors, and all that
	- test with color_test.nes

# Input

write 1 -> $4016: signal controller to poll its input
write 0 -> $4016: signal controller to finish its poll

read $4016 or $4017: reads controller input (port 0 or 1), one bit at a time
	reads highest bit only. then it left shifts by one bit
	reads right shifts bits by one

order of inputs:

(highest bit) -> lowest bit

A B Select Start Up Down Left Right

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

## fixing audio

i showed spelunker music bug and someone said:

"that sounds like the hardware sweeps aren't being terminated properly"


## about passing vbl nmi timing test

https://www.nesdev.org/wiki/CPU_interrupts

read "Branch instructions and interrupts"

there's special cases with branch instructions.

that's probably why #7 fails at the last vbl nmi timing testa.
