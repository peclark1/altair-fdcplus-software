;=============================================================================
; 3712BOOT.COM v0.1
;
; Safe load/verify experiment for Altair FDC+ firmware 1.8 Drive Type 8.
;
; This program runs under the existing CP/M system, talks directly to the
; FDC+3712 at ports 08h/09h, and loads the CP/M 2.2 system tracks from Mike
; Douglas's supplied CPM22v1.0-FDC+3712-48K.dsk disk into their intended
; 48K-memory addresses.
;
; IMPORTANT: v0.1 DOES NOT transfer control to the loaded CP/M image.
; It performs reads only, verifies the loaded CCP/BIOS signatures and a
; checksum, reports the result, and returns to the currently running CP/M.
;
; The checked-in Mike Douglas BOOT.ASM has MEMSIZE=56, but the supplied disk
; image is explicitly the 48K build. Its boot sector identifies:
;       CCP base  = A600h
;       BIOS base = BC00h
; The original loader reads 51 system sectors using physical interleave 2:
;       track 0: sectors 3,5,...25,2,4,...26  -> A600h-B27Fh
;       track 1: sectors 1,3,...25,2,4,...26  -> B280h-BF7Fh
;
; Expected additive 16-bit checksum over A600h-BF7Fh for the supplied image:
;       54B0h
;
; There are NO write or format commands in this program.
;
; Assemble with Pasmo:
;   pasmo --bin src/3712boot.asm build/3712BOOT.COM build/3712boot.sym
;=============================================================================

        ORG     0100H

; CP/M BDOS -- console output only
BDOS            EQU     0005H
BDOS_CONOUT     EQU     02H
BDOS_PRINT      EQU     09H

CR              EQU     0DH
LF              EQU     0AH

; FD3712 controller commands
C_READ          EQU     03H
C_SEEK          EQU     09H
C_CLRERR        EQU     0BH
C_RESTORE       EQU     0DH
C_SETTRK        EQU     11H
C_LDCFG         EQU     15H
C_DRVSEC        EQU     21H
C_RDBUF         EQU     40H
C_SHIFT         EQU     41H
C_RESET         EQU     81H

; Controller status bits used by Mike's PROM driver
S_BUSY          EQU     01H
S_SKERR         EQU     02H
S_CRCERR        EQU     08H
S_WRTPRT        EQU     10H
S_NOTRDY        EQU     20H
S_FATAL         EQU     S_SKERR+S_CRCERR+S_NOTRDY

; FDC+3712 I/O registers
CMDOUT          EQU     08H
DATAIN          EQU     08H
DATAOUT         EQU     09H

SECLEN          EQU     128
NUMSEC          EQU     26

; Supplied 48K CP/M image layout
CCPBASE         EQU     0A600H
BIOSBASE        EQU     0BC00H
LOADEND         EQU     0BF80H          ; first byte after loaded image
LOADLEN         EQU     LOADEND-CCPBASE ; 1980h = 6528 bytes
EXPECTED_SUM    EQU     054B0H

;-----------------------------------------------------------------------------
; Program entry
;-----------------------------------------------------------------------------
START:
        LD      DE,MSG_BANNER
        CALL    PRINT_STR

        LD      DE,MSG_INIT
        CALL    PRINT_STR
        XOR     A
        LD      (DRVNUM),A              ; drive 0
        LD      (TRKNUM),A
        INC     A
        LD      (SECNUM),A              ; sector 1 default for restore

        CALL    INIT_CONTROLLER
        JR      C,INIT_TIMEOUT
        LD      (LAST_STATUS),A
        CALL    PRINT_STATUS_LINE

        LD      A,(LAST_STATUS)
        AND     S_FATAL
        JR      NZ,INIT_FAILED

        XOR     A
        LD      (SECTOR_COUNT),A

        ; Mike's cold loader starts track 0 at physical sector 3 with the
        ; destination corresponding to CCP+128. The wrap in LOAD_TRACK_IMAGE
        ; later reads physical sector 2 into CCPBASE itself.
        LD      DE,MSG_LOAD_T0
        CALL    PRINT_STR
        XOR     A
        LD      (TRKNUM),A              ; track 0
        LD      A,3
        LD      HL,CCPBASE+SECLEN        ; A680h
        CALL    LOAD_TRACK_IMAGE
        JR      C,LOAD_FAILED
        LD      DE,MSG_OK
        CALL    PRINT_STR

        LD      DE,MSG_LOAD_T1
        CALL    PRINT_STR
        LD      A,1
        LD      (TRKNUM),A              ; track 1
        LD      HL,CCPBASE+SECLEN*(NUMSEC-1) ; B280h
        LD      A,1
        CALL    LOAD_TRACK_IMAGE
        JR      C,LOAD_FAILED
        LD      DE,MSG_OK
        CALL    PRINT_STR

        LD      DE,MSG_LOADED1
        CALL    PRINT_STR
        LD      A,(SECTOR_COUNT)
        CALL    PRINT_DEC2
        LD      DE,MSG_LOADED2
        CALL    PRINT_STR

        ; Verify CCP first 16 bytes.
        LD      DE,MSG_CCP_SIG
        CALL    PRINT_STR
        LD      HL,CCPBASE
        LD      DE,EXPECTED_CCP_SIG
        LD      B,16
        CALL    COMPARE_BYTES
        JR      NZ,VERIFY_FAILED_CCP
        LD      DE,MSG_PASS
        CALL    PRINT_STR

        ; Verify BIOS jump table first 16 bytes.
        LD      DE,MSG_BIOS_SIG
        CALL    PRINT_STR
        LD      HL,BIOSBASE
        LD      DE,EXPECTED_BIOS_SIG
        LD      B,16
        CALL    COMPARE_BYTES
        JR      NZ,VERIFY_FAILED_BIOS
        LD      DE,MSG_PASS
        CALL    PRINT_STR

        ; Additive checksum across the complete 51-sector loaded region.
        LD      DE,MSG_CHECKSUM
        CALL    PRINT_STR
        CALL    CHECKSUM_LOADED_IMAGE    ; DE=sum
        PUSH    DE
        CALL    PRINT_HEX16_DE
        POP     DE

        LD      A,D
        CP      54H
        JR      NZ,VERIFY_FAILED_SUM
        LD      A,E
        CP      0B0H
        JR      NZ,VERIFY_FAILED_SUM
        LD      DE,MSG_PASS_SUFFIX
        CALL    PRINT_STR

        LD      DE,MSG_SUCCESS
        CALL    PRINT_STR
        RET

INIT_TIMEOUT:
        LD      DE,MSG_INIT_TIMEOUT
        CALL    PRINT_STR
        RET

INIT_FAILED:
        LD      DE,MSG_INIT_ERROR
        CALL    PRINT_STR
        RET

LOAD_FAILED:
        LD      DE,MSG_LOAD_ERROR1
        CALL    PRINT_STR
        CALL    PRINT_CURRENT_TS
        LD      DE,MSG_LOAD_ERROR2
        CALL    PRINT_STR
        LD      A,(LOAD_STATUS)
        CP      0FFH
        JR      Z,LOAD_FAILED_TIMEOUT
        CALL    PRINT_STATUS_LINE
        LD      DE,MSG_ABORT
        CALL    PRINT_STR
        RET

LOAD_FAILED_TIMEOUT:
        LD      DE,MSG_TIMEOUT
        CALL    PRINT_STR
        LD      DE,MSG_ABORT
        CALL    PRINT_STR
        RET

VERIFY_FAILED_CCP:
        LD      DE,MSG_FAIL
        CALL    PRINT_STR
        LD      DE,MSG_VERIFY_CCP
        CALL    PRINT_STR
        RET

VERIFY_FAILED_BIOS:
        LD      DE,MSG_FAIL
        CALL    PRINT_STR
        LD      DE,MSG_VERIFY_BIOS
        CALL    PRINT_STR
        RET

VERIFY_FAILED_SUM:
        LD      DE,MSG_FAIL_SUFFIX
        CALL    PRINT_STR
        LD      DE,MSG_VERIFY_SUM
        CALL    PRINT_STR
        RET

;=============================================================================
; CP/M system-track loader
;=============================================================================

; LOAD_TRACK_IMAGE
;   A  = starting physical sector (track 0 uses 3, track 1 uses 1)
;   HL = destination address associated with that sector
;   TRKNUM already contains track number.
;
; This is the same interleave-2 address/sector progression used by Mike's
; BOOT.ASM:  odd physical sectors first, then even physical sectors. The
; address advances 256 bytes per physical +2 sector. At the wrap, 25*128
; bytes are subtracted so the sectors land in contiguous logical memory.
;
; Returns carry set on any read/seek/timeout error. LOAD_STATUS contains
; either controller status or FFh for BUSY timeout.
LOAD_TRACK_IMAGE:
        LD      (CUR_SECTOR),A
        LD      (LOAD_ADDR),HL

LOAD_TRACK_LOOP:
        LD      A,(CUR_SECTOR)
        LD      (SECNUM),A
        LD      HL,(LOAD_ADDR)
        LD      (DMA_PTR),HL

        CALL    READ_SECTOR_TO_DMA
        JR      NC,LOAD_TRACK_STATUS
        LD      A,0FFH
        LD      (LOAD_STATUS),A
        SCF
        RET

LOAD_TRACK_STATUS:
        LD      (LOAD_STATUS),A
        AND     S_FATAL
        JR      Z,LOAD_TRACK_READ_OK
        SCF
        RET

LOAD_TRACK_READ_OK:
        LD      A,(SECTOR_COUNT)
        INC     A
        LD      (SECTOR_COUNT),A

        ; Next logical destination is +2 sectors = +0100h.
        LD      HL,(LOAD_ADDR)
        LD      DE,0100H
        ADD     HL,DE
        LD      (LOAD_ADDR),HL

        ; Next physical sector is +2.
        LD      A,(CUR_SECTOR)
        ADD     A,2
        CP      NUMSEC+1
        JR      C,LOAD_TRACK_SET_NEXT

        ; Wrap 27->2 or 28->3 and rewind the destination by 25 sectors.
        SUB     NUMSEC-1                ; subtract 25
        LD      (CUR_SECTOR),A
        LD      HL,(LOAD_ADDR)
        LD      DE,0F380H               ; -0C80h = -(25*128)
        ADD     HL,DE
        LD      (LOAD_ADDR),HL

        CP      2                       ; first wrap continues with evens
        JR      Z,LOAD_TRACK_LOOP

        ; Second wrap yields 3: the complete track has been traversed.
        OR      A                       ; clear carry
        RET

LOAD_TRACK_SET_NEXT:
        LD      (CUR_SECTOR),A
        JR      LOAD_TRACK_LOOP

;=============================================================================
; FDC+3712 controller routines -- read only
;=============================================================================

INIT_CONTROLLER:
        LD      A,C_RESET
        CALL    OUT_CMD
        CALL    SELECT_SECTOR
        LD      A,C_RESTORE
        CALL    DO_CMD
        RET

; Read selected TRKNUM/SECNUM into address DMA_PTR.
; Returns A=controller status, carry set only on BUSY timeout.
READ_SECTOR_TO_DMA:
        CALL    SELECT_SEEK
        RET     C
        LD      (SEEK_STATUS),A
        AND     S_FATAL
        JR      NZ,READ_RETURN_SEEK_ERROR

        LD      A,10
        LD      (RETRIES),A

READ_RETRY:
        LD      A,C_READ
        CALL    DO_CMD
        RET     C
        LD      (READ_STATUS),A
        AND     S_NOTRDY+S_CRCERR
        JR      Z,READ_TRANSFER

        LD      A,C_CLRERR
        CALL    OUT_CMD
        LD      A,(RETRIES)
        DEC     A
        LD      (RETRIES),A
        JR      NZ,READ_RETRY

        LD      A,(READ_STATUS)
        OR      A
        RET

READ_RETURN_SEEK_ERROR:
        LD      A,(SEEK_STATUS)
        OR      A
        RET

READ_TRANSFER:
        LD      HL,(DMA_PTR)
        LD      B,SECLEN
READ_BUFFER_LOOP:
        LD      A,C_RDBUF
        OUT     (CMDOUT),A
        IN      A,(DATAIN)
        LD      (HL),A

        LD      A,C_SHIFT
        OUT     (CMDOUT),A

        INC     HL
        DJNZ    READ_BUFFER_LOOP

        XOR     A                       ; leave examine-status mode selected
        OUT     (CMDOUT),A
        LD      A,(READ_STATUS)
        OR      A
        RET

SELECT_SEEK:
        XOR     A                       ; FDC+3712 configuration = zero
        OUT     (DATAOUT),A
        LD      A,C_LDCFG
        CALL    OUT_CMD

        CALL    SELECT_SECTOR

        LD      A,(TRKNUM)
        OUT     (DATAOUT),A
        LD      A,C_SETTRK
        CALL    OUT_CMD

        LD      A,C_SEEK
        CALL    DO_CMD
        RET

SELECT_SECTOR:
        LD      A,(DRVNUM)
        AND     03H
        RRCA
        RRCA                            ; drive 0..3 -> bits 7..6
        LD      C,A
        LD      A,(SECNUM)
        OR      C
        OUT     (DATAOUT),A
        LD      A,C_DRVSEC
        CALL    OUT_CMD
        RET

DO_CMD:
        CALL    OUT_CMD
        LD      BC,0FFFFH
DO_CMD_WAIT:
        IN      A,(DATAIN)
        AND     S_BUSY
        JR      Z,DO_CMD_DONE
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,DO_CMD_WAIT

        LD      A,0FFH
        SCF
        RET

DO_CMD_DONE:
        IN      A,(DATAIN)
        OR      A
        RET

OUT_CMD:
        OUT     (CMDOUT),A
        XOR     A
        OUT     (CMDOUT),A
        RET

;=============================================================================
; Verification
;=============================================================================

; HL=memory, DE=expected bytes, B=count. Returns Z if all match.
COMPARE_BYTES:
COMPARE_LOOP:
        LD      A,(DE)
        CP      (HL)
        RET     NZ
        INC     DE
        INC     HL
        DJNZ    COMPARE_LOOP
        XOR     A
        RET

; Add all bytes A600h-BF7Fh. Returns 16-bit sum in DE.
CHECKSUM_LOADED_IMAGE:
        LD      HL,CCPBASE
        LD      BC,LOADLEN
        LD      DE,0000H
CHECKSUM_LOOP:
        LD      A,E
        ADD     A,(HL)
        LD      E,A
        JR      NC,CHECKSUM_NO_CARRY
        INC     D
CHECKSUM_NO_CARRY:
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CHECKSUM_LOOP
        RET

;=============================================================================
; Display support
;=============================================================================

PRINT_STR:                              ; DE -> '$'-terminated string
        LD      C,BDOS_PRINT
        JP      BDOS

; Preserve all pointer/counter registers around BDOS console output. This is
; the v0.2.1 fix proven in 3712TEST on the physical IMSAI.
PUTCHAR:                                ; A=character
        PUSH    BC
        PUSH    DE
        PUSH    HL
        LD      E,A
        LD      C,BDOS_CONOUT
        CALL    BDOS
        POP     HL
        POP     DE
        POP     BC
        RET

PRINT_HEX8:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    PRINT_NIBBLE
        POP     AF
PRINT_NIBBLE:
        AND     0FH
        ADD     A,'0'
        CP      ':'
        JR      C,PRINT_NIBBLE_GO
        ADD     A,7
PRINT_NIBBLE_GO:
        JP      PUTCHAR

PRINT_HEX16_DE:
        LD      A,D
        CALL    PRINT_HEX8
        LD      A,E
        JP      PRINT_HEX8

PRINT_DEC2:
        LD      B,'0'
PRINT_DEC2_TENS:
        CP      10
        JR      C,PRINT_DEC2_ONES
        SUB     10
        INC     B
        JR      PRINT_DEC2_TENS
PRINT_DEC2_ONES:
        PUSH    AF
        LD      A,B
        CALL    PUTCHAR
        POP     AF
        ADD     A,'0'
        JP      PUTCHAR

PRINT_CURRENT_TS:
        LD      A,'T'
        CALL    PUTCHAR
        LD      A,(TRKNUM)
        CALL    PRINT_DEC2
        LD      A,'/'
        CALL    PUTCHAR
        LD      A,'S'
        CALL    PUTCHAR
        LD      A,(SECNUM)
        JP      PRINT_DEC2

PRINT_STATUS_LINE:                      ; A=status
        PUSH    AF
        LD      DE,MSG_RAW
        CALL    PRINT_STR
        POP     AF
        PUSH    AF
        CALL    PRINT_HEX8
        LD      DE,MSG_STATUS_FLAGS
        CALL    PRINT_STR
        POP     AF
        LD      (STATUS_TMP),A

        LD      A,(STATUS_TMP)
        AND     S_BUSY
        CALL    NZ,PRINT_BUSY
        LD      A,(STATUS_TMP)
        AND     S_SKERR
        CALL    NZ,PRINT_SKERR
        LD      A,(STATUS_TMP)
        AND     S_CRCERR
        CALL    NZ,PRINT_CRCERR
        LD      A,(STATUS_TMP)
        AND     S_WRTPRT
        CALL    NZ,PRINT_WRTPRT
        LD      A,(STATUS_TMP)
        AND     S_NOTRDY
        CALL    NZ,PRINT_NOTRDY

        LD      A,(STATUS_TMP)
        AND     S_BUSY+S_SKERR+S_CRCERR+S_WRTPRT+S_NOTRDY
        JR      NZ,PRINT_STATUS_EOL
        LD      DE,MSG_STATUS_OK
        CALL    PRINT_STR
PRINT_STATUS_EOL:
        LD      DE,MSG_STATUS_END
        JP      PRINT_STR

PRINT_BUSY:
        LD      DE,MSG_BUSY
        JP      PRINT_STR
PRINT_SKERR:
        LD      DE,MSG_SKERR
        JP      PRINT_STR
PRINT_CRCERR:
        LD      DE,MSG_CRCERR
        JP      PRINT_STR
PRINT_WRTPRT:
        LD      DE,MSG_WRTPRT
        JP      PRINT_STR
PRINT_NOTRDY:
        LD      DE,MSG_NOTRDY
        JP      PRINT_STR

;=============================================================================
; Data
;=============================================================================

DRVNUM:         DB      0
TRKNUM:         DB      0
SECNUM:         DB      1
CUR_SECTOR:     DB      0
RETRIES:        DB      0
SECTOR_COUNT:   DB      0
SEEK_STATUS:    DB      0
READ_STATUS:    DB      0
LAST_STATUS:    DB      0
LOAD_STATUS:    DB      0
STATUS_TMP:     DB      0
LOAD_ADDR:      DW      0
DMA_PTR:        DW      0

EXPECTED_CCP_SIG:
        DB      0C3H,05CH,0A9H,0C3H,058H,0A9H,07FH,000H
        DB      043H,06FH,070H,079H,072H,069H,067H,068H

EXPECTED_BIOS_SIG:
        DB      0C3H,036H,0BCH,0C3H,092H,0BCH,0C3H,0E1H
        DB      0BCH,0C3H,0EEH,0BCH,0C3H,0FDH,0BCH,0C3H

MSG_BANNER:
        DB      CR,LF
        DB      'FDC+3712 BOOT TEST v0.1 - LOAD/VERIFY ONLY',CR,LF
        DB      'Mike Douglas 48K CP/M 2.2 image; drive 0',CR,LF
        DB      'NO control transfer and NO disk writes.',CR,LF,'$'
MSG_INIT:
        DB      CR,LF,'Reset/select/restore: $'
MSG_LOAD_T0:
        DB      'Load system track 0 (25 sectors): $'
MSG_LOAD_T1:
        DB      'Load system track 1 (26 sectors): $'
MSG_OK:
        DB      'OK',CR,LF,'$'
MSG_LOADED1:
        DB      'Loaded $'
MSG_LOADED2:
        DB      ' sectors into A600-BF7F.',CR,LF,CR,LF,'$'
MSG_CCP_SIG:
        DB      'CCP signature at A600:  $'
MSG_BIOS_SIG:
        DB      'BIOS signature at BC00: $'
MSG_CHECKSUM:
        DB      'Checksum A600-BF7F:     $'
MSG_PASS:
        DB      'PASS',CR,LF,'$'
MSG_FAIL:
        DB      'FAIL',CR,LF,'$'
MSG_PASS_SUFFIX:
        DB      '  PASS',CR,LF,'$'
MSG_FAIL_SUFFIX:
        DB      '  FAIL',CR,LF,'$'
MSG_SUCCESS:
        DB      CR,LF
        DB      'PASS: complete 48K CP/M system image loaded and verified.',CR,LF
        DB      'Boot jump intentionally NOT performed; returning to current CP/M.',CR,LF,'$'
MSG_VERIFY_CCP:
        DB      'Loaded CCP does not match the supplied 48K reference image.',CR,LF
        DB      'No boot jump was attempted.',CR,LF,'$'
MSG_VERIFY_BIOS:
        DB      'Loaded BIOS does not match the supplied 48K reference image.',CR,LF
        DB      'No boot jump was attempted.',CR,LF,'$'
MSG_VERIFY_SUM:
        DB      'Expected checksum is 54B0h for the supplied 48K image.',CR,LF
        DB      'No boot jump was attempted.',CR,LF,'$'
MSG_LOAD_ERROR1:
        DB      CR,LF,'Read failed at $'
MSG_LOAD_ERROR2:
        DB      ': $'
MSG_TIMEOUT:
        DB      'TIMEOUT waiting for BUSY.',CR,LF,'$'
MSG_ABORT:
        DB      'Load aborted. No disk writes and no boot jump were attempted.',CR,LF,'$'
MSG_INIT_TIMEOUT:
        DB      'TIMEOUT waiting for controller BUSY during initialization.',CR,LF,'$'
MSG_INIT_ERROR:
        DB      'Initialization/restore returned a fatal controller status.',CR,LF,'$'
MSG_RAW:
        DB      'status=$'
MSG_STATUS_FLAGS:
        DB      '  [$'
MSG_STATUS_OK:
        DB      'OK$'
MSG_STATUS_END:
        DB      ']',CR,LF,'$'
MSG_BUSY:
        DB      'BUSY $'
MSG_SKERR:
        DB      'SEEK-ERROR $'
MSG_CRCERR:
        DB      'CRC-ERROR $'
MSG_WRTPRT:
        DB      'WRITE-PROTECT $'
MSG_NOTRDY:
        DB      'NOT-READY $'

        END     START
