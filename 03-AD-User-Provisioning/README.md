# AD User Provisioning

Módulo de automação desenvolvido em PowerShell para apoiar o processo de provisionamento de usuários em ambientes Active Directory.

O módulo foi projetado com foco em validação, padronização, tratamento de duplicidades e execução segura em modo de simulação.

---

## Objetivo

Automatizar e padronizar etapas relacionadas à criação de usuários no Active Directory, reduzindo atividades manuais e ajudando a evitar erros durante o processo de provisionamento.

O projeto utiliza uma arquitetura baseada em configuração, permitindo adaptar regras de nomenclatura e comportamento do provisionamento de acordo com diferentes ambientes.

---

## Funcionalidades

Atualmente o módulo possui:

- Validação da configuração do Active Directory
- Validação de conectividade com o Active Directory
- Geração automática de `SamAccountName`
- Remoção de acentos na geração do nome de usuário
- Suporte a diferentes formatos de nomenclatura
- Suporte a diferentes tipos de usuário
- Tratamento de `SamAccountName` duplicado
- Incremento automático para resolução de duplicidades
- Tratamento de nomes que excedem o limite configurado
- Geração de `UserPrincipalName (UPN)`
- Modo de simulação para testes
- Provisionamento preparado para integração com Active Directory real

---

## Estrutura

```text
03-AD-User-Provisioning
│
├── AD-Configuration.json
├── AD-Functions.psm1
├── Provision-ADUser.ps1
└── README.md
```

---

## AD-Configuration.json

Arquivo responsável pelas configurações utilizadas pelo módulo.

Entre as configurações disponíveis estão:

- Domínio
- Domain Controller
- Target OU
- Modo de simulação
- Regras de validação dos usuários
- Configuração do User Principal Name
- Tipos de usuário
- Regras de `SamAccountName`
- Tratamento de duplicidades
- Política para nomes longos

Exemplo:

```json
{
    "Domain": "BRSPO",
    "DomainController": "",
    "TargetOU": "",
    "SimulationMode": true,

    "UserValidation": {
        "FirstName": {
            "MinLength": 2
        },
        "LastName": {
            "MinLength": 2
        }
    },

    "UserPrincipalName": {
        "Enabled": true,
        "Domain": "example.local"
    }
}
```

> O domínio `example.local` utilizado nos exemplos é apenas um domínio de demonstração.

---

## AD-Functions.psm1

Módulo PowerShell responsável por concentrar as principais funções utilizadas no processo de provisionamento.

Principais funções:

```text
Test-ADConfiguration
Test-ADConnectivity
Test-ADUserExists
Test-ADUserProvisioning
Get-ADSamAccountName
Get-UniqueADSamAccountName
New-ADUserProvision
```

A separação das funções em um módulo permite organizar melhor o código e facilita sua reutilização em diferentes scripts e processos de automação.

---

## Provision-ADUser.ps1

Script principal responsável por executar o fluxo de provisionamento.

O processo inclui:

1. Carregamento da configuração
2. Validação da configuração
3. Validação da conectividade
4. Coleta dos dados do usuário
5. Seleção do tipo de usuário
6. Geração do `SamAccountName`
7. Validação de duplicidade
8. Geração do `UserPrincipalName`
9. Execução do provisionamento
10. Apresentação do resultado

---

## Modo de Simulação

O projeto possui um modo de simulação controlado pela configuração:

```json
"SimulationMode": true
```

Quando o modo de simulação está habilitado, nenhuma alteração é realizada no Active Directory.

O sistema executa o fluxo de provisionamento e apresenta o usuário que seria criado.

Exemplo:

```text
********** MODO DE SIMULAÇÃO **********

Consulta ao Active Directory não será realizada.
O sistema está executando em modo de simulação.

Usuário que seria criado:
Nome:              Maria Silva
SamAccountName:    silva.maria
UserPrincipalName: silva.maria@example.local
Tipo:              Employee
Domínio:           BRSPO

Nenhuma alteração foi realizada no Active Directory.
```

Esse modo permite testar as regras e o fluxo do sistema localmente antes de utilizar um ambiente Active Directory real.

---

## Tipos de Usuário

O módulo permite configurar diferentes tipos de usuários.

Exemplo:

```json
"UserTypes": {
    "Employee": {
        "Description": "Funcionário",
        "Format": "LastName.FirstName",
        "Suffix": ""
    },
    "Contractor": {
        "Description": "Terceiro",
        "Format": "LastName.FirstName",
        "Suffix": ".ext"
    },
    "Intern": {
        "Description": "Estagiário",
        "Format": "LastName.FirstName",
        "Suffix": ".est"
    }
}
```

A configuração permite adaptar o padrão de nomenclatura conforme o tipo de usuário.

---

## Geração do SamAccountName

O `SamAccountName` é gerado automaticamente utilizando as regras definidas em `AD-Configuration.json`.

O módulo suporta diferentes formatos de nomenclatura, incluindo:

```text
FirstName.LastName
LastName.FirstName
FirstNameLastName
LastNameFirstName
FirstInitial.LastName
```

Também é possível configurar:

- Remoção de acentos
- Sufixos
- Limite máximo de caracteres
- Política para nomes longos

Exemplo:

```text
Nome: Maria Silva
Tipo: Employee

SamAccountName:
silva.maria
```

Para um usuário do tipo `Contractor`:

```text
Nome: Maria Silva
Tipo: Contractor

SamAccountName:
silva.maria.ext
```

---

## Tratamento de Duplicidades

Quando um `SamAccountName` já existe, o módulo pode utilizar uma estratégia de incremento para encontrar um nome disponível.

Exemplo:

```text
silva.maria
silva.maria2
silva.maria3
```

A estratégia é configurável através da seção:

```json
"DuplicateHandling": {
    "Enabled": true,
    "Strategy": "Increment"
}
```

No modo de simulação, os nomes existentes utilizados para os testes são definidos em:

```json
"Simulation": {
    "ExistingSamAccountNames": [
        "silva.maria.ext",
        "silva.maria2.ext",
        "silva.maria3.ext"
    ]
}
```

Dessa forma, o comportamento de tratamento de duplicidades pode ser validado sem necessidade de conexão com um Active Directory real.

---

## Tratamento de Nomes Longos

O módulo possui uma política específica para situações em que o `SamAccountName` ultrapassa o limite configurado.

A configuração permite definir a estratégia utilizada para esses casos.

Exemplo:

```json
"LongNamePolicy": {
    "Enabled": true,
    "Strategy": "Manual"
}
```

Quando a estratégia `Manual` é utilizada, o sistema solicita ao operador um `SamAccountName` alternativo.

Isso permite evitar truncamentos automáticos que poderiam gerar nomes de usuário inesperados.

---

## User Principal Name (UPN)

Quando habilitado, o módulo gera automaticamente o `UserPrincipalName`.

Exemplo:

```text
SamAccountName:
silva.maria

UserPrincipalName:
silva.maria@example.local
```

O domínio utilizado para o UPN é definido na configuração:

```json
"UserPrincipalName": {
    "Enabled": true,
    "Domain": "example.local"
}
```

O domínio `example.local` utilizado no exemplo é apenas um domínio de demonstração.

---

## Validações

Antes da execução do provisionamento, o módulo realiza validações relacionadas a:

- Configuração do ambiente
- Domínio
- Nome e sobrenome
- Tamanho mínimo dos nomes
- `SamAccountName`
- Limite máximo de caracteres
- Caracteres permitidos
- Tipos de usuário
- Configuração do UPN
- Regras de duplicidade
- Política para nomes longos

Caso uma configuração obrigatória esteja incorreta, o processo é interrompido e o sistema apresenta a informação necessária para correção.

---

## Active Directory Real

O módulo possui estrutura preparada para execução em um ambiente Active Directory real.

Nesse cenário, devem ser configurados os parâmetros necessários, incluindo:

```json
"DomainController": "",
"TargetOU": ""
```

A execução real depende de:

- Ambiente Active Directory disponível
- Domain Controller acessível
- Permissões adequadas
- Configuração correta da OU de destino
- Módulo PowerShell do Active Directory disponível

Durante os testes locais, recomenda-se manter:

```json
"SimulationMode": true
```

---

## Segurança

O projeto foi desenvolvido com preocupação em evitar alterações acidentais durante a fase de desenvolvimento e testes.

O modo de simulação permite validar o comportamento do sistema sem realizar alterações no Active Directory.

Informações sensíveis, como credenciais e senhas, não devem ser armazenadas diretamente no código-fonte ou nos arquivos de configuração.

A implementação de credenciais, senhas e outros mecanismos de autenticação deverá utilizar mecanismos seguros nas futuras etapas do projeto.

---

## Tecnologias

- PowerShell
- Active Directory PowerShell Module
- JSON
- Git
- GitHub

---

## Status do Projeto

🚧 **Em desenvolvimento**

O módulo `AD User Provisioning` está sendo desenvolvido como parte do **PowerShell Automation Toolkit**, um projeto voltado para automação de tarefas de infraestrutura e administração de ambientes Microsoft.

Atualmente, o módulo possui um fluxo funcional em **modo de simulação**, permitindo validar regras de provisionamento antes da utilização em um ambiente Active Directory real.

---

## Próximos Passos

Possíveis evoluções do módulo:

- Provisionamento em ambiente Active Directory real
- Integração com Microsoft Entra ID
- Integração com Microsoft Graph
- Automação de grupos
- Automação de permissões
- Logs de execução
- Relatórios
- Interface para operação
- Melhorias de tratamento de erros
- Recursos adicionais de segurança

---

## Autor

**Adriano Felix Lacerda**

Projeto desenvolvido como parte do **PowerShell Automation Toolkit**.
