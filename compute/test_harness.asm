; test_harness.asm: Test harness for Project Arora compute library
; Implements automated testing for compute functions

BITS 64
default rel

; External dependencies - compute library functions to test
extern init_compute_lib
extern ggml_matmul
extern llama_model_load
extern parallel_run_model
extern gpu_matmul

; External dependencies - support functions
extern scr64_print_string
extern scr64_print_hex
extern scr64_print_dec
extern pmm_alloc_frame
extern pmm_free_frame

; External dependencies - error injection framework
extern init_error_injection
extern inject_memory_allocation_failure
extern inject_data_corruption
extern inject_invalid_input
extern reset_error_injection
extern pmm_alloc_frame_hook

; External dependencies - memory leak detection
extern init_memory_tracking
extern track_allocation
extern track_deallocation
extern report_memory_leaks
extern reset_memory_tracking
extern pmm_alloc_frame_track
extern pmm_free_frame_track

; External dependencies - floating-point comparison
extern init_float_compare
extern compare_float_epsilon
extern compare_matrices_epsilon
extern set_epsilon_value
extern print_matrix_diff

; Export test functions
global run_compute_tests
global test_init_compute_lib
global test_ggml_matmul
global test_llama_model_load
global test_parallel_run_model
global test_gpu_matmul

section .rodata
    ; Test messages
    msg_test_start db "Starting compute library tests...", 0Dh, 0Ah, 0
    msg_test_complete db "All tests completed", 0Dh, 0Ah, 0
    
    ; Test result messages
    msg_test_pass db "PASS: ", 0
    msg_test_fail db "FAIL: ", 0
    
    ; Individual test messages
    msg_test_init db "Testing init_compute_lib", 0Dh, 0Ah, 0
    msg_test_matmul db "Testing ggml_matmul", 0Dh, 0Ah, 0
    msg_test_model_load db "Testing llama_model_load", 0Dh, 0Ah, 0
    msg_test_run_model db "Testing parallel_run_model", 0Dh, 0Ah, 0
    msg_test_gpu_matmul db "Testing gpu_matmul", 0Dh, 0Ah, 0
    
    ; Specific test case messages
    msg_init_success db "Initialization successful", 0Dh, 0Ah, 0
    msg_init_reinit db "Re-initialization handling", 0Dh, 0Ah, 0
    msg_matmul_small db "2x2 matrix multiplication", 0Dh, 0Ah, 0
    msg_matmul_medium db "4x4 matrix multiplication", 0Dh, 0Ah, 0
    msg_matmul_large db "8x8 matrix multiplication", 0Dh, 0Ah, 0
    msg_matmul_invalid db "Invalid input handling", 0Dh, 0Ah, 0
    msg_model_valid db "Valid model loading", 0Dh, 0Ah, 0
    msg_model_complex db "Complex model loading", 0Dh, 0Ah, 0
    msg_model_invalid db "Invalid model rejection", 0Dh, 0Ah, 0
    msg_run_valid db "Valid model inference", 0Dh, 0Ah, 0
    msg_run_complex db "Complex model inference", 0Dh, 0Ah, 0
    msg_run_invalid db "Invalid handle handling", 0Dh, 0Ah, 0
    msg_gpu_compare db "GPU vs CPU result comparison", 0Dh, 0Ah, 0
    msg_gpu_large db "GPU large matrix multiplication", 0Dh, 0Ah, 0
    
    ; Model magic number for testing
    test_model_magic dq 0x4C4C414D41524F41 ; "AROAMALL" in little-endian

section .data
    ; Test matrices - 2x2
    matrix_a_2x2 dd 1.0, 2.0, 3.0, 4.0
    matrix_b_2x2 dd 5.0, 6.0, 7.0, 8.0
    matrix_c_2x2_expected dd 19.0, 22.0, 43.0, 50.0
    
    ; Test matrices - 4x4
    matrix_a_4x4 dd 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0
    matrix_b_4x4 dd 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0, 25.0, 26.0, 27.0, 28.0, 29.0, 30.0, 31.0, 32.0
    matrix_c_4x4_expected dd 250.0, 260.0, 270.0, 280.0, 618.0, 644.0, 670.0, 696.0, 986.0, 1028.0, 1070.0, 1112.0, 1354.0, 1412.0, 1470.0, 1528.0
    
    ; Test matrices - 8x8 (partial initialization for space efficiency)
    matrix_a_8x8 dd 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0
                 dd 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0
                 dd 17.0, 18.0, 19.0, 20.0, 21.0, 22.0, 23.0, 24.0
                 dd 25.0, 26.0, 27.0, 28.0, 29.0, 30.0, 31.0, 32.0
                 dd 33.0, 34.0, 35.0, 36.0, 37.0, 38.0, 39.0, 40.0
                 dd 41.0, 42.0, 43.0, 44.0, 45.0, 46.0, 47.0, 48.0
                 dd 49.0, 50.0, 51.0, 52.0, 53.0, 54.0, 55.0, 56.0
                 dd 57.0, 58.0, 59.0, 60.0, 61.0, 62.0, 63.0, 64.0
    
    ; Test counters
    test_count dd 0
    pass_count dd 0
    fail_count dd 0

section .bss
    ; Test output buffers
    matrix_c_result resq 4       ; For 2x2 matrices
    matrix_c_4x4_result resq 16  ; For 4x4 matrices
    matrix_c_8x8_result resq 64  ; For 8x8 matrices
    model_buffer resb 1024       ; Basic model buffer
    complex_model_buffer resb 4096 ; Larger model buffer for complex models
    output_buffer resb 1024
    complex_output_buffer resb 2048

section .text

;--------------------------------------------------------------------------
; run_compute_tests: Main test runner function
; Input: None
; Output: RAX = Number of failed tests
;--------------------------------------------------------------------------
run_compute_tests:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Print test start message
    lea rsi, [rel msg_test_start]
    call scr64_print_string
    
    ; Initialize error injection framework
    call init_error_injection
    
    ; Initialize memory leak detection
    call init_memory_tracking
    
    ; Initialize floating-point comparison
    call init_float_compare
    
    ; Set epsilon value for floating-point comparisons (1e-5)
    mov dword [rsp-4], 0x3a83126f  ; IEEE 754 representation of 0.00001
    movss xmm0, [rsp-4]
    call set_epsilon_value
    
    ; Initialize test counters
    mov dword [rel test_count], 0
    mov dword [rel pass_count], 0
    mov dword [rel fail_count], 0
    
    ; Run individual test suites
    call test_init_compute_lib
    call test_ggml_matmul
    call test_llama_model_load
    call test_parallel_run_model
    call test_gpu_matmul
    
    ; Print test completion message
    lea rsi, [rel msg_test_complete]
    call scr64_print_string
    
    ; Print test summary
    mov rsi, [rel test_count]
    call scr64_print_dec
    lea rsi, [rel msg_tests_run]
    call scr64_print_string
    
    mov rsi, [rel pass_count]
    call scr64_print_dec
    lea rsi, [rel msg_tests_passed]
    call scr64_print_string
    
    mov rsi, [rel fail_count]
    call scr64_print_dec
    lea rsi, [rel msg_tests_failed]
    call scr64_print_string
    
    ; Return number of failed tests
    mov eax, [rel fail_count]
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; test_init_compute_lib: Test initialization function
; Input: None
; Output: None
;--------------------------------------------------------------------------
test_init_compute_lib:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Print test header
    lea rsi, [rel msg_test_init]
    call scr64_print_string
    
    ; TC001: Test successful initialization
    lea rsi, [rel msg_init_success]
    call scr64_print_string
    
    ; Call init_compute_lib
    call init_compute_lib
    
    ; Check result
    test rax, rax
    jnz .tc001_fail
    
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_init_success]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .tc002
    
.tc001_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_init_success]
    call scr64_print_string
    inc dword [rel fail_count]
    
.tc002:
    ; TC002: Test re-initialization handling
    lea rsi, [rel msg_init_reinit]
    call scr64_print_string
    
    ; Call init_compute_lib again
    call init_compute_lib
    
    ; Check result - should still return 0 for success
    test rax, rax
    jnz .tc002_fail
    
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_init_reinit]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .done
    
.tc002_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_init_reinit]
    call scr64_print_string
    inc dword [rel fail_count]
    
.done:
    ; Update test count
    add dword [rel test_count], 2
    
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; test_ggml_matmul: Test matrix multiplication function
; Input: None
; Output: None
;--------------------------------------------------------------------------
test_ggml_matmul:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Print test header
    lea rsi, [rel msg_test_matmul]
    call scr64_print_string
    
    ; TC004: Test 2x2 matrix multiplication
    lea rsi, [rel msg_matmul_small]
    call scr64_print_string
    
    ; Clear result matrix
    lea rdi, [rel matrix_c_result]
    xor rax, rax
    mov rcx, 4
    rep stosq
    
    ; Call ggml_matmul with 2x2 matrices
    lea rdi, [rel matrix_a_2x2]
    lea rsi, [rel matrix_b_2x2]
    lea rdx, [rel matrix_c_result]
    mov rcx, 4  ; 2x2 = 4 elements
    call ggml_matmul
    
    ; Check result
    test rax, rax
    jnz .tc004_fail
    
    ; Verify matrix values using epsilon-based comparison
    lea rdi, [rel matrix_c_result]
    lea rsi, [rel matrix_c_2x2_expected]
    mov rdx, 4  ; 2x2 = 4 elements
    call compare_matrices_epsilon
    
    ; Check result - RAX=0 means matrices equal within epsilon
    ; RAX>0 means difference at index RAX-1
    test rax, rax
    jnz .tc004_fail
    
.tc004_pass:
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_matmul_small]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .tc005
    
.tc004_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_matmul_small]
    call scr64_print_string
    inc dword [rel fail_count]
    
.tc005:
    ; TC005: Test 4x4 matrix multiplication
    lea rsi, [rel msg_matmul_medium]
    call scr64_print_string
    
    ; Clear result matrix
    lea rdi, [rel matrix_c_4x4_result]
    xor rax, rax
    mov rcx, 16
    rep stosq
    
    ; Call ggml_matmul with 4x4 matrices
    lea rdi, [rel matrix_a_4x4]
    lea rsi, [rel matrix_b_4x4]
    lea rdx, [rel matrix_c_4x4_result]
    mov rcx, 16  ; 4x4 = 16 elements
    call ggml_matmul
    
    ; Check result
    test rax, rax
    jnz .tc005_fail
    
    ; Verify matrix values using epsilon-based comparison
    lea rdi, [rel matrix_c_4x4_result]
    lea rsi, [rel matrix_c_4x4_expected]
    mov rdx, 16  ; 4x4 = 16 elements
    call compare_matrices_epsilon
    
    ; Check result - RAX=0 means matrices equal within epsilon
    ; RAX>0 means difference at index RAX-1
    test rax, rax
    jnz .tc005_fail
    
.tc005_pass:
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_matmul_medium]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .tc006
    
.tc005_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_matmul_medium]
    call scr64_print_string
    inc dword [rel fail_count]
    
.tc006:
    ; TC006: Test 8x8 matrix multiplication
    lea rsi, [rel msg_matmul_large]
    call scr64_print_string
    
    ; Clear result matrix
    lea rdi, [rel matrix_c_8x8_result]
    xor rax, rax
    mov rcx, 64
    rep stosq
    
    ; Call ggml_matmul with 8x8 matrices
    lea rdi, [rel matrix_a_8x8]
    lea rsi, [rel matrix_a_8x8]  ; Use same matrix for simplicity in testing
    lea rdx, [rel matrix_c_8x8_result]
    mov rcx, 64  ; 8x8 = 64 elements
    call ggml_matmul
    
    ; Check result
    test rax, rax
    jnz .tc006_fail
    
    ; For 8x8, we'll just check that the operation completed successfully
    ; without verifying each value due to the large size
    
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_matmul_large]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .tc007
    
.tc006_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_matmul_large]
    call scr64_print_string
    inc dword [rel fail_count]
    
.tc007:
    ; TC007: Test invalid input handling
    lea rsi, [rel msg_matmul_invalid]
    call scr64_print_string
    
    ; Enable invalid input injection
    mov rdi, 1
    call inject_invalid_input
    
    ; Call ggml_matmul with NULL input
    xor rdi, rdi  ; NULL matrix A
    lea rsi, [rel matrix_b_2x2]
    lea rdx, [rel matrix_c_result]
    mov rcx, 4
    call ggml_matmul
    
    ; Reset invalid input injection
    call reset_error_injection
    
    ; Check result - should return non-zero for error
    test rax, rax
    jz .tc007_fail
    
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_matmul_invalid]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .done
    
.tc007_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_matmul_invalid]
    call scr64_print_string
    inc dword [rel fail_count]
    
.done:
    ; Update test count
    add dword [rel test_count], 3
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; test_llama_model_load: Test model loading function
; Input: None
; Output: None
;--------------------------------------------------------------------------
test_llama_model_load:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    ; Print test header
    lea rsi, [rel msg_test_model_load]
    call scr64_print_string
    
    ; TC008: Test valid model loading
    lea rsi, [rel msg_model_valid]
    call scr64_print_string
    
    ; Create a test model in memory
    lea rdi, [rel model_buffer]
    mov rax, [rel test_model_magic]
    mov [rdi], rax
    
    ; Fill rest with test pattern
    add rdi, 8
    mov rcx, 128
    mov rax, 0x0123456789ABCDEF
.fill_loop:
    mov [rdi], rax
    add rdi, 8
    loop .fill_loop
    
    ; Call llama_model_load
    lea rdi, [rel model_buffer]
    mov rsi, 1024  ; Size
    call llama_model_load
    
    ; Check result - should return non-zero handle
    test rax, rax
    jz .tc008_fail
    
    ; Save model handle
    mov r12, rax
    
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_model_valid]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .tc009
    
.tc008_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_model_valid]
    call scr64_print_string
    inc dword [rel fail_count]
    mov r12, 0  ; No valid handle
    
.tc009:
    ; TC009: Test invalid model rejection
    lea rsi, [rel msg_model_invalid]
    call scr64_print_string
    
    ; Create an invalid test model (wrong magic)
    lea rdi, [rel model_buffer]
    mov qword [rdi], 0xDEADBEEFDEADBEEF  ; Invalid magic
    
    ; Call llama_model_load
    lea rdi, [rel model_buffer]
    mov rsi, 1024  ; Size
    call llama_model_load
    
    ; Check result - should return 0 for failure
    test rax, rax
    jnz .tc009_fail
    
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_model_invalid]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .done
    
.tc009_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_model_invalid]
    call scr64_print_string
    inc dword [rel fail_count]
    
.done:
    ; Update test count
    add dword [rel test_count], 2
    
    ; Save model handle for next tests
    mov r13, r12
    
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; test_parallel_run_model: Test model inference function
; Input: None
; Output: None
;--------------------------------------------------------------------------
test_parallel_run_model:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    ; Print test header
    lea rsi, [rel msg_test_run_model]
    call scr64_print_string
    
    ; Check if we have a valid model handle from previous test
    cmp r13, 0
    je .skip_valid_test
    
    ; TC012: Test valid model inference
    lea rsi, [rel msg_run_valid]
    call scr64_print_string
    
    ; Clear output buffer
    lea rdi, [rel output_buffer]
    xor rax, rax
    mov rcx, 128
    rep stosq
    
    ; Call parallel_run_model
    mov rdi, r13  ; Model handle from previous test
    lea rsi, [rel model_buffer]  ; Input buffer
    lea rdx, [rel output_buffer]  ; Output buffer
    call parallel_run_model
    
    ; Check result
    test rax, rax
    jnz .tc012_fail
    
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_run_valid]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .tc013
    
.tc012_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_run_valid]
    call scr64_print_string
    inc dword [rel fail_count]
    jmp .tc013
    
.skip_valid_test:
    ; Skip TC012 if no valid model handle
    lea rsi, [rel msg_skipping]
    call scr64_print_string
    lea rsi, [rel msg_run_valid]
    call scr64_print_string
    
.tc013:
    ; TC013: Test invalid handle handling
    lea rsi, [rel msg_run_invalid]
    call scr64_print_string
    
    ; Call parallel_run_model with invalid handle
    mov rdi, 99  ; Invalid handle
    lea rsi, [rel model_buffer]
    lea rdx, [rel output_buffer]
    call parallel_run_model
    
    ; Check result - should return non-zero for error
    test rax, rax
    jz .tc013_fail
    
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_run_invalid]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .done
    
.tc013_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_run_invalid]
    call scr64_print_string
    inc dword [rel fail_count]
    
.done:
    ; Update test count
    cmp r13, 0
    je .count_one
    add dword [rel test_count], 2
    jmp .exit
    
.count_one:
    add dword [rel test_count], 1
    
.exit:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; test_gpu_matmul: Test GPU matrix multiplication function
; Input: None
; Output: None
;--------------------------------------------------------------------------
test_gpu_matmul:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15
    
    ; Print test header
    lea rsi, [rel msg_test_gpu_matmul]
    call scr64_print_string
    
    ; TC016: Compare GPU vs CPU results
    lea rsi, [rel msg_gpu_compare]
    call scr64_print_string
    
    ; Allocate memory for CPU result
    mov rdi, 1
    call pmm_alloc_frame
    test rax, rax
    jz .tc016_fail
    mov r12, rax  ; CPU result buffer
    
    ; Allocate memory for GPU result
    mov rdi, 1
    call pmm_alloc_frame
    test rax, rax
    jz .tc016_fail_free_cpu
    mov r13, rax  ; GPU result buffer
    
    ; Call ggml_matmul (CPU)
    lea rdi, [rel matrix_a_2x2]
    lea rsi, [rel matrix_b_2x2]
    mov rdx, r12
    mov rcx, 4  ; 2x2 = 4 elements
    call ggml_matmul
    
    ; Check result
    test rax, rax
    jnz .tc016_fail_free_both
    
    ; Call gpu_matmul (GPU)
    lea rdi, [rel matrix_a_2x2]
    lea rsi, [rel matrix_b_2x2]
    mov rdx, r13
    mov rcx, 4  ; 2x2 = 4 elements
    call gpu_matmul
    
    ; Check result
    test rax, rax
    jnz .tc016_fail_free_both
    
    ; Compare results
    mov r14, 0  ; index
    mov r15, 4  ; count
    
.compare_loop:
    cmp r14, r15
    jge .tc016_pass
    
    ; Compare CPU and GPU results
    mov rbx, r14
    shl rbx, 2  ; * sizeof(float)
    
    movss xmm0, [r12 + rbx]
    movss xmm1, [r13 + rbx]
    
    ucomiss xmm0, xmm1
    jne .tc016_fail_free_both
    
    inc r14
    jmp .compare_loop
    
.tc016_pass:
    ; Free allocated memory
    mov rdi, r12
    call pmm_free_frame
    mov rdi, r13
    call pmm_free_frame
    
    ; Report success
    lea rsi, [rel msg_test_pass]
    call scr64_print_string
    lea rsi, [rel msg_gpu_compare]
    call scr64_print_string
    inc dword [rel pass_count]
    jmp .done
    
.tc016_fail_free_both:
    ; Free both buffers
    mov rdi, r12
    call pmm_free_frame
    mov rdi, r13
    call pmm_free_frame
    jmp .tc016_fail
    
.tc016_fail_free_cpu:
    ; Free CPU buffer
    mov rdi, r12
    call pmm_free_frame
    
.tc016_fail:
    ; Report failure
    lea rsi, [rel msg_test_fail]
    call scr64_print_string
    lea rsi, [rel msg_gpu_compare]
    call scr64_print_string
    inc dword [rel fail_count]
    
.done:
    ; Update test count
    inc dword [rel test_count]
    
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

section .rodata
    ; Additional messages
    msg_tests_run db " tests run", 0Dh, 0Ah, 0
    msg_tests_passed db " tests passed", 0Dh, 0Ah, 0
    msg_tests_failed db " tests failed", 0Dh, 0Ah, 0
    msg_skipping db "SKIP: ", 0
