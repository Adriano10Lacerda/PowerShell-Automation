#Requires -Version 5.1

<#
.SYNOPSIS
    Group Core V2.

.DESCRIPTION
    Núcleo de consulta e inventário de grupos do Active Directory.

    O módulo suporta:
    - Simulation Mode
    - Active Directory real
    - Consulta de grupo
    - Consulta de membros
    - Consulta de associação
    - Inventário consolidado

    Este módulo NÃO executa alterações em grupos.
    Operações de alteração serão responsabilidade da camada
    Group Management.
#>

$modelsPath = Join-Path $PSScriptRoot "Group-Models.ps1"

if (-not (Test-Path -LiteralPath $modelsPath)) {
    throw "Arquivo Group-Models.ps1 não encontrado: $modelsPath"
}

. $modelsPath

function Get-GroupConfigurationValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$Property
    )

    if ($null -eq $Configuration) {
        return $null
    }

    $propertyInfo = $Configuration.PSObject.Properties[$Property]

    if ($null -eq $propertyInfo) {
        return $null
    }

    return $propertyInfo.Value
}

function Get-SimulatedGroup {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $simulation = Get-GroupConfigurationValue `
        -Configuration $Configuration `
        -Property "Simulation"

    if ($null -eq $simulation) {
        return $null
    }

    $groups = Get-GroupConfigurationValue `
        -Configuration $simulation `
        -Property "ExistingGroups"

    if ($null -eq $groups) {
        return $null
    }

    foreach ($group in @($groups)) {
        if ([string]::Equals(
            [string]$group.Name,
            $Name,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $group
        }
    }

    return $null
}

function Test-GroupCoreConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $errors = New-Object System.Collections.Generic.List[string]

    if ($null -eq $Configuration) {
        $errors.Add("Configuration é obrigatória.")
        return @($errors)
    }

    if ($null -eq $Configuration.PSObject.Properties["SimulationMode"]) {
        $errors.Add("SimulationMode não encontrado.")
    }

    if ($null -eq $Configuration.PSObject.Properties["ActiveDirectory"]) {
        $errors.Add("ActiveDirectory não encontrado.")
    }

    if ($null -eq $Configuration.PSObject.Properties["Group"]) {
        $errors.Add("Group não encontrado.")
    }

    if ($null -eq $Configuration.PSObject.Properties["Simulation"]) {
        $errors.Add("Simulation não encontrado.")
    }

    if ($null -ne $Configuration.PSObject.Properties["Simulation"]) {

        $simulation = $Configuration.Simulation

        if ($null -eq $simulation.PSObject.Properties["ExistingGroups"]) {
            $errors.Add("Simulation.ExistingGroups não encontrado.")
        }

        if ($null -eq $simulation.PSObject.Properties["ExistingUsers"]) {
            $errors.Add("Simulation.ExistingUsers não encontrado.")
        }
    }

    return @($errors)
}

function Test-GroupCoreConnectivity {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    if ([bool]$Configuration.SimulationMode) {
        return New-GroupResultModel `
            -Success $true `
            -Data "Simulation Mode" `
            -Error "" `
            -SimulationMode $true
    }

    try {

        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            return New-GroupResultModel `
                -Success $false `
                -Data $null `
                -Error "Módulo ActiveDirectory não encontrado." `
                -SimulationMode $false
        }

        Import-Module ActiveDirectory -ErrorAction Stop

        $domainController = ""

        if ($null -ne $Configuration.ActiveDirectory) {
            $domainController = [string]$Configuration.ActiveDirectory.DomainController
        }

        if ([string]::IsNullOrWhiteSpace($domainController)) {
            return New-GroupResultModel `
                -Success $false `
                -Data $null `
                -Error "DomainController não configurado." `
                -SimulationMode $false
        }

        $domain = Get-ADDomain `
            -Server $domainController `
            -ErrorAction Stop

        return New-GroupResultModel `
            -Success $true `
            -Data $domain `
            -Error "" `
            -SimulationMode $false

    }
    catch {
        return New-GroupResultModel `
            -Success $false `
            -Data $null `
            -Error $_.Exception.Message `
            -SimulationMode $false
    }
}

function Get-GroupADInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $configurationErrors = Test-GroupCoreConfiguration `
        -Configuration $Configuration

    if ($configurationErrors.Count -gt 0) {
        return New-GroupResultModel `
            -Success $false `
            -Data $null `
            -Error ($configurationErrors -join " ") `
            -SimulationMode ([bool]$Configuration.SimulationMode)
    }

    if ([bool]$Configuration.SimulationMode) {

        $group = Get-SimulatedGroup `
            -Configuration $Configuration `
            -Name $GroupName

        if ($null -eq $group) {
            return New-GroupResultModel `
                -Success $false `
                -Data $null `
                -Error "Grupo '$GroupName' não encontrado no Simulation Mode." `
                -SimulationMode $true
        }

        $memberCount = @($group.Members).Count

        $identity = New-GroupIdentityModel `
            -Name ([string]$group.Name) `
            -SamAccountName ([string]$group.Name) `
            -DistinguishedName "" `
            -GroupCategory ([string]$Configuration.Group.DefaultCategory) `
            -GroupScope ([string]$Configuration.Group.DefaultScope)

        $data = [PSCustomObject]@{
            Identity    = $identity
            Description = [string]$group.Description
            Exists      = $true
            MemberCount = $memberCount
        }

        return New-GroupResultModel `
            -Success $true `
            -Data $data `
            -Error "" `
            -SimulationMode $true
    }

    try {

        Import-Module ActiveDirectory -ErrorAction Stop

        $domainController = [string]$Configuration.ActiveDirectory.DomainController

        $group = Get-ADGroup `
            -Identity $GroupName `
            -Server $domainController `
            -Properties Description, GroupCategory, GroupScope, DistinguishedName `
            -ErrorAction Stop

        $members = @(Get-ADGroupMember `
            -Identity $group `
            -Server $domainController `
            -ErrorAction Stop)

        $identity = New-GroupIdentityModel `
            -Name ([string]$group.Name) `
            -SamAccountName ([string]$group.SamAccountName) `
            -DistinguishedName ([string]$group.DistinguishedName) `
            -GroupCategory ([string]$group.GroupCategory) `
            -GroupScope ([string]$group.GroupScope)

        $data = [PSCustomObject]@{
            Identity    = $identity
            Description = [string]$group.Description
            Exists      = $true
            MemberCount = $members.Count
        }

        return New-GroupResultModel `
            -Success $true `
            -Data $data `
            -Error "" `
            -SimulationMode $false
    }
    catch {

        return New-GroupResultModel `
            -Success $false `
            -Data $null `
            -Error $_.Exception.Message `
            -SimulationMode $false
    }
}

function Get-GroupMembers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $configurationErrors = Test-GroupCoreConfiguration `
        -Configuration $Configuration

    if ($configurationErrors.Count -gt 0) {
        return New-GroupResultModel `
            -Success $false `
            -Data @() `
            -Error ($configurationErrors -join " ") `
            -SimulationMode ([bool]$Configuration.SimulationMode)
    }

    if ([bool]$Configuration.SimulationMode) {

        $group = Get-SimulatedGroup `
            -Configuration $Configuration `
            -Name $GroupName

        if ($null -eq $group) {
            return New-GroupResultModel `
                -Success $false `
                -Data @() `
                -Error "Grupo '$GroupName' não encontrado no Simulation Mode." `
                -SimulationMode $true
        }

        $members = foreach ($member in @($group.Members)) {

            [PSCustomObject]@{
                SamAccountName = [string]$member
                Name           = [string]$member
                ObjectClass    = "user"
            }
        }

        return New-GroupResultModel `
            -Success $true `
            -Data @($members) `
            -Error "" `
            -SimulationMode $true
    }

    try {

        Import-Module ActiveDirectory -ErrorAction Stop

        $domainController = [string]$Configuration.ActiveDirectory.DomainController

        $members = @(Get-ADGroupMember `
            -Identity $GroupName `
            -Server $domainController `
            -ErrorAction Stop)

        $result = foreach ($member in $members) {

            [PSCustomObject]@{
                SamAccountName = [string]$member.SamAccountName
                Name           = [string]$member.Name
                ObjectClass    = [string]$member.objectClass
            }
        }

        return New-GroupResultModel `
            -Success $true `
            -Data @($result) `
            -Error "" `
            -SimulationMode $false
    }
    catch {

        return New-GroupResultModel `
            -Success $false `
            -Data @() `
            -Error $_.Exception.Message `
            -SimulationMode $false
    }
}

function Get-GroupMembership {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $membersResult = Get-GroupMembers `
        -GroupName $GroupName `
        -Configuration $Configuration

    if (-not $membersResult.Success) {
        return New-GroupResultModel `
            -Success $false `
            -Data $false `
            -Error $membersResult.Error `
            -SimulationMode $membersResult.SimulationMode
    }

    $isMember = $false

    foreach ($member in @($membersResult.Data)) {

        if ([string]::Equals(
            [string]$member.SamAccountName,
            $SamAccountName,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            $isMember = $true
            break
        }
    }

    $data = [PSCustomObject]@{
        GroupName       = $GroupName
        SamAccountName  = $SamAccountName
        IsMember        = $isMember
    }

    return New-GroupResultModel `
        -Success $true `
        -Data $data `
        -Error "" `
        -SimulationMode $membersResult.SimulationMode
}

function Get-GroupInventory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $groupResult = Get-GroupADInfo `
        -GroupName $GroupName `
        -Configuration $Configuration

    if (-not $groupResult.Success) {
        return New-GroupResultModel `
            -Success $false `
            -Data $null `
            -Error $groupResult.Error `
            -SimulationMode $groupResult.SimulationMode
    }

    $membersResult = Get-GroupMembers `
        -GroupName $GroupName `
        -Configuration $Configuration

    if (-not $membersResult.Success) {
        return New-GroupResultModel `
            -Success $false `
            -Data $null `
            -Error $membersResult.Error `
            -SimulationMode $membersResult.SimulationMode
    }

    $inventory = New-GroupInventoryModel `
        -Name ([string]$groupResult.Data.Identity.Name) `
        -SamAccountName ([string]$groupResult.Data.Identity.SamAccountName) `
        -Description ([string]$groupResult.Data.Description) `
        -GroupCategory ([string]$groupResult.Data.Identity.GroupCategory) `
        -GroupScope ([string]$groupResult.Data.Identity.GroupScope) `
        -DistinguishedName ([string]$groupResult.Data.Identity.DistinguishedName) `
        -Exists ([bool]$groupResult.Data.Exists) `
        -MemberCount (@($membersResult.Data).Count) `
        -Members @($membersResult.Data)

    return New-GroupResultModel `
        -Success $true `
        -Data $inventory `
        -Error "" `
        -SimulationMode $groupResult.SimulationMode
}

Export-ModuleMember -Function `
    Get-GroupADInfo, `
    Get-GroupMembers, `
    Get-GroupMembership, `
    Get-GroupInventory