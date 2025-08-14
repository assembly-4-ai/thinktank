; gpu_irq.asm: Interrupt Request Handling Module
; Project Arora - Bare-Metal NVIDIA RTX 4060 Integration
; Implements IRQ vector handling for GPU events and asynchronous operations
; Follows Project Arora coding rules: custom functions, no ints, no syscalls

section .text

; External dependencies from Project Arora
extern scr64_print_string
extern shell_print_newline
extern string_to_hex
extern hex_to_string

; External dependencies from GPU modules
extern gpu_mmio_read_reg32
extern gpu_mmio_write_reg32
extern gpu_get_device_info

; Global exports
global gpu_irq_init
global gpu_irq_enable
global gpu_irq_disable
global gpu_irq_handler
global gpu_irq_register_callback
global gpu_irq_unregister_callback
global gpu_irq_get_status
global gpu_irq_clear_pending
global gpu_irq_setup_vector
global gpu_irq_cleanup

; IRQ register offsets from cpu_gpu manual
GPU_IRQ_STATUS_REG equ 0x00002000
GPU_IRQ_ENABLE_REG equ 0x00002004
GPU_IRQ_CLEAR_REG equ 0x00002008
GPU_IRQ_VECTOR_REG equ 0x0000200C
GPU_IRQ_MASK_REG equ 0x00002010
GPU_IRQ_PENDING_REG equ 0x00002014
GPU_IRQ_PRIORITY_REG equ 0x00002018
GPU_IRQ_CONFIG_REG equ 0x0000201C

; DMA interrupt registers
GPU_DMA_IRQ_STATUS_REG equ 0x0000102C
GPU_DMA_IRQ_ENABLE_REG equ 0x00001030
GPU_DMA_IRQ_CLEAR_REG equ 0x00001034

; Display interrupt registers
GPU_DISPLAY_IRQ_STATUS_REG equ 0x0062002C
GPU_DISPLAY_IRQ_ENABLE_REG equ 0x00620030
GPU_DISPLAY_IRQ_CLEAR_REG equ 0x00620034

; Compute engine interrupt registers
GPU_COMPUTE_IRQ_STATUS_REG equ 0x0080002C
GPU_COMPUTE_IRQ_ENABLE_REG equ 0x00800030
GPU_COMPUTE_IRQ_CLEAR_REG equ 0x00800034

; IRQ types and bit definitions
IRQ_TYPE_DMA_COMPLETE equ 0x00000001
IRQ_TYPE_DMA_ERROR equ 0x00000002
IRQ_TYPE_DISPLAY_VSYNC equ 0x00000004
IRQ_TYPE_DISPLAY_ERROR equ 0x00000008
IRQ_TYPE_COMPUTE_COMPLETE equ 0x00000010
IRQ_TYPE_COMPUTE_ERROR equ 0x00000020
IRQ_TYPE_THERMAL_WARNING equ 0x00000040
IRQ_TYPE_POWER_EVENT equ 0x00000080
IRQ_TYPE_ERROR_FATAL equ 0x00000100
IRQ_TYPE_MEMORY_ERROR equ 0x00000200

; IRQ priority levels
IRQ_PRIORITY_CRITICAL equ 0
IRQ_PRIORITY_HIGH equ 1
IRQ_PRIORITY_NORMAL equ 2
IRQ_PRIORITY_LOW equ 3

; Constants
MAX_IRQ_CALLBACKS equ 32
IRQ_VECTOR_BASE equ 0x50
IRQ_TIMEOUT_CYCLES equ 1000000

; IRQ callback structure
struc irq_callback
    .handler_func   resq 1
    .user_data      resq 1
    .irq_type       resq 1
    .priority       resq 1
    .enabled        resq 1
endstruc

; IRQ state structure
struc irq_state
    .initialized    resq 1
    .enabled        resq 1
    .vector_number  resq 1
    .total_irqs     resq 1
    .pending_irqs   resq 1
    .error_count    resq 1
    .callback_count resq 1
endstruc

gpu_irq_init:
    ; Initialize GPU interrupt handling system
    ; Input: RDI = IRQ vector number to use
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push r12
    
    ; Save IRQ vector number
    mov [irq_state_data + irq_state.vector_number], rdi
    mov r12, rdi
    
    ; Print initialization message
    mov rdi, irq_init_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Step 1: Disable all GPU interrupts
    call gpu_irq_disable_all
    
    ; Step 2: Clear any pending interrupts
    call gpu_irq_clear_all_pending
    
    ; Step 3: Setup IRQ vector in interrupt controller
    mov rdi, r12
    call gpu_irq_setup_vector
    
    ; Check vector setup result
    test rax, rax
    jnz .irq_init_failed
    
    ; Step 4: Configure IRQ priorities
    call gpu_irq_configure_priorities
    
    ; Check priority configuration result
    test rax, rax
    jnz .irq_init_failed
    
    ; Step 5: Initialize callback system
    call gpu_irq_init_callbacks
    
    ; Check callback initialization result
    test rax, rax
    jnz .irq_init_failed
    
    ; Step 6: Configure GPU IRQ routing
    call gpu_irq_configure_routing
    
    ; Check routing configuration result
    test rax, rax
    jnz .irq_init_failed
    
    ; Mark as initialized
    mov qword [irq_state_data + irq_state.initialized], 1
    
    ; Success
    mov rdi, irq_init_success_msg
    call scr64_print_string
    call shell_print_newline
    
    xor rax, rax
    jmp .irq_init_complete
    
.irq_init_failed:
    ; Cleanup on failure
    call gpu_irq_cleanup
    
    mov rdi, irq_init_failed_msg
    call scr64_print_string
    call shell_print_newline
    
    mov rax, 1
    
.irq_init_complete:
    pop r12
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_irq_disable_all:
    ; Disable all GPU interrupt sources
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    
    ; Disable main GPU interrupts
    mov rdi, GPU_IRQ_ENABLE_REG
    mov esi, 0
    call gpu_mmio_write_reg32
    
    ; Disable DMA interrupts
    mov rdi, GPU_DMA_IRQ_ENABLE_REG
    mov esi, 0
    call gpu_mmio_write_reg32
    
    ; Disable display interrupts
    mov rdi, GPU_DISPLAY_IRQ_ENABLE_REG
    mov esi, 0
    call gpu_mmio_write_reg32
    
    ; Disable compute interrupts
    mov rdi, GPU_COMPUTE_IRQ_ENABLE_REG
    mov esi, 0
    call gpu_mmio_write_reg32
    
    pop rsi
    pop rdi
    pop rbp
    ret

gpu_irq_clear_all_pending:
    ; Clear all pending GPU interrupts
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    
    ; Clear main GPU interrupts
    mov rdi, GPU_IRQ_CLEAR_REG
    mov esi, 0xFFFFFFFF
    call gpu_mmio_write_reg32
    
    ; Clear DMA interrupts
    mov rdi, GPU_DMA_IRQ_CLEAR_REG
    mov esi, 0xFFFFFFFF
    call gpu_mmio_write_reg32
    
    ; Clear display interrupts
    mov rdi, GPU_DISPLAY_IRQ_CLEAR_REG
    mov esi, 0xFFFFFFFF
    call gpu_mmio_write_reg32
    
    ; Clear compute interrupts
    mov rdi, GPU_COMPUTE_IRQ_CLEAR_REG
    mov esi, 0xFFFFFFFF
    call gpu_mmio_write_reg32
    
    pop rsi
    pop rdi
    pop rbp
    ret

gpu_irq_setup_vector:
    ; Setup IRQ vector in system interrupt controller
    ; Input: RDI = vector number
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    ; This is a simplified implementation
    ; In a real system, this would program the APIC or interrupt controller
    
    ; Configure GPU to use specified vector
    mov rdi, GPU_IRQ_VECTOR_REG
    mov rsi, [irq_state_data + irq_state.vector_number]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    ; Verify vector was set correctly
    mov rdi, GPU_IRQ_VECTOR_REG
    call gpu_mmio_read_reg32
    
    ; Check if vector matches what we set
    cmp eax, [irq_state_data + irq_state.vector_number]
    jne .vector_setup_failed
    
    ; Success
    xor rax, rax
    jmp .vector_setup_complete
    
.vector_setup_failed:
    ; Vector setup failed
    mov rax, 1
    
.vector_setup_complete:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_irq_configure_priorities:
    ; Configure interrupt priorities for different GPU events
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Set priority for different interrupt types
    ; Critical: Fatal errors, thermal warnings
    ; High: DMA completion, compute completion
    ; Normal: Display events
    ; Low: Power events
    
    ; Configure priority register
    mov eax, 0
    
    ; Set critical priority for fatal errors (bits 1-0)
    or eax, IRQ_PRIORITY_CRITICAL
    
    ; Set high priority for DMA events (bits 3-2)
    mov ebx, IRQ_PRIORITY_HIGH
    shl ebx, 2
    or eax, ebx
    
    ; Set normal priority for display events (bits 5-4)
    mov ebx, IRQ_PRIORITY_NORMAL
    shl ebx, 4
    or eax, ebx
    
    ; Set low priority for power events (bits 7-6)
    mov ebx, IRQ_PRIORITY_LOW
    shl ebx, 6
    or eax, ebx
    
    ; Write priority configuration
    mov rdi, GPU_IRQ_PRIORITY_REG
    mov esi, eax
    call gpu_mmio_write_reg32
    
    ; Success
    xor rax, rax
    
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_irq_init_callbacks:
    ; Initialize IRQ callback system
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdi
    
    ; Clear all callback entries
    mov rdi, irq_callbacks
    mov rcx, MAX_IRQ_CALLBACKS * irq_callback_size
    shr rcx, 3                      ; Convert to qwords
    xor rax, rax
    rep stosq
    
    ; Initialize callback count
    mov qword [irq_state_data + irq_state.callback_count], 0
    
    ; Success
    xor rax, rax
    
    pop rdi
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

gpu_irq_configure_routing:
    ; Configure how GPU interrupts are routed to the CPU
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    
    ; Configure interrupt routing in GPU
    ; Route all interrupts to main IRQ line
    mov rdi, GPU_IRQ_CONFIG_REG
    mov esi, 0x00000001             ; Route to main IRQ
    call gpu_mmio_write_reg32
    
    ; Configure interrupt mask (enable all types initially disabled)
    mov rdi, GPU_IRQ_MASK_REG
    mov esi, 0xFFFFFFFF             ; Mask all interrupts initially
    call gpu_mmio_write_reg32
    
    ; Success
    xor rax, rax
    
    pop rsi
    pop rdi
    pop rbp
    ret

gpu_irq_enable:
    ; Enable GPU interrupt handling
    ; Input: RDI = IRQ type mask to enable
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    ; Check if IRQ system is initialized
    cmp qword [irq_state_data + irq_state.initialized], 1
    jne .enable_failed
    
    ; Save IRQ type mask
    mov rbx, rdi
    
    ; Read current mask register
    mov rdi, GPU_IRQ_MASK_REG
    call gpu_mmio_read_reg32
    
    ; Clear bits for interrupts we want to enable
    not rbx
    and eax, ebx
    
    ; Write back updated mask
    mov rdi, GPU_IRQ_MASK_REG
    mov esi, eax
    call gpu_mmio_write_reg32
    
    ; Enable main GPU interrupt
    mov rdi, GPU_IRQ_ENABLE_REG
    mov esi, 1
    call gpu_mmio_write_reg32
    
    ; Mark IRQ system as enabled
    mov qword [irq_state_data + irq_state.enabled], 1
    
    ; Success
    xor rax, rax
    jmp .enable_complete
    
.enable_failed:
    ; Enable failed
    mov rax, 1
    
.enable_complete:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_irq_disable:
    ; Disable GPU interrupt handling
    ; Input: RDI = IRQ type mask to disable
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    ; Save IRQ type mask
    mov rbx, rdi
    
    ; Read current mask register
    mov rdi, GPU_IRQ_MASK_REG
    call gpu_mmio_read_reg32
    
    ; Set bits for interrupts we want to disable
    or eax, ebx
    
    ; Write back updated mask
    mov rdi, GPU_IRQ_MASK_REG
    mov esi, eax
    call gpu_mmio_write_reg32
    
    ; If all interrupts are disabled, disable main IRQ
    cmp eax, 0xFFFFFFFF
    jne .disable_complete
    
    ; Disable main GPU interrupt
    mov rdi, GPU_IRQ_ENABLE_REG
    mov esi, 0
    call gpu_mmio_write_reg32
    
    ; Mark IRQ system as disabled
    mov qword [irq_state_data + irq_state.enabled], 0
    
.disable_complete:
    ; Success
    xor rax, rax
    
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_irq_handler:
    ; Main GPU interrupt handler
    ; Input: None (called by interrupt controller)
    ; Output: None
    
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
    push r12
    push r13
    push r14
    push r15
    
    ; Increment total IRQ count
    inc qword [irq_state_data + irq_state.total_irqs]
    
    ; Read main IRQ status
    mov rdi, GPU_IRQ_STATUS_REG
    call gpu_mmio_read_reg32
    mov r12, rax                    ; Save main status
    
    ; Check for DMA interrupts
    test eax, IRQ_TYPE_DMA_COMPLETE
    jz .check_dma_error
    
    call gpu_irq_handle_dma_complete
    
.check_dma_error:
    test r12d, IRQ_TYPE_DMA_ERROR
    jz .check_display_vsync
    
    call gpu_irq_handle_dma_error
    
.check_display_vsync:
    test r12d, IRQ_TYPE_DISPLAY_VSYNC
    jz .check_display_error
    
    call gpu_irq_handle_display_vsync
    
.check_display_error:
    test r12d, IRQ_TYPE_DISPLAY_ERROR
    jz .check_compute_complete
    
    call gpu_irq_handle_display_error
    
.check_compute_complete:
    test r12d, IRQ_TYPE_COMPUTE_COMPLETE
    jz .check_compute_error
    
    call gpu_irq_handle_compute_complete
    
.check_compute_error:
    test r12d, IRQ_TYPE_COMPUTE_ERROR
    jz .check_thermal
    
    call gpu_irq_handle_compute_error
    
.check_thermal:
    test r12d, IRQ_TYPE_THERMAL_WARNING
    jz .check_power
    
    call gpu_irq_handle_thermal_warning
    
.check_power:
    test r12d, IRQ_TYPE_POWER_EVENT
    jz .check_fatal
    
    call gpu_irq_handle_power_event
    
.check_fatal:
    test r12d, IRQ_TYPE_ERROR_FATAL
    jz .check_memory
    
    call gpu_irq_handle_fatal_error
    
.check_memory:
    test r12d, IRQ_TYPE_MEMORY_ERROR
    jz .clear_interrupts
    
    call gpu_irq_handle_memory_error
    
.clear_interrupts:
    ; Clear processed interrupts
    mov rdi, GPU_IRQ_CLEAR_REG
    mov esi, r12d
    call gpu_mmio_write_reg32
    
    ; Call registered callbacks
    mov rdi, r12                    ; IRQ status
    call gpu_irq_call_callbacks
    
    ; Decrement pending IRQ count
    dec qword [irq_state_data + irq_state.pending_irqs]
    
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
    pop rbp
    ret

gpu_irq_handle_dma_complete:
    ; Handle DMA completion interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print debug message
    mov rdi, irq_dma_complete_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Clear DMA completion interrupt
    mov rdi, GPU_DMA_IRQ_CLEAR_REG
    mov esi, IRQ_TYPE_DMA_COMPLETE
    call gpu_mmio_write_reg32
    
    pop rdi
    pop rbp
    ret

gpu_irq_handle_dma_error:
    ; Handle DMA error interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print error message
    mov rdi, irq_dma_error_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Increment error count
    inc qword [irq_state_data + irq_state.error_count]
    
    ; Clear DMA error interrupt
    mov rdi, GPU_DMA_IRQ_CLEAR_REG
    mov esi, IRQ_TYPE_DMA_ERROR
    call gpu_mmio_write_reg32
    
    pop rdi
    pop rbp
    ret

gpu_irq_handle_display_vsync:
    ; Handle display VSYNC interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Clear display VSYNC interrupt
    mov rdi, GPU_DISPLAY_IRQ_CLEAR_REG
    mov esi, IRQ_TYPE_DISPLAY_VSYNC
    call gpu_mmio_write_reg32
    
    pop rdi
    pop rbp
    ret

gpu_irq_handle_display_error:
    ; Handle display error interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print error message
    mov rdi, irq_display_error_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Increment error count
    inc qword [irq_state_data + irq_state.error_count]
    
    ; Clear display error interrupt
    mov rdi, GPU_DISPLAY_IRQ_CLEAR_REG
    mov esi, IRQ_TYPE_DISPLAY_ERROR
    call gpu_mmio_write_reg32
    
    pop rdi
    pop rbp
    ret

gpu_irq_handle_compute_complete:
    ; Handle compute completion interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print debug message
    mov rdi, irq_compute_complete_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Clear compute completion interrupt
    mov rdi, GPU_COMPUTE_IRQ_CLEAR_REG
    mov esi, IRQ_TYPE_COMPUTE_COMPLETE
    call gpu_mmio_write_reg32
    
    pop rdi
    pop rbp
    ret

gpu_irq_handle_compute_error:
    ; Handle compute error interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print error message
    mov rdi, irq_compute_error_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Increment error count
    inc qword [irq_state_data + irq_state.error_count]
    
    ; Clear compute error interrupt
    mov rdi, GPU_COMPUTE_IRQ_CLEAR_REG
    mov esi, IRQ_TYPE_COMPUTE_ERROR
    call gpu_mmio_write_reg32
    
    pop rdi
    pop rbp
    ret

gpu_irq_handle_thermal_warning:
    ; Handle thermal warning interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print warning message
    mov rdi, irq_thermal_warning_msg
    call scr64_print_string
    call shell_print_newline
    
    ; This is a critical event - could implement thermal throttling here
    
    pop rdi
    pop rbp
    ret

gpu_irq_handle_power_event:
    ; Handle power event interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print power event message
    mov rdi, irq_power_event_msg
    call scr64_print_string
    call shell_print_newline
    
    pop rdi
    pop rbp
    ret

gpu_irq_handle_fatal_error:
    ; Handle fatal error interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print fatal error message
    mov rdi, irq_fatal_error_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Increment error count
    inc qword [irq_state_data + irq_state.error_count]
    
    ; This is a critical event - could implement system shutdown here
    
    pop rdi
    pop rbp
    ret

gpu_irq_handle_memory_error:
    ; Handle memory error interrupt
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print memory error message
    mov rdi, irq_memory_error_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Increment error count
    inc qword [irq_state_data + irq_state.error_count]
    
    pop rdi
    pop rbp
    ret

gpu_irq_register_callback:
    ; Register a callback function for specific IRQ types
    ; Input: RDI = callback function pointer
    ; Input: RSI = user data pointer
    ; Input: RDX = IRQ type mask
    ; Input: RCX = priority level
    ; Output: RAX = callback ID on success, 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Check if we have space for more callbacks
    mov rax, [irq_state_data + irq_state.callback_count]
    cmp rax, MAX_IRQ_CALLBACKS
    jge .register_failed
    
    ; Find next available callback slot
    mov r12, rax                    ; Callback index
    imul rax, irq_callback_size
    add rax, irq_callbacks
    mov r13, rax                    ; Callback structure pointer
    
    ; Fill callback structure
    mov [r13 + irq_callback.handler_func], rdi
    mov [r13 + irq_callback.user_data], rsi
    mov [r13 + irq_callback.irq_type], rdx
    mov [r13 + irq_callback.priority], rcx
    mov qword [r13 + irq_callback.enabled], 1
    
    ; Increment callback count
    inc qword [irq_state_data + irq_state.callback_count]
    
    ; Return callback ID (index + 1)
    mov rax, r12
    inc rax
    jmp .register_complete
    
.register_failed:
    ; Registration failed
    xor rax, rax
    
.register_complete:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

gpu_irq_unregister_callback:
    ; Unregister a previously registered callback
    ; Input: RDI = callback ID
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Validate callback ID
    test rdi, rdi
    jz .unregister_failed
    
    dec rdi                         ; Convert to index
    cmp rdi, MAX_IRQ_CALLBACKS
    jge .unregister_failed
    
    ; Calculate callback structure address
    imul rdi, irq_callback_size
    add rdi, irq_callbacks
    
    ; Check if callback is valid
    cmp qword [rdi + irq_callback.handler_func], 0
    je .unregister_failed
    
    ; Clear callback structure
    mov rcx, irq_callback_size / 8
    xor rax, rax
    rep stosq
    
    ; Decrement callback count
    dec qword [irq_state_data + irq_state.callback_count]
    
    ; Success
    xor rax, rax
    jmp .unregister_complete
    
.unregister_failed:
    ; Unregistration failed
    mov rax, 1
    
.unregister_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_irq_call_callbacks:
    ; Call registered callbacks for triggered interrupts
    ; Input: RDI = IRQ status mask
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push r12
    push r13
    push r14
    push r15
    
    ; Save IRQ status
    mov r12, rdi
    
    ; Iterate through all callbacks
    xor r13, r13                    ; Callback index
    
.callback_loop:
    ; Check if we've processed all callbacks
    cmp r13, [irq_state_data + irq_state.callback_count]
    jge .callbacks_complete
    
    ; Calculate callback structure address
    mov rax, r13
    imul rax, irq_callback_size
    add rax, irq_callbacks
    mov r14, rax
    
    ; Check if callback is enabled
    cmp qword [r14 + irq_callback.enabled], 1
    jne .next_callback
    
    ; Check if callback handles any of the triggered IRQs
    mov rax, [r14 + irq_callback.irq_type]
    and rax, r12
    jz .next_callback
    
    ; Call the callback function
    mov rdi, rax                    ; IRQ types that triggered
    mov rsi, [r14 + irq_callback.user_data]
    call [r14 + irq_callback.handler_func]
    
.next_callback:
    inc r13
    jmp .callback_loop
    
.callbacks_complete:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

gpu_irq_get_status:
    ; Get current IRQ status
    ; Input: None
    ; Output: RAX = IRQ status register value
    
    push rbp
    mov rbp, rsp
    
    ; Read IRQ status register
    mov rdi, GPU_IRQ_STATUS_REG
    call gpu_mmio_read_reg32
    
    pop rbp
    ret

gpu_irq_clear_pending:
    ; Clear specific pending interrupts
    ; Input: RDI = IRQ type mask to clear
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rsi
    
    ; Clear specified interrupts
    mov rdi, GPU_IRQ_CLEAR_REG
    mov esi, edi
    call gpu_mmio_write_reg32
    
    pop rsi
    pop rbp
    ret

gpu_irq_cleanup:
    ; Cleanup IRQ handling system
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    
    ; Disable all interrupts
    call gpu_irq_disable_all
    
    ; Clear all pending interrupts
    call gpu_irq_clear_all_pending
    
    ; Clear state
    mov qword [irq_state_data + irq_state.initialized], 0
    mov qword [irq_state_data + irq_state.enabled], 0
    mov qword [irq_state_data + irq_state.callback_count], 0
    
    pop rbp
    ret

; Data section
section .data
    irq_init_msg db 'GPU IRQ: Initializing interrupt handling system...', 0
    irq_init_success_msg db 'GPU IRQ: Interrupt handling successfully initialized', 0
    irq_init_failed_msg db 'GPU IRQ: Failed to initialize interrupt handling', 0
    irq_dma_complete_msg db 'GPU IRQ: DMA transfer completed', 0
    irq_dma_error_msg db 'GPU IRQ: DMA error occurred', 0
    irq_display_error_msg db 'GPU IRQ: Display error occurred', 0
    irq_compute_complete_msg db 'GPU IRQ: Compute operation completed', 0
    irq_compute_error_msg db 'GPU IRQ: Compute error occurred', 0
    irq_thermal_warning_msg db 'GPU IRQ: Thermal warning - GPU overheating!', 0
    irq_power_event_msg db 'GPU IRQ: Power event occurred', 0
    irq_fatal_error_msg db 'GPU IRQ: FATAL ERROR - System may be unstable!', 0
    irq_memory_error_msg db 'GPU IRQ: Memory error occurred', 0

; BSS section
section .bss
    ; IRQ state
    irq_state_data resb irq_state_size
    
    ; IRQ callback array
    irq_callbacks resb irq_callback_size * MAX_IRQ_CALLBACKS

