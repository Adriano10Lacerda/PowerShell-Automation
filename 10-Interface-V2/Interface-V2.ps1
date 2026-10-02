#Requires -Version 5.1

<#
.SYNOPSIS
    Launcher principal da Interface V2.

.DESCRIPTION
    Inicializa a interface central do PowerShell Automation V2.

.NOTES
    V2 - Interface Central
#>

$ErrorActionPreference = "Stop"

$functionsPath = Join-Path `
    $PSScriptRoot `
    "Interface-V2-Functions.psm1"

if (-not (Test-Path -LiteralPath $functionsPath)) {
    Write-Host ""
    Write-Host "Interface-V2-Functions.psm1 não encontrado." -ForegroundColor Red
    Write-Host ""
    exit 1
}

try {
    Import-Module `
        $functionsPath `
        -Force `
        -ErrorAction Stop

    Start-V2Interface
}
catch {
    Write-Host ""
    Write-Host "Erro ao iniciar Power Shell Automation V2:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    exit 1
}