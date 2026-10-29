\# AD Group Management



\## Visão geral



O módulo \*\*AD Group Management\*\* automatiza operações de gerenciamento de grupos no Active Directory, com suporte a modo de simulação e execução integrada ao Active Directory quando configurado para isso.



O módulo utiliza PowerShell e organiza as operações em funções reutilizáveis, com validação de configuração e tratamento de erros.



\## Funcionalidades



\- Verificar se um grupo existe.

\- Criar grupos com escopo e categoria configuráveis.

\- Adicionar usuários a grupos.

\- Remover usuários de grupos.

\- Listar os membros de um grupo.

\- Validar a configuração do módulo.

\- Verificar a conectividade com o Active Directory.

\- Executar operações em modo de simulação.

\- Validar condições como grupo inexistente, usuário inexistente e associação duplicada no cenário simulado.



\## Estrutura dos arquivos



| Arquivo | Descrição |

|---|---|

| `AD-Group-Management.ps1` | Script principal com menu interativo. |

| `Group-Functions.psm1` | Funções de configuração, consulta e gerenciamento de grupos. |

| `Group-Configuration.example.json` | Exemplo de configuração. |

| `Group-Configuration.json` | Configuração utilizada pelo script em execução. |

| `Test-ADGroupManagement.ps1` | Testes automatizados do módulo. |



\## Requisitos



\- Windows com PowerShell.

\- Arquivos do módulo presentes nos caminhos esperados.

\- Arquivo `Group-Configuration.json` válido.

\- Para operações reais, módulo PowerShell `ActiveDirectory` disponível e permissões adequadas no domínio.

\- Controlador de domínio configurado para operações reais.



\## Configuração



O exemplo `Group-Configuration.example.json` contém os seguintes parâmetros:



| Parâmetro | Descrição |

|---|---|

| `SimulationMode` | Define se as operações utilizam o cenário simulado. |

| `ActiveDirectory.DomainController` | Controlador de domínio utilizado nas operações reais. |

| `ActiveDirectory.TargetOU` | Caminho opcional da OU de destino para novos grupos. |

| `Group.DefaultScope` | Escopo padrão do grupo, como `Global`. |

| `Group.DefaultCategory` | Categoria padrão do grupo, como `Security`. |

| `Group.RequireDescription` | Define se a descrição do grupo é obrigatória. |

| `Operations` | Contém indicadores de operações habilitadas na configuração. |

| `Simulation.ExistingGroups` | Lista de grupos utilizados no cenário simulado. |

| `Simulation.ExistingUsers` | Lista de usuários utilizados no cenário simulado. |



\### Exemplo de configuração



```json

{

&#x20; "SimulationMode": true,

&#x20; "ActiveDirectory": {

&#x20;   "DomainController": "",

&#x20;   "TargetOU": ""

&#x20; },

&#x20; "Group": {

&#x20;   "DefaultScope": "Global",

&#x20;   "DefaultCategory": "Security",

&#x20;   "RequireDescription": true

&#x20; },

&#x20; "Operations": {

&#x20;   "CreateGroup": true,

&#x20;   "AddMember": true,

&#x20;   "RemoveMember": true,

&#x20;   "ListMembers": true

&#x20; },

&#x20; "Simulation": {

&#x20;   "ExistingGroups": \[],

&#x20;   "ExistingUsers": \[]

&#x20; }

}

```



O arquivo de exemplo pode ser copiado para `Group-Configuration.json` e ajustado conforme o ambiente. Para iniciar com segurança, mantenha `SimulationMode` como `true`.



\*\*Observação:\*\* a implementação valida a estrutura da seção `Operations`, mas as funções de gerenciamento não consultam individualmente esses indicadores para bloquear cada operação.



\## Como executar



Na raiz do repositório, execute:



```powershell

.\\06-AD-Group-Management\\AD-Group-Management.ps1

```



O menu interativo oferece:



| Opção | Operação |

|---|---|

| `1` | Verificar grupo |

| `2` | Criar grupo |

| `3` | Adicionar usuário ao grupo |

| `4` | Remover usuário do grupo |

| `5` | Listar membros do grupo |

| `0` | Sair |



Para adicionar ou remover um usuário, informe o nome do grupo e o `SamAccountName` do usuário.



\## Modo de simulação



Com `SimulationMode` definido como `true`:



\- Não é realizada conexão real com o Active Directory.

\- As consultas utilizam os dados definidos na seção `Simulation`.

\- A criação e as alterações de associação de membros ocorrem nos objetos de simulação durante a execução.

\- Os resultados indicam que a operação foi simulada e que nenhuma alteração real foi realizada.



Os dados simulados não devem ser interpretados como dados atualizados do domínio.



\## Operações reais e segurança



Com `SimulationMode` definido como `false`, o módulo pode utilizar os comandos do PowerShell Active Directory para consultar e alterar grupos.



Essas operações podem criar grupos e adicionar ou remover usuários no domínio. Antes de desabilitar a simulação:



1\. Revise `Group-Configuration.json`.

2\. Configure `ActiveDirectory.DomainController`.

3\. Confira o caminho de `ActiveDirectory.TargetOU`, se utilizado.

4\. Confirme que a conta de execução possui somente as permissões necessárias.

5\. Teste em um ambiente controlado e valide os resultados antes de utilizar em produção.



A configuração contém indicadores na seção `Operations`, mas eles não funcionam como controles efetivos de autorização no código atual.



\## Testes automatizados



Execute:



```powershell

.\\06-AD-Group-Management\\Test-ADGroupManagement.ps1

```



Os testes automatizados ajudam a verificar o comportamento implementado pelo módulo. A aprovação dos testes não substitui validações de conectividade, permissões e operações reais em um ambiente controlado.



\## Limitações e observações



\- O script principal realiza uma operação do menu por execução e encerra após processá-la.

\- O cenário de simulação depende das listas de grupos e usuários configuradas.

\- A conectividade real depende do módulo ActiveDirectory, do controlador de domínio e das permissões da conta.

\- Os indicadores da seção `Operations` são validados estruturalmente, mas não bloqueiam individualmente as operações.

\- O módulo deve permanecer em modo de simulação durante a validação inicial e os testes de documentação.
