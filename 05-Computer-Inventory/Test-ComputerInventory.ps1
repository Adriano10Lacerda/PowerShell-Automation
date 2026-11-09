
# ============================================
# Test-ComputerInventory.ps1
# PowerShell Automation
# Testes do modulo Computer Inventory
# ============================================

$ErrorActionPreference = "Stop"
Import-Module Microsoft.PowerShell.Management -ErrorAction Stop
Import-Module Microsoft.PowerShell.Utility -ErrorAction Stop
$global:PSModuleAutoLoadingPreference = 'None'
Write-Output 'HARNESS_START:COMPUTER_INVENTORY_V1'

if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) {
    throw "ActiveDirectory já está carregado neste processo; o teste será interrompido."
}

$ModulePath = Join-Path $PSScriptRoot "Inventory-Functions.psm1"
$ConfigPath = Join-Path $PSScriptRoot "Inventory-Configuration.example.json"

function Assert-InventoryProjectFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $Root = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd([char[]]@('\', '/'))
    $FullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not [System.IO.Path]::IsPathFullyQualified($Path) -or
        $Path.StartsWith('\\') -or $Path.StartsWith('//') -or
        $Path.StartsWith('\\?\') -or $Path.StartsWith('\\.\') -or
        $FullPath.StartsWith('\\') -or
        [System.IO.Path]::GetPathRoot($FullPath).StartsWith('\\')) {
        throw "Caminho local absoluto exigido para entrada: $Path"
    }
    $VolumeRoot = [System.IO.Path]::GetPathRoot($FullPath)
    if ($FullPath.Substring($VolumeRoot.Length).Contains(':')) {
        throw "ADS ou fluxo alternativo recusado para entrada: $FullPath"
    }
    $RootPrefix = $Root + [System.IO.Path]::DirectorySeparatorChar
    if (-not $FullPath.StartsWith($RootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Arquivo de entrada fora da pasta do teste: $FullPath"
    }

    $CurrentPath = $VolumeRoot
    foreach ($Segment in @($FullPath.Substring($VolumeRoot.Length) -split '[\\/]+' | Where-Object { $_ })) {
        $CurrentPath = Join-Path -Path $CurrentPath -ChildPath $Segment
        try {
            $Attributes = [System.IO.File]::GetAttributes($CurrentPath)
        }
        catch [System.IO.FileNotFoundException] { break }
        catch [System.IO.DirectoryNotFoundException] { break }
        if (($Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Entrada atravessa reparse point: $CurrentPath"
        }
    }

    if (-not [System.IO.File]::Exists($FullPath)) {
        throw "Arquivo de entrada ausente: $FullPath"
    }
    return $FullPath
}

$ModulePath = Assert-InventoryProjectFile -Path $ModulePath
$ConfigPath = Assert-InventoryProjectFile -Path $ConfigPath

$TotalTests = 0
$PassedTests = 0
$FailedTests = 0

function Invoke-Test {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Test
    )

    $script:TotalTests++

    try {
        & $Test
        $script:PassedTests++
        Write-Host "PASSOU - $Name" -ForegroundColor Green
    }
    catch {
        $script:FailedTests++
        Write-Host "FALHOU - $Name" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
    }
}

Write-Host "`n=== TESTES - COMPUTER INVENTORY ===" -ForegroundColor Cyan

Invoke-Test -Name "Modulo encontrado" -Test {
    if (-not (Test-Path $ModulePath)) {
        throw "Modulo nao encontrado."
    }
}

Invoke-Test -Name "Configuracao JSON valida" -Test {
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuracao nao encontrada."
    }

    $config = [System.IO.File]::ReadAllText($ConfigPath) | ConvertFrom-Json

    if ($null -eq $config.Inventory -or $null -eq $config.Output) {
        throw "Secoes Inventory ou Output ausentes."
    }
}

Import-Module $ModulePath -Force

$inventoryModules = @(Get-Module | Where-Object { $_.Path -eq [System.IO.Path]::GetFullPath($ModulePath) })
if ($inventoryModules.Count -ne 1) {
    throw "Esperada uma instância Inventory-Functions; encontradas $($inventoryModules.Count)."
}
$inventoryModule = $inventoryModules[0]

$inventoryExternalCallCounts = @{
        GetCimInstance = 0
        GetBitLockerVolume = 0
        GetCommand = 0
        GetModule = 0
        ImportModule = 0
}

# Install through the module's actual SessionState. A scriptblock invoked with
# `& $ModuleInfo { ... }` can run in a transient scope and is not proof that a
# `Function:\script:` entry was added to the module instance.
$inventoryModule.SessionState.InvokeCommand.InvokeScript($true, {
    param($Counters)
    $script:ExternalCallCounts = $Counters

    Set-Item Function:\script:Get-CimInstance -Value ({
        # V1-HARNESS:CIM-STUB
        param([string]$ClassName, [string]$Filter, [string]$ErrorAction)
        $Counters.GetCimInstance++
        if ($ClassName -eq '__V1_HARNESS_SENTINEL__') {
            return [PSCustomObject]@{ Sentinel = 'V1-HARNESS:CIM-STUB' }
        }
        switch ($ClassName) {
            'Win32_ComputerSystem' { return [PSCustomObject]@{ Name='FIXTURE-PC'; UserName='fixture\user'; Manufacturer='Fixture'; Model='Model'; TotalPhysicalMemory=17179869184 } }
            'Win32_ComputerSystemProduct' { return [PSCustomObject]@{ IdentifyingNumber='FIXTURE-SERIAL' } }
            'Win32_BIOS' { return [PSCustomObject]@{ SMBIOSBIOSVersion='FIXTURE-BIOS' } }
            'Win32_OperatingSystem' { return [PSCustomObject]@{ Caption='Fixture OS'; Version='0.0'; BuildNumber='0'; OSArchitecture='x64'; InstallDate=$null; LastBootUpTime=$null } }
            'Win32_Processor' { return @([PSCustomObject]@{ Name='Fixture CPU'; NumberOfCores=2; NumberOfLogicalProcessors=4; MaxClockSpeed=2000 }) }
            'Win32_LogicalDisk' { return @([PSCustomObject]@{ DriveType=3; DeviceID='C:'; VolumeName='Fixture'; FileSystem='NTFS'; Size=1073741824; FreeSpace=536870912 }) }
            'Win32_NetworkAdapterConfiguration' { return @([PSCustomObject]@{ Description='Fixture NIC'; IPAddress=@('192.0.2.10','2001:db8::10'); MACAddress='00-00-5E-00-53-01'; DefaultIPGateway=@('192.0.2.1'); DNSServerSearchOrder=@('192.0.2.53') }) }
            default { throw "Get-CimInstance inesperado bloqueado: $ClassName" }
        }
    }.GetNewClosure()) -Force
    Set-Item Function:\script:Get-Command -Value ({
        # V1-HARNESS:COMMAND-LOOKUP-STUB
        param([string]$Name, [string]$ErrorAction)
        $Counters.GetCommand++
        if ($Name -ne 'Get-BitLockerVolume') { throw "Get-Command inesperado bloqueado: $Name" }
        [PSCustomObject]@{ Name='Get-BitLockerVolume'; CommandType='Function'; Definition='V1-HARNESS:BITLOCKER-STUB' }
    }.GetNewClosure()) -Force
    Set-Item Function:\script:Get-BitLockerVolume -Value ({
        # V1-HARNESS:BITLOCKER-STUB
        param([string]$ErrorAction)
        $Counters.GetBitLockerVolume++
        @([PSCustomObject]@{ MountPoint='C:'; VolumeStatus='FullyEncrypted'; EncryptionMethod='Fixture'; ProtectionStatus='On'; LockStatus='Unlocked' })
    }.GetNewClosure()) -Force
    Set-Item Function:\script:Get-Module -Value ({
        # V1-HARNESS:MODULE-LOOKUP-FAIL-CLOSED
        param([string]$Name, [switch]$ListAvailable, [string]$ErrorAction)
        $Counters.GetModule++
        throw "Get-Module inesperado bloqueado: $Name"
    }.GetNewClosure()) -Force
    Set-Item Function:\script:Import-Module -Value ({
        # V1-HARNESS:MODULE-IMPORT-FAIL-CLOSED
        param([string]$Name, [string]$FullyQualifiedName, [switch]$Force, [string]$ErrorAction)
        $Counters.ImportModule++
        throw "Import-Module inesperado bloqueado: $Name"
    }.GetNewClosure()) -Force
}, $null, @($inventoryExternalCallCounts)) | Out-Null

$inventoryStubResolution = $inventoryModule.SessionState.InvokeCommand.InvokeScript($true, {
    $Cim1 = Microsoft.PowerShell.Core\Get-Command Get-CimInstance -CommandType Function -ErrorAction SilentlyContinue
    $Cim2 = Microsoft.PowerShell.Core\Get-Command Get-CimInstance -CommandType Function -ErrorAction SilentlyContinue
    $BitLocker = Microsoft.PowerShell.Core\Get-Command Get-BitLockerVolume -CommandType Function -ErrorAction SilentlyContinue
    $CommandLookup = Microsoft.PowerShell.Core\Get-Command Get-Command -CommandType Function -ErrorAction SilentlyContinue
    $ModuleLookup = Microsoft.PowerShell.Core\Get-Command Get-Module -CommandType Function -ErrorAction SilentlyContinue
    $Loader = Microsoft.PowerShell.Core\Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        Cim = $Cim1
        CimSameInstance = [object]::ReferenceEquals($Cim1, $Cim2)
        BitLocker = $BitLocker
        CommandLookup = $CommandLookup
        ModuleLookup = $ModuleLookup
        Loader = $Loader
        CimSentinel = $Cim1.Definition -match 'V1-HARNESS:CIM-STUB'
        BitLockerSentinel = $BitLocker.Definition -match 'V1-HARNESS:BITLOCKER-STUB'
        CommandLookupSentinel = $CommandLookup.Definition -match 'V1-HARNESS:COMMAND-LOOKUP-STUB'
        ModuleLookupSentinel = $ModuleLookup.Definition -match 'V1-HARNESS:MODULE-LOOKUP-FAIL-CLOSED'
        LoaderSentinel = $Loader.Definition -match 'V1-HARNESS:MODULE-IMPORT-FAIL-CLOSED'
        CimSignature = $Cim1.Parameters.ContainsKey('ClassName')
        BitLockerSignature = $BitLocker.Parameters.ContainsKey('ErrorAction')
    }
}, $null, @())
if ($inventoryStubResolution.Cim.CommandType -ne 'Function' -or
    -not $inventoryStubResolution.CimSameInstance -or
    $inventoryStubResolution.BitLocker.CommandType -ne 'Function' -or
    $inventoryStubResolution.CommandLookup.CommandType -ne 'Function' -or
    $inventoryStubResolution.ModuleLookup.CommandType -ne 'Function' -or
    $inventoryStubResolution.Loader.CommandType -ne 'Function' -or
    -not $inventoryStubResolution.CimSentinel -or
    -not $inventoryStubResolution.BitLockerSentinel -or
    -not $inventoryStubResolution.CommandLookupSentinel -or
    -not $inventoryStubResolution.ModuleLookupSentinel -or
    -not $inventoryStubResolution.LoaderSentinel -or
    -not $inventoryStubResolution.CimSignature -or
    -not $inventoryStubResolution.BitLockerSignature) {
    throw "Resolução incompleta dos stubs no SessionState do Inventory-Functions."
}
$inventoryCountsAtGate = $inventoryModule.SessionState.InvokeCommand.InvokeScript(
    $true,
    { @{} + $script:ExternalCallCounts },
    $null,
    @()
)
if ($inventoryCountsAtGate.GetCimInstance -ne 0 -or
    $inventoryCountsAtGate.GetBitLockerVolume -ne 0 -or
    $inventoryCountsAtGate.GetCommand -ne 0 -or
    $inventoryCountsAtGate.GetModule -ne 0 -or
    $inventoryCountsAtGate.ImportModule -ne 0) {
    throw "Uma fronteira foi chamada durante a instalação ou verificação do gate."
}

function Assert-TestPathWithinRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    foreach ($candidate in @($Path, $Root)) {
        if ([string]::IsNullOrWhiteSpace($candidate) -or
            $candidate.StartsWith('\\') -or
            $candidate.StartsWith('//') -or
            $candidate.StartsWith('\\?\') -or
            $candidate.StartsWith('\\.\') -or
            $candidate.StartsWith('\??\') -or
            $candidate -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "Caminho ambíguo, externo ou com traversal recusado: $candidate"
        }

        $colonIndexes = @()
        for ($index = 0; $index -lt $candidate.Length; $index++) {
            if ($candidate[$index] -eq ':') { $colonIndexes += $index }
        }
        $isDrivePrefix = $colonIndexes.Count -eq 1 -and $colonIndexes[0] -eq 1 -and
            $candidate.Length -gt 2 -and $candidate[2] -eq [System.IO.Path]::DirectorySeparatorChar
        if ($colonIndexes.Count -gt 0 -and -not $isDrivePrefix) {
            throw "ADS ou caminho com prefixo de dispositivo recusado: $candidate"
        }
    }

    if (-not [System.IO.Path]::IsPathFullyQualified($Root) -or
        -not [System.IO.Path]::IsPathFullyQualified($Path)) {
        throw 'Raiz e destino devem ser caminhos locais absolutos.'
    }

    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd([System.IO.Path]::DirectorySeparatorChar)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $rootPrefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Caminho fora da raiz temporária autorizada: $fullPath"
    }

    Assert-TestPathNoReparsePoints -Path $fullRoot
    Assert-TestPathNoReparsePoints -Path $fullPath
    return $fullPath
}

function Assert-TestPathNoReparsePoints {
    param([Parameter(Mandatory)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $volumeRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrWhiteSpace($volumeRoot) -or $fullPath.StartsWith('\\')) {
        throw "Caminho não local recusado: $fullPath"
    }

    $currentPath = $volumeRoot
    $remaining = $fullPath.Substring($volumeRoot.Length)
    foreach ($segment in @($remaining -split '[\\/]+' | Where-Object { $_ })) {
        $currentPath = Join-Path -Path $currentPath -ChildPath $segment
        try {
            $attributes = [System.IO.File]::GetAttributes($currentPath)
        }
        catch [System.IO.FileNotFoundException] { break }
        catch [System.IO.DirectoryNotFoundException] { break }
        catch {
            throw "Não foi possível verificar o caminho '$currentPath': $($_.Exception.Message)"
        }

        if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse point recusado no caminho: $currentPath"
        }
    }
}

function Assert-TestDirectoryTreeNoReparsePoints {
    param([Parameter(Mandatory)][string]$Root)

    $fullRoot = [System.IO.Path]::GetFullPath($Root)
    Assert-TestPathNoReparsePoints -Path $fullRoot
    if (-not [System.IO.Directory]::Exists($fullRoot)) {
        throw "A raiz de limpeza não existe: $fullRoot"
    }

    $pendingDirectories = New-Object 'System.Collections.Generic.Stack[string]'
    $pendingDirectories.Push($fullRoot)
    while ($pendingDirectories.Count -gt 0) {
        $directory = $pendingDirectories.Pop()
        foreach ($entry in [System.IO.Directory]::GetFileSystemEntries($directory)) {
            try {
                $attributes = [System.IO.File]::GetAttributes($entry)
            }
            catch {
                throw "Não foi possível verificar item antes da limpeza '$entry': $($_.Exception.Message)"
            }

            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Limpeza recursiva bloqueada: reparse point encontrado em '$entry'."
            }
            if (($attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                $pendingDirectories.Push($entry)
            }
        }
    }
}

function Remove-InventoryTestTree {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$AllowedParent
    )

    $FullRoot = Assert-TestPathWithinRoot -Path $Root -Root $AllowedParent
    if (-not [System.IO.Directory]::Exists($FullRoot)) { return }
    Assert-TestDirectoryTreeNoReparsePoints -Root $FullRoot

    $Pending = New-Object 'System.Collections.Generic.Stack[string]'
    $Pending.Push($FullRoot)
    while ($Pending.Count -gt 0) {
        $CurrentDirectory = $Pending.Peek()
        $CurrentAttributes = [System.IO.File]::GetAttributes($CurrentDirectory)
        if (($CurrentAttributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($CurrentAttributes -band [System.IO.FileAttributes]::Directory) -eq 0) {
            throw "Limpeza interrompida porque o diretório mudou de identidade: $CurrentDirectory"
        }
        $Children = @([System.IO.Directory]::GetFileSystemEntries($CurrentDirectory))
        if ($Children.Count -gt 0) {
            $Child = $Children[0]
            $null = Assert-TestPathWithinRoot -Path $Child -Root $FullRoot
            $Attributes = [System.IO.File]::GetAttributes($Child)
            if (($Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Limpeza interrompida diante de reparse point: $Child"
            }
            if (($Attributes -band [System.IO.FileAttributes]::Directory) -ne 0) {
                $Pending.Push($Child)
            }
            else {
                [System.IO.File]::Delete($Child)
            }
            continue
        }

        $Attributes = [System.IO.File]::GetAttributes($CurrentDirectory)
        if (($Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Limpeza interrompida diante de reparse point: $CurrentDirectory"
        }
        $null = $Pending.Pop()
        [System.IO.Directory]::Delete($CurrentDirectory, $false)
    }
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
if (-not [System.IO.Directory]::Exists($tempRoot)) {
    throw "Diretório temporário não existe: $tempRoot"
}
Assert-TestPathNoReparsePoints -Path $tempRoot
$tempRootItem = Get-Item -LiteralPath $tempRoot -Force -ErrorAction Stop
if (($tempRootItem.Attributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
    ($tempRootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Diretório temporário não é uma raiz local segura: $tempRoot"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$config.SimulationMode = $true

Invoke-Test -Name "SimulationMode não booleano é rejeitado" -Test {
    $invalidConfig = $config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $invalidConfig.SimulationMode = "true"

    $rejected = $false
    try {
        Get-ComputerInventory -Configuration $invalidConfig -ErrorAction Stop |
            Out-Null
    }
    catch {
        $rejected = $_.Exception.Message -match "SimulationMode"
    }

    if (-not $rejected) {
        throw "Uma configuração sem SimulationMode Boolean deveria ser rejeitada."
    }
}

Invoke-Test -Name "Coleta real exige autorização explícita" -Test {
    $realConfig = $config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $realConfig.SimulationMode = $false

    $rejected = $false
    try {
        Get-ComputerInventory -Configuration $realConfig -ErrorAction Stop |
            Out-Null
    }
    catch {
        $rejected = $_.Exception.Message -match "AllowRealOperation"
    }

    if (-not $rejected) {
        throw "A coleta real deveria ser bloqueada sem -AllowRealOperation."
    }
}

Invoke-Test -Name "Exportação respeita WhatIf sem criar arquivos" -Test {
    $whatIfConfig = $config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $whatIfConfig.SimulationMode = $false
    $whatIfConfig.Output.Directory = Join-Path $tempRoot (
        "Inventory-WhatIf-" + [guid]::NewGuid().ToString("N")
    )
    $null = Assert-TestPathWithinRoot -Path $whatIfConfig.Output.Directory -Root $tempRoot
    $whatIfConfig.Output.Formats = @("JSON")
    $whatIfInventory = Get-ComputerInventory -Configuration $config

    $result = Export-ComputerInventory `
        -Inventory $whatIfInventory `
        -Configuration $whatIfConfig `
        -AllowedRoot $tempRoot `
        -AllowRealOperation `
        -WhatIf

    if ($result.Success -ne $false -or
        (Test-Path -LiteralPath $whatIfConfig.Output.Directory)) {
        throw "WhatIf deveria recusar a gravação e não criar arquivos."
    }
}
Invoke-Test -Name "Coleta simulada identificada" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($inventory.SimulationMode -ne $true) {
        throw "O inventario nao identificou o modo de simulacao."
    }
}

Invoke-Test -Name "Dados ficticios do computador" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.ComputerSystem -and
        $inventory.ComputerSystem.ComputerName -ne "SIMULATED-PC") {
        throw "Identificacao simulada inesperada."
    }
}

Invoke-Test -Name "Sistema operacional simulado" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.OperatingSystem -and
        $inventory.OperatingSystem.OperatingSystem -ne "Windows (Simulacao)") {
        throw "Sistema operacional simulado inesperado."
    }
}

Invoke-Test -Name "Processador simulado" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.Processor -and
        $inventory.Processor.ProcessorName -ne "CPU de Demonstracao") {
        throw "Processador simulado inesperado."
    }
}

Invoke-Test -Name "Memoria simulada" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.Memory -and
        $inventory.Memory.TotalMemoryGB -ne 16) {
        throw "Memoria simulada inesperada."
    }
}

Invoke-Test -Name "Disco simulado" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.Disk -and @($inventory.Disk).Count -eq 0) {
        throw "Nenhum disco simulado retornado."
    }
}

Invoke-Test -Name "Rede simulada" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.Network -and @($inventory.Network).Count -eq 0) {
        throw "Nenhum adaptador simulado retornado."
    }
}

Invoke-Test -Name "BitLocker sem consulta real" -Test {
    $inventory = Get-ComputerInventory -Configuration $config

    if ($config.Inventory.BitLocker -and
        $inventory.BitLocker.Message -notlike "*nao foi consultado*") {
        throw "A resposta simulada do BitLocker nao corresponde ao esperado."
    }
}

Invoke-Test -Name "Exportacao simulada sem arquivos" -Test {
    $inventory = Get-ComputerInventory -Configuration $config
    $result = Export-ComputerInventory -Inventory $inventory -Configuration $config

    if ($result.Success -ne $true) {
        throw "A simulacao da exportacao falhou."
    }

    if (@($result.Files).Count -ne 0) {
        throw "A simulacao informou arquivos gerados."
    }

    if ($null -ne $result.Directory) {
        throw "A simulacao informou um diretorio de saida."
    }

    if ($result.SimulationMode -ne $true) {
        throw "O resultado nao identificou o modo de simulacao."
    }
}

$inventoryCountersBeforeAuthorizedFixture = $inventoryModule.SessionState.InvokeCommand.InvokeScript(
    $true, { @{} + $script:ExternalCallCounts }, $null, @()
)
Invoke-Test -Name "Coleta autorizada usa somente fixtures CIM e BitLocker" -Test {
    $fixtureConfig = $config | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $fixtureConfig.SimulationMode = $false
    $fixtureInventory = Get-ComputerInventory -Configuration $fixtureConfig -AllowRealOperation

    if ($fixtureInventory.ComputerSystem.ComputerName -ne 'FIXTURE-PC' -or
        $fixtureInventory.OperatingSystem.OperatingSystem -ne 'Fixture OS' -or
        $fixtureInventory.Processor.ProcessorName -ne 'Fixture CPU' -or
        $fixtureInventory.BitLocker.Volumes[0].MountPoint -ne 'C:') {
        throw "A coleta autorizada não retornou as fixtures sintéticas esperadas."
    }

    $fixtureCounters = $inventoryModule.SessionState.InvokeCommand.InvokeScript(
        $true, { @{} + $script:ExternalCallCounts }, $null, @()
    )
    if ($fixtureCounters.GetCimInstance -le 0 -or $fixtureCounters.GetBitLockerVolume -le 0 -or
        $fixtureCounters.GetCommand -le 0 -or $fixtureCounters.GetModule -ne 0 -or $fixtureCounters.ImportModule -ne 0) {
        throw "As fronteiras autorizadas não foram atendidas exclusivamente pelos stubs esperados."
    }
}
$inventoryCountersAfterAuthorizedFixture = $inventoryModule.SessionState.InvokeCommand.InvokeScript(
    $true, { @{} + $script:ExternalCallCounts }, $null, @()
)


# ============================================
# Testes adicionais de exportação (dados fictícios)
# ============================================

$testRoot = Join-Path $tempRoot (
    "PSAutomation-InventoryTests-" + [guid]::NewGuid().ToString("N")
)
$testRoot = [System.IO.Path]::GetFullPath($testRoot)
$null = Assert-TestPathWithinRoot -Path $testRoot -Root $tempRoot
if (Test-Path -LiteralPath $testRoot) {
    throw "A raiz temporária exclusiva do teste já existe; execução bloqueada."
}
$testRootOwned = $false

try {
    New-Item -ItemType Directory -Path $testRoot -ErrorAction Stop | Out-Null
    $testRootOwned = $true
    Assert-TestPathNoReparsePoints -Path $testRoot
    $null = Assert-TestPathWithinRoot -Path (Join-Path $testRoot 'Output') -Root $testRoot

    $configExport = $config | ConvertTo-Json -Depth 20 |
        ConvertFrom-Json

    $configExport.SimulationMode = $true
    $inventoryExport = Get-ComputerInventory -Configuration $configExport

    Invoke-Test -Name "Exportação real sem autorização falha antes de criar a raiz" -Test {
        $unauthorizedConfig = $configExport | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $unauthorizedConfig.SimulationMode = $false
        $unauthorizedConfig.Output.Directory = "Unauthorized"
        $unauthorized = $false
        try {
            Export-ComputerInventory `
                -Inventory $inventoryExport `
                -Configuration $unauthorizedConfig `
                -AllowedRoot $testRoot `
                -ErrorAction Stop |
                Out-Null
        }
        catch {
            $unauthorized = $_.Exception.Message -match "AllowRealOperation"
        }
        $unauthorizedDestination = Join-Path $testRoot 'Unauthorized'
        if (-not $unauthorized -or (Test-Path -LiteralPath $unauthorizedDestination)) {
            throw "A exportação sem autorização deveria falhar antes de criar seu destino."
        }
    }

    Invoke-Test -Name "ComputerName malicioso é rejeitado antes de qualquer escrita" -Test {
        $maliciousInventory = $inventoryExport | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $maliciousInventory.ComputerSystem.ComputerName = '..\..\outside'
        $syntheticRoot = Join-Path $testRoot ("Inventory-FakeRoot-" + [guid]::NewGuid().ToString('N'))
        $null = Assert-TestPathWithinRoot -Path $syntheticRoot -Root $testRoot

        $inventoryModule.SessionState.InvokeCommand.InvokeScript($true, {
            $script:ExportMutationCounters = @{
                NewItem = 0
                SetContent = 0
                ExportCsv = 0
            }

            Set-Item Function:\script:Get-Item -Value {
                # V1-HARNESS:EXPORT-GET-ITEM-STUB
                [CmdletBinding()]
                param([string]$LiteralPath, [switch]$Force, [string]$ErrorAction)
                $fullPath = [System.IO.Path]::GetFullPath($LiteralPath)
                [PSCustomObject]@{
                    FullName = $fullPath
                    Attributes = [System.IO.FileAttributes]::Directory
                    PSIsContainer = $true
                }
            } -Force

            Set-Item Function:\script:Test-Path -Value {
                # V1-HARNESS:EXPORT-TEST-PATH-STUB
                [CmdletBinding()]
                param([string]$LiteralPath, [switch]$PathType, [string]$ErrorAction)
                return $true
            } -Force

            Set-Item Function:\script:New-Item -Value {
                # V1-HARNESS:EXPORT-NEW-ITEM-FAIL-CLOSED
                [CmdletBinding()]
                param([string]$ItemType, [string]$Path, [string]$ErrorAction)
                $script:ExportMutationCounters.NewItem++
                throw "New-Item inesperado bloqueado: $Path"
            } -Force

            Set-Item Function:\script:Set-Content -Value {
                # V1-HARNESS:EXPORT-SET-CONTENT-FAIL-CLOSED
                [CmdletBinding()]
                param([string]$Path, [string]$LiteralPath, [string]$Encoding, [string]$ErrorAction)
                $script:ExportMutationCounters.SetContent++
                throw "Set-Content inesperado bloqueado: $Path"
            } -Force

            Set-Item Function:\script:Export-Csv -Value {
                # V1-HARNESS:EXPORT-CSV-FAIL-CLOSED
                [CmdletBinding()]
                param([string]$Path, [string]$LiteralPath, [switch]$NoTypeInformation, [string]$Encoding, [string]$ErrorAction)
                $script:ExportMutationCounters.ExportCsv++
                throw "Export-Csv inesperado bloqueado: $Path"
            } -Force
            $Names = @('Get-Item', 'Test-Path', 'New-Item', 'Set-Content', 'Export-Csv')
            $Gate = foreach ($Name in $Names) {
                $First = Microsoft.PowerShell.Core\Get-Command $Name -CommandType Function -ErrorAction Stop
                $Second = Microsoft.PowerShell.Core\Get-Command $Name -CommandType Function -ErrorAction Stop
                [PSCustomObject]@{
                    Name = $Name
                    CommandType = $First.CommandType
                    SameInstance = [object]::ReferenceEquals($First, $Second)
                    Sentinel = $First.Definition -match 'V1-HARNESS:EXPORT-'
                }
            }
            if (@($Gate | Where-Object {
                $_.CommandType -ne 'Function' -or -not $_.SameInstance -or -not $_.Sentinel
            }).Count -ne 0) {
                throw 'Gate de stubs de filesystem não foi comprovado no SessionState efetivo.'
            }
            if ($script:ExportMutationCounters.NewItem -ne 0 -or
                $script:ExportMutationCounters.SetContent -ne 0 -or
                $script:ExportMutationCounters.ExportCsv -ne 0) {
                throw 'Uma mutação de arquivo ocorreu durante a instalação dos stubs.'
            }
        }, $null, @()) | Out-Null

        try {
            $maliciousConfig = $configExport | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $maliciousConfig.SimulationMode = $false
            $maliciousConfig.Output.Directory = 'Reports'
            $maliciousConfig.Output.Formats = @('JSON', 'CSV')

            $result = Export-ComputerInventory `
                -Inventory $maliciousInventory `
                -Configuration $maliciousConfig `
                -AllowedRoot $syntheticRoot `
                -AllowRealOperation `
                -Confirm:$false

            $writeCounts = $inventoryModule.SessionState.InvokeCommand.InvokeScript(
                $true,
                { @{} + $script:ExportMutationCounters },
                $null,
                @()
            )
            if ($result.Success -ne $false -or $result.Message -notmatch 'segmento de nome de arquivo') {
                throw "ComputerName malicioso não foi rejeitado: $($result.Message)"
            }
            if ($writeCounts.NewItem -ne 0 -or $writeCounts.SetContent -ne 0 -or $writeCounts.ExportCsv -ne 0) {
                throw "Houve tentativa de escrita antes da rejeição: $($writeCounts | ConvertTo-Json -Compress)"
            }
        }
        finally {
            $inventoryModule.SessionState.InvokeCommand.InvokeScript($true, {
                foreach ($name in @('Get-Item', 'Test-Path', 'New-Item', 'Set-Content', 'Export-Csv')) {
                    Microsoft.PowerShell.Management\Remove-Item `
                        -LiteralPath ("Function:\script:" + $name) `
                        -ErrorAction SilentlyContinue
                }
                Microsoft.PowerShell.Utility\Remove-Variable `
                    -Name ExportMutationCounters `
                    -Scope Script `
                    -ErrorAction SilentlyContinue
            }, $null, @()) | Out-Null
        }
    }

    Invoke-Test -Name "Destinos externos, UNC, traversal, dispositivo e ADS falham fechado" -Test {
        $outsidePath = Join-Path $tempRoot ("Inventory-Outside-" + [guid]::NewGuid().ToString("N"))
        $invalidPaths = @(
            '..\Escape',
            '\\server\share',
            '\\?\C:\Windows',
            '\Device\HarddiskVolume1\Windows',
            'Reports:stream',
            $outsidePath
        )

        foreach ($invalidPath in $invalidPaths) {
            $invalidConfig = $configExport | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $invalidConfig.SimulationMode = $false
            $invalidConfig.Output.Directory = $invalidPath
            $invalidConfig.Output.Formats = @('JSON')
            $result = Export-ComputerInventory `
                -Inventory $inventoryExport `
                -Configuration $invalidConfig `
                -AllowedRoot $testRoot `
                -AllowRealOperation `
                -WhatIf

            if ($result.Success -ne $false -or [string]::IsNullOrWhiteSpace($result.Message)) {
                throw "Destino inválido não foi rejeitado: $invalidPath"
            }
        }
    }

    Invoke-Test -Name "Destino com reparse point é rejeitado" -Test {
        $targetDirectory = Join-Path $testRoot 'ReparseTarget'
        $junctionDirectory = Join-Path $testRoot 'ReparseOutput'
        $null = Assert-TestPathWithinRoot -Path $targetDirectory -Root $testRoot
        $null = Assert-TestPathWithinRoot -Path $junctionDirectory -Root $testRoot
        if ([System.IO.Directory]::Exists($targetDirectory) -or [System.IO.File]::Exists($targetDirectory) -or
            [System.IO.Directory]::Exists($junctionDirectory) -or [System.IO.File]::Exists($junctionDirectory)) {
            throw 'O caminho do teste de reparse point já existe; criação bloqueada.'
        }
        $targetCreated = $false
        $junctionCreated = $false
        try {
            New-Item -ItemType Directory -Path $targetDirectory -ErrorAction Stop | Out-Null
            $targetCreated = $true
            New-Item -ItemType Junction -Path $junctionDirectory -Target $targetDirectory -ErrorAction Stop |
                Out-Null
            $junctionCreated = $true
            $junctionConfig = $configExport | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            $junctionConfig.SimulationMode = $false
            $junctionConfig.Output.Directory = Join-Path $junctionDirectory 'Reports'
            $junctionResult = Export-ComputerInventory `
                -Inventory $inventoryExport `
                -Configuration $junctionConfig `
                -AllowedRoot $testRoot `
                -AllowRealOperation `
                -WhatIf

            if ($junctionResult.Success -ne $false -or $junctionResult.Message -notmatch 'reparse point') {
                throw "A exportação através de junction deveria ser rejeitada antes da escrita."
            }
        }
        finally {
            if ($junctionCreated) {
                $junctionItem = Get-Item -LiteralPath $junctionDirectory -Force -ErrorAction Stop
                if (($junctionItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0 -or
                    $junctionItem.LinkType -ne 'Junction') {
                    throw 'O item criado para o teste não corresponde à junction esperada; remoção bloqueada.'
                }
                Remove-Item -LiteralPath $junctionDirectory -Force -ErrorAction Stop
            }
            if ($targetCreated -and [System.IO.Directory]::Exists($targetDirectory)) {
                Assert-TestDirectoryTreeNoReparsePoints -Root $targetDirectory
                [System.IO.Directory]::Delete($targetDirectory, $false)
            }
        }
    }

    Invoke-Test -Name "Exportação JSON válida" -Test {
        $configJson = $configExport | ConvertTo-Json -Depth 20 |
            ConvertFrom-Json
        $configJson.SimulationMode = $false
        $configJson.Output.Directory = Join-Path $testRoot "JSON"
        $null = Assert-TestPathWithinRoot -Path $configJson.Output.Directory -Root $testRoot
        $configJson.Output.Formats = @("JSON")

        $result = Export-ComputerInventory `
            -Inventory $inventoryExport `
            -Configuration $configJson `
            -AllowedRoot $testRoot `
            -AllowRealOperation `
            -Confirm:$false

        if (-not $result.Success -or @($result.Files).Count -ne 1) {
            throw "A exportação JSON não retornou exatamente um arquivo."
        }

        $null = Assert-TestPathWithinRoot -Path $result.Files[0] -Root $testRoot

        $json = Get-Content -LiteralPath $result.Files[0] -Raw |
            ConvertFrom-Json -ErrorAction Stop

        if ($json.ComputerSystem.ComputerName -ne "SIMULATED-PC") {
            throw "O JSON não contém o computador fictício esperado."
        }
    }

    Invoke-Test -Name "Exportação CSV válida com 18 colunas" -Test {
        $configCsv = $configExport | ConvertTo-Json -Depth 20 |
            ConvertFrom-Json
        $configCsv.SimulationMode = $false
        $configCsv.Output.Directory = Join-Path $testRoot "CSV"
        $null = Assert-TestPathWithinRoot -Path $configCsv.Output.Directory -Root $testRoot
        $configCsv.Output.Formats = @("CSV")

        $result = Export-ComputerInventory `
            -Inventory $inventoryExport `
            -Configuration $configCsv `
            -AllowedRoot $testRoot `
            -AllowRealOperation `
            -Confirm:$false

        if (-not $result.Success -or @($result.Files).Count -ne 1) {
            throw "A exportação CSV não retornou exatamente um arquivo."
        }

        $null = Assert-TestPathWithinRoot -Path $result.Files[0] -Root $testRoot

        $rows = @(Import-Csv -LiteralPath $result.Files[0] -ErrorAction Stop)

        if ($rows.Count -ne 1) {
            throw "O CSV deveria conter exatamente um registro."
        }

        if (@($rows[0].PSObject.Properties).Count -ne 18) {
            throw "O CSV não contém as 18 colunas esperadas."
        }

        if ($rows[0].ComputerName -ne "SIMULATED-PC") {
            throw "O CSV não contém o computador fictício esperado."
        }
    }

    Invoke-Test -Name "Exportação para caminho absoluto" -Test {
        $configAbs = $configExport | ConvertTo-Json -Depth 20 |
            ConvertFrom-Json
        $configAbs.SimulationMode = $false
        $configAbs.Output.Directory = Join-Path $testRoot "Absolute"
        $null = Assert-TestPathWithinRoot -Path $configAbs.Output.Directory -Root $testRoot
        $configAbs.Output.Formats = @("JSON", "CSV")

        $result = Export-ComputerInventory `
            -Inventory $inventoryExport `
            -Configuration $configAbs `
            -AllowedRoot $testRoot `
            -AllowRealOperation `
            -Confirm:$false

        if (-not $result.Success) {
            throw "Falha no caminho absoluto: $($result.Message)"
        }

        if (@($result.Files).Count -ne 2) {
            throw "Esperados dois arquivos no caminho absoluto."
        }

        foreach ($file in $result.Files) {
            $null = Assert-TestPathWithinRoot -Path $file -Root $testRoot
            if (-not (Test-Path -LiteralPath $file)) {
                throw "Arquivo não encontrado: $file"
            }
        }
    }

    Invoke-Test -Name "Diretório inválido tratado como falha" -Test {
        $configInvalid = $configExport | ConvertTo-Json -Depth 20 |
            ConvertFrom-Json
        $configInvalid.SimulationMode = $false
        $configInvalid.Output.Directory = " "
        $configInvalid.Output.Formats = @("JSON")

        $result = Export-ComputerInventory `
            -Inventory $inventoryExport `
            -Configuration $configInvalid `
            -AllowedRoot $testRoot `
            -AllowRealOperation `
            -Confirm:$false

        if ($result.Success -ne $false) {
            throw "A função deveria informar falha para diretório vazio."
        }

        if ([string]::IsNullOrWhiteSpace($result.Message)) {
            throw "A função deveria retornar uma mensagem de erro."
        }
    }
}
finally {
    if ($testRootOwned) {
        $validatedRoot = Assert-TestPathWithinRoot -Path $testRoot -Root $tempRoot
        if (-not [System.IO.Directory]::Exists($validatedRoot)) {
            throw "A raiz criada pelo teste desapareceu antes da limpeza; cleanup recusado: $validatedRoot"
        }
        Remove-InventoryTestTree -Root $validatedRoot -AllowedParent $tempRoot
    }
}

$inventoryCounters = $inventoryModule.SessionState.InvokeCommand.InvokeScript(
    $true, { @{} + $script:ExternalCallCounts }, $null, @()
)
foreach ($counterName in $inventoryCounters.Keys) {
    if ($inventoryCounters[$counterName] -ne $inventoryCountersAfterAuthorizedFixture[$counterName]) {
        throw "Fronteira de coleta chamada novamente depois do cenário fixture: $counterName"
    }
}
if (($inventoryCountersBeforeAuthorizedFixture.GetCimInstance + $inventoryCountersBeforeAuthorizedFixture.GetBitLockerVolume) -ne 0) {
    throw "Simulation/Preview/autorização ausente alcançou CIM ou BitLocker antes do cenário autorizado com fixtures."
}

Remove-Module Inventory-Functions -ErrorAction SilentlyContinue
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "Total: $TotalTests | Passaram: $PassedTests | Falharam: $FailedTests"
Write-Host "============================================" -ForegroundColor Cyan

if ($FailedTests -gt 0) {
    throw "Existem testes com falha."
}
Write-Output 'HARNESS_PASS:COMPUTER_INVENTORY_V1'
