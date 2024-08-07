#################################################
# HelloID-Conn-Prov-Target-Iloq-Update
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Get-IloqResolvedURL {
    [CmdletBinding()]
    param (
        [object]
        $config
    )
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add('Content-Type', 'application/json')
        $headers.Add('SessionId', $SessionId)

        $splatParams = @{
            Uri         = "$($config.BaseUrl)/api/v2/Url/GetUrl"
            Method      = 'POST'
            ContentType = 'application/json'
            Body        = @{
                'CustomerCode' = $($config.CustomerCode)
            }  | ConvertTo-Json
        }
        $resolvedUrl = Invoke-RestMethod @splatParams -Verbose:$false

        if ([string]::IsNullOrEmpty($resolvedUrl) ) {
            Write-Information "No Resolved - URL found, keep on using the URL provided: $($config.BaseUrl)."
        } else {
            Write-Information "Resolved - URL found [$resolvedUrl , Using the found url to execute the subsequent requests."
            $config.BaseUrl = $resolvedUrl
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Get-IloqSessionId {
    [CmdletBinding()]
    param (
        [object]
        $config
    )

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add('Content-Type', 'application/json')
        $params = @{
            Uri     = "$($config.BaseUrl)/api/v2/CreateSession"
            Method  = 'POST'
            Headers = $headers
            Body    = @{
                'CustomerCode' = $($config.CustomerCode)
                'UserName'     = $($config.UserName)
                'Password'     = $($config.Password)
            } | ConvertTo-Json
        }
        $response = Invoke-RestMethod @params -Verbose:$false
        Write-Output $response.SessionID
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}


function Get-IloqLockGroupId {
    [CmdletBinding()]
    param (
        [object]
        $config,

        [string]
        $SessionId
    )

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add('Content-Type', 'application/json')
        $headers.Add('SessionId', $SessionId)
        $params = @{
            Uri     = "$($config.BaseUrl)/api/v2/LockGroups"
            Method  = 'GET'
            Headers = $headers
        }
        $response = Invoke-RestMethod @params -Verbose:$false
        Write-Output $response.LockGroup_ID
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
function Set-IloqLockGroup {
    [CmdletBinding()]
    param (
        [object]
        $config,

        [string]
        $SessionId,

        [string]
        $LockGroupId
    )

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

        $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $headers.Add('Content-Type', 'application/json')
        $headers.Add('SessionId', $SessionId)
        $params = @{
            Uri     = "$($config.BaseUrl)/api/v2/SetLockGroup"
            Method  = 'POST'
            Headers = $headers
            Body    = @{
                'LockGroup_ID' = $LockGroupId
            } | ConvertTo-Json
        }
        $response = Invoke-RestMethod @params -Verbose:$false
        Write-Output $response.LockGroup_ID
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Confirm-IloqAccessKeyEndDate {
    [CmdletBinding()]
    param(
        [string]
        [Parameter(Mandatory)]
        $PersonId,

        [Parameter(Mandatory)]
        $Headers,

        [Parameter()]
        [AllowNull()]
        $EndDate
    )
    try {
        Write-Information 'Verifying if an iLOQ account has access keys assigned'
        $splatParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/Persons/$($PersonId)/Keys"
            Method      = 'GET'
            Headers     = $Headers
            ContentType = 'application/json; charset=utf-8'
        }
        $responseKeys = Invoke-RestMethod @splatParams -Verbose:$false

        if ($responseKeys.keys.Length -eq 0) {
            throw  "No Keys assigned to Person AccountReference: [$($PersonId)]"
        } else {
            Write-Information "Checking if the end date needs to be updated for the assigned access keys [$($responseKeys.Keys.Description -join ', ')]"
            foreach ($key in $responseKeys.Keys) {
                $splatIloqAccessKeyExpireDate = @{
                    Key     = $key
                    EndDate = $EndDate
                    Headers = $headers
                }
                Update-IloqAccessKeyExpireDate @splatIloqAccessKeyExpireDate

                $splatIloqAccessKeyTimeLimitSlot = @{
                    Key     = $key
                    EndDate = $EndDate
                    Headers = $headers
                }
                Update-IloqAccessKeyTimeLimitSlot @splatIloqAccessKeyTimeLimitSlot
            }
        }
    } catch {
        Write-Warning "Could not update AccessKey for person [$($PersonId)] Error: $($_)"
    }
}

function Update-ILOQAccessKeyExpireDate {
    [CmdletBinding()]
    param(
        [Parameter(mandatory)]
        $Key,

        [Parameter(mandatory)]
        [AllowNull()]
        $EndDate,

        [Parameter(mandatory)]
        $Headers
    )
    try {
        if (Confirm-UpdateRequiredExpireDate -NewEndDate $EndDate -CurrentEndDate $Key.ExpireDate) {
            Write-Information "ExpireDate of AccessKey [$($Key.Description)] not in sync. Updating ExpireDate"
            $Key.ExpireDate = $EndDate
            $bodyKey = @{
                Key = $Key
            } | ConvertTo-Json

            if (-not($actionContext.dryRun -eq $true)) {
                $splatParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/Keys"
                    Method      = 'PUT'
                    Headers     = $Headers
                    Body        = $bodyKey
                    ContentType = 'application/json; charset=utf-8'
                }
                $null = Invoke-RestMethod @splatParams -Verbose:$false
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
function Confirm-UpdateRequiredExpireDate {
    [CmdletBinding()]
    param(
        [Parameter()]
        $NewEndDate,

        [Parameter()]
        $CurrentEndDate
    )
    if (-not [string]::IsNullOrEmpty($NewEndDate)) {
        $_enddate = ([Datetime]$NewEndDate).ToShortDateString()
    }
    if (-not [string]::IsNullOrEmpty($CurrentEndDate)) {
        $_currentEnddate = ([Datetime]$CurrentEndDate).ToShortDateString()
    }
    if ($_currentEnddate -ne $_enddate) {
        Write-Output $true
    }
}

function Update-IloqAccessKeyTimeLimitSlot {
    [CmdletBinding()]
    param(
        [Parameter(mandatory)]
        $Key,

        [Parameter(mandatory)]
        [AllowNull()]
        $EndDate,

        [Parameter(mandatory)]
        $Headers
    )
    try {
        Write-Information "Get KeyTimeLimitSlots of Key $($Key.Description)"
        $splatParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/Keys/$($Key.FNKey_ID)/TimeLimitTitles?mode=0"
            Method  = 'GET'
            Headers = $Headers
        }
        $TimeLimitTitles = Invoke-RestMethod @splatParams -Verbose:$false
        $endDateObject = $TimeLimitTitles.KeyTimeLimitSlots | Where-Object { $_.slotNo -eq 1 }
        $currentEndDate = $null
        if ($null -ne $endDateObject ) {
            $currentEndDate = $endDateObject.LimitDateLg
        }
        if (Confirm-UpdateRequiredExpireDate -NewEndDate $EndDate -CurrentEndDate $currentEndDate) {
            Write-Information "EndDate Update required of AccessKey [$($Key.Description)]"
            Write-Information "Update TimeLimit of AccessKey: [$($Key.Description)]. New EndDate is [$($EndDate)]"

            # Retrieve the existing security accesses, Because updating Time Limits overwrites the existing accesses.
            $splatParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/v2/Keys/$($Key.FNKey_ID)/SecurityAccesses?mode=0"
                Method  = 'GET'
                Headers = $Headers
            }
            $currentSecurityAccesses = ([array](Invoke-RestMethod @splatParams -Verbose:$false).SecurityAccesses)

            $body = @{
                KeyScheduler                       = @{}
                OfflineExpirationSeconds           = 0
                OutsideUserZoneTimeLimitTitleSlots = @()
                SecurityAccessIds                  = @()
                TimeLimitSlots                     = @()
            }
            if ( $null -ne $currentSecurityAccesses.SecurityAccess_ID  ) {
                $body.SecurityAccessIds += $currentSecurityAccesses.SecurityAccess_ID
            }

            if (-not ([string]::IsNullOrEmpty($EndDate))) {
                $body.TimeLimitSlots += @{
                    LimitDateLg   = $EndDate
                    SlotNo        = 1
                    TimeLimitData = @()
                }
            }
            if ($actionContext.dryRun -eq $true) {
                Write-Warning "[DryRun] Update EndDate AccessKey: [$($Key.Description)] will be executed during enforcement"
                Write-Information "Current EndDate [$($Key.ExpireDate)] New EndDate: [$($EndDate)]"
            }
            if (-not($actionContext.dryRun -eq $true)) {
                $splatParams = @{
                    Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/Keys/$($Key.FNKey_ID)/SecurityAccesses"
                    Method      = 'PUT'
                    Headers     = $Headers
                    Body        = ($body | ConvertTo-Json -Depth 10)
                    ContentType = 'application/json; charset=utf-8'
                }
                $null = Invoke-RestMethod @splatParams -Verbose:$false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Action  = 'UpdateAccount'
                        Message = "Update end date AccessKey: [$($key.Description)] was successful"
                        IsError = $false
                    })
            }
        }
    } catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-IloqError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = ''
            FriendlyMessage  = ''
        }

        if ($null -eq $ErrorObject.Exception.Response) {
            $httpErrorObj.ErrorDetails = $ErrorObject.Exception.Message
            $httpErrorObj.FriendlyMessage = $ErrorObject.Exception.Message
        } else {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
            $httpErrorObj.FriendlyMessage = ($ErrorObject.ErrorDetails.Message | ConvertFrom-Json).Message
        }
        Write-Output $httpErrorObj
    }
}

#endregion

try {
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information "Verifying if a Iloq account for [$($personContext.Person.DisplayName)] exists"

    # First step is to get the correct url to use for the rest of the API calls.
    $null = Get-IloqResolvedURL -Config $actionContext.Configuration

    # Get the iLOQ sessionId
    $sessionId = Get-IloqSessionId -Config $actionContext.Configuration

    # Get the iLOQ lockGroupId
    $lockGroupId = Get-IloqLockGroupId -Config $actionContext.Configuration -SessionId $sessionId

    # Set the iLOQ lockGroup in order to make authenticated calls
    $null = Set-IloqLockGroup -Config $actionContext.Configuration -SessionId $sessionId -LockGroupId $lockGroupId

    $headers = [System.Collections.Generic.Dictionary[string, string]]::new()
    $headers.Add('Content-Type', 'application/json; charset=utf-8')
    $headers.Add('SessionId', $sessionId)

    try {
        $splatParams = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/Persons/$($actionContext.References.Account)"
            Method      = 'GET'
            Headers     = $headers
            ContentType = 'application/json; charset=utf-8'
        }
        $correlatedAccount = Invoke-RestMethod @splatParams -Verbose:$false
        $outputContext.PreviousData = $correlatedAccount.PsObject.Copy()

        if ($outputContext.PreviousData.ExternalCanEdit -eq $true)
        {
            $outputContext.PreviousData |  Add-Member -Force -MemberType NoteProperty  -Name "ExternalCanEdit" -Value  "true"
        } else {
            $outputContext.PreviousData |  Add-Member -Force -MemberType NoteProperty  -Name "ExternalCanEdit" -Value  "false"
        }
        if ($null -eq $outputContext.PreviousData.EmploymentEndDate)
        {
            $outputContext.PreviousData |  Add-Member -Force -MemberType NoteProperty  -Name "EmploymentEndDate" -Value  ''
        }
    } catch {
        if ($_.Errordetails.message -match 'Invalid value') {
            $correlatedAccount = $null
        } else{
            throw $_
        }
    }



    # Always compare the account against the current account in target system

    $actionList = [System.Collections.Generic.list[object]]::new()
    if ($null -ne $correlatedAccount) {

        $actionList += 'Confirm-IloqAccessKeyEndDate'
        $splatCompareProperties = @{
            ReferenceObject  = @(($($outputContext.PreviousData) | Select-Object * -ExcludeProperty State).PSObject.Properties)
            DifferenceObject =  @((([PSCustomObject]$actionContext.Data)| Select-Object * -ExcludeProperty State).PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { ($_.SideIndicator -eq '=>')  }
        if ($propertiesChanged) {
            $actionList += 'UpdateAccount'
            $dryRunMessage = "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"
        } else {
            $actionList += 'NoChanges'
            $dryRunMessage = 'No changes will be made to the account during enforcement'
        }
    } else {
        $actionList += 'NotFound'
        $dryRunMessage = "Iloq account for: [$($personContext.Person.DisplayName)] not found. Possibly deleted."
    }

    # Add a message and the result of each of the validations showing what will happen during enforcement
    if ($actionContext.DryRun -eq $true) {
        Write-Information "[DryRun] $dryRunMessage"
    }

    # Process
    foreach ($action in $actionList) {
        switch ($action) {
            'Confirm-IloqAccessKeyEndDate'{
                # Keeping the end date of the access key in sync is a separate process that does not update the person itself, but only the assigned access keys.
                # Therefore, this is encapsulated in a single function with its own dry-run and audit logging. When an exception occurs, only a warning is shown,
                # so it does not disrupt the account update process.
                $splatConfirmIloqAccessKey = @{
                    PersonId = $actionContext.References.Account
                    Headers  = $headers
                    Enddate  = $actionContext.Data.EmploymentEndDate
                }
                $null = Confirm-IloqAccessKeyEndDate @splatConfirmIloqAccessKey
                break;
            }
            'UpdateAccount' {
                Write-Information "Updating Iloq account with accountReference: [$($actionContext.References.Account)]"

                if (-not($actionContext.DryRun -eq $true)) {

                    # currently HellID does not support the configuration of boolean fields in the interfase
                        # so conversion to boolean from text is required here for the relevant variables
                    [bool] $externalCanEdit = $false
                    if ($actionContext.Data.ExternalCanEdit -eq "true") {
                        $externalCanEdit = $true
                    }
                    $actionContext.Data |  Add-Member -Force -MemberType NoteProperty  -Name "ExternalCanEdit" -Value  $ExternalCanEdit

                    $account = [PSCustomObject]@{
                        Person = [PSCustomObject]$actionContext.Data
                    }
                    $account.Person |  Add-Member -MemberType NoteProperty  -Name "Person_ID" -Value  $actionContext.References.Account
                    [bool] $externalCanEdit = $false
                    if ($actionContext.Data.ExternalCanEdit -eq "true") {
                        $externalCanEdit = $true
                    }
                    $account.Person |  Add-Member -Force -MemberType NoteProperty  -Name "ExternalCanEdit" -Value  $externalCanEdit

                    $body = $account
                    $splatParams = @{
                        Uri         = "$($actionContext.Configuration.BaseUrl)/api/v2/Persons"
                        Method      = 'PUT'
                        Headers     = $headers
                        Body        = $body | ConvertTo-Json
                        ContentType = 'application/json; charset=utf-8'
                    }

                    $null = Invoke-RestMethod @splatParams -Verbose:$false
                }

                # Make sure to test with special characters and if needed; add utf8 encoding.

                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                        IsError = $false
                    })
                break
            }
            'NoChanges' {
                Write-Information "No changes to Iloq account with accountReference: [$($actionContext.References.Account)]"
                $outputContext.Success = $true
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = 'No changes will be made to the account during enforcement'
                        IsError = $false
                    })
                break
            }
            'NotFound' {
                $outputContext.Success = $false
                $outputContext.AuditLogs.Add([PSCustomObject]@{
                        Message = "Iloq account with accountReference: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted, or the account is not correlated"
                        IsError = $true
                    })
                break
            }
        }
    }
} catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-IloqError -ErrorObject $ex
        $auditMessage = "Could not update Iloq account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not update Iloq account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}
