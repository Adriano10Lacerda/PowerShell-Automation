# ============================================
# Testes - AD User Provisioning
# ============================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "AD-Functions.psm1"
$ConfigurationPath = Join-Path $PSScriptRoot "AD-Configuration.json"

Import-Module $ModulePath -Force

$Configuration = Get-Content $ConfigurationPath -Raw | ConvertFrom-Json

$Passed = 0
$Failed = 0
$Total = 0

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
# 1. Configuração
# ============================================

Invoke-Test "Configuração atual é válida" {

    Test-ADConfiguration `
        -Configuration $Configuration | Out-Null
}

Invoke-Test "SimulationMode está habilitado" {

    if ($Configuration.SimulationMode -ne $true) {
        throw "SimulationMode deveria estar habilitado."
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

    try {
        Test-ADUserProvisioning `
            -FirstName " " `
            -LastName "Silva" `
            -SamAccountName "silva.maria" `
            -Configuration $Configuration | Out-Null

        throw "Era esperado erro para FirstName vazio."
    }
    catch {
        if ($_.Exception.Message -notmatch "primeiro nome") {
            throw
        }
    }
}

Invoke-Test "Sobrenome vazio é rejeitado" {

    try {
        Test-ADUserProvisioning `
            -FirstName "Maria" `
            -LastName " " `
            -SamAccountName "maria" `
            -Configuration $Configuration | Out-Null

        throw "Era esperado erro para LastName vazio."
    }
    catch {
        if ($_.Exception.Message -notmatch "sobrenome") {
            throw
        }
    }
}

Invoke-Test "SamAccountName com caracteres inválidos é rejeitado" {

    try {
        Test-ADUserProvisioning `
            -FirstName "Maria" `
            -LastName "Silva" `
            -SamAccountName "silva maria" `
            -Configuration $Configuration | Out-Null

        throw "Era esperado erro para caracteres inválidos."
    }
    catch {
        if ($_.Exception.Message -notmatch "caracteres inválidos") {
            throw
        }
    }
}

Invoke-Test "SamAccountName acima do limite é rejeitado" {

    $LongSam = "abcdefghijklmnopqrstu"

    try {
        Test-ADUserProvisioning `
            -FirstName "Maria" `
            -LastName "Silva" `
            -SamAccountName $LongSam `
            -Configuration $Configuration | Out-Null

        throw "Era esperado erro para SamAccountName acima do limite."
    }
    catch {
        if ($_.Exception.Message -notmatch "mais de") {
            throw
        }
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

    try {
        Get-ADSamAccountName `
            -FirstName "Maria" `
            -LastName "Silva" `
            -UserType "Unknown" `
            -Configuration $Configuration | Out-Null

        throw "Era esperado erro para tipo inexistente."
    }
    catch {
        if ($_.Exception.Message -notmatch "não está configurado") {
            throw
        }
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

    try {
        Get-ADSamAccountName `
            -FirstName "Alexandre" `
            -LastName "Nascimentosilva" `
            -UserType "Contractor" `
            -Configuration $Configuration | Out-Null

        throw "Era esperado erro para nome acima do limite."
    }
    catch {
        if ($_.Exception.Message -notmatch "ultrapassa o limite") {
            throw
        }
    }
}

# ============================================
# 6. Conectividade
# ============================================

Invoke-Test "Modo de simulação não conecta ao AD" {

    $Result = Test-ADConnectivity `
        -Configuration $Configuration

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
        UserPrincipalName = "maria.silva.test@example.local"
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