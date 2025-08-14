ENTRY(_start)

SECTIONS
{
    . = 0x0000000000000000;

    .text : ALIGN(0x1000)
    {
        _kernel_start = .;
        *(.text)
    }

    .rodata : ALIGN(0x1000)
    {
        *(.rodata)
    }

    .data : ALIGN(0x1000)
    {
        *(.data)
    }

    .bss : ALIGN(0x1000)
    {
        *(.bss)
        _kernel_end = .;
    }

    /DISCARD/ :
    {
        *(.note*)
        *(.iplt)
        *(.igot.plt)
        *(.eh_frame)
        *(.fini)
        *(.interp)
        *(.dynamic)
        *(.dynsym)
        *(.dynstr)
        *(.hash)
        *(.gnu.version)
        *(.gnu.version_d)
        *(.gnu.version_r)
        *(.comment)
        *(.debug*)
        *(.stab*)
        *(.rel*)
        *(.rela*)
    }
}


