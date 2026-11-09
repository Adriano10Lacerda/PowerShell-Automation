function Test-GPOConfiguration {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $Errors = @()

    if ($Configuration.SimulationMode -isnot [bool]) {
        $Errors += "A configuração 'SimulationMode' deve ser um valor Booleano explícito."
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

    foreach ($Operation in @("CheckGPO", "ListGPOs", "CreateGPO", "CheckLinks", "ListLinks")) {

        $OperationFlag = $Configuration.Operations.PSObject.Properties[$Operation]
        if ($null -eq $OperationFlag -or $OperationFlag.Value -isnot [bool]) {
            $Errors += "A flag 'Operations.$Operation' deve existir e ser Booleana."
        }
    }

    if ($Configuration.SimulationMode -eq $true) {
        if ($null -eq $Configuration.Simulation) {
            $Errors += "A seção 'Simulation' é obrigatória quando o modo de simulação está habilitado."
        }
        elseif ($null -eq $Configuration.Simulation.PSObject.Properties["ExistingGPOs"] -or
            $null -eq $Configuration.Simulation.ExistingGPOs) {
            $Errors += "A propriedade 'Simulation.ExistingGPOs' não foi definida ou é nula."
        }
    }

    if ($Errors.Count -gt 0) {
        throw ($Errors -join "`n")
    }

    return $true
}


function Assert-GPOOperationAuthorization {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $true)]
        [ValidateSet("CheckGPO", "ListGPOs", "CreateGPO", "CheckLinks", "ListLinks")]
        [string]$Operation,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRealOperation
    )

    Test-GPOConfiguration -Configuration $Configuration | Out-Null

    if ($Configuration.Operations.$Operation -ne $true) {
        throw "A operação '$Operation' está desabilitada na configuração."
    }

    if ($Configuration.SimulationMode -eq $false) {
        if (-not $AllowRealOperation) {
            throw "A operação real '$Operation' exige a autorização explícita -AllowRealOperation."
        }

        if ([string]::IsNullOrWhiteSpace($Configuration.ActiveDirectory.DomainController) -or
            [string]::IsNullOrWhiteSpace($Configuration.ActiveDirectory.TargetDomain)) {
            throw "DomainController e TargetDomain são obrigatórios para operações reais."
        }
    }
}


function Initialize-GPOConnection {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    if ($Configuration.SimulationMode) {
        throw "A conexão com Group Policy não pode ser inicializada em modo de simulação."
    }

    if (-not (Get-Module -ListAvailable -Name GroupPolicy)) {
        throw "O módulo 'GroupPolicy' não está disponível. Instale as ferramentas de gerenciamento de Group Policy."
    }

    try {

        Import-Module GroupPolicy -ErrorAction Stop

        return $true

    }
    catch {

        throw "Não foi possível carregar o módulo GroupPolicy. Detalhes: $($_.Exception.Message)"
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


function Test-GPOExistsInternal {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $true)]
        [ValidateSet("CheckGPO", "CreateGPO", "CheckLinks", "ListLinks")]
        [string]$Operation,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRealOperation
    )

    if ([string]::IsNullOrWhiteSpace($GPOName)) {
        throw "O nome da GPO é obrigatório."
    }

    Assert-GPOOperationAuthorization -Configuration $Configuration -Operation $Operation -AllowRealOperation:$AllowRealOperation

    if ($Configuration.SimulationMode) {

        $GPO = Get-SimulatedGPO `
            -Configuration $Configuration `
            -GPOName $GPOName

        return [PSCustomObject]@{
            Exists     = ($null -ne $GPO)
            Simulation = $true
            Name       = $GPOName
        }
    }

    Initialize-GPOConnection -Configuration $Configuration | Out-Null

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


function Test-GPOExists {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRealOperation
    )

    Assert-GPOOperationAuthorization -Configuration $Configuration -Operation CheckGPO -AllowRealOperation:$AllowRealOperation
    Test-GPOExistsInternal -GPOName $GPOName -Configuration $Configuration -Operation CheckGPO -AllowRealOperation:$AllowRealOperation
}


function Get-GPOList {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRealOperation
    )

    Assert-GPOOperationAuthorization -Configuration $Configuration -Operation ListGPOs -AllowRealOperation:$AllowRealOperation

    if ($Configuration.SimulationMode) {

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

    Initialize-GPOConnection -Configuration $Configuration | Out-Null

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

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $false)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRealOperation
    )

    Assert-GPOOperationAuthorization -Configuration $Configuration -Operation CreateGPO -AllowRealOperation:$AllowRealOperation

    if ([string]::IsNullOrWhiteSpace($GPOName)) {
        throw "O nome da GPO é obrigatório."
    }

    if ($Configuration.GPO.RequireDescription -eq $true) {

        if ([string]::IsNullOrWhiteSpace($Description)) {
            throw "A descrição da GPO é obrigatória."
        }
    }

    $Target = "GPO '$GPOName'"
    $Action = if ($Configuration.SimulationMode) { "Criar GPO simulada" } else { "Criar GPO no domínio" }
    if (-not $PSCmdlet.ShouldProcess($Target, $Action)) {
        return [PSCustomObject]@{
            Success     = $false
            Simulation  = $Configuration.SimulationMode
            Name        = $GPOName
            Description = $Description
            Message     = "A criação não foi aprovada por ShouldProcess; nenhuma consulta ou alteração foi realizada."
        }
    }

    $Existing = Test-GPOExistsInternal `
        -GPOName $GPOName `
        -Configuration $Configuration `
        -Operation CreateGPO `
        -AllowRealOperation:$AllowRealOperation

    if ($Existing.Exists -eq $true) {
        throw "A GPO '$GPOName' já existe."
    }

    if ($Configuration.SimulationMode) {

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

    Initialize-GPOConnection -Configuration $Configuration | Out-Null

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


function Get-GPOLinksInternal {

    param (
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $true)]
        [ValidateSet("CheckLinks", "ListLinks")]
        [string]$Operation,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRealOperation
    )

    Assert-GPOOperationAuthorization -Configuration $Configuration -Operation $Operation -AllowRealOperation:$AllowRealOperation

    if ([string]::IsNullOrWhiteSpace($GPOName)) {
        throw "O nome da GPO é obrigatório."
    }

    $Existing = Test-GPOExistsInternal `
        -GPOName $GPOName `
        -Configuration $Configuration `
        -Operation $Operation `
        -AllowRealOperation:$AllowRealOperation

    if ($Existing.Exists -eq $false) {
        throw "A GPO '$GPOName' não existe."
    }

    if ($Configuration.SimulationMode) {

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

    Initialize-GPOConnection -Configuration $Configuration | Out-Null

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


function Get-GPOLinks {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$GPOName,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRealOperation
    )

    Get-GPOLinksInternal -GPOName $GPOName -Configuration $Configuration -Operation CheckLinks -AllowRealOperation:$AllowRealOperation
}


function Invoke-GPOManagement {

    [CmdletBinding(SupportsShouldProcess = $true)]
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
        [string]$Description,

        [Parameter(Mandatory = $false)]
        [switch]$AllowRealOperation
    )

    Assert-GPOOperationAuthorization -Configuration $Configuration -Operation $Operation -AllowRealOperation:$AllowRealOperation

    switch ($Operation) {

        "CheckGPO" {

            return Test-GPOExists `
                -GPOName $GPOName `
                -Configuration $Configuration `
                -AllowRealOperation:$AllowRealOperation
        }

        "ListGPOs" {

            return Get-GPOList `
                -Configuration $Configuration `
                -AllowRealOperation:$AllowRealOperation
        }

        "CreateGPO" {

            $CreateParameters = @{
                GPOName            = $GPOName
                Description        = $Description
                Configuration      = $Configuration
                AllowRealOperation = $AllowRealOperation
            }
            if ($PSBoundParameters.ContainsKey("WhatIf")) {
                $CreateParameters["WhatIf"] = $WhatIf
            }
            if ($PSBoundParameters.ContainsKey("Confirm")) {
                $CreateParameters["Confirm"] = $Confirm
            }
            return New-GPOProvision @CreateParameters
        }

        "CheckLinks" {

            return Get-GPOLinks `
                -GPOName $GPOName `
                -Configuration $Configuration `
                -AllowRealOperation:$AllowRealOperation
        }

        "ListLinks" {

            if ([string]::IsNullOrWhiteSpace($GPOName)) {
                throw "O nome da GPO é obrigatório para listar os vínculos."
            }

            return Get-GPOLinksInternal `
                -GPOName $GPOName `
                -Configuration $Configuration `
                -Operation ListLinks `
                -AllowRealOperation:$AllowRealOperation
        }
    }
}


Export-ModuleMember -Function `
    Test-GPOConfiguration,
    Test-GPOExists,
    Get-GPOList,
    New-GPOProvision,
    Get-GPOLinks,
    Invoke-GPOManagement