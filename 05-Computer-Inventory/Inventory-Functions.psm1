# ============================================
# Inventory-Functions.psm1
# PowerShell Automation
# Módulo de Inventário de Computadores
# ============================================

function Get-ComputerSystemInventory {

    try {

        $ComputerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $ComputerProduct = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop
        $BIOS = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop

        return [PSCustomObject]@{
            ComputerName = $ComputerSystem.Name
            LoggedOnUser = $ComputerSystem.UserName
            Manufacturer = $ComputerSystem.Manufacturer
            Model = $ComputerSystem.Model
            SerialNumber = $ComputerProduct.IdentifyingNumber
            BIOSVersion = $BIOS.SMBIOSBIOSVersion
        }
    }
    catch {

        return [PSCustomObject]@{
            ComputerName = $env:COMPUTERNAME
            LoggedOnUser = $null
            Manufacturer = $null
            Model = $null
            SerialNumber = $null
            BIOSVersion = $null
            Error = $_.Exception.Message
        }
    }
}


function Get-OperatingSystemInventory {

    try {

        $OperatingSystem = Get-CimInstance `
            -ClassName Win32_OperatingSystem `
            -ErrorAction Stop

        return [PSCustomObject]@{
            OperatingSystem = $OperatingSystem.Caption
            Version = $OperatingSystem.Version
            Build = $OperatingSystem.BuildNumber
            Architecture = $OperatingSystem.OSArchitecture
            InstallDate = $OperatingSystem.InstallDate
            LastBootUpTime = $OperatingSystem.LastBootUpTime
        }
    }
    catch {

        return [PSCustomObject]@{
            OperatingSystem = $null
            Version = $null
            Build = $null
            Architecture = $null
            InstallDate = $null
            LastBootUpTime = $null
            Error = $_.Exception.Message
        }
    }
}


function Get-ProcessorInventory {

    try {

        $Processor = Get-CimInstance `
            -ClassName Win32_Processor `
            -ErrorAction Stop

        $Processors = @($Processor)

        $Name = (
            $Processors |
            Select-Object -ExpandProperty Name -Unique
        ) -join " | "

        $Cores = (
            $Processors |
            Measure-Object -Property NumberOfCores -Sum
        ).Sum

        $LogicalProcessors = (
            $Processors |
            Measure-Object -Property NumberOfLogicalProcessors -Sum
        ).Sum

        $MaxClockSpeed = (
            $Processors |
            Measure-Object -Property MaxClockSpeed -Maximum
        ).Maximum

        return [PSCustomObject]@{
            ProcessorName = $Name
            PhysicalCores = $Cores
            LogicalProcessors = $LogicalProcessors
            MaxClockSpeedMHz = $MaxClockSpeed
        }
    }
    catch {

        return [PSCustomObject]@{
            ProcessorName = $null
            PhysicalCores = $null
            LogicalProcessors = $null
            MaxClockSpeedMHz = $null
            Error = $_.Exception.Message
        }
    }
}


function Get-MemoryInventory {

    try {

        $ComputerSystem = Get-CimInstance `
            -ClassName Win32_ComputerSystem `
            -ErrorAction Stop

        $TotalMemoryGB = [math]::Round(
            $ComputerSystem.TotalPhysicalMemory / 1GB,
            2
        )

        return [PSCustomObject]@{
            TotalMemoryGB = $TotalMemoryGB
        }
    }
    catch {

        return [PSCustomObject]@{
            TotalMemoryGB = $null
            Error = $_.Exception.Message
        }
    }
}


function Get-DiskInventory {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    try {

        $Disks = Get-CimInstance `
            -ClassName Win32_LogicalDisk `
            -ErrorAction Stop

        $Results = @()

        foreach ($Disk in $Disks) {

            if (
                $Disk.DriveType -eq 3 -and
                $Configuration.Disk.IncludeFixedDrives -eq $true
            ) {

                $Results += [PSCustomObject]@{
                    Drive = $Disk.DeviceID
                    VolumeName = $Disk.VolumeName
                    FileSystem = $Disk.FileSystem
                    SizeGB = [math]::Round($Disk.Size / 1GB, 2)
                    FreeSpaceGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
                    UsedSpaceGB = [math]::Round(
                        ($Disk.Size - $Disk.FreeSpace) / 1GB,
                        2
                    )
                    DriveType = "Fixed"
                }
            }

            if (
                $Disk.DriveType -eq 2 -and
                $Configuration.Disk.IncludeRemovableDrives -eq $true
            ) {

                $Results += [PSCustomObject]@{
                    Drive = $Disk.DeviceID
                    VolumeName = $Disk.VolumeName
                    FileSystem = $Disk.FileSystem
                    SizeGB = [math]::Round($Disk.Size / 1GB, 2)
                    FreeSpaceGB = [math]::Round($Disk.FreeSpace / 1GB, 2)
                    UsedSpaceGB = [math]::Round(
                        ($Disk.Size - $Disk.FreeSpace) / 1GB,
                        2
                    )
                    DriveType = "Removable"
                }
            }
        }

        return @($Results)
    }
    catch {

        return @(
            [PSCustomObject]@{
                Drive = $null
                VolumeName = $null
                FileSystem = $null
                SizeGB = $null
                FreeSpaceGB = $null
                UsedSpaceGB = $null
                DriveType = $null
                Error = $_.Exception.Message
            }
        )
    }
}


function Get-NetworkInventory {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    try {

        $Adapters = Get-CimInstance `
            -ClassName Win32_NetworkAdapterConfiguration `
            -Filter "IPEnabled = True" `
            -ErrorAction Stop

        $Results = @()

        foreach ($Adapter in $Adapters) {

            $IPv4Addresses = @()

            if ($Configuration.Network.IncludeIPv4 -eq $true) {

                $IPv4Addresses = @(
                    $Adapter.IPAddress |
                    Where-Object {
                        $_ -match '^\d{1,3}(\.\d{1,3}){3}$'
                    }
                )
            }

            $IPv6Addresses = @()

            if ($Configuration.Network.IncludeIPv6 -eq $true) {

                $IPv6Addresses = @(
                    $Adapter.IPAddress |
                    Where-Object {
                        $_ -match ':'
                    }
                )
            }

            $MACAddress = $null

            if ($Configuration.Network.IncludeMACAddress -eq $true) {

                $MACAddress = $Adapter.MACAddress
            }

            $Results += [PSCustomObject]@{
                Description = $Adapter.Description
                MACAddress = $MACAddress
                IPv4Address = $IPv4Addresses -join ", "
                IPv6Address = $IPv6Addresses -join ", "
                DefaultGateway = $Adapter.DefaultIPGateway -join ", "
                DNSServers = $Adapter.DNSServerSearchOrder -join ", "
            }
        }

        return @($Results)
    }
    catch {

        return @(
            [PSCustomObject]@{
                Description = $null
                MACAddress = $null
                IPv4Address = $null
                IPv6Address = $null
                DefaultGateway = $null
                DNSServers = $null
                Error = $_.Exception.Message
            }
        )
    }
}


function Get-BitLockerInventory {

    try {

        if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {

            return [PSCustomObject]@{
                Status = "Unavailable"
                Available = $false
                Volumes = @()
                Message = "O comando Get-BitLockerVolume não está disponível neste computador."
            }
        }

        try {

            $Volumes = Get-BitLockerVolume -ErrorAction Stop
        }
        catch {

            return [PSCustomObject]@{
                Status = "Error"
                Available = $false
                Volumes = @()
                Message = $_.Exception.Message
            }
        }

        $Results = @()

        foreach ($Volume in $Volumes) {

            $Results += [PSCustomObject]@{
                MountPoint = $Volume.MountPoint
                VolumeStatus = $Volume.VolumeStatus
                EncryptionMethod = $Volume.EncryptionMethod
                ProtectionStatus = $Volume.ProtectionStatus
                LockStatus = $Volume.LockStatus
            }
        }

        return [PSCustomObject]@{
            Status = "Success"
            Available = $true
            Volumes = @($Results)
            Message = "Informações de BitLocker coletadas com sucesso."
        }
    }
    catch {

        return [PSCustomObject]@{
            Status = "Error"
            Available = $false
            Volumes = @()
            Message = $_.Exception.Message
        }
    }
}


function Get-ComputerInventory {

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [switch]$AllowRealCollection
    )

    if ($Configuration.SimulationMode -isnot [bool]) {
        throw "SimulationMode deve ser definido explicitamente como Boolean."
    }

    if (-not $Configuration.SimulationMode) {
        if (-not $AllowRealCollection -and -not $WhatIfPreference) {
            throw "Coleta real bloqueada. Informe -AllowRealCollection explicitamente."
        }
        if (-not $PSCmdlet.ShouldProcess(
                [string]$env:COMPUTERNAME,
                'Coletar inventário local via CIM e BitLocker')) {
            return [PSCustomObject]@{
                CollectionDateTime = $null
                SimulationMode = $false
                CollectionStatus = 'Preview'
                ComputerSystem = $null
                OperatingSystem = $null
                Processor = $null
                Memory = $null
                Disk = @()
                Network = @()
                BitLocker = $null
                Message = 'Coleta não executada; ShouldProcess/WhatIf recusou a operação.'
            }
        }
        if (-not $AllowRealCollection) {
            throw "Coleta real bloqueada. Informe -AllowRealCollection explicitamente."
        }
    }

    $ComputerSystem = $null
    $OperatingSystem = $null
    $Processor = $null
    $Memory = $null
    $Disk = @()
    $Network = @()
    $BitLocker = $null


    if ($Configuration.SimulationMode -eq $true) {

        $ComputerSystem = $null
        $OperatingSystem = $null
        $Processor = $null
        $Memory = $null
        $Disk = @()
        $Network = @()
        $BitLocker = $null

        if ($Configuration.Inventory.ComputerSystem -eq $true) {
            $ComputerSystem = [PSCustomObject]@{
                ComputerName = "SIMULATED-PC"
                LoggedOnUser = "DEMO\Usuario"
                Manufacturer = "Fabricante de Demonstracao"
                Model = "Modelo de Demonstracao"
                SerialNumber = "SIM-000001"
                BIOSVersion = "SIM-1.0"
            }
        }

        if ($Configuration.Inventory.OperatingSystem -eq $true) {
            $OperatingSystem = [PSCustomObject]@{
                OperatingSystem = "Windows (Simulacao)"
                Version = "0.0"
                Build = "00000"
                Architecture = "64-bit"
            }
        }

        if ($Configuration.Inventory.Processor -eq $true) {
            $Processor = [PSCustomObject]@{
                ProcessorName = "CPU de Demonstracao"
                PhysicalCores = 4
                LogicalProcessors = 8
            }
        }

        if ($Configuration.Inventory.Memory -eq $true) {
            $Memory = [PSCustomObject]@{
                TotalMemoryGB = 16
            }
        }

        if ($Configuration.Inventory.Disk -eq $true) {
            $Disk = @(
                [PSCustomObject]@{
                    Drive = "C:"
                    SizeGB = 256
                    FreeSpaceGB = 128
                }
            )
        }

        if ($Configuration.Inventory.Network -eq $true) {
            $Network = @(
                [PSCustomObject]@{
                    Description = "Adaptador de Rede de Demonstracao"
                    IPv4Address = "192.0.2.10"
                    MACAddress = "00-00-00-00-00-01"
                }
            )
        }

        if ($Configuration.Inventory.BitLocker -eq $true) {
            $BitLocker = [PSCustomObject]@{
                Status = "Unavailable"
                Available = $false
                Volumes = @()
                Message = "Dados ficticios: BitLocker nao foi consultado."
            }
        }

        return [PSCustomObject]@{
            CollectionDateTime = (Get-Date).ToUniversalTime().ToString("o")
            SimulationMode = $true
            CollectionStatus = 'Simulated'
            ComputerSystem = $ComputerSystem
            OperatingSystem = $OperatingSystem
            Processor = $Processor
            Memory = $Memory
            Disk = @($Disk)
            Network = @($Network)
            BitLocker = $BitLocker
        }
    }


    if ($Configuration.Inventory.ComputerSystem -eq $true) {

        $ComputerSystem = Get-ComputerSystemInventory
    }

    if ($Configuration.Inventory.OperatingSystem -eq $true) {

        $OperatingSystem = Get-OperatingSystemInventory
    }

    if ($Configuration.Inventory.Processor -eq $true) {

        $Processor = Get-ProcessorInventory
    }

    if ($Configuration.Inventory.Memory -eq $true) {

        $Memory = Get-MemoryInventory
    }

    if ($Configuration.Inventory.Disk -eq $true) {

        $Disk = Get-DiskInventory `
            -Configuration $Configuration
    }

    if ($Configuration.Inventory.Network -eq $true) {

        $Network = Get-NetworkInventory `
            -Configuration $Configuration
    }

    if ($Configuration.Inventory.BitLocker -eq $true) {

        $BitLocker = Get-BitLockerInventory
    }

    return [PSCustomObject]@{
        CollectionDateTime = (Get-Date).ToUniversalTime().ToString("o")
        SimulationMode = $false
        CollectionStatus = 'Completed'
        ComputerSystem = $ComputerSystem
        OperatingSystem = $OperatingSystem
        Processor = $Processor
        Memory = $Memory
        Disk = @($Disk)
        Network = @($Network)
        BitLocker = $BitLocker
    }
}


function Assert-ComputerInventoryPathSyntax {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ParameterName
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -ne $Path.Trim()) {
        throw "$ParameterName contém um caminho vazio ou ambíguo."
    }

    $normalizedPath = $Path.Replace('/', '\')
    if ($normalizedPath.StartsWith('\\') -or
        $normalizedPath.StartsWith('\??\') -or
        $normalizedPath.StartsWith('\Device\')) {
        throw "$ParameterName não pode usar namespace de dispositivo ou caminho UNC."
    }
    $isDriveAbsolute = $normalizedPath -match '^[A-Za-z]:\\'
    if ($normalizedPath -match '^[A-Za-z]:(?!\\)') {
        throw "$ParameterName não pode usar caminho relativo a unidade."
    }
    if ($normalizedPath.StartsWith('\') -and -not $isDriveAbsolute) {
        throw "$ParameterName deve usar um caminho relativo ou absoluto em unidade local."
    }

    $segments = @($normalizedPath.Split([char]92) | Where-Object { $_ -ne '' })
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $segment = $segments[$index]

        if ($segment -eq '.' -or $segment -eq '..') {
            throw "$ParameterName não pode conter segmentos '.' ou '..'."
        }

        if ($isDriveAbsolute -and $index -eq 0 -and $segment -match '^[A-Za-z]:$') {
            continue
        }

        if ($segment -match '[<>:"|?*\x00-\x1F]' -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) {
            throw "$ParameterName contém caracteres ou segmentos inválidos."
        }

        if ($segment -match '^(?i)(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
            throw "$ParameterName não pode usar nomes de dispositivo reservados."
        }
    }

    if ($normalizedPath.Contains(':') -and -not $isDriveAbsolute) {
        throw "$ParameterName não pode conter Alternate Data Streams."
    }

    if ($isDriveAbsolute -and $segments.Count -gt 0 -and $segments[0] -match '^[A-Za-z]:$') {
        $segments = @($segments | Select-Object -Skip 1)
    }

    if ($segments.Count -eq 0 -and -not $isDriveAbsolute) {
        throw "$ParameterName deve identificar um caminho abaixo da raiz permitida."
    }
}


function Assert-ComputerInventoryNoReparsePoints {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $volumeRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ([string]::IsNullOrWhiteSpace($volumeRoot) -or $fullPath.StartsWith('\\')) {
        throw "Caminho de exportação não local ou sem raiz de volume: $fullPath"
    }

    $currentPath = $volumeRoot
    $remainingPath = $fullPath.Substring($volumeRoot.Length)
    foreach ($segment in @($remainingPath.Split([char]92) | Where-Object { $_ -ne '' })) {
        $currentPath = Join-Path $currentPath $segment
        try {
            $item = Get-Item -LiteralPath $currentPath -Force -ErrorAction Stop
        }
        catch [System.Management.Automation.ItemNotFoundException] {
            break
        }
        catch [System.IO.FileNotFoundException] {
            break
        }
        catch [System.IO.DirectoryNotFoundException] {
            break
        }
        catch {
            throw "Não foi possível validar o caminho de exportação '$currentPath': $($_.Exception.Message)"
        }

        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Caminho de exportação contém reparse point: $currentPath"
        }
    }
}


function Resolve-ComputerInventoryExportDirectory {

    param (
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot
    )

    Assert-ComputerInventoryPathSyntax -Path $AllowedRoot -ParameterName 'AllowedRoot'
    Assert-ComputerInventoryPathSyntax -Path $OutputDirectory -ParameterName 'Output.Directory'

    if ($AllowedRoot.Replace('/', '\') -notmatch '^[A-Za-z]:\\') {
        throw 'AllowedRoot deve ser um caminho local absoluto confiável.'
    }

    $resolvedRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd([char]92)
    $rootVolume = [System.IO.Path]::GetPathRoot($resolvedRoot)
    if ([string]::IsNullOrWhiteSpace($rootVolume) -or $resolvedRoot.StartsWith('\\')) {
        throw 'AllowedRoot deve estar em uma unidade local, não em UNC ou dispositivo.'
    }

    if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
        $resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
    }
    else {
        $resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $OutputDirectory))
    }

    $rootWithSeparator = $resolvedRoot.TrimEnd([char]92) + [System.IO.Path]::DirectorySeparatorChar
    $isWithinRoot = $resolvedOutput.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedOutput.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $isWithinRoot) {
        throw "Output.Directory deve permanecer dentro de AllowedRoot ('$resolvedRoot')."
    }

    Assert-ComputerInventoryNoReparsePoints -Path $resolvedRoot
    Assert-ComputerInventoryNoReparsePoints -Path $resolvedOutput

    foreach ($existingPath in @($resolvedRoot, $resolvedOutput)) {
        if (Test-Path -LiteralPath $existingPath -ErrorAction Stop) {
            $existingItem = Get-Item -LiteralPath $existingPath -Force -ErrorAction Stop
            if (-not $existingItem.PSIsContainer) {
                throw "O caminho de exportação não é um diretório: $existingPath"
            }
        }
    }

    return $resolvedOutput
}


function Assert-ComputerInventoryFileNameSegment {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -ne $Name.Trim() -or
        $Name -eq '.' -or $Name -eq '..' -or
        $Name -match '[\\/:<>:"|?*\x00-\x1F]' -or
        $Name.EndsWith('.') -or $Name.EndsWith(' ')) {
        throw 'ComputerName não é um segmento de nome de arquivo válido.'
    }

    if ($Name -match '^(?i)(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
        throw 'ComputerName não pode usar um nome de dispositivo reservado.'
    }
}


function Resolve-ComputerInventoryExportFilePath {

    param (
        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot,

        [Parameter(Mandatory = $true)]
        [string]$ReportDirectory,

        [Parameter(Mandatory = $true)]
        [string]$FileName
    )

    Assert-ComputerInventoryFileNameSegment -Name $FileName

    $resolvedRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd([char]92)
    $resolvedDirectory = [System.IO.Path]::GetFullPath($ReportDirectory)
    $resolvedFile = [System.IO.Path]::GetFullPath((Join-Path $resolvedDirectory $FileName))
    $rootWithSeparator = $resolvedRoot.TrimEnd([char]92) + [System.IO.Path]::DirectorySeparatorChar

    foreach ($candidate in @($resolvedDirectory, $resolvedFile)) {
        $isWithinRoot = $candidate.Equals($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $candidate.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $isWithinRoot) {
            throw "Destino de arquivo escapou de AllowedRoot ('$resolvedRoot')."
        }
    }

    Assert-ComputerInventoryNoReparsePoints -Path $resolvedFile

    if (Test-Path -LiteralPath $resolvedFile -ErrorAction Stop) {
        $existingFile = Get-Item -LiteralPath $resolvedFile -Force -ErrorAction Stop
        if (($existingFile.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Destino de arquivo é reparse point: $resolvedFile"
        }
        throw "Destino de exportação já existe; sobrescrita bloqueada: $resolvedFile"
    }

    return $resolvedFile
}


function Write-ComputerInventoryFileCreateNew {

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $stream = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    catch {
        if ($null -ne $stream) {
            throw [System.IO.IOException]::new(
                "Falha ao gravar arquivo criado com CreateNew; destino preservado para inspeção: $Path",
                $_.Exception
            )
        }
        throw
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}


function Export-ComputerInventory {

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Inventory,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration,

        [switch]$AllowRealOperation,

        [Parameter()]
        [string]$AllowedRoot = (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'PowerShell-Automation\ComputerInventory')
    )

    if ($Configuration.SimulationMode -isnot [bool]) {
        throw "SimulationMode deve ser definido explicitamente como Boolean."
    }

    if ($Configuration.SimulationMode -eq $true) {
        return [PSCustomObject]@{
            Success = $true
            SimulationMode = $true
            Partial = $false
            Directory = $null
            Files = @()
            UncertainFiles = @()
            Message = "Simulacao concluida. Nenhum arquivo foi gravado."
        }
    }

    if (-not $AllowRealOperation) {
        throw "Exportação real bloqueada. Informe -AllowRealOperation explicitamente."
    }

    $ReportDirectory = $null
    $ExportedFiles = @()
    $PendingTarget = $null

    try {

        $OutputDirectory = [string]$Configuration.Output.Directory

        if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
            throw "O diretorio de saida nao foi configurado."
        }

        $ReportDirectory = Resolve-ComputerInventoryExportDirectory `
            -OutputDirectory $OutputDirectory `
            -AllowedRoot $AllowedRoot

        $ComputerName = [string]$Inventory.ComputerSystem.ComputerName
        if ([string]::IsNullOrWhiteSpace($ComputerName)) {
            $ComputerName = [string]$env:COMPUTERNAME
        }
        Assert-ComputerInventoryFileNameSegment -Name $ComputerName

        $Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
        $BaseFileName = 'ComputerInventory_' + $ComputerName + '_' + $Timestamp
        $ExportTargets = @{}

        $Formats = @($Configuration.Output.Formats)
        if ($Formats.Count -eq 0) {
            throw 'Pelo menos um formato JSON ou CSV deve ser configurado.'
        }

        foreach ($Format in $Formats) {
            if ($Format -isnot [string] -or $Format.ToUpperInvariant() -notin @('JSON', 'CSV')) {
                throw "Formato de exportação não suportado: $Format"
            }
            switch ($Format.ToUpperInvariant()) {
                "JSON" {
                    if ($ExportTargets.ContainsKey("JSON")) {
                        throw "Formato JSON duplicado na configuração de exportação."
                    }
                    $ExportTargets["JSON"] = Resolve-ComputerInventoryExportFilePath `
                        -AllowedRoot $AllowedRoot `
                        -ReportDirectory $ReportDirectory `
                        -FileName "$BaseFileName.json"
                }
                "CSV" {
                    if ($ExportTargets.ContainsKey("CSV")) {
                        throw "Formato CSV duplicado na configuração de exportação."
                    }
                    $ExportTargets["CSV"] = Resolve-ComputerInventoryExportFilePath `
                        -AllowedRoot $AllowedRoot `
                        -ReportDirectory $ReportDirectory `
                        -FileName "$BaseFileName.csv"
                }
            }
        }

        $targetSummary = ($ExportTargets.Values -join ', ')
        if (-not $PSCmdlet.ShouldProcess($targetSummary, "Criar relatórios de inventário de computador")) {
            return [PSCustomObject]@{
                Success = $false
                SimulationMode = $false
                Partial = $false
                Directory = $ReportDirectory
                Files = @()
                UncertainFiles = @()
                Message = "A exportação não foi aprovada; nenhum arquivo foi gravado."
            }
        }

        if (-not (Test-Path -LiteralPath $AllowedRoot -ErrorAction Stop)) {

            New-Item `
                -ItemType Directory `
                -Path $AllowedRoot `
                -ErrorAction Stop |
                Out-Null
        }

        Assert-ComputerInventoryNoReparsePoints -Path $AllowedRoot

        if (-not (Test-Path -LiteralPath $ReportDirectory -ErrorAction Stop)) {

            New-Item `
                -ItemType Directory `
                -Path $ReportDirectory `
                -ErrorAction Stop |
                Out-Null
        }

        Assert-ComputerInventoryNoReparsePoints -Path $ReportDirectory

        foreach ($Format in $Formats) {

            switch ($Format.ToUpper()) {

                "JSON" {

                    $JsonPath = Resolve-ComputerInventoryExportFilePath `
                        -AllowedRoot $AllowedRoot `
                        -ReportDirectory $ReportDirectory `
                        -FileName "$BaseFileName.json"
                    if ($JsonPath -ne $ExportTargets["JSON"]) {
                        throw "Destino JSON mudou após a validação inicial."
                    }

                    $PendingTarget = $JsonPath
                    $jsonText = ConvertTo-Json -InputObject $Inventory -Depth 10
                    $jsonBytes = ([System.Text.UTF8Encoding]::new($false)).GetBytes($jsonText)
                    Write-ComputerInventoryFileCreateNew -Path $JsonPath -Bytes $jsonBytes

                    $ExportedFiles += $JsonPath
                    $PendingTarget = $null
                }

                "CSV" {

                    $CsvPath = Resolve-ComputerInventoryExportFilePath `
                        -AllowedRoot $AllowedRoot `
                        -ReportDirectory $ReportDirectory `
                        -FileName "$BaseFileName.csv"
                    if ($CsvPath -ne $ExportTargets["CSV"]) {
                        throw "Destino CSV mudou após a validação inicial."
                    }

                    $ComputerSystem = $Inventory.ComputerSystem
                    $OperatingSystem = $Inventory.OperatingSystem
                    $Processor = $Inventory.Processor
                    $Memory = $Inventory.Memory

                    $DiskSummary = (
                        @($Inventory.Disk) |
                        Where-Object {
                            $null -ne $_.Drive
                        } |
                        ForEach-Object {
                            "$($_.Drive) $($_.SizeGB)GB / Livre $($_.FreeSpaceGB)GB"
                        }
                    ) -join " | "

                    $NetworkSummary = (
                        @($Inventory.Network) |
                        Where-Object {
                            $null -ne $_.Description
                        } |
                        ForEach-Object {
                            "$($_.Description) - IPv4: $($_.IPv4Address) - MAC: $($_.MACAddress)"
                        }
                    ) -join " | "

                    $BitLockerStatus = $null

                    if ($null -ne $Inventory.BitLocker) {

                        $BitLockerStatus = $Inventory.BitLocker.Status
                    }

                    $FlatInventory = [PSCustomObject]@{
                        CollectionDateTime = $Inventory.CollectionDateTime
                        ComputerName = $ComputerSystem.ComputerName
                        LoggedOnUser = $ComputerSystem.LoggedOnUser
                        Manufacturer = $ComputerSystem.Manufacturer
                        Model = $ComputerSystem.Model
                        SerialNumber = $ComputerSystem.SerialNumber
                        BIOSVersion = $ComputerSystem.BIOSVersion
                        OperatingSystem = $OperatingSystem.OperatingSystem
                        OSVersion = $OperatingSystem.Version
                        OSBuild = $OperatingSystem.Build
                        Architecture = $OperatingSystem.Architecture
                        ProcessorName = $Processor.ProcessorName
                        PhysicalCores = $Processor.PhysicalCores
                        LogicalProcessors = $Processor.LogicalProcessors
                        TotalMemoryGB = $Memory.TotalMemoryGB
                        Disks = $DiskSummary
                        Network = $NetworkSummary
                        BitLockerStatus = $BitLockerStatus
                    }

                    $PendingTarget = $CsvPath
                    $csvLines = @(ConvertTo-Csv -InputObject $FlatInventory -NoTypeInformation)
                    $csvText = [string]::Join([Environment]::NewLine, [string[]]$csvLines) + [Environment]::NewLine
                    $csvBytes = ([System.Text.UTF8Encoding]::new($false)).GetBytes($csvText)
                    Write-ComputerInventoryFileCreateNew -Path $CsvPath -Bytes $csvBytes

                    $ExportedFiles += $CsvPath
                    $PendingTarget = $null
                }

            }
        }

        return [PSCustomObject]@{
            Success = $true
            SimulationMode = $false
            Partial = $false
            Directory = $ReportDirectory
            Files = $ExportedFiles
            UncertainFiles = @()
            Message = "Inventário exportado com sucesso."
        }
    }
    catch {

        return [PSCustomObject]@{
            Success = $false
            SimulationMode = $false
            Partial = (@($ExportedFiles).Count -gt 0 -or $null -ne $PendingTarget)
            Directory = $ReportDirectory
            Files = @($ExportedFiles)
            UncertainFiles = if ($null -ne $PendingTarget) { @($PendingTarget) } else { @() }
            Message = $_.Exception.Message
        }
    }
}


Export-ModuleMember -Function `
    Get-ComputerSystemInventory, `
    Get-OperatingSystemInventory, `
    Get-ProcessorInventory, `
    Get-MemoryInventory, `
    Get-DiskInventory, `
    Get-NetworkInventory, `
    Get-BitLockerInventory, `
    Get-ComputerInventory, `
    Export-ComputerInventory
