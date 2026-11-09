#Requires -Version 5.1

$ErrorActionPreference = "Stop"
Import-Module Microsoft.PowerShell.Management -ErrorAction Stop
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$global:PSModuleAutoLoadingPreference = 'None'
Write-Output 'HARNESS_START:USER_ACCOUNT_ACTIONS_V1'

if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) {
    throw "ActiveDirectory já está carregado neste processo; o harness não continuará."
}

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

    $actionsModules = @(Get-Module | Where-Object { $_.Path -eq [System.IO.Path]::GetFullPath($actionsPath) })
    if ($actionsModules.Count -ne 1) { throw "Esperada uma instância User Actions; encontradas $($actionsModules.Count)." }
    $actionsModule = $actionsModules[0]
    $userCoreModule = & $actionsModule { (Get-Command Get-UserADInfo -CommandType Function -ErrorAction Stop).Module }
    if ($null -eq $userCoreModule -or $userCoreModule.Path -ne [System.IO.Path]::GetFullPath($userCorePath)) {
        throw "Get-UserADInfo não resolve para a instância esperada do User Core."
    }
    if ($null -ne $actionsModule) {
        & $actionsModule {
            $script:ExternalCallCounts = @{ GetModule=0; ImportModule=0; Unlock=0; Enable=0; Disable=0; SetUser=0 }
            $script:ShouldProcessDecision = $true
            Set-Item Function:\script:Invoke-UserActionShouldProcess { param($Cmdlet,$Target,$Action); return $script:ShouldProcessDecision } -Force
            Set-Item Function:\script:Get-Module { param([string]$Name,[switch]$ListAvailable); if ($Name -ne 'ActiveDirectory') { throw "Get-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.GetModule++; [PSCustomObject]@{Name='ActiveDirectory'} } -Force
            Set-Item Function:\script:Import-Module { param([string]$Name,[string]$ErrorAction); if ($Name -ne 'ActiveDirectory') { throw "Import-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.ImportModule++ } -Force
            Set-Item Function:\script:Unlock-ADAccount { param([string]$Identity,[string]$Server,[string]$ErrorAction); $script:ExternalCallCounts.Unlock++ } -Force
            Set-Item Function:\script:Enable-ADAccount { param([string]$Identity,[string]$Server,[string]$ErrorAction); $script:ExternalCallCounts.Enable++ } -Force
            Set-Item Function:\script:Disable-ADAccount { param([string]$Identity,[string]$Server,[string]$ErrorAction); $script:ExternalCallCounts.Disable++ } -Force
            Set-Item Function:\script:Set-ADUser { param([string]$Identity,[string]$Server,[bool]$ChangePasswordAtLogon,[string]$ErrorAction); $script:ExternalCallCounts.SetUser++ } -Force
        }
    }
    if ($null -ne $userCoreModule) {
        & $userCoreModule {
            $script:ExternalCallCounts = @{ GetModule=0; ImportModule=0; GetADUser=0 }
            $script:ADFixtureNull = $false
            Set-Item Function:\script:Get-Module { param([string]$Name,[switch]$ListAvailable); if ($Name -ne 'ActiveDirectory') { throw "Get-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.GetModule++; [PSCustomObject]@{Name='ActiveDirectory'} } -Force
            Set-Item Function:\script:Import-Module { param([string]$Name,[string]$ErrorAction); if ($Name -ne 'ActiveDirectory') { throw "Import-Module inesperado bloqueado: $Name" }; $script:ExternalCallCounts.ImportModule++ } -Force
            Set-Item Function:\script:Get-ADUser { param([string]$Identity,[string]$Server,[string[]]$Properties,[string]$ErrorAction); $script:ExternalCallCounts.GetADUser++; if ($script:ADFixtureNull) { return $null }; [PSCustomObject]@{SamAccountName='fixture.user';UserPrincipalName='fixture.user@example.invalid';Name='Fixture User';Enabled=$true;LockedOut=$false;MemberOf=@()} } -Force
        }
    }

    $actionsStubResolution = & $actionsModule {
        [PSCustomObject]@{
            Loader = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
            ModuleLookup = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
            Mutator = (Get-Command Disable-ADAccount -CommandType Function -ErrorAction SilentlyContinue).CommandType
            LoaderModule = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Module
            ModuleLookupModule = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Module
            MutatorModule = (Get-Command Disable-ADAccount -CommandType Function -ErrorAction SilentlyContinue).Module
            UnlockModule = (Get-Command Unlock-ADAccount -CommandType Function -ErrorAction SilentlyContinue).Module
            EnableModule = (Get-Command Enable-ADAccount -CommandType Function -ErrorAction SilentlyContinue).Module
            SetUserModule = (Get-Command Set-ADUser -CommandType Function -ErrorAction SilentlyContinue).Module
            LoaderIdentity = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.ImportModule'
            ModuleLookupIdentity = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetModule'
            MutatorIdentity = (Get-Command Disable-ADAccount -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.Disable'
            UnlockIdentity = (Get-Command Unlock-ADAccount -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.Unlock'
            EnableIdentity = (Get-Command Enable-ADAccount -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.Enable'
            SetUserIdentity = (Get-Command Set-ADUser -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.SetUser'
        }
    }
    $coreStubResolution = & $userCoreModule {
        [PSCustomObject]@{
            Loader = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
            ModuleLookup = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).CommandType
            ADUser = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).CommandType
            LoaderModule = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Module
            ModuleLookupModule = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Module
            ADUserModule = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).Module
            LoaderIdentity = (Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.ImportModule'
            ModuleLookupIdentity = (Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetModule'
            ADUserIdentity = (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).Definition -match 'ExternalCallCounts.GetADUser'
        }
    }
    if ($actionsStubResolution.Loader -ne 'Function' -or $actionsStubResolution.ModuleLookup -ne 'Function' -or $actionsStubResolution.Mutator -ne 'Function' -or
        $coreStubResolution.Loader -ne 'Function' -or $coreStubResolution.ModuleLookup -ne 'Function' -or $coreStubResolution.ADUser -ne 'Function' -or
        $actionsStubResolution.LoaderModule -ne $actionsModule -or $actionsStubResolution.ModuleLookupModule -ne $actionsModule -or
        $actionsStubResolution.MutatorModule -ne $actionsModule -or $actionsStubResolution.UnlockModule -ne $actionsModule -or
        $actionsStubResolution.EnableModule -ne $actionsModule -or $actionsStubResolution.SetUserModule -ne $actionsModule -or
        $coreStubResolution.LoaderModule -ne $userCoreModule -or $coreStubResolution.ModuleLookupModule -ne $userCoreModule -or
        $coreStubResolution.ADUserModule -ne $userCoreModule -or
        -not $actionsStubResolution.LoaderIdentity -or -not $actionsStubResolution.ModuleLookupIdentity -or -not $actionsStubResolution.MutatorIdentity -or
        -not $actionsStubResolution.UnlockIdentity -or -not $actionsStubResolution.EnableIdentity -or -not $actionsStubResolution.SetUserIdentity -or
        -not $coreStubResolution.LoaderIdentity -or -not $coreStubResolution.ModuleLookupIdentity -or -not $coreStubResolution.ADUserIdentity) {
        throw "Resolução incompleta dos stubs nos SessionStates de User Actions/Core."
    }

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
# SEGURANÇA - TESTES SEM EXECUÇÃO REAL NO ACTIVE DIRECTORY
# ============================================================

Write-TestResult `
    "Configuração principal mantém SimulationMode ativo" `
    ($configuration.SimulationMode -eq $true)

Write-TestResult `
    "Configuração de simulação não define controlador de domínio" `
    ([string]::IsNullOrWhiteSpace($configuration.DomainController))

Write-TestResult `
    "Usuário de simulação para Unlock está configurado" `
    ($configuration.Simulation.LockedSamAccountNames -contains "silva.maria.ext")

Write-TestResult `
    "Usuário de simulação para Disable está configurado" `
    ($configuration.Simulation.DisabledSamAccountNames -contains "silva.maria3.ext")

Write-TestResult `
    "Configuração de simulação não inclui usuários de produção" `
    ($configuration.Simulation.ExistingSamAccountNames.Count -eq 3)

# ============================================================
# ISOLAMENTO FAIL-CLOSED
# ============================================================

$realFixtureConfiguration = [PSCustomObject]@{}
foreach ($configurationProperty in $configuration.PSObject.Properties) {
    $realFixtureConfiguration | Add-Member -NotePropertyName $configurationProperty.Name -NotePropertyValue $configurationProperty.Value
}
$realFixtureConfiguration.SimulationMode = $false
$realFixtureConfiguration.DomainController = 'fixture.invalid'
$actionCountsBefore = & $actionsModule { @{} + $script:ExternalCallCounts }
$coreCountsBefore = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "Caminhos de ações simuladas não chamaram fronteiras" ((($actionCountsBefore.Values | Measure-Object -Sum).Sum -eq 0) -and (($coreCountsBefore.Values | Measure-Object -Sum).Sum -eq 0))
$actionStubResolution = & $actionsModule { (Get-Command Disable-ADAccount -CommandType Function -ErrorAction SilentlyContinue).CommandType }
$actionCoreStubResolution = & $userCoreModule { (Get-Command Get-ADUser -CommandType Function -ErrorAction SilentlyContinue).CommandType }
Write-TestResult "Actions e Core aninhado resolvem stubs em seus módulos" ($actionStubResolution -eq 'Function' -and $actionCoreStubResolution -eq 'Function')
$blockedWrite = Invoke-UserDisableAccount -SamAccountName 'fixture.user' -Configuration $realFixtureConfiguration -Execute
$actionCountsAfterBlocked = & $actionsModule { @{} + $script:ExternalCallCounts }
$coreCountsAfterBlocked = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "Execute sem autorizações de leitura/escrita falha fechado" (-not $blockedWrite.Success -and $blockedWrite.Error -match 'AllowRealRead')
Write-TestResult "Execute não autorizado não chama fronteiras" ((($actionCountsBefore.Values | Measure-Object -Sum).Sum -eq ($actionCountsAfterBlocked.Values | Measure-Object -Sum).Sum) -and (($coreCountsBefore.Values | Measure-Object -Sum).Sum -eq ($coreCountsAfterBlocked.Values | Measure-Object -Sum).Sum))
$readOnlyWrite = Invoke-UserDisableAccount -SamAccountName 'fixture.user' -Configuration $realFixtureConfiguration -Execute -AllowRealRead -Confirm:$false
$writeOnlyAction = Invoke-UserDisableAccount -SamAccountName 'fixture.user' -Configuration $realFixtureConfiguration -Execute -AllowRealWrite -Confirm:$false
$countsAfterSplitChecks = & $actionsModule { @{} + $script:ExternalCallCounts }
Write-TestResult "AllowRealRead não autoriza mutação" (-not $readOnlyWrite.Success -and $readOnlyWrite.Error -match 'AllowRealWrite')
Write-TestResult "AllowRealWrite não autoriza leitura" (-not $writeOnlyAction.Success -and $writeOnlyAction.Error -match 'AllowRealRead')
Write-TestResult "Autorizações separadas falham antes das fronteiras" (($countsAfterSplitChecks.Values | Measure-Object -Sum).Sum -eq ($actionCountsAfterBlocked.Values | Measure-Object -Sum).Sum)

$whatIfWrite = Invoke-UserDisableAccount -SamAccountName 'fixture.user' -Configuration $realFixtureConfiguration -Execute -AllowRealRead -AllowRealWrite -WhatIf
$actionCountsAfterWhatIf = & $actionsModule { @{} + $script:ExternalCallCounts }
$coreCountsAfterWhatIf = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "WhatIf não coleta nem altera" ($whatIfWrite.Mode -eq 'Preview' -and $whatIfWrite.Cancelled -eq $false)
Write-TestResult "WhatIf mantém contadores externos" ((($actionCountsAfterBlocked.Values | Measure-Object -Sum).Sum -eq ($actionCountsAfterWhatIf.Values | Measure-Object -Sum).Sum) -and (($coreCountsAfterBlocked.Values | Measure-Object -Sum).Sum -eq ($coreCountsAfterWhatIf.Values | Measure-Object -Sum).Sum))
$conflictingWhatIf = Invoke-UserDisableAccount -SamAccountName 'silva.maria.ext' -Configuration $configuration -Execute -AllowRealRead -AllowRealWrite -WhatIf
$countsAfterConflictingWhatIf = & $actionsModule { @{} + $script:ExternalCallCounts }
Write-TestResult "Actions rejeita autorizações conflitantes antes de WhatIf" (-not $conflictingWhatIf.Success -and $conflictingWhatIf.Error -match 'conflit' -and (($countsAfterConflictingWhatIf.Values | Measure-Object -Sum).Sum -eq ($actionCountsAfterWhatIf.Values | Measure-Object -Sum).Sum))

& $actionsModule { $script:ShouldProcessDecision = $false }
$countsBeforeDecline = & $actionsModule { @{} + $script:ExternalCallCounts }
$declinedWrite = Invoke-UserDisableAccount -SamAccountName 'fixture.user' -Configuration $realFixtureConfiguration -Execute -AllowRealRead -AllowRealWrite -Confirm:$false
$countsAfterDecline = & $actionsModule { @{} + $script:ExternalCallCounts }
Write-TestResult "Recusa ShouldProcess é cancelamento determinístico" ($declinedWrite.Status -eq 'Cancelled' -and $declinedWrite.Cancelled -and $declinedWrite.Mode -eq 'Preview')
Write-TestResult "Recusa ShouldProcess ocorre antes de qualquer consulta" (($countsBeforeDecline.Values | Measure-Object -Sum).Sum -eq ($countsAfterDecline.Values | Measure-Object -Sum).Sum)
& $actionsModule { $script:ShouldProcessDecision = $true }

$authorizedStubWrite = Invoke-UserDisableAccount -SamAccountName 'fixture.user' -Configuration $realFixtureConfiguration -Execute -AllowRealRead -AllowRealWrite -Confirm:$false
$authorizedActionCounts = & $actionsModule { @{} + $script:ExternalCallCounts }
$authorizedCoreCounts = & $userCoreModule { @{} + $script:ExternalCallCounts }
Write-TestResult "Fluxo autorizado termina em mutador stub" ($authorizedStubWrite.Success -and $authorizedActionCounts.Disable -eq 1)
Write-TestResult "Fluxo autorizado usa somente stubs contados" ($authorizedActionCounts.GetModule -gt 0 -and $authorizedActionCounts.ImportModule -gt 0 -and $authorizedCoreCounts.GetADUser -gt 0)

& $userCoreModule { $script:ADFixtureNull = $true }
$notFoundActionPreviews = @(
    (Get-UserUnlockPreview -SamAccountName 'missing.fixture' -Configuration $realFixtureConfiguration -AllowRealRead),
    (Get-UserEnablePreview -SamAccountName 'missing.fixture' -Configuration $realFixtureConfiguration -AllowRealRead),
    (Get-UserDisablePreview -SamAccountName 'missing.fixture' -Configuration $realFixtureConfiguration -AllowRealRead),
    (Get-UserForcePasswordChangePreview -SamAccountName 'missing.fixture' -Configuration $realFixtureConfiguration -AllowRealRead)
)
$notFoundActions = @(
    (Invoke-UserUnlockAccount -SamAccountName 'missing.fixture' -Configuration $realFixtureConfiguration -Execute -AllowRealRead -AllowRealWrite -Confirm:$false),
    (Invoke-UserEnableAccount -SamAccountName 'missing.fixture' -Configuration $realFixtureConfiguration -Execute -AllowRealRead -AllowRealWrite -Confirm:$false),
    (Invoke-UserDisableAccount -SamAccountName 'missing.fixture' -Configuration $realFixtureConfiguration -Execute -AllowRealRead -AllowRealWrite -Confirm:$false),
    (Invoke-UserForcePasswordChange -SamAccountName 'missing.fixture' -Configuration $realFixtureConfiguration -Execute -AllowRealRead -AllowRealWrite -Confirm:$false)
)
& $userCoreModule { $script:ADFixtureNull = $false }
$notFoundActionCounts = & $actionsModule { @{} + $script:ExternalCallCounts }
Write-TestResult "As quatro previews preservam NotFound sem Error" (@($notFoundActionPreviews | Where-Object { $_.Status -ne 'NotFound' -or $_.QueryStatus -ne 'NotFound' -or $_.UserFound -ne $false -or $null -ne $_.Error }).Count -eq 0)
Write-TestResult "As quatro ações preservam NotFound e falham sem alegar sucesso" (@($notFoundActions | Where-Object { $_.Success -or $_.Status -ne 'NotFound' -or $_.QueryStatus -ne 'NotFound' -or $null -ne $_.Error }).Count -eq 0)
Write-TestResult "NotFound não alcança mutadores" (($notFoundActionCounts.Unlock -eq $authorizedActionCounts.Unlock) -and ($notFoundActionCounts.Enable -eq $authorizedActionCounts.Enable) -and ($notFoundActionCounts.Disable -eq $authorizedActionCounts.Disable) -and ($notFoundActionCounts.SetUser -eq $authorizedActionCounts.SetUser))

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
    Write-Output 'HARNESS_PASS:USER_ACCOUNT_ACTIONS_V1'
    exit 0
}
else {
    Write-Host "USER ACCOUNT ACTIONS: EXISTEM TESTES COM FALHA!" -ForegroundColor Red
    exit 1
}
