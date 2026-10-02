#Requires -Version 5.1

<#
.SYNOPSIS
    Modelos de dados do User Core V2.

.DESCRIPTION
    Define o modelo padronizado utilizado pelo User Core
    para representar informações de usuários do Active Directory.

.NOTES
    PowerShell Automation V2
#>

function New-UserIdentityModel {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        SamAccountName    = $null
        UserPrincipalName = $null
        DistinguishedName = $null
        ObjectGuid        = $null
    }
}

function New-UserPersonalModel {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Name        = $null
        GivenName   = $null
        Surname     = $null
        DisplayName = $null
        Mail        = $null
    }
}

function New-UserOrganizationModel {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Department = $null
        Title      = $null
        Company    = $null
        Manager    = $null
    }
}

function New-UserAccountModel {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Enabled               = $null
        LockedOut             = $null
        PasswordExpired       = $null
        PasswordNeverExpires  = $null
        PasswordNotRequired   = $null
        AccountExpirationDate = $null
    }
}

function New-UserActivityModel {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        LastLogonDate = $null
        Created       = $null
        Modified      = $null
    }
}

function New-UserModel {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        Identity     = New-UserIdentityModel
        Personal     = New-UserPersonalModel
        Organization = New-UserOrganizationModel
        Account      = New-UserAccountModel
        Activity     = New-UserActivityModel
        Groups       = @()
    }
}

Export-ModuleMember -Function @(
    "New-UserIdentityModel",
    "New-UserPersonalModel",
    "New-UserOrganizationModel",
    "New-UserAccountModel",
    "New-UserActivityModel",
    "New-UserModel"
)