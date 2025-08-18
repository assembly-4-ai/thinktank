    global ai_pow
; Project Arora - Bare-Metal NASM AI Implementation
; Implements essential mathematical functions without external dependencies
; Adheres to Project Arora coding rules: no ints, syscalls, libs - all custom

    global ai_pow
    global MATH_PI
    global MATH_E
    global MATH_LN2
    global MATH_LOG2E
    global MATH_SQRT2
    global MATH_SQRT1_2
    
    global EXP_C0
    global EXP_C1
    global EXP_C2
    global EXP_C3
    global EXP_C4
    global EXP_C5
    global EXP_C6
    global EXP_C7
    
    global SIN_C1
    global SIN_C3
    global SIN_C5
    global SIN_C7
    global SIN_C9
    
    global COS_C0
    global COS_C2
    global COS_C4
    global COS_C6
    global COS_C8
    
    global SQRT_TABLE
    
    global GELU_SQRT_2_PI
    global GELU_COEFF
    
    global EPSILON
    global MAX_EXP_ARG
    global MIN_EXP_ARG

section .data
    ; Mathematical constants (high precision)
    MATH_PI         dq 3.1415926535897932384626433832795
    MATH_E          dq 2.7182818284590452353602874713527
    MATH_LN2        dq 0.6931471805599453094172321214582
    MATH_LOG2E      dq 1.4426950408889634073599246810019
    MATH_SQRT2      dq 1.4142135623730950488016887242097
    MATH_SQRT1_2    dq 0.7071067811865475244008443621048
    
    ; Polynomial coefficients for exp(x) approximation
    EXP_C0          dq 1.0
    EXP_C1          dq 1.0
    EXP_C2          dq 0.5
    EXP_C3          dq 0.16666666666666666
    EXP_C4          dq 0.041666666666666664
    EXP_C5          dq 0.008333333333333333
    EXP_C6          dq 0.001388888888888889
    EXP_C7          dq 0.0001984126984126984
    
    ; Polynomial coefficients for sin(x) approximation
    SIN_C1          dq 1.0
    SIN_C3          dq -0.16666666666666666
    SIN_C5          dq 0.008333333333333333
    SIN_C7          dq -0.0001984126984126984
    SIN_C9          dq 0.0000027557319223986
    
    ; Polynomial coefficients for cos(x) approximation
    COS_C0          dq 1.0
    COS_C2          dq -0.5
    COS_C4          dq 0.041666666666666664
    COS_C6          dq -0.001388888888888889
    COS_C8          dq 0.000024801587301587302
    
    ; Lookup table for fast sqrt approximation (initial guess)
    SQRT_TABLE      times 256 dq 0.0
    
    ; Constants for GELU approximation
    GELU_SQRT_2_PI  dq 0.7978845608028654  ; sqrt(2/pi)
    GELU_COEFF      dq 0.044715
    
    ; Constants for numerical stability
    EPSILON         dq 1e-15
    MAX_EXP_ARG     dq 700.0
    MIN_EXP_ARG     dq -700.0

section .bss
    ; Temporary storage for complex calculations
    temp_storage    resq 16
    
section .text
    global ai_exp
    global ai_log
    global ai_sin
    global ai_cos
    global ai_tan
    global ai_sqrt
    global ai_pow
    global ai_tanh
    global ai_sigmoid
    global ai_relu
    global ai_gelu
    global ai_silu
    global ai_softmax
    global ai_rms_norm
    global ai_layer_norm
    global ai_init_math_tables

ai_init_math_tables:
    ; Initialize lookup tables for mathematical functions
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    
    ; Initialize sqrt lookup table
    xor rbx, rbx
    
.init_sqrt_loop:
    cmp rbx, 256
    jge .init_done
    
    ; Calculate initial guess for sqrt(x)
    ; Using bit manipulation for fast approximation
    mov rax, rbx
    shl rax, 52          ; Shift to exponent position
    add rax, 0x3FE0000000000000  ; Add bias
    mov [SQRT_TABLE + rbx * 8], rax
    
    inc rbx
    jmp .init_sqrt_loop
    
.init_done:
    xor rax, rax
    
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

ai_exp:
    ; Compute e^x using Taylor series
    ; Input: XMM0 = x
    ; Output: XMM0 = e^x
    
    push rbp
    mov rbp, rsp
    
    ; Check for overflow/underflow
    movsd xmm1, [MAX_EXP_ARG]
    ucomisd xmm0, xmm1
    ja .exp_overflow
    
    movsd xmm1, [MIN_EXP_ARG]
    ucomisd xmm0, xmm1
    jb .exp_underflow
    
    ; Range reduction: x = n * ln(2) + r, where |r| <= ln(2)/2
    movsd xmm1, [MATH_LOG2E]
    mulsd xmm1, xmm0     ; x * log2(e)
    
    ; Round to nearest integer
    roundsd xmm2, xmm1, 0
    
    ; Calculate remainder r = x - n * ln(2)
    movsd xmm3, [MATH_LN2]
    mulsd xmm3, xmm2
    subsd xmm0, xmm3     ; r = x - n * ln(2)
    
    ; Store n for later use
    cvtsd2si rax, xmm2
    
    ; Compute exp(r) using Taylor series
    ; exp(r) = 1 + r + r^2/2! + r^3/3! + ...
    movsd xmm1, xmm0     ; r
    movsd xmm2, [EXP_C0] ; result = 1.0
    
    ; Term 1: r
    movsd xmm3, [EXP_C1]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    
    ; Term 2: r^2/2!
    mulsd xmm1, xmm0     ; r^2
    movsd xmm3, [EXP_C2]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    
    ; Term 3: r^3/3!
    mulsd xmm1, xmm0     ; r^3
    movsd xmm3, [EXP_C3]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    
    ; Term 4: r^4/4!
    mulsd xmm1, xmm0     ; r^4
    movsd xmm3, [EXP_C4]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    
    ; Term 5: r^5/5!
    mulsd xmm1, xmm0     ; r^5
    movsd xmm3, [EXP_C5]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    
    ; Term 6: r^6/6!
    mulsd xmm1, xmm0     ; r^6
    movsd xmm3, [EXP_C6]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    
    ; Term 7: r^7/7!
    mulsd xmm1, xmm0     ; r^7
    movsd xmm3, [EXP_C7]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3
    
    ; Scale by 2^n
    test rax, rax
    jz .exp_done
    
    ; Create 2^n by manipulating exponent
    add rax, 1023        ; Add bias
    shl rax, 52          ; Shift to exponent position
    movq xmm1, rax
    mulsd xmm2, xmm1
    
.exp_done:
    movsd xmm0, xmm2
    jmp .exp_return
    
.exp_overflow:
    ; Return infinity
    mov rax, 0x7FF0000000000000
    movq xmm0, rax
    jmp .exp_return
    
.exp_underflow:
    ; Return zero
    xorpd xmm0, xmm0
    
.exp_return:
    pop rbp
    ret

ai_log:
    ; Compute natural logarithm using Newton-Raphson method
    ; Input: XMM0 = x
    ; Output: XMM0 = ln(x)
    
    push rbp
    mov rbp, rsp
    
    ; Check for invalid input
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jbe .log_error
    
    ; Extract exponent and mantissa
    movq rax, xmm0
    mov rbx, rax
    shr rbx, 52          ; Extract exponent
    sub rbx, 1023        ; Remove bias
    
    ; Normalize mantissa to [1, 2)
    and rax, 0x000FFFFFFFFFFFFF
    or rax, 0x3FF0000000000000
    movq xmm1, rax       ; Normalized mantissa
    
    ; Use polynomial approximation for ln(1+x) where x = mantissa - 1
    movsd xmm2, [EXP_C0] ; 1.0
    subsd xmm1, xmm2     ; x = mantissa - 1
    
    ; ln(1+x) ≈ x - x²/2 + x³/3 - x⁴/4 + ...
    movsd xmm0, xmm1     ; x
    movsd xmm2, xmm1     ; x
    mulsd xmm2, xmm1     ; x²
    movsd xmm3, xmm2
    mulsd xmm3, xmm1     ; x³
    
    ; Calculate series
    movsd xmm4, xmm2
    movsd xmm5, [EXP_C2] ; 0.5
    mulsd xmm4, xmm5
    subsd xmm0, xmm4     ; x - x²/2
    
    movsd xmm4, xmm3
    movsd xmm5, [EXP_C3] ; 1/3
    mulsd xmm5, [EXP_C3]
    mulsd xmm5, [EXP_C0]
    mulsd xmm4, xmm5
    addsd xmm0, xmm4     ; + x³/3
    
    ; Add exponent contribution: ln(2) * exponent
    cvtsi2sd xmm1, rbx
    movsd xmm2, [MATH_LN2]
    mulsd xmm1, xmm2
    addsd xmm0, xmm1
    
    jmp .log_return
    
.log_error:
    ; Return NaN for invalid input
    mov rax, 0x7FF8000000000000
    movq xmm0, rax
    
.log_return:
    pop rbp
    ret

ai_sin:
    ; Compute sin(x) using Taylor series
    ; Input: XMM0 = x (in radians)
    ; Output: XMM0 = sin(x)
    
    push rbp
    mov rbp, rsp
    
    ; Range reduction: reduce x to [-π, π]
    movsd xmm1, [MATH_PI]
    addsd xmm1, xmm1     ; 2π
    
    ; x = x - 2π * round(x / 2π)
    divsd xmm0, xmm1
    roundsd xmm2, xmm0, 0
    mulsd xmm2, xmm1
    subsd xmm0, xmm2
    
    ; Taylor series: sin(x) = x - x³/3! + x⁵/5! - x⁷/7! + ...
    movsd xmm1, xmm0     ; x
    movsd xmm2, xmm0     ; result = x
    mulsd xmm1, xmm0     ; x²
    
    ; Term: -x³/3!
    movsd xmm3, xmm1
    mulsd xmm3, xmm0     ; x³
    movsd xmm4, [SIN_C3]
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    
    ; Term: x⁵/5!
    mulsd xmm1, xmm0     ; x⁴
    mulsd xmm1, xmm0     ; x⁵
    movsd xmm3, xmm1
    movsd xmm4, [SIN_C5]
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    
    ; Term: -x⁷/7!
    mulsd xmm1, xmm0     ; x⁶
    mulsd xmm1, xmm0     ; x⁷
    movsd xmm3, xmm1
    movsd xmm4, [SIN_C7]
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    
    ; Term: x⁹/9!
    mulsd xmm1, xmm0     ; x⁸
    mulsd xmm1, xmm0     ; x⁹
    movsd xmm3, xmm1
    movsd xmm4, [SIN_C9]
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    
    movsd xmm0, xmm2
    
    pop rbp
    ret

ai_cos:
    ; Compute cos(x) using Taylor series
    ; Input: XMM0 = x (in radians)
    ; Output: XMM0 = cos(x)
    
    push rbp
    mov rbp, rsp
    
    ; Range reduction: reduce x to [-π, π]
    movsd xmm1, [MATH_PI]
    addsd xmm1, xmm1     ; 2π
    
    ; x = x - 2π * round(x / 2π)
    divsd xmm0, xmm1
    roundsd xmm2, xmm0, 0
    mulsd xmm2, xmm1
    subsd xmm0, xmm2
    
    ; Taylor series: cos(x) = 1 - x²/2! + x⁴/4! - x⁶/6! + ...
    movsd xmm1, xmm0
    mulsd xmm1, xmm0     ; x²
    movsd xmm2, [COS_C0] ; result = 1.0
    
    ; Term: -x²/2!
    movsd xmm3, xmm1
    movsd xmm4, [COS_C2]
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    
    ; Term: x⁴/4!
    mulsd xmm1, xmm0     ; x³
    mulsd xmm1, xmm0     ; x⁴
    movsd xmm3, xmm1
    movsd xmm4, [COS_C4]
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    
    ; Term: -x⁶/6!
    mulsd xmm1, xmm0     ; x⁵
    mulsd xmm1, xmm0     ; x⁶
    movsd xmm3, xmm1
    movsd xmm4, [COS_C6]
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    
    ; Term: x⁸/8!
    mulsd xmm1, xmm0     ; x⁷
    mulsd xmm1, xmm0     ; x⁸
    movsd xmm3, xmm1
    movsd xmm4, [COS_C8]
    mulsd xmm3, xmm4
    addsd xmm2, xmm3
    
    movsd xmm0, xmm2
    
    pop rbp
    ret

ai_sqrt:
    ; Compute square root using Newton-Raphson method
    ; Input: XMM0 = x
    ; Output: XMM0 = sqrt(x)
    
    push rbp
    mov rbp, rsp
    
    ; Check for negative input
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jb .sqrt_error
    je .sqrt_zero
    
    ; Get initial approximation using bit manipulation
    movq rax, xmm0
    shr rax, 1
    add rax, 0x1FF8000000000000
    movq xmm1, rax       ; Initial guess
    
    ; Newton-Raphson iterations: x_{n+1} = (x_n + a/x_n) / 2
    ; Perform 4 iterations for good precision
    
    ; Iteration 1
    movsd xmm2, xmm0
    divsd xmm2, xmm1
    addsd xmm1, xmm2
    movsd xmm2, [EXP_C2] ; 0.5
    mulsd xmm1, xmm2
    
    ; Iteration 2
    movsd xmm2, xmm0
    divsd xmm2, xmm1
    addsd xmm1, xmm2
    movsd xmm2, [EXP_C2]
    mulsd xmm1, xmm2
    
    ; Iteration 3
    movsd xmm2, xmm0
    divsd xmm2, xmm1
    addsd xmm1, xmm2
    movsd xmm2, [EXP_C2]
    mulsd xmm1, xmm2
    
    ; Iteration 4
    movsd xmm2, xmm0
    divsd xmm2, xmm1
    addsd xmm1, xmm2
    movsd xmm2, [EXP_C2]
    mulsd xmm1, xmm2
    
    movsd xmm0, xmm1
    jmp .sqrt_return
    
.sqrt_zero:
    xorpd xmm0, xmm0
    jmp .sqrt_return
    
.sqrt_error:
    ; Return NaN for negative input
    mov rax, 0x7FF8000000000000
    movq xmm0, rax
    
.sqrt_return:
    pop rbp
    ret

ai_tanh:
    ; Compute tanh(x) = (e^x - e^(-x)) / (e^x + e^(-x))
    ; Input: XMM0 = x
    ; Output: XMM0 = tanh(x)
    
    push rbp
    mov rbp, rsp
    sub rsp, 16
    
    ; Store original x
    movsd [rsp], xmm0
    
    ; Compute e^x
    call ai_exp
    movsd [rsp + 8], xmm0  ; Store e^x
    
    ; Compute e^(-x)
    movsd xmm0, [rsp]
    xorpd xmm1, xmm1
    subsd xmm1, xmm0     ; -x
    movsd xmm0, xmm1
    call ai_exp          ; e^(-x)
    
    ; Calculate tanh = (e^x - e^(-x)) / (e^x + e^(-x))
    movsd xmm1, [rsp + 8]  ; e^x
    movsd xmm2, xmm0       ; e^(-x)
    
    ; Numerator: e^x - e^(-x)
    movsd xmm3, xmm1
    subsd xmm3, xmm2
    
    ; Denominator: e^x + e^(-x)
    addsd xmm1, xmm2
    
    ; Result
    divsd xmm3, xmm1
    movsd xmm0, xmm3
    
    add rsp, 16
    pop rbp
    ret

ai_sigmoid:
    ; Compute sigmoid(x) = 1 / (1 + e^(-x))
    ; Input: XMM0 = x
    ; Output: XMM0 = sigmoid(x)
    
    push rbp
    mov rbp, rsp
    
    ; Compute -x
    xorpd xmm1, xmm1
    subsd xmm1, xmm0
    movsd xmm0, xmm1
    
    ; Compute e^(-x)
    call ai_exp
    
    ; Compute 1 + e^(-x)
    movsd xmm1, [EXP_C0]  ; 1.0
    addsd xmm0, xmm1
    
    ; Compute 1 / (1 + e^(-x))
    movsd xmm1, [EXP_C0]  ; 1.0
    divsd xmm1, xmm0
    movsd xmm0, xmm1
    
    pop rbp
    ret

ai_relu:
    ; Compute ReLU(x) = max(0, x)
    ; Input: XMM0 = x
    ; Output: XMM0 = ReLU(x)
    
    push rbp
    mov rbp, rsp
    
    xorpd xmm1, xmm1
    maxsd xmm0, xmm1
    
    pop rbp
    ret

ai_gelu:
    ; Compute GELU(x) = 0.5 * x * (1 + tanh(sqrt(2/π) * (x + 0.044715 * x³)))
    ; Input: XMM0 = x
    ; Output: XMM0 = GELU(x)
    
    push rbp
    mov rbp, rsp
    sub rsp, 24
    
    ; Store original x
    movsd [rsp], xmm0
    
    ; Compute x³
    movsd xmm1, xmm0
    mulsd xmm1, xmm0     ; x²
    mulsd xmm1, xmm0     ; x³
    
    ; Compute 0.044715 * x³
    movsd xmm2, [GELU_COEFF]
    mulsd xmm1, xmm2
    
    ; Compute x + 0.044715 * x³
    addsd xmm0, xmm1
    
    ; Multiply by sqrt(2/π)
    movsd xmm1, [GELU_SQRT_2_PI]
    mulsd xmm0, xmm1
    
    ; Store intermediate result
    movsd [rsp + 8], xmm0
    
    ; Compute tanh of the result
    call ai_tanh
    
    ; Add 1
    movsd xmm1, [EXP_C0]  ; 1.0
    addsd xmm0, xmm1
    
    ; Multiply by original x
    movsd xmm1, [rsp]
    mulsd xmm0, xmm1
    
    ; Multiply by 0.5
    movsd xmm1, [EXP_C2]  ; 0.5
    mulsd xmm0, xmm1
    
    add rsp, 24
    pop rbp
    ret

ai_silu:
    ; Compute SiLU(x) = x * sigmoid(x)
    ; Input: XMM0 = x
    ; Output: XMM0 = SiLU(x)
    
    push rbp
    mov rbp, rsp
    sub rsp, 8
    
    ; Store original x
    movsd [rsp], xmm0
    
    ; Compute sigmoid(x)
    call ai_sigmoid
    
    ; Multiply by original x
    movsd xmm1, [rsp]
    mulsd xmm0, xmm1
    
    add rsp, 8
    pop rbp
    ret

ai_softmax:
    ; Compute softmax over an array of values
    ; Input: RDI = input array, RSI = output array, RDX = length
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push r8
    push r9
    sub rsp, 16
    
    ; Find maximum value for numerical stability
    movsd xmm0, [rdi]
    mov rcx, rdx
    mov rbx, rdi
    
.find_max:
    test rcx, rcx
    jz .max_found
    movsd xmm1, [rbx]
    maxsd xmm0, xmm1
    add rbx, 8
    dec rcx
    jmp .find_max
    
.max_found:
    movsd [rsp], xmm0    ; Store max value
    
    ; Compute exp(x_i - max) and sum
    xorpd xmm1, xmm1     ; sum = 0
    mov rcx, rdx
    mov rbx, rdi
    mov r8, rsi
    
.exp_loop:
    test rcx, rcx
    jz .exp_done
    
    ; Compute exp(x_i - max)
    movsd xmm0, [rbx]
    subsd xmm0, [rsp]
    
    push rcx
    push rbx
    push r8
    call ai_exp
    pop r8
    pop rbx
    pop rcx
    
    ; Store exp value and add to sum
    movsd [r8], xmm0
    addsd xmm1, xmm0
    
    add rbx, 8
    add r8, 8
    dec rcx
    jmp .exp_loop
    
.exp_done:
    movsd [rsp + 8], xmm1  ; Store sum
    
    ; Normalize by dividing each exp value by sum
    mov rcx, rdx
    mov r8, rsi
    
.normalize_loop:
    test rcx, rcx
    jz .softmax_success
    
    movsd xmm0, [r8]
    divsd xmm0, [rsp + 8]
    movsd [r8], xmm0
    
    add r8, 8
    dec rcx
    jmp .normalize_loop
    
.softmax_success:
    xor rax, rax
    
    add rsp, 16
    pop r9
    pop r8
    pop rcx
    pop rbx
    pop rbp
    ret

ai_rms_norm:
    ; Compute RMS normalization: x / sqrt(mean(x²) + ε)
    ; Input: RDI = input array, RSI = output array, RDX = length, XMM0 = epsilon
    ; Output: RAX = 0 on success
    
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push r8
    sub rsp, 16
    
    movsd [rsp], xmm0    ; Store epsilon
    
    ; Compute sum of squares
    xorpd xmm0, xmm0     ; sum = 0
    mov rcx, rdx
    mov rbx, rdi
    
.sum_squares:
    test rcx, rcx
    jz .mean_computed
    
    movsd xmm1, [rbx]
    mulsd xmm1, xmm1     ; x²
    addsd xmm0, xmm1
    
    add rbx, 8
    dec rcx
    jmp .sum_squares
    
.mean_computed:
    ; Divide by length to get mean
    cvtsi2sd xmm1, rdx
    divsd xmm0, xmm1
    
    ; Add epsilon
    addsd xmm0, [rsp]
    
    ; Compute sqrt
    call ai_sqrt
    movsd [rsp + 8], xmm0  ; Store sqrt(mean + ε)
    
    ; Normalize each element
    mov rcx, rdx
    mov rbx, rdi
    mov r8, rsi
    
.normalize:
    test rcx, rcx
    jz .rms_success
    
    movsd xmm0, [rbx]
    divsd xmm0, [rsp + 8]
    movsd [r8], xmm0
    
    add rbx, 8
    add r8, 8
    dec rcx
    jmp .normalize
    
.rms_success:
    xor rax, rax
    
    add rsp, 16
    pop r8
    pop rcx
    pop rbx
    pop rbp
    ret

; Additional mathematical functions would be implemented here:
; - ai_layer_norm (Layer normalization)
; - ai_pow (Power function)
; - ai_tan (Tangent function)
; - Bessel functions for advanced operations
; - Gamma function for statistical operations
; - Error function (erf) for GELU variants



ai_pow:
    ; Compute x^y = e^(y * ln(x))
    ; Input: XMM0 = x, XMM1 = y
    ; Output: XMM0 = x^y

    push rbp
    mov rbp, rsp
    sub rsp, 16

    ; Store y
    movsd [rsp], xmm1

    ; Compute ln(x)
    call ai_log

    ; Multiply by y
    movsd xmm1, [rsp]
    mulsd xmm0, xmm1

    ; Compute e^(y * ln(x))
    call ai_exp

    add rsp, 16
    pop rbp
    ret


