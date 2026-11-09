function Resolve-ComputerCoreMode {
    [CmdletBinding()]
    param(
        [switch]$SimulationMode,
        [switch]$Preview,
        [switch]$AllowRealOperation
    )

    $whatIfRequested = [bool]$WhatIfPreference
    $explicitPreview = $Preview.IsPresent
    $previewRequested = $explicitPreview -or $whatIfRequested

    if (($SimulationMode -and $previewRequested) -or
        (($SimulationMode -or $explicitPreview) -and $AllowRealOperation)) {
        throw "Modos conflitantes. Use SimulationMode, Preview/WhatIf ou AllowRealOperation, somente um por chamada."
    }

    if ($SimulationMode) { return "Simulation" }
    if ($previewRequested) { return "Preview" }
    if ($AllowRealOperation) { return "Real" }

    throw "Modo obrigatório. Informe -SimulationMode, -Preview/-WhatIf ou -AllowRealOperation."
}

function Invoke-ComputerCoreShouldProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [string]$Action
    )

    return $Cmdlet.ShouldProcess($Target, $Action)
}

function Invoke-ComputerCoreCimQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ClassName,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][bool]$IsLocal,
        [string]$Filter
    )

    try {
        if ($IsLocal) {
            if ([string]::IsNullOrWhiteSpace($Filter)) {
                $items = @(Get-CimInstance -ClassName $ClassName -ErrorAction Stop)
            }
            else {
                $items = @(Get-CimInstance -ClassName $ClassName -Filter $Filter -ErrorAction Stop)
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($Filter)) {
            $items = @(Get-CimInstance -ClassName $ClassName -ComputerName $ComputerName -ErrorAction Stop)
        }
        else {
            $items = @(Get-CimInstance -ClassName $ClassName -ComputerName $ComputerName -Filter $Filter -ErrorAction Stop)
        }

        $items = @($items | Where-Object { $null -ne $_ })

        if ($items.Count -eq 0) {
            return [PSCustomObject]@{ Success = $true; QueryStatus = "NoData"; Data = @(); Error = $null }
        }

        return [PSCustomObject]@{ Success = $true; QueryStatus = "Complete"; Data = $items; Error = $null }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; QueryStatus = "Error"; Data = @(); Error = $_.Exception.Message }
    }
}

function Resolve-ComputerCoreConnectivity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ComputerName)

    try {
        $responses = @(Test-Connection -ComputerName $ComputerName -Count 1 -ErrorAction Stop)
        if ($responses.Count -eq 0) {
            return [PSCustomObject]@{ Reachable = $false; Status = "NoResponse"; ResponseTimeMs = $null; Error = $null }
        }

        $probe = $responses[0]
        $statusCodeProperty = $probe.PSObject.Properties["StatusCode"]
        if ($null -ne $statusCodeProperty -and $null -ne $statusCodeProperty.Value) {
            if ([int]$statusCodeProperty.Value -eq 0) {
                $latencyProperty = $probe.PSObject.Properties["Latency"]
                $responseTime = if ($null -ne $latencyProperty -and $null -ne $latencyProperty.Value) { [math]::Round([double]$latencyProperty.Value, 2) } else { $null }
                return [PSCustomObject]@{ Reachable = $true; Status = "Responded"; ResponseTimeMs = $responseTime; Error = $null }
            }
            if ([int]$statusCodeProperty.Value -in @(11002, 11003, 11004, 11005, 11010, 11013, 11014, 11018)) {
                return [PSCustomObject]@{ Reachable = $false; Status = "NoResponse"; ResponseTimeMs = $null; Error = $null }
            }
            return [PSCustomObject]@{ Reachable = $null; Status = "Error"; ResponseTimeMs = $null; Error = "Test-Connection reported ICMP status code $($statusCodeProperty.Value)." }
        }

        $statusProperty = $probe.PSObject.Properties["Status"]
        if ($null -ne $statusProperty -and $null -ne $statusProperty.Value) {
            $probeStatus = [string]$statusProperty.Value
            if ($probeStatus -match '^(?i:Success|Succeeded|Alive|Reply|Responded)$') {
                $latencyProperty = $probe.PSObject.Properties["Latency"]
                $responseTime = if ($null -ne $latencyProperty -and $null -ne $latencyProperty.Value) { [math]::Round([double]$latencyProperty.Value, 2) } else { $null }
                return [PSCustomObject]@{ Reachable = $true; Status = "Responded"; ResponseTimeMs = $responseTime; Error = $null }
            }
            if ($probeStatus -match '^(?i:TimedOut|TimeOut|DestinationHostUnreachable|RequestTimedOut|NoResponse)$') {
                return [PSCustomObject]@{ Reachable = $false; Status = "NoResponse"; ResponseTimeMs = $null; Error = $null }
            }
            return [PSCustomObject]@{ Reachable = $null; Status = "Error"; ResponseTimeMs = $null; Error = "Test-Connection returned an unrecognized status '$probeStatus'." }
        }

        $latencyProperty = $probe.PSObject.Properties["Latency"]
        if ($null -ne $latencyProperty -and $null -ne $latencyProperty.Value) {
            $responseTime = [math]::Round([double]$latencyProperty.Value, 2)
            return [PSCustomObject]@{ Reachable = $true; Status = "Responded"; ResponseTimeMs = $responseTime; Error = $null }
        }

        return [PSCustomObject]@{ Reachable = $null; Status = "Error"; ResponseTimeMs = $null; Error = "Test-Connection retornou um objeto sem indicador de resposta reconhecido." }
    }
    catch {
        return [PSCustomObject]@{ Reachable = $null; Status = "Error"; ResponseTimeMs = $null; Error = $_.Exception.Message }
    }
}

function New-ComputerCoreCancelledResult {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    [PSCustomObject]@{
        Success        = $false
        Data           = $null
        Error          = $Message
        Message        = $Message
        SimulationMode = $false
        Preview        = $true
        IsSimulated    = $false
        Mode           = "Preview"
        Status         = "Cancelled"
        Cancelled      = $true
        CollectionStatus = "Cancelled"
        QueryStatus    = "NotQueried"
    }
}

function New-ComputerCoreDemoADInfo {
    param(
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][ValidateSet("Simulation", "Preview")][string]$Mode
    )

    [PSCustomObject]@{
        Found             = $null
        Name              = $Hostname
        Enabled           = $true
        OperatingSystem   = "Windows (dados demonstrativos)"
        Description       = "Dado fictício; nenhuma consulta AD foi realizada."
        ManagedBy         = $null
        Created           = $null
        LastUpdated       = $null
        DistinguishedName = "CN=$Hostname,OU=DEMO,DC=example,DC=invalid"
        IsSimulated       = $true
        Mode              = $Mode
        QueryStatus       = "NotQueried"
    }
}

function New-ComputerCoreDemoCimInfo {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateSet("Simulation", "Preview")][string]$Mode
    )

    [PSCustomObject]@{
        System = [PSCustomObject]@{
            Manufacturer = "DEMO"
            Model        = "Modelo Demonstrativo"
            SerialNumber = "DEMO-NO-REAL-DATA"
        }
        OperatingSystem = [PSCustomObject]@{
            Caption = "Windows (dados demonstrativos)"
            Version = "0.0"
            Build = "DEMO"
            Architecture = "N/A"
        }
        Processor = [PSCustomObject]@{ Name = "CPU Demonstrativa"; Cores = 0; LogicalCores = 0 }
        Memory = [PSCustomObject]@{ TotalGB = 0 }
        Storage = @()
        Network = @()
        BitLocker = [PSCustomObject]@{
            Status = "NotQueried"
            Volumes = @()
            Error = "Dado fictício; BitLocker não foi consultado."
            IsSimulated = $true
            Mode = $Mode
        }
        Connectivity = [PSCustomObject]@{ Reachable = $null; Status = "NotQueried"; ResponseTimeMs = $null; Error = $null; IsSimulated = $true; Mode = $Mode }
        QueryStatus = "NotQueried"
        Hostname = $ComputerName
        IsSimulated = $true
        Mode = $Mode
    }
}

function New-ComputerCoreModeResult {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][ValidateSet("Simulation", "Preview")][string]$Mode
    )

    $ad = New-ComputerCoreDemoADInfo -Hostname $ComputerName -Mode $Mode
    $cim = New-ComputerCoreDemoCimInfo -ComputerName $ComputerName -Mode $Mode
    $data = [PSCustomObject]@{
        Status = if ($Mode -eq "Simulation") { "Simulated" } else { "Preview" }
        Hostname = $ComputerName
        CollectionDateTime = [datetime]::UtcNow
        AD = $ad
        Connectivity = $cim.Connectivity
        System = $cim.System
        OperatingSystem = $cim.OperatingSystem
        Processor = $cim.Processor
        Memory = $cim.Memory
        Storage = @($cim.Storage)
        Network = @($cim.Network)
        BitLocker = $cim.BitLocker
        Errors = @()
        IsSimulated = $true
        Mode = $Mode
        CollectionStatus = $Mode
    }

    [PSCustomObject]@{
        Success = $true
        Data = $data
        Error = $null
        SimulationMode = ($Mode -eq "Simulation")
        Preview = ($Mode -eq "Preview")
        Cancelled = $false
        IsSimulated = $true
        Mode = $Mode
        Status = if ($Mode -eq "Simulation") { "Simulated" } else { "Preview" }
        CollectionStatus = $Mode
    }
}

function Get-ComputerADInfo {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Hostname,

        [switch]$SimulationMode,
        [switch]$Preview,
        [switch]$AllowRealOperation
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data = $null
        Error = $null
        IsSimulated = $false
        Mode = "Error"
        SimulationMode = $false
        Preview = $false
        Cancelled = $false
        Status = "Error"
        QueryStatus = "NotQueried"
        CollectionStatus = "Error"
    }

    $queryStarted = $false
    try {
        $mode = Resolve-ComputerCoreMode `
            -SimulationMode:$SimulationMode `
            -Preview:$Preview `
            -AllowRealOperation:$AllowRealOperation

        if ($mode -in @("Simulation", "Preview")) {
            $result.Data = New-ComputerCoreDemoADInfo -Hostname $Hostname -Mode $mode
            $result.Success = $true
            $result.IsSimulated = $true
            $result.Mode = $mode
            $result.SimulationMode = ($mode -eq "Simulation")
            $result.Preview = ($mode -eq "Preview")
            $result.Cancelled = $false
            $result.Status = if ($mode -eq "Simulation") { "Simulated" } else { "Preview" }
            $result.QueryStatus = "NotQueried"
            $result.CollectionStatus = $mode
            return $result
        }

        if (-not (Invoke-ComputerCoreShouldProcess -Cmdlet $PSCmdlet -Target $Hostname -Action "Consultar Active Directory")) {
            return New-ComputerCoreCancelledResult -Message "Consulta cancelada pelo usuário; nenhuma chamada ao Active Directory foi realizada."
        }

        $queryStarted = $true

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

        if ($null -eq $computer) {
            $result.Success = $true
            $result.Data = [PSCustomObject]@{
                Found = $false
                Name = $null
                Enabled = $null
                OperatingSystem = $null
                Description = $null
                ManagedBy = $null
                Created = $null
                LastUpdated = $null
                DistinguishedName = $null
                IsSimulated = $false
                Mode = "Real"
                QueryStatus = "NotFound"
            }
            $result.Mode = "Real"
            $result.Status = "NotFound"
            $result.QueryStatus = "NotFound"
            $result.CollectionStatus = "Complete"
            $result.IsSimulated = $false
            return $result
        }

        $computerNameProperty = $computer.PSObject.Properties["Name"]
        if ($null -eq $computerNameProperty -or [string]::IsNullOrWhiteSpace([string]$computerNameProperty.Value)) {
            throw "A resposta AD não contém um nome de computador válido."
        }

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
            QueryStatus       = "Found"
        }

        $result.Success = $true
        $result.QueryStatus = "Found"
        $result.CollectionStatus = "Complete"
        $result.IsSimulated = $false
        $result.Mode = "Real"
        $result.SimulationMode = $false
        $result.Preview = $false
        $result.Cancelled = $false
        $result.Status = "Collected"
    }
    catch {
        $result.Error = $_.Exception.Message
        $result.Data = [PSCustomObject]@{
            Found = $null
            Name = $null
            Enabled = $null
            OperatingSystem = $null
            Description = $null
            ManagedBy = $null
            Created = $null
            LastUpdated = $null
            DistinguishedName = $null
            IsSimulated = $false
            Mode = if ($mode -eq "Real") { "Real" } else { "Error" }
            QueryStatus = if ($queryStarted) { "Error" } else { "NotQueried" }
            Error = $_.Exception.Message
        }
        $result.QueryStatus = if ($queryStarted) { "Error" } else { "NotQueried" }
        $result.CollectionStatus = "Error"
        $result.IsSimulated = $false
        $result.Mode = "Error"
        $result.SimulationMode = $false
        $result.Preview = $false
        $result.Cancelled = $false
        $result.Status = "Error"
    }

    return $result
}


function Get-ComputerCimInfo {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [switch]$SimulationMode,
        [switch]$Preview,
        [switch]$AllowRealOperation
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
        IsSimulated = $false
        Mode = "Error"
        SimulationMode = $false
        Preview = $false
        Cancelled = $false
        Status = "Error"
        QueryStatus = "NotQueried"
        CollectionStatus = "Error"
        Errors = @()
    }

    $queryStarted = $false
    try {
        $mode = Resolve-ComputerCoreMode `
            -SimulationMode:$SimulationMode `
            -Preview:$Preview `
            -AllowRealOperation:$AllowRealOperation

        if ($mode -in @("Simulation", "Preview")) {
            $result.Data = New-ComputerCoreDemoCimInfo -ComputerName $ComputerName -Mode $mode
            $result.Success = $true
            $result.IsSimulated = $true
            $result.Mode = $mode
            $result.SimulationMode = ($mode -eq "Simulation")
            $result.Preview = ($mode -eq "Preview")
            $result.Cancelled = $false
            $result.Status = if ($mode -eq "Simulation") { "Simulated" } else { "Preview" }
            $result.QueryStatus = "NotQueried"
            $result.CollectionStatus = $mode
            return $result
        }

        if (-not (Invoke-ComputerCoreShouldProcess -Cmdlet $PSCmdlet -Target $ComputerName -Action "Consultar inventário CIM, BitLocker e conectividade")) {
            return New-ComputerCoreCancelledResult -Message "Consulta cancelada pelo usuário; nenhuma chamada CIM, BitLocker ou de rede foi realizada."
        }

        $queryStarted = $true

        # ============================================================
        # LOCAL / REMOTE
        # ============================================================

        $isLocalComputer = (
            $ComputerName -eq $env:COMPUTERNAME -or
            $ComputerName -eq "localhost" -or
            $ComputerName -eq "."
        )


        $computerSystemQuery = Invoke-ComputerCoreCimQuery -ClassName "Win32_ComputerSystem" -ComputerName $ComputerName -IsLocal:$isLocalComputer
        $operatingSystemQuery = Invoke-ComputerCoreCimQuery -ClassName "Win32_OperatingSystem" -ComputerName $ComputerName -IsLocal:$isLocalComputer
        $processorQuery = Invoke-ComputerCoreCimQuery -ClassName "Win32_Processor" -ComputerName $ComputerName -IsLocal:$isLocalComputer
        $biosQuery = Invoke-ComputerCoreCimQuery -ClassName "Win32_BIOS" -ComputerName $ComputerName -IsLocal:$isLocalComputer
        $computerProductQuery = Invoke-ComputerCoreCimQuery -ClassName "Win32_ComputerSystemProduct" -ComputerName $ComputerName -IsLocal:$isLocalComputer
        $logicalDisksQuery = Invoke-ComputerCoreCimQuery -ClassName "Win32_LogicalDisk" -ComputerName $ComputerName -IsLocal:$isLocalComputer -Filter "DriveType = 3"
        $networkAdaptersQuery = Invoke-ComputerCoreCimQuery -ClassName "Win32_NetworkAdapterConfiguration" -ComputerName $ComputerName -IsLocal:$isLocalComputer -Filter "IPEnabled = TRUE"

        $computerSystem = @($computerSystemQuery.Data | Select-Object -First 1) | Select-Object -First 1
        $operatingSystem = @($operatingSystemQuery.Data | Select-Object -First 1) | Select-Object -First 1
        $processor = @($processorQuery.Data | Select-Object -First 1) | Select-Object -First 1
        $bios = @($biosQuery.Data | Select-Object -First 1) | Select-Object -First 1
        $computerProduct = @($computerProductQuery.Data | Select-Object -First 1) | Select-Object -First 1


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

        $logicalDisks = @($logicalDisksQuery.Data)

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

        $networkAdapters = @($networkAdaptersQuery.Data)

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

        $connectivity = Resolve-ComputerCoreConnectivity -ComputerName $ComputerName

        $queryResults = @(
            $computerSystemQuery, $operatingSystemQuery, $processorQuery,
            $biosQuery, $computerProductQuery, $logicalDisksQuery, $networkAdaptersQuery
        )
        $queryErrors = @(
            foreach ($queryResult in $queryResults) {
                if ($queryResult.QueryStatus -eq "Error") {
                    [PSCustomObject]@{ Source = "CIM"; Message = $queryResult.Error }
                }
            }
        )
        if ($connectivity.Status -eq "Error") {
            $queryErrors += [PSCustomObject]@{ Source = "Connectivity"; Message = $connectivity.Error }
        }
        if ($bitLocker.Error) {
            $queryErrors += [PSCustomObject]@{ Source = "BitLocker"; Message = $bitLocker.Error }
        }

        $requiredQueryResults = @($computerSystemQuery, $operatingSystemQuery, $processorQuery)
        $requiredDataCount = @($requiredQueryResults | Where-Object { $_.QueryStatus -eq "Complete" }).Count
        $allRequiredDataPresent = $requiredDataCount -eq $requiredQueryResults.Count
        $anyCimDataPresent = @($queryResults | Where-Object { $_.QueryStatus -eq "Complete" }).Count -gt 0
        if ($queryErrors.Count -gt 0) {
            $cimCollectionStatus = if ($anyCimDataPresent) { "Partial" } else { "Error" }
            $cimQueryStatus = if ($anyCimDataPresent) { "Partial" } else { "Error" }
        }
        elseif ($allRequiredDataPresent) {
            $cimCollectionStatus = "Complete"
            $cimQueryStatus = "Complete"
        }
        elseif ($anyCimDataPresent) {
            $cimCollectionStatus = "Partial"
            $cimQueryStatus = "Partial"
        }
        else {
            $cimCollectionStatus = "Error"
            $cimQueryStatus = "NoData"
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
                TotalGB = if ($null -ne $computerSystem -and $null -ne $computerSystem.TotalPhysicalMemory) {
                    [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
                }
                else { $null }
            }

            Storage = [array]$storage

            Network = [array]$network

            BitLocker = $bitLocker

            Connectivity = $connectivity
            QueryStatus = $cimQueryStatus
            CollectionStatus = $cimCollectionStatus
            QueryStates = [PSCustomObject]@{
                ComputerSystem = $computerSystemQuery.QueryStatus
                OperatingSystem = $operatingSystemQuery.QueryStatus
                Processor = $processorQuery.QueryStatus
                BIOS = $biosQuery.QueryStatus
                ComputerSystemProduct = $computerProductQuery.QueryStatus
                Storage = $logicalDisksQuery.QueryStatus
                Network = $networkAdaptersQuery.QueryStatus
                Connectivity = $connectivity.Status
                BitLocker = if ($bitLocker.Error) { "Error" } else { "Complete" }
            }
            Errors = $queryErrors
        }

        $result.Success = $anyCimDataPresent
        $result.Error = if ($queryErrors.Count -gt 0) {
            ($queryErrors | ForEach-Object { $_.Message }) -join "; "
        }
        elseif (-not $anyCimDataPresent) {
            "CIM queries completed but returned no usable data."
        }
        else { $null }
        $result.Errors = $queryErrors
        $result.QueryStatus = $cimQueryStatus
        $result.CollectionStatus = $cimCollectionStatus
        $result.IsSimulated = $false
        $result.Mode = "Real"
        $result.SimulationMode = $false
        $result.Preview = $false
        $result.Cancelled = $false
        $result.Status = $cimQueryStatus
    }
    catch {

        $result.Error = $_.Exception.Message
        $result.Errors = @([PSCustomObject]@{ Source = "CIM"; Message = $_.Exception.Message })
        $result.QueryStatus = if ($queryStarted) { "Error" } else { "NotQueried" }
        $result.CollectionStatus = "Error"
        $result.IsSimulated = $false
        $result.Mode = "Error"
        $result.SimulationMode = $false
        $result.Preview = $false
        $result.Cancelled = $false
        $result.Status = "Error"
    }

    return $result
}


# ================================================================
# COMPUTER INVENTORY
# ================================================================

function Get-ComputerInventory {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ComputerName,

        [switch]$SimulationMode,
        [switch]$Preview,
        [switch]$AllowRealOperation
    )

    $result = [PSCustomObject]@{
        Success = $false
        Data    = $null
        Error   = $null
        SimulationMode = $false
        Preview = $false
        IsSimulated = $false
        Mode = "Error"
        Status = "Error"
        Cancelled = $false
        CollectionStatus = "Error"
    }

    try {
        $mode = Resolve-ComputerCoreMode `
            -SimulationMode:$SimulationMode `
            -Preview:$Preview `
            -AllowRealOperation:$AllowRealOperation

        if ($mode -in @("Simulation", "Preview")) {
            return New-ComputerCoreModeResult -ComputerName $ComputerName -Mode $mode
        }

        if (-not (Invoke-ComputerCoreShouldProcess -Cmdlet $PSCmdlet -Target $ComputerName -Action "Coletar inventário real do computador")) {
            return New-ComputerCoreCancelledResult -Message "Coleta cancelada pelo usuário; nenhuma consulta externa foi realizada."
        }

        # ------------------------------------------------------------
        # Active Directory
        # ------------------------------------------------------------

        $adResult = Get-ComputerADInfo `
            -Hostname $ComputerName `
            -AllowRealOperation `
            -Confirm:$false


        # ------------------------------------------------------------
        # CIM
        # ------------------------------------------------------------

        $cimResult = Get-ComputerCimInfo `
            -ComputerName $ComputerName `
            -AllowRealOperation `
            -Confirm:$false


        # ------------------------------------------------------------
        # AD DATA
        # ------------------------------------------------------------

        if ($null -ne $adResult -and $null -ne $adResult.Data) {
            $adData = $adResult.Data
        }
        else {
            $adData = [PSCustomObject]@{
                Found = $null
                Error = if ($null -ne $adResult) { $adResult.Error } else { "AD helper did not return a result." }
                QueryStatus = if ($null -ne $adResult) { $adResult.QueryStatus } else { "Error" }
            }
        }

        $cimData = if ($null -ne $cimResult) { $cimResult.Data } else { $null }
        $collectionErrors = @()
        if ($null -eq $adResult -or -not $adResult.Success) {
            $adMessage = if ($null -ne $adResult -and $adResult.Error) { $adResult.Error } else { "AD query failed without an error message." }
            $collectionErrors += [PSCustomObject]@{ Source = "ActiveDirectory"; Message = $adMessage }
        }
        if ($null -ne $cimResult -and $null -ne $cimResult.Errors) {
            $collectionErrors += @($cimResult.Errors)
        }
        elseif ($null -eq $cimResult -or -not $cimResult.Success) {
            $cimMessage = if ($null -ne $cimResult -and $cimResult.Error) { $cimResult.Error } else { "CIM query returned no usable data." }
            $collectionErrors += [PSCustomObject]@{ Source = "CIM"; Message = $cimMessage }
        }

        $adComplete = ($null -ne $adResult -and $adResult.CollectionStatus -eq "Complete")
        $cimComplete = ($null -ne $cimResult -and $cimResult.CollectionStatus -eq "Complete")
        if ($adComplete -and $cimComplete) { $result.CollectionStatus = "Complete" }
        elseif (($null -ne $adResult -and $adResult.Success) -or ($null -ne $cimResult -and $cimResult.Success)) { $result.CollectionStatus = "Partial" }
        else { $result.CollectionStatus = "Error" }


        # ------------------------------------------------------------
        # CONSOLIDATED INVENTORY
        # ------------------------------------------------------------

        $result.Data = [PSCustomObject]@{

            Hostname = $ComputerName

            CollectionDateTime = (
                Get-Date
            ).ToUniversalTime()


            AD = $adData


            Connectivity = if ($null -ne $cimData -and $null -ne $cimData.Connectivity) { $cimData.Connectivity }
                else {
                    [PSCustomObject]@{
                        Reachable = $null
                        Status = if ($null -ne $cimResult -and $cimResult.QueryStatus -eq "NotQueried") { "NotQueried" } else { "Error" }
                        ResponseTimeMs = $null
                        Error = if ($null -ne $cimResult) { $cimResult.Error } else { "CIM helper did not return a result." }
                    }
                }


            System = if ($null -ne $cimData) { $cimData.System } else { $null }


            OperatingSystem = if ($null -ne $cimData) { $cimData.OperatingSystem } else { $null }


            Processor = if ($null -ne $cimData) { $cimData.Processor } else { $null }


            Memory = if ($null -ne $cimData) { $cimData.Memory } else { $null }


            Storage = if ($null -ne $cimData) { [array]$cimData.Storage } else { [array]@() }


            Network = if ($null -ne $cimData) { [array]$cimData.Network } else { [array]@() }


            BitLocker = if ($null -ne $cimData) { $cimData.BitLocker } else { $null }


            Errors = $collectionErrors
            IsSimulated = $false
            Mode = "Real"
            Status = $result.CollectionStatus
            CollectionStatus = $result.CollectionStatus
            QueryStatus = [PSCustomObject]@{
                ActiveDirectory = if ($null -ne $adResult) { $adResult.QueryStatus } else { "Error" }
                CIM = if ($null -ne $cimResult) { $cimResult.QueryStatus } else { "Error" }
            }
        }


        # ------------------------------------------------------------
        # SUCCESS
        # ------------------------------------------------------------

        $result.Success = (($null -ne $adResult -and $adResult.Success) -or ($null -ne $cimResult -and $cimResult.Success))
        if ($collectionErrors.Count -gt 0) {
            $result.Error = ($collectionErrors | ForEach-Object { $_.Message }) -join "; "
        }
        $result.SimulationMode = $false
        $result.Preview = $false
        $result.IsSimulated = $false
        $result.Mode = "Real"
        $result.Status = if ($result.CollectionStatus -eq "Complete") { "Collected" } else { $result.CollectionStatus }
    }
    catch {

        $result.Error = $_.Exception.Message
        $result.SimulationMode = $false
        $result.Preview = $false
        $result.IsSimulated = $false
        $result.Mode = "Error"
        $result.Status = "Error"
        $result.Cancelled = $false
        $result.CollectionStatus = "Error"
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
