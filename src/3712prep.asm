;=============================================================================
; 3712PREP.COM v0.1
;
; Safe transition-preparation utility for the Altair FDC+3712 CP/M 2.2 path.
;
; Run 3712BOOT v0.2 immediately before this program. 3712BOOT leaves the
; verified 48K CP/M 2.2 system image staged at 8000H-997FH. This program:
;
;   1. Verifies the staged CCP and BIOS signatures.
;   2. Verifies the original full-image checksum (54B0H).
;   3. Verifies every BIOS byte that will be patched.
;   4. Redirects the staged BIOS disk/console vectors from the original
;      F400H PROM and Altair console routines to a future RAM service layer
;      at C000H.
;   5. Verifies all patched bytes and the expected patched checksum (4F80H).
;
; It does NOT copy the staged image to A600H-BF7FH, does NOT install anything
; at C000H, does NOT transfer control, and performs NO disk writes.
;
; Assemble with Pasmo:
;   pasmo --bin src/3712prep.asm build/3712PREP.COM build/3712prep.sym
;=============================================================================

        ORG     0100H

BDOS            EQU     0005H
BDOS_CONOUT     EQU     02H
BDOS_PRINT      EQU     09H

CR              EQU     0DH
LF              EQU     0AH

STAGEBASE       EQU     08000H
STAGEBIOS       EQU     09600H
STAGEEND        EQU     09980H
STAGELEN        EQU     STAGEEND-STAGEBASE

ORIG_SUM        EQU     054B0H
PATCHED_SUM     EQU     04F80H
PATCH_COUNT     EQU     19

; Future RAM service vector addresses at C000H.
SVC_COLD        EQU     0C003H
SVC_WARM        EQU     0C006H
SVC_HOME        EQU     0C009H
SVC_SELDRV      EQU     0C00CH
SVC_SETTRK      EQU     0C00FH
SVC_SETSEC      EQU     0C012H
SVC_SETDMA      EQU     0C015H
SVC_READ        EQU     0C018H
SVC_WRITE       EQU     0C01BH
SVC_CONST       EQU     0C01EH
SVC_CONIN       EQU     0C021H
SVC_CONOUT      EQU     0C024H
SVC_LISTST      EQU     0C027H

;-----------------------------------------------------------------------------
; Entry
;-----------------------------------------------------------------------------
START:
        LD      DE,MSG_BANNER
        CALL    PRINT_STR

        LD      DE,MSG_CCP
        CALL    PRINT_STR
        LD      HL,STAGEBASE
        LD      DE,EXPECTED_CCP_SIG
        LD      B,16
        CALL    COMPARE_BYTES
        JP      NZ,FAIL_CCP
        LD      DE,MSG_PASS
        CALL    PRINT_STR

        LD      DE,MSG_BIOS
        CALL    PRINT_STR
        LD      HL,STAGEBIOS
        LD      DE,EXPECTED_BIOS_SIG
        LD      B,16
        CALL    COMPARE_BYTES
        JP      NZ,FAIL_BIOS
        LD      DE,MSG_PASS
        CALL    PRINT_STR

        LD      DE,MSG_ORIG_SUM
        CALL    PRINT_STR
        CALL    CHECKSUM_STAGE
        PUSH    DE
        CALL    PRINT_HEX16_DE
        POP     DE
        LD      A,D
        CP      054H
        JP      NZ,FAIL_ORIG_SUM
        LD      A,E
        CP      0B0H
        JP      NZ,FAIL_ORIG_SUM
        LD      DE,MSG_PASS_SUFFIX
        CALL    PRINT_STR

        LD      DE,MSG_VALIDATE
        CALL    PRINT_STR
        CALL    VALIDATE_ORIGINAL_PATCHES
        JP      NZ,FAIL_PATCH_SOURCE
        LD      A,PATCH_COUNT
        CALL    PRINT_DEC2
        LD      DE,MSG_SITES_OK
        CALL    PRINT_STR

        CALL    APPLY_PATCHES

        LD      DE,MSG_VERIFY_PATCH
        CALL    PRINT_STR
        CALL    VALIDATE_NEW_PATCHES
        JP      NZ,FAIL_PATCH_VERIFY
        LD      A,PATCH_COUNT
        CALL    PRINT_DEC2
        LD      DE,MSG_SITES_OK
        CALL    PRINT_STR

        LD      DE,MSG_PATCHED_SUM
        CALL    PRINT_STR
        CALL    CHECKSUM_STAGE
        PUSH    DE
        CALL    PRINT_HEX16_DE
        POP     DE
        LD      A,D
        CP      04FH
        JP      NZ,FAIL_PATCHED_SUM
        LD      A,E
        CP      080H
        JP      NZ,FAIL_PATCHED_SUM
        LD      DE,MSG_PASS_SUFFIX
        CALL    PRINT_STR

        LD      DE,MSG_SUCCESS
        CALL    PRINT_STR
        RET

FAIL_CCP:
        LD      DE,MSG_FAIL
        CALL    PRINT_STR
        LD      DE,MSG_ERR_CCP
        JP      PRINT_AND_RETURN

FAIL_BIOS:
        LD      DE,MSG_FAIL
        CALL    PRINT_STR
        LD      DE,MSG_ERR_BIOS
        JP      PRINT_AND_RETURN

FAIL_ORIG_SUM:
        LD      DE,MSG_FAIL_SUFFIX
        CALL    PRINT_STR
        LD      DE,MSG_ERR_ORIG_SUM
        JP      PRINT_AND_RETURN

FAIL_PATCH_SOURCE:
        LD      DE,MSG_FAIL
        CALL    PRINT_STR
        LD      DE,MSG_ERR_PATCH_SOURCE
        JP      PRINT_AND_RETURN

FAIL_PATCH_VERIFY:
        LD      DE,MSG_FAIL
        CALL    PRINT_STR
        LD      DE,MSG_ERR_PATCH_VERIFY
        JP      PRINT_AND_RETURN

FAIL_PATCHED_SUM:
        LD      DE,MSG_FAIL_SUFFIX
        CALL    PRINT_STR
        LD      DE,MSG_ERR_PATCHED_SUM

PRINT_AND_RETURN:
        CALL    PRINT_STR
        RET

;=============================================================================
; Patch-table processing
;=============================================================================
; Each table entry is:
;   DW stage address
;   DB original byte 0,1,2
;   DB patched  byte 0,1,2
; A zero address terminates the table.

; Return Z if all original bytes match. No memory is changed.
VALIDATE_ORIGINAL_PATCHES:
        LD      HL,PATCH_TABLE
VOP_NEXT:
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        INC     HL
        LD      A,B
        OR      C
        JR      Z,VOP_GOOD

        LD      A,(BC)
        CP      (HL)
        RET     NZ
        INC     BC
        INC     HL
        LD      A,(BC)
        CP      (HL)
        RET     NZ
        INC     BC
        INC     HL
        LD      A,(BC)
        CP      (HL)
        RET     NZ
        INC     HL

        ; Skip three replacement bytes.
        INC     HL
        INC     HL
        INC     HL
        JR      VOP_NEXT
VOP_GOOD:
        XOR     A
        RET

; Apply all replacement triples. Caller must validate first.
APPLY_PATCHES:
        LD      HL,PATCH_TABLE
AP_NEXT:
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        INC     HL
        LD      A,B
        OR      C
        RET     Z

        ; Skip original triple.
        INC     HL
        INC     HL
        INC     HL

        LD      A,(HL)
        LD      (BC),A
        INC     BC
        INC     HL
        LD      A,(HL)
        LD      (BC),A
        INC     BC
        INC     HL
        LD      A,(HL)
        LD      (BC),A
        INC     HL
        JR      AP_NEXT

; Return Z if all replacement bytes are present.
VALIDATE_NEW_PATCHES:
        LD      HL,PATCH_TABLE
VNP_NEXT:
        LD      C,(HL)
        INC     HL
        LD      B,(HL)
        INC     HL
        LD      A,B
        OR      C
        JR      Z,VNP_GOOD

        ; Skip original triple.
        INC     HL
        INC     HL
        INC     HL

        LD      A,(BC)
        CP      (HL)
        RET     NZ
        INC     BC
        INC     HL
        LD      A,(BC)
        CP      (HL)
        RET     NZ
        INC     BC
        INC     HL
        LD      A,(BC)
        CP      (HL)
        RET     NZ
        INC     HL
        JR      VNP_NEXT
VNP_GOOD:
        XOR     A
        RET

;=============================================================================
; Verification helpers
;=============================================================================
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

CHECKSUM_STAGE:
        LD      HL,STAGEBASE
        LD      BC,STAGELEN
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

;=============================================================================
; Known signatures from Mike Douglas's supplied 48K image
;=============================================================================
EXPECTED_CCP_SIG:
        DB      0C3H,05CH,0A9H,0C3H,058H,0A9H,07FH,000H
        DB      043H,06FH,070H,079H,072H,069H,067H,068H

EXPECTED_BIOS_SIG:
        DB      0C3H,036H,0BCH,0C3H,092H,0BCH,0C3H,0E1H
        DB      0BCH,0C3H,0EEH,0BCH,0C3H,0FDH,0BCH,0C3H

;=============================================================================
; Staged BIOS patch table
;=============================================================================
; Final BIOS BC00H is staged at 9600H, so the low-byte offsets are identical.
; All source triples below were independently verified against the supplied
; CPM22v1.0-FDC+3712-48K.dsk image before this table was created.
PATCH_TABLE:
        ; BIOS entry vectors: cold, warm, console, disk, list status
        DW      09600H
        DB      0C3H,036H,0BCH, 0C3H,003H,0C0H
        DW      09603H
        DB      0C3H,092H,0BCH, 0C3H,006H,0C0H
        DW      09606H
        DB      0C3H,0E1H,0BCH, 0C3H,01EH,0C0H
        DW      09609H
        DB      0C3H,0EEH,0BCH, 0C3H,021H,0C0H
        DW      0960CH
        DB      0C3H,0FDH,0BCH, 0C3H,024H,0C0H
        DW      0960FH
        DB      0C3H,040H,0BDH, 0C3H,024H,0C0H
        DW      09612H
        DB      0C3H,026H,0BDH, 0C3H,024H,0C0H
        DW      09615H
        DB      0C3H,017H,0BDH, 0C3H,021H,0C0H
        DW      09618H
        DB      0C3H,009H,0F4H, 0C3H,009H,0C0H
        DW      0961EH
        DB      0C3H,00FH,0F4H, 0C3H,00FH,0C0H
        DW      09621H
        DB      0C3H,012H,0F4H, 0C3H,012H,0C0H
        DW      09624H
        DB      0C3H,015H,0F4H, 0C3H,015H,0C0H
        DW      09627H
        DB      0C3H,018H,0F4H, 0C3H,018H,0C0H
        DW      0962AH
        DB      0C3H,01BH,0F4H, 0C3H,01BH,0C0H
        DW      0962DH
        DB      0C3H,033H,0BDH, 0C3H,027H,0C0H

        ; Internal BIOS calls retained for robustness even though cold/warm
        ; BIOS entry vectors are redirected above.
        DW      0963CH
        DB      0CDH,003H,0F4H, 0CDH,003H,0C0H
        DW      09695H
        DB      0CDH,006H,0F4H, 0CDH,006H,0C0H
        DW      096A1H
        DB      0CDH,015H,0F4H, 0CDH,015H,0C0H
        DW      096CAH
        DB      0CDH,00CH,0F4H, 0CDH,00CH,0C0H

        DW      0000H

;=============================================================================
; Messages
;=============================================================================
MSG_BANNER:
        DB      CR,LF
        DB      'FDC+3712 PREP v0.1 - STAGED BIOS PATCH ONLY',CR,LF
        DB      'No disk writes, no final copy, no control transfer.',CR,LF,CR,LF,'$'
MSG_CCP:
        DB      'CCP signature at 8000:        $'
MSG_BIOS:
        DB      'BIOS signature at 9600:       $'
MSG_ORIG_SUM:
        DB      'Original checksum 8000-997F:  $'
MSG_VALIDATE:
        DB      'Original BIOS patch sites:    $'
MSG_VERIFY_PATCH:
        DB      'Patched BIOS patch sites:     $'
MSG_PATCHED_SUM:
        DB      'Patched checksum 8000-997F:   $'
MSG_PASS:
        DB      'PASS',CR,LF,'$'
MSG_FAIL:
        DB      'FAIL',CR,LF,'$'
MSG_PASS_SUFFIX:
        DB      '  PASS',CR,LF,'$'
MSG_FAIL_SUFFIX:
        DB      '  FAIL',CR,LF,'$'
MSG_SITES_OK:
        DB      ' sites PASS',CR,LF,'$'
MSG_SUCCESS:
        DB      CR,LF
        DB      'PASS: staged CP/M image is prepared for C000 RAM services.',CR,LF
        DB      'Active CP/M memory and final A600-BF7F image were not changed.',CR,LF,'$'
MSG_ERR_CCP:
        DB      'ABORT: staged CCP signature is missing. Run 3712BOOT v0.2 first.',CR,LF,'$'
MSG_ERR_BIOS:
        DB      'ABORT: staged BIOS signature is missing. Run 3712BOOT v0.2 first.',CR,LF,'$'
MSG_ERR_ORIG_SUM:
        DB      'ABORT: expected original checksum is 54B0.',CR,LF
        DB      'No BIOS patch bytes were changed.',CR,LF,'$'
MSG_ERR_PATCH_SOURCE:
        DB      'ABORT: one or more expected original BIOS bytes did not match.',CR,LF
        DB      'No BIOS patch bytes were changed.',CR,LF,'$'
MSG_ERR_PATCH_VERIFY:
        DB      'ERROR: one or more replacement BIOS bytes failed verification.',CR,LF
        DB      'Active CP/M memory was not changed.',CR,LF,'$'
MSG_ERR_PATCHED_SUM:
        DB      'ERROR: expected patched checksum is 4F80.',CR,LF
        DB      'Active CP/M memory was not changed.',CR,LF,'$'

        END     START
