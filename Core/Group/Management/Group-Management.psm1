#Requires -Version 5.1

<#
.SYNOPSIS
    Group Management V2.

.DESCRIPTION
    Camada de gerenciamento de grupos sobre o Group Core V2.

    Operações:
    - Consulta de grupo
    - Listagem de membros
    - Adição de membro
    - Remoção de membro

    Alterações seguem:
    Preview -> Confirm -> Execute -> Result -> Audit

    Em SimulationMode nenhuma alteração real é realizada.
    As alterações simuladas são persistidas no objeto Configuration
    durante a execução do processo atual.
#>

$groupCorePath = Join-Path `
    $PSScriptRoot `
    "..\Group-Functions.psm1"

$auditPath = Join-Path `
    $PSScriptRoot `
    "..\..\Audit\Audit-Functions.psm1"

if (-not (Test-Path -LiteralPath $groupCorePath)) {
    throw "Group-Functions.psm1 não encontrado: $groupCorePath"
}

if (-not (Test-Path -LiteralPath $auditPath)) {
    throw "Audit-Functions.psm1 não encontrado: $auditPath"
}

Import-Module $groupCorePath -Force -ErrorAction Stop
Import-Module $auditPath -Force -ErrorAction Stop

function New-GroupManagementResult {
    param(
        [bool]$Success = $false,
        [object]$Data = $null,
        [string]$Error = "",
        [bool]$SimulationMode = $false,
        [bool]$Changed = $false,
        [object]$Audit = $null
    )

    [PSCustomObject]@{
        Success        = $Success
        Data           = $Data
        Error          = $Error
        SimulationMode = $SimulationMode
        Changed        = $Changed
        Audit          = $Audit
    }
}

function Get-SimulationGroup {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$GroupName
    )

    foreach ($group in @($Configuration.Simulation.ExistingGroups)) {

        if ([string]::Equals(
            [string]$group.Name,
            $GroupName,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $group
        }
    }

    return $null
}

function Test-SimulationUserExists {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName
    )

    foreach ($user in @($Configuration.Simulation.ExistingUsers)) {

        if ([string]::Equals(
            [string]$user,
            $SamAccountName,
            [System.StringComparison]::OrdinalIgnoreCase
        )) {
            return $true
        }
    }

    return $false
}

function Set-SimulationGroupMembers {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Group,

        [Parameter(Mandatory = $true)]
        [string[]]$Members
    )

    $Group.Members = @($Members)

    return @($Group.Members)
}

function Add-SimulationGroupMember {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Group,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName
    )

    $members = @($Group.Members)

    $members += $SamAccountName

    return Set-SimulationGroupMembers `
        -Group $Group `
        -Members $members
}

function Remove-SimulationGroupMember {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Group,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName
    )

    $members = @(
        foreach ($member in @($Group.Members)) {

            if (-not [string]::Equals(
                [string]$member,
                $SamAccountName,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
                $member
            }
        }
    )

    return Set-SimulationGroupMembers `
        -Group $Group `
        -Members $members
}

function New-GroupAuditRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [string]$Result,

        [Parameter(Mandatory = $true)]
        [bool]$SimulationMode,

        [Parameter(Mandatory = $true)]
        [bool]$Changed
    )

    $auditResult = New-AuditRecord `
        -Action $Action `
        -SamAccountName $SamAccountName `
        -Result $Result `
        -SimulationMode $SimulationMode `
        -Changed $Changed

    if (-not $auditResult.Success) {
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Error   = $auditResult.Error
        }
    }

    $validationResult = Test-AuditRecord `
        -Record $auditResult.Data

    if (-not $validationResult.Success) {
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Error   = $validationResult.Error
        }
    }

    return [PSCustomObject]@{
        Success = $true
        Data    = $auditResult.Data
        Error   = $null
    }
}

function Get-GroupManagementPreview {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("AddMember", "RemoveMember")]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $groupResult = Get-GroupADInfo `
        -GroupName $GroupName `
        -Configuration $Configuration

    if (-not $groupResult.Success) {

        return New-GroupManagementResult `
            -Success $false `
            -Error $groupResult.Error `
            -SimulationMode $groupResult.SimulationMode
    }

    $membershipResult = Get-GroupMembership `
        -GroupName $GroupName `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration

    if (-not $membershipResult.Success) {

        return New-GroupManagementResult `
            -Success $false `
            -Error $membershipResult.Error `
            -SimulationMode $membershipResult.SimulationMode
    }

    $userExists = $false

    if ($Configuration.SimulationMode) {

        $userExists = Test-SimulationUserExists `
            -Configuration $Configuration `
            -SamAccountName $SamAccountName
    }
    else {

        try {

            Import-Module ActiveDirectory -ErrorAction Stop

            $domainController = [string]$Configuration.ActiveDirectory.DomainController

            $null = Get-ADUser `
                -Identity $SamAccountName `
                -Server $domainController `
                -ErrorAction Stop

            $userExists = $true
        }
        catch {
            $userExists = $false
        }
    }

    if (-not $userExists) {

        return New-GroupManagementResult `
            -Success $false `
            -Error "Usuário '$SamAccountName' não encontrado." `
            -SimulationMode ([bool]$Configuration.SimulationMode)
    }

    $isMember = [bool]$membershipResult.Data.IsMember

    if ($Action -eq "AddMember") {

        if ($isMember) {

            return New-GroupManagementResult `
                -Success $false `
                -Error "Usuário '$SamAccountName' já é membro de '$GroupName'." `
                -SimulationMode ([bool]$Configuration.SimulationMode)
        }

        $preview = [PSCustomObject]@{
            Action          = "AddMember"
            GroupName       = $GroupName
            SamAccountName  = $SamAccountName
            CurrentState    = "NotMember"
            TargetState     = "Member"
            CanExecute      = $true
            RequiresConfirm = $true
        }
    }
    else {

        if (-not $isMember) {

            return New-GroupManagementResult `
                -Success $false `
                -Error "Usuário '$SamAccountName' não é membro de '$GroupName'." `
                -SimulationMode ([bool]$Configuration.SimulationMode)
        }

        $preview = [PSCustomObject]@{
            Action          = "RemoveMember"
            GroupName       = $GroupName
            SamAccountName  = $SamAccountName
            CurrentState    = "Member"
            TargetState     = "NotMember"
            CanExecute      = $true
            RequiresConfirm = $true
        }
    }

    return New-GroupManagementResult `
        -Success $true `
        -Data $preview `
        -SimulationMode ([bool]$Configuration.SimulationMode)
}

function Invoke-GroupAddMember {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [switch]$Execute
    )

    $previewResult = Get-GroupManagementPreview `
        -Action "AddMember" `
        -GroupName $GroupName `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration

    if (-not $previewResult.Success) {
        return $previewResult
    }

    if (-not $Execute) {
        return $previewResult
    }

    if ([bool]$Configuration.SimulationMode) {

        $group = Get-SimulationGroup `
            -Configuration $Configuration `
            -GroupName $GroupName

        if ($null -eq $group) {

            return New-GroupManagementResult `
                -Success $false `
                -Error "Grupo '$GroupName' não encontrado para alteração simulada." `
                -SimulationMode $true
        }

        $null = Add-SimulationGroupMember `
            -Group $group `
            -SamAccountName $SamAccountName

        $result = [PSCustomObject]@{
            Action         = "AddMember"
            GroupName      = $GroupName
            SamAccountName = $SamAccountName
            PreviousState  = "NotMember"
            CurrentState   = "Member"
            Changed        = $true
            SimulationMode = $true
        }

        $audit = New-GroupAuditRecord `
            -Action "AddMember" `
            -SamAccountName $SamAccountName `
            -Result "Success" `
            -SimulationMode $true `
            -Changed $true

        if (-not $audit.Success) {

            return New-GroupManagementResult `
                -Success $false `
                -Data $result `
                -Error "Alteração simulada realizada, mas a auditoria falhou: $($audit.Error)" `
                -SimulationMode $true `
                -Changed $true
        }

        return New-GroupManagementResult `
            -Success $true `
            -Data $result `
            -SimulationMode $true `
            -Changed $true `
            -Audit $audit.Data
    }

    try {

        Import-Module ActiveDirectory -ErrorAction Stop

        $domainController = [string]$Configuration.ActiveDirectory.DomainController

        Add-ADGroupMember `
            -Identity $GroupName `
            -Members $SamAccountName `
            -Server $domainController `
            -ErrorAction Stop

        $result = [PSCustomObject]@{
            Action         = "AddMember"
            GroupName      = $GroupName
            SamAccountName = $SamAccountName
            PreviousState  = "NotMember"
            CurrentState   = "Member"
            Changed        = $true
            SimulationMode = $false
        }

        $audit = New-GroupAuditRecord `
            -Action "AddMember" `
            -SamAccountName $SamAccountName `
            -Result "Success" `
            -SimulationMode $false `
            -Changed $true

        if (-not $audit.Success) {

            return New-GroupManagementResult `
                -Success $false `
                -Data $result `
                -Error "Alteração realizada, mas a auditoria falhou: $($audit.Error)" `
                -SimulationMode $false `
                -Changed $true
        }

        return New-GroupManagementResult `
            -Success $true `
            -Data $result `
            -SimulationMode $false `
            -Changed $true `
            -Audit $audit.Data
    }
    catch {

        $audit = New-GroupAuditRecord `
            -Action "AddMember" `
            -SamAccountName $SamAccountName `
            -Result "Failed" `
            -SimulationMode $false `
            -Changed $false

        $auditError = ""

        if (-not $audit.Success) {
            $auditError = " Auditoria também falhou: $($audit.Error)"
        }

        return New-GroupManagementResult `
            -Success $false `
            -Error "$($_.Exception.Message)$auditError" `
            -SimulationMode $false
    }
}

function Invoke-GroupRemoveMember {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [switch]$Execute
    )

    $previewResult = Get-GroupManagementPreview `
        -Action "RemoveMember" `
        -GroupName $GroupName `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration

    if (-not $previewResult.Success) {
        return $previewResult
    }

    if (-not $Execute) {
        return $previewResult
    }

    if ([bool]$Configuration.SimulationMode) {

        $group = Get-SimulationGroup `
            -Configuration $Configuration `
            -GroupName $GroupName

        if ($null -eq $group) {

            return New-GroupManagementResult `
                -Success $false `
                -Error "Grupo '$GroupName' não encontrado para alteração simulada." `
                -SimulationMode $true
        }

        $null = Remove-SimulationGroupMember `
            -Group $group `
            -SamAccountName $SamAccountName

        $result = [PSCustomObject]@{
            Action         = "RemoveMember"
            GroupName      = $GroupName
            SamAccountName = $SamAccountName
            PreviousState  = "Member"
            CurrentState   = "NotMember"
            Changed        = $true
            SimulationMode = $true
        }

        $audit = New-GroupAuditRecord `
            -Action "RemoveMember" `
            -SamAccountName $SamAccountName `
            -Result "Success" `
            -SimulationMode $true `
            -Changed $true

        if (-not $audit.Success) {

            return New-GroupManagementResult `
                -Success $false `
                -Data $result `
                -Error "Alteração simulada realizada, mas a auditoria falhou: $($audit.Error)" `
                -SimulationMode $true `
                -Changed $true
        }

        return New-GroupManagementResult `
            -Success $true `
            -Data $result `
            -SimulationMode $true `
            -Changed $true `
            -Audit $audit.Data
    }

    try {

        Import-Module ActiveDirectory -ErrorAction Stop

        $domainController = [string]$Configuration.ActiveDirectory.DomainController

        Remove-ADGroupMember `
            -Identity $GroupName `
            -Members $SamAccountName `
            -Server $domainController `
            -Confirm:$false `
            -ErrorAction Stop

        $result = [PSCustomObject]@{
            Action         = "RemoveMember"
            GroupName      = $GroupName
            SamAccountName = $SamAccountName
            PreviousState  = "Member"
            CurrentState   = "NotMember"
            Changed        = $true
            SimulationMode = $false
        }

        $audit = New-GroupAuditRecord `
            -Action "RemoveMember" `
            -SamAccountName $SamAccountName `
            -Result "Success" `
            -SimulationMode $false `
            -Changed $true

        if (-not $audit.Success) {

            return New-GroupManagementResult `
                -Success $false `
                -Data $result `
                -Error "Alteração realizada, mas a auditoria falhou: $($audit.Error)" `
                -SimulationMode $false `
                -Changed $true
        }

        return New-GroupManagementResult `
            -Success $true `
            -Data $result `
            -SimulationMode $false `
            -Changed $true `
            -Audit $audit.Data
    }
    catch {

        $audit = New-GroupAuditRecord `
            -Action "RemoveMember" `
            -SamAccountName $SamAccountName `
            -Result "Failed" `
            -SimulationMode $false `
            -Changed $false

        $auditError = ""

        if (-not $audit.Success) {
            $auditError = " Auditoria também falhou: $($audit.Error)"
        }

        return New-GroupManagementResult `
            -Success $false `
            -Error "$($_.Exception.Message)$auditError" `
            -SimulationMode $false
    }
}

function Get-GroupManagement {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $inventoryResult = Get-GroupInventory `
        -GroupName $GroupName `
        -Configuration $Configuration

    if (-not $inventoryResult.Success) {

        return New-GroupManagementResult `
            -Success $false `
            -Error $inventoryResult.Error `
            -SimulationMode $inventoryResult.SimulationMode
    }

    return New-GroupManagementResult `
        -Success $true `
        -Data $inventoryResult.Data `
        -SimulationMode $inventoryResult.SimulationMode
}

function Get-GroupManagementMembers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration
    )

    $membersResult = Get-GroupMembers `
        -GroupName $GroupName `
        -Configuration $Configuration

    if (-not $membersResult.Success) {

        return New-GroupManagementResult `
            -Success $false `
            -Error $membersResult.Error `
            -SimulationMode $membersResult.SimulationMode
    }

    return New-GroupManagementResult `
        -Success $true `
        -Data @($membersResult.Data) `
        -SimulationMode $membersResult.SimulationMode
}

Export-ModuleMember -Function `
    Get-GroupManagement, `
    Get-GroupManagementMembers, `
    Get-GroupManagementPreview, `
    Invoke-GroupAddMember, `
    Invoke-GroupRemoveMember