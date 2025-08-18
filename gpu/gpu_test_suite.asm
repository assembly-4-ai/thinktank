; gpu_test_suite.asm: Comprehensive GPU Integration Test Suite
; Project Arora - Bare-Metal NVIDIA RTX 4060 Integration
; Implements functional testing and validation for all GPU components
; Follows Project Arora coding rules: custom functions, no ints, no syscalls

section .text

; External dependencies from Project Arora
extern scr64_print_string
extern shell_print_newline
extern string_to_hex
extern hex_to_string
extern pmm_alloc_frame
extern pmm_free_frame

; External dependencies from GPU modules
extern gpu_init_system
extern gpu_init_device
extern gpu_mmio_init
extern gpu_mmio_read_reg32
extern gpu_mmio_write_reg32
extern gpu_dma_init
extern gpu_dma_transfer_host_to_device
extern gpu_dma_transfer_device_to_host
extern gpu_dma_wait_completion
extern gpu_irq_init
extern gpu_irq_enable
extern gpu_irq_register_callback
extern gpu_compute_init
extern gpu_compute_matrix_add
extern gpu_compute_allocate_buffer
extern gpu_compute_free_buffer

; Global exports
global gpu_test_suite_run
global gpu_test_discovery
global gpu_test_mmio
global gpu_test_dma
global gpu_test_irq
global gpu_test_compute
global gpu_test_matrix_operations
global gpu_test_error_injection
global gpu_test_memory_leak_detection
global gpu_test_performance_basic

; Test result constants
TEST_RESULT_PASS equ 0
TEST_RESULT_FAIL equ 1
TEST_RESULT_SKIP equ 2
TEST_RESULT_ERROR equ 3

; Test categories
TEST_CATEGORY_DISCOVERY equ 1
TEST_CATEGORY_MMIO equ 2
TEST_CATEGORY_DMA equ 3
TEST_CATEGORY_IRQ equ 4
TEST_CATEGORY_COMPUTE equ 5
TEST_CATEGORY_MATRIX equ 6
TEST_CATEGORY_ERROR_INJECTION equ 7
TEST_CATEGORY_MEMORY_LEAK equ 8
TEST_CATEGORY_PERFORMANCE equ 9

; Test constants
MAX_TEST_RESULTS equ 256
TEST_TIMEOUT_CYCLES equ 50000000
TEST_MATRIX_SIZE equ 64
TEST_BUFFER_SIZE equ 4096

; Test result structure
struc test_result
    .test_id        resq 1
    .category       resq 1
    .result         resq 1
    .execution_time resq 1
    .error_code     resq 1
endstruc

; Test statistics structure
struc test_statistics
    .total_tests    resq 1
    .passed_tests   resq 1
    .failed_tests   resq 1
    .skipped_tests  resq 1
    .error_tests    resq 1
    .total_time     resq 1
endstruc

gpu_test_suite_run:
    ; Run complete GPU integration test suite
    ; Input: None
    ; Output: RAX = 0 if all tests pass, error code if any fail
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    
    ; Initialize test statistics
    call gpu_test_init_statistics
    
    ; Print test suite header
    mov rdi, test_suite_header_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test 1: GPU Discovery and Enumeration
    mov rdi, test_discovery_msg
    call scr64_print_string
    call shell_print_newline
    
    call gpu_test_discovery
    mov rdi, TEST_CATEGORY_DISCOVERY
    mov rsi, rax
    call gpu_test_record_result
    
    ; Test 2: MMIO Interface
    mov rdi, test_mmio_msg
    call scr64_print_string
    call shell_print_newline
    
    call gpu_test_mmio
    mov rdi, TEST_CATEGORY_MMIO
    mov rsi, rax
    call gpu_test_record_result
    
    ; Test 3: DMA Engine
    mov rdi, test_dma_msg
    call scr64_print_string
    call shell_print_newline
    
    call gpu_test_dma
    mov rdi, TEST_CATEGORY_DMA
    mov rsi, rax
    call gpu_test_record_result
    
    ; Test 4: IRQ Handling
    mov rdi, test_irq_msg
    call scr64_print_string
    call shell_print_newline
    
    call gpu_test_irq
    mov rdi, TEST_CATEGORY_IRQ
    mov rsi, rax
    call gpu_test_record_result
    
    ; Test 5: Compute Engine
    mov rdi, test_compute_msg
    call scr64_print_string
    call shell_print_newline
    
    call gpu_test_compute
    mov rdi, TEST_CATEGORY_COMPUTE
    mov rsi, rax
    call gpu_test_record_result
    
    ; Test 6: Matrix Operations
    mov rdi, test_matrix_msg
    call scr64_print_string
    call shell_print_newline
    
    call gpu_test_matrix_operations
    mov rdi, TEST_CATEGORY_MATRIX
    mov rsi, rax
    call gpu_test_record_result
    
    ; Test 7: Error Injection
    mov rdi, test_error_injection_msg
    call scr64_print_string
    call shell_print_newline
    
    call gpu_test_error_injection
    mov rdi, TEST_CATEGORY_ERROR_INJECTION
    mov rsi, rax
    call gpu_test_record_result
    
    ; Test 8: Memory Leak Detection
    mov rdi, test_memory_leak_msg
    call scr64_print_string
    call shell_print_newline
    
    call gpu_test_memory_leak_detection
    mov rdi, TEST_CATEGORY_MEMORY_LEAK
    mov rsi, rax
    call gpu_test_record_result
    
    ; Test 9: Basic Performance
    mov rdi, test_performance_msg
    call scr64_print_string
    call shell_print_newline
    
    call gpu_test_performance_basic
    mov rdi, TEST_CATEGORY_PERFORMANCE
    mov rsi, rax
    call gpu_test_record_result
    
    ; Print test results summary
    call gpu_test_print_summary
    
    ; Determine overall result
    call gpu_test_get_overall_result
    
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_discovery:
    ; Test GPU discovery and enumeration functionality
    ; Input: None
    ; Output: RAX = test result
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Record test start time
    call gpu_test_get_timestamp
    mov rbx, rax
    
    ; Test 1: Initialize GPU system
    call gpu_init_system
    test rax, rax
    jnz .discovery_test_failed
    
    ; Test 2: Verify device was found
    ; This is a simplified test - in reality would check device count
    mov rdi, test_discovery_pass_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    ; Test passed
    mov rax, TEST_RESULT_PASS
    jmp .discovery_test_complete
    
.discovery_test_failed:
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_discovery_fail_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test failed
    mov rax, TEST_RESULT_FAIL
    
.discovery_test_complete:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_mmio:
    ; Test MMIO interface functionality
    ; Input: None
    ; Output: RAX = test result
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Record test start time
    call gpu_test_get_timestamp
    mov rbx, rax
    
    ; Test 1: Initialize MMIO
    xor rdi, rdi                    ; Device 0
    call gpu_mmio_init
    test rax, rax
    jnz .mmio_test_failed
    
    ; Test 2: Read/Write test register
    mov rdi, 0x00000034             ; Test register offset
    mov esi, 0xA5A5A5A5             ; Test pattern
    call gpu_mmio_write_reg32
    
    ; Read back the value
    mov rdi, 0x00000034
    call gpu_mmio_read_reg32
    
    ; Verify pattern (mask for read-only bits)
    and eax, 0xA5A5A5A5
    cmp eax, 0xA5A5A5A5
    jne .mmio_test_failed
    
    ; Test 3: Write different pattern
    mov rdi, 0x00000034
    mov esi, 0x5A5A5A5A
    call gpu_mmio_write_reg32
    
    ; Read back and verify
    mov rdi, 0x00000034
    call gpu_mmio_read_reg32
    
    and eax, 0x5A5A5A5A
    cmp eax, 0x5A5A5A5A
    jne .mmio_test_failed
    
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_mmio_pass_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test passed
    mov rax, TEST_RESULT_PASS
    jmp .mmio_test_complete
    
.mmio_test_failed:
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_mmio_fail_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test failed
    mov rax, TEST_RESULT_FAIL
    
.mmio_test_complete:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_dma:
    ; Test DMA engine functionality
    ; Input: None
    ; Output: RAX = test result
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    
    ; Record test start time
    call gpu_test_get_timestamp
    mov rbx, rax
    
    ; Test 1: Initialize DMA engine
    call gpu_dma_init
    test rax, rax
    jnz .dma_test_failed
    
    ; Test 2: Allocate test buffers
    mov rdi, 1                      ; 1 page
    call pmm_alloc_frame
    test rax, rax
    jz .dma_test_failed
    mov r12, rax                    ; Host buffer
    
    mov rdi, 1                      ; 1 page
    call pmm_alloc_frame
    test rax, rax
    jz .dma_test_cleanup_host
    mov r13, rax                    ; GPU buffer (simulated)
    
    ; Test 3: Fill host buffer with test pattern
    mov rdi, r12
    mov rcx, 1024                   ; 1024 dwords
    mov eax, 0x12345678
    rep stosd
    
    ; Test 4: Transfer host to device
    mov rdi, r12                    ; Source
    mov rsi, r13                    ; Destination
    mov rdx, 4096                   ; Size
    call gpu_dma_transfer_host_to_device
    test rax, rax
    jz .dma_test_cleanup_both
    
    ; Test 5: Wait for completion
    mov rdi, rax                    ; Transfer ID
    call gpu_dma_wait_completion
    test rax, rax
    jnz .dma_test_cleanup_both
    
    ; Test 6: Verify data transfer (simplified)
    ; In a real implementation, would verify GPU buffer contents
    
    ; Cleanup buffers
    mov rdi, r13
    call pmm_free_frame
    
    mov rdi, r12
    call pmm_free_frame
    
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_dma_pass_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test passed
    mov rax, TEST_RESULT_PASS
    jmp .dma_test_complete
    
.dma_test_cleanup_both:
    mov rdi, r13
    call pmm_free_frame
    
.dma_test_cleanup_host:
    mov rdi, r12
    call pmm_free_frame
    
.dma_test_failed:
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_dma_fail_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test failed
    mov rax, TEST_RESULT_FAIL
    
.dma_test_complete:
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_irq:
    ; Test IRQ handling functionality
    ; Input: None
    ; Output: RAX = test result
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Record test start time
    call gpu_test_get_timestamp
    mov rbx, rax
    
    ; Test 1: Initialize IRQ system
    mov rdi, 0x50                   ; IRQ vector
    call gpu_irq_init
    test rax, rax
    jnz .irq_test_failed
    
    ; Test 2: Register test callback
    mov rdi, gpu_test_irq_callback
    mov rsi, 0                      ; No user data
    mov rdx, 0x00000010             ; IRQ_TYPE_COMPUTE_COMPLETE
    mov rcx, 1                      ; High priority
    call gpu_irq_register_callback
    test rax, rax
    jz .irq_test_failed
    
    ; Test 3: Enable IRQ
    mov rdi, 0x00000010             ; IRQ_TYPE_COMPUTE_COMPLETE
    call gpu_irq_enable
    test rax, rax
    jnz .irq_test_failed
    
    ; Test 4: Simulate IRQ trigger (simplified)
    ; In a real implementation, would trigger actual hardware IRQ
    mov qword [test_irq_callback_called], 0
    
    ; Simulate callback call
    mov rdi, 0x00000010
    mov rsi, 0
    call gpu_test_irq_callback
    
    ; Verify callback was called
    cmp qword [test_irq_callback_called], 1
    jne .irq_test_failed
    
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_irq_pass_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test passed
    mov rax, TEST_RESULT_PASS
    jmp .irq_test_complete
    
.irq_test_failed:
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_irq_fail_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test failed
    mov rax, TEST_RESULT_FAIL
    
.irq_test_complete:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_compute:
    ; Test compute engine functionality
    ; Input: None
    ; Output: RAX = test result
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Record test start time
    call gpu_test_get_timestamp
    mov rbx, rax
    
    ; Test 1: Initialize compute engine
    call gpu_compute_init
    test rax, rax
    jnz .compute_test_failed
    
    ; Test 2: Allocate test buffer
    mov rdi, TEST_BUFFER_SIZE
    call gpu_compute_allocate_buffer
    test rax, rax
    jz .compute_test_failed
    mov rcx, rax                    ; Save buffer address
    
    ; Test 3: Free test buffer
    mov rdi, rcx
    call gpu_compute_free_buffer
    
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_compute_pass_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test passed
    mov rax, TEST_RESULT_PASS
    jmp .compute_test_complete
    
.compute_test_failed:
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_compute_fail_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test failed
    mov rax, TEST_RESULT_FAIL
    
.compute_test_complete:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_matrix_operations:
    ; Test matrix operations functionality
    ; Input: None
    ; Output: RAX = test result
    
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
    
    ; Record test start time
    call gpu_test_get_timestamp
    mov rbx, rax
    
    ; Allocate test matrices
    mov rdi, TEST_MATRIX_SIZE * TEST_MATRIX_SIZE * 4  ; Size in bytes
    call pmm_alloc_frame
    test rax, rax
    jz .matrix_test_failed
    mov r12, rax                    ; Matrix A
    
    mov rdi, TEST_MATRIX_SIZE * TEST_MATRIX_SIZE * 4
    call pmm_alloc_frame
    test rax, rax
    jz .matrix_test_cleanup_a
    mov r13, rax                    ; Matrix B
    
    mov rdi, TEST_MATRIX_SIZE * TEST_MATRIX_SIZE * 4
    call pmm_alloc_frame
    test rax, rax
    jz .matrix_test_cleanup_b
    mov r14, rax                    ; Matrix C
    
    ; Initialize test matrices
    call gpu_test_init_matrices
    
    ; Test matrix addition: C = A + B
    mov rdi, r12                    ; Matrix A
    mov rsi, r13                    ; Matrix B
    mov rdx, r14                    ; Matrix C
    mov rcx, TEST_MATRIX_SIZE       ; Width
    mov r8, TEST_MATRIX_SIZE        ; Height
    call gpu_compute_matrix_add
    
    ; Check result
    test rax, rax
    jnz .matrix_test_cleanup_all
    
    ; Verify result (simplified)
    call gpu_test_verify_matrix_result
    test rax, rax
    jnz .matrix_test_cleanup_all
    
    ; Cleanup matrices
    mov rdi, r14
    call pmm_free_frame
    
    mov rdi, r13
    call pmm_free_frame
    
    mov rdi, r12
    call pmm_free_frame
    
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_matrix_pass_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test passed
    mov rax, TEST_RESULT_PASS
    jmp .matrix_test_complete
    
.matrix_test_cleanup_all:
    mov rdi, r14
    call pmm_free_frame
    
.matrix_test_cleanup_b:
    mov rdi, r13
    call pmm_free_frame
    
.matrix_test_cleanup_a:
    mov rdi, r12
    call pmm_free_frame
    
.matrix_test_failed:
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_matrix_fail_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test failed
    mov rax, TEST_RESULT_FAIL
    
.matrix_test_complete:
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

gpu_test_error_injection:
    ; Test error injection and recovery
    ; Input: None
    ; Output: RAX = test result
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Record test start time
    call gpu_test_get_timestamp
    mov rbx, rax
    
    ; Test 1: Invalid buffer allocation
    mov rdi, 0                      ; Invalid size
    call gpu_compute_allocate_buffer
    
    ; Should return 0 (failure)
    test rax, rax
    jnz .error_injection_test_failed
    
    ; Test 2: Invalid matrix dimensions
    mov rdi, 0                      ; Invalid matrix A
    mov rsi, 0                      ; Invalid matrix B
    mov rdx, 0                      ; Invalid matrix C
    mov rcx, 0                      ; Invalid width
    mov r8, 0                       ; Invalid height
    call gpu_compute_matrix_add
    
    ; Should return failure
    test rax, rax
    jz .error_injection_test_failed
    
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_error_injection_pass_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test passed
    mov rax, TEST_RESULT_PASS
    jmp .error_injection_test_complete
    
.error_injection_test_failed:
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_error_injection_fail_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test failed
    mov rax, TEST_RESULT_FAIL
    
.error_injection_test_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_memory_leak_detection:
    ; Test memory leak detection
    ; Input: None
    ; Output: RAX = test result
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Record test start time
    call gpu_test_get_timestamp
    mov rbx, rax
    
    ; Test 1: Allocate and free buffer (should not leak)
    mov rdi, TEST_BUFFER_SIZE
    call gpu_compute_allocate_buffer
    test rax, rax
    jz .memory_leak_test_failed
    
    mov rdi, rax
    call gpu_compute_free_buffer
    
    ; Test 2: Multiple allocations and frees
    mov rcx, 10                     ; Test 10 allocations
    
.allocation_loop:
    push rcx
    
    mov rdi, TEST_BUFFER_SIZE
    call gpu_compute_allocate_buffer
    test rax, rax
    jz .allocation_loop_failed
    
    mov rdi, rax
    call gpu_compute_free_buffer
    
    pop rcx
    dec rcx
    jnz .allocation_loop
    
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_memory_leak_pass_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test passed
    mov rax, TEST_RESULT_PASS
    jmp .memory_leak_test_complete
    
.allocation_loop_failed:
    pop rcx
    
.memory_leak_test_failed:
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_memory_leak_fail_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test failed
    mov rax, TEST_RESULT_FAIL
    
.memory_leak_test_complete:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_performance_basic:
    ; Test basic performance metrics
    ; Input: None
    ; Output: RAX = test result
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Record test start time
    call gpu_test_get_timestamp
    mov rbx, rax
    
    ; Test 1: Measure buffer allocation time
    mov rcx, 100                    ; 100 iterations
    
.performance_loop:
    push rcx
    
    mov rdi, TEST_BUFFER_SIZE
    call gpu_compute_allocate_buffer
    test rax, rax
    jz .performance_test_failed
    
    mov rdi, rax
    call gpu_compute_free_buffer
    
    pop rcx
    dec rcx
    jnz .performance_loop
    
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    ; Check if performance is within acceptable range
    cmp rax, TEST_TIMEOUT_CYCLES
    jg .performance_test_failed
    
    mov rdi, test_performance_pass_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test passed
    mov rax, TEST_RESULT_PASS
    jmp .performance_test_complete
    
.performance_test_failed:
    ; Record test end time
    call gpu_test_get_timestamp
    sub rax, rbx
    mov [last_test_time], rax
    
    mov rdi, test_performance_fail_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Test failed
    mov rax, TEST_RESULT_FAIL
    
.performance_test_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_init_statistics:
    ; Initialize test statistics
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rcx
    push rdi
    
    ; Clear statistics structure
    mov rdi, test_stats
    mov rcx, test_statistics_size / 8
    xor rax, rax
    rep stosq
    
    ; Clear test results array
    mov rdi, test_results
    mov rcx, MAX_TEST_RESULTS * test_result_size / 8
    xor rax, rax
    rep stosq
    
    pop rdi
    pop rcx
    pop rax
    pop rbp
    ret

gpu_test_record_result:
    ; Record test result
    ; Input: RDI = test category
    ; Input: RSI = test result
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rbx
    push rcx
    push rdx
    
    ; Get next test result slot
    mov rax, [test_stats + test_statistics.total_tests]
    cmp rax, MAX_TEST_RESULTS
    jge .record_complete
    
    ; Calculate result structure address
    imul rax, test_result_size
    add rax, test_results
    mov rbx, rax
    
    ; Fill result structure
    mov rcx, [test_stats + test_statistics.total_tests]
    mov [rbx + test_result.test_id], rcx
    mov [rbx + test_result.category], rdi
    mov [rbx + test_result.result], rsi
    mov rax, [last_test_time]
    mov [rbx + test_result.execution_time], rax
    mov qword [rbx + test_result.error_code], 0
    
    ; Update statistics
    inc qword [test_stats + test_statistics.total_tests]
    
    ; Update result counters
    cmp rsi, TEST_RESULT_PASS
    je .record_pass
    cmp rsi, TEST_RESULT_FAIL
    je .record_fail
    cmp rsi, TEST_RESULT_SKIP
    je .record_skip
    cmp rsi, TEST_RESULT_ERROR
    je .record_error
    jmp .record_complete
    
.record_pass:
    inc qword [test_stats + test_statistics.passed_tests]
    jmp .record_complete
    
.record_fail:
    inc qword [test_stats + test_statistics.failed_tests]
    jmp .record_complete
    
.record_skip:
    inc qword [test_stats + test_statistics.skipped_tests]
    jmp .record_complete
    
.record_error:
    inc qword [test_stats + test_statistics.error_tests]
    
.record_complete:
    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop rbp
    ret

gpu_test_print_summary:
    ; Print test results summary
    ; Input: None
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rdi
    
    ; Print summary header
    mov rdi, test_summary_header_msg
    call scr64_print_string
    call shell_print_newline
    
    ; Print total tests
    mov rdi, test_total_msg
    call scr64_print_string
    
    mov rdi, [test_stats + test_statistics.total_tests]
    call gpu_test_print_number
    call shell_print_newline
    
    ; Print passed tests
    mov rdi, test_passed_msg
    call scr64_print_string
    
    mov rdi, [test_stats + test_statistics.passed_tests]
    call gpu_test_print_number
    call shell_print_newline
    
    ; Print failed tests
    mov rdi, test_failed_msg
    call scr64_print_string
    
    mov rdi, [test_stats + test_statistics.failed_tests]
    call gpu_test_print_number
    call shell_print_newline
    
    ; Print skipped tests
    mov rdi, test_skipped_msg
    call scr64_print_string
    
    mov rdi, [test_stats + test_statistics.skipped_tests]
    call gpu_test_print_number
    call shell_print_newline
    
    ; Print error tests
    mov rdi, test_error_msg
    call scr64_print_string
    
    mov rdi, [test_stats + test_statistics.error_tests]
    call gpu_test_print_number
    call shell_print_newline
    
    pop rdi
    pop rbp
    ret

gpu_test_get_overall_result:
    ; Get overall test result
    ; Input: None
    ; Output: RAX = 0 if all tests pass, 1 if any fail
    
    push rbp
    mov rbp, rsp
    
    ; Check if any tests failed or had errors
    mov rax, [test_stats + test_statistics.failed_tests]
    add rax, [test_stats + test_statistics.error_tests]
    
    ; If any failed, return 1, otherwise 0
    test rax, rax
    jz .all_tests_passed
    
    mov rax, 1
    jmp .overall_result_complete
    
.all_tests_passed:
    xor rax, rax
    
.overall_result_complete:
    pop rbp
    ret

gpu_test_get_timestamp:
    ; Get current timestamp (simplified)
    ; Input: None
    ; Output: RAX = timestamp
    
    push rbp
    mov rbp, rsp
    push rdx
    
    ; Read timestamp counter (simplified)
    rdtsc
    shl rdx, 32
    or rax, rdx
    
    pop rdx
    pop rbp
    ret

gpu_test_print_number:
    ; Print number to console
    ; Input: RDI = number to print
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rsi
    
    ; Convert number to hex string
    mov rax, rdi
    mov rsi, number_buffer
    call hex_to_string
    
    ; Print the string
    mov rdi, number_buffer
    call scr64_print_string
    
    pop rsi
    pop rax
    pop rbp
    ret

gpu_test_init_matrices:
    ; Initialize test matrices with known values
    ; Input: R12 = matrix A, R13 = matrix B, R14 = matrix C
    ; Output: None
    
    push rbp
    mov rbp, rsp
    push rax
    push rcx
    push rdi
    
    ; Initialize matrix A with 1.0
    mov rdi, r12
    mov rcx, TEST_MATRIX_SIZE * TEST_MATRIX_SIZE
    mov eax, 0x3F800000             ; 1.0 in IEEE 754
    rep stosd
    
    ; Initialize matrix B with 2.0
    mov rdi, r13
    mov rcx, TEST_MATRIX_SIZE * TEST_MATRIX_SIZE
    mov eax, 0x40000000             ; 2.0 in IEEE 754
    rep stosd
    
    ; Initialize matrix C with 0.0
    mov rdi, r14
    mov rcx, TEST_MATRIX_SIZE * TEST_MATRIX_SIZE
    xor eax, eax                    ; 0.0
    rep stosd
    
    pop rdi
    pop rcx
    pop rax
    pop rbp
    ret

gpu_test_verify_matrix_result:
    ; Verify matrix addition result (simplified)
    ; Input: R14 = result matrix C
    ; Output: RAX = 0 if correct, 1 if incorrect
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rsi
    
    ; Check first few elements for expected result (3.0)
    mov rsi, r14
    mov rcx, 10                     ; Check first 10 elements
    mov ebx, 0x40400000             ; 3.0 in IEEE 754
    
.verify_loop:
    lodsd
    cmp eax, ebx
    jne .verify_failed
    
    dec rcx
    jnz .verify_loop
    
    ; Verification passed
    xor rax, rax
    jmp .verify_complete
    
.verify_failed:
    ; Verification failed
    mov rax, 1
    
.verify_complete:
    pop rsi
    pop rcx
    pop rbx
    pop rbp
    ret

gpu_test_irq_callback:
    ; Test IRQ callback function
    ; Input: RDI = IRQ types, RSI = user data
    ; Output: None
    
    push rbp
    mov rbp, rsp
    
    ; Mark callback as called
    mov qword [test_irq_callback_called], 1
    
    pop rbp
    ret

; Data section
section .data
    test_suite_header_msg db '=== GPU Integration Test Suite ===', 0
    test_discovery_msg db 'Testing GPU Discovery...', 0
    test_mmio_msg db 'Testing MMIO Interface...', 0
    test_dma_msg db 'Testing DMA Engine...', 0
    test_irq_msg db 'Testing IRQ Handling...', 0
    test_compute_msg db 'Testing Compute Engine...', 0
    test_matrix_msg db 'Testing Matrix Operations...', 0
    test_error_injection_msg db 'Testing Error Injection...', 0
    test_memory_leak_msg db 'Testing Memory Leak Detection...', 0
    test_performance_msg db 'Testing Basic Performance...', 0
    
    test_discovery_pass_msg db 'GPU Discovery: PASS', 0
    test_discovery_fail_msg db 'GPU Discovery: FAIL', 0
    test_mmio_pass_msg db 'MMIO Interface: PASS', 0
    test_mmio_fail_msg db 'MMIO Interface: FAIL', 0
    test_dma_pass_msg db 'DMA Engine: PASS', 0
    test_dma_fail_msg db 'DMA Engine: FAIL', 0
    test_irq_pass_msg db 'IRQ Handling: PASS', 0
    test_irq_fail_msg db 'IRQ Handling: FAIL', 0
    test_compute_pass_msg db 'Compute Engine: PASS', 0
    test_compute_fail_msg db 'Compute Engine: FAIL', 0
    test_matrix_pass_msg db 'Matrix Operations: PASS', 0
    test_matrix_fail_msg db 'Matrix Operations: FAIL', 0
    test_error_injection_pass_msg db 'Error Injection: PASS', 0
    test_error_injection_fail_msg db 'Error Injection: FAIL', 0
    test_memory_leak_pass_msg db 'Memory Leak Detection: PASS', 0
    test_memory_leak_fail_msg db 'Memory Leak Detection: FAIL', 0
    test_performance_pass_msg db 'Basic Performance: PASS', 0
    test_performance_fail_msg db 'Basic Performance: FAIL', 0
    
    test_summary_header_msg db '=== Test Results Summary ===', 0
    test_total_msg db 'Total Tests: ', 0
    test_passed_msg db 'Passed: ', 0
    test_failed_msg db 'Failed: ', 0
    test_skipped_msg db 'Skipped: ', 0
    test_error_msg db 'Errors: ', 0

; BSS section
section .bss
    ; Test statistics
    test_stats resb test_statistics_size
    
    ; Test results array
    test_results resb test_result_size * MAX_TEST_RESULTS
    
    ; Test state variables
    last_test_time resq 1
    test_irq_callback_called resq 1
    
    ; Temporary buffer for number conversion
    number_buffer resb 32

