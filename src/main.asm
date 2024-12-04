org 0x7C00              ; Tells the assembler where we expect our code to be loaded
bits 16                 ; Emit 16-bit code

%define ENDL 0x0D, 0x0A

start:
    jmp main            ; Ensure main is start point

; Prints a string to the screen.
; Params:
;   ds:si points to string
puts:
    ; Save registers we will modify
    push si
    push ax

.loop:
    lodsb               ; Loads next character in al
    or al, al           ; verify if character is null
    jz .done

    mov ah, 0x0e
    mov bh, 0
    int 0x10

    jmp .loop

.done:
    ; Pop registers in reverse order
    pop ax
    pop si
    ret

; Main entry point of program
main:
    ; Setup data segments
    mov ax, 0           ; Cannot write to ds/es directly
    mov ds, ax
    mov es, ax

    ; Setup stack
    mov ss, ax
    mov sp, 0x7C00      ; Stack grows downwards, so put pointer as start of program.

    ; Print startup message
    mov si, msg_hello
    call puts

    hlt                 ; Halts CPU

.halt:                  ; Put program in loop so it doesn't access memory it shouldn't
    jmp .halt

; Set message on startup
msg_hello: db 'Hello world!', ENDL, 0

; BOIS expects last sector to be 0AA55h
times 510-($-$$) db 0   ; db emits bytes, times repeats instruction, $-$$ is size of program in nasm
dw 0AA55h               ; Put the final sector