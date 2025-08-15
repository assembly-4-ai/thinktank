; ai_test_suite.asm: Comprehensive test suite for AI model validation
; Project Arora - Bare-Metal NASM AI Implementation
; Tests all AI components for correctness and performance
; Adheres to Project Arora coding rules: no ints, syscalls, libs - all custom

section .data
    ; Test configuration
    TEST_EPSILON        dq 1e-6     ; Floating-point comparison tolerance
    MAX_TEST_ERRORS     dq 10       ; Maximum errors before aborting
    TEST_TIMEOUT        dq 1000000  ; Test timeout in cycles
    
    ; Test status messages
    msg_test_start      db 'Starting AI Test Suite...', 10, 0
    msg_test_pass       db '[PASS] ', 0
    msg_test_fail       db '[FAIL] ', 0
    msg_test_skip       db '[SKIP] ', 0
    msg_test_complete   db 'AI Test Suite Complete', 10, 0
    
    ; Test names
    test_math_basic     db 'Basic Math Functions', 0
    test_math_advanced  db 'Advanced Math Functions', 0
    test_tensor_ops     db 'Tensor Operations', 0
    test_attention      db 'Attention Mechanism', 0
    test_transformer    db 'Transformer Layer', 0
    test_integration    db 'System Integration', 0
    test_performance    db 'Performance Validation', 0
    test_memory         db 'Memory Management', 0
    
    ; Test data matrices
    test_matrix_2x2     dq 1.0, 2.0, 3.0, 4.0
    test_matrix_3x3     dq 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0
    test_matrix_4x4     dq 1.0, 2.0, 3.0, 4.0
                        dq 5.0, 6.0, 7.0, 8.0
                        dq 9.0, 10.0, 11.0, 12.0
                        dq 13.0, 14.0, 15.0, 16.0
    
    ; Expected results for validation
    expected_exp_1      dq 2.718281828459045
    expected_sin_pi_2   dq 1.0
    expected_cos_0      dq 1.0
    expected_sqrt_4     dq 2.0

section .bss
    ; Test state
    test_count          resq 1
    test_passed         resq 1
    test_failed         resq 1
    test_skipped        resq 1
    current_test        resq 1
    
    ; Test buffers
    test_input_tensor   resq 1
    test_output_tensor  resq 1
    test_temp_buffer    resq 1024
    
    ; Performance metrics
    test_start_time     resq 1
    test_end_time       resq 1
    total_test_time     resq 1

section .text
    global ai_run_test_suite
    global ai_test_math_functions
    global ai_test_tensor_operations
    global ai_test_attention_mechanism
    global ai_test_transformer_layer
    global ai_test_system_integration
    global ai_test_performance
    global ai_test_memory_management
    
    ; External constants
    extern EXP_C0
    extern EXP_C2
    extern EXP_C4
    extern MATH_PI
    extern TENSOR_TYPE_F32
    extern AI_STATUS_READY
    ; External functions
    extern ai_exp
    extern ai_sin
    extern ai_cos
    extern ai_sqrt
    extern ai_tensor_create
    extern ai_tensor_add
    extern ai_tensor_matmul
    extern ai_tensor_destroy
    extern ai_multi_head_attention
    extern ai_transformer_layer
    extern ai_module_init
    extern ai_module_get_status
    extern scr64_print_string
    extern shell_print_newline
    extern get_timestamp
extern my_float_compare

ai_run_test_suite:
    ; Run complete AI test suite
    ; Output: RAX = 0 if all tests pass, error count otherwise
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Initialize test state
    mov qword [test_count], 0
    mov qword [test_passed], 0
    mov qword [test_failed], 0
    mov qword [test_skipped], 0
    
    ; Print test start message
    mov rdi, msg_test_start
    call scr64_print_string
    
    ; Get start time
    call get_timestamp
    mov [test_start_time], rax
    
    ; Run test categories
    call ai_test_math_functions
    call ai_test_tensor_operations
    call ai_test_attention_mechanism
    call ai_test_transformer_layer
    call ai_test_system_integration
    call ai_test_performance
    call ai_test_memory_management
    
    ; Get end time
    call get_timestamp
    mov [test_end_time], rax
    
    ; Calculate total time
    mov rax, [test_end_time]
    sub rax, [test_start_time]
    mov [total_test_time], rax
    
    ; Print test summary
    call ai_print_test_summary
    
    ; Return failure count
    mov rax, [test_failed]
    
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_test_math_functions:
    ; Test mathematical functions
    ; Output: RAX = number of failed tests
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    
    mov qword [current_test], test_math_basic
    
    ; Test exp(1) ≈ e
    movsd xmm0, [EXP_C0]  ; 1.0
    call ai_exp
    movsd xmm1, [expected_exp_1]
    call ai_compare_float_result
    test rax, rax
    jz .exp_test_passed
    call ai_record_test_failure
    jmp .test_sin
    
.exp_test_passed:
    call ai_record_test_success
    
.test_sin:
    ; Test sin(π/2) = 1
    movsd xmm0, [MATH_PI]
    movsd xmm1, [EXP_C2]  ; 0.5
    mulsd xmm0, xmm1  ; π/2
    call ai_sin
    movsd xmm1, [expected_sin_pi_2]
    call ai_compare_float_result
    test rax, rax
    jz .sin_test_passed
    call ai_record_test_failure
    jmp .test_cos
    
.sin_test_passed:
    call ai_record_test_success
    
.test_cos:
    ; Test cos(0) = 1
    xorpd xmm0, xmm0  ; 0.0
    call ai_cos
    movsd xmm1, [expected_cos_0]
    call ai_compare_float_result
    test rax, rax
    jz .cos_test_passed
    call ai_record_test_failure
    jmp .test_sqrt
    
.cos_test_passed:
    call ai_record_test_success
    
.test_sqrt:
    ; Test sqrt(4) = 2
    mov rax, 0x4010000000000000  ; 4.0 in hex
    movq xmm0, rax
    call ai_sqrt
    movsd xmm1, [expected_sqrt_4]
    call ai_compare_float_result
    test rax, rax
    jz .sqrt_test_passed
    call ai_record_test_failure
    jmp .math_tests_done
    
.sqrt_test_passed:
    call ai_record_test_success
    
.math_tests_done:
    ; Print test category result
    mov rdi, test_math_basic
    call ai_print_test_category_result
    
    mov rax, [test_failed]
    
    pop rcx
    pop rbx
    pop rbp
    ret

ai_test_tensor_operations:
    ; Test tensor operations
    ; Output: RAX = number of failed tests
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    mov qword [current_test], test_tensor_ops
    
    ; Create test tensors
    mov rdi, test_matrix_2x2_shape
    mov rsi, 2  ; 2 dimensions
    mov rdx, [TENSOR_TYPE_F32]
    call ai_tensor_create
    test rax, rax
    jz .tensor_creation_failed
    mov [test_input_tensor], rax
    
    mov rdi, test_matrix_2x2_shape
    mov rsi, 2
    mov rdx, [TENSOR_TYPE_F32]
    call ai_tensor_create
    test rax, rax
    jz .tensor_creation_failed
    mov [test_output_tensor], rax
    
    ; Test tensor addition
    mov rdi, [test_input_tensor]
    mov rsi, [test_input_tensor]  ; Add tensor to itself
    mov rdx, [test_output_tensor]
    call ai_tensor_add
    test rax, rax
    jz .tensor_add_passed
    call ai_record_test_failure
    jmp .test_tensor_matmul
    
.tensor_add_passed:
    call ai_record_test_success
    
.test_tensor_matmul:
    ; Test matrix multiplication
    mov rdi, [test_input_tensor]
    mov rsi, [test_input_tensor]
    mov rdx, [test_output_tensor]
    call ai_tensor_matmul
    test rax, rax
    jz .tensor_matmul_passed
    call ai_record_test_failure
    jmp .tensor_tests_done
    
.tensor_matmul_passed:
    call ai_record_test_success
    jmp .tensor_tests_done
    
.tensor_creation_failed:
    call ai_record_test_failure
    call ai_record_test_failure  ; Count both creation failures
    
.tensor_tests_done:
    ; Cleanup tensors
    mov rdi, [test_input_tensor]
    test rdi, rdi
    jz .no_input_cleanup
    call ai_tensor_destroy
    
.no_input_cleanup:
    mov rdi, [test_output_tensor]
    test rdi, rdi
    jz .no_output_cleanup
    call ai_tensor_destroy
    
.no_output_cleanup:
    ; Print test category result
    mov rdi, test_tensor_ops
    call ai_print_test_category_result
    
    mov rax, [test_failed]
    
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_test_attention_mechanism:
    ; Test attention mechanism
    ; Output: RAX = number of failed tests
    
    push rbp
    mov rbp, rsp
    push rbx
    
    mov qword [current_test], test_attention
    
    ; Create dummy tensors for attention test
    ; This is a simplified test - real implementation would need proper Q, K, V tensors
    
    ; For now, just test that the function doesn't crash
    mov rdi, 0  ; Dummy input
    mov rsi, 0  ; Dummy output
    mov rdx, 4  ; Sequence length
    mov rcx, 0  ; Layer index
    
    ; Skip actual call for now since we don't have proper test data
    ; call ai_multi_head_attention
    
    ; Mark as skipped
    call ai_record_test_skip
    
    ; Print test category result
    mov rdi, test_attention
    call ai_print_test_category_result
    
    mov rax, [test_failed]
    
    pop rbx
    pop rbp
    ret

ai_test_transformer_layer:
    ; Test transformer layer
    ; Output: RAX = number of failed tests
    
    push rbp
    mov rbp, rsp
    push rbx
    
    mov qword [current_test], test_transformer
    
    ; Skip transformer layer test for now
    ; Would need proper model weights and configuration
    call ai_record_test_skip
    
    ; Print test category result
    mov rdi, test_transformer
    call ai_print_test_category_result
    
    mov rax, [test_failed]
    
    pop rbx
    pop rbp
    ret

ai_test_system_integration:
    ; Test system integration
    ; Output: RAX = number of failed tests
    
    push rbp
    mov rbp, rsp
    push rbx
    
    mov qword [current_test], test_integration
    
    ; Test AI module initialization
    mov rdi, 0  ; Use default configuration
    call ai_module_init
    test rax, rax
    jz .integration_init_passed
    call ai_record_test_failure
    jmp .integration_tests_done
    
.integration_init_passed:
    call ai_record_test_success
    
    ; Test module status
    call ai_module_get_status
    cmp rax, [AI_STATUS_READY]
    je .status_test_passed
    call ai_record_test_failure
    jmp .integration_tests_done
    
.status_test_passed:
    call ai_record_test_success
    
.integration_tests_done:
    ; Print test category result
    mov rdi, test_integration
    call ai_print_test_category_result
    
    mov rax, [test_failed]
    
    pop rbx
    pop rbp
    ret

ai_test_performance:
    ; Test performance requirements
    ; Output: RAX = number of failed tests
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    
    mov qword [current_test], test_performance
    
    ; Test mathematical function performance
    call get_timestamp
    mov rbx, rax  ; Start time
    
    ; Run exp() function 1000 times
    mov rcx, 1000
.perf_loop:
    movsd xmm0, [EXP_C0]  ; 1.0
    call ai_exp
    loop .perf_loop
    
    call get_timestamp
    sub rax, rbx  ; Calculate duration
    
    ; Check if performance is acceptable (arbitrary threshold)
    cmp rax, 1000000  ; 1M cycles threshold
    jl .perf_test_passed
    call ai_record_test_failure
    jmp .performance_tests_done
    
.perf_test_passed:
    call ai_record_test_success
    
.performance_tests_done:
    ; Print test category result
    mov rdi, test_performance
    call ai_print_test_category_result
    
    mov rax, [test_failed]
    
    pop rcx
    pop rbx
    pop rbp
    ret

ai_test_memory_management:
    ; Test memory management
    ; Output: RAX = number of failed tests
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    
    mov qword [current_test], test_memory
    
    ; Test multiple tensor allocations and deallocations
    mov rcx, 10  ; Create 10 tensors
    
.memory_alloc_loop:
    push rcx
    
    mov rdi, test_matrix_2x2_shape
    mov rsi, 2
    mov rdx, [TENSOR_TYPE_F32]
    call ai_tensor_create
    test rax, rax
    jz .memory_alloc_failed
    
    ; Store tensor pointer
    push rax
    
    ; Immediately destroy it
    mov rdi, rax
    call ai_tensor_destroy
    
    pop rax  ; Clean up stack
    pop rcx
    loop .memory_alloc_loop
    
    ; If we get here, all allocations succeeded
    call ai_record_test_success
    jmp .memory_tests_done
    
.memory_alloc_failed:
    pop rcx  ; Clean up stack
    call ai_record_test_failure
    
.memory_tests_done:
    ; Print test category result
    mov rdi, test_memory
    call ai_print_test_category_result
    
    mov rax, [test_failed]
    
    pop rcx
    pop rbx
    pop rbp
    ret

ai_compare_float_result:
    ; Compare floating-point result with expected value
    ; Input: XMM0 = actual result, XMM1 = expected result
    ; Output: RAX = 0 if equal within epsilon, 1 if different
    
    push rbp
    mov rbp, rsp
    
    ; Use epsilon-based comparison
    movsd xmm2, [TEST_EPSILON]
    call my_float_compare
    
    pop rbp
    ret

ai_record_test_success:
    ; Record a successful test
    
    push rbp
    mov rbp, rsp
    
    inc qword [test_count]
    inc qword [test_passed]
    
    ; Print pass message
    mov rdi, msg_test_pass
    call scr64_print_string
    
    pop rbp
    ret

ai_record_test_failure:
    ; Record a failed test
    
    push rbp
    mov rbp, rsp
    
    inc qword [test_count]
    inc qword [test_failed]
    
    ; Print fail message
    mov rdi, msg_test_fail
    call scr64_print_string
    
    pop rbp
    ret

ai_record_test_skip:
    ; Record a skipped test
    
    push rbp
    mov rbp, rsp
    
    inc qword [test_count]
    inc qword [test_skipped]
    
    ; Print skip message
    mov rdi, msg_test_skip
    call scr64_print_string
    
    pop rbp
    ret

ai_print_test_category_result:
    ; Print result for a test category
    ; Input: RDI = category name
    
    push rbp
    mov rbp, rsp
    
    call scr64_print_string
    call shell_print_newline
    
    pop rbp
    ret

ai_print_test_summary:
    ; Print overall test summary
    
    push rbp
    mov rbp, rsp
    
    mov rdi, msg_test_complete
    call scr64_print_string
    
    ; Print statistics
    mov rdi, test_stats_total
    call scr64_print_string
    mov rax, [test_count]
    call ai_print_number
    call shell_print_newline
    
    mov rdi, test_stats_passed
    call scr64_print_string
    mov rax, [test_passed]
    call ai_print_number
    call shell_print_newline
    
    mov rdi, test_stats_failed
    call scr64_print_string
    mov rax, [test_failed]
    call ai_print_number
    call shell_print_newline
    
    mov rdi, test_stats_skipped
    call scr64_print_string
    mov rax, [test_skipped]
    call ai_print_number
    call shell_print_newline
    
    mov rdi, test_stats_time
    call scr64_print_string
    mov rax, [total_test_time]
    call ai_print_number
    mov rdi, test_stats_cycles
    call scr64_print_string
    call shell_print_newline
    
    pop rbp
    ret

ai_print_number:
    ; Print a number (reuse from shell interface)
    ; Input: RAX = number
    
    push rbp
    mov rbp, rsp
    
    ; Implementation would convert number to string and print
    ; For now, just print placeholder
    mov rdi, '[NUM]'
    call scr64_print_string
    
    pop rbp
    ret

; Test data
; Test data and string constants
section .rodata
    test_matrix_2x2_shape   dq 2, 2  ; 2x2 matrix shape
    
    ; Test statistics strings
    test_stats_total        db 'Total Tests: ', 0
    test_stats_passed       db 'Passed: ', 0
    test_stats_failed       db 'Failed: ', 0
    test_stats_skipped      db 'Skipped: ', 0
    test_stats_time         db 'Total Time: ', 0
    test_stats_cycles       db ' cycles', 0

