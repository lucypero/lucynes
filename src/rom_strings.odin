
package main

/// scratch, quick access

// rom_in_nes :: "roms/Battletoads.nes"
// rom_in_nes :: "roms/Castlevania.nes"
// rom_in_nes :: "roms/Super Mario Bros. 3.nes"
// rom_in_nes :: "roms/SuperMarioBros.nes"
// rom_in_nes :: "roms/Spelunker.nes"

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
// rom_in_nes :: "roms/Battletoads & Double Dragon - The Ultimate Team.nes"

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

// rom_in_nes :: "roms/Spelunker.nes"
// rom_in_nes :: "roms/Adventures of Lolo II , The.nes"
// rom_in_nes :: "roms/Dragon Warrior.nes" // this is dragon quest. mapper 1
// rom_in_nes :: "roms/Batman.nes"

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
// https://github.com/christopherpow/nes-test-roms/blob/master/vbl_nmi_timing/readme.txt

// rom_in_nes :: "tests/vbl_nmi_timing/1.frame_basics.nes" // passed
// rom_in_nes :: "tests/vbl_nmi_timing/2.vbl_timing.nes" // passed
// rom_in_nes :: "tests/vbl_nmi_timing/3.even_odd_frames.nes" // passed
// rom_in_nes :: "tests/vbl_nmi_timing/4.vbl_clear_timing.nes" // passed

// i fail 3 but i don't understand this one.
// rom_in_nes :: "tests/vbl_nmi_timing/5.nmi_suppression.nes" // passed
// rom_in_nes :: "tests/vbl_nmi_timing/6.nmi_disable.nes" // passed
// HERE
rom_in_nes :: "tests/vbl_nmi_timing/7.nmi_timing.nes" // failed #3

// NMI tests

// rom_in_nes :: "tests/nmi_sync/demo_ntsc.nes"
// rom_in_nes :: "tests/cpu_interrupts_v2/cpu_interrupts.nes"
// rom_in_nes :: "tests/cpu_interrupts_v2/rom_singles/2-nmi_and_brk.nes"
// rom_in_nes :: "tests/cpu_interrupts_v2/rom_singles/3-nmi_and_irq.nes"

// Audio tests

// rom_in_nes :: "tests/audio/clip_5b_nrom.nes"
// rom_in_nes :: "tests/audio/sweep_5b_nrom.nes"

// Sprite 0 Hit tests. they all pass

// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/01.basics.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/02.alignment.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/03.corners.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/04.flip.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/05.left_clip.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/06.right_edge.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/07.screen_bottom.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/08.double_height.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/09.timing_basics.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/10.timing_order.nes"
// rom_in_nes :: "tests/sprite_hit_tests_2005.10.05/11.edge_timing.nes"
