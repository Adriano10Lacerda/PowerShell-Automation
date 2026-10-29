\# Interface GUI — PowerShell Automation



\## Visão geral



O módulo Interface GUI apresenta uma interface gráfica para o projeto PowerShell Automation, utilizando Windows Presentation Foundation (WPF) e XAML.



A interface reúne consultas e validações de Active Directory (AD) e Group Policy Objects (GPO) em uma janela central, com área para exibição de resultados e mensagens de status.



\*\*Versão identificada na interface:\*\* GUI V0.1.



\## Requisitos



\- Windows com suporte a WPF.

\- Windows PowerShell compatível com os assemblies .NET utilizados pelo script.

\- Repositório PowerShell Automation completo.

\- Arquivos de configuração e módulos AD e GPO presentes nos diretórios esperados.

\- `SimulationMode = true` nas configurações de AD e GPO.



\## Arquivos



| Arquivo | Descrição |

|---|---|

| `Interface-GUI.ps1` | Implementação da interface gráfica e das ações dos botões. |

| `Test-Interface-GUI.ps1` | Testes automatizados estruturais da interface. |



\## Recursos implementados



\### Visão geral



\- Janela central com navegação lateral.

\- Cartões para os módulos AD, Microsoft Entra ID, GPO e testes.

\- Área de mensagens e status.

\- Campo para exibir os resultados das consultas.



\### Active Directory



A interface oferece:



\- Validação da configuração AD.

\- Teste de conectividade em modo de simulação.

\- Consulta simulada de existência de usuário pelo `sAMAccountName`.

\- Validação para impedir consultas com o campo de usuário vazio.

\- Tratamento de erros e apresentação das mensagens na janela.



\### Group Policy Objects (GPO)



A interface oferece:



\- Listagem de GPOs.

\- Consulta de uma GPO específica.

\- Consulta de vínculos de uma GPO.

\- Tratamento de erros e apresentação dos resultados.



As consultas utilizam o módulo GPO e sua configuração, com modo de simulação obrigatório.



\## Funcionalidades informativas ou pendentes



Na implementação atual:



\- \*\*Microsoft Entra ID:\*\* o botão exibe uma mensagem informativa; a integração funcional não está habilitada nessa tela.

\- \*\*Testes e validação:\*\* o botão também exibe uma mensagem informativa; não executa a suíte de testes.

\- A interface identifica visualmente o ambiente como modo de simulação.



Essas opções não devem ser consideradas integrações funcionais concluídas.



\## Segurança



O script verifica se `SimulationMode` está definido como `true` nas configurações de AD e GPO. Se a condição não for atendida, a inicialização é interrompida.



As ações disponíveis nesta interface são destinadas à validação e consulta em modo de simulação. Não se deve interpretar o resultado como confirmação de conectividade real ou de execução de alterações no ambiente.



\## Como executar



Na raiz do repositório, execute:



```powershell

.\\11-Interface-GUI\\Interface-GUI.ps1

```



A janela é exibida por meio de `ShowDialog()`.



Antes da execução, confira a existência dos arquivos de configuração e módulos esperados:



\- `03-AD-User-Provisioning\\AD-Configuration.json`

\- `03-AD-User-Provisioning\\AD-Functions.psm1`

\- `07-GPO-Management\\GPO-Configuration.json`

\- `07-GPO-Management\\GPO-Functions.psm1`



\## Testes automatizados



Execute:



```powershell

.\\11-Interface-GUI\\Test-Interface-GUI.ps1

```



\### Último resultado registrado



\- Total de testes: 15

\- Aprovados: 15

\- Falhas: 0



Os testes são estruturais e verificam itens como sintaxe, definição da janela WPF, validação do modo de simulação, presença das funções, tratamento de erros e conexão dos botões às ações.



A aprovação dos testes estruturais não substitui testes funcionais em um ambiente controlado.



\## Limitações conhecidas



\- A integração com Microsoft Entra ID é apenas informativa nessa tela.

\- A opção Testes e validação é apenas informativa.

\- As operações AD e GPO estão configuradas para simulação.

\- A interface não deve ser considerada uma ferramenta de execução real de alterações de infraestrutura sem implementação, validação e testes adicionais.