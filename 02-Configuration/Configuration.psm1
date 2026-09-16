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

    if (-not (Test-Path $ConfigurationPath))
    {
        throw "Arquivo de configuracao nao encontrado: $ConfigurationPath"
    }

    try
    {
        $Config = Get-Content $ConfigurationPath -Raw | ConvertFrom-Json
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
    }

    # Valida o formato da data
    if ([string]::IsNullOrWhiteSpace($Config.FormatoData))
    {
        $Erros += "O campo FormatoData nao pode ficar vazio."
    }
    else
    {
        # Tokens de data/hora permitidos pelo projeto
        $TokensDataPermitidos = @(
            "d",
            "dd",
            "ddd",
            "dddd",
            "f",
            "ff",
            "fff",
            "ffff",
            "fffff",
            "ffffff",
            "fffffff",
            "F",
            "FF",
            "FFF",
            "FFFF",
            "FFFFF",
            "FFFFFF",
            "FFFFFFF",
            "g",
            "gg",
            "h",
            "hh",
            "H",
            "HH",
            "K",
            "m",
            "mm",
            "M",
            "MM",
            "MMM",
            "MMMM",
            "s",
            "ss",
            "t",
            "tt",
            "y",
            "yy",
            "yyy",
            "yyyy",
            "yyyyy",
            "yyyyyy",
            "yyyyyyy",
            "z",
            "zz",
            "zzz"
        )

        $FormatoDataValido = $false

        foreach ($Token in $TokensDataPermitidos)
        {
            if ($Config.FormatoData -match [regex]::Escape($Token))
            {
                $FormatoDataValido = $true
                break
            }
        }

        if (-not $FormatoDataValido)
        {
            $Erros += "O campo FormatoData nao possui um token de data valido."
        }
        else
        {
            try
            {
                Get-Date -Format $Config.FormatoData -ErrorAction Stop | Out-Null
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

    # Interrompe se houver erros
    if ($Erros.Count -gt 0)
    {
        throw ($Erros -join " | ")
    }

    return $Config
}

Export-ModuleMember -Function Get-Configuration