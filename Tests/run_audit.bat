@echo off
title Suite Completa de Auditoria y Tests - Descon MMO
cls
echo ====================================================================
echo   EJECUTANDO BANCO COMPLETO DE AUDITORIAS Y TESTS (DESCON MMO)
echo ====================================================================
echo.

cd /d "%~dp0"

set /a total_tests=0
set /a failed_tests=0

for %%f in (audit_*.js) do (
    echo --------------------------------------------------------------------
    echo [EJECUTANDO TEST]: %%f
    echo --------------------------------------------------------------------
    node "%%f"
    if errorlevel 1 (
        echo.
        echo [ERROR CRITICO] El test %%f ha fallado.
        set /a failed_tests+=1
    )
    set /a total_tests+=1
    echo.
)

echo ====================================================================
echo   RESUMEN FINAL DE LA SUITE DE AUDITORIAS
echo ====================================================================
echo   Total de Tests Ejecutados: %total_tests%
echo   Tests con Fallos:          %failed_tests%
echo ====================================================================
if %failed_tests% gtr 0 (
    echo   ESTADO: ATENCION - ALGUNOS TESTS HAN FALLADO.
) else (
    echo   ESTADO: EXITO TOTAL - TODOS LOS TESTS PASARON CORRECTAMENTE.
)
echo ====================================================================
pause
