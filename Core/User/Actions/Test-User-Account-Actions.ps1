#Requires -Version 5.1

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
Write-Host "       TESTES - USER ACCOUNT ACTIONS V2" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$actionsPath = Join-Path `
    $PSScriptRoot `
    "User-Account-Actions.psm1"

$userCorePath = Join-Path `
    $PSScriptRoot `
    "..\User-Functions.psm1"

$auditPath = Join-Path `
    $PSScriptRoot `
    "..\..\Audit\Audit-Functions.psm1"


# ============================================================
# ARQUIVOS
# ============================================================

Write-TestResult `
    "User-Account-Actions.psm1 existe" `
    (Test-Path -LiteralPath $actionsPath)

Write-TestResult `
    "User Core existe" `
    (Test-Path -LiteralPath $userCorePath)

Write-TestResult `
    "Audit Core existe" `
    (Test-Path -LiteralPath $auditPath)


# ============================================================
# IMPORTAÇÃO
# ============================================================

$moduleImported = $false

try {
    Import-Module `
        $actionsPath `
        -Force `
        -ErrorAction Stop

    $moduleImported = $true
}
catch {
    $moduleImported = $false
}

Write-TestResult `
    "User Account Actions importa sem erro" `
    $moduleImported


# ============================================================
# FUNÇÕES
# ============================================================

Write-TestResult `
    "Get-UserUnlockPreview disponível" `
    ($null -ne (
        Get-Command `
            Get-UserUnlockPreview `
            -ErrorAction SilentlyContinue
    ))

Write-TestResult `
    "Invoke-UserUnlockAccount disponível" `
    ($null -ne (
        Get-Command `
            Invoke-UserUnlockAccount `
            -ErrorAction SilentlyContinue
    ))


# ============================================================
# CONFIGURAÇÃO
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

        LockedSamAccountNames = @(
            "silva.maria.ext"
        )
    }
}

Write-TestResult `
    "Configuração de simulação criada" `
    ($null -ne $configuration)


# ============================================================
# PREVIEW
# ============================================================

$preview = Get-UserUnlockPreview `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Preview retorna sucesso" `
    ($preview.Success -eq $true)

Write-TestResult `
    "Preview identifica usuário" `
    ($preview.UserFound -eq $true)

Write-TestResult `
    "Preview identifica conta bloqueada" `
    ($preview.LockedOut -eq $true)

Write-TestResult `
    "Preview permite execução" `
    ($preview.CanExecute -eq $true)

Write-TestResult `
    "Preview exige confirmação" `
    ($preview.RequiresConfirm -eq $true)

Write-TestResult `
    "Preview informa SimulationMode" `
    ($preview.SimulationMode -eq $true)

Write-TestResult `
    "Preview possui dados da ação" `
    ($null -ne $preview.Preview)

Write-TestResult `
    "Preview informa estado LockedOut" `
    ($preview.Preview.CurrentState -eq "LockedOut")

Write-TestResult `
    "Preview informa estado Unlocked" `
    ($preview.Preview.TargetState -eq "Unlocked")


# ============================================================
# PREVIEW ONLY + AUDIT
# ============================================================

$previewExecution = Invoke-UserUnlockAccount `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Sem -Execute retorna sucesso controlado" `
    ($previewExecution.Success -eq $true)

Write-TestResult `
    "Sem -Execute não executa ação" `
    ($previewExecution.Executed -eq $false)

Write-TestResult `
    "Sem -Execute retorna PreviewOnly" `
    ($previewExecution.Status -eq "PreviewOnly")

Write-TestResult `
    "Sem -Execute não altera dados" `
    ($previewExecution.Changed -eq $false)

Write-TestResult `
    "PreviewOnly gera auditoria" `
    ($null -ne $previewExecution.Audit)

Write-TestResult `
    "Auditoria PreviewOnly possui resultado correto" `
    ($previewExecution.Audit.Result -eq "PreviewOnly")

Write-TestResult `
    "Auditoria PreviewOnly identifica ação" `
    ($previewExecution.Audit.Action -eq "UnlockUserAccount")

Write-TestResult `
    "Auditoria PreviewOnly identifica usuário" `
    ($previewExecution.Audit.SamAccountName -eq "silva.maria.ext")

Write-TestResult `
    "Auditoria PreviewOnly informa SimulationMode" `
    ($previewExecution.Audit.SimulationMode -eq $true)


# ============================================================
# EXECUÇÃO SIMULADA + AUDIT
# ============================================================

$simulationExecution = Invoke-UserUnlockAccount `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Execução simulada retorna sucesso" `
    ($simulationExecution.Success -eq $true)

Write-TestResult `
    "SimulationMode continua ativo" `
    ($simulationExecution.SimulationMode -eq $true)

Write-TestResult `
    "Execução simulada é identificada" `
    ($simulationExecution.Executed -eq $true)

Write-TestResult `
    "Execução simulada não altera AD" `
    ($simulationExecution.Changed -eq $false)

Write-TestResult `
    "Status da simulação é Simulated" `
    ($simulationExecution.Status -eq "Simulated")

Write-TestResult `
    "Execução simulada gera auditoria" `
    ($null -ne $simulationExecution.Audit)

Write-TestResult `
    "Auditoria registra Simulated" `
    ($simulationExecution.Audit.Result -eq "Simulated")

Write-TestResult `
    "Auditoria registra SimulationMode" `
    ($simulationExecution.Audit.SimulationMode -eq $true)

Write-TestResult `
    "Auditoria registra Changed False" `
    ($simulationExecution.Audit.Changed -eq $false)

Write-TestResult `
    "Auditoria não registra Password" `
    ($simulationExecution.Audit.PSObject.Properties.Name -notcontains "Password")

Write-TestResult `
    "Auditoria não registra Credential" `
    ($simulationExecution.Audit.PSObject.Properties.Name -notcontains "Credential")


# ============================================================
# USUÁRIO NÃO BLOQUEADO
# ============================================================

$notLockedPreview = Get-UserUnlockPreview `
    -SamAccountName "silva.maria2.ext" `
    -Configuration $configuration

Write-TestResult `
    "Usuário não bloqueado retorna sucesso" `
    ($notLockedPreview.Success -eq $true)

Write-TestResult `
    "Usuário não bloqueado não permite execução" `
    ($notLockedPreview.CanExecute -eq $false)

$notLockedExecution = Invoke-UserUnlockAccount `
    -SamAccountName "silva.maria2.ext" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Usuário não bloqueado não é alterado" `
    ($notLockedExecution.Changed -eq $false)

Write-TestResult `
    "Usuário não bloqueado retorna NoChange" `
    ($notLockedExecution.Status -eq "NoChange")

Write-TestResult `
    "Usuário não bloqueado gera auditoria" `
    ($null -ne $notLockedExecution.Audit)

Write-TestResult `
    "Auditoria informa NoChange" `
    ($notLockedExecution.Audit.Result -eq "NoChange")


# ============================================================
# USUÁRIO INEXISTENTE
# ============================================================

$missingResult = Invoke-UserUnlockAccount `
    -SamAccountName "usuario.inexistente" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Usuário inexistente gera falha controlada" `
    ($missingResult.Success -eq $false)

Write-TestResult `
    "Usuário inexistente possui erro" `
    (-not [string]::IsNullOrWhiteSpace($missingResult.Error))


# ============================================================
# ENTRADA INVÁLIDA
# ============================================================

$invalidResult = Invoke-UserUnlockAccount `
    -SamAccountName " " `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "SamAccountName inválido é tratado" `
    ($invalidResult.Success -eq $false)

Write-TestResult `
    "Entrada inválida possui erro controlado" `
    (-not [string]::IsNullOrWhiteSpace($invalidResult.Error))


# ============================================================
# AMBIENTE REAL
# ============================================================

$realConfiguration = [PSCustomObject]@{
    Domain = "BRSPO"
    DomainController = "INVALID-DC-TEST"
    SimulationMode = $false

    UserPrincipalName = [PSCustomObject]@{
        Enabled = $true
        Domain  = "example.local"
    }

    Simulation = [PSCustomObject]@{
        ExistingSamAccountNames = @()
        LockedSamAccountNames = @()
    }
}

$realResult = Invoke-UserUnlockAccount `
    -SamAccountName "usuario.teste.inexistente" `
    -Configuration $realConfiguration `
    -Execute

Write-TestResult `
    "Ambiente real inválido é tratado com falha controlada" `
    ($realResult.Success -eq $false)


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
    Write-Host "USER ACCOUNT ACTIONS: TODOS OS TESTES PASSARAM!" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "USER ACCOUNT ACTIONS: EXISTEM TESTES COM FALHA!" -ForegroundColor Red
    exit 1
}