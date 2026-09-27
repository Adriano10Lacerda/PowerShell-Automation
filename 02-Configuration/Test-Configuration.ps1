
# ===========================================
# Enterprise Configuration - Automated Tests
# Author: Adriano Felix Lacerda
# ===========================================

$ErrorActionPreference = "Stop"

$CaminhoModulo = Join-Path $PSScriptRoot "Configuration.psm1"

Import-Module $CaminhoModulo -Force

$TotalTestes = 0
$TestesPassaram = 0
$TestesFalharam = 0

$DiretorioTemporario = Join-Path $env:TEMP (
    "ConfigurationTests_" + [guid]::NewGuid().ToString("N")
)

New-Item -Path $DiretorioTemporario -ItemType Directory -Force |
    Out-Null

function Invoke-Test {
    param (
        [string]$Nome,
        [scriptblock]$Acao
    )

    $script:TotalTestes++

    try {
        & $Acao

        Write-Host "[PASS] $Nome" -ForegroundColor Green
        $script:TestesPassaram++
    }
    catch {
        Write-Host "[FAIL] $Nome" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor DarkRed
        $script:TestesFalharam++
    }
}

function New-TestConfiguration {
    param (
        [hashtable]$Overrides = @{}
    )

    $Config = @{
        Prefixo = "EMP"
        QuantidadeCaracteres = 12
        FormatoData = "ddMM"
        CaracteresEspeciais = "!@#$%&*"
    }

    foreach ($Chave in $Overrides.Keys) {
        $Config[$Chave] = $Overrides[$Chave]
    }

    $CaminhoArquivo = Join-Path $DiretorioTemporario (
        [guid]::NewGuid().ToString("N") + ".json"
    )

    $Config |
        ConvertTo-Json |
        Set-Content -Path $CaminhoArquivo -Encoding utf8

    return $CaminhoArquivo
}

function Assert-ConfigurationThrows {
    param (
        [string]$Caminho
    )

    $ErroEsperado = $false

    try {
        Get-Configuration -ConfigurationPath $Caminho
    }
    catch {
        $ErroEsperado = $true
    }

    if (-not $ErroEsperado) {
        throw "Era esperado que a configuração fosse rejeitada."
    }
}

try {
    # 1. Configuração válida
    Invoke-Test "Configuração válida é aceita" {
        $Caminho = New-TestConfiguration

        $Config = Get-Configuration -ConfigurationPath $Caminho

        if ($Config.Prefixo -ne "EMP") {
            throw "Prefixo inesperado."
        }

        if ($Config.QuantidadeCaracteres -ne 12) {
            throw "Quantidade inesperada."
        }
    }

    # 2. Arquivo inexistente
    Invoke-Test "Arquivo inexistente é rejeitado" {
        $Caminho = Join-Path $DiretorioTemporario "inexistente.json"

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 3. JSON inválido
    Invoke-Test "JSON inválido é rejeitado" {
        $Caminho = Join-Path $DiretorioTemporario "invalido.json"

        Set-Content -Path $Caminho -Value "{ JSON inválido" -Encoding utf8

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 4. Prefixo vazio
    Invoke-Test "Prefixo vazio é rejeitado" {
        $Caminho = New-TestConfiguration @{
            Prefixo = ""
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 5. Quantidade ausente
    Invoke-Test "Quantidade ausente é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = $null
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 6. Quantidade não inteira
    Invoke-Test "Quantidade não inteira é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = "abc"
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 7. Quantidade abaixo do mínimo
    Invoke-Test "Quantidade abaixo de 4 é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = 3
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 8. Formato de data vazio
    Invoke-Test "Formato de data vazio é rejeitado" {
        $Caminho = New-TestConfiguration @{
            FormatoData = ""
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 9. Formato de data inválido
    Invoke-Test "Formato de data sem token válido é rejeitado" {
        $Caminho = New-TestConfiguration @{
            FormatoData = "abc"
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 10. Caracteres especiais vazios
    Invoke-Test "Caracteres especiais vazios são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = ""
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 11. Quantidade máxima permitida
    Invoke-Test "Quantidade máxima de 128 é aceita" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = 128
        }

        $Config = Get-Configuration -ConfigurationPath $Caminho

        if ($Config.QuantidadeCaracteres -ne 128) {
            throw "A quantidade máxima não foi preservada."
        }
    }

    # 12. Quantidade acima do máximo
    Invoke-Test "Quantidade acima de 128 é rejeitada" {
        $Caminho = New-TestConfiguration @{
            QuantidadeCaracteres = 129
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 13. Caracteres especiais com letras
    Invoke-Test "Caracteres especiais com letras são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = "!@#ABC"
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 14. Caracteres especiais com números
    Invoke-Test "Caracteres especiais com números são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = "!@#123"
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 15. Caracteres especiais com espaços
    Invoke-Test "Caracteres especiais com espaços são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = "!@# "
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 16. Prefixo ausente
    Invoke-Test "Prefixo ausente é rejeitado" {
        $Caminho = New-TestConfiguration @{
            Prefixo = $null
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }

    # 17. Caracteres especiais ausentes
    Invoke-Test "Caracteres especiais ausentes são rejeitados" {
        $Caminho = New-TestConfiguration @{
            CaracteresEspeciais = $null
        }

        Assert-ConfigurationThrows -Caminho $Caminho
    }
}
finally {
    if (Test-Path $DiretorioTemporario) {
        Remove-Item -Path $DiretorioTemporario -Recurse -Force
    }
}

Write-Host ""
Write-Host "============================================"
Write-Host " RESULTADO DOS TESTES - MODULO 02"
Write-Host "============================================"
Write-Host ""
Write-Host "Total de testes : $TotalTestes"
Write-Host "Passaram        : $TestesPassaram"
Write-Host "Falharam        : $TestesFalharam"
Write-Host ""

if ($TestesFalharam -eq 0) {
    Write-Host "STATUS: TODOS OS TESTES PASSARAM" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "STATUS: EXISTEM FALHAS" -ForegroundColor Red
    exit 1
}