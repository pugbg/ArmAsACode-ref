[cmdletbinding()]
param
(
    #ClientId
    [Parameter(Mandatory=$false)]
    [string]$ClientId = '',

    #ClientSecret
    [Parameter(Mandatory=$false)]
    [string]$ClientSecret = '',

    #TenantId
    [Parameter(Mandatory=$false)]
    [string]$TenantId = '',
    
    #SubscriptionId
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId = '',

    #AAResourceGroupName
    [Parameter(Mandatory=$false)]
    [string]$AAResourceGroupName = '',

    #AAautomationAccountName
    [Parameter(Mandatory=$false)]
    [string]$AAautomationAccountName = '',

    #AARunbookName
    [Parameter(Mandatory=$false)]
    [string]$AARunbookName = ''
)

process
{
    #Authenticate
    try
    {
        $UrlParameters = @{
            'grant_type'    = 'client_credentials'
            'resource'      = 'https://management.core.windows.net/'
            'client_id'     = $ClientID
            'client_secret' = $ClientSecret
        }
        $UrlParametersAsString = new-object -TypeName System.Collections.ArrayList -ErrorAction Stop
        foreach ($k in $UrlParameters.Keys)
        {
            $UrlParametersAsString.add("$([System.Web.HttpUtility]::UrlEncode($k))=$([System.Web.HttpUtility]::UrlEncode($UrlParameters[$k]))")
        }

        $InvokeWebRequestBody = @{
            Uri    = "https://login.microsoftonline.com/$TenantId/oauth2/token"
            Method = 'Post'
            Headers = @{
                'content-type' = 'application/x-www-form-urlencoded'
            }
            body=$UrlParametersAsString -join '&'
        }

        $Response = Invoke-WebRequest @InvokeWebRequestBody -ErrorAction Stop
        $responseContent = $Response.Content | ConvertFrom-Json
        $token = $responseContent.access_token
    }
    catch
    {
        Write-Error "Autneticate failed. Details: $_" -ErrorAction Stop
    }

    #Start Job
    try
    {
        $StartJobParams = @{
            Uri="https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$AAResourceGroupName/providers/Microsoft.Automation/automationAccounts/$AAautomationAccountName/jobs/$((New-Guid).Guid)?api-version=2017-05-15-preview"
            Method='PUT'
            Body=(@{
                properties=@{
                    runbook=@{
                        Name=$AARunbookName
                    }
                }
            } | ConvertTo-Json -Compress -ErrorAction Stop)
            headers=@{
                Authorization="Bearer $token"
                'content-type'='application/json'
            }
        }

        $Response2 = Invoke-WebRequest @StartJobParams -ErrorAction Stop
    }
    catch
    {
        Write-Error "Start Job failed. Details: $_" -ErrorAction Stop
    }

}
