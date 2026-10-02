#Requires -Version 5.1

<#
.SYNOPSIS
    Ações administrativas de contas de usuário - V2.

.DESCRIPTION
    Camada responsável por ações administrativas sobre contas
    de usuários do Active Directory.

    Primeira ação implementada:
    - Unlock User Account

    Princípios:
    - Simulation Mode seguro.
    - Preview antes da execução.
    - Execução somente com -Execute.
    - Nunca registra senha ou credenciais.
    - Auditoria após o resultado da ação.
    - Retorno padronizado.
#>

Set-StrictMode -Version Latest

$userCorePath = Join-Path `
    $PSScriptRoot `
    "..\User-Functions.psm1"

$auditPath = Join-Path `
    $PSScriptRoot `
    "..\..\Audit\Audit-Functions.psm1"

if (-not (Test-Path -LiteralPath $userCorePath)) {
    throw "User Core não encontrado: $userCorePath"
}

if (-not (Test-Path -LiteralPath $auditPath)) {
    throw "Audit Core não encontrado: $auditPath"
}

Import-Module $userCorePath -Force -ErrorAction Stop
Import-Module $auditPath -Force -ErrorAction Stop


function Get-UserUnlockPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Configuration
    )

    $result = [PSCustomObject]@{
        Success         = $false
        Action          = "UnlockUserAccount"
        SamAccountName  = $SamAccountName
        SimulationMode  = $false
        UserFound       = $false
        LockedOut       = $false
        CanExecute      = $false
        RequiresConfirm = $true
        Preview         = $null
        Error           = $null
    }

    try {
        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
            $result.Error =
                "O SamAccountName é obrigatório para realizar o desbloqueio."
            return $result
        }

        if ($Configuration.PSObject.Properties.Name -contains "SimulationMode") {
            $result.SimulationMode = [bool]$Configuration.SimulationMode
        }

        $userResult = Get-UserADInfo `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration

        if ($null -eq $userResult) {
            $result.Error = "User Core não retornou resultado."
            return $result
        }

        if (-not $userResult.Success) {
            $result.Error = $userResult.Error
            return $result
        }

        if ($null -eq $userResult.Data) {
            $result.Error =
                "User Core informou sucesso, mas não retornou dados do usuário."
            return $result
        }

        $result.UserFound = $true

        $lockedOut = $false

        if ($null -ne $userResult.Data.Account) {
            if (
                $userResult.Data.Account.PSObject.Properties.Name `
                    -contains "LockedOut"
            ) {
                $lockedOut = [bool]$userResult.Data.Account.LockedOut
            }
        }

        if ($result.SimulationMode) {
            if (
                $null -ne $Configuration.Simulation -and
                $Configuration.Simulation.PSObject.Properties.Name `
                    -contains "LockedSamAccountNames"
            ) {
                $lockedNames = @(
                    $Configuration.Simulation.LockedSamAccountNames
                )

                if ($lockedNames -contains $SamAccountName) {
                    $lockedOut = $true
                }
            }
        }

        $result.LockedOut = $lockedOut

        if ($lockedOut) {
            $result.CanExecute = $true
        }
        else {
            $result.CanExecute = $false
        }

        $actionDescription = if ($lockedOut) {
            "Desbloquear a conta do usuário."
        }
        else {
            "A conta do usuário não está bloqueada."
        }

        $result.Preview = [PSCustomObject]@{
            Action          = "UnlockUserAccount"
            SamAccountName  = $SamAccountName
            Description     = $actionDescription
            CurrentState    = if ($lockedOut) {
                "LockedOut"
            }
            else {
                "NotLocked"
            }
            TargetState     = if ($lockedOut) {
                "Unlocked"
            }
            else {
                "NoChange"
            }
            SimulationMode  = $result.SimulationMode
            RequiresConfirm = $true
            CanExecute      = $result.CanExecute
        }

        $result.Success = $true

        return $result
    }
    catch {
        $result.Success = $false
        $result.Error =
            "Erro controlado ao gerar preview de desbloqueio: $($_.Exception.Message)"

        return $result
    }
}


function New-UserUnlockAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [string]$Result,

        [Parameter(Mandatory)]
        [bool]$SimulationMode,

        [Parameter(Mandatory)]
        [bool]$Changed
    )

    return New-AuditRecord `
        -Action "UnlockUserAccount" `
        -SamAccountName $SamAccountName `
        -Result $Result `
        -SimulationMode $SimulationMode `
        -Changed $Changed
}


function Invoke-UserUnlockAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]$Configuration,

        [Parameter()]
        [switch]$Execute
    )

    $result = [PSCustomObject]@{
        Success         = $false
        Action          = "UnlockUserAccount"
        SamAccountName  = $SamAccountName
        SimulationMode  = $false
        Executed        = $false
        Changed         = $false
        Status          = "NotExecuted"
        Error           = $null
        Audit           = $null
    }

    try {
        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
            $result.Error =
                "O SamAccountName é obrigatório para realizar o desbloqueio."

            return $result
        }

        if ($Configuration.PSObject.Properties.Name -contains "SimulationMode") {
            $result.SimulationMode = [bool]$Configuration.SimulationMode
        }

        $preview = Get-UserUnlockPreview `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration

        if (-not $preview.Success) {
            $result.Error = $preview.Error
            return $result
        }

        if (-not $preview.UserFound) {
            $result.Error =
                "Usuário '$SamAccountName' não foi encontrado."

            return $result
        }

        if (-not $preview.CanExecute) {
            $result.Success = $true
            $result.Status = "NoChange"

            $auditResult = New-UserUnlockAudit `
                -SamAccountName $SamAccountName `
                -Result "NoChange" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if ($auditResult.Success) {
                $result.Audit = $auditResult.Data
            }

            return $result
        }

        if (-not $Execute) {
            $result.Success = $true
            $result.Status = "PreviewOnly"

            $auditResult = New-UserUnlockAudit `
                -SamAccountName $SamAccountName `
                -Result "PreviewOnly" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if ($auditResult.Success) {
                $result.Audit = $auditResult.Data
            }

            return $result
        }

        if ($result.SimulationMode) {
            $result.Success = $true
            $result.Executed = $true
            $result.Changed = $false
            $result.Status = "Simulated"

            $auditResult = New-UserUnlockAudit `
                -SamAccountName $SamAccountName `
                -Result "Simulated" `
                -SimulationMode $true `
                -Changed $false

            if ($auditResult.Success) {
                $result.Audit = $auditResult.Data
            }
            else {
                $result.Success = $false
                $result.Error = $auditResult.Error
            }

            return $result
        }

        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            $result.Error =
                "O módulo 'ActiveDirectory' não está instalado neste computador."

            return $result
        }

        if ([string]::IsNullOrWhiteSpace($Configuration.DomainController)) {
            $result.Error =
                "O DomainController deve ser configurado para executar a ação."

            return $result
        }

        Import-Module ActiveDirectory -ErrorAction Stop

        Unlock-ADAccount `
            -Identity $SamAccountName `
            -Server $Configuration.DomainController `
            -ErrorAction Stop

        $result.Success = $true
        $result.Executed = $true
        $result.Changed = $true
        $result.Status = "Executed"

        $auditResult = New-UserUnlockAudit `
            -SamAccountName $SamAccountName `
            -Result "Executed" `
            -SimulationMode $false `
            -Changed $true

        if ($auditResult.Success) {
            $result.Audit = $auditResult.Data
        }
        else {
            $result.Success = $false
            $result.Error = $auditResult.Error
        }

        return $result
    }
    catch {
        $result.Success = $false
        $result.Error =
            "Não foi possível desbloquear o usuário '$SamAccountName'. Detalhes: $($_.Exception.Message)"
        return $result
    }
}


Export-ModuleMember -Function @(
    "Get-UserUnlockPreview",
    "Invoke-UserUnlockAccount"
)