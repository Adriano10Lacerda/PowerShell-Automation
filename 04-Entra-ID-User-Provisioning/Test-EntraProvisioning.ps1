# ============================================
# Test-EntraProvisioning.ps1
# Testes do módulo Entra ID User Provisioning
# ============================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "Entra-Functions.psm1"
$ConfigPath = Join-Path $PSScriptRoot "Entra-Configuration.json"

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

    Write-Host "FALHOU - O usuário inválido foi aceito." -ForegroundColor Red

    $FailedTests++
}
catch {

    $PassedTests++

    Write-Host "PASSOU - Usuário inválido foi rejeitado corretamente." -ForegroundColor Green
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
# TESTE 8 - PÓS-VALIDAÇÃO SEM GRAPH
# ============================================

Write-Host "Teste 8 - Validação da função de pós-provisionamento" -ForegroundColor Yellow

$TotalTests++

$PostValidationCommand = Get-Command `
    Test-EntraUserPostProvisioning `
    -ErrorAction SilentlyContinue

if ($null -ne $PostValidationCommand) {

    $PassedTests++

    Write-Host "PASSOU - Função de pós-validação disponível." -ForegroundColor Green
}
else {

    $FailedTests++

    Write-Host "FALHOU - Função de pós-validação não encontrada." -ForegroundColor Red
}

Write-Host ""

# ============================================
# RESUMO DOS TESTES
# ============================================

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "              RESUMO DOS TESTES" -ForegroundColor Cyan
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