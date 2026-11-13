
# ===========================================
# Enterprise Configuration Module
# Author: Adriano Felix Lacerda
# ===========================================

function Get-Configuration
{
    [CmdletBinding(DefaultParameterSetName = 'TrustedPath')]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ConfigurationPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Confined')]
        [string]$ApprovedRoot,

        [Parameter(Mandatory = $true, ParameterSetName = 'Confined')]
        [string]$ApprovedRootIdentity
    )

    if ($PSCmdlet.ParameterSetName -eq 'Confined')
    {
        try
        {
            $workspaceModule = Join-Path (Split-Path -Parent $PSScriptRoot) 'Validation/ConfinedWorkspace.psm1'
            if (-not [System.IO.File]::Exists($workspaceModule)) {
                throw [System.IO.FileNotFoundException]::new('Confined workspace validator is unavailable.')
            }
            Import-Module -Name $workspaceModule -ErrorAction Stop
            $literalPath = Resolve-ConfinedWorkspacePath `
                -Root $ApprovedRoot `
                -Identity $ApprovedRootIdentity `
                -Path $ConfigurationPath
        }
        catch
        {
            $cause = $_.Exception.GetBaseException()
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                $cause, 'Configuration.UnsafePath', 'SecurityError', $ConfigurationPath))
        }
    }

    try
    {
        if ($PSCmdlet.ParameterSetName -eq 'Confined')
        {
            $stream = [System.IO.File]::Open($literalPath, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                $reader = [System.IO.StreamReader]::new(
                    $stream, [System.Text.UTF8Encoding]::new($false, $true), $true, 1024, $true)
                try { $json = $reader.ReadToEnd() }
                finally { $reader.Dispose() }
            }
            finally { $stream.Dispose() }
        }
        else
        {
            $json = Get-Content -LiteralPath $ConfigurationPath -Raw -ErrorAction Stop
        }
    }
    catch
    {
        $cause = $_.Exception.GetBaseException()
        if ($cause -is [System.Text.DecoderFallbackException]) {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.FormatException]::new('O arquivo de configuracao nao possui texto UTF-8 valido.', $cause),
                'Configuration.InvalidJson', 'InvalidData', $ConfigurationPath))
        }
        if ($cause -is [System.IO.FileNotFoundException] -or
            $cause -is [System.IO.DirectoryNotFoundException] -or
            $cause -is [System.Management.Automation.ItemNotFoundException])
        {
            $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new("Arquivo de configuracao nao encontrado: $ConfigurationPath", $cause),
                'Configuration.NotFound', 'ObjectNotFound', $ConfigurationPath))
        }
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.IOException]::new("Falha ao ler o arquivo de configuracao: $ConfigurationPath", $cause),
            'Configuration.ReadFailed', 'ReadError', $ConfigurationPath))
    }

    try
    {
        if ([string]::IsNullOrWhiteSpace($json))
        {
            throw [System.FormatException]::new('JSON vazio.')
        }
        $Config = ConvertFrom-Json -InputObject $json -ErrorAction Stop
    }
    catch
    {
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.FormatException]::new('O arquivo de configuracao possui formato invalido.', $_.Exception),
            'Configuration.InvalidJson', 'InvalidData', $ConfigurationPath))
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
        $PSCmdlet.ThrowTerminatingError([System.Management.Automation.ErrorRecord]::new(
            [System.IO.InvalidDataException]::new(($Erros -join ' | ')),
            'Configuration.InvalidSchema', 'InvalidData', $ConfigurationPath))
    }

    return $Config
}

Export-ModuleMember -Function Get-Configuration
