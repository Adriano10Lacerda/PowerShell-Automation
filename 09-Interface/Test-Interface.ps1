$ErrorActionPreference = "Stop"

$InterfaceFunctionsPath = Join-Path $PSScriptRoot "Interface-Functions.psm1"

$TestsPassed = 0
$TestsFailed = 0


function Invoke-Test {

    param (
        [string]$Name,
        [scriptblock]$Test
    )

    try {

        & $Test

        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:TestsPassed++

    }
    catch {

        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Yellow

        $script:TestsFailed++
    }
}


Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "       TESTES - INTERFACE POWERSHELL          " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""


# ==========================================================
# Interface
# ==========================================================

Invoke-Test "Interface-Functions.psm1 existe" {

    if (-not (Test-Path $InterfaceFunctionsPath)) {
        throw "Interface-Functions.psm1 não encontrado."
    }
}


Invoke-Test "Interface-Functions.psm1 importa corretamente" {

    Import-Module $InterfaceFunctionsPath -Force
}


# ==========================================================
# Funções da Interface
# ==========================================================

Invoke-Test "Função Start-PasswordGenerator existe" {

    if (-not (Get-Command Start-PasswordGenerator -ErrorAction SilentlyContinue)) {
        throw "Start-PasswordGenerator não encontrada."
    }
}


Invoke-Test "Função Start-Configuration existe" {

    if (-not (Get-Command Start-Configuration -ErrorAction SilentlyContinue)) {
        throw "Start-Configuration não encontrada."
    }
}


Invoke-Test "Função Start-ADUserProvisioning existe" {

    if (-not (Get-Command Start-ADUserProvisioning -ErrorAction SilentlyContinue)) {
        throw "Start-ADUserProvisioning não encontrada."
    }
}


Invoke-Test "Função Start-EntraUserProvisioning existe" {

    if (-not (Get-Command Start-EntraUserProvisioning -ErrorAction SilentlyContinue)) {
        throw "Start-EntraUserProvisioning não encontrada."
    }
}


Invoke-Test "Função Start-ComputerInventory existe" {

    if (-not (Get-Command Start-ComputerInventory -ErrorAction SilentlyContinue)) {
        throw "Start-ComputerInventory não encontrada."
    }
}


Invoke-Test "Função Start-ADGroupManagement existe" {

    if (-not (Get-Command Start-ADGroupManagement -ErrorAction SilentlyContinue)) {
        throw "Start-ADGroupManagement não encontrada."
    }
}


Invoke-Test "Função Start-GPOManagement existe" {

    if (-not (Get-Command Start-GPOManagement -ErrorAction SilentlyContinue)) {
        throw "Start-GPOManagement não encontrada."
    }
}


Invoke-Test "Função Start-Reporting existe" {

    if (-not (Get-Command Start-Reporting -ErrorAction SilentlyContinue)) {
        throw "Start-Reporting não encontrada."
    }
}


# ==========================================================
# Módulo 01
# ==========================================================

Invoke-Test "Módulo 01 existe" {

    $Path = Join-Path $PSScriptRoot "..\01-Password-Generator\Generate-Password.ps1"

    if (-not (Test-Path $Path)) {
        throw "Generate-Password.ps1 não encontrado."
    }
}


# ==========================================================
# Módulo 02
# ==========================================================

Invoke-Test "Módulo 02 existe" {

    $Path = Join-Path $PSScriptRoot "..\02-Configuration\Configuration.psm1"

    if (-not (Test-Path $Path)) {
        throw "Configuration.psm1 não encontrado."
    }
}


Invoke-Test "Validate-Configuration.ps1 existe" {

    $Path = Join-Path $PSScriptRoot "..\02-Configuration\Validate-Configuration.ps1"

    if (-not (Test-Path $Path)) {
        throw "Validate-Configuration.ps1 não encontrado."
    }
}


# ==========================================================
# Módulo 03
# ==========================================================

Invoke-Test "Módulo 03 existe" {

    $Path = Join-Path $PSScriptRoot "..\03-AD-User-Provisioning\Provision-ADUser.ps1"

    if (-not (Test-Path $Path)) {
        throw "Provision-ADUser.ps1 não encontrado."
    }
}


# ==========================================================
# Módulo 04
# ==========================================================

Invoke-Test "Módulo 04 existe" {

    $Path = Join-Path $PSScriptRoot "..\04-Entra-ID-User-Provisioning\Provision-EntraUser.ps1"

    if (-not (Test-Path $Path)) {
        throw "Provision-EntraUser.ps1 não encontrado."
    }
}


# ==========================================================
# Módulo 05
# ==========================================================

Invoke-Test "Módulo 05 existe" {

    $Path = Join-Path $PSScriptRoot "..\05-Computer-Inventory\Computer-Inventory.ps1"

    if (-not (Test-Path $Path)) {
        throw "Computer-Inventory.ps1 não encontrado."
    }
}


# ==========================================================
# Módulo 06
# ==========================================================

Invoke-Test "Módulo 06 existe" {

    $Path = Join-Path $PSScriptRoot "..\06-AD-Group-Management\AD-Group-Management.ps1"

    if (-not (Test-Path $Path)) {
        throw "AD-Group-Management.ps1 não encontrado."
    }
}


# ==========================================================
# Módulo 07
# ==========================================================

Invoke-Test "Módulo 07 existe" {

    $Path = Join-Path $PSScriptRoot "..\07-GPO-Management\GPO-Management.ps1"

    if (-not (Test-Path $Path)) {
        throw "GPO-Management.ps1 não encontrado."
    }
}


# ==========================================================
# Módulo 08
# ==========================================================

Invoke-Test "Módulo 08 existe" {

    $Path = Join-Path $PSScriptRoot "..\08-Reporting\Reporting.ps1"

    if (-not (Test-Path $Path)) {
        throw "Reporting.ps1 não encontrado."
    }
}


# ==========================================================
# Resultado
# ==========================================================

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "                 RESULTADO                    " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

Write-Host ""
Write-Host "Total de testes : $($TestsPassed + $TestsFailed)"
Write-Host "Passaram        : $TestsPassed" -ForegroundColor Green
Write-Host "Falharam        : $TestsFailed" -ForegroundColor Red
Write-Host ""

if ($TestsFailed -eq 0) {

    Write-Host "STATUS: TODOS OS TESTES PASSARAM" -ForegroundColor Green

}
else {

    Write-Host "STATUS: EXISTEM TESTES COM FALHA" -ForegroundColor Red

    exit 1
}