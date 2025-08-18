; screen_gop.asm: Screen Output using UEFI GOP Framebuffer (Post-ExitBS)
; Uses CALL/RET. Strict one instruction per line.
; Depends on: boot_defs_temp.inc

BITS 64
default rel
global scr64_init, scr64_print_string, scr64_print_hex, scr64_print_dec, scr64_print_char
global gop_framebuffer_base, gop_framebuffer_size, gop_h_res, gop_v_res
global gop_pixels_per_scanline, gop_pixel_format

extern panic64
extern itoa64
extern simple_font_bitmap ; Assume 8x16 font bitmap data provided

%include "boot_defs_temp.inc"

section .data align=8
    ; GOP information - made global for access from other modules
    gop_framebuffer_base dq 0
    gop_framebuffer_size dq 0
    gop_fb_base dq 0
    gop_h_res dd 0
    gop_v_res dd 0
    gop_pixels_per_scanline dd 0
    gop_pixel_format dd PixelBlueGreenRedReserved8BitPerColor ; Default assumption
    
    ; Screen state
    cursor_x dw 0
    cursor_y dw 0
    font_height db 16
    font_width db 8
    font_fg_color dd 0x00FFFFFF ; White BGRA
    font_bg_color dd 0x00000000 ; Black BGRA
    hex_digits db "0123456789ABCDEF"
    
    ; Error messages
    msg_gop_error db "GOP Error: Invalid framebuffer parameters", 0

section .bss align=16
    dec_buffer resb 32

section .text

;--------------------------------------------------------------------------
; scr64_init: Initialize screen driver with GOP framebuffer information
; Input: RDI=FB Base, RSI=HRes, RDX=VRes, RCX=PixelsPerScanline, R8=PixelFormat
; Output: None
;--------------------------------------------------------------------------
scr64_init:
    ; Validate input parameters
    test rdi, rdi
    jz .error_invalid_params
    
    test esi, esi
    jz .error_invalid_params
    
    test edx, edx
    jz .error_invalid_params
    
    test ecx, ecx
    jz .error_invalid_params
    
    ; Store framebuffer information
    mov [gop_fb_base], rdi
    mov [gop_framebuffer_base], rdi
    
    mov [gop_h_res], esi
    
    mov [gop_v_res], edx
    
    mov [gop_pixels_per_scanline], ecx
    
    mov [gop_pixel_format], r8d
    
    ; Calculate framebuffer size (pixels_per_scanline * vres * 4)
    mov rax, rcx
    mul rdx
    shl rax, 2
    mov [gop_framebuffer_size], rax
    
    ; Initialize cursor position
    mov word [cursor_x], 0
    
    mov word [cursor_y], 0
    
    ; Success
    xor rax, rax
    ret
    
.error_invalid_params:
    ; If we can't print yet, just return error
    mov rsi, msg_gop_error
    call panic64
    mov rax, 1
    ret

;--------------------------------------------------------------------------
; putpixel: Draw a pixel at specified coordinates with specified color
; Input: ECX=x, EDX=y, R8D=color (BGRA32)
; Output: None
;--------------------------------------------------------------------------
putpixel:
    ; Save potentially clobbered registers if necessary for caller
    push rax
    push rdi
    push r10
    push r11

    ; Bounds check
    cmp ecx, [gop_h_res]
    jge .putpixel_exit
    
    cmp edx, [gop_v_res]
    jge .putpixel_exit

    ; Calculate offset: offset = (y * pixels_per_scanline + x) * 4
    mov r10d, edx
    imul r10, [gop_pixels_per_scanline]
    
    mov r11d, ecx
    add r10, r11
    
    shl r10, 2

    mov rdi, [gop_fb_base]
    add rdi, r10
    
    mov [rdi], r8d

.putpixel_exit:
    pop r11
    pop r10
    pop rdi
    pop rax
    ret

;--------------------------------------------------------------------------
; scroll_screen: Scroll the screen up by one text line
; Input: None
; Output: None
;--------------------------------------------------------------------------
scroll_screen:
    ; Save registers used
    push rsi
    push rdi
    push rcx
    push rdx
    push rax
    push r10
    push r11

    ; Calculate bytes per text line
    movzx r10, byte [font_height]
    mov r11d, [gop_pixels_per_scanline]
    imul r10, r11
    
    shl r10, 2

    ; Calculate source/destination for scroll copy
    mov rsi, [gop_fb_base]
    add rsi, r10
    
    mov rdi, [gop_fb_base]

    ; Calculate bytes to copy
    mov ecx, [gop_v_res]
    movzx edx, byte [font_height]
    sub ecx, edx
    
    imul rcx, r10

    test rcx, rcx
    jle .scroll_clear

    ; Copy lines up
    rep movsb

.scroll_clear:
    ; Calculate start address of last text line to clear
    mov rdi, [gop_fb_base]
    mov eax, [gop_v_res]
    movzx edx, byte [font_height]
    sub eax, edx
    
    imul rax, [gop_pixels_per_scanline]
    shl rax, 2
    
    add rdi, rax

    ; Clear using background color (DWORDs)
    mov rcx, r10
    shr rcx, 2
    
    mov eax, [font_bg_color]
    rep stosd

    ; Restore registers
    pop r11
    pop r10
    pop rax
    pop rdx
    pop rcx
    pop rdi
    pop rsi
    ret

;--------------------------------------------------------------------------
; scr64_putchar_at: Draw a character at specified text coordinates
; Input: AL=Char, BX=X_char_pos, CX=Y_char_pos
; Output: None
;--------------------------------------------------------------------------
scr64_putchar_at:
    ; Save ALL potentially used registers (inc. by putpixel)
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
    push r12
    push r13
    push r14
    push r15

    ; Keep original char/coords safe
    mov r14b, al
    mov r14w, bx
    mov r15w, cx

    ; Calculate pixel coordinates top-left corner
    movzx r10, byte [font_width]
    movzx r11, byte [font_height]
    
    movzx rbx, r14w
    imul rbx, r10
    
    movzx rcx, r15w
    imul rcx, r11

    ; Calculate offset in font bitmap data
    movzx rax, r14b
    imul rax, r11
    
    lea rsi, [simple_font_bitmap]
    add rsi, rax

    ; Loop through font pixels (y_font = 0 to font_height-1)
    mov r10, 0
.font_y_loop:
    cmp r10b, [font_height]
    jge .putchar_done

    mov r11, 0
    mov dl, [rsi + r10]

.font_x_loop:
    cmp r11b, [font_width]
    jge .font_next_row

    ; Calculate screen coordinates for this pixel
    mov r12d, ebx
    add r12b, r11b
    
    mov r13d, ecx
    add r13b, r10b

    ; Create mask and test font bit
    mov al, 1
    mov r9b, 7
    sub r9b, r11b
    
    push rcx
    mov cl, r9b
    shl al, cl
    pop rcx
    
    test dl, al
    jz .pixel_off

; Pixel on:
    mov r8d, [font_fg_color]
    mov ecx, r12d
    mov edx, r13d
    
    call putpixel
    jmp .pixel_next

.pixel_off:
    mov r8d, [font_bg_color]
    mov ecx, r12d
    mov edx, r13d
    
    call putpixel

.pixel_next:
    inc r11
    jmp .font_x_loop

.font_next_row:
    inc r10
    jmp .font_y_loop

.putchar_done:
    ; Restore registers
    pop r15
    pop r14
    pop r13
    pop r12
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

;--------------------------------------------------------------------------
; scr64_print_char: Print a character at current cursor position
; Input: AL = Character
; Output: None
;--------------------------------------------------------------------------
scr64_print_char:
    push rax
    push rbx
    push rcx
    push rdx
    push r10

    cmp al, 10
    je .newline

    cmp al, 8
    je .backspace

    ; --- Normal character ---
    mov bl, [cursor_x]
    mov cl, [cursor_y]
    
    call scr64_putchar_at

    ; --- Advance cursor ---
    mov bx, [cursor_x]
    inc bx
    
    ; Max chars per line = HRes / font_width
    mov ax, [gop_h_res]
    xor dx, dx
    
    movzx cx, byte [font_width]
    div cx
    
    cmp bx, ax
    jl .update_cursor_x

    ; --- Wrap cursor ---
.newline_logic:
    xor bx, bx
    mov cx, [cursor_y]
    inc cx
    
    ; Max text rows = VRes / font_height
    mov ax, [gop_v_res]
    xor dx, dx
    
    movzx r10w, byte [font_height]
    div r10w
    
    cmp cx, ax
    jl .set_cursor_y
    
    ; Scroll
    dec cx
    call scroll_screen
    
.set_cursor_y:
    mov [cursor_y], cx
    
.update_cursor_x:
    mov [cursor_x], bx
    jmp .print_char_done

.newline:
    jmp .newline_logic

.backspace:
    mov bx, [cursor_x]
    test bx, bx
    jz .print_char_done
    
    dec bx
    mov [cursor_x], bx
    
    ; Erase character at new cursor position
    mov cx, [cursor_y]
    mov al, ' '
    
    call scr64_putchar_at
    jmp .print_char_done

.print_char_done:
    pop r10
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

;--------------------------------------------------------------------------
; scr64_print_string: Print a null-terminated string at current cursor position
; Input: RSI = string pointer
; Output: None
;--------------------------------------------------------------------------
scr64_print_string:
    push rsi
    push rax
    
.loop:
    mov al, [rsi]
    test al, al
    jz .done
    
    call scr64_print_char
    inc rsi
    
    jmp .loop
    
.done:
    pop rax
    pop rsi
    ret

;--------------------------------------------------------------------------
; scr64_print_hex: Print a hexadecimal value
; Input: RSI = value
; Output: None
;--------------------------------------------------------------------------
scr64_print_hex:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi

    mov rbx, rsi
    mov rcx, 16
    
    lea rsi, [hex_digits]
    
.hex_loop:
    dec rcx
    
    ; Extract nibble using SHR
    mov rax, rbx
    push rcx
    
    mov cl, 4
    mul cl
    
    mov cl, 60
    sub cl, al
    
    pop rcx
    shr rax, cl
    
    and al, 0x0F
    mov dl, [rsi + rax]
    
    ; Print character DL
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    
    mov al, dl
    call scr64_print_char
    
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax

    test rcx, rcx
    jnz .hex_loop
    
.hex_done:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

;--------------------------------------------------------------------------
; scr64_print_dec: Print a decimal value
; Input: RAX = value
; Output: None
;--------------------------------------------------------------------------
scr64_print_dec:
    push rdi
    push rsi
    push rax

    lea rdi, [dec_buffer]
    call itoa64
    
    mov rsi, rdi
    call scr64_print_string

    pop rax
    pop rsi
    pop rdi
    ret
