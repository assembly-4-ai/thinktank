; gpu_dma.asm: Direct Memory Access Engine Module
; Project Arora - Bare-Metal NVIDIA RTX 4060 Integration
; Implements high-performance DMA transfers between CPU and GPU memory
; Follows Project Arora coding rules: custom functions, no ints, no syscalls

section .text

; External dependencies from Project Arora
extern pmm_alloc_frame
extern pmm_free_frame
extern scr64_print_string
extern shell_print_newline
extern string_to_hex
extern hex_to_string

; External dependencies from GPU modules
extern gpu_mmio_read_reg32
extern gpu_mmio_write_reg32
extern gpu_mmio_read_reg64
extern gpu_mmio_write_reg64

; Global exports
global gpu_dma_init
global gpu_dma_transfer_host_to_device
global gpu_dma_transfer_device_to_host
global gpu_dma_transfer_device_to_device
global gpu_dma_wait_completion
global gpu_dma_get_status
global gpu_dma_abort_transfer
global gpu_dma_setup_descriptor_ring
global gpu_dma_cleanup

; DMA register offsets based on cpu_gpu manual
GPU_DMA_CONTROL_REG equ 0x00001000
GPU_DMA_STATUS_REG equ 0x00001004
GPU_DMA_SRC_ADDR_LOW_REG equ 0x00001008
GPU_DMA_SRC_ADDR_HIGH_REG equ 0x0000100C
GPU_DMA_DST_ADDR_LOW_REG equ 0x00001010
GPU_DMA_DST_ADDR_HIGH_REG equ 0x00001014
GPU_DMA_SIZE_REG equ 0x00001018
GPU_DMA_DESCRIPTOR_ADDR_LOW_REG equ 0x0000101C
GPU_DMA_DESCRIPTOR_ADDR_HIGH_REG equ 0x00001020
GPU_DMA_RING_HEAD_REG equ 0x00001024
GPU_DMA_RING_TAIL_REG equ 0x00001028
GPU_DMA_INTERRUPT_STATUS_REG equ 0x0000102C
GPU_DMA_INTERRUPT_ENABLE_REG equ 0x00001030

; DMA control register bits
DMA_CONTROL_ENABLE equ 0x00000001
DMA_CONTROL_START equ 0x00000002
DMA_CONTROL_RESET equ 0x00000004
DMA_CONTROL_INTERRUPT_ENABLE equ 0x00000008
DMA_CONTROL_DESCRIPTOR_MODE equ 0x00000010

; DMA status register bits
DMA_STATUS_BUSY equ 0x00000001
DMA_STATUS_COMPLETE equ 0x00000002
DMA_STATUS_ERROR equ 0x00000004
DMA_STATUS_RING_EMPTY equ 0x00000008
DMA_STATUS_RING_FULL equ 0x00000010

; DMA transfer types
DMA_TYPE_HOST_TO_DEVICE equ 0
DMA_TYPE_DEVICE_TO_HOST equ 1
DMA_TYPE_DEVICE_TO_DEVICE equ 2

; Constants
DMA_MAX_TRANSFER_SIZE equ 0x10000000    ; 256MB max transfer
DMA_DESCRIPTOR_RING_SIZE equ 256        ; 256 descriptors
DMA_TIMEOUT_CYCLES equ 100000000        ; Timeout for DMA operations
DMA_ALIGNMENT_REQUIREMENT equ 64        ; 64-byte alignment

; DMA descriptor structure
struc dma_descriptor
    .src_addr_low       resd 1
    .src_addr_high      resd 1
    .dst_addr_low       resd 1
    .dst_addr_high      resd 1
    .size               resd 1
    .control            resd 1
    .status             resd 1
    .next_descriptor    resd 1
endstruc

; DMA engine state structure
struc dma_engine_state
    .initialized        resq 1
    .descriptor_ring    resq 1
    .ring_physical_addr resq 1
    .ring_head          resq 1
    .ring_tail          resq 1
    .active_transfers   resq 1
    .total_transfers    resq 1
    .error_count        resq 1
endstruc

gpu_dma_init:
    ; Initialize DMA engine for GPU memory transfers
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    
    ; Print initialization message
    mov rdi, dma_init_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Step 1: Reset DMA engine
    call gpu_dma_reset_engine
    
    ; Check reset result
    test rax, rax
    jnz .dma_init_failed
    
    ; Step 2: Allocate descriptor ring
    call gpu_dma_allocate_descriptor_ring
    
    ; Check allocation result
    test rax, rax
    jnz .dma_init_failed
    
    ; Step 3: Setup descriptor ring in hardware
    call gpu_dma_setup_descriptor_ring
    
    ; Check setup result
    test rax, rax
    jnz .dma_init_failed
    
    ; Step 4: Enable DMA engine
    call gpu_dma_enable_engine
    
    ; Check enable result
    test rax, rax
    jnz .dma_init_failed
    
    ; Step 5: Verify DMA engine is ready
    call gpu_dma_verify_ready
    
    ; Check ready result
    test rax, rax
    jnz .dma_init_failed
    
    ; Mark as initialized
    mov qword [dma_state + dma_engine_state.initialized], 1
    
    ; Success
    mov rdi, dma_init_success_msg
    call scr64_print_string
    call shell_print_newline
    
    xor rax, rax
    jmp .dma_init_complete
    
.dma_init_failed:
    ; Cleanup on failure
    call gpu_dma_cleanup
    
    mov rdi, dma_init_failed_msg
    call scr64_print_string
    call shell_print_newline
    
    mov rax, 1
    
.dma_init_complete:
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_reset_engine:
    ; Reset DMA engine to initial state
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Write reset bit to control register
    mov rdi, GPU_DMA_CONTROL_REG
    mov esi, DMA_CONTROL_RESET
    call gpu_mmio_write_reg32
    
    ; Wait for reset to complete
    mov rcx, DMA_TIMEOUT_CYCLES
    
.reset_wait_loop:
    ; Read control register
    mov rdi, GPU_DMA_CONTROL_REG
    call gpu_mmio_read_reg32
    
    ; Check if reset bit is cleared
    test eax, DMA_CONTROL_RESET
    jz .reset_complete
    
    ; Decrement timeout counter
    dec rcx
    jnz .reset_wait_loop
    
    ; Reset timeout
    mov rax, 1
    jmp .reset_done
    
.reset_complete:
    ; Clear any pending status
    mov rdi, GPU_DMA_STATUS_REG
    mov esi, 0xFFFFFFFF
    call gpu_mmio_write_reg32
    
    ; Success
    xor rax, rax
    
.reset_done:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_allocate_descriptor_ring:
    ; Allocate memory for DMA descriptor ring
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    
    ; Calculate ring size in bytes
    mov rax, DMA_DESCRIPTOR_RING_SIZE
    imul rax, dma_descriptor_size
    
    ; Round up to page boundary
    add rax, 0xFFF
    and rax, 0xFFFFF000
    
    ; Calculate number of pages needed
    shr rax, 12
    mov rbx, rax
    
    ; Allocate physically contiguous memory
    mov rdi, rbx
    call pmm_alloc_frame
    
    ; Check allocation result
    test rax, rax
    jz .allocation_failed
    
    ; Store descriptor ring address
    mov [dma_state + dma_engine_state.descriptor_ring], rax
    mov [dma_state + dma_engine_state.ring_physical_addr], rax
    
    ; Initialize descriptor ring
    call gpu_dma_initialize_descriptor_ring
    
    ; Success
    xor rax, rax
    jmp .allocation_complete
    
.allocation_failed:
    ; Allocation failed
    mov rax, 1
    
.allocation_complete:
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_initialize_descriptor_ring:
    ; Initialize DMA descriptor ring structure
    ; Input: None (uses allocated ring)
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Get descriptor ring address
    mov rdi, [dma_state + dma_engine_state.descriptor_ring]
    
    ; Clear entire ring
    mov rcx, DMA_DESCRIPTOR_RING_SIZE
    imul rcx, dma_descriptor_size
    shr rcx, 3                      ; Convert to qwords
    xor rax, rax
    rep stosq
    
    ; Initialize ring pointers
    mov qword [dma_state + dma_engine_state.ring_head], 0
    mov qword [dma_state + dma_engine_state.ring_tail], 0
    mov qword [dma_state + dma_engine_state.active_transfers], 0
    mov qword [dma_state + dma_engine_state.total_transfers], 0
    mov qword [dma_state + dma_engine_state.error_count], 0
    
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

gpu_dma_setup_descriptor_ring:
    ; Setup descriptor ring in GPU hardware
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Get ring physical address
    mov rbx, [dma_state + dma_engine_state.ring_physical_addr]
    
    ; Write ring base address (low 32 bits)
    mov rdi, GPU_DMA_DESCRIPTOR_ADDR_LOW_REG
    mov esi, ebx
    call gpu_mmio_write_reg32
    
    ; Write ring base address (high 32 bits)
    mov rdi, GPU_DMA_DESCRIPTOR_ADDR_HIGH_REG
    shr rbx, 32
    mov esi, ebx
    call gpu_mmio_write_reg32
    
    ; Initialize ring head and tail pointers
    mov rdi, GPU_DMA_RING_HEAD_REG
    mov esi, 0
    call gpu_mmio_write_reg32
    
    mov rdi, GPU_DMA_RING_TAIL_REG
    mov esi, 0
    call gpu_mmio_write_reg32
    
    ; Success
    xor rax, rax
    
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_enable_engine:
    ; Enable DMA engine for operation
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Read current control register
    mov rdi, GPU_DMA_CONTROL_REG
    call gpu_mmio_read_reg32
    
    ; Set enable and descriptor mode bits
    or eax, DMA_CONTROL_ENABLE
    or eax, DMA_CONTROL_DESCRIPTOR_MODE
    or eax, DMA_CONTROL_INTERRUPT_ENABLE
    
    ; Write back control register
    mov rdi, GPU_DMA_CONTROL_REG
    mov esi, eax
    call gpu_mmio_write_reg32
    
    ; Verify engine is enabled
    mov rdi, GPU_DMA_CONTROL_REG
    call gpu_mmio_read_reg32
    
    ; Check enable bit
    test eax, DMA_CONTROL_ENABLE
    jz .enable_failed
    
    ; Success
    xor rax, rax
    jmp .enable_complete
    
.enable_failed:
    ; Enable failed
    mov rax, 1
    
.enable_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_verify_ready:
    ; Verify DMA engine is ready for transfers
    ; Input: None
    ; Output: RAX = 0 if ready, error code if not ready
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Read status register
    mov rdi, GPU_DMA_STATUS_REG
    call gpu_mmio_read_reg32
    
    ; Check for error conditions
    test eax, DMA_STATUS_ERROR
    jnz .not_ready
    
    ; Check if engine is busy with initialization
    test eax, DMA_STATUS_BUSY
    jnz .not_ready
    
    ; Engine is ready
    xor rax, rax
    jmp .ready_check_complete
    
.not_ready:
    ; Engine is not ready
    mov rax, 1
    
.ready_check_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_transfer_host_to_device:
    ; Transfer data from host memory to GPU memory
    ; Input: RDI = source address (host)
    ; Input: RSI = destination address (GPU)
    ; Input: RDX = transfer size in bytes
    ; Output: RAX = transfer ID on success, 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi                    ; Source address
    mov r13, rsi                    ; Destination address
    mov r14, rdx                    ; Transfer size
    mov r15, DMA_TYPE_HOST_TO_DEVICE ; Transfer type
    
    ; Validate parameters
    call gpu_dma_validate_transfer_params
    
    ; Check validation result
    test rax, rax
    jnz .transfer_failed
    
    ; Get next descriptor slot
    call gpu_dma_get_next_descriptor
    
    ; Check if descriptor is available
    test rax, rax
    jz .transfer_failed
    
    ; Save descriptor pointer
    mov rbx, rax
    
    ; Setup descriptor
    mov rdi, rbx
    mov rsi, r12                    ; Source
    mov rdx, r13                    ; Destination
    mov rcx, r14                    ; Size
    mov r8, r15                     ; Type
    call gpu_dma_setup_descriptor
    
    ; Submit transfer
    mov rdi, rbx
    call gpu_dma_submit_transfer
    
    ; Check submission result
    test rax, rax
    jz .transfer_failed
    
    ; Return transfer ID (descriptor index)
    call gpu_dma_get_descriptor_index
    jmp .transfer_complete
    
.transfer_failed:
    ; Transfer failed
    xor rax, rax
    
.transfer_complete:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_transfer_device_to_host:
    ; Transfer data from GPU memory to host memory
    ; Input: RDI = source address (GPU)
    ; Input: RSI = destination address (host)
    ; Input: RDX = transfer size in bytes
    ; Output: RAX = transfer ID on success, 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi                    ; Source address
    mov r13, rsi                    ; Destination address
    mov r14, rdx                    ; Transfer size
    mov r15, DMA_TYPE_DEVICE_TO_HOST ; Transfer type
    
    ; Validate parameters
    call gpu_dma_validate_transfer_params
    
    ; Check validation result
    test rax, rax
    jnz .transfer_failed
    
    ; Get next descriptor slot
    call gpu_dma_get_next_descriptor
    
    ; Check if descriptor is available
    test rax, rax
    jz .transfer_failed
    
    ; Save descriptor pointer
    mov rbx, rax
    
    ; Setup descriptor
    mov rdi, rbx
    mov rsi, r12                    ; Source
    mov rdx, r13                    ; Destination
    mov rcx, r14                    ; Size
    mov r8, r15                     ; Type
    call gpu_dma_setup_descriptor
    
    ; Submit transfer
    mov rdi, rbx
    call gpu_dma_submit_transfer
    
    ; Check submission result
    test rax, rax
    jz .transfer_failed
    
    ; Return transfer ID
    call gpu_dma_get_descriptor_index
    jmp .transfer_complete
    
.transfer_failed:
    ; Transfer failed
    xor rax, rax
    
.transfer_complete:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_transfer_device_to_device:
    ; Transfer data between GPU memory locations
    ; Input: RDI = source address (GPU)
    ; Input: RSI = destination address (GPU)
    ; Input: RDX = transfer size in bytes
    ; Output: RAX = transfer ID on success, 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi                    ; Source address
    mov r13, rsi                    ; Destination address
    mov r14, rdx                    ; Transfer size
    mov r15, DMA_TYPE_DEVICE_TO_DEVICE ; Transfer type
    
    ; Validate parameters
    call gpu_dma_validate_transfer_params
    
    ; Check validation result
    test rax, rax
    jnz .transfer_failed
    
    ; Get next descriptor slot
    call gpu_dma_get_next_descriptor
    
    ; Check if descriptor is available
    test rax, rax
    jz .transfer_failed
    
    ; Save descriptor pointer
    mov rbx, rax
    
    ; Setup descriptor
    mov rdi, rbx
    mov rsi, r12                    ; Source
    mov rdx, r13                    ; Destination
    mov rcx, r14                    ; Size
    mov r8, r15                     ; Type
    call gpu_dma_setup_descriptor
    
    ; Submit transfer
    mov rdi, rbx
    call gpu_dma_submit_transfer
    
    ; Check submission result
    test rax, rax
    jz .transfer_failed
    
    ; Return transfer ID
    call gpu_dma_get_descriptor_index
    jmp .transfer_complete
    
.transfer_failed:
    ; Transfer failed
    xor rax, rax
    
.transfer_complete:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_validate_transfer_params:
    ; Validate DMA transfer parameters
    ; Input: R12 = source, R13 = destination, R14 = size, R15 = type
    ; Output: RAX = 0 if valid, error code if invalid
    
    push rbp
    mov rbp, rsp
    
    ; Check if DMA is initialized
    cmp qword [dma_state + dma_engine_state.initialized], 1
    jne .params_invalid
    
    ; Check transfer size
    test r14, r14
    jz .params_invalid
    
    ; Check maximum transfer size
    cmp r14, DMA_MAX_TRANSFER_SIZE
    jg .params_invalid
    
    ; Check alignment requirements
    test r12, DMA_ALIGNMENT_REQUIREMENT - 1
    jnz .params_invalid
    
    test r13, DMA_ALIGNMENT_REQUIREMENT - 1
    jnz .params_invalid
    
    test r14, DMA_ALIGNMENT_REQUIREMENT - 1
    jnz .params_invalid
    
    ; Check transfer type
    cmp r15, DMA_TYPE_DEVICE_TO_DEVICE
    jg .params_invalid
    
    ; Parameters are valid
    xor rax, rax
    jmp .validation_complete
    
.params_invalid:
    ; Parameters are invalid
    mov rax, 1
    
.validation_complete:
    pop rbp
    ret

gpu_dma_get_next_descriptor:
    ; Get next available descriptor from ring
    ; Input: None
    ; Output: RAX = descriptor pointer, or 0 if ring is full
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Get current tail position
    mov rax, [dma_state + dma_engine_state.ring_tail]
    mov rbx, rax
    
    ; Calculate next tail position
    inc rax
    cmp rax, DMA_DESCRIPTOR_RING_SIZE
    jl .tail_ok
    xor rax, rax                    ; Wrap around
    
.tail_ok:
    ; Check if ring is full (next tail == head)
    mov rcx, [dma_state + dma_engine_state.ring_head]
    cmp rax, rcx
    je .ring_full
    
    ; Update tail position
    mov [dma_state + dma_engine_state.ring_tail], rax
    
    ; Calculate descriptor address
    mov rax, [dma_state + dma_engine_state.descriptor_ring]
    imul rbx, dma_descriptor_size
    add rax, rbx
    
    jmp .get_descriptor_complete
    
.ring_full:
    ; Ring is full
    xor rax, rax
    
.get_descriptor_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_setup_descriptor:
    ; Setup DMA descriptor with transfer parameters
    ; Input: RDI = descriptor pointer
    ; Input: RSI = source address
    ; Input: RDX = destination address
    ; Input: RCX = size
    ; Input: R8 = transfer type
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    
    ; Clear descriptor
    mov rax, rdi
    mov rbx, dma_descriptor_size / 8
    push rdi
    xor rax, rax
    rep stosq
    pop rdi
    
    ; Set source address
    mov [rdi + dma_descriptor.src_addr_low], esi
    shr rsi, 32
    mov [rdi + dma_descriptor.src_addr_high], esi
    
    ; Set destination address
    mov [rdi + dma_descriptor.dst_addr_low], edx
    shr rdx, 32
    mov [rdi + dma_descriptor.dst_addr_high], edx
    
    ; Set transfer size
    mov [rdi + dma_descriptor.size], ecx
    
    ; Set control flags based on transfer type
    mov eax, 0x00000001             ; Valid descriptor
    
    ; Add type-specific flags
    cmp r8, DMA_TYPE_HOST_TO_DEVICE
    je .setup_h2d
    cmp r8, DMA_TYPE_DEVICE_TO_HOST
    je .setup_d2h
    cmp r8, DMA_TYPE_DEVICE_TO_DEVICE
    je .setup_d2d
    jmp .setup_complete
    
.setup_h2d:
    or eax, 0x00000010              ; Host to device flag
    jmp .setup_complete
    
.setup_d2h:
    or eax, 0x00000020              ; Device to host flag
    jmp .setup_complete
    
.setup_d2d:
    or eax, 0x00000040              ; Device to device flag
    
.setup_complete:
    ; Set control field
    mov [rdi + dma_descriptor.control], eax
    
    ; Initialize status
    mov dword [rdi + dma_descriptor.status], 0
    
    pop rbx
    pop rax
    pop rbp
    ret

gpu_dma_submit_transfer:
    ; Submit DMA transfer to hardware
    ; Input: RDI = descriptor pointer
    ; Output: RAX = 1 on success, 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Update ring tail in hardware
    mov rax, [dma_state + dma_engine_state.ring_tail]
    mov rdi, GPU_DMA_RING_TAIL_REG
    mov esi, eax
    call gpu_mmio_write_reg32
    
    ; Increment active transfer count
    inc qword [dma_state + dma_engine_state.active_transfers]
    inc qword [dma_state + dma_engine_state.total_transfers]
    
    ; Success
    mov rax, 1
    
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_get_descriptor_index:
    ; Get index of current descriptor
    ; Input: RBX = descriptor pointer
    ; Output: RAX = descriptor index
    
    push rbp
    mov rbp, rsp
    push rcx
    push rdx
    
    ; Calculate index
    mov rax, rbx
    sub rax, [dma_state + dma_engine_state.descriptor_ring]
    mov rcx, dma_descriptor_size
    xor rdx, rdx
    div rcx
    
    pop rdx
    pop rcx
    pop rbp
    ret

gpu_dma_wait_completion:
    ; Wait for DMA transfer completion
    ; Input: RDI = transfer ID
    ; Output: RAX = 0 on success, error code on failure/timeout
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    ; Calculate descriptor address
    mov rax, [dma_state + dma_engine_state.descriptor_ring]
    imul rdi, dma_descriptor_size
    add rax, rdi
    mov rbx, rax                    ; Descriptor pointer
    
    ; Wait for completion with timeout
    mov rcx, DMA_TIMEOUT_CYCLES
    
.wait_loop:
    ; Check descriptor status
    mov eax, [rbx + dma_descriptor.status]
    
    ; Check if transfer is complete
    test eax, 0x00000002            ; Complete bit
    jnz .transfer_complete
    
    ; Check for error
    test eax, 0x00000004            ; Error bit
    jnz .transfer_error
    
    ; Check timeout
    dec rcx
    jnz .wait_loop
    
    ; Timeout
    mov rax, 2
    jmp .wait_done
    
.transfer_complete:
    ; Decrement active transfer count
    dec qword [dma_state + dma_engine_state.active_transfers]
    
    ; Success
    xor rax, rax
    jmp .wait_done
    
.transfer_error:
    ; Increment error count
    inc qword [dma_state + dma_engine_state.error_count]
    
    ; Error
    mov rax, 1
    
.wait_done:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_get_status:
    ; Get DMA engine status
    ; Input: None
    ; Output: RAX = status register value
    
    push rbp
    mov rbp, rsp
    
    ; Read status register
    mov rdi, GPU_DMA_STATUS_REG
    call gpu_mmio_read_reg32
    
    pop rbp
    ret

gpu_dma_abort_transfer:
    ; Abort a specific DMA transfer
    ; Input: RDI = transfer ID
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Calculate descriptor address
    mov rax, [dma_state + dma_engine_state.descriptor_ring]
    imul rdi, dma_descriptor_size
    add rax, rdi
    mov rbx, rax
    
    ; Mark descriptor as aborted
    mov dword [rbx + dma_descriptor.status], 0x00000008 ; Aborted bit
    
    ; Clear control field
    mov dword [rbx + dma_descriptor.control], 0
    
    ; Success
    xor rax, rax
    
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_dma_cleanup:
    ; Cleanup DMA engine resources
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rdi
    
    ; Disable DMA engine
    mov rdi, GPU_DMA_CONTROL_REG
    mov esi, 0
    call gpu_mmio_write_reg32
    
    ; Free descriptor ring if allocated
    mov rax, [dma_state + dma_engine_state.descriptor_ring]
    test rax, rax
    jz .cleanup_complete
    
    mov rdi, rax
    call pmm_free_frame
    
    ; Clear state
    mov qword [dma_state + dma_engine_state.descriptor_ring], 0
    mov qword [dma_state + dma_engine_state.initialized], 0
    
.cleanup_complete:
    pop rdi
    pop rax
    pop rbp
    ret

; Data section
section .data
    dma_init_msg db 'GPU DMA: Initializing DMA engine...', 0
    dma_init_success_msg db 'GPU DMA: DMA engine successfully initialized', 0
    dma_init_failed_msg db 'GPU DMA: Failed to initialize DMA engine', 0
    dma_transfer_start_msg db 'GPU DMA: Starting transfer...', 0
    dma_transfer_complete_msg db 'GPU DMA: Transfer completed', 0
    dma_transfer_failed_msg db 'GPU DMA: Transfer failed', 0

; BSS section
section .bss
    ; DMA engine state
    dma_state resb dma_engine_state_size

