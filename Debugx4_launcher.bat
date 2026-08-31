@echo off
:: v188.1: Lanzador de 4 Instancias (QUAD-SYNC) - con OFFSET_Y
:: Distribuye las ventanas en las 4 esquinas del monitor, bajando las de arriba
:: para que no queden cortadas por la barra de titulo.
title Descon QUAD-Launcher

set GODOT="E:\PROGRAMAS\Godot\Godot_v4.6.2-stable_win64.exe"
set PROJECT_PATH="E:\Descon\descon"

:: --- CONFIGURA TUS CUENTAS AQUI ---
set USER1=Caelli94
set PASS1=1234

set USER2=Player1
set PASS2=1234

set USER3=Player3
set PASS3=1234

set USER4=Player5
set PASS4=1234
:: ----------------------------------

:: Configuracion de resolucion (Por defecto 1920x1080)
:: Si tienes un monitor diferente, ajusta W y H.
:: OFFSET_Y = pixeles a bajar las ventanas superiores (recomendado 30-40)
set W=1920
set H=1080
set OFFSET_Y=35

:: Calculo de tamanos (Mitad del monitor, descontando offset)
set /a usableH=%H% - %OFFSET_Y%
set /a halfW=%W% / 2
set /a halfH=%usableH% / 2
set /a bottomY=%OFFSET_Y% + %halfH%

echo Iniciando 4 pilotos en formacion (offset Y=%OFFSET_Y%)...

:: 1. Superior Izquierda
start "" %GODOT% --path %PROJECT_PATH% --user %USER1% --pass %PASS1% --win_pos 0,%OFFSET_Y% --win_size %halfW%,%halfH%

:: 2. Superior Derecha
start "" %GODOT% --path %PROJECT_PATH% --user %USER2% --pass %PASS2% --win_pos %halfW%,%OFFSET_Y% --win_size %halfW%,%halfH%

:: 3. Inferior Izquierda
start "" %GODOT% --path %PROJECT_PATH% --user %USER3% --pass %PASS3% --win_pos 0,%bottomY% --win_size %halfW%,%halfH%

:: 4. Inferior Derecha
start "" %GODOT% --path %PROJECT_PATH% --user %USER4% --pass %PASS4% --win_pos %halfW%,%bottomY% --win_size %halfW%,%halfH%

echo Despliegue completo.
exit
