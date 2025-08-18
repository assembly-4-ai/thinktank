; keyboard_pic.asm: Interrupt-driven PS/2 Keyboard Handler (64-bit)
; PIC-compliant version that avoids global variables in .bss/.data sections
; Depends on: boot_defs_temp.inc

BITS 64
default rel

; Exports
global keyboard_init, keyboard_process_scancode, getchar_from_buffer
global init_keyboard_runtime_data

; External dependencies
extern pmm_alloc_frame, pmm_free_frame
extern scr64_print_string, scr64_print_hex

%include "boot_defs_temp.inc"

; Structure of runtime keyboard data block:
; Offset 0:  keyboard_runtime_data_ptr (qword)
; Offset 8:  kb_lshift_pressed (byte)
; Offset 9:  kb_rshift_pressed (byte)
; Offset 10: kb_capslock_on (byte)
; Offset 11: padding (5 bytes)
; Offset 16: key_buffer (KEY_BUFFER_SIZE bytes)
; Offset 272: key_buffer_head (word)
; Offset 274: key_buffer_tail (word)
; Offset 276: scan_code_table (SCAN_CODE_TABLE_SIZE * 2 bytes)
; Offset 532: shifted_scan_code_table (SHIFTED_SCAN_CODE_TABLE_SIZE * 2 bytes)
; Total size: 788 bytes

%define KEYBOARD_RUNTIME_DATA_SIZE 788
%define OFFSET_KEYBOARD_RUNTIME_PTR 0
%define OFFSET_KB_LSHIFT_PRESSED 8
%define OFFSET_KB_RSHIFT_PRESSED 9
%define OFFSET_KB_CAPSLOCK_ON 10
%define OFFSET_KEY_BUFFER 16
%define OFFSET_KEY_BUFFER_HEAD 272
%define OFFSET_KEY_BUFFER_TAIL 274
%define OFFSET_SCAN_CODE_TABLE 276
%define OFFSET_SHIFTED_SCAN_CODE_TABLE 532

%define SCAN_CODE_TABLE_SIZE 89
%define SHIFTED_SCAN_CODE_TABLE_SIZE 89

section .data
    ; Single global pointer to runtime allocated data
    keyboard_runtime_data_ptr dq 0
    
    ; Error messages
    msg_keyboard_init db "Initializing keyboard...", 0
    msg_keyboard_error db "Keyboard initialization error", 0

section .text

;--------------------------------------------------------------------------
; init_keyboard_runtime_data: Allocate and initialize keyboard runtime data
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
init_keyboard_runtime_data:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    push r12
    push r13
    push r14
    push r15
    
    ; Check if already initialized
    mov rax, [rel keyboard_runtime_data_ptr]
    test rax, rax
    jnz .already_initialized
    
    ; Allocate memory for keyboard runtime data
    mov rdi, (KEYBOARD_RUNTIME_DATA_SIZE + 4095) / 4096  ; Pages needed
    call pmm_alloc_frame
    test rax, rax
    jz .allocation_error
    
    ; Save pointer to allocated memory
    mov [rel keyboard_runtime_data_ptr], rax
    mov r15, rax  ; Save pointer in R15 for initialization
    
    ; Store self-reference at offset 0
    mov [r15 + OFFSET_KEYBOARD_RUNTIME_PTR], r15
    
    ; Initialize keyboard state
    mov byte [r15 + OFFSET_KB_LSHIFT_PRESSED], 0
    mov byte [r15 + OFFSET_KB_RSHIFT_PRESSED], 0
    mov byte [r15 + OFFSET_KB_CAPSLOCK_ON], 0
    
    ; Initialize key buffer
    mov word [r15 + OFFSET_KEY_BUFFER_HEAD], 0
    mov word [r15 + OFFSET_KEY_BUFFER_TAIL], 0
    
    ; Initialize scan code tables
    lea rdi, [r15 + OFFSET_SCAN_CODE_TABLE]
    call init_scan_code_tables
    
    ; Success
    xor rax, rax
    jmp .done
    
.already_initialized:
    ; Already initialized, return success
    xor rax, rax
    jmp .done
    
.allocation_error:
    ; Failed to allocate memory
    mov rsi, msg_keyboard_error
    call scr64_print_string
    mov rax, 1
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; init_scan_code_tables: Initialize scan code tables in runtime data
; Input: RDI = Pointer to scan code table area in runtime data
; Output: None
;--------------------------------------------------------------------------
init_scan_code_tables:
    push rbp
    mov rbp, rsp
    push rax
    push rcx
    push rsi
    push rdi
    
    ; Initialize normal scan code table
    ; First row: 0x00-0x0F (NULL,ESC,1-0,-,=,BS,TAB)
    mov word [rdi + 0*2], 0
    mov word [rdi + 1*2], 27
    mov word [rdi + 2*2], '1'
    mov word [rdi + 3*2], '2'
    mov word [rdi + 4*2], '3'
    mov word [rdi + 5*2], '4'
    mov word [rdi + 6*2], '5'
    mov word [rdi + 7*2], '6'
    mov word [rdi + 8*2], '7'
    mov word [rdi + 9*2], '8'
    mov word [rdi + 10*2], '9'
    mov word [rdi + 11*2], '0'
    mov word [rdi + 12*2], '-'
    mov word [rdi + 13*2], '='
    mov word [rdi + 14*2], 8
    mov word [rdi + 15*2], 9
    
    ; Second row: 0x10-0x1F (Q-P,[,],Enter,LCtrl,A,S)
    mov word [rdi + 16*2], 'q'
    mov word [rdi + 17*2], 'w'
    mov word [rdi + 18*2], 'e'
    mov word [rdi + 19*2], 'r'
    mov word [rdi + 20*2], 't'
    mov word [rdi + 21*2], 'y'
    mov word [rdi + 22*2], 'u'
    mov word [rdi + 23*2], 'i'
    mov word [rdi + 24*2], 'o'
    mov word [rdi + 25*2], 'p'
    mov word [rdi + 26*2], '['
    mov word [rdi + 27*2], ']'
    mov word [rdi + 28*2], 13
    mov word [rdi + 29*2], 0
    mov word [rdi + 30*2], 'a'
    mov word [rdi + 31*2], 's'
    
    ; Third row: 0x20-0x2F (D-L,;,',`,LShift,\,Z-V)
    mov word [rdi + 32*2], 'd'
    mov word [rdi + 33*2], 'f'
    mov word [rdi + 34*2], 'g'
    mov word [rdi + 35*2], 'h'
    mov word [rdi + 36*2], 'j'
    mov word [rdi + 37*2], 'k'
    mov word [rdi + 38*2], 'l'
    mov word [rdi + 39*2], ';'
    mov word [rdi + 40*2], "'"
    mov word [rdi + 41*2], '`'
    mov word [rdi + 42*2], 0
    mov word [rdi + 43*2], '\'
    mov word [rdi + 44*2], 'z'
    mov word [rdi + 45*2], 'x'
    mov word [rdi + 46*2], 'c'
    mov word [rdi + 47*2], 'v'
    
    ; Fourth row: 0x30-0x3F (B-M,,,.,/,RShift,KP*,LAlt,Space,Caps,F1-F6)
    mov word [rdi + 48*2], 'b'
    mov word [rdi + 49*2], 'n'
    mov word [rdi + 50*2], 'm'
    mov word [rdi + 51*2], ','
    mov word [rdi + 52*2], '.'
    mov word [rdi + 53*2], '/'
    mov word [rdi + 54*2], 0
    mov word [rdi + 55*2], 0
    mov word [rdi + 56*2], 0
    mov word [rdi + 57*2], ' '
    mov word [rdi + 58*2], 0
    mov word [rdi + 59*2], 0
    mov word [rdi + 60*2], 0
    mov word [rdi + 61*2], 0
    mov word [rdi + 62*2], 0
    mov word [rdi + 63*2], 0
    
    ; Fifth row: 0x40-0x4F (F7-F12 placeholders, others...)
    mov rcx, 16
    lea rdi, [rdi + 64*2]
    xor rax, rax
    rep stosw
    
    ; Sixth row: 0x50-0x58 (Kp2,3,0,. placeholders)
    mov rcx, 9
    xor rax, rax
    rep stosw
    
    ; Now initialize shifted scan code table
    ; First row: 0x00-0x0F
    mov word [rdi + 0*2], 0
    mov word [rdi + 1*2], 27
    mov word [rdi + 2*2], '!'
    mov word [rdi + 3*2], '@'
    mov word [rdi + 4*2], '#'
    mov word [rdi + 5*2], '$'
    mov word [rdi + 6*2], '%'
    mov word [rdi + 7*2], '^'
    mov word [rdi + 8*2], '&'
    mov word [rdi + 9*2], '*'
    mov word [rdi + 10*2], '('
    mov word [rdi + 11*2], ')'
    mov word [rdi + 12*2], '_'
    mov word [rdi + 13*2], '+'
    mov word [rdi + 14*2], 8
    mov word [rdi + 15*2], 9
    
    ; Second row: 0x10-0x1F
    mov word [rdi + 16*2], 'Q'
    mov word [rdi + 17*2], 'W'
    mov word [rdi + 18*2], 'E'
    mov word [rdi + 19*2], 'R'
    mov word [rdi + 20*2], 'T'
    mov word [rdi + 21*2], 'Y'
    mov word [rdi + 22*2], 'U'
    mov word [rdi + 23*2], 'I'
    mov word [rdi + 24*2], 'O'
    mov word [rdi + 25*2], 'P'
    mov word [rdi + 26*2], '{'
    mov word [rdi + 27*2], '}'
    mov word [rdi + 28*2], 13
    mov word [rdi + 29*2], 0
    mov word [rdi + 30*2], 'A'
    mov word [rdi + 31*2], 'S'
    
    ; Third row: 0x20-0x2F
    mov word [rdi + 32*2], 'D'
    mov word [rdi + 33*2], 'F'
    mov word [rdi + 34*2], 'G'
    mov word [rdi + 35*2], 'H'
    mov word [rdi + 36*2], 'J'
    mov word [rdi + 37*2], 'K'
    mov word [rdi + 38*2], 'L'
    mov word [rdi + 39*2], ':'
    mov word [rdi + 40*2], '"'
    mov word [rdi + 41*2], '~'
    mov word [rdi + 42*2], 0
    mov word [rdi + 43*2], '|'
    mov word [rdi + 44*2], 'Z'
    mov word [rdi + 45*2], 'X'
    mov word [rdi + 46*2], 'C'
    mov word [rdi + 47*2], 'V'
    
    ; Fourth row: 0x30-0x3F
    mov word [rdi + 48*2], 'B'
    mov word [rdi + 49*2], 'N'
    mov word [rdi + 50*2], 'M'
    mov word [rdi + 51*2], '<'
    mov word [rdi + 52*2], '>'
    mov word [rdi + 53*2], '?'
    mov word [rdi + 54*2], 0
    mov word [rdi + 55*2], 0
    mov word [rdi + 56*2], 0
    mov word [rdi + 57*2], ' '
    mov word [rdi + 58*2], 0
    mov word [rdi + 59*2], 0
    mov word [rdi + 60*2], 0
    mov word [rdi + 61*2], 0
    mov word [rdi + 62*2], 0
    mov word [rdi + 63*2], 0
    
    ; Fifth row: 0x40-0x4F
    mov rcx, 16
    lea rdi, [rdi + 64*2]
    xor rax, rax
    rep stosw
    
    ; Sixth row: 0x50-0x58
    mov rcx, 9
    xor rax, rax
    rep stosw
    
    pop rdi
    pop rsi
    pop rcx
    pop rax
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_keyboard_runtime_data: Get pointer to keyboard runtime data
; Input: None
; Output: RAX = Pointer to keyboard runtime data, 0 if not initialized
;--------------------------------------------------------------------------
get_keyboard_runtime_data:
    mov rax, [rel keyboard_runtime_data_ptr]
    ret

;--------------------------------------------------------------------------
; keyboard_init: Initialize keyboard state flags
;--------------------------------------------------------------------------
keyboard_init:
    push rbp
    mov rbp, rsp
    push rsi
    
    ; Print initialization message
    mov rsi, msg_keyboard_init
    call scr64_print_string
    
    ; Initialize keyboard runtime data
    call init_keyboard_runtime_data
    
    pop rsi
    pop rbp
    ret

;--------------------------------------------------------------------------
; keyboard_process_scancode: Process a keyboard scancode
; Input: RDI = Scancode
; Output: None
;--------------------------------------------------------------------------
keyboard_process_scancode:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r15
    
    ; Get keyboard runtime data pointer
    call get_keyboard_runtime_data
    mov r15, rax  ; Save pointer in R15
    test r15, r15
    jz .done      ; Not initialized, nothing to do
    
    mov cl, dil   ; Use CL for scancode processing
    
    test cl, 0x80 ; Test high bit (key release)
    jnz .key_release
    
.key_press:
    cmp cl, SC_LSHIFT_MAKE  ; Check for modifier presses
    je .lshift_press
    cmp cl, SC_RSHIFT_MAKE
    je .rshift_press
    cmp cl, SC_CAPSLOCK_MAKE
    je .capslock_toggle
    
    ; --- Key Press - Translate Scancode ---
    movzx rsi, cl           ; RSI = scancode index (zero-extended)
    cmp rsi, SCAN_CODE_TABLE_SIZE ; Bounds check
    jae .ignore_key         ; If index too high, ignore
    
    ; Determine if shift is active
    mov r8b, 0              ; R8B = shift_active flag
    cmp byte [r15 + OFFSET_KB_LSHIFT_PRESSED], 1
    je .shift_is_active
    cmp byte [r15 + OFFSET_KB_RSHIFT_PRESSED], 1
    je .shift_is_active
    jmp .get_base_char      ; No shift pressed
    
.shift_is_active:
    mov r8b, 1              ; Set shift_active flag
    
.get_base_char:
    lea rdx, [r15 + OFFSET_SCAN_CODE_TABLE]
    mov ax, [rdx + rsi*2]   ; Get base character (or 0)
    mov dl, al              ; Save base char in DL for caps logic
    
    ; Apply Caps Lock only to 'a'-'z'
    cmp al, 'a'; jl .apply_shift
    cmp al, 'z'; jg .apply_shift
    ; Is Alpha char
    test r8b, 1             ; Shift pressed?
    jnz .alpha_shift_pressed
    ; Shift NOT pressed
    cmp byte [r15 + OFFSET_KB_CAPSLOCK_ON], 1 ; Caps Lock ON?
    jne .use_base_char      ; No, use lowercase base char (already in AX)
    lea rdx, [r15 + OFFSET_SHIFTED_SCAN_CODE_TABLE]
    mov ax, [rdx + rsi*2]   ; Yes, use uppercase char
    jmp .char_translated
.alpha_shift_pressed:
    ; Shift IS pressed
    cmp byte [r15 + OFFSET_KB_CAPSLOCK_ON], 1 ; Caps Lock ON?
    jne .use_shifted_char   ; No, use standard shifted char (uppercase)
    movzx ax, dl            ; Yes, use inverted caps (lowercase, saved in DL)
    jmp .char_translated
    
.apply_shift:               ; Not an alpha char, apply normal shift
    test r8b, 1             ; Shift pressed?
    jz .use_base_char       ; No, use base char
    
.use_shifted_char:          ; Get shifted char
    lea rdx, [r15 + OFFSET_SHIFTED_SCAN_CODE_TABLE]
    mov ax, [rdx + rsi*2]
    jmp .char_translated
    
.use_base_char:
    ; AX already contains base char from first lookup
    ; Fall through
    
.char_translated:
    or ax, ax               ; Check if valid char (not 0 from table)
    jz .ignore_key          ; Ignore if 0
    
    ; --- Add character to buffer ---
    movzx rdi, word [r15 + OFFSET_KEY_BUFFER_HEAD] ; Current head index
    movzx rcx, word [r15 + OFFSET_KEY_BUFFER_TAIL] ; Current tail index
    
    mov rbx, rdi            ; Save head index before incrementing
    inc di                  ; Increment head index
    cmp di, KEY_BUFFER_SIZE ; Wrap around buffer size?
    jne .no_wrap
    xor di, di              ; Wrap to 0
.no_wrap:
    cmp di, cx              ; Check if head caught up to tail (buffer full)
    je .buffer_full
    
    ; Buffer not full, store character (AL) and update head
    lea rdx, [r15 + OFFSET_KEY_BUFFER]
    mov [rdx + rbx], al     ; Store char at old head position
    mov [r15 + OFFSET_KEY_BUFFER_HEAD], di ; Update head pointer
    jmp .done               ; Done processing scancode
    
.buffer_full:
    ; Optional: Signal buffer full error? For now, just ignore key.
    jmp .ignore_key
    
.key_release:
    and cl, 0x7F            ; Mask off the release bit (high bit)
    cmp cl, SC_LSHIFT_MAKE
    je .lshift_release
    cmp cl, SC_RSHIFT_MAKE
    je .rshift_release
    ; Ignore other key releases
    jmp .ignore_key
    
.lshift_press: 
    mov byte [r15 + OFFSET_KB_LSHIFT_PRESSED], 1
    jmp .ignore_key
    
.lshift_release: 
    mov byte [r15 + OFFSET_KB_LSHIFT_PRESSED], 0
    jmp .ignore_key
    
.rshift_press: 
    mov byte [r15 + OFFSET_KB_RSHIFT_PRESSED], 1
    jmp .ignore_key
    
.rshift_release: 
    mov byte [r15 + OFFSET_KB_RSHIFT_PRESSED], 0
    jmp .ignore_key
    
.capslock_toggle: 
    mov al, [r15 + OFFSET_KB_CAPSLOCK_ON]
    xor al, 1
    mov [r15 + OFFSET_KB_CAPSLOCK_ON], al
    jmp .ignore_key
    
.ignore_key:
    ; Key was ignored (modifier, release, unknown, or buffer full)
    
.done:
    pop r15
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; getchar_from_buffer: Reads next character from keyboard buffer.
; Output: AL = Character, or 0 if buffer is empty.
;--------------------------------------------------------------------------
getchar_from_buffer:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push r15
    
    ; Get keyboard runtime data pointer
    call get_keyboard_runtime_data
    mov r15, rax  ; Save pointer in R15
    test r15, r15
    jz .empty     ; Not initialized, return empty
    
    movzx rbx, word [r15 + OFFSET_KEY_BUFFER_TAIL] ; Get current tail index
    movzx rcx, word [r15 + OFFSET_KEY_BUFFER_HEAD] ; Get current head index
    cmp bx, cx    ; Is tail == head?
    je .empty     ; Yes, buffer is empty
    
    ; Buffer not empty, read character and advance tail
    lea rdx, [r15 + OFFSET_KEY_BUFFER]
    mov al, [rdx + rbx]     ; Read char from buffer
    inc bx                  ; Increment tail index
    cmp bx, KEY_BUFFER_SIZE ; Wrap around buffer size?
    jne .tail_no_wrap
    xor bx, bx              ; Wrap to 0
.tail_no_wrap:
    mov [r15 + OFFSET_KEY_BUFFER_TAIL], bx ; Update tail pointer
    jmp .done
    
.empty:
    ; Return 0 for empty buffer
    xor al, al
    
.done:
    pop r15
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret
