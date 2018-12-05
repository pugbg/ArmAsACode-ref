<#PSScriptInfo

.VERSION 1.0.0.0

.GUID 7f69fd96-5bec-4c60-9352-d7d3d1713b3c

.AUTHOR example@contoso.com

.COMPANYNAME 

.COPYRIGHT 

.TAGS 

.LICENSEURI 

.PROJECTURI 

.ICONURI 

.EXTERNALMODULEDEPENDENCIES 

.REQUIREDSCRIPTS 

.EXTERNALSCRIPTDEPENDENCIES 

.RELEASENOTES

#>

<# 

.DESCRIPTION 

This script should be used to create and update the Azure Automation Account used for CountryHosting subscription provisioning

#> 

[CmdletBinding()]
param
(
    #AutomationAccountName
    [Parameter(Mandatory = $true)]
    [string]$AutomationAccountName,

    #ResourceGroupName
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,
      
    #ArmTemplateStagingStorageAccountName
    [Parameter(Mandatory = $true)]
    [string]$ArmTemplateStagingStorageAccountName,

    #Location
    [Parameter(Mandatory = $true)]
    [string]$Location,

    #ConnectionsFolderPath
    [Parameter(Mandatory = $false)]
    [string[]]$ConnectionsFolderPath,

    #VariablesFolderPath
    [Parameter(Mandatory = $false)]
    [string[]]$VariablesFolderPath,

    #RunbooksFolderPath
    [Parameter(Mandatory = $false)]
    [string[]]$RunbooksFolderPath,

    #WebhooksFolderPath
    [Parameter(Mandatory = $false)]
    [string[]]$WebhooksFolderPath
)

begin
{
    $TempArmTemplateParameterFile = "$PSScriptRoot\tempArmTemplateParameters.json"
    $StagingStorageAccount_ContainerName = 'armtemplatestagingarea'
    $ArmTempalteStagingItemsDurationInMinutes = 30
}

process
{
    try
    {
        #Ensure ArmTemplateStaging StorageAccount
        try
        {
            Write-Information "Ensure ArmTemplateStaging StorageAccount started" -InformationAction Continue
            $StagingStorageAccount = Get-AzureRmStorageAccount -Name $ArmTemplateStagingStorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue | Where-Object {$_.Location -eq $Location}
            if ($StagingStorageAccount)
            {
                Write-Information "Ensure ArmTemplateStaging StorageAccount in progress. StorageAccount: $ArmTemplateStagingStorageAccountName already exists" -InformationAction Continue 
            }
            else
            {
                Write-Information "Ensure ArmTemplateStaging StorageAccount in progress. Creating StorageAccount: $ArmTemplateStagingStorageAccountName" -InformationAction Continue 
                $NewAzureRmStorageAccount_Params = @{
                    Name              = $ArmTemplateStagingStorageAccountName
                    ResourceGroupName = $ResourceGroupName
                    Location          = $Location
                    AccessTier        = 'Hot'
                    SkuName           = 'Standard_RAGRS'
                    Kind              = 'StorageV2'
                }
                $StagingStorageAccount = New-AzureRmStorageAccount @NewAzureRmStorageAccount_Params -ErrorAction Stop
            }

            $StagingStorageAccount_ContainerExists = Get-AzureStorageContainer -Name $StagingStorageAccount_ContainerName -Context $StagingStorageAccount.Context -ErrorAction SilentlyContinue
            if ($StagingStorageAccount_ContainerExists)
            {
                Write-Information "Ensure ArmTemplateStaging StorageAccount in progress. Removing StorageAccountContainer: $StagingStorageAccount_ContainerName" -InformationAction Continue 
                $null = Remove-AzureStorageContainer -Name $StagingStorageAccount_ContainerName -Context $StagingStorageAccount.Context -Force -ErrorAction SilentlyContinue
            }
            Write-Information "Ensure ArmTemplateStaging StorageAccount in progress. Creating StorageAccountContainer: $StagingStorageAccount_ContainerName" -InformationAction Continue 
            $StagingStorageAccount_Container = New-AzureStorageContainer -Name $StagingStorageAccount_ContainerName -Context $StagingStorageAccount.Context -ErrorAction Stop

            Write-Information "Ensure ArmTemplateStaging StorageAccount completed" -InformationAction Continue
        }
        catch
        {
            Write-Error "Ensure ArmTemplateStaging StorageAccount failed. Details: $_" -ErrorAction Stop
        }

        $ArmTemplateParameters = @{
            '$schema'      = 'https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#'
            contentVersion = '1.0.0.0'
            parameters     = @{
                accountName = @{
                    value = $AutomationAccountName
                }
            }
        }

        if ($PSBoundParameters.ContainsKey('Location'))
        {
            $ArmTemplateParameters['parameters'].Add('Location', @{value = $Location})
        }

        #Add Connections to ArmTemplate
        try
        {
            Write-Information "Add Connections to ArmTemplate started" -InformationAction Continue
            if (-not $ConnectionsFolderPath)
            {
                $ConnectionsFolderPath = Split-Path -Path $PSScriptRoot -Parent -ErrorAction Stop | Join-Path -ChildPath 'Connections'
            }

            $Connections = new-object -TypeName System.Collections.ArrayList -ErrorAction Stop
            foreach ($CFP in $ConnectionsFolderPath)
            {
                Get-ChildItem -Path $CFP -Filter *.json -File -ErrorAction Stop | foreach {
                    Write-Information "Add Connections to ArmTemplate in progress. Adding $($_.BaseName)" -InformationAction Continue
                    $Connection = get-content -Path $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                    $Null = $Connections.Add($Connection)
                }
            }
            if ($Connections.Count -gt 0)
            {
                $null = $ArmTemplateParameters['parameters'].Add('connections', @{value = $Connections})
            }
            Write-Information "Add Connections to ArmTemplate completed" -InformationAction Continue
        }
        catch
        {
            Write-Error "Add Connections to ArmTemplate failed. Details: $_" -ErrorAction Stop
        }

        #Add Variables to ArmTemplate
        try
        {
            Write-Information "Add Variables to ArmTemplate started" -InformationAction Continue
            if (-not $VariablesFolderPath)
            {
                $VariablesFolderPath = Split-Path -Path $PSScriptRoot -Parent -ErrorAction Stop | Join-Path -ChildPath 'Variables'
            }
            $Variables = new-object -TypeName System.Collections.ArrayList -ErrorAction Stop
            foreach ($VFP in $VariablesFolderPath)
            {
                remove-variable -Name VariableDefinitionPath -ErrorAction SilentlyContinue
                $VariablesDefinitionFilePath = Join-Path -Path $VFP -ChildPath 'variables.json' -Resolve -ErrorAction Stop
                $VariablesDefinition = get-content -Path $VariablesDefinitionFilePath -raw | ConvertFrom-Json -ErrorAction Stop
                foreach ($variableName in $VariablesDefinition.psobject.Properties.Name)
                {
                    Write-Information "Add Variables to ArmTemplate in progress. Adding $variableName" -InformationAction Continue
                    
                    #Retrieve Variable Value
                    Remove-variable -name VariableValueFilePath -ErrorAction SilentlyContinue
                    $VariableValueFilePath = Join-Path -Path $VFP -ChildPath $VariablesDefinition."$variableName".ValueFileName -Resolve -ErrorAction Stop


                    $Null = $Variables.Add([pscustomobject]@{
                            Name        = $variableName
                            Description = $VariablesDefinition."$variableName".Description
                            IsEncrypted = $VariablesDefinition."$variableName".IsEncrypted
                            Value       = ((get-content -Path $VariableValueFilePath -raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop) | ConvertTo-Json -Depth 10 -Compress -ErrorAction Stop | convertto-json -ErrorAction Stop)
                        })
                }
            }
            if ($Variables.Count -gt 0)
            {
                $null = $ArmTemplateParameters['parameters'].Add('variables', @{value = $Variables})
            }
            Write-Information "Add Variables to ArmTemplate completed" -InformationAction Continue
        }
        catch
        {
            Write-Error "Add Variables to ArmTemplate failed. Details: $_" -ErrorAction Stop
        }

        #Add Runbooks to ArmTemplate
        try
        {
            Write-Information "Add Runbooks to ArmTemplate started" -InformationAction Continue
            if (-not $RunbooksFolderPath)
            {
                $RunbooksFolderPath = Split-Path -Path $PSScriptRoot -Parent -ErrorAction Stop | Join-Path -ChildPath 'PowerShellRunbooks'
            }
            $Runbooks = new-object -TypeName System.Collections.ArrayList -ErrorAction Stop
            foreach ($RFP in $RunbooksFolderPath)
            {
                Get-ChildItem -Path $RFP -Filter *.ps1 -File -ErrorAction Stop | foreach {
                    Write-Information "Add Runbooks to ArmTemplate in progress. Adding $($_.BaseName)" -InformationAction Continue
                        
                    #Upload Runbook to the Staging ArmTemplate StorageAccount
                    $RunbookMetadata = Test-ScriptFileInfo -Path $_.FullName -ErrorAction Stop
                    $RunbookFile = Set-AzureStorageBlobContent -Context $StagingStorageAccount.Context -File $_.FullName -Container $StagingStorageAccount_ContainerName -ErrorAction Stop
                    $NewAzureStorageblobSASToken_Params = @{
                        Blob       = $RunbookFile.Name
                        Context    = $StagingStorageAccount_Container.Context
                        container  = $StagingStorageAccount_Container.Name
                        Permission = 'r'
                        StartTime  = (get-date)
                        ExpiryTime = (get-date).AddMinutes($ArmTempalteStagingItemsDurationInMinutes)
                        Protocol   = 'HttpsOnly'
                        FullUri    = $true
                    }
                    $RunbookFileAccessUri = New-AzureStorageblobSASToken @NewAzureStorageblobSASToken_Params -ErrorAction Stop

                    $Null = $Runbooks.Add(@{
                            Name               = $_.BaseName
                            logVerbose         = $false
                            logProgress        = $true
                            runbookType        = "PowerShell"
                            publishContentLink = @{
                                uri     = $RunbookFileAccessUri
                                version = $RunbookMetadata.Version
                            }
                            description        = $RunbookMetadata.Description
                        })
                }
            }
            if ($Runbooks.Count -gt 0)
            {
                $null = $ArmTemplateParameters['parameters'].Add('Runbooks', @{value = $Runbooks})
            }
            Write-Information "Add Runbooks to ArmTemplate completed" -InformationAction Continue
        }
        catch
        {
            Write-Error "Add Runbooks to ArmTemplate failed. Details: $_" -ErrorAction Stop
        }

        #Deploy ArmTemplate
        try
        {
            Write-Information "Deploy ArmTemplate started" -InformationAction Continue
            
            $ArmTemplateParameters | ConvertTo-Json -Depth 50 -ErrorAction Stop | Out-File -FilePath $TempArmTemplateParameterFile -Force -ErrorAction Stop
            $NewAzureRmResourceGroupDeployment_Params += @{
                ResourceGroupName     = $ResourceGroupName
                TemplateFile          = (Join-Path -Path $PSScriptRoot -ChildPath 'AutomationAccount.json')
                TemplateParameterFile = $TempArmTemplateParameterFile
            }
            $deployment = New-AzureRmResourceGroupDeployment @NewAzureRmResourceGroupDeployment_Params -ErrorAction Stop
            
            Write-Information "Deploy ArmTemplate completed" -InformationAction Continue
        }
        catch
        {
            Write-Error "Deploy ArmTemplate failed. Details: $_" -ErrorAction Stop
        }

        #Deploy Webhooks
        try
        {
            Write-Information "Deploy Webhooks started" -InformationAction Continue

            if (-not $WebhooksFolderPath)
            {
                $WebhooksFolderPath = Split-Path -Path $PSScriptRoot -Parent -ErrorAction Stop | Join-Path -ChildPath 'Webhooks'
            }
            foreach ($WHFP in $WebhooksFolderPath)
            {
                remove-variable -Name WebhookDefinitions -ErrorAction SilentlyContinue
                $WebhookDefinitions = Get-ChildItem -Path $WHFP -Filter 'webhook_*.json' -ErrorAction Stop | foreach {
                    Get-Content -Path $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                }
                foreach ($WHDef in $WebhookDefinitions)
                {
                    Write-Information "Deploy Webhooks in progress. Processing: $($WHDef.Name)" -InformationAction Continue
                    
                    Remove-Variable -Name Webhook -ErrorAction SilentlyContinue

                    $Webhook = Get-AzureRmAutomationWebhook -Name $WHDef.Name -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ErrorAction SilentlyContinue
                    if (-not $webhook -or ($Webhook -and $Webhook.ExpiryTime -lt (get-date)))
                    {
                        if ($Webhook -and $Webhook.ExpiryTime -lt (get-date))
                        {
                            Write-Information "Deploy Webhooks in progress. Updating $($WHDef.Name), expired. Removing it." -InformationAction Continue
                            $null = Remove-AzureRmAutomationWebhook -Name $WHDef.Name -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -ErrorAction Stop
                        }

                        Write-Information "Deploy Webhooks in progress. Creating $($WHDef.Name)" -InformationAction Continue
                        $Webhook = New-AzureRmAutomationWebhook -Name $WHDef.Name -RunbookName $WHDef.runbookName -IsEnabled $true -ExpiryTime (get-date).AddMonths($WHDef.ValidityInMonths) -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Force -ErrorAction Stop
                        $null = Set-AzureKeyVaultSecret -VaultName $WHDef.UriSecredKeyVaultName -Name $WHDef.UriSecredName -SecretValue (ConvertTo-SecureString -AsPlainText -Force -String $webhook.WebhookURI) -Expires $Webhook.ExpiryTime.Date -ErrorAction Stop
                    }
                    else 
                    {
                        Write-Information "Deploy Webhooks in progress. Skipping $($WHDef.Name), already exists." -InformationAction Continue
                    }
                }
            }

            Write-Information "Deploy Webhooks completed" -InformationAction Continue
        }
        catch
        {
            Write-Error "Deploy Webhooks failed. Details: $_" -ErrorAction Stop
        }
    }
    finally
    {
        #Cleanup
        try
        {
            Write-Information "Cleanup started" -InformationAction Continue
            if ($StagingStorageAccount_Container)
            {
                Write-Information "Cleanup in progress. Removing StorageAccountContainer: $($StagingStorageAccount_Container.Name)" -InformationAction Continue
                Remove-AzureStorageContainer -Name $StagingStorageAccount_Container.Name -Context $StagingStorageAccount_Container.Context -Force -ErrorAction Stop
            }
            if (test-path -Path $TempArmTemplateParameterFile)
            {
                Write-Information "Cleanup in progress. Removing TempArmTemplateParameterFile: $TempArmTemplateParameterFile" -InformationAction Continue
                $null = Remove-item -Path $TempArmTemplateParameterFile -Force -ErrorAction Stop
            }
            Write-Information "Cleanup completed" -InformationAction Continue
        }
        catch
        {
            Write-Error "Cleanup failed. Details: $_" -ErrorAction Stop
        }

    }
}
