org 0x7C00              ; Tells the assembler where we expect our code to be loaded
bits 16                 ; Emit 16-bit code

%define ENDL 0x0D, 0x0A

; FAT12 header
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; extended boot record
ebr_drive_number:           db 0                    ; 0x00 floppy, 0x80 hdd, useless
                            db 0                    ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; serial number, value doesn't matter
ebr_volume_label:           db 'NANOBYTE OS'        ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '           ; 8 bytes

;
; Code goes here
;

start:
    jmp main            ; Ensure main is start point

; Prints a string to the screen.
; Params:
;   ds:si points to string
puts:
    ; Save registers we will modify
    push si
    push ax
    push bx

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
    pop bx
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

    ; Read something from floppy disk
    mov [ebr_drive_number], dl
    mov ax, 1
    mov cl, 1
    mov bx, 0x7E00
    call disk_read

    ; Print startup message
    mov si, msg_hello
    call puts

    cli
    hlt                 ; Halts CPU

; Error Handlers
floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h
    jmp 0FFFFh:0

.halt:
    cli
    hlt

; Disk routines

; Converts an LBA address to a CHS address
; Params:
;   - ax: LBA address
; Returns:
;   - cx [bits 0-5]: sector number
;   - cx [bits 6-15]: cylinder
;   - dh: head
lba_to_chs:
    push ax
    push dx
    
    xor dx, dx                                      ; dx = 0
    div word [bdb_sectors_per_track]                ; ax = LBA / sectors per track

    inc dx                                          ; dx = (LBA % sectors per track + 1) = sector
    mov cx, dx                                      ; cx = sector

    xor dx, dx                                      ; dx = 0
    div word [bdb_heads]                            ; ax = (LBA / sectors per track) / heads

    mov dh, dl                                      ; dh = head
    mov ch, al                                      ; ch = cylinder
    shl ah, 6
    or cl, ah                                       ; put upper 2 bits of cylinder in cl

    pop ax
    mov dl, al                                     ; restor DL
    pop ax
    ret

; Reads sectors from a disk
; Params:
;   - ax: LBA address
;   - cl: number of sectors to read
;   - dl: drive number
;   - es:bx: memory address where to store read data
disk_read:
    push ax
    push bx
    push cx
    push dx
    push di

    push cx                                         ; Save CL
    call lba_to_chs                                 ; compute CHS
    pop ax                                          ; al = cl

    mov ah, 02h
    mov di, 3                                       ; retry count

.retry:
    pusha                                           ; save all registers
    stc                                             ; set carry flag
    int 13h                                         ; if stc cleared = success
    jnc .done

    ; read failed
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    jmp floppy_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Resets disk controller
; Param:
;   - dl: drive number
disk_reset:
    pusha
    mov ah, 0
    stc
    int 13h
    jc floppy_error
    popa
    ret

; Set message on startup
msg_hello:              db 'Hello world!', ENDL, 0
msg_read_failed:        db 'Read failed from disk!', ENDL, 0

; BOIS expects last sector to be 0AA55h
times 510-($-$$) db 0   ; db emits bytes, times repeats instruction, $-$$ is size of program in nasm
dw 0AA55h               ; Put the final sector