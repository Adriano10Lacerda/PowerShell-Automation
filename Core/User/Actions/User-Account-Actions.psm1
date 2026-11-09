#Requires -Version 5.1

<#
.SYNOPSIS
    Ações administrativas de contas de usuário - PowerShell Automation V2.

.DESCRIPTION
    Implementa ações controladas sobre contas de usuário:
    - Unlock
    - Enable
    - Disable
    - Force Password Change

    Princípios:
    - Preview antes da execução.
    - Confirmação na camada de interface.
    - Simulation Mode.
    - Auditoria.
    - Nenhuma senha ou credencial em auditoria.
    - Execução real somente quando SimulationMode = $false.
#>

Set-StrictMode -Version Latest

$userCorePath = Join-Path `
    $PSScriptRoot `
    "..\User-Functions.psm1"

$auditPath = Join-Path `
    $PSScriptRoot `
    "..\..\Audit\Audit-Functions.psm1"

if (-not (Test-Path -LiteralPath $userCorePath)) {
    throw "User-Functions.psm1 não encontrado: $userCorePath"
}

if (-not (Test-Path -LiteralPath $auditPath)) {
    throw "Audit-Functions.psm1 não encontrado: $auditPath"
}

Import-Module `
    $userCorePath `
    -Force `
    -ErrorAction Stop

Import-Module `
    $auditPath `
    -Force `
    -ErrorAction Stop

function Invoke-UserActionShouldProcess {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.PSCmdlet]$Cmdlet,
        [Parameter(Mandatory)] [string]$Target,
        [Parameter(Mandatory)] [string]$Action
    )
    return $Cmdlet.ShouldProcess($Target, $Action)
}


# ============================================================
# AUDITORIA
# ============================================================

function New-UserAccountActionAudit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [string]$Result,

        [Parameter()]
        [bool]$SimulationMode = $false,

        [Parameter()]
        [bool]$Changed = $false
    )

    return New-AuditRecord `
        -Action $Action `
        -SamAccountName $SamAccountName `
        -Result $Result `
        -SimulationMode $SimulationMode `
        -Changed $Changed
}


# ============================================================
# UNLOCK - PREVIEW
# ============================================================

function Get-UserUnlockPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead
    )

    try {
        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
            throw "SamAccountName não pode ser vazio."
        }

        if ($null -eq $Configuration) {
            throw "Configuration não pode ser nula."
        }

        $userResult = Get-UserADInfo `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration `
            -AllowRealRead:$AllowRealRead

        if ($userResult.QueryStatus -eq "NotFound") {
            return [PSCustomObject]@{
                Success         = $false
                Action          = "UnlockUserAccount"
                SamAccountName  = $SamAccountName
                SimulationMode  = [bool]$Configuration.SimulationMode
                UserFound       = $false
                LockedOut       = $false
                CanExecute      = $false
                RequiresConfirm = $false
                Preview         = $null
                Status          = "NotFound"
                QueryStatus     = "NotFound"
                Error           = $null
            }
        }

        if (-not $userResult.Success) {
            return [PSCustomObject]@{
                Success         = $false
                Action          = "UnlockUserAccount"
                SamAccountName  = $SamAccountName
                SimulationMode  = $Configuration.SimulationMode
                UserFound       = $false
                LockedOut       = $false
                CanExecute      = $false
                RequiresConfirm = $false
                Preview         = $null
                Error           = $userResult.Error
            }
        }

        $lockedOut = [bool]$userResult.Data.Account.LockedOut

        if ($Configuration.SimulationMode) {
            if (
                $Configuration.Simulation.LockedSamAccountNames -contains
                $SamAccountName
            ) {
                $lockedOut = $true
            }
        }

        if ($lockedOut) {
            $currentState = "LockedOut"
            $targetState = "Unlocked"
            $canExecute = $true
            $description = "Desbloquear a conta do usuário."
        }
        else {
            $currentState = "NotLocked"
            $targetState = "NoChange"
            $canExecute = $false
            $description = "A conta do usuário não está bloqueada."
        }

        return [PSCustomObject]@{
            Success         = $true
            Action          = "UnlockUserAccount"
            SamAccountName  = $SamAccountName
            SimulationMode  = [bool]$Configuration.SimulationMode
            UserFound       = $true
            LockedOut       = $lockedOut
            CanExecute      = $canExecute
            RequiresConfirm = $true

            Preview = [PSCustomObject]@{
                Action          = "UnlockUserAccount"
                Description     = $description
                CurrentState    = $currentState
                TargetState     = $targetState
                SimulationMode  = [bool]$Configuration.SimulationMode
                RequiresConfirm = $true
                CanExecute      = $canExecute
            }

            Error = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success         = $false
            Action          = "UnlockUserAccount"
            SamAccountName  = $SamAccountName
            SimulationMode  = $false
            UserFound       = $false
            LockedOut       = $false
            CanExecute      = $false
            RequiresConfirm = $false
            Preview         = $null
            Error           = "Erro ao criar preview de desbloqueio. Detalhes: $($_.Exception.Message)"
        }
    }
}


# ============================================================
# UNLOCK - EXECUÇÃO
# ============================================================

function Invoke-UserUnlockAccount {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [Parameter()]
        [switch]$Execute,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$AllowRealWrite
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
            throw "SamAccountName não pode ser vazio."
        }

        if ($null -eq $Configuration) {
            throw "Configuration não pode ser nula."
        }

        if ($null -eq $Configuration.PSObject.Properties['SimulationMode'] -or $Configuration.SimulationMode -isnot [bool]) { throw 'SimulationMode deve ser definido explicitamente como Boolean.' }
        $result.SimulationMode = [bool]$Configuration.SimulationMode

        if ($result.SimulationMode -and ($AllowRealRead -or $AllowRealWrite)) { $result.Error = "Modos conflitantes: SimulationMode não pode ser combinado com autorização real."; return $result }
        if ($WhatIfPreference) { $result.Success = $true; $result.Status = "Preview"; $result | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"; $result | Add-Member -NotePropertyName Cancelled -NotePropertyValue $false; return $result }
        if (-not $result.SimulationMode -and -not $AllowRealRead) { $result.Error = "Leitura real bloqueada. Informe -AllowRealRead explicitamente."; return $result }
        if (-not $result.SimulationMode -and $Execute -and -not $AllowRealWrite) { $result.Error = "Escrita real bloqueada. Informe -AllowRealWrite explicitamente."; return $result }
        if (-not $result.SimulationMode -and $Execute -and -not (Invoke-UserActionShouldProcess -Cmdlet $PSCmdlet -Target $SamAccountName -Action "Desbloquear conta de usuário")) { $result.Status = "Cancelled"; $result.Error = "Operação cancelada pelo ShouldProcess."; $result | Add-Member -NotePropertyName Cancelled -NotePropertyValue $true; $result | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"; return $result }

        $preview = Get-UserUnlockPreview `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration `
            -AllowRealRead:$AllowRealRead

        if (-not $preview.Success) {
            if ($preview.QueryStatus -eq "NotFound") {
                $result.Status = "NotFound"
                $result | Add-Member -NotePropertyName QueryStatus -NotePropertyValue "NotFound"
                return $result
            }
            $result.Error = $preview.Error
            return $result
        }

        if (-not $preview.UserFound) {
            $result.Error = "Usuário não encontrado."
            return $result
        }

        if (-not $preview.CanExecute) {
            $result.Success = $true
            $result.Status = "NoChange"

            $auditResult = New-UserAccountActionAudit `
                -Action "UnlockUserAccount" `
                -SamAccountName $SamAccountName `
                -Result "NoChange" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        if (-not $Execute) {
            $result.Success = $true
            $result.Status = "PreviewOnly"

            $auditResult = New-UserAccountActionAudit `
                -Action "UnlockUserAccount" `
                -SamAccountName $SamAccountName `
                -Result "PreviewOnly" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        if ($Configuration.SimulationMode) {
            $result.Success = $true
            $result.Executed = $true
            $result.Changed = $false
            $result.Status = "Simulated"

            $auditResult = New-UserAccountActionAudit `
                -Action "UnlockUserAccount" `
                -SamAccountName $SamAccountName `
                -Result "Simulated" `
                -SimulationMode $true `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        $adModule = Get-Module -ListAvailable -Name ActiveDirectory

        if ($null -eq $adModule) {
            throw "O módulo ActiveDirectory não está instalado ou disponível neste computador."
        }

        Import-Module `
            ActiveDirectory `
            -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($Configuration.DomainController)) {
            throw "DomainController deve ser informado para execução real."
        }

        Unlock-ADAccount `
            -Identity $SamAccountName `
            -Server $Configuration.DomainController `
            -ErrorAction Stop

        $result.Success = $true
        $result.Executed = $true
        $result.Changed = $true
        $result.Status = "Executed"

        $auditResult = New-UserAccountActionAudit `
            -Action "UnlockUserAccount" `
            -SamAccountName $SamAccountName `
            -Result "Executed" `
            -SimulationMode $false `
            -Changed $true

        if (-not $auditResult.Success) {
            $result.Success = $false
            $result.Error = $auditResult.Error
            return $result
        }

        $result.Audit = $auditResult.Data

        return $result
    }
    catch {
        $result.Success = $false
        $result.Error = "Erro ao executar desbloqueio. Detalhes: $($_.Exception.Message)"

        return $result
    }
}


# ============================================================
# ENABLE - PREVIEW
# ============================================================

function Get-UserEnablePreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead
    )

    try {
        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
            throw "SamAccountName não pode ser vazio."
        }

        if ($null -eq $Configuration) {
            throw "Configuration não pode ser nula."
        }

        $userResult = Get-UserADInfo `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration `
            -AllowRealRead:$AllowRealRead

        if ($userResult.QueryStatus -eq "NotFound") {
            return [PSCustomObject]@{
                Success         = $false
                Action          = "EnableUserAccount"
                SamAccountName  = $SamAccountName
                SimulationMode  = [bool]$Configuration.SimulationMode
                UserFound       = $false
                Enabled         = $false
                CanExecute      = $false
                RequiresConfirm = $false
                Preview         = $null
                Status          = "NotFound"
                QueryStatus     = "NotFound"
                Error           = $null
            }
        }

        if (-not $userResult.Success) {
            return [PSCustomObject]@{
                Success         = $false
                Action          = "EnableUserAccount"
                SamAccountName  = $SamAccountName
                SimulationMode  = $Configuration.SimulationMode
                UserFound       = $false
                Enabled         = $false
                CanExecute      = $false
                RequiresConfirm = $false
                Preview         = $null
                Error           = $userResult.Error
            }
        }

        $enabled = [bool]$userResult.Data.Account.Enabled

        if ($Configuration.SimulationMode) {
            if (
                $Configuration.Simulation.DisabledSamAccountNames -contains
                $SamAccountName
            ) {
                $enabled = $false
            }
        }

        if ($enabled) {
            $currentState = "Enabled"
            $targetState = "NoChange"
            $canExecute = $false
            $description = "A conta do usuário já está ativa."
        }
        else {
            $currentState = "Disabled"
            $targetState = "Enabled"
            $canExecute = $true
            $description = "Ativar a conta do usuário."
        }

        return [PSCustomObject]@{
            Success         = $true
            Action          = "EnableUserAccount"
            SamAccountName  = $SamAccountName
            SimulationMode  = [bool]$Configuration.SimulationMode
            UserFound       = $true
            Enabled         = $enabled
            CanExecute      = $canExecute
            RequiresConfirm = $true

            Preview = [PSCustomObject]@{
                Action          = "EnableUserAccount"
                Description     = $description
                CurrentState    = $currentState
                TargetState     = $targetState
                SimulationMode  = [bool]$Configuration.SimulationMode
                RequiresConfirm = $true
                CanExecute      = $canExecute
            }

            Error = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success         = $false
            Action          = "EnableUserAccount"
            SamAccountName  = $SamAccountName
            SimulationMode  = $false
            UserFound       = $false
            Enabled         = $false
            CanExecute      = $false
            RequiresConfirm = $false
            Preview         = $null
            Error           = "Erro ao criar preview de ativação. Detalhes: $($_.Exception.Message)"
        }
    }
}


# ============================================================
# ENABLE - EXECUÇÃO
# ============================================================

function Invoke-UserEnableAccount {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [Parameter()]
        [switch]$Execute,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$AllowRealWrite
    )

    $result = [PSCustomObject]@{
        Success         = $false
        Action          = "EnableUserAccount"
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
            throw "SamAccountName não pode ser vazio."
        }

        if ($null -eq $Configuration) {
            throw "Configuration não pode ser nula."
        }

        if ($null -eq $Configuration.PSObject.Properties['SimulationMode'] -or $Configuration.SimulationMode -isnot [bool]) { throw 'SimulationMode deve ser definido explicitamente como Boolean.' }
        $result.SimulationMode = [bool]$Configuration.SimulationMode

        if ($result.SimulationMode -and ($AllowRealRead -or $AllowRealWrite)) { $result.Error = "Modos conflitantes: SimulationMode não pode ser combinado com autorização real."; return $result }
        if ($WhatIfPreference) { $result.Success = $true; $result.Status = "Preview"; $result | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"; $result | Add-Member -NotePropertyName Cancelled -NotePropertyValue $false; return $result }
        if (-not $result.SimulationMode -and -not $AllowRealRead) { $result.Error = "Leitura real bloqueada. Informe -AllowRealRead explicitamente."; return $result }
        if (-not $result.SimulationMode -and $Execute -and -not $AllowRealWrite) { $result.Error = "Escrita real bloqueada. Informe -AllowRealWrite explicitamente."; return $result }
        if (-not $result.SimulationMode -and $Execute -and -not (Invoke-UserActionShouldProcess -Cmdlet $PSCmdlet -Target $SamAccountName -Action "Habilitar conta de usuário")) { $result.Status = "Cancelled"; $result.Error = "Operação cancelada pelo ShouldProcess."; $result | Add-Member -NotePropertyName Cancelled -NotePropertyValue $true; $result | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"; return $result }

        $preview = Get-UserEnablePreview `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration `
            -AllowRealRead:$AllowRealRead

        if (-not $preview.Success) {
            if ($preview.QueryStatus -eq "NotFound") {
                $result.Status = "NotFound"
                $result | Add-Member -NotePropertyName QueryStatus -NotePropertyValue "NotFound"
                return $result
            }
            $result.Error = $preview.Error
            return $result
        }

        if (-not $preview.UserFound) {
            $result.Error = "Usuário não encontrado."
            return $result
        }

        if (-not $preview.CanExecute) {
            $result.Success = $true
            $result.Status = "NoChange"

            $auditResult = New-UserAccountActionAudit `
                -Action "EnableUserAccount" `
                -SamAccountName $SamAccountName `
                -Result "NoChange" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        if (-not $Execute) {
            $result.Success = $true
            $result.Status = "PreviewOnly"

            $auditResult = New-UserAccountActionAudit `
                -Action "EnableUserAccount" `
                -SamAccountName $SamAccountName `
                -Result "PreviewOnly" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        if ($Configuration.SimulationMode) {
            $result.Success = $true
            $result.Executed = $true
            $result.Changed = $false
            $result.Status = "Simulated"

            $auditResult = New-UserAccountActionAudit `
                -Action "EnableUserAccount" `
                -SamAccountName $SamAccountName `
                -Result "Simulated" `
                -SimulationMode $true `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        $adModule = Get-Module -ListAvailable -Name ActiveDirectory

        if ($null -eq $adModule) {
            throw "O módulo ActiveDirectory não está instalado ou disponível neste computador."
        }

        Import-Module `
            ActiveDirectory `
            -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($Configuration.DomainController)) {
            throw "DomainController deve ser informado para execução real."
        }

        Enable-ADAccount `
            -Identity $SamAccountName `
            -Server $Configuration.DomainController `
            -ErrorAction Stop

        $result.Success = $true
        $result.Executed = $true
        $result.Changed = $true
        $result.Status = "Executed"

        $auditResult = New-UserAccountActionAudit `
            -Action "EnableUserAccount" `
            -SamAccountName $SamAccountName `
            -Result "Executed" `
            -SimulationMode $false `
            -Changed $true

        if (-not $auditResult.Success) {
            $result.Success = $false
            $result.Error = $auditResult.Error
            return $result
        }

        $result.Audit = $auditResult.Data

        return $result
    }
    catch {
        $result.Success = $false
        $result.Error = "Erro ao executar ativação. Detalhes: $($_.Exception.Message)"

        return $result
    }
}


# ============================================================
# DISABLE - PREVIEW
# ============================================================

function Get-UserDisablePreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead
    )

    try {
        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
            throw "SamAccountName não pode ser vazio."
        }

        if ($null -eq $Configuration) {
            throw "Configuration não pode ser nula."
        }

        $userResult = Get-UserADInfo `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration `
            -AllowRealRead:$AllowRealRead

        if ($userResult.QueryStatus -eq "NotFound") {
            return [PSCustomObject]@{
                Success         = $false
                Action          = "DisableUserAccount"
                SamAccountName  = $SamAccountName
                SimulationMode  = [bool]$Configuration.SimulationMode
                UserFound       = $false
                Enabled         = $false
                CanExecute      = $false
                RequiresConfirm = $false
                Preview         = $null
                Status          = "NotFound"
                QueryStatus     = "NotFound"
                Error           = $null
            }
        }

        if (-not $userResult.Success) {
            return [PSCustomObject]@{
                Success         = $false
                Action          = "DisableUserAccount"
                SamAccountName  = $SamAccountName
                SimulationMode  = $Configuration.SimulationMode
                UserFound       = $false
                Enabled         = $false
                CanExecute      = $false
                RequiresConfirm = $false
                Preview         = $null
                Error           = $userResult.Error
            }
        }

        $enabled = [bool]$userResult.Data.Account.Enabled

        if ($Configuration.SimulationMode) {
            if (
                $Configuration.Simulation.DisabledSamAccountNames -contains
                $SamAccountName
            ) {
                $enabled = $false
            }
        }

        if ($enabled) {
            $currentState = "Enabled"
            $targetState = "Disabled"
            $canExecute = $true
            $description = "Desativar a conta do usuário."
        }
        else {
            $currentState = "Disabled"
            $targetState = "NoChange"
            $canExecute = $false
            $description = "A conta do usuário já está desativada."
        }

        return [PSCustomObject]@{
            Success         = $true
            Action          = "DisableUserAccount"
            SamAccountName  = $SamAccountName
            SimulationMode  = [bool]$Configuration.SimulationMode
            UserFound       = $true
            Enabled         = $enabled
            CanExecute      = $canExecute
            RequiresConfirm = $true

            Preview = [PSCustomObject]@{
                Action          = "DisableUserAccount"
                Description     = $description
                CurrentState    = $currentState
                TargetState     = $targetState
                SimulationMode  = [bool]$Configuration.SimulationMode
                RequiresConfirm = $true
                CanExecute      = $canExecute
            }

            Error = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success         = $false
            Action          = "DisableUserAccount"
            SamAccountName  = $SamAccountName
            SimulationMode  = $false
            UserFound       = $false
            Enabled         = $false
            CanExecute      = $false
            RequiresConfirm = $false
            Preview         = $null
            Error           = "Erro ao criar preview de desativação. Detalhes: $($_.Exception.Message)"
        }
    }
}


# ============================================================
# DISABLE - EXECUÇÃO
# ============================================================

function Invoke-UserDisableAccount {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [Parameter()]
        [switch]$Execute,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$AllowRealWrite
    )

    $result = [PSCustomObject]@{
        Success         = $false
        Action          = "DisableUserAccount"
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
            throw "SamAccountName não pode ser vazio."
        }

        if ($null -eq $Configuration) {
            throw "Configuration não pode ser nula."
        }

        if ($null -eq $Configuration.PSObject.Properties['SimulationMode'] -or $Configuration.SimulationMode -isnot [bool]) { throw 'SimulationMode deve ser definido explicitamente como Boolean.' }
        $result.SimulationMode = [bool]$Configuration.SimulationMode

        if ($result.SimulationMode -and ($AllowRealRead -or $AllowRealWrite)) { $result.Error = "Modos conflitantes: SimulationMode não pode ser combinado com autorização real."; return $result }
        if ($WhatIfPreference) { $result.Success = $true; $result.Status = "Preview"; $result | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"; $result | Add-Member -NotePropertyName Cancelled -NotePropertyValue $false; return $result }
        if (-not $result.SimulationMode -and -not $AllowRealRead) { $result.Error = "Leitura real bloqueada. Informe -AllowRealRead explicitamente."; return $result }
        if (-not $result.SimulationMode -and $Execute -and -not $AllowRealWrite) { $result.Error = "Escrita real bloqueada. Informe -AllowRealWrite explicitamente."; return $result }
        if (-not $result.SimulationMode -and $Execute -and -not (Invoke-UserActionShouldProcess -Cmdlet $PSCmdlet -Target $SamAccountName -Action "Desabilitar conta de usuário")) { $result.Status = "Cancelled"; $result.Error = "Operação cancelada pelo ShouldProcess."; $result | Add-Member -NotePropertyName Cancelled -NotePropertyValue $true; $result | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"; return $result }

        $preview = Get-UserDisablePreview `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration `
            -AllowRealRead:$AllowRealRead

        if (-not $preview.Success) {
            if ($preview.QueryStatus -eq "NotFound") {
                $result.Status = "NotFound"
                $result | Add-Member -NotePropertyName QueryStatus -NotePropertyValue "NotFound"
                return $result
            }
            $result.Error = $preview.Error
            return $result
        }

        if (-not $preview.UserFound) {
            $result.Error = "Usuário não encontrado."
            return $result
        }

        if (-not $preview.CanExecute) {
            $result.Success = $true
            $result.Status = "NoChange"

            $auditResult = New-UserAccountActionAudit `
                -Action "DisableUserAccount" `
                -SamAccountName $SamAccountName `
                -Result "NoChange" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        if (-not $Execute) {
            $result.Success = $true
            $result.Status = "PreviewOnly"

            $auditResult = New-UserAccountActionAudit `
                -Action "DisableUserAccount" `
                -SamAccountName $SamAccountName `
                -Result "PreviewOnly" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        if ($Configuration.SimulationMode) {
            $result.Success = $true
            $result.Executed = $true
            $result.Changed = $false
            $result.Status = "Simulated"

            $auditResult = New-UserAccountActionAudit `
                -Action "DisableUserAccount" `
                -SamAccountName $SamAccountName `
                -Result "Simulated" `
                -SimulationMode $true `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        $adModule = Get-Module -ListAvailable -Name ActiveDirectory

        if ($null -eq $adModule) {
            throw "O módulo ActiveDirectory não está instalado ou disponível neste computador."
        }

        Import-Module `
            ActiveDirectory `
            -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($Configuration.DomainController)) {
            throw "DomainController deve ser informado para execução real."
        }

        Disable-ADAccount `
            -Identity $SamAccountName `
            -Server $Configuration.DomainController `
            -ErrorAction Stop

        $result.Success = $true
        $result.Executed = $true
        $result.Changed = $true
        $result.Status = "Executed"

        $auditResult = New-UserAccountActionAudit `
            -Action "DisableUserAccount" `
            -SamAccountName $SamAccountName `
            -Result "Executed" `
            -SimulationMode $false `
            -Changed $true

        if (-not $auditResult.Success) {
            $result.Success = $false
            $result.Error = $auditResult.Error
            return $result
        }

        $result.Audit = $auditResult.Data

        return $result
    }
    catch {
        $result.Success = $false
        $result.Error = "Erro ao executar desativação. Detalhes: $($_.Exception.Message)"

        return $result
    }
}


# ============================================================
# FORCE PASSWORD CHANGE - PREVIEW
# ============================================================

function Get-UserForcePasswordChangePreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead
    )

    try {
        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
            throw "SamAccountName não pode ser vazio."
        }

        if ($null -eq $Configuration) {
            throw "Configuration não pode ser nula."
        }

        $userResult = Get-UserADInfo `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration `
            -AllowRealRead:$AllowRealRead

        if ($userResult.QueryStatus -eq "NotFound") {
            return [PSCustomObject]@{
                Success               = $false
                Action                = "ForcePasswordChange"
                SamAccountName        = $SamAccountName
                SimulationMode        = [bool]$Configuration.SimulationMode
                UserFound             = $false
                PasswordChangeAtLogon = $false
                CanExecute            = $false
                RequiresConfirm       = $false
                Preview               = $null
                Status                = "NotFound"
                QueryStatus           = "NotFound"
                Error                 = $null
            }
        }

        if (-not $userResult.Success) {
            return [PSCustomObject]@{
                Success              = $false
                Action               = "ForcePasswordChange"
                SamAccountName       = $SamAccountName
                SimulationMode       = $Configuration.SimulationMode
                UserFound            = $false
                PasswordChangeAtLogon = $false
                CanExecute           = $false
                RequiresConfirm      = $false
                Preview              = $null
                Error                = $userResult.Error
            }
        }

        $passwordChangeAtLogon = $false

        if (
            $userResult.Data.Account.PSObject.Properties.Name -contains
            "PasswordChangeAtLogon"
        ) {
            $passwordChangeAtLogon = [bool]$userResult.Data.Account.PasswordChangeAtLogon
        }

        if ($Configuration.SimulationMode) {
            if (
                $Configuration.Simulation.PSObject.Properties.Name -contains
                "PasswordChangeAtLogonSamAccountNames"
            ) {
                if (
                    $Configuration.Simulation.PasswordChangeAtLogonSamAccountNames -contains
                    $SamAccountName
                ) {
                    $passwordChangeAtLogon = $true
                }
            }
        }

        if ($passwordChangeAtLogon) {
            $currentState = "Required"
            $targetState = "NoChange"
            $canExecute = $false
            $description = "A troca de senha no próximo logon já está configurada."
        }
        else {
            $currentState = "NotRequired"
            $targetState = "Required"
            $canExecute = $true
            $description = "Forçar troca de senha no próximo logon."
        }

        return [PSCustomObject]@{
            Success               = $true
            Action                = "ForcePasswordChange"
            SamAccountName        = $SamAccountName
            SimulationMode        = [bool]$Configuration.SimulationMode
            UserFound             = $true
            PasswordChangeAtLogon = $passwordChangeAtLogon
            CanExecute            = $canExecute
            RequiresConfirm      = $true

            Preview = [PSCustomObject]@{
                Action                = "ForcePasswordChange"
                Description           = $description
                CurrentState          = $currentState
                TargetState           = $targetState
                SimulationMode        = [bool]$Configuration.SimulationMode
                RequiresConfirm       = $true
                CanExecute            = $canExecute
                PasswordChangeAtLogon = $passwordChangeAtLogon
            }

            Error = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success               = $false
            Action                = "ForcePasswordChange"
            SamAccountName        = $SamAccountName
            SimulationMode       = $false
            UserFound             = $false
            PasswordChangeAtLogon = $false
            CanExecute            = $false
            RequiresConfirm      = $false
            Preview               = $null
            Error                 = "Erro ao criar preview de troca de senha. Detalhes: $($_.Exception.Message)"
        }
    }
}


# ============================================================
# FORCE PASSWORD CHANGE - EXECUÇÃO
# ============================================================

function Invoke-UserForcePasswordChange {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration,

        [Parameter()]
        [switch]$Execute,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$AllowRealWrite
    )

    $result = [PSCustomObject]@{
        Success               = $false
        Action                = "ForcePasswordChange"
        SamAccountName        = $SamAccountName
        SimulationMode        = $false
        Executed              = $false
        Changed               = $false
        Status                = "NotExecuted"
        Error                 = $null
        Audit                 = $null
    }

    try {
        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
            throw "SamAccountName não pode ser vazio."
        }

        if ($null -eq $Configuration) {
            throw "Configuration não pode ser nula."
        }

        if ($null -eq $Configuration.PSObject.Properties['SimulationMode'] -or $Configuration.SimulationMode -isnot [bool]) { throw 'SimulationMode deve ser definido explicitamente como Boolean.' }
        $result.SimulationMode = [bool]$Configuration.SimulationMode

        if ($result.SimulationMode -and ($AllowRealRead -or $AllowRealWrite)) { $result.Error = "Modos conflitantes: SimulationMode não pode ser combinado com autorização real."; return $result }
        if ($WhatIfPreference) { $result.Success = $true; $result.Status = "Preview"; $result | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"; $result | Add-Member -NotePropertyName Cancelled -NotePropertyValue $false; return $result }
        if (-not $result.SimulationMode -and -not $AllowRealRead) { $result.Error = "Leitura real bloqueada. Informe -AllowRealRead explicitamente."; return $result }
        if (-not $result.SimulationMode -and $Execute -and -not $AllowRealWrite) { $result.Error = "Escrita real bloqueada. Informe -AllowRealWrite explicitamente."; return $result }
        if (-not $result.SimulationMode -and $Execute -and -not (Invoke-UserActionShouldProcess -Cmdlet $PSCmdlet -Target $SamAccountName -Action "Forçar troca de senha")) { $result.Status = "Cancelled"; $result.Error = "Operação cancelada pelo ShouldProcess."; $result | Add-Member -NotePropertyName Cancelled -NotePropertyValue $true; $result | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"; return $result }

        $preview = Get-UserForcePasswordChangePreview `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration `
            -AllowRealRead:$AllowRealRead

        if (-not $preview.Success) {
            if ($preview.QueryStatus -eq "NotFound") {
                $result.Status = "NotFound"
                $result | Add-Member -NotePropertyName QueryStatus -NotePropertyValue "NotFound"
                return $result
            }
            $result.Error = $preview.Error
            return $result
        }

        if (-not $preview.UserFound) {
            $result.Error = "Usuário não encontrado."
            return $result
        }

        if (-not $preview.CanExecute) {
            $result.Success = $true
            $result.Status = "NoChange"

            $auditResult = New-UserAccountActionAudit `
                -Action "ForcePasswordChange" `
                -SamAccountName $SamAccountName `
                -Result "NoChange" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        if (-not $Execute) {
            $result.Success = $true
            $result.Status = "PreviewOnly"

            $auditResult = New-UserAccountActionAudit `
                -Action "ForcePasswordChange" `
                -SamAccountName $SamAccountName `
                -Result "PreviewOnly" `
                -SimulationMode $result.SimulationMode `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        if ($Configuration.SimulationMode) {
            $result.Success = $true
            $result.Executed = $true
            $result.Changed = $false
            $result.Status = "Simulated"

            $auditResult = New-UserAccountActionAudit `
                -Action "ForcePasswordChange" `
                -SamAccountName $SamAccountName `
                -Result "Simulated" `
                -SimulationMode $true `
                -Changed $false

            if (-not $auditResult.Success) {
                $result.Success = $false
                $result.Error = $auditResult.Error
                return $result
            }

            $result.Audit = $auditResult.Data

            return $result
        }

        $adModule = Get-Module -ListAvailable -Name ActiveDirectory

        if ($null -eq $adModule) {
            throw "O módulo ActiveDirectory não está instalado ou disponível neste computador."
        }

        Import-Module `
            ActiveDirectory `
            -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($Configuration.DomainController)) {
            throw "DomainController deve ser informado para execução real."
        }

        Set-ADUser `
            -Identity $SamAccountName `
            -Server $Configuration.DomainController `
            -ChangePasswordAtLogon $true `
            -ErrorAction Stop

        $result.Success = $true
        $result.Executed = $true
        $result.Changed = $true
        $result.Status = "Executed"

        $auditResult = New-UserAccountActionAudit `
            -Action "ForcePasswordChange" `
            -SamAccountName $SamAccountName `
            -Result "Executed" `
            -SimulationMode $false `
            -Changed $true

        if (-not $auditResult.Success) {
            $result.Success = $false
            $result.Error = $auditResult.Error
            return $result
        }

        $result.Audit = $auditResult.Data

        return $result
    }
    catch {
        $result.Success = $false
        $result.Error = "Erro ao forçar troca de senha. Detalhes: $($_.Exception.Message)"

        return $result
    }
}


# ============================================================
# EXPORT
# ============================================================

Export-ModuleMember -Function @(
    "Get-UserUnlockPreview",
    "Invoke-UserUnlockAccount",
    "Get-UserEnablePreview",
    "Invoke-UserEnableAccount",
    "Get-UserDisablePreview",
    "Invoke-UserDisableAccount",
    "Get-UserForcePasswordChangePreview",
    "Invoke-UserForcePasswordChange"
)
