# Harness persistente de integração administrativa — Missão 40

## Objetivo e escopo

Este conjunto valida Unlock, Enable, Disable e Force Password Change de User, além de Add/Remove de membros Group. O modo padrão é exclusivamente sintético. O modo explícito `ProductionStubbed` importa os módulos locais de produção após auditoria estática recursiva, instala stubs nas instâncias reais de Core e Actions/Management e executa as funções de produção usando somente fixtures fictícias. ActiveDirectory permanece descarregado; o stub bloqueia imports AD e nenhuma chamada real ou escrita no repositório é permitida.

## Arquitetura

- `Integration.Common.psm1`: caminhos permitidos, registro de instâncias e referências, identidade de stubs, importação sintética transacional, gates de autorização simulados, contadores e asserções fail-closed. A função de instalação em `PSModuleInfo` é exercitada apenas no módulo do próprio harness; não é aplicada a módulos de produção.
- `Integration.Fixtures.psm1`: objetos fictícios independentes para usuários, grupos, autorizações e resultados.
- `Test-UserActions.ps1`: matrizes sintética e `ProductionStubbed` para as quatro ações User e casos de acesso, erro, mutação e auditoria.
- `Test-GroupMutations.ps1`: matrizes sintética e `ProductionStubbed` para Add/Remove, estado de associação, consulta, autorização e auditoria; inclui a remoção simulada do último membro e verifica que o grupo permanece com uma coleção vazia.
- `Test-Isolation-Negative.ps1`: testes negativos do modelo de isolamento; não carrega módulos do projeto.
- `Invoke-AdminMutationIntegration.ps1`: inicia cada suite em processo PowerShell 7 separado, exige marcadores e exit code zero, captura stdout/stderr e aplica timeout.

## Pré-requisitos e execução segura

PowerShell 7. O modo padrão é sintético:

```powershell
pwsh -NoProfile -NonInteractive -File .\Validation\Missao40\Invoke-AdminMutationIntegration.ps1
```

Suites separadas:

```powershell
pwsh -NoProfile -NonInteractive -File .\Validation\Missao40\Invoke-AdminMutationIntegration.ps1 -Suite User
pwsh -NoProfile -NonInteractive -File .\Validation\Missao40\Invoke-AdminMutationIntegration.ps1 -Suite Group
pwsh -NoProfile -NonInteractive -File .\Validation\Missao40\Invoke-AdminMutationIntegration.ps1 -Suite Negative
```

Para a validação controlada com os módulos reais e dependências externas substituídas por stubs:

```powershell
pwsh -NoProfile -NonInteractive -File .\Validation\Missao40\Invoke-AdminMutationIntegration.ps1 -Mode ProductionStubbed -Suite All
```

Para executar os pontos de entrada administrativos da Interface V2 com entrada determinística e imports transacionais, use um processo filho por ação/cenário:

```powershell
pwsh -NoProfile -NonInteractive -File .\Validation\Missao40\Invoke-AdminMutationIntegration.ps1 -Mode InterfaceStubbed -Suite All
```

Esse modo audita estaticamente os inicializadores e a closure local, instala o importador no SessionState da Interface, valida a allowlist antes do import `-Force`, instrumenta Core e Actions/Management antes de devolver o controle, e exige sentinelas, identidades, entrada consumida, contadores e marcador de gate. Cada cenário roda em processo separado para impedir reutilização de autorização ou instâncias forçadas. O modo não executa `Start-V2Interface` nem menus gerais; limita-se aos quatro pontos de entrada de ações User e aos dois pontos de entrada Group Add/Remove.

`ProductionStubbed` não usa AD: cada import `ActiveDirectory` é interceptado no SessionState do módulo, e os cmdlets AD de leitura/escrita são funções fictícias com sentinelas e contadores. O runner exige o gate positivo, identidade e parâmetros dos stubs, zero chamadas inesperadas, ActiveDirectory ausente, marcadores, evidência JSON, contagem exata, exit code zero e hashes íntegros. O modo não é uma autorização para executar infraestrutura real. Não execute os scripts filhos diretamente para contornar o runner e o gate.

O runner valida SHA-256 dos arquivos críticos e dos sete arquivos do harness antes/depois. Os resultados estruturados são emitidos em stdout; não cria logs nem arquivos temporários.

## Cenários cobertos sinteticamente

As matrizes representam SimulationMode, Preview, WhatIf, ausência de autorização, somente leitura, escrita inválida, autorização válida com Execute, recusa de ShouldProcess, cancelamento, NotFound, erro de consulta, falha fictícia do mutador, falha de auditoria posterior, autorização de outra operação e reimportação. Group acrescenta grupo/usuário inexistente e membro presente/ausente.

Os resultados `Partial` preservam `Changed = true` quando a auditoria falha depois da mutação fictícia; não alegam rollback. No modo `ProductionStubbed`, as chamadas percorrem funções reais dos módulos Actions/Group Management e Core, mas as operações de diretório, mutação e auditoria são stubs; isso não substitui validação de interface interativa ou teste em ambiente de homologação.

## Interpretação e bloqueios

`PASS` exige exit code zero, marcadores de início/gate/conclusão, contagem esperada e evidências estruturadas. Erro, timeout, marcador ausente, caminho fora da raiz, stub ou assinatura ausente, identidade substituída e referência obsoleta bloqueiam o cenário. `PASS` sintético só valida o modelo sintético; `PASS` em `ProductionStubbed` só valida os caminhos de funções abrangidos sob stubs, não a integração funcional completa da V1.

## Etapa futura de integração real

O harness não executa os seis pontos de entrada da Interface V2 nem fluxos administrativos de UI. O gate impede reimportação de produção após a instrumentação; o comportamento funcional de `Import-Module -Force` nos módulos reais não é exercitado. PowerShell 5.1 é apenas uma validação estática separada, nunca funcional. Para uma regressão de release ainda são necessários os outros testes V1 isolados, revisão da cobertura completa e auditoria final dos riscos.

## Restrições

Não instalar dependências, não usar infraestrutura externa, não executar ações reais, não tratar `Execute` como autorização e não interpretar estes resultados sintéticos como liberação da V1 ou prontidão para release.
