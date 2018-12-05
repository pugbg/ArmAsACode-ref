[cmdletbinding()]
param
(
    #WebHookUri
    [Parameter(Mandatory = $false)]
    [string]$WebHookUri = ''
)

process
{
    #Start Job
    try
    {
        $StartJobParams = @{
            Uri     = $WebHookUri
            Method  = 'POST'
            Body    = (@{
                    Parameters = @{}
                } | ConvertTo-Json -Compress -ErrorAction Stop)
            headers = @{
                'content-type' = 'application/json'
            }
        }

        $Response2 = Invoke-WebRequest @StartJobParams -ErrorAction Stop
    }
    catch
    {
        Write-Error "Start Job failed. Details: $_" -ErrorAction Stop
    }

}