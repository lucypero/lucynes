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


## Fixing spelunker


$82FD: INC $48 // A:$20, X:$1C, Y:$FF, PY: 45, PX: 119, (x:118, y:45), PV: 149
$82FF: RTS // A:$20, X:$1C, Y:$FF, PY: 45, PX: 137, (x:136, y:45), PV: 149
$822D: DEC $1F // A:$20, X:$1C, Y:$FF, PY: 45, PX: 152, (x:151, y:45), PV: 149
$822F: BNE -> $822A // A:$20, X:$1C, Y:$FF, PY: 45, PX: 161, (x:160, y:45), PV: 149
$822A: JSR $82BA // A:$20, X:$1C, Y:$FF, PY: 45, PX: 179, (x:178, y:45), PV: 149
$82BA: LDA $023E // A:$2D, X:$1C, Y:$FF, PY: 45, PX: 191, (x:190, y:45), PV: 149
$82BD: STA $10 // A:$2D, X:$1C, Y:$FF, PY: 45, PX: 200, (x:199, y:45), PV: 149
$82BF: LDA $023F // A:$BE, X:$1C, Y:$FF, PY: 45, PX: 212, (x:211, y:45), PV: 149
$82C2: STA $11 // A:$BE, X:$1C, Y:$FF, PY: 45, PX: 221, (x:220, y:45), PV: 149
$82C4: JSR $BC43 // A:$BE, X:$1C, Y:$FF, PY: 45, PX: 239, (x:238, y:45), PV: 149
$BC43: LDA $10 // A:$2D, X:$1C, Y:$FF, PY: 45, PX: 248, (x:247, y:45), PV: 149
$BC45: CMP $3C // A:$2D, X:$1C, Y:$FF, PY: 45, PX: 257, (x:256, y:45), PV: 149
$BC47: BNE -> $BC50 // A:$2D, X:$1C, Y:$FF, PY: 45, PX: 266, (x:265, y:45), PV: 149
$BC50: LDA $3E // A:$4, X:$1C, Y:$FF, PY: 45, PX: 275, (x:274, y:45), PV: 149
$BC52: BNE -> $BC50 // A:$4, X:$1C, Y:$FF, PY: 45, PX: 284, (x:283, y:45), PV: 149

it gets stuck between those 2 lines
