Param
(
    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $userName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $password,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $subscriptionName,

    #Group Name
    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $ADGroupName,

    #Group description
    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $ADGroupDescription
)

Install-Module -Name AzureADPreview -ErrorAction SilentlyContinue -Force 
Import-Module Azure -ErrorAction SilentlyContinue
Import-Module AzureRM.Resources

$secpasswd = ConvertTo-SecureString $password -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($userName, $secpasswd)
Login-AzureRmAccount -Credential $mycreds -SubscriptionName $subscriptionName

$TenantId = $currentContext.Subscription.TenantId

Connect-AzureAD -TenantId $TenantId -Credential $mycreds

echo "creating and setting group object Id !"
New-AzureADGroup -Description $ADGroupDescription -DisplayName $ADGroupName -MailEnabled $false -SecurityEnabled $true -MailNickName "NotSet"

$Group = Get-AzureADGroup -Filter " DisplayName eq ? $($ADGroupName)"
$devId = $Group.ObjectId.ToString()
Write-Host ("##vso[task.setvariable variable=ObjId;]$devId")
Write-Host "DynamicVariable: "$env:ObjId