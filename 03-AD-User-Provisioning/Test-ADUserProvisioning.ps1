
# ============================================
# Testes - AD User Provisioning
# ============================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "AD-Functions.psm1"
$ConfigurationPath = Join-Path $PSScriptRoot "AD-Configuration.json"

if (-not (Test-Path $ModulePath)) {
    throw "Módulo não encontrado: $ModulePath"
}

if (-not (Test-Path $ConfigurationPath)) {
    throw "Configuração não encontrada: $ConfigurationPath"
}

Import-Module $ModulePath -Force

$Configuration = Get-Content $ConfigurationPath -Raw |
    ConvertFrom-Json -ErrorAction Stop

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