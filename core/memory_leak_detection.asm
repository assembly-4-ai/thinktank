; memory_leak_detection.asm: Memory leak detection for Project Arora testing
; Implements tracking of memory allocations and deallocations

BITS 64
default rel

; Export memory tracking functions
global init_memory_tracking
global track_allocation
global track_deallocation
global report_memory_leaks
global reset_memory_tracking

; External dependencies
extern scr64_print_string
extern scr64_print_hex
extern scr64_print_dec

section .rodata
    ; Memory tracking messages
    msg_memory_tracking_init db "Initializing memory leak detection...", 0Dh, 0Ah, 0
    msg_memory_tracking_reset db "Memory tracking reset", 0Dh, 0Ah, 0
    msg_allocation_tracked db "Allocation tracked: ", 0
    msg_deallocation_tracked db "Deallocation tracked: ", 0
    msg_leak_report_header db "Memory Leak Report:", 0Dh, 0Ah, 0
    msg_no_leaks db "No memory leaks detected", 0Dh, 0Ah, 0
    msg_leak_detected db "LEAK DETECTED: ", 0
    msg_bytes db " bytes at address ", 0
    msg_allocation_count db "Total allocations: ", 0
    msg_deallocation_count db "Total deallocations: ", 0
    msg_bytes_allocated db "Total bytes allocated: ", 0
    msg_bytes_leaked db "Total bytes leaked: ", 0
    msg_newline db 0Dh, 0Ah, 0

section .data
    ; Memory tracking state
    tracking_enabled dd 0
    allocation_count dd 0
    deallocation_count dd 0
    total_bytes_allocated dq 0
    total_bytes_leaked dq 0
    
    ; Maximum number of allocations to track
    MAX_ALLOCATIONS equ 1024
    
    ; Current index in tracking arrays
    current_index dd 0

section .bss
    ; Arrays to track allocations and deallocations
    allocation_addresses resq MAX_ALLOCATIONS
    allocation_sizes resq MAX_ALLOCATIONS
    deallocation_addresses resq MAX_ALLOCATIONS
    
    ; Bitmap to track which allocations have been freed
    allocation_freed resb MAX_ALLOCATIONS

section .text

;--------------------------------------------------------------------------
; init_memory_tracking: Initialize memory leak detection
; Input: None
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
init_memory_tracking:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    
    ; Print initialization message
    lea rsi, [rel msg_memory_tracking_init]
    call scr64_print_string
    
    ; Reset tracking state
    mov dword [rel tracking_enabled], 1
    mov dword [rel allocation_count], 0
    mov dword [rel deallocation_count], 0
    mov qword [rel total_bytes_allocated], 0
    mov qword [rel total_bytes_leaked], 0
    mov dword [rel current_index], 0
    
    ; Clear tracking arrays
    lea rdi, [rel allocation_addresses]
    xor rax, rax
    mov rcx, MAX_ALLOCATIONS
    rep stosq
    
    lea rdi, [rel allocation_sizes]
    xor rax, rax
    mov rcx, MAX_ALLOCATIONS
    rep stosq
    
    lea rdi, [rel deallocation_addresses]
    xor rax, rax
    mov rcx, MAX_ALLOCATIONS
    rep stosq
    
    lea rdi, [rel allocation_freed]
    xor rax, rax
    mov rcx, MAX_ALLOCATIONS
    rep stosb
    
    ; Return success
    xor rax, rax
    
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; track_allocation: Track a memory allocation
; Input: RDI = Address, RSI = Size in bytes
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
track_allocation:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Check if tracking is enabled
    cmp dword [rel tracking_enabled], 0
    je .skip_tracking
    
    ; Check if we've reached the maximum number of allocations
    mov ebx, [rel current_index]
    cmp ebx, MAX_ALLOCATIONS
    jge .skip_tracking
    
    ; Store allocation information
    lea rax, [rel allocation_addresses]
    mov [rax + rbx * 8], rdi
    
    lea rax, [rel allocation_sizes]
    mov [rax + rbx * 8], rsi
    
    ; Mark as not freed
    lea rax, [rel allocation_freed]
    mov byte [rax + rbx], 0
    
    ; Update counters
    inc dword [rel allocation_count]
    add [rel total_bytes_allocated], rsi
    inc dword [rel current_index]
    
    ; Debug output if needed
    ; lea rsi, [rel msg_allocation_tracked]
    ; call scr64_print_string
    ; mov rsi, rdi
    ; call scr64_print_hex
    ; lea rsi, [rel msg_newline]
    ; call scr64_print_string
    
.skip_tracking:
    ; Return success
    xor rax, rax
    
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; track_deallocation: Track a memory deallocation
; Input: RDI = Address
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
track_deallocation:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    
    ; Check if tracking is enabled
    cmp dword [rel tracking_enabled], 0
    je .skip_tracking
    
    ; Find the allocation in our tracking array
    xor rbx, rbx
    mov r12d, [rel current_index]
    
.find_loop:
    cmp rbx, r12
    jge .not_found
    
    lea rax, [rel allocation_addresses]
    cmp [rax + rbx * 8], rdi
    je .found
    
    inc rbx
    jmp .find_loop
    
.found:
    ; Mark as freed
    lea rax, [rel allocation_freed]
    mov byte [rax + rbx], 1
    
    ; Update counters
    inc dword [rel deallocation_count]
    
    ; Debug output if needed
    ; lea rsi, [rel msg_deallocation_tracked]
    ; call scr64_print_string
    ; mov rsi, rdi
    ; call scr64_print_hex
    ; lea rsi, [rel msg_newline]
    ; call scr64_print_string
    
    jmp .skip_tracking
    
.not_found:
    ; This could be a deallocation of something we didn't track
    ; or a double free - in a real system we might want to report this
    
.skip_tracking:
    ; Return success
    xor rax, rax
    
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; report_memory_leaks: Generate a report of memory leaks
; Input: None
; Output: RAX = Number of leaks detected
;--------------------------------------------------------------------------
report_memory_leaks:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    
    ; Check if tracking is enabled
    cmp dword [rel tracking_enabled], 0
    je .no_leaks
    
    ; Print report header
    lea rsi, [rel msg_leak_report_header]
    call scr64_print_string
    
    ; Print allocation statistics
    lea rsi, [rel msg_allocation_count]
    call scr64_print_string
    mov esi, [rel allocation_count]
    call scr64_print_dec
    lea rsi, [rel msg_newline]
    call scr64_print_string
    
    lea rsi, [rel msg_deallocation_count]
    call scr64_print_string
    mov esi, [rel deallocation_count]
    call scr64_print_dec
    lea rsi, [rel msg_newline]
    call scr64_print_string
    
    lea rsi, [rel msg_bytes_allocated]
    call scr64_print_string
    mov rsi, [rel total_bytes_allocated]
    call scr64_print_dec
    lea rsi, [rel msg_newline]
    call scr64_print_string
    
    ; Reset leak counter
    mov qword [rel total_bytes_leaked], 0
    xor r14, r14  ; Leak counter
    
    ; Scan for leaks
    xor rbx, rbx
    mov r12d, [rel current_index]
    
.scan_loop:
    cmp rbx, r12
    jge .scan_done
    
    ; Check if this allocation was freed
    lea rax, [rel allocation_freed]
    movzx r13, byte [rax + rbx]
    test r13, r13
    jnz .next_allocation
    
    ; This is a leak - report it
    lea rsi, [rel msg_leak_detected]
    call scr64_print_string
    
    ; Print size
    lea rax, [rel allocation_sizes]
    mov rsi, [rax + rbx * 8]
    call scr64_print_dec
    
    ; Add to total leaked bytes
    add [rel total_bytes_leaked], rsi
    
    ; Print address
    lea rsi, [rel msg_bytes]
    call scr64_print_string
    lea rax, [rel allocation_addresses]
    mov rsi, [rax + rbx * 8]
    call scr64_print_hex
    lea rsi, [rel msg_newline]
    call scr64_print_string
    
    ; Increment leak counter
    inc r14
    
.next_allocation:
    inc rbx
    jmp .scan_loop
    
.scan_done:
    ; Print total bytes leaked
    lea rsi, [rel msg_bytes_leaked]
    call scr64_print_string
    mov rsi, [rel total_bytes_leaked]
    call scr64_print_dec
    lea rsi, [rel msg_newline]
    call scr64_print_string
    
    ; Check if we found any leaks
    test r14, r14
    jnz .return_leaks
    
    ; No leaks found
    lea rsi, [rel msg_no_leaks]
    call scr64_print_string
    xor rax, rax
    jmp .done
    
.no_leaks:
    ; Tracking not enabled
    xor rax, rax
    jmp .done
    
.return_leaks:
    ; Return number of leaks
    mov rax, r14
    
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

;--------------------------------------------------------------------------
; reset_memory_tracking: Reset memory tracking state
; Input: None
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
reset_memory_tracking:
    push rbp
    mov rbp, rsp
    
    ; Print reset message
    lea rsi, [rel msg_memory_tracking_reset]
    call scr64_print_string
    
    ; Reset tracking state
    mov dword [rel allocation_count], 0
    mov dword [rel deallocation_count], 0
    mov qword [rel total_bytes_allocated], 0
    mov qword [rel total_bytes_leaked], 0
    mov dword [rel current_index], 0
    
    ; Clear tracking arrays
    lea rdi, [rel allocation_addresses]
    xor rax, rax
    mov rcx, MAX_ALLOCATIONS
    rep stosq
    
    lea rdi, [rel allocation_sizes]
    xor rax, rax
    mov rcx, MAX_ALLOCATIONS
    rep stosq
    
    lea rdi, [rel deallocation_addresses]
    xor rax, rax
    mov rcx, MAX_ALLOCATIONS
    rep stosq
    
    lea rdi, [rel allocation_freed]
    xor rax, rax
    mov rcx, MAX_ALLOCATIONS
    rep stosb
    
    ; Return success
    xor rax, rax
    
    pop rbp
    ret

;--------------------------------------------------------------------------
; Hooks for memory allocation/deallocation functions
;--------------------------------------------------------------------------

; Hook for pmm_alloc_frame to track allocations
; This would be called by a modified version of the test harness
global pmm_alloc_frame_track
pmm_alloc_frame_track:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Save original parameter
    mov rbx, rdi
    
    ; Call the real allocation function
    call pmm_alloc_frame
    
    ; Check if allocation succeeded
    test rax, rax
    jz .done
    
    ; Track the allocation
    mov rdi, rax  ; Address
    mov rsi, 4096  ; Size (page size)
    call track_allocation
    
.done:
    pop rbx
    pop rbp
    ret

; Hook for pmm_free_frame to track deallocations
; This would be called by a modified version of the test harness
global pmm_free_frame_track
pmm_free_frame_track:
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Save original parameter
    mov rbx, rdi
    
    ; Track the deallocation before it happens
    call track_deallocation
    
    ; Call the real deallocation function
    mov rdi, rbx
    call pmm_free_frame
    
    pop rbx
    pop rbp
    ret

extern pmm_alloc_frame
extern pmm_free_frame


