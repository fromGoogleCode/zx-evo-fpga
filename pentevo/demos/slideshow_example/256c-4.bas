 10 CLEAR 32767
 20 FOR a=0 TO 3
 25 CLS
 30 GO SUB 100
 35 GO SUB 200
 40 GO SUB 500
 50 NEXT a
 60 RUN
100 REM Load palette
110 OUT 175,194:REM mode 256c, 360x288
120 OUT 431,16:REM video page 16
125 OUT 687,0:REM xscroll=0
130 OUT 5551,24:REM fmaps to 32768, enable
140 LET p$="PAL"+STR$ (a)
150 PRINT p$
160 RANDOMIZE USR 15619:REM :LOAD p$ CODE 32768
170 OUT 5551,0:REM fmaps disable
199 RETURN
200 REM load picture
210 FOR f=0 TO 8
220 LET f$="PIC"+STR$ (a)+STR$ (f)
230 PRINT f$
240 OUT 5039,f+16:REM page select
250 RANDOMIZE USR 15619:REM :LOAD f$ CODE 49152
480 NEXT f
490 OUT 5039,0:REM page 0
499 RETURN
500 FOR s=0 TO 152:OUT 687,s
510 IF INKEY$<>"" THEN RETURN
520 PAUSE 1:NEXT s
600 FOR s=152 TO 0 STEP -1:OUT 687,s
610 IF INKEY$<>"" THEN RETURN
620 PAUSE 1:NEXT s
999 GO TO 500