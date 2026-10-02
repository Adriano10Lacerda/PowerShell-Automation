Set-StrictMode -Version Latest

$script:ComputerCorePath = Join-Path $PSScriptRoot "..\Computer-Functions.psm1"

if (-not (Test-Path -LiteralPath $script:ComputerCorePath)) {
    throw "Computer Core não encontrado em: $script:ComputerCorePath"
}

Import-Module $script:ComputerCorePath -Force


function Get-ComputerManagement {
    <#
    .SYNOPSIS
        Consulta consolidada de um computador.

    .DESCRIPTION
        Utiliza o Computer Core para coletar informações de Active Directory,
        hardware, sistema operacional, processador, memória, armazenamento,
        rede, BitLocker e conectividade.

        O Management organiza o resultado do Core para consumo da interface
        e futuras ações administrativas.

    .PARAMETER Hostname
        Nome do computador que será consultado.

    .PARAMETER SimulationMode
        Mantém o contexto de Simulation Mode para futuras operações.
        A consulta atual é somente leitura.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname,

        [switch]$SimulationMode
    )

    $hostnameNormalized = $Hostname.Trim().ToUpperInvariant()

    if ([string]::IsNullOrWhiteSpace($hostnameNormalized)) {
        return [PSCustomObject]@{
            Success        = $false
            Hostname       = $Hostname
            SimulationMode = [bool]$SimulationMode
            Status         = "Invalid"
            Summary        = $null
            Data           = $null
            Errors         = @(
                [PSCustomObject]@{
                    Source  = "ComputerManagement"
                    Message = "Hostname não pode ser vazio."
                }
            )
        }
    }

    try {

        # ==================================================
        # COMPUTER CORE
        # ==================================================

        $coreResult = Get-ComputerInventory `
            -ComputerName $hostnameNormalized


        # ==================================================
        # VALIDAR RETORNO DO CORE
        # ==================================================

        if ($null -eq $coreResult) {
            return [PSCustomObject]@{
                Success        = $false
                Hostname       = $hostnameNormalized
                SimulationMode = [bool]$SimulationMode
                Status         = "Error"
                Summary        = $null
                Data           = $null
                Errors         = @(
                    [PSCustomObject]@{
                        Source  = "ComputerCore"
                        Message = "O Computer Core não retornou resultado."
                    }
                )
            }
        }


        # ==================================================
        # INVENTÁRIO REAL
        # ==================================================
        #
        # Get-ComputerInventory retorna:
        #
        # Success
        # Data
        # Error
        #
        # O inventário está dentro de Data.
        #

        $inventory = $coreResult.Data


        # ==================================================
        # ERROS
        # ==================================================

        $errors = @()

        if ($null -ne $coreResult.Error) {
            $errors += [PSCustomObject]@{
                Source  = "ComputerCore"
                Message = [string]$coreResult.Error
            }
        }

        if ($null -ne $inventory) {
            if ($null -ne $inventory.Errors) {
                $errors += @($inventory.Errors)
            }
        }


        # ==================================================
        # CASO O CORE NÃO TENHA DADOS
        # ==================================================

        if ($null -eq $inventory) {

            return [PSCustomObject]@{
                Success        = [bool]$coreResult.Success
                Hostname       = $hostnameNormalized
                SimulationMode = [bool]$SimulationMode
                Status         = "Unavailable"
                Summary        = $null
                Data           = $null
                Errors         = $errors
            }
        }


        # ==================================================
        # ACTIVE DIRECTORY
        # ==================================================

        $adFound = $false

        if ($null -ne $inventory.AD) {
            if ($null -ne $inventory.AD.Found) {
                $adFound = [bool]$inventory.AD.Found
            }
        }


        # ==================================================
        # CONNECTIVITY
        # ==================================================

        $reachable = $false

        if ($null -ne $inventory.Connectivity) {
            if ($null -ne $inventory.Connectivity.Reachable) {
                $reachable = [bool]$inventory.Connectivity.Reachable
            }
        }


        # ==================================================
        # STATUS OPERACIONAL
        # ==================================================

        $status = "Unknown"

        if ($adFound -and $reachable) {
            $status = "Online"
        }
        elseif ($adFound -and -not $reachable) {
            $status = "Offline"
        }
        elseif (-not $adFound -and $reachable) {
            $status = "ReachableOnly"
        }
        elseif (-not $adFound -and -not $reachable) {
            $status = "Unavailable"
        }


        # ==================================================
        # SISTEMA OPERACIONAL
        # ==================================================

        $operatingSystem = $null

        if ($null -ne $inventory.OperatingSystem) {
            $operatingSystem = $inventory.OperatingSystem.Caption
        }


        # ==================================================
        # MODELO
        # ==================================================

        $computerModel = $null

        if ($null -ne $inventory.System) {
            $computerModel = $inventory.System.Model
        }


        # ==================================================
        # MEMÓRIA
        # ==================================================

        $memoryGB = $null

        if ($null -ne $inventory.Memory) {
            $memoryGB = $inventory.Memory.TotalGB
        }


        # ==================================================
        # PROCESSADOR
        # ==================================================

        $processorName = $null

        if ($null -ne $inventory.Processor) {
            $processorName = $inventory.Processor.Name
        }


        # ==================================================
        # BITLOCKER
        # ==================================================

        $bitLockerStatus = "NotAvailable"

        if ($null -ne $inventory.BitLocker) {
            if ($null -ne $inventory.BitLocker.Status) {
                $bitLockerStatus = $inventory.BitLocker.Status
            }
        }


        # ==================================================
        # SUMMARY
        # ==================================================

        $summary = [PSCustomObject]@{
            Hostname        = $inventory.Hostname
            Status          = $status
            ADFound         = $adFound
            Reachable       = $reachable
            OperatingSystem = $operatingSystem
            Model           = $computerModel
            MemoryGB        = $memoryGB
            Processor       = $processorName
            BitLockerStatus = $bitLockerStatus
            ErrorCount      = $errors.Count
            SimulationMode  = [bool]$SimulationMode
        }


        # ==================================================
        # MANAGEMENT RESULT
        # ==================================================

        return [PSCustomObject]@{
            Success        = [bool]$coreResult.Success
            Hostname       = $inventory.Hostname
            SimulationMode = [bool]$SimulationMode
            Status         = $status
            Summary        = $summary
            Data           = $inventory
            Errors         = $errors
        }
    }
    catch {

        return [PSCustomObject]@{
            Success        = $false
            Hostname       = $hostnameNormalized
            SimulationMode = [bool]$SimulationMode
            Status         = "Error"
            Summary        = $null
            Data           = $null
            Errors         = @(
                [PSCustomObject]@{
                    Source  = "ComputerManagement"
                    Message = $_.Exception.Message
                }
            )
        }
    }
}


function Get-ComputerManagementSummary {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname,

        [switch]$SimulationMode
    )

    $result = Get-ComputerManagement `
        -Hostname $Hostname `
        -SimulationMode:$SimulationMode

    if ($null -eq $result) {
        return $null
    }

    return $result.Summary
}


function Test-ComputerManagement {

    [CmdletBinding()]
    param()

    $coreFunctionAvailable = $null -ne (
        Get-Command Get-ComputerInventory -ErrorAction SilentlyContinue
    )

    $managementFunctionAvailable = $null -ne (
        Get-Command Get-ComputerManagement -ErrorAction SilentlyContinue
    )

    [PSCustomObject]@{
        Success = (
            $coreFunctionAvailable -and
            $managementFunctionAvailable
        )

        ComputerCoreAvailable = $coreFunctionAvailable

        ManagementAvailable = $managementFunctionAvailable

        ModulePath = $PSCommandPath

        ComputerCorePath = $script:ComputerCorePath
    }
}


Export-ModuleMember -Function @(
    "Get-ComputerManagement",
    "Get-ComputerManagementSummary",
    "Test-ComputerManagement"
)