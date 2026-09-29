# ============================================
# Test-EntraProvisioning.ps1
# Testes do módulo Entra ID User Provisioning
# ============================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "Entra-Functions.psm1"
$ConfigPath = Join-Path $PSScriptRoot "Entra-Configuration.example.json"

# ============================================
# CARREGAR MÓDULO
# ============================================

Import-Module $ModulePath -Force

# ============================================
# CARREGAR CONFIGURAÇÃO
# ============================================

$Config = Get-Content $ConfigPath -Raw |
    ConvertFrom-Json

# ============================================
# CONFIGURAÇÃO DE TESTE
# ============================================
# Os testes nunca devem depender do modo real
# configurado no ambiente do usuário.

$TestConfig = $Config | ConvertTo-Json -Depth 20 |
    ConvertFrom-Json

$TestConfig.SimulationMode = $true

$TestConfig.Simulation.ExistingUserPrincipalNames = @(
    "maria.silva@example.onmicrosoft.com",
    "joao.santos@example.onmicrosoft.com"
)

# ============================================
# CONTADORES
# ============================================

$TotalTests = 0
$PassedTests = 0
$FailedTests = 0

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "   TESTES - ENTRA ID USER PROVISIONING" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Módulo carregado: OK" -ForegroundColor Green
Write-Host "Configuração carregada: OK" -ForegroundColor Green
Write-Host "Ambiente de teste: SIMULAÇÃO" -ForegroundColor Yellow
Write-Host ""

# ============================================
# TESTE 1 - VALIDAÇÃO DA CONFIGURAÇÃO
# ============================================

Write-Host "Teste 1 - Validação da configuração" -ForegroundColor Yellow

$TotalTests++

try {

    Test-EntraConfiguration `
        -Configuration $TestConfig |
        Out-Null

    $PassedTests++

    Write-Host "PASSOU - Configuração válida." -ForegroundColor Green
}
catch {

    $FailedTests++

    Write-Host "FALHOU - Configuração inválida." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""

# ============================================
# TESTE 2 - USUÁRIO VÁLIDO
# ============================================

Write-Host "Teste 2 - Validação de usuário válido" -ForegroundColor Yellow

$TotalTests++

$UserValid = [PSCustomObject]@{
    FirstName         = "Carlos"
    LastName          = "Oliveira"
    DisplayName       = "Carlos Oliveira"
    UserPrincipalName = "carlos.oliveira@example.onmicrosoft.com"
    MailNickname      = "carlos.oliveira"
    JobTitle          = "Analista de Infraestrutura"
    Department        = "Tecnologia"
    AccountEnabled    = $true
}

try {

    Test-EntraUserProvisioning `
        -User $UserValid `
        -Configuration $TestConfig |
        Out-Null

    $PassedTests++

    Write-Host "PASSOU - Usuário válido." -ForegroundColor Green
}
catch {

    $FailedTests++

    Write-Host "FALHOU - Usuário válido foi rejeitado." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""

# ============================================
# TESTE 2.1 - VALIDAÇÃO DE ACCOUNTENABLED
# ============================================

Write-Host "Teste 2.1 - Validação de AccountEnabled" -ForegroundColor Yellow

$AccountEnabledTests = @(
    @{
        Name = "Valor booleano true"
        Value = $true
        IncludeProperty = $true
        ExpectedValid = $true
    }
    @{
        Name = "Valor booleano false"
        Value = $false
        IncludeProperty = $true
        ExpectedValid = $true
    }
    @{
        Name = "Texto false"
        Value = "false"
        IncludeProperty = $true
        ExpectedValid = $false
    }
    @{
        Name = "Valor nulo"
        Value = $null
        IncludeProperty = $true
        ExpectedValid = $false
    }
    @{
        Name = "Propriedade ausente"
        Value = $null
        IncludeProperty = $false
        ExpectedValid = $false
    }
)

foreach ($Case in $AccountEnabledTests) {

    $TotalTests++

    $TestUser = [PSCustomObject]@{
        FirstName         = "Carlos"
        LastName          = "Oliveira"
        DisplayName       = "Carlos Oliveira"
        UserPrincipalName = "carlos.oliveira@example.onmicrosoft.com"
        MailNickname      = "carlos.oliveira"
        JobTitle          = "Analista"
        Department        = "Tecnologia"
    }

    if ($Case.IncludeProperty) {
        $TestUser | Add-Member `
            -MemberType NoteProperty `
            -Name "AccountEnabled" `
            -Value $Case.Value
    }

    try {

        Test-EntraUserProvisioning `
            -User $TestUser `
            -Configuration $TestConfig |
            Out-Null

        if ($Case.ExpectedValid) {

            $PassedTests++

            Write-Host "PASSOU - $($Case.Name)" -ForegroundColor Green
        }
        else {

            $FailedTests++

            Write-Host "FALHOU - $($Case.Name) foi aceito indevidamente." `
                -ForegroundColor Red
        }
    }
    catch {

        if (-not $Case.ExpectedValid -and
            $_.Exception.Message -match "AccountEnabled") {

            $PassedTests++

            Write-Host "PASSOU - $($Case.Name) foi rejeitado." `
                -ForegroundColor Green
        }
        else {

            $FailedTests++

            Write-Host "FALHOU - $($Case.Name)" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
}

Write-Host ""

# ============================================
# TESTE 3 - USUÁRIO INVÁLIDO
# ============================================

Write-Host "Teste 3 - Validação de usuário inválido" -ForegroundColor Yellow

$TotalTests++

$UserInvalid = [PSCustomObject]@{
    FirstName         = "A"
    LastName          = "S"
    DisplayName       = "A S"
    UserPrincipalName = "usuario-invalido"
    MailNickname      = "usuario-invalido"
    JobTitle          = "Analista"
    Department        = "Tecnologia"
    AccountEnabled    = $true
}

try {

    Test-EntraUserProvisioning `
        -User $UserInvalid `
        -Configuration $TestConfig |
        Out-Null

    $FailedTests++

    Write-Host "FALHOU - O usuário inválido foi aceito." `
        -ForegroundColor Red
}
catch {

    $ExpectedError = $_.Exception.Message

    if (
        $ExpectedError -match "FirstName|LastName|UserPrincipalName|MailNickname"
    ) {

        $PassedTests++

        Write-Host "PASSOU - Usuário inválido rejeitado pela validação." `
            -ForegroundColor Green
    }
    else {

        $FailedTests++

        Write-Host "FALHOU - Erro inesperado durante a validação." `
            -ForegroundColor Red

        Write-Host $ExpectedError -ForegroundColor Red
    }
}

Write-Host ""

# ============================================
# TESTE 4 - USUÁRIO DUPLICADO
# ============================================

Write-Host "Teste 4 - Detecção de usuário duplicado" -ForegroundColor Yellow

$TotalTests++

$UserDuplicate = [PSCustomObject]@{
    FirstName         = "Maria"
    LastName          = "Silva"
    DisplayName       = "Maria Silva"
    UserPrincipalName = "maria.silva@example.onmicrosoft.com"
    MailNickname      = "maria.silva"
    JobTitle          = "Analista"
    Department        = "Tecnologia"
    AccountEnabled    = $true
}

try {

    $Exists = Test-EntraUserExists `
        -UserPrincipalName $UserDuplicate.UserPrincipalName `
        -Configuration $TestConfig

    if ($Exists -eq $true) {

        $PassedTests++

        Write-Host "PASSOU - Usuário duplicado foi identificado corretamente." -ForegroundColor Green
    }
    else {

        $FailedTests++

        Write-Host "FALHOU - Usuário duplicado não foi identificado." -ForegroundColor Red
    }
}
catch {

    $FailedTests++

    Write-Host "FALHOU - Erro durante a detecção de duplicidade." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""

# ============================================
# TESTE 5 - PROVISIONAMENTO SIMULADO
# ============================================

Write-Host "Teste 5 - Provisionamento simulado" -ForegroundColor Yellow

$TotalTests++

$UserNew = [PSCustomObject]@{
    FirstName         = "Carlos"
    LastName          = "Oliveira"
    DisplayName       = "Carlos Oliveira"
    UserPrincipalName = "carlos.oliveira2@example.onmicrosoft.com"
    MailNickname      = "carlos.oliveira2"
    JobTitle          = "Analista de Infraestrutura"
    Department        = "Tecnologia"
    AccountEnabled    = $true
}

try {

    $Result = New-EntraUserProvision `
        -User $UserNew `
        -Configuration $TestConfig

    if (
        $Result.Success -eq $true -and
        $Result.Simulation -eq $true -and
        $Result.PostValidation -eq $false -and
        $Result.UserPrincipalName -eq $UserNew.UserPrincipalName
    ) {

        $PassedTests++

        Write-Host "PASSOU - Usuário preparado em modo de simulação." -ForegroundColor Green
        Write-Host "UPN: $($Result.UserPrincipalName)" -ForegroundColor Green
        Write-Host "Mensagem: $($Result.Message)" -ForegroundColor Green
    }
    else {

        $FailedTests++

        Write-Host "FALHOU - Resultado inesperado." -ForegroundColor Red
    }
}
catch {

    $FailedTests++

    Write-Host "FALHOU - Erro durante o provisionamento simulado." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""

# ============================================
# TESTE 6 - USUÁRIO NÃO EXISTENTE
# ============================================

Write-Host "Teste 6 - Usuário não existente" -ForegroundColor Yellow

$TotalTests++

$UserNotExists = "novo.usuario@example.onmicrosoft.com"

try {

    $Exists = Test-EntraUserExists `
        -UserPrincipalName $UserNotExists `
        -Configuration $TestConfig

    if ($Exists -eq $false) {

        $PassedTests++

        Write-Host "PASSOU - Usuário não existe na simulação." -ForegroundColor Green
    }
    else {

        $FailedTests++

        Write-Host "FALHOU - Usuário foi identificado incorretamente como existente." -ForegroundColor Red
    }
}
catch {

    $FailedTests++

    Write-Host "FALHOU - Erro ao verificar usuário." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""

# ============================================
# TESTE 7 - CONVERSÃO DE IDENTIFICADOR
# ============================================

Write-Host "Teste 7 - Conversão de identificador" -ForegroundColor Yellow

$TotalTests++

try {

    $Result = ConvertTo-EntraIdentifier `
        -Text "João da Silva"

    if ($Result -eq "joao-da-silva") {

        $PassedTests++

        Write-Host "PASSOU - Identificador normalizado corretamente." -ForegroundColor Green
        Write-Host "Resultado: $Result" -ForegroundColor Green
    }
    else {

        $FailedTests++

        Write-Host "FALHOU - Resultado inesperado: $Result" -ForegroundColor Red
    }
}
catch {

    $FailedTests++

    Write-Host "FALHOU - Erro na conversão do identificador." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""

# ============================================
# TESTE 8 - PÓS-VALIDAÇÃO FUNCIONAL
# ============================================

Write-Host "Teste 8 - Pós-validação funcional" -ForegroundColor Yellow

# Simular resposta do Microsoft Graph

# Preservar função global existente, se houver
$HadOriginalGetMgUser = Test-Path Function:\global:Get-MgUser

if ($HadOriginalGetMgUser) {
    $OriginalGetMgUser = (
        Get-Item Function:\global:Get-MgUser
    ).ScriptBlock
}

# Preservar variável global existente, se houver
$HadOriginalMockEntraUser = (
    Test-Path Variable:\global:MockEntraUser
)

if ($HadOriginalMockEntraUser) {
    $OriginalMockEntraUser = $global:MockEntraUser
}
function global:Get-MgUser {
    param (
        $UserId,
        $Property,
        $ErrorAction
        )

     return $global:MockEntraUser
    }
    

$ExpectedUser = [PSCustomObject]@{
    DisplayName       = "Carlos Oliveira"
    UserPrincipalName = "carlos.oliveira@example.onmicrosoft.com"
}

$Scenarios = @(
    [PSCustomObject]@{
        Name = "Usuário com dados corretos"
        User = [PSCustomObject]@{
            Id                = "id-123"
            DisplayName       = "Carlos Oliveira"
            UserPrincipalName = "carlos.oliveira@example.onmicrosoft.com"
        }
        UserId = "id-123"
        ShouldPass = $true
    },
    [PSCustomObject]@{
        Name = "ID divergente"
        User = [PSCustomObject]@{
            Id                = "id-999"
            DisplayName       = "Carlos Oliveira"
            UserPrincipalName = "carlos.oliveira@example.onmicrosoft.com"
        }
        UserId = "id-123"
        ShouldPass = $false
    },
    [PSCustomObject]@{
        Name = "UPN divergente"
        User = [PSCustomObject]@{
            Id                = "id-123"
            DisplayName       = "Carlos Oliveira"
            UserPrincipalName = "outro@example.onmicrosoft.com"
        }
        UserId = "id-123"
        ShouldPass = $false
    },
    [PSCustomObject]@{
        Name = "UPN nulo"
        User = [PSCustomObject]@{
            Id                = "id-123"
            DisplayName       = "Carlos Oliveira"
            UserPrincipalName = $null
        }
        UserId = "id-123"
        ShouldPass = $false
    },
    [PSCustomObject]@{
        Name = "UPN vazio"
        User = [PSCustomObject]@{
            Id                = "id-123"
            DisplayName       = "Carlos Oliveira"
            UserPrincipalName = ""
        }
        UserId = "id-123"
        ShouldPass = $false
    },
    [PSCustomObject]@{
        Name = "UPN com letras maiúsculas"
        User = [PSCustomObject]@{
            Id                = "id-123"
            DisplayName       = "Carlos Oliveira"
            UserPrincipalName = "CARLOS.OLIVEIRA@EXAMPLE.ONMICROSOFT.COM"
        }
        UserId = "id-123"
        ShouldPass = $true
    }
)

try {
    foreach ($Scenario in $Scenarios) {

    $TotalTests++
    $global:MockEntraUser = $Scenario.User
    $ActualPass = $false
    $ErrorMessage = ""

    try {
        $Result = Test-EntraUserPostProvisioning `
            -UserId $Scenario.UserId `
            -ExpectedUser $ExpectedUser

        $ActualPass = $true
    }
    catch {
        $ErrorMessage = $_.Exception.Message
    }

    $TestPassed = ($ActualPass -eq $Scenario.ShouldPass)

    if (@("UPN nulo", "UPN vazio") -contains $Scenario.Name) {
        $TestPassed = (
            $TestPassed -and
            $ErrorMessage -match "UserPrincipalName está vazio ou nulo"
        )
    }

    if ($TestPassed) {
        $PassedTests++
        Write-Host "PASSOU - $($Scenario.Name)" -ForegroundColor Green
    }
    else {
        $FailedTests++
        Write-Host "FALHOU - $($Scenario.Name)" -ForegroundColor Red

        if ($ErrorMessage) {
            Write-Host $ErrorMessage -ForegroundColor Red
        }
    }
}

# Remover a função simulada após os testes
}
finally {
    # Restaurar função global anterior ou remover o mock
    if ($HadOriginalGetMgUser) {
        Set-Item `
            -Path Function:\global:Get-MgUser `
            -Value $OriginalGetMgUser
    }
    else {
        Remove-Item `
            -Path Function:\global:Get-MgUser `
            -ErrorAction SilentlyContinue
    }

    # Restaurar variável global anterior ou removê-la
    if ($HadOriginalMockEntraUser) {
        $global:MockEntraUser = $OriginalMockEntraUser
    }
    else {
        Remove-Variable `
            -Name MockEntraUser `
            -Scope Global `
            -ErrorAction SilentlyContinue
    }
}
Write-Host ""

# ============================================
# TESTE 9 - BLOQUEIO DE CRIAÇÃO NA SIMULAÇÃO
# ============================================

Write-Host "Teste 9 - Bloqueio de criação na simulação" `
    -ForegroundColor Yellow

$TotalTests++

$global:NewMgUserCallCount = 0

$HadOriginalNewMgUser = Test-Path Function:\global:New-MgUser

if ($HadOriginalNewMgUser) {
    $OriginalNewMgUser = (
        Get-Item Function:\global:New-MgUser
    ).ScriptBlock
}

try {

    function global:New-MgUser {
        $global:NewMgUserCallCount++
        throw "New-MgUser foi chamado durante a simulação."
    }

    $UserSimulationGuard = [PSCustomObject]@{
        FirstName         = "Teste"
        LastName          = "Simulacao"
        DisplayName       = "Teste Simulacao"
        UserPrincipalName = "teste.simulacao.guard@example.onmicrosoft.com"
        MailNickname      = "teste.simulacao.guard"
        JobTitle          = "Teste"
        Department        = "Teste"
        AccountEnabled    = $true
    }

    $ResultGuard = New-EntraUserProvision `
        -User $UserSimulationGuard `
        -Configuration $TestConfig

    if (
        $ResultGuard.Success -eq $true -and
        $ResultGuard.Simulation -eq $true -and
        $global:NewMgUserCallCount -eq 0
    ) {
        $PassedTests++

        Write-Host "PASSOU - New-MgUser não foi chamado." `
            -ForegroundColor Green
    }
    else {
        $FailedTests++

        Write-Host "FALHOU - Resultado inesperado na simulação." `
            -ForegroundColor Red
    }
}
catch {

    $FailedTests++

    Write-Host "FALHOU - Erro durante o teste de simulação." `
        -ForegroundColor Red

    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {

    if ($HadOriginalNewMgUser) {
        Set-Item `
            -Path Function:\global:New-MgUser `
            -Value $OriginalNewMgUser
    }
    else {
        Remove-Item `
            -Path Function:\global:New-MgUser `
            -ErrorAction SilentlyContinue
    }

    Remove-Variable `
        -Name NewMgUserCallCount `
        -Scope Global `
        -ErrorAction SilentlyContinue
}

Write-Host ""

# ============================================
# TESTE 10 - TENANTID COM FORMATO INVÁLIDO
# ============================================

Write-Host "Teste 10 - TenantId com formato inválido" `
    -ForegroundColor Yellow

$TotalTests++

$InvalidTenantConfig = $TestConfig |
    ConvertTo-Json -Depth 20 |
    ConvertFrom-Json

$InvalidTenantConfig.SimulationMode = $false
$InvalidTenantConfig.TenantId = "111111111111111111111111111111111111"
$InvalidTenantConfig.Domain = "example.onmicrosoft.com"

try {

    Test-EntraConfiguration `
        -Configuration $InvalidTenantConfig |
        Out-Null

    $FailedTests++

    Write-Host "FALHOU - TenantId inválido foi aceito." `
        -ForegroundColor Red
}
catch {

    if (
        $_.Exception.Message -match
        "O 'TenantId' não possui um formato válido\."
    ) {
        $PassedTests++

        Write-Host "PASSOU - TenantId inválido foi rejeitado." `
            -ForegroundColor Green
    }
    else {
        $FailedTests++

        Write-Host "FALHOU - Ocorreu um erro inesperado." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red
    }
}

Write-Host ""

# ============================================
# TESTE 11 - DOMAIN AUSENTE NO MODO REAL
# ============================================

Write-Host "Teste 11 - Domain ausente no modo real" `
    -ForegroundColor Yellow

$TotalTests++

$MissingDomainConfig = $TestConfig |
    ConvertTo-Json -Depth 20 |
    ConvertFrom-Json

$MissingDomainConfig.SimulationMode = $false
$MissingDomainConfig.TenantId = "11111111-1111-1111-1111-111111111111"
$MissingDomainConfig.Domain = ""

try {

    Test-EntraConfiguration `
        -Configuration $MissingDomainConfig |
        Out-Null

    $FailedTests++

    Write-Host "FALHOU - Configuração sem Domain foi aceita." `
        -ForegroundColor Red
}
catch {

    if ($_.Exception.Message -match "Domain") {

        $PassedTests++

        Write-Host "PASSOU - Domain ausente foi rejeitado." `
            -ForegroundColor Green
    }
    else {

        $FailedTests++

        Write-Host "FALHOU - Erro inesperado." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

Write-Host ""

# ============================================
# TESTES 12 A 15 - SIMULATIONMODE INVÁLIDO
# ============================================

$InvalidSimulationModes = @(
    [PSCustomObject]@{
        TestNumber = 12
        Value      = "true"
        Description = "texto true"
    }
    [PSCustomObject]@{
        TestNumber = 13
        Value      = "false"
        Description = "texto false"
    }
    [PSCustomObject]@{
        TestNumber = 14
        Value      = 1
        Description = "valor numérico"
    }
    [PSCustomObject]@{
        TestNumber = 15
        Value      = "ativo"
        Description = "texto arbitrário"
    }
)

foreach ($Case in $InvalidSimulationModes) {

    Write-Host "Teste $($Case.TestNumber) - SimulationMode inválido: $($Case.Description)" -ForegroundColor Yellow

    $TotalTests++

    $InvalidConfig = $TestConfig |
        ConvertTo-Json -Depth 20 |
        ConvertFrom-Json

    $InvalidConfig.SimulationMode = $Case.Value

    try {

        Test-EntraConfiguration `
            -Configuration $InvalidConfig |
            Out-Null

        $FailedTests++

        Write-Host "FALHOU - Valor inválido foi aceito." -ForegroundColor Red
    }
    catch {

        if (
            $_.Exception.Message -match "SimulationMode"
        ) {

            $PassedTests++

            Write-Host "PASSOU - Valor inválido foi rejeitado." -ForegroundColor Green
        }
        else {

            $FailedTests++

            Write-Host "FALHOU - Erro diferente do esperado." -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }

    Write-Host ""
}

# ============================================
# TESTE 16 - BLOQUEIO COM SIMULATIONMODE INVÁLIDO
# ============================================

Write-Host "Teste 16 - Bloqueio com SimulationMode inválido" `
    -ForegroundColor Yellow

$TotalTests++

$InvalidConfig = $TestConfig |
    ConvertTo-Json -Depth 20 |
    ConvertFrom-Json

$InvalidConfig.SimulationMode = "false"

$UserInvalidConfig = [PSCustomObject]@{
    FirstName         = "Teste"
    LastName          = "ConfigInvalida"
    DisplayName       = "Teste ConfigInvalida"
    UserPrincipalName = "teste.config.invalida@example.onmicrosoft.com"
    MailNickname      = "teste.config.invalida"
    JobTitle          = "Teste"
    Department        = "Teste"
    AccountEnabled    = $true
}

try {

    $null = New-EntraUserProvision `
        -User $UserInvalidConfig `
        -Configuration $InvalidConfig

    $FailedTests++

    Write-Host "FALHOU - A configuração inválida foi aceita." `
        -ForegroundColor Red
}
catch {

    if ($_.Exception.Message -match "SimulationMode") {

        $PassedTests++

        Write-Host "PASSOU - SimulationMode inválido foi bloqueado." `
            -ForegroundColor Green
    }
    else {

        $FailedTests++

        Write-Host "FALHOU - Erro diferente do esperado." `
            -ForegroundColor Red

        Write-Host $_.Exception.Message `
            -ForegroundColor Red
    }
}

Write-Host ""

# ============================================
# TESTES 17 A 19 - MOCKS DO MICROSOFT GRAPH
# ============================================

Write-Host "Preparando mocks do Microsoft Graph..." -ForegroundColor Cyan

$MockFunctionNames = @(
    "Get-MgUser",
    "Get-MgContext",
    "New-MgUser",
    "Read-Host"
)

$OriginalMockFunctions = @{}

foreach ($FunctionName in $MockFunctionNames) {

    $FunctionPath = "Function:\global:$FunctionName"

    $OriginalMockFunctions[$FunctionName] = @{
        Exists = Test-Path $FunctionPath
        ScriptBlock = if (Test-Path $FunctionPath) {
            (Get-Item $FunctionPath).ScriptBlock
        }
        else {
            $null
        }
    }
}

$global:EntraMockScenario = "Success"
$global:EntraMockParameters = $null

$MockConfig = $TestConfig |
    ConvertTo-Json -Depth 20 |
    ConvertFrom-Json

$MockConfig.SimulationMode = $false

$MockUser = [PSCustomObject]@{
    FirstName         = "Teste"
    LastName          = "Mock"
    DisplayName       = "Teste Mock"
    UserPrincipalName = "teste.mock@example.onmicrosoft.com"
    MailNickname      = "teste.mock"
    JobTitle          = "Teste"
    Department        = "Automacao"
    AccountEnabled    = $true
}

try {

    # --------------------------------------------
    # MOCK - CONTEXTO DO GRAPH
    # --------------------------------------------

    function global:Get-MgContext {
        return [PSCustomObject]@{
            TenantId = "00000000-0000-0000-0000-000000000000"
            Account  = "teste@example.onmicrosoft.com"
            AuthType = "Mock"
            Scopes   = @("User.ReadWrite.All")
        }
    }

    # --------------------------------------------
    # MOCK - SENHA FICTÍCIA
    # --------------------------------------------

    function global:Read-Host {
        param (
            [string]$Prompt,
            [switch]$AsSecureString
        )

        return ConvertTo-SecureString `
            "SenhaFicticia123!" `
            -AsPlainText `
            -Force
    }

    # --------------------------------------------
    # MOCK - CONSULTA DE USUÁRIO
    # --------------------------------------------

    function global:Get-MgUser {
        param (
            $UserId,
            $Property,
            $ErrorAction
        )

    if (
        $UserId -eq $MockUser.UserPrincipalName
    ) {
        throw "Request_ResourceNotFound"
    }

    if ($global:EntraMockScenario -eq "PostValidationFailure") {
        throw "Falha fictícia na pós-validação."
    }

    return [PSCustomObject]@{
        Id                = "MOCK-USER-ID-001"
        DisplayName       = $MockUser.DisplayName
        UserPrincipalName = $MockUser.UserPrincipalName
    }
}

    # --------------------------------------------
    # MOCK - CRIAÇÃO DE USUÁRIO
    # --------------------------------------------

    function global:New-MgUser {
        param (
            [hashtable]$BodyParameter,
            [string]$ErrorAction
        )

        $global:EntraMockParameters = $BodyParameter

        if ($global:EntraMockScenario -eq "CreationFailure") {
            throw "Falha fictícia na criação do usuário."
        }

        return [PSCustomObject]@{
            Id = "MOCK-USER-ID-001"
        }
    }

    # ============================================
    # TESTE 17 - CRIAÇÃO COM MOCKS
    # ============================================

    Write-Host ""
    Write-Host "Teste 17 - Criação com mocks do Graph" -ForegroundColor Yellow

    $TotalTests++

    $global:EntraMockScenario = "Success"

    try {

        $Result17 = New-EntraUserProvision `
            -User $MockUser `
            -Configuration $MockConfig

        $Parameters17 = $global:EntraMockParameters

        if (
            $Result17.Success -eq $true -and
            $Result17.Simulation -eq $false -and
            $Result17.PostValidation -eq $true -and
            $Parameters17.accountEnabled -eq $true -and
            $Parameters17.displayName -eq $MockUser.DisplayName -and
            $Parameters17.mailNickname -eq $MockUser.MailNickname -and
            $Parameters17.userPrincipalName -eq $MockUser.UserPrincipalName -and
            $Parameters17.passwordProfile.forceChangePasswordNextSignIn -eq $true
        ) {

            $PassedTests++

            Write-Host "PASSOU - Parâmetros e pós-validação conferidos." -ForegroundColor Green
        }
        else {

            $FailedTests++

            Write-Host "FALHOU - Parâmetros ou resultado inesperado." -ForegroundColor Red
        }
    }
    catch {

        $FailedTests++

        Write-Host "FALHOU - Erro no teste de criação com mocks." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }

    # ============================================
    # TESTE 18 - FALHA NA CRIAÇÃO
    # ============================================

    Write-Host ""
    Write-Host "Teste 18 - Falha na criação do usuário" -ForegroundColor Yellow

    $TotalTests++

    $global:EntraMockScenario = "CreationFailure"

    try {

        $null = New-EntraUserProvision `
            -User $MockUser `
            -Configuration $MockConfig

        $FailedTests++

        Write-Host "FALHOU - A falha de criação não foi detectada." -ForegroundColor Red
    }
    catch {

        if (
            $_.Exception.Message -match "Falha fictícia na criação"
        ) {

            $PassedTests++

            Write-Host "PASSOU - Falha de criação tratada corretamente." -ForegroundColor Green
        }
        else {

            $FailedTests++

            Write-Host "FALHOU - Mensagem inesperada." -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }

    # ============================================
    # TESTE 19 - FALHA NA PÓS-VALIDAÇÃO
    # ============================================

    Write-Host ""
    Write-Host "Teste 19 - Falha na pós-validação" -ForegroundColor Yellow

    $TotalTests++

    $global:EntraMockScenario = "PostValidationFailure"

    try {

        $null = New-EntraUserProvision `
            -User $MockUser `
            -Configuration $MockConfig

        $FailedTests++

        Write-Host "FALHOU - A falha de pós-validação não foi detectada." -ForegroundColor Red
    }
    catch {

        if (
            $_.Exception.Message -match "não foi possível realizar a pós-validação"
        ) {

            $PassedTests++

            Write-Host "PASSOU - Falha de pós-validação detectada." -ForegroundColor Green
        }
        else {

            $FailedTests++

            Write-Host "FALHOU - Mensagem inesperada." -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
    }
}
catch {

    $FailedTests++

    Write-Host "ERRO NA PREPARAÇÃO DOS MOCKS:" `
        -ForegroundColor Red

    Write-Host $_.Exception.Message `
        -ForegroundColor Red
}
finally {

    # Restaurar funções globais anteriores

    foreach ($FunctionName in $MockFunctionNames) {

        $FunctionPath = "Function:\global:$FunctionName"
        $Original = $OriginalMockFunctions[$FunctionName]

        if ($Original.Exists) {

            Set-Item `
                -Path $FunctionPath `
                -Value $Original.ScriptBlock
        }
        else {

            Remove-Item `
                -Path $FunctionPath `
                -ErrorAction SilentlyContinue
        }
    }

    Remove-Variable `
        -Name EntraMockScenario `
        -Scope Global `
        -ErrorAction SilentlyContinue

    Remove-Variable `
        -Name EntraMockParameters `
        -Scope Global `
        -ErrorAction SilentlyContinue
}

Write-Host ""

# ============================================
# RESUMO DOS TESTES
# ============================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "              RESUMO DOS TESTES"              -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
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

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan