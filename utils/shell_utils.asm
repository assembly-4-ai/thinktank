; shell_utils.asm: Shell utility functions
; Project Arora - Bare-Metal NASM AI Implementation

section .text
    global shell_print_newline
    global shell_register_command

shell_print_newline:
    ; Prints a newline character to the console
    ; TODO: Implement actual console output
    ret

shell_register_command:
    ; Registers a command with the shell
    ; TODO: Implement actual command registration
    ret




section .data
    global sh_eol
sh_eol db 0Dh, 0Ah, 0


