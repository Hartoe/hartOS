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
    ; Setup data segments
    mov ax, 0           ; Cannot write to ds/es directly
    mov ds, ax
    mov es, ax

    ; Setup stack
    mov ss, ax
    mov sp, 0x7C00      ; Stack grows downwards, so put pointer as start of program.

    push es
    push word .after
    retf

.after:

    ; Read something from floppy disk
    mov [ebr_drive_number], dl

    ; Show loading message
    mov si, msg_loading
    call puts

    ; Read drive parameters (sectors per track and head count)
    push es
    mov ah, 08h
    int 13h
    jc floppy_error
    pop es

    and cl, 0x3F                        ; Remove top 2 bits
    xor ch, ch
    mov [bdb_sectors_per_track], cx     ; Sector count

    inc dh
    mov [bdb_heads], dh                 ; Head count

    ; Read FAT root directory
    mov ax, [bdb_sectors_per_fat]       ; LBA of root dir = reserved + fats * sectors per fat
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx                              ; ax = (fats * sectors_per_fat)
    add ax, [bdb_reserved_sectors]      ; ax = LBA of root
    push ax

    ; Compute size of root directory = (32 * number_of_entries) / bytes_per_sector
    mov ax, [bdb_dir_entries_count]
    shl ax, 5                           ; ax *= 32
    xor dx, dx                          ; dx = 0
    div word [bdb_bytes_per_sector]     ; number of sectors we need to read

    test dx, dx                         ; if dx != 0, add 1
    jz .root_dir_after
    inc ax                              ; division remainder != 0, add 1
                                        ; this means we have a sector only partially filled with entries
.root_dir_after:
    
    ; Read root directory
    mov cl, al                          ; cl = number of sectors to read = size of root directory
    pop ax                              ; ax = LBA of root directory
    mov dl, [ebr_drive_number]
    mov bx, buffer                      ; es:bx = buffer
    call disk_read

    ; Search for kernel.bin
    xor bx, bx
    mov di, buffer

.search_kernel:
    mov si, file_kernel_bin
    mov cx, 11                          ; compare up to 11 characters
    push di
    repe cmpsb
    pop di
    je .found_kernel

    add di, 32
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_kernel

    ; Kernel not found
    jmp kernel_not_found_error

.found_kernel

    ; di should have the address of the entry
    mov ax, [di + 26]
    mov [kernel_cluster], ax
    
    ; Load FAT from disk into memory
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    ; Read kernel and process FAT chain
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    
    ; Read next cluster
    mov ax, [kernel_cluster]
    add ax, 31                          ; not nice hardcoded value :(

    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]

    ; Compute location of next cluster
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx

    mov si, buffer
    add si, ax
    mov ax, [ds:si]

    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF

.next_cluster_after:
    cmp ax, 0x0FF8
    jae .read_finish

    mov [kernel_cluster], ax
    jmp .load_kernel_loop

.read_finish:
    ; Jump to our kernel
    mov dl, [ebr_drive_number]          ; boot device in dl

    mov ax, KERNEL_LOAD_SEGMENT         ; set segment registers
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    ; Should never happen
    jmp wait_key_and_reboot

    cli                                 ; Disable interupts
    hlt                                 ; Halts CPU

; Error Handlers
floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

kernel_not_found_error:
    mov si, msg_kernel_not_found
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 16h
    jmp 0FFFFh:0

.halt:
    cli
    hlt

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
    mov dl, al                                      ; restore dl
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

msg_loading:            db 'Loading...', ENDL, 0
msg_read_failed:        db 'Read failed from disk!', ENDL, 0
msg_kernel_not_found:   db 'STAGE2.BIN file not found!', ENDL, 0
file_kernel_bin:        db 'STAGE2  BIN'
kernel_cluster:         dw 0

KERNEL_LOAD_SEGMENT     equ 0x2000
KERNEL_LOAD_OFFSET      equ 0

times 510-($-$$) db 0
dw 0AA55h

buffer: