# Computer Inventory — PowerShell Automation



## Visão geral



O módulo **Computer Inventory** realiza o inventário de computadores Windows, coletando informações de hardware, sistema operacional, armazenamento, rede e BitLocker.



O projeto permite configurar quais informações serão coletadas e exportar os resultados nos formatos JSON e CSV.



O módulo também possui um modo de simulação que utiliza dados fictícios para demonstrar o funcionamento sem realizar a coleta real ou gravar relatórios.



## Funcionalidades



- Inventário de informações do computador.

- Coleta de dados do sistema operacional.

- Identificação do processador e da memória RAM.

- Inventário de discos fixos e removíveis.

- Coleta de informações de adaptadores de rede.

- Consulta de informações de BitLocker, quando disponível.

- Exportação de relatórios em JSON e CSV.

- Configuração das categorias de inventário.

- Modo de simulação para testes e demonstrações.

- Tratamento de erros durante a coleta e exportação.



## Informações coletadas



| Categoria | Informações |

|---|---|

| Computador | Nome, usuário conectado, fabricante, modelo, número de série e versão da BIOS |

| Sistema operacional | Edição, versão, build, arquitetura, data de instalação e última inicialização |

| Processador | Nome, núcleos físicos, processadores lógicos e frequência máxima |

| Memória | Memória RAM total em GB |

| Discos | Unidade, nome do volume, sistema de arquivos, tamanho, espaço livre e espaço utilizado |

| Rede | Descrição do adaptador, IPv4, IPv6, endereço MAC, gateway e servidores DNS |

| BitLocker | Ponto de montagem, status do volume, método de criptografia, proteção e bloqueio |



A disponibilidade de algumas informações depende do sistema, das permissões e dos recursos instalados.



## Estrutura do módulo



```text

05-Computer-Inventory/

├── Computer-Inventory.ps1

├── Inventory-Functions.psm1

├── Inventory-Configuration.example.json

├── Inventory-Configuration.json

├── Test-ComputerInventory.ps1

└── Reports/

```



### Arquivos principais



- `Computer-Inventory.ps1`: script principal de execução.

- `Inventory-Functions.psm1`: funções responsáveis pela coleta e exportação.

- `Inventory-Configuration.example.json`: exemplo de configuração.

- `Inventory-Configuration.json`: configuração utilizada na execução local.

- `Test-ComputerInventory.ps1`: testes automatizados do módulo.

- `Reports/`: diretório padrão para os relatórios gerados.



## Configuração



O módulo utiliza um arquivo JSON para definir o comportamento do inventário.



Exemplo:



```json

{

&#x20; "SimulationMode": true,

&#x20; "Inventory": {

&#x20;   "ComputerSystem": true,

&#x20;   "OperatingSystem": true,

&#x20;   "Processor": true,

&#x20;   "Memory": true,

&#x20;   "Disk": true,

&#x20;   "Network": true,

&#x20;   "BitLocker": true

&#x20; },

&#x20; "Output": {

&#x20;   "Formats": [

&#x20;     "JSON",

&#x20;     "CSV"

&#x20;   ],

&#x20;   "Directory": "Reports"

&#x20; },

&#x20; "Disk": {

&#x20;   "IncludeFixedDrives": true,

&#x20;   "IncludeRemovableDrives": false

&#x20; },

&#x20; "Network": {

&#x20;   "IncludeIPv4": true,

&#x20;   "IncludeIPv6": false,

&#x20;   "IncludeMACAddress": true

&#x20; }

}

```



### Parâmetros de configuração



| Parâmetro | Descrição |

|---|---|

| `SimulationMode` | Ativa ou desativa a simulação |

| `Inventory` | Define as categorias que serão coletadas |

| `Output.Formats` | Define os formatos de exportação |

| `Output.Directory` | Define o diretório dos relatórios |

| `Disk.IncludeFixedDrives` | Inclui discos fixos |

| `Disk.IncludeRemovableDrives` | Inclui discos removíveis |

| `Network.IncludeIPv4` | Inclui endereços IPv4 |

| `Network.IncludeIPv6` | Inclui endereços IPv6 |

| `Network.IncludeMACAddress` | Inclui endereços MAC |



## Modo de simulação



Quando `SimulationMode` está definido como `true`:



- São utilizados dados fictícios.

- Não ocorre coleta real das informações do computador.

- O BitLocker não é consultado.

- Nenhum relatório é gravado.

- O resultado informa que a execução foi simulada.



Esse modo é indicado para demonstrações, testes e validação inicial.



## Execução



Abra o PowerShell na raiz do projeto e execute:



```powershell

.\05-Computer-Inventory\Computer-Inventory.ps1

```



O script verifica os arquivos necessários, carrega a configuração, executa a coleta, apresenta um resumo no terminal e realiza a exportação conforme os parâmetros definidos.



## Exportação de relatórios



Os formatos suportados são:



- **JSON:** preserva a estrutura do inventário, incluindo os objetos de cada categoria.

- **CSV:** consolida as informações em um registro tabular com 18 colunas.



Os arquivos são gerados com nome baseado no computador e na data e hora da execução.



Exemplo:



```text

ComputerInventory\_NOME-DO-COMPUTADOR\_2026-10-26\_105900.json

ComputerInventory\_NOME-DO-COMPUTADOR\_2026-10-26\_105900.csv

```



O diretório de saída pode ser relativo ao módulo ou um caminho absoluto.



## Testes automatizados



O módulo possui o script:



```powershell

.\05-Computer-Inventory\Test-ComputerInventory.ps1

```



Os testes verificam a existência dos arquivos, a validade da configuração, a coleta simulada, os dados fictícios, a exportação JSON e CSV, o uso de caminhos absolutos e o tratamento de diretórios inválidos.



Os testes de exportação utilizam dados fictícios e diretórios temporários, que são removidos ao final da execução.



### Resultado dos testes

| Indicador | Resultado |
|---|---:|
| Total de testes | 15 |
| Aprovados | 15 |
| Falharam | 0 |

**Status: aprovado.** Todos os testes automatizados foram concluídos com sucesso.


## Requisitos



- Windows com PowerShell.

- Permissões adequadas para consultar as informações do computador.

- Módulo `Get-BitLockerVolume` disponível para coleta de informações de BitLocker.

- Arquivos de configuração e módulo presentes no diretório do projeto.



## Segurança e privacidade



Os relatórios podem conter informações do ambiente, como nome do computador, usuário conectado, número de série, endereços de rede e dados de proteção de volumes.



Antes de compartilhar os relatórios, verifique se eles contêm informações que devem permanecer restritas ao ambiente corporativo.



Utilize o arquivo `Inventory-Configuration.example.json` como referência para preparar a configuração local.



## Projeto



Parte do projeto **PowerShell Automation**, voltado à automação de tarefas administrativas e de infraestrutura Windows.



Repositório: https://github.com/Adriano10Lacerda/PowerShell-Automation







