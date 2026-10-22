$ErrorActionPreference = "Stop"
$module = Import-Module (Join-Path $PSScriptRoot "Computer-Functions.psm1") -Force -PassThru
$global:PSAutomationTestPassed = 0
$global:PSAutomationTestFailed = 0

function Assert-Test {
    param([string]$Name, [bool]$Condition)
    if ($Condition) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
        $global:PSAutomationTestPassed++
    } else {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        $global:PSAutomationTestFailed++
    }
}

try {
    & $module {
        function Get-ComputerADInfo {
            param([string]$Hostname)
            if ($Hostname -eq "COMPUTER-THAT-DOES-NOT-EXIST-999999") {
                return [PSCustomObject]@{ Success=$false; Data=$null; Error="Falha AD simulada" }
            }
            [PSCustomObject]@{
                Success=$true; Error=$null
                Data=[PSCustomObject]@{ Found=$true; Name=$Hostname; Enabled=$true }
            }
        }

        function Get-ComputerCimInfo {
            param([string]$ComputerName)
            if ($ComputerName -eq "COMPUTER-THAT-DOES-NOT-EXIST-999999") {
                return [PSCustomObject]@{ Success=$false; Data=$null; Error="Falha CIM simulada" }
            }
            [PSCustomObject]@{
                Success=$true; Error=$null
                Data=[PSCustomObject]@{
                    System=[PSCustomObject]@{ Manufacturer="MOCK-OK"; Model="ModeloTeste"; SerialNumber="SERIAL-TESTE" }
                    OperatingSystem=[PSCustomObject]@{ Caption="Windows Teste" }
                    Processor=[PSCustomObject]@{ Name="CPU Teste" }
                    Memory=[PSCustomObject]@{ TotalGB=8 }
                    Storage=@([PSCustomObject]@{ DeviceID="C:"; SizeGB=100 })
                    Network=@([PSCustomObject]@{ Name="Rede Teste" })
                    BitLocker=[PSCustomObject]@{ Status="Simulado" }
                    Connectivity=[PSCustomObject]@{ Reachable=$true }
                }
            }
        }

        $cim = Get-ComputerCimInfo -ComputerName "TEST-PC-SIMULADO"
        $inventory = Get-ComputerInventory -ComputerName "TEST-PC-SIMULADO"
        $invalid = Get-ComputerInventory -ComputerName "COMPUTER-THAT-DOES-NOT-EXIST-999999"

        $checks = @(
            @{ Name="CIM simulado retorna sucesso"; Pass=($cim.Success -eq $true) }
            @{ Name="CIM inclui fabricante"; Pass=($cim.Data.System.Manufacturer -eq "MOCK-OK") }
            @{ Name="CIM inclui sistema operacional"; Pass=(-not [string]::IsNullOrWhiteSpace($cim.Data.OperatingSystem.Caption)) }
            @{ Name="CIM inclui processador"; Pass=(-not [string]::IsNullOrWhiteSpace($cim.Data.Processor.Name)) }
            @{ Name="CIM inclui memória"; Pass=($cim.Data.Memory.TotalGB -gt 0) }
            @{ Name="CIM inclui armazenamento"; Pass=($cim.Data.Storage.Count -gt 0) }
            @{ Name="CIM inclui rede"; Pass=($cim.Data.Network.Count -gt 0) }
            @{ Name="CIM inclui BitLocker"; Pass=(-not [string]::IsNullOrWhiteSpace($cim.Data.BitLocker.Status)) }
            @{ Name="CIM inclui conectividade"; Pass=($cim.Data.Connectivity.Reachable -eq $true) }
            @{ Name="Inventário retorna sucesso"; Pass=($inventory.Success -eq $true) }
            @{ Name="Hostname preservado"; Pass=($inventory.Data.Hostname -eq "TEST-PC-SIMULADO") }
            @{ Name="Data de coleta preenchida"; Pass=($null -ne $inventory.Data.CollectionDateTime) }
            @{ Name="Inventário inclui AD"; Pass=($null -ne $inventory.Data.AD) }
            @{ Name="Inventário inclui sistema"; Pass=($inventory.Data.System.Manufacturer -eq "MOCK-OK") }
            @{ Name="Inventário inclui Errors"; Pass=($null -ne $inventory.Data.Errors) }
            @{ Name="Inventário sem erros simulados"; Pass=($inventory.Data.Errors.Count -eq 0) }
            @{ Name="JSON gerado"; Pass=(-not [string]::IsNullOrWhiteSpace(($inventory.Data | ConvertTo-Json -Depth 8))) }
            @{ Name="Hostname inválido tratado"; Pass=($null -ne $invalid) }
            @{ Name="Falhas AD e CIM registradas"; Pass=($invalid.Data.Errors.Count -eq 2) }
            @{ Name="Falha total retorna Success false"; Pass=($invalid.Success -eq $false) }
        )

        foreach ($check in $checks) {
            if ($check.Pass) {
                Write-Host "[PASS] $($check.Name)" -ForegroundColor Green
                $global:PSAutomationTestPassed++
            } else {
                Write-Host "[FAIL] $($check.Name)" -ForegroundColor Red
                $global:PSAutomationTestFailed++
            }
        }
    }
} catch {
    Write-Host "[ERRO INESPERADO] $($_.Exception.Message)" -ForegroundColor Red
    $global:PSAutomationTestFailed++
} finally {
    Remove-Module $module.Name -ErrorAction SilentlyContinue
}

Write-Host "`n===== RESUMO DOS TESTES ISOLADOS =====" -ForegroundColor Cyan
Write-Host "Aprovados: $global:PSAutomationTestPassed"
Write-Host "Falhas: $global:PSAutomationTestFailed"
if ($global:PSAutomationTestFailed -gt 0) { exit 1 } else { exit 0 }


