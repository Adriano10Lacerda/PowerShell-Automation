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

Para executar a suíte de testes:

```powershell
.\02-Configuration\Test-Configuration.ps1
```

### Resultado da validação da V1

| Indicador | Resultado |
|---|---:|
| Total de testes | 21 |
| Testes aprovados | 21 |
| Testes reprovados | 0 |
| Taxa de aprovação | 100% |

**Status: todos os testes passaram.**

A suíte contempla cenários de sucesso e falha, incluindo arquivo inexistente, JSON inválido, campos ausentes, valores inválidos, limites de quantidade, formatos de data e caracteres especiais.

## Observação

O módulo é responsável por carregar e validar configurações. A execução de outras operações do PowerShell-Automation depende dos scripts que consomem essas configurações.
