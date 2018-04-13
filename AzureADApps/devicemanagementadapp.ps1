<#

.PREREQUISITE
1. An Azure Active Directory tenant.
2. A Global Admin user within tenant.
3. Existing resource group with key-vault.
4. Application name, uri, reply url.
5. User principal name.

.PARAMETER WebApplicationName
Name of web application representing the key vault AD application.

.PARAMETER WebApplicationUri
App ID URI of web application.

.PARAMETER WebApplicationReplyUrl
Reply URL of web application. 

.PARAMETER userPrincipalName
The user principal name to be granted key vault permissions.

.PARAMETER resourceGroupName
The name of the resorce group.

.PARAMETER vaultName
The name of the key vault.

.EXAMPLE
. SetupKeyVaultApplications.ps1 -WebApplicationName 'myKeyVaultADApp' -WebApplicationUri 'http://myKeyVaultADApp' -WebApplicationReplyUrl 'http://myKeyVaultADApp' -userPrincipalName 'someuser@domain.com' -resourceGroupName 'someazureresourcegroup' -vaultName 'someazurekeyvault'

#>

Param
(
    [Parameter(ParameterSetName='Customize',Mandatory=$true)]	
	[String]
	$AdminPortalAppName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
	$AdminPortalAppUri,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $AdminPortalAppReplyUrl,

     [Parameter(ParameterSetName='Customize',Mandatory=$true)]	
	[String]
	$DeviceManagementAppName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
	$DeviceManagementAppUri,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $DeviceManagementAppReplyUrl,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
	$FanApiAppUri,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $userName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $password,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $subscriptionName
)

Install-Module -Name AzureADPreview -ErrorAction SilentlyContinue -Force 
Import-Module Azure -ErrorAction SilentlyContinue
Import-Module AzureRM.Resources

$AdminPortalAppName.Trim();
$AdminPortalAppUri.Trim();
$AdminPortalAppReplyUrl.Trim();
$DeviceManagementAppName.Trim();
$DeviceManagementAppUri.Trim();
$DeviceManagementAppReplyUrl.Trim();

Try
{
    $FilePath = Join-Path $PSScriptRoot "Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
    Add-Type -Path $FilePath
}
Catch
{
    Write-Warning $_.Exception.Message
}

Set-StrictMode -Version 3

$secpasswd = ConvertTo-SecureString $password -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($userName, $secpasswd)
Login-AzureRmAccount -Credential $mycreds -SubscriptionName $subscriptionName
$currentContext = Get-AzureRmContext

$TenantId = $currentContext.Subscription.TenantId

Connect-AzureAD -TenantId $TenantId -Credential $mycreds

$adAppCheck = Get-AzureRmADApplication -IdentifierUri $AdminPortalAppUri

If ($adAppCheck -ne $null)
{
   echo "The AD App $AdminPortalAppName already exists ! exiting now !"
   exit 
}

$DMadAppCheck = Get-AzureRmADApplication -IdentifierUri $DeviceManagementAppUri

If ($DMadAppCheck -ne $null)
{
   echo "The AD App $DeviceManagementAppName already exists ! exiting now !"
   exit 
}

function Create-AesManagedObject($key, $IV) {

    $aesManaged = New-Object "System.Security.Cryptography.AesManaged"
    $aesManaged.Mode = [System.Security.Cryptography.CipherMode]::CBC
    $aesManaged.Padding = [System.Security.Cryptography.PaddingMode]::Zeros
    $aesManaged.BlockSize = 128
    $aesManaged.KeySize = 256

    if ($IV) {
        if ($IV.getType().Name -eq "String") {
            $aesManaged.IV = [System.Convert]::FromBase64String($IV)
        }
        else {
            $aesManaged.IV = $IV
        }
    }

    if ($key) {
        if ($key.getType().Name -eq "String") {
            $aesManaged.Key = [System.Convert]::FromBase64String($key)
        }
        else {
            $aesManaged.Key = $key
        }
    }

    $aesManaged
}

function Create-AesKey() {
    $aesManaged = Create-AesManagedObject 
    $aesManaged.GenerateKey()
    [System.Convert]::ToBase64String($aesManaged.Key)
}


# New application for device management ------------------------------------------------------------------------------------------------------------------


$keyValueDM = Create-AesKey

echo $keyValueDM 

Write-Host ("##vso[task.setvariable variable=DMAppSecret;]$keyValueDM")
Write-Host "DynamicVariable: $env:DMAppSecret"

$psadCredentialDM = New-Object Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADPasswordCredential

$startDateDM = Get-Date

$psadCredentialDM.StartDate = $startDateDM

$psadCredentialDM.EndDate = $startDateDM.AddYears(1)

$psadCredentialDM.KeyId = [guid]::NewGuid()

$psadCredentialDM.Password = $KeyValueDM

New-AzureRmADApplication –DisplayName $DeviceManagementAppName -HomePage $DeviceManagementAppUri -IdentifierUris $DeviceManagementAppUri -PasswordCredentials $psadCredentialDM -ReplyUrls $DeviceManagementAppReplyUrl

$adapp = Get-AzureRmADApplication -IdentifierUri $DeviceManagementAppUri


New-AzureRmADServicePrincipal -ApplicationId $adapp.ApplicationId

Start-Sleep -Seconds 30

$authority = "https://login.microsoftonline.com/$TenantId"

function GetGraphAuthHeader() {

    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2"  # Set well-known client ID for AzurePowerShell
    $redirectUri = "urn:ietf:wg:oauth:2.0:oob" # Set redirect URI for Azure PowerShell
    $resourceAppIdURI = "https://graph.windows.net/" # resource we want to use
    # Create Authentication Context tied to Azure AD Tenant
    $authContext = New-Object "Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext" -ArgumentList $authority
    # Acquire token
    $authResult = $authContext.AcquireToken($resourceAppIdURI, $clientId, $redirectUri, "Auto")
    $authHeader = $authResult.CreateAuthorizationHeader()
    $headers = @{"Authorization" = $authHeader; "Content-Type"="application/json"}    
    return $headers
}

$adapp = Get-AzureRmADApplication -IdentifierUri $DeviceManagementAppUri

$headers = GetGraphAuthHeader 
$url = "https://graph.windows.net/$TenantId/applications/$($adapp.ObjectID)?api-version=1.6"
$postUpdate = "{`"appRoles`":[
    {
      `"allowedMemberTypes`": [
        `"User`"
      ],
      `"description`": `"Administrative access to the application`",
      `"displayName`": `"Administrator`",
      `"id`": `"{GUID / Object ID of administrator AD group in the tenant.}`",
      `"isEnabled`": true,
      `"value`": `"Admin`"
    },
    {
      `"allowedMemberTypes`": [
        `"User`"
      ],
      `"description`": `"Read only access to information`",
      `"displayName`": `"Readers`",
      `"id`": `"{GUID / Object ID of Readers AD group in the tenant.}`",
      `"isEnabled`": true,
      `"value`": `"ReadOnly`"
    }
  ]
}";
$updateResult = Invoke-RestMethod -Uri $url -Method "PATCH" -Headers $headers -Body $postUpdate        
echo $updateResult

$adapp = Get-AzureRmADApplication -IdentifierUri $DeviceManagementAppUri

$headers = GetGraphAuthHeader 
$url = "https://graph.windows.net/$TenantId/applications/$($adapp.ObjectID)?api-version=1.6"
$postUpdate = "{`"requiredResourceAccess`":[{`"resourceAppId`":`"00000002-0000-0000-c000-000000000000`",
`"resourceAccess`":[{`"id`":`"311a71cc-e848-46a1-bdf8-97ff7156d8e6`",`"type`":`"Scope`"}]}]}";
$updateResult = Invoke-RestMethod -Uri $url -Method "PATCH" -Headers $headers -Body $postUpdate        
echo $updateResult

$adapp = Get-AzureRmADApplication -IdentifierUri $DeviceManagementAppUri

$clientId = $adapp.ApplicationId

Write-Host ("##vso[task.setvariable variable=DMAppClientId;]$clientId")
Write-Host "DynamicVariable: $env:DMAppClientId"

 Set-AzureRmADApplication -ObjectId $adapp.ObjectID -DisplayName $DeviceManagementAppName -HomePage $DeviceManagementAppUri -IdentifierUris $DeviceManagementAppUri -ReplyUrls $DeviceManagementAppReplyUrl

<#New-AzureRmADServicePrincipal -ApplicationId $adapp.ApplicationId#>


# New application for admin portal ------------------------------------------------------------------------------------------------------------------


#Create the 44-character key value

$keyValueAP = Create-AesKey

echo $keyValueAP 

Write-Host ("##vso[task.setvariable variable=APAppSecret;]$keyValueAP")
Write-Host "DynamicVariable: $env:APAppSecret"

$psadCredentialAP = New-Object Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADPasswordCredential

$startDateAP = Get-Date

$psadCredentialAP.StartDate = $startDateAP

$psadCredentialAP.EndDate = $startDateAP.AddYears(1)

$psadCredentialAP.KeyId = [guid]::NewGuid()

$psadCredentialAP.Password = $KeyValueAP

New-AzureRmADApplication –DisplayName $AdminPortalAppName -HomePage $AdminPortalAppUri -IdentifierUris $AdminPortalAppUri -PasswordCredentials $psadCredentialAP -ReplyUrls $AdminPortalAppReplyUrl

$authority = "https://login.microsoftonline.com/$TenantId"


$adapp = Get-AzureRmADApplication -IdentifierUri $AdminPortalAppUri


New-AzureRmADServicePrincipal -ApplicationId $adapp.ApplicationId

Start-Sleep -Seconds 30

$headers = GetGraphAuthHeader 
$url = "https://graph.windows.net/$TenantId/applications/$($adapp.ObjectID)?api-version=1.6"
$postUpdate = "{`"appRoles`":[
  {
    `"allowedMemberTypes`": [
      `"User`"
    ],
    `"description`": `"Administrative access to the application`",
    `"displayName`": `"Administrator`",
    `"id`": `"{GUID / Object ID of administrator AD group in the tenant.}`",
    `"isEnabled`": true,
    `"value`": `"Admin`"
  },
  {
    `"allowedMemberTypes`": [
      `"User`"
    ],
    `"description`": `"Read only access to information`",
    `"displayName`": `"Readers`",
    `"id`": `"{GUID / Object ID of Readers AD group in the tenant.}`",
    `"isEnabled`": true,
    `"value`": `"ReadOnly`"
  }
  ]
}";
$updateResult = Invoke-RestMethod -Uri $url -Method "PATCH" -Headers $headers -Body $postUpdate        
echo $updateResult

$adapp = Get-AzureRmADApplication -IdentifierUri $AdminPortalAppUri
$dmapp = Get-AzureRmADApplication -IdentifierUri $DeviceManagementAppUri

$secpasswd = ConvertTo-SecureString $password -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($userName, $secpasswd)
Connect-AzureAD -TenantId $TenantId -Credential $mycreds

$permissions = Get-AzureADApplication -ObjectId $dmapp.ObjectId |  Select-Object -ExpandProperty Oauth2Permissions
$permissionId = $permissions.Id.ToString()

$fanApiApp = Get-AzureRmADApplication -IdentifierUri $FanApiAppUri
$permissionsFanApi = Get-AzureADApplication -ObjectId $fanApiApp.ObjectId |  Select-Object -ExpandProperty Oauth2Permissions
$permissionIdFanApi = $permissionsFanApi.Id.ToString()

$headers = GetGraphAuthHeader 
$url = "https://graph.windows.net/$TenantId/applications/$($adapp.ObjectID)?api-version=1.6"
$postUpdate = "{`"requiredResourceAccess`":[{`"resourceAppId`":`"00000002-0000-0000-c000-000000000000`",
`"resourceAccess`":[{`"id`":`"311a71cc-e848-46a1-bdf8-97ff7156d8e6`",`"type`":`"Scope`"}]},{`"resourceAppId`":`"$($dmapp.ApplicationId)`",
`"resourceAccess`":[{`"id`":`"$($permissionId)`",`"type`":`"Scope`"}]},{`"resourceAppId`":`"$($fanApiApp.ApplicationId)`",
`"resourceAccess`":[{`"id`":`"$($permissionIdFanApi)`",`"type`":`"Scope`"}]}]}";

$updateResult = Invoke-RestMethod -Uri $url -Method "PATCH" -Headers $headers -Body $postUpdate        
echo $updateResult

$adapp = Get-AzureRmADApplication -IdentifierUri $AdminPortalAppUri

$clientId = $adapp.ApplicationId

Write-Host ("##vso[task.setvariable variable=APAppClientId;]$clientId")
Write-Host "DynamicVariable: $env:APAppClientId"

Set-AzureRmADApplication -ObjectId $adapp.ObjectID -DisplayName $AdminPortalAppName -HomePage $AdminPortalAppUri -IdentifierUris $AdminPortalAppUri -ReplyUrls $AdminPortalAppReplyUrl
<#Set-AzureADApplication -ObjectId 048b083a-ab48-482c-8286-429b864d5cd1 -RequiredResourceAccess m#>