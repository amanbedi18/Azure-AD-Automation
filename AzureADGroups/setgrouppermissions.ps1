Param
(
    [Parameter(ParameterSetName='Customize',Mandatory=$true)]	
	[String]
	$AppName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $userName,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $password,

    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $subscriptionName,

    #Name of the role in the app to map with AD group
    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $AppRoleName,

    #AD Group Name
    [Parameter(ParameterSetName='Customize',Mandatory=$true)]
	[String]
    $ADGroupName
)


Install-Module -Name AzureADPreview -ErrorAction SilentlyContinue -Force 
Import-Module Azure -ErrorAction SilentlyContinue
Import-Module AzureRM.Resources

Set-StrictMode -Version 3

$secpasswd = ConvertTo-SecureString $password -AsPlainText -Force
$mycreds = New-Object System.Management.Automation.PSCredential ($userName, $secpasswd)

Login-AzureRmAccount -Credential $mycreds -SubscriptionName $subscriptionName

$currentContext = Get-AzureRmContext

$TenantId = $currentContext.Subscription.TenantId

Connect-AzureAD -TenantId $TenantId -Credential $mycreds

$app = Get-AzureADServicePrincipal -SearchString $AppName

$list_of_names_to_map = @($ADGroupName)
foreach ($AD_group_name in $list_of_names_to_map) {
$AADGroup = Get-AzureADGroup -SearchString $AD_group_name
$AppRole = $App.AppRoles | ?{$_.value -like $AppRoleName}

$NewAssignmentParams = @{
'id'          = $AppRole.Id;
'objectid'    = $AADGroup.ObjectId;
'PrincipalId' = $AADGroup.ObjectId;
'ResourceId'  = $App.ObjectId;
}

New-AzureADGroupAppRoleAssignment @NewAssignmentParams
}