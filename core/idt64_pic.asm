; idt64_pic.asm: IDT Setup for Exceptions (post-UEFI)
; Fully PIC-compliant version that avoids absolute addressing in .text section
; Depends on: boot_defs_temp.inc

BITS 64
default rel
global setup_final_idt64_exceptions
global setup_final_idt64
global load_idt64
global init_idt64_runtime_data
global get_idt64_pointer

extern panic64           ; For common ISR handler
extern pmm_alloc_frame, pmm_free_frame

%include "boot_defs_temp.inc" ; Needs CODE64_SEL

struc Idt64Entry
    .OffsetLow      resw 1
    .Selector       resw 1
    .IST            resb 1  ; Interrupt Stack Table index
    .TypeAttr       resb 1
    .OffsetMid      resw 1
    .OffsetHigh     resd 1
    .Reserved       resd 1
endstruc
Idt64Entry_size equ 16

; Gate Types for IDT Entry's TypeAttr field
%define IDT_TYPE_INT_GATE   0x8E ; Interrupt Gate, P=1, DPL=0, Type=0xE
%define IDT_TYPE_TRAP_GATE  0x8F ; Trap Gate, P=1, DPL=0, Type=0xF

; Structure of runtime IDT data block:
; Offset 0:  idt64_runtime_data_ptr (qword)
; Offset 8:  idt64_pointer (10 bytes)
; Offset 18: padding (6 bytes)
; Offset 24: isr_attrs (32 bytes)
; Offset 56: isr_ist (32 bytes)
; Total size: 88 bytes

%define IDT64_RUNTIME_DATA_SIZE 88
%define OFFSET_IDT64_RUNTIME_PTR 0
%define OFFSET_IDT64_POINTER 8
%define OFFSET_ISR_ATTRS 24
%define OFFSET_ISR_IST 56

section .data
    ; Single global pointer to runtime allocated data
    idt64_runtime_data_ptr dq 0

section .text

;--------------------------------------------------------------------------
; init_idt64_runtime_data: Allocate and initialize IDT64 runtime data
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
init_idt64_runtime_data:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Check if already initialized
    mov rax, [rel idt64_runtime_data_ptr]
    test rax, rax
    jnz .already_initialized
    
    ; Allocate memory for IDT64 runtime data
    mov rdi, (IDT64_RUNTIME_DATA_SIZE + 4095) / 4096  ; Pages needed
    call pmm_alloc_frame
    test rax, rax
    jz .allocation_error
    
    ; Save pointer to allocated memory
    mov [rel idt64_runtime_data_ptr], rax
    mov rdi, rax
    
    ; Store self-reference at offset 0
    mov [rdi + OFFSET_IDT64_RUNTIME_PTR], rax
    
    ; Initialize IDT pointer
    mov word [rdi + OFFSET_IDT64_POINTER], 0      ; Limit (set at runtime)
    mov qword [rdi + OFFSET_IDT64_POINTER + 2], 0 ; Base (set at runtime)
    
    ; Initialize ISR attributes
    lea rsi, [rdi + OFFSET_ISR_ATTRS]
    
    ; Attributes for first 20 exceptions
    ; Use Trap Gate for Debug, Breakpoint; Interrupt Gate otherwise
    mov byte [rsi + 0], IDT_TYPE_INT_GATE
    mov byte [rsi + 1], IDT_TYPE_TRAP_GATE
    mov byte [rsi + 2], IDT_TYPE_INT_GATE
    mov byte [rsi + 3], IDT_TYPE_TRAP_GATE
    mov byte [rsi + 4], IDT_TYPE_TRAP_GATE
    mov byte [rsi + 5], IDT_TYPE_INT_GATE
    mov byte [rsi + 6], IDT_TYPE_INT_GATE
    mov byte [rsi + 7], IDT_TYPE_INT_GATE
    mov byte [rsi + 8], IDT_TYPE_INT_GATE
    mov byte [rsi + 9], IDT_TYPE_INT_GATE
    mov byte [rsi + 10], IDT_TYPE_INT_GATE
    mov byte [rsi + 11], IDT_TYPE_INT_GATE
    mov byte [rsi + 12], IDT_TYPE_INT_GATE
    mov byte [rsi + 13], IDT_TYPE_INT_GATE
    mov byte [rsi + 14], IDT_TYPE_INT_GATE
    mov byte [rsi + 15], IDT_TYPE_INT_GATE
    mov byte [rsi + 16], IDT_TYPE_INT_GATE
    mov byte [rsi + 17], IDT_TYPE_INT_GATE
    mov byte [rsi + 18], IDT_TYPE_INT_GATE
    mov byte [rsi + 19], IDT_TYPE_INT_GATE
    
    ; Initialize ISR IST indices
    lea rsi, [rdi + OFFSET_ISR_IST]
    
    ; IST indices for first 20 exceptions
    ; Use IST 1 for NMI (2) and DF (8), IST 0 for others
    mov byte [rsi + 0], 0
    mov byte [rsi + 1], 0
    mov byte [rsi + 2], 1 ; NMI uses IST 1
    mov byte [rsi + 3], 0
    mov byte [rsi + 4], 0
    mov byte [rsi + 5], 0
    mov byte [rsi + 6], 0
    mov byte [rsi + 7], 0
    mov byte [rsi + 8], 1 ; Double Fault uses IST 1
    mov byte [rsi + 9], 0
    mov byte [rsi + 10], 0
    mov byte [rsi + 11], 0
    mov byte [rsi + 12], 0
    mov byte [rsi + 13], 0
    mov byte [rsi + 14], 0
    mov byte [rsi + 15], 0
    mov byte [rsi + 16], 0
    mov byte [rsi + 17], 0
    mov byte [rsi + 18], 0
    mov byte [rsi + 19], 0
    
    ; Success
    xor rax, rax
    jmp .done
    
.already_initialized:
    ; Already initialized, return success
    xor rax, rax
    jmp .done
    
.allocation_error:
    ; Failed to allocate memory
    mov rax, 1
    
.done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_idt64_runtime_data: Get pointer to IDT64 runtime data
; Input: None
; Output: RAX = Pointer to IDT64 runtime data, 0 if not initialized
;--------------------------------------------------------------------------
get_idt64_runtime_data:
    mov rax, [rel idt64_runtime_data_ptr]
    ret

;--------------------------------------------------------------------------
; get_idt64_pointer: Get pointer to IDT64 pointer variable
; Input: None
; Output: RAX = Pointer to IDT64 pointer variable
;--------------------------------------------------------------------------
get_idt64_pointer:
    push rbp
    mov rbp, rsp
    
    ; Get IDT64 runtime data pointer
    call get_idt64_runtime_data
    test rax, rax
    jz .not_initialized
    
    ; Return pointer to IDT64 pointer
    add rax, OFFSET_IDT64_POINTER
    jmp .done
    
.not_initialized:
    ; Return 0 if not initialized
    xor rax, rax
    
.done:
    pop rbp
    ret

;--------------------------------------------------------------------------
; setup_final_idt64_exceptions: Sets up IDT entries for ISRs 0-31.
; Input:
;   RDI = Physical address of allocated memory for IDT (IDT_MAX_ENTRIES * 16 bytes)
; Output: None, IDT written at [RDI], idt64_pointer updated
; Destroys: RAX, RBX, RCX, RDX, RDI, RSI
;--------------------------------------------------------------------------
setup_final_idt64_exceptions:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Initialize IDT64 runtime data if not already done
    call init_idt64_runtime_data
    test rax, rax
    jnz .setup_error
    
    ; Get IDT64 runtime data pointer
    call get_idt64_runtime_data
    mov r15, rax  ; Save pointer in R15
    
    push rdi ; Save IDT base address

    ; Zero the entire IDT table first
    mov rcx, IDT_MAX_ENTRIES * Idt64Entry_size
    xor al, al
    rep stosb ; Simple zeroing

    pop rdi ; Restore IDT base address
    mov rsi, rdi ; RSI = Current IDT entry pointer

    ; Setup exceptions 0-31 using dynamic dispatch
    xor rcx, rcx ; ISR number / table index
.isr_loop:
    cmp rcx, 32 ; Only setup first 32 exceptions
    jae .isr_loop_done

    ; Get ISR handler address based on vector number
    ; We'll use a computed jump to get the right handler
    mov rax, rcx
    call get_isr_handler_address
    
    ; Determine attributes and IST (use defaults if beyond specific tables)
    cmp rcx, 20
    jae .use_generic_attr
    
    ; Get attributes and IST from runtime data
    lea r12, [r15 + OFFSET_ISR_ATTRS]
    lea r13, [r15 + OFFSET_ISR_IST]
    mov bl, [r12 + rcx] ; TypeAttr
    mov dl, [r13 + rcx] ; IST index
    jmp .set_entry
    
.use_generic_attr:
    mov bl, IDT_TYPE_INT_GATE ; Default attribute
    xor dl, dl                ; Default IST (0)

.set_entry:
    ; Deconstruct handler address (RAX) and write to entry (pointed by RSI)
    mov word [rsi + Idt64Entry.OffsetLow], ax
    mov word [rsi + Idt64Entry.Selector], CODE64_SEL
    mov byte [rsi + Idt64Entry.IST], dl          ; IST index
    mov byte [rsi + Idt64Entry.TypeAttr], bl     ; Type and attributes
    shr rax, 16
    mov word [rsi + Idt64Entry.OffsetMid], ax
    shr rax, 16
    mov dword [rsi + Idt64Entry.OffsetHigh], eax
    mov dword [rsi + Idt64Entry.Reserved], 0     ; Reserved field must be 0

    add rsi, Idt64Entry_size ; Move to next IDT entry
    inc rcx
    jmp .isr_loop
.isr_loop_done:

    ; Update IDTR variable in runtime data
    mov rax, rdi ; IDT Base address
    mov word [r15 + OFFSET_IDT64_POINTER], (IDT_MAX_ENTRIES * Idt64Entry_size - 1) ; Limit
    mov [r15 + OFFSET_IDT64_POINTER + 2], rax ; Base

    xor rax, rax ; Return success
    jmp .setup_done
    
.setup_error:
    ; Return error code
    mov rax, 1
    
.setup_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_isr_handler_address: Get the address of an ISR handler based on vector
; Input: RAX = Vector number (0-31)
; Output: RAX = Address of ISR handler
; Uses PC-relative addressing to avoid absolute references
;--------------------------------------------------------------------------
get_isr_handler_address:
    ; Use a jump table approach with PC-relative addressing
    push rbx
    push rcx
    push rdx
    
    ; Bounds check
    cmp rax, 31
    ja .use_generic
    
    ; Compute jump offset into the table
    mov rbx, rax
    mov rcx, 8  ; Each entry is 8 bytes (address size)
    mul rcx
    
    ; Get address of jump table (PC-relative)
    lea rdx, [rel .isr_jump_table]
    add rdx, rax
    
    ; Get handler address from table
    mov rax, [rdx]
    jmp .done
    
.use_generic:
    ; Use generic handler for vectors > 31
    lea rax, [rel isr_generic_stub]
    
.done:
    pop rdx
    pop rcx
    pop rbx
    ret

; Jump table with ISR handler addresses
; This is a PC-relative table that doesn't require absolute addressing
.isr_jump_table:
    dq isr0_stub, isr1_stub, isr2_stub, isr3_stub, isr4_stub
    dq isr5_stub, isr6_stub, isr7_stub, isr8_stub, isr9_stub
    dq isr10_stub, isr11_stub, isr12_stub, isr13_stub, isr14_stub
    dq isr15_stub, isr16_stub, isr17_stub, isr18_stub, isr19_stub
    dq isr_generic_stub, isr_generic_stub, isr_generic_stub, isr_generic_stub
    dq isr_generic_stub, isr_generic_stub, isr_generic_stub, isr_generic_stub
    dq isr_generic_stub, isr_generic_stub, isr_generic_stub, isr_generic_stub

;--------------------------------------------------------------------------
; load_idt64: Loads the IDT using LIDT instruction
; Input: None
; Output: None
;--------------------------------------------------------------------------
load_idt64:
    push rbp
    mov rbp, rsp
    
    ; Get IDT64 pointer
    call get_idt64_pointer
    test rax, rax
    jz .not_initialized
    
    ; Load IDT
    lidt [rax]
    
.not_initialized:
    pop rbp
    ret

;--------------------------------------------------------------------------
; setup_final_idt64: Wrapper for setup_final_idt64_exceptions
; Input:
;   RDI = Physical address of allocated memory for IDT (IDT_MAX_ENTRIES * 16 bytes)
; Output: None
;--------------------------------------------------------------------------
setup_final_idt64:
    ; Just call setup_final_idt64_exceptions
    jmp setup_final_idt64_exceptions

; --- ISR Stubs (push ISR number, push error code if applicable) ---
; Error codes pushed by CPU for: 8, 10, 11, 12, 13, 14, 17, 21, 29, 30
%macro ISR_STUB 2-3 0 ; Params: ISR_Num, PushErrorCode (0 or 1), ErrorCodeValue (optional)
isr%1_stub:
    %if %2 == 0
        push qword %3 ; Push dummy error code (or specific value)
    %endif
    push %1 ; Push ISR number
    jmp common_isr_handler
%endmacro

ISR_STUB 0, 0 ; Divide Error
ISR_STUB 1, 0 ; Debug
ISR_STUB 2, 0 ; NMI
ISR_STUB 3, 0 ; Breakpoint
ISR_STUB 4, 0 ; Overflow
ISR_STUB 5, 0 ; Bound Range Exceeded
ISR_STUB 6, 0 ; Invalid Opcode
ISR_STUB 7, 0 ; Device Not Available
ISR_STUB 8, 1 ; Double Fault (Pushes Error Code)
ISR_STUB 9, 0 ; Coprocessor Segment Overrun
ISR_STUB 10, 1 ; Invalid TSS (Pushes Error Code)
ISR_STUB 11, 1 ; Segment Not Present (Pushes Error Code)
ISR_STUB 12, 1 ; Stack-Segment Fault (Pushes Error Code)
ISR_STUB 13, 1 ; General Protection Fault (Pushes Error Code)
ISR_STUB 14, 1 ; Page Fault (Pushes Error Code)
ISR_STUB 15, 0, -1 ; Reserved, push -1 as dummy code
ISR_STUB 16, 0 ; x87 Floating-Point Exception
ISR_STUB 17, 1 ; Alignment Check (Pushes Error Code)
ISR_STUB 18, 0 ; Machine Check
ISR_STUB 19, 0 ; SIMD Floating-Point Exception
; ISRs 20-31 are Reserved or used for virtualization/security

; Generic stub for other vectors (pushes vector number)
isr_generic_stub:
    ; We get here for vectors 20-31 if they occur
    push 0 ; Dummy error code
    push -1 ; Placeholder vector number
    jmp common_isr_handler

;--------------------------------------------------------------------------
; common_isr_handler: Common handler for CPU exceptions
; Stack state on entry seen by C: struct InterruptFrame* frame;
; Stack state on assembly entry:
;   [RSP+16] ISR Number
;   [RSP+8]  Error Code (or dummy)
;   [RSP]    Return RIP (pushed by CPU interrupt)
;   [RSP-8]  Return CS
;   [RSP-16] Return RFLAGS
;   [RSP-24] Return RSP
;   [RSP-32] Return SS
;--------------------------------------------------------------------------
common_isr_handler:
    ; Save all general purpose registers
    push r15; push r14; push r13; push r12
    push r11; push r10; push r9;  push r8
    push rbp; push rdi; push rsi
    push rdx; push rcx; push rbx; push rax

    ; Pass ISR number (now at RSP + 15*8 + 16) and error code (RSP + 15*8 + 8) to panic
    mov rdi, [rsp + 15*8 + 16] ; ISR Number
    mov rsi, [rsp + 15*8 + 8]  ; Error Code
    ; Optional: Pass stack frame pointer (RSP before pushes)
    ; mov rdx, rsp
    ; add rdx, 15*8 + 24 ; Calculate original RSP where RIP was pushed
    ; Call panic64(isr_num, error_code)
    call panic64 ; panic64 needs to work post-ExitBS and print RDI/RSI

    ; Halt after panic - panic64 should not return
.halt_isr:
    cli
    hlt
    jmp .halt_isr
