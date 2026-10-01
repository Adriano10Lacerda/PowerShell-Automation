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

        # Detecta se a consulta é local ou remota
        $isLocalComputer = (
            $ComputerName -eq $env:COMPUTERNAME -or
            $ComputerName -eq "localhost" -or
            $ComputerName -eq "."
        )

        # Computer System
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

        # Operating System
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

        # Processor
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

        # BIOS
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

        # Computer System Product
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

        # Serial Number com fallback
        $serialNumber = $bios.SerialNumber

        if ([string]::IsNullOrWhiteSpace($serialNumber)) {
            $serialNumber = $computerProduct.IdentifyingNumber
        }

        # Monta o resultado
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
        }

        $result.Success = $true
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}


Export-ModuleMember -Function Get-ComputerADInfo, Get-ComputerCimInfo
