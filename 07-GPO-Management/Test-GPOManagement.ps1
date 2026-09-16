$ErrorActionPreference = "Stop"

# Caminhos
$ScriptPath = $PSScriptRoot
$ModulePath = Join-Path $ScriptPath "GPO-Functions.psm1"
$ConfigPath = Join-Path $ScriptPath "GPO-Configuration.json"

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

        Write-Host "[PASS] $Name" -ForegroundColor Green
        $script:PassedTests++
    }
    catch {

        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor Red

        $script:FailedTests++
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
# TESTE 2 - Arquivo de configuração
# ============================================================

Test-Result "Arquivo GPO-Configuration.json encontrado" {

    if (-not (Test-Path $ConfigPath)) {
        throw "Arquivo GPO-Configuration.json não encontrado."
    }
}

# Importar módulo
Import-Module $ModulePath -Force

# Carregar configuração
$Configuration = Get-Content $ConfigPath -Raw | ConvertFrom-Json

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

Test-Result "Conectividade em modo de simulação" {

    $Result = Test-GPOConnectivity `
        -Configuration $Configuration

    if ($Result.Simulation -ne $true) {
        throw "O resultado deveria indicar Simulation = True."
    }

    if ($Result.Connected -ne $false) {
        throw "Connected deveria ser False no modo de simulação."
    }
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

    $TestConfiguration = $Configuration.PSObject.Copy()

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

    $TestConfiguration = $Configuration.PSObject.Copy()

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