@echo off
rem Compila ZXP3 para MiSTer con Quartus 17.0 desde linea de comandos
set QUARTUS=C:\altera_lite\17.0\quartus\bin64
"%QUARTUS%\quartus_sh.exe" --flow compile zxp3 -c zxp3
if errorlevel 1 goto :error
for /f %%i in ('powershell -nologo -noprofile -command "Get-Date -Format yyyyMMdd"') do set DT=%%i
copy /y output_files\zxp3.rbf releases\ZXP3_%DT%.rbf >nul
echo Hecho: releases\ZXP3_%DT%.rbf
goto :eof
:error
echo Error de compilacion
exit /b 1
