#requires -Version 5.1

<#
.SYNOPSIS
    User Management V2.

.DESCRIPTION
    Camada de gerenciamento de usuários acima do User Core.

    Nesta etapa:
    - Consulta usuário.
    - Gera resumo operacional.
    - Preserva o modelo completo retornado pelo Core.
    - Trata erros de forma controlada.

    Nenhuma ação administrativa é executada nesta etapa.
#>

Set-StrictMode -Version Latest

# ============================================================
# IMPORTAÇÃO DO USER CORE
# ============================================================

$userCorePath = Join-Path $PSScriptRoot "..\User-Functions.psm1"

if (-not (Test-Path -LiteralPath $userCorePath)) {
    throw "User Core não encontrado: $userCorePath"
}

Import-Module $userCorePath -Force


# ============================================================
# NEW-USER-MANAGEMENT-SUMMARY
# ============================================================

function New-UserManagementSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $User,

        [Parameter()]
        [bool]$SimulationMode = $false
    )

    try {

        # ----------------------------------------------------
        # Valores padrão
        # ----------------------------------------------------

        $samAccountName = $null
        $userPrincipalName = $null
        $displayName = $null
        $mail = $null
        $department = $null
        $title = $null
        $enabled = $false
        $lockedOut = $false
        $passwordExpired = $false
        $lastLogonDate = $null

        # ----------------------------------------------------
        # Identity
        # ----------------------------------------------------

        if ($null -ne $User.Identity) {

            if ($User.Identity.PSObject.Properties.Name -contains "SamAccountName") {
                $samAccountName = $User.Identity.SamAccountName
            }

            if ($User.Identity.PSObject.Properties.Name -contains "UserPrincipalName") {
                $userPrincipalName = $User.Identity.UserPrincipalName
            }
        }

        # ----------------------------------------------------
        # Personal
        # ----------------------------------------------------

        if ($null -ne $User.Personal) {

            if ($User.Personal.PSObject.Properties.Name -contains "DisplayName") {
                $displayName = $User.Personal.DisplayName
            }

            if ($User.Personal.PSObject.Properties.Name -contains "Mail") {
                $mail = $User.Personal.Mail
            }
        }

        # ----------------------------------------------------
        # Organization
        # ----------------------------------------------------

        if ($null -ne $User.Organization) {

            if ($User.Organization.PSObject.Properties.Name -contains "Department") {
                $department = $User.Organization.Department
            }

            if ($User.Organization.PSObject.Properties.Name -contains "Title") {
                $title = $User.Organization.Title
            }
        }

        # ----------------------------------------------------
        # Account
        # ----------------------------------------------------

        if ($null -ne $User.Account) {

            if ($User.Account.PSObject.Properties.Name -contains "Enabled") {
                $enabled = [bool]$User.Account.Enabled
            }

            if ($User.Account.PSObject.Properties.Name -contains "LockedOut") {
                $lockedOut = [bool]$User.Account.LockedOut
            }

            if ($User.Account.PSObject.Properties.Name -contains "PasswordExpired") {
                $passwordExpired = [bool]$User.Account.PasswordExpired
            }
        }

        # ----------------------------------------------------
        # Activity
        # ----------------------------------------------------

        if ($null -ne $User.Activity) {

            if ($User.Activity.PSObject.Properties.Name -contains "LastLogonDate") {
                $lastLogonDate = $User.Activity.LastLogonDate
            }
        }

        # ----------------------------------------------------
        # Status
        # ----------------------------------------------------

        $status = "Unknown"

        if (-not $enabled) {
            $status = "Disabled"
        }
        elseif ($lockedOut) {
            $status = "LockedOut"
        }
        elseif ($passwordExpired) {
            $status = "PasswordExpired"
        }
        else {
            $status = "Active"
        }

        # ----------------------------------------------------
        # Summary
        # ----------------------------------------------------

        return [PSCustomObject]@{
            SamAccountName    = $samAccountName
            DisplayName       = $displayName
            UserPrincipalName = $userPrincipalName
            Status            = $status
            Enabled           = $enabled
            LockedOut         = $lockedOut
            PasswordExpired   = $passwordExpired
            Department        = $department
            Title             = $title
            Mail              = $mail
            LastLogonDate     = $lastLogonDate
            ErrorCount        = 0
            SimulationMode    = $SimulationMode
        }
    }
    catch {
        throw "Falha ao criar resumo do usuário: $($_.Exception.Message)"
    }
}


# ============================================================
# GET-USER-MANAGEMENT
# ============================================================

function Get-UserManagement {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $Configuration
    )

    $result = [PSCustomObject]@{
        Success        = $false
        SamAccountName = $SamAccountName
        SimulationMode = $false
        Status         = "Unknown"
        Summary        = $null
        Data           = $null
        Errors         = @()
    }

    try {

        # ----------------------------------------------------
        # Validação
        # ----------------------------------------------------

        if ([string]::IsNullOrWhiteSpace($SamAccountName)) {

            $result.Errors = @(
                "SamAccountName não pode ser vazio."
            )

            return $result
        }

        # ----------------------------------------------------
        # Simulation Mode
        # ----------------------------------------------------

        if (
            $null -ne $Configuration.PSObject.Properties["SimulationMode"]
        ) {
            $result.SimulationMode = [bool]$Configuration.SimulationMode
        }

        # ----------------------------------------------------
        # User Core
        # ----------------------------------------------------

        $coreResult = Get-UserADInfo `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration

        if ($null -eq $coreResult) {

            $result.Errors = @(
                "User Core não retornou resultado."
            )

            return $result
        }

        # ----------------------------------------------------
        # Core retornou erro
        # ----------------------------------------------------

        if (-not $coreResult.Success) {

            $errors = @()

            if (
                $coreResult.PSObject.Properties.Name -contains "Error" -and
                $null -ne $coreResult.Error
            ) {
                $errors += $coreResult.Error
            }

            if (
                $coreResult.PSObject.Properties.Name -contains "Errors" -and
                $null -ne $coreResult.Errors
            ) {
                $errors += @($coreResult.Errors)
            }

            if ($errors.Count -eq 0) {
                $errors += "User Core informou falha sem mensagem de erro."
            }

            $result.Errors = $errors

            return $result
        }

        # ----------------------------------------------------
        # Dados do usuário
        # ----------------------------------------------------

        $user = $coreResult.Data

        if ($null -eq $user) {

            $result.Errors = @(
                "User Core informou sucesso, mas não retornou os dados do usuário."
            )

            return $result
        }

        $result.Data = $user

        # ----------------------------------------------------
        # Resumo
        # ----------------------------------------------------

        $result.Summary = New-UserManagementSummary `
            -User $user `
            -SimulationMode $result.SimulationMode

        $result.Status = $result.Summary.Status

        $result.Success = $true

        return $result
    }
    catch {

        $result.Success = $false

        $result.Errors = @(
            "Erro controlado no User Management: $($_.Exception.Message)"
        )

        return $result
    }
}


# ============================================================
# GET-USER-MANAGEMENT-SUMMARY
# ============================================================

function Get-UserManagementSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        $ManagementResult
    )

    try {

        if (-not $ManagementResult.Success) {

            $errorMessage = "Resultado do User Management inválido."

            if (
                $ManagementResult.PSObject.Properties.Name -contains "Errors" -and
                $null -ne $ManagementResult.Errors
            ) {
                $errorMessage = @($ManagementResult.Errors) -join "; "
            }

            return [PSCustomObject]@{
                Success = $false
                Data    = $null
                Error   = $errorMessage
            }
        }

        return [PSCustomObject]@{
            Success = $true
            Data    = $ManagementResult.Summary
            Error   = $null
        }
    }
    catch {

        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Error   = "Erro ao obter resumo do User Management: $($_.Exception.Message)"
        }
    }
}


# ============================================================
# EXPORTAÇÃO
# ============================================================

Export-ModuleMember -Function @(
    "New-UserManagementSummary",
    "Get-UserManagement",
    "Get-UserManagementSummary"
)