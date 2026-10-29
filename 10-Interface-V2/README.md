\# Interface V2 — PowerShell Automation



\## Visão geral



O módulo \*\*Interface V2\*\* fornece uma interface central em PowerShell para funcionalidades de administração de infraestrutura Microsoft. Ele integra operações de gerenciamento de usuários, grupos, computadores e políticas, com recursos de consulta, pré-visualização e confirmação de ações.



\## Requisitos



\- Windows PowerShell 5.1 ou superior.

\- Repositório PowerShell Automation clonado localmente.

\- Módulos e configurações necessários para cada funcionalidade.

\- Permissões adequadas no ambiente de destino para operações reais.



\## Estrutura dos arquivos



| Arquivo | Descrição |

|---|---|

| `Interface-V2.ps1` | Inicializa a interface e importa o módulo de funções. |

| `Interface-V2-Functions.psm1` | Contém o menu principal e as funções integradas. |

| `Test-Interface-V2.ps1` | Executa testes automatizados de estrutura e integração. |



O diretório também contém arquivos de backup (`.bak`), que não fazem parte do fluxo normal de inicialização.



\## Funcionalidades



\### 1. Users — gerenciamento de usuários



\- Consulta e resumo de usuários.

\- Exibição de detalhes.

\- Desbloqueio de contas.

\- Ativação e desativação de contas.

\- Solicitação de alteração de senha no próximo logon.

\- Pré-visualização e confirmação antes de executar ações compatíveis.



\### 2. Groups — gerenciamento de grupos



\- Consulta de grupos e membros.

\- Inclusão e remoção de membros.

\- Pré-visualização e confirmação das operações.

\- Atualização da consulta após as ações.



\### 3. Computers — gerenciamento de computadores



\- Consulta por hostname.

\- Exibição de resumo e detalhes.

\- Apresentação de informações de status.

\- Tratamento de erros de consulta e indicação de modo de simulação.



\### 4. Policies — gerenciamento de políticas



A interface integra o gerenciamento de políticas de Grupo (GPO), incluindo opções de listagem, consulta de GPOs, consulta de vínculos e criação simulada. O comportamento depende do módulo GPO e da configuração carregada.



\## Opções ainda em desenvolvimento



As opções abaixo exibem mensagens de desenvolvimento na implementação atual:



\- \*\*Accounts\*\*

\- \*\*Reports\*\*

\- \*\*Settings\*\*



Essas opções não devem ser consideradas funcionalidades concluídas.



\## Execução



Na raiz do repositório, execute:



```powershell

.\\10-Interface-V2\\Interface-V2.ps1

```



O launcher verifica a existência de `Interface-V2-Functions.psm1`, importa o módulo e inicia `Start-V2Interface`. Em caso de erro de inicialização, apresenta a mensagem correspondente.



\## Testes



Execute:



```powershell

.\\10-Interface-V2\\Test-Interface-V2.ps1

```



\### Último resultado registrado



\- Total: 105 testes

\- Aprovados: 105

\- Falhas: 0



Os testes verificam a existência dos arquivos, importação do módulo, disponibilidade das funções, integração dos módulos, estrutura do menu e presença de controles de execução. A aprovação desses testes não substitui testes controlados em um ambiente real.



\## Segurança e operação



\- Revise a configuração antes de executar operações em ambiente real.

\- Utilize o modo de simulação quando disponível para validar o fluxo antes da execução.

\- Confirme cuidadosamente as ações que alteram contas, grupos ou políticas.

\- Utilize uma conta com somente as permissões necessárias.

\- Não armazene senhas ou credenciais diretamente nos arquivos do projeto.

\- Teste as operações reais em ambiente controlado antes de utilizá-las em produção.



\## Observações



A Interface V2 possui funcionalidades implementadas e opções ainda em desenvolvimento. Consulte os módulos integrados e suas configurações para conhecer os requisitos e limitações específicos de cada operação.

