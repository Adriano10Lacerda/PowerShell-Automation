#Requires -Version 5.1

<#
.SYNOPSIS
    Funções principais do User Core V2.

.DESCRIPTION
    Fornece operações de consulta de usuários do Active Directory
    com contrato padronizado Success/Data/Error.

.NOTES
    PowerShell Automation V2
#>

$modelsPath = Join-Path `
    $PSScriptRoot `
    "User-Models.ps1"

if (-not (Test-Path -LiteralPath $modelsPath)) {
    throw "User-Models.ps1 não encontrado: $modelsPath"
}

. $modelsPath

function Test-UserADExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $false
        Error   = $null
    }

    if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
        $result.Error = "O SamAccountName é obrigatório para realizar a consulta."
        return $result
    }

    # ============================================================
    # SIMULATION MODE
    # ============================================================

    if ($Configuration.SimulationMode -eq $true) {

        $existingNames = @()

        if ($null -ne $Configuration.Simulation) {

            if ($null -ne $Configuration.Simulation.ExistingSamAccountNames) {
                $existingNames = @(
                    $Configuration.Simulation.ExistingSamAccountNames
                )
            }
        }

        $exists = $existingNames -contains $SamAccountName

        return [PSCustomObject]@{
            Success = $true
            Data    = $exists
            Error   = $null
        }
    }

    # ============================================================
    # VALIDAR ACTIVE DIRECTORY
    # ============================================================

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {

        $result.Error = `
            "O módulo 'ActiveDirectory' não está instalado neste computador."

        return $result
    }

    if ([string]::IsNullOrWhiteSpace($Configuration.DomainController)) {

        $result.Error = `
            "O DomainController deve ser configurado para consultar o Active Directory."

        return $result
    }

    try {

        Import-Module `
            ActiveDirectory `
            -ErrorAction Stop

        Get-ADUser `
            -Identity $SamAccountName `
            -Server $Configuration.DomainController `
            -ErrorAction Stop | Out-Null

        $result.Success = $true
        $result.Data = $true

        return $result
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {

        $result.Success = $true
        $result.Data = $false

        return $result
    }
    catch {

        $result.Error = `
            "Não foi possível consultar o usuário '$SamAccountName'. Detalhes: $($_.Exception.Message)"

        return $result
    }
}

function Get-UserADInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [PSCustomObject]$Configuration
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    if ([string]::IsNullOrWhiteSpace($SamAccountName)) {

        $result.Error = `
            "O SamAccountName é obrigatório para realizar a consulta."

        return $result
    }

    # ============================================================
    # SIMULATION MODE
    # ============================================================

    if ($Configuration.SimulationMode -eq $true) {

        $existsResult = Test-UserADExists `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration

        if (-not $existsResult.Success) {

            $result.Error = $existsResult.Error
            return $result
        }

        if (-not $existsResult.Data) {

            $result.Error = `
                "Usuário '$SamAccountName' não encontrado no ambiente de simulação."

            return $result
        }

        $user = New-UserModel

        $user.Identity.SamAccountName = $SamAccountName
        $user.Identity.UserPrincipalName = `
            "$SamAccountName@$($Configuration.UserPrincipalName.Domain)"

        $user.Identity.DistinguishedName = `
            "CN=$SamAccountName,OU=Simulation,$($Configuration.Domain)"

        $user.Personal.Name = $SamAccountName
        $user.Personal.DisplayName = $SamAccountName

        $user.Account.Enabled = $true
        $user.Account.LockedOut = $false
        $user.Account.PasswordExpired = $false
        $user.Account.PasswordNeverExpires = $false
        $user.Account.PasswordNotRequired = $false

        $user.Activity.Created = $null
        $user.Activity.Modified = $null
        $user.Activity.LastLogonDate = $null

        $result.Success = $true
        $result.Data = $user

        return $result
    }

    # ============================================================
    # VALIDAR ACTIVE DIRECTORY
    # ============================================================

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {

        $result.Error = `
            "O módulo 'ActiveDirectory' não está instalado neste computador."

        return $result
    }

    if ([string]::IsNullOrWhiteSpace($Configuration.DomainController)) {

        $result.Error = `
            "O DomainController deve ser configurado para consultar o Active Directory."

        return $result
    }

    try {

        Import-Module `
            ActiveDirectory `
            -ErrorAction Stop

        $adUser = Get-ADUser `
            -Identity $SamAccountName `
            -Server $Configuration.DomainController `
            -Properties `
                UserPrincipalName,
                DistinguishedName,
                ObjectGuid,
                GivenName,
                Surname,
                DisplayName,
                Mail,
                Department,
                Title,
                Company,
                Manager,
                Enabled,
                LockedOut,
                PasswordExpired,
                PasswordNeverExpires,
                PasswordNotRequired,
                AccountExpirationDate,
                LastLogonDate,
                whenCreated,
                whenChanged,
                MemberOf `
            -ErrorAction Stop

        $user = New-UserModel

        # ========================================================
        # IDENTITY
        # ========================================================

        $user.Identity.SamAccountName = $adUser.SamAccountName
        $user.Identity.UserPrincipalName = $adUser.UserPrincipalName
        $user.Identity.DistinguishedName = $adUser.DistinguishedName
        $user.Identity.ObjectGuid = $adUser.ObjectGuid

        # ========================================================
        # PERSONAL
        # ========================================================

        $user.Personal.Name = $adUser.Name
        $user.Personal.GivenName = $adUser.GivenName
        $user.Personal.Surname = $adUser.Surname
        $user.Personal.DisplayName = $adUser.DisplayName
        $user.Personal.Mail = $adUser.Mail

        # ========================================================
        # ORGANIZATION
        # ========================================================

        $user.Organization.Department = $adUser.Department
        $user.Organization.Title = $adUser.Title
        $user.Organization.Company = $adUser.Company
        $user.Organization.Manager = $adUser.Manager

        # ========================================================
        # ACCOUNT
        # ========================================================

        $user.Account.Enabled = $adUser.Enabled
        $user.Account.LockedOut = $adUser.LockedOut
        $user.Account.PasswordExpired = $adUser.PasswordExpired
        $user.Account.PasswordNeverExpires = $adUser.PasswordNeverExpires
        $user.Account.PasswordNotRequired = $adUser.PasswordNotRequired
        $user.Account.AccountExpirationDate = $adUser.AccountExpirationDate

        # ========================================================
        # ACTIVITY
        # ========================================================

        $user.Activity.LastLogonDate = $adUser.LastLogonDate
        $user.Activity.Created = $adUser.whenCreated
        $user.Activity.Modified = $adUser.whenChanged

        # ========================================================
        # GROUPS
        # ========================================================

        if ($null -ne $adUser.MemberOf) {
            $user.Groups = @($adUser.MemberOf)
        }
        else {
            $user.Groups = @()
        }

        $result.Success = $true
        $result.Data = $user

        return $result
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {

        $result.Error = `
            "Usuário '$SamAccountName' não encontrado no Active Directory."

        return $result
    }
    catch {

        $result.Error = `
            "Não foi possível consultar o usuário '$SamAccountName'. Detalhes: $($_.Exception.Message)"

        return $result
    }
}

Export-ModuleMember -Function @(
    "Test-UserADExists",
    "Get-UserADInfo"
)