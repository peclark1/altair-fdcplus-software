;=============================================================================
; 3712HAND.COM v0.1
;
; Atomic handoff from the currently running CP/M system to Mike Douglas's
; supplied 48K CP/M 2.2 FDC+3712 image.
;
; REQUIRED sequence:
;   3712BOOT   -> stages original image at 8000H-997FH
;   3712PREP   -> validates/patches stage; checksum becomes 4F80H
;   3712HAND   -> this program
;
; Before the irreversible point this program:
;   * verifies the prepared 4F80H staged image
;   * verifies the two prepared cold/warm vectors
;   * asks for an explicit 'P' confirmation to finalize the staged vectors
;   * verifies checksum 5005H while the old CP/M is still intact
;   * asks for a second explicit 'B' confirmation before the real handoff
;
; After the irreversible point it:
;   * stops using BDOS and disables interrupts
;   * installs the read-only C000H RAM service layer
;   * copies 8000H-997FH to final A600H-BF7FH
;   * verifies the final image checksum
;   * jumps to C000H for the CP/M 2.2 cold start
;
; No FDC+ write command exists in the v0.1 RAM service layer.
;=============================================================================

        ORG     0100H

BDOS            EQU     0005H
BDOS_CONIN      EQU     01H
BDOS_CONOUT     EQU     02H
BDOS_PRINT      EQU     09H

CR              EQU     0DH
LF              EQU     0AH

STAGEBASE       EQU     08000H
STAGEBIOS       EQU     09600H
STAGEEND        EQU     09980H
STAGELEN        EQU     STAGEEND-STAGEBASE

FINALBASE       EQU     0A600H
FINALEND        EQU     0BF80H
FINALLEN        EQU     FINALEND-FINALBASE

SVCBASE         EQU     0C000H

PREP_SUM_H      EQU     04FH
PREP_SUM_L      EQU     080H
FINAL_SUM_H     EQU     050H
FINAL_SUM_L     EQU     005H

CIO_STATUS      EQU     00H
CIO_DATA        EQU     01H
CIO_TX_READY    EQU     04H

;-----------------------------------------------------------------------------
; Entry / safe preflight
;-----------------------------------------------------------------------------
START:
        LD      (ORIG_SP),SP
        LD      SP,PRIVATE_STACK_TOP

        LD      DE,MSG_BANNER
        CALL    PRINT_STR

        LD      DE,MSG_STAGE_SUM
        CALL    PRINT_STR
        CALL    CHECKSUM_STAGE
        PUSH    DE
        CALL    PRINT_HEX16_DE
        POP     DE
        LD      A,D
        CP      PREP_SUM_H
        JP      NZ,FAIL_PREP_SUM
        LD      A,E
        CP      PREP_SUM_L
        JP      NZ,FAIL_PREP_SUM
        LD      DE,MSG_PASS_SUFFIX
        CALL    PRINT_STR

        LD      DE,MSG_VECTOR_CHECK
        CALL    PRINT_STR
        LD      HL,STAGEBIOS
        LD      DE,EXPECTED_PREP_VECTORS
        LD      B,6
        CALL    COMPARE_BYTES
        JP      NZ,FAIL_VECTORS
        LD      DE,MSG_PASS
        CALL    PRINT_STR

        LD      DE,MSG_WARNING
        CALL    PRINT_STR

        LD      C,BDOS_CONIN
        CALL    BDOS
        CALL    TO_UPPER
        CP      'P'
        JP      NZ,ABORT_USER

        ; Finalize only the staged BIOS. Active CP/M is still untouched here.
        CALL    APPLY_FINAL_VECTOR_FIX

        LD      DE,MSG_FINAL_STAGE
        CALL    PRINT_STR
        CALL    CHECKSUM_STAGE
        PUSH    DE
        CALL    PRINT_HEX16_DE
        POP     DE
        LD      A,D
        CP      FINAL_SUM_H
        JP      NZ,FAIL_FINAL_SUM
        LD      A,E
        CP      FINAL_SUM_L
        JP      NZ,FAIL_FINAL_SUM
        LD      DE,MSG_PASS_SUFFIX
        CALL    PRINT_STR

        ; Second confirmation is deliberately after the 5005H check. This
        ; allows the complete final staged patch to be bench-tested safely.
        LD      DE,MSG_FINAL_CONFIRM
        CALL    PRINT_STR
        LD      C,BDOS_CONIN
        CALL    BDOS
        CALL    TO_UPPER
        CP      'B'
        JP      NZ,ABORT_FINAL

        LD      DE,MSG_COMMIT
        CALL    PRINT_STR

;=============================================================================
; IRREVERSIBLE HANDOFF
; No BDOS calls are permitted below this point.
;=============================================================================
        DI
        LD      SP,PRIVATE_STACK_TOP

        ; Install C000 RAM service layer. This can overwrite the old CP/M BIOS.
        LD      HL,SVC_IMAGE
        LD      DE,SVCBASE
        LD      BC,SVC_IMAGE_END-SVC_IMAGE
        LDIR

        ; Verify the service image byte-for-byte before replacing CP/M 3.
        LD      HL,SVC_IMAGE
        LD      DE,SVCBASE
        LD      BC,SVC_IMAGE_END-SVC_IMAGE
        CALL    COMPARE_BLOCK
        JP      NZ,FATAL_SVC

        ; Install the prepared 48K CP/M 2.2 system at its final addresses.
        LD      HL,STAGEBASE
        LD      DE,FINALBASE
        LD      BC,STAGELEN
        LDIR

        ; Verify the final copy before entering it.
        LD      HL,FINALBASE
        LD      BC,FINALLEN
        CALL    CHECKSUM_RANGE
        LD      A,D
        CP      FINAL_SUM_H
        JP      NZ,FATAL_IMAGE
        LD      A,E
        CP      FINAL_SUM_L
        JP      NZ,FATAL_IMAGE

        JP      SVCBASE                  ; never returns

;-----------------------------------------------------------------------------
; Safe failure / abort paths (BDOS still valid)
;-----------------------------------------------------------------------------
FAIL_PREP_SUM:
        LD      DE,MSG_FAIL_SUFFIX
        CALL    PRINT_STR
        LD      DE,MSG_ERR_PREP_SUM
        JP      PRINT_AND_EXIT

FAIL_VECTORS:
        LD      DE,MSG_FAIL
        CALL    PRINT_STR
        LD      DE,MSG_ERR_VECTORS
        JP      PRINT_AND_EXIT

FAIL_FINAL_SUM:
        ; Restore the exact 3712PREP vector bytes before returning to CP/M.
        CALL    RESTORE_PREP_VECTORS
        LD      DE,MSG_FAIL_SUFFIX
        CALL    PRINT_STR
        LD      DE,MSG_ERR_FINAL_SUM
        JP      PRINT_AND_EXIT

ABORT_FINAL:
        CALL    RESTORE_PREP_VECTORS
        LD      DE,MSG_ABORT_FINAL
        CALL    PRINT_STR
        JP      EXIT_TO_CPM

ABORT_USER:
        LD      DE,MSG_ABORT
        CALL    PRINT_STR
        JP      EXIT_TO_CPM

PRINT_AND_EXIT:
        CALL    PRINT_STR
EXIT_TO_CPM:
        LD      SP,(ORIG_SP)
        RET

;-----------------------------------------------------------------------------
; Prepared -> final staged-vector correction
;
; 3712PREP intentionally proved all 19 redirects without executing them.
; For the actual service layer:
;   BC00 cold vector -> C000 full cold-start service
;   BC03 warm vector -> original BIOS wBoot at BC92
;
; The internal calls already patched by PREP remain:
;   BC3C CALL C003  (PROM-style pCOLD)
;   BC95 CALL C006  (PROM-style pWARM)
;-----------------------------------------------------------------------------
APPLY_FINAL_VECTOR_FIX:
        LD      A,0C3H
        LD      (STAGEBIOS+0),A
        XOR     A
        LD      (STAGEBIOS+1),A
        LD      A,0C0H
        LD      (STAGEBIOS+2),A

        LD      A,0C3H
        LD      (STAGEBIOS+3),A
        LD      A,092H
        LD      (STAGEBIOS+4),A
        LD      A,0BCH
        LD      (STAGEBIOS+5),A
        RET

RESTORE_PREP_VECTORS:
        LD      A,0C3H
        LD      (STAGEBIOS+0),A
        LD      A,003H
        LD      (STAGEBIOS+1),A
        LD      A,0C0H
        LD      (STAGEBIOS+2),A

        LD      A,0C3H
        LD      (STAGEBIOS+3),A
        LD      A,006H
        LD      (STAGEBIOS+4),A
        LD      A,0C0H
        LD      (STAGEBIOS+5),A
        RET

;=============================================================================
; Verification helpers
;=============================================================================
COMPARE_BYTES:
COMPARE_BYTES_LOOP:
        LD      A,(DE)
        CP      (HL)
        RET     NZ
        INC     DE
        INC     HL
        DJNZ    COMPARE_BYTES_LOOP
        XOR     A
        RET

; HL=source, DE=destination, BC=count. Returns Z if identical.
COMPARE_BLOCK:
        LD      A,B
        OR      C
        JR      Z,COMPARE_BLOCK_GOOD
COMPARE_BLOCK_LOOP:
        LD      A,(DE)
        CP      (HL)
        RET     NZ
        INC     HL
        INC     DE
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,COMPARE_BLOCK_LOOP
COMPARE_BLOCK_GOOD:
        XOR     A
        RET

CHECKSUM_STAGE:
        LD      HL,STAGEBASE
        LD      BC,STAGELEN
        ; fall through

; HL=start, BC=count. Returns additive 16-bit sum in DE.
CHECKSUM_RANGE:
        LD      DE,0000H
CHECKSUM_RANGE_LOOP:
        LD      A,E
        ADD     A,(HL)
        LD      E,A
        JR      NC,CHECKSUM_RANGE_NO_CARRY
        INC     D
CHECKSUM_RANGE_NO_CARRY:
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,CHECKSUM_RANGE_LOOP
        RET

;=============================================================================
; CP/M display helpers used before the irreversible point
;=============================================================================
PRINT_STR:
        LD      C,BDOS_PRINT
        JP      BDOS

PUTCHAR:
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

TO_UPPER:
        CP      'a'
        RET     C
        CP      'z'+1
        RET     NC
        AND     05FH
        RET

;=============================================================================
; Fatal display after the irreversible point -- direct Console I/O only
;=============================================================================
FATAL_SVC:
        LD      HL,MSG_FATAL_SVC
        CALL    DIRECT_PRINT_Z
        JP      FATAL_HALT

FATAL_IMAGE:
        LD      HL,MSG_FATAL_IMAGE
        CALL    DIRECT_PRINT_Z
        ; fall through

FATAL_HALT:
        JP      FATAL_HALT              ; reset is the only recovery

DIRECT_PRINT_Z:
        LD      A,(HL)
        OR      A
        RET     Z
        INC     HL
        CALL    DIRECT_OUT
        JR      DIRECT_PRINT_Z

DIRECT_OUT:
        PUSH    AF
DIRECT_OUT_WAIT:
        IN      A,(CIO_STATUS)
        AND     CIO_TX_READY
        JR      Z,DIRECT_OUT_WAIT
        POP     AF
        OR      A
        RET     Z
        OUT     (CIO_DATA),A
        RET

;=============================================================================
; Expected prepared vector bytes / messages
;=============================================================================
EXPECTED_PREP_VECTORS:
        DB      0C3H,003H,0C0H          ; prepared BC00 -> C003
        DB      0C3H,006H,0C0H          ; prepared BC03 -> C006

MSG_BANNER:
        DB      CR,LF
        DB      'FDC+3712 HANDOFF v0.1 - REAL CP/M 2.2 BOOT',CR,LF
        DB      'First boot is READ ONLY and uses Console I/O at 00H/01H.'
        DB      CR,LF,CR,LF,'$'

MSG_STAGE_SUM:
        DB      'Prepared checksum 8000-997F:  $'
MSG_VECTOR_CHECK:
        DB      'Prepared cold/warm vectors:   $'
MSG_FINAL_STAGE:
        DB      CR,LF,'Final staged checksum:          $'

MSG_PASS:
        DB      'PASS',CR,LF,'$'
MSG_PASS_SUFFIX:
        DB      '  PASS',CR,LF,'$'
MSG_FAIL:
        DB      'FAIL',CR,LF,'$'
MSG_FAIL_SUFFIX:
        DB      '  FAIL',CR,LF,'$'

MSG_WARNING:
        DB      CR,LF
        DB      'Drive 0 must contain the validated 48K CP/M 2.2 disk.',CR,LF
        DB      'Press P to test/finalize staged boot vectors; any other key aborts: $'

MSG_FINAL_CONFIRM:
        DB      CR,LF
        DB      '5005 verified. Press B for the NON-RETURNING boot;',CR,LF
        DB      'any other key restores the 4F80 prepared stage and aborts: $'

MSG_COMMIT:
        DB      CR,LF
        DB      '5005 PASS. Installing C000 services and replacing CP/M now...'
        DB      CR,LF,'$'

MSG_ABORT:
        DB      CR,LF,'Aborted before final-vector preparation. Current CP/M was not changed.',CR,LF,'$'
MSG_ABORT_FINAL:
        DB      CR,LF
        DB      'Aborted after 5005 test. Prepared 4F80 vectors restored;',CR,LF
        DB      'current CP/M was not changed.',CR,LF,'$'

MSG_ERR_PREP_SUM:
        DB      'ABORT: expected 4F80. Run 3712BOOT then 3712PREP immediately first.'
        DB      CR,LF,'$'
MSG_ERR_VECTORS:
        DB      'ABORT: prepared BIOS vectors do not match 3712PREP v0.1.'
        DB      CR,LF,'$'
MSG_ERR_FINAL_SUM:
        DB      'ABORT: expected final staged checksum 5005. Prepared vectors restored.'
        DB      CR,LF,'$'

MSG_FATAL_SVC:
        DB      CR,LF
        DB      'FATAL: C000 RAM service copy verification failed. RESET required.'
        DB      CR,LF,0
MSG_FATAL_IMAGE:
        DB      CR,LF
        DB      'FATAL: A600-BF7F CP/M image verification failed. RESET required.'
        DB      CR,LF,0

;-----------------------------------------------------------------------------
; The service binary is assembled separately at logical address C000H and
; embedded verbatim here so 3712HAND.COM is the only file needed at handoff.
;-----------------------------------------------------------------------------
SVC_IMAGE:
        INCBIN  "build/3712SVC.BIN"
SVC_IMAGE_END:

ORIG_SP:
        DW      0000H

PRIVATE_STACK:
        DS      128
PRIVATE_STACK_TOP:

        END     START
