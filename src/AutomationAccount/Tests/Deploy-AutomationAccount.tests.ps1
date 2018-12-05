Describe 'Deploy AAA to Azure' {

    $SubscriptionName = ''
    $KeyVaultName = ''
    $ResourceGroupName = ''
    $AutomationAccountName = ''
    $Location= ''
    $ArmTemplateStagingStorageAccountName= ''

    $null = Set-AzureRmContext -SubscriptionName $SubscriptionName -ErrorAction Stop

    $AutomationAccountRootFolder = Split-Path -Path $PSScriptRoot -Parent -ErrorAction Stop
    $TempTestStoragePath = "$PSScriptRoot\tempteststorage"
    if (Test-Path -Path $TempTestStoragePath)
    {
        $null = Remove-Item -Path $TempTestStoragePath -Force -Recurse -ErrorAction Stop
    }
    $TempTestStorage = New-Item -Path $TempTestStoragePath -ItemType Directory -Force -ErrorAction Stop

    #Tokens
    $Tokens = @{
        '#{token1}#'='Value2'
    }

    #Tokanize Variables
    $TokanizedVariablesPath = New-Item -Path "$TempTestStoragePath\Variables" -ItemType Directory -Force -ErrorAction Stop
    Copy-Item -Path "$AutomationAccountRootFolder\Variables\variables.json" -Destination $TokanizedVariablesPath -ErrorAction Stop
    $Variables = Get-ChildItem -Path "$AutomationAccountRootFolder\Variables" -Filter 'variable_*.json'
    foreach ($var in $Variables)
    {
        $VarContent = Get-Content -Path $var.fullname -raw -ErrorAction Stop
        $tokens.Keys | foreach {
            $VarContent = $VarContent -replace $_,$tokens[$_]
        }
        Out-File -FilePath "$TokanizedVariablesPath\$($var.Name)" -InputObject $VarContent -Force -ErrorAction Stop
    }

    #Tokanize Connections
    $TokanizedConnectionsPath = New-Item -Path "$TempTestStoragePath\Connections" -ItemType Directory -Force -ErrorAction Stop
    $Connections = Get-ChildItem -Path "$AutomationAccountRootFolder\Connections" -Filter 'connection_*.json'
    foreach ($con in $Connections)
    {
        $ConContent = Get-Content -Path $con.fullname -raw -ErrorAction Stop
        $tokens.Keys | foreach {
            $ConContent = $ConContent -replace $_,$tokens[$_]
        }
        Out-File -FilePath "$TokanizedConnectionsPath\$($con.Name)" -InputObject $ConContent -Force -ErrorAction Stop
    }

    $TestParams = @{
        AutomationAccountName=$AutomationAccountName
        ResourceGroupName=$ResourceGroupName
        ArmTemplateStagingStorageAccountName=$ArmTemplateStagingStorageAccountName
        Location=$Location
        ConnectionsFolderPath=$TokanizedConnectionsPath.FullName
        VariablesFolderPath=$TokanizedVariablesPath.FullName
        RunbooksFolderPath="$AutomationAccountRootFolder\PowerShellRunbooks"
    }

    & "$AutomationAccountRootFolder\Templates\Deploy-AutomationAccount.ps1" @TestParams -ErrorAction Stop
}