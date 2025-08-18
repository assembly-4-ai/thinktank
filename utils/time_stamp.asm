default rel

global get_timestamp

section .text

get_timestamp:
    ; Get current timestamp using rdtsc
    ; Input: None
    ; Output: RAX = timestamp
    
    push rdx
    rdtsc
    shl rdx, 32
    or rax, rdx
    pop rdx
    ret


