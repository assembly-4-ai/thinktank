; loaded_image.asm - UEFI Loaded Image Information Retrieval
; Implements robust retrieval and storage of loaded image information

BITS 64
default rel

%include "boot_defs_temp.inc"

; External dependencies
extern panic64, scr64_print_string, scr64_print_hex, scr64_print_char

; Exports
global retrieve_loaded_image_info
global loaded_image_base, loaded_image_size
global loaded_image_device_handle, loaded_image_file_path

section .data
    ; Loaded image information
    loaded_image_base dq 0
    loaded_image_size dq 0
    loaded_image_device_handle dq 0
    loaded_image_file_path dq 0
    
    ; Error messages
    msg_loaded_image_error db "Error retrieving loaded image info: ", 0
    msg_loaded_image_base db "Loaded Image Base: 0x", 0
    msg_loaded_image_size db "Loaded Image Size: 0x", 0
    msg_loaded_image_device db "Loaded Image Device Handle: 0x", 0

section .text

;--------------------------------------------------------------------------
; retrieve_loaded_image_info: Retrieves and stores loaded image information
; Input: RDI = Loaded Image Protocol interface pointer
; Output: RAX = 0 on success, error code otherwise
;--------------------------------------------------------------------------
retrieve_loaded_image_info:
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
    push r15
    
    ; Validate input parameter
    test rdi, rdi
    jz .error_invalid_param
    
    ; Store loaded image interface pointer for later use
    mov r12, rdi
    
    ; Get image base address
    mov rax, [rdi + OFFSET_LOADED_IMAGE_IMAGEBASE]
    mov [loaded_image_base], rax
    
    ; Get image size
    mov rax, [rdi + OFFSET_LOADED_IMAGE_IMAGESIZE]
    mov [loaded_image_size], rax
    
    ; Get device handle
    mov rax, [rdi + 16] ; DeviceHandle offset
    mov [loaded_image_device_handle], rax
    
    ; Get file path
    mov rax, [rdi + 24] ; FilePath offset
    mov [loaded_image_file_path], rax
    
    ; Print loaded image information (if debug output is enabled)
    mov rsi, msg_loaded_image_base
    call scr64_print_string
    
    mov rsi, [loaded_image_base]
    call scr64_print_hex
    
    mov al, 10 ; Newline
    call scr64_print_char
    
    mov rsi, msg_loaded_image_size
    call scr64_print_string
    
    mov rsi, [loaded_image_size]
    call scr64_print_hex
    
    mov al, 10 ; Newline
    call scr64_print_char
    
    mov rsi, msg_loaded_image_device
    call scr64_print_string
    
    mov rsi, [loaded_image_device_handle]
    call scr64_print_hex
    
    mov al, 10 ; Newline
    call scr64_print_char
    
    ; Success
    xor rax, rax
    jmp .done
    
.error_invalid_param:
    ; Invalid parameter
    mov rsi, msg_loaded_image_error
    call scr64_print_string
    
    mov rsi, 1 ; Error code
    call scr64_print_hex
    
    mov rax, 1
    
.done:
    pop r15
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

;--------------------------------------------------------------------------
; get_loaded_image_path_string: Converts DevicePath to string (if needed)
; Input: RDI = File path pointer (from loaded image)
; Output: RAX = String pointer (or 0 if not available/convertible)
;--------------------------------------------------------------------------
get_loaded_image_path_string:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Validate input parameter
    test rdi, rdi
    jz .error_invalid_param
    
    ; For now, just return 0 as we don't have a full DevicePath to string converter
    ; This would be implemented in a more complete version
    xor rax, rax
    jmp .done
    
.error_invalid_param:
    xor rax, rax
    
.done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret
