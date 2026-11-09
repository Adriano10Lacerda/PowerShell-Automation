
# ============================================
# Testes - AD User Provisioning
# ============================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "AD-Functions.psm1"

if (-not (Test-Path $ModulePath)) {
    throw "Módulo não encontrado: $ModulePath"
}

Import-Module $ModulePath -Force

function New-TestConfiguration {
    param (
        [bool]$SimulationMode = $true
    )

    $RealOperationEnabled = -not $SimulationMode

    return [PSCustomObject]@{
        Domain           = "example.test"
        DomainController = "dc.example.test"
        TargetOU         = "OU=Test,DC=example,DC=test"
        SimulationMode   = $SimulationMode
        Operations       = [PSCustomObject]@{
            CreateUser = $RealOperationEnabled
        }
        RealOperations   = [PSCustomObject]@{
            Enabled    = $RealOperationEnabled
            Operations = [PSCustomObject]@{
                CreateUser = $RealOperationEnabled
            }
        }
        UserValidation   = [PSCustomObject]@{
            FirstName = [PSCustomObject]@{ MinLength = 2 }
            LastName  = [PSCustomObject]@{ MinLength = 2 }
        }
        UserPrincipalName = [PSCustomObject]@{
            Enabled = $true
            Domain  = "example.test"
        }
        Simulation       = [PSCustomObject]@{
            ExistingSamAccountNames = @(
                "silva.maria.ext",
                "silva.maria2.ext",
                "silva.maria3.ext"
            )
        }
        SamAccountName   = [PSCustomObject]@{
            Enabled       = $true
            MaxLength     = 20
            RemoveAccents = $true
        }
        DuplicateHandling = [PSCustomObject]@{
            Enabled  = $true
            Strategy = "Increment"
        }
        LongNamePolicy = [PSCustomObject]@{
            Enabled  = $true
            Strategy = "Manual"
        }
        UserTypes = [PSCustomObject]@{
            Employee = [PSCustomObject]@{
                Description = "Employee"
                Format      = "LastName.FirstName"
                Suffix      = ""
            }
            Contractor = [PSCustomObject]@{
                Description = "Contractor"
                Format      = "LastName.FirstName"
                Suffix      = ".ext"
            }
            Intern = [PSCustomObject]@{
                Description = "Intern"
                Format      = "LastName.FirstName"
                Suffix      = ".est"
            }
        }
    }
}

$Configuration = New-TestConfiguration

$Passed = 0
$Failed = 0
$Total = 0

# ============================================
# Função auxiliar para executar testes
# ============================================

function Invoke-Test {
    param (
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [scriptblock]$Test
    )

    $script:Total++

    try {
        & $Test

        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:Passed++
    }
    catch {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Red
        $script:Failed++
    }
}

# ============================================
# Função auxiliar para validar erros esperados
# ============================================

function Assert-Throws {
    param (
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [Parameter(Mandatory)]
        [string]$ExpectedMessage
    )

    $CaughtError = $null

    try {
        & $Action
    }
    catch {
        $CaughtError = $_
    }

    if ($null -eq $CaughtError) {
        throw "Era esperado um erro contendo: '$ExpectedMessage', mas nenhum erro foi gerado."
    }

    if ($CaughtError.Exception.Message -notmatch $ExpectedMessage) {
        throw "Mensagem de erro inesperada. Esperado: '$ExpectedMessage'. Recebido: '$($CaughtError.Exception.Message)'"
    }
}

# ============================================
# 1. Configuração
# ============================================

Invoke-Test "Configuração atual é válida" {
    Test-ADConfiguration -Configuration $Configuration | Out-Null
}

Invoke-Test "SimulationMode está habilitado" {
    if ($Configuration.SimulationMode -ne $true) {
        throw "SimulationMode deveria estar habilitado."
    }
}
Invoke-Test "SimulationMode com tipo inválido é rejeitado" {
    $InvalidConfiguration = $Configuration.PSObject.Copy()
    $InvalidConfiguration.SimulationMode = "true"

    Assert-Throws -ExpectedMessage "SimulationMode" -Action {
        Test-ADConfiguration -Configuration $InvalidConfiguration | Out-Null
    }
}

Invoke-Test "Tipos de usuário estão configurados" {
    $UserTypes = @(
        $Configuration.UserTypes.PSObject.Properties.Name
    )

    if ($UserTypes.Count -lt 3) {
        throw "Era esperado pelo menos 3 tipos de usuário."
    }
}

# ============================================
# 2. Validação de usuário
# ============================================

Invoke-Test "Usuário válido é aceito" {
    Test-ADUserProvisioning `
        -FirstName "Maria" `
        -LastName "Silva" `
        -SamAccountName "silva.maria" `
        -Configuration $Configuration | Out-Null
}

Invoke-Test "Primeiro nome vazio é rejeitado" {
    Assert-Throws -ExpectedMessage "primeiro nome" -Action {
        Test-ADUserProvisioning `
            -FirstName " " `
            -LastName "Silva" `
            -SamAccountName "silva.maria" `
            -Configuration $Configuration | Out-Null
    }
}

Invoke-Test "Sobrenome vazio é rejeitado" {
    Assert-Throws -ExpectedMessage "sobrenome" -Action {
        Test-ADUserProvisioning `
            -FirstName "Maria" `
            -LastName " " `
            -SamAccountName "maria" `
            -Configuration $Configuration | Out-Null
    }
}

Invoke-Test "SamAccountName com caracteres inválidos é rejeitado" {
    Assert-Throws -ExpectedMessage "caracteres inválidos" -Action {
        Test-ADUserProvisioning `
            -FirstName "Maria" `
            -LastName "Silva" `
            -SamAccountName "silva maria" `
            -Configuration $Configuration | Out-Null
    }
}

Invoke-Test "SamAccountName acima do limite é rejeitado" {
    $LongSam = "abcdefghijklmnopqrstu"

    Assert-Throws -ExpectedMessage "mais de" -Action {
        Test-ADUserProvisioning `
            -FirstName "Maria" `
            -LastName "Silva" `
            -SamAccountName $LongSam `
            -Configuration $Configuration | Out-Null
    }
}

# ============================================
# 3. Geração de SamAccountName
# ============================================

Invoke-Test "Employee gera SamAccountName correto" {
    $Result = Get-ADSamAccountName `
        -FirstName "Maria" `
        -LastName "Silva" `
        -UserType "Employee" `
        -Configuration $Configuration

    if ($Result -ne "silva.maria") {
        throw "Resultado inesperado: $Result"
    }
}

Invoke-Test "Contractor aplica sufixo corretamente" {
    $Result = Get-ADSamAccountName `
        -FirstName "Maria" `
        -LastName "Silva" `
        -UserType "Contractor" `
        -Configuration $Configuration

    if ($Result -ne "silva.maria.ext") {
        throw "Resultado inesperado: $Result"
    }
}

Invoke-Test "Intern aplica sufixo corretamente" {
    $Result = Get-ADSamAccountName `
        -FirstName "Andre" `
        -LastName "Oliveira" `
        -UserType "Intern" `
        -Configuration $Configuration

    if ($Result -ne "oliveira.andre.est") {
        throw "Resultado inesperado: $Result"
    }
}

Invoke-Test "Acentos são removidos" {
    $Result = Get-ADSamAccountName `
        -FirstName "João" `
        -LastName "Gonçalves" `
        -UserType "Employee" `
        -Configuration $Configuration

    if ($Result -ne "goncalves.joao") {
        throw "Resultado inesperado: $Result"
    }
}

Invoke-Test "Tipo de usuário inexistente é rejeitado" {
    Assert-Throws -ExpectedMessage "não está configurado" -Action {
        Get-ADSamAccountName `
            -FirstName "Maria" `
            -LastName "Silva" `
            -UserType "Unknown" `
            -Configuration $Configuration | Out-Null
    }
}

# ============================================
# 4. Duplicidade
# ============================================

Invoke-Test "SamAccountName disponível permanece igual" {
    $Result = Get-UniqueADSamAccountName `
        -SamAccountName "novo.usuario" `
        -Configuration $Configuration `
        -ExistingSamAccountNames @(
            "silva.maria.ext"
        )

    if ($Result -ne "novo.usuario") {
        throw "Resultado inesperado: $Result"
    }
}

Invoke-Test "Duplicidade gera próximo SamAccountName disponível" {
    $Result = Get-UniqueADSamAccountName `
        -SamAccountName "silva.maria.ext" `
        -Configuration $Configuration `
        -ExistingSamAccountNames @(
            "silva.maria.ext",
            "silva.maria2.ext",
            "silva.maria3.ext"
        )

    if ($Result -ne "silva.maria4.ext") {
        throw "Resultado inesperado: $Result"
    }
}

Invoke-Test "Duplicidade respeita limite de caracteres" {
    $Result = Get-UniqueADSamAccountName `
        -SamAccountName "abcdefghijklmno.ext" `
        -Configuration $Configuration `
        -ExistingSamAccountNames @(
            "abcdefghijklmno.ext"
        )

    if ($Result.Length -gt $Configuration.SamAccountName.MaxLength) {
        throw "SamAccountName excedeu o limite configurado."
    }
}

# ============================================
# 5. Nomes longos
# ============================================

Invoke-Test "Nome longo dispara política Manual" {
    Assert-Throws -ExpectedMessage "ultrapassa o limite" -Action {
        Get-ADSamAccountName `
            -FirstName "Alexandre" `
            -LastName "Nascimentosilva" `
            -UserType "Contractor" `
            -Configuration $Configuration | Out-Null
    }
}

# ============================================
# 6. Conectividade
# ============================================

Invoke-Test "Modo de simulação não conecta ao AD" {
    $Result = Test-ADConnectivity -Configuration $Configuration

    if ($Result.Simulation -ne $true) {
        throw "O resultado deveria indicar Simulation = true."
    }

    if ($Result.Connected -ne $false) {
        throw "SimulationMode não deveria indicar conexão real."
    }
}

# ============================================
# 7. Provisionamento em simulação
# ============================================

Invoke-Test "Provisionamento simulado não realiza alteração real" {
    $User = [PSCustomObject]@{
        FirstName         = "Maria"
        LastName          = "Silva"
        DisplayName       = "Maria Silva"
        UserType          = "Employee"
        SamAccountName    = "maria.silva.test"
        UserPrincipalName = "maria.silva.test@example.test"
    }

    $Result = New-ADUserProvision `
        -User $User `
        -Configuration $Configuration

    if ($Result.Success -ne $true) {
        throw "Provisionamento simulado deveria retornar Success = true."
    }

    if ($Result.Simulation -ne $true) {
        throw "Resultado deveria indicar Simulation = true."
    }

    if ($Result.SamAccountName -ne $User.SamAccountName) {
        throw "SamAccountName retornado não corresponde ao usuário."
    }
}

# ============================================
# 8. Validação de segurança do provisionamento
# ============================================

Invoke-Test "UPN vazio é rejeitado quando o recurso está habilitado" {

    $User = [PSCustomObject]@{
        FirstName         = "Maria"
        LastName          = "Silva"
        DisplayName       = "Maria Silva"
        UserType          = "Employee"
        SamAccountName    = "maria.silva.test"
        UserPrincipalName = $null
    }

    Assert-Throws -ExpectedMessage "UserPrincipalName não pode estar vazio" -Action {
        New-ADUserProvision `
            -User $User `
            -Configuration $Configuration | Out-Null
    }
}

Invoke-Test "UPN com domínio diferente do configurado é rejeitado" {

    $User = [PSCustomObject]@{
        FirstName         = "Maria"
        LastName          = "Silva"
        DisplayName       = "Maria Silva"
        UserType          = "Employee"
        SamAccountName    = "maria.silva.test"
        UserPrincipalName = "maria.silva.test@outro.local"
    }

    Assert-Throws -ExpectedMessage "deve corresponder" -Action {
        New-ADUserProvision `
            -User $User `
            -Configuration $Configuration | Out-Null
    }
}

Invoke-Test "SamAccountName inválido é rejeitado no provisionamento direto" {

    $User = [PSCustomObject]@{
        FirstName         = "Maria"
        LastName          = "Silva"
        DisplayName       = "Maria Silva"
        UserType          = "Employee"
        SamAccountName    = "maria silva"
        UserPrincipalName = "maria silva@example.local"
    }

    Assert-Throws -ExpectedMessage "caracteres inválidos" -Action {
        New-ADUserProvision `
            -User $User `
            -Configuration $Configuration | Out-Null
    }
}

Invoke-Test "Provisionamento aceita UPN desabilitado" {

    $TestConfiguration = $Configuration |
        ConvertTo-Json -Depth 100 |
        ConvertFrom-Json

    $TestConfiguration.UserPrincipalName.Enabled = $false

    $User = [PSCustomObject]@{
        FirstName         = "Maria"
        LastName          = "Silva"
        DisplayName       = "Maria Silva"
        UserType          = "Employee"
        SamAccountName    = "maria.silva.test"
        UserPrincipalName = $null
    }

    $Result = New-ADUserProvision `
        -User $User `
        -Configuration $TestConfiguration

    if ($Result.Success -ne $true) {
        throw "O provisionamento deveria ser aceito com UPN desabilitado."
    }

    if ($Result.Simulation -ne $true) {
        throw "O resultado deveria indicar modo de simulação."
    }
}

Invoke-Test "Tipo inexistente é rejeitado no provisionamento direto" {

    $User = [PSCustomObject]@{
        FirstName         = "Maria"
        LastName          = "Silva"
        DisplayName       = "Maria Silva"
        UserType          = "InvalidUserType"
        SamAccountName    = "maria.silva.test"
        UserPrincipalName = "maria.silva.test@example.local"
    }

    Assert-Throws `
        -ExpectedMessage "não encontrado na configuração" `
        -Action {
            New-ADUserProvision `
                -User $User `
                -Configuration $Configuration | Out-Null
        }
}

# ============================================
# 9. Proteções de operações reais isoladas
# ============================================

$ADFunctionsModule = Get-Module -Name "AD-Functions"

& $ADFunctionsModule {
    $script:ADUserIsolationCounters = [PSCustomObject]@{
        ModuleLookups = 0
        ModuleImports = 0
        Connectivity  = 0
        DomainQueries = 0
        Existence     = 0
        Users         = 0
        WriteStubCalls = 0
    }

    function script:Get-Module {
        # AD_USER_ISOLATION_STUB:Get-Module
        param (
            [switch]$ListAvailable,
            [string]$Name
        )

        $script:ADUserIsolationCounters.ModuleLookups++
        throw "Isolated AD test blocked unexpected Get-Module access for '$Name'."
    }

    function script:Import-Module {
        [CmdletBinding()]
        # AD_USER_ISOLATION_STUB:Import-Module
        param (
            [string]$Name
        )

        $script:ADUserIsolationCounters.ModuleImports++
        throw "Isolated AD test blocked unexpected Import-Module access for '$Name'."
    }

    function script:Get-ADDomain {
        [CmdletBinding()]
        # AD_USER_ISOLATION_STUB:Get-ADDomain
        param (
            [string]$Server
        )

        $script:ADUserIsolationCounters.DomainQueries++
        throw "Isolated AD test blocked unexpected Get-ADDomain query."
    }

    function script:Get-ADUser {
        [CmdletBinding()]
        # AD_USER_ISOLATION_STUB:Get-ADUser
        param (
            [string]$Identity,
            [string]$Server
        )

        $script:ADUserIsolationCounters.Users++
        return $null
    }

    function script:New-ADUser {
        [CmdletBinding()]
        # AD_USER_ISOLATION_STUB:New-ADUser
        param (
            [string]$Name,
            [string]$GivenName,
            [string]$Surname,
            [string]$DisplayName,
            [string]$SamAccountName,
            [string]$Path,
            [string]$Server,
            [bool]$Enabled,
            [string]$UserPrincipalName,
            [switch]$PassThru
        )

        $script:ADUserIsolationCounters.WriteStubCalls++
        return [PSCustomObject]@{
            SamAccountName    = $SamAccountName
            DistinguishedName = "CN=$Name,$Path"
        }
    }

    function script:Test-ADConnectivity {
        [CmdletBinding()]
        # AD_USER_ISOLATION_STUB:Test-ADConnectivity
        param (
            [PSCustomObject]$Configuration,
            [switch]$AllowRealOperation
        )

        $script:ADUserIsolationCounters.Connectivity++
        return [PSCustomObject]@{
            Connected  = $true
            Simulation = $false
        }
    }

    function script:Test-ADUserExists {
        [CmdletBinding()]
        # AD_USER_ISOLATION_STUB:Test-ADUserExists
        param (
            [string]$SamAccountName,
            [PSCustomObject]$Configuration,
            [switch]$AllowRealOperation
        )

        $script:ADUserIsolationCounters.Existence++
        return $false
    }

    function script:Assert-ADUserIsolationStubsActive {
        $RequiredFunctions = @(
            "Get-Module",
            "Import-Module",
            "Get-ADDomain",
            "Get-ADUser",
            "New-ADUser",
            "Test-ADConnectivity",
            "Test-ADUserExists"
        )

        foreach ($FunctionName in $RequiredFunctions) {
            try {
                $ResolvedFunction = Get-Command `
                    -Name $FunctionName `
                    -CommandType Function `
                    -ErrorAction Stop
            }
            catch {
                throw "Isolated AD test refused to run: required function stub '$FunctionName' could not be resolved in module scope. $($_.Exception.Message)"
            }

            if (
                $null -eq $ResolvedFunction -or
                $ResolvedFunction.CommandType -ne [System.Management.Automation.CommandTypes]::Function -or
                -not $ResolvedFunction.ScriptBlock.ToString().Contains(
                    "AD_USER_ISOLATION_STUB:$FunctionName"
                )
            ) {
                throw "Isolated AD test refused to run: resolved command '$FunctionName' is not the required module-scope test function."
            }
        }
    }
}

$RealConfiguration = New-TestConfiguration -SimulationMode:$false
$RealUser = [PSCustomObject]@{
    FirstName         = "Maria"
    LastName          = "Silva"
    DisplayName       = "Maria Silva"
    UserType          = "Employee"
    SamAccountName    = "silva.maria"
    UserPrincipalName = "silva.maria@example.test"
}

function Get-ADUserIsolationCounters {
    return (& $ADFunctionsModule {
        $script:ADUserIsolationCounters
    })
}

function Assert-ADUserIsolationStubsActive {
    & $ADFunctionsModule {
        Assert-ADUserIsolationStubsActive
    }
}

function Reset-ADUserIsolationCounters {
    & $ADFunctionsModule {
        foreach ($Property in $script:ADUserIsolationCounters.PSObject.Properties) {
            $Property.Value = 0
        }
    }
}

function Assert-NoADUserExternalCalls {
    $Counters = Get-ADUserIsolationCounters

    foreach ($CounterName in @(
        "ModuleLookups",
        "ModuleImports",
        "Connectivity",
        "DomainQueries",
        "Existence",
        "Users",
        "WriteStubCalls"
    )) {
        if ($Counters.$CounterName -ne 0) {
            throw "A chamada externa '$CounterName' não deveria ter ocorrido."
        }
    }
}

Invoke-Test "Chamadas diretas a consultas AD bloqueiam sem autorização" {
    Assert-Throws -ExpectedMessage "-AllowRealOperation" -Action {
        Test-ADConnectivity -Configuration $RealConfiguration | Out-Null
    }

    Assert-Throws -ExpectedMessage "-AllowRealOperation" -Action {
        Test-ADUserExists `
            -SamAccountName $RealUser.SamAccountName `
            -Configuration $RealConfiguration | Out-Null
    }

    Assert-Throws -ExpectedMessage "-AllowRealOperation" -Action {
        Get-UniqueADSamAccountName `
            -SamAccountName $RealUser.SamAccountName `
            -Configuration $RealConfiguration | Out-Null
    }

    Assert-NoADUserExternalCalls
}

Invoke-Test "Gates ausentes ou inválidos bloqueiam antes das consultas" {
    $AuthorizationCases = @(
        [PSCustomObject]@{
            Expected = "SimulationMode.*booleano"
            Update   = { param($Config) $Config.SimulationMode = "false" }
        },
        [PSCustomObject]@{
            Expected = "RealOperations.Enabled.*true"
            Update   = { param($Config) $Config.RealOperations.Enabled = $null }
        },
        [PSCustomObject]@{
            Expected = "Operations.CreateUser.*true"
            Update   = { param($Config) $Config.Operations.CreateUser = $null }
        },
        [PSCustomObject]@{
            Expected = "RealOperations.Operations.CreateUser.*true"
            Update   = { param($Config) $Config.RealOperations.Operations.CreateUser = $null }
        }
    )

    foreach ($AuthorizationCase in $AuthorizationCases) {
        $TestConfiguration = $RealConfiguration |
            ConvertTo-Json -Depth 100 |
            ConvertFrom-Json
        $UpdateConfiguration = $AuthorizationCase.Update
        & $UpdateConfiguration $TestConfiguration | Out-Null

        Assert-Throws `
            -ExpectedMessage $AuthorizationCase.Expected `
            -Action {
                New-ADUserProvision `
                    -User $RealUser `
                    -Configuration $TestConfiguration `
                    -AllowRealOperation | Out-Null
            }
    }

    Assert-Throws -ExpectedMessage "-AllowRealOperation" -Action {
        New-ADUserProvision `
            -User $RealUser `
            -Configuration $RealConfiguration | Out-Null
    }

    Assert-NoADUserExternalCalls
}

Invoke-Test "WhatIf autorizado não consulta nem escreve e informa não realização" {
    Assert-ADUserIsolationStubsActive
    Reset-ADUserIsolationCounters

    $Result = New-ADUserProvision `
        -User $RealUser `
        -Configuration $RealConfiguration `
        -AllowRealOperation `
        -WhatIf

    if (
        $Result.Success -ne $false -or
        $Result.Performed -ne $false -or
        $Result.Simulation -ne $false -or
        $Result.Message -notmatch "não realizado"
    ) {
        throw "A recusa de ShouldProcess via WhatIf deve retornar resultado explícito de não realização."
    }

    Assert-NoADUserExternalCalls
}

Invoke-Test "WhatIf sem AllowRealOperation retorna preview sem AD" {
    Assert-ADUserIsolationStubsActive
    Reset-ADUserIsolationCounters

    $Result = New-ADUserProvision `
        -User $RealUser `
        -Configuration $RealConfiguration `
        -WhatIf

    if (
        $Result.Success -ne $false -or
        $Result.Performed -ne $false -or
        $Result.Simulation -ne $false -or
        $Result.Message -notmatch "não realizado"
    ) {
        throw "WhatIf sem autorização deve informar explicitamente que nada foi realizado."
    }

    Assert-NoADUserExternalCalls
}

Invoke-Test "WhatIf adicional retorna não realizado quando ShouldProcess recusa" {
    Assert-ADUserIsolationStubsActive
    Reset-ADUserIsolationCounters

    $Result = New-ADUserProvision `
        -User $RealUser `
        -Configuration $RealConfiguration `
        -AllowRealOperation `
        -WhatIf

    if (
        $Result.Success -ne $false -or
        $Result.Performed -ne $false -or
        $Result.Simulation -ne $false -or
        $Result.Message -notmatch "não realizado"
    ) {
        throw "ShouldProcess recusado deve informar que a operação real não foi realizada."
    }

    Assert-NoADUserExternalCalls
}

Invoke-Test "SimulationMode true bloqueia operação real mesmo com todos os gates ativos" {
    Assert-ADUserIsolationStubsActive
    Reset-ADUserIsolationCounters

    $FullyAuthorizedSimulationConfiguration = New-TestConfiguration
    $FullyAuthorizedSimulationConfiguration.RealOperations.Enabled = $true
    $FullyAuthorizedSimulationConfiguration.Operations.CreateUser = $true
    $FullyAuthorizedSimulationConfiguration.RealOperations.Operations.CreateUser = $true

    $Result = New-ADUserProvision `
        -User $RealUser `
        -Configuration $FullyAuthorizedSimulationConfiguration `
        -AllowRealOperation

    if ($Result.Success -ne $true -or $Result.Simulation -ne $true) {
        throw "SimulationMode true deve preservar o resultado de simulação, não executar a operação real."
    }

    if ($Result.PSObject.Properties.Name -contains "Performed" -and $Result.Performed -ne $false) {
        throw "O resultado de simulação não pode indicar que uma operação real foi realizada."
    }

    Assert-NoADUserExternalCalls
}

Invoke-Test "WhatIf em simulação preserva o comportamento sem estado real" {
    $SimulationConfiguration = New-TestConfiguration
    $SimulationConfiguration.PSObject.Properties.Remove("Operations")
    $SimulationConfiguration.PSObject.Properties.Remove("RealOperations")
    $Before = @($SimulationConfiguration.Simulation.ExistingSamAccountNames)

    Test-ADConfiguration -Configuration $SimulationConfiguration | Out-Null

    $Result = New-ADUserProvision `
        -User $RealUser `
        -Configuration $SimulationConfiguration `
        -WhatIf

    if ($Result.Simulation -ne $true -or $Result.Success -ne $true) {
        throw "O comportamento de simulação existente não foi preservado."
    }

    if (
        (Compare-Object `
            -ReferenceObject $Before `
            -DifferenceObject $SimulationConfiguration.Simulation.ExistingSamAccountNames).Count -gt 0
    ) {
        throw "O estado simulado foi alterado."
    }

    Assert-NoADUserExternalCalls
}

Invoke-Test "Autorização válida percorre fluxo isolado com ShouldProcess aceito" {
    Assert-ADUserIsolationStubsActive
    Reset-ADUserIsolationCounters

    $Result = New-ADUserProvision `
        -User $RealUser `
        -Configuration $RealConfiguration `
        -AllowRealOperation `
        -Confirm:$false

    if ($Result.Success -ne $true -or $Result.Simulation -ne $false) {
        throw "O fluxo isolado autorizado não concluiu conforme esperado."
    }

    $Counters = Get-ADUserIsolationCounters
    if (
        $Counters.Connectivity -ne 1 -or
        $Counters.Existence -ne 1 -or
        $Counters.WriteStubCalls -ne 1
    ) {
        throw "Os stubs de conectividade, existência e escrita não foram chamados uma vez."
    }

    if ($Counters.ModuleImports -ne 0 -or $Counters.ModuleLookups -ne 0) {
        throw "O fluxo isolado tentou localizar ou carregar o módulo ActiveDirectory."
    }

    if ($Counters.DomainQueries -ne 0 -or $Counters.Users -ne 0) {
        throw "O fluxo isolado alcançou comandos de consulta ActiveDirectory que deveriam estar bloqueados."
    }
}

Invoke-Test "Identificador único real usa somente o stub de consulta" {
    Assert-ADUserIsolationStubsActive
    Reset-ADUserIsolationCounters

    $Result = Get-UniqueADSamAccountName `
        -SamAccountName "silva.maria" `
        -Configuration $RealConfiguration `
        -AllowRealOperation

    if ($Result -ne "silva.maria") {
        throw "O identificador retornado pelo fluxo controlado é inesperado."
    }

    $Counters = Get-ADUserIsolationCounters
    if ($Counters.Users -ne 1) {
        throw "A consulta de usuários deveria ter sido encaminhada ao stub uma vez."
    }

    if (
        $Counters.ModuleImports -ne 0 -or
        $Counters.ModuleLookups -ne 0 -or
        $Counters.DomainQueries -ne 0 -or
        $Counters.Connectivity -ne 0 -or
        $Counters.Existence -ne 0 -or
        $Counters.WriteStubCalls -ne 0
    ) {
        throw "A consulta isolada tentou importar o módulo ou alcançar outro caminho ActiveDirectory."
    }
}

Invoke-Test "Cada função direta bloqueia sem autorização" {
    Reset-ADUserIsolationCounters

    $DirectCalls = @(
        [PSCustomObject]@{
            Name = "Test-ADConnectivity"
            Action = {
                param($Config)
                Test-ADConnectivity -Configuration $Config | Out-Null
            }
        },
        [PSCustomObject]@{
            Name = "Test-ADUserExists"
            Action = {
                param($Config)
                Test-ADUserExists `
                    -SamAccountName $RealUser.SamAccountName `
                    -Configuration $Config | Out-Null
            }
        },
        [PSCustomObject]@{
            Name = "Get-UniqueADSamAccountName"
            Action = {
                param($Config)
                Get-UniqueADSamAccountName `
                    -SamAccountName $RealUser.SamAccountName `
                    -Configuration $Config | Out-Null
            }
        },
        [PSCustomObject]@{
            Name = "New-ADUserProvision"
            Action = {
                param($Config)
                New-ADUserProvision `
                    -User $RealUser `
                    -Configuration $Config | Out-Null
            }
        }
    )

    foreach ($DirectCall in $DirectCalls) {
        Assert-Throws -ExpectedMessage "-AllowRealOperation" -Action {
            & $DirectCall.Action $RealConfiguration
        }
    }

    Assert-NoADUserExternalCalls
}

Invoke-Test "SimulationMode ausente ou inválido bloqueia todas as funções diretas" {
    $InvalidModes = @(
        [PSCustomObject]@{
            Name = "ausente"
            Update = {
                param($Config)
                $Config.PSObject.Properties.Remove("SimulationMode")
            }
            Message = "SimulationMode.*booleano"
        },
        [PSCustomObject]@{
            Name = "texto"
            Update = {
                param($Config)
                $Config.SimulationMode = "false"
            }
            Message = "SimulationMode.*booleano"
        }
    )

    foreach ($InvalidMode in $InvalidModes) {
        $TestConfiguration = $RealConfiguration |
            ConvertTo-Json -Depth 100 |
            ConvertFrom-Json
        $UpdateConfiguration = $InvalidMode.Update
        & $UpdateConfiguration $TestConfiguration | Out-Null

        $DirectCalls = @(
            { param($Config) Test-ADConnectivity -Configuration $Config -AllowRealOperation | Out-Null },
            { param($Config) Test-ADUserExists -SamAccountName $RealUser.SamAccountName -Configuration $Config -AllowRealOperation | Out-Null },
            { param($Config) Get-UniqueADSamAccountName -SamAccountName $RealUser.SamAccountName -Configuration $Config -AllowRealOperation | Out-Null },
            { param($Config) New-ADUserProvision -User $RealUser -Configuration $Config -AllowRealOperation | Out-Null }
        )

        foreach ($DirectCall in $DirectCalls) {
            Assert-Throws -ExpectedMessage $InvalidMode.Message -Action {
                & $DirectCall $TestConfiguration
            }
        }
    }

    Assert-NoADUserExternalCalls
}

Invoke-Test "Cada gate de autorização ausente ou falso bloqueia todas as funções diretas" {
    $GateCases = @(
        [PSCustomObject]@{
            Name = "RealOperations.Enabled ausente"
            Update = { param($Config) $Config.RealOperations.PSObject.Properties.Remove("Enabled") }
            Message = "RealOperations.Enabled.*true"
        },
        [PSCustomObject]@{
            Name = "RealOperations ausente"
            Update = { param($Config) $Config.PSObject.Properties.Remove("RealOperations") }
            Message = "seção 'RealOperations'"
        },
        [PSCustomObject]@{
            Name = "RealOperations.Operations ausente"
            Update = { param($Config) $Config.RealOperations.PSObject.Properties.Remove("Operations") }
            Message = "seção 'RealOperations.Operations'"
        },
        [PSCustomObject]@{
            Name = "RealOperations.Enabled falso"
            Update = { param($Config) $Config.RealOperations.Enabled = $false }
            Message = "RealOperations.Enabled.*true"
        },
        [PSCustomObject]@{
            Name = "Operations ausente"
            Update = { param($Config) $Config.PSObject.Properties.Remove("Operations") }
            Message = "seção 'Operations'"
        },
        [PSCustomObject]@{
            Name = "Operations.CreateUser ausente"
            Update = { param($Config) $Config.Operations.PSObject.Properties.Remove("CreateUser") }
            Message = "Operations.CreateUser.*true"
        },
        [PSCustomObject]@{
            Name = "Operations.CreateUser falso"
            Update = { param($Config) $Config.Operations.CreateUser = $false }
            Message = "Operations.CreateUser.*true"
        },
        [PSCustomObject]@{
            Name = "RealOperations.Operations.CreateUser ausente"
            Update = { param($Config) $Config.RealOperations.Operations.PSObject.Properties.Remove("CreateUser") }
            Message = "RealOperations.Operations.CreateUser.*true"
        },
        [PSCustomObject]@{
            Name = "RealOperations.Operations.CreateUser falso"
            Update = { param($Config) $Config.RealOperations.Operations.CreateUser = $false }
            Message = "RealOperations.Operations.CreateUser.*true"
        }
    )

    foreach ($GateCase in $GateCases) {
        $TestConfiguration = $RealConfiguration |
            ConvertTo-Json -Depth 100 |
            ConvertFrom-Json
        $UpdateConfiguration = $GateCase.Update
        & $UpdateConfiguration $TestConfiguration | Out-Null

        $DirectCalls = @(
            { param($Config) Test-ADConnectivity -Configuration $Config -AllowRealOperation | Out-Null },
            { param($Config) Test-ADUserExists -SamAccountName $RealUser.SamAccountName -Configuration $Config -AllowRealOperation | Out-Null },
            { param($Config) Get-UniqueADSamAccountName -SamAccountName $RealUser.SamAccountName -Configuration $Config -AllowRealOperation | Out-Null },
            { param($Config) New-ADUserProvision -User $RealUser -Configuration $Config -AllowRealOperation | Out-Null }
        )

        foreach ($DirectCall in $DirectCalls) {
            Assert-Throws -ExpectedMessage $GateCase.Message -Action {
                & $DirectCall $TestConfiguration
            }
        }
    }

    Assert-NoADUserExternalCalls
}

function Invoke-IsolatedProvisionEntrypoint {
    param (
        [Parameter(Mandatory)]
        [hashtable]$EntryParameters
    )

    $EntryScriptPath = Join-Path $PSScriptRoot "Provision-ADUser.ps1"
    $EntryConfiguration = New-TestConfiguration -SimulationMode:$false

    return & {
        param (
            $ScriptPath,
            $ConfigurationForEntry
        )

        $EntryState = [PSCustomObject]@{
            PathChecks          = 0
            ConfigurationReads = 0
            ImportCalls         = 0
            Connectivity        = 0
            UniqueNameQueries   = 0
            ProvisionCalls      = 0
            ShouldProcessCalls  = 0
            Writes              = 0
            ReadHostCalls       = 0
        }

        function Test-Path {
            param ([string]$Path)
            $EntryState.PathChecks++
            return $true
        }

        function Get-Content {
            param (
                [string]$Path,
                [switch]$Raw
            )

            $EntryState.ConfigurationReads++
            return ConvertTo-Json -InputObject $ConfigurationForEntry -Depth 100
        }

        function Import-Module {
            [CmdletBinding()]
            param (
                [string]$Name,
                [switch]$Force
            )

            $EntryState.ImportCalls++
        }

        function Test-ADConfiguration {
            param ([PSCustomObject]$Configuration)
            return $true
        }

        function Assert-ADRealOperationAuthorization {
            param (
                [PSCustomObject]$Configuration,
                [bool]$AllowRealOperation
            )

            if (-not $AllowRealOperation) {
                throw "O entrypoint não encaminhou -AllowRealOperation."
            }
        }

        function Test-ADConnectivity {
            param (
                [PSCustomObject]$Configuration,
                [switch]$AllowRealOperation
            )

            $EntryState.Connectivity++
            return [PSCustomObject]@{
                Connected  = $true
                Simulation = $false
                Message    = "Stub de conectividade."
            }
        }

        function Get-UniqueADSamAccountName {
            param (
                [string]$SamAccountName,
                [PSCustomObject]$Configuration,
                [switch]$AllowRealOperation
            )

            $EntryState.UniqueNameQueries++
            return $SamAccountName
        }

        function New-ADUserProvision {
            [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
            param (
                [PSCustomObject]$User,
                [PSCustomObject]$Configuration,
                [switch]$AllowRealOperation
            )

            $EntryState.ProvisionCalls++
            $EntryState.ShouldProcessCalls++

            if (-not $PSCmdlet.ShouldProcess(
                $Configuration.TargetOU,
                "Criar usuário $($User.SamAccountName)"
            )) {
                return [PSCustomObject]@{
                    Success        = $false
                    Simulation     = $false
                    Performed      = $false
                    SamAccountName = $User.SamAccountName
                    Message        = "Provisionamento não realizado."
                }
            }

            $EntryState.Writes++
            return [PSCustomObject]@{
                Success        = $true
                Simulation     = $false
                Performed      = $true
                SamAccountName = $User.SamAccountName
                Message        = "Provisionamento realizado pelo stub."
            }
        }

        function Read-Host {
            param ([string]$Prompt)
            $EntryState.ReadHostCalls++

            switch ($EntryState.ReadHostCalls) {
                1 { return "Maria" }
                2 { return "Silva" }
                3 { return "1" }
                default { throw "Read-Host inesperado no cenário isolado." }
            }
        }

        . $ScriptPath @EntryParameters

        return [PSCustomObject]@{
            Counters = $EntryState
            Result   = $ProvisioningResult
        }
    } $EntryScriptPath $EntryConfiguration
}

Invoke-Test "Entrypoint WhatIf sem autorização não consulta AD nem escreve" {
    $EntryResult = Invoke-IsolatedProvisionEntrypoint -EntryParameters @{
        WhatIf = $true
    }

    if ($EntryResult.Counters.Connectivity -ne 0) {
        throw "O entrypoint consultou conectividade durante WhatIf."
    }

    if ($EntryResult.Counters.UniqueNameQueries -ne 0) {
        throw "O entrypoint consultou disponibilidade do SamAccountName durante WhatIf."
    }

    if ($EntryResult.Counters.Writes -ne 0) {
        throw "O stub de escrita foi executado durante WhatIf."
    }

    if (
        $EntryResult.Result.Success -ne $false -or
        $EntryResult.Result.Performed -ne $false -or
        $EntryResult.Result.Message -notmatch "não realizado"
    ) {
        throw "O resultado do entrypoint não informou explicitamente que a operação não foi realizada."
    }

    if ($EntryResult.Counters.ProvisionCalls -ne 1 -or $EntryResult.Counters.ShouldProcessCalls -ne 1) {
        throw "WhatIf deveria chegar uma vez ao ShouldProcess do mutador."
    }

    if ($EntryResult.Counters.ConfigurationReads -ne 1 -or $EntryResult.Counters.ImportCalls -ne 1) {
        throw "A configuração em memória ou o stub de importação não foi usado como esperado."
    }
}

Invoke-Test "Entrypoint não duplica ShouldProcess e Confirm falso segue o fluxo isolado" {
    $EntryScriptPath = Join-Path $PSScriptRoot "Provision-ADUser.ps1"
    $Tokens = $null
    $ParseErrors = $null
    $EntryAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $EntryScriptPath,
        [ref]$Tokens,
        [ref]$ParseErrors
    )

    if ($ParseErrors.Count -gt 0) {
        throw "O entrypoint contém erros de sintaxe."
    }

    $DispatcherShouldProcessCalls = @(
        $EntryAst.FindAll(
            {
                param($Node)

                $Node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $Node.Member -is [System.Management.Automation.Language.StringConstantExpressionAst] -and
                $Node.Member.Value -eq "ShouldProcess"
            },
            $true
        )
    )

    if ($DispatcherShouldProcessCalls.Count -ne 0) {
        throw "O entrypoint não deve chamar ShouldProcess; a confirmação pertence ao mutador."
    }

    $EntryResult = Invoke-IsolatedProvisionEntrypoint -EntryParameters @{
        AllowRealOperation = $true
        Confirm            = $false
    }

    if (
        $EntryResult.Counters.Connectivity -ne 1 -or
        $EntryResult.Counters.UniqueNameQueries -ne 1
    ) {
        throw "O fluxo confirmado sem prompt não percorreu os stubs de consulta esperados."
    }

    if ($EntryResult.Counters.ProvisionCalls -ne 1 -or $EntryResult.Counters.ShouldProcessCalls -ne 1) {
        throw "A operação deveria passar por um único ShouldProcess no mutador."
    }

    if ($EntryResult.Counters.Writes -ne 1) {
        throw "O stub de escrita deveria ser chamado uma vez com Confirm:$false."
    }
}

# O prompt interativo de -Confirm:$true não é acionado na suíte isolada.
# A recusa determinística é coberta pelo ShouldProcess real com -WhatIf; não há
# um mecanismo seguro no escopo desta suíte para injetar uma resposta "N" ao prompt.

# ============================================
# Resultado final
# ============================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "       RESULTADO DOS TESTES - MODULO 03" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total de testes : $Total"
Write-Host "Passaram        : $Passed" -ForegroundColor Green
Write-Host "Falharam        : $Failed" -ForegroundColor Red
Write-Host ""

if ($Failed -eq 0) {
    Write-Host "STATUS: TODOS OS TESTES PASSARAM" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "STATUS: EXISTEM TESTES COM FALHA" -ForegroundColor Red
    exit 1
}
