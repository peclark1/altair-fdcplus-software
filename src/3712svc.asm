;=============================================================================
; 3712SVC.BIN v0.1
;
; RAM-resident CP/M 2.2 service layer for the IMSAI/FDC+3712 handoff.
;
; Logical address: C000H
; Console: S100Computers Console I/O V2 at ports 00H/01H
; Disk:    FDC+ firmware 1.8 Drive Type 8 / FD3712 at ports 08H/09H
;
; The first boot version is intentionally READ ONLY. The WRITE BIOS service
; returns error (A=1) without issuing any FDC+ write command.
;
; Vector layout matches the staged BIOS patches produced by 3712PREP:
;   C000  full cold-start entry used by 3712HAND
;   C003  PROM-style pCOLD service (save BIOS address)
;   C006  PROM-style pWARM service (reload CCP+BDOS)
;   C009  HOME
;   C00C  select drive
;   C00F  set track
;   C012  set sector
;   C015  set DMA
;   C018  read
;   C01B  write (read-only error)
;   C01E  console status
;   C021  console input
;   C024  console output
;   C027  list status
;=============================================================================

        ORG     0C000H

        JP      COLD_FULL
        JP      PROM_COLD
        JP      PROM_WARM
        JP      HOME
        JP      SELDRV
        JP      SETTRK
        JP      SETSEC
        JP      SETDMA
        JP      READ
        JP      WRITE_RO
        JP      CONST
        JP      CONIN
        JP      CONOUT
        JP      LISTST

;-----------------------------------------------------------------------------
; CP/M 2.2 / supplied 48K image addresses
;-----------------------------------------------------------------------------
BIOSBASE        EQU     0BC00H
COLDCOMMON      EQU     0BC9EH
IOBYTE          EQU     0003H
CDISK           EQU     0004H

CCPLEN          EQU     0800H
BDOSLEN         EQU     0E00H
NUMSEC          EQU     26
SECLEN          EQU     128

;-----------------------------------------------------------------------------
; Page-zero work area reserved for BIOS/ROM use by the original PROM
;-----------------------------------------------------------------------------
DRVNUM          EQU     0040H
TRKNUM          EQU     0041H
SECNUM          EQU     0042H
DMAADDR         EQU     0043H
DRVTRK          EQU     0045H
BIOSADR         EQU     0046H

;-----------------------------------------------------------------------------
; FDC+3712
;-----------------------------------------------------------------------------
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

S_BUSY          EQU     01H
S_SKERR         EQU     02H
S_CRCERR        EQU     08H
S_NOTRDY        EQU     20H

CMDOUT          EQU     08H
DATAIN          EQU     08H
DATAOUT         EQU     09H

;-----------------------------------------------------------------------------
; Console I/O V2
;-----------------------------------------------------------------------------
CIO_STATUS      EQU     00H
CIO_DATA        EQU     01H
CIO_RX_READY    EQU     02H
CIO_TX_READY    EQU     04H

CR              EQU     0DH
LF              EQU     0AH

;=============================================================================
; Cold start
;=============================================================================
; The staged BIOS cold vector is finalized by 3712HAND as JMP C000H.
; This routine avoids the original Altair 2SIO initialization and banner.
; It initializes our disk state, prints through Console I/O, and then enters
; the original generic BIOS "coldCpm" tail at BC9EH. coldCpm installs page-zero
; warm-boot/BDOS vectors and enters CCP at A603H.
COLD_FULL:
        DI
        LD      SP,0100H

        LD      HL,BIOSBASE
        LD      (BIOSADR),HL

        CALL    INIT_ALL

        ; Preserve the image's default IOBYTE value (95H). Our patched BIOS
        ; entry vectors do not depend on it, but this matches the supplied BIOS.
        LD      A,095H
        LD      (IOBYTE),A
        XOR     A
        LD      (CDISK),A

        LD      HL,MSG_COLD
        CALL    PRINT_Z

        ; Original MODE byte is zero, so emulate "no cold command line":
        ; coldCpm POPs PSW and jumps to CCPBASE+3 when Z is set.
        XOR     A
        PUSH    AF
        JP      COLDCOMMON

; PROM-style pCOLD: original BIOS passes HL=BIOSBASE and expects a return.
PROM_COLD:
        LD      (BIOSADR),HL
        RET

;=============================================================================
; Warm boot
;=============================================================================
; Reproduce Mike Douglas PROM.ASM pWARM semantics: reload CCP+BDOS from
; tracks 0 and 1, stopping before the BIOS at BC00H, then return to the
; original BIOS wBoot routine. On a read failure, restart the reload.
PROM_WARM:
        CALL    INIT_ALL

        LD      HL,(BIOSADR)
        LD      DE,0EA80H               ; -(0800H+0E00H)+0080H
        ADD     HL,DE                   ; CCP+128 = A680H
        LD      C,0
        CALL    SETTRK
        LD      A,3
        CALL    LOAD_TRK

        LD      HL,(BIOSADR)
        LD      DE,0F680H               ; -(1600H)+(25*128) = -0980H
        ADD     HL,DE                   ; B280H
        LD      C,1
        CALL    SETTRK
        LD      A,1
        ; fall through

LOAD_TRK:
        LD      C,A                     ; current physical sector

LOAD_TRK_LOOP:
        LD      A,(BIOSADR+1)
        DEC     A
        CP      H
        JP      C,LOAD_TRK_SKIP         ; do not overwrite BIOS page

        PUSH    HL
        PUSH    BC

        CALL    SETSEC
        LD      B,H
        LD      C,L
        CALL    SETDMA
        CALL    READ

        POP     BC
        POP     HL
        OR      A
        JP      NZ,PROM_WARM            ; retry whole warm load on error

LOAD_TRK_SKIP:
        LD      DE,0100H                ; interleave 2 => +2 sectors
        ADD     HL,DE

        LD      A,2
        ADD     A,C
        CP      NUMSEC+1
        JP      C,LOAD_TRK

        SUB     NUMSEC-1                ; wrap 27->2 or 28->3
        LD      DE,0F380H               ; -(25*128) = -0C80H
        ADD     HL,DE

        CP      2
        JP      Z,LOAD_TRK
        RET

;=============================================================================
; Standard PROM-style disk service entries
;=============================================================================
HOME:
        LD      C,0
        ; fall through

SETTRK:
        LD      A,C
        LD      (TRKNUM),A
        RET

SELDRV:
        LD      A,C
        LD      (DRVNUM),A
        LD      A,0FFH
        LD      (DRVTRK),A
        RET

SETSEC:
        LD      A,C
        LD      (SECNUM),A
        RET

SETDMA:
        LD      H,B
        LD      L,C
        LD      (DMAADDR),HL
        RET

;-----------------------------------------------------------------------------
; READ - return A=0 on success, nonzero on failure
;-----------------------------------------------------------------------------
READ:
        CALL    SELECT_SEEK
        JP      NZ,ERR_EXIT

        LD      C,10

READ_RETRY:
        LD      A,C_READ
        CALL    DO_CMD
        AND     S_NOTRDY+S_CRCERR
        JP      Z,READ_TRANSFER

        CALL    CLR_ERRORS
        DEC     C
        JP      NZ,READ_RETRY
        JP      ERR_EXIT

READ_TRANSFER:
        LD      HL,(DMAADDR)
        LD      C,SECLEN

READ_BUFFER_LOOP:
        LD      A,C_RDBUF
        OUT     (CMDOUT),A
        IN      A,(DATAIN)
        LD      (HL),A

        LD      A,C_SHIFT
        OUT     (CMDOUT),A

        INC     HL
        DEC     C
        JP      NZ,READ_BUFFER_LOOP

        XOR     A
        OUT     (CMDOUT),A
        RET

; First physical boot is intentionally read-only.
WRITE_RO:
        LD      A,1
        OR      A
        RET

ERR_EXIT:
        LD      A,1
        OR      A
        RET

;=============================================================================
; Controller helpers
;=============================================================================
SELECT_SEEK:
        XOR     A
        OUT     (DATAOUT),A
        LD      A,C_LDCFG
        CALL    OUT_CMD

        CALL    SELECT_SECTOR
        CALL    SEEK
        RET

SELECT_SECTOR:
        LD      A,(DRVNUM)
        AND     03H
        RRCA
        RRCA
        LD      C,A

        LD      A,(SECNUM)
        OR      C
        OUT     (DATAOUT),A

        LD      A,C_DRVSEC
        CALL    OUT_CMD
        RET

SEEK:
        LD      C,2

SEEK_LOOP:
        LD      A,(TRKNUM)
        LD      HL,DRVTRK
        CP      (HL)
        RET     Z

        LD      (HL),A
        LD      A,(TRKNUM)
        OUT     (DATAOUT),A
        LD      A,C_SETTRK
        CALL    OUT_CMD

        LD      A,C_SEEK
        CALL    DO_CMD
        AND     S_NOTRDY+S_CRCERR
        RET     Z

        CALL    CLR_ERRORS
        LD      (HL),0FFH
        DEC     C
        JP      NZ,SEEK_LOOP

        CALL    RESET0
        LD      A,S_SKERR
        OR      A
        RET

INIT_ALL:
        XOR     A
        LD      (DRVNUM),A
        INC     A
        LD      (SECNUM),A
        ; fall through

RESET0:
        LD      A,C_RESET
        CALL    OUT_CMD

        CALL    SELECT_SECTOR
        LD      A,0FFH
        LD      (DRVTRK),A
        LD      A,C_RESTORE
        JP      DO_CMD

DO_CMD:
        CALL    OUT_CMD

DO_CMD_WAIT:
        IN      A,(DATAIN)
        AND     S_BUSY
        JP      NZ,DO_CMD_WAIT

        IN      A,(DATAIN)
        RET

CLR_ERRORS:
        LD      A,C_CLRERR
        ; fall through

OUT_CMD:
        OUT     (CMDOUT),A
        XOR     A
        OUT     (CMDOUT),A
        RET

;=============================================================================
; Console I/O V2 service entries
;=============================================================================
CONST:
        IN      A,(CIO_STATUS)
        AND     CIO_RX_READY
        JP      Z,CONST_NONE
        LD      A,0FFH
        RET
CONST_NONE:
        XOR     A
        RET

CONIN:
        CALL    CONST
        JP      Z,CONIN
        IN      A,(CIO_DATA)
        AND     07FH
        RET

; BIOS passes output character in C.
CONOUT:
        LD      A,C
        OR      A
        RET     Z                       ; do not send NUL to Console I/O
        PUSH    AF
CONOUT_WAIT:
        IN      A,(CIO_STATUS)
        AND     CIO_TX_READY
        JP      Z,CONOUT_WAIT
        POP     AF
        OUT     (CIO_DATA),A
        RET

LISTST:
        LD      A,0FFH
        RET

PRINT_Z:
        LD      A,(HL)
        OR      A
        RET     Z
        INC     HL
        LD      C,A
        CALL    CONOUT
        JP      PRINT_Z

MSG_COLD:
        DB      CR,LF
        DB      '48K CP/M 2.2 v1.0 - FDC+3712 / IMSAI target',CR,LF
        DB      'Console I/O at 00H/01H; disk writes disabled for first boot.'
        DB      CR,LF,0

        END
