#Requires -Version 5.1
# Prepared for separately authorized offline execution. NOT RUN in Mission 81-E.
$ErrorActionPreference = 'Stop'
$launcherPath = Join-Path $PSScriptRoot 'Interface.ps1'
$source = [IO.File]::ReadAllText($launcherPath)

function Assert-DemoCondition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

# Fail closed before invoking the launcher: only console I/O is allowed in Demo.
$tokens = $null; $parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($launcherPath, [ref]$tokens, [ref]$parseErrors)
Assert-DemoCondition ($parseErrors.Count -eq 0) 'Launcher has parser errors.'
Assert-DemoCondition ($ast.ParamBlock.Parameters.Count -eq 1 -and
    $ast.ParamBlock.Parameters[0].Name.VariablePath.UserPath -ceq 'Demo' -and
    $ast.ParamBlock.Parameters[0].StaticType -eq [System.Management.Automation.SwitchParameter]) 'Expected only switch Demo.'
$branch = $ast.EndBlock.Statements[0]
Assert-DemoCondition ($branch -is [System.Management.Automation.Language.IfStatementAst]) 'Demo must precede normal startup.'
Assert-DemoCondition ($branch.Clauses.Count -eq 1 -and $branch.Clauses[0].Item1.Extent.Text -ceq '$Demo' -and
    $null -eq $branch.ElseClause) 'Unexpected Demo guard.'
foreach ($command in $branch.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)) {
    Assert-DemoCondition ($command.GetCommandName() -cin @('Write-Host','Read-Host')) 'Unexpected command in Demo.'
}
foreach ($variable in $branch.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
    Assert-DemoCondition ($variable.VariablePath.UserPath -cin @('Demo','ErrorActionPreference','demoPages','demoOption','null')) 'Unexpected variable or host identity access in Demo.'
}
foreach ($member in $branch.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] }, $true)) {
    Assert-DemoCondition ($member -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        -not $member.Static -and $member.Expression.Extent.Text -ceq '$demoPages' -and
        $member.Member.Value -ceq 'ContainsKey') 'Unexpected member or filesystem API in Demo.'
}
Assert-DemoCondition (@($branch.FindAll({ param($n) $n -is [System.Management.Automation.Language.TypeExpressionAst] -or
    $n -is [System.Management.Automation.Language.ExitStatementAst] -or $n -is [System.Management.Automation.Language.RedirectionAst] }, $true)).Count -eq 0) 'Demo contains a type, exit, or redirection.'
Assert-DemoCondition ($branch.Clauses[0].Item2.Statements[-1] -is [System.Management.Automation.Language.ReturnStatementAst]) 'Demo must return before normal startup.'
Assert-DemoCondition ($branch.Extent.Text -match '\$ErrorActionPreference\s*=\s*''Stop''') 'Demo errors must terminate.'

# Compare the entire original normal body, ignoring only CRLF/LF representation.
$marker = '$InterfaceFunctionsPath = Join-Path $PSScriptRoot "Interface-Functions.psm1"'
$offset = $source.IndexOf($marker, [StringComparison]::Ordinal)
Assert-DemoCondition ($offset -ge 0) 'Normal startup marker is missing.'
$normalBytes = [Text.Encoding]::UTF8.GetBytes($source.Substring($offset).Replace("`r`n", "`n"))
$sha = [Security.Cryptography.SHA256]::Create()
try { $normalHash = ([BitConverter]::ToString($sha.ComputeHash($normalBytes))).Replace('-', '') }
finally { $sha.Dispose() }
Assert-DemoCondition ($normalHash -ceq '445DC31D1340D9736EF4CF532124C5EDDE4905C1323925FB1664815CB421E7C3') 'Original normal flow changed.'

function Invoke-DemoScenario {
    param([string[]]$Inputs, [ValidateSet('Demo','Normal','FalseDemo')][string]$Mode = 'Demo', [int]$FailReadAt = 0)
    $fixture = [PSCustomObject]@{
        InputQueue = [Collections.Generic.Queue[string]]::new()
        Output = [Collections.Generic.List[string]]::new()
        Forbidden = [Collections.Generic.List[string]]::new()
        Reads = 0; Imports = 0; PathChecks = 0; Returned = $false; Error = $null
    }
    foreach ($value in $Inputs) { $fixture.InputQueue.Enqueue($value) }
    try {
        & {
            param($TargetScript, $State, $ScenarioMode, $FailureIndex)
            function Write-Host {
                param([object]$Object, [object]$ForegroundColor, [switch]$NoNewline)
                $State.Output.Add([string]$Object)
            }
            function Read-Host {
                param([string]$Prompt)
                $State.Reads++
                if ($FailureIndex -gt 0 -and $State.Reads -eq $FailureIndex) { throw 'Injected read failure.' }
                if ($State.InputQueue.Count -eq 0) { throw 'Fixture input exhausted.' }
                return $State.InputQueue.Dequeue()
            }
            function Join-Path {
                param([string]$Path, [string]$ChildPath)
                if ($ScenarioMode -eq 'Demo') { $State.Forbidden.Add('Join-Path'); throw 'Demo consulted a path.' }
                return [IO.Path]::Combine($Path, $ChildPath)
            }
            function Test-Path {
                param([string]$Path)
                if ($ScenarioMode -eq 'Demo') { $State.Forbidden.Add('Test-Path'); throw 'Demo consulted a file.' }
                $State.PathChecks++; return $true
            }
            function Import-Module {
                param([string]$Name, [switch]$Force)
                if ($ScenarioMode -eq 'Demo') { $State.Forbidden.Add('Import-Module'); throw 'Demo imported a module.' }
                $State.Imports++ # Stub only: never import the real module.
            }
            function Clear-Host {
                if ($ScenarioMode -eq 'Demo') { $State.Forbidden.Add('Clear-Host'); throw 'Unexpected Demo host operation.' }
            }
            $blocked = @('Get-Content','Set-Content','Add-Content','Out-File','New-Item','Remove-Item','Copy-Item','Move-Item',
                'Get-Item','Get-ChildItem','Export-Csv','Export-Clixml','Get-ADUser','Get-ADComputer','Get-ADDomain',
                'Get-ADGroup','Get-MgContext','Get-MgUser','New-MgUser','Connect-MgGraph','Get-GPO','New-GPO',
                'Get-GPOReport','Get-CimInstance','Get-WmiObject','Get-BitLockerVolume','Test-Connection',
                'Test-NetConnection','Resolve-DnsName','Invoke-Command','Invoke-WebRequest','Invoke-RestMethod',
                'Invoke-Expression','Start-Process','Get-ComputerInfo','Get-Date','hostname','whoami','Pause',
                'Start-PasswordGenerator','Start-Configuration','Start-ADUserProvisioning','Start-EntraUserProvisioning',
                'Start-ComputerInventory','Start-ADGroupManagement','Start-GPOManagement','Start-Reporting')
            foreach ($name in $blocked) {
                Set-Item -LiteralPath ('Function:\local:' + $name) -Value {
                    $State.Forbidden.Add($MyInvocation.MyCommand.Name)
                    throw 'Forbidden operation reached a sentinel.'
                }
            }
            if ($ScenarioMode -eq 'Normal') { & $TargetScript }
            elseif ($ScenarioMode -eq 'FalseDemo') { & $TargetScript -Demo:$false }
            else { & $TargetScript -Demo }
            $State.Returned = $true
        } $launcherPath $fixture $Mode $FailReadAt
    }
    catch { $fixture.Error = $_.Exception.Message }
    finally {
        # A caught sentinel exception must still fail the scenario.
        Assert-DemoCondition ($fixture.Forbidden.Count -eq 0) ('Forbidden calls: ' + ($fixture.Forbidden -join ','))
    }
    return $fixture
}

$script:passed = 0; $script:failed = 0
function Invoke-DemoCheck {
    param([string]$Name, [scriptblock]$Check)
    try { & $Check; $script:passed++; Write-Host "PASS: $Name" }
    catch { $script:failed++; Write-Host "FAIL: $Name - $($_.Exception.Message)" }
}
Invoke-DemoCheck 'All eight fictional pages and safe return' {
    $inputs = @(); foreach ($number in 1..8) { $inputs += [string]$number; $inputs += '' }; $inputs += '0'
    $r = Invoke-DemoScenario -Inputs $inputs
    Assert-DemoCondition ($r.Returned -and $null -eq $r.Error -and $r.InputQueue.Count -eq 0) 'Navigation failed.'
    foreach ($label in @('NAO GERADA','usuario.demo','example.invalid','DEMO-PC-001','DEMO-GROUP','DEMO-POLICY','3 registros','Nenhum JSON carregado')) {
        Assert-DemoCondition (($r.Output -join "`n").Contains($label)) "Missing fixture: $label"
    }
    Assert-DemoCondition ($r.Imports -eq 0 -and $r.PathChecks -eq 0) 'Demo initialized dependencies.'
}
Invoke-DemoCheck 'Invalid input is text, never a command' {
    $r = Invoke-DemoScenario -Inputs @('9','','Get-ADUser; whoami','0')
    Assert-DemoCondition ($r.Returned -and $null -eq $r.Error -and $r.InputQueue.Count -eq 0) 'Invalid input escaped navigation.'
    Assert-DemoCondition (@($r.Output | Where-Object { $_ -eq 'Opcao invalida. Escolha 1-8 ou 0.' }).Count -eq 3) 'Expected three invalid inputs.'
}
Invoke-DemoCheck 'Immediate exit returns to caller' {
    $r = Invoke-DemoScenario -Inputs @('0')
    Assert-DemoCondition ($r.Returned -and $null -eq $r.Error -and $r.Reads -eq 1) 'Immediate exit failed.'
}
Invoke-DemoCheck 'Menu read failure cannot fall through' {
    $r = Invoke-DemoScenario -Inputs @() -FailReadAt 1
    Assert-DemoCondition (-not $r.Returned -and $r.Error -eq 'Injected read failure.' -and $r.Imports -eq 0 -and $r.PathChecks -eq 0) 'Read failure reached normal startup.'
}
Invoke-DemoCheck 'Page read failure cannot fall through' {
    $r = Invoke-DemoScenario -Inputs @('4') -FailReadAt 2
    Assert-DemoCondition (-not $r.Returned -and $r.Error -eq 'Injected read failure.' -and $r.Imports -eq 0 -and $r.PathChecks -eq 0) 'Page failure reached normal startup.'
}
foreach ($normalMode in @('Normal','FalseDemo')) {
    Invoke-DemoCheck "Normal startup preserved: $normalMode (stubbed)" {
        $r = Invoke-DemoScenario -Inputs @('0') -Mode $normalMode
        Assert-DemoCondition ($r.Returned -and $null -eq $r.Error -and $r.Imports -eq 1 -and $r.PathChecks -eq 1) 'Normal startup contract changed.'
    }
}
Write-Host "Demo checks: $script:passed passed; $script:failed failed."
if ($script:failed -gt 0) { exit 1 }
