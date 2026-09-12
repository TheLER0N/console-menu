@echo off
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"

echo ================================================================
echo   GitHub Init: TheLER0N/console-menu
echo ================================================================
echo.

:: Проверка git
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo [XX] Git не найден. Установи Git для Windows.
    pause
    exit /b 1
)

echo [OK] Git найден
echo.

:: Инициализация репозитория
if not exist .git (
    echo [i] Инициализирую git репозиторий...
    git init
    git branch -M main
    echo [OK] Репозиторий инициализирован
) else (
    echo [i] Репозиторий уже инициализирован
)
echo.

:: Добавление remote
git remote get-url origin >nul 2>&1
if %errorlevel% neq 0 (
    echo [i] Добавляю remote origin...
    git remote add origin https://github.com/TheLER0N/console-menu.git
    echo [OK] Remote добавлен
) else (
    echo [i] Remote origin уже существует
)
echo.

:: Добавление файлов
echo [i] Добавляю файлы в git...
git add .
echo [OK] Файлы добавлены
echo.

:: Первый коммит
echo [i] Создаю первый коммит...
git commit -m "Initial commit: Console Menu MVP (.NET 4.8 + WPF)"
if %errorlevel% neq 0 (
    echo [i] Нечего коммитить или ошибка
)
echo.

:: Пуш в GitHub
echo [i] Пушу в GitHub...
echo     Введи credentials GitHub при запросе
echo.
git push -u origin main

if %errorlevel% equ 0 (
    echo.
    echo ================================================================
    echo   [OK] Готово! Проект загружен в GitHub
    echo   https://github.com/TheLER0N/console-menu
    echo ================================================================
) else (
    echo.
    echo [XX] Ошибка пуша. Проверь credentials и доступ к репозиторию.
)

echo.
pause
endlocal