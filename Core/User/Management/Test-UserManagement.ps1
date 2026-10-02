#requires -Version 5.1

<#
.SYNOPSIS
    Testes do User Management V2.

.DESCRIPTION
    Valida a camada de gerenciamento de usuários
    utilizando o User Core em Simulation Mode.

.NOTES
    Projeto: PowerShell-Automation
    Versão: V2
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "           TESTES - USER MANAGEMENT V2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$script:Total = 0
$script:Pass = 0
$script:Fail = 0

function Test-Condition {
    param(
        [string]$Name,
        [bool]$Condition
    )

    $script:Total++

    if ($Condition) {
        $script:Pass++
        Write-Host "PASSOU: $Name" -ForegroundColor Green
    }
    else {
        $script:Fail++
        Write-Host "FALHOU: $Name" -ForegroundColor Red
    }
}

# ============================================================
# CAMINHOS
# ============================================================

$managementPath = Join-Path $PSScriptRoot "User-Management.psm1"
$corePath = Join-Path $PSScriptRoot "..\User-Functions.psm1"
$configPath = Join-Path $PSScriptRoot "..\..\03-AD-User-Provisioning\AD-Configuration.json"


# ============================================================
# TESTE 1 - ARQUIVOS
# ============================================================

Test-Condition `
    -Name "User-Management.psm1 existe" `
    -Condition (Test-Path -LiteralPath $managementPath)

Test-Condition `
    -Name "User Core existe" `
    -Condition (Test-Path -LiteralPath $corePath)


# ============================================================
# IMPORTAÇÃO
# ============================================================

try {
    Import-Module $managementPath -Force

    Test-Condition `
        -Name "User Management importa sem erro" `
        -Condition $true
}
catch {
    Test-Condition `
        -Name "User Management importa sem erro" `
        -Condition $false

    Write-Host ""
    Write-Host "Erro de importação:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red

    exit 1
}


# ============================================================
# FUNÇÕES DISPONÍVEIS
# ============================================================

Test-Condition `
    -Name "New-UserManagementSummary disponível" `
    -Condition ($null -ne (Get-Command New-UserManagementSummary -ErrorAction SilentlyContinue))

Test-Condition `
    -Name "Get-UserManagement disponível" `
    -Condition ($null -ne (Get-Command Get-UserManagement -ErrorAction SilentlyContinue))

Test-Condition `
    -Name "Get-UserManagementSummary disponível" `
    -Condition ($null -ne (Get-Command Get-UserManagementSummary -ErrorAction SilentlyContinue))


# ============================================================
# CONFIGURAÇÃO DE SIMULAÇÃO
# ============================================================

$configuration = [PSCustomObject]@{
    Domain = "BRSPO"

    DomainController = ""

    SimulationMode = $true

    UserPrincipalName = [PSCustomObject]@{
        Enabled = $true
        Domain  = "example.local"
    }

    Simulation = [PSCustomObject]@{
        ExistingSamAccountNames = @(
            "silva.maria.ext",
            "silva.maria2.ext",
            "silva.maria3.ext"
        )
    }
}

Test-Condition `
    -Name "Configuração de simulação criada" `
    -Condition (
        $configuration.SimulationMode -eq $true -and
        $configuration.Simulation.ExistingSamAccountNames.Count -eq 3
    )


# ============================================================
# CONSULTA DE USUÁRIO EXISTENTE
# ============================================================

$existingResult = Get-UserManagement `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Test-Condition `
    -Name "Usuário existente retorna sucesso" `
    -Condition ($existingResult.Success -eq $true)

Test-Condition `
    -Name "SamAccountName retornado corretamente" `
    -Condition ($existingResult.SamAccountName -eq "silva.maria.ext")

Test-Condition `
    -Name "SimulationMode está ativo" `
    -Condition ($existingResult.SimulationMode -eq $true)

Test-Condition `
    -Name "Status do usuário está disponível" `
    -Condition (-not [string]::IsNullOrWhiteSpace($existingResult.Status))

Test-Condition `
    -Name "Summary foi criado" `
    -Condition ($null -ne $existingResult.Summary)

Test-Condition `
    -Name "Data completa do usuário está disponível" `
    -Condition ($null -ne $existingResult.Data)


# ============================================================
# CAMPOS DO SUMMARY
# ============================================================

Test-Condition `
    -Name "Summary possui SamAccountName" `
    -Condition ($existingResult.Summary.SamAccountName -eq "silva.maria.ext")

Test-Condition `
    -Name "Summary possui DisplayName" `
    -Condition (-not [string]::IsNullOrWhiteSpace($existingResult.Summary.DisplayName))

Test-Condition `
    -Name "Summary possui UPN" `
    -Condition (-not [string]::IsNullOrWhiteSpace($existingResult.Summary.UserPrincipalName))

Test-Condition `
    -Name "Summary possui Enabled" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "Enabled")

Test-Condition `
    -Name "Summary possui LockedOut" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "LockedOut")

Test-Condition `
    -Name "Summary possui PasswordExpired" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "PasswordExpired")

Test-Condition `
    -Name "Summary possui Department" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "Department")

Test-Condition `
    -Name "Summary possui Title" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "Title")

Test-Condition `
    -Name "Summary possui Mail" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "Mail")

Test-Condition `
    -Name "Summary possui LastLogonDate" `
    -Condition ($existingResult.Summary.PSObject.Properties.Name -contains "LastLogonDate")


# ============================================================
# CONSULTA DE USUÁRIO INEXISTENTE
# ============================================================

$missingResult = Get-UserManagement `
    -SamAccountName "usuario.nao.existe" `
    -Configuration $configuration

Test-Condition `
    -Name "Usuário inexistente gera falha controlada" `
    -Condition ($missingResult.Success -eq $false)

Test-Condition `
    -Name "Usuário inexistente possui mensagem de erro" `
    -Condition (@($missingResult.Errors).Count -gt 0)


# ============================================================
# ENTRADA INVÁLIDA
# ============================================================

$invalidResult = Get-UserManagement `
    -SamAccountName " " `
    -Configuration $configuration

Test-Condition `
    -Name "SamAccountName inválido é tratado" `
    -Condition ($invalidResult.Success -eq $false)

Test-Condition `
    -Name "Entrada inválida gera erro controlado" `
    -Condition (@($invalidResult.Errors).Count -gt 0)


# ============================================================
# SUMMARY HELPER
# ============================================================

$summaryResult = Get-UserManagementSummary `
    -ManagementResult $existingResult

Test-Condition `
    -Name "Get-UserManagementSummary retorna sucesso" `
    -Condition ($summaryResult.Success -eq $true)

Test-Condition `
    -Name "Get-UserManagementSummary retorna Data" `
    -Condition ($null -ne $summaryResult.Data)


# ============================================================
# ERRO CONTROLADO DO SUMMARY
# ============================================================

$failedManagement = [PSCustomObject]@{
    Success = $false
    Errors  = @(
        "Usuário não encontrado."
    )
}

$failedSummary = Get-UserManagementSummary `
    -ManagementResult $failedManagement

Test-Condition `
    -Name "Summary de resultado com erro é tratado" `
    -Condition ($failedSummary.Success -eq $false)

Test-Condition `
    -Name "Summary de erro preserva mensagem" `
    -Condition (
        $failedSummary.Error -like "*Usuário não encontrado*"
    )


# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "                  RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $script:Total"
Write-Host "PASS  : $script:Pass" -ForegroundColor Green
Write-Host "FAIL  : $script:Fail" -ForegroundColor Red

Write-Host ""

if ($script:Fail -eq 0) {
    Write-Host "USER MANAGEMENT: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "USER MANAGEMENT: EXISTEM TESTES COM FALHA!" -ForegroundColor Red
    exit 1
}