# Módulo 04 — Entra ID User Provisioning



## Visão geral



O módulo **Entra ID User Provisioning** automatiza a preparação, validação e criação de usuários no Microsoft Entra ID por meio do Microsoft Graph PowerShell SDK.



O módulo oferece um modo de simulação para testar o fluxo sem realizar alterações reais no tenant e um modo real para provisionar usuários após a validação da configuração, dos dados e da conexão.



## Estrutura do módulo



```text

04-Entra-ID-User-Provisioning/

├── Entra-Configuration.example.json

├── Entra-Configuration.json

├── Entra-Functions.psm1

├── Provision-EntraUser.ps1

└── Test-EntraProvisioning.ps1

```



| Arquivo | Descrição |

|---|---|

| `Entra-Configuration.example.json` | Exemplo de configuração do módulo. |

| `Entra-Configuration.json` | Configuração utilizada na execução local. |

| `Entra-Functions.psm1` | Contém as funções de validação, normalização, verificação de duplicidade, conexão, provisionamento e pós-validação. |

| `Provision-EntraUser.ps1` | Script principal de provisionamento de usuários. |

| `Test-EntraProvisioning.ps1` | Suíte de testes automatizados do módulo. |



## Configuração



O módulo utiliza um arquivo JSON para definir o tenant, o domínio, o modo de execução e os dados de simulação.



Exemplo:



```json

{

&#x20;   "TenantId": "00000000-0000-0000-0000-000000000000",

&#x20;   "Domain": "example.onmicrosoft.com",

&#x20;   "SimulationMode": true,



&#x20;   "UserPrincipalName": {

&#x20;       "Domain": "example.onmicrosoft.com"

&#x20;   },



&#x20;   "Simulation": {

&#x20;       "ExistingUserPrincipalNames": [

&#x20;           "maria.silva@example.onmicrosoft.com",

&#x20;           "joao.santos@example.onmicrosoft.com"

&#x20;       ]

&#x20;   }

}

```



### Parâmetros



| Parâmetro | Descrição |

|---|---|

| `TenantId` | Identificador do tenant Microsoft Entra ID. É obrigatório no modo real e deve possuir formato GUID válido. |

| `Domain` | Domínio configurado para a operação real. |

| `SimulationMode` | Define se a operação será simulada (`true`) ou real (`false`). Deve ser um valor booleano. |

| `UserPrincipalName.Domain` | Domínio utilizado para gerar o UPN do usuário. |

| `Simulation.ExistingUserPrincipalNames` | Lista de UPNs utilizados para simular a verificação de usuários existentes. |



O arquivo de exemplo utiliza um domínio fictício e mantém `SimulationMode` habilitado.



## Funcionalidades



### 1. Validação de configuração



A função `Test-EntraConfiguration` valida:



- Tipo booleano de `SimulationMode`.

- Formato do `TenantId` quando o modo real está habilitado.

- Presença do domínio no modo real.

- Configuração do domínio do UPN.

- Estrutura dos dados de simulação.



### 2. Normalização de identificadores



A função `ConvertTo-EntraIdentifier` normaliza os nomes utilizados na geração dos identificadores:



- Remove acentos.

- Converte espaços em hífens.

- Remove caracteres fora do conjunto de letras, números e hífens.

- Remove hífens duplicados e das extremidades.

- Converte o resultado para letras minúsculas.



Exemplo:



```text

Entrada:  João da Silva

Resultado: joao-da-silva

```



### 3. Validação de dados do usuário



A função `Test-EntraUserProvisioning` verifica:



- Nome e sobrenome obrigatórios.

- Comprimento mínimo de dois caracteres para nome e sobrenome.

- Formato do User Principal Name (UPN).

- Presença do `MailNickname`.

- Tipo booleano da propriedade `AccountEnabled`.



### 4. Verificação de duplicidade



A função `Test-EntraUserExists` verifica se o UPN já está sendo utilizado.



No modo de simulação, a verificação utiliza a lista configurada em `Simulation.ExistingUserPrincipalNames`.



No modo real, utiliza `Get-MgUser` para consultar o Microsoft Graph.



### 5. Validação da conexão com o tenant



A função `Test-EntraTenantConnection` verifica:



- Disponibilidade do comando `Get-MgContext`.

- Existência de uma sessão autenticada no Microsoft Graph.

- Presença do Tenant ID no contexto autenticado.

- Correspondência entre o tenant conectado e o tenant configurado.



### 6. Provisionamento de usuários



A função `New-EntraUserProvision` executa as validações antes de iniciar o provisionamento.



No modo de simulação, retorna um resultado indicando que o usuário foi preparado, sem realizar alterações no Entra ID.



No modo real, utiliza `New-MgUser` para criar o usuário no Microsoft Entra ID.



A senha inicial é solicitada durante a operação. O módulo configura a troca de senha no próximo login e não armazena a senha inicial. Os dados temporários utilizados no processamento são limpos ao final da operação.



### 7. Pós-validação



A função `Test-EntraUserPostProvisioning` consulta o usuário criado e verifica:



- ID retornado pelo Microsoft Graph.

- Display Name.

- User Principal Name.



A operação retorna sucesso somente quando os dados conferidos correspondem aos valores esperados.



## Execução



Para iniciar o provisionamento:



```powershell

.\04-Entra-ID-User-Provisioning\Provision-EntraUser.ps1

```



O script solicita o nome e o sobrenome, gera os identificadores do usuário, apresenta os dados para conferência e solicita confirmação antes de prosseguir.



## Modo de simulação



Com `SimulationMode` definido como `true`:



- O fluxo de provisionamento é executado em simulação.

- A verificação de duplicidade utiliza os dados configurados para simulação.

- A função de criação não chama `New-MgUser`.

- Nenhuma alteração real é realizada no Microsoft Entra ID.



Esse modo permite validar o comportamento do módulo sem criar usuários no tenant.



## Modo real



Com `SimulationMode` definido como `false`, o módulo pode executar operações reais no Microsoft Entra ID.



Antes da execução, é necessário:



- Configurar corretamente o tenant e o domínio.

- Possuir uma sessão autenticada no Microsoft Graph.

- Ter os comandos necessários do Microsoft Graph PowerShell SDK disponíveis.

- Conferir os dados do usuário.

- Confirmar explicitamente a operação.



**Atenção:** o modo real pode criar um usuário no tenant configurado. Utilize-o somente em um ambiente autorizado e após revisar os parâmetros da operação.



## Testes automatizados



Para executar a suíte de testes:



```powershell

.\04-Entra-ID-User-Provisioning\Test-EntraProvisioning.ps1

```



A suíte contempla testes de:



- Validação de configuração.

- Validação de usuários.

- Propriedade `AccountEnabled`.

- Detecção de usuários duplicados.

- Provisionamento simulado.

- Usuários inexistentes.

- Normalização de identificadores.

- Pós-validação.

- Bloqueio de criação no modo de simulação.

- Validação de Tenant ID e domínio.

- Valores inválidos de `SimulationMode`.

- Criação e falhas utilizando mocks do Microsoft Graph.



### Resultado dos testes



| Indicador | Resultado |

|---|---:|

| Total de testes | 29 |

| Testes aprovados | 29 |

| Testes reprovados | 0 |

| Taxa de aprovação | 100% |



**Status: todos os testes passaram.**



Os testes foram executados em ambiente de simulação, incluindo cenários com mocks do Microsoft Graph.



## Tecnologias utilizadas



- PowerShell

- Microsoft Entra ID

- Microsoft Graph PowerShell SDK

- JSON

- Testes automatizados com simulação e mocks



## Objetivo do módulo



Demonstrar uma abordagem estruturada para provisionamento de usuários no Microsoft Entra ID, com validação de dados, controle de duplicidade, simulação, confirmação explícita e pós-validação da operação.




