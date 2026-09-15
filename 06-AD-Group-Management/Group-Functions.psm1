function Test-ADGroupConfiguration {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    if ($null -eq $Configuration.SimulationMode) {
        $Errors += "A configuração 'SimulationMode' não foi definida."
    }

    if ($null -eq $Configuration.ActiveDirectory) {
        $Errors += "A seção 'ActiveDirectory' não foi definida."
    }

    if ($null -eq $Configuration.Group) {
        $Errors += "A seção 'Group' não foi definida."
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Configuration.Group.DefaultScope)) {
            $Errors += "O 'Group.DefaultScope' não foi definido."
        }

        if ([string]::IsNullOrWhiteSpace($Configuration.Group.DefaultCategory)) {
            $Errors += "O 'Group.DefaultCategory' não foi definido."
        }
    }

    if ($null -eq $Configuration.Operations) {
        $Errors += "A seção 'Operations' não foi definida."
    }

    if ($Configuration.SimulationMode -eq $true) {

        if ($null -eq $Configuration.Simulation) {
            $Errors += "A seção 'Simulation' é obrigatória quando o modo de simulação está habilitado."
        }
        else {
            if ($null -eq $Configuration.Simulation.ExistingGroups) {
                $Errors += "A lista 'Simulation.ExistingGroups' não foi definida."
            }

            if ($null -eq $Configuration.Simulation.ExistingUsers) {
                $Errors += "A lista 'Simulation.ExistingUsers' não foi definida."
            }
        }
    }

    if ($Errors.Count -gt 0) {
        throw ($Errors -join "`n")
    }

    return $true
}


function Test-ADGroupConnectivity {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ($Configuration.SimulationMode -eq $true) {

        return [PSCustomObject]@{
            Connected   = $false
            Simulation  = $true
            Message     = "Modo de simulação ativo. Nenhuma conexão com o Active Directory foi realizada."
        }
    }

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "O módulo 'ActiveDirectory' não está instalado ou disponível neste computador."
    }

    Import-Module ActiveDirectory -ErrorAction Stop

    if ([string]::IsNullOrWhiteSpace($Configuration.ActiveDirectory.DomainController)) {
        throw "O 'DomainController' é obrigatório quando o modo de simulação está desabilitado."
    }

    try {

        $Domain = Get-ADDomain `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop

        return [PSCustomObject]@{
            Connected        = $true
            Simulation       = $false
            Domain           = $Domain.DNSRoot
            DomainController = $Configuration.ActiveDirectory.DomainController
            Message          = "Conexão com o Active Directory validada com sucesso."
        }
    }
    catch {

        throw "Não foi possível conectar ao Active Directory. Detalhes: $($_.Exception.Message)"
    }
}


function Get-SimulatedADGroup {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ($null -eq $Configuration.Simulation) {
        return $null
    }

    return $Configuration.Simulation.ExistingGroups |
        Where-Object { $_.Name -eq $GroupName } |
        Select-Object -First 1
}


function Test-ADGroupExists {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ($Configuration.SimulationMode -eq $true) {

        $Group = Get-SimulatedADGroup `
            -GroupName $GroupName `
            -Configuration $Configuration

        return ($null -ne $Group)
    }

    if (-not (Get-Command Get-ADGroup -ErrorAction SilentlyContinue)) {
        throw "O comando 'Get-ADGroup' não está disponível."
    }

    try {

        Get-ADGroup `
            -Identity $GroupName `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop | Out-Null

        return $true
    }
    catch {

        if ($_.Exception.Message -match "Cannot find an object") {
            return $false
        }

        throw "Não foi possível verificar o grupo '$GroupName'. Detalhes: $($_.Exception.Message)"
    }
}


function Test-ADGroupMember {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ($Configuration.SimulationMode -eq $true) {

        $Group = Get-SimulatedADGroup `
            -GroupName $GroupName `
            -Configuration $Configuration

        if ($null -eq $Group) {

            return [PSCustomObject]@{
                Exists  = $false
                Member  = $false
                Message = "O grupo '$GroupName' não existe."
            }
        }

        $IsMember = $Group.Members -contains $UserName

        return [PSCustomObject]@{
            Exists  = $true
            Member  = $IsMember
            Message = if ($IsMember) {
                "O usuário '$UserName' pertence ao grupo '$GroupName'."
            }
            else {
                "O usuário '$UserName' não pertence ao grupo '$GroupName'."
            }
        }
    }

    try {

        $Members = Get-ADGroupMember `
            -Identity $GroupName `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop

        $Member = $Members | Where-Object {
            $_.SamAccountName -eq $UserName
        }

        return [PSCustomObject]@{
            Exists  = $true
            Member  = ($null -ne $Member)
            Message = if ($null -ne $Member) {
                "O usuário '$UserName' pertence ao grupo '$GroupName'."
            }
            else {
                "O usuário '$UserName' não pertence ao grupo '$GroupName'."
            }
        }
    }
    catch {

        throw "Não foi possível verificar a associação do usuário '$UserName' ao grupo '$GroupName'. Detalhes: $($_.Exception.Message)"
    }
}


function Get-ADGroupMembers {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ($Configuration.SimulationMode -eq $true) {

        $Group = Get-SimulatedADGroup `
            -GroupName $GroupName `
            -Configuration $Configuration

        if ($null -eq $Group) {
            throw "O grupo '$GroupName' não existe."
        }

        $Members = @()

        foreach ($UserName in @($Group.Members)) {

            $Members += [PSCustomObject]@{
                SamAccountName = $UserName
                Name           = $UserName
                ObjectClass    = "user"
            }
        }

        return $Members
    }

    try {

        return @(Get-ADGroupMember `
            -Identity $GroupName `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop)
    }
    catch {

        throw "Não foi possível consultar os membros do grupo '$GroupName'. Detalhes: $($_.Exception.Message)"
    }
}


function New-ADGroupProvision {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ($Configuration.Group.RequireDescription -eq $true) {

        if ([string]::IsNullOrWhiteSpace($Description)) {
            throw "A descrição do grupo é obrigatória."
        }
    }

    if (Test-ADGroupExists `
        -GroupName $GroupName `
        -Configuration $Configuration) {

        throw "O grupo '$GroupName' já existe."
    }

    if ($Configuration.SimulationMode -eq $true) {

        $NewGroup = [PSCustomObject]@{
            Name        = $GroupName
            Description = $Description
            Members     = @()
        }

        $Configuration.Simulation.ExistingGroups += $NewGroup

        return [PSCustomObject]@{
            Success     = $true
            Simulation  = $true
            Operation   = "CreateGroup"
            GroupName   = $GroupName
            Description = $Description
            Scope       = $Configuration.Group.DefaultScope
            Category    = $Configuration.Group.DefaultCategory
            Message     = "Grupo criado na simulação. Nenhuma alteração real foi realizada."
        }
    }

    try {

        $Parameters = @{
            Name          = $GroupName
            Description   = $Description
            GroupScope    = $Configuration.Group.DefaultScope
            GroupCategory = $Configuration.Group.DefaultCategory
            Server        = $Configuration.ActiveDirectory.DomainController
            ErrorAction   = "Stop"
        }

        if (-not [string]::IsNullOrWhiteSpace($Configuration.ActiveDirectory.TargetOU)) {
            $Parameters["Path"] = $Configuration.ActiveDirectory.TargetOU
        }

        New-ADGroup @Parameters

        return [PSCustomObject]@{
            Success     = $true
            Simulation  = $false
            Operation   = "CreateGroup"
            GroupName   = $GroupName
            Description = $Description
            Message     = "Grupo criado com sucesso."
        }
    }
    catch {

        throw "Não foi possível criar o grupo '$GroupName'. Detalhes: $($_.Exception.Message)"
    }
}


function Add-ADGroupMemberProvision {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Group = Get-SimulatedADGroup `
        -GroupName $GroupName `
        -Configuration $Configuration

    if ($Configuration.SimulationMode -eq $true) {

        if ($null -eq $Group) {
            throw "O grupo '$GroupName' não existe."
        }

        if ($Configuration.Simulation.ExistingUsers -notcontains $UserName) {
            throw "O usuário '$UserName' não existe no ambiente de simulação."
        }

        if ($Group.Members -contains $UserName) {
            throw "O usuário '$UserName' já pertence ao grupo '$GroupName'."
        }

        $Group.Members += $UserName

        return [PSCustomObject]@{
            Success    = $true
            Simulation = $true
            Operation  = "AddMember"
            GroupName  = $GroupName
            UserName   = $UserName
            Message    = "Usuário adicionado ao grupo na simulação. Nenhuma alteração real foi realizada."
        }
    }

    if (-not (Test-ADGroupExists `
        -GroupName $GroupName `
        -Configuration $Configuration)) {

        throw "O grupo '$GroupName' não existe."
    }

    try {

        Add-ADGroupMember `
            -Identity $GroupName `
            -Members $UserName `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop

        return [PSCustomObject]@{
            Success    = $true
            Simulation = $false
            Operation  = "AddMember"
            GroupName  = $GroupName
            UserName   = $UserName
            Message    = "Usuário adicionado ao grupo com sucesso."
        }
    }
    catch {

        throw "Não foi possível adicionar o usuário '$UserName' ao grupo '$GroupName'. Detalhes: $($_.Exception.Message)"
    }
}


function Remove-ADGroupMemberProvision {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Group = Get-SimulatedADGroup `
        -GroupName $GroupName `
        -Configuration $Configuration

    if ($Configuration.SimulationMode -eq $true) {

        if ($null -eq $Group) {
            throw "O grupo '$GroupName' não existe."
        }

        if ($Configuration.Simulation.ExistingUsers -notcontains $UserName) {
            throw "O usuário '$UserName' não existe no ambiente de simulação."
        }

        if ($Group.Members -notcontains $UserName) {
            throw "O usuário '$UserName' não pertence ao grupo '$GroupName'."
        }

        $Group.Members = @(
            $Group.Members | Where-Object {
                $_ -ne $UserName
            }
        )

        return [PSCustomObject]@{
            Success    = $true
            Simulation = $true
            Operation  = "RemoveMember"
            GroupName  = $GroupName
            UserName   = $UserName
            Message    = "Usuário removido do grupo na simulação. Nenhuma alteração real foi realizada."
        }
    }

    if (-not (Test-ADGroupExists `
        -GroupName $GroupName `
        -Configuration $Configuration)) {

        throw "O grupo '$GroupName' não existe."
    }

    try {

        Remove-ADGroupMember `
            -Identity $GroupName `
            -Members $UserName `
            -Server $Configuration.ActiveDirectory.DomainController `
            -Confirm:$false `
            -ErrorAction Stop

        return [PSCustomObject]@{
            Success    = $true
            Simulation = $false
            Operation  = "RemoveMember"
            GroupName  = $GroupName
            UserName   = $UserName
            Message    = "Usuário removido do grupo com sucesso."
        }
    }
    catch {

        throw "Não foi possível remover o usuário '$UserName' do grupo '$GroupName'. Detalhes: $($_.Exception.Message)"
    }
}


function Invoke-ADGroupManagement {

    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            "CreateGroup",
            "AddMember",
            "RemoveMember",
            "ListMembers",
            "CheckGroup"
        )]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [string]$UserName,

        [string]$Description
    )

    Test-ADGroupConfiguration -Configuration $Configuration | Out-Null

    if ($Configuration.SimulationMode -eq $false) {
        Test-ADGroupConnectivity -Configuration $Configuration | Out-Null
    }

    switch ($Operation) {

        "CreateGroup" {

            return New-ADGroupProvision `
                -GroupName $GroupName `
                -Description $Description `
                -Configuration $Configuration
        }

        "AddMember" {

            if ([string]::IsNullOrWhiteSpace($UserName)) {
                throw "O UserName é obrigatório para a operação AddMember."
            }

            return Add-ADGroupMemberProvision `
                -GroupName $GroupName `
                -UserName $UserName `
                -Configuration $Configuration
        }

        "RemoveMember" {

            if ([string]::IsNullOrWhiteSpace($UserName)) {
                throw "O UserName é obrigatório para a operação RemoveMember."
            }

            return Remove-ADGroupMemberProvision `
                -GroupName $GroupName `
                -UserName $UserName `
                -Configuration $Configuration
        }

        "ListMembers" {

            return Get-ADGroupMembers `
                -GroupName $GroupName `
                -Configuration $Configuration
        }

        "CheckGroup" {

            $Exists = Test-ADGroupExists `
                -GroupName $GroupName `
                -Configuration $Configuration

            return [PSCustomObject]@{
                GroupName  = $GroupName
                Exists     = $Exists
                Simulation = $Configuration.SimulationMode
            }
        }
    }
}


Export-ModuleMember -Function `
    Test-ADGroupConfiguration, `
    Test-ADGroupConnectivity, `
    Test-ADGroupExists, `
    Test-ADGroupMember, `
    Get-ADGroupMembers, `
    New-ADGroupProvision, `
    Add-ADGroupMemberProvision, `
    Remove-ADGroupMemberProvision, `
    Invoke-ADGroupManagement