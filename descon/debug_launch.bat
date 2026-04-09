@echo off
:: v187.10: Lanzador Ultra-Rápido (.bat) - Clic y cierra
title Lanzador Descon MMO

set GODOT="E:\PROGRAMAS\Godot\Godot_v4.6.2-stable_win64.exe"
set PROJECT_PATH="E:\Descon\descon"

:: --- CONFIGURA TUS CONTRASEÑAS AQUÍ ---
set PASS_Caelli94=1234
set PASS_Player3=1234
:: --------------------------------------

echo Iniciando instancias de Descon MMO...

:: Lanzar Jugador 1
start "" %GODOT% --path %PROJECT_PATH% --user Caelli94 --pass %PASS_Caelli94% --win_pos 10,40 --win_size 950,500

:: Lanzar Jugador 2
start "" %GODOT% --path %PROJECT_PATH% --user Player3 --pass %PASS_Player3% --win_pos 960,540 --win_size 950,500

exit
