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
