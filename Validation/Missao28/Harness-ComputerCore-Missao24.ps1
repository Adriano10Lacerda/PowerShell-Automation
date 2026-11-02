# Harness proposto para PowerShell 7.6.9 e Pester 3.4.0.
# O runner futuro deve carregar Pester 3.4.0 antes deste arquivo.
# Executar somente em processo descartável e mediante autorização explícita.

if ($PSVersionTable.PSVersion -ne [version]'7.6.9') {
    throw "PowerShell inesperado: $($PSVersionTable.PSVersion)"
}

$pesterModules = @(Get-Module -Name Pester)
if ($pesterModules.Count -ne 1 -or
    $pesterModules[0].Version -ne [version]'3.4.0') {
    throw 'Pester 3.4.0 precisa estar carregado exatamente uma vez.'
}

# Impede importação automática. Os módulos necessários serão carregados
# explicitamente no processo futuro.
$PSModuleAutoLoadingPreference = 'None'

$modulePath =
    'C:\projetos\PowerShell-Automation\Core\Computer\Computer-Functions.psm1'

# Parsing e inspeção da AST não executam o módulo.
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $modulePath,
    [ref]$tokens,
    [ref]$parseErrors
)

if ($parseErrors.Count -gt 0) {
    throw 'O módulo contém erros de parsing; execução bloqueada.'
}

$qualifiedExternalCalls = @(
    $ast.FindAll(
        {
            param($node)

            if ($node -isnot [System.Management.Automation.Language.CommandAst]) {
                return $false
            }

            $commandName = $node.GetCommandName()
            if ([string]::IsNullOrWhiteSpace($commandName)) {
                return $false
            }

            return $commandName -match (
                '(?i)(^|\\)(Get-ADComputer|Get-CimInstance|' +
                'Get-BitLockerVolume|Invoke-Command|Test-Connection)$'
            )
        },
        $true
    )
)

$dynamicInvocations = @(
    $ast.FindAll(
        {
            param($node)

            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.InvocationOperator -eq
                [System.Management.Automation.Language.TokenKind]::Ampersand -and
            [string]::IsNullOrWhiteSpace($node.GetCommandName())
        },
        $true
    )
)

$uncoveredLaunchCommands = @(
    $ast.FindAll(
        {
            param($node)

            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -in @(
                'Invoke-Expression',
                'Start-Process'
            )
        },
        $true
    )
)

if ($qualifiedExternalCalls.Count -gt 0) {
    throw 'Há chamadas externas qualificadas por módulo; execução bloqueada.'
}

if ($dynamicInvocations.Count -gt 0) {
    throw 'Há invocações dinâmicas; revise-as antes de executar o fluxo.'
}

if ($uncoveredLaunchCommands.Count -gt 0) {
    throw 'Há comandos de execução não cobertos pelo harness.'
}

# Carrega a instância pela localização explícita e guarda o PSModuleInfo.
$module = Import-Module -Name $modulePath -PassThru -ErrorAction Stop
$moduleName = $module.Name
$inventoryCommand = Get-Command `
    -Name Get-ComputerInventory `
    -ErrorAction Stop

if (-not [object]::ReferenceEquals($module, $inventoryCommand.Module)) {
    throw 'Get-ComputerInventory não pertence ao PSModuleInfo retido.'
}

$modulesWithSameName = @(Get-Module -Name $moduleName)
if ($modulesWithSameName.Count -ne 1 -or
    -not [object]::ReferenceEquals($modulesWithSameName[0], $module)) {
    throw 'O nome do módulo não identifica uma instância única.'
}

$guardNames = @(
    'Get-ADComputer',
    'Get-CimInstance',
    'Get-BitLockerVolume',
    'Invoke-Command',
    'Test-Connection',
    'Import-Module'
)

# Aborta se aliases conflitarem no escopo chamador ou no escopo do módulo.
$globalAliasConflicts = @(
    Get-Alias -Name $guardNames -ErrorAction SilentlyContinue
)

$moduleAliasConflicts = @(
    InModuleScope -ModuleName $moduleName {
        $names = @(
            'Get-ADComputer',
            'Get-CimInstance',
            'Get-BitLockerVolume',
            'Invoke-Command',
            'Test-Connection',
            'Import-Module'
        )

        foreach ($name in $names) {
            Get-Alias -Name $name -ErrorAction SilentlyContinue
        }
    }
)

if ($globalAliasConflicts.Count -gt 0 -or
    $moduleAliasConflicts.Count -gt 0) {
    throw 'Há aliases conflitantes; execução bloqueada.'
}

# Estado compartilhado explicitamente por referência entre os escopos
# do arquivo de teste, blocos Pester e InModuleScope.
$global:ComputerCoreHarness = @{
    ModulePath = $modulePath
    ModuleName = $moduleName
    ModuleInfo = $module
    InventoryCommand = $inventoryCommand
    InventoryCommandName = 'Get-ComputerInventory'

    Calibration = @{
        ExternalPassed = $false
        HelpersPassed  = $false
    }

    HelperCalls = @{
        AD  = New-Object 'System.Collections.Generic.List[object]'
        CIM = New-Object 'System.Collections.Generic.List[object]'
    }

    PesterExternalCalls =
        New-Object 'System.Collections.Generic.List[object]'

    GuardFallbackCalls =
        New-Object 'System.Collections.Generic.List[object]'

    ProbeErrors =
        New-Object 'System.Collections.Generic.List[object]'

    ProbeReturns =
        New-Object 'System.Collections.Generic.List[string]'

    FixtureAD = [PSCustomObject]@{
        Success = $true
        Error   = $null
        Data    = [PSCustomObject]@{
            Found   = $true
            Name    = 'ISOLATION-CANARY'
            Enabled = $true
        }
    }

    FixtureCIM = [PSCustomObject]@{
        Success = $true
        Error   = $null
        Data    = [PSCustomObject]@{
            System = [PSCustomObject]@{
                Manufacturer = 'MOCK-MANUFACTURER'
                Model        = 'MOCK-MODEL'
                SerialNumber = 'MOCK-SERIAL'
            }

            OperatingSystem = [PSCustomObject]@{
                Caption      = 'MOCK-OS'
                Version      = '0.0'
                Build        = '0'
                Architecture = 'x64'
            }

            Processor = [PSCustomObject]@{
                Name         = 'MOCK-CPU'
                Cores        = 2
                LogicalCores = 4
            }

            Memory = [PSCustomObject]@{
                TotalGB = 8
            }

            Storage = @()
            Network = @()

            BitLocker = [PSCustomObject]@{
                Status  = 'NotAvailable'
                Volumes = @()
                Error   = $null
            }

            Connectivity = [PSCustomObject]@{
                Reachable      = $true
                ResponseTimeMs = 0
            }
        }
    }
}

Describe 'Computer Core — isolamento com Pester 3.4.0' {

    # Os guards são funções locais ao módulo. Os parâmetros abaixo cobrem
    # as combinações atualmente usadas pelo código de produção.
    # [CmdletBinding()] fornece os parâmetros comuns, incluindo -ErrorAction.
    # Mudanças futuras na assinatura devem reprovar a calibração.

    InModuleScope -ModuleName $global:ComputerCoreHarness.ModuleName {
        function Get-ADComputer {
            [CmdletBinding()]
            param(
                [string]$Identity,
                [object[]]$Properties
            )

            $global:ComputerCoreHarness.GuardFallbackCalls.Add(
                [PSCustomObject]@{
                    Command = 'Get-ADComputer'
                    Values  = @{
                        Identity   = $Identity
                        Properties = $Properties
                    }
                }
            )

            throw 'GUARD-FALLBACK:Get-ADComputer'
        }

        function Get-CimInstance {
            [CmdletBinding()]
            param(
                [string]$ClassName,
                [string]$ComputerName,
                [string]$Filter
            )

            $global:ComputerCoreHarness.GuardFallbackCalls.Add(
                [PSCustomObject]@{
                    Command = 'Get-CimInstance'
                    Values  = @{
                        ClassName    = $ClassName
                        ComputerName = $ComputerName
                        Filter       = $Filter
                    }
                }
            )

            throw 'GUARD-FALLBACK:Get-CimInstance'
        }

        function Get-BitLockerVolume {
            [CmdletBinding()]
            param()

            $global:ComputerCoreHarness.GuardFallbackCalls.Add(
                [PSCustomObject]@{
                    Command = 'Get-BitLockerVolume'
                    Values  = @{}
                }
            )

            throw 'GUARD-FALLBACK:Get-BitLockerVolume'
        }

        function Invoke-Command {
            [CmdletBinding()]
            param(
                [string[]]$ComputerName,
                [scriptblock]$ScriptBlock
            )

            $global:ComputerCoreHarness.GuardFallbackCalls.Add(
                [PSCustomObject]@{
                    Command = 'Invoke-Command'
                    Values  = @{
                        ComputerName = $ComputerName
                        ScriptBlock  = [string]$ScriptBlock
                    }
                }
            )

            throw 'GUARD-FALLBACK:Invoke-Command'
        }

        function Test-Connection {
            [CmdletBinding()]
            param(
                [string[]]$ComputerName,
                [int]$Count
            )

            $global:ComputerCoreHarness.GuardFallbackCalls.Add(
                [PSCustomObject]@{
                    Command = 'Test-Connection'
                    Values  = @{
                        ComputerName = $ComputerName
                        Count        = $Count
                    }
                }
            )

            throw 'GUARD-FALLBACK:Test-Connection'
        }

        function Import-Module {
            [CmdletBinding()]
            param(
                [Parameter(Position = 0)]
                [string[]]$Name
            )

            $global:ComputerCoreHarness.GuardFallbackCalls.Add(
                [PSCustomObject]@{
                    Command = 'Import-Module'
                    Values  = @{
                        Name = $Name
                    }
                }
            )

            throw 'GUARD-FALLBACK:Import-Module'
        }
    }

    # Mocks internos: registram parâmetros e retornam fixtures.
    Mock -CommandName Get-ComputerADInfo `
        -ModuleName $global:ComputerCoreHarness.ModuleName `
        -MockWith {
            $global:ComputerCoreHarness.HelperCalls.AD.Add(
                [PSCustomObject]@{
                    Hostname = $Hostname
                }
            )

            return $global:ComputerCoreHarness.FixtureAD
        }

    Mock -CommandName Get-ComputerCimInfo `
        -ModuleName $global:ComputerCoreHarness.ModuleName `
        -MockWith {
            $global:ComputerCoreHarness.HelperCalls.CIM.Add(
                [PSCustomObject]@{
                    ComputerName = $ComputerName
                }
            )

            return $global:ComputerCoreHarness.FixtureCIM
        }

    # Mocks externos catch-all, sem ParameterFilter.
    Mock -CommandName Get-ADComputer `
        -ModuleName $global:ComputerCoreHarness.ModuleName `
        -MockWith {
            $global:ComputerCoreHarness.PesterExternalCalls.Add(
                [PSCustomObject]@{
                    Command = 'Get-ADComputer'
                    Values  = @{
                        Identity   = $Identity
                        Properties = $Properties
                    }
                }
            )

            throw 'PESTER-FAIL-FAST:Get-ADComputer'
        }

    Mock -CommandName Get-CimInstance `
        -ModuleName $global:ComputerCoreHarness.ModuleName `
        -MockWith {
            $global:ComputerCoreHarness.PesterExternalCalls.Add(
                [PSCustomObject]@{
                    Command = 'Get-CimInstance'
                    Values  = @{
                        ClassName    = $ClassName
                        ComputerName = $ComputerName
                        Filter       = $Filter
                    }
                }
            )

            throw 'PESTER-FAIL-FAST:Get-CimInstance'
        }

    Mock -CommandName Get-BitLockerVolume `
        -ModuleName $global:ComputerCoreHarness.ModuleName `
        -MockWith {
            $global:ComputerCoreHarness.PesterExternalCalls.Add(
                [PSCustomObject]@{
                    Command = 'Get-BitLockerVolume'
                    Values  = @{}
                }
            )

            throw 'PESTER-FAIL-FAST:Get-BitLockerVolume'
        }

    Mock -CommandName Invoke-Command `
        -ModuleName $global:ComputerCoreHarness.ModuleName `
        -MockWith {
            $global:ComputerCoreHarness.PesterExternalCalls.Add(
                [PSCustomObject]@{
                    Command = 'Invoke-Command'
                    Values  = @{
                        ComputerName = $ComputerName
                        ScriptBlock  = [string]$ScriptBlock
                    }
                }
            )

            throw 'PESTER-FAIL-FAST:Invoke-Command'
        }

    Mock -CommandName Test-Connection `
        -ModuleName $global:ComputerCoreHarness.ModuleName `
        -MockWith {
            $global:ComputerCoreHarness.PesterExternalCalls.Add(
                [PSCustomObject]@{
                    Command = 'Test-Connection'
                    Values  = @{
                        ComputerName = $ComputerName
                        Count        = $Count
                    }
                }
            )

            throw 'PESTER-FAIL-FAST:Test-Connection'
        }

    Mock -CommandName Import-Module `
        -ModuleName $global:ComputerCoreHarness.ModuleName `
        -MockWith {
            $global:ComputerCoreHarness.PesterExternalCalls.Add(
                [PSCustomObject]@{
                    Command = 'Import-Module'
                    Values  = @{
                        Name = $Name
                    }
                }
            )

            throw 'PESTER-FAIL-FAST:Import-Module'
        }

    Context 'Calibração dos interceptadores externos' {
        It 'aciona cada mock externo no módulo, sem fallback nem retorno normal' {
            $global:ComputerCoreHarness.PesterExternalCalls.Clear()
            $global:ComputerCoreHarness.GuardFallbackCalls.Clear()
            $global:ComputerCoreHarness.ProbeErrors.Clear()
            $global:ComputerCoreHarness.ProbeReturns.Clear()

            InModuleScope -ModuleName $global:ComputerCoreHarness.ModuleName {
                function Invoke-RecordedProbe {
                    param(
                        [string]$ProbeName,
                        [scriptblock]$Probe
                    )

                    try {
                        & $Probe
                        $global:ComputerCoreHarness.ProbeReturns.Add($ProbeName)
                    }
                    catch {
                        $global:ComputerCoreHarness.ProbeErrors.Add(
                            [PSCustomObject]@{
                                Name    = $ProbeName
                                Message = $_.Exception.Message
                            }
                        )
                    }
                }

                Invoke-RecordedProbe 'Get-ADComputer' {
                    Get-ADComputer -Identity 'ISOLATION-CANARY'
                }

                Invoke-RecordedProbe 'Get-CimInstance' {
                    Get-CimInstance -ClassName 'Win32_ComputerSystem'
                }

                Invoke-RecordedProbe 'Get-BitLockerVolume' {
                    Get-BitLockerVolume -ErrorAction Stop
                }

                Invoke-RecordedProbe 'Invoke-Command' {
                    Invoke-Command `
                        -ComputerName 'ISOLATION-CANARY' `
                        -ScriptBlock { 'CANARY' } `
                        -ErrorAction Stop
                }

                Invoke-RecordedProbe 'Test-Connection' {
                    Test-Connection `
                        -ComputerName 'ISOLATION-CANARY' `
                        -Count 1 `
                        -ErrorAction Stop
                }

                Invoke-RecordedProbe 'Import-Module' {
                    Import-Module ActiveDirectory -ErrorAction Stop
                }
            }

            foreach ($probeName in @(
                'Get-ADComputer',
                'Get-CimInstance',
                'Get-BitLockerVolume',
                'Invoke-Command',
                'Test-Connection',
                'Import-Module'
            )) {
                $probeErrorsForCommand = @(
                    $global:ComputerCoreHarness.ProbeErrors |
                        Where-Object { $_.Name -eq $probeName }
                )

                if ($probeErrorsForCommand.Count -ne 1 -or
                    $probeErrorsForCommand[0].Message -notlike
                        "PESTER-FAIL-FAST:$probeName*") {
                    throw "Calibração não atingiu o mock Pester de $probeName."
                }

                Assert-MockCalled -CommandName $probeName `
                    -ModuleName $global:ComputerCoreHarness.ModuleName `
                    -Times 1 -Exactly -Scope It
            }

            $global:ComputerCoreHarness.ProbeReturns.Count | Should Be 0
            $global:ComputerCoreHarness.GuardFallbackCalls.Count | Should Be 0
            $global:ComputerCoreHarness.PesterExternalCalls.Count | Should Be 6

            $global:ComputerCoreHarness.Calibration.ExternalPassed = $true
        }
    }

    Context 'Calibração dos helpers internos' {
        It 'aciona os mocks dos helpers dentro do módulo' {
            if (-not $global:ComputerCoreHarness.Calibration.ExternalPassed) {
                throw 'Calibração externa falhou; probe de helpers bloqueado.'
            }

            $global:ComputerCoreHarness.HelperCalls.AD.Clear()
            $global:ComputerCoreHarness.HelperCalls.CIM.Clear()
            $global:ComputerCoreHarness.PesterExternalCalls.Clear()
            $global:ComputerCoreHarness.GuardFallbackCalls.Clear()

            InModuleScope -ModuleName $global:ComputerCoreHarness.ModuleName {
                Get-ComputerADInfo -Hostname 'ISOLATION-CANARY'
                Get-ComputerCimInfo -ComputerName 'ISOLATION-CANARY'
            }

            Assert-MockCalled -CommandName Get-ComputerADInfo `
                -ModuleName $global:ComputerCoreHarness.ModuleName `
                -Times 1 -Exactly -Scope It

            Assert-MockCalled -CommandName Get-ComputerCimInfo `
                -ModuleName $global:ComputerCoreHarness.ModuleName `
                -Times 1 -Exactly -Scope It

            $global:ComputerCoreHarness.HelperCalls.AD.Count | Should Be 1
            $global:ComputerCoreHarness.HelperCalls.AD[0].Hostname |
                Should Be 'ISOLATION-CANARY'

            $global:ComputerCoreHarness.HelperCalls.CIM.Count | Should Be 1
            $global:ComputerCoreHarness.HelperCalls.CIM[0].ComputerName |
                Should Be 'ISOLATION-CANARY'

            $global:ComputerCoreHarness.PesterExternalCalls.Count | Should Be 0
            $global:ComputerCoreHarness.GuardFallbackCalls.Count | Should Be 0

            $global:ComputerCoreHarness.Calibration.HelpersPassed = $true
        }
    }

    Context 'Fluxo controlado de Get-ComputerInventory' {
        It 'usa os mocks internos e não chama comandos externos' {
            if (-not $global:ComputerCoreHarness.Calibration.ExternalPassed -or
                -not $global:ComputerCoreHarness.Calibration.HelpersPassed) {
                throw 'Calibração incompleta; fluxo de inventário bloqueado.'
            }

            $global:ComputerCoreHarness.HelperCalls.AD.Clear()
            $global:ComputerCoreHarness.HelperCalls.CIM.Clear()
            $global:ComputerCoreHarness.PesterExternalCalls.Clear()
            $global:ComputerCoreHarness.GuardFallbackCalls.Clear()

$result = & $global:ComputerCoreHarness.InventoryCommand -ComputerName 'ISOLATION-CANARY'

            $result.Success | Should Be $true
            $result.Data.Hostname | Should Be 'ISOLATION-CANARY'
            $result.Data.AD.Name | Should Be 'ISOLATION-CANARY'
            $result.Data.System.Manufacturer | Should Be 'MOCK-MANUFACTURER'

            $global:ComputerCoreHarness.HelperCalls.AD.Count | Should Be 1
            $global:ComputerCoreHarness.HelperCalls.AD[0].Hostname |
                Should Be 'ISOLATION-CANARY'

            $global:ComputerCoreHarness.HelperCalls.CIM.Count | Should Be 1
            $global:ComputerCoreHarness.HelperCalls.CIM[0].ComputerName |
                Should Be 'ISOLATION-CANARY'

            Assert-MockCalled -CommandName Get-ComputerADInfo `
                -ModuleName $global:ComputerCoreHarness.ModuleName `
                -Times 1 -Exactly -Scope It

            Assert-MockCalled -CommandName Get-ComputerCimInfo `
                -ModuleName $global:ComputerCoreHarness.ModuleName `
                -Times 1 -Exactly -Scope It

            foreach ($externalName in @(
                'Get-ADComputer',
                'Get-CimInstance',
                'Get-BitLockerVolume',
                'Invoke-Command',
                'Test-Connection',
                'Import-Module'
            )) {
                Assert-MockCalled -CommandName $externalName `
                    -ModuleName $global:ComputerCoreHarness.ModuleName `
                    -Times 0 -Exactly -Scope It
            }

            $global:ComputerCoreHarness.PesterExternalCalls.Count | Should Be 0
            $global:ComputerCoreHarness.GuardFallbackCalls.Count | Should Be 0
        }
    }
}
