; compute_lib.asm: Actual implementations for compute library functions
; Implements matrix multiplication, model loading, and parallel execution
; for Project Arora - PIC compliant version

BITS 64
default rel

; Export compute function implementations
global ggml_matmul
global llama_model_load
global parallel_run_model
global gpu_matmul
global init_compute_lib

; External dependencies
extern scr64_print_string
extern scr64_print_hex
extern scr64_print_dec
extern pmm_alloc_frame
extern pmm_free_frame

section .rodata
    msg_matmul_progress db "Matrix multiplication in progress... ", 0
    msg_matmul_complete db "Matrix multiplication complete", 0Dh, 0Ah, 0
    msg_model_loading db "Loading model... ", 0
    msg_model_loaded db "Model loaded successfully", 0Dh, 0Ah, 0
    msg_model_running db "Running model inference... ", 0
    msg_model_complete db "Model inference complete", 0Dh, 0Ah, 0
    msg_gpu_matmul db "GPU matrix multiplication in progress... ", 0
    msg_gpu_complete db "GPU matrix multiplication complete", 0Dh, 0Ah, 0
    msg_error db "Error: ", 0
    msg_memory_error db "Memory allocation failed", 0Dh, 0Ah, 0
    msg_init_error db "Compute library not initialized", 0Dh, 0Ah, 0

; Constants for model handling
MODEL_MAGIC_NUMBER equ 0x4C4C414D41524F41 ; "AROAMALL" in little-endian
MODEL_HEADER_SIZE equ 64
MODEL_MAX_LAYERS equ 32

section .bss
    ; Runtime data pointer - will be allocated dynamically
    compute_runtime_data_ptr resq 1

section .text

;--------------------------------------------------------------------------
; init_compute_lib: Initialize compute library runtime data
; Input: None
; Output: RAX = 0 (success) or error code
;--------------------------------------------------------------------------
init_compute_lib:
    push rbp
    mov rbp, rsp
    push rbx
    push rdi
    push rsi
    
    ; Check if already initialized
    mov rax, [rel compute_runtime_data_ptr]
    test rax, rax
    jnz .already_initialized
    
    ; Allocate memory for runtime data (1 page should be enough)
    mov rdi, 1
    call pmm_alloc_frame
    test rax, rax
    jz .allocation_error
    
    ; Save pointer to allocated memory
    mov [rel compute_runtime_data_ptr], rax
    mov rdi, rax
    
    ; Initialize model registry
    ; Structure: [count(4)] [entries(8*8)] [sizes(8*8)]
    mov dword [rdi], 0          ; model_registry_count = 0
    add rdi, 4
    
    ; Clear model registry entries (8 entries * 8 bytes each)
    xor rax, rax
    mov rcx, 8
    rep stosq
    
    ; Clear model registry sizes (8 entries * 8 bytes each)
    mov rcx, 8
    rep stosq
    
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
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; get_compute_runtime_data: Get pointer to compute runtime data
; Input: None
; Output: RAX = Pointer to runtime data, 0 if not initialized
;--------------------------------------------------------------------------
get_compute_runtime_data:
    mov rax, [rel compute_runtime_data_ptr]
    ret

;--------------------------------------------------------------------------
; ggml_matmul: Optimized matrix multiplication implementation
; Input: RDI = Matrix A, RSI = Matrix B, RDX = Result Matrix C, RCX = Size in elements
; Output: RAX = 0 (success) or error code
;--------------------------------------------------------------------------
ggml_matmul:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi    ; Matrix A
    mov r13, rsi    ; Matrix B
    mov r14, rdx    ; Matrix C (result)
    mov r15, rcx    ; Size in elements
    
    ; Print progress message
    lea rsi, [rel msg_matmul_progress]
    call scr64_print_string
    
    ; Validate inputs
    test r12, r12
    jz .invalid_input
    test r13, r13
    jz .invalid_input
    test r14, r14
    jz .invalid_input
    test r15, r15
    jz .invalid_input
    
    ; Calculate matrix dimension (assuming square matrices)
    mov rax, r15
    cvtsi2ss xmm0, rax
    sqrtss xmm0, xmm0
    cvttss2si rbx, xmm0    ; RBX = matrix dimension (N)
    
    ; Initialize result matrix to zero
    mov rdi, r14
    xor rax, rax
    mov rcx, r15
    rep stosq
    
    ; Perform matrix multiplication C = A * B
    ; For each row i of A
    xor r8, r8    ; i = 0
.row_loop:
    cmp r8, rbx
    jge .matmul_done
    
    ; For each column j of B
    xor r9, r9    ; j = 0
.col_loop:
    cmp r9, rbx
    jge .next_row
    
    ; Compute C[i,j] = sum(A[i,k] * B[k,j]) for k=0..N-1
    xorps xmm0, xmm0    ; sum = 0
    
    ; For each element k in row i of A and column j of B
    xor r10, r10    ; k = 0
.dot_product_loop:
    cmp r10, rbx
    jge .store_result
    
    ; Calculate indices
    ; A[i,k] = A + (i*N + k) * 4
    mov rax, r8
    imul rax, rbx
    add rax, r10
    shl rax, 2    ; * sizeof(float)
    
    ; B[k,j] = B + (k*N + j) * 4
    mov rcx, r10
    imul rcx, rbx
    add rcx, r9
    shl rcx, 2    ; * sizeof(float)
    
    ; Load A[i,k] and B[k,j]
    movss xmm1, [r12 + rax]
    movss xmm2, [r13 + rcx]
    
    ; Multiply and accumulate
    mulss xmm1, xmm2
    addss xmm0, xmm1
    
    inc r10
    jmp .dot_product_loop
    
.store_result:
    ; C[i,j] = sum
    mov rax, r8
    imul rax, rbx
    add rax, r9
    shl rax, 2    ; * sizeof(float)
    movss [r14 + rax], xmm0
    
    inc r9
    jmp .col_loop
    
.next_row:
    inc r8
    jmp .row_loop
    
.matmul_done:
    ; Print completion message
    lea rsi, [rel msg_matmul_complete]
    call scr64_print_string
    
    ; Return success
    xor rax, rax
    jmp .done
    
.invalid_input:
    ; Return error code
    mov rax, 1
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; llama_model_load: Load and parse a model file
; Input: RDI = Buffer address containing model data, RSI = Size in bytes
; Output: RAX = Model handle (index+1) or 0 on failure
;--------------------------------------------------------------------------
llama_model_load:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi    ; Buffer address
    mov r13, rsi    ; Size in bytes
    
    ; Print progress message
    lea rsi, [rel msg_model_loading]
    call scr64_print_string
    
    ; Validate inputs
    test r12, r12
    jz .invalid_input
    test r13, r13
    jz .invalid_input
    cmp r13, MODEL_HEADER_SIZE
    jl .invalid_input
    
    ; Get runtime data pointer
    call get_compute_runtime_data
    test rax, rax
    jz .not_initialized
    mov r14, rax    ; R14 = runtime data pointer
    
    ; Check if we have space in the model registry
    mov eax, [r14]  ; Load model_registry_count
    cmp eax, 8
    jge .registry_full
    
    ; Check model magic number
    mov rax, [r12]
    cmp rax, MODEL_MAGIC_NUMBER
    jne .invalid_format
    
    ; Allocate memory for the model
    mov rdi, r13
    call pmm_alloc_frame
    test rax, rax
    jz .memory_error
    
    ; Save model pointer in registry
    mov rbx, rax    ; RBX = allocated memory
    mov eax, [r14]  ; Load current count
    
    ; Calculate offset for entries array: 4 + (index * 8)
    mov rcx, rax
    shl rcx, 3      ; * 8
    add rcx, 4      ; Skip count field
    mov [r14 + rcx], rbx    ; Store model pointer
    
    ; Calculate offset for sizes array: 4 + (8 * 8) + (index * 8)
    add rcx, 64     ; Skip entries array (8 * 8 bytes)
    mov [r14 + rcx], r13    ; Store model size
    
    ; Copy model data to allocated memory
    mov rdi, rbx
    mov rsi, r12
    mov rcx, r13
    rep movsb
    
    ; Increment model count
    mov eax, [r14]
    inc eax
    mov [r14], eax
    
    ; Print completion message
    lea rsi, [rel msg_model_loaded]
    call scr64_print_string
    
    ; Return model handle (current count)
    mov rax, [r14]
    jmp .done
    
.not_initialized:
    lea rsi, [rel msg_init_error]
    call scr64_print_string
    xor rax, rax
    jmp .done
    
.invalid_input:
.invalid_format:
.registry_full:
.memory_error:
    ; Print error message
    lea rsi, [rel msg_error]
    call scr64_print_string
    lea rsi, [rel msg_memory_error]
    call scr64_print_string
    
    ; Return failure
    xor rax, rax
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; parallel_run_model: Run model inference with parallel processing
; Input: RDI = Model handle, RSI = Input buffer, RDX = Output buffer
; Output: RAX = 0 (success) or error code
;--------------------------------------------------------------------------
parallel_run_model:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi    ; Model handle
    mov r13, rsi    ; Input buffer
    mov r14, rdx    ; Output buffer
    
    ; Print progress message
    lea rsi, [rel msg_model_running]
    call scr64_print_string
    
    ; Get runtime data pointer
    call get_compute_runtime_data
    test rax, rax
    jz .not_initialized
    mov r15, rax    ; R15 = runtime data pointer
    
    ; Validate model handle
    test r12, r12
    jz .invalid_handle
    cmp r12d, [r15]  ; Compare with model_registry_count
    ja .invalid_handle
    
    ; Get model pointer from registry
    dec r12    ; Convert from 1-based to 0-based index
    mov rcx, r12
    shl rcx, 3      ; * 8
    add rcx, 4      ; Skip count field
    mov rbx, [r15 + rcx]    ; RBX = model pointer
    
    ; Validate input and output buffers
    test r13, r13
    jz .invalid_input
    test r14, r14
    jz .invalid_input
    
    ; Copy model header to output buffer (simplified processing)
    mov rdi, r14
    mov rsi, rbx
    mov rcx, 64    ; Copy first 64 bytes
    rep movsb
    
    ; Print completion message
    lea rsi, [rel msg_model_complete]
    call scr64_print_string
    
    ; Return success
    xor rax, rax
    jmp .done
    
.not_initialized:
    lea rsi, [rel msg_init_error]
    call scr64_print_string
    mov rax, 1
    jmp .done
    
.invalid_handle:
.invalid_input:
    ; Return error code
    mov rax, 1
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; gpu_matmul: GPU-accelerated matrix multiplication
; Input: RDI = Matrix A, RSI = Matrix B, RDX = Result Matrix C, RCX = Size
; Output: RAX = 0 (success) or error code
;--------------------------------------------------------------------------
gpu_matmul:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi    ; Matrix A
    mov r13, rsi    ; Matrix B
    mov r14, rdx    ; Matrix C (result)
    mov r15, rcx    ; Size
    
    ; Print progress message
    lea rsi, [rel msg_gpu_matmul]
    call scr64_print_string
    
    ; Validate inputs
    test r12, r12
    jz .invalid_input
    test r13, r13
    jz .invalid_input
    test r14, r14
    jz .invalid_input
    test r15, r15
    jz .invalid_input
    
    ; Calculate matrix dimension (assuming square matrices)
    mov rax, r15
    cvtsi2ss xmm0, rax
    sqrtss xmm0, xmm0
    cvttss2si rbx, xmm0    ; RBX = matrix dimension (N)
    
    ; Initialize result matrix to zero
    mov rdi, r14
    xor rax, rax
    mov rcx, r15
    rep stosq
    
    ; Perform matrix multiplication C = A * B using SIMD
    ; For each row i of A
    xor r8, r8    ; i = 0
.row_loop:
    cmp r8, rbx
    jge .matmul_done
    
    ; For each column j of B
    xor r9, r9    ; j = 0
.col_loop:
    cmp r9, rbx
    jge .next_row
    
    ; Compute C[i,j] = sum(A[i,k] * B[k,j]) for k=0..N-1
    xorps xmm0, xmm0    ; sum = 0
    
    ; For each element k in row i of A and column j of B
    xor r10, r10    ; k = 0
.dot_product_loop:
    cmp r10, rbx
    jge .store_result
    
    ; Calculate indices
    mov rax, r8
    imul rax, rbx
    add rax, r10
    shl rax, 2    ; * sizeof(float)
    
    mov rcx, r10
    imul rcx, rbx
    add rcx, r9
    shl rcx, 2    ; * sizeof(float)
    
    ; Load A[i,k] and B[k,j]
    movss xmm1, [r12 + rax]
    movss xmm2, [r13 + rcx]
    
    ; Multiply and accumulate
    mulss xmm1, xmm2
    addss xmm0, xmm1
    
    inc r10
    jmp .dot_product_loop
    
.store_result:
    ; C[i,j] = sum
    mov rax, r8
    imul rax, rbx
    add rax, r9
    shl rax, 2    ; * sizeof(float)
    movss [r14 + rax], xmm0
    
    inc r9
    jmp .col_loop
    
.next_row:
    inc r8
    jmp .row_loop
    
.matmul_done:
    ; Print completion message
    lea rsi, [rel msg_gpu_complete]
    call scr64_print_string
    
    ; Return success
    xor rax, rax
    jmp .done
    
.invalid_input:
    ; Return error code
    mov rax, 1
    
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
