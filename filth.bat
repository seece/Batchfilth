@echo off
rem FiLTH "compiler"
setlocal EnableDelayedExpansion
rem echo %~f0

rem The compiler also uses the stack implementation to keep track of
rem generated return label line numbers.
call :init_stack

set infile=%1
set outfile=%2

set hit_marker=nej

echo @echo off> %outfile%
echo REM COMPILED WITH FiLTH>> %outfile%
echo setlocal EnableDelayedExpansion>> %outfile%
echo setlocal EnableExtensions>> %outfile%
echo call :init_stack>> %outfile%

rem Then process the input script.
rem setlocal DisableDelayedExpansion
set linenum=1

rem for /f "usebackq tokens=* delims=" %%a in (`type %infile%`) do (
 for /f "tokens=* delims= " %%a in (%infile%) do (
    set line=%%a
    set firstchar=!line:~0,1!

    for /F "tokens=1,2 delims= " %%a in ("!line!") do (
        set first=%%a
        set second=%%b
    )

    if "!firstchar!" == "#" (
        rem Comments are translated to batch comments.
        echo rem !line:~1!>> %outfile%
    ) else if "!firstchar!" == "$" (
        rem Lines prefixed with $ are passed through as is.
        echo !line:~1!>> %outfile%
    ) else if "!firstchar!" == ":" (
        rem We use regular batch script label syntax
        echo !line!>>%outfile%
    ) else if "!line!" == "do" (
        echo :label!linenum!>>%outfile%
        call :push !linenum!
    ) else if "!line!" == "loop" (
        call :pop
        echo call :top>>%outfile%
        echo if not ^^!ret^^! == ^0 ^(goto :label!ret!^)>>%outfile%
        echo call :pop>>%outfile%
    ) else if "!first!" == "go" (
        echo goto !second!>>%outfile%
    ) else if "!first!" == "if" (
        echo call :pop>>%outfile%
        echo ^if %%ret%%==^1 ^(goto :!second!^)>>%outfile%
    ) else (
        rem Otherwise create subroutine calls.
        echo call :!line!>>%outfile%
    )

    set /a linenum+=1
)
rem setlocal EnableDelayedExpansion
echo exit /b >> %outfile%

type "%~f0" >> %outfile%
goto :EOF

rem Runtime code begins here

:init_stack
set sp=0
set ret=
set val=
exit/b

:to_fixed
    call :pop
    set /a a="%ret% * (1<< 10)"
    call :push %a%
exit/b

:to_int
    call :pop
    set /a a="%ret% / (1 << 10)"
    call :push %a%
exit/b

:fmul
    call :pop
    set a=!ret!
    call :pop
    set /a result="(!ret! * !a!) >> 10"
    call :push !result!
exit/b

:fdiv
    call :pop
    set a=%ret%
    call :pop
    set /a result="((%ret% << 4) / %a%) << 6"
    call :push %result%
exit/b

:string_to_fixed
    call :pop
    set str=%ret%
    rem Split to whole and fractional part.
    for /F "tokens=1,2 delims=." %%a in ("%str%") do (
        set whole=%%a
        set fract=%%b
    )
    if not defined fract set "fract=0"

    rem Remove quotes.
    set whole=%whole:"=%
    set fract=%fract:"=%

    rem Extract the sign so we can add it back later.
    set sign=
    if %whole% lss 0 (
        set sign=-
        set /a "whole*= -1"
    )

    set fractlen=0
    call :strlen fractlen fract

    rem Remove leading zeroes from _fract
    set zeroes=0
    for /f "tokens=* delims=0" %%N in ("%fract%") do (
        set "fract=%%N"
        set /a zeroes+=1
    )
    if not defined fract set "fract=0"

    rem No exponentiation function so we need silly loop.
    set fractpower=1
    for /L %%i in (1,1,%fractlen%) do set /a fractpower*=10

    rem fract_fixed = (fract_decimal << 10) / 10^fract_string_length
    set /a "fract=(%fract% << 10) / %fractpower%"

    set /a "num=(%whole% << 10) + %fract%"
    set num=%sign%%num%
    call :push %num%
exit/b

:fixed_to_string
    set sign=
    call :pop
    set num=%ret%
    rem Remove minus sign if present.
    if %num% lss 0 (
        set sign=-
        set /a num=-1*%num%
    )
    call :push %num%
    call :push %num%
    call :to_int
    call :pop
    set whole=%ret%

    call :push %whole%
    call :to_fixed
    call :sub
    call :pop
    rem We basically move from 2^10 scaled fixed point to 10^4 based one.
    set /a fract="(%ret%*10000) / (1 << 10)"
    set decimals=
    rem Then we print the leftmost decimal, multiply by 10 and repeat
    for /L %%i in (0,1,4) do (
        set /a int="(!fract! / 1000) %% 10"
        set decimals=!decimals!!int!
        set /a fract="!fract!*10" 
    )

    call :push "%sign%%whole%.%decimals%"

exit/b

:fixed
    call :push %1
    call :string_to_fixed
exit/b

:input
    call :pop
    set /p "input_val=%ret%"
    call :push "%input_val%"
exit/b

:print
    call :pop
    rem Simply strip out all double quotes from the string.
    echo %ret:"=%
exit /b

:peep
    rem Prints the value at the top of stack, but does not remove it.
    call :dup
    call :print
exit /b

:bin_op
    call :pop
    set a=%ret%
    call :pop
    set /a result=%ret% %1 %a% 
    call :push %result%
exit/b

:add
    call :bin_op +
exit/b

:dec
    call :pop
    set /a result=%ret%-1
    call :push %result%
exit/b

:inc
    call :pop
    set /a result=%ret%+1
    call :push %result%
exit/b

:sub
    call :bin_op -
exit/b

:mul
    call :bin_op *
exit/b

:div
    call :bin_op /
exit/b

:abs
    call :pop
    if not %ret% geq 0 set /a ret=-%ret%
    call :push %ret%
exit/b

:top
    set /a top_of_stack=%sp%-1
    call :read %top_of_stack%
exit/b

:read
    if not defined stack[%1] (
        echo Memory access violation! %1
        exit /b
    )

    set ret=!stack[%1]!
exit /b

:dup
    call :pop
    call :push %ret%
    call :push %ret%
exit/b

:over
    call :pop
    set first=%ret%
    call :pop
    set second=%ret%
    call :push %second%
    call :push %first%
    call :push %second%
exit/b

:rot
    call :pop
    set first=%ret%
    call :pop
    set second=%ret%
    call :pop
    set third=%ret%
    call :push %second%
    call :push %first%
    call :push %third%
exit/b

:swap
    call :pop
    set first=%ret%
    call :pop
    set second=%ret%
    call :push %first%
    call :push %second%
exit/b

:push
    set stack[%sp%]=%1
    set /a sp=%sp%+1
exit /b

:pop
    call :top
    set /a sp=%sp%-1
exit /b

:test
    call :pop
    set first=%ret%
    call :pop
    set second=%ret%
    set result=0
    if %first% %1 %second% set result=1
    call :push %result%
exit/b

:debug_printstack
    echo sp: %sp%
    set /a stackend=%sp% - 1
    for /L %%i in (0,1,%stackend%) do (
        echo %%i: !stack[%%i]!
    )
exit /b

rem http://stackoverflow.com/a/5841587
:strlen <resultVar> <stringVar>
(   
    setlocal EnableDelayedExpansion
    set "s=!%~2!#"
    set "len=0"
    for %%P in (4096 2048 1024 512 256 128 64 32 16 8 4 2 1) do (
        if "!s:~%%P,1!" NEQ "" ( 
            set /a "len+=%%P"
            set "s=!s:~%%P!"
        )
    )
)
( 
    endlocal
    set "%~1=%len%"
    exit /b
)

