function New-ComputerInventoryModel {
    param(
        [string]$Hostname
    )

    [PSCustomObject]@{
        CollectionDateTime = (Get-Date).ToUniversalTime()
        Hostname           = $Hostname

        AD = [PSCustomObject]@{
            Found        = $null
            Enabled      = $null
            OperatingSystem = $null
            Description  = $null
            ManagedBy    = $null
            Created      = $null
            LastUpdated  = $null
            DistinguishedName = $null
        }

        Connectivity = [PSCustomObject]@{
            Reachable = $null
            ResponseTimeMs = $null
        }

        System = [PSCustomObject]@{
            Manufacturer = $null
            Model        = $null
            SerialNumber = $null
        }

        OperatingSystem = [PSCustomObject]@{
            Caption      = $null
            Version      = $null
            Build        = $null
            Architecture = $null
        }

        Processor = [PSCustomObject]@{
            Name          = $null
            Cores         = $null
            LogicalCores  = $null
        }

        Memory = [PSCustomObject]@{
            TotalGB = $null
        }

        Storage = @()

        Network = @()

        BitLocker = @()

        Errors = @()
    }
}