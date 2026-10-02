#Requires -Version 5.1

<#
.SYNOPSIS
    Funções principais do Audit Core V2.

.DESCRIPTION
    Camada responsável pela criação e validação
    de registros de auditoria.

    Princípios:
    - Não registra senhas.
    - Não registra credenciais.
    - Não executa ações administrativas.
    - Registro padronizado.
    - Compatível com Simulation Mode.
#>

Set-StrictMode -Version Latest

$modelsPath = Join-Path `
    $PSScriptRoot `
    "Audit-Models.ps1"

if (-not (Test-Path -LiteralPath $modelsPath)) {
    throw "Audit-Models.ps1 não encontrado: $modelsPath"
}

. $modelsPath

function New-AuditRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Action,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SamAccountName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Result,

        [Parameter()]
        [bool]$SimulationMode = $false,

        [Parameter()]
        [bool]$Changed = $false,

        [Parameter()]
        [string]$Operator = $env:USERNAME
    )

    try {

        if ([string]::IsNullOrWhiteSpace($Operator)) {
            $Operator = "Unknown"
        }

        $record = New-AuditRecordModel `
            -Action $Action `
            -SamAccountName $SamAccountName `
            -Result $Result `
            -SimulationMode $SimulationMode `
            -Changed $Changed `
            -Operator $Operator

        return [PSCustomObject]@{
            Success = $true
            Data    = $record
            Error   = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Data    = $null
            Error   = "Não foi possível criar o registro de auditoria. Detalhes: $($_.Exception.Message)"
        }
    }
}

function Test-AuditRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Record
    )

    try {

        if ($null -eq $Record) {
            return [PSCustomObject]@{
                Success = $false
                Data    = $false
                Error   = "O registro de auditoria não pode ser nulo."
            }
        }

        $requiredProperties = @(
            "Timestamp",
            "Operator",
            "Action",
            "SamAccountName",
            "Result",
            "SimulationMode",
            "Changed"
        )

        foreach ($property in $requiredProperties) {

            if ($Record.PSObject.Properties.Name -notcontains $property) {
                return [PSCustomObject]@{
                    Success = $false
                    Data    = $false
                    Error   = "Propriedade obrigatória ausente: $property"
                }
            }
        }

        if ($Record.PSObject.Properties.Name -contains "Password") {
            return [PSCustomObject]@{
                Success = $false
                Data    = $false
                Error   = "O registro de auditoria não pode conter senha."
            }
        }

        if ($Record.PSObject.Properties.Name -contains "Credential") {
            return [PSCustomObject]@{
                Success = $false
                Data    = $false
                Error   = "O registro de auditoria não pode conter credenciais."
            }
        }

        return [PSCustomObject]@{
            Success = $true
            Data    = $true
            Error   = $null
        }
    }
    catch {
        return [PSCustomObject]@{
            Success = $false
            Data    = $false
            Error   = "Erro ao validar registro de auditoria. Detalhes: $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function @(
    "New-AuditRecord",
    "Test-AuditRecord"
)
