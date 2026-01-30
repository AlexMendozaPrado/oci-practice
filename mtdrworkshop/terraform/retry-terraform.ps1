# Script para reintentar Terraform hasta que haya capacidad
# Ejecutar: .\retry-terraform.ps1
# Detener: Ctrl+C

$maxRetries = 1000          # Numero maximo de intentos
$waitSeconds = 60           # Segundos entre intentos (1 minuto)
$terraformPath = "C:\Users\fluid\AppData\Local\Microsoft\WinGet\Links\terraform.exe"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Script de Reintento para OCI Terraform" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Este script reintentara 'terraform apply' cada $waitSeconds segundos"
Write-Host "hasta que se cree el node pool exitosamente."
Write-Host ""
Write-Host "Presiona Ctrl+C para detener en cualquier momento."
Write-Host ""

$attempt = 0
$success = $false

while (-not $success -and $attempt -lt $maxRetries) {
    $attempt++
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Write-Host "[$timestamp] Intento $attempt de $maxRetries..." -ForegroundColor Yellow

    # Ejecutar terraform apply
    $output = & $terraformPath apply -auto-approve 2>&1
    $exitCode = $LASTEXITCODE

    # Mostrar resumen del output
    $outputStr = $output -join "`n"

    if ($exitCode -eq 0) {
        Write-Host ""
        Write-Host "============================================" -ForegroundColor Green
        Write-Host "  EXITO! Recursos creados correctamente" -ForegroundColor Green
        Write-Host "============================================" -ForegroundColor Green
        Write-Host ""
        $success = $true
    }
    elseif ($outputStr -match "Out of host capacity") {
        Write-Host "  -> Sin capacidad disponible. Reintentando en $waitSeconds segundos..." -ForegroundColor Red

        # Mostrar barra de progreso
        for ($i = $waitSeconds; $i -gt 0; $i--) {
            Write-Host "`r  -> Esperando: $i segundos restantes...   " -NoNewline -ForegroundColor DarkGray
            Start-Sleep -Seconds 1
        }
        Write-Host ""
    }
    elseif ($outputStr -match "No changes") {
        Write-Host "  -> No hay cambios pendientes. Todo esta creado!" -ForegroundColor Green
        $success = $true
    }
    else {
        Write-Host "  -> Error diferente detectado:" -ForegroundColor Magenta
        # Mostrar las ultimas lineas del error
        $output | Select-Object -Last 10 | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkMagenta }
        Write-Host ""
        Write-Host "  -> Reintentando en $waitSeconds segundos..." -ForegroundColor Yellow
        Start-Sleep -Seconds $waitSeconds
    }
}

if (-not $success) {
    Write-Host ""
    Write-Host "Se alcanzo el maximo de $maxRetries intentos sin exito." -ForegroundColor Red
    Write-Host "Puedes ejecutar el script nuevamente mas tarde." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Script finalizado."
