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

Write-Host ""
Write-Host "Tipos de usuário disponíveis:" -ForegroundColor Cyan

$UserTypeKeys = @($Configuration.UserTypes.PSObject.Properties.Name)

for ($i = 0; $i -lt $UserTypeKeys.Count; $i++) {
    $Key = $UserTypeKeys[$i]
    $Description = $Configuration.UserTypes.$Key.Description

    Write-Host "$($i + 1) - $Description"
}

Write-Host ""

$UserTypeSelection = Read-Host "Escolha o tipo de usuário"

if (-not ($UserTypeSelection -match '^\d+$')) {
    Write-Host ""
    Write-Host "ERRO: Escolha um número válido." -ForegroundColor Red
    exit 1
}

$UserTypeIndex = [int]$UserTypeSelection - 1

if ($UserTypeIndex -lt 0 -or $UserTypeIndex -ge $UserTypeKeys.Count) {
    Write-Host ""
    Write-Host "ERRO: Tipo de usuário inválido." -ForegroundColor Red
    exit 1
}

$UserType = $UserTypeKeys[$UserTypeIndex]

# ============================================
# Gerar SamAccountName automaticamente
# ============================================

try {
    $SamAccountName = Get-ADSamAccountName `
        -FirstName $FirstName `
        -LastName $LastName `
        -UserType $UserType `
        -Configuration $Configuration
}
catch {

    if (
        $Configuration.LongNamePolicy.Enabled -and
        $Configuration.LongNamePolicy.Strategy -eq "Manual" -and
        $_.Exception.Message -like "*ultrapassa o limite configurado*"
    ) {

        Write-Host ""
        Write-Host "============================================" -ForegroundColor Yellow
        Write-Host "      SAMACCOUNTNAME MUITO LONGO" -ForegroundColor Yellow
        Write-Host "============================================" -ForegroundColor Yellow
        Write-Host ""

        Write-Host "O nome gerado automaticamente não pode ser utilizado."
        Write-Host "Limite configurado: $($Configuration.SamAccountName.MaxLength) caracteres."
        Write-Host ""

        do {
            $SamAccountName = Read-Host "Digite manualmente o SamAccountName"

            try {
                Test-ADUserProvisioning `
                    -FirstName $FirstName `
                    -LastName $LastName `
                    -SamAccountName $SamAccountName `
                    -Configuration $Configuration | Out-Null

                $ManualNameValid = $true
            }
            catch {
                $ManualNameValid = $false

                Write-Host ""
                Write-Host "ERRO: SamAccountName inválido." -ForegroundColor Red
                Write-Host $_.Exception.Message -ForegroundColor Red
                Write-Host ""
            }

        } until ($ManualNameValid)
    }
    else {

        Write-Host ""
        Write-Host "ERRO AO GERAR SAMACCOUNTNAME:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""

        exit 1
    }
}

Write-Host ""
Write-Host "SamAccountName gerado: $SamAccountName" -ForegroundColor Green

# ============================================
# Validação dos dados
# ============================================

try {
    Test-ADUserProvisioning `
        -FirstName $FirstName `
        -LastName $LastName `
        -SamAccountName $SamAccountName `
        -Configuration $Configuration | Out-Null
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
# Verificar disponibilidade do SamAccountName
# ============================================

Write-Host ""
Write-Host "Verificando disponibilidade do SamAccountName..." -ForegroundColor Cyan

try {

    if ($Configuration.OfflineSimulation -eq $true) {

        Write-Host ""
        Write-Host "********** SIMULAÇÃO OFFLINE **********" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Consulta ao Active Directory desativada."
        Write-Host "O sistema está executando em ambiente local."
        Write-Host ""

        $UniqueSamAccountName = Get-UniqueADSamAccountName `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration `
            -ExistingSamAccountNames $Configuration.Simulation.ExistingSamAccountNames
    }
    else {

        $UniqueSamAccountName = Get-UniqueADSamAccountName `
            -SamAccountName $SamAccountName `
            -Configuration $Configuration
    }

}
catch {

    Write-Host ""
    Write-Host "ERRO AO VERIFICAR DISPONIBILIDADE:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "A operação foi interrompida por segurança." -ForegroundColor Yellow

    exit 1
}

# ============================================
# Verificar se houve alteração
# ============================================

if ($UniqueSamAccountName -ne $SamAccountName) {

    Write-Host ""
    Write-Host "O SamAccountName '$SamAccountName' já está em uso." -ForegroundColor Yellow
    Write-Host "Novo SamAccountName disponível: '$UniqueSamAccountName'" -ForegroundColor Green
    Write-Host ""

}
else {

    Write-Host ""
    Write-Host "SamAccountName disponível: $UniqueSamAccountName" -ForegroundColor Green
}

$SamAccountName = $UniqueSamAccountName

# ============================================
# Objeto final de provisionamento
# ============================================

$User = [PSCustomObject]@{
    FirstName      = $FirstName
    LastName       = $LastName
    DisplayName    = $DisplayName
    UserType       = $UserType
    SamAccountName = $SamAccountName
}

# ============================================
# Modo de simulação
# ============================================

if ($Configuration.SimulationMode -eq $true) {

    Write-Host ""
    Write-Host "********** MODO SIMULAÇÃO **********" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Usuário que seria criado:"
    Write-Host "Nome:              $($User.DisplayName)"
    Write-Host "SamAccountName:    $($User.SamAccountName)"
    Write-Host "Domínio:           $($Configuration.Domain)"
    Write-Host "Domain Controller: $($Configuration.DomainController)"
    Write-Host "Target OU:         $($Configuration.TargetOU)"
    Write-Host ""

    Write-Host "Nenhuma alteração foi realizada no Active Directory." -ForegroundColor Green
}