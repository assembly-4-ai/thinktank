; pic_pic.asm: PIC-compliant Programmable Interrupt Controller functions
; Provides PIC remapping and control functions in a position-independent way

BITS 64
default rel

; Exports
global pic_remap, pic_send_eoi, pic_mask_irq, pic_unmask_irq

; External dependencies
extern scr64_print_string

%include "boot_defs_temp.inc"

; PIC constants (in case they're not in boot_defs_temp.inc)
%define ICW1_INIT 0x10
%define ICW1_ICW4 0x01
%define ICW4_8086 0x01

section .rodata
    ; Messages
    msg_pic_remap db "Remapping PIC...", 0
    msg_pic_remap_ok db "PIC remapped successfully", 0

section .text

;--------------------------------------------------------------------------
; io_wait: Short delay for PIC I/O operations
; Input: None
; Output: None
;--------------------------------------------------------------------------
io_wait:
    push rax
    push rdx
    
    mov al, 0
    out 0x80, al
    
    pop rdx
    pop rax
    ret

;--------------------------------------------------------------------------
; pic_remap: Remap PIC IRQs to avoid conflicts with CPU exceptions
; Input: None
; Output: None
;--------------------------------------------------------------------------
pic_remap:
    push rbp
    mov rbp, rsp
    push rax
    push rcx
    push rdx
    push rsi
    
    ; Print remapping message
    lea rsi, [rel msg_pic_remap]
    call scr64_print_string
    
    ; Save masks
    in al, PIC1_DATA
    mov cl, al
    in al, PIC2_DATA
    mov ch, al
    
    ; ICW1: Start initialization sequence in cascade mode
    mov al, ICW1_INIT | ICW1_ICW4
    out PIC1_COMMAND, al
    call io_wait
    out PIC2_COMMAND, al
    call io_wait
    
    ; ICW2: Set vector offsets
    mov al, PIC1_IRQ_START
    out PIC1_DATA, al
    call io_wait
    mov al, PIC2_IRQ_START
    out PIC2_DATA, al
    call io_wait
    
    ; ICW3: Tell Master PIC that there is a slave at IRQ2
    mov al, 4    ; Bit mask: 00000100, meaning IRQ2
    out PIC1_DATA, al
    call io_wait
    
    ; ICW3: Tell Slave PIC its cascade identity
    mov al, 2    ; Slave ID is 2
    out PIC2_DATA, al
    call io_wait
    
    ; ICW4: Set 8086 mode
    mov al, ICW4_8086
    out PIC1_DATA, al
    call io_wait
    out PIC2_DATA, al
    call io_wait
    
    ; Restore masks
    mov al, cl
    out PIC1_DATA, al
    mov al, ch
    out PIC2_DATA, al
    
    ; Print success message
    lea rsi, [rel msg_pic_remap_ok]
    call scr64_print_string
    
    pop rsi
    pop rdx
    pop rcx
    pop rax
    pop rbp
    ret

;--------------------------------------------------------------------------
; pic_send_eoi: Send End-Of-Interrupt signal to PIC
; Input: AL = IRQ number (0-15)
; Output: None
;--------------------------------------------------------------------------
pic_send_eoi:
    push rbp
    mov rbp, rsp
    push rax
    push rdx
    
    cmp al, 8
    jb .master_eoi
    
    ; Send EOI to slave PIC
    mov al, PIC_EOI
    out PIC2_COMMAND, al
    
.master_eoi:
    ; Send EOI to master PIC
    mov al, PIC_EOI
    out PIC1_COMMAND, al
    
    pop rdx
    pop rax
    pop rbp
    ret

;--------------------------------------------------------------------------
; pic_mask_irq: Mask (disable) a specific IRQ line
; Input: AL = IRQ number (0-15)
; Output: None
;--------------------------------------------------------------------------
pic_mask_irq:
    push rbp
    mov rbp, rsp
    push rax
    push rdx
    push rcx
    
    cmp al, 8
    jb .master_mask
    
    ; Mask slave PIC IRQ
    mov dl, al
    sub dl, 8
    mov cl, dl
    mov al, 1
    shl al, cl
    mov ah, al
    
    mov dx, PIC2_DATA
    in al, dx
    or al, ah
    out dx, al
    jmp .done
    
.master_mask:
    ; Mask master PIC IRQ
    mov dl, al
    mov cl, dl
    mov al, 1
    shl al, cl
    mov ah, al
    
    mov dx, PIC1_DATA
    in al, dx
    or al, ah
    out dx, al
    
.done:
    pop rcx
    pop rdx
    pop rax
    pop rbp
    ret

;--------------------------------------------------------------------------
; pic_unmask_irq: Unmask (enable) a specific IRQ line
; Input: AL = IRQ number (0-15)
; Output: None
;--------------------------------------------------------------------------
pic_unmask_irq:
    push rbp
    mov rbp, rsp
    push rax
    push rdx
    push rcx
    
    cmp al, 8
    jb .master_unmask
    
    ; Unmask slave PIC IRQ
    mov dl, al
    sub dl, 8
    mov cl, dl
    mov al, 1
    shl al, cl
    not al
    mov ah, al
    
    mov dx, PIC2_DATA
    in al, dx
    and al, ah
    out dx, al
    jmp .done
    
.master_unmask:
    ; Unmask master PIC IRQ
    mov dl, al
    mov cl, dl
    mov al, 1
    shl al, cl
    not al
    mov ah, al
    
    mov dx, PIC1_DATA
    in al, dx
    and al, ah
    out dx, al
    
.done:
    pop rcx
    pop rdx
    pop rax
    pop rbp
    ret
