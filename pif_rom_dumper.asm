// Dump PIF ROM to the first 2k of SRAM
//
// This includes a bit of PIF RAM and registers at the end.
// The idea is that since WatchLo is preserved on reset, we can get a
// Watch exception while our old handler is still resident, before PIF ROM
// is disabled.
//
// Thanks to Zoinkity for the idea.
// Almost everything in LIB is by Peter Lemon (krom), thanks for all the help!
// SRAM interface from Visor's Neon64 w/ Savestates
// -hcs 2020-05-31

arch n64.cpu
endian msb
output "pif_rom_dumper.n64", create
fill 0x10'1000

origin 0
base 0x8000'0000
include "LIB/N64.INC"
include "LIB/N64_RSP.INC"
include "LIB/N64_GFX.INC"
N64_HEADER(Start, "PIF ROM dumper")
insert "LIB/N64_BOOTCODE.BIN"

constant pif_copy(0x8030'0000)
constant pif_copy_end(pif_copy+0x800)
constant scratchpad(pif_copy_end)
constant magic(0xcedec0de)

constant HW_INT_PRE_NMI(2)
constant WatchExcCode(23)

constant fb(0xa010'0000)
constant fb_width(640)
constant fb_height(240)

constant text_start_x(46)
constant text_start_y(16)

constant font_rom(0xb000'0b70)
constant font_width(13)
constant font_height(14)
constant font_char_bytes(23)
constant font_chars(50)
constant font_horizontal_spacing(1)
constant font_vertical_spacing(2)

map 'A',0,26  // A-Z
map 'a',0,26  // a-z
map '0',26,10 // 0-9
map '!',36,3  // !-#
map 0b0'111'010,39  // '
map '*',40,6  // * to /
map ':',46
map '=',47
map '?',48
map '@',49
map ' ',50
map '\n',254

Start:
  lui a0, PIF_BASE
  lli t0, 8
  sw t0, PIF_RAM+$3C(a0)

  mtc0 r0, Status
  mtc0 r0, WatchLo
  mtc0 r0, WatchHi

// Install exception vector.
  la t0, CommonExceptionVector
  lui t1, 0x8000
  lw t2, 0(t0)
  lw t3, 4(t0)
  lw t4, 8(t0)
  lw t5, 12(t0)
  sw t2, 0x180(t1)
  sw t3, 0x184(t1)
  sw t4, 0x188(t1)
  sw t5, 0x18c(t1)
  cache data_hit_write_back, 0x180(t1)
  cache inst_hit_invalidate, 0x180(t1)

// Enable pre-NMI interrupt
  la t0, 1<<(8+2+HW_INT_PRE_NMI)|1
  mtc0 t0, Status

  ScreenNTSC(fb_width, fb_height, BPP16, fb)

  jal ClearScreen
  nop

  jal InitText
  nop

  la t0, scratchpad
  cache data_hit_invalidate, 0(t0)
  lw t2, 0(t0)
  la t1, magic
  sw r0, 0(t0)
  cache data_hit_write_back, 0(t0)
  beq t1,t2,+
  nop

  la a0, press_reset_msg
  jal PrintStr255
  nop

  jal FlushText
  nop

-;j -;nop

  la a0, ok_msg
  jal PrintStr255
  nop

+

// Print the start of what we dumped
  la s2, space_msg
  lli s1, 8
  la s0, pif_copy
-
  lw a0, 0(s0)
  jal PrintHex
  lli a1, 8
  jal PrintStr255
  move a0, s2

  lw a0, 4(s0)
  jal PrintHex
  lli a1, 8
  jal PrintStr255
  move a0, s2

  lw a0, 8(s0)
  jal PrintHex
  lli a1, 8
  jal PrintStr255
  move a0, s2

  lw a0, 12(s0)
  jal PrintHex
  lli a1, 8
  la a0, newline_msg
  jal PrintStr255
  nop

  addi s0, 16
  addi s1, -1
  bnez s1,-

  la a0, ellipsis_msg
  jal PrintStr255
  nop

// Save to SRAM
  la a0, saving_msg
  jal PrintStr255
  nop

  jal FlushText
  nop

  jal SetupSram
  nop

  la a0, pif_copy&0x7f'ffff
  jal SaveSram
  lli a1, (pif_copy_end-pif_copy)/8*8+7

// Load back from SRAM into scratchpad
  la a0, scratchpad
  move t0, a0
  la t1, scratchpad + (pif_copy_end-pif_copy)
-
  cache data_hit_invalidate, 0(t0)
  bne t0, t1,-
  addi t0, DCACHE_LINE

  la a0, scratchpad&0x7f'ffff
  jal LoadSram
  lli a1, (pif_copy_end-pif_copy)/8*8+7

// Compare
  la t0, pif_copy
  la t1, scratchpad
  la t2, pif_copy_end
-
  ld t3, 0(t0)
  ld t4, 0(t1)
  beq t3, t4,+
  addi t0, 8

  la a0, save_bad_msg
  jal PrintStr255
  nop
  jal FlushText
  nop
-;j -; nop

+
  bne t0, t2,--
  addi t1, 8

  la a0, ok_msg
  jal PrintStr255
  nop

  jal FlushText
  nop

-;j -;nop

CommonExceptionVector:
  la k0, HandleException
  jr k0
  nop

HandleException:
  mfc0 k0, Cause

  andi k1, k0, %0111'1100
  bnez k1, not_interrupt
  nop

  andi k1, k0, 1<<(8+2+HW_INT_PRE_NMI)
  beqz k1, not_pre_nmi
  nop

  la a0, pre_nmi_msg
  jal PrintStr255
  nop
  jal FlushText
  nop
// pre-NMI interrupt

// Trap IPL read from SP Status
  la k0, (((SP_BASE << 16)+SP_STATUS)&0x1fff'ffff) |2
  mtc0 k0, WatchLo
  mtc0 r0, WatchHi

  la k0, scratchpad
  sw r0, 0(k0)
  cache data_hit_write_back, 0(k0)

// Fall through to spin.
not_pre_nmi:
-;j -;nop

not_interrupt:
  lli k0, WatchExcCode<<2
  bne k0, k1, not_watch
  nop

// Watch exception, we should now have read access to PIF ROM

  mtc0 r0, WatchLo
  mtc0 r0, WatchHi

  la k0, scratchpad
  sd t0, 0(k0)
  sd t1, 8(k0)
  sd t2, 16(k0)
  sd t3, 24(k0)
  sd t4, 32(k0)
  sd t5, 40(k0)
  sd t6, 48(k0)

  la t0, (PIF_BASE<<16)+PIF_ROM
  lli t2, pif_copy_end-pif_copy
  la t3, pif_copy
-
// ROM can only be read one 32-bit word at a time
  lw t1, 0(t0)
  lw t4, 4(t0)
  lw t5, 8(t0)
  lw t6, 12(t0)

  cache data_create_dirty_exclusive, 0(t3)
  sw t1, 0(t3)
  sw t4, 4(t3)
  sw t5, 8(t3)
  sw t6, 12(t3)
  cache data_hit_write_back, 0(t3)

  addi t0, 16
  addi t2, -16
  bnez t2,-
  addi t3, 16

  ld t0, 0(k0)
  ld t1, 8(k0)
  ld t2, 16(k0)
  ld t3, 24(k0)
  ld t4, 32(k0)
  ld t5, 40(k0)
  ld t6, 48(k0)

  la k1, magic
  sw k1, 0(k0)
  cache data_hit_write_back, 0(k0)

// Proceed with boot
  eret

not_watch:
-;j -;nop

SetupSram:
// Set timing for SRAM
  lui t0,PI_BASE
  li t1, 0x5
  sw t1,PI_BSD_DOM2_LAT(t0)
  li t1, 0xc
  sw t1,PI_BSD_DOM2_PWD(t0)
  li t1, 0xd
  sw t1,PI_BSD_DOM2_PGS(t0)
  li t1, 0x2
  sw t1,PI_BSD_DOM2_RLS(t0)

  jr ra
  nop

// a0: DRAM addr
// a1: size
SaveSram:
  lui t0,PI_BASE
-
  lw t1, PI_STATUS(t0)
  andi t1, 3 // IO/DMA busy
  bnez t1,-
  nop

  sw a0, PI_DRAM_ADDR(t0)

  la t1, 0x0800'0000
  sw t1, PI_CART_ADDR(t0)

  sw a1, PI_RD_LEN(t0)

-
  lw t1, PI_STATUS(t0)
  andi t1, 3
  bnez t1,-
  nop

  jr ra
  nop

// a0: DRAM addr
// a1: size (8 byte aligned, -1)
LoadSram:
  lui t0,PI_BASE
-
  lw t1, PI_STATUS(t0)
  andi t1, 3 // IO/DMA busy
  bnez t1,-
  nop

  sw a0, PI_DRAM_ADDR(t0)

  la t1, 0x0800'0000
  sw t1, PI_CART_ADDR(t0)

  sw a1, PI_WR_LEN(t0)

-
  lw t1, PI_STATUS(t0)
  andi t1, 3
  bnez t1,-
  nop

  jr ra
  nop


ClearScreen:
  la t0, fb
  la t1, fb+(fb_width*fb_height*2+7)/8*8
-
  sd r0, 0(t0)
  bne t0, t1,-
  addi t0, 8

  jr ra
  nop

InitText:
// Load font from bootcode
//
  lui t0, PI_BASE
  la t1, font_rom&0x1fff'ffff
  sw t1, PI_CART_ADDR(t0)
  la t1, font&0x7f'ffff
  sw t1, PI_DRAM_ADDR(t0)
  la t1, (font_char_bytes*font_chars+7)/DCACHE_LINE*DCACHE_LINE-1
  sw t1, PI_WR_LEN(t0)

-
  la t2, font
  cache data_hit_invalidate, 0(t2)
  addi t1, -DCACHE_LINE
  bgtz t1,-
  addi t2, DCACHE_LINE

-
  lw t1, PI_STATUS(t0)
  andi t1, 3
  bnez t1,-
  nop
  
// Fill in a blank for ' '
  la t0, font+font_chars*font_char_bytes
  lli t1, font_char_bytes
-
  sb r0, 0(t0)
  addi t1, -1
  bnez t1,-
  addi t0,1

  la t8, text_buffer
  la t9, text_buffer_write
  sw t8, 0(t9)

  la t8, fb+((text_start_y*fb_width)+text_start_x)*2
  la t9, text_cursor
  jr ra
  sw t8, 0(t9)

// a0: pointer to 255-terminated string
PrintStr255:
  la t1, text_buffer_write
  lw t2, 0(t1)
  lli t3, 255

-
  lbu t0, 0(a0)
  beq t0, t3,+
  addi a0, 1
  sb t0, 0(t2)
  j -
  addi t2, 1
+

  jr ra
  sw t2, 0(t1)

// a0: value
// a1: length to print
scope PrintHex: {
  constant val(a0)
  constant len(a1)
  constant out(t0)
  constant dgts(t1)
  constant tmp(t2)

// seek to the end to write backwards
  la tmp, text_buffer_write
  lw out, 0(tmp)
  add out, len
  sw out, 0(tmp)
  addi out, -1

  la dgts, digits

-
  addi  len, -1
  andi  tmp, val, 0xf
  add   tmp, dgts
  lbu   tmp, 0(tmp)
  dsrl  val, 4
  sb    tmp, 0(out)
  bnez  len,-
  addi  out, -1

  jr ra
  nop
}

FlushText:
// Render chars with IPL3 font
  la a0, text_buffer
  la a1, text_cursor
  lw a1, 0(a1)
  la a2, font
  lli a3, font_char_bytes
  lli t8, 254
  la t9, text_buffer_write
  lw t9, 0(t9)

char_loop:
  beq a0, t9, char_loop_end
  lbu t0, 0 (a0)
  addi a0, 1
  mult t0, a3
  bne t0, t8,+
  mflo t1
  
  la t0, text_cursor
  lw a1, 0(t0)
  addi a1, (font_height+font_vertical_spacing)*fb_width*2
  j char_loop
  sw a1, 0(t0)
+

  addu t1, a2   // font address
  lb t2, 0(t1)  // font bits
  lli t3, 8-1   // bits left
  sll t2, 32-8
  addi t1, 1
  lli t4, font_height-1 // rows to do
-;lli t5, font_width-1 // pixels to do

-;bltz t2,+
  lli t6, 0xfffe
  lli t6, 0x0000
+;sh t6, 0(a1)
  addi a1, 2
  sll t2, 1

  bnez t3,+
  addi t3, -1
  lb t2, 0(t1)
  lli t3, 8-1
  sll t2, 32-8
  addi t1, 1
+

  bnez t5,-
  addi t5, -1

  addi a1, (fb_width-font_width)*2 // move down a (pixel) line, back one char

  bnez t4,--
  addi t4, -1

  j char_loop
  addi a1, (font_width+font_horizontal_spacing-font_height*fb_width)*2 // move up to start of next char

char_loop_end:
  la t9, text_buffer_write
  la t8, text_buffer
  sw t8, 0(t9)

  la t9, text_cursor
  jr ra
  sw a1, 0(t9)

newline_msg:
  db "\n",255
space_msg:
  db " ",255
ellipsis_msg:
  db "...\n",255
ok_msg:
  db "Ok!\n",255
saving_msg:
  db "Saving to SRAM ...\n",255
save_bad_msg:
  db "Save verify failed.\n",255
press_reset_msg:
  db "Hit Reset to dump PIF ROM\n",255
pre_nmi_msg:
  db "Pre-NMI...\n",255
digits:
  db "01234567"
  db "89ABCDEF"

align(8)
font:
  fill font_char_bytes*(font_chars+1)

align(4)
text_cursor:
  dw 0
text_buffer_write:
  dw 0
text_buffer:
