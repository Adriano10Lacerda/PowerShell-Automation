function Test-GPOConfiguration {

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

    if ($null -eq $Configuration.GPO) {
        $Errors += "A seção 'GPO' não foi definida."
    }

    if ($null -eq $Configuration.Operations) {
        $Errors += "A seção 'Operations' não foi definida."
    }

    if ($Configuration.SimulationMode -eq $true) {

        if ($null -eq $Configuration.Simulation) {
            $Errors += "A seção 'Simulation' é obrigatória quando o modo de simulação está habilitado."
        }

        elseif ($null -eq $Configuration.Simulation.ExistingGPOs) {
            $Errors += "A propriedade 'Simulation.ExistingGPOs' não foi definida."
        }
    }

    if ($Errors.Count -gt 0) {
        throw ($Errors -join "`n")
    }

    return $true
}


function Test-GPOConnectivity {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ($Configuration.SimulationMode -eq $true) {

        return [PSCustomObject]@{
            Connected  = $false
            Simulation = $true
            Message    = "Modo de simulação ativo. Nenhuma conexão com Active Directory foi realizada."
        }
    }

    if ([string]::IsNullOrWhiteSpace($Configuration.ActiveDirectory.DomainController)) {
        throw "O DomainController é obrigatório quando o modo de simulação está desabilitado."
    }

    if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
        throw "O módulo 'GroupPolicy' não está disponível. Instale as ferramentas de gerenciamento de Group Policy."
    }

    try {

        Import-Module GroupPolicy -ErrorAction Stop

        $Domain = Get-GPO `
            -All `
            -Domain $Configuration.ActiveDirectory.TargetDomain `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop

        return [PSCustomObject]@{
            Connected  = $true
            Simulation = $false
            Domain     = $Configuration.ActiveDirectory.TargetDomain
            Message    = "Conexão com Active Directory validada com sucesso."
        }

    }
    catch {

        throw "Não foi possível validar a conexão com Active Directory/GPO. Detalhes: $($_.Exception.Message)"
    }
}


function Get-SimulatedGPO {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$GPOName
    )

    if ($null -eq $Configuration.Simulation.ExistingGPOs) {
        return $null
    }

    foreach ($GPO in $Configuration.Simulation.ExistingGPOs) {

        if ($GPO.Name -eq $GPOName) {
            return $GPO
        }
    }

    return $null
}


function Test-GPOExists {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ([string]::IsNullOrWhiteSpace($GPOName)) {
        throw "O nome da GPO é obrigatório."
    }

    if ($Configuration.SimulationMode -eq $true) {

        $GPO = Get-SimulatedGPO `
            -Configuration $Configuration `
            -GPOName $GPOName

        return [PSCustomObject]@{
            Exists     = ($null -ne $GPO)
            Simulation = $true
            Name       = $GPOName
        }
    }

    Test-GPOConnectivity -Configuration $Configuration | Out-Null

    try {

        $GPO = Get-GPO `
            -Name $GPOName `
            -Domain $Configuration.ActiveDirectory.TargetDomain `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop

        return [PSCustomObject]@{
            Exists     = ($null -ne $GPO)
            Simulation = $false
            Name       = $GPOName
            DisplayName = $GPO.DisplayName
            Id         = $GPO.Id
        }

    }
    catch {

        if ($_.Exception.Message -match "not found" -or
            $_.Exception.Message -match "não foi encontrado" -or
            $_.Exception.Message -match "Cannot find") {

            return [PSCustomObject]@{
                Exists     = $false
                Simulation = $false
                Name       = $GPOName
            }
        }

        throw "Não foi possível verificar a GPO '$GPOName'. Detalhes: $($_.Exception.Message)"
    }
}


function Get-GPOList {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ($Configuration.SimulationMode -eq $true) {

        if ($null -eq $Configuration.Simulation.ExistingGPOs) {
            return @()
        }

        return @(
            foreach ($GPO in $Configuration.Simulation.ExistingGPOs) {

                [PSCustomObject]@{
                    Name        = $GPO.Name
                    DisplayName = $GPO.DisplayName
                    Description = $GPO.Description
                    Links       = @($GPO.Links).Count
                    Simulation  = $true
                }
            }
        )
    }

    Test-GPOConnectivity -Configuration $Configuration | Out-Null

    try {

        $GPOs = Get-GPO `
            -All `
            -Domain $Configuration.ActiveDirectory.TargetDomain `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop

        return @(
            foreach ($GPO in $GPOs) {

                [PSCustomObject]@{
                    Name        = $GPO.DisplayName
                    DisplayName = $GPO.DisplayName
                    Description = $GPO.Description
                    Id          = $GPO.Id
                    Simulation  = $false
                }
            }
        )
    }
    catch {

        throw "Não foi possível listar as GPOs. Detalhes: $($_.Exception.Message)"
    }
}


function New-GPOProvision {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ([string]::IsNullOrWhiteSpace($GPOName)) {
        throw "O nome da GPO é obrigatório."
    }

    if ($Configuration.GPO.RequireDescription -eq $true) {

        if ([string]::IsNullOrWhiteSpace($Description)) {
            throw "A descrição da GPO é obrigatória."
        }
    }

    $Existing = Test-GPOExists `
        -GPOName $GPOName `
        -Configuration $Configuration

    if ($Existing.Exists -eq $true) {
        throw "A GPO '$GPOName' já existe."
    }

    if ($Configuration.SimulationMode -eq $true) {

        $NewGPO = [PSCustomObject]@{
            Name        = $GPOName
            DisplayName = $GPOName
            Description = $Description
            Links       = @()
        }

        $Configuration.Simulation.ExistingGPOs += $NewGPO

        return [PSCustomObject]@{
            Success     = $true
            Simulation  = $true
            Name        = $GPOName
            Description = $Description
            Message     = "GPO criada em modo de simulação. Nenhuma alteração real foi realizada."
        }
    }

    Test-GPOConnectivity -Configuration $Configuration | Out-Null

    try {

        $Parameters = @{
            Name        = $GPOName
            Domain      = $Configuration.ActiveDirectory.TargetDomain
            Server      = $Configuration.ActiveDirectory.DomainController
            ErrorAction = "Stop"
        }

        if (-not [string]::IsNullOrWhiteSpace($Description)) {
            $Parameters["Comment"] = $Description
        }

        $NewGPO = New-GPO @Parameters

        return [PSCustomObject]@{
            Success     = $true
            Simulation  = $false
            Name        = $NewGPO.DisplayName
            Description = $NewGPO.Description
            Id          = $NewGPO.Id
            Message     = "GPO criada com sucesso no Active Directory."
        }
    }
    catch {

        throw "Não foi possível criar a GPO '$GPOName'. Detalhes: $($_.Exception.Message)"
    }
}


function Get-GPOLinks {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Existing = Test-GPOExists `
        -GPOName $GPOName `
        -Configuration $Configuration

    if ($Existing.Exists -eq $false) {
        throw "A GPO '$GPOName' não existe."
    }

    if ($Configuration.SimulationMode -eq $true) {

        $GPO = Get-SimulatedGPO `
            -Configuration $Configuration `
            -GPOName $GPOName

        if ($null -eq $GPO.Links -or $GPO.Links.Count -eq 0) {
            return @()
        }

        return @(
            foreach ($Link in $GPO.Links) {

                [PSCustomObject]@{
                    GPOName    = $GPO.Name
                    Target     = $Link
                    Simulation = $true
                }
            }
        )
    }

    Test-GPOConnectivity -Configuration $Configuration | Out-Null

    try {

        $GPO = Get-GPO `
            -Name $GPOName `
            -Domain $Configuration.ActiveDirectory.TargetDomain `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop

        $Report = Get-GPOReport `
            -Guid $GPO.Id `
            -ReportType Xml `
            -Domain $Configuration.ActiveDirectory.TargetDomain `
            -Server $Configuration.ActiveDirectory.DomainController `
            -ErrorAction Stop

        [xml]$XmlReport = $Report

        $Links = @(
            $XmlReport.GPO.LinksTo | ForEach-Object {
                $_.SOMPath
            }
        )

        return @(
            foreach ($Link in $Links) {

                [PSCustomObject]@{
                    GPOName    = $GPO.DisplayName
                    Target     = $Link
                    Simulation = $false
                }
            }
        )
    }
    catch {

        throw "Não foi possível consultar os vínculos da GPO '$GPOName'. Detalhes: $($_.Exception.Message)"
    }
}


function Invoke-GPOManagement {

    param (
        [Parameter(Mandatory = $true)]
        [ValidateSet(
            "CheckGPO",
            "ListGPOs",
            "CreateGPO",
            "CheckLinks",
            "ListLinks"
        )]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $false)]
        [string]$GPOName,

        [Parameter(Mandatory = $false)]
        [string]$Description
    )

    Test-GPOConfiguration `
        -Configuration $Configuration |
        Out-Null

    # Verificar se a operação está habilitada
    if ($null -eq $Configuration.Operations) {
        throw "A seção 'Operations' não foi definida na configuração."
    }

    if ($Configuration.Operations.$Operation -ne $true) {
        throw "A operação '$Operation' está desabilitada na configuração."
    }

    switch ($Operation) {

        "CheckGPO" {

            return Test-GPOExists `
                -GPOName $GPOName `
                -Configuration $Configuration
        }

        "ListGPOs" {

            return Get-GPOList `
                -Configuration $Configuration
        }

        "CreateGPO" {

            return New-GPOProvision `
                -GPOName $GPOName `
                -Description $Description `
                -Configuration $Configuration
        }

        "CheckLinks" {

            return Get-GPOLinks `
                -GPOName $GPOName `
                -Configuration $Configuration
        }

        "ListLinks" {

            if ([string]::IsNullOrWhiteSpace($GPOName)) {
                throw "O nome da GPO é obrigatório para listar os vínculos."
            }

            return Get-GPOLinks `
                -GPOName $GPOName `
                -Configuration $Configuration
        }
    }
}


Export-ModuleMember -Function `
    Test-GPOConfiguration,
    Test-GPOConnectivity,
    Test-GPOExists,
    Get-GPOList,
    New-GPOProvision,
    Get-GPOLinks,
    Invoke-GPOManagement