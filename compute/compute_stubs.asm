; compute_stubs.asm: Stub implementations for compute library functions
; These stubs allow the build to complete while the actual implementations
; are pending in the TODO list

BITS 64
default rel

; Export compute function stubs
global ggml_matmul
global llama_model_load
global parallel_run_model
global gpu_matmul

; External dependencies
extern scr64_print_string

section .rodata
    msg_ggml_matmul_stub db "STUB: ggml_matmul called", 0Dh, 0Ah, 0
    msg_llama_model_load_stub db "STUB: llama_model_load called", 0Dh, 0Ah, 0
    msg_parallel_run_model_stub db "STUB: parallel_run_model called", 0Dh, 0Ah, 0
    msg_gpu_matmul_stub db "STUB: gpu_matmul called", 0Dh, 0Ah, 0

section .text

;--------------------------------------------------------------------------
; ggml_matmul: Stub implementation for matrix multiplication
; Input: RDI = Matrix A, RSI = Matrix B, RDX = Result Matrix C, RCX = Size
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
ggml_matmul:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rdx
    push rcx
    
    ; Print stub message
    mov rsi, msg_ggml_matmul_stub
    call scr64_print_string
    
    ; Return success
    xor rax, rax
    
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    ret

;--------------------------------------------------------------------------
; llama_model_load: Stub implementation for loading LLM model
; Input: RDI = Buffer address, RSI = Size in bytes
; Output: RAX = Model handle (stub returns 1)
;--------------------------------------------------------------------------
llama_model_load:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    
    ; Print stub message
    mov rsi, msg_llama_model_load_stub
    call scr64_print_string
    
    ; Return dummy model handle
    mov rax, 1
    
    pop rsi
    pop rdi
    pop rbp
    ret

;--------------------------------------------------------------------------
; parallel_run_model: Stub implementation for running model in parallel
; Input: RDI = Model handle, RSI = Input buffer, RDX = Output buffer
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
parallel_run_model:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rdx
    
    ; Print stub message
    mov rsi, msg_parallel_run_model_stub
    call scr64_print_string
    
    ; Return success
    xor rax, rax
    
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    ret

;--------------------------------------------------------------------------
; gpu_matmul: Stub implementation for GPU matrix multiplication
; Input: RDI = Matrix A, RSI = Matrix B, RDX = Result Matrix C, RCX = Size
; Output: RAX = 0 (success)
;--------------------------------------------------------------------------
gpu_matmul:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rdx
    push rcx
    
    ; Print stub message
    mov rsi, msg_gpu_matmul_stub
    call scr64_print_string
    
    ; Return success
    xor rax, rax
    
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    ret
