#!/bin/bash
set -e

# Create uefi.lds
cat > uefi.lds << EOL
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
EOL

# Create core/screen_gop.asm
cat > core/screen_gop.asm << EOL
; screen_gop.asm: Screen Output using UEFI GOP Framebuffer (Post-ExitBS)
; Depends on: boot_defs_temp.inc

BITS 64
default rel

global scr64_init, scr64_print_string, scr64_print_hex, scr64_print_dec, scr64_print_char
global gop_framebuffer_base, gop_framebuffer_size, gop_h_res, gop_v_res
global gop_pixels_per_scanline, gop_pixel_format
global putpixel, scr64_putchar_at

extern panic64
extern itoa64
extern simple_font_bitmap

%include "boot_defs_temp.inc"

section .data
    gop_framebuffer_base dq 0
    gop_framebuffer_size dq 0
    gop_fb_base dq 0
    gop_h_res dd 0
    gop_v_res dd 0
    gop_pixels_per_scanline dd 0
    gop_pixel_format dd PixelBlueGreenRedReserved8BitPerColor
    cursor_x dw 0
    cursor_y dw 0
    font_height db 16
    font_width db 8
    font_fg_color dd 0x00FFFFFF
    font_bg_color dd 0x00000000
    hex_digits db "0123456789ABCDEF"
    msg_gop_error db "GOP Error: Invalid framebuffer parameters", 0

section .bss
    dec_buffer resb 21

section .text

scr64_init:
    mov [gop_fb_base], rdi
    mov [gop_framebuffer_base], rdi
    mov [gop_h_res], esi
    mov [gop_v_res], edx
    mov [gop_pixels_per_scanline], ecx
    mov [gop_pixel_format], r8d
    mov rax, rdx
    imul rax, rcx
    shl rax, 2
    mov [gop_framebuffer_size], rax
    ret

putpixel:
    cmp ecx, [gop_h_res]
    jge .putpixel_exit
    cmp edx, [gop_v_res]
    jge .putpixel_exit
    mov r10d, [gop_pixels_per_scanline]
    imul r10d, edx
    add r10d, ecx
    shl r10, 2
    mov rdi, [gop_fb_base]
    add rdi, r10
    mov [rdi], r8d
.putpixel_exit:
    ret

scr64_putchar_at:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    mov r10, rdi
    mov r11, rsi
    mov r12, rdx
    imul r11, [font_width]
    imul r12, [font_height]
    movzx rax, r10b
    imul rax, 16
    lea rbx, [simple_font_bitmap + rax]
    mov r8, 0
.font_y_loop:
    cmp r8, 16
    jge .putchar_done
    mov r9, 0
    mov al, [rbx + r8]
.font_x_loop:
    cmp r9, 8
    jge .font_next_row
    mov r10, r9
    shl al, 1
    jnc .pixel_off
    mov ecx, r11d
    add ecx, r9d
    mov edx, r12d
    add edx, r8d
    mov r8d, [font_fg_color]
    call putpixel
    jmp .pixel_next
.pixel_off:
    mov ecx, r11d
    add ecx, r9d
    mov edx, r12d
    add edx, r8d
    mov r8d, [font_bg_color]
    call putpixel
.pixel_next:
    inc r9
    jmp .font_x_loop
.font_next_row:
    inc r8
    jmp .font_y_loop
.putchar_done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

scr64_print_char:
    cmp al, 0x0A
    je .newline
    cmp al, 0x08
    je .backspace
    movzx rdi, al
    mov rsi, [cursor_x]
    mov rdx, [cursor_y]
    call scr64_putchar_at
    inc word [cursor_x]
    mov ax, [gop_h_res]
    shr ax, 3
    cmp [cursor_x], ax
    jl .print_char_done
.newline:
    mov word [cursor_x], 0
    inc word [cursor_y]
    mov ax, [gop_v_res]
    shr ax, 4
    cmp [cursor_y], ax
    jl .print_char_done
    dec word [cursor_y]
    jmp .print_char_done
.backspace:
    cmp word [cursor_x], 0
    jle .print_char_done
    dec word [cursor_x]
    mov rdi, ' '
    mov rsi, [cursor_x]
    mov rdx, [cursor_y]
    call scr64_putchar_at
.print_char_done:
    ret

scr64_print_string:
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    call scr64_print_char
    inc rsi
    jmp .loop
.done:
    ret

scr64_print_hex:
    mov rdi, dec_buffer + 19
    mov byte [rdi + 1], 0
    mov rcx, 16
.hex_loop:
    mov rdx, rax
    and rdx, 0x0F
    mov dl, [hex_digits + rdx]
    mov [rdi], dl
    dec rdi
    shr rax, 4
    loop .hex_loop
    inc rdi
    mov rsi, rdi
    call scr64_print_string
    ret

scr64_print_dec:
    mov rdi, dec_buffer + 19
    mov byte [rdi + 1], 0
    mov rbx, 10
    test rax, rax
    jnz .not_zero
    mov byte [rdi], '0'
    dec rdi
    jmp .loop_end
.not_zero:
.loop:
    xor rdx, rdx
    div rbx
    add dl, '0'
    mov [rdi], dl
    dec rdi
    test rax, rax
    jnz .loop
.loop_end:
    inc rdi
    mov rsi, rdi
    call scr64_print_string
    ret
EOL

# Create demo/demo.asm
cat > demo/demo.asm << EOL
; demo.asm: "Parallax" Demo
; By Jules

BITS 64
default rel

section .data
    msg_demo db "Parallax Demo!", 0Dh, 0Ah, 0
    NUM_STARS equ 256
    STAR_SIZE equ 6
    stars:
        times NUM_STARS db 0, 0, 0, 0, 0, 0

section .text
global parallax_main

extern scr64_print_string
extern putpixel
extern gop_h_res, gop_v_res
extern scr64_putchar_at

parallax_main:
    push rbp
    mov rbp, rsp

    call _init_stars

.loop:
    call _draw_stars
    jmp .loop

    pop rbp
    ret

_init_stars:
    mov rdi, stars
    mov rcx, NUM_STARS
.loop:
    call rand
    movsx rdx, ax
    mov [rdi], dx
    call rand
    movsx rdx, ax
    mov [rdi + 2], dx
    call rand
    mov [rdi + 4], ax
    add rdi, STAR_SIZE
    dec rcx
    jnz .loop
    ret

section .data
seed:
    dw 0x1234
section .text

rand:
    mov ax, [seed]
    mov cx, ax
    shl ax, 1
    adc ax, 0
    shl ax, 1
    adc ax, 0
    shl ax, 1
    adc ax, 0
    shl ax, 1
    adc ax, 0
    xor ax, cx
    mov [seed], ax
    ret

_draw_stars:
    mov rdi, stars
    mov rcx, NUM_STARS
.loop:
    movsx rax, word [rdi]
    mov rdx, 1024
    imul rax, rdx
    movsx rdx, word [rdi + 4]
    add rdx, 1024
    cqo
    idiv rdx
    mov r10, [gop_h_res]
    shr r10, 1
    add rax, r10
    mov r8, rax

    movsx rax, word [rdi + 2]
    mov rdx, 1024
    imul rax, rdx
    movsx rdx, word [rdi + 4]
    add rdx, 1024
    cqo
    idiv rdx
    mov r10, [gop_v_res]
    shr r10, 1
    add rax, r10
    mov r9, rax

    mov ecx, r8d
    mov edx, r9d
    mov r8d, 0x00FFFFFF
    call putpixel

    mov ax, [rdi + 4]
    sub ax, 16
    cmp ax, -1024
    jg .z_ok
    mov ax, 1024
.z_ok:
    mov [rdi + 4], ax

    add rdi, STAR_SIZE
    dec rcx
    jnz .loop
    ret
EOL

# Create shell/shell.asm
cat > shell/shell.asm << EOL
;**File 14: `shell.asm`**

;```assembly
; shell.asm: Command Shell (Post-ExitBootServices)
; Depends on: boot_defs_temp.inc, screen_gop.asm, keyboard.asm,
;             fat32.asm, pmm64_uefi.asm, compute libraries

BITS 64
default rel
global shell_run
; Required Externals
extern fat32_read_file ; From fat32.asm
extern pmm_alloc_large_frame, pmm_free_large_frame ; From pmm64_uefi.asm
extern scr64_print_string, scr64_print_hex, scr64_print_dec, scr64_print_char ; From screen_gop.asm
extern getchar_from_buffer ; From keyboard.asm (or wrapper calling it)
extern panic64 ; From payload/panic module
; Compute function externals (to be linked)
extern ggml_matmul, llama_model_load, parallel_run_model, gpu_matmul, init_compute_lib
; Potentially needed helpers
extern memcpy64, memset64, strcmp64, itoa64 ; Assumed utilities
extern parallax_main

%include "boot_defs_temp.inc"

section .data align=64
sh_prompt       db "> ", 0 ; Shortened prompt
sh_eol          db 0Dh, 0Ah, 0
cmd_help        db "help", 0
cmd_exit        db "exit", 0
cmd_matmul      db "matmul", 0 ; Usage: matmul <size_mb>
cmd_loadmodel   db "loadmodel", 0 ; Usage: loadmodel <size_mb> <filename>
cmd_runmodel    db "runmodel", 0 ; Usage: runmodel <filename> (loads then runs)
cmd_cls         db "cls", 0 ; Example: Clear screen
cmd_parallax    db "parallax", 0
msg_help        db "Commands: help, exit, cls, matmul, loadmodel, runmodel, parallax", 0Dh, 0Ah, 0
msg_unknown_cmd db "Unknown command", 0Dh, 0Ah, 0
msg_matmul_start db "Starting Matmul...", 0Dh, 0Ah, 0
msg_matmul_done db "Matmul Done!", 0Dh, 0Ah, 0
msg_alloc_fail  db "Allocation Failed!", 0Dh, 0Ah, 0
msg_parse_fail  db "Parse Error!", 0Dh, 0Ah, 0
msg_load_fail   db "Load Failed: ", 0
msg_loading_model db "Loading Model: ", 0
msg_model_size  db " Size (MB): ", 0
msg_model_loaded db " Model Loaded!", 0Dh, 0Ah, 0
msg_running_model db "Running Model: ", 0
msg_run_fail    db "Run Failed!", 0Dh, 0Ah, 0
msg_compute_init_error db "Error initializing compute library", 0Dh, 0Ah, 0

; Simple argument storage
MAX_ARGS equ 8
argv dq 0, 0, 0, 0, 0, 0, 0, 0 ; Array of pointers to tokens
argc dq 0 ; Argument count

section .bss align=16
sh_input_buffer resb 256
sh_token_buffer resb 256 ; Buffer to hold token pointers and null terminators

section .text

;--------------------------------------------------------------------------
; strcmp64_simple: Simple string compare for commands
; Input: RDI = string1 (null terminated), RSI = string2 (null terminated)
; Output: ZF=1 if equal, ZF=0 if not equal
; Destroys: AL, BL, RDI, RSI
;--------------------------------------------------------------------------
strcmp64_simple:
.loop:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .noteq
    test al, al ; Check for null terminator
    jz .eq ; Both ended at the same time
    inc rdi
    inc rsi
    jmp .loop
.noteq:
    cmp al, bl ; Set ZF=0
    ret
.eq:
    ; ZF is already set
    ret

;--------------------------------------------------------------------------
; parse_uint64: Converts ASCII decimal string to 64-bit unsigned integer
; Input: RSI = Pointer to string
; Output: RAX = Resulting integer, RDX = Pointer after last digit parsed.
;         Carry set if invalid char found or overflow (overflow not checked here).
; Destroys: RAX, RCX, RDX
;--------------------------------------------------------------------------
parse_uint64:
    xor rax, rax ; Result
    mov rdx, rsi ; Keep track of position
    mov rcx, 10 ; Base
.parse_loop:
    movzx r8, byte [rdx] ; Get char
    test r8b, r8b
    jz .done_ok ; End of string

    cmp r8b, '0'
    jb .fail
    cmp r8b, '9'
    ja .fail

    ; Valid digit
    sub r8b, '0' ; Convert char to integer value
    ; Check for overflow before multiplying? For simplicity, skip now.
    imul rax, rax, 10 ; result *= 10 (Use IMUL for potential neg later?)
    add rax, r8 ; result += digit
    inc rdx ; Next char
    jmp .parse_loop

.fail:
    stc ; Set carry on error
    ret
.done_ok:
    clc ; Clear carry on success
    ret

;--------------------------------------------------------------------------
; read_input: Reads a line from keyboard into buffer using getchar
; Input: RDI = buffer, RCX = max size
; Output: RAX = length read (excluding null)
;--------------------------------------------------------------------------
read_input:
    push rbx; push rcx; push rdi
    xor rbx, rbx ; Current buffer index/length
.read_loop:
    call getchar_from_buffer ; Get char (blocking) -> AL
    cmp al, 0x0D ; Enter key?
    je .input_done
    cmp al, 0x08 ; Backspace?
    je .backspace

    ; Normal character
    cmp rbx, rcx ; Check buffer overflow (leave space for null)
    jge .read_loop ; Buffer full, ignore char

    mov [rdi + rbx], al ; Store char
    inc rbx
    ; Echo character
    push rax; call scr64_print_char; pop rax
    jmp .read_loop

.backspace:
    test rbx, rbx
    jz .read_loop ; Nothing to backspace
    dec rbx
    ; Echo backspace, space, backspace
    mov al, 8; call scr64_print_char
    mov al, ' '; call scr64_print_char
    mov al, 8; call scr64_print_char
    jmp .read_loop

.input_done:
    mov byte [rdi + rbx], 0 ; Null terminate
    mov rax, rbx ; Return length
    ; Print newline
    push rax; mov al, 10; call scr64_print_char; pop rax
    pop rdi; pop rcx; pop rbx
    ret

;--------------------------------------------------------------------------
; tokenize: Splits input string into space-separated tokens
; Input: RSI = Input string, RDI = argv buffer (array of pointers)
;        RCX = Max Args
; Output: RAX = argc, RDI contains argv pointers
; Destroys: RDX, R8, R9, R10
; Modifies input string by inserting null terminators!
;--------------------------------------------------------------------------
tokenize:
    mov r8, rdi ; Save start of argv buffer
    mov r9, 0 ; Current arg count (argc)
    mov r10, rcx ; Save max args

.skip_leading_whitespace:
    mov dl, [rsi]
    test dl, dl ; End of string?
    jz .tokenize_done
    cmp dl, ' ' ; Space?
    je .found_space
    cmp dl, 9 ; Tab?
    je .found_space
    ; Found start of a token
    jmp .start_token
.found_space:
    inc rsi
    jmp .skip_leading_whitespace

.start_token:
    cmp r9, r10 ; Check max args
    jge .tokenize_done ; Too many args

    mov [rdi], rsi ; Store pointer to start of token in argv
    add rdi, 8 ; Next argv slot
    inc r9 ; Increment argc

.scan_token:
    mov dl, [rsi]
    test dl, dl
    jz .tokenize_done ; End of string is end of token
    cmp dl, ' '
    je .end_token
    cmp dl, 9
    je .end_token
    ; Character is part of token
    inc rsi
    jmp .scan_token

.end_token:
    mov byte [rsi], 0 ; Null terminate the token in the input string
    inc rsi
    jmp .skip_leading_whitespace ; Look for next token

.tokenize_done:

    mov [rdi], byte 0 ; Null terminate argv array
    mov rax, r9 ; Return argc
    mov rdi, r8 ; Return original argv buffer start
    ret

;--------------------------------------------------------------------------
; shell_run: Main shell loop
;--------------------------------------------------------------------------
shell_run:
    push rbx; push r12; push r13; push r14; push r15

    ; Initialize compute library
    call init_compute_lib
    test rax, rax
    jnz .compute_init_error

    call parallax_main

.prompt_loop:
    ; Print prompt
    mov rsi, sh_prompt
    call scr64_print_string

    ; Read input
    lea rdi, [sh_input_buffer]
    mov rcx, 255 ; Max chars for input buffer
    call read_input
    test rax, rax ; Check if any input was read
    jz .prompt_loop ; Empty line, just re-prompt

    ; Tokenize input
    lea rdi, [argv] ; Destination argv array
    lea rsi, [sh_input_buffer] ; Source input string
    mov rcx, MAX_ARGS
    call tokenize
    mov [argc], rax ; Store argc

    ; Process command if argc > 0
    cmp rax, 0
    jle .prompt_loop ; No command entered

    ; Get first token (command)
    mov rbx, [argv] ;    RBX = argv[0] (command string)

    ; --- Command Dispatch ---
    mov rdi, rbx;
    lea rsi, [cmd_help];
    call strcmp64_simple;
    jz .cmd_help_handler
    mov rdi, rbx;
    lea rsi, [cmd_exit];
    call strcmp64_simple;
    jz .cmd_exit_handler
    mov rdi, rbx;
    lea rsi, [cmd_matmul];
    call strcmp64_simple;
    jz .cmd_matmul_handler
    mov rdi, rbx;
    lea rsi, [cmd_loadmodel];
    call strcmp64_simple;
    jz .cmd_loadmodel_handler
    mov rdi, rbx;
    lea rsi, [cmd_runmodel];
    call strcmp64_simple;
    jz .cmd_runmodel_handler
    mov rdi, rbx;
    lea rsi, [cmd_cls];
    call strcmp64_simple;
    jz .cmd_cls_handler
    mov rdi, rbx;
    lea rsi, [cmd_parallax];
    call strcmp64_simple;
    jz .cmd_parallax_handler

    ; Unknown command
    mov rsi, msg_unknown_cmd
    call scr64_print_string
    jmp .prompt_loop

.cmd_help_handler:
    mov rsi, msg_help
    call scr64_print_string
    jmp .prompt_loop

.cmd_exit_handler:
    jmp .shell_exit

.cmd_cls_handler:
    ; TODO: Implement screen clear using scr64 functions
    jmp .prompt_loop

.cmd_parallax_handler:
    call parallax_main
    jmp .prompt_loop

.cmd_matmul_handler:
    cmp qword [argc], 2 ; Check for "matmul <size>"
    jne .parse_fail_shell
    mov rsi, [argv+8] ; Argv[1] = size string
    call parse_uint64
    jc .parse_fail_shell ; Carry set means invalid number
    ; RAX = size in MB
    ; Allocate buffers (Example: A=size, B=size, C=size)
    mov r12, rax ; R12 = size_mb
    shl r12, 20 ; size_bytes
    mov rcx, -1;
    call pmm_alloc_large_frame;
    mov r13, rax ; Alloc A
    mov rcx, -1;
    call pmm_alloc_large_frame;
    mov r14, rax ; Alloc B
    mov rcx, -1;
    call pmm_alloc_large_frame;
    mov r15, rax ; Alloc C
    test r13, r13;
    jz .alloc_fail_matmul
    test r14, r14;
    jz .alloc_fail_matmul
    test r15, r15;
    jz .alloc_fail_matmul
    ; Buffers allocated
    mov rsi, msg_matmul_start;
    call scr64_print_string
    ; --- Call ggml_matmul ---
    mov rdi, r13;
    mov rsi, r14;
    mov rdx, r15 ; Args: A, B, C buffers
    mov rcx, r12;
    shr rcx, 2 ; Size in elements? Assuming 4-byte floats? Adjust as needed.
    ;Need to disable interrupts around compute?
    cli
    call ggml_matmul
    sti
    ; --- Compute Done ---
    mov rsi, msg_matmul_done;
    call scr64_print_string
    ; Free buffers
    mov rdi, r15;
    mov rcx, -1;
    call pmm_free_large_frame
    mov rdi, r14;
    mov rcx, -1;
    call pmm_free_large_frame
    mov rdi, r13;
    mov rcx, -1;
    call pmm_free_large_frame
    jmp .prompt_loop
.alloc_fail_matmul:
    ; Free any successfully allocated buffers before failing
    test r15, r15;
    jz .check_b_fail;
    mov rdi, r15;
    mov rcx, -1;
    call pmm_free_large_frame
.check_b_fail:
    test r14, r14;
    jz .check_a_fail;
    mov rdi, r14;
    mov rcx, -1;
    call pmm_free_large_frame
.check_a_fail:
    test r13, r13;
    jz .alloc_msg_done;
    mov rdi, r13;
    mov rcx, -1;
    call pmm_free_large_frame
.alloc_msg_done:
    mov rsi, msg_alloc_fail; call scr64_print_string
    jmp .prompt_loop


.cmd_loadmodel_handler:
    cmp qword [argc], 3 ; Check for "loadmodel <size_mb> <filename>"
    jne .parse_fail_shell
    ; Parse size
    mov rsi, [argv+8] ; Argv[1] = size string
    call parse_uint64
    jc .parse_fail_shell
    test rax, rax
    jz .parse_fail_shell ; Size cannot be 0
    mov r12, rax ; R12 = size_mb
    shl r12, 20 ; R12 = size_bytes
    ; Get filename
    mov rdi, [argv+16] ; Argv[2] = filename

    ; Print messages
    mov rsi, msg_loading_model;
    call scr64_print_string
    mov rsi, rdi;
    call scr64_print_string ; Print filename
    mov rsi, msg_model_size;
    call scr64_print_string
    mov rax, r12;
    shr rax, 20;
    call scr64_print_dec ; Print size_mb
    mov rsi, sh_eol;
    call scr64_print_string

    ; Allocate buffer for model
    mov rcx, -1; call pmm_alloc_large_frame ; Request pages based on size_bytes (pmm_alloc_large_frame needs size/pages ?)
    ; *** NOTE: pmm_alloc_large_frame needs modification to take size/pages ***
    ; For now, assume it allocates one large frame - THIS IS LIKELY WRONG
    test rax, rax
    jz .alloc_fail_shell
    mov rsi, rax ; RSI = buffer physical address

    ; Read file into buffer
    ; RDI=Filename, RSI=Buffer, RDX=Size, R8B=Drive(needs setting?)
    mov rdx, r12 ; Bytes to read
    ; Need boot drive number? mov r8b, [gBootDriveNum]
    call fat32_read_file
    jnc .load_ok
    ; Read failed
    mov r14, rax ; Save error code
    mov rdi, rsi ; Buffer to free
    mov rcx, -1;
    call pmm_free_large_frame
    mov rsi, msg_load_fail;
    call scr64_print_string
    mov rax, r14;
    call scr64_print_hex ; Print FAT error code
    mov rsi, sh_eol;
    call scr64_print_string
    jmp .prompt_loop
.load_ok:
    ; RAX contains bytes read, compare with expected size?
    mov rsi, msg_model_loaded; call scr64_print_string
    ; --- Call llama_model_load ---
    ; Assuming it takes buffer pointer and size
    mov rdi, rsi ; Buffer address
    mov rsi, r12 ; Size in bytes
    call llama_model_load
    ; llama_model_load might take ownership or copy, free buffer? Depends on its API.
    ; If llama_model_load doesn't copy, DON'T free the buffer here.
    mov rdi, [rsp+8];
    mov rcx, -1;
    call pmm_free_large_frame ; Free if copied
    jmp .prompt_loop

.cmd_runmodel_handler:
    ; Similar to loadmodel, but then calls parallel_run_model or similar
    ; Needs implementation
    ;mov rsi, todo runmodel needs inplementation
    ;call scr64_print_string
    mov rsi, sh_eol;
    call scr64_print_string
    jmp .prompt_loop


.parse_fail_shell:
    mov rsi, msg_parse_fail
    call scr64_print_string
    jmp .prompt_loop
.compute_init_error:
    mov rsi, msg_compute_init_error
    call scr64_print_string
    jmp .shell_exit

.alloc_fail_shell:
    mov rsi, msg_alloc_fail
    call scr64_print_string
    jmp .prompt_loop


.shell_exit:
    ; Maybe print a message before halting?
    pop r15;
    pop r14;
    pop r13;
    pop r12;
    pop rbx
    ret ; Return to caller (main_uefi_loader)
EOL
