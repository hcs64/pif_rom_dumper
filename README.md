# pif_rom_dumper

This will dump the PIF ROM to SRAM, where it can be easily read.

To use:

1. Load and run the `pif_rom_dumper.n64` ROM on a flashcart / backup device / ROM emulator. See below notes for Everdrive 64 and 64drive.
2. When the onscreen instructions appear, press the console's Reset button. It should briefly say "Pre-NMI" and then reset.
3. A message should say "Saving to SRAM..." and "Ok!". You can now turn off the N64.
4. Extract the first 0x7c0 bytes from the SRAM save, this is the PIF ROM.

## Notes for Everdrive

Locate the `save_db.txt` file in the `ED64` directory on your SD card. Add this line to the CRC detection section:

```
0x5716C25D=3 (pif_rom_dumper)
```

When you successfully run the dumper, a save file called `pif_rom_dumper.srm` will be created in the `ED64\Saves` directory.

## Notes for 64drive

I prefer to use the command line tool to send the ROM over USB, set the save type to 256K SRAM, and then read back the SRAM directly.

If you instead want to run pif_rom_dumper off of a SD or CF card, follow these instructions:

1. Check the 64drive options menu, "Reset button action" must be set to "Game".
2. Select `pif_rom_dumper.n64` from the menu. Before you press Load, first set "Force Save" to 256K.

(I'm not 100% sure this will work, I haven't been able to test it.)

When you successfully run the dumper, a save file called `pif_rom_dumper.sra` will be created. Depending on your settings this may be alongside the `pif_rom_dumper.n64` ROM or in a subdirectory called `Saves`.

## Troubleshooting

If you see "Save verify failed." then SRAM was not configured correctly, see the documentation for your device.
