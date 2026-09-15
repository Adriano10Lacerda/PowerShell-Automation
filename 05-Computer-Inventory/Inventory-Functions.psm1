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

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    $ComputerSystem = $null
    $OperatingSystem = $null
    $Processor = $null
    $Memory = $null
    $Disk = @()
    $Network = @()
    $BitLocker = $null

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
        ComputerSystem = $ComputerSystem
        OperatingSystem = $OperatingSystem
        Processor = $Processor
        Memory = $Memory
        Disk = @($Disk)
        Network = @($Network)
        BitLocker = $BitLocker
    }
}


function Export-ComputerInventory {

    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Inventory,

        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Configuration
    )

    try {

        $ReportDirectory = Join-Path `
            $PSScriptRoot `
            $Configuration.Output.Directory

        if (-not (Test-Path $ReportDirectory)) {

            New-Item `
                -ItemType Directory `
                -Path $ReportDirectory `
                -Force |
                Out-Null
        }

        $ComputerName = $Inventory.ComputerSystem.ComputerName

        if ([string]::IsNullOrWhiteSpace($ComputerName)) {

            $ComputerName = $env:COMPUTERNAME
        }

        $Timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"

        $BaseFileName = "ComputerInventory_${ComputerName}_${Timestamp}"

        $ExportedFiles = @()

        foreach ($Format in $Configuration.Output.Formats) {

            switch ($Format.ToUpper()) {

                "JSON" {

                    $JsonPath = Join-Path `
                        $ReportDirectory `
                        "$BaseFileName.json"

                    $Inventory |
                        ConvertTo-Json -Depth 10 |
                        Set-Content `
                            -Path $JsonPath `
                            -Encoding UTF8

                    $ExportedFiles += $JsonPath
                }

                "CSV" {

                    $CsvPath = Join-Path `
                        $ReportDirectory `
                        "$BaseFileName.csv"

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

                    $FlatInventory |
                        Export-Csv `
                            -Path $CsvPath `
                            -NoTypeInformation `
                            -Encoding UTF8

                    $ExportedFiles += $CsvPath
                }

                default {

                    Write-Warning "Formato de exportação não suportado: $Format"
                }
            }
        }

        return [PSCustomObject]@{
            Success = $true
            Directory = $ReportDirectory
            Files = $ExportedFiles
            Message = "Inventário exportado com sucesso."
        }
    }
    catch {

        return [PSCustomObject]@{
            Success = $false
            Directory = $null
            Files = @()
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