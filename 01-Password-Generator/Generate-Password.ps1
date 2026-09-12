# ===========================================
# Enterprise Password Generator
# Author: Adriano Felix Lacerda
# ===========================================

Write-Host ""

# Localiza o módulo de configuração
$CaminhoModulo = Join-Path $PSScriptRoot "..\02-Configuration\Configuration.psm1"

# Verifica se o módulo existe
if (-not (Test-Path $CaminhoModulo))
{
    Write-Host ""
    Write-Host "Erro: Configuration.psm1 nao encontrado." -ForegroundColor Red
    exit
}

# Carrega o módulo de configuração
Import-Module $CaminhoModulo -Force

# Localiza o arquivo de configuração
$CaminhoConfig = Join-Path $PSScriptRoot "..\02-Configuration\config.json"

# Carrega e valida a configuração
try
{
    $Config = Get-Configuration -ConfigurationPath $CaminhoConfig
}
catch
{
    Write-Host ""
    Write-Host "Erro: Configuracao invalida." -ForegroundColor Red
    Write-Host ""

    $Erros = $_.Exception.Message -split " \| "

    foreach ($Erro in $Erros)
    {
        Write-Host "- $Erro" -ForegroundColor Red
    }

    Write-Host ""
    exit
}

# Função para gerar índice aleatório criptograficamente seguro
function Get-SecureRandomIndex
{
    param (
        [int]$Maximum
    )

    $Random = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    try
    {
        $Bytes = New-Object byte[] 4
        $Random.GetBytes($Bytes)

        $Numero = [BitConverter]::ToUInt32($Bytes, 0)

        return [int]($Numero % $Maximum)
    }
    finally
    {
        $Random.Dispose()
    }
}

# Obtém valores da configuração
$Prefixo = $Config.Prefixo
$QuantidadeCaracteres = $Config.QuantidadeCaracteres
$FormatoData = $Config.FormatoData
$Especiais = $Config.CaracteresEspeciais

# Obtém a data conforme configuração
$Data = Get-Date -Format $FormatoData

# Grupos de caracteres
$Maiusculas = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
$Minusculas = "abcdefghijklmnopqrstuvwxyz"
$Numeros = "0123456789"

# Seleciona um caractere obrigatório de cada grupo
$Obrigatorios = @(
    $Maiusculas[(Get-SecureRandomIndex -Maximum $Maiusculas.Length)]
    $Minusculas[(Get-SecureRandomIndex -Maximum $Minusculas.Length)]
    $Numeros[(Get-SecureRandomIndex -Maximum $Numeros.Length)]
    $Especiais[(Get-SecureRandomIndex -Maximum $Especiais.Length)]
)

# Embaralha os caracteres obrigatórios
$Embaralhados = New-Object System.Collections.Generic.List[string]

foreach ($Caractere in $Obrigatorios)
{
    $Embaralhados.Add($Caractere)
}

for ($i = $Embaralhados.Count - 1; $i -gt 0; $i--)
{
    $Posicao = Get-SecureRandomIndex -Maximum ($i + 1)

    $Temporario = $Embaralhados[$i]
    $Embaralhados[$i] = $Embaralhados[$Posicao]
    $Embaralhados[$Posicao] = $Temporario
}

# Junta todos os grupos
$Caracteres = $Maiusculas + $Minusculas + $Numeros + $Especiais

# Começa a parte aleatória
$ParteAleatoria = $Embaralhados -join ""

# Gera os caracteres restantes
for ($i = 4; $i -lt $QuantidadeCaracteres; $i++)
{
    $Posicao = Get-SecureRandomIndex -Maximum $Caracteres.Length
    $ParteAleatoria += $Caracteres[$Posicao]
}

# Monta a senha final
$Senha = $Prefixo + $Data + $ParteAleatoria

# Exibe o resultado
Write-Host ""

Write-Host "------------------------------------" -ForegroundColor Cyan
Write-Host "    Enterprise Password Generator  " -ForegroundColor Green
Write-Host "------------------------------------" -ForegroundColor Cyan

Write-Host ""

Write-Host "Prefixo: $Prefixo" -ForegroundColor Yellow
Write-Host "Data: $Data" -ForegroundColor Yellow
Write-Host "Caracteres aleatorios: $QuantidadeCaracteres" -ForegroundColor Yellow
Write-Host "Senha gerada: $Senha" -ForegroundColor Green

Write-Host ""