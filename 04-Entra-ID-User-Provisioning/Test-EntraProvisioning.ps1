# ============================================
# Test-EntraProvisioning.ps1
# Testes do módulo Entra ID User Provisioning
# ============================================

$ModulePath = Join-Path $PSScriptRoot "Entra-Functions.psm1"
$ConfigPath = Join-Path $PSScriptRoot "Entra-Configuration.json"

# Carregar módulo
Import-Module $ModulePath -Force

# Carregar configuração
$Config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Contadores
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
Write-Host ""

# ============================================
# TESTE 1 - Validação da configuração
# ============================================

Write-Host "Teste 1 - Validação da configuração" -ForegroundColor Yellow

$TotalTests++

try {

    Test-EntraConfiguration -Configuration $Config | Out-Null

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
# TESTE 2 - Usuário válido
# ============================================

Write-Host "Teste 2 - Validação de usuário válido" -ForegroundColor Yellow

$TotalTests++

$UserValid = [PSCustomObject]@{
    FirstName           = "Carlos"
    LastName            = "Oliveira"
    DisplayName         = "Carlos Oliveira"
    UserPrincipalName   = "carlos.oliveira@example.onmicrosoft.com"
    MailNickname        = "carlos.oliveira"
    JobTitle            = "Analista de Infraestrutura"
    Department          = "Tecnologia"
    AccountEnabled      = $true
}

try {

    Test-EntraUserProvisioning `
        -User $UserValid `
        -Configuration $Config | Out-Null

    $PassedTests++

    Write-Host "PASSOU - Usuário válido." -ForegroundColor Green
}
catch {

    $FailedTests++

    Write-Host "FALHOU - Usuário inválido." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""

# ============================================
# TESTE 3 - Usuário inválido
# ============================================

Write-Host "Teste 3 - Validação de usuário inválido" -ForegroundColor Yellow

$TotalTests++

$UserInvalid = [PSCustomObject]@{
    FirstName           = "A"
    LastName            = "S"
    DisplayName         = "A S"
    UserPrincipalName   = "usuario-invalido"
    MailNickname        = "usuario-invalido"
    JobTitle            = "Analista"
    Department          = "Tecnologia"
    AccountEnabled      = $true
}

try {

    Test-EntraUserProvisioning `
        -User $UserInvalid `
        -Configuration $Config | Out-Null

    Write-Host "FALHOU - O usuário inválido foi aceito." -ForegroundColor Red

    $FailedTests++
}
catch {

    $PassedTests++

    Write-Host "PASSOU - Usuário inválido foi rejeitado corretamente." -ForegroundColor Green
}

Write-Host ""

# ============================================
# TESTE 4 - Usuário duplicado
# ============================================

Write-Host "Teste 4 - Detecção de usuário duplicado" -ForegroundColor Yellow

$TotalTests++

$UserDuplicate = [PSCustomObject]@{
    FirstName           = "Maria"
    LastName            = "Silva"
    DisplayName         = "Maria Silva"
    UserPrincipalName   = "maria.silva@example.onmicrosoft.com"
    MailNickname        = "maria.silva"
    JobTitle            = "Analista"
    Department          = "Tecnologia"
    AccountEnabled      = $true
}

try {

    New-EntraUserProvision `
        -User $UserDuplicate `
        -Configuration $Config | Out-Null

    Write-Host "FALHOU - O usuário duplicado foi aceito." -ForegroundColor Red

    $FailedTests++
}
catch {

    $PassedTests++

    Write-Host "PASSOU - Usuário duplicado foi rejeitado corretamente." -ForegroundColor Green
}

Write-Host ""

# ============================================
# TESTE 5 - Provisionamento simulado
# ============================================

Write-Host "Teste 5 - Provisionamento simulado" -ForegroundColor Yellow

$TotalTests++

$UserNew = [PSCustomObject]@{
    FirstName           = "Carlos"
    LastName            = "Oliveira"
    DisplayName         = "Carlos Oliveira"
    UserPrincipalName   = "carlos.oliveira@example.onmicrosoft.com"
    MailNickname        = "carlos.oliveira"
    JobTitle            = "Analista de Infraestrutura"
    Department          = "Tecnologia"
    AccountEnabled      = $true
}

try {

    $Result = New-EntraUserProvision `
        -User $UserNew `
        -Configuration $Config

    if ($Result.Success -eq $true -and $Result.Simulation -eq $true) {

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
# TESTE 6 - Usuário não existente
# ============================================

Write-Host "Teste 6 - Usuário não existente" -ForegroundColor Yellow

$TotalTests++

$UserNotExists = "novo.usuario@example.onmicrosoft.com"

try {

    $Exists = Test-EntraUserExists `
        -UserPrincipalName $UserNotExists `
        -Configuration $Config

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