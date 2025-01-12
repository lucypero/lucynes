
package main

/// scratch, quick access

// rom_in_nes :: "roms/Battletoads.nes"
// rom_in_nes :: "roms/Castlevania.nes"
rom_in_nes :: "roms/Super Mario Bros. 3.nes"
// rom_in_nes :: "roms/SuperMarioBros.nes"

/// FULLY WORKING GAMES:

// Mapper 0

// rom_in_nes :: "roms/SuperMarioBros.nes"
// rom_in_nes :: "roms/DonkeyKong.nes"
// rom_in_nes :: "roms/Kung Fu.nes"
// rom_in_nes :: "roms/IceClimber.nes"
// rom_in_nes :: "roms/PacMan.nes"
// rom_in_nes :: "roms/Bomberman.nes"

// Mapper 1

// rom_in_nes :: "roms/Mega Man II.nes"
// rom_in_nes :: "roms/Legend of Zelda, The.nes"
// rom_in_nes :: "roms/Tetris.nes"
// rom_in_nes :: "roms/Final Fantasy.nes"
// rom_in_nes :: "roms/Final Fantasy II (USA) (Proto).nes"
// rom_in_nes :: "roms/Metroid.nes"
// rom_in_nes :: "roms/Blaster Master.nes"
// rom_in_nes :: "roms/Batman.nes"

// Mapper 2

// rom_in_nes :: "roms/Mega Man.nes"
// rom_in_nes :: "roms/Metal Gear.nes"
// rom_in_nes :: "roms/Contra.nes"
// rom_in_nes :: "roms/Duck Tales.nes"
// rom_in_nes :: "roms/Castlevania.nes"

// Mapper 3

// rom_in_nes :: "roms/Ghostbusters.nes"
// rom_in_nes :: "roms/Solomon's Key.nes" // wow this one is actually good

// Mapper 4

// rom_in_nes :: "roms/Silver Surfer.nes"
// rom_in_nes :: "roms/Solomon's Key 2 (Europe).nes"
// rom_in_nes :: "roms/Mega Man III.nes"
// rom_in_nes :: "roms/Mega Man IV.nes"
// rom_in_nes :: "roms/Mega Man V.nes"
// rom_in_nes :: "roms/Mega Man VI.nes"
// rom_in_nes :: "roms/Final Fantasy III (Japan).nes"
// rom_in_nes :: "roms/Super Mario Bros. 3.nes"

// Mapper 7

// rom_in_nes :: "roms/Cobra Triangle.nes" 
// rom_in_nes :: "roms/R.C. Pro-Am II.nes"
// rom_in_nes :: "roms/Teenage Mutant Ninja Turtles.nes"
// rom_in_nes :: "roms/Ghosts 'N Goblins.nes"

/// NON-WORKING GAMES: 

// Reason: Mapper unsupported

// Mapper 64

// rom_in_nes :: "roms/Ms. Pac Man (Tengen).nes"

// Mapper 67

// rom_in_nes :: "roms/Spy Hunter.nes"
// rom_in_nes :: "roms/Karate Kid, The.nes"

// Mapper 69

// rom_in_nes :: "roms/Batman - Return of the Joker.nes"

// Reason: Emulator Bug

// rom_in_nes :: "roms/Battletoads & Double Dragon - The Ultimate Team.nes"
// rom_in_nes :: "roms/Battletoads.nes" // doesn't work after start screens and start cutscene. if i force sprite 0 hit, it works.
// rom_in_nes :: "roms/Spelunker.nes"
// rom_in_nes :: "roms/Adventures of Lolo II , The.nes"
// rom_in_nes :: "roms/Dragon Warrior.nes" // this is dragon quest. mapper 1

/// TEST ROMS:

// hard to judge if u pass
// rom_in_nes :: "tests/full_nes_palette.nes"
// rom_in_nes :: "tests/nmi_sync/demo_pal.nes"
// rom_in_nes :: "tests/240pee.nes"
// rom_in_nes :: "tests/full_palette.nes"

// rom_in_nes :: "tests/cpu_timing_test6/cpu_timing_test.nes" // passed
// rom_in_nes :: "tests/branch_timing_tests/1.Branch_Basics.nes" // passed
// rom_in_nes :: "nestest/nestest.nes" // passed

// rom_in_nes :: "tests/color_test.nes" // failed. tests ppu mask emphasis and grayscale (important)

/// VBL NMI TIMING

// rom_in_nes :: "tests/vbl_nmi_timing/1.frame_basics.nes" // Fails. Fix it.
// rom_in_nes :: "tests/vbl_nmi_timing/2.vbl_timing.nes"
// rom_in_nes :: "tests/vbl_nmi_timing/3.even_odd_frames.nes"
// rom_in_nes :: "tests/vbl_nmi_timing/4.vbl_clear_timing.nes"
// rom_in_nes :: "tests/vbl_nmi_timing/5.nmi_suppression.nes"
// rom_in_nes :: "tests/vbl_nmi_timing/6.nmi_disable.nes"
// rom_in_nes :: "tests/vbl_nmi_timing/7.nmi_timing.nes"

// NMI tests

// rom_in_nes :: "tests/nmi_sync/demo_ntsc.nes"
// rom_in_nes :: "tests/cpu_interrupts_v2/cpu_interrupts.nes"
// rom_in_nes :: "tests/cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes"
// rom_in_nes :: "tests/cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes"


// Audio tests

// rom_in_nes :: "tests/audio/clip_5b_nrom.nes"
// rom_in_nes :: "tests/audio/sweep_5b_nrom.nes"
