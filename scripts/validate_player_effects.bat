@echo off
setlocal
set "PROJECT_ROOT=%~dp0.."

set "GODOT_BIN=%GODOT_BIN%"
if "%GODOT_BIN%"=="" (
  where godot4 >nul 2>nul
  if %errorlevel%==0 (
    for /f "delims=" %%i in ('where godot4') do set "GODOT_BIN=%%i"
  ) else (
    where godot >nul 2>nul
    if %errorlevel%==0 (
      for /f "delims=" %%i in ('where godot') do set "GODOT_BIN=%%i"
    )
  )
)
if "%GODOT_BIN%"=="" (
  echo Godot not found. Set GODOT_BIN to an absolute path to godot4.exe.
  exit /b 127
)

"%GODOT_BIN%" --headless --path "%PROJECT_ROOT%" -s scripts/validate_player_effects.gd
if %errorlevel% neq 0 exit /b %errorlevel%

endlocal
