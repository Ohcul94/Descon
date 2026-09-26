@echo off
title Auditoria de Talentos - Descon MMO
cls
echo ====================================================================
echo   Ejecutando Test Suite de Auditoria de Talentos (Server-Side)
echo ====================================================================
echo.
cd /d "%~dp0"
node audit_talents.js
echo.
echo ====================================================================
pause
