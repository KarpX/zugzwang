param(
    [switch]$Sync
)

# run_lichess_sim.ps1
# Запуск Lichess API шахматных симуляций для проекта «Белый Король» (Zugzwang)
#
# Сценарий 1 (Playthrough 1 / Hard): бот побеждает среднего и сильного игрока (по 3 партии).
# Сценарий 2 (Playthrough 2 / Адаптивный): бот проигрывает слабому игроку с плавным снижением сложности (3 партии).

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($Sync) {
    $RunnerPy = Join-Path $ScriptDir "lichess_simulation_runner_sync.py"
    $ModeName = "Синхронный (Strict Single-Request, 100% стабильность)"
} else {
    $RunnerPy = Join-Path $ScriptDir "lichess_simulation_runner.py"
    $ModeName = "Асинхронный / параллельный (3 потока)"
}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "   Запуск Lichess API шахматных симуляций (Zugzwang Godot Engine)     " -ForegroundColor Cyan
Write-Host "   Режим: $ModeName" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

python -u $RunnerPy

$exitCode = $LASTEXITCODE
if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host ">>> ТЕСТЫ ЗАВЕРШЕНЫ УСПЕШНО! Все требования выполнены. <<<" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host ">>> ОШИБКА: Некоторые тесты провалены (код: $exitCode) <<<" -ForegroundColor Red
}

exit $exitCode
