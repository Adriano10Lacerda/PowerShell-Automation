function Get-ComputerADInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            throw "O módulo ActiveDirectory não está instalado ou disponível neste computador."
        }

        Import-Module ActiveDirectory -ErrorAction Stop

        $computer = Get-ADComputer `
            -Identity $Hostname `
            -Properties OperatingSystem,
                        Description,
                        ManagedBy,
                        whenCreated,
                        whenChanged,
                        DistinguishedName,
                        Enabled `
            -ErrorAction Stop

        $result.Data = [PSCustomObject]@{
            Found             = $true
            Name              = $computer.Name
            Enabled           = $computer.Enabled
            OperatingSystem   = $computer.OperatingSystem
            Description       = $computer.Description
            ManagedBy         = $computer.ManagedBy
            Created           = $computer.whenCreated
            LastUpdated       = $computer.whenChanged
            DistinguishedName = $computer.DistinguishedName
        }

        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}


function Get-ComputerCimInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {

        # ============================================================
        # LOCAL / REMOTE
        # ============================================================

        $isLocalComputer = (
            $ComputerName -eq $env:COMPUTERNAME -or
            $ComputerName -eq "localhost" -or
            $ComputerName -eq "."
        )


        # ============================================================
        # COMPUTER SYSTEM
        # ============================================================

        if ($isLocalComputer) {
            $computerSystem = Get-CimInstance `
                -ClassName Win32_ComputerSystem `
                -ErrorAction Stop
        }
        else {
            $computerSystem = Get-CimInstance `
                -ClassName Win32_ComputerSystem `
                -ComputerName $ComputerName `
                -ErrorAction Stop
        }


        # ============================================================
        # OPERATING SYSTEM
        # ============================================================

        if ($isLocalComputer) {
            $operatingSystem = Get-CimInstance `
                -ClassName Win32_OperatingSystem `
                -ErrorAction Stop
        }
        else {
            $operatingSystem = Get-CimInstance `
                -ClassName Win32_OperatingSystem `
                -ComputerName $ComputerName `
                -ErrorAction Stop
        }


        # ============================================================
        # PROCESSOR
        # ============================================================

        if ($isLocalComputer) {
            $processor = Get-CimInstance `
                -ClassName Win32_Processor `
                -ErrorAction Stop |
                Select-Object -First 1
        }
        else {
            $processor = Get-CimInstance `
                -ClassName Win32_Processor `
                -ComputerName $ComputerName `
                -ErrorAction Stop |
                Select-Object -First 1
        }


        # ============================================================
        # BIOS
        # ============================================================

        if ($isLocalComputer) {
            $bios = Get-CimInstance `
                -ClassName Win32_BIOS `
                -ErrorAction Stop
        }
        else {
            $bios = Get-CimInstance `
                -ClassName Win32_BIOS `
                -ComputerName $ComputerName `
                -ErrorAction Stop
        }


        # ============================================================
        # COMPUTER SYSTEM PRODUCT
        # ============================================================

        if ($isLocalComputer) {
            $computerProduct = Get-CimInstance `
                -ClassName Win32_ComputerSystemProduct `
                -ErrorAction Stop
        }
        else {
            $computerProduct = Get-CimInstance `
                -ClassName Win32_ComputerSystemProduct `
                -ComputerName $ComputerName `
                -ErrorAction Stop
        }


        # ============================================================
        # SERIAL NUMBER
        # ============================================================

        $serialNumber = $bios.SerialNumber

        if ([string]::IsNullOrWhiteSpace($serialNumber)) {
            $serialNumber = $computerProduct.IdentifyingNumber
        }


        # ============================================================
        # STORAGE
        # ============================================================

        if ($isLocalComputer) {
            $logicalDisks = @(
                Get-CimInstance `
                    -ClassName Win32_LogicalDisk `
                    -Filter "DriveType = 3" `
                    -ErrorAction Stop
            )
        }
        else {
            $logicalDisks = @(
                Get-CimInstance `
                    -ClassName Win32_LogicalDisk `
                    -ComputerName $ComputerName `
                    -Filter "DriveType = 3" `
                    -ErrorAction Stop
            )
        }

        $storage = @(
            foreach ($disk in $logicalDisks) {

                $totalGB = 0
                $freeGB = 0
                $freePercent = 0

                if ($disk.Size -gt 0) {

                    $totalGB = [math]::Round(
                        $disk.Size / 1GB,
                        2
                    )

                    $freeGB = [math]::Round(
                        $disk.FreeSpace / 1GB,
                        2
                    )

                    $freePercent = [math]::Round(
                        ($disk.FreeSpace / $disk.Size) * 100,
                        2
                    )
                }

                [PSCustomObject]@{
                    DeviceID    = $disk.DeviceID
                    VolumeName  = $disk.VolumeName
                    FileSystem  = $disk.FileSystem
                    TotalGB     = $totalGB
                    FreeGB      = $freeGB
                    FreePercent = $freePercent
                }
            }
        )


        # ============================================================
        # NETWORK
        # ============================================================

        if ($isLocalComputer) {
            $networkAdapters = @(
                Get-CimInstance `
                    -ClassName Win32_NetworkAdapterConfiguration `
                    -Filter "IPEnabled = TRUE" `
                    -ErrorAction Stop
            )
        }
        else {
            $networkAdapters = @(
                Get-CimInstance `
                    -ClassName Win32_NetworkAdapterConfiguration `
                    -ComputerName $ComputerName `
                    -Filter "IPEnabled = TRUE" `
                    -ErrorAction Stop
            )
        }

        $network = @(
            foreach ($adapter in $networkAdapters) {

                $ipv4 = @(
                    $adapter.IPAddress |
                        Where-Object {
                            $_ -match '^\d{1,3}(\.\d{1,3}){3}$'
                        }
                )

                $ipv6 = @(
                    $adapter.IPAddress |
                        Where-Object {
                            $_ -match ':'
                        }
                )

                [PSCustomObject]@{
                    Description = $adapter.Description
                    MACAddress  = $adapter.MACAddress
                    IPv4        = @($ipv4)
                    IPv6        = @($ipv6)
                }
            }
        )


        # ============================================================
        # BITLOCKER
        # ============================================================

        $bitLocker = [PSCustomObject]@{
            Status  = "NotAvailable"
            Volumes = @()
            Error   = $null
        }

        try {

            if ($isLocalComputer) {

                $bitLockerVolumes = @(
                    Get-BitLockerVolume -ErrorAction Stop
                )
            }
            else {

                $bitLockerVolumes = @(
                    Invoke-Command `
                        -ComputerName $ComputerName `
                        -ScriptBlock {
                            Get-BitLockerVolume -ErrorAction Stop
                        } `
                        -ErrorAction Stop
                )
            }

            if ($bitLockerVolumes.Count -eq 0) {

                $bitLocker.Status = "NotAvailable"

                $bitLocker.Error =
                    "Nenhum volume BitLocker foi retornado pelo sistema."
            }
            else {

                foreach ($volume in $bitLockerVolumes) {

                    $protectionStatus = switch ($volume.ProtectionStatus) {

                        1 {
                            "Protected"
                        }

                        0 {
                            "NotProtected"
                        }

                        default {
                            "Unknown"
                        }
                    }

                    $bitLocker.Volumes += [PSCustomObject]@{
                        MountPoint       = $volume.MountPoint
                        VolumeStatus     = [string]$volume.VolumeStatus
                        ProtectionStatus = $protectionStatus
                        EncryptionMethod = [string]$volume.EncryptionMethod
                    }
                }

                $protectedVolumes = @(
                    $bitLocker.Volumes |
                        Where-Object {
                            $_.ProtectionStatus -eq "Protected"
                        }
                )

                if ($protectedVolumes.Count -gt 0) {
                    $bitLocker.Status = "Protected"
                }
                else {
                    $bitLocker.Status = "NotProtected"
                }
            }
        }
        catch {

            $bitLocker.Status = "NotAvailable"
            $bitLocker.Error = $_.Exception.Message
        }


        # ============================================================
        # CONNECTIVITY
        # ============================================================

        $connectivity = [PSCustomObject]@{
            Reachable      = $false
            ResponseTimeMs = $null
        }

        try {

            $ping = Test-Connection `
                -ComputerName $ComputerName `
                -Count 1 `
                -ErrorAction Stop

            $connectivity.Reachable = $true

            if ($ping.Latency -ne $null) {

                $connectivity.ResponseTimeMs = [math]::Round(
                    [double]$ping.Latency,
                    2
                )
            }
        }
        catch {

            $connectivity.Reachable = $false
        }


        # ============================================================
        # RESULTADO CIM
        # ============================================================

        $result.Data = [PSCustomObject]@{

            System = [PSCustomObject]@{
                Manufacturer = $computerSystem.Manufacturer
                Model        = $computerSystem.Model
                SerialNumber = $serialNumber
            }

            OperatingSystem = [PSCustomObject]@{
                Caption      = $operatingSystem.Caption
                Version      = $operatingSystem.Version
                Build        = $operatingSystem.BuildNumber
                Architecture = $operatingSystem.OSArchitecture
            }

            Processor = [PSCustomObject]@{
                Name         = $processor.Name
                Cores        = $processor.NumberOfCores
                LogicalCores = $processor.NumberOfLogicalProcessors
            }

            Memory = [PSCustomObject]@{
                TotalGB = [math]::Round(
                    $computerSystem.TotalPhysicalMemory / 1GB,
                    2
                )
            }

            Storage = [array]$storage

            Network = [array]$network

            BitLocker = $bitLocker

            Connectivity = $connectivity
        }

        $result.Success = $true
    }
    catch {

        $result.Error = $_.Exception.Message
    }

    return $result
}


# ================================================================
# COMPUTER INVENTORY
# ================================================================

function Get-ComputerInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
    }

    try {

        # ------------------------------------------------------------
        # Active Directory
        # ------------------------------------------------------------

        $adResult = Get-ComputerADInfo `
            -Hostname $ComputerName


        # ------------------------------------------------------------
        # CIM
        # ------------------------------------------------------------

        $cimResult = Get-ComputerCimInfo `
            -ComputerName $ComputerName


        # ------------------------------------------------------------
        # AD DATA
        # ------------------------------------------------------------

        if ($adResult.Success) {

            $adData = $adResult.Data
        }
        else {

            $adData = [PSCustomObject]@{
                Found = $false
                Error = $adResult.Error
            }
        }


        # ------------------------------------------------------------
        # CONSOLIDATED INVENTORY
        # ------------------------------------------------------------

        $result.Data = [PSCustomObject]@{

            Hostname = $ComputerName

            CollectionDateTime = (
                Get-Date
            ).ToUniversalTime()


            AD = $adData


            Connectivity = if ($cimResult.Success) {
                $cimResult.Data.Connectivity
            }
            else {
                $null
            }


            System = if ($cimResult.Success) {
                $cimResult.Data.System
            }
            else {
                $null
            }


            OperatingSystem = if ($cimResult.Success) {
                $cimResult.Data.OperatingSystem
            }
            else {
                $null
            }


            Processor = if ($cimResult.Success) {
                $cimResult.Data.Processor
            }
            else {
                $null
            }


            Memory = if ($cimResult.Success) {
                $cimResult.Data.Memory
            }
            else {
                $null
            }


            Storage = if ($cimResult.Success) {
                [array]$cimResult.Data.Storage
            }
            else {
                [array]@()
            }


            Network = if ($cimResult.Success) {
                [array]$cimResult.Data.Network
            }
            else {
                [array]@()
            }


            BitLocker = if ($cimResult.Success) {
                $cimResult.Data.BitLocker
            }
            else {
                $null
            }


            Errors = @(
                if (-not $adResult.Success) {

                    [PSCustomObject]@{
                        Source  = "ActiveDirectory"
                        Message = $adResult.Error
                    }
                }

                if (-not $cimResult.Success) {

                    [PSCustomObject]@{
                        Source  = "CIM"
                        Message = $cimResult.Error
                    }
                }
            )
        }


        # ------------------------------------------------------------
        # SUCCESS
        # ------------------------------------------------------------

        if ($adResult.Success -or $cimResult.Success) {

            $result.Success = $true
        }
        else {

            $result.Error =
                "Não foi possível obter informações do computador via AD ou CIM."
        }
    }
    catch {

        $result.Error = $_.Exception.Message
    }

    return $result
}


# ================================================================
# EXPORTS
# ================================================================

Export-ModuleMember -Function `
    Get-ComputerADInfo, `
    Get-ComputerCimInfo, `
    Get-ComputerInventory