@echo off
:: v188.1: Lanzador DEBUG configurable (estilo QUAD-SYNC)
:: Ahora es archivo de texto editable, igual que quad_launch.bat
:: Copia este archivo o edita las cuentas abajo para configurar las sesiones.
title Lanzador Descon DEBUG

set GODOT="E:\PROGRAMAS\Godot\Godot_v4.6.2-stable_win64.exe"
set PROJECT_PATH="E:\Descon\descon"

:: --- CONFIGURA TUS CUENTAS AQUI ---
:: Edita USER/PASS para cada sesion. Deja en blanco para no abrirla.
:: Ejemplo: set USER1=Caelli94 / set PASS1=1234
set USER1=Player1
set PASS1=1234

set USER2=Player5
set PASS2=1234

:: Descomenta estas lineas si quieres 3ra y 4ta sesion:
:: set USER3=Player5
:: set PASS3=1234
:: set USER4=Player1
:: set PASS4=1234
set USER3=
set PASS3=
set USER4=
set PASS4=
:: ----------------------------------

:: Configuracion de resolucion y posicion
:: W/H = resolucion de tu monitor. OFFSET_Y = cuanto bajar las ventanas de arriba
:: para que no queden cortadas por la barra de titulo de Windows.
set W=1920
set H=1080
set OFFSET_Y=60

:: Calculo de tamanos (mitad del monitor, descontando el offset superior)
set /a usableH=%H% - %OFFSET_Y%
set /a halfW=%W% / 2
set /a halfH=%usableH% / 2
set /a bottomY=%OFFSET_Y% + %halfH%

echo ==========================================
echo Lanzador DEBUG - Iniciando sesiones...
echo Offset superior: %OFFSET_Y% px (ajustado para que no se corte)
echo ==========================================

:: 1. Superior Izquierda
if not "%USER1%"=="" (
    echo [1] Lanzando %USER1% en 0,%OFFSET_Y% - %halfW%x%halfH%
    start "" %GODOT% --path %PROJECT_PATH% --user %USER1% --pass %PASS1% --win_pos 0,%OFFSET_Y% --win_size %halfW%,%halfH%
) else (
    echo [1] Slot 1 vacio - omitido
)

:: 2. Superior Derecha
if not "%USER2%"=="" (
    echo [2] Lanzando %USER2% en %halfW%,%OFFSET_Y% - %halfW%x%halfH%
    start "" %GODOT% --path %PROJECT_PATH% --user %USER2% --pass %PASS2% --win_pos %halfW%,%OFFSET_Y% --win_size %halfW%,%halfH%
) else (
    echo [2] Slot 2 vacio - omitido
)

:: 3. Inferior Izquierda (opcional)
if not "%USER3%"=="" (
    echo [3] Lanzando %USER3% en 0,%bottomY% - %halfW%x%halfH%
    start "" %GODOT% --path %PROJECT_PATH% --user %USER3% --pass %PASS3% --win_pos 0,%bottomY% --win_size %halfW%,%halfH%
)

:: 4. Inferior Derecha (opcional)
if not "%USER4%"=="" (
    echo [4] Lanzando %USER4% en %halfW%,%bottomY% - %halfW%x%halfH%
    start "" %GODOT% --path %PROJECT_PATH% --user %USER4% --pass %PASS4% --win_pos %halfW%,%bottomY% --win_size %halfW%,%halfH%
)

echo Despliegue DEBUG completo.
:: Si quieres usar layout diagonal clasico (2 ventanas en diagonal), comenta el bloque de arriba
:: y descomenta estas dos lineas:
:: start "" %GODOT% --path %PROJECT_PATH% --user %USER1% --pass %PASS1% --win_pos 10,%OFFSET_Y% --win_size 950,500
:: start "" %GODOT% --path %PROJECT_PATH% --user %USER2% --pass %PASS2% --win_pos 960,%bottomY% --win_size 950,500

exit
