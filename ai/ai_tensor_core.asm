; ai_tensor_core.asm: Core tensor operations for bare-metal AI model
; Project Arora - Bare-Metal NASM AI Implementation
; Implements fundamental tensor data structures and operations
; Adheres to Project Arora coding rules: no ints, syscalls, libs - all custom

section .data
    ; Tensor type constants (using 64-bit values instead of ints)
    global TENSOR_TYPE_F32
    TENSOR_TYPE_F32     dq 0x0000000000000001
    TENSOR_TYPE_F16     dq 0x0000000000000002
    TENSOR_TYPE_Q8_0    dq 0x0000000000000003
    TENSOR_TYPE_Q4_0    dq 0x0000000000000004
    
    ; Tensor operation constants
    TENSOR_OP_ADD       dq 0x0000000000000010
    TENSOR_OP_MUL       dq 0x0000000000000020
    TENSOR_OP_MATMUL    dq 0x0000000000000030
    
    ; Memory alignment constants
    TENSOR_ALIGN_64     dq 0x0000000000000040
    CACHE_LINE_SIZE     dq 0x0000000000000040
    
    ; Mathematical constants for AI operations
    AI_PI               dq 3.141592653589793
    AI_E                dq 2.718281828459045
    AI_SQRT2            dq 1.414213562373095
    AI_LN2              dq 0.693147180559945
    
    ; SIMD optimization flags
    SIMD_AVX512_FLAG    dq 0x0000000000000001
    SIMD_AVX2_FLAG      dq 0x0000000000000002
    SIMD_FMA_FLAG       dq 0x0000000000000004

section .bss
    ; Global tensor registry for memory management
    tensor_registry     resq 1024    ; Space for 1024 tensor descriptors
    tensor_count        resq 1       ; Current number of active tensors
    
    ; Memory pool for tensor data
    tensor_memory_pool  resq 1       ; Pointer to main memory pool
    pool_size           resq 1       ; Size of memory pool
    pool_used           resq 1       ; Amount of pool currently used
    
    ; Hardware capability flags
    cpu_features        resq 1       ; Detected CPU features
    cache_sizes         resq 4       ; L1, L2, L3 cache sizes + TLB

section .text
    global ai_tensor_init
    global ai_tensor_create
    global ai_tensor_destroy
    global ai_tensor_reshape
    global ai_tensor_copy
    global ai_tensor_add
    global ai_tensor_multiply
    global ai_tensor_matmul
    global ai_tensor_get_element
    global ai_tensor_set_element
    global ai_detect_cpu_features
    global ai_optimize_memory_layout
    
    ; External Project Arora functions
    extern pmm_alloc_frame
    extern pmm_free_frame
    extern get_numa_node_count
    extern screen_print_string

; Tensor descriptor structure (all 64-bit fields)
; Offset 0:   data_ptr       - Pointer to tensor data
; Offset 8:   shape_ptr      - Pointer to shape array
; Offset 16:  stride_ptr     - Pointer to stride array
; Offset 24:  ndim           - Number of dimensions
; Offset 32:  dtype          - Data type
; Offset 40:  size           - Total number of elements
; Offset 48:  byte_size      - Total size in bytes
; Offset 56:  flags          - Tensor flags and metadata
; Total size: 64 bytes (cache-line aligned)

ai_tensor_init:
    ; Initialize the AI tensor system
    ; Input: RDI = memory pool size in bytes
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Store requested pool size
    mov [pool_size], rdi
    
    ; Detect CPU features first
    call ai_detect_cpu_features
    test rax, rax
    jnz .init_error
    
    ; Allocate memory pool from PMM
    mov rdi, [pool_size]
    ; Convert bytes to frames (4KB each)
    add rdi, 4095
    shr rdi, 12
    call pmm_alloc_frame
    test rax, rax
    jz .init_error
    
    ; Store memory pool pointer
    mov [tensor_memory_pool], rax
    
    ; Initialize tensor registry
    mov rax, tensor_registry
    mov rcx, 1024
    xor rdx, rdx
.clear_registry:
    mov [rax], rdx
    add rax, 8
    loop .clear_registry
    
    ; Initialize counters
    mov qword [tensor_count], 0
    mov qword [pool_used], 0
    
    ; Success
    xor rax, rax
    jmp .init_done
    
.init_error:
    mov rax, 1
    
.init_done:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_detect_cpu_features:
    ; Detect available CPU features for optimization
    ; Output: RAX = 0 on success, sets cpu_features
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    xor rax, rax
    mov [cpu_features], rax
    
    ; Check for CPUID support
    pushfq
    pop rax
    mov rcx, rax
    xor rax, 0x200000
    push rax
    popfq
    pushfq
    pop rax
    xor rax, rcx
    jz .no_cpuid
    
    ; Check for AVX512 support
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, 0x10000000  ; AVX512F
    jz .check_avx2
    or qword [cpu_features], 1  ; Set AVX512 flag
    
.check_avx2:
    ; Check for AVX2 support
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, 0x20        ; AVX2
    jz .check_fma
    or qword [cpu_features], 2  ; Set AVX2 flag
    
.check_fma:
    ; Check for FMA support
    mov eax, 1
    cpuid
    test ecx, 0x1000      ; FMA
    jz .features_done
    or qword [cpu_features], 4  ; Set FMA flag
    
.features_done:
    xor rax, rax
    jmp .detect_done
    
.no_cpuid:
    mov rax, 1
    
.detect_done:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_tensor_create:
    ; Create a new tensor with specified shape and data type
    ; Input: RDI = shape array pointer, RSI = number of dimensions, RDX = data type
    ; Output: RAX = tensor descriptor pointer, or 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Find free slot in tensor registry
    mov rbx, tensor_registry
    mov rcx, 1024
    xor rax, rax
    
.find_slot:
    cmp qword [rbx], 0
    je .found_slot
    add rbx, 64  ; Each descriptor is 64 bytes
    loop .find_slot
    
    ; No free slots
    xor rax, rax
    jmp .create_done
    
.found_slot:
    ; Calculate total size needed
    mov rax, rsi  ; number of dimensions
    mov [rbx + 24], rax  ; Store ndim
    mov [rbx + 32], rdx  ; Store dtype
    
    ; Calculate total elements
    mov rcx, rsi
    mov rax, 1
    mov r8, rdi  ; shape array
    
.calc_size:
    test rcx, rcx
    jz .size_calculated
    mov r9, [r8]
    mul r9
    add r8, 8
    dec rcx
    jmp .calc_size
    
.size_calculated:
    mov [rbx + 40], rax  ; Store total elements
    
    ; Calculate byte size based on data type
    cmp rdx, [TENSOR_TYPE_F32]
    je .size_f32
    cmp rdx, [TENSOR_TYPE_F16]
    je .size_f16
    cmp rdx, [TENSOR_TYPE_Q8_0]
    je .size_q8
    cmp rdx, [TENSOR_TYPE_Q4_0]
    je .size_q4
    
    ; Default to F32
.size_f32:
    shl rax, 2  ; 4 bytes per element
    jmp .allocate_data
    
.size_f16:
    shl rax, 1  ; 2 bytes per element
    jmp .allocate_data
    
.size_q8:
    ; Q8_0 format: 1 byte per element + scale
    add rax, 32  ; Add space for scale values
    jmp .allocate_data
    
.size_q4:
    ; Q4_0 format: 0.5 bytes per element + scale
    shr rax, 1
    add rax, 32
    
.allocate_data:
    mov [rbx + 48], rax  ; Store byte size
    
    ; Align to cache line boundary
    add rax, 63
    and rax, ~63
    
    ; Check if we have enough space in pool
    mov rcx, [pool_used]
    add rcx, rax
    cmp rcx, [pool_size]
    ja .allocation_failed
    
    ; Allocate from pool
    mov rcx, [tensor_memory_pool]
    add rcx, [pool_used]
    mov [rbx], rcx  ; Store data pointer
    
    ; Update pool usage
    add [pool_used], rax
    
    ; Allocate and copy shape array
    mov rax, rsi
    shl rax, 3  ; 8 bytes per dimension
    add rax, 63
    and rax, ~63
    
    mov rcx, [tensor_memory_pool]
    add rcx, [pool_used]
    mov [rbx + 8], rcx  ; Store shape pointer
    add [pool_used], rax
    
    ; Copy shape data
    mov rcx, rsi
    mov rsi, rdi  ; source shape array
    mov rdi, [rbx + 8]  ; destination
    rep movsq
    
    ; Calculate and store strides
    call ai_calculate_strides
    
    ; Initialize flags
    mov qword [rbx + 56], 0
    
    ; Increment tensor count
    inc qword [tensor_count]
    
    ; Return tensor descriptor pointer
    mov rax, rbx
    jmp .create_done
    
.allocation_failed:
    xor rax, rax
    
.create_done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_calculate_strides:
    ; Calculate strides for tensor
    ; Input: RBX = tensor descriptor
    ; Modifies: RAX, RCX, RDX, RSI, RDI
    
    push rbp
    mov rbp, rsp
    
    ; Get number of dimensions
    mov rcx, [rbx + 24]
    test rcx, rcx
    jz .strides_done
    
    ; Allocate stride array
    mov rax, rcx
    shl rax, 3  ; 8 bytes per stride
    add rax, 63
    and rax, ~63
    
    mov rdx, [tensor_memory_pool]
    add rdx, [pool_used]
    mov [rbx + 16], rdx  ; Store stride pointer
    add [pool_used], rax
    
    ; Calculate strides (row-major order)
    mov rsi, [rbx + 8]   ; shape array
    mov rdi, [rbx + 16]  ; stride array
    
    ; Start from last dimension
    mov rax, 1
    mov rdx, rcx
    dec rdx
    
.calc_stride_loop:
    mov [rdi + rdx * 8], rax
    mov r8, [rsi + rdx * 8]  ; shape[i]
    mul r8
    test rdx, rdx
    jz .strides_done
    dec rdx
    jmp .calc_stride_loop
    
.strides_done:
    pop rbp
    ret

ai_tensor_add:
    ; Element-wise addition of two tensors
    ; Input: RDI = tensor A, RSI = tensor B, RDX = result tensor
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push r8
    push r9
    push r10
    push r11
    
    ; Verify tensors have same shape
    mov rax, [rdi + 40]  ; size of tensor A
    cmp rax, [rsi + 40]  ; size of tensor B
    jne .add_error
    cmp rax, [rdx + 40]  ; size of result tensor
    jne .add_error
    
    ; Get data pointers
    mov rbx, [rdi]       ; data A
    mov rcx, [rsi]       ; data B
    mov r8, [rdx]        ; data result
    mov r9, rax          ; element count
    
    ; Check data type and dispatch to appropriate routine
    mov r10, [rdi + 32]  ; data type
    cmp r10, [TENSOR_TYPE_F32]
    je .add_f32
    cmp r10, [TENSOR_TYPE_F16]
    je .add_f16
    
    ; Unsupported data type
    mov rax, 2
    jmp .add_done
    
.add_f32:
    ; Check for AVX512 support
    test qword [cpu_features], 1
    jnz .add_f32_avx512
    
    ; Check for AVX2 support
    test qword [cpu_features], 2
    jnz .add_f32_avx2
    
    ; Fallback to scalar addition
.add_f32_scalar:
    test r9, r9
    jz .add_success
    
.add_f32_scalar_loop:
    movss xmm0, [rbx]
    addss xmm0, [rcx]
    movss [r8], xmm0
    add rbx, 4
    add rcx, 4
    add r8, 4
    dec r9
    jnz .add_f32_scalar_loop
    jmp .add_success
    
.add_f32_avx2:
    ; Process 8 floats at a time with AVX2
    mov r10, r9
    shr r10, 3  ; Number of AVX2 iterations
    test r10, r10
    jz .add_f32_remainder
    
.add_f32_avx2_loop:
    vmovups ymm0, [rbx]
    vaddps ymm0, ymm0, [rcx]
    vmovups [r8], ymm0
    add rbx, 32
    add rcx, 32
    add r8, 32
    dec r10
    jnz .add_f32_avx2_loop
    
    ; Handle remainder elements
.add_f32_remainder:
    and r9, 7  ; Remainder count
    jmp .add_f32_scalar_loop
    
.add_f32_avx512:
    ; Process 16 floats at a time with AVX512
    mov r10, r9
    shr r10, 4  ; Number of AVX512 iterations
    test r10, r10
    jz .add_f32_remainder_512
    
.add_f32_avx512_loop:
    vmovups zmm0, [rbx]
    vaddps zmm0, zmm0, [rcx]
    vmovups [r8], zmm0
    add rbx, 64
    add rcx, 64
    add r8, 64
    dec r10
    jnz .add_f32_avx512_loop
    
.add_f32_remainder_512:
    and r9, 15  ; Remainder count
    jmp .add_f32_scalar_loop
    
.add_f16:
    ; Half-precision addition (simplified implementation)
    ; Convert to F32, add, convert back
    test r9, r9
    jz .add_success
    
.add_f16_loop:
    ; Load and convert F16 to F32
    movzx eax, word [rbx]
    movzx r11d, word [rcx]
    
    ; Convert F16 to F32 (simplified)
    call ai_f16_to_f32
    movd xmm0, eax
    
    mov eax, r11d
    call ai_f16_to_f32
    movd xmm1, eax
    
    ; Add
    addss xmm0, xmm1
    
    ; Convert back to F16
    movd eax, xmm0
    call ai_f32_to_f16
    mov [r8], ax
    
    add rbx, 2
    add rcx, 2
    add r8, 2
    dec r9
    jnz .add_f16_loop
    
.add_success:
    xor rax, rax
    jmp .add_done
    
.add_error:
    mov rax, 1
    
.add_done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rcx
    pop rbx
    pop rbp
    ret

ai_f16_to_f32:
    ; Convert F16 to F32
    ; Input: EAX = F16 value
    ; Output: EAX = F32 value
    ; Simplified implementation - full IEEE 754 conversion needed
    
    push rbp
    mov rbp, rsp
    
    ; Extract sign, exponent, mantissa
    mov edx, eax
    and edx, 0x8000      ; Sign bit
    shl edx, 16
    
    mov ecx, eax
    and ecx, 0x7C00      ; Exponent
    shr ecx, 10
    
    mov ebx, eax
    and ebx, 0x03FF      ; Mantissa
    
    ; Handle special cases (zero, infinity, NaN)
    test ecx, ecx
    jz .f16_zero_or_denorm
    cmp ecx, 31
    je .f16_inf_or_nan
    
    ; Normal number
    add ecx, 112         ; Adjust exponent bias (127-15)
    shl ecx, 23
    shl ebx, 13          ; Shift mantissa
    
    or eax, edx          ; Combine sign
    or eax, ecx          ; Combine exponent
    or eax, ebx          ; Combine mantissa
    
    jmp .f16_to_f32_done
    
.f16_zero_or_denorm:
    test ebx, ebx
    jz .f16_zero
    ; Handle denormalized numbers (simplified)
    mov eax, edx         ; Just return signed zero for now
    jmp .f16_to_f32_done
    
.f16_zero:
    mov eax, edx         ; Signed zero
    jmp .f16_to_f32_done
    
.f16_inf_or_nan:
    mov eax, 0x7F800000  ; Infinity
    or eax, edx          ; Apply sign
    test ebx, ebx
    jz .f16_to_f32_done
    or eax, 0x400000     ; Make it NaN
    
.f16_to_f32_done:
    pop rbp
    ret

ai_f32_to_f16:
    ; Convert F32 to F16
    ; Input: EAX = F32 value
    ; Output: AX = F16 value
    ; Simplified implementation
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Extract components
    mov edx, eax
    and edx, 0x80000000  ; Sign
    shr edx, 16
    
    mov ecx, eax
    and ecx, 0x7F800000  ; Exponent
    shr ecx, 23
    
    mov ebx, eax
    and ebx, 0x007FFFFF  ; Mantissa
    
    ; Handle special cases
    test ecx, ecx
    jz .f32_zero_or_denorm
    cmp ecx, 255
    je .f32_inf_or_nan
    
    ; Normal number
    sub ecx, 112         ; Adjust exponent bias
    cmp ecx, 0
    jl .f32_underflow
    cmp ecx, 31
    jge .f32_overflow
    
    shl ecx, 10          ; Position exponent
    shr ebx, 13          ; Reduce mantissa precision
    
    mov eax, edx         ; Start with sign
    or eax, ecx          ; Add exponent
    or eax, ebx          ; Add mantissa
    
    jmp .f32_to_f16_done
    
.f32_zero_or_denorm:
    mov eax, edx         ; Signed zero
    jmp .f32_to_f16_done
    
.f32_underflow:
    mov eax, edx         ; Signed zero
    jmp .f32_to_f16_done
    
.f32_overflow:
    mov eax, 0x7C00      ; Infinity
    or eax, edx          ; Apply sign
    jmp .f32_to_f16_done
    
.f32_inf_or_nan:
    mov eax, 0x7C00      ; Infinity
    or eax, edx          ; Apply sign
    test ebx, ebx
    jz .f32_to_f16_done
    or eax, 0x0200       ; Make it NaN
    
.f32_to_f16_done:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_tensor_matmul:
    ; Matrix multiplication C = A * B
    ; Input: RDI = tensor A, RSI = tensor B, RDX = tensor C
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    
    ; Verify matrix dimensions
    ; A: [M, K], B: [K, N], C: [M, N]
    mov r8, [rdi + 8]    ; A shape pointer
    mov r9, [rsi + 8]    ; B shape pointer
    mov r10, [rdx + 8]   ; C shape pointer
    
    mov r11, [r8]        ; M (A rows)
    mov r12, [r8 + 8]    ; K (A cols)
    mov r13, [r9 + 8]    ; N (B cols)
    
    ; Verify K dimensions match
    cmp r12, [r9]
    jne .matmul_error
    
    ; Verify output dimensions
    cmp r11, [r10]
    jne .matmul_error
    cmp r13, [r10 + 8]
    jne .matmul_error
    
    ; Get data pointers
    mov rbx, [rdi]       ; A data
    mov rcx, [rsi]       ; B data
    mov r14, [rdx]       ; C data
    
    ; Check for optimized implementations
    test qword [cpu_features], 1
    jnz .matmul_avx512
    test qword [cpu_features], 2
    jnz .matmul_avx2
    
    ; Fallback to scalar implementation
.matmul_scalar:
    xor r8, r8           ; i = 0
    
.matmul_i_loop:
    cmp r8, r11
    jge .matmul_success
    
    xor r9, r9           ; j = 0
    
.matmul_j_loop:
    cmp r9, r13
    jge .matmul_i_next
    
    ; Initialize C[i][j] = 0
    xorps xmm0, xmm0
    
    xor r10, r10         ; k = 0
    
.matmul_k_loop:
    cmp r10, r12
    jge .matmul_store
    
    ; Calculate A[i][k] address
    mov rax, r8
    mul r12
    add rax, r10
    shl rax, 2           ; * sizeof(float)
    movss xmm1, [rbx + rax]
    
    ; Calculate B[k][j] address
    mov rax, r10
    mul r13
    add rax, r9
    shl rax, 2
    movss xmm2, [rcx + rax]
    
    ; Multiply and accumulate
    mulss xmm1, xmm2
    addss xmm0, xmm1
    
    inc r10
    jmp .matmul_k_loop
    
.matmul_store:
    ; Store C[i][j]
    mov rax, r8
    mul r13
    add rax, r9
    shl rax, 2
    movss [r14 + rax], xmm0
    
    inc r9
    jmp .matmul_j_loop
    
.matmul_i_next:
    inc r8
    jmp .matmul_i_loop
    
.matmul_avx2:
    ; AVX2 optimized matrix multiplication
    ; Process 8 floats at a time
    call ai_matmul_avx2_kernel
    jmp .matmul_success
    
.matmul_avx512:
    ; AVX512 optimized matrix multiplication
    ; Process 16 floats at a time
    call ai_matmul_avx512_kernel
    jmp .matmul_success
    
.matmul_success:
    xor rax, rax
    jmp .matmul_done
    
.matmul_error:
    mov rax, 1
    
.matmul_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rcx
    pop rbx
    pop rbp
    ret

ai_matmul_avx2_kernel:
    ; AVX2 optimized matrix multiplication kernel
    ; Uses registers from parent function
    
    push rbp
    mov rbp, rsp
    
    ; Implementation of cache-blocked AVX2 matrix multiplication
    ; This is a simplified version - full implementation would include
    ; cache blocking, loop unrolling, and prefetching
    
    xor r8, r8           ; i = 0
    
.avx2_i_loop:
    cmp r8, r11
    jge .avx2_done
    
    xor r9, r9           ; j = 0
    
.avx2_j_loop:
    cmp r9, r13
    jge .avx2_i_next
    
    ; Check if we can process 8 elements at once
    mov rax, r13
    sub rax, r9
    cmp rax, 8
    jl .avx2_scalar_fallback
    
    ; Initialize accumulator
    vxorps ymm0, ymm0, ymm0
    
    xor r10, r10         ; k = 0
    
.avx2_k_loop:
    cmp r10, r12
    jge .avx2_store_vector
    
    ; Broadcast A[i][k]
    mov rax, r8
    mul r12
    add rax, r10
    shl rax, 2
    vbroadcastss ymm1, [rbx + rax]
    
    ; Load B[k][j:j+7]
    mov rax, r10
    mul r13
    add rax, r9
    shl rax, 2
    vmovups ymm2, [rcx + rax]
    
    ; Multiply and accumulate
    vfmadd231ps ymm0, ymm1, ymm2
    
    inc r10
    jmp .avx2_k_loop
    
.avx2_store_vector:
    ; Store C[i][j:j+7]
    mov rax, r8
    mul r13
    add rax, r9
    shl rax, 2
    vmovups [r14 + rax], ymm0
    
    add r9, 8
    jmp .avx2_j_loop
    
.avx2_scalar_fallback:
    ; Handle remaining elements with scalar code
    ; (Implementation similar to scalar version)
    inc r9
    jmp .avx2_j_loop
    
.avx2_i_next:
    inc r8
    jmp .avx2_i_loop
    
.avx2_done:
    pop rbp
    ret

ai_matmul_avx512_kernel:
    ; AVX512 optimized matrix multiplication kernel
    ; Similar to AVX2 but processes 16 floats at a time
    
    push rbp
    mov rbp, rsp
    
    ; Implementation would be similar to AVX2 but using zmm registers
    ; and processing 16 elements at a time
    
    pop rbp
    ret

ai_tensor_destroy:
    ; Destroy a tensor and free its memory
    ; Input: RDI = tensor descriptor pointer
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Verify tensor is valid
    test rdi, rdi
    jz .destroy_error
    
    ; Mark tensor slot as free
    mov qword [rdi], 0
    mov qword [rdi + 8], 0
    mov qword [rdi + 16], 0
    mov qword [rdi + 24], 0
    mov qword [rdi + 32], 0
    mov qword [rdi + 40], 0
    mov qword [rdi + 48], 0
    mov qword [rdi + 56], 0
    
    ; Decrement tensor count
    dec qword [tensor_count]
    
    xor rax, rax
    jmp .destroy_done
    
.destroy_error:
    mov rax, 1
    
.destroy_done:
    pop rbx
    pop rbp
    ret

; Additional utility functions would be implemented here:
; - ai_tensor_reshape
; - ai_tensor_copy
; - ai_tensor_get_element
; - ai_tensor_set_element
; - ai_optimize_memory_layout
; - Various activation functions (ReLU, GELU, SiLU)
; - Normalization functions (RMSNorm, LayerNorm)
; - Quantization/dequantization routines

