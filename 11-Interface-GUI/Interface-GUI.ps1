$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xamlXml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="PowerShell Automation | Control Center"
        Height="720" Width="1120"
        MinHeight="620" MinWidth="950"
        WindowStartupLocation="CenterScreen"
        Background="#F3F5F9"
        FontFamily="Segoe UI">
    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="235"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <Border Grid.Column="0" Background="#172033">
            <DockPanel LastChildFill="True">
                <StackPanel DockPanel.Dock="Top" Margin="22,28,18,20">
                    <TextBlock Text="PS AUTOMATION" Foreground="White"
                               FontSize="20" FontWeight="Bold"/>
                    <TextBlock Text="CONTROL CENTER" Foreground="#91A0BA"
                               FontSize="10" Margin="0,5,0,0"/>
                </StackPanel>

                <StackPanel DockPanel.Dock="Top" Margin="12,10,12,0">
                    <TextBlock Text="NAVEGAÇÃO" Foreground="#91A0BA"
                               FontSize="10" Margin="12,8,0,12"/>
                    <Button x:Name="btnHome" Content="  Visão geral"
                            Background="#2B3A55" Foreground="White"
                            BorderThickness="0" Padding="14,12"
                            HorizontalContentAlignment="Left" FontSize="14"/>
                    <Button x:Name="btnAD" Content="  Active Directory"
                            Background="Transparent" Foreground="#D7DEEA"
                            BorderThickness="0" Padding="14,12"
                            HorizontalContentAlignment="Left" FontSize="14"/>
                    <Button x:Name="btnEntra" Content="  Microsoft Entra ID"
                            Background="Transparent" Foreground="#D7DEEA"
                            BorderThickness="0" Padding="14,12"
                            HorizontalContentAlignment="Left" FontSize="14"/>
                    <Button x:Name="btnGPO" Content="  Políticas GPO"
                            Background="Transparent" Foreground="#D7DEEA"
                            BorderThickness="0" Padding="14,12"
                            HorizontalContentAlignment="Left" FontSize="14"/>
                    <Button x:Name="btnTests" Content="  Testes e validação"
                            Background="Transparent" Foreground="#D7DEEA"
                            BorderThickness="0" Padding="14,12"
                            HorizontalContentAlignment="Left" FontSize="14"/>
                </StackPanel>

                <Border DockPanel.Dock="Bottom" Background="#202C42"
                        Margin="12" Padding="12" CornerRadius="8">
                    <StackPanel>
                        <TextBlock Text="AMBIENTE DE EXECUÇÃO"
                                   Foreground="#91A0BA" FontSize="10"/>
                        <TextBlock Text="SIMULATION MODE"
                                   Foreground="#75D6A0" FontSize="13"
                                   FontWeight="Bold" Margin="0,7,0,0"/>
                        <TextBlock Text="Operações reais desabilitadas nesta tela"
                                   Foreground="#D7DEEA" FontSize="10"
                                   TextWrapping="Wrap" Margin="0,4,0,0"/>
                    </StackPanel>
                </Border>
            </DockPanel>
        </Border>

        <Grid Grid.Column="1" Margin="30">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <StackPanel Grid.Row="0" Margin="0,0,0,24">
                <TextBlock Text="Painel de automação"
                           FontSize="27" FontWeight="Bold"
                           Foreground="#172033"/>
                <TextBlock Text="Gerencie e valide seus módulos em um único lugar."
                           FontSize="13" Foreground="#65718A"
                           Margin="0,7,0,0"/>
            </StackPanel>

            <Border Grid.Row="1" Background="White" CornerRadius="10"
                    Padding="18" Margin="0,0,0,22">
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <StackPanel>
                        <TextBlock Text="STATUS DO PROJETO"
                                   Foreground="#65718A" FontSize="10"/>
                        <TextBlock Text="PowerShell Automation"
                                   Foreground="#172033" FontSize="18"
                                   FontWeight="SemiBold" Margin="0,5,0,0"/>
                        <TextBlock Text="Interface gráfica inicial"
                                   Foreground="#65718A" FontSize="12"
                                   Margin="0,4,0,0"/>
                    </StackPanel>
                    <Border Grid.Column="1" Background="#E0F7E9"
                            CornerRadius="6" Padding="12,8"
                            VerticalAlignment="Center">
                        <TextBlock Text="●  MODO SIMULAÇÃO"
                                   Foreground="#18794E" FontSize="11"
                                   FontWeight="Bold"/>
                    </Border>
                </Grid>
            </Border>

            <TextBlock Grid.Row="2" Text="MÓDULOS DISPONÍVEIS"
                       FontSize="11" FontWeight="Bold"
                       Foreground="#65718A" Margin="0,0,0,12"/>


<ScrollViewer Grid.Row="3"
              VerticalScrollBarVisibility="Auto"
              HorizontalScrollBarVisibility="Disabled">
    <StackPanel>
        <UniformGrid Columns="2">
            <Border Background="White" CornerRadius="10"
                    Margin="0,0,10,10" Padding="18"
                    MinHeight="175">
                <StackPanel>
                    <TextBlock Text="01  |  AD" Foreground="#4361EE"
                               FontSize="12" FontWeight="Bold"/>
                    <TextBlock Text="Active Directory"
                               Foreground="#172033" FontSize="17"
                               FontWeight="SemiBold" Margin="0,10,0,5"/>
                    <TextBlock Text="Provisionamento e administração de usuários."
                               Foreground="#65718A" FontSize="12"
                               TextWrapping="Wrap" Margin="0,0,0,16"/>
                    <Button x:Name="cardAD" Content="Abrir módulo"
                            Padding="10,7" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>

            <Border Background="White" CornerRadius="10"
                    Margin="0,0,0,10" Padding="18"
                    MinHeight="175">
                <StackPanel>
                    <TextBlock Text="02  |  ENTRA ID" Foreground="#4361EE"
                               FontSize="12" FontWeight="Bold"/>
                    <TextBlock Text="Microsoft Entra ID"
                               Foreground="#172033" FontSize="17"
                               FontWeight="SemiBold" Margin="0,10,0,5"/>
                    <TextBlock Text="Provisionamento de identidades na nuvem."
                               Foreground="#65718A" FontSize="12"
                               TextWrapping="Wrap" Margin="0,0,0,16"/>
                    <Button x:Name="cardEntra" Content="Abrir módulo"
                            Padding="10,7" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>

            <Border Background="White" CornerRadius="10"
                    Margin="0,0,10,10" Padding="18"
                    MinHeight="175">
                <StackPanel>
                    <TextBlock Text="03  |  GPO" Foreground="#4361EE"
                               FontSize="12" FontWeight="Bold"/>
                    <TextBlock Text="Políticas de grupo"
                               Foreground="#172033" FontSize="17"
                               FontWeight="SemiBold" Margin="0,10,0,5"/>
                    <TextBlock Text="Consulta e validação de políticas de domínio."
                               Foreground="#65718A" FontSize="12"
                               TextWrapping="Wrap" Margin="0,0,0,16"/>
                    <Button x:Name="cardGPO" Content="Abrir módulo"
                            Padding="10,7" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>

            <Border Background="White" CornerRadius="10"
                    Margin="0,0,0,10" Padding="18"
                    MinHeight="175">
                <StackPanel>
                    <TextBlock Text="04  |  QA" Foreground="#4361EE"
                               FontSize="12" FontWeight="Bold"/>
                    <TextBlock Text="Testes e validação"
                               Foreground="#172033" FontSize="17"
                               FontWeight="SemiBold" Margin="0,10,0,5"/>
                    <TextBlock Text="Área de preparação para testes automatizados."
                               Foreground="#65718A" FontSize="12"
                               TextWrapping="Wrap" Margin="0,0,0,16"/>
                    <Button x:Name="cardTests" Content="Ver módulo"
                            Padding="10,7" HorizontalAlignment="Left"/>
                </StackPanel>
            </Border>
        </UniformGrid>

        <Border Background="#E8EDF7" CornerRadius="8"
                Padding="15" Margin="0,4,0,10">
            <StackPanel>
                <TextBlock Text="ÁREA DE MENSAGENS"
                           Foreground="#344563" FontSize="11"
                           FontWeight="Bold"/>
                <TextBlock x:Name="StatusText"
           Text="Interface carregada. Nenhum módulo foi executado."
           Foreground="#344563" FontSize="12"
           TextWrapping="Wrap" Margin="0,7,0,10"/>

<WrapPanel Margin="0,0,0,10">
    <Button x:Name="btnADValidate" Content="Validar configuração AD"
            Padding="10,7" Margin="0,0,8,6"/>
    <Button x:Name="btnADConnectivity" Content="Testar conectividade AD"
            Padding="10,7" Margin="0,0,8,6"/>
</WrapPanel>
<WrapPanel Margin="0,0,0,10">
    <TextBlock Text="Login do usuário (sAMAccountName):" VerticalAlignment="Center"
               Margin="0,0,8,6" Foreground="#344563"/>
    <TextBox x:Name="txtADSamAccountName" Width="190"
             Padding="7,5" Margin="0,0,8,6"
             Text="silva.maria.ext"/>
    <Button x:Name="btnADUserExists" Content="Consultar usuário"
            Padding="10,7" Margin="0,0,8,6"/>
</WrapPanel>
<WrapPanel Margin="0,0,0,10">
    <Button x:Name="btnGPOList" Content="Listar GPOs"
            Padding="10,7" Margin="0,0,8,6"/>
    <Button x:Name="btnGPOCheck" Content="Consultar GPO"
            Padding="10,7" Margin="0,0,8,6"/>
    <Button x:Name="btnGPOLinks" Content="Consultar vínculos"
            Padding="10,7" Margin="0,0,8,6"/>
</WrapPanel>

<TextBox x:Name="OutputText"
         Height="190"
         IsReadOnly="True"
         AcceptsReturn="True"
         TextWrapping="NoWrap"
         VerticalScrollBarVisibility="Auto"
         HorizontalScrollBarVisibility="Auto"
         FontFamily="Consolas"
         FontSize="12"
         Padding="10"
         Background="#FFFFFF"
         Foreground="#172033"
         BorderBrush="#CBD5E1"
         Text="Os resultados das consultas aparecerão aqui."/>
            </StackPanel>
        </Border>
    </StackPanel>
</ScrollViewer>


            <TextBlock Grid.Row="4"
                       Text="PowerShell Automation  |  GUI V0.1  |  Ambiente seguro"
                       Foreground="#8A94A8" FontSize="10"
                       Margin="0,18,0,0"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = [System.Xml.XmlNodeReader]::new($xamlXml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$statusText = $window.FindName("StatusText")

$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) "07-GPO-Management\GPO-Configuration.json"
$moduloPath = Join-Path (Split-Path $PSScriptRoot -Parent) "07-GPO-Management\GPO-Functions.psm1"

$script:GuiGpoConfig = Get-Content $configPath -Raw | ConvertFrom-Json
if ($script:GuiGpoConfig.SimulationMode -ne $true) {
    throw "A interface GUI exige SimulationMode = true."
}

Import-Module $moduloPath -Force

$showModuleMessage = {
    param($moduleName)
    $statusText.Text = "Módulo selecionado: $moduleName. Integração funcional ainda não habilitada; nenhuma operação foi executada."
}

# Integração AD: consultas permitidas somente em modo de simulação.
$script:GuiADConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) "03-AD-User-Provisioning\AD-Configuration.json"
$script:GuiADModulePath = Join-Path (Split-Path $PSScriptRoot -Parent) "03-AD-User-Provisioning\AD-Functions.psm1"
$script:GuiADConfig = Get-Content $script:GuiADConfigPath -Raw | ConvertFrom-Json

if ($script:GuiADConfig.SimulationMode -ne $true) {
    throw "A interface GUI exige SimulationMode = true para operações AD."
}

Import-Module $script:GuiADModulePath -Force

function Invoke-GuiADAction {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Validar", "Conectividade", "ConsultarUsuario")]
        [string]$Acao
    )

    $output = $window.FindName("OutputText")
    $status = $window.FindName("StatusText")

    try {
        if ($script:GuiADConfig.SimulationMode -ne $true) {
            throw "Modo de simulação desativado. Operação cancelada."
        }

        switch ($Acao) {
            "Validar" {
                $resultado = Test-ADConfiguration -Configuration $script:GuiADConfig
                $texto = "Validação da configuração AD:`r`n" +
                    ($resultado | Format-List | Out-String -Width 120)
                $status.Text = "Validação da configuração AD concluída."
            }
            "Conectividade" {
                $resultado = Test-ADConnectivity -Configuration $script:GuiADConfig
                $texto = "Teste de conectividade AD (simulação):`r`n" +
                    ($resultado | Format-List | Out-String -Width 120)
                $status.Text = "Teste concluído em modo de simulação; nenhuma conexão real foi realizada."
            }
            "ConsultarUsuario" {
                $sam = $window.FindName("txtADSamAccountName").Text.Trim()

                if ([string]::IsNullOrWhiteSpace($sam)) {
                    throw "Informe um sAMAccountName para consultar."
                }

                $resultado = Test-ADUserExists `
                    -SamAccountName $sam `
                    -Configuration $script:GuiADConfig

                $texto = "Consulta simulada do usuário: $sam`r`n" +
                    ($resultado | Format-List | Out-String -Width 120)
                $status.Text = "Consulta de usuário simulada concluída."
            }
        }

        $output.Text = $texto.Trim()
    }
    catch {
        $status.Text = "Falha na operação AD."
        $output.Text = $_.Exception.Message
    }
}
$window.FindName("btnHome").Add_Click({
    $statusText.Text = "Visão geral. Interface carregada em modo visual."
})
$window.FindName("btnAD").Add_Click({ Invoke-GuiADAction -Acao "Validar" })
$window.FindName("cardAD").Add_Click({ Invoke-GuiADAction -Acao "Validar" })
$window.FindName("btnEntra").Add_Click({ & $showModuleMessage "Microsoft Entra ID" })
$window.FindName("cardEntra").Add_Click({ & $showModuleMessage "Microsoft Entra ID" })
# Ações GPO: todas as consultas usam a configuração em modo de simulação.
$script:GuiGpoConfig = Get-Content $configPath -Raw | ConvertFrom-Json
$script:GuiGpoOutput = $window.FindName("OutputText")
$script:GuiGpoStatus = $window.FindName("StatusText")

function Invoke-GuiGpoAction {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Listar", "Consultar", "Vinculos")]
        [string]$Acao
    )

    try {
        if ($script:GuiGpoConfig.SimulationMode -ne $true) {
            throw "Modo de simulação desativado. Operação cancelada."
        }

        switch ($Acao) {
            "Listar" {
                $dados = @(Get-GPOList -Configuration $script:GuiGpoConfig)
                $texto = $dados |
                    Format-Table Name, DisplayName, Description, Links, Simulation -Wrap -AutoSize |
                    Out-String -Width 160
                $script:GuiGpoStatus.Text = "Consulta concluída: GPOs simuladas."
            }
            "Consultar" {
                $dados = Test-GPOExists `
                    -GPOName "GPO-Desktop-Security" `
                    -Configuration $script:GuiGpoConfig
                $texto = $dados | Format-List | Out-String -Width 160
                $script:GuiGpoStatus.Text = "Consulta concluída: GPO-Desktop-Security."
            }
            "Vinculos" {
                $dados = @(Get-GPOLinks `
                    -GPOName "GPO-Desktop-Security" `
                    -Configuration $script:GuiGpoConfig)

                if ($dados.Count -gt 0) {
                    $texto = $dados |
                        Format-Table GPOName, Target, Simulation -Wrap -AutoSize |
                        Out-String -Width 160
                }
                else {
                    $texto = "Nenhum vínculo encontrado na simulação."
                }

                $script:GuiGpoStatus.Text = "Consulta de vínculos concluída."
            }
        }

        $script:GuiGpoOutput.Text = $texto.TrimEnd()
    }
    catch {
        $script:GuiGpoStatus.Text = "Falha na consulta GPO."
        $script:GuiGpoOutput.Text = $_.Exception.Message
    }
}

$window.FindName("btnGPO").Add_Click({
    Invoke-GuiGpoAction -Acao "Listar"
})
$window.FindName("cardGPO").Add_Click({
    Invoke-GuiGpoAction -Acao "Listar"
})
$window.FindName("btnADValidate").Add_Click({
    Invoke-GuiADAction -Acao "Validar"
})
$window.FindName("btnADConnectivity").Add_Click({
    Invoke-GuiADAction -Acao "Conectividade"
})
$window.FindName("btnADUserExists").Add_Click({
    Invoke-GuiADAction -Acao "ConsultarUsuario"
})
$window.FindName("btnGPOList").Add_Click({
    Invoke-GuiGpoAction -Acao "Listar"
})
$window.FindName("btnGPOCheck").Add_Click({
    Invoke-GuiGpoAction -Acao "Consultar"
})
$window.FindName("btnGPOLinks").Add_Click({
    Invoke-GuiGpoAction -Acao "Vinculos"
})
$window.FindName("btnTests").Add_Click({ & $showModuleMessage "Testes e validação" })
$window.FindName("cardTests").Add_Click({ & $showModuleMessage "Testes e validação" })

$null = $window.ShowDialog()
