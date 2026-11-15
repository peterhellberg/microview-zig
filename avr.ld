/* Layout for the ATmega328P: 32 KiB of flash from 0, 2 KiB of RAM from 0x100
   (the AVR address space puts registers and I/O below it). .data is copied
   from flash by _start, so its load address differs from where it runs. */

OUTPUT_FORMAT("elf32-avr")
ENTRY(_start)

MEMORY
{
  flash (rx)  : ORIGIN = 0x000000, LENGTH = 0x8000
  ram   (rwx) : ORIGIN = 0x800100, LENGTH = 0x0800
}

SECTIONS
{
  .text : {
    *(.text.start)
    *(.text*)
    *(.rodata*)
  } > flash

  .data : {
    __data_start = .;
    *(.data*)
    __data_end = .;
  } > ram AT > flash

  __data_load = LOADADDR(.data);
  __stack = ORIGIN(ram) + LENGTH(ram) - 1;

  .bss (NOLOAD) : {
    __bss_start = .;
    *(.bss*)
    *(COMMON)
    __bss_end = .;
  } > ram
}
