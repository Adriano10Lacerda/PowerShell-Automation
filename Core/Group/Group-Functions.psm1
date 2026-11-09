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

function New-GroupResultModel {
    param(
        [bool]$Success = $false,
        [object]$Data = $null,
        [string]$Error = "",
        [bool]$SimulationMode = $false,
        [ValidateSet('NotQueried','Found','NotFound','Error','Simulation')]
        [string]$QueryStatus = 'NotQueried'
    )
    [PSCustomObject]@{
        Success = $Success
        Data = $Data
        Error = $Error
        SimulationMode = $SimulationMode
        QueryStatus = $QueryStatus
    }
}

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
    elseif ($Configuration.SimulationMode -isnot [bool]) {
        $errors.Add("SimulationMode deve ser Boolean.")
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
        [object]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead
    )

    if ($null -eq $Configuration -or $Configuration.SimulationMode -isnot [bool]) {
        return New-GroupResultModel -Success $false -Error "SimulationMode deve ser definido explicitamente como Boolean." -SimulationMode $false
    }
    if (-not $Configuration.SimulationMode -and -not $AllowRealRead) {
        return New-GroupResultModel -Success $false -Error "Consulta real bloqueada. Informe -AllowRealRead explicitamente." -SimulationMode $false
    }

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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$Preview
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

    if ($Configuration.SimulationMode -and $AllowRealRead) {
        return New-GroupResultModel -Success $false -Data $null -Error "Configuração contraditória: SimulationMode não pode ser combinado com AllowRealRead." -SimulationMode $true -QueryStatus "NotQueried"
    }
    if ($Preview -or $WhatIfPreference) {
        $previewResult = New-GroupResultModel -Success $true -Data $null -Error "" -SimulationMode ([bool]$Configuration.SimulationMode)
        $previewResult.QueryStatus = "NotQueried"
        $previewResult | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        return $previewResult
    }
    if (-not $Configuration.SimulationMode -and -not $AllowRealRead) {
        $blocked = New-GroupResultModel -Success $false -Data $null -Error "Consulta real bloqueada. Informe -AllowRealRead explicitamente. AllowRealOperation não concede autorização de leitura." -SimulationMode $false
        $blocked.QueryStatus = "NotQueried"
        return $blocked
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
                -SimulationMode $true `
                -QueryStatus "Simulation"
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
            -SimulationMode $true `
            -QueryStatus "Simulation"
    }

    try {

        Import-Module ActiveDirectory -ErrorAction Stop

        $domainController = [string]$Configuration.ActiveDirectory.DomainController

        $group = Get-ADGroup `
            -Identity $GroupName `
            -Server $domainController `
            -Properties Description, GroupCategory, GroupScope, DistinguishedName `
            -ErrorAction Stop

        if ($null -eq $group) {
            return New-GroupResultModel -Success $false -Data $null -Error "Grupo '$GroupName' não encontrado." -SimulationMode $false -QueryStatus "NotFound"
        }

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

        $result = New-GroupResultModel `
            -Success $true `
            -Data $data `
            -Error "" `
            -SimulationMode $false
        $result.QueryStatus = "Found"
        return $result
    }
    catch {

        $status = if ($_.Exception.GetType().FullName -eq "Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException") { "NotFound" } else { "Error" }
        $result = New-GroupResultModel `
            -Success $false `
            -Data $null `
            -Error $_.Exception.Message `
            -SimulationMode $false
        $result.QueryStatus = $status
        return $result
    }
}

function Get-GroupMembers {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$Preview
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

    if ($Configuration.SimulationMode -and $AllowRealRead) {
        return New-GroupResultModel -Success $false -Data @() -Error "Configuração contraditória: SimulationMode não pode ser combinado com AllowRealRead." -SimulationMode $true -QueryStatus "NotQueried"
    }
    if ($Preview -or $WhatIfPreference) {
        $previewResult = New-GroupResultModel -Success $true -Data @() -Error "" -SimulationMode ([bool]$Configuration.SimulationMode)
        $previewResult.QueryStatus = "NotQueried"
        $previewResult | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        return $previewResult
    }
    if (-not $Configuration.SimulationMode -and -not $AllowRealRead) {
        $blocked = New-GroupResultModel -Success $false -Data @() -Error "Consulta real bloqueada. Informe -AllowRealRead explicitamente. AllowRealOperation não concede autorização de leitura." -SimulationMode $false
        $blocked.QueryStatus = "NotQueried"
        return $blocked
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
                -SimulationMode $true `
                -QueryStatus "Simulation"
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
            -SimulationMode $true `
            -QueryStatus "Simulation"
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

        $result = New-GroupResultModel `
            -Success $true `
            -Data @($result) `
            -Error "" `
            -SimulationMode $false
        $result.QueryStatus = "Found"
        return $result
    }
    catch {

        $status = if ($_.Exception.GetType().FullName -eq "Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException") { "NotFound" } else { "Error" }
        $result = New-GroupResultModel `
            -Success $false `
            -Data @() `
            -Error $_.Exception.Message `
            -SimulationMode $false
        $result.QueryStatus = $status
        return $result
    }
}

function Get-GroupMembership {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$Preview
    )

    $configurationErrors = Test-GroupCoreConfiguration -Configuration $Configuration
    if ($configurationErrors.Count -gt 0) {
        return New-GroupResultModel -Success $false -Data $null -Error ($configurationErrors -join ' ') -SimulationMode $false -QueryStatus 'NotQueried'
    }

    if ($Configuration.SimulationMode -and $AllowRealRead) {
        return New-GroupResultModel -Success $false -Data $null -Error "Configuração contraditória: SimulationMode não pode ser combinado com AllowRealRead." -SimulationMode $true -QueryStatus "NotQueried"
    }
    if ($Preview -or $WhatIfPreference) {
        $previewResult = New-GroupResultModel -Success $true -Data $null -Error "" -SimulationMode ([bool]$Configuration.SimulationMode)
        $previewResult.QueryStatus = "NotQueried"
        $previewResult | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        return $previewResult
    }

    $membersResult = Get-GroupMembers `
        -GroupName $GroupName `
        -Configuration $Configuration `
        -AllowRealRead:$AllowRealRead `
        -Preview:$Preview

    if (-not $membersResult.Success) {
        return New-GroupResultModel `
            -Success $false `
            -Data $false `
            -Error $membersResult.Error `
            -SimulationMode $membersResult.SimulationMode `
            -QueryStatus $membersResult.QueryStatus
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
        -SimulationMode $membersResult.SimulationMode `
        -QueryStatus $membersResult.QueryStatus
}

function Get-GroupInventory {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$Preview
    )

    $configurationErrors = Test-GroupCoreConfiguration -Configuration $Configuration
    if ($configurationErrors.Count -gt 0) {
        return New-GroupResultModel -Success $false -Data $null -Error ($configurationErrors -join ' ') -SimulationMode $false -QueryStatus 'NotQueried'
    }

    if ($Configuration.SimulationMode -and $AllowRealRead) {
        return New-GroupResultModel -Success $false -Data $null -Error "Configuração contraditória: SimulationMode não pode ser combinado com AllowRealRead." -SimulationMode $true -QueryStatus "NotQueried"
    }
    if ($Preview -or $WhatIfPreference) {
        $previewResult = New-GroupResultModel -Success $true -Data $null -Error "" -SimulationMode ([bool]$Configuration.SimulationMode)
        $previewResult.QueryStatus = "NotQueried"
        $previewResult | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        return $previewResult
    }

    $groupResult = Get-GroupADInfo `
        -GroupName $GroupName `
        -Configuration $Configuration `
        -AllowRealRead:$AllowRealRead `
        -Preview:$Preview

    if (-not $groupResult.Success) {
        return New-GroupResultModel `
            -Success $false `
            -Data $null `
            -Error $groupResult.Error `
            -SimulationMode $groupResult.SimulationMode `
            -QueryStatus $groupResult.QueryStatus
    }

    $membersResult = Get-GroupMembers `
        -GroupName $GroupName `
        -Configuration $Configuration `
        -AllowRealRead:$AllowRealRead `
        -Preview:$Preview

    if (-not $membersResult.Success) {
        return New-GroupResultModel `
            -Success $false `
            -Data $null `
            -Error $membersResult.Error `
            -SimulationMode $membersResult.SimulationMode `
            -QueryStatus $membersResult.QueryStatus
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
        -SimulationMode $groupResult.SimulationMode `
        -QueryStatus $groupResult.QueryStatus
}

Export-ModuleMember -Function `
    Get-GroupADInfo, `
    Get-GroupMembers, `
    Get-GroupMembership, `
    Get-GroupInventory
