/* UEFI Application Linker Script for Project Arora
 * This script defines the memory layout for our UEFI application
 */

OUTPUT_FORMAT("elf64-x86-64", "elf64-x86-64", "elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

SECTIONS
{
    /* UEFI applications are loaded at any address chosen by the firmware */
    /* We use 0x10000000 as a base address for relative offsets */
    . = 0x10000000;

    /* .text section contains code */
    .text : ALIGN(16) {
        *(.text)
        *(.text.*)
        . = ALIGN(16);
    }

    /* .rodata section contains read-only data */
    .rodata : ALIGN(16) {
        *(.rodata)
        *(.rodata.*)
        . = ALIGN(16);
    }

    /* .data section contains initialized data */
    .data : ALIGN(16) {
        *(.data)
        *(.data.*)
        . = ALIGN(16);
    }

    /* .bss section contains uninitialized data */
    .bss : ALIGN(16) {
        *(.bss)
        *(.bss.*)
        *(COMMON)
        . = ALIGN(16);
    }

    /* Discard unnecessary sections */
    /DISCARD/ : {
        *(.note.*)
        *(.comment)
        *(.eh_frame)
    }
}
