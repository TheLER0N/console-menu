@echo off
setlocal
cd /d "%~dp0"

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "PROJ=%ROOT%\src\ConsoleMenu.Wpf\ConsoleMenu.Wpf.csproj"
set "PUBLISH=%ROOT%\build\publish"
set "RESULT=%ROOT%\result"

where dotnet >nul 2>&1
if errorlevel 1 (
  echo [XX] dotnet not found
  exit /b 1
)

if not exist "%PROJ%" (
  echo [XX] %PROJ% not found
  exit /b 1
)

tasklist /FI "IMAGENAME eq ConsoleMenu.Wpf.exe" 2>NUL | find /I "ConsoleMenu.Wpf.exe" >NUL
if not errorlevel 1 (
  echo [XX] Close ConsoleMenu.Wpf.exe before building
  exit /b 1
)

echo [i] Clean publish cache
if exist "%PUBLISH%" rmdir /s /q "%PUBLISH%"
if not exist "%RESULT%" mkdir "%RESULT%"
if not exist "%RESULT%\data" mkdir "%RESULT%\data"

echo [i] Clean result except data
pushd "%RESULT%"
for %%F in (*) do del /f /q /a "%%F" >nul 2>&1
for /D %%D in (*) do if /I not "%%D"=="data" rmdir /s /q "%%D" >nul 2>&1
popd

echo [i] Publish backend and WPF shell
dotnet publish "%PROJ%" -c Release -o "%PUBLISH%" -v q --nologo
if errorlevel 1 (
  echo [XX] Publish failed
  exit /b 1
)

echo [i] Copy build into result
robocopy "%PUBLISH%" "%RESULT%" /E /XD data /NFL /NDL /NP /NJH /NJS /NC /NS
if errorlevel 8 (
  echo [XX] Robocopy failed
  exit /b 1
)

if exist "%ROOT%\data\ui" (
  echo [i] Sync frontend ui
  robocopy "%ROOT%\data\ui" "%RESULT%\data\ui" /MIR /NFL /NDL /NP /NJH /NJS /NC /NS
  if errorlevel 8 (
    echo [XX] UI copy failed
    exit /b 1
  )
)

if exist "%ROOT%\data\media" (
  echo [i] Sync frontend media without deleting user files
  robocopy "%ROOT%\data\media" "%RESULT%\data\media" /E /NFL /NDL /NP /NJH /NJS /NC /NS
  if errorlevel 8 (
    echo [XX] Media copy failed
    exit /b 1
  )
)

if exist "%ROOT%\data\store-page.html" (
  echo [i] Copy store-page.html
  copy /Y "%ROOT%\data\store-page.html" "%RESULT%\data\store-page.html" >nul
  if errorlevel 1 (
    echo [XX] store-page.html copy failed
    exit /b 1
  )
)

if not exist "%RESULT%\data\store.json" (
  if exist "%ROOT%\data\store.json" (
    echo [i] Seed store.json
    copy /Y "%ROOT%\data\store.json" "%RESULT%\data\store.json" >nul
  )
)

echo [OK] Result: %RESULT%
exit /b 0