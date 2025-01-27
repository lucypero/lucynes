# lucyNES

NES emulator written in Odin.

# Features

- Debugger view with some debugging features
- Menu view to interact with the emulator
- Save states
- Controller support
- CRT Shader toggle
- (Partial) Sound
- Enough emulation accuracy to run Battletoads and hundreds of other games perfectly.
- Supported Mappers: 	NROM, MMC1, UXROM, CNROM, MMC3, GxROM, AxROM

# Controls (Keyboard)

`M` - Toggle menu view

`F1` - Save to selected slot

`F4` - Load from selected slot

`P` - Pause

`WASD` - (NES Controller) Arrows

`H` - (NES Controller) A button

`J` - (NES Controller) B button

`Y` - (NES Controller) Select button

`U` - (NES Controller) Start button

# Controls (assuming an XBOX controller)

`D-pad` - Arrows

`A` - A Button

`X` - B Button

`View Button` - Select

`Menu Button` - Start

# What to work on next

- [ ] Improve sound
- [ ] Implement DMC
- [ ] Finish implementing PPUMASK features
- [ ] Fix Dragon Warrior
- [ ] Fix Batman
- [ ] Implement more popular mappers
- [ ] In-app ROM selection

# How to build

`odin run src -out:lucynes.exe`

It will not run if the default ROM isn't in the `roms` directory. If you want to play a specific ROM, you can...:

```
odin build src -o:speed -out:lucynes.exe
lucynes [path-to-rom]
```

Example, after building:

`lucynes roms/Castlevania.nes` (assuming `Castlevania.nes` is in the `roms` directory, in the same directory as the `lucynes` executable.

# Showcase

## Debugger view

https://github.com/user-attachments/assets/240fbda8-4e75-4b93-b485-15ab7fd3c7bb

## Menu view

https://github.com/user-attachments/assets/a09d3cc3-a58b-44ea-8771-bcb8bb00a3d6

## Screenshots

![Megaman VI on lucynes](https://github.com/user-attachments/assets/41ba0e3a-9520-4b11-a5cc-7926bf3f15bd)
![Solomon's Key 2 on lucynes](https://github.com/user-attachments/assets/7bba8fa2-858e-4e73-86e4-8f94d46db19e)
![Super Mario Brothers 3 on lucynes](https://github.com/user-attachments/assets/d9f08bdb-c45f-4e40-a321-475b2d216d60)
![Castlevania on lucynes](https://github.com/user-attachments/assets/069c21ad-2653-4021-84a9-5d6bb4e4053a)
![Final Fantasy 3 on lucynes](https://github.com/user-attachments/assets/52720c8b-1ca9-4c55-9fca-33ae737b970a)
![The Legend of Zelda on lucynes](https://github.com/user-attachments/assets/edcbadf1-9f50-46f0-8274-e45dc8d71233)
