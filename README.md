# Azure-AD-Automation

## Azure Active Directory automation PowerShell scripts.

### This repository contains automation PowerShell scripts for common Azure AD app / group management scenarios such as:

1. Creating Azure AD groups and defining roles and mapping them with Azure AD app roles.
2. Creating Azure AD Application to manage Azure SQL Server DB by adding the same as admin in the database & also adds members of an existing group in the AD as SQL server administrators.
3. Creating an Azure AD application with roles defined in it and also demonstrate setting up trust between 2 AD applications using delegated OAauth permission via Graph API.

_Each folder has necessary automation scripts and supporting files to facilitate the mentioned functionality. Below is how to run the scripts for the same: _

## 1. Creating AD Groups and mapping app roles

The _AzureADGroupsfolder_ has 2 scripts:

### * createAzureADGroups.ps1

This script will create a new Azure AD Group.

The following are the script parameters:

* userName = name of the subscription & AD admin account 
* password = password of the subscription & AD admin
* subscriptionName = password of the azure subscription
* ADGroupName = name of the Azure AD group
* ADGroupDescription = description of Azure AD group

On executing the script the a new AD Group will be created with desired name and description in the tenant.

### * setgrouppermissions.ps1

This script will map an AD group as role to existing AD app role. Useful if you want users in a certain group to be mapped to a certain role associated to an AD application.

The following are the script parameters:

* AppName= name of the azure AD App
* userName = name of the subscription & AD admin account 
* password = password of the subscription & AD admin
* subscriptionName = password of the azure subscription
* AppRoleName= name of the Azure AD app role
* ADGroupName= name of the Azure AD group

On executing the script the group will be configured to mapped to the given role existing in the provided AD application.

## 2. Creating AD Apps for Azure SQL server administration

The _AzureSQLAdApp_ has 2 scripts:

### * SqlAdminSetup.sql

This SQL script will create a new db owner member from an existing AD application.

The following are the script parameters:

* sqladappname = name of the desired AD application 

The script will be executed by the SqlAuthADAppAutomation.ps1 and the AD app created by the PowerShell script will be registered as a db owner member at the target database by executing this SQL script against it.

### * SqlAuthADAppAutomation.ps1

This Script will generate an AD application protected by a secret key, grant permissions to authenticate AD users and generate a service principal for the same. The AD application will be added as an administrator role on the target databases. Also if the drSqlServer flag is set to true then for configured target databases, the SqlAdminSetup.sql will be run against each of the database and the created AD application will be added to the db as the db owner member.

The following are the script parameters:

* SqlADAppName = name of the desired AD application 
* SqlADAppUri = app id uri of the desired AD application 
* SqlADAppReplyUrl = reply url of the desired AD application 
* SqlResourceGroupName = resource group name where the sql server belongs to
* SqlServerName = name of the sql server  
* SqlADGroupName = name of the desired AD group to grant administrator access against the SQL server
* userName = user name of the azure subscription owner
* password = password of the azure subscription owner
* subscriptionName = name of the azure subscription
* drSqlServer = flag to enable the azure ad application to be added as an administrator on the target sql servers

On executing the script the desired AD application is created, the desired AD group is configured to give admin access to only group members against the target sql server and the AD application is added as db owner member at the target sql databases.

## 3. Creating AD service principal and azure AD apps with trust setup via OAuth permissions

The _Azure-AD-Automation_ has 2 scripts:

### * AzureServicePrincipal.ps1

This script will generate an Azure service principal account and assign owner role to the azure subscription.

The following are the script parameters:

* subscriptionName = name of the azure subscription
* password = password to protect the service principal 
* spnRole = name of the permission to be granted 
* environmentName = name of the azure environment

On executing the script a new azure AD application is created with the provided configurations and protected by the given password. Post this a service principal is created against the same and granted owner permission to azure subscription.
This service principal can now be used to connect securely to the azure subscription and manage resources.

### * devicemanagementadapp.ps1

This Script will generate an AD application protected by a secret key, set up roles in the AD application and map them with the configured azure AD groups and give delegated permissions to enable AD authentication via the application and read user profile. 

Post this, another AD application will be created which will also be protected by secret key, have the user roles and AD group mapping, enabled for AD auth via delegated permissions, finally get OAuth2Permissions of an existing AD app and set the delegated permission to access the same by updating the app manifest to establish trust with the target application.

The following are the script parameters:

* AdminPortalAppName = name of the desired AD application 
* AdminPortalAppUri = app id uri of the desired AD application 
* AdminPortalAppReplyUrl = reply url of the ad application
* DeviceManagementAppName = app name of the second ad app
* DeviceManagementAppUri = app ID uri of the second ad app  
* DeviceManagementAppReplyUrl = reply url of the second ad app
* FanApiAppUri = The app ID uri of the app to set up trust with via OAuth permissions
* userName= user name of the azure subscription owner
* password = password of the azure subscription owner 
* subscriptionName= name of the azure subscription

On executing the script the first AD app created is the one with variables containing Device management which is protected by a secret key, with modified app manifest with configured user roles and AD group mapping & delegated permissions to azure AD for auth and reading user profile info.

Post this another application will be created (the one with variable names containing admin portal) which is similar to the first AD application with additional delegated permission entry in the app manifest pointing to OAuth permission grant to an existing application identified by its unique app id uri (fan api app uri in this case) to establish trust with the existing AD application.
