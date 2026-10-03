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

Write-TestResult `
    "Get-UserEnablePreview disponível" `
    ($null -ne (
        Get-Command `
            Get-UserEnablePreview `
            -ErrorAction SilentlyContinue
    ))

Write-TestResult `
    "Invoke-UserEnableAccount disponível" `
    ($null -ne (
        Get-Command `
            Invoke-UserEnableAccount `
            -ErrorAction SilentlyContinue
    ))

Write-TestResult `
    "Get-UserDisablePreview disponível" `
    ($null -ne (
        Get-Command `
            Get-UserDisablePreview `
            -ErrorAction SilentlyContinue
    ))

Write-TestResult `
    "Invoke-UserDisableAccount disponível" `
    ($null -ne (
        Get-Command `
            Invoke-UserDisableAccount `
            -ErrorAction SilentlyContinue
    ))

Write-TestResult `
    "Get-UserForcePasswordChangePreview disponível" `
    ($null -ne (
        Get-Command `
            Get-UserForcePasswordChangePreview `
            -ErrorAction SilentlyContinue
    ))

Write-TestResult `
    "Invoke-UserForcePasswordChange disponível" `
    ($null -ne (
        Get-Command `
            Invoke-UserForcePasswordChange `
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

        DisabledSamAccountNames = @(
            "silva.maria3.ext"
        )

        PasswordChangeAtLogonSamAccountNames = @()
    }
}

Write-TestResult `
    "Configuração de simulação criada" `
    ($null -ne $configuration)


# ============================================================
# UNLOCK - PREVIEW
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
# UNLOCK - PREVIEW ONLY + AUDIT
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
# UNLOCK - EXECUÇÃO SIMULADA + AUDIT
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
# UNLOCK - USUÁRIO NÃO BLOQUEADO
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
# ENABLE - PREVIEW
# ============================================================

$enablePreview = Get-UserEnablePreview `
    -SamAccountName "silva.maria3.ext" `
    -Configuration $configuration

Write-TestResult `
    "Enable Preview retorna sucesso" `
    ($enablePreview.Success -eq $true)

Write-TestResult `
    "Enable Preview identifica usuário" `
    ($enablePreview.UserFound -eq $true)

Write-TestResult `
    "Enable Preview identifica conta desabilitada" `
    ($enablePreview.Enabled -eq $false)

Write-TestResult `
    "Enable Preview permite execução" `
    ($enablePreview.CanExecute -eq $true)

Write-TestResult `
    "Enable Preview exige confirmação" `
    ($enablePreview.RequiresConfirm -eq $true)

Write-TestResult `
    "Enable Preview informa SimulationMode" `
    ($enablePreview.SimulationMode -eq $true)

Write-TestResult `
    "Enable Preview possui dados da ação" `
    ($null -ne $enablePreview.Preview)

Write-TestResult `
    "Enable Preview informa estado Disabled" `
    ($enablePreview.Preview.CurrentState -eq "Disabled")

Write-TestResult `
    "Enable Preview informa estado Enabled" `
    ($enablePreview.Preview.TargetState -eq "Enabled")


# ============================================================
# ENABLE - PREVIEW ONLY + AUDIT
# ============================================================

$enablePreviewExecution = Invoke-UserEnableAccount `
    -SamAccountName "silva.maria3.ext" `
    -Configuration $configuration

Write-TestResult `
    "Enable sem -Execute retorna sucesso controlado" `
    ($enablePreviewExecution.Success -eq $true)

Write-TestResult `
    "Enable sem -Execute não executa ação" `
    ($enablePreviewExecution.Executed -eq $false)

Write-TestResult `
    "Enable sem -Execute retorna PreviewOnly" `
    ($enablePreviewExecution.Status -eq "PreviewOnly")

Write-TestResult `
    "Enable sem -Execute não altera dados" `
    ($enablePreviewExecution.Changed -eq $false)

Write-TestResult `
    "Enable PreviewOnly gera auditoria" `
    ($null -ne $enablePreviewExecution.Audit)

Write-TestResult `
    "Enable Audit identifica ação" `
    ($enablePreviewExecution.Audit.Action -eq "EnableUserAccount")

Write-TestResult `
    "Enable Audit informa PreviewOnly" `
    ($enablePreviewExecution.Audit.Result -eq "PreviewOnly")

Write-TestResult `
    "Enable Audit identifica usuário" `
    ($enablePreviewExecution.Audit.SamAccountName -eq "silva.maria3.ext")

Write-TestResult `
    "Enable Audit informa SimulationMode" `
    ($enablePreviewExecution.Audit.SimulationMode -eq $true)


# ============================================================
# ENABLE - EXECUÇÃO SIMULADA + AUDIT
# ============================================================

$enableSimulation = Invoke-UserEnableAccount `
    -SamAccountName "silva.maria3.ext" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Enable simulado retorna sucesso" `
    ($enableSimulation.Success -eq $true)

Write-TestResult `
    "Enable simulado mantém SimulationMode" `
    ($enableSimulation.SimulationMode -eq $true)

Write-TestResult `
    "Enable simulado é identificado" `
    ($enableSimulation.Executed -eq $true)

Write-TestResult `
    "Enable simulado não altera AD" `
    ($enableSimulation.Changed -eq $false)

Write-TestResult `
    "Enable simulado retorna Simulated" `
    ($enableSimulation.Status -eq "Simulated")

Write-TestResult `
    "Enable simulado gera auditoria" `
    ($null -ne $enableSimulation.Audit)

Write-TestResult `
    "Enable Audit registra Simulated" `
    ($enableSimulation.Audit.Result -eq "Simulated")

Write-TestResult `
    "Enable Audit registra SimulationMode" `
    ($enableSimulation.Audit.SimulationMode -eq $true)

Write-TestResult `
    "Enable Audit registra Changed False" `
    ($enableSimulation.Audit.Changed -eq $false)

Write-TestResult `
    "Enable Audit não registra Password" `
    ($enableSimulation.Audit.PSObject.Properties.Name -notcontains "Password")

Write-TestResult `
    "Enable Audit não registra Credential" `
    ($enableSimulation.Audit.PSObject.Properties.Name -notcontains "Credential")


# ============================================================
# ENABLE - USUÁRIO JÁ ATIVO
# ============================================================

$alreadyEnabledPreview = Get-UserEnablePreview `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Usuário já ativo retorna sucesso" `
    ($alreadyEnabledPreview.Success -eq $true)

Write-TestResult `
    "Usuário já ativo não permite execução" `
    ($alreadyEnabledPreview.CanExecute -eq $false)

$alreadyEnabledExecution = Invoke-UserEnableAccount `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Usuário já ativo não é alterado" `
    ($alreadyEnabledExecution.Changed -eq $false)

Write-TestResult `
    "Usuário já ativo retorna NoChange" `
    ($alreadyEnabledExecution.Status -eq "NoChange")

Write-TestResult `
    "Usuário já ativo gera auditoria" `
    ($null -ne $alreadyEnabledExecution.Audit)

Write-TestResult `
    "Enable Audit informa NoChange" `
    ($alreadyEnabledExecution.Audit.Result -eq "NoChange")


# ============================================================
# DISABLE - PREVIEW
# ============================================================

$disablePreview = Get-UserDisablePreview `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Disable Preview retorna sucesso" `
    ($disablePreview.Success -eq $true)

Write-TestResult `
    "Disable Preview identifica usuário" `
    ($disablePreview.UserFound -eq $true)

Write-TestResult `
    "Disable Preview identifica conta ativa" `
    ($disablePreview.Enabled -eq $true)

Write-TestResult `
    "Disable Preview permite execução" `
    ($disablePreview.CanExecute -eq $true)

Write-TestResult `
    "Disable Preview exige confirmação" `
    ($disablePreview.RequiresConfirm -eq $true)

Write-TestResult `
    "Disable Preview informa SimulationMode" `
    ($disablePreview.SimulationMode -eq $true)

Write-TestResult `
    "Disable Preview possui dados da ação" `
    ($null -ne $disablePreview.Preview)

Write-TestResult `
    "Disable Preview informa estado Enabled" `
    ($disablePreview.Preview.CurrentState -eq "Enabled")

Write-TestResult `
    "Disable Preview informa estado Disabled" `
    ($disablePreview.Preview.TargetState -eq "Disabled")


# ============================================================
# DISABLE - PREVIEW ONLY + AUDIT
# ============================================================

$disablePreviewExecution = Invoke-UserDisableAccount `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Disable sem -Execute retorna sucesso controlado" `
    ($disablePreviewExecution.Success -eq $true)

Write-TestResult `
    "Disable sem -Execute não executa ação" `
    ($disablePreviewExecution.Executed -eq $false)

Write-TestResult `
    "Disable sem -Execute retorna PreviewOnly" `
    ($disablePreviewExecution.Status -eq "PreviewOnly")

Write-TestResult `
    "Disable sem -Execute não altera dados" `
    ($disablePreviewExecution.Changed -eq $false)

Write-TestResult `
    "Disable PreviewOnly gera auditoria" `
    ($null -ne $disablePreviewExecution.Audit)

Write-TestResult `
    "Disable Audit identifica ação" `
    ($disablePreviewExecution.Audit.Action -eq "DisableUserAccount")

Write-TestResult `
    "Disable Audit informa PreviewOnly" `
    ($disablePreviewExecution.Audit.Result -eq "PreviewOnly")

Write-TestResult `
    "Disable Audit identifica usuário" `
    ($disablePreviewExecution.Audit.SamAccountName -eq "silva.maria.ext")

Write-TestResult `
    "Disable Audit informa SimulationMode" `
    ($disablePreviewExecution.Audit.SimulationMode -eq $true)


# ============================================================
# DISABLE - EXECUÇÃO SIMULADA + AUDIT
# ============================================================

$disableSimulation = Invoke-UserDisableAccount `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Disable simulado retorna sucesso" `
    ($disableSimulation.Success -eq $true)

Write-TestResult `
    "Disable simulado mantém SimulationMode" `
    ($disableSimulation.SimulationMode -eq $true)

Write-TestResult `
    "Disable simulado é identificado" `
    ($disableSimulation.Executed -eq $true)

Write-TestResult `
    "Disable simulado não altera AD" `
    ($disableSimulation.Changed -eq $false)

Write-TestResult `
    "Disable simulado retorna Simulated" `
    ($disableSimulation.Status -eq "Simulated")

Write-TestResult `
    "Disable simulado gera auditoria" `
    ($null -ne $disableSimulation.Audit)

Write-TestResult `
    "Disable Audit registra Simulated" `
    ($disableSimulation.Audit.Result -eq "Simulated")

Write-TestResult `
    "Disable Audit registra SimulationMode" `
    ($disableSimulation.Audit.SimulationMode -eq $true)

Write-TestResult `
    "Disable Audit registra Changed False" `
    ($disableSimulation.Audit.Changed -eq $false)

Write-TestResult `
    "Disable Audit não registra Password" `
    ($disableSimulation.Audit.PSObject.Properties.Name -notcontains "Password")

Write-TestResult `
    "Disable Audit não registra Credential" `
    ($disableSimulation.Audit.PSObject.Properties.Name -notcontains "Credential")


# ============================================================
# DISABLE - USUÁRIO JÁ DESABILITADO
# ============================================================

$alreadyDisabledPreview = Get-UserDisablePreview `
    -SamAccountName "silva.maria3.ext" `
    -Configuration $configuration

Write-TestResult `
    "Usuário já desabilitado retorna sucesso" `
    ($alreadyDisabledPreview.Success -eq $true)

Write-TestResult `
    "Usuário já desabilitado não permite execução" `
    ($alreadyDisabledPreview.CanExecute -eq $false)

$alreadyDisabledExecution = Invoke-UserDisableAccount `
    -SamAccountName "silva.maria3.ext" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Usuário já desabilitado não é alterado" `
    ($alreadyDisabledExecution.Changed -eq $false)

Write-TestResult `
    "Usuário já desabilitado retorna NoChange" `
    ($alreadyDisabledExecution.Status -eq "NoChange")

Write-TestResult `
    "Usuário já desabilitado gera auditoria" `
    ($null -ne $alreadyDisabledExecution.Audit)

Write-TestResult `
    "Disable Audit informa NoChange" `
    ($alreadyDisabledExecution.Audit.Result -eq "NoChange")


# ============================================================
# FORCE PASSWORD CHANGE - PREVIEW
# ============================================================

$forcePasswordChangePreview = Get-UserForcePasswordChangePreview `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Force Password Change Preview retorna sucesso" `
    ($forcePasswordChangePreview.Success -eq $true)

Write-TestResult `
    "Force Password Change Preview identifica usuário" `
    ($forcePasswordChangePreview.UserFound -eq $true)

Write-TestResult `
    "Force Password Change Preview identifica estado atual NotRequired" `
    ($forcePasswordChangePreview.PasswordChangeAtLogon -eq $false)

Write-TestResult `
    "Force Password Change Preview permite execução" `
    ($forcePasswordChangePreview.CanExecute -eq $true)

Write-TestResult `
    "Force Password Change Preview exige confirmação" `
    ($forcePasswordChangePreview.RequiresConfirm -eq $true)

Write-TestResult `
    "Force Password Change Preview informa SimulationMode" `
    ($forcePasswordChangePreview.SimulationMode -eq $true)

Write-TestResult `
    "Force Password Change Preview possui dados da ação" `
    ($null -ne $forcePasswordChangePreview.Preview)

Write-TestResult `
    "Force Password Change Preview informa estado NotRequired" `
    ($forcePasswordChangePreview.Preview.CurrentState -eq "NotRequired")

Write-TestResult `
    "Force Password Change Preview informa estado Required" `
    ($forcePasswordChangePreview.Preview.TargetState -eq "Required")


# ============================================================
# FORCE PASSWORD CHANGE - PREVIEW ONLY + AUDIT
# ============================================================

$forcePreviewExecution = Invoke-UserForcePasswordChange `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration

Write-TestResult `
    "Force Password Change sem -Execute retorna sucesso controlado" `
    ($forcePreviewExecution.Success -eq $true)

Write-TestResult `
    "Force Password Change sem -Execute não executa ação" `
    ($forcePreviewExecution.Executed -eq $false)

Write-TestResult `
    "Force Password Change sem -Execute retorna PreviewOnly" `
    ($forcePreviewExecution.Status -eq "PreviewOnly")

Write-TestResult `
    "Force Password Change sem -Execute não altera dados" `
    ($forcePreviewExecution.Changed -eq $false)

Write-TestResult `
    "Force Password Change PreviewOnly gera auditoria" `
    ($null -ne $forcePreviewExecution.Audit)

Write-TestResult `
    "Force Password Change Audit identifica ação" `
    ($forcePreviewExecution.Audit.Action -eq "ForcePasswordChange")

Write-TestResult `
    "Force Password Change Audit informa PreviewOnly" `
    ($forcePreviewExecution.Audit.Result -eq "PreviewOnly")

Write-TestResult `
    "Force Password Change Audit identifica usuário" `
    ($forcePreviewExecution.Audit.SamAccountName -eq "silva.maria.ext")

Write-TestResult `
    "Force Password Change Audit informa SimulationMode" `
    ($forcePreviewExecution.Audit.SimulationMode -eq $true)


# ============================================================
# FORCE PASSWORD CHANGE - EXECUÇÃO SIMULADA + AUDIT
# ============================================================

$forceSimulation = Invoke-UserForcePasswordChange `
    -SamAccountName "silva.maria.ext" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Force Password Change simulado retorna sucesso" `
    ($forceSimulation.Success -eq $true)

Write-TestResult `
    "Force Password Change simulado mantém SimulationMode" `
    ($forceSimulation.SimulationMode -eq $true)

Write-TestResult `
    "Force Password Change simulado é identificado" `
    ($forceSimulation.Executed -eq $true)

Write-TestResult `
    "Force Password Change simulado não altera AD" `
    ($forceSimulation.Changed -eq $false)

Write-TestResult `
    "Force Password Change simulado retorna Simulated" `
    ($forceSimulation.Status -eq "Simulated")

Write-TestResult `
    "Force Password Change simulado gera auditoria" `
    ($null -ne $forceSimulation.Audit)

Write-TestResult `
    "Force Password Change Audit registra Simulated" `
    ($forceSimulation.Audit.Result -eq "Simulated")

Write-TestResult `
    "Force Password Change Audit registra SimulationMode" `
    ($forceSimulation.Audit.SimulationMode -eq $true)

Write-TestResult `
    "Force Password Change Audit registra Changed False" `
    ($forceSimulation.Audit.Changed -eq $false)

Write-TestResult `
    "Force Password Change Audit não registra Password" `
    ($forceSimulation.Audit.PSObject.Properties.Name -notcontains "Password")

Write-TestResult `
    "Force Password Change Audit não registra Credential" `
    ($forceSimulation.Audit.PSObject.Properties.Name -notcontains "Credential")


# ============================================================
# FORCE PASSWORD CHANGE - USUÁRIO JÁ CONFIGURADO
# ============================================================

$forceAlreadyConfiguration = [PSCustomObject]@{
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

        DisabledSamAccountNames = @(
            "silva.maria3.ext"
        )

        PasswordChangeAtLogonSamAccountNames = @(
            "silva.maria.ext"
        )
    }
}

$forceAlreadyPreview = Get-UserForcePasswordChangePreview `
    -SamAccountName "silva.maria.ext" `
    -Configuration $forceAlreadyConfiguration

Write-TestResult `
    "Usuário já configurado para troca de senha retorna sucesso" `
    ($forceAlreadyPreview.Success -eq $true)

Write-TestResult `
    "Usuário já configurado para troca de senha não permite execução" `
    ($forceAlreadyPreview.CanExecute -eq $false)

Write-TestResult `
    "Usuário já configurado para troca de senha informa estado Required" `
    ($forceAlreadyPreview.PasswordChangeAtLogon -eq $true)

$forceAlreadyExecution = Invoke-UserForcePasswordChange `
    -SamAccountName "silva.maria.ext" `
    -Configuration $forceAlreadyConfiguration `
    -Execute

Write-TestResult `
    "Usuário já configurado para troca de senha não é alterado" `
    ($forceAlreadyExecution.Changed -eq $false)

Write-TestResult `
    "Usuário já configurado para troca de senha retorna NoChange" `
    ($forceAlreadyExecution.Status -eq "NoChange")

Write-TestResult `
    "Usuário já configurado para troca de senha gera auditoria" `
    ($null -ne $forceAlreadyExecution.Audit)

Write-TestResult `
    "Force Password Change Audit informa NoChange" `
    ($forceAlreadyExecution.Audit.Result -eq "NoChange")


# ============================================================
# USUÁRIO INEXISTENTE - UNLOCK
# ============================================================

$missingUnlockResult = Invoke-UserUnlockAccount `
    -SamAccountName "usuario.inexistente" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Unlock de usuário inexistente gera falha controlada" `
    ($missingUnlockResult.Success -eq $false)

Write-TestResult `
    "Unlock de usuário inexistente possui erro" `
    (-not [string]::IsNullOrWhiteSpace($missingUnlockResult.Error))


# ============================================================
# USUÁRIO INEXISTENTE - ENABLE
# ============================================================

$missingEnableResult = Invoke-UserEnableAccount `
    -SamAccountName "usuario.inexistente" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Enable de usuário inexistente gera falha controlada" `
    ($missingEnableResult.Success -eq $false)

Write-TestResult `
    "Enable de usuário inexistente possui erro" `
    (-not [string]::IsNullOrWhiteSpace($missingEnableResult.Error))


# ============================================================
# USUÁRIO INEXISTENTE - DISABLE
# ============================================================

$missingDisableResult = Invoke-UserDisableAccount `
    -SamAccountName "usuario.inexistente" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Disable de usuário inexistente gera falha controlada" `
    ($missingDisableResult.Success -eq $false)

Write-TestResult `
    "Disable de usuário inexistente possui erro" `
    (-not [string]::IsNullOrWhiteSpace($missingDisableResult.Error))


# ============================================================
# USUÁRIO INEXISTENTE - FORCE PASSWORD CHANGE
# ============================================================

$missingForcePasswordChangeResult = Invoke-UserForcePasswordChange `
    -SamAccountName "usuario.inexistente" `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Force Password Change de usuário inexistente gera falha controlada" `
    ($missingForcePasswordChangeResult.Success -eq $false)

Write-TestResult `
    "Force Password Change de usuário inexistente possui erro" `
    (-not [string]::IsNullOrWhiteSpace($missingForcePasswordChangeResult.Error))


# ============================================================
# ENTRADA INVÁLIDA - UNLOCK
# ============================================================

$invalidUnlockResult = Invoke-UserUnlockAccount `
    -SamAccountName " " `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Unlock com SamAccountName inválido é tratado" `
    ($invalidUnlockResult.Success -eq $false)

Write-TestResult `
    "Unlock inválido possui erro controlado" `
    (-not [string]::IsNullOrWhiteSpace($invalidUnlockResult.Error))


# ============================================================
# ENTRADA INVÁLIDA - ENABLE
# ============================================================

$invalidEnableResult = Invoke-UserEnableAccount `
    -SamAccountName " " `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Enable com SamAccountName inválido é tratado" `
    ($invalidEnableResult.Success -eq $false)

Write-TestResult `
    "Enable inválido possui erro controlado" `
    (-not [string]::IsNullOrWhiteSpace($invalidEnableResult.Error))


# ============================================================
# ENTRADA INVÁLIDA - DISABLE
# ============================================================

$invalidDisableResult = Invoke-UserDisableAccount `
    -SamAccountName " " `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Disable com SamAccountName inválido é tratado" `
    ($invalidDisableResult.Success -eq $false)

Write-TestResult `
    "Disable inválido possui erro controlado" `
    (-not [string]::IsNullOrWhiteSpace($invalidDisableResult.Error))


# ============================================================
# ENTRADA INVÁLIDA - FORCE PASSWORD CHANGE
# ============================================================

$invalidForcePasswordChangeResult = Invoke-UserForcePasswordChange `
    -SamAccountName " " `
    -Configuration $configuration `
    -Execute

Write-TestResult `
    "Force Password Change com SamAccountName inválido é tratado" `
    ($invalidForcePasswordChangeResult.Success -eq $false)

Write-TestResult `
    "Force Password Change inválido possui erro controlado" `
    (-not [string]::IsNullOrWhiteSpace($invalidForcePasswordChangeResult.Error))


# ============================================================
# AMBIENTE REAL - CONFIGURAÇÃO INVÁLIDA
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
        DisabledSamAccountNames = @()
        PasswordChangeAtLogonSamAccountNames = @()
    }
}


# ============================================================
# AMBIENTE REAL - UNLOCK
# ============================================================

$realUnlockResult = Invoke-UserUnlockAccount `
    -SamAccountName "usuario.teste.inexistente" `
    -Configuration $realConfiguration `
    -Execute

Write-TestResult `
    "Ambiente real inválido do Unlock é tratado com falha controlada" `
    ($realUnlockResult.Success -eq $false)


# ============================================================
# AMBIENTE REAL - ENABLE
# ============================================================

$realEnableResult = Invoke-UserEnableAccount `
    -SamAccountName "usuario.teste.inexistente" `
    -Configuration $realConfiguration `
    -Execute

Write-TestResult `
    "Ambiente real inválido do Enable é tratado com falha controlada" `
    ($realEnableResult.Success -eq $false)


# ============================================================
# AMBIENTE REAL - DISABLE
# ============================================================

$realDisableResult = Invoke-UserDisableAccount `
    -SamAccountName "usuario.teste.inexistente" `
    -Configuration $realConfiguration `
    -Execute

Write-TestResult `
    "Ambiente real inválido do Disable é tratado com falha controlada" `
    ($realDisableResult.Success -eq $false)


# ============================================================
# AMBIENTE REAL - FORCE PASSWORD CHANGE
# ============================================================

$realForcePasswordChangeResult = Invoke-UserForcePasswordChange `
    -SamAccountName "usuario.teste.inexistente" `
    -Configuration $realConfiguration `
    -Execute

Write-TestResult `
    "Ambiente real inválido do Force Password Change é tratado com falha controlada" `
    ($realForcePasswordChangeResult.Success -eq $false)


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