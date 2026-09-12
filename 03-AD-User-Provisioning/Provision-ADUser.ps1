# ============================================
# AD User Provisioning
# ============================================

$ErrorActionPreference = "Stop"

# Caminhos
$ConfigurationPath = Join-Path $PSScriptRoot "AD-Configuration.json"
$ModulePath = Join-Path $PSScriptRoot "AD-Functions.psm1"

# ============================================
# Carregar módulo
# ============================================

Import-Module $ModulePath -Force

# ============================================
# Carregar configuração
# ============================================

if (-not (Test-Path $ConfigurationPath)) {
    throw "Arquivo de configuração não encontrado: $ConfigurationPath"
}

$Configuration = Get-Content $ConfigurationPath -Raw | ConvertFrom-Json

# ============================================
# Validar configuração
# ============================================

Test-ADConfiguration -Configuration $Configuration | Out-Null

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "      AD USER PROVISIONING" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Domínio: $($Configuration.Domain)"
Write-Host "Modo de simulação: $($Configuration.SimulationMode)"
Write-Host ""

# ============================================
# Dados do usuário
# ============================================

$FirstName = Read-Host "Digite o primeiro nome"
$LastName = Read-Host "Digite o sobrenome"
$SamAccountName = Read-Host "Digite o SamAccountName"

# ============================================
# Validação dos dados
# ============================================

try {
    Test-ADUserProvisioning `
        -FirstName $FirstName `
        -LastName $LastName `
        -SamAccountName $SamAccountName | Out-Null
}
catch {
    Write-Host ""
    Write-Host "ERRO DE VALIDAÇÃO:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "A operação foi interrompida." -ForegroundColor Yellow

    exit 1
}

$DisplayName = "$FirstName $LastName"

# ============================================
# Verificar usuário existente
# ============================================

if ($Configuration.OfflineSimulation -eq $true) {

    Write-Host ""
    Write-Host "********** SIMULAÇÃO OFFLINE **********" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Consulta ao Active Directory desativada."
    Write-Host "O sistema está executando em ambiente local."
    Write-Host ""

}
else {

    Write-Host ""
    Write-Host "Verificando se o usuário já existe..." -ForegroundColor Cyan

    try {
        $UserExists = Test-ADUserExists -SamAccountName $SamAccountName
    }
    catch {
        Write-Host ""
        Write-Host "ERRO: Não foi possível consultar o Active Directory." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        Write-Host "A operação foi interrompida por segurança." -ForegroundColor Yellow

        exit 1
    }

    if ($UserExists) {
        Write-Host ""
        Write-Host "ERRO: O usuário '$SamAccountName' já existe no Active Directory." -ForegroundColor Red
        Write-Host "A criação foi bloqueada para evitar duplicidade." -ForegroundColor Red

        exit 1
    }

    Write-Host "Usuário não encontrado. Pode continuar." -ForegroundColor Green
}

# ============================================
# Modo de simulação
# ============================================

if ($Configuration.SimulationMode -eq $true) {

    Write-Host ""
    Write-Host "********** MODO SIMULAÇÃO **********" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Usuário que seria criado:"
    Write-Host "Nome:              $DisplayName"
    Write-Host "SamAccountName:    $SamAccountName"
    Write-Host "Domínio:           $($Configuration.Domain)"
    Write-Host "Domain Controller: $($Configuration.DomainController)"
    Write-Host "Target OU:         $($Configuration.TargetOU)"
    Write-Host ""

    Write-Host "Nenhuma alteração foi realizada no Active Directory." -ForegroundColor Green
}