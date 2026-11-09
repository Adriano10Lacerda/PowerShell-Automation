#Requires -Version 5.1
Set-StrictMode -Version Latest

function New-AdminHarnessState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectRoot)

    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    [pscustomobject]@{
        Mode = 'SyntheticOnly'
        ProjectRoot = $root
        RunId = [guid]::NewGuid().ToString('N')
        Modules = [System.Collections.ArrayList]::new()
        ActiveModules = @{}
        ImportLog = [System.Collections.ArrayList]::new()
        ImportDepth = 0
        Commands = @{}
        CapturedReferences = [System.Collections.ArrayList]::new()
        AllowedSyntheticImports = @{}
        Counters = [ordered]@{
            ImportModule = 0; GetModule = 0; GetADUser = 0; GetADGroup = 0
            GetADGroupMember = 0; Unlock = 0; Enable = 0; Disable = 0; SetUser = 0
            AddGroupMember = 0; RemoveGroupMember = 0; Audit = 0; Unexpected = 0
        }
        Results = [System.Collections.ArrayList]::new()
        Blocked = $true
    }
}

function Resolve-AdminAllowedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AllowedRoot,
        [switch]$RequireExisting
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'FAIL-CLOSED: caminho vazio.' }
    if ($Path -match '[*?\[\]]') { throw 'FAIL-CLOSED: wildcards não são permitidos em caminhos de dependência.' }
    if ($Path.StartsWith('\\') -or $Path -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { throw 'FAIL-CLOSED: caminhos de rede e URI não são permitidos.' }
    $root = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $candidate = [IO.Path]::GetFullPath($Path)
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "FAIL-CLOSED: caminho fora da raiz permitida: $candidate"
    }
    if ($RequireExisting) {
        if (-not (Test-Path -LiteralPath $candidate)) { throw "FAIL-CLOSED: caminho não existe: $candidate" }
        $current = $candidate
        while ($true) {
            if (Test-Path -LiteralPath $current) {
                $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "FAIL-CLOSED: caminho atravessa reparse point: $current" }
            }
            if ($current -eq $root) { break }
            $parent = Split-Path -Parent $current
            if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { throw 'FAIL-CLOSED: caminho não alcançou a raiz permitida.' }
            $current = $parent
        }
        $resolved = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate -ErrorAction Stop).ProviderPath)
        if (-not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'FAIL-CLOSED: caminho resolvido fora da raiz permitida.' }
        $candidate = $resolved
    }
    return $candidate
}

function Assert-AdminImportAllowed {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Path)
    if ($State.Mode -ne 'SyntheticOnly') { throw 'FAIL-CLOSED: modo de harness não reconhecido.' }
    $full = Resolve-AdminAllowedPath -Path $Path -AllowedRoot $State.ProjectRoot
    if (-not $State.AllowedSyntheticImports.ContainsKey($full)) {
        $State.Counters.Unexpected++
        throw "FAIL-CLOSED: import não consta da allowlist sintética: $full"
    }
    return $full
}

function Register-AdminSyntheticModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Path,
        [switch]$FailImport,
        [switch]$FailInstrumentation
    )
    $full = Resolve-AdminAllowedPath -Path $Path -AllowedRoot $State.ProjectRoot
    $State.AllowedSyntheticImports[$full] = [pscustomobject]@{
        Name = $Name; Path = $full; FailImport = [bool]$FailImport
        FailInstrumentation = [bool]$FailInstrumentation
    }
    return $full
}

function Register-AdminModuleInstance {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Path, [string]$InstanceId = '')
    $full = Resolve-AdminAllowedPath -Path $Path -AllowedRoot $State.ProjectRoot
    if ([string]::IsNullOrWhiteSpace($InstanceId)) { $InstanceId = [guid]::NewGuid().ToString('N') }
    $module = [pscustomobject]@{ Name = $Name; Path = $full; InstanceId = $InstanceId; Generation = $State.Modules.Count + 1 }
    [void]$State.Modules.Add($module)
    $State.ActiveModules[$full] = $module
    return $module
}

function Assert-AdminModuleIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Expected, [Parameter(Mandatory)]$Actual)
    if ($null -eq $Actual -or $Expected.InstanceId -ne $Actual.InstanceId -or $Expected.Path -ne $Actual.Path) {
        throw 'FAIL-CLOSED: instância de módulo substituída ou inesperada.'
    }
    return $true
}

function Register-AdminCapturedReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][string]$CommandName, [Parameter(Mandatory)]$Module, [Parameter(Mandatory)][string]$Sentinel)
    $ref = [pscustomobject]@{ CommandName = $CommandName; ModuleInstanceId = $Module.InstanceId; ModulePath = $Module.Path; Sentinel = $Sentinel }
    [void]$State.CapturedReferences.Add($ref)
    return $ref
}

function Assert-AdminCapturedReferencesCurrent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    foreach ($ref in $State.CapturedReferences) {
        $current = @($State.Commands.Values | Where-Object { $_.Name -eq $ref.CommandName -and $_.ModuleInstanceId -eq $ref.ModuleInstanceId -and $_.Sentinel -eq $ref.Sentinel })
        if ($current.Count -ne 1) { throw "FAIL-CLOSED: referência obsoleta ou ambígua: $($ref.CommandName)" }
        $module = @($State.Modules | Where-Object { $_.InstanceId -eq $ref.ModuleInstanceId })
        if ($module.Count -ne 1) { throw "FAIL-CLOSED: módulo da referência não é a instância ativa: $($ref.CommandName)" }
        if (-not $State.ActiveModules.ContainsKey($ref.ModulePath) -or $State.ActiveModules[$ref.ModulePath].InstanceId -ne $ref.ModuleInstanceId) {
            throw "FAIL-CLOSED: referência obsoleta após reimportação: $($ref.CommandName)"
        }
    }
    return $true
}

function Register-AdminSyntheticStub {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Module,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Parameters,
        [Parameter(Mandatory)][string]$Sentinel,
        [Parameter(Mandatory)][scriptblock]$Handler
    )
    if ([string]::IsNullOrWhiteSpace($Sentinel)) { throw 'FAIL-CLOSED: sentinela vazia.' }
    $key = $Module.InstanceId + '|' + $Name
    $State.Commands[$key] = [pscustomobject]@{
        Name = $Name; ModuleInstanceId = $Module.InstanceId
        Parameters = @($Parameters); Sentinel = $Sentinel; Handler = $Handler
        CommandType = 'Function'
    }
    return $State.Commands[$key]
}

function Assert-AdminSyntheticStub {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Module, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RequiredParameters, [Parameter(Mandatory)][string]$Sentinel)
    $key = $Module.InstanceId + '|' + $Name
    if (-not $State.Commands.ContainsKey($key)) { throw "FAIL-CLOSED: stub ausente: $Name" }
    $command = $State.Commands[$key]
    if ($command.CommandType -ne 'Function' -or $command.Sentinel -ne $Sentinel) { throw "FAIL-CLOSED: identidade/sentinela inválida: $Name" }
    foreach ($parameter in $RequiredParameters) {
        if ($command.Parameters -notcontains $parameter) { throw "FAIL-CLOSED: assinatura incompatível em ${Name}: $parameter" }
    }
    return $command
}

function Install-AdminModuleStub {
    <# Installs a synthetic/test stub in the script scope of one identified PSModuleInfo. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module,
        [Parameter(Mandatory)][string]$CommandName,
        [Parameter(Mandatory)][scriptblock]$Stub,
        [Parameter(Mandatory)][string]$Sentinel,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$RequiredParameters,
        [Parameter(Mandatory)][string]$ExpectedModulePath,
        [Parameter(Mandatory)][string]$ProjectRoot
    )
    $allowedExpectedPath = Resolve-AdminAllowedPath -Path $ExpectedModulePath -AllowedRoot $ProjectRoot -RequireExisting
    if ([IO.Path]::GetFullPath($Module.Path) -ne $allowedExpectedPath) { throw 'FAIL-CLOSED: caminho da instância não corresponde ao esperado.' }
    if ($Stub.ToString() -notlike "*$Sentinel*") { throw "FAIL-CLOSED: corpo do stub não contém sentinela $Sentinel." }
    & $Module {
        param($Name, $Body)
        Set-Item -Path ("Function:\script:" + $Name) -Value $Body -Force -ErrorAction Stop
    } $CommandName $Stub
    $resolution = & $Module {
        param($Name)
        $command = Get-Command -Name $Name -CommandType Function -ErrorAction Stop
        $sessionModule = $ExecutionContext.SessionState.Module
        [pscustomobject]@{
            Command = $command
            CommandType = $command.CommandType
            Definition = $command.Definition
            ParameterNames = @($command.Parameters.Keys)
            SessionModule = $sessionModule
            SessionModulePath = $sessionModule.Path
        }
    } $CommandName
    if (-not [object]::ReferenceEquals($resolution.SessionModule, $Module) -or
        [IO.Path]::GetFullPath($resolution.SessionModulePath) -ne $allowedExpectedPath) {
        throw "FAIL-CLOSED: $CommandName resolveu fora do SessionState esperado."
    }
    foreach ($parameter in $RequiredParameters) {
        if ($resolution.ParameterNames -notcontains $parameter) { throw "FAIL-CLOSED: assinatura incompatível em ${CommandName}: $parameter" }
    }
    if ($resolution.Definition -notlike "*$Sentinel*") { throw "FAIL-CLOSED: sentinela não encontrada na função resolvida: $CommandName" }
    return [pscustomobject]@{
        Name = $CommandName; CommandType = $resolution.CommandType
        Module = $resolution.SessionModule; ModulePath = $resolution.SessionModulePath
        Parameters = $resolution.ParameterNames; Sentinel = $Sentinel
    }
}

function Invoke-AdminSyntheticImport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][scriptblock]$Instrument,
        [scriptblock]$NestedImports,
        [switch]$Force
    )
    $full = Assert-AdminImportAllowed -State $State -Path $Path
    $spec = $State.AllowedSyntheticImports[$full]
    if ($State.ActiveModules.ContainsKey($full) -and -not $Force) {
        Assert-AdminCapturedReferencesCurrent -State $State | Out-Null
        return $State.ActiveModules[$full]
    }
    $State.Counters.ImportModule++
    $State.ImportDepth++
    [void]$State.ImportLog.Add([pscustomobject]@{ Path=$full; Name=$spec.Name; Force=[bool]$Force; Depth=$State.ImportDepth })
    try {
        if ($spec.FailImport) { throw "SYNTHETIC-IMPORT-FAIL:$($spec.Name)" }
        if ($null -ne $NestedImports) {
            $nestedResult = & $NestedImports $State
            if ($null -eq $nestedResult -or -not $nestedResult.Success) { throw "FAIL-CLOSED: import aninhado não aprovado para $($spec.Name)." }
        }
        $instance = Register-AdminModuleInstance -State $State -Name $spec.Name -Path $full
        if ($spec.FailInstrumentation) { throw "FAIL-CLOSED: instrumentação falhou para $($spec.Name); consumidor não recebeu a instância." }
        $instrumented = & $Instrument $State $instance
        if (-not $instrumented) { throw "FAIL-CLOSED: gate de instrumentação não aprovado para $($spec.Name)." }
        Assert-AdminCapturedReferencesCurrent -State $State | Out-Null
        return $instance
    }
    finally { $State.ImportDepth-- }
}

function Invoke-AdminSyntheticCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)]$Module, [Parameter(Mandatory)][string]$Name, [hashtable]$Arguments = @{})
    $key = $Module.InstanceId + '|' + $Name
    if (-not $State.Commands.ContainsKey($key)) { $State.Counters.Unexpected++; throw "FAIL-CLOSED: comando sem stub: $Name" }
    return & $State.Commands[$key].Handler $State $Arguments
}

function Test-AdminSyntheticMutationGate {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scenario)
    $reasons = [System.Collections.Generic.List[string]]::new()
    if ($Scenario.SimulationMode) { $reasons.Add('SimulationMode') }
    if ($Scenario.Preview) { $reasons.Add('Preview') }
    if ($Scenario.WhatIf) { $reasons.Add('WhatIf') }
    if (-not $Scenario.Execute) { $reasons.Add('Execute ausente') }
    if (-not $Scenario.AllowRealRead) { $reasons.Add('autorização de leitura ausente') }
    if (-not $Scenario.AllowRealWrite -or -not $Scenario.WriteAuthorizationValid) { $reasons.Add('autorização de escrita inválida/ausente') }
    if ($Scenario.AuthorizationOperation -ne $Scenario.Operation) { $reasons.Add('autorização de outra operação') }
    if (-not $Scenario.ShouldProcess) { $reasons.Add('ShouldProcess recusado') }
    if ($Scenario.Cancelled) { $reasons.Add('Cancelado') }
    [pscustomobject]@{ Allowed = ($reasons.Count -eq 0); Reasons = @($reasons); Status = if ($reasons.Count) { 'Blocked' } else { 'AuthorizedFixtureOnly' } }
}

function Invoke-AdminSyntheticMutation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)]$Fixture,
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][string]$MutationCounter,
        [string[]]$ReadCounters = @('GetADUser'),
        [hashtable]$ReadStatuses = @{},
        [switch]$NoMutationRequired
    )
    $gate = Test-AdminSyntheticMutationGate -Scenario $Scenario
    if (-not $gate.Allowed) { return [pscustomobject]@{ Success = $false; Status = 'Blocked'; Changed = $false; Error = ($gate.Reasons -join '; '); Gate = $gate } }
    foreach ($readCounter in $ReadCounters) {
        if (-not $State.Counters.Contains($readCounter)) { throw "FAIL-CLOSED: contador de leitura não declarado: $readCounter" }
        $State.Counters[$readCounter]++
        $queryStatus = if ($ReadStatuses.ContainsKey($readCounter)) { $ReadStatuses[$readCounter] } else { $Fixture.QueryStatus }
        if ($queryStatus -eq 'NotFound') { return [pscustomobject]@{ Success = $false; Status = 'NotFound'; Changed = $false; Error = "Fixture sem resultado em $readCounter."; Gate = $gate } }
        if ($queryStatus -eq 'Error') { return [pscustomobject]@{ Success = $false; Status = 'Error'; Changed = $false; Error = $Fixture.Error; Gate = $gate } }
        if ($queryStatus -notin @('Found','Complete',$null,'')) { throw "FAIL-CLOSED: estado de leitura desconhecido: $queryStatus" }
    }
    if ($NoMutationRequired) { return [pscustomobject]@{ Success = $true; Status = 'NoChange'; Changed = $false; Error = $null; Gate = $gate } }
    $State.Counters[$MutationCounter]++
    if ($Fixture.MutationFails) { return [pscustomobject]@{ Success = $false; Status = 'Error'; Changed = $false; Error = 'Falha fictícia do mutador.'; Gate = $gate } }
    $State.Counters.Audit++
    if ($Fixture.AuditFails) { return [pscustomobject]@{ Success = $false; Status = 'Partial'; Changed = $true; Error = 'Auditoria fictícia falhou após mutação; rollback não executado.'; Gate = $gate } }
    return [pscustomobject]@{ Success = $true; Status = 'Completed'; Changed = $true; Error = $null; Gate = $gate }
}

function Add-AdminHarnessResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][ValidateSet('PASS','FAIL','BLOCKED','NOT RUN')][string]$Status, [Parameter(Mandatory)][string]$Name, [string]$Detail = '')
    $entry = [pscustomobject]@{ Status = $Status; Name = $Name; Detail = $Detail }
    [void]$State.Results.Add($entry)
    return $entry
}

function Assert-AdminHarness {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State, [Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Name)
    $status = if ($Condition) { 'PASS' } else { 'FAIL' }
    Add-AdminHarnessResult -State $State -Status $status -Name $Name | Out-Null
    if (-not $Condition) { throw "ASSERTION-FAIL:$Name" }
}

function Resolve-AdminStaticAstValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Management.Automation.Language.Ast]$Expression,
        [Parameter(Mandatory)][System.Management.Automation.Language.ScriptBlockAst]$RootAst,
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string[]]$VariableStack = @()
    )
    if ($Expression -is [System.Management.Automation.Language.PipelineAst]) {
        if ($Expression.PipelineElements.Count -ne 1) { throw 'FAIL-CLOSED: expressão de caminho não é estática.' }
        $pipelineElement = $Expression.PipelineElements[0]
        if ($pipelineElement -is [System.Management.Automation.Language.CommandExpressionAst]) { $pipelineElement = $pipelineElement.Expression }
        return Resolve-AdminStaticAstValue -Expression $pipelineElement -RootAst $RootAst -SourcePath $SourcePath -ProjectRoot $ProjectRoot -VariableStack $VariableStack
    }
    if ($Expression -is [System.Management.Automation.Language.CommandExpressionAst]) {
        return Resolve-AdminStaticAstValue -Expression $Expression.Expression -RootAst $RootAst -SourcePath $SourcePath -ProjectRoot $ProjectRoot -VariableStack $VariableStack
    }
    if ($Expression -is [System.Management.Automation.Language.StringConstantExpressionAst]) { return $Expression.Value }
    if ($Expression -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        if ($Expression.NestedExpressions.Count -ne 0) { throw 'FAIL-CLOSED: string expansível dinâmica em caminho de dependência.' }
        return $Expression.Value
    }
    if ($Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
        $variableName = $Expression.VariablePath.UserPath
        if ($variableName -ieq 'PSScriptRoot') { return [IO.Path]::GetDirectoryName($SourcePath) }
        if ($VariableStack -contains $variableName) { throw "FAIL-CLOSED: ciclo de variáveis no caminho: $variableName" }
        $assignments = @($RootAst.FindAll({ param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -ieq $variableName
        },$true))
        if ($assignments.Count -ne 1) { throw "FAIL-CLOSED: variável de caminho ausente ou ambígua: $variableName em $SourcePath" }
        return Resolve-AdminStaticAstValue -Expression $assignments[0].Right -RootAst $RootAst -SourcePath $SourcePath -ProjectRoot $ProjectRoot -VariableStack @($VariableStack + $variableName)
    }
    if ($Expression -is [System.Management.Automation.Language.CommandAst]) {
        if ($Expression.GetCommandName() -ne 'Join-Path' -or $Expression.CommandElements.Count -ne 3) { throw 'FAIL-CLOSED: somente Join-Path estático é aceito para dependências.' }
        $basePath = Resolve-AdminStaticAstValue -Expression $Expression.CommandElements[1] -RootAst $RootAst -SourcePath $SourcePath -ProjectRoot $ProjectRoot -VariableStack $VariableStack
        $childPath = Resolve-AdminStaticAstValue -Expression $Expression.CommandElements[2] -RootAst $RootAst -SourcePath $SourcePath -ProjectRoot $ProjectRoot -VariableStack $VariableStack
        if (-not [IO.Path]::IsPathRooted([string]$basePath)) { throw 'FAIL-CLOSED: Join-Path não parte de uma raiz comprovada.' }
        return [IO.Path]::GetFullPath((Join-Path ([string]$basePath) ([string]$childPath)))
    }
    throw "FAIL-CLOSED: forma AST não permitida para caminho: $($Expression.GetType().Name)"
}

function Get-AdminStaticImportTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Management.Automation.Language.CommandAst]$Command)
    for ($index = 1; $index -lt $Command.CommandElements.Count; $index++) {
        $element = $Command.CommandElements[$index]
        if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
            if ($element.ParameterName -ieq 'Name' -and ($index + 1) -lt $Command.CommandElements.Count) { return $Command.CommandElements[$index + 1] }
            continue
        }
        return $element
    }
    throw 'FAIL-CLOSED: Import-Module sem alvo estático.'
}

function Assert-AdminProductionStaticClosure {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Paths, [Parameter(Mandatory)][string]$ProjectRoot)
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $initializerAllowlist = @('Set-StrictMode','Join-Path','Test-Path','Import-Module','Export-ModuleMember')
    $moduleFiles = [System.Collections.Generic.List[string]]::new()
    $scriptFiles = [System.Collections.Generic.List[string]]::new()
    $externalImports = [System.Collections.Generic.List[object]]::new()
    $externalCommands = [System.Collections.Generic.List[object]]::new()
    $edges = [System.Collections.Generic.List[object]]::new()
    $visited = @{}
    $visiting = @{}
    $visit = $null
    $visit = {
        param([string]$Candidate,[string]$Kind,[string]$ParentPath,[int]$Line)
        $full = Resolve-AdminAllowedPath -Path $Candidate -AllowedRoot $root -RequireExisting
        $key = $full.ToLowerInvariant()
        if ($visiting.ContainsKey($key)) { throw "FAIL-CLOSED: ciclo de dependência detectado: $full" }
        if ($visited.ContainsKey($key)) { return }
        $visiting[$key] = $true
        if ($Kind -eq 'Module') { $moduleFiles.Add($full) | Out-Null } else { $scriptFiles.Add($full) | Out-Null }
        $tokens = $null; $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw "FAIL-CLOSED: erro AST em ${full}: $($parseErrors[0].Message)" }
        $commands = $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] },$true)
        foreach ($command in $commands) {
            $insideFunction = $false; $parent = $command.Parent
            while ($null -ne $parent) { if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $insideFunction = $true; break }; $parent = $parent.Parent }
            $name = $command.GetCommandName()
            if ($command.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot) {
                if ($command.CommandElements.Count -ne 1 -or $command.CommandElements[0] -isnot [System.Management.Automation.Language.VariableExpressionAst]) { throw "FAIL-CLOSED: dot-source dinâmico não comprovado em ${full}:$($command.Extent.StartLineNumber)" }
                $targetExpression = $command.CommandElements[0]
                $target = Resolve-AdminStaticAstValue -Expression $targetExpression -RootAst $ast -SourcePath $full -ProjectRoot $root
                $resolvedTarget = if ([IO.Path]::IsPathRooted([string]$target)) { [string]$target } else { Join-Path (Split-Path -Parent $full) ([string]$target) }
                $resolvedTarget = Resolve-AdminAllowedPath -Path $resolvedTarget -AllowedRoot $root -RequireExisting
                if ([IO.Path]::GetExtension($resolvedTarget) -ne '.ps1') { throw "FAIL-CLOSED: dot-source não é script .ps1 auditável: $resolvedTarget" }
                $edges.Add([pscustomobject]@{ From=$full; To=$resolvedTarget; Kind='DotSource'; Line=$command.Extent.StartLineNumber }) | Out-Null
                & $visit $resolvedTarget 'Script' $full $command.Extent.StartLineNumber
                continue
            }
            if ([string]::IsNullOrWhiteSpace($name)) { throw "FAIL-CLOSED: chamada dinâmica não auditável em ${full}:$($command.Extent.StartLineNumber)" }
            if (-not $insideFunction -and $initializerAllowlist -notcontains $name) { throw "FAIL-CLOSED: comando de inicialização não auditado em ${full}:$($command.Extent.StartLineNumber): $name" }
            if ($name -match '^(ipmo|gmo)$' -or $name -match '^[^\\]+\\(Import-Module|Get-Module|Get-ADUser|Get-ADDomain|Get-ADGroup|Get-ADGroupMember|Unlock-ADAccount|Enable-ADAccount|Disable-ADAccount|Set-ADUser|Add-ADGroupMember|Remove-ADGroupMember)$') {
                throw "FAIL-CLOSED: alias ou comando qualificado contorna a interceptação em ${full}:$($command.Extent.StartLineNumber): $name"
            }
            if ($name -match '^(Microsoft\.ActiveDirectory\.Management|ActiveDirectory)\\') { throw "FAIL-CLOSED: chamada AD qualificada não interceptável em ${full}:$($command.Extent.StartLineNumber): $name" }
            if ($name -in @('Get-ADUser','Get-ADDomain','Get-ADGroup','Get-ADGroupMember','Unlock-ADAccount','Enable-ADAccount','Disable-ADAccount','Set-ADUser','Add-ADGroupMember','Remove-ADGroupMember','Get-Module','Import-Module')) {
                $externalCommands.Add([pscustomobject]@{ Path=$full; Name=$name; Line=$command.Extent.StartLineNumber; InFunction=$insideFunction }) | Out-Null
            }
            if ($name -eq 'Import-Module') {
                $targetAst = Get-AdminStaticImportTarget -Command $command
                if ($targetAst -is [System.Management.Automation.Language.StringConstantExpressionAst] -and $targetAst.Value -match '^(ActiveDirectory|Microsoft\.ActiveDirectory\.Management)$') {
                    if (-not $insideFunction) { throw "FAIL-CLOSED: import AD no inicializador de ${full}:$($command.Extent.StartLineNumber)" }
                    $externalImports.Add([pscustomobject]@{ Path=$full; Name=$targetAst.Value; Line=$command.Extent.StartLineNumber }) | Out-Null
                    continue
                }
                $target = Resolve-AdminStaticAstValue -Expression $targetAst -RootAst $ast -SourcePath $full -ProjectRoot $root
                $resolvedTarget = if ([IO.Path]::IsPathRooted([string]$target)) { [string]$target } else { Join-Path (Split-Path -Parent $full) ([string]$target) }
                $resolvedTarget = Resolve-AdminAllowedPath -Path $resolvedTarget -AllowedRoot $root -RequireExisting
                if ([IO.Path]::GetExtension($resolvedTarget) -ne '.psm1') { throw "FAIL-CLOSED: import local não é .psm1 auditável: $resolvedTarget" }
                $edges.Add([pscustomobject]@{ From=$full; To=$resolvedTarget; Kind='ImportModule'; Line=$command.Extent.StartLineNumber }) | Out-Null
                & $visit $resolvedTarget 'Module' $full $command.Extent.StartLineNumber
            }
        }
        $visiting.Remove($key)
        $visited[$key] = $true
    }
    foreach ($path in $Paths) { & $visit $path 'Module' '' 0 }
    [pscustomobject]@{
        Modules=@($moduleFiles | Select-Object -Unique); Scripts=@($scriptFiles | Select-Object -Unique)
        Edges=@($edges); ExternalImports=@($externalImports); ExternalCommands=@($externalCommands)
        AllFiles=@(@($moduleFiles)+@($scriptFiles) | Select-Object -Unique)
    }
}

function New-AdminProductionGateState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][ValidateSet('User','Group')][string]$Domain,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)]$Fixture,
        [Parameter(Mandatory)]$Scenario
    )
    $root = [IO.Path]::GetFullPath($ProjectRoot)
    $paths = if ($Domain -eq 'User') {
        @{
            Actions = Join-Path $root 'Core/User/Actions/User-Account-Actions.psm1'
            Core = Join-Path $root 'Core/User/User-Functions.psm1'
            Audit = Join-Path $root 'Core/Audit/Audit-Functions.psm1'
        }
    } else {
        @{
            Management = Join-Path $root 'Core/Group/Management/Group-Management.psm1'
            Core = Join-Path $root 'Core/Group/Group-Functions.psm1'
            Audit = Join-Path $root 'Core/Audit/Audit-Functions.psm1'
        }
    }
    $rootRole = if ($Domain -eq 'User') { 'Actions' } else { 'Management' }
    $static = Assert-AdminProductionStaticClosure -Paths @($paths[$rootRole]) -ProjectRoot $root
    $staticModules = @($static.Modules)
    foreach ($role in @('Core','Audit')) { if ($staticModules -notcontains $paths[$role]) { throw "FAIL-CLOSED: dependência $role não consta do fechamento AST." } }
    $allowed = @{}
    foreach ($entry in $paths.GetEnumerator()) {
        $canonical = Resolve-AdminAllowedPath -Path $entry.Value -AllowedRoot $root -RequireExisting
        if (-not ($static.Modules -contains $canonical)) { throw "FAIL-CLOSED: módulo allowlisted não pertence ao grafo AST: $canonical" }
        $allowed[$canonical] = $entry.Key
    }
    $closureHashes = @{}
    foreach ($closurePath in $static.AllFiles) { $closureHashes[$closurePath] = (Get-FileHash -LiteralPath $closurePath -Algorithm SHA256 -ErrorAction Stop).Hash }
    [pscustomobject]@{
        Mode='ProductionWithInMemoryStubs'; ProjectRoot=$root; Domain=$Domain; Operation=$Operation
        Fixture=$Fixture; Scenario=$Scenario; Paths=$paths; StaticEvidence=$static; ClosureHashes=$closureHashes
        AllowedPaths=$allowed; ImportCounts=@{}; ImportLog=[System.Collections.ArrayList]::new()
        ModuleInstances=[System.Collections.ArrayList]::new(); StubEvidence=[System.Collections.ArrayList]::new()
        CapturedReferences=[System.Collections.ArrayList]::new(); Counters=[ordered]@{
            GetModule=0; ADImportBlocked=0; GetADUser=0; GetADDomain=0; GetADGroup=0; GetADGroupMember=0
            Unlock=0; Enable=0; Disable=0; SetUser=0; AddGroupMember=0; RemoveGroupMember=0
            Audit=0; TestAudit=0; Unexpected=0
        }
        GatePassed=$false; PreviousGlobalImport=$null; PreviousGlobalState=$null; ImportDispatcher=$null; NativeImporter=$null; LastMutation=$null
        InterfaceModule=$null; InterfaceHash=$null; InterfaceImportRole=$null; InterfaceImportCount=0; InterfaceInputQueue=[System.Collections.ArrayList]::new(); InterfaceInputIndex=0; InterfaceOutputCount=0; InterfaceUsesScopedGuard=$false
    }
}

function New-AdminProductionStubBody {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$Role,[Parameter(Mandatory)][string]$CommandName)
    switch ($CommandName) {
        'Get-Module' { return { param([string]$Name,[switch]$ListAvailable,[switch]$ListImported)
            if ($Name -ne 'ActiveDirectory') { $global:M43ProductionGate.Counters.Unexpected = [int]$global:M43ProductionGate.Counters.Unexpected + 1; throw 'M43_FAIL_CLOSED:Get-Module name not allowed.' }
            $global:M43ProductionGate.Counters.GetModule = [int]$global:M43ProductionGate.Counters.GetModule + 1
            if ($global:M43ProductionGate.Fixture.ADModuleAvailable -eq $false) { return $null }
            return [pscustomobject]@{ Name='ActiveDirectory'; ModuleBase='SYNTHETIC_ONLY'; Version='0.0.0.0' }
            # M43_STUB_SENTINEL:Get-Module
        } }
        'Import-Module' { return { param([string]$Name,[switch]$Force,[string]$ErrorAction)
            if ($Name -ne 'ActiveDirectory') { $global:M43ProductionGate.Counters.Unexpected = [int]$global:M43ProductionGate.Counters.Unexpected + 1; throw 'M43_FAIL_CLOSED:unexpected module import from production function.' }
            $global:M43ProductionGate.Counters.ADImportBlocked = [int]$global:M43ProductionGate.Counters.ADImportBlocked + 1
            return
            # M43_STUB_SENTINEL:Import-Module
        } }
        'Get-ADUser' { return { param([string]$Identity,[string]$Server,[string[]]$Properties,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.GetADUser = [int]$global:M43ProductionGate.Counters.GetADUser + 1
            if ($global:M43ProductionGate.Fixture.User.QueryStatus -eq 'Error') { throw $global:M43ProductionGate.Fixture.User.Error }
            if ($global:M43ProductionGate.Fixture.User.QueryStatus -eq 'NotFound') { return $null }
            return [pscustomobject]@{ SamAccountName=$Identity; UserPrincipalName=($Identity + '@fixture.invalid'); Name='Synthetic User'; Enabled=$global:M43ProductionGate.Fixture.User.Enabled; LockedOut=$global:M43ProductionGate.Fixture.User.LockedOut; PasswordChangeAtLogon=$global:M43ProductionGate.Fixture.User.PasswordChangeAtLogon; MemberOf=@() }
            # M43_STUB_SENTINEL:Get-ADUser
        } }
        'Get-ADDomain' { return { param([string]$Server,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.GetADDomain = [int]$global:M43ProductionGate.Counters.GetADDomain + 1
            if ($global:M43ProductionGate.Fixture.DomainQueryStatus -eq 'Error') { throw 'Synthetic domain query error.' }
            if ($global:M43ProductionGate.Fixture.DomainQueryStatus -eq 'NotFound') { return }
            return [pscustomobject]@{ DNSRoot='fixture.invalid'; PDCEmulator='dc.fixture.invalid' }
            # M43_STUB_SENTINEL:Get-ADDomain
        } }
        'Get-ADGroup' { return { param([string]$Identity,[string]$Server,[string[]]$Properties,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.GetADGroup = [int]$global:M43ProductionGate.Counters.GetADGroup + 1
            if ($global:M43ProductionGate.Fixture.Group.QueryStatus -eq 'Error') { throw $global:M43ProductionGate.Fixture.Group.Error }
            if ($global:M43ProductionGate.Fixture.Group.QueryStatus -eq 'NotFound') { return $null }
            return [pscustomobject]@{ Name=$Identity; SamAccountName=$Identity; Description='Synthetic group'; GroupCategory='Security'; GroupScope='Global'; DistinguishedName=('CN=' + $Identity) }
            # M43_STUB_SENTINEL:Get-ADGroup
        } }
        'Get-ADGroupMember' { return { param($Identity,[string]$Server,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.GetADGroupMember = [int]$global:M43ProductionGate.Counters.GetADGroupMember + 1
            if ($global:M43ProductionGate.Fixture.Group.QueryStatus -eq 'Error') { throw $global:M43ProductionGate.Fixture.Group.Error }
            if ($global:M43ProductionGate.Fixture.Group.QueryStatus -eq 'NotFound') { return @() }
            return @($global:M43ProductionGate.Fixture.Group.Members | ForEach-Object { [pscustomobject]@{ SamAccountName=[string]$_; Name=[string]$_; objectClass='user' } })
            # M43_STUB_SENTINEL:Get-ADGroupMember
        } }
        'Unlock-ADAccount' { return { param([string]$Identity,[string]$Server,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.Unlock = [int]$global:M43ProductionGate.Counters.Unlock + 1
            $global:M43ProductionGate.LastMutation=[pscustomobject]@{ Command='Unlock-ADAccount'; Identity=$Identity; Server=$Server }
            if ($global:M43ProductionGate.Fixture.OperationResult.MutationFails) { throw 'Synthetic Unlock mutation failure.' }
            # M43_STUB_SENTINEL:Unlock-ADAccount
        } }
        'Enable-ADAccount' { return { param([string]$Identity,[string]$Server,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.Enable = [int]$global:M43ProductionGate.Counters.Enable + 1
            $global:M43ProductionGate.LastMutation=[pscustomobject]@{ Command='Enable-ADAccount'; Identity=$Identity; Server=$Server }
            if ($global:M43ProductionGate.Fixture.OperationResult.MutationFails) { throw 'Synthetic Enable mutation failure.' }
            # M43_STUB_SENTINEL:Enable-ADAccount
        } }
        'Disable-ADAccount' { return { param([string]$Identity,[string]$Server,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.Disable = [int]$global:M43ProductionGate.Counters.Disable + 1
            $global:M43ProductionGate.LastMutation=[pscustomobject]@{ Command='Disable-ADAccount'; Identity=$Identity; Server=$Server }
            if ($global:M43ProductionGate.Fixture.OperationResult.MutationFails) { throw 'Synthetic Disable mutation failure.' }
            # M43_STUB_SENTINEL:Disable-ADAccount
        } }
        'Set-ADUser' { return { param([string]$Identity,[string]$Server,[bool]$ChangePasswordAtLogon,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.SetUser = [int]$global:M43ProductionGate.Counters.SetUser + 1
            $global:M43ProductionGate.LastMutation=[pscustomobject]@{ Command='Set-ADUser'; Identity=$Identity; Server=$Server; ChangePasswordAtLogon=$ChangePasswordAtLogon }
            if ($global:M43ProductionGate.Fixture.OperationResult.MutationFails) { throw 'Synthetic Set-ADUser mutation failure.' }
            # M43_STUB_SENTINEL:Set-ADUser
        } }
        'Add-ADGroupMember' { return { param([string]$Identity,[string]$Members,[string]$Server,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.AddGroupMember = [int]$global:M43ProductionGate.Counters.AddGroupMember + 1
            $global:M43ProductionGate.LastMutation=[pscustomobject]@{ Command='Add-ADGroupMember'; Identity=$Identity; Members=$Members; Server=$Server }
            if ($global:M43ProductionGate.Fixture.OperationResult.MutationFails) { throw 'Synthetic Add group member failure.' }
            # M43_STUB_SENTINEL:Add-ADGroupMember
        } }
        'Remove-ADGroupMember' { return { param([string]$Identity,[string]$Members,[string]$Server,[switch]$Confirm,[string]$ErrorAction)
            $global:M43ProductionGate.Counters.RemoveGroupMember = [int]$global:M43ProductionGate.Counters.RemoveGroupMember + 1
            $global:M43ProductionGate.LastMutation=[pscustomobject]@{ Command='Remove-ADGroupMember'; Identity=$Identity; Members=$Members; Server=$Server }
            if ($global:M43ProductionGate.Fixture.OperationResult.MutationFails) { throw 'Synthetic Remove group member failure.' }
            # M43_STUB_SENTINEL:Remove-ADGroupMember
        } }
        'New-AuditRecord' { return { param([string]$Action,[string]$SamAccountName,[string]$Result,[bool]$SimulationMode,[bool]$Changed,[string]$Operator)
            $global:M43ProductionGate.Counters.Audit = [int]$global:M43ProductionGate.Counters.Audit + 1
            if ($global:M43ProductionGate.Fixture.OperationResult.AuditFails) { return [pscustomobject]@{ Success=$false; Data=$null; Error='Synthetic audit failure.' } }
            return [pscustomobject]@{ Success=$true; Data=[pscustomobject]@{ Timestamp=[DateTime]::UtcNow; Operator='synthetic.operator'; Action=$Action; SamAccountName=$SamAccountName; Result=$Result; SimulationMode=$SimulationMode; Changed=$Changed }; Error=$null }
            # M43_STUB_SENTINEL:New-AuditRecord
        } }
        'Test-AuditRecord' { return { param([pscustomobject]$Record)
            $global:M43ProductionGate.Counters.TestAudit = [int]$global:M43ProductionGate.Counters.TestAudit + 1
            if ($global:M43ProductionGate.Fixture.OperationResult.AuditFails) { return [pscustomobject]@{ Success=$false; Data=$false; Error='Synthetic audit validation failure.' } }
            return [pscustomobject]@{ Success=$true; Data=($null -ne $Record); Error=$null }
            # M43_STUB_SENTINEL:Test-AuditRecord
        } }
        'Invoke-UserActionShouldProcess' { return { param($Cmdlet,$Target,$Action)
            return [bool]$global:M43ProductionGate.Scenario.ShouldProcess
            # M43_STUB_SENTINEL:Invoke-UserActionShouldProcess
        } }
        'Invoke-GroupManagementShouldProcess' { return { param($Cmdlet,$Target,$Action)
            return [bool]$global:M43ProductionGate.Scenario.ShouldProcess
            # M43_STUB_SENTINEL:Invoke-GroupManagementShouldProcess
        } }
        default { throw "FAIL-CLOSED: stub não definido para $Role/$CommandName." }
    }
}

function Install-AdminProductionRoleStubs {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module,[Parameter(Mandatory)][string]$Role)
    $names = switch ($Role) {
        'Core' { if($State.Domain -eq 'User'){@('Get-Module','Import-Module','Get-ADUser')}else{@('Get-Module','Import-Module','Get-ADDomain','Get-ADGroup','Get-ADGroupMember')} }
        'Actions' { @('Get-Module','Import-Module','Unlock-ADAccount','Enable-ADAccount','Disable-ADAccount','Set-ADUser','New-AuditRecord','Invoke-UserActionShouldProcess') }
        'Management' { @('Get-Module','Import-Module','Get-ADUser','Add-ADGroupMember','Remove-ADGroupMember','New-AuditRecord','Test-AuditRecord','Invoke-GroupManagementShouldProcess') }
        default { @() }
    }
    $required = @{
        'Get-Module'=@('Name','ListAvailable')
        'Import-Module'=@('Name','Force','ErrorAction')
        'Get-ADUser'=@('Identity','Server','ErrorAction')
        'Get-ADDomain'=@('Server','ErrorAction')
        'Get-ADGroup'=@('Identity','Server','ErrorAction')
        'Get-ADGroupMember'=@('Identity','Server','ErrorAction')
        'Unlock-ADAccount'=@('Identity','Server','ErrorAction')
        'Enable-ADAccount'=@('Identity','Server','ErrorAction')
        'Disable-ADAccount'=@('Identity','Server','ErrorAction')
        'Set-ADUser'=@('Identity','Server','ChangePasswordAtLogon','ErrorAction')
        'Add-ADGroupMember'=@('Identity','Members','Server','ErrorAction')
        'Remove-ADGroupMember'=@('Identity','Members','Server','Confirm','ErrorAction')
        'New-AuditRecord'=@('Action','SamAccountName','Result','SimulationMode','Changed','Operator')
        'Test-AuditRecord'=@('Record')
        'Invoke-UserActionShouldProcess'=@('Cmdlet','Target','Action')
        'Invoke-GroupManagementShouldProcess'=@('Cmdlet','Target','Action')
    }
    foreach ($name in $names) {
        $sentinel = 'M43_STUB_SENTINEL:' + $name
        $body = New-AdminProductionStubBody -State $State -Role $Role -CommandName $name
        $requiredParameters = if ($required.ContainsKey($name)) { $required[$name] } else { @() }
        $resolution = Install-AdminModuleStub -Module $Module -CommandName $name -Stub $body -Sentinel $sentinel -RequiredParameters $requiredParameters -ExpectedModulePath $Module.Path -ProjectRoot $State.ProjectRoot
        $State.StubEvidence.Add([pscustomobject]@{ Role=$Role; Name=$name; ModulePath=$Module.Path; Module=$Module; Sentinel=$sentinel; CommandType=$resolution.CommandType; Parameters=$resolution.Parameters }) | Out-Null
    }
}

function Import-AdminProductionModuleChain {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    if ($State.GatePassed -or $State.ModuleInstances.Count -gt 0) { throw 'FAIL-CLOSED: processo de importação do gate já foi iniciado; use processo novo.' }
    if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) { throw 'FAIL-CLOSED: ActiveDirectory já estava carregado antes do gate.' }
    $State.PreviousGlobalState = Get-Variable -Name PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue
    Set-Variable -Name PSModuleAutoLoadingPreference -Scope Global -Value 'None' -Force
    $global:M43ProductionGate = $State
    $rootRole = if ($State.Domain -eq 'User') { 'Actions' } else { 'Management' }
    $rootPath = Resolve-AdminAllowedPath -Path $State.Paths[$rootRole] -AllowedRoot $State.ProjectRoot -RequireExisting
    if (-not $State.AllowedPaths.ContainsKey($rootPath) -or $State.AllowedPaths[$rootPath] -ne $rootRole) { throw 'FAIL-CLOSED: módulo raiz não consta da allowlist auditada.' }
    # Local nested imports execute naturally inside the real module SessionState. Their AST targets were resolved and allowlisted before this call.
    $rootModule = Microsoft.PowerShell.Core\Import-Module -Name $rootPath -Force -PassThru -ErrorAction Stop
    if ($null -eq $rootModule -or [IO.Path]::GetFullPath($rootModule.Path) -ne $rootPath) { throw 'FAIL-CLOSED: identidade do módulo raiz não corresponde à allowlist.' }
    $nestedModules = & $rootModule { Microsoft.PowerShell.Core\Get-Module -All }
    foreach ($role in @('Core','Audit')) {
        $expectedPath = Resolve-AdminAllowedPath -Path $State.Paths[$role] -AllowedRoot $State.ProjectRoot -RequireExisting
        $matches = @($nestedModules | Where-Object { $_.Path -and [IO.Path]::GetFullPath($_.Path) -eq $expectedPath })
        if ($matches.Count -ne 1) { throw "FAIL-CLOSED: esperado exatamente um $role no SessionState consumidor; encontrados $($matches.Count)." }
        $State.ModuleInstances.Add([pscustomobject]@{ Role=$role; Path=$expectedPath; Module=$matches[0]; Guid=$matches[0].Guid; Version=$matches[0].Version }) | Out-Null
    }
    $State.ModuleInstances.Add([pscustomobject]@{ Role=$rootRole; Path=$rootPath; Module=$rootModule; Guid=$rootModule.Guid; Version=$rootModule.Version }) | Out-Null
    $core = @($State.ModuleInstances | Where-Object Role -eq 'Core')[0].Module
    Install-AdminProductionRoleStubs -State $State -Module $core -Role Core
    Install-AdminProductionRoleStubs -State $State -Module $rootModule -Role $rootRole
    if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) { throw 'FAIL-CLOSED: ActiveDirectory apareceu durante importação local.' }
    $allowedStubNames = @($State.StubEvidence | ForEach-Object { $_.ModulePath + '|' + $_.Name })
    foreach ($external in $State.StaticEvidence.ExternalCommands) {
        $externalPath = [IO.Path]::GetFullPath($external.Path)
        $roleForPath = $null
        foreach ($entry in $State.Paths.GetEnumerator()) { if ([IO.Path]::GetFullPath($entry.Value) -eq $externalPath) { $roleForPath = $entry.Key; break } }
        if ($roleForPath -in @('Core',$rootRole) -and ($allowedStubNames -notcontains ($externalPath + '|' + $external.Name))) {
            throw "FAIL-CLOSED: fronteira AST sem stub no módulo dono: $($external.Name) ($externalPath`:$($external.Line))"
        }
    }
    return Assert-AdminProductionGate -State $State
}

function Invoke-AdminGuardedProductionImport {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][object]$Name,[switch]$Force,[switch]$PassThru)
    if ($Name -isnot [string]) { $State.Counters.Unexpected++; throw 'FAIL-CLOSED: somente import por caminho explícito é permitido.' }
    if ($Name -eq 'ActiveDirectory' -or $Name -match 'ActiveDirectory') { $State.Counters.Unexpected++; throw 'FAIL-CLOSED: import ActiveDirectory bloqueado.' }
    $full = Resolve-AdminAllowedPath -Path $Name -AllowedRoot $State.ProjectRoot -RequireExisting
    if (-not $State.AllowedPaths.ContainsKey($full)) { $State.Counters.Unexpected++; throw "FAIL-CLOSED: import local fora da allowlist: $full" }
    if ($State.ImportCounts.ContainsKey($full)) { $State.Counters.Unexpected++; throw "FAIL-CLOSED: reimport não aprovado nesta operação isolada: $full" }
    $role = $State.AllowedPaths[$full]
    $State.ImportCounts[$full] = 1
    $State.ImportLog.Add([pscustomobject]@{ Path=$full; Role=$role; Force=[bool]$Force; Depth=$State.ImportLog.Count+1 }) | Out-Null
    $loaded = Microsoft.PowerShell.Core\Import-Module -Name $full -Force:$Force -PassThru -ErrorAction Stop
    $instances = @(Microsoft.PowerShell.Core\Get-Module -All | Where-Object { $_.Path -and [IO.Path]::GetFullPath($_.Path) -eq $full })
    if ($instances.Count -ne 1) { throw "FAIL-CLOSED: esperada uma instância de $role em $full; encontradas $($instances.Count)." }
    $module = $instances[0]
    if (-not [object]::ReferenceEquals($loaded,$module)) { throw "FAIL-CLOSED: identidade do Import-Module divergente para $role." }
    if ($role -in @('Core','Actions','Management')) { Install-AdminProductionRoleStubs -State $State -Module $module -Role $role }
    $State.ModuleInstances.Add([pscustomobject]@{ Role=$role; Path=$full; Module=$module; Guid=$module.Guid; Version=$module.Version }) | Out-Null
    $stillLoaded = Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory
    if ($stillLoaded) { throw 'FAIL-CLOSED: ActiveDirectory apareceu carregado durante import controlado.' }
    if ($PassThru) { return $module }
}

function Install-AdminProductionImportGuard {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    $native = Get-Command Microsoft.PowerShell.Core\Import-Module -CommandType Cmdlet -ErrorAction Stop
    if ($native.Name -ne 'Import-Module' -or $native.ModuleName -ne 'Microsoft.PowerShell.Core') { throw 'FAIL-CLOSED: comando nativo Import-Module não identificado.' }
    $State.PreviousGlobalImport = Get-Command Import-Module -CommandType Function -ErrorAction SilentlyContinue
    $State.PreviousGlobalState = Get-Variable -Name PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue
    Set-Variable -Name PSModuleAutoLoadingPreference -Scope Global -Value 'None' -Force
    $State.ImportDispatcher = { param($Name,$Force,$PassThru) Invoke-AdminGuardedProductionImport -State $global:M43ProductionGate -Name $Name -Force:$Force -PassThru:$PassThru }
    $global:M43ProductionGate = $State
    $wrapper = {
        [CmdletBinding()]
        param([Parameter(Position=0)]$Name,[switch]$Force,[switch]$PassThru)
        if ($null -eq $global:M43ProductionGate -or $null -eq $global:M43ProductionGate.ImportDispatcher) { throw 'M43_IMPORT_GATE_FAIL_CLOSED: dispatcher ausente.' }
        & $global:M43ProductionGate.ImportDispatcher $Name $Force $PassThru
        # M43_IMPORT_GATE_SENTINEL
    }
    Set-Item Function:\global:Import-Module -Value $wrapper -Force
    $resolved = Get-Command Import-Module -CommandType Function -ErrorAction Stop
    if ($resolved.Definition -notlike '*M43_IMPORT_GATE_SENTINEL*') { throw 'FAIL-CLOSED: wrapper global Import-Module não resolveu.' }
    $State.NativeImporter = $native
    return $resolved
}

function Install-AdminInterfaceImportGuard {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module)
    $resolved = & $Module { Get-Command Import-Module -CommandType Function -ErrorAction Stop }
    if ($resolved.Definition -notlike '*M43_IMPORT_GATE_SENTINEL*') { throw 'FAIL-CLOSED: Interface não resolve para o wrapper global Import-Module.' }
    $State.StubEvidence.Add([pscustomobject]@{ Role='Interface'; Name='Import-Module'; ModulePath=$Module.Path; Sentinel='M43_IMPORT_GATE_SENTINEL'; CommandType=$resolved.CommandType }) | Out-Null
    return $true
}

function Assert-AdminInterfaceInitializerSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ProjectRoot)
    $full = Resolve-AdminAllowedPath -Path $Path -AllowedRoot $ProjectRoot -RequireExisting
    if ([IO.Path]::GetExtension($full) -ne '.psm1') { throw 'FAIL-CLOSED: Interface deve ser um módulo local .psm1.' }
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($full,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) { throw "FAIL-CLOSED: AST inválida no módulo Interface: $($errors[0].Message)" }
    if($null -ne $ast.ParamBlock -or $null -ne $ast.DynamicParamBlock){throw 'FAIL-CLOSED: module parameter/dynamic parameter blocks are not approved for Interface initialization.'}
    $topLevelStatements=@()
    foreach($block in @($ast.BeginBlock,$ast.ProcessBlock,$ast.EndBlock)){if($null -ne $block){$topLevelStatements+=@($block.Statements)}}
    foreach ($statement in $topLevelStatements) {
        if ($statement -is [System.Management.Automation.Language.FunctionDefinitionAst]) { continue }
        if ($statement -is [System.Management.Automation.Language.PipelineAst] -and $statement.PipelineElements.Count -eq 1 -and
            $statement.PipelineElements[0] -is [System.Management.Automation.Language.CommandAst] -and
            $statement.PipelineElements[0].GetCommandName() -eq 'Export-ModuleMember') { continue }
        throw "FAIL-CLOSED: inicializador da Interface contém operação não aprovada: $($statement.GetType().Name) em ${full}:$($statement.Extent.StartLineNumber)"
    }
    return [pscustomobject]@{ Path=$full; Hash=(Get-FileHash -LiteralPath $full -Algorithm SHA256 -ErrorAction Stop).Hash; InitializerStatements=$topLevelStatements.Count }
}

function Import-AdminInterfaceModuleSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][string]$Path)
    if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) { throw 'FAIL-CLOSED: ActiveDirectory já estava carregado antes da Interface.' }
    $proof = Assert-AdminInterfaceInitializerSafe -Path $Path -ProjectRoot $State.ProjectRoot
    $State.PreviousGlobalState = Get-Variable -Name PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue
    Set-Variable -Name PSModuleAutoLoadingPreference -Scope Global -Value 'None' -Force
    if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) { throw 'FAIL-CLOSED: ActiveDirectory já estava carregado antes da Interface.' }
    $loaded = Microsoft.PowerShell.Core\Import-Module -Name $proof.Path -Force -PassThru -ErrorAction Stop
    if ($null -eq $loaded -or [IO.Path]::GetFullPath($loaded.Path) -ne $proof.Path) { throw 'FAIL-CLOSED: identidade da Interface importada divergiu do caminho auditado.' }
    $instances = @(Microsoft.PowerShell.Core\Get-Module -All | Where-Object { $_.Path -and [IO.Path]::GetFullPath($_.Path) -eq $proof.Path })
    if ($instances.Count -ne 1 -or -not [object]::ReferenceEquals($instances[0],$loaded)) { throw 'FAIL-CLOSED: instância da Interface ausente, duplicada ou substituída.' }
    if ((Get-FileHash -LiteralPath $proof.Path -Algorithm SHA256 -ErrorAction Stop).Hash -ne $proof.Hash) { throw 'FAIL-CLOSED: Interface mudou durante o import.' }
    if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) { throw 'FAIL-CLOSED: ActiveDirectory apareceu durante o import da Interface.' }
    $State.InterfaceModule = $loaded
    $State.InterfaceHash = $proof.Hash
    $global:M43ProductionGate = $State
    $State.ImportLog.Add([pscustomobject]@{ Path=$proof.Path; Role='Interface'; Force=$true; Depth=0; StaticInitializer=$true }) | Out-Null
    return $loaded
}

function Complete-AdminInterfaceImportTransaction {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Consumer,[Parameter(Mandatory)][string]$RequestedPath,[Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$LoadedModule,[switch]$Force)
    if (-not [object]::ReferenceEquals($Consumer,$State.InterfaceModule)) { $State.Counters.Unexpected++; throw 'FAIL-CLOSED: importador chamado fora do SessionState da Interface.' }
    if ($State.GatePassed -or $State.InterfaceImportCount -ne 0) { $State.Counters.Unexpected++; throw 'FAIL-CLOSED: somente um import transacional por processo é permitido; inicie processo novo.' }
    $role = if ($State.Domain -eq 'User') { 'Actions' } else { 'Management' }
    $expectedPath = Resolve-AdminAllowedPath -Path $State.Paths[$role] -AllowedRoot $State.ProjectRoot -RequireExisting
    $requested = Resolve-AdminAllowedPath -Path $RequestedPath -AllowedRoot $State.ProjectRoot -RequireExisting
    if ($requested -ne $expectedPath -or -not $Force -or $State.InterfaceImportRole -ne $role) { $State.Counters.Unexpected++; throw 'FAIL-CLOSED: alvo, role ou -Force do import Interface não corresponde à allowlist transacional.' }
    if ([IO.Path]::GetFullPath($LoadedModule.Path) -ne $expectedPath) { throw 'FAIL-CLOSED: Import-Module devolveu uma instância diferente da allowlist.' }
    $staticBefore = $State.StaticEvidence
    foreach ($path in $staticBefore.AllFiles) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "FAIL-CLOSED: dependência removida durante import: $path" }
        if ($State.ClosureHashes[$path] -ne (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash) { throw "FAIL-CLOSED: dependência mudou após auditoria AST: $path" }
    }
    $moduleChildren = @(& $LoadedModule { Microsoft.PowerShell.Core\Get-Module -All })
    $resolvedByPath = @{}
    foreach ($modulePath in $State.AllowedPaths.Keys) {
        $matches = @($moduleChildren | Where-Object { $_.Path -and [IO.Path]::GetFullPath($_.Path) -eq $modulePath })
        if ($matches.Count -ne 1) { throw "FAIL-CLOSED: SessionState do módulo raiz deve conter exatamente uma instância para $modulePath; encontradas $($matches.Count)." }
        $resolvedByPath[$modulePath] = $matches[0]
    }
    foreach ($auditCommand in @('New-AuditRecord','Test-AuditRecord')) {
        $auditResolved = & $resolvedByPath[$State.Paths.Audit] { param($Name) Get-Command -Name $Name -CommandType Function -ErrorAction Stop } $auditCommand
        if (-not $auditResolved.Module -or -not [object]::ReferenceEquals($auditResolved.Module,$resolvedByPath[$State.Paths.Audit])) { throw "FAIL-CLOSED: comando Audit não pertence à instância allowlisted: $auditCommand" }
    }
    $auditPath=[IO.Path]::GetFullPath($State.Paths.Audit)
    $auditExternal=@($State.StaticEvidence.ExternalCommands|Where-Object{[IO.Path]::GetFullPath($_.Path) -eq $auditPath})
    if($auditExternal.Count -gt 0){throw ('FAIL-CLOSED: Audit contém fronteira externa sem stub no SessionState correto: '+(($auditExternal|ForEach-Object Name|Select-Object -Unique)-join ', '))}
    $consumerImporter = & $Consumer { Get-Command Import-Module -CommandType Function -ErrorAction Stop }
    if ($consumerImporter.Definition -notlike '*M47_INTERFACE_IMPORT_SENTINEL*') { throw 'FAIL-CLOSED: importador transacional não está no SessionState da Interface auditada.' }
    $State.InterfaceImportCount++
    $State.ModuleInstances.Clear()
    foreach ($entry in @(
        [pscustomobject]@{Role='Interface';Path=$Consumer.Path;Module=$Consumer},
        [pscustomobject]@{Role=$role;Path=$expectedPath;Module=$LoadedModule},
        [pscustomobject]@{Role='Core';Path=$State.Paths.Core;Module=$resolvedByPath[$State.Paths.Core]},
        [pscustomobject]@{Role='Audit';Path=$State.Paths.Audit;Module=$resolvedByPath[$State.Paths.Audit]}
    )) {
        $State.ModuleInstances.Add([pscustomobject]@{Role=$entry.Role;Path=$entry.Path;Module=$entry.Module;Guid=$entry.Module.Guid;Version=$entry.Module.Version}) | Out-Null
    }
    Install-AdminProductionRoleStubs -State $State -Module $resolvedByPath[$State.Paths.Core] -Role Core
    Install-AdminProductionRoleStubs -State $State -Module $LoadedModule -Role $role
    $consumerFunctions = if ($State.Domain -eq 'User') { @('Get-UserUnlockPreview','Get-UserEnablePreview','Get-UserDisablePreview','Get-UserForcePasswordChangePreview','Invoke-UserUnlockAccount','Invoke-UserEnableAccount','Invoke-UserDisableAccount','Invoke-UserForcePasswordChange') } else { @('Get-GroupManagementPreview','Get-GroupManagementMembers','Invoke-GroupAddMember','Invoke-GroupRemoveMember') }
    foreach ($functionName in $consumerFunctions) {
        $resolved = & $Consumer { param($Name) Get-Command -Name $Name -CommandType Function -ErrorAction Stop } $functionName
        if (-not $resolved.Module -or -not [object]::ReferenceEquals($resolved.Module,$LoadedModule)) { throw "FAIL-CLOSED: Interface $functionName não resolve para a instância instrumentada de $role." }
        $State.CapturedReferences.Add([pscustomobject]@{CommandName=$functionName;Module=$resolved.Module;ModuleGuid=$resolved.Module.Guid;Definition=$resolved.Definition}) | Out-Null
    }
    foreach ($entry in $State.ModuleInstances) {
        if (-not [object]::ReferenceEquals($entry.Module,(Microsoft.PowerShell.Core\Get-Module -All | Where-Object { $_.Path -and [IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($entry.Path) } | Select-Object -Last 1))) { throw "FAIL-CLOSED: identidade de módulo trocada: $($entry.Role)." }
    }
    if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) { throw 'FAIL-CLOSED: ActiveDirectory carregado durante import transacional.' }
    if ((Get-FileHash -LiteralPath $State.InterfaceModule.Path -Algorithm SHA256 -ErrorAction Stop).Hash -ne $State.InterfaceHash) { throw 'FAIL-CLOSED: módulo Interface alterado durante transação.' }
    foreach ($counterName in $State.Counters.Keys) { if ([int]$State.Counters[$counterName] -ne 0) { throw "FAIL-CLOSED: fronteira acionada antes do gate: $counterName" } }
    $State.GatePassed = $true
    return [pscustomobject]@{Passed=$true;ConsumerPath=$Consumer.Path;RootRole=$role;RootPath=$expectedPath;CorePath=$State.Paths.Core;AuditPath=$State.Paths.Audit;Modules=@($State.ModuleInstances|ForEach-Object{[pscustomobject]@{Role=$_.Role;Path=$_.Path;Guid=$_.Guid}});Stubs=@($State.StubEvidence|ForEach-Object{[pscustomobject]@{Role=$_.Role;Name=$_.Name;Sentinel=$_.Sentinel;Parameters=$_.Parameters}});Imports=$State.ImportLog.Count;ActiveDirectoryLoaded=$false;ExternalCallsBeforeGate=0}
}

function Assert-AdminInterfaceReferencesCurrent {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    if(-not $State.GatePassed -or $State.InterfaceImportCount -ne 1){throw 'FAIL-CLOSED: no interface transaction is currently approved.'}
    $interfaceEntry=@($State.ModuleInstances|Where-Object Role -eq 'Interface')
    $rootRole=if($State.Domain -eq 'User'){'Actions'}else{'Management'}
    $rootEntry=@($State.ModuleInstances|Where-Object Role -eq $rootRole)
    $coreEntry=@($State.ModuleInstances|Where-Object Role -eq 'Core')
    $auditEntry=@($State.ModuleInstances|Where-Object Role -eq 'Audit')
    if($interfaceEntry.Count -ne 1 -or $rootEntry.Count -ne 1 -or $coreEntry.Count -ne 1 -or $auditEntry.Count -ne 1){throw 'FAIL-CLOSED: interface transaction module inventory is ambiguous.'}
    $commands=@($State.CapturedReferences)
    foreach($reference in $commands){
        $resolved=& $State.InterfaceModule {param($Name)Get-Command -Name $Name -CommandType Function -ErrorAction Stop} $reference.CommandName
        if(-not [object]::ReferenceEquals($resolved.Module,$reference.Module) -or -not [object]::ReferenceEquals($resolved.Module,$rootEntry[0].Module) -or $resolved.Definition -ne $reference.Definition){throw "FAIL-CLOSED: interface command reference became stale: $($reference.CommandName)"}
    }
    $nested=@(& $rootEntry[0].Module {Microsoft.PowerShell.Core\Get-Module -All})
    foreach($dependency in @($coreEntry[0],$auditEntry[0])){
        $current=@($nested|Where-Object{$_.Path -and [IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($dependency.Path)})
        if($current.Count -ne 1 -or -not [object]::ReferenceEquals($current[0],$dependency.Module)){throw "FAIL-CLOSED: nested module reference became stale: $($dependency.Role)."}
    }
    $importer=& $State.InterfaceModule {Get-Command Import-Module -CommandType Function -ErrorAction Stop}
    if($importer.Definition -notlike '*M47_INTERFACE_IMPORT_SENTINEL*' -or $State.Counters.Unexpected -ne 0 -or (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory)){throw 'FAIL-CLOSED: import guard or external state changed after interface execution.'}
    foreach($uiStub in @($State.StubEvidence|Where-Object Role -eq 'InterfaceUI')){
        $resolved=& $State.InterfaceModule {param($Name)Get-Command -Name $Name -CommandType Function -ErrorAction Stop} $uiStub.Name
        if($resolved.Definition -notlike "*$($uiStub.Sentinel)*"){throw "FAIL-CLOSED: UI boundary stub changed: $($uiStub.Name)."}
    }
    return [pscustomobject]@{Passed=$true;CapturedReferences=$commands.Count;Modules=@($interfaceEntry[0].Path,$rootEntry[0].Path,$coreEntry[0].Path,$auditEntry[0].Path);UnexpectedCalls=$State.Counters.Unexpected;ActiveDirectoryLoaded=$false}
}

function Assert-AdminInterfaceImportRequest {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Consumer,[Parameter(Mandatory)][string]$RequestedPath,[switch]$Force)
    if (-not [object]::ReferenceEquals($Consumer,$State.InterfaceModule)) { $State.Counters.Unexpected++; throw 'FAIL-CLOSED: import request origin is not the instrumented Interface module.' }
    $role = if ($State.Domain -eq 'User') { 'Actions' } else { 'Management' }
    if ($State.InterfaceImportRole -ne $role -or $State.GatePassed -or $State.InterfaceImportCount -ne 0 -or -not $Force) { $State.Counters.Unexpected++; throw 'FAIL-CLOSED: import transaction state/role/Force is not authorized.' }
    if ($RequestedPath -match '[*?\[\]]' -or $RequestedPath.StartsWith('\\') -or $RequestedPath -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') { $State.Counters.Unexpected++; throw 'FAIL-CLOSED: import path cannot be dynamic, wildcarded, or remote.' }
    $requested = Resolve-AdminAllowedPath -Path $RequestedPath -AllowedRoot $State.ProjectRoot -RequireExisting
    $expected = Resolve-AdminAllowedPath -Path $State.Paths[$role] -AllowedRoot $State.ProjectRoot -RequireExisting
    if ($requested -ne $expected -or -not $State.AllowedPaths.ContainsKey($expected)) { $State.Counters.Unexpected++; throw 'FAIL-CLOSED: Interface import target is outside the exact local allowlist.' }
    if (Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory) { throw 'FAIL-CLOSED: ActiveDirectory loaded before the interface import transaction.' }
    return [pscustomobject]@{Passed=$true;Role=$role;Path=$expected;Force=$true;Consumer=$Consumer}
}

function Install-AdminInterfaceTransactionGuard {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module,[Parameter(Mandatory)][ValidateSet('Actions','Management')][string]$ExpectedRole)
    if (-not [object]::ReferenceEquals($Module,$State.InterfaceModule)) { throw 'FAIL-CLOSED: Interface alvo não corresponde ao módulo importado.' }
    $State.InterfaceImportRole = $ExpectedRole
    $State.InterfaceUsesScopedGuard = $true
    $bodyText = @'
        [CmdletBinding()]
        param([Parameter(Position=0)][string]$Name,[switch]$Force,[switch]$PassThru)
        if (-not $global:M47InterfaceGate -or -not $global:M47InterfaceGate.GatePassed -and $global:M47InterfaceGate.InterfaceImportCount -gt 0) { throw 'M47_IMPORT_FAIL_CLOSED: estado transacional inválido.' }
        $consumer = $global:M47InterfaceGate.InterfaceModule
        $preflight = Assert-AdminInterfaceImportRequest -State $global:M47InterfaceGate -Consumer $consumer -RequestedPath $Name -Force:$Force
        if (-not $preflight.Passed) { throw 'M47_IMPORT_FAIL_CLOSED: preflight rejected.' }
        # Native import executes in this function's Interface module SessionState, preserving the consumer scope.
        $loaded = Microsoft.PowerShell.Core\Import-Module -Name $Name -Force:$Force -PassThru -ErrorAction Stop
        $gate = Complete-AdminInterfaceImportTransaction -State $global:M47InterfaceGate -Consumer $consumer -RequestedPath $Name -LoadedModule $loaded -Force:$Force
        if (-not $gate.Passed) { throw 'M47_IMPORT_FAIL_CLOSED: transaction gate did not pass.' }
        if ($PassThru) { return $loaded }
        # M47_INTERFACE_IMPORT_SENTINEL
'@
    & $Module { param($Text) $ImportBody=[scriptblock]::Create($Text); Set-Item -Path Function:\script:Import-Module -Value $ImportBody -Force -ErrorAction Stop } $bodyText
    $resolved = & $Module { Get-Command Import-Module -CommandType Function -ErrorAction Stop }
    if ($resolved.Definition -notlike '*M47_INTERFACE_IMPORT_SENTINEL*') { throw 'FAIL-CLOSED: importador transacional não resolveu no SessionState da Interface.' }
    $global:M47InterfaceGate = $State
    $State.StubEvidence.Add([pscustomobject]@{Role='Interface';Name='Import-Module';ModulePath=$Module.Path;Module=$Module;Sentinel='M47_INTERFACE_IMPORT_SENTINEL';CommandType=$resolved.CommandType;Parameters=@($resolved.Parameters.Keys)})|Out-Null
    return [pscustomobject]@{Module=$Module;Command=$resolved;Sentinel='M47_INTERFACE_IMPORT_SENTINEL';Role=$ExpectedRole}
}

function Install-AdminInterfaceUiStubs {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[Parameter(Mandatory)][System.Management.Automation.PSModuleInfo]$Module)
    if (-not [object]::ReferenceEquals($Module,$State.InterfaceModule)) { throw 'FAIL-CLOSED: UI stubs devem ser instalados no SessionState Interface.' }
    $readHost = { param([string]$Prompt,[switch]$AsSecureString)
        if ($global:M47InterfaceGate.InterfaceInputIndex -ge $global:M47InterfaceGate.InterfaceInputQueue.Count) { throw 'M47_UI_FAIL_CLOSED: entrada Read-Host não prevista.' }
        $value = [string]$global:M47InterfaceGate.InterfaceInputQueue[$global:M47InterfaceGate.InterfaceInputIndex]
        $global:M47InterfaceGate.InterfaceInputIndex++
        return $value
        # M47_UI_SENTINEL:Read-Host
    }
    $writeHost = { param([Parameter(ValueFromRemainingArguments=$true)]$Object,[string]$ForegroundColor,[switch]$NoNewline,[string]$Separator)
        $global:M47InterfaceGate.InterfaceOutputCount++
        # M47_UI_SENTINEL:Write-Host
    }
    $clearHost = {
        $global:M47InterfaceGate.InterfaceOutputCount++
        # M47_UI_SENTINEL:Clear-Host
    }
    & $Module {
        param($Read,$Write,$Clear)
        Set-Item Function:\script:Read-Host -Value $Read -Force
        Set-Item Function:\script:Write-Host -Value $Write -Force
        Set-Item Function:\script:Clear-Host -Value $Clear -Force
    } $readHost $writeHost $clearHost
    foreach ($item in @(@{Name='Read-Host';Body=$readHost;Params=@('Prompt');Sentinel='M47_UI_SENTINEL:Read-Host'},@{Name='Write-Host';Body=$writeHost;Params=@('Object');Sentinel='M47_UI_SENTINEL:Write-Host'},@{Name='Clear-Host';Body=$clearHost;Params=@();Sentinel='M47_UI_SENTINEL:Clear-Host'})) {
        $resolved = & $Module { param($Name) Get-Command $Name -CommandType Function -ErrorAction Stop } $item.Name
        if ($resolved.Definition -notlike "*$($item.Sentinel)*") { throw "FAIL-CLOSED: stub UI ausente: $($item.Name)." }
        $State.StubEvidence.Add([pscustomobject]@{Role='InterfaceUI';Name=$item.Name;ModulePath=$Module.Path;Module=$Module;Sentinel=$item.Sentinel;CommandType=$resolved.CommandType;Parameters=@($resolved.Parameters.Keys)})|Out-Null
    }
    return $true
}

function Assert-AdminProductionGate {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    $adModule = Microsoft.PowerShell.Core\Get-Module -Name ActiveDirectory
    if ($adModule) { throw 'FAIL-CLOSED: ActiveDirectory carregado.' }
    if ($State.ModuleInstances.Count -lt 3) { throw 'FAIL-CLOSED: import chain incompleta.' }
    foreach ($entry in $State.ModuleInstances) {
        $current = @($State.ModuleInstances | Where-Object { $_.Path -eq $entry.Path })
        if ($current.Count -ne 1 -or -not [object]::ReferenceEquals($current[0].Module,$entry.Module)) { throw "FAIL-CLOSED: instância substituída: $($entry.Role)" }
        if ($entry.Role -eq 'Interface') { Install-AdminInterfaceImportGuard -State $State -Module $entry.Module | Out-Null }
    }
    foreach ($stub in $State.StubEvidence) {
        if ($stub.Role -eq 'Interface') { continue }
        $resolved = & $stub.Module { param($Name) Get-Command $Name -CommandType Function -ErrorAction Stop } $stub.Name
        if ($resolved.Definition -notlike "*$($stub.Sentinel)*") { throw "FAIL-CLOSED: sentinela não resolvida: $($stub.Role)/$($stub.Name)" }
    }
    $rootRole = if ($State.Domain -eq 'User') { 'Actions' } else { 'Management' }
    $rootModule = @($State.ModuleInstances | Where-Object { $_.Role -eq $rootRole })
    $coreModule = @($State.ModuleInstances | Where-Object { $_.Role -eq 'Core' })
    $auditModule = @($State.ModuleInstances | Where-Object { $_.Role -eq 'Audit' })
    if ($rootModule.Count -ne 1 -or $coreModule.Count -ne 1 -or $auditModule.Count -ne 1) { throw 'FAIL-CLOSED: instâncias Core/Management/Audit ausentes ou ambíguas.' }
    $dependencyNames = if ($State.Domain -eq 'User') { @('Get-UserADInfo') } else { @('Get-GroupADInfo','Get-GroupMembers') }
    foreach ($dependencyName in $dependencyNames) {
        $dependency = & $rootModule[0].Module { param($Name) Get-Command $Name -CommandType Function -ErrorAction Stop } $dependencyName
        if (-not $dependency -or [string]::IsNullOrWhiteSpace($dependency.ModuleName) -or $dependency.ModuleName -ne $coreModule[0].Module.Name) {
            throw "FAIL-CLOSED: dependência não resolve para a instância Core auditada: $dependencyName"
        }
    }
    foreach ($counterName in $State.Counters.Keys) {
        if ([int]$State.Counters[$counterName] -ne 0) { throw "FAIL-CLOSED: fronteira externa acionada antes da aprovação do gate: $counterName" }
    }
    if ($State.Counters.Unexpected -ne 0) { throw 'FAIL-CLOSED: houve tentativa de comando/import inesperado.' }
    $State.GatePassed = $true
    return [pscustomobject]@{ Passed=$true; Modules=@($State.ModuleInstances | ForEach-Object { [pscustomobject]@{Role=$_.Role;Path=$_.Path;Guid=$_.Guid;Version=$_.Version} }); Stubs=@($State.StubEvidence | ForEach-Object { [pscustomobject]@{Role=$_.Role;Name=$_.Name;Sentinel=$_.Sentinel;CommandType=$_.CommandType;Parameters=$_.Parameters} }); ActiveDirectoryLoaded=$false; UnexpectedCalls=$State.Counters.Unexpected; StaticFiles=$State.StaticEvidence.AllFiles; Imports=$State.ImportLog.Count }
}

function Restore-AdminProductionImportGuard {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    if (-not $State.InterfaceUsesScopedGuard) {
        Remove-Item Function:\global:Import-Module -Force -ErrorAction SilentlyContinue
        if ($null -ne $State.PreviousGlobalImport) { Set-Item Function:\global:Import-Module -Value $State.PreviousGlobalImport.ScriptBlock -Force }
    }
    Remove-Variable -Name M43ProductionGate -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name M47InterfaceGate -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $State.PreviousGlobalState) { Set-Variable -Name PSModuleAutoLoadingPreference -Scope Global -Value $State.PreviousGlobalState.Value -Force }
    else { Remove-Variable -Name PSModuleAutoLoadingPreference -Scope Global -ErrorAction SilentlyContinue }
}

Export-ModuleMember -Function @(
    'New-AdminHarnessState','Resolve-AdminAllowedPath','Assert-AdminImportAllowed',
    'Register-AdminSyntheticModule','Register-AdminModuleInstance','Assert-AdminModuleIdentity',
    'Register-AdminCapturedReference','Assert-AdminCapturedReferencesCurrent',
    'Register-AdminSyntheticStub','Assert-AdminSyntheticStub','Install-AdminModuleStub',
    'Invoke-AdminSyntheticImport','Invoke-AdminSyntheticCommand','Test-AdminSyntheticMutationGate',
    'Invoke-AdminSyntheticMutation','Add-AdminHarnessResult','Assert-AdminHarness',
    'Resolve-AdminStaticAstValue','Assert-AdminProductionStaticClosure','New-AdminProductionGateState','New-AdminProductionStubBody',
    'Install-AdminProductionRoleStubs','Invoke-AdminGuardedProductionImport','Install-AdminProductionImportGuard',
    'Import-AdminProductionModuleChain','Install-AdminInterfaceImportGuard','Assert-AdminProductionGate','Restore-AdminProductionImportGuard',
    'Assert-AdminInterfaceInitializerSafe','Import-AdminInterfaceModuleSafe','Assert-AdminInterfaceImportRequest','Complete-AdminInterfaceImportTransaction','Assert-AdminInterfaceReferencesCurrent','Install-AdminInterfaceTransactionGuard','Install-AdminInterfaceUiStubs'
)
