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

function Invoke-GroupManagementShouldProcess {
    param(
        [Parameter(Mandatory)] [System.Management.Automation.PSCmdlet]$Cmdlet,
        [Parameter(Mandatory)] [string]$Target,
        [Parameter(Mandatory)] [string]$Action
    )
    return $Cmdlet.ShouldProcess($Target, $Action)
}

function New-GroupManagementResult {
    param(
        [bool]$Success = $false,
        [object]$Data = $null,
        [string]$Error = "",
        [bool]$SimulationMode = $false,
        [bool]$Changed = $false,
        [object]$Audit = $null,
        [ValidateSet('NotQueried','Found','NotFound','Error','Simulation')]
        [string]$QueryStatus = 'NotQueried'
    )

    [PSCustomObject]@{
        Success        = $Success
        Data           = $Data
        Error          = $Error
        SimulationMode = $SimulationMode
        Changed        = $Changed
        Audit          = $Audit
        QueryStatus    = $QueryStatus
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
        [AllowEmptyCollection()]
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
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("AddMember", "RemoveMember")]
        [string]$Action,

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

    if ($null -eq $Configuration -or $Configuration.SimulationMode -isnot [bool]) {
        return New-GroupManagementResult -Success $false -Error "SimulationMode deve ser definido explicitamente como Boolean." -SimulationMode $false
    }
    if ($Configuration.SimulationMode -and $AllowRealRead) {
        return New-GroupManagementResult -Success $false -Error "Modos conflitantes: SimulationMode não pode ser combinado com AllowRealRead." -SimulationMode $true
    }
    if ($Preview -or $WhatIfPreference) {
        $previewOnly = New-GroupManagementResult -Success $true -Data ([PSCustomObject]@{ Action=$Action; GroupName=$GroupName; SamAccountName=$SamAccountName; CurrentState="Unknown"; TargetState="Unknown"; CanExecute=$false; RequiresConfirm=$false }) -SimulationMode ([bool]$Configuration.SimulationMode)
        $previewOnly | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        $previewOnly | Add-Member -NotePropertyName Cancelled -NotePropertyValue $false
        return $previewOnly
    }
    if (-not $Configuration.SimulationMode -and -not $AllowRealRead) {
        return New-GroupManagementResult -Success $false -Error "Consulta real bloqueada. Informe -AllowRealRead explicitamente. AllowRealOperation não concede autorização de leitura." -SimulationMode $false
    }

    $groupResult = Get-GroupADInfo `
        -GroupName $GroupName `
        -Configuration $Configuration `
        -AllowRealRead:$AllowRealRead

    if (-not $groupResult.Success) {

        return New-GroupManagementResult `
            -Success $false `
            -Error $groupResult.Error `
            -SimulationMode $groupResult.SimulationMode `
            -QueryStatus $groupResult.QueryStatus
    }

    $membershipResult = Get-GroupMembership `
        -GroupName $GroupName `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -AllowRealRead:$AllowRealRead

    if (-not $membershipResult.Success) {

        return New-GroupManagementResult `
            -Success $false `
            -Error $membershipResult.Error `
            -SimulationMode $membershipResult.SimulationMode `
            -QueryStatus $membershipResult.QueryStatus
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

            $userResult = Get-ADUser `
                -Identity $SamAccountName `
                -Server $domainController `
                -ErrorAction Stop

            $userExists = ($null -ne $userResult)
            $userQueryStatus = if ($userExists) { 'Found' } else { 'NotFound' }
        }
        catch {
            if ($_.Exception.GetType().FullName -eq "Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException") {
                $userExists = $false
                $userQueryStatus = 'NotFound'
            }
            else {
                return New-GroupManagementResult `
                    -Success $false `
                    -Error "Erro ao consultar o usuário '$SamAccountName' no Active Directory: $($_.Exception.Message)" `
                    -SimulationMode $false `
                    -QueryStatus "Error"
            }
        }
    }

    if (-not $userExists) {

        return New-GroupManagementResult `
            -Success $false `
            -Error "Usuário '$SamAccountName' não encontrado." `
            -SimulationMode ([bool]$Configuration.SimulationMode) `
            -QueryStatus $(if ($Configuration.SimulationMode) { 'Simulation' } else { $userQueryStatus })
    }

    $isMember = [bool]$membershipResult.Data.IsMember

    if ($Action -eq "AddMember") {

        if ($isMember) {

            return New-GroupManagementResult `
                -Success $false `
                -Error "Usuário '$SamAccountName' já é membro de '$GroupName'." `
                -SimulationMode ([bool]$Configuration.SimulationMode)
        }

        $actionPreview = [PSCustomObject]@{
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

        $actionPreview = [PSCustomObject]@{
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
        -Data $actionPreview `
        -SimulationMode ([bool]$Configuration.SimulationMode) `
        -QueryStatus $(if ($Configuration.SimulationMode) { 'Simulation' } else { 'Found' })
}

function Invoke-GroupAddMember {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [switch]$Execute,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$AllowRealWrite
    )

    if ($null -eq $Configuration -or $Configuration.SimulationMode -isnot [bool]) {
        return New-GroupManagementResult -Success $false -Error "SimulationMode deve ser definido explicitamente como Boolean." -SimulationMode $false
    }
    if ($Configuration.SimulationMode -and ($AllowRealRead -or $AllowRealWrite)) {
        return New-GroupManagementResult -Success $false -Error "Modos conflitantes: SimulationMode não pode ser combinado com autorização real." -SimulationMode $true
    }
    if ($WhatIfPreference) {
        $whatIf = New-GroupManagementResult -Success $true -Error "Pre-visualização WhatIf; nenhuma consulta ou alteração foi realizada." -SimulationMode $false
        $whatIf | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        $whatIf | Add-Member -NotePropertyName Cancelled -NotePropertyValue $false
        return $whatIf
    }
    if (-not $Configuration.SimulationMode -and -not $AllowRealRead) {
        return New-GroupManagementResult -Success $false -Error "Leitura real bloqueada. Informe -AllowRealRead explicitamente." -SimulationMode $false
    }
    if (-not $Configuration.SimulationMode -and $Execute -and -not $AllowRealWrite) {
        return New-GroupManagementResult -Success $false -Error "Escrita real bloqueada. Informe -AllowRealWrite; Execute e AllowRealOperation não são autorização." -SimulationMode $false
    }
    if (-not $Configuration.SimulationMode -and $Execute -and -not (Invoke-GroupManagementShouldProcess -Cmdlet $PSCmdlet -Target "$GroupName/$SamAccountName" -Action "Adicionar membro ao grupo")) {
        $cancelled = New-GroupManagementResult -Success $false -Error "Operação cancelada pelo ShouldProcess." -SimulationMode $false
        $cancelled | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        $cancelled | Add-Member -NotePropertyName Cancelled -NotePropertyValue $true
        return $cancelled
    }

    $previewResult = Get-GroupManagementPreview `
        -Action "AddMember" `
        -GroupName $GroupName `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -AllowRealRead:$AllowRealRead

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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [object]$Configuration,

        [switch]$Execute,

        [switch]$AllowRealOperation,

        [switch]$AllowRealRead,

        [switch]$AllowRealWrite
    )

    if ($null -eq $Configuration -or $Configuration.SimulationMode -isnot [bool]) {
        return New-GroupManagementResult -Success $false -Error "SimulationMode deve ser definido explicitamente como Boolean." -SimulationMode $false
    }
    if ($Configuration.SimulationMode -and ($AllowRealRead -or $AllowRealWrite)) {
        return New-GroupManagementResult -Success $false -Error "Modos conflitantes: SimulationMode não pode ser combinado com autorização real." -SimulationMode $true
    }
    if ($WhatIfPreference) {
        $whatIf = New-GroupManagementResult -Success $true -Error "Pre-visualização WhatIf; nenhuma consulta ou alteração foi realizada." -SimulationMode $false
        $whatIf | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        $whatIf | Add-Member -NotePropertyName Cancelled -NotePropertyValue $false
        return $whatIf
    }
    if (-not $Configuration.SimulationMode -and -not $AllowRealRead) {
        return New-GroupManagementResult -Success $false -Error "Leitura real bloqueada. Informe -AllowRealRead explicitamente." -SimulationMode $false
    }
    if (-not $Configuration.SimulationMode -and $Execute -and -not $AllowRealWrite) {
        return New-GroupManagementResult -Success $false -Error "Escrita real bloqueada. Informe -AllowRealWrite; Execute e AllowRealOperation não são autorização." -SimulationMode $false
    }
    if (-not $Configuration.SimulationMode -and $Execute -and -not (Invoke-GroupManagementShouldProcess -Cmdlet $PSCmdlet -Target "$GroupName/$SamAccountName" -Action "Remover membro do grupo")) {
        $cancelled = New-GroupManagementResult -Success $false -Error "Operação cancelada pelo ShouldProcess." -SimulationMode $false
        $cancelled | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        $cancelled | Add-Member -NotePropertyName Cancelled -NotePropertyValue $true
        return $cancelled
    }

    $previewResult = Get-GroupManagementPreview `
        -Action "RemoveMember" `
        -GroupName $GroupName `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration `
        -AllowRealRead:$AllowRealRead

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

    if ($null -eq $Configuration -or $Configuration.SimulationMode -isnot [bool]) {
        return New-GroupManagementResult -Success $false -Error "SimulationMode deve ser definido explicitamente como Boolean." -SimulationMode $false
    }
    if ($Configuration.SimulationMode -and $AllowRealRead) {
        return New-GroupManagementResult -Success $false -Error "Modos conflitantes: SimulationMode não pode ser combinado com AllowRealRead." -SimulationMode $true
    }
    if ($Preview -or $WhatIfPreference) {
        $previewResult = New-GroupManagementResult -Success $true -Error "Pré-visualização; nenhuma consulta foi realizada." -SimulationMode ([bool]$Configuration.SimulationMode)
        $previewResult | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        $previewResult | Add-Member -NotePropertyName Cancelled -NotePropertyValue $false
        return $previewResult
    }

    $inventoryResult = Get-GroupInventory `
        -GroupName $GroupName `
        -Configuration $Configuration `
        -AllowRealRead:$AllowRealRead `
        -Preview:$Preview

    if (-not $inventoryResult.Success) {

        return New-GroupManagementResult `
            -Success $false `
            -Error $inventoryResult.Error `
            -SimulationMode $inventoryResult.SimulationMode `
            -QueryStatus $inventoryResult.QueryStatus
    }

    return New-GroupManagementResult `
        -Success $true `
        -Data $inventoryResult.Data `
        -SimulationMode $inventoryResult.SimulationMode `
        -QueryStatus $inventoryResult.QueryStatus
}

function Get-GroupManagementMembers {
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

    if ($null -eq $Configuration -or $Configuration.SimulationMode -isnot [bool]) {
        return New-GroupManagementResult -Success $false -Error "SimulationMode deve ser definido explicitamente como Boolean." -SimulationMode $false
    }
    if ($Configuration.SimulationMode -and $AllowRealRead) {
        return New-GroupManagementResult -Success $false -Error "Modos conflitantes: SimulationMode não pode ser combinado com AllowRealRead." -SimulationMode $true
    }
    if ($Preview -or $WhatIfPreference) {
        $previewResult = New-GroupManagementResult -Success $true -Data @() -Error "Pré-visualização; nenhuma consulta foi realizada." -SimulationMode ([bool]$Configuration.SimulationMode)
        $previewResult | Add-Member -NotePropertyName Mode -NotePropertyValue "Preview"
        $previewResult | Add-Member -NotePropertyName Cancelled -NotePropertyValue $false
        return $previewResult
    }

    $membersResult = Get-GroupMembers `
        -GroupName $GroupName `
        -Configuration $Configuration `
        -AllowRealRead:$AllowRealRead `
        -Preview:$Preview

    if (-not $membersResult.Success) {

        return New-GroupManagementResult `
            -Success $false `
            -Error $membersResult.Error `
            -SimulationMode $membersResult.SimulationMode `
            -QueryStatus $membersResult.QueryStatus
    }

    return New-GroupManagementResult `
        -Success $true `
        -Data @($membersResult.Data) `
        -SimulationMode $membersResult.SimulationMode `
        -QueryStatus $membersResult.QueryStatus
}

Export-ModuleMember -Function `
    Get-GroupManagement, `
    Get-GroupManagementMembers, `
    Get-GroupManagementPreview, `
    Invoke-GroupAddMember, `
    Invoke-GroupRemoveMember
