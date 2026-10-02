#Requires -Version 5.1

<#
.SYNOPSIS
    Modelos de auditoria do PowerShell Automation V2.
#>

function New-AuditRecordModel {
    [CmdletBinding()]
    param(
        [string]$Action,
        [string]$SamAccountName,
        [string]$Result,
        [bool]$SimulationMode,
        [bool]$Changed,
        [string]$Operator
    )

    return [PSCustomObject]@{
        Timestamp       = Get-Date
        Operator        = $Operator
        Action          = $Action
        SamAccountName  = $SamAccountName
        Result          = $Result
        SimulationMode  = $SimulationMode
        Changed         = $Changed
    }
}
