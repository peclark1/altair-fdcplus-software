;=============================================================================
; 3712TEST.COM v0.2
;
; Read-only CP/M diagnostic for Altair FDC+ firmware 1.8 Drive Type 8.
;
; The Drive Type 8 firmware emulates the iCOM/Pertec FD3712 interface used by
; Mike Douglas's FDC+3712 software. Controller access is deliberately direct;
; CP/M BDOS is used only for console output.
;
; v0.2:
;   - optional decimal track/sector arguments: 3712TEST [track [sector]]
;   - defaults to track 0, sector 1
;   - reads/dumps the requested 128-byte sector
;   - recognizes Mike Douglas's boot-sector signature when reading T0/S1
;   - directly reads and displays the CP/M 2.2 directory from track 2 using
;     the standard 8-inch SSSD skew table and DPB from Mike's BIOS.ASM
;
; There are NO write or format commands in this program.
;
; Assemble with Pasmo:
;   pasmo --bin src/3712test.asm build/3712TEST.COM
;
; Controller command sequence and register definitions are derived from
; Mike Douglas's FDC+3712 PROM.ASM v1.0 (2021-09-11).
; Disk layout values are derived from his BIOS.ASM:
;   26 x 128-byte sectors/track, OFF=2, DRM=63, 1K blocks, AL0=C0h,
;   standard IBM-3740/CP/M interleave of 6.
;=============================================================================

        ORG     0100H

; CP/M BDOS
BDOS            EQU     0005H
BDOS_CONOUT     EQU     02H
BDOS_PRINT      EQU     09H
CMDTAIL_LEN     EQU     0080H
CMDTAIL         EQU     0081H

CR              EQU     0DH
LF              EQU     0AH
SPACE           EQU     20H

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

; Controller status bits used by Mike's driver
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
NUMTRK          EQU     77
NUMSEC          EQU     26
DIRTRACK        EQU     2
DIRSECS         EQU     16              ; 64 entries x 32 bytes / 128

;-----------------------------------------------------------------------------
; Program entry
;-----------------------------------------------------------------------------
START:
        LD      DE,MSG_BANNER
        CALL    PRINT_STR

        XOR     A
        LD      (DRVNUM),A              ; drive 0
        LD      (TRKNUM),A              ; default track 0
        INC     A
        LD      (SECNUM),A              ; default sector 1

        CALL    PARSE_ARGS
        JR      NC,ARGS_OK
        LD      DE,MSG_USAGE
        CALL    PRINT_STR
        RET

ARGS_OK:
        LD      DE,MSG_TARGET1
        CALL    PRINT_STR
        LD      A,(TRKNUM)
        CALL    PRINT_DEC2
        LD      DE,MSG_TARGET2
        CALL    PRINT_STR
        LD      A,(SECNUM)
        CALL    PRINT_DEC2
        LD      DE,MSG_EOL_ONLY
        CALL    PRINT_STR

        LD      DE,MSG_INIT
        CALL    PRINT_STR
        CALL    INIT_CONTROLLER
        JR      C,CMD_TIMEOUT
        LD      (RESTORE_STATUS),A
        CALL    PRINT_STATUS_LINE

        LD      A,(RESTORE_STATUS)
        AND     S_FATAL
        JR      NZ,INIT_FAILED

        CALL    PRINT_READ_LABEL
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

        LD      A,(TRKNUM)
        OR      A
        JR      NZ,SKIP_SIGNATURE
        LD      A,(SECNUM)
        CP      1
        JR      NZ,SKIP_SIGNATURE

        CALL    CHECK_SIGNATURE
        JR      NZ,SIG_BAD
        LD      DE,MSG_SIG_OK
        CALL    PRINT_STR
        JR      DO_DIRECTORY

SIG_BAD:
        LD      DE,MSG_SIG_BAD
        CALL    PRINT_STR
        JR      DO_DIRECTORY

SKIP_SIGNATURE:
        LD      DE,MSG_SIG_SKIP
        CALL    PRINT_STR

DO_DIRECTORY:
        CALL    LIST_DIRECTORY
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
; Command tail parsing
;=============================================================================

; Syntax: 3712TEST [track [sector]]
; Decimal track 0-76, sector 1-26. No arguments defaults to T0/S1.
; Returns carry on syntax/range error.
PARSE_ARGS:
        LD      A,(CMDTAIL_LEN)
        LD      B,A
        LD      HL,CMDTAIL
        CALL    SKIP_SPACES
        LD      A,B
        OR      A
        RET     Z

        CALL    PARSE_DEC8
        RET     C
        CP      NUMTRK
        JR      NC,PARSE_ARGS_BAD
        LD      (TRKNUM),A

        CALL    SKIP_SPACES
        LD      A,B
        OR      A
        RET     Z

        CALL    PARSE_DEC8
        RET     C
        OR      A
        JR      Z,PARSE_ARGS_BAD
        CP      NUMSEC+1
        JR      NC,PARSE_ARGS_BAD
        LD      (SECNUM),A

        CALL    SKIP_SPACES
        LD      A,B
        OR      A
        JR      NZ,PARSE_ARGS_BAD
        OR      A                       ; clear carry
        RET

PARSE_ARGS_BAD:
        SCF
        RET

SKIP_SPACES:
        LD      A,B
        OR      A
        RET     Z
        LD      A,(HL)
        CP      SPACE
        RET     NZ
        INC     HL
        DEC     B
        JR      SKIP_SPACES

; Parse an unsigned decimal byte from HL/B command-tail cursor.
; Leaves HL/B positioned at first non-digit. Returns A=value, carry on error.
PARSE_DEC8:
        LD      A,B
        OR      A
        JR      Z,PARSE_DEC_BAD
        LD      A,(HL)
        CP      '0'
        JR      C,PARSE_DEC_BAD
        CP      '9'+1
        JR      NC,PARSE_DEC_BAD

        LD      C,0
PARSE_DEC_LOOP:
        LD      A,B
        OR      A
        JR      Z,PARSE_DEC_DONE
        LD      A,(HL)
        CP      '0'
        JR      C,PARSE_DEC_DONE
        CP      '9'+1
        JR      NC,PARSE_DEC_DONE
        SUB     '0'
        LD      E,A                     ; digit

        LD      A,C                     ; value * 10 + digit
        ADD     A,A                     ; *2
        JR      C,PARSE_DEC_BAD
        LD      D,A                     ; save *2
        ADD     A,A                     ; *4
        JR      C,PARSE_DEC_BAD
        ADD     A,A                     ; *8
        JR      C,PARSE_DEC_BAD
        ADD     A,D                     ; *10
        JR      C,PARSE_DEC_BAD
        ADD     A,E
        JR      C,PARSE_DEC_BAD
        LD      C,A

        INC     HL
        DEC     B
        JR      PARSE_DEC_LOOP

PARSE_DEC_DONE:
        LD      A,C
        OR      A                       ; clear carry
        RET

PARSE_DEC_BAD:
        SCF
        RET

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
; Issue command in A, then wait for BUSY to clear. Mike's original PROM waits
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
; CP/M directory reader
;=============================================================================

; Mike's BIOS DPB reserves two tracks (OFF=2). With 64 directory entries and
; two 1K directory blocks (AL0=C0h), the directory occupies 16 logical sectors
; at the beginning of track 2. These are their physical sector numbers after
; the standard 8-inch SSSD skew/interleave-6 translation.
DIR_PHYS_SECTORS:
        DB      01,07,13,19,25,05,11,17
        DB      23,03,09,15,21,02,08,14

LIST_DIRECTORY:
        LD      DE,MSG_DIR_HEADER
        CALL    PRINT_STR

        LD      A,DIRTRACK
        LD      (TRKNUM),A
        XOR     A
        LD      (DIR_COUNT),A

        LD      HL,DIR_PHYS_SECTORS
        LD      B,DIRSECS
DIR_SECTOR_LOOP:
        LD      A,(HL)
        LD      (SECNUM),A
        INC     HL
        PUSH    HL
        PUSH    BC

        CALL    READ_SECTOR
        JR      C,DIR_TIMEOUT
        LD      (READ_STATUS),A
        AND     S_FATAL
        JR      NZ,DIR_READ_ERROR

        CALL    PROCESS_DIR_SECTOR
        POP     BC
        POP     HL
        DJNZ    DIR_SECTOR_LOOP

        LD      A,(DIR_COUNT)
        OR      A
        JR      NZ,DIR_HAVE_FILES
        LD      DE,MSG_DIR_EMPTY
        CALL    PRINT_STR
        RET

DIR_HAVE_FILES:
        LD      DE,MSG_DIR_TOTAL1
        CALL    PRINT_STR
        LD      A,(DIR_COUNT)
        CALL    PRINT_DEC2
        LD      DE,MSG_DIR_TOTAL2
        CALL    PRINT_STR
        RET

DIR_TIMEOUT:
        POP     BC
        POP     HL
        LD      DE,MSG_DIR_TIMEOUT1
        CALL    PRINT_STR
        CALL    PRINT_CURRENT_TS
        LD      DE,MSG_DIR_TIMEOUT2
        CALL    PRINT_STR
        RET

DIR_READ_ERROR:
        LD      A,(READ_STATUS)
        LD      (STATUS_TMP),A
        POP     BC
        POP     HL
        LD      DE,MSG_DIR_ERROR1
        CALL    PRINT_STR
        CALL    PRINT_CURRENT_TS
        LD      DE,MSG_DIR_ERROR2
        CALL    PRINT_STR
        LD      A,(STATUS_TMP)
        CALL    PRINT_STATUS_LINE
        RET

; Process four 32-byte CP/M 2.2 directory entries in BUFFER.
; We display valid user 0-15 entries whose extent number is zero. With EXM=0
; on this disk, that yields one DIR-style line per file instead of repeating
; subsequent extents of larger files.
PROCESS_DIR_SECTOR:
        LD      HL,BUFFER
        LD      B,4
PROCESS_DIR_ENTRY:
        LD      A,(HL)
        CP      0E5H                    ; deleted/unused
        JR      Z,PROCESS_DIR_NEXT
        CP      10H                     ; only CP/M users 0-15
        JR      NC,PROCESS_DIR_NEXT
        LD      (DIR_USER),A

        PUSH    HL
        LD      DE,12
        ADD     HL,DE
        LD      A,(HL)                  ; EX extent number
        POP     HL
        OR      A
        JR      NZ,PROCESS_DIR_NEXT

        PUSH    BC
        CALL    PRINT_DIR_ENTRY
        POP     BC
        LD      A,(DIR_COUNT)
        INC     A
        LD      (DIR_COUNT),A

PROCESS_DIR_NEXT:
        LD      DE,32
        ADD     HL,DE
        DJNZ    PROCESS_DIR_ENTRY
        RET

; HL -> directory entry. Print: U00 FILENAME.EXT
PRINT_DIR_ENTRY:
        PUSH    HL

        LD      A,'U'
        CALL    PUTCHAR
        LD      A,(DIR_USER)
        CALL    PRINT_DEC2
        LD      A,SPACE
        CALL    PUTCHAR

        INC     HL                      ; filename starts at +1
        LD      B,8
PRINT_DIR_NAME:
        LD      A,(HL)
        AND     7FH                     ; strip CP/M attribute high bit
        CP      SPACE
        JR      Z,PRINT_DIR_NAME_SKIP
        CALL    PUTCHAR
PRINT_DIR_NAME_SKIP:
        INC     HL
        DJNZ    PRINT_DIR_NAME

        ; HL now points at three extension bytes. See whether extension exists.
        PUSH    HL
        LD      B,3
PRINT_DIR_EXT_CHECK:
        LD      A,(HL)
        AND     7FH
        CP      SPACE
        JR      NZ,PRINT_DIR_EXT_YES
        INC     HL
        DJNZ    PRINT_DIR_EXT_CHECK
        POP     HL
        JR      PRINT_DIR_EOL

PRINT_DIR_EXT_YES:
        POP     HL
        LD      A,'.'
        CALL    PUTCHAR
        LD      B,3
PRINT_DIR_EXT:
        LD      A,(HL)
        AND     7FH
        CP      SPACE
        JR      Z,PRINT_DIR_EXT_SKIP
        CALL    PUTCHAR
PRINT_DIR_EXT_SKIP:
        INC     HL
        DJNZ    PRINT_DIR_EXT

PRINT_DIR_EOL:
        LD      A,CR
        CALL    PUTCHAR
        LD      A,LF
        CALL    PUTCHAR
        POP     HL
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

; Print A as two decimal digits (00-99).
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

PRINT_READ_LABEL:
        LD      DE,MSG_READ1
        CALL    PRINT_STR
        LD      A,(TRKNUM)
        CALL    PRINT_DEC2
        LD      DE,MSG_READ2
        CALL    PRINT_STR
        LD      A,(SECNUM)
        CALL    PRINT_DEC2
        LD      DE,MSG_READ3
        JP      PRINT_STR

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

; 8 lines x 16 bytes. Each line displays an offset, hex bytes, and ASCII.
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
        LD      A,SPACE
        CALL    PUTCHAR

        LD      C,16
DUMP_HEX_LOOP:
        LD      A,(HL)
        CALL    PRINT_HEX8
        LD      A,SPACE
        CALL    PUTCHAR
        INC     HL
        DEC     C
        JR      NZ,DUMP_HEX_LOOP

        LD      A,SPACE
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
DIR_USER:       DB      0
DIR_COUNT:      DB      0

EXPECTED_SIG:
        DB      31H,0F6H,00H,0EH,00H,0CDH,0CH,0F4H
        DB      0EH,00H,0CDH,0FH,0F4H,21H,80H,0A6H

MSG_BANNER:
        DB      CR,LF
        DB      'FDC+3712 TEST v0.2 - READ ONLY',CR,LF
        DB      'Drive 0, IBM-3740 / CP/M 2.2',CR,LF,'$'
MSG_USAGE:
        DB      CR,LF,'Usage: 3712TEST [track [sector]]',CR,LF
        DB      '       track 0-76, sector 1-26 (decimal)',CR,LF,'$'
MSG_TARGET1:
        DB      'Requested sector: T$'
MSG_TARGET2:
        DB      '/S$'
MSG_EOL_ONLY:
        DB      CR,LF,'$'
MSG_INIT:
        DB      CR,LF,'Reset/select/restore: $'
MSG_READ1:
        DB      'Read T$'
MSG_READ2:
        DB      '/S$'
MSG_READ3:
        DB      ': $'
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
        DB      CR,LF,'NOTE: T0/S1 read succeeded, but the known Mike CP/M signature did not match.',CR,LF,'$'
MSG_SIG_SKIP:
        DB      CR,LF,'Boot signature check skipped (only applies to T0/S1).',CR,LF,'$'
MSG_INIT_FAIL:
        DB      'Initialization/restore returned an error. No sector read attempted.',CR,LF,'$'
MSG_READ_FAIL:
        DB      'Sector read failed. No disk writes were attempted.',CR,LF,'$'
MSG_TIMEOUT:
        DB      CR,LF,'TIMEOUT waiting for controller BUSY to clear.',CR,LF
        DB      'Check FDC+ firmware/type, cable, drive power, READY, and disk.',CR,LF,'$'
MSG_DIR_HEADER:
        DB      CR,LF,'CP/M DIRECTORY (direct FDC+3712 read, track 2):',CR,LF,'$'
MSG_DIR_EMPTY:
        DB      '(no active extent-0 directory entries found)',CR,LF,'$'
MSG_DIR_TOTAL1:
        DB      'Directory: $'
MSG_DIR_TOTAL2:
        DB      ' files listed.',CR,LF,'$'
MSG_DIR_TIMEOUT1:
        DB      CR,LF,'Directory read TIMEOUT at $'
MSG_DIR_TIMEOUT2:
        DB      '.',CR,LF,'$'
MSG_DIR_ERROR1:
        DB      CR,LF,'Directory read error at $'
MSG_DIR_ERROR2:
        DB      ': $'
MSG_DONE:
        DB      CR,LF,'Read-only test complete. Returning to CP/M.',CR,LF,'$'

BUFFER:
        DS      SECLEN,0

        END     START
