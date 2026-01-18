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
