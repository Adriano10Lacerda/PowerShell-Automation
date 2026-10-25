
# ===========================================
# Enterprise Configuration Module
# Author: Adriano Felix Lacerda
# ===========================================

function Get-Configuration
{
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigurationPath
    )

    # Valida a existencia do arquivo
    if (-not (Test-Path -LiteralPath $ConfigurationPath -PathType Leaf))
    {
        throw "Arquivo de configuracao nao encontrado: $ConfigurationPath"
    }

    # Carrega e valida o JSON
    try
    {
        $Config = Get-Content -LiteralPath $ConfigurationPath -Raw |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch
    {
        throw "O arquivo de configuracao possui formato invalido."
    }

    $Erros = @()

    # Valida o prefixo
    if ([string]::IsNullOrWhiteSpace($Config.Prefixo))
    {
        $Erros += "O campo Prefixo nao pode ficar vazio."
    }

    # Valida a quantidade de caracteres aleatorios
    if ($null -eq $Config.QuantidadeCaracteres)
    {
        $Erros += "O campo QuantidadeCaracteres e obrigatorio."
    }
    else
    {
        $QuantidadeTexto = $Config.QuantidadeCaracteres.ToString()
        $QuantidadeInteira = 0

        $EhInteiro = [int]::TryParse(
            $QuantidadeTexto,
            [ref]$QuantidadeInteira
        )

        if (-not $EhInteiro)
        {
            $Erros += "QuantidadeCaracteres deve ser um numero inteiro."
        }
        elseif ($QuantidadeInteira -lt 4)
        {
            $Erros += "QuantidadeCaracteres deve ser no minimo 4."
        }
        elseif ($QuantidadeInteira -gt 128)
        {
            $Erros += "QuantidadeCaracteres deve ser no maximo 128."
        }
    }

    # Valida o formato da data
    if ([string]::IsNullOrWhiteSpace($Config.FormatoData))
    {
        $Erros += "O campo FormatoData nao pode ficar vazio."
    }
    else
    {
        # Formatos de data permitidos pela V1
        $FormatosDataPermitidos = @(
            "ddMM",
            "dd/MM/yyyy",
            "yyyy-MM-dd"
        )

        $FormatoDataValido = $false

        if ($Config.FormatoData -cin $FormatosDataPermitidos)
        {
            $FormatoDataValido = $true
        }

        if (-not $FormatoDataValido)
        {
            $Erros += "O campo FormatoData deve utilizar um dos formatos permitidos: ddMM, dd/MM/yyyy ou yyyy-MM-dd."
        }
        else
        {
            try
            {
                Get-Date -Format $Config.FormatoData -ErrorAction Stop |
                    Out-Null
            }
            catch
            {
                $Erros += "O campo FormatoData possui um formato invalido."
            }
        }
    }

    # Valida os caracteres especiais
    if ([string]::IsNullOrWhiteSpace($Config.CaracteresEspeciais))
    {
        $Erros += "O campo CaracteresEspeciais nao pode ficar vazio."
    }
    elseif ($Config.CaracteresEspeciais -match '[A-Za-z0-9\s]')
    {
        $Erros += "CaracteresEspeciais nao pode conter letras, numeros ou espacos."
    }

    # Interrompe se houver erros
    if ($Erros.Count -gt 0)
    {
        throw ($Erros -join " | ")
    }

    return $Config
}

Export-ModuleMember -Function Get-Configuration
