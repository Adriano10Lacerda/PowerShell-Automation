# Módulo 02 — Configuration

## Visão geral

O módulo **Configuration** fornece uma função centralizada para carregar e validar arquivos de configuração JSON utilizados pelo projeto PowerShell-Automation.

A validação ajuda a identificar configurações ausentes, valores inválidos e parâmetros fora dos limites definidos antes de serem utilizados pelos scripts.

## Estrutura do módulo

```text
02-Configuration/
├── config.example.json
├── config.json
├── Configuration.psm1
├── Test-Configuration.ps1
└── Validate-Configuration.ps1
```

### Arquivos

| Arquivo | Descrição |
|---|---|
| `Configuration.psm1` | Contém a função `Get-Configuration`. |
| `config.example.json` | Exemplo de configuração para referência. |
| `config.json` | Arquivo de configuração utilizado na validação local. |
| `Test-Configuration.ps1` | Executa os testes automatizados do módulo. |
| `Validate-Configuration.ps1` | Valida o arquivo `config.json` e apresenta os valores configurados. |

## Função disponível

### `Get-Configuration`

Carrega um arquivo JSON e valida os parâmetros definidos nele.

**Parâmetro:**

| Parâmetro | Tipo | Obrigatório | Descrição |
|---|---|---|---|
| `ConfigurationPath` | String | Sim | Caminho do arquivo JSON que será carregado e validado. |
| `ApprovedRoot` | String | No modo confinado | Raiz local previamente existente e aprovada pelo chamador, independente do conteúdo do JSON. |
| `ApprovedRootIdentity` | String | No modo confinado | Identidade atual do diretório raiz (volume e ID) usada para detectar substituição durante a validação; não é uma credencial nem atestação. |

As chamadas existentes com apenas `ConfigurationPath` continuam aceitas para caminhos confiáveis. No modo confinado, forneça os dois parâmetros de raiz e um caminho absoluto sob ela. O módulo distingue caminho inseguro, arquivo ausente, falha de leitura, JSON inválido e esquema inválido.

**Exemplo de utilização:**

```powershell
Import-Module .\02-Configuration\Configuration.psm1 -Force

$config = Get-Configuration `
    -ConfigurationPath ".\02-Configuration\config.json"

$config
```

## Parâmetros de configuração

O arquivo de exemplo utiliza os seguintes parâmetros:

```json
{
    "Prefixo": "EMP",
    "QuantidadeCaracteres": 12,
    "FormatoData": "ddMM",
    "CaracteresEspeciais": "!@#$%&*"
}
```

| Parâmetro | Regra de validação |
|---|---|
| `Prefixo` | Deve estar presente e não pode ser vazio ou conter somente espaços em branco. |
| `QuantidadeCaracteres` | Deve estar presente, ser um número inteiro e estar entre 4 e 128. |
| `FormatoData` | Deve estar presente e corresponder a um dos formatos aceitos: `ddMM`, `dd/MM/yyyy` ou `yyyy-MM-dd`. |
| `CaracteresEspeciais` | Deve estar presente e não pode ser vazio. Não pode conter letras, números ou espaços. |

## Validações implementadas

O módulo verifica:

- Existência do arquivo informado.
- Validade da estrutura JSON.
- Presença dos parâmetros obrigatórios.
- Valores vazios ou ausentes.
- Tipo inteiro e limites da quantidade de caracteres.
- Formatos de data permitidos.
- Presença de letras, números ou espaços na configuração de caracteres especiais.

Quando são identificados erros, a função apresenta as mensagens de validação para que a configuração possa ser corrigida.

## Validar a configuração

Para executar o script de validação:

```powershell
.\02-Configuration\Validate-Configuration.ps1
```

O script carrega o módulo, valida o arquivo `config.json` e apresenta os parâmetros quando a configuração é válida.

## Testes automatizados

O harness recebe uma raiz exclusiva e vazia, provisionada previamente para a tentativa, e sua identidade registrada por um provisionador confiável. Não há fallback para o temporário do ambiente. Exemplo para uso após autorização e prova da fronteira:

```powershell
.\02-Configuration\Test-Configuration.ps1 -WorkspaceRoot $WorkspaceRoot
```

O harness requer `WorkspaceRoot` explícito, existente, local, vazio e aprovado para a tentativa. Ele não cria diretórios, não altera ACLs e não usa `%TEMP%` como fallback. A validação exige que a raiz e os ancestrais satisfaçam a política de acesso já configurada, além de rejeitar caminhos ambíguos e reparse points. A identidade do diretório é uma verificação de consistência, não autenticação de um provider. Este fluxo destina-se somente a scripts próprios, revisados e autorizados em ambiente administrativo confiável; não é isolamento contra código malicioso executado com o mesmo token, Administrators ou SYSTEM. A validação por caminho e a abertura/leitura posterior ainda têm uma janela TOCTOU contra concorrência hostil. O harness exclui apenas fixtures registradas por esta tentativa, sem recursão, após revalidar identidade e conteúdo; em caso de divergência, preserva os objetos e marca `CLEANUP_INCOMPLETE`. A raiz nunca é excluída.

Chamadores existentes de Get-Configuration com apenas ConfigurationPath continuam no parameter set TrustedPath para preservar compatibilidade. Esse modo pressupõe que o chamador já confia no caminho e não deve ser usado para arquivos não confiáveis. O harness usa o parameter set Confined com a raiz e identidade explícitas.

### Resultado histórico da validação

| Indicador | Resultado |
|---|---:|
| Total de testes | 21 |
| Testes aprovados | 21 |
| Testes reprovados | 0 |
| Taxa de aprovação | 100% |

Esses números são históricos. A suíte alterada depende de validação futura em ambiente confinado.

A suíte contempla cenários de sucesso e falha, incluindo arquivo inexistente, JSON inválido, campos ausentes, valores inválidos, limites de quantidade, formatos de data e caracteres especiais.

O código atual preserva os 21 cenários da evidência histórica e acrescenta 18 verificações-fonte, para um total esperado de 39: traversal, UNC, dispositivo e ADS testados no helper e na API `Get-Configuration` do parameter set Confined; raiz inexistente e raiz não vazia; identidade divergente; preservação de fixture durante falha de identidade/hash; preservação de arquivo não registrado; ExitCode não zero para falhas de setup/cleanup; compatibilidade TrustedPath; e detecção de reparse point pela API Confined. A validação de reparse tenta criar um link simbólico com nome aleatório somente dentro do WorkspaceRoot validado, aponta-o para a própria raiz e remove apenas o link, sem recursão. Se a criação não for suportada ou autorizada pelo ambiente, o cenário é contado como BLOCKED e o processo termina com código diferente de zero; não há alteração de ACL ou política. Falha na limpeza do link também impede PASS e deixa a execução não-zero.

Os cenários de raiz não vazia e de identidade/hash de cleanup usam fixtures criadas pelo próprio harness no workspace aprovado. O cenário de arquivo não registrado remove temporariamente o registro em memória de uma fixture do harness para demonstrar que a limpeza ignora arquivos sem propriedade registrada; o registro é restaurado para a limpeza final. Nenhum caso autoriza limpeza recursiva ou remoção da raiz.

A contagem esperada da fonte é 39 casos (21 preservados + 18 adicionados), mas isso não constitui resultado de execução. Uma execução futura somente poderá ser considerada aprovada se não houver FAIL ou BLOCKED, setup e cleanup concluírem sem ambiguidade e o ExitCode for zero. O requisito de DACL/identidade de WorkspaceRoot continua dependente de provisionamento prévio válido; o harness não cria nem altera ACLs. Esta suíte não prova isolamento contra concorrência hostil ou processos com o mesmo token, Administrators ou SYSTEM. As verificações por caminho e a remoção do link ainda têm limites TOCTOU sob esse modelo.

## Observação

O módulo é responsável por carregar e validar configurações. A execução de outras operações do PowerShell-Automation depende dos scripts que consomem essas configurações.
