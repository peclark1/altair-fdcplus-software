;=============================================================================
; 3712TEST.COM
;
; Read-only CP/M diagnostic for Altair FDC+ firmware 1.8 Drive Type 8.
;
; The Drive Type 8 firmware emulates the iCOM/Pertec FD3712 interface used by
; Mike Douglas's FDC+3712 software.  Controller access is deliberately direct;
; CP/M BDOS is used only for console output.
;
; First test:
;   - reset controller
;   - select drive 0 / sector 1
;   - restore to track 0
;   - read track 0 / sector 1 (128 bytes)
;   - dump the sector and compare its first 16 bytes with the supplied
;     CPM22v1.0-FDC+3712-48K.dsk image
;
; There are NO write or format commands in this program.
;
; Assemble with Pasmo:
;   pasmo --bin src/3712test.asm build/3712TEST.COM
;
; Controller command sequence and register definitions are derived from
; Mike Douglas's FDC+3712 PROM.ASM v1.0 (2021-09-11).
;=============================================================================

        ORG     0100H

; CP/M BDOS
BDOS            EQU     0005H
BDOS_CONOUT     EQU     02H
BDOS_PRINT      EQU     09H

CR              EQU     0DH
LF              EQU     0AH

; FD3712 controller commands
C_STATUS        EQU     00H
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

; Controller status bits
S_BUSY          EQU     01H
S_SKERR         EQU     02H
S_CRCERR        EQU     08H
S_WRTPRT        EQU     10H
S_NOTRDY        EQU     20H
S_FATAL         EQU     S_SKERR+S_CRCERR+S_NOTRDY

; Interface registers used by Mike's FDC+3712 implementation
CMDOUT          EQU     08H
DATAIN          EQU     08H
DATAOUT         EQU     09H

SECLEN          EQU     128

;-----------------------------------------------------------------------------
; Program entry
;-----------------------------------------------------------------------------
START:
        LD      DE,MSG_BANNER
        CALL    PRINT_STR

        XOR     A
        LD      (DRVNUM),A              ; drive 0
        LD      (TRKNUM),A              ; track 0
        INC     A
        LD      (SECNUM),A              ; sector 1

        LD      DE,MSG_INIT
        CALL    PRINT_STR
        CALL    INIT_CONTROLLER
        JR      C,CMD_TIMEOUT
        LD      (RESTORE_STATUS),A
        CALL    PRINT_STATUS_LINE

        LD      A,(RESTORE_STATUS)
        AND     S_FATAL
        JR      NZ,INIT_FAILED

        LD      DE,MSG_READ
        CALL    PRINT_STR
        CALL    READ_SECTOR
        JR      C,CMD_TIMEOUT
        LD      (READ_STATUS),A
        CALL    PRINT_STATUS_LINE

        LD      A,(READ_STATUS)
        AND     S_FATAL
        JR      NZ,READ_FAILED

        LD      DE,MSG_DUMP
        CALL    PRINT_STR
        CALL    DUMP_SECTOR

        CALL    CHECK_SIGNATURE
        JR      NZ,SIG_BAD
        LD      DE,MSG_SIG_OK
        CALL    PRINT_STR
        JR      EXIT_OK

SIG_BAD:
        LD      DE,MSG_SIG_BAD
        CALL    PRINT_STR
        JR      EXIT_OK

INIT_FAILED:
        LD      DE,MSG_INIT_FAIL
        CALL    PRINT_STR
        JR      EXIT

READ_FAILED:
        LD      DE,MSG_READ_FAIL
        CALL    PRINT_STR
        JR      EXIT

CMD_TIMEOUT:
        LD      DE,MSG_TIMEOUT
        CALL    PRINT_STR
        JR      EXIT

EXIT_OK:
        LD      DE,MSG_DONE
        CALL    PRINT_STR
EXIT:
        RET                             ; return to CCP

;=============================================================================
; FDC+3712 controller routines
;=============================================================================

; INIT_CONTROLLER
; Matches the important portion of Mike Douglas's initAll/reset0 sequence:
; reset controller, select drive/sector, restore selected drive to track zero.
; Returns A=status from RESTORE, carry set only on BUSY timeout.
INIT_CONTROLLER:
        LD      A,C_RESET
        CALL    OUT_CMD

        CALL    SELECT_SECTOR

        LD      A,C_RESTORE
        CALL    DO_CMD
        RET

; READ_SECTOR
; Read the sector selected by DRVNUM/TRKNUM/SECNUM into BUFFER.
; Returns A=read status, carry set only on timeout.
READ_SECTOR:
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
        OR      A                       ; clear carry
        RET

READ_RETURN_SEEK_ERROR:
        LD      A,(SEEK_STATUS)
        OR      A                       ; clear carry
        RET

READ_TRANSFER:
        LD      HL,BUFFER
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

        XOR     A                       ; leave controller in examine-status mode
        OUT     (CMDOUT),A
        LD      A,(READ_STATUS)
        OR      A                       ; clear carry
        RET

; SELECT_SEEK
; Load zero configuration bits, select drive/sector, program track, and seek.
; Returns A=SEEK status; carry indicates BUSY timeout.
SELECT_SEEK:
        XOR     A                       ; FDC+3712 configuration = 0
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

; SELECT_SECTOR
; FD3712 drive number occupies bits 7-6; sector occupies the low six bits.
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

; DO_CMD
; Issue command in A, then wait for BUSY to clear.  Mike's original PROM waits
; indefinitely; this diagnostic adds a bounded timeout so CP/M can recover from
; an absent/misconfigured controller.
; Returns A=status with carry clear, or A=FF/carry set on timeout.
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
        OR      A                       ; clear carry
        RET

; OUT_CMD
; FDC+3712 commands are followed by zero to return the interface to
; examine-status mode, exactly as in Mike's PROM.ASM.
OUT_CMD:
        OUT     (CMDOUT),A
        XOR     A
        OUT     (CMDOUT),A
        RET

;=============================================================================
; Display support (through CP/M BDOS)
;=============================================================================

PRINT_STR:                              ; DE -> '$'-terminated text
        LD      C,BDOS_PRINT
        JP      BDOS

PUTCHAR:                                ; A=character
        PUSH    BC
        PUSH    DE
        LD      E,A
        LD      C,BDOS_CONOUT
        CALL    BDOS
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
        LD      DE,MSG_OK_FLAG
        CALL    PRINT_STR
PRINT_STATUS_EOL:
        LD      DE,MSG_EOL
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

; 8 lines x 16 bytes.  Each line displays an offset, hex bytes, and ASCII.
DUMP_SECTOR:
        LD      HL,BUFFER
        LD      D,0                     ; offset 00,10,...70
        LD      B,8
DUMP_LINE:
        PUSH    BC
        PUSH    HL

        LD      A,D
        CALL    PRINT_HEX8
        LD      A,':'
        CALL    PUTCHAR
        LD      A,' '
        CALL    PUTCHAR

        LD      C,16
DUMP_HEX_LOOP:
        LD      A,(HL)
        CALL    PRINT_HEX8
        LD      A,' '
        CALL    PUTCHAR
        INC     HL
        DEC     C
        JR      NZ,DUMP_HEX_LOOP

        LD      A,' '
        CALL    PUTCHAR
        LD      A,'|'
        CALL    PUTCHAR

        POP     HL
        LD      C,16
DUMP_ASCII_LOOP:
        LD      A,(HL)
        CP      20H
        JR      C,DUMP_DOT
        CP      7FH
        JR      NC,DUMP_DOT
        JR      DUMP_ASCII_OUT
DUMP_DOT:
        LD      A,'.'
DUMP_ASCII_OUT:
        CALL    PUTCHAR
        INC     HL
        DEC     C
        JR      NZ,DUMP_ASCII_LOOP

        LD      A,'|'
        CALL    PUTCHAR
        LD      A,CR
        CALL    PUTCHAR
        LD      A,LF
        CALL    PUTCHAR

        LD      A,D
        ADD     A,10H
        LD      D,A
        POP     BC
        DJNZ    DUMP_LINE
        RET

; Compare first 16 bytes against track 0/sector 1 of the supplied
; CPM22v1.0-FDC+3712-48K.dsk image.
; Returns Z on match, NZ on mismatch.
CHECK_SIGNATURE:
        LD      HL,BUFFER
        LD      DE,EXPECTED_SIG
        LD      B,16
SIG_LOOP:
        LD      A,(DE)
        CP      (HL)
        RET     NZ
        INC     DE
        INC     HL
        DJNZ    SIG_LOOP
        XOR     A                       ; force Z
        RET

;=============================================================================
; Variables / strings / sector buffer
;=============================================================================

DRVNUM:         DB      0
TRKNUM:         DB      0
SECNUM:         DB      1
RETRIES:        DB      0
RESTORE_STATUS: DB      0
SEEK_STATUS:    DB      0
READ_STATUS:    DB      0
STATUS_TMP:     DB      0

EXPECTED_SIG:
        DB      31H,0F6H,00H,0EH,00H,0CDH,0CH,0F4H
        DB      0EH,00H,0CDH,0FH,0F4H,21H,80H,0A6H

MSG_BANNER:
        DB      CR,LF
        DB      'FDC+3712 TEST v0.1 - READ ONLY',CR,LF
        DB      'Drive 0, IBM-3740 track 0 sector 1',CR,LF,'$'
MSG_INIT:
        DB      CR,LF,'Reset/select/restore: $'
MSG_READ:
        DB      'Read T00/S01: $'
MSG_RAW:
        DB      'status=$'
MSG_STATUS_FLAGS:
        DB      '  [$'
MSG_OK_FLAG:
        DB      'OK$'
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
MSG_EOL:
        DB      ']',CR,LF,'$'
MSG_DUMP:
        DB      CR,LF,'128-byte sector dump:',CR,LF,'$'
MSG_SIG_OK:
        DB      CR,LF,'PASS: Mike Douglas CP/M boot-sector signature matched.',CR,LF,'$'
MSG_SIG_BAD:
        DB      CR,LF,'NOTE: sector read succeeded, but the known Mike CP/M signature did not match.',CR,LF,'$'
MSG_INIT_FAIL:
        DB      'Initialization/restore returned an error. No sector read attempted.',CR,LF,'$'
MSG_READ_FAIL:
        DB      'Sector read failed. No disk writes were attempted.',CR,LF,'$'
MSG_TIMEOUT:
        DB      CR,LF,'TIMEOUT waiting for controller BUSY to clear.',CR,LF
        DB      'Check FDC+ firmware/type, cable, drive power, READY, and disk.',CR,LF,'$'
MSG_DONE:
        DB      CR,LF,'Read-only test complete. Returning to CP/M.',CR,LF,'$'

BUFFER:
        DS      SECLEN,0

        END     START
