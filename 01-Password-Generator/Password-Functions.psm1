
# ============================================
# Enterprise Password Generator - Functions
# Author: Adriano Felix Lacerda
# ============================================

Set-StrictMode -Version Latest

# ============================================
# Gera um índice aleatório criptograficamente seguro
# ============================================

function Get-SecureRandomIndex {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Maximum
    )

    return [System.Security.Cryptography.RandomNumberGenerator]::GetInt32($Maximum)
}

# ============================================
# Gera uma senha segura
# ============================================

function New-SecurePassword {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Prefixo,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Data,

        [Parameter(Mandatory = $true)]
        [ValidateRange(4, 128)]
        [int]$QuantidadeCaracteres,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$CaracteresEspeciais
    )

    # ============================================
    # Validações de entrada
    # ============================================

    if ([string]::IsNullOrWhiteSpace($Prefixo)) {
        throw "O prefixo não pode ficar vazio."
    }

    if ([string]::IsNullOrWhiteSpace($Data)) {
        throw "A data não pode ficar vazia."
    }

    if ([string]::IsNullOrWhiteSpace($CaracteresEspeciais)) {
        throw "Os caracteres especiais não podem ficar vazios."
    }

    if ($CaracteresEspeciais -match '[A-Za-z0-9\s]') {
        throw "A lista de caracteres especiais não pode conter letras, números ou espaços."
    }

    # ============================================
    # Grupos de caracteres
    # ============================================

    $Maiusculas = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $Minusculas = "abcdefghijklmnopqrstuvwxyz"
    $Numeros = "0123456789"

    # ============================================
    # Seleciona um caractere obrigatório de cada grupo
    # ============================================

    $Obrigatorios = @(
        $Maiusculas[(Get-SecureRandomIndex -Maximum $Maiusculas.Length)]
        $Minusculas[(Get-SecureRandomIndex -Maximum $Minusculas.Length)]
        $Numeros[(Get-SecureRandomIndex -Maximum $Numeros.Length)]
        $CaracteresEspeciais[(Get-SecureRandomIndex -Maximum $CaracteresEspeciais.Length)]
    )

    # ============================================
    # Embaralha os caracteres obrigatórios
    # ============================================

    $Embaralhados = [System.Collections.Generic.List[string]]::new()

    foreach ($Caractere in $Obrigatorios) {
        $Embaralhados.Add([string]$Caractere)
    }

    for ($i = $Embaralhados.Count - 1; $i -gt 0; $i--) {
        $Posicao = Get-SecureRandomIndex -Maximum ($i + 1)

        $Temporario = $Embaralhados[$i]
        $Embaralhados[$i] = $Embaralhados[$Posicao]
        $Embaralhados[$Posicao] = $Temporario
    }

    # ============================================
    # Combina os grupos de caracteres
    # ============================================

    $Caracteres = $Maiusculas + $Minusculas + $Numeros + $CaracteresEspeciais

    # ============================================
    # Gera a parte aleatória da senha
    # ============================================

    $ParteAleatoria = $Embaralhados -join ""

    for ($i = 4; $i -lt $QuantidadeCaracteres; $i++) {
        $Posicao = Get-SecureRandomIndex -Maximum $Caracteres.Length
        $ParteAleatoria += $Caracteres[$Posicao]
    }

    # ============================================
    # Retorna a senha completa
    # ============================================

    return ($Prefixo + $Data + $ParteAleatoria)
}

# ============================================
# Exporta as funções públicas do módulo
# ============================================

Export-ModuleMember -Function Get-SecureRandomIndex, New-SecurePassword