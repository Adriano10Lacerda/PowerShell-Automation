# ============================================
# Testes - Password Generator
# ============================================

$ErrorActionPreference = "Stop"

$ModulePath = Join-Path $PSScriptRoot "Password-Functions.psm1"

Import-Module $ModulePath -Force

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
# 1. Geração de índices
# ============================================

Invoke-Test "Limite 1 retorna somente índice 0" {
    $Result = Get-SecureRandomIndex -Maximum 1

    if ($Result -ne 0) {
        throw "Era esperado índice 0, mas foi retornado $Result."
    }
}

Invoke-Test "Limite 2 retorna índice válido" {
    $Result = Get-SecureRandomIndex -Maximum 2

    if ($Result -lt 0 -or $Result -ge 2) {
        throw "Índice fora do intervalo: $Result."
    }
}

Invoke-Test "Limite 10 retorna índice válido" {
    $Result = Get-SecureRandomIndex -Maximum 10

    if ($Result -lt 0 -or $Result -ge 10) {
        throw "Índice fora do intervalo: $Result."
    }
}

Invoke-Test "Limite 26 retorna índice válido" {
    $Result = Get-SecureRandomIndex -Maximum 26

    if ($Result -lt 0 -or $Result -ge 26) {
        throw "Índice fora do intervalo: $Result."
    }
}

Invoke-Test "Limite 62 retorna índice válido" {
    $Result = Get-SecureRandomIndex -Maximum 62

    if ($Result -lt 0 -or $Result -ge 62) {
        throw "Índice fora do intervalo: $Result."
    }
}

# ============================================
# 2. Rejeição de entradas inválidas
# ============================================

Invoke-Test "Limite zero é rejeitado" {
    $Rejeitado = $false

    try {
        Get-SecureRandomIndex -Maximum 0 | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "O limite zero deveria ser rejeitado."
    }
}

Invoke-Test "Limite negativo é rejeitado" {
    $Rejeitado = $false

    try {
        Get-SecureRandomIndex -Maximum -1 | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "O limite negativo deveria ser rejeitado."
    }
}

Invoke-Test "Limite acima do máximo permitido é rejeitado" {
    $Rejeitado = $false

    try {
        Get-SecureRandomIndex -Maximum 2147483648 | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "O limite acima de Int32.MaxValue deveria ser rejeitado."
    }
}

# ============================================
# 3. Testes repetidos de limites
# ============================================

Invoke-Test "1.000 índices respeitam cada limite testado" {
    $Limites = @(1, 2, 10, 26, 62, 1000)

    foreach ($Limite in $Limites) {
        for ($i = 0; $i -lt 1000; $i++) {
            $Indice = Get-SecureRandomIndex -Maximum $Limite

            if ($Indice -lt 0 -or $Indice -ge $Limite) {
                throw "Índice $Indice fora do intervalo para limite $Limite."
            }
        }
    }
}


# ============================================
# 4. Testes de geração de senha
# ============================================

$ParametrosTeste = @{
    Prefixo = "EMP"
    Data = "2709"
    QuantidadeCaracteres = 12
    CaracteresEspeciais = '!@#$%&*'
}

Invoke-Test "Geração retorna uma senha não vazia" {
    $Senha = New-SecurePassword @ParametrosTeste

    if ([string]::IsNullOrWhiteSpace($Senha)) {
        throw "A senha gerada não pode ser vazia."
    }
}

Invoke-Test "Comprimento total da senha está correto" {
    $Senha = New-SecurePassword @ParametrosTeste
    $ComprimentoEsperado = 3 + 4 + 12

    if ($Senha.Length -ne $ComprimentoEsperado) {
        throw "Comprimento incorreto. Esperado: $ComprimentoEsperado; obtido: $($Senha.Length)."
    }
}

Invoke-Test "Senha contém prefixo e data configurados" {
    $Senha = New-SecurePassword @ParametrosTeste

    if (-not $Senha.StartsWith("EMP2709")) {
        throw "A senha não começa com o prefixo e a data esperados."
    }
}

Invoke-Test "Senha contém os quatro grupos obrigatórios" {
    $Senha = New-SecurePassword @ParametrosTeste
    $ParteAleatoria = $Senha.Substring(7)

    $TemMaiuscula = $ParteAleatoria -cmatch '[A-Z]'
    $TemMinuscula = $ParteAleatoria -cmatch '[a-z]'
    $TemNumero = $ParteAleatoria -match '\d'
    $TemEspecial = $ParteAleatoria.IndexOfAny(
        [char[]]'!@#$%&*'
    ) -ge 0

    if (-not ($TemMaiuscula -and $TemMinuscula -and $TemNumero -and $TemEspecial)) {
        throw "A parte aleatória não contém todos os grupos obrigatórios."
    }
}

Invoke-Test "Quantidade mínima de caracteres é aceita" {
    $ParametrosMinimos = $ParametrosTeste.Clone()
    $ParametrosMinimos.QuantidadeCaracteres = 4

    $Senha = New-SecurePassword @ParametrosMinimos

    if ($Senha.Length -ne 11) {
        throw "O comprimento total deveria ser 11 caracteres."
    }
}

Invoke-Test "Quantidade abaixo do mínimo é rejeitada" {
    $Rejeitado = $false

    try {
        New-SecurePassword `
            -Prefixo "EMP" `
            -Data "2709" `
            -QuantidadeCaracteres 3 `
            -CaracteresEspeciais '!@#$%&*' | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "A quantidade abaixo de 4 deveria ser rejeitada."
    }
}

Invoke-Test "Caracteres especiais vazios são rejeitados" {
    $Rejeitado = $false

    try {
        New-SecurePassword `
            -Prefixo "EMP" `
            -Data "2709" `
            -QuantidadeCaracteres 12 `
            -CaracteresEspeciais "" | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "Caracteres especiais vazios deveriam ser rejeitados."
    }
}

# ============================================
# 5. Testes adicionais de validação
# ============================================

Invoke-Test "Letras nos caracteres especiais são rejeitadas" {
    $Rejeitado = $false

    try {
        New-SecurePassword `
            -Prefixo "EMP" `
            -Data "2709" `
            -QuantidadeCaracteres 12 `
            -CaracteresEspeciais '!@ABC' | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "Letras deveriam ser rejeitadas nos caracteres especiais."
    }
}

Invoke-Test "Números nos caracteres especiais são rejeitados" {
    $Rejeitado = $false

    try {
        New-SecurePassword `
            -Prefixo "EMP" `
            -Data "2709" `
            -QuantidadeCaracteres 12 `
            -CaracteresEspeciais '!@123' | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "Números deveriam ser rejeitados nos caracteres especiais."
    }
}

Invoke-Test "Espaços nos caracteres especiais são rejeitados" {
    $Rejeitado = $false

    try {
        New-SecurePassword `
            -Prefixo "EMP" `
            -Data "2709" `
            -QuantidadeCaracteres 12 `
            -CaracteresEspeciais '!@ #' | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "Espaços deveriam ser rejeitados nos caracteres especiais."
    }
}

Invoke-Test "Limite máximo de 128 caracteres é aceito" {
    $ParametrosMaximos = $ParametrosTeste.Clone()
    $ParametrosMaximos.QuantidadeCaracteres = 128

    $Senha = New-SecurePassword @ParametrosMaximos

    if ($Senha.Length -ne 135) {
        throw "O comprimento total deveria ser 135 caracteres."
    }
}

Invoke-Test "Quantidade acima de 128 é rejeitada" {
    $Rejeitado = $false

    try {
        New-SecurePassword `
            -Prefixo "EMP" `
            -Data "2709" `
            -QuantidadeCaracteres 129 `
            -CaracteresEspeciais '!@#$%&*' | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "A quantidade acima de 128 deveria ser rejeitada."
    }
}

Invoke-Test "Prefixo vazio é rejeitado" {
    $Rejeitado = $false

    try {
        New-SecurePassword `
            -Prefixo "" `
            -Data "2709" `
            -QuantidadeCaracteres 12 `
            -CaracteresEspeciais '!@#$%&*' | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "O prefixo vazio deveria ser rejeitado."
    }
}

Invoke-Test "Data vazia é rejeitada" {
    $Rejeitado = $false

    try {
        New-SecurePassword `
            -Prefixo "EMP" `
            -Data "" `
            -QuantidadeCaracteres 12 `
            -CaracteresEspeciais '!@#$%&*' | Out-Null
    }
    catch {
        $Rejeitado = $true
    }

    if (-not $Rejeitado) {
        throw "A data vazia deveria ser rejeitada."
    }
}

# ============================================
# Resultado final
# ============================================

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " RESULTADO DOS TESTES - MODULO 01" -ForegroundColor Cyan
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