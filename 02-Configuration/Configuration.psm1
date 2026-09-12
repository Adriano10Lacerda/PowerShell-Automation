# ===========================================
# Enterprise Configuration Module
# Author: Adriano Felix Lacerda
# ===========================================

function Get-Configuration
{
    param (
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

    # Valida a quantidade
    if ($null -eq $Config.QuantidadeCaracteres)
    {
        $Erros += "O campo QuantidadeCaracteres e obrigatorio."
    }
    elseif ($Config.QuantidadeCaracteres -lt 4)
    {
        $Erros += "QuantidadeCaracteres deve ser no minimo 4."
    }

    # Valida o formato da data
    if ([string]::IsNullOrWhiteSpace($Config.FormatoData))
    {
        $Erros += "O campo FormatoData nao pode ficar vazio."
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