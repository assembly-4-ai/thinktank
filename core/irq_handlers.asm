; irq_handlers.asm - IRQ Stubs & Handler Registration for APIC
; Implements robust IRQ handling for keyboard, AHCI, and timer

BITS 64
default rel

; External dependencies
extern panic64, scr64_print_string, scr64_print_hex
extern keyboard_process_scancode
extern ahci_interrupt_handler
extern acpi_lapic_base, acpi_ioapic_base
extern ahci_irq_handler  ; Changed from global to extern to avoid multiple definition

; Exports
global setup_irq_handlers
global register_irq_handler
global irq_dispatch_table
global keyboard_irq_handler, timer_irq_handler
global irq_keyboard_stub, irq_ahci_stub, irq_timer_stub

section .data
    ; IRQ handler dispatch table (64 entries for potential IRQs)
    irq_dispatch_table times 64 dq 0
    
    ; IRQ numbers for devices
    KEYBOARD_IRQ equ 1
    AHCI_IRQ equ 14
    TIMER_IRQ equ 0
    
    ; APIC register offsets
    LAPIC_ID                equ 0x20
    LAPIC_EOI               equ 0xB0
    LAPIC_SPURIOUS          equ 0xF0
    LAPIC_ICR_LOW           equ 0x300
    LAPIC_ICR_HIGH          equ 0x310
    LAPIC_LVT_TIMER         equ 0x320
    LAPIC_TIMER_INIT_COUNT  equ 0x380
    LAPIC_TIMER_CURRENT     equ 0x390
    LAPIC_TIMER_DIVIDE      equ 0x3E0
    
    IOAPIC_IOREGSEL         equ 0x00
    IOAPIC_IOWIN            equ 0x10
    IOAPIC_REDTBL           equ 0x10
    
    ; Error messages
    msg_irq_setup db "Setting up IRQ handlers...", 0
    msg_irq_register db "Registering IRQ handler for IRQ ", 0
    msg_irq_invalid db "Invalid IRQ number or handler!", 0
    msg_keyboard_irq db "Keyboard IRQ received", 0
    msg_ahci_irq db "AHCI IRQ received", 0
    msg_timer_irq db "Timer IRQ received", 0
    msg_spurious_irq db "Spurious IRQ received: ", 0

section .text

;--------------------------------------------------------------------------
; setup_irq_handlers: Initialize IRQ handling system and register default handlers
; Input: None
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
setup_irq_handlers:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    
    ; Print setup message
    mov rsi, msg_irq_setup
    call scr64_print_string
    
    ; Initialize dispatch table with default handlers
    lea rdi, [irq_dispatch_table]
    mov rcx, 64
    lea rax, [default_irq_handler]
    
.init_loop:
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .init_loop
    
    ; Register specific handlers
    mov rdi, KEYBOARD_IRQ
    lea rsi, [keyboard_irq_handler]
    call register_irq_handler
    
    mov rdi, AHCI_IRQ
    lea rsi, [ahci_irq_handler]
    call register_irq_handler
    
    mov rdi, TIMER_IRQ
    lea rsi, [timer_irq_handler]
    call register_irq_handler
    
    ; Configure LAPIC (Local APIC)
    call configure_lapic
    
    ; Configure IOAPIC
    call configure_ioapic
    
    ; Success
    xor rax, rax
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; register_irq_handler: Register a handler function for a specific IRQ
; Input: RDI = IRQ number
;        RSI = Handler function pointer
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
register_irq_handler:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Validate IRQ number
    cmp rdi, 63
    ja .invalid_irq
    
    ; Validate handler pointer
    test rsi, rsi
    jz .invalid_handler
    
    ; Print registration message
    push rdi
    push rsi
    mov rsi, msg_irq_register
    call scr64_print_string
    pop rsi
    pop rdi
    
    push rsi
    mov rsi, rdi
    call scr64_print_hex
    pop rsi
    
    ; Register handler in dispatch table
    lea rax, [irq_dispatch_table]
    mov rcx, rdi
    shl rcx, 3 ; Multiply by 8 (size of pointer)
    add rax, rcx
    mov [rax], rsi
    
    ; Success
    xor rax, rax
    jmp .done
    
.invalid_irq:
.invalid_handler:
    ; Print error message
    mov rsi, msg_irq_invalid
    call scr64_print_string
    
    mov rax, 1
    
.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; configure_lapic: Configure Local APIC for interrupt handling
; Input: None
; Output: None
;--------------------------------------------------------------------------
configure_lapic:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Get LAPIC base address
    mov rbx, [acpi_lapic_base]
    test rbx, rbx
    jz .done ; Skip if not available
    
    ; Enable LAPIC (Set bit 8 in Spurious Interrupt Register)
    mov eax, [rbx + LAPIC_SPURIOUS]
    or eax, 0x100
    mov [rbx + LAPIC_SPURIOUS], eax
    
    ; Configure timer (if needed)
    ; For now, we'll just set it up but not enable it
    mov dword [rbx + LAPIC_LVT_TIMER], 0x10000 ; Masked, Vector 0
    mov dword [rbx + LAPIC_TIMER_DIVIDE], 0x0B ; Divide by 1
    
.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; configure_ioapic: Configure I/O APIC for external interrupts
; Input: None
; Output: None
;--------------------------------------------------------------------------
configure_ioapic:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    
    ; Get IOAPIC base address
    mov rbx, [acpi_ioapic_base]
    test rbx, rbx
    jz .done ; Skip if not available
    
    ; Configure keyboard IRQ (IRQ 1 -> Vector 0x21)
    mov edi, 1 ; IRQ number
    mov esi, 0x21 ; Vector number
    xor edx, edx ; Delivery mode 0 (normal)
    xor ecx, ecx ; Not masked
    call ioapic_set_irq
    
    ; Configure AHCI IRQ (IRQ 14 -> Vector 0x2E)
    mov edi, 14 ; IRQ number
    mov esi, 0x2E ; Vector number
    xor edx, edx ; Delivery mode 0 (normal)
    xor ecx, ecx ; Not masked
    call ioapic_set_irq
    
    ; Configure timer IRQ (IRQ 0 -> Vector 0x20)
    mov edi, 0 ; IRQ number
    mov esi, 0x20 ; Vector number
    xor edx, edx ; Delivery mode 0 (normal)
    xor ecx, ecx ; Not masked
    call ioapic_set_irq
    
.done:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; ioapic_set_irq: Configure a specific IRQ in the I/O APIC
; Input: EDI = IRQ number
;        ESI = Vector number
;        EDX = Delivery mode
;        ECX = Masked (1) or not (0)
; Output: None
;--------------------------------------------------------------------------
ioapic_set_irq:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Get IOAPIC base address
    mov rbx, [acpi_ioapic_base]
    test rbx, rbx
    jz .done ; Skip if not available
    
    ; Calculate redirection table entry offset
    mov eax, edi
    shl eax, 1 ; Multiply by 2 (each entry is 2 dwords)
    add eax, IOAPIC_REDTBL
    
    ; Build low dword of redirection entry
    mov r8d, esi ; Vector
    shl edx, 8
    or r8d, edx ; Delivery mode
    test ecx, ecx
    jz .not_masked
    or r8d, 0x10000 ; Set mask bit
.not_masked:
    
    ; Write low dword
    mov dword [rbx + IOAPIC_IOREGSEL], eax
    mov dword [rbx + IOAPIC_IOWIN], r8d
    
    ; Write high dword (destination)
    add eax, 1
    mov dword [rbx + IOAPIC_IOREGSEL], eax
    mov dword [rbx + IOAPIC_IOWIN], 0 ; CPU 0
    
.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; send_eoi: Send End-Of-Interrupt to LAPIC
; Input: None
; Output: None
;--------------------------------------------------------------------------
send_eoi:
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    
    ; Get LAPIC base address
    mov rbx, [acpi_lapic_base]
    test rbx, rbx
    jz .done ; Skip if not available
    
    ; Write to EOI register
    mov dword [rbx + LAPIC_EOI], 0
    
.done:
    pop rbx
    pop rax
    pop rbp
    ret

;--------------------------------------------------------------------------
; IRQ Handler Implementations
;--------------------------------------------------------------------------

; Default IRQ handler (for unregistered IRQs)
default_irq_handler:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
    
    ; Print spurious IRQ message with IRQ number
    mov rsi, msg_spurious_irq
    call scr64_print_string
    
    mov rsi, rdi ; IRQ number
    call scr64_print_hex
    
    ; Send EOI
    call send_eoi
    
    pop rdi
    pop rsi
    pop rbp
    ret

; Keyboard IRQ handler
keyboard_irq_handler:
    push rbp
    mov rbp, rsp
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
    
    ; Print keyboard IRQ message
    mov rsi, msg_keyboard_irq
    call scr64_print_string
    
    ; Read scancode from keyboard port
    in al, 0x60
    
    ; Process scancode
    movzx rdi, al
    call keyboard_process_scancode
    
    ; Send EOI
    call send_eoi
    
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
    pop rbp
    ret

; AHCI IRQ handler is now defined in ahci.asm
; We use extern ahci_irq_handler instead

; Timer IRQ handler
timer_irq_handler:
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Print timer IRQ message
    mov rsi, msg_timer_irq
    call scr64_print_string
    
    ; Timer-specific processing would go here
    
    ; Send EOI
    call send_eoi
    
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

;--------------------------------------------------------------------------
; IRQ Stubs (called directly from IDT)
;--------------------------------------------------------------------------

; These stubs save all registers and call the appropriate handler

; Keyboard IRQ stub (IRQ 1)
irq_keyboard_stub:
    push rax
    push rcx
    push rdx
    push rbx
    push rbp
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
    
    mov rdi, KEYBOARD_IRQ
    mov rsi, [irq_dispatch_table + KEYBOARD_IRQ * 8]
    call rsi
    
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
    pop rbp
    pop rbx
    pop rdx
    pop rcx
    pop rax
    iretq

; AHCI IRQ stub (IRQ 14)
irq_ahci_stub:
    push rax
    push rcx
    push rdx
    push rbx
    push rbp
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
    
    mov rdi, AHCI_IRQ
    mov rsi, [irq_dispatch_table + AHCI_IRQ * 8]
    call rsi
    
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
    pop rbp
    pop rbx
    pop rdx
    pop rcx
    pop rax
    iretq

; Timer IRQ stub (IRQ 0)
irq_timer_stub:
    push rax
    push rcx
    push rdx
    push rbx
    push rbp
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
    
    mov rdi, TIMER_IRQ
    mov rsi, [irq_dispatch_table + TIMER_IRQ * 8]
    call rsi
    
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
    pop rbp
    pop rbx
    pop rdx
    pop rcx
    pop rax
    iretq
