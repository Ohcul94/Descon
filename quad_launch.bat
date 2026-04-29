@echo off
:: v188.0: Lanzador de 4 Instancias (QUAD-SYNC)
:: Distribuye las ventanas en las 4 esquinas del monitor.
title Descon QUAD-Launcher

set GODOT="E:\PROGRAMAS\Godot\Godot_v4.6.2-stable_win64.exe"
set PROJECT_PATH="E:\Descon\descon"

:: --- CONFIGURA TUS CUENTAS AQUÍ ---
set USER1=Caelli94
set PASS1=1234

set USER2=Player1
set PASS2=1234

set USER3=Player3
set PASS3=1234

set USER4=Player5
set PASS4=1234
:: ----------------------------------

:: Configuración de resolución (Por defecto 1920x1080)
:: Si tienes un monitor diferente, ajusta W y H.
set W=1920
set H=1080

:: Cálculo de tamaños (Mitad del monitor)
set /a halfW=%W% / 2
set /a halfH=%H% / 2

echo Iniciando 4 pilotos en formacion...

:: 1. Superior Izquierda
start "" %GODOT% --path %PROJECT_PATH% --user %USER1% --pass %PASS1% --win_pos 0,0 --win_size %halfW%,%halfH%

:: 2. Superior Derecha
start "" %GODOT% --path %PROJECT_PATH% --user %USER2% --pass %PASS2% --win_pos %halfW%,0 --win_size %halfW%,%halfH%

:: 3. Inferior Izquierda
start "" %GODOT% --path %PROJECT_PATH% --user %USER3% --pass %PASS3% --win_pos 0,%halfH% --win_size %halfW%,%halfH%

:: 4. Inferior Derecha
start "" %GODOT% --path %PROJECT_PATH% --user %USER4% --pass %PASS4% --win_pos %halfW%,%halfH% --win_size %halfW%,%halfH%

echo Despliegue completo.
exit
