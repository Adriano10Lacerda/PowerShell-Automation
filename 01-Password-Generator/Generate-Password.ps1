# ===========================================
# Enterprise Password Generator
# Author: Adriano Felix Lacerda
# ===========================================

Write-Host ""

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

# Solicita o prefixo
$Prefixo = Read-Host "Digite o prefixo"

# Valida o prefixo
if ([string]::IsNullOrWhiteSpace($Prefixo))
{
    Write-Host ""
    Write-Host "Erro: O prefixo nao pode ficar vazio." -ForegroundColor Red
    exit
}

# Solicita a quantidade de caracteres aleatórios
$EntradaQuantidade = Read-Host "Digite a quantidade de caracteres aleatorios"

# Valida se a entrada contém somente números
if ($EntradaQuantidade -notmatch '^\d+$')
{
    Write-Host ""
    Write-Host "Erro: Digite somente numeros." -ForegroundColor Red
    exit
}

# Converte a entrada para número
[int]$QuantidadeCaracteres = $EntradaQuantidade

# Valida a quantidade mínima
if ($QuantidadeCaracteres -lt 4)
{
    Write-Host ""
    Write-Host "Erro: A quantidade deve ser no minimo 4 caracteres." -ForegroundColor Red
    exit
}

# Obtém a data atual no formato DDMM
$Data = Get-Date -Format "ddMM"

# Grupos de caracteres
$Maiusculas = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
$Minusculas = "abcdefghijklmnopqrstuvwxyz"
$Numeros = "0123456789"
$Especiais = "!@#$%&*"

# Seleciona um caractere de cada grupo usando aleatoriedade segura
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

# Gera os caracteres restantes usando aleatoriedade segura
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