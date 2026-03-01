@echo off
setlocal
pushd "%~dp0"

call :compile_if_exists ".\Assets\Assets.rc" ".\Assets.RES" || goto :fail
call :compile_if_exists ".\Misc\Misc.rc" ".\Misc.RES" || goto :fail

call :compile_if_exists ".\Cursors\Cursors.rc" ".\Cursors.RES" || goto :fail
call :compile_if_exists ".\Sounds\Sounds.rc" ".\Sounds.RES" || goto :fail
call :compile_if_exists ".\Particles\Particles.rc" ".\Particles.RES" || goto :fail
call :compile_if_exists ".\Custom\Custom.rc" ".\Custom.RES" || goto :fail

call :compile_if_exists ".\Styles\Orig\orig.rc" ".\Orig.RES" || goto :fail
call :compile_if_exists ".\Styles\Orig\Music\orig_music.rc" ".\Orig_music.RES" || goto :fail

call :compile_if_exists ".\Styles\Ohno\ohno.rc" ".\Ohno.RES" || goto :fail
call :compile_if_exists ".\Styles\Ohno\Music\ohno_music.rc" ".\Ohno_music.RES" || goto :fail

call :compile_if_exists ".\Styles\H94\h94.rc" ".\H94.RES" || goto :fail
call :compile_if_exists ".\Styles\H94\Music\h94_music.rc" ".\H94_music.RES" || goto :fail

call :compile_if_exists ".\Styles\X91\x91.rc" ".\X91.RES" || goto :fail
call :compile_if_exists ".\Styles\X92\x92.rc" ".\X92.RES" || goto :fail

echo.
echo Done.
popd
exit /b 0

:fail
echo.
echo Resource build failed.
popd
exit /b 1

:compile_if_exists
set "rc=%~1"
set "res=%~2"
if not exist "%rc%" (
  echo Skipping missing %rc%
  exit /b 0
)
echo Building %res% from %rc%
brcc32.exe -fo "%res%" "%rc%"
if errorlevel 1 (
  echo ERROR: Failed to build %res%
  exit /b 1
)
exit /b 0
