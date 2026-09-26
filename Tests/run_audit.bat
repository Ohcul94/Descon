@echo off
title Suite Completa de Auditoria y Tests - Descon MMO
cls
echo ====================================================================
echo   EJECUTANDO BANCO COMPLETO DE AUDITORIAS Y TESTS (DESCON MMO)
echo ====================================================================
echo.

cd /d "%~dp0"

echo [1/5] Auditoria del Sistema de Talentos...
node audit_talents.js
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] El test de talentos fallo.
)

echo.
echo [2/5] Auditoria de Tienda, Items, Naves y Crafting...
node audit_items_shop.js
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] El test de tienda e items fallo.
)

echo.
echo [3/5] Auditoria de Misiones, Recompensas y Unlocks...
node audit_quests.js
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] El test de misiones fallo.
)

echo.
echo [4/5] Auditoria de Mapas, Zonas, Mobs y Modos de Juego...
node audit_maps_mobs.js
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] El test de mapas y mobs fallo.
)

echo.
echo [5/5] Auditoria de Habilidades, Combate y Anti-Cheat...
node audit_skills_combat.js
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] El test de habilidades y combate fallo.
)

echo.
echo ====================================================================
echo   TODOS LOS TESTS DE LA SUITE HAN SIDO EJECUTADOS.
echo ====================================================================
pause
