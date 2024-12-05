org 0x0                 ; Tells the assembler where we expect our code to be loaded
bits 16                 ; Emit 16-bit code

%define ENDL 0x0D, 0x0A

start:
    ; Print startup message
    mov si, msg_hello
    call puts

.halt:
    cli
    hlt                 ; Halts CPU

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

; Set message on startup
msg_hello: db 'Hello from KERNEL!', ENDL, 0