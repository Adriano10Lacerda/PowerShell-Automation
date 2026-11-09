$ErrorActionPreference = "Stop"

# Caminhos
$ScriptPath = $PSScriptRoot
$ModulePath = Join-Path $ScriptPath "GPO-Functions.psm1"
$GpoModule = $null
$Configuration = [PSCustomObject]@{
    SimulationMode = $true
    ActiveDirectory = [PSCustomObject]@{
        DomainController = ""
        TargetDomain = ""
    }
    GPO = [PSCustomObject]@{
        DefaultDescription = "Automated test GPO"
        RequireDescription = $true
    }
    Operations = [PSCustomObject]@{
        CheckGPO = $true
        ListGPOs = $true
        CreateGPO = $true
        CheckLinks = $true
        ListLinks = $true
    }
    Simulation = [PSCustomObject]@{
        ExistingGPOs = @(
            [PSCustomObject]@{
                Name = "GPO-Desktop-Security"
                DisplayName = "GPO-Desktop-Security"
                Description = "Desktop security policy"
                Links = @("OU=Computers,DC=example,DC=local")
            },
            [PSCustomObject]@{
                Name = "GPO-Office-Standard"
                DisplayName = "GPO-Office-Standard"
                Description = "Office standard policy"
                Links = @("OU=Users,DC=example,DC=local")
            },
            [PSCustomObject]@{
                Name = "GPO-Windows-Update"
                DisplayName = "GPO-Windows-Update"
                Description = "Windows update policy"
                Links = @()
            }
        )
    }
}

$ExistingGPOsProperty = $Configuration.Simulation.PSObject.Properties["ExistingGPOs"]
if ($null -eq $ExistingGPOsProperty -or $null -eq $ExistingGPOsProperty.Value) {
    throw "Simulation.ExistingGPOs deve existir e não pode ser nulo."
}

# Contadores
$TotalTests = 0
$PassedTests = 0
$FailedTests = 0

function Test-Result {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Test
    )

    $script:TotalTests++

    try {

        & $Test

        if ($script:GPOIsolationStubsVerified -eq $true) {
            Assert-GPOExternalCallCountsZero -Scenario $Name
        }

        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:PassedTests++
    }
    catch {

        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Red

        $script:FailedTests++
    }
}

function Copy-GPOTestConfiguration {
    $Configuration | ConvertTo-Json -Depth 10 | ConvertFrom-Json
}

function Get-GPOExternalCallCounts {
    & $GpoModule {
        return $script:GPOExternalCallCounts
    }
}

function Assert-GPOExternalCallCountsZero {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Scenario
    )

    $Counts = Get-GPOExternalCallCounts
    foreach ($Name in $Counts.Keys) {
        if ($Counts[$Name] -ne 0) {
            throw "A fronteira externa '$Name' foi chamada durante '$Scenario' ($($Counts[$Name]) chamada(s))."
        }
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "       Testes - GPO Management" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# TESTE 1 - Arquivo de funções
# ============================================================

Test-Result "Arquivo GPO-Functions.psm1 encontrado" {

    if (-not (Test-Path $ModulePath)) {
        throw "Arquivo GPO-Functions.psm1 não encontrado."
    }
}

# ============================================================
# TESTE 2 - Configuração isolada em memória
# ============================================================

Test-Result "Configuração de teste em memória" {

    if ($Configuration.SimulationMode -isnot [bool] -or $Configuration.SimulationMode -ne $true) {
        throw "A configuração de teste deve habilitar SimulationMode com Boolean true."
    }
}

try {
    if (Get-Module | Where-Object { $_.Path -eq $ModulePath }) {
        throw "O módulo GPO já está carregado nesta sessão; execute a suíte em um processo isolado."
    }

    $GpoModule = Import-Module $ModulePath -PassThru
    if ($null -eq $GpoModule) {
        throw "Não foi possível carregar o módulo GPO para a suíte isolada."
    }

    & $GpoModule {
        $script:GPOExternalCallCounts = [ordered]@{
            GetModule = 0
            ImportModule = 0
            GetGPO = 0
            GetGPOReport = 0
            NewGPO = 0
        }

        Set-Item -Path Function:\script:Get-Module -Value {
            $script:GPOExternalCallCounts.GetModule++
            throw "FAIL-CLOSED: Get-Module não pode ser chamado pela suíte GPO."
        }
        Set-Item -Path Function:\script:Import-Module -Value {
            $script:GPOExternalCallCounts.ImportModule++
            throw "FAIL-CLOSED: Import-Module externo não pode ser chamado pela suíte GPO."
        }

        Set-Item -Path Function:\script:Get-GPO -Value {
            $script:GPOExternalCallCounts.GetGPO++
            throw "FAIL-CLOSED: Get-GPO não pode ser chamado pela suíte de simulação."
        }
        Set-Item -Path Function:\script:Get-GPOReport -Value {
            $script:GPOExternalCallCounts.GetGPOReport++
            throw "FAIL-CLOSED: Get-GPOReport não pode ser chamado pela suíte de simulação."
        }
        Set-Item -Path Function:\script:New-GPO -Value {
            $script:GPOExternalCallCounts.NewGPO++
            throw "FAIL-CLOSED: New-GPO não pode ser chamado pela suíte de simulação."
        }
    }

    & $GpoModule {
        $ModuleName = $ExecutionContext.SessionState.Module.Name
        if ([string]::IsNullOrWhiteSpace($ModuleName)) {
            throw "Não foi possível identificar o módulo GPO durante a validação dos stubs fail-closed."
        }

        foreach ($CommandName in @("Get-Module", "Import-Module", "Get-GPO", "Get-GPOReport", "New-GPO")) {
            $StubPath = "Function:\$CommandName"
            $ScopedStub = Get-Item -LiteralPath $StubPath -ErrorAction Stop
            $ScopedDefinition = [string]$ScopedStub.Definition
            if ([string]::IsNullOrWhiteSpace($ScopedDefinition) -or
                $ScopedDefinition -notmatch "FAIL-CLOSED:") {
                throw "O stub '$CommandName' não está instalado no escopo corrente do módulo ou não contém FAIL-CLOSED."
            }

            $ResolvedCommand = Get-Command -Name $CommandName -CommandType Function -ErrorAction Stop
            $ResolvedDefinition = [string]$ResolvedCommand.Definition
            if ($ResolvedCommand.CommandType -ne [System.Management.Automation.CommandTypes]::Function -or
                $ResolvedCommand.ModuleName -ne $ModuleName -or
                [string]::IsNullOrWhiteSpace($ResolvedDefinition) -or
                $ResolvedDefinition -ne $ScopedDefinition -or
                $ResolvedDefinition -notmatch "FAIL-CLOSED:") {
                throw "A resolução efetiva de '$CommandName' não corresponde ao stub fail-closed instalado no módulo '$ModuleName'."
            }
        }

        if ($null -eq $script:GPOExternalCallCounts) {
            throw "Os contadores dos stubs fail-closed não foram inicializados corretamente."
        }
        foreach ($CounterName in @("GetModule", "ImportModule", "GetGPO", "GetGPOReport", "NewGPO")) {
            if (-not $script:GPOExternalCallCounts.Contains($CounterName)) {
                throw "O contador do stub '$CounterName' não foi inicializado."
            }
        }
    }

    $script:GPOIsolationStubsVerified = $true

# ============================================================
# TESTE 3 - Configuração válida
# ============================================================

Test-Result "Configuração válida" {

    $Result = Test-GPOConfiguration `
        -Configuration $Configuration

    if ($Result -ne $true) {
        throw "A configuração não foi validada."
    }
}

# ============================================================
# TESTE 4 - SimulationMode
# ============================================================

Test-Result "SimulationMode habilitado" {

    if ($Configuration.SimulationMode -ne $true) {
        throw "SimulationMode deveria estar habilitado."
    }
}

# ============================================================
# TESTE 5 - Conectividade simulada
# ============================================================

Test-Result "Simulação não utiliza comandos externos de Group Policy" {

    $null = Get-GPOList -Configuration $Configuration
    Assert-GPOExternalCallCountsZero -Scenario "Simulation"
}

# ============================================================
# TESTE 6 - GPO existente
# ============================================================

Test-Result "Identificar GPO existente" {

    $Result = Test-GPOExists `
        -GPOName "GPO-Desktop-Security" `
        -Configuration $Configuration

    if ($Result.Exists -ne $true) {
        throw "A GPO existente não foi identificada."
    }
}

# ============================================================
# TESTE 7 - GPO inexistente
# ============================================================

Test-Result "Identificar GPO inexistente" {

    $Result = Test-GPOExists `
        -GPOName "GPO-Inexistente" `
        -Configuration $Configuration

    if ($Result.Exists -ne $false) {
        throw "A GPO inexistente foi identificada incorretamente."
    }
}

# ============================================================
# TESTE 8 - Listagem de GPOs
# ============================================================

Test-Result "Listar GPOs" {

    $Result = @(Get-GPOList `
        -Configuration $Configuration)

    if ($Result.Count -lt 3) {
        throw "A listagem deveria retornar pelo menos 3 GPOs."
    }

    if (-not ($Result.Name -contains "GPO-Desktop-Security")) {
        throw "GPO-Desktop-Security não foi encontrada na listagem."
    }

    if (-not ($Result.Name -contains "GPO-Office-Standard")) {
        throw "GPO-Office-Standard não foi encontrada na listagem."
    }

    if (-not ($Result.Name -contains "GPO-Windows-Update")) {
        throw "GPO-Windows-Update não foi encontrada na listagem."
    }
}

# ============================================================
# TESTE 9 - Criação de GPO
# ============================================================

Test-Result "Criar GPO em modo de simulação" {

    $Result = New-GPOProvision `
        -GPOName "GPO-Teste-Automatizado" `
        -Description "GPO criada durante teste automatizado" `
        -Configuration $Configuration

    if ($Result.Success -ne $true) {
        throw "A criação da GPO não retornou Success = True."
    }

    if ($Result.Simulation -ne $true) {
        throw "A criação deveria ocorrer em modo de simulação."
    }
}

# ============================================================
# TESTE 10 - Verificação pós-criação
# ============================================================

Test-Result "Identificar GPO criada" {

    $Result = Test-GPOExists `
        -GPOName "GPO-Teste-Automatizado" `
        -Configuration $Configuration

    if ($Result.Exists -ne $true) {
        throw "A GPO criada não foi encontrada posteriormente."
    }
}

# ============================================================
# TESTE 11 - Impedir criação duplicada
# ============================================================

Test-Result "Impedir criação de GPO duplicada" {

    $ErrorCaptured = $false

    try {

        New-GPOProvision `
            -GPOName "GPO-Teste-Automatizado" `
            -Description "Tentativa duplicada" `
            -Configuration $Configuration | Out-Null
    }
    catch {

        $ErrorCaptured = $true
    }

    if ($ErrorCaptured -ne $true) {
        throw "A criação duplicada deveria ser bloqueada."
    }
}

# ============================================================
# TESTE 12 - GPO com vínculo
# ============================================================

Test-Result "Identificar vínculo de GPO" {

    $Result = @(Get-GPOLinks `
        -GPOName "GPO-Desktop-Security" `
        -Configuration $Configuration)

    if ($Result.Count -ne 1) {
        throw "A GPO deveria possuir exatamente 1 vínculo."
    }

    if ($Result[0].Target -ne "OU=Computers,DC=example,DC=local") {
        throw "O destino do vínculo não corresponde ao esperado."
    }
}

# ============================================================
# TESTE 13 - GPO sem vínculo
# ============================================================

Test-Result "Identificar GPO sem vínculos" {

    $Result = @(Get-GPOLinks `
        -GPOName "GPO-Windows-Update" `
        -Configuration $Configuration)

    if ($Result.Count -ne 0) {
        throw "A GPO deveria possuir zero vínculos."
    }
}

# ============================================================
# TESTE 14 - CheckGPO através da função principal
# ============================================================

Test-Result "CheckGPO através da função principal" {

    $Result = Invoke-GPOManagement `
        -Operation CheckGPO `
        -Configuration $Configuration `
        -GPOName "GPO-Office-Standard"

    if ($Result.Exists -ne $true) {
        throw "A operação CheckGPO não identificou a GPO."
    }
}

# ============================================================
# TESTE 15 - ListGPOs através da função principal
# ============================================================

Test-Result "ListGPOs através da função principal" {

    $Result = @(Invoke-GPOManagement `
        -Operation ListGPOs `
        -Configuration $Configuration)

    if ($Result.Count -lt 3) {
        throw "A operação ListGPOs deveria retornar pelo menos 3 GPOs."
    }
}

# ============================================================
# TESTE 16 - CreateGPO através da função principal
# ============================================================

Test-Result "CreateGPO através da função principal" {

    $Result = Invoke-GPOManagement `
        -Operation CreateGPO `
        -Configuration $Configuration `
        -GPOName "GPO-Teste-Principal" `
        -Description "GPO criada através da função principal"

    if ($Result.Success -ne $true) {
        throw "A operação CreateGPO não retornou sucesso."
    }

    if ($Result.Simulation -ne $true) {
        throw "A operação CreateGPO deveria estar em simulação."
    }
}

# ============================================================
# TESTE 17 - CheckLinks através da função principal
# ============================================================

Test-Result "CheckLinks através da função principal" {

    $Result = @(Invoke-GPOManagement `
        -Operation CheckLinks `
        -Configuration $Configuration `
        -GPOName "GPO-Desktop-Security")

    if ($Result.Count -ne 1) {
        throw "A operação CheckLinks deveria retornar 1 vínculo."
    }
}

# ============================================================
# TESTE 18 - ListLinks através da função principal
# ============================================================

Test-Result "ListLinks através da função principal" {

    $Result = @(Invoke-GPOManagement `
        -Operation ListLinks `
        -Configuration $Configuration `
        -GPOName "GPO-Office-Standard")

    if ($Result.Count -ne 1) {
        throw "A operação ListLinks deveria retornar 1 vínculo."
    }
}

# ============================================================
# TESTE 19 - Bloquear operação em GPO inexistente
# ============================================================

Test-Result "Bloquear consulta de vínculos de GPO inexistente" {

    $ErrorCaptured = $false

    try {

        Get-GPOLinks `
            -GPOName "GPO-Inexistente" `
            -Configuration $Configuration | Out-Null
    }
    catch {

        $ErrorCaptured = $true
    }

    if ($ErrorCaptured -ne $true) {
        throw "A operação deveria bloquear uma GPO inexistente."
    }
}

# ============================================================
# TESTE 20 - Bloquear operação desabilitada
# ============================================================

Test-Result "Bloquear operação desabilitada na configuração" {

    $TestConfiguration = Copy-GPOTestConfiguration

    $TestConfiguration.Operations.CreateGPO = $false

    $ErrorCaptured = $false

    try {

        Invoke-GPOManagement `
            -Operation CreateGPO `
            -Configuration $TestConfiguration `
            -GPOName "GPO-Teste-Bloqueio" `
            -Description "Teste de bloqueio" |
            Out-Null
    }
    catch {

        $ErrorCaptured = $true

        if ($_.Exception.Message -notmatch "está desabilitada") {
            throw "A mensagem de erro não corresponde ao bloqueio esperado."
        }
    }

    if ($ErrorCaptured -ne $true) {
        throw "A operação CreateGPO deveria ter sido bloqueada."
    }
}


# ============================================================
# TESTE 21 - Permitir operação habilitada
# ============================================================

Test-Result "Permitir operação habilitada na configuração" {

    $TestConfiguration = Copy-GPOTestConfiguration

    $TestConfiguration.Operations.CreateGPO = $true

    $Result = Invoke-GPOManagement `
        -Operation CreateGPO `
        -Configuration $TestConfiguration `
        -GPOName "GPO-Teste-Operacao-Habilitada" `
        -Description "Teste de operação habilitada"

    if ($Result.Success -ne $true) {
        throw "A operação CreateGPO deveria ter sido executada."
    }

    if ($Result.Simulation -ne $true) {
        throw "A operação deveria ocorrer em modo de simulação."
    }
}

# ============================================================
# TESTE 22 - Mutator direto respeita a flag
# ============================================================

Test-Result "Bloquear mutator direto com operação desabilitada" {

    $TestConfiguration = Copy-GPOTestConfiguration
    $TestConfiguration.Operations.CreateGPO = $false
    $ErrorCaptured = $false

    try {
        New-GPOProvision `
            -GPOName "GPO-Teste-Direto-Bloqueado" `
            -Description "Teste de autorização direta" `
            -Configuration $TestConfiguration |
            Out-Null
    }
    catch {
        $ErrorCaptured = $_.Exception.Message -match "está desabilitada"
    }

    if (-not $ErrorCaptured) {
        throw "O mutator direto deveria bloquear a operação desabilitada."
    }
}

# ============================================================
# TESTE 23 - Operação real bloqueada por padrão
# ============================================================

Test-Result "Bloquear operação real sem autorização explícita" {

    Assert-GPOExternalCallCountsZero -Scenario "pré-condição de ausência de autorização"
    $TestConfiguration = Copy-GPOTestConfiguration
    $TestConfiguration.SimulationMode = $false
    $TestConfiguration.ActiveDirectory.DomainController = "dc.invalid"
    $TestConfiguration.ActiveDirectory.TargetDomain = "example.invalid"
    $ErrorCaptured = $false

    try {
        New-GPOProvision `
            -GPOName "GPO-Teste-Real-Bloqueado" `
            -Description "Operação real deve ser bloqueada" `
            -Configuration $TestConfiguration |
            Out-Null
    }
    catch {
        $ErrorCaptured = $_.Exception.Message -match "autorização explícita"
    }

    if (-not $ErrorCaptured) {
        throw "A operação real sem -AllowRealOperation deveria ser bloqueada antes de qualquer chamada externa."
    }

    Assert-GPOExternalCallCountsZero -Scenario "ausência de autorização real"
}

# ============================================================
# TESTE 24 - WhatIf não altera a simulação
# ============================================================

Test-Result "WhatIf não altera os fixtures em memória" {

    Assert-GPOExternalCallCountsZero -Scenario "pré-condição WhatIf"
    $TestConfiguration = Copy-GPOTestConfiguration
    $BeforeCount = @($TestConfiguration.Simulation.ExistingGPOs).Count
    $Result = New-GPOProvision `
        -GPOName "GPO-Teste-WhatIf" `
        -Description "Preview sem alteração de estado" `
        -Configuration $TestConfiguration `
        -WhatIf

    if ($Result.Success -ne $false) {
        throw "WhatIf deveria informar que a criação não foi aprovada."
    }

    if (@($TestConfiguration.Simulation.ExistingGPOs).Count -ne $BeforeCount) {
        throw "WhatIf alterou os fixtures em memória."
    }

    Assert-GPOExternalCallCountsZero -Scenario "WhatIf"
}

# ============================================================
# TESTE 25 - Stubs fail-closed nunca acionados
# ============================================================

Test-Result "Nenhum cmdlet externo de Group Policy foi chamado" {

    $Counts = Get-GPOExternalCallCounts
    Assert-GPOExternalCallCountsZero -Scenario "regressão GPO completa"
    Write-Host ("Contadores externos GPO: " + (($Counts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", "))
}

# ============================================================
# RESULTADO
# ============================================================

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "             RESULTADO DOS TESTES" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Total de testes : $TotalTests"
Write-Host "Passaram        : $PassedTests" -ForegroundColor Green
Write-Host "Falharam        : $FailedTests" -ForegroundColor Red

Write-Host ""

if ($FailedTests -eq 0) {

    Write-Host "STATUS: TODOS OS TESTES PASSARAM" -ForegroundColor Green
}
else {

    Write-Host "STATUS: EXISTEM TESTES COM FALHA" -ForegroundColor Red
}
}
finally {
    if ($null -ne $GpoModule) {
        Remove-Module -ModuleInfo $GpoModule -Force -ErrorAction Stop
    }
}

# V1 EXIT CODE HANDLING
if ($FailedTests -gt 0) {
    exit 1
}

exit 0
