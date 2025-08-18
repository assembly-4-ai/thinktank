; ai_transformer_core.asm: Transformer architecture implementation
; Project Arora - Bare-Metal NASM AI Implementation
; Implements transformer layers and attention mechanisms
; Adheres to Project Arora coding rules: no ints, syscalls, libs - all custom

section .data
    ; Transformer configuration constants
    MAX_SEQ_LENGTH      dq 2048
    MAX_VOCAB_SIZE      dq 32000
    MAX_HIDDEN_SIZE     dq 4096
    MAX_NUM_HEADS       dq 32
    MAX_NUM_LAYERS      dq 32
    
    ; Attention scaling constants
    SQRT_HEAD_DIM       dq 0.0  ; Will be computed based on head dimension
    INV_SQRT_HEAD_DIM   dq 0.0  ; 1/sqrt(head_dim)
    
    ; Position encoding constants
    ROPE_THETA          dq 10000.0
    ROPE_SCALING        dq 1.0
    
    ; Numerical stability constants
    ATTENTION_EPSILON   dq 1e-6
    NORM_EPSILON        dq 1e-5
    
    ; Memory layout constants
    TENSOR_ALIGNMENT    dq 64   ; 64-byte alignment for SIMD
    CACHE_BLOCK_SIZE    dq 256  ; Cache blocking size

section .bss
    ; Transformer model state
    model_config        resq 16  ; Model configuration
    layer_weights       resq 1   ; Pointer to layer weights
    position_cache      resq 1   ; Cached position encodings
    attention_cache     resq 1   ; Attention computation cache
    
    ; Working memory for computations
    query_buffer        resq 1   ; Query tensor buffer
    key_buffer          resq 1   ; Key tensor buffer
    value_buffer        resq 1   ; Value tensor buffer
    attention_weights   resq 1   ; Attention weight matrix
    output_buffer       resq 1   ; Output buffer
    
    ; Layer normalization buffers
    norm_mean           resq 1   ; Mean for normalization
    norm_variance       resq 1   ; Variance for normalization
    
    ; Feed-forward network buffers
    ffn_intermediate    resq 1   ; Intermediate FFN activations
    ffn_output          resq 1   ; FFN output

section .text
    global ai_transformer_init
    global ai_transformer_forward
    global ai_attention_layer
    global ai_feed_forward_layer
    global ai_layer_norm
    global ai_rope_encoding
    global ai_multi_head_attention
    global ai_scaled_dot_product_attention
    global ai_position_encoding
    global ai_transformer_cleanup
    
    ; External functions
    extern ai_tensor_create
    extern ai_tensor_destroy
    extern ai_tensor_matmul
    extern ai_tensor_add
    extern ai_softmax
    extern ai_rms_norm
    extern ai_silu
    extern ai_sin
    extern ai_cos
    extern pmm_alloc_frame
    extern pmm_free_frame

; Model configuration structure (128 bytes)
; Offset 0:   vocab_size
; Offset 8:   hidden_size
; Offset 16:  num_layers
; Offset 24:  num_heads
; Offset 32:  head_dim
; Offset 40:  intermediate_size
; Offset 48:  max_seq_length
; Offset 56:  rope_theta
; Offset 64:  norm_epsilon
; Offset 72:  attention_epsilon
; Offset 80:  use_rope
; Offset 88:  use_gelu
; Offset 96:  reserved[4]

ai_transformer_init:
    ; Initialize transformer model
    ; Input: RDI = model configuration pointer
    ; Output: RAX = 0 on success, error code on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    
    ; Copy model configuration
    mov rsi, rdi
    mov rdi, model_config
    mov rcx, 16  ; 16 qwords = 128 bytes
    rep movsq
    
    ; Validate configuration
    mov rax, [model_config]      ; vocab_size
    cmp rax, [MAX_VOCAB_SIZE]
    ja .init_error
    
    mov rax, [model_config + 8]  ; hidden_size
    cmp rax, [MAX_HIDDEN_SIZE]
    ja .init_error
    
    mov rax, [model_config + 48] ; max_seq_length
    cmp rax, [MAX_SEQ_LENGTH]
    ja .init_error
    
    ; Calculate head dimension
    mov rax, [model_config + 8]  ; hidden_size
    mov rbx, [model_config + 24] ; num_heads
    xor rdx, rdx
    div rbx
    mov [model_config + 32], rax ; head_dim
    
    ; Calculate sqrt(head_dim) for attention scaling
    cvtsi2sd xmm0, rax
    call ai_sqrt
    movsd [SQRT_HEAD_DIM], xmm0
    
    ; Calculate 1/sqrt(head_dim)
    movsd xmm1, [EXP_C0]  ; 1.0
    divsd xmm1, xmm0
    movsd [INV_SQRT_HEAD_DIM], xmm1
    
    ; Allocate working buffers
    call ai_allocate_transformer_buffers
    test rax, rax
    jnz .init_error
    
    ; Initialize position encoding cache
    call ai_init_position_cache
    test rax, rax
    jnz .init_error
    
    ; Success
    xor rax, rax
    jmp .init_done
    
.init_error:
    mov rax, 1
    
.init_done:
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_allocate_transformer_buffers:
    ; Allocate working memory buffers for transformer computations
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    
    ; Calculate buffer sizes
    mov rax, [model_config + 8]  ; hidden_size
    mov rbx, [model_config + 48] ; max_seq_length
    mul rbx                      ; hidden_size * max_seq_length
    shl rax, 3                   ; * 8 bytes per element
    mov rcx, rax                 ; Base buffer size
    
    ; Allocate query buffer
    mov rdi, rcx
    call ai_allocate_aligned_buffer
    test rax, rax
    jz .alloc_error
    mov [query_buffer], rax
    
    ; Allocate key buffer
    mov rdi, rcx
    call ai_allocate_aligned_buffer
    test rax, rax
    jz .alloc_error
    mov [key_buffer], rax
    
    ; Allocate value buffer
    mov rdi, rcx
    call ai_allocate_aligned_buffer
    test rax, rax
    jz .alloc_error
    mov [value_buffer], rax
    
    ; Allocate attention weights buffer (seq_length * seq_length)
    mov rax, [model_config + 48] ; max_seq_length
    mul rax                      ; seq_length²
    shl rax, 3                   ; * 8 bytes
    mov rdi, rax
    call ai_allocate_aligned_buffer
    test rax, rax
    jz .alloc_error
    mov [attention_weights], rax
    
    ; Allocate output buffer
    mov rdi, rcx
    call ai_allocate_aligned_buffer
    test rax, rax
    jz .alloc_error
    mov [output_buffer], rax
    
    ; Allocate FFN intermediate buffer
    mov rax, [model_config + 40] ; intermediate_size
    mov rbx, [model_config + 48] ; max_seq_length
    mul rbx
    shl rax, 3
    mov rdi, rax
    call ai_allocate_aligned_buffer
    test rax, rax
    jz .alloc_error
    mov [ffn_intermediate], rax
    
    ; Success
    xor rax, rax
    jmp .alloc_done
    
.alloc_error:
    mov rax, 1
    
.alloc_done:
    pop rcx
    pop rbx
    pop rbp
    ret

ai_allocate_aligned_buffer:
    ; Allocate aligned memory buffer
    ; Input: RDI = size in bytes
    ; Output: RAX = buffer pointer or 0 on failure
    
    push rbp
    mov rbp, rsp
    push rbx
    
    ; Add alignment padding
    add rdi, 63
    and rdi, ~63     ; Align to 64-byte boundary
    
    ; Convert to frames (4KB each)
    add rdi, 4095
    shr rdi, 12
    
    ; Allocate from PMM
    call pmm_alloc_frame
    
    pop rbx
    pop rbp
    ret

ai_init_position_cache:
    ; Initialize position encoding cache for RoPE
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; Calculate cache size
    mov rax, [model_config + 48] ; max_seq_length
    mov rbx, [model_config + 32] ; head_dim
    mul rbx
    shl rax, 4                   ; * 16 bytes (2 doubles per position)
    
    ; Allocate position cache
    mov rdi, rax
    call ai_allocate_aligned_buffer
    test rax, rax
    jz .pos_cache_error
    mov [position_cache], rax
    
    ; Pre-compute position encodings
    mov rdi, rax                 ; Cache pointer
    mov rsi, [model_config + 48] ; max_seq_length
    mov rdx, [model_config + 32] ; head_dim
    call ai_precompute_rope_cache
    
    xor rax, rax
    jmp .pos_cache_done
    
.pos_cache_error:
    mov rax, 1
    
.pos_cache_done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_precompute_rope_cache:
    ; Pre-compute RoPE (Rotary Position Encoding) cache
    ; Input: RDI = cache pointer, RSI = max_seq_length, RDX = head_dim
    ; Output: Cache filled with sin/cos values
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push r8
    push r9
    push r10
    
    mov r8, rdi      ; Cache pointer
    mov r9, rsi      ; max_seq_length
    mov r10, rdx     ; head_dim
    
    ; Outer loop: position
    xor rbx, rbx     ; position = 0
    
.pos_loop:
    cmp rbx, r9
    jge .rope_cache_done
    
    ; Inner loop: dimension pairs
    xor rcx, rcx     ; dim = 0
    
.dim_loop:
    cmp rcx, r10
    jge .pos_next
    
    ; Calculate theta = position / (10000^(2*dim/head_dim))
    ; First compute 2*dim/head_dim
    mov rax, rcx
    shl rax, 1       ; 2*dim
    cvtsi2sd xmm0, rax
    cvtsi2sd xmm1, r10
    divsd xmm0, xmm1 ; 2*dim/head_dim
    
    ; Compute 10000^(2*dim/head_dim)
    movsd xmm1, [ROPE_THETA]  ; 10000.0
    call ai_pow      ; 10000^(2*dim/head_dim)
    
    ; Compute theta = position / (10000^(2*dim/head_dim))
    cvtsi2sd xmm1, rbx
    divsd xmm1, xmm0
    
    ; Compute sin(theta) and cos(theta)
    movsd xmm0, xmm1
    call ai_sin
    movsd xmm2, xmm0 ; sin(theta)
    
    movsd xmm0, xmm1
    call ai_cos
    movsd xmm3, xmm0 ; cos(theta)
    
    ; Store sin and cos in cache
    ; Cache layout: [sin0, cos0, sin1, cos1, ...]
    mov rax, rbx
    mul r10
    add rax, rcx
    shl rax, 4       ; * 16 bytes (2 doubles)
    
    movsd [r8 + rax], xmm2      ; sin
    movsd [r8 + rax + 8], xmm3  ; cos
    
    add rcx, 2       ; Process pairs of dimensions
    jmp .dim_loop
    
.pos_next:
    inc rbx
    jmp .pos_loop
    
.rope_cache_done:
    pop r10
    pop r9
    pop r8
    pop rcx
    pop rbx
    pop rbp
    ret

ai_transformer_forward:
    ; Forward pass through transformer model
    ; Input: RDI = input tensor, RSI = output tensor, RDX = sequence length
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push r8
    push r9
    push r10
    
    mov rbx, rdi     ; Input tensor
    mov rcx, rsi     ; Output tensor
    mov r8, rdx      ; Sequence length
    
    ; Validate sequence length
    cmp r8, [model_config + 48]
    ja .forward_error
    
    ; Process through each transformer layer
    mov r9, [model_config + 16]  ; num_layers
    xor r10, r10                 ; layer_idx = 0
    
.layer_loop:
    cmp r10, r9
    jge .forward_success
    
    ; Apply transformer layer
    mov rdi, rbx     ; Input
    mov rsi, rcx     ; Output
    mov rdx, r8      ; Sequence length
    mov rcx, r10     ; Layer index
    call ai_transformer_layer
    test rax, rax
    jnz .forward_error
    
    ; Swap input/output for next layer
    mov rax, rbx
    mov rbx, rcx
    mov rcx, rax
    
    inc r10
    jmp .layer_loop
    
.forward_success:
    xor rax, rax
    jmp .forward_done
    
.forward_error:
    mov rax, 1
    
.forward_done:
    pop r10
    pop r9
    pop r8
    pop rcx
    pop rbx
    pop rbp
    ret

ai_transformer_layer:
    ; Single transformer layer forward pass
    ; Input: RDI = input, RSI = output, RDX = seq_length, RCX = layer_idx
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    sub rsp, 32
    
    mov [rsp], rdi       ; Store input
    mov [rsp + 8], rsi   ; Store output
    mov [rsp + 16], rdx  ; Store seq_length
    mov [rsp + 24], rcx  ; Store layer_idx
    
    ; 1. Pre-attention layer normalization
    mov rdi, [rsp]       ; Input
    mov rsi, [output_buffer]  ; Normalized output
    mov rdx, [rsp + 16]  ; seq_length
    call ai_layer_norm_pre_attention
    test rax, rax
    jnz .layer_error
    
    ; 2. Multi-head attention
    mov rdi, [output_buffer]  ; Normalized input
    mov rsi, [output_buffer]  ; Attention output (in-place)
    mov rdx, [rsp + 16]       ; seq_length
    mov rcx, [rsp + 24]       ; layer_idx
    call ai_multi_head_attention
    test rax, rax
    jnz .layer_error
    
    ; 3. Residual connection after attention
    mov rdi, [rsp]            ; Original input
    mov rsi, [output_buffer]  ; Attention output
    mov rdx, [output_buffer]  ; Result
    call ai_tensor_add
    test rax, rax
    jnz .layer_error
    
    ; 4. Pre-FFN layer normalization
    mov rdi, [output_buffer]  ; Input
    mov rsi, [ffn_intermediate]  ; Normalized output
    mov rdx, [rsp + 16]       ; seq_length
    call ai_layer_norm_pre_ffn
    test rax, rax
    jnz .layer_error
    
    ; 5. Feed-forward network
    mov rdi, [ffn_intermediate]  ; Normalized input
    mov rsi, [ffn_intermediate]  ; FFN output (in-place)
    mov rdx, [rsp + 16]          ; seq_length
    mov rcx, [rsp + 24]          ; layer_idx
    call ai_feed_forward_layer
    test rax, rax
    jnz .layer_error
    
    ; 6. Final residual connection
    mov rdi, [output_buffer]     ; Previous output
    mov rsi, [ffn_intermediate]  ; FFN output
    mov rdx, [rsp + 8]           ; Final output
    call ai_tensor_add
    test rax, rax
    jnz .layer_error
    
    xor rax, rax
    jmp .layer_done
    
.layer_error:
    mov rax, 1
    
.layer_done:
    add rsp, 32
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_multi_head_attention:
    ; Multi-head attention mechanism
    ; Input: RDI = input, RSI = output, RDX = seq_length, RCX = layer_idx
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    
    mov r8, rdi      ; Input
    mov r9, rsi      ; Output
    mov r10, rdx     ; seq_length
    mov r11, rcx     ; layer_idx
    
    ; Get model dimensions
    mov rax, [model_config + 24]  ; num_heads
    mov rbx, [model_config + 32]  ; head_dim
    
    ; Compute Q, K, V projections
    ; Q = input * W_q
    mov rdi, r8                   ; Input
    mov rsi, [query_buffer]       ; Q output
    mov rdx, r11                  ; layer_idx (for weight selection)
    mov rcx, 0                    ; Projection type: Query
    call ai_linear_projection
    test rax, rax
    jnz .mha_error
    
    ; K = input * W_k
    mov rdi, r8                   ; Input
    mov rsi, [key_buffer]         ; K output
    mov rdx, r11                  ; layer_idx
    mov rcx, 1                    ; Projection type: Key
    call ai_linear_projection
    test rax, rax
    jnz .mha_error
    
    ; V = input * W_v
    mov rdi, r8                   ; Input
    mov rsi, [value_buffer]       ; V output
    mov rdx, r11                  ; layer_idx
    mov rcx, 2                    ; Projection type: Value
    call ai_linear_projection
    test rax, rax
    jnz .mha_error
    
    ; Apply RoPE to Q and K if enabled
    cmp qword [model_config + 80], 0  ; use_rope
    je .skip_rope
    
    mov rdi, [query_buffer]
    mov rsi, r10                  ; seq_length
    call ai_apply_rope
    
    mov rdi, [key_buffer]
    mov rsi, r10                  ; seq_length
    call ai_apply_rope
    
.skip_rope:
    ; Compute scaled dot-product attention for each head
    mov rax, [model_config + 24]  ; num_heads
    xor rbx, rbx                  ; head_idx = 0
    
.head_loop:
    cmp rbx, rax
    jge .heads_done
    
    ; Compute attention for this head
    mov rdi, [query_buffer]
    mov rsi, [key_buffer]
    mov rdx, [value_buffer]
    mov rcx, [output_buffer]
    mov r8, r10                   ; seq_length
    mov r9, rbx                   ; head_idx
    call ai_scaled_dot_product_attention
    test rax, rax
    jnz .mha_error
    
    inc rbx
    jmp .head_loop
    
.heads_done:
    ; Concatenate heads and apply output projection
    mov rdi, [output_buffer]      ; Multi-head output
    mov rsi, r9                   ; Final output
    mov rdx, r11                  ; layer_idx
    mov rcx, 3                    ; Projection type: Output
    call ai_linear_projection
    test rax, rax
    jnz .mha_error
    
    xor rax, rax
    jmp .mha_done
    
.mha_error:
    mov rax, 1
    
.mha_done:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_scaled_dot_product_attention:
    ; Scaled dot-product attention for a single head
    ; Input: RDI = Q, RSI = K, RDX = V, RCX = output, R8 = seq_length, R9 = head_idx
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r10
    push r11
    push r12
    
    mov r10, rdi     ; Q
    mov r11, rsi     ; K
    mov r12, rdx     ; V
    
    ; Calculate head offset
    mov rax, [model_config + 32]  ; head_dim
    mul r9                        ; head_idx * head_dim
    mov rbx, rax                  ; head_offset
    
    ; Compute attention scores: scores = Q * K^T / sqrt(head_dim)
    ; For each query position
    xor rdi, rdi     ; q_pos = 0
    
.q_loop:
    cmp rdi, r8
    jge .attention_done
    
    ; For each key position
    xor rsi, rsi     ; k_pos = 0
    
.k_loop:
    cmp rsi, r8
    jge .q_next
    
    ; Compute dot product between Q[q_pos] and K[k_pos]
    call ai_compute_qk_dot_product
    
    ; Scale by 1/sqrt(head_dim)
    mulsd xmm0, [INV_SQRT_HEAD_DIM]
    
    ; Store in attention weights matrix
    mov rax, rdi
    mul r8
    add rax, rsi
    shl rax, 3       ; * 8 bytes
    mov rdx, [attention_weights]
    movsd [rdx + rax], xmm0
    
    inc rsi
    jmp .k_loop
    
.q_next:
    inc rdi
    jmp .q_loop
    
.attention_done:
    ; Apply softmax to each row of attention weights
    xor rdi, rdi     ; row = 0
    
.softmax_loop:
    cmp rdi, r8
    jge .softmax_done
    
    ; Apply softmax to row
    mov rax, rdi
    mul r8
    shl rax, 3
    mov rsi, [attention_weights]
    add rsi, rax     ; Row start
    mov rdx, rsi     ; Output (in-place)
    mov rcx, r8      ; Length
    call ai_softmax
    
    inc rdi
    jmp .softmax_loop
    
.softmax_done:
    ; Compute output: output = attention_weights * V
    call ai_compute_attention_output
    
    xor rax, rax
    
    pop r12
    pop r11
    pop r10
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_compute_qk_dot_product:
    ; Compute dot product between query and key vectors
    ; Input: RDI = q_pos, RSI = k_pos, R10 = Q, R11 = K, RBX = head_offset
    ; Output: XMM0 = dot product
    
    push rbp
    mov rbp, rsp
    push rcx
    push rdx
    push r8
    
    ; Calculate Q vector address
    mov rax, rdi                  ; q_pos
    mov rcx, [model_config + 8]   ; hidden_size
    mul rcx
    add rax, rbx                  ; + head_offset
    shl rax, 3                    ; * 8 bytes
    add rax, r10                  ; Q base address
    mov rdx, rax                  ; Q vector address
    
    ; Calculate K vector address
    mov rax, rsi                  ; k_pos
    mul rcx                       ; * hidden_size
    add rax, rbx                  ; + head_offset
    shl rax, 3                    ; * 8 bytes
    add rax, r11                  ; K base address
    mov r8, rax                   ; K vector address
    
    ; Compute dot product
    xorpd xmm0, xmm0              ; sum = 0
    mov rcx, [model_config + 32]  ; head_dim
    
.dot_loop:
    test rcx, rcx
    jz .dot_done
    
    movsd xmm1, [rdx]
    mulsd xmm1, [r8]
    addsd xmm0, xmm1
    
    add rdx, 8
    add r8, 8
    dec rcx
    jmp .dot_loop
    
.dot_done:
    pop r8
    pop rdx
    pop rcx
    pop rbp
    ret

ai_apply_rope:
    ; Apply Rotary Position Encoding (RoPE)
    ; Input: RDI = tensor, RSI = seq_length
    ; Output: Tensor modified in-place
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    
    mov rbx, rdi     ; Tensor
    mov rcx, rsi     ; seq_length
    
    ; For each position
    xor r8, r8       ; pos = 0
    
.rope_pos_loop:
    cmp r8, rcx
    jge .rope_done
    
    ; For each dimension pair
    mov r9, [model_config + 32]  ; head_dim
    shr r9, 1                    ; head_dim / 2 (process pairs)
    xor rdx, rdx                 ; dim_pair = 0
    
.rope_dim_loop:
    cmp rdx, r9
    jge .rope_pos_next
    
    ; Get cached sin/cos values
    mov rax, r8                  ; position
    mov rsi, [model_config + 32] ; head_dim
    mul rsi
    add rax, rdx
    shl rax, 1                   ; * 2 (for pair)
    shl rax, 4                   ; * 16 bytes
    mov rsi, [position_cache]
    add rsi, rax
    
    movsd xmm2, [rsi]            ; sin
    movsd xmm3, [rsi + 8]        ; cos
    
    ; Calculate tensor element addresses
    mov rax, r8                  ; position
    mov rsi, [model_config + 8]  ; hidden_size
    mul rsi
    add rax, rdx
    shl rax, 1                   ; * 2 (for pair)
    shl rax, 3                   ; * 8 bytes
    
    ; Load x and y values
    movsd xmm0, [rbx + rax]      ; x
    movsd xmm1, [rbx + rax + 8]  ; y
    
    ; Apply rotation: x' = x*cos - y*sin, y' = x*sin + y*cos
    movsd xmm4, xmm0             ; x
    mulsd xmm4, xmm3             ; x*cos
    movsd xmm5, xmm1             ; y
    mulsd xmm5, xmm2             ; y*sin
    subsd xmm4, xmm5             ; x' = x*cos - y*sin
    
    movsd xmm5, xmm0             ; x
    mulsd xmm5, xmm2             ; x*sin
    movsd xmm6, xmm1             ; y
    mulsd xmm6, xmm3             ; y*cos
    addsd xmm5, xmm6             ; y' = x*sin + y*cos
    
    ; Store rotated values
    movsd [rbx + rax], xmm4      ; x'
    movsd [rbx + rax + 8], xmm5  ; y'
    
    inc rdx
    jmp .rope_dim_loop
    
.rope_pos_next:
    inc r8
    jmp .rope_pos_loop
    
.rope_done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_feed_forward_layer:
    ; Feed-forward network layer
    ; Input: RDI = input, RSI = output, RDX = seq_length, RCX = layer_idx
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    
    ; 1. First linear projection: input -> intermediate
    mov rdi, [rsp]               ; Input
    mov rsi, [ffn_intermediate]  ; Intermediate buffer
    mov rdx, [rsp + 16]          ; layer_idx
    mov rcx, 4                   ; Projection type: FFN up
    call ai_linear_projection
    test rax, rax
    jnz .ffn_error
    
    ; 2. Apply activation function (SiLU/Swish)
    mov rdi, [ffn_intermediate]
    mov rsi, [rsp + 24]          ; seq_length
    call ai_apply_activation_silu
    test rax, rax
    jnz .ffn_error
    
    ; 3. Second linear projection: intermediate -> output
    mov rdi, [ffn_intermediate]  ; Intermediate
    mov rsi, [rsp + 8]           ; Output
    mov rdx, [rsp + 16]          ; layer_idx
    mov rcx, 5                   ; Projection type: FFN down
    call ai_linear_projection
    test rax, rax
    jnz .ffn_error
    
    xor rax, rax
    jmp .ffn_done
    
.ffn_error:
    mov rax, 1
    
.ffn_done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_apply_activation_silu:
    ; Apply SiLU activation function to tensor
    ; Input: RDI = tensor, RSI = seq_length
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    
    mov rbx, rdi     ; Tensor
    mov rcx, rsi     ; seq_length
    
    ; Calculate total elements
    mov rax, [model_config + 40] ; intermediate_size
    mul rcx                      ; * seq_length
    mov rcx, rax                 ; Total elements
    
.silu_loop:
    test rcx, rcx
    jz .silu_done
    
    ; Apply SiLU to element
    movsd xmm0, [rbx]
    call ai_silu
    movsd [rbx], xmm0
    
    add rbx, 8
    dec rcx
    jmp .silu_loop
    
.silu_done:
    xor rax, rax
    
    pop rcx
    pop rbx
    pop rbp
    ret

; Additional functions would be implemented here:
; - ai_linear_projection (matrix multiplication with weights)
; - ai_layer_norm_pre_attention
; - ai_layer_norm_pre_ffn
; - ai_compute_attention_output
; - ai_transformer_cleanup
; - Weight loading and management functions
; - Quantization support for weights
; - Gradient checkpointing for memory efficiency


    extern ai_sqrt
    extern ai_pow
    extern ai_layer_norm_pre_attention
    extern ai_layer_norm_pre_ffn
    extern ai_linear_projection
    extern ai_compute_attention_output
    extern EXP_C0




ai_layer_norm_pre_attention:
    ; Placeholder for pre-attention layer normalization
    ; TODO: Implement actual layer normalization logic
    xor rax, rax
    ret




ai_layer_norm_pre_ffn:
    ; Placeholder for pre-FFN layer normalization
    ; TODO: Implement actual layer normalization logic
    xor rax, rax
    ret




ai_linear_projection:
    ; Placeholder for linear projection
    ; TODO: Implement actual linear projection logic
    xor rax, rax
    ret




ai_compute_attention_output:
    ; Placeholder for computing attention output
    ; TODO: Implement actual attention output computation logic
    xor rax, rax
    ret


