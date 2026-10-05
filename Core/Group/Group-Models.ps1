#Requires -Version 5.1

<#
.SYNOPSIS
    Modelos de dados do Group Core V2.

.DESCRIPTION
    Define os modelos padronizados utilizados pelo núcleo
    de gerenciamento e inventário de grupos do Active Directory.

    Nenhuma operação de alteração é executada neste arquivo.
#>

function New-GroupIdentityModel {
    param(
        [string]$Name = "",
        [string]$SamAccountName = "",
        [string]$DistinguishedName = "",
        [string]$GroupCategory = "",
        [string]$GroupScope = ""
    )

    [PSCustomObject]@{
        Name              = $Name
        SamAccountName    = $SamAccountName
        DistinguishedName = $DistinguishedName
        GroupCategory     = $GroupCategory
        GroupScope        = $GroupScope
    }
}

function New-GroupMembershipModel {
    param(
        [string]$SamAccountName = "",
        [string]$Name = "",
        [string]$ObjectClass = ""
    )

    [PSCustomObject]@{
        SamAccountName = $SamAccountName
        Name           = $Name
        ObjectClass    = $ObjectClass
    }
}

function New-GroupInventoryModel {
    param(
        [string]$Name = "",
        [string]$SamAccountName = "",
        [string]$Description = "",
        [string]$GroupCategory = "",
        [string]$GroupScope = "",
        [string]$DistinguishedName = "",
        [bool]$Exists = $false,
        [int]$MemberCount = 0,
        [object[]]$Members = @()
    )

    [PSCustomObject]@{
        Identity = New-GroupIdentityModel `
            -Name $Name `
            -SamAccountName $SamAccountName `
            -DistinguishedName $DistinguishedName `
            -GroupCategory $GroupCategory `
            -GroupScope $GroupScope

        Description = $Description
        Exists      = $Exists
        MemberCount = $MemberCount
        Members     = @($Members)
    }
}

function New-GroupResultModel {
    param(
        [bool]$Success = $false,
        [object]$Data = $null,
        [string]$Error = "",
        [bool]$SimulationMode = $false
    )

    [PSCustomObject]@{
        Success        = $Success
        Data           = $Data
        Error          = $Error
        SimulationMode = $SimulationMode
    }
}

Export-ModuleMember -Function `
    New-GroupIdentityModel, `
    New-GroupMembershipModel, `
    New-GroupInventoryModel, `
    New-GroupResultModel