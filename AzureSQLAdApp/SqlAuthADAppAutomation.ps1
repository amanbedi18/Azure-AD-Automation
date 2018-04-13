<#

.PREREQUISITE
1. An Azure Active Directory tenant.
2. A Global Admin user within tenant.
3. Application name, uri, reply url.

.PARAMETER AmsADAppName
Name of web application representing the key vault AD application.

.PARAMETER AmsADAppUri
App ID URI of web application.

.PARAMETER AmsADAppReplyUrl
Reply URL of web application. 

.PARAMETER userName
The user for portal.

.PARAMETER password
Portal password.

#>

Param
(
    [Parameter(ParameterSetName='Customize',Mandatory=$true)]	
	[String]
	$SqlADAppName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
	$SqlADAppUri,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $SqlADAppReplyUrl,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $SqlResourceGroupName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $SqlServerName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $SqlADGroupName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $userName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $password,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $subscriptionName,

    [Parameter(ParameterSetName='Customize',Mandatory=$false)]
	[switch]
    $drSqlServer
)

<#
Install-Module -Name AzureADPreview -ErrorAction SilentlyContinue -Force 
Import-Module Azure -ErrorAction SilentlyContinue
Import-Module AzureRM.Resources
#>
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
<#
Connect-AzureAD -TenantId $TenantId -Credential $mycreds
#>

$adAppCheck = Get-AzureRmADApplication -IdentifierUri $SqlADAppUri

If ($adAppCheck -ne $null)
{
   echo "The AD App $SqlADAppName already exists ! exiting now !"
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


$secretKey = Create-AesKey

echo $secretKey 

Write-Host ("##vso[task.setvariable variable=SqlADSecret;]$secretKey")
Write-Host "DynamicVariable: $env:SqlADSecret"

$psadCredentialAP = New-Object Microsoft.Azure.Commands.Resources.Models.ActiveDirectory.PSADPasswordCredential

$startDateAP = Get-Date

$psadCredentialAP.StartDate = $startDateAP

$psadCredentialAP.EndDate = $startDateAP.AddYears(1)

$psadCredentialAP.KeyId = [guid]::NewGuid()

$psadCredentialAP.Password = $secretKey

New-AzureRmADApplication –DisplayName $SqlADAppName -HomePage $SqlADAppUri -IdentifierUris $SqlADAppUri -PasswordCredentials $psadCredentialAP -ReplyUrls $SqlADAppReplyUrl

$adapp = Get-AzureRmADApplication -IdentifierUri $SqlADAppUri

New-AzureRmADServicePrincipal -ApplicationId $adapp.ApplicationId

$clientId = $adapp.ApplicationId

echo $clientId 

Write-Host ("##vso[task.setvariable variable=SqlADClientId;]$clientId")
Write-Host "DynamicVariable: $env:SqlADClientId"

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

$adapp = Get-AzureRmADApplication -IdentifierUri $SqlADAppUri

$headers = GetGraphAuthHeader 
$url = "https://graph.windows.net/$TenantId/applications/$($adapp.ObjectID)?api-version=1.6"
$postUpdate = "{`"requiredResourceAccess`":[{`"resourceAppId`":`"00000002-0000-0000-c000-000000000000`",
`"resourceAccess`":[{`"id`":`"311a71cc-e848-46a1-bdf8-97ff7156d8e6`",`"type`":`"Scope`"}]}]}";

$updateResult = Invoke-RestMethod -Uri $url -Method "PATCH" -Headers $headers -Body $postUpdate

echo $updateResult

Set-AzureRmSqlServerActiveDirectoryAdministrator -ResourceGroupName $SqlResourceGroupName -ServerName $SqlServerName -DisplayName $SqlADGroupName

function UpdateDatabase{
    param
    (
        [Parameter(ParameterSetName='Customize',Mandatory=$true)]    
        [string] $sqlscriptPath,

        [Parameter(ParameterSetName='Customize',Mandatory=$true)]    
        [string] $databaseName
    )
	$query = Get-Content -Path $sqlscriptPath
	
	$connection = New-Object System.Data.SqlClient.SqlConnection
	$connection.ConnectionString = "Data Source=$SqlServerName.database.windows.net;Initial Catalog=$databaseName;Authentication=Active Directory Password;UID=$userName;PWD=$password;"
	$connection.Open()
	$command = $connection.CreateCommand()
	$command.CommandText = $query
	$command.ExecuteNonQuery()
	$connection.Close()
}


if(!$drSqlServer)
{

    $sqlscriptPath = [System.io.path]::combine($PSScriptRoot,'SqlAdminSetup.sql')

    (Get-Content $sqlscriptPath).replace("@sqladappname", $SqlADAppName) | Set-Content $sqlscriptPath

    $databaseList = "{db name}","{db name}","{db name}","{db name}","{db name}"

    Connect-AzureAD -TenantId $TenantId -Credential $mycreds

    foreach($database in $databaseList)
    {
        UpdateDatabase -sqlscriptPath $sqlscriptPath -databaseName $database
    }
}
