#Requires -Version 5.1

<#
.SYNOPSIS
    Testes da Interface Central V2.

.DESCRIPTION
    Valida a estrutura, funções e integrações
    da Interface V2.

    Integrações atuais:
    - Computer Management
    - User Management
    - User Account Actions
        - Unlock
        - Enable
        - Disable
        - Force Password Change

.NOTES
    V2 - Interface Central
#>

$ErrorActionPreference = "Stop"

$script:Passed = 0
$script:Failed = 0

function Write-TestResult {
    param(
        [string]$Name,
        [bool]$Success
    )

    if ($Success) {
        Write-Host "PASSOU: $Name" -ForegroundColor Green
        $script:Passed++
    }
    else {
        Write-Host "FALHOU: $Name" -ForegroundColor Red
        $script:Failed++
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        TESTES - INTERFACE V2" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$functionsPath = Join-Path `
    $PSScriptRoot `
    "Interface-V2-Functions.psm1"

$launcherPath = Join-Path `
    $PSScriptRoot `
    "Interface-V2.ps1"

$computerManagementPath = Join-Path `
    $PSScriptRoot `
    "..\Core\Computer\Management\Computer-Management.psm1"

$userManagementPath = Join-Path `
    $PSScriptRoot `
    "..\Core\User\Management\User-Management.psm1"

$userActionsPath = Join-Path `
    $PSScriptRoot `
    "..\Core\User\Actions\User-Account-Actions.psm1"


# ============================================================
# TESTES DE ARQUIVOS
# ============================================================

Write-TestResult `
    "Interface-V2-Functions.psm1 existe" `
    (Test-Path -LiteralPath $functionsPath)

Write-TestResult `
    "Interface-V2.ps1 existe" `
    (Test-Path -LiteralPath $launcherPath)

Write-TestResult `
    "Computer-Management.psm1 existe" `
    (Test-Path -LiteralPath $computerManagementPath)

Write-TestResult `
    "User-Management.psm1 existe" `
    (Test-Path -LiteralPath $userManagementPath)

Write-TestResult `
    "User-Account-Actions.psm1 existe" `
    (Test-Path -LiteralPath $userActionsPath)


# ============================================================
# IMPORTAÇÃO
# ============================================================

$moduleImported = $false

try {
    Import-Module `
        $functionsPath `
        -Force `
        -ErrorAction Stop

    $moduleImported = $true
}
catch {
    $moduleImported = $false
}

Write-TestResult `
    "Interface V2 importa sem erro" `
    $moduleImported


# ============================================================
# FUNÇÕES
# ============================================================

$expectedFunctions = @(
    "Write-V2Header",
    "Pause-V2",
    "Show-V2DevelopmentMessage",
    "Start-V2ComputerManagement",
    "Show-V2UserSummary",
    "Show-V2UserDetails",
    "Start-V2UserUnlockAccount",
    "Start-V2UserEnableAccount",
    "Start-V2UserDisableAccount",
    "Start-V2UserForcePasswordChange",
    "Start-V2UserManagement",
    "Show-V2MainMenu",
    "Start-V2Interface"
)

foreach ($functionName in $expectedFunctions) {

    $command = Get-Command `
        $functionName `
        -ErrorAction SilentlyContinue

    Write-TestResult `
        "Função '$functionName' disponível" `
        ($null -ne $command)
}


# ============================================================
# CONTEÚDO DO LAUNCHER
# ============================================================

$launcherContent = ""

try {
    $launcherContent = Get-Content `
        -LiteralPath $launcherPath `
        -Raw `
        -ErrorAction Stop
}
catch {
    $launcherContent = ""
}

Write-TestResult `
    "Launcher referencia Interface-V2-Functions.psm1" `
    ($launcherContent -match "Interface-V2-Functions\.psm1")

Write-TestResult `
    "Launcher chama Start-V2Interface" `
    ($launcherContent -match "Start-V2Interface")


# ============================================================
# CONTEÚDO DO MÓDULO
# ============================================================

$moduleContent = ""

try {
    $moduleContent = Get-Content `
        -LiteralPath $functionsPath `
        -Raw `
        -ErrorAction Stop
}
catch {
    $moduleContent = ""
}


# ============================================================
# MENU PRINCIPAL
# ============================================================

Write-TestResult `
    "Menu contém Users" `
    ($moduleContent -match "Users")

Write-TestResult `
    "Menu contém Accounts" `
    ($moduleContent -match "Accounts")

Write-TestResult `
    "Menu contém Groups" `
    ($moduleContent -match "Groups")

Write-TestResult `
    "Menu contém Computers" `
    ($moduleContent -match "Computers")

Write-TestResult `
    "Menu contém Policies" `
    ($moduleContent -match "Policies")

Write-TestResult `
    "Menu contém Reports" `
    ($moduleContent -match "Reports")

Write-TestResult `
    "Menu contém Settings" `
    ($moduleContent -match "Settings")

Write-TestResult `
    "Menu contém Exit" `
    ($moduleContent -match "Exit")


# ============================================================
# COMPUTER MANAGEMENT
# ============================================================

Write-TestResult `
    "Computer Management é integrado" `
    ($moduleContent -match "Computer-Management\.psm1")

Write-TestResult `
    "Get-ComputerManagementSummary é utilizado" `
    ($moduleContent -match "Get-ComputerManagementSummary")

Write-TestResult `
    "Hostname é solicitado ao operador" `
    ($moduleContent -match 'Read-Host "  Hostname"')

Write-TestResult `
    "Modo simulação de computador é apresentado" `
    ($moduleContent -match "SimulationMode")

Write-TestResult `
    "Erros da consulta de computador são tratados" `
    ($moduleContent -match "ErrorCount")


# ============================================================
# USER MANAGEMENT
# ============================================================

Write-TestResult `
    "User Management é integrado" `
    ($moduleContent -match "User-Management\.psm1")

Write-TestResult `
    "Get-UserManagement é utilizado" `
    ($moduleContent -match "Get-UserManagement")

Write-TestResult `
    "SamAccountName é solicitado ao operador" `
    ($moduleContent -match 'Read-Host "  SamAccountName"')

Write-TestResult `
    "Resumo de usuário é apresentado" `
    ($moduleContent -match "Show-V2UserSummary")

Write-TestResult `
    "Detalhes de usuário são apresentados" `
    ($moduleContent -match "Show-V2UserDetails")

Write-TestResult `
    "Modo simulação de usuário é apresentado" `
    ($moduleContent -match "MODO SIMULAÇÃO: ATIVO")

Write-TestResult `
    "Erros da consulta de usuário são tratados" `
    ($moduleContent -match "Usuário não encontrado")


# ============================================================
# USER ACCOUNT ACTIONS - INTEGRAÇÃO
# ============================================================

Write-TestResult `
    "User Account Actions é integrado" `
    ($moduleContent -match "User-Account-Actions\.psm1")


# ============================================================
# UNLOCK
# ============================================================

Write-TestResult `
    "Start-V2UserUnlockAccount existe" `
    ($moduleContent -match "function Start-V2UserUnlockAccount")

Write-TestResult `
    "Get-UserUnlockPreview é utilizado" `
    ($moduleContent -match "Get-UserUnlockPreview")

Write-TestResult `
    "Invoke-UserUnlockAccount é utilizado" `
    ($moduleContent -match "Invoke-UserUnlockAccount")

Write-TestResult `
    "Ação de desbloqueio exige confirmação" `
    ($moduleContent -match 'Confirma a execução\? \[S/N\]')

Write-TestResult `
    "Execução usa -Execute" `
    ($moduleContent -match "Invoke-UserUnlockAccount[\s\S]*-Execute")

Write-TestResult `
    "Modo simulação de desbloqueio é apresentado" `
    ($moduleContent -match "DESBLOQUEIO SIMULADO COM SUCESSO")

Write-TestResult `
    "Execução real apresenta resultado" `
    ($moduleContent -match "CONTA DESBLOQUEADA COM SUCESSO")

Write-TestResult `
    "Cancelamento da ação é tratado" `
    ($moduleContent -match "Ação cancelada pelo operador")

Write-TestResult `
    "Estado LockedOut é apresentado no preview" `
    ($moduleContent -match "CurrentState")

Write-TestResult `
    "Estado Unlocked é apresentado no preview" `
    ($moduleContent -match "TargetState")

Write-TestResult `
    "Menu do usuário contém desbloqueio" `
    ($moduleContent -match "2\. Desbloquear conta")


# ============================================================
# ENABLE
# ============================================================

Write-TestResult `
    "Start-V2UserEnableAccount existe" `
    ($moduleContent -match "function Start-V2UserEnableAccount")

Write-TestResult `
    "Get-UserEnablePreview é utilizado" `
    ($moduleContent -match "Get-UserEnablePreview")

Write-TestResult `
    "Invoke-UserEnableAccount é utilizado" `
    ($moduleContent -match "Invoke-UserEnableAccount")

Write-TestResult `
    "Mensagem de ativação simulada existe" `
    ($moduleContent -match "ATIVAÇÃO SIMULADA COM SUCESSO")

Write-TestResult `
    "Mensagem de ativação real existe" `
    ($moduleContent -match "CONTA ATIVADA COM SUCESSO")

Write-TestResult `
    "Menu contém ativação de conta" `
    ($moduleContent -match "3\. Ativar conta")


# ============================================================
# DISABLE
# ============================================================

Write-TestResult `
    "Start-V2UserDisableAccount existe" `
    ($moduleContent -match "function Start-V2UserDisableAccount")

Write-TestResult `
    "Get-UserDisablePreview é utilizado" `
    ($moduleContent -match "Get-UserDisablePreview")

Write-TestResult `
    "Invoke-UserDisableAccount é utilizado" `
    ($moduleContent -match "Invoke-UserDisableAccount")

Write-TestResult `
    "Mensagem de desativação simulada existe" `
    ($moduleContent -match "DESATIVAÇÃO SIMULADA COM SUCESSO")

Write-TestResult `
    "Mensagem de desativação real existe" `
    ($moduleContent -match "CONTA DESATIVADA COM SUCESSO")

Write-TestResult `
    "Menu contém desativação de conta" `
    ($moduleContent -match "4\. Desativar conta")


# ============================================================
# FORCE PASSWORD CHANGE
# ============================================================

Write-TestResult `
    "Start-V2UserForcePasswordChange existe" `
    ($moduleContent -match "function Start-V2UserForcePasswordChange")

Write-TestResult `
    "Get-UserForcePasswordChangePreview é utilizado" `
    ($moduleContent -match "Get-UserForcePasswordChangePreview")

Write-TestResult `
    "Invoke-UserForcePasswordChange é utilizado" `
    ($moduleContent -match "Invoke-UserForcePasswordChange")

Write-TestResult `
    "Mensagem de troca de senha simulada existe" `
    ($moduleContent -match "TROCA DE SENHA SIMULADA COM SUCESSO")

Write-TestResult `
    "Mensagem de troca de senha real existe" `
    ($moduleContent -match "TROCA DE SENHA OBRIGATÓRIA CONFIGURADA COM SUCESSO")

Write-TestResult `
    "Menu contém força de troca de senha" `
    ($moduleContent -match "5\. Forçar troca de senha no próximo logon")


# ============================================================
# MENU DO USUÁRIO
# ============================================================

Write-TestResult `
    "Menu contém nova consulta" `
    ($moduleContent -match "6\. Nova consulta")

Write-TestResult `
    "Menu do usuário mantém opção Voltar" `
    ($moduleContent -match "0\. Voltar")

Write-TestResult `
    "Simulation possui DisabledSamAccountNames" `
    ($moduleContent -match "DisabledSamAccountNames")

Write-TestResult `
    "Simulation possui PasswordChangeAtLogonSamAccountNames" `
    ($moduleContent -match "PasswordChangeAtLogonSamAccountNames")


# ============================================================
# PADRÃO DE SEGURANÇA
# ============================================================

Write-TestResult `
    "Interface não contém senha em texto" `
    ($moduleContent -notmatch '(?i)\bpassword\s*[:=]\s*["''][^"'']+["'']')

Write-TestResult `
    "Interface não contém Credential em configuração" `
    ($moduleContent -notmatch '(?i)\bCredential\s*[:=]')


# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RESULTADO DOS TESTES" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total : $($script:Passed + $script:Failed)"
Write-Host "PASS  : $script:Passed" -ForegroundColor Green
Write-Host "FAIL  : $script:Failed" -ForegroundColor $(if ($script:Failed -eq 0) { "Green" } else { "Red" })

Write-Host ""

if ($script:Failed -eq 0) {
    Write-Host "INTERFACE V2: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "INTERFACE V2: EXISTEM TESTES COM FALHA." -ForegroundColor Red
    exit 1
}