@echo off
setlocal enabledelayedexpansion

REM Windows wrapper for scripts/validate_all.sh
REM Runs: Godot import, backend node tests, then Godot scene validation.

set "PROJECT_ROOT=%~dp0.."
if not defined GODOT_BIN set "GODOT_BIN="
if not defined NODE_BIN set "NODE_BIN="

if "%GODOT_BIN%"=="" (
  where godot4 >nul 2>nul
  if %errorlevel%==0 (
    for /f "delims=" %%i in ('where godot4 ^| findstr /i "godot4"') do set "GODOT_BIN=%%i"
  ) else (
    where godot >nul 2>nul
    if %errorlevel%==0 (
      for /f "delims=" %%i in ('where godot ^| findstr /i "godot"') do set "GODOT_BIN=%%i"
    )
  )
)

if not defined GODOT_BIN (
  echo Godot not found. Set GODOT_BIN to an absolute path to godot4.exe.
  exit /b 127
)

if not exist "%GODOT_BIN%" (
  echo GODOT_BIN does not point to an executable: "%GODOT_BIN%"
  exit /b 127
)

REM Node is required for backend tests.
if "%NODE_BIN%"=="" (
  REM Prefer system node.js if available.
  if exist "C:\\Program Files\\nodejs\\node.exe" (
    set "NODE_BIN=C:\\Program Files\\nodejs\\node.exe"
  )
)

if "%NODE_BIN%"=="" (
  REM Hardcoded fallback for this dev machine/environment.
  if exist "C:\\Users\\Kyttu\\miniforge3\\envs\\ryzen-ai-1.8.0\\Lib\\site-packages\\playwright\\driver\\node.exe" (
    set "NODE_BIN=C:\\Users\\Kyttu\\miniforge3\\envs\\ryzen-ai-1.8.0\\Lib\\site-packages\\playwright\\driver\\node.exe"
  )
)

if "%NODE_BIN%"=="" (
  where node >nul 2>nul
  if %errorlevel%==0 (
    for /f "delims=" %%i in ('where node') do set "NODE_BIN=%%i"
  ) else (
    REM Fallback to Playwright's bundled node.exe in the existing conda env.
    REM (User-provided path; avoids relying on USERPROFILE/HOME variables.)
    if exist "C:\\Users\\Kyttu\\miniforge3\\envs\\ryzen-ai-1.8.0\\Lib\\site-packages\\playwright\\driver\\node.exe" (
      set "NODE_BIN=C:\\Users\\Kyttu\\miniforge3\\envs\\ryzen-ai-1.8.0\\Lib\\site-packages\\playwright\\driver\\node.exe"
    )
  )
)

if not defined NODE_BIN (
  echo Node not found. Set NODE_BIN to an absolute path to node.exe.
  exit /b 127
)

if not exist "%NODE_BIN%" (
  echo NODE_BIN does not point to an executable: "%NODE_BIN%"
  exit /b 127
)

echo == import
"%GODOT_BIN%" --headless --path "%PROJECT_ROOT%" --import
if errorlevel 1 exit /b %errorlevel%

echo == backend
"%NODE_BIN%" --test "%PROJECT_ROOT%"/backend/*.test.mjs
if errorlevel 1 exit /b %errorlevel%

echo == game
"%GODOT_BIN%" --headless --path "%PROJECT_ROOT%" res://scenes/validate.tscn
if errorlevel 1 exit /b %errorlevel%

echo FULL GAME VALIDATION OK
endlocal
