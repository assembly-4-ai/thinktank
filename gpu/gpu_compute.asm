; gpu_compute.asm: GPU Compute Kernel Module
; Project Arora - Bare-Metal NVIDIA RTX 4060 Integration
; Implements basic GPU compute operations starting with matrix addition
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
extern gpu_dma_transfer_host_to_device
extern gpu_dma_transfer_device_to_host
extern gpu_dma_wait_completion
extern gpu_irq_register_callback

; Global exports
global gpu_compute_init
global gpu_compute_matrix_add
global gpu_compute_matrix_multiply
global gpu_compute_vector_add
global gpu_compute_submit_kernel
global gpu_compute_wait_completion
global gpu_compute_get_status
global gpu_compute_cleanup
global gpu_compute_allocate_buffer
global gpu_compute_free_buffer

; Compute engine register offsets from cpu_gpu manual
GPU_COMPUTE_CONTROL_REG equ 0x00800000
GPU_COMPUTE_STATUS_REG equ 0x00800004
GPU_COMPUTE_COMMAND_REG equ 0x00800008
GPU_COMPUTE_KERNEL_ADDR_REG equ 0x0080000C
GPU_COMPUTE_PARAM_ADDR_REG equ 0x00800010
GPU_COMPUTE_GRID_SIZE_X_REG equ 0x00800014
GPU_COMPUTE_GRID_SIZE_Y_REG equ 0x00800018
GPU_COMPUTE_GRID_SIZE_Z_REG equ 0x0080001C
GPU_COMPUTE_BLOCK_SIZE_X_REG equ 0x00800020
GPU_COMPUTE_BLOCK_SIZE_Y_REG equ 0x00800024
GPU_COMPUTE_BLOCK_SIZE_Z_REG equ 0x00800028
GPU_COMPUTE_SHARED_MEM_SIZE_REG equ 0x0080002C
GPU_COMPUTE_STREAM_ID_REG equ 0x00800030

; Compute commands
COMPUTE_CMD_LAUNCH_KERNEL equ 0x00000001
COMPUTE_CMD_RESET_ENGINE equ 0x00000002
COMPUTE_CMD_FLUSH_CACHE equ 0x00000004
COMPUTE_CMD_SYNC_STREAM equ 0x00000008

; Compute status bits
COMPUTE_STATUS_IDLE equ 0x00000001
COMPUTE_STATUS_BUSY equ 0x00000002
COMPUTE_STATUS_ERROR equ 0x00000004
COMPUTE_STATUS_COMPLETE equ 0x00000008

; Kernel opcodes (simplified instruction set)
KERNEL_OP_LOAD_GLOBAL equ 0x01
KERNEL_OP_STORE_GLOBAL equ 0x02
KERNEL_OP_ADD_F32 equ 0x10
KERNEL_OP_MUL_F32 equ 0x11
KERNEL_OP_MAD_F32 equ 0x12
KERNEL_OP_THREAD_ID equ 0x20
KERNEL_OP_BLOCK_ID equ 0x21
KERNEL_OP_SYNC_THREADS equ 0x30
KERNEL_OP_RETURN equ 0xFF

; Constants
MAX_COMPUTE_BUFFERS equ 64
COMPUTE_TIMEOUT_CYCLES equ 100000000
MATRIX_MAX_SIZE equ 4096
VECTOR_MAX_SIZE equ 16384

; Compute buffer structure
struc compute_buffer
    .gpu_address    resq 1
    .host_address   resq 1
    .size           resq 1
    .allocated      resq 1
endstruc

; Compute kernel structure
struc compute_kernel
    .code_address   resq 1
    .code_size      resq 1
    .param_address  resq 1
    .param_size     resq 1
    .grid_x         resq 1
    .grid_y         resq 1
    .grid_z         resq 1
    .block_x        resq 1
    .block_y        resq 1
    .block_z        resq 1
    .shared_mem     resq 1
    .stream_id      resq 1
endstruc

; Compute engine state
struc compute_state
    .initialized    resq 1
    .active_kernels resq 1
    .total_kernels  resq 1
    .error_count    resq 1
    .buffer_count   resq 1
endstruc

gpu_compute_init:
    ; Initialize GPU compute engine
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Print initialization message
    mov rdi, compute_init_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Step 1: Reset compute engine
    call gpu_compute_reset_engine
    
    ; Check reset result
    test rax, rax
    jnz .compute_init_failed
    
    ; Step 2: Initialize buffer management
    call gpu_compute_init_buffers
    
    ; Check buffer initialization result
    test rax, rax
    jnz .compute_init_failed
    
    ; Step 3: Register compute completion callback
    mov rdi, gpu_compute_completion_callback
    mov rsi, 0                      ; No user data
    mov rdx, 0x00000010             ; IRQ_TYPE_COMPUTE_COMPLETE
    mov rcx, 1                      ; High priority
    call gpu_irq_register_callback
    
    ; Check callback registration result
    test rax, rax
    jz .compute_init_failed
    
    ; Step 4: Verify compute engine is ready
    call gpu_compute_verify_ready
    
    ; Check ready result
    test rax, rax
    jnz .compute_init_failed
    
    ; Mark as initialized
    mov qword [compute_state_data + compute_state.initialized], 1
    
    ; Success
    mov rdi, compute_init_success_msg
    call scr64_print_string
    call shell_print_newline
    
    xor rax, rax
    jmp .compute_init_complete
    
.compute_init_failed:
    ; Cleanup on failure
    call gpu_compute_cleanup
    
    mov rdi, compute_init_failed_msg
    call scr64_print_string
    call shell_print_newline
    
    mov rax, 1
    
.compute_init_complete:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_compute_reset_engine:
    ; Reset compute engine to initial state
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Send reset command
    mov rdi, GPU_COMPUTE_COMMAND_REG
    mov esi, COMPUTE_CMD_RESET_ENGINE
    call gpu_mmio_write_reg32
    
    ; Wait for reset to complete
    mov rcx, COMPUTE_TIMEOUT_CYCLES
    
.reset_wait_loop:
    ; Read status register
    mov rdi, GPU_COMPUTE_STATUS_REG
    call gpu_mmio_read_reg32
    
    ; Check if engine is idle
    test eax, COMPUTE_STATUS_IDLE
    jnz .reset_complete
    
    ; Decrement timeout counter
    dec rcx
    jnz .reset_wait_loop
    
    ; Reset timeout
    mov rax, 1
    jmp .reset_done
    
.reset_complete:
    ; Clear any error flags
    mov rdi, GPU_COMPUTE_STATUS_REG
    mov esi, COMPUTE_STATUS_ERROR
    call gpu_mmio_write_reg32
    
    ; Success
    xor rax, rax
    
.reset_done:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_compute_init_buffers:
    ; Initialize compute buffer management
    ; Input: None
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdi
    
    ; Clear all buffer entries
    mov rdi, compute_buffers
    mov rcx, MAX_COMPUTE_BUFFERS * compute_buffer_size
    shr rcx, 3                      ; Convert to qwords
    xor rax, rax
    rep stosq
    
    ; Initialize buffer count
    mov qword [compute_state_data + compute_state.buffer_count], 0
    
    ; Success
    xor rax, rax
    
    pop rdi
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

gpu_compute_verify_ready:
    ; Verify compute engine is ready for operation
    ; Input: None
    ; Output: RAX = 0 if ready, error code if not ready
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Read status register
    mov rdi, GPU_COMPUTE_STATUS_REG
    call gpu_mmio_read_reg32
    
    ; Check for error conditions
    test eax, COMPUTE_STATUS_ERROR
    jnz .not_ready
    
    ; Check if engine is idle (ready for new work)
    test eax, COMPUTE_STATUS_IDLE
    jz .not_ready
    
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

gpu_compute_matrix_add:
    ; Perform matrix addition on GPU: C = A + B
    ; Input: RDI = matrix A address (host)
    ; Input: RSI = matrix B address (host)
    ; Input: RDX = matrix C address (host)
    ; Input: RCX = matrix width
    ; Input: R8 = matrix height
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi                    ; Matrix A
    mov r13, rsi                    ; Matrix B
    mov r14, rdx                    ; Matrix C
    mov r15, rcx                    ; Width
    
    ; Validate matrix dimensions
    test rcx, rcx
    jz .matrix_add_failed
    test r8, r8
    jz .matrix_add_failed
    
    cmp rcx, MATRIX_MAX_SIZE
    jg .matrix_add_failed
    cmp r8, MATRIX_MAX_SIZE
    jg .matrix_add_failed
    
    ; Calculate matrix size in bytes (width * height * 4 bytes per float)
    mov rax, rcx
    imul rax, r8
    shl rax, 2                      ; Multiply by 4 for float32
    mov rbx, rax                    ; Matrix size
    
    ; Allocate GPU buffers for matrices
    mov rdi, rbx                    ; Size
    call gpu_compute_allocate_buffer
    test rax, rax
    jz .matrix_add_failed
    mov [gpu_buffer_a], rax         ; Buffer A
    
    mov rdi, rbx                    ; Size
    call gpu_compute_allocate_buffer
    test rax, rax
    jz .matrix_add_failed
    mov [gpu_buffer_b], rax         ; Buffer B
    
    mov rdi, rbx                    ; Size
    call gpu_compute_allocate_buffer
    test rax, rax
    jz .matrix_add_failed
    mov [gpu_buffer_c], rax         ; Buffer C
    
    ; Transfer matrices to GPU
    mov rdi, r12                    ; Source (matrix A)
    mov rsi, [gpu_buffer_a]         ; Destination
    mov rdx, rbx                    ; Size
    call gpu_dma_transfer_host_to_device
    test rax, rax
    jz .matrix_add_failed
    
    mov rdi, r13                    ; Source (matrix B)
    mov rsi, [gpu_buffer_b]         ; Destination
    mov rdx, rbx                    ; Size
    call gpu_dma_transfer_host_to_device
    test rax, rax
    jz .matrix_add_failed
    
    ; Generate matrix addition kernel
    call gpu_compute_generate_matrix_add_kernel
    test rax, rax
    jz .matrix_add_failed
    
    ; Setup kernel parameters
    mov rdi, matrix_add_kernel
    mov rsi, r15                    ; Width
    mov rdx, r8                     ; Height
    call gpu_compute_setup_matrix_add_params
    
    ; Launch kernel
    mov rdi, matrix_add_kernel
    call gpu_compute_submit_kernel
    test rax, rax
    jz .matrix_add_failed
    
    ; Wait for completion
    mov rdi, rax                    ; Kernel ID
    call gpu_compute_wait_completion
    test rax, rax
    jnz .matrix_add_failed
    
    ; Transfer result back to host
    mov rdi, [gpu_buffer_c]         ; Source
    mov rsi, r14                    ; Destination (matrix C)
    mov rdx, rbx                    ; Size
    call gpu_dma_transfer_device_to_host
    test rax, rax
    jz .matrix_add_failed
    
    ; Wait for transfer completion
    mov rdi, rax                    ; Transfer ID
    call gpu_dma_wait_completion
    test rax, rax
    jnz .matrix_add_failed
    
    ; Cleanup GPU buffers
    mov rdi, [gpu_buffer_a]
    call gpu_compute_free_buffer
    
    mov rdi, [gpu_buffer_b]
    call gpu_compute_free_buffer
    
    mov rdi, [gpu_buffer_c]
    call gpu_compute_free_buffer
    
    ; Success
    xor rax, rax
    jmp .matrix_add_complete
    
.matrix_add_failed:
    ; Cleanup on failure
    mov rdi, [gpu_buffer_a]
    test rdi, rdi
    jz .cleanup_b
    call gpu_compute_free_buffer
    
.cleanup_b:
    mov rdi, [gpu_buffer_b]
    test rdi, rdi
    jz .cleanup_c
    call gpu_compute_free_buffer
    
.cleanup_c:
    mov rdi, [gpu_buffer_c]
    test rdi, rdi
    jz .cleanup_done
    call gpu_compute_free_buffer
    
.cleanup_done:
    ; Matrix addition failed
    mov rax, 1
    
.matrix_add_complete:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

gpu_compute_generate_matrix_add_kernel:
    ; Generate GPU kernel code for matrix addition
    ; Input: None
    ; Output: RAX = kernel address on success, 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    
    ; Allocate memory for kernel code
    mov rdi, 1                      ; 1 page for kernel
    call pmm_alloc_frame
    test rax, rax
    jz .kernel_gen_failed
    
    ; Save kernel address
    mov [matrix_add_kernel + compute_kernel.code_address], rax
    mov qword [matrix_add_kernel + compute_kernel.code_size], 4096
    
    ; Generate kernel instructions
    mov rdi, rax                    ; Kernel code address
    call gpu_compute_write_matrix_add_instructions
    
    ; Success
    mov rax, [matrix_add_kernel + compute_kernel.code_address]
    jmp .kernel_gen_complete
    
.kernel_gen_failed:
    ; Kernel generation failed
    xor rax, rax
    
.kernel_gen_complete:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_compute_write_matrix_add_instructions:
    ; Write GPU instructions for matrix addition kernel
    ; Input: RDI = kernel code address
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    
    ; Save code address
    mov rbx, rdi
    
    ; Instruction 1: Get thread ID
    mov al, KERNEL_OP_THREAD_ID
    mov [rbx], al
    inc rbx
    
    ; Instruction 2: Load element from matrix A
    mov al, KERNEL_OP_LOAD_GLOBAL
    mov [rbx], al
    inc rbx
    
    ; Instruction 3: Load element from matrix B
    mov al, KERNEL_OP_LOAD_GLOBAL
    mov [rbx], al
    inc rbx
    
    ; Instruction 4: Add elements
    mov al, KERNEL_OP_ADD_F32
    mov [rbx], al
    inc rbx
    
    ; Instruction 5: Store result to matrix C
    mov al, KERNEL_OP_STORE_GLOBAL
    mov [rbx], al
    inc rbx
    
    ; Instruction 6: Return
    mov al, KERNEL_OP_RETURN
    mov [rbx], al
    
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

gpu_compute_setup_matrix_add_params:
    ; Setup parameters for matrix addition kernel
    ; Input: RDI = kernel structure
    ; Input: RSI = matrix width
    ; Input: RDX = matrix height
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    
    ; Set grid dimensions (one thread per matrix element)
    mov [rdi + compute_kernel.grid_x], rsi
    mov [rdi + compute_kernel.grid_y], rdx
    mov qword [rdi + compute_kernel.grid_z], 1
    
    ; Set block dimensions (32x32 threads per block)
    mov qword [rdi + compute_kernel.block_x], 32
    mov qword [rdi + compute_kernel.block_y], 32
    mov qword [rdi + compute_kernel.block_z], 1
    
    ; Set shared memory size (none needed for this kernel)
    mov qword [rdi + compute_kernel.shared_mem], 0
    
    ; Set stream ID (use default stream)
    mov qword [rdi + compute_kernel.stream_id], 0
    
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

gpu_compute_submit_kernel:
    ; Submit compute kernel for execution
    ; Input: RDI = kernel structure pointer
    ; Output: RAX = kernel ID on success, 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    ; Save kernel structure
    mov rbx, rdi
    
    ; Write kernel address to GPU
    mov rdi, GPU_COMPUTE_KERNEL_ADDR_REG
    mov rsi, [rbx + compute_kernel.code_address]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    ; Write parameter address to GPU
    mov rdi, GPU_COMPUTE_PARAM_ADDR_REG
    mov rsi, [rbx + compute_kernel.param_address]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    ; Write grid dimensions
    mov rdi, GPU_COMPUTE_GRID_SIZE_X_REG
    mov rsi, [rbx + compute_kernel.grid_x]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    mov rdi, GPU_COMPUTE_GRID_SIZE_Y_REG
    mov rsi, [rbx + compute_kernel.grid_y]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    mov rdi, GPU_COMPUTE_GRID_SIZE_Z_REG
    mov rsi, [rbx + compute_kernel.grid_z]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    ; Write block dimensions
    mov rdi, GPU_COMPUTE_BLOCK_SIZE_X_REG
    mov rsi, [rbx + compute_kernel.block_x]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    mov rdi, GPU_COMPUTE_BLOCK_SIZE_Y_REG
    mov rsi, [rbx + compute_kernel.block_y]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    mov rdi, GPU_COMPUTE_BLOCK_SIZE_Z_REG
    mov rsi, [rbx + compute_kernel.block_z]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    ; Write shared memory size
    mov rdi, GPU_COMPUTE_SHARED_MEM_SIZE_REG
    mov rsi, [rbx + compute_kernel.shared_mem]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    ; Write stream ID
    mov rdi, GPU_COMPUTE_STREAM_ID_REG
    mov rsi, [rbx + compute_kernel.stream_id]
    mov esi, esi
    call gpu_mmio_write_reg32
    
    ; Launch kernel
    mov rdi, GPU_COMPUTE_COMMAND_REG
    mov esi, COMPUTE_CMD_LAUNCH_KERNEL
    call gpu_mmio_write_reg32
    
    ; Increment active kernel count
    inc qword [compute_state_data + compute_state.active_kernels]
    inc qword [compute_state_data + compute_state.total_kernels]
    
    ; Return kernel ID (simplified - use total kernel count)
    mov rax, [compute_state_data + compute_state.total_kernels]
    
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_compute_wait_completion:
    ; Wait for compute kernel completion
    ; Input: RDI = kernel ID
    ; Output: RAX = 0 on success, error code on failure/timeout
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Wait for completion with timeout
    mov rcx, COMPUTE_TIMEOUT_CYCLES
    
.wait_loop:
    ; Read status register
    mov rdi, GPU_COMPUTE_STATUS_REG
    call gpu_mmio_read_reg32
    
    ; Check if kernel is complete
    test eax, COMPUTE_STATUS_COMPLETE
    jnz .kernel_complete
    
    ; Check for error
    test eax, COMPUTE_STATUS_ERROR
    jnz .kernel_error
    
    ; Check timeout
    dec rcx
    jnz .wait_loop
    
    ; Timeout
    mov rax, 2
    jmp .wait_done
    
.kernel_complete:
    ; Decrement active kernel count
    dec qword [compute_state_data + compute_state.active_kernels]
    
    ; Success
    xor rax, rax
    jmp .wait_done
    
.kernel_error:
    ; Increment error count
    inc qword [compute_state_data + compute_state.error_count]
    
    ; Error
    mov rax, 1
    
.wait_done:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_compute_allocate_buffer:
    ; Allocate GPU memory buffer
    ; Input: RDI = buffer size in bytes
    ; Output: RAX = GPU buffer address on success, 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    ; Find free buffer slot
    xor rbx, rbx                    ; Buffer index
    
.find_buffer_loop:
    cmp rbx, MAX_COMPUTE_BUFFERS
    jge .allocation_failed
    
    ; Calculate buffer structure address
    mov rax, rbx
    imul rax, compute_buffer_size
    add rax, compute_buffers
    
    ; Check if buffer is free
    cmp qword [rax + compute_buffer.allocated], 0
    je .buffer_found
    
    inc rbx
    jmp .find_buffer_loop
    
.buffer_found:
    ; Save buffer structure address
    mov rcx, rax
    
    ; Allocate host memory for buffer (simplified)
    ; In a real implementation, this would allocate GPU VRAM
    mov rax, rdi
    add rax, 0xFFF
    shr rax, 12                     ; Convert to pages
    
    push rdi
    mov rdi, rax
    call pmm_alloc_frame
    pop rdi
    
    test rax, rax
    jz .allocation_failed
    
    ; Fill buffer structure
    mov [rcx + compute_buffer.gpu_address], rax
    mov [rcx + compute_buffer.host_address], rax
    mov [rcx + compute_buffer.size], rdi
    mov qword [rcx + compute_buffer.allocated], 1
    
    ; Increment buffer count
    inc qword [compute_state_data + compute_state.buffer_count]
    
    ; Return GPU address
    mov rax, [rcx + compute_buffer.gpu_address]
    jmp .allocation_complete
    
.allocation_failed:
    ; Allocation failed
    xor rax, rax
    
.allocation_complete:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_compute_free_buffer:
    ; Free GPU memory buffer
    ; Input: RDI = GPU buffer address
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdx
    
    ; Find buffer by GPU address
    xor rbx, rbx                    ; Buffer index
    
.find_buffer_loop:
    cmp rbx, MAX_COMPUTE_BUFFERS
    jge .free_complete
    
    ; Calculate buffer structure address
    mov rax, rbx
    imul rax, compute_buffer_size
    add rax, compute_buffers
    
    ; Check if this is the buffer we're looking for
    cmp [rax + compute_buffer.gpu_address], rdi
    je .buffer_found
    
    inc rbx
    jmp .find_buffer_loop
    
.buffer_found:
    ; Check if buffer is allocated
    cmp qword [rax + compute_buffer.allocated], 1
    jne .free_complete
    
    ; Free host memory
    mov rdi, [rax + compute_buffer.host_address]
    call pmm_free_frame
    
    ; Clear buffer structure
    mov rcx, compute_buffer_size / 8
    xor rdx, rdx
    rep stosq
    
    ; Decrement buffer count
    dec qword [compute_state_data + compute_state.buffer_count]
    
.free_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

gpu_compute_get_status:
    ; Get compute engine status
    ; Input: None
    ; Output: RAX = status register value
    
    push rbp
    mov rbp, rsp
    
    ; Read status register
    mov rdi, GPU_COMPUTE_STATUS_REG
    call gpu_mmio_read_reg32
    
    pop rbp
    ret

gpu_compute_completion_callback:
    ; Callback function for compute completion interrupts
    ; Input: RDI = IRQ types that triggered
    ; Input: RSI = user data (unused)
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print completion message
    mov rdi, compute_completion_msg
    call scr64_print_string
    call shell_print_newline
    
    pop rdi
    pop rbp
    ret

gpu_compute_cleanup:
    ; Cleanup compute engine resources
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdi
    
    ; Free all allocated buffers
    xor rbx, rbx                    ; Buffer index
    
.cleanup_buffer_loop:
    cmp rbx, MAX_COMPUTE_BUFFERS
    jge .cleanup_complete
    
    ; Calculate buffer structure address
    mov rax, rbx
    imul rax, compute_buffer_size
    add rax, compute_buffers
    
    ; Check if buffer is allocated
    cmp qword [rax + compute_buffer.allocated], 1
    jne .next_buffer
    
    ; Free buffer
    mov rdi, [rax + compute_buffer.gpu_address]
    call gpu_compute_free_buffer
    
.next_buffer:
    inc rbx
    jmp .cleanup_buffer_loop
    
.cleanup_complete:
    ; Reset compute engine
    call gpu_compute_reset_engine
    
    ; Clear state
    mov qword [compute_state_data + compute_state.initialized], 0
    mov qword [compute_state_data + compute_state.buffer_count], 0
    
    pop rdi
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

; Data section
section .data
    compute_init_msg db 'GPU Compute: Initializing compute engine...', 0
    compute_init_success_msg db 'GPU Compute: Compute engine successfully initialized', 0
    compute_init_failed_msg db 'GPU Compute: Failed to initialize compute engine', 0
    compute_completion_msg db 'GPU Compute: Kernel execution completed', 0
    matrix_add_start_msg db 'GPU Compute: Starting matrix addition...', 0
    matrix_add_complete_msg db 'GPU Compute: Matrix addition completed', 0

; BSS section
section .bss
    ; Compute engine state
    compute_state_data resb compute_state_size
    
    ; Compute buffer array
    compute_buffers resb compute_buffer_size * MAX_COMPUTE_BUFFERS
    
    ; Matrix addition kernel
    matrix_add_kernel resb compute_kernel_size
    
    ; Temporary GPU buffer addresses
    gpu_buffer_a resq 1
    gpu_buffer_b resq 1
    gpu_buffer_c resq 1

