# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE file in the project root for license information.

#
# Powershell script to deploy the resources - Customer portal, Publisher portal and the Azure SQL Database
#

#.\Deploy.ps1 `
# -WebAppNamePrefix "amp_saas_accelerator_<unique>" `
# -Location "<region>" `
# -PublisherAdminUsers "<your@email.address>"

Param(  
   [string][Parameter(Mandatory)]$WebAppNamePrefix, # Prefix used for creating web applications
   [string][Parameter()]$ResourceGroupForDeployment, # Name of the resource group to deploy the resources
   [string][Parameter(Mandatory)]$Location, # Location of the resource group
   [string][Parameter(Mandatory)]$PublisherAdminUsers, # Provide a list of email addresses (as comma-separated-values) that should be granted access to the Publisher Portal
   [string][Parameter()]$TenantID, # The value should match the value provided for Active Directory TenantID in the Technical Configuration of the Transactable Offer in Partner Center
   [string][Parameter()]$AzureSubscriptionID, # Subscription where the resources be deployed
   [string][Parameter()]$ADApplicationID, # The value should match the value provided for Active Directory Application ID in the Technical Configuration of the Transactable Offer in Partner Center
   [string][Parameter()]$ADApplicationSecret, # Secret key of the AD Application
   [string][Parameter()]$ADApplicationIDAdmin, # Multi-Tenant Active Directory Application ID 
   [string][Parameter()]$ADMTApplicationIDPortal, #Multi-Tenant Active Directory Application ID for the Landing Portal
   [string][Parameter()]$IsAdminPortalMultiTenant, # If set to true, the Admin Portal will be configured as a multi-tenant application. This is by default set to false. 
   [string][Parameter()]$SQLDatabaseName, # Name of the database (Defaults to AMPSaaSDB)
   [string][Parameter()]$SQLServerName, # Name of the database server (without database.windows.net)
   [string][Parameter()]$LogoURLpng,  # URL for Publisher .png logo
   [string][Parameter()]$LogoURLico,  # URL for Publisher .ico logo
   [string][Parameter()]$KeyVault, # Name of KeyVault
   [switch][Parameter()]$Quiet #if set, only show error / warning output from script commands
)

# Define the warning message
$message = @"
The SaaS Accelerator is offered under the MIT License as open source software and is not supported by Microsoft.

If you need help with the accelerator or would like to report defects or feature requests use the Issues feature on the GitHub repository at https://aka.ms/SaaSAccelerator

Do you agree? (Y/N)
"@

# Display the message in yellow
Write-Host $message -ForegroundColor Yellow

# Prompt the user for input
$response = Read-Host

# Check the user's response
if ($response -ne 'Y' -and $response -ne 'y') {
    Write-Host "You did not agree. Exiting..." -ForegroundColor Red
    exit
}

# Proceed if the user agrees
Write-Host "Thank you for agreeing. Proceeding with the script..." -ForegroundColor Green

# Make sure to install Az Module before running this script
# Install-Module Az
# Install-Module -Name AzureAD

#region Select Tenant / Subscription for deployment

$currentContext = az account show | ConvertFrom-Json
$currentTenant = $currentContext.tenantId
$currentSubscription = $currentContext.id

#Get TenantID if not set as argument
if(!($TenantID)) {    
    Get-AzTenant | Format-Table
    if (!($TenantID = Read-Host "⌨  Type your TenantID or press Enter to accept your current one [$currentTenant]")) { $TenantID = $currentTenant }    
}
else {
    Write-Host "🔑 Tenant provided: $TenantID"
}

#Get Azure Subscription if not set as argument
if(!($AzureSubscriptionID)) {    
    Get-AzSubscription -TenantId $TenantID | Format-Table
    if (!($AzureSubscriptionID = Read-Host "⌨  Type your SubscriptionID or press Enter to accept your current one [$currentSubscription]")) { $AzureSubscriptionID = $currentSubscription }
}
else {
    Write-Host "🔑 Azure Subscription provided: $AzureSubscriptionID"
}

#Set the AZ Cli context
az account set -s $AzureSubscriptionID
Write-Host "🔑 Azure Subscription '$AzureSubscriptionID' selected."

#endregion



$ErrorActionPreference = "Stop"
$startTime = Get-Date
#region Select Tenant / Subscription for deployment

$currentContext = az account show | ConvertFrom-Json
$currentTenant = $currentContext.tenantId
$currentSubscription = $currentContext.id

#Get TenantID if not set as argument
if(!($TenantID)) {    
    Get-AzTenant | Format-Table
    if (!($TenantID = Read-Host "⌨  Type your TenantID or press Enter to accept your current one [$currentTenant]")) { $TenantID = $currentTenant }    
}
else {
    Write-Host "🔑 Tenant provided: $TenantID"
}

#Get Azure Subscription if not set as argument
if(!($AzureSubscriptionID)) {    
    Get-AzSubscription -TenantId $TenantID | Format-Table
    if (!($AzureSubscriptionID = Read-Host "⌨  Type your SubscriptionID or press Enter to accept your current one [$currentSubscription]")) { $AzureSubscriptionID = $currentSubscription }
}
else {
    Write-Host "🔑 Azure Subscription provided: $AzureSubscriptionID"
}

#Set the AZ Cli context
az account set -s $AzureSubscriptionID
Write-Host "🔑 Azure Subscription '$AzureSubscriptionID' selected."

#endregion




#region Set up Variables and Default Parameters

if ($ResourceGroupForDeployment -eq "") {
    $ResourceGroupForDeployment = $WebAppNamePrefix 
}
if ($SQLServerName -eq "") {
    $SQLServerName = $WebAppNamePrefix + "-sql"
}
if ($SQLDatabaseName -eq "") {
    $SQLDatabaseName = $WebAppNamePrefix +"AMPSaaSDB"
}


if($KeyVault -eq "")
{
# User did not define KeyVault, so we will create one. 
# We need to check if the KeyVault already exists or purge before going forward

   $KeyVault=$WebAppNamePrefix+"-kv"

   # Check if the KeyVault exists under resource group
   $kv_check=$(az keyvault show -n $KeyVault -g $ResourceGroupForDeployment) 2>$null    

   # If KeyVault does not exist under resource group, then we need to check if it deleted KeyVault
   if($kv_check -eq $null)
   {
	#region Check If KeyVault Exists
		$KeyVaultApiUri="https://management.azure.com/subscriptions/$AzureSubscriptionID/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2019-09-01"
		$KeyVaultApiBody='{"name": "'+$KeyVault+'","type": "Microsoft.KeyVault/vaults"}'

		$kv_check=az rest --method post --uri $KeyVaultApiUri --headers 'Content-Type=application/json' --body $KeyVaultApiBody | ConvertFrom-Json

		if( $kv_check.reason -eq "AlreadyExists")
		{
			Write-Host ""
			Write-Host "🛑  KeyVault name "  -NoNewline -ForegroundColor Red
			Write-Host "$KeyVault"  -NoNewline -ForegroundColor Red -BackgroundColor Yellow
			Write-Host " already exists." -ForegroundColor Red
			Write-Host "   To Purge KeyVault please use the following doc:"
			Write-Host "   https://learn.microsoft.com/en-us/cli/azure/keyvault?view=azure-cli-latest#az-keyvault-purge."
			Write-Host "   You could use new KeyVault name by using parameter" -NoNewline 
			Write-Host " -KeyVault"  -ForegroundColor Green
			exit 1
		}
	#endregion
	}

}
else {
    # User specified a KeyVault, check if it exists and create if needed
    Write-Host "🔑 Using specified KeyVault: $KeyVault" -ForegroundColor Green
    Write-Host "🔑 KeyVault Resource Group: $ResourceGroupForDeployment" -ForegroundColor Green
    
    $kv_check=$(az keyvault show -n $KeyVault -g $ResourceGroupForDeployment) 2>$null
    if($kv_check -eq $null)
    {
        Write-Host "🔑 KeyVault '$KeyVault' not found, creating it..." -ForegroundColor Yellow
        
        # Check if KeyVault name is available globally
        $KeyVaultApiUri="https://management.azure.com/subscriptions/$AzureSubscriptionID/providers/Microsoft.KeyVault/checkNameAvailability?api-version=2019-09-01"
        $KeyVaultApiBody='{"name": "'+$KeyVault+'","type": "Microsoft.KeyVault/vaults"}'
        $kv_check=az rest --method post --uri $KeyVaultApiUri --headers 'Content-Type=application/json' --body $KeyVaultApiBody | ConvertFrom-Json

        if( $kv_check.reason -eq "AlreadyExists")
        {
            Write-Host ""
            Write-Host "🛑  KeyVault name "  -NoNewline -ForegroundColor Red
            Write-Host "$KeyVault"  -NoNewline -ForegroundColor Red -BackgroundColor Yellow
            Write-Host " already exists in another resource group." -ForegroundColor Red
            Write-Host "   Please specify a different KeyVault name or use the existing one in its current resource group."
            exit 1
        }
        else {
            Write-Host "✅ KeyVault name is available, will be created during deployment" -ForegroundColor Green
        }
    }
    else {
        Write-Host "✅ Existing KeyVault found and ready for configuration" -ForegroundColor Green
    }
}

$SaaSApiConfiguration_CodeHash= git log --format='%H' -1
$azCliOutput = if($Quiet){'none'} else {'json'}

#endregion

#region Validate Parameters

if($WebAppNamePrefix.Length -gt 21) {
    Throw "🛑 Web name prefix must be less than 21 characters."
    exit 1
}

if(!($KeyVault -match "^[a-zA-Z][a-z0-9-]+$")) {
    Throw "🛑 KeyVault name only allows alphanumeric and hyphens, but cannot start with a number or special character."
    exit 1
}


#endregion 

#region pre-checks

# check if dotnet 8 is installed

$dotnetversion = dotnet --version

if(!$dotnetversion.StartsWith('8.')) {
    Throw "🛑 Dotnet 8 not installed. Install dotnet8 and re-run the script."
    Exit
}

#endregion


Write-Host "Starting SaaS Accelerator Deployment..."

# Refresh Azure CLI tokens to prevent expiration issues
Write-host "🔑 Refreshing Azure CLI tokens"
az account get-access-token --resource https://database.windows.net/ --output none
az account get-access-token --resource https://management.azure.com/ --output none
az account get-access-token --resource https://graph.microsoft.com/ --output none
Write-host "✅ Azure CLI tokens refreshed"


#region Check If SQL Server Exist - REMOVED
# This check has been removed to allow idempotent deployment
# The script now properly handles existing SQL Servers in the main deployment section
#endregion

#region Dowloading assets if provided

# Download Publisher's PNG logo
if($LogoURLpng) { 
    Write-Host "📷 Logo image provided"
	Write-Host "   🔵 Downloading Logo image file"
    Invoke-WebRequest -Uri $LogoURLpng -OutFile "../src/CustomerSite/wwwroot/contoso-sales.png"
    Invoke-WebRequest -Uri $LogoURLpng -OutFile "../src/AdminSite/wwwroot/contoso-sales.png"
    Write-Host "   🔵 Logo image downloaded"
}

# Download Publisher's FAVICON logo
if($LogoURLico) { 
    Write-Host "📷 Logo icon provided"
	Write-Host "   🔵 Downloading Logo icon file"
    Invoke-WebRequest -Uri $LogoURLico -OutFile "../src/CustomerSite/wwwroot/favicon.ico"
    Invoke-WebRequest -Uri $LogoURLico -OutFile "../src/AdminSite/wwwroot/favicon.ico"
    Write-Host "   🔵 Logo icon downloaded"
}

#endregion
 
#region Create AAD App Registrations

#Record the current ADApps to reduce deployment instructions at the end
$ISLoginAppProvided = ($ADApplicationIDAdmin -ne "" -or $ADMTApplicationIDPortal -ne "")


if($ISLoginAppProvided){
	Write-Host "🔑 Multi-Tenant App Registrations provided."
	Write-Host "   ➡️ Admin Portal App Registration ID:" $ADApplicationIDAdmin
	Write-Host "   ➡️ Landing Page App Registration ID:" $ADMTApplicationIDPortal
}
else {
	Write-Host "🔑 Multi-Tenant App Registrations not provided."
}



if($IsAdminPortalMultiTenant -eq "true"){
	Write-Host "🔑 Admin Portal App Registration set as Multi-Tenant."
	$IsAdminPortalMultiTenant = $true
}
else {
	Write-Host "🔑 Admin Portal App Registration set as Single-Tenant."
	$IsAdminPortalMultiTenant = $false
}






#Create App Registration for authenticating calls to the Marketplace API
if (!($ADApplicationID)) {   
    Write-Host "🔑 Creating Fulfilment API App Registration"
    try {   
        $ADApplication = az ad app create --only-show-errors --sign-in-audience AzureADMYOrg --display-name "$WebAppNamePrefix-FulfillmentAppReg" | ConvertFrom-Json
		$ADObjectID = $ADApplication.id
        $ADApplicationID = $ADApplication.appId
        sleep 5 #this is to give time to AAD to register
		# create service principal
		az ad sp create --id $ADApplicationID
        $ADApplicationSecret = az ad app credential reset --id $ADObjectID --append --display-name 'SaaSAPI' --years 2 --query password --only-show-errors --output tsv
				
        Write-Host "   🔵 FulfilmentAPI App Registration created."
		Write-Host "      ➡️ Application ID:" $ADApplicationID
    }
    catch [System.Net.WebException],[System.IO.IOException] {
        Write-Host "🚨🚨   $PSItem.Exception"
        break;
    }
}

#Create Multi-Tenant App Registration for Admin Portal User Login
if (!($ADApplicationIDAdmin)) {  
    Write-Host "🔑 Creating Admin Portal SSO App Registration"
    try {
	
		$appCreateRequestBodyJson = @"
{
	"displayName" : "$WebAppNamePrefix-AdminPortalAppReg",
	"api": 
	{
		"requestedAccessTokenVersion" : 2
	},
	"signInAudience" : "AzureADMyOrg",
	"web":
	{ 
		"redirectUris": 
		[
			
			"https://$WebAppNamePrefix-admin.azurewebsites.net",
			"https://$WebAppNamePrefix-admin.azurewebsites.net/",
			"https://$WebAppNamePrefix-admin.azurewebsites.net/Home/Index",
			"https://$WebAppNamePrefix-admin.azurewebsites.net/Home/Index/"
		],
		"logoutUrl": "https://$WebAppNamePrefix-admin.azurewebsites.net/logout",
		"implicitGrantSettings": 
			{ "enableIdTokenIssuance" : true }
	},
	"requiredResourceAccess":
	[{
		"resourceAppId": "00000003-0000-0000-c000-000000000000",
		"resourceAccess":
			[{ 
				"id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d",
				"type": "Scope" 
			}]
	}]
}
"@	
		if ($PsVersionTable.Platform -ne 'Unix') {
			#On Windows, we need to escape quotes and remove new lines before sending the payload to az rest. 
			# See: https://github.com/Azure/azure-cli/blob/dev/doc/quoting-issues-with-powershell.md#double-quotes--are-lost
			$appCreateRequestBodyJson = $appCreateRequestBodyJson.replace('"','\"').replace("`r`n","")
		}

		$adminPortalAppReg = $(az rest --method POST --headers "Content-Type=application/json" --uri https://graph.microsoft.com/v1.0/applications --body $appCreateRequestBodyJson  ) | ConvertFrom-Json
	
		$ADApplicationIDAdmin = $adminPortalAppReg.appId
		$ADMTObjectIDAdmin = $adminPortalAppReg.id
	
        Write-Host "   🔵 Admin Portal SSO App Registration created."
		Write-Host "      ➡️ Application Id: $ADApplicationIDAdmin"


		# Download Publisher's AppRegistration logo
        if($LogoURLpng) { 
			Write-Host "   🔵 Logo image provided. Setting the Application branding logo"
			Write-Host "      ➡️ Setting the Application branding logo"
			$token=(az account get-access-token --resource "https://graph.microsoft.com" --query accessToken --output tsv)
			$logoWeb = Invoke-WebRequest $LogoURLpng
			$logoContentType = $logoWeb.Headers["Content-Type"]
			$logoContent = $logoWeb.Content
			
			$uploaded = Invoke-WebRequest `
			  -Uri "https://graph.microsoft.com/v1.0/applications/$ADMTObjectIDAdmin/logo" `
			  -Method "PUT" `
			  -Header @{"Authorization"="Bearer $token";"Content-Type"="$logoContentType";} `
			  -Body $logoContent
		    
			Write-Host "      ➡️ Application branding logo set."
        }

    }
    catch [System.Net.WebException],[System.IO.IOException] {
        Write-Host "🚨🚨   $PSItem.Exception"
        break;
    }
}

#Create Multi-Tenant App Registration for Landing Page User Login
if (!($ADMTApplicationIDPortal)) {  
    Write-Host "🔑 Creating Landing Page SSO App Registration"
    try {
	
		$appCreateRequestBodyJson = @"
{
	"displayName" : "$WebAppNamePrefix-LandingpageAppReg",
	"api": 
	{
		"requestedAccessTokenVersion" : 2
	},
	"signInAudience" : "AzureADandPersonalMicrosoftAccount",
	"web":
	{ 
		"redirectUris": 
		[
			"https://$WebAppNamePrefix-portal.azurewebsites.net",
			"https://$WebAppNamePrefix-portal.azurewebsites.net/",
			"https://$WebAppNamePrefix-portal.azurewebsites.net/Home/Index",
			"https://$WebAppNamePrefix-portal.azurewebsites.net/Home/Index/"
			
		],
		"logoutUrl": "https://$WebAppNamePrefix-portal.azurewebsites.net/logout",
		"implicitGrantSettings": 
			{ "enableIdTokenIssuance" : true }
	},
	"requiredResourceAccess":
	[{
		"resourceAppId": "00000003-0000-0000-c000-000000000000",
		"resourceAccess":
			[{ 
				"id": "e1fe6dd8-ba31-4d61-89e7-88639da4683d",
				"type": "Scope" 
			}]
	}]
}
"@	
		if ($PsVersionTable.Platform -ne 'Unix') {
			#On Windows, we need to escape quotes and remove new lines before sending the payload to az rest. 
			# See: https://github.com/Azure/azure-cli/blob/dev/doc/quoting-issues-with-powershell.md#double-quotes--are-lost
			$appCreateRequestBodyJson = $appCreateRequestBodyJson.replace('"','\"').replace("`r`n","")
		}

		$landingpageLoginAppReg = $(az rest --method POST --headers "Content-Type=application/json" --uri https://graph.microsoft.com/v1.0/applications --body $appCreateRequestBodyJson  ) | ConvertFrom-Json
	
		$ADMTApplicationIDPortal = $landingpageLoginAppReg.appId
		$ADMTObjectIDPortal = $landingpageLoginAppReg.id
	
        Write-Host "   🔵 Landing Page SSO App Registration created."
		Write-Host "      ➡️ Application Id: $ADMTApplicationIDPortal"
	
		# Download Publisher's AppRegistration logo
        if($LogoURLpng) { 
			Write-Host "   🔵 Logo image provided. Setting the Application branding logo"
			Write-Host "      ➡️ Setting the Application branding logo"
			$token=(az account get-access-token --resource "https://graph.microsoft.com" --query accessToken --output tsv)
			$logoWeb = Invoke-WebRequest $LogoURLpng
			$logoContentType = $logoWeb.Headers["Content-Type"]
			$logoContent = $logoWeb.Content
			
			$uploaded = Invoke-WebRequest `
			  -Uri "https://graph.microsoft.com/v1.0/applications/$ADMTObjectIDPortal/logo" `
			  -Method "PUT" `
			  -Header @{"Authorization"="Bearer $token";"Content-Type"="$logoContentType";} `
			  -Body $logoContent
		    
			Write-Host "      ➡️ Application branding logo set."
        }

    }
    catch [System.Net.WebException],[System.IO.IOException] {
        Write-Host "🚨🚨   $PSItem.Exception"
        break;
    }
}

#endregion

#region Prepare Code Packages
Write-host "📜 Prepare publish files for the application"
if (!(Test-Path '../Publish')) {		
	Write-host "   🔵 Preparing Admin Site"  
	dotnet publish ../src/AdminSite/AdminSite.csproj -c release -o ../Publish/AdminSite/ -v q

	Write-host "   🔵 Preparing Metered Scheduler"
	dotnet publish ../src/MeteredTriggerJob/MeteredTriggerJob.csproj -c release -o ../Publish/AdminSite/app_data/jobs/triggered/MeteredTriggerJob/ -v q --runtime win-x64 --self-contained true 

	Write-host "   🔵 Preparing Customer Site"
	dotnet publish ../src/CustomerSite/CustomerSite.csproj -c release -o ../Publish/CustomerSite/ -v q

	Write-host "   🔵 Zipping packages"
	Compress-Archive -Path ../Publish/AdminSite/* -DestinationPath ../Publish/AdminSite.zip -Force
	Compress-Archive -Path ../Publish/CustomerSite/* -DestinationPath ../Publish/CustomerSite.zip -Force
}
#endregion

#region Deploy Azure Resources Infrastructure
Write-host "☁ Deploy Azure Resources"

#Set-up resource name variables
$WebAppNameService=$WebAppNamePrefix+"-asp"
$WebAppNameAdmin=$WebAppNamePrefix+"-admin"
$WebAppNamePortal=$WebAppNamePrefix+"-portal"
$VnetName=$WebAppNamePrefix+"-vnet"
$privateSqlEndpointName=$WebAppNamePrefix+"-db-pe"
$privateKvEndpointName=$WebAppNamePrefix+"-kv-pe"
$privateSqlDnsZoneName="privatelink.database.windows.net"
$privateKvDnsZoneName="privatelink.vaultcore.windows.net"
$privateSqlLink =$WebAppNamePrefix+"-db-link"
$privateKvlink =$WebAppNamePrefix+"-kv-link"
$WebSubnetName="web"
$SqlSubnetName="sql"
$KvSubnetName="kv"
$DefaultSubnetName="default"

#keep the space at the end of the string - bug in az cli running on windows powershell truncates last char https://github.com/Azure/azure-cli/issues/10066
$ADApplicationSecretKeyVault="@Microsoft.KeyVault(VaultName=$KeyVault;SecretName=ADApplicationSecret) "
$DefaultConnectionKeyVault="@Microsoft.KeyVault(VaultName=$KeyVault;SecretName=DefaultConnection) "
$ServerUri = $SQLServerName+".database.windows.net"
$ServerUriPrivate = $SQLServerName+".privatelink.database.windows.net"
$Connection="Server=tcp:"+$ServerUriPrivate+";Database="+$SQLDatabaseName+";TrustServerCertificate=True;Authentication=Active Directory Managed Identity;"

Write-host "   🔵 Resource Group"
Write-host "      ➡️ Check if Resource Group exists"
$rgExists = az group show --name $ResourceGroupForDeployment 2>$null
if (-not $rgExists) {
    Write-host "      ➡️ Creating Resource Group"
az group create --location $Location --name $ResourceGroupForDeployment --output $azCliOutput
    Write-host "      ✅ Resource Group created successfully"
    Write-host "      ⏳ Waiting 10 seconds for resource group to be fully available..."
    Start-Sleep -Seconds 10
} else {
    Write-host "      ✅ Resource Group already exists, using existing one"
}

Write-host "      ➡️ Create VNET and Subnet"
Write-host "      🔍 Debug Info:"
Write-host "         Resource Group: $ResourceGroupForDeployment"
Write-host "         VNet Name: $VnetName"
Write-host "         Location: $Location"
Write-host "      ➡️ Checking if VNet '$VnetName' exists..."
try {
    $vnetExists = az network vnet show --resource-group $ResourceGroupForDeployment --name $VnetName 2>$null
    if ($LASTEXITCODE -eq 0 -and $vnetExists) {
        Write-host "      ✅ VNet '$VnetName' already exists, using existing one"
    } else {
        Write-host "      ➡️ VNet '$VnetName' not found, creating it..."
        az network vnet create --resource-group $ResourceGroupForDeployment --name $VnetName --address-prefixes "10.0.0.0/20" --output $azCliOutput
        if ($LASTEXITCODE -eq 0) {
            Write-host "      ✅ VNet created successfully"
            Write-host "      ⏳ Waiting 5 seconds for VNet to be fully available..."
            Start-Sleep -Seconds 5
        } else {
            Write-host "      ❌ VNet creation failed with exit code $LASTEXITCODE"
            throw "VNet creation failed"
        }
    }
} catch {
    Write-host "      ❌ Error checking VNet existence: $($_.Exception.Message)"
    Write-host "      ➡️ Attempting to create VNet anyway..."
az network vnet create --resource-group $ResourceGroupForDeployment --name $VnetName --address-prefixes "10.0.0.0/20" --output $azCliOutput
    if ($LASTEXITCODE -eq 0) {
        Write-host "      ✅ VNet created successfully"
        Write-host "      ⏳ Waiting 5 seconds for VNet to be fully available..."
        Start-Sleep -Seconds 5
    } else {
        Write-host "      ❌ VNet creation failed with exit code $LASTEXITCODE"
        throw "VNet creation failed"
    }
}

Write-host "      ➡️ Create Subnets"
Write-host "      ⏳ Waiting 5 seconds for VNet to be fully available for subnet operations..."
Start-Sleep -Seconds 5

# Manual verification that VNet is accessible
Write-host "      🔍 Verifying VNet accessibility..."
$vnetVerify = az network vnet show --resource-group $ResourceGroupForDeployment --name $VnetName --query "name" -o tsv 2>$null
if ($LASTEXITCODE -eq 0 -and $vnetVerify) {
    Write-host "      ✅ VNet verification successful: $vnetVerify"
} else {
    Write-host "      ❌ VNet verification failed - VNet may not be accessible"
    Write-host "      💡 This could be a permissions issue or the VNet may be in a different resource group"
    Write-host "      🔍 Attempting to continue anyway..."
}

# Check and create each subnet
$subnets = @(
    @{Name=$DefaultSubnetName; Prefix="10.0.0.0/24"},
    @{Name=$WebSubnetName; Prefix="10.0.1.0/24"; ServiceEndpoints="Microsoft.Sql Microsoft.KeyVault"; Delegations="Microsoft.Web/serverfarms"},
    @{Name=$SqlSubnetName; Prefix="10.0.2.0/24"},
    @{Name=$KvSubnetName; Prefix="10.0.3.0/24"}
)

foreach ($subnet in $subnets) {
    Write-host "      ➡️ Checking subnet '$($subnet.Name)'..."
    try {
        $subnetExists = az network vnet subnet show --resource-group $ResourceGroupForDeployment --vnet-name $VnetName --name $subnet.Name 2>$null
        if ($LASTEXITCODE -eq 0 -and $subnetExists) {
            Write-host "      ✅ Subnet '$($subnet.Name)' already exists, skipping"
        } else {
            Write-host "      ➡️ Creating subnet '$($subnet.Name)'"
            $maxRetries = 3
            $retryCount = 0
            $success = $false
            
            while ($retryCount -lt $maxRetries -and -not $success) {
                $retryCount++
                Write-host "      🔄 Attempt $retryCount of $maxRetries..."
                
                $cmd = "az network vnet subnet create --resource-group $ResourceGroupForDeployment --vnet-name $VnetName -n $($subnet.Name) --address-prefixes $($subnet.Prefix)"
                if ($subnet.ServiceEndpoints) {
                    $cmd += " --service-endpoints $($subnet.ServiceEndpoints)"
                }
                if ($subnet.Delegations) {
                    $cmd += " --delegations $($subnet.Delegations)"
                }
                $cmd += " --output $azCliOutput"
                
                Invoke-Expression $cmd
                if ($LASTEXITCODE -eq 0) {
                    Write-host "      ✅ Subnet '$($subnet.Name)' created successfully"
                    $success = $true
                } else {
                    Write-host "      ❌ Subnet '$($subnet.Name)' creation failed with exit code $LASTEXITCODE"
                    if ($retryCount -lt $maxRetries) {
                        Write-host "      ⏳ Waiting 10 seconds before retry..."
                        Start-Sleep -Seconds 10
                    }
                }
            }
            
            if (-not $success) {
                Write-host "      ❌ Failed to create subnet '$($subnet.Name)' after $maxRetries attempts"
                Write-host "      💡 This subnet may already exist or there may be a permissions issue"
            }
        }
    } catch {
        Write-host "      ❌ Error checking subnet '$($subnet.Name)': $($_.Exception.Message)"
        Write-host "      ➡️ Attempting to create subnet anyway..."
        $cmd = "az network vnet subnet create --resource-group $ResourceGroupForDeployment --vnet-name $VnetName -n $($subnet.Name) --address-prefixes $($subnet.Prefix)"
        if ($subnet.ServiceEndpoints) {
            $cmd += " --service-endpoints $($subnet.ServiceEndpoints)"
        }
        if ($subnet.Delegations) {
            $cmd += " --delegations $($subnet.Delegations)"
        }
        $cmd += " --output $azCliOutput"
        Invoke-Expression $cmd
        if ($LASTEXITCODE -eq 0) {
            Write-host "      ✅ Subnet '$($subnet.Name)' created successfully"
        } else {
            Write-host "      ❌ Subnet '$($subnet.Name)' creation failed with exit code $LASTEXITCODE"
        }
    }
} 

Write-host "      ➡️ Create Sql Server"
Write-host "      ➡️ Checking if SQL Server '$SQLServerName' exists..."
try {
    $sqlServerExists = az sql server show --name $SQLServerName --resource-group $ResourceGroupForDeployment 2>$null
    if ($LASTEXITCODE -eq 0 -and $sqlServerExists) {
        Write-host "      ✅ SQL Server '$SQLServerName' already exists, using existing one"
    } else {
        Write-host "      ➡️ Creating SQL Server '$SQLServerName'"
        $userId = az ad signed-in-user show --query id -o tsv 
        $userdisplayname = az ad signed-in-user show --query displayName -o tsv 
        # Create SQL Server with both Azure AD and SQL Server authentication enabled
        # This allows both Azure AD users and SQL Server username/password authentication
        az sql server create --name $SQLServerName --resource-group $ResourceGroupForDeployment --location $Location --admin-user "sqladmin" --admin-password "YourSecurePassword123!" --external-admin-principal-type User --external-admin-name $userdisplayname --external-admin-sid $userId --output $azCliOutput
        if ($LASTEXITCODE -eq 0) {
            Write-host "      ✅ SQL Server created successfully"
            Write-host "      ⏳ Waiting 10 seconds for SQL Server to be fully available..."
            Start-Sleep -Seconds 10
        } else {
            Write-host "      ❌ SQL Server creation failed with exit code $LASTEXITCODE"
            throw "SQL Server creation failed"
        }
    }
} catch {
    Write-host "      ❌ Error checking SQL Server existence: $($_.Exception.Message)"
    Write-host "      ➡️ Attempting to create SQL Server anyway..."
$userId = az ad signed-in-user show --query id -o tsv 
$userdisplayname = az ad signed-in-user show --query displayName -o tsv 
    az sql server create --name $SQLServerName --resource-group $ResourceGroupForDeployment --location $Location --admin-user "sqladmin" --admin-password "YourSecurePassword123!" --external-admin-principal-type User --external-admin-name $userdisplayname --external-admin-sid $userId --output $azCliOutput
    if ($LASTEXITCODE -eq 0) {
        Write-host "      ✅ SQL Server created successfully"
        Write-host "      ⏳ Waiting 10 seconds for SQL Server to be fully available..."
        Start-Sleep -Seconds 10
    } else {
        Write-host "      ❌ SQL Server creation failed with exit code $LASTEXITCODE"
        throw "SQL Server creation failed"
    }
}
Write-host "      ➡️ Set minimalTlsVersion to 1.2"
az sql server update --name $SQLServerName --resource-group $ResourceGroupForDeployment --set minimalTlsVersion="1.2"
Write-host "      ➡️ Add SQL Server Firewall rules"
az sql server firewall-rule create --resource-group $ResourceGroupForDeployment --server $SQLServerName -n AllowAzureIP --start-ip-address "0.0.0.0" --end-ip-address "0.0.0.0" --output $azCliOutput
if ($env:ACC_CLOUD -eq $null){
    Write-host "      ➡️ Running in local environment - Add current IP to firewall"
	$publicIp = (Invoke-WebRequest -uri "https://api.ipify.org").Content
    az sql server firewall-rule create --resource-group $ResourceGroupForDeployment --server $SQLServerName -n AllowIP --start-ip-address "$publicIp" --end-ip-address "$publicIp" --output $azCliOutput
}

Write-host "      ➡️ Create SQL DB"
$sqlDbExists = az sql db show --name $SQLDatabaseName --server $SQLServerName --resource-group $ResourceGroupForDeployment 2>$null
if (-not $sqlDbExists) {
    Write-host "      ➡️ Creating SQL Database '$SQLDatabaseName'"
az sql db create --resource-group $ResourceGroupForDeployment --server $SQLServerName --name $SQLDatabaseName  --edition Standard  --capacity 10 --zone-redundant false --output $azCliOutput
    Write-host "      ✅ SQL Database created successfully"
    Write-host "      ⏳ Waiting 5 seconds for SQL Database to be fully available..."
    Start-Sleep -Seconds 5
} else {
    Write-host "      ✅ SQL Database '$SQLDatabaseName' already exists, using existing one"
}

Write-host "   🔵 KeyVault"
Write-host "      ➡️ Configuring KeyVault"
# Check if KeyVault exists and create if needed
$kvExists = az keyvault show --name $KeyVault --resource-group $ResourceGroupForDeployment 2>$null
if (-not $kvExists) {
    Write-host "      ➡️ Creating KeyVault '$KeyVault'"
    try {
        az keyvault create --name $KeyVault --resource-group $ResourceGroupForDeployment --location $Location --enable-rbac-authorization false --output $azCliOutput
        Write-host "      ✅ KeyVault created successfully"
    } catch {
        if ($_.Exception.Message -like "*deleted state*") {
            Write-host "      ⚠️ KeyVault exists in soft-deleted state, purging..."
            az keyvault purge --name $KeyVault
            Start-Sleep -Seconds 30
            az keyvault create --name $KeyVault --resource-group $ResourceGroupForDeployment --location $Location --enable-rbac-authorization false --output $azCliOutput
            Write-host "      ✅ KeyVault created successfully after purge"
        } elseif ($_.Exception.Message -like "*token*" -or $_.Exception.Message -like "*expired*") {
            Write-host "      ⚠️ Azure CLI token expired, refreshing..."
            az account get-access-token --resource https://management.azure.com/ --output none
            az keyvault create --name $KeyVault --resource-group $ResourceGroupForDeployment --location $Location --enable-rbac-authorization false --output $azCliOutput
            Write-host "      ✅ KeyVault created successfully after token refresh"
        } else {
            Write-host "      ❌ KeyVault creation failed: $($_.Exception.Message)"
            throw "KeyVault creation failed. Please resolve the issue and retry."
        }
    }
         } else {
             Write-host "      ✅ KeyVault '$KeyVault' already exists, using existing one"
         }

         Write-host "      ⏳ Waiting 5 seconds for KeyVault to be fully available..."
         Start-Sleep -Seconds 5

Write-host "      ➡️ Add Secrets"
# Add current user's IP to KeyVault firewall to allow script execution
Write-host "      🔧 Adding current IP to KeyVault firewall..."
$currentIp = (Invoke-WebRequest -uri "https://api.ipify.org").Content
Write-host "      📍 Current IP: $currentIp"
try {
    az keyvault network-rule add --name $KeyVault --resource-group $ResourceGroupForDeployment --ip-address $currentIp --output $azCliOutput
    Write-host "      ✅ IP added to KeyVault firewall"
} catch {
    Write-host "      ⚠️ Could not add IP to firewall, trying to add secrets anyway..."
}

az keyvault secret set --vault-name $KeyVault --name ADApplicationSecret --value="$ADApplicationSecret" --output $azCliOutput
az keyvault secret set --vault-name $KeyVault --name DefaultConnection --value $Connection --output $azCliOutput
Write-host "      ➡️ Update Firewall"
az keyvault update --name $KeyVault --resource-group $ResourceGroupForDeployment --default-action Deny --output $azCliOutput
az keyvault network-rule add --name $KeyVault --resource-group $ResourceGroupForDeployment --vnet-name $VnetName --subnet $WebSubnetName --output $azCliOutput

Write-host "   🔵 App Service Plan"
Write-host "      ➡️ Check if App Service Plan exists"
$aspExists = az appservice plan show --name $WebAppNameService --resource-group $ResourceGroupForDeployment 2>$null
if (-not $aspExists) {
    Write-host "      ➡️ Creating App Service Plan '$WebAppNameService'"
az appservice plan create -g $ResourceGroupForDeployment -n $WebAppNameService --sku B1 --output $azCliOutput
    Write-host "      ✅ App Service Plan created successfully"
    Write-host "      ⏳ Waiting 5 seconds for App Service Plan to be fully available..."
    Start-Sleep -Seconds 5
} else {
    Write-host "      ✅ App Service Plan '$WebAppNameService' already exists, using existing one"
}

Write-host "   🔵 Admin Portal WebApp"
Write-host "      ➡️ Check if Admin WebApp exists"
$adminWebAppExists = az webapp show --name $WebAppNameAdmin --resource-group $ResourceGroupForDeployment 2>$null
if (-not $adminWebAppExists) {
    Write-host "      ➡️ Creating Admin WebApp '$WebAppNameAdmin'"
az webapp create -g $ResourceGroupForDeployment -p $WebAppNameService -n $WebAppNameAdmin  --runtime dotnet:8 --output $azCliOutput
    # Enable VNet route all to ensure traffic routes through VNet for private endpoint access
    az webapp config set -g $ResourceGroupForDeployment -n $WebAppNameAdmin --vnet-route-all-enabled true --output $azCliOutput
    Write-host "      ✅ Admin WebApp created successfully"
    Write-host "      ⏳ Waiting 15 seconds for Admin WebApp to be fully available..."
    Start-Sleep -Seconds 15
} else {
    Write-host "      ✅ Admin WebApp '$WebAppNameAdmin' already exists, using existing one"
    # Ensure VNet route all is enabled for existing WebApp
    Write-host "      🔧 Ensuring VNet route all is enabled..."
    az webapp config set -g $ResourceGroupForDeployment -n $WebAppNameAdmin --vnet-route-all-enabled true --output $azCliOutput
}

Write-host "      ➡️ Assign Identity"
$WebAppNameAdminId = az webapp identity assign -g $ResourceGroupForDeployment  -n $WebAppNameAdmin --identities [system] --query principalId -o tsv
Write-host "      ⏳ Waiting 5 seconds for identity assignment to propagate..."
Start-Sleep -Seconds 25

Write-host "      ➡️ Setup access to KeyVault"
az keyvault set-policy --name $KeyVault  --object-id $WebAppNameAdminId --secret-permissions get list --key-permissions get list --resource-group $ResourceGroupForDeployment --output $azCliOutput
Write-host "      ⏳ Waiting 5 seconds for KeyVault policy to propagate..."
Start-Sleep -Seconds 25

Write-host "      ➡️ Set Configuration"
az webapp config connection-string set -g $ResourceGroupForDeployment -n $WebAppNameAdmin -t SQLAzure --output $azCliOutput --settings DefaultConnection=$DefaultConnectionKeyVault 
az webapp config appsettings set -g $ResourceGroupForDeployment  -n $WebAppNameAdmin --output $azCliOutput --settings KnownUsers=$PublisherAdminUsers SaaSApiConfiguration__AdAuthenticationEndPoint=https://login.microsoftonline.com SaaSApiConfiguration__ClientId=$ADApplicationID SaaSApiConfiguration__ClientSecret=$ADApplicationSecretKeyVault SaaSApiConfiguration__FulFillmentAPIBaseURL=https://marketplaceapi.microsoft.com/api SaaSApiConfiguration__FulFillmentAPIVersion=2018-08-31 SaaSApiConfiguration__GrantType=client_credentials SaaSApiConfiguration__MTClientId=$ADApplicationIDAdmin SaaSApiConfiguration__IsAdminPortalMultiTenant=$IsAdminPortalMultiTenant SaaSApiConfiguration__Resource=20e940b3-4c77-4b0b-9a53-9e16a1b010a7 SaaSApiConfiguration__TenantId=$TenantID SaaSApiConfiguration__SignedOutRedirectUri=https://$WebAppNamePrefix-admin.azurewebsites.net/Home/Index/ SaaSApiConfiguration_CodeHash=$SaaSApiConfiguration_CodeHash
az webapp config set -g $ResourceGroupForDeployment -n $WebAppNameAdmin --always-on true  --output $azCliOutput

Write-host "   🔵 Customer Portal WebApp"
Write-host "      ➡️ Check if Customer WebApp exists"
$portalWebAppExists = az webapp show --name $WebAppNamePortal --resource-group $ResourceGroupForDeployment 2>$null
if (-not $portalWebAppExists) {
    Write-host "      ➡️ Creating Customer WebApp '$WebAppNamePortal'"
az webapp create -g $ResourceGroupForDeployment -p $WebAppNameService -n $WebAppNamePortal --runtime dotnet:8 --output $azCliOutput
    # Enable VNet route all to ensure traffic routes through VNet for private endpoint access
    az webapp config set -g $ResourceGroupForDeployment -n $WebAppNamePortal --vnet-route-all-enabled true --output $azCliOutput
    Write-host "      ✅ Customer WebApp created successfully"
    Write-host "      ⏳ Waiting 15 seconds for Customer WebApp to be fully available..."
    Start-Sleep -Seconds 15
} else {
    Write-host "      ✅ Customer WebApp '$WebAppNamePortal' already exists, using existing one"
    # Ensure VNet route all is enabled for existing WebApp
    Write-host "      🔧 Ensuring VNet route all is enabled..."
    az webapp config set -g $ResourceGroupForDeployment -n $WebAppNamePortal --vnet-route-all-enabled true --output $azCliOutput
}

Write-host "      ➡️ Assign Identity"
$WebAppNamePortalId= az webapp identity assign -g $ResourceGroupForDeployment  -n $WebAppNamePortal --identities [system] --query principalId -o tsv 
Write-host "      ⏳ Waiting 5 seconds for identity assignment to propagate..."
Start-Sleep -Seconds 5

Write-host "      ➡️ Setup access to KeyVault"
az keyvault set-policy --name $KeyVault  --object-id $WebAppNamePortalId --secret-permissions get list --key-permissions get list --resource-group $ResourceGroupForDeployment --output $azCliOutput
Write-host "      ⏳ Waiting 5 seconds for KeyVault policy to propagate..."
Start-Sleep -Seconds 5

Write-host "      ➡️ Set Configuration"
az webapp config connection-string set -g $ResourceGroupForDeployment -n $WebAppNamePortal -t SQLAzure --output $azCliOutput --settings DefaultConnection="@Microsoft.KeyVault(VaultName=$KeyVault;SecretName=PortalConnection) "
az webapp config appsettings set -g $ResourceGroupForDeployment  -n $WebAppNamePortal --output $azCliOutput --settings SaaSApiConfiguration__AdAuthenticationEndPoint=https://login.microsoftonline.com SaaSApiConfiguration__ClientId=$ADApplicationID SaaSApiConfiguration__ClientSecret=$ADApplicationSecretKeyVault SaaSApiConfiguration__FulFillmentAPIBaseURL=https://marketplaceapi.microsoft.com/api SaaSApiConfiguration__FulFillmentAPIVersion=2018-08-31 SaaSApiConfiguration__GrantType=client_credentials SaaSApiConfiguration__MTClientId=$ADMTApplicationIDPortal SaaSApiConfiguration__Resource=20e940b3-4c77-4b0b-9a53-9e16a1b010a7 SaaSApiConfiguration__TenantId=$TenantID SaaSApiConfiguration__SignedOutRedirectUri=https://$WebAppNamePrefix-portal.azurewebsites.net/Home/Index/ SaaSApiConfiguration_CodeHash=$SaaSApiConfiguration_CodeHash
az webapp config set -g $ResourceGroupForDeployment -n $WebAppNamePortal --always-on true --output $azCliOutput

#endregion

#region Deploy Code
Write-host "📜 Deploy Code"

Write-host "   🔵 Deploy Code to Admin Portal"
az webapp deploy --resource-group $ResourceGroupForDeployment --name $WebAppNameAdmin --src-path "../Publish/AdminSite.zip" --type zip --output $azCliOutput
Write-host "      ⏳ Waiting 10 seconds for Admin WebApp deployment to complete..."
Start-Sleep -Seconds 10

Write-host "   🔵 Deploy Code to Customer Portal"
az webapp deploy --resource-group $ResourceGroupForDeployment --name $WebAppNamePortal --src-path "../Publish/CustomerSite.zip" --type zip --output $azCliOutput
Write-host "      ⏳ Waiting 10 seconds for Customer WebApp deployment to complete..."
Start-Sleep -Seconds 10

Write-host "   🔵 Update Firewall for WebApps and SQL"
# Use full resource IDs to avoid warnings about resource group assumptions
$vnetResourceId = "/subscriptions/$AzureSubscriptionID/resourceGroups/$ResourceGroupForDeployment/providers/Microsoft.Network/virtualNetworks/$VnetName"
$subnetResourceId = "$vnetResourceId/subnets/$WebSubnetName"

Write-host "      ➡️ Adding VNet integration for Customer Portal"
az webapp vnet-integration add --resource-group $ResourceGroupForDeployment --name $WebAppNamePortal --subnet $subnetResourceId --output $azCliOutput

Write-host "      ➡️ Adding VNet integration for Admin Portal"
az webapp vnet-integration add --resource-group $ResourceGroupForDeployment --name $WebAppNameAdmin --subnet $subnetResourceId --output $azCliOutput

Write-host "      ➡️ Creating SQL Server VNet rule"
az sql server vnet-rule create --name $WebAppNamePrefix-vnet --resource-group $ResourceGroupForDeployment --server $SQLServerName --vnet-name $VnetName --subnet $WebSubnetName --output $azCliOutput

Write-host "   🔵 Clean up"
Write-host "      ➡️ Cleaning up temporary files..."
# Remove temporary files if they exist
if (Test-Path "../src/AdminSite/appsettings.Development.json") {
    Remove-Item -Path "../src/AdminSite/appsettings.Development.json" -Force
    Write-host "      ✅ Removed appsettings.Development.json"
} else {
    Write-host "      ℹ️ appsettings.Development.json not found, skipping"
}

if (Test-Path "script.sql") {
    Remove-Item -Path "script.sql" -Force
    Write-host "      ✅ Removed script.sql"
} else {
    Write-host "      ℹ️ script.sql not found, skipping"
}

#Remove-Item -Path ../Publish -recurse -Force

#endregion

#region Create SQL Private Endpoints
# Get SQL Server
$sqlServerId=az sql server show --name $SQLServerName --resource-group $ResourceGroupForDeployment --query id -o tsv

# Create a private endpoint
az network private-endpoint create --name $privateSqlEndpointName --resource-group $ResourceGroupForDeployment --vnet-name $vnetName --subnet $SqlSubnetName --private-connection-resource-id $sqlServerId --group-ids sqlServer --connection-name sqlConnection


# Create a SQL private DNS zone
az network private-dns zone create --name $privateSqlDnsZoneName --resource-group $ResourceGroupForDeployment

# Link the SQL private DNS zone to the VNet
az network private-dns link vnet create --name $privateSqlLink --resource-group $ResourceGroupForDeployment --virtual-network $vnetName --zone-name $privateSqlDnsZoneName --registration-enabled false

az network private-endpoint dns-zone-group create --resource-group $ResourceGroupForDeployment --endpoint-name $privateSqlEndpointName --name "sql-zone-group"   --private-dns-zone $privateSqlDnsZoneName   --zone-name "sqlserver"
#endregion


#region Create KV Private Endpoints
# Get KV Server
$keyVaultId=az keyvault show --name $KeyVault --resource-group $ResourceGroupForDeployment --query id -o tsv

# Create a KV private endpoint
az network private-endpoint create --name $privateKvEndpointName --resource-group $ResourceGroupForDeployment --vnet-name $vnetName --subnet $KvSubnetName --private-connection-resource-id $keyVaultId --group-ids vault  --connection-name kvConnection


# Create a KV private DNS zone
az network private-dns zone create --name $privateKvDnsZoneName --resource-group $ResourceGroupForDeployment

# Link the KV private DNS zone to the VNet
az network private-dns link vnet create --name $privateKvLink --resource-group $ResourceGroupForDeployment --virtual-network $vnetName --zone-name $privateKvDnsZoneName --registration-enabled false

az network private-endpoint dns-zone-group create --resource-group $ResourceGroupForDeployment --endpoint-name $privateKvEndpointName --name "Kv-zone-group"   --private-dns-zone $privateKvDnsZoneName   --zone-name "Kv-zone"
#endregion

#region Configure Database
Write-host "🗄️ Configure Database"
Write-host "   🔵 Deploy Database Schema and Users"
Write-host "      ➡️ Generate SQL schema/data script"
# Use SQL Server authentication for migration script generation
# This ensures migrations work reliably without Azure AD token issues
$ConnectionString="Server=tcp:"+$ServerUri+";Database="+$SQLDatabaseName+";User Id=sqladmin;Password=YourSecurePassword123!;TrustServerCertificate=True;"
Set-Content -Path ../src/AdminSite/appsettings.Development.json -value "{`"ConnectionStrings`": {`"DefaultConnection`":`"$ConnectionString`"}}"
dotnet-ef migrations script  --output script.sql --idempotent --context SaaSKitContext --project ../src/DataAccess/DataAccess.csproj --startup-project ../src/AdminSite/AdminSite.csproj
Write-host "      ➡️ Execute SQL schema/data script"
Invoke-Sqlcmd -InputFile ./script.sql -ConnectionString $ConnectionString

Write-host "      ➡️ Execute SQL script to Add WebApps"
$AddAppsIdsToDB = "CREATE USER [$WebAppNameAdmin] FROM EXTERNAL PROVIDER;ALTER ROLE db_datareader ADD MEMBER  [$WebAppNameAdmin];ALTER ROLE db_datawriter ADD MEMBER  [$WebAppNameAdmin]; GRANT EXEC TO [$WebAppNameAdmin]; CREATE USER [$WebAppNamePortal] FROM EXTERNAL PROVIDER;ALTER ROLE db_datareader ADD MEMBER [$WebAppNamePortal];ALTER ROLE db_datawriter ADD MEMBER [$WebAppNamePortal]; GRANT EXEC TO [$WebAppNamePortal];"

# Use Azure AD authentication for creating Azure AD users
Write-host "      ➡️ Using Azure AD authentication for WebApp user creation"
$AzureADConnectionString="Server=tcp:"+$ServerUri+";Database="+$SQLDatabaseName+";Authentication=Active Directory Default;TrustServerCertificate=True;"
try {
    Invoke-Sqlcmd -Query $AddAppsIdsToDB -ConnectionString $AzureADConnectionString
    Write-host "      ✅ WebApp users created successfully with Azure AD authentication"
} catch {
    Write-host "      ❌ Azure AD authentication failed: $($_.Exception.Message)"
    Write-host "      🔄 Trying alternative method..."
    
    # Alternative: Create SQL Server users instead of Azure AD users
    Write-host "      ➡️ Creating SQL Server users as fallback"
    $SQLServerUsers = "CREATE LOGIN [$WebAppNameAdmin] WITH PASSWORD = 'WebAppPassword123!'; CREATE USER [$WebAppNameAdmin] FOR LOGIN [$WebAppNameAdmin]; ALTER ROLE db_datareader ADD MEMBER [$WebAppNameAdmin]; ALTER ROLE db_datawriter ADD MEMBER [$WebAppNameAdmin]; GRANT EXEC TO [$WebAppNameAdmin]; CREATE LOGIN [$WebAppNamePortal] WITH PASSWORD = 'WebAppPassword123!'; CREATE USER [$WebAppNamePortal] FOR LOGIN [$WebAppNamePortal]; ALTER ROLE db_datareader ADD MEMBER [$WebAppNamePortal]; ALTER ROLE db_datawriter ADD MEMBER [$WebAppNamePortal]; GRANT EXEC TO [$WebAppNamePortal];"
    
    try {
        # Create logins in master database first
        $MasterConnectionString = "Server=tcp:"+$ServerUri+";Database=master;User Id=sqladmin;Password=YourSecurePassword123!;TrustServerCertificate=True;"
        $CreateLogins = "CREATE LOGIN [$WebAppNameAdmin] WITH PASSWORD = 'WebAppPassword123!'; CREATE LOGIN [$WebAppNamePortal] WITH PASSWORD = 'WebAppPassword123!';"
        Invoke-Sqlcmd -Query $CreateLogins -ConnectionString $MasterConnectionString
        
        # Create users in specific database
        Invoke-Sqlcmd -Query $SQLServerUsers -ConnectionString $ConnectionString
        Write-host "      ✅ SQL Server users created successfully as fallback"
        
        # Update connection strings to use SQL Server authentication
        $AdminConnection="Server=tcp:"+$ServerUriPrivate+";Database="+$SQLDatabaseName+";User Id="+$WebAppNameAdmin+";Password=WebAppPassword123!;TrustServerCertificate=True;"
        $PortalConnection="Server=tcp:"+$ServerUriPrivate+";Database="+$SQLDatabaseName+";User Id="+$WebAppNamePortal+";Password=WebAppPassword123!;TrustServerCertificate=True;"
        
        # Update KeyVault secrets
        az keyvault secret set --vault-name $KeyVault --name DefaultConnection --value $AdminConnection --output $azCliOutput
        az keyvault secret set --vault-name $KeyVault --name PortalConnection --value $PortalConnection --output $azCliOutput
        
        Write-host "      ✅ Updated connection strings to use SQL Server authentication"
    } catch {
        Write-host "      ❌ SQL Server user creation also failed: $($_.Exception.Message)"
        Write-host "      💡 Manual intervention required - please create users manually"
        throw
    }
}

Write-host "   🔵 Final Database Cleanup"
Write-host "      ➡️ Cleaning up database-related temporary files..."
# Remove temporary files if they exist
if (Test-Path "../src/AdminSite/appsettings.Development.json") {
    Remove-Item -Path "../src/AdminSite/appsettings.Development.json" -Force
    Write-host "      ✅ Removed appsettings.Development.json"
} else {
    Write-host "      ℹ️ appsettings.Development.json not found, skipping"
}

if (Test-Path "script.sql") {
    Remove-Item -Path "script.sql" -Force
    Write-host "      ✅ Removed script.sql"
} else {
    Write-host "      ℹ️ script.sql not found, skipping"
}
Write-host "      ✅ Database configuration completed successfully"
#endregion

#region Present Output

Write-host "✅ If the intallation completed without error complete the folllowing checklist:"
if ($ISLoginAppProvided) {  #If provided then show the user where to add the landing page in AAD, otherwise script did this already for the user.
	Write-host "   🔵 Add The following URLs to the multi-tenant Landing Page AAD App Registration in Azure Portal:"
	Write-host "      ➡️ https://$WebAppNamePrefix-portal.azurewebsites.net"
	Write-host "      ➡️ https://$WebAppNamePrefix-portal.azurewebsites.net/"
	Write-host "      ➡️ https://$WebAppNamePrefix-portal.azurewebsites.net/Home/Index"
	Write-host "      ➡️ https://$WebAppNamePrefix-portal.azurewebsites.net/Home/Index/"
	Write-host "   🔵 Add The following URLs to the multi-tenant Admin Portal AAD App Registration in Azure Portal:"
	Write-host "      ➡️ https://$WebAppNamePrefix-admin.azurewebsites.net"
	Write-host "      ➡️ https://$WebAppNamePrefix-admin.azurewebsites.net/"
	Write-host "      ➡️ https://$WebAppNamePrefix-admin.azurewebsites.net/Home/Index"
	Write-host "      ➡️ https://$WebAppNamePrefix-admin.azurewebsites.net/Home/Index/"
	Write-host "   🔵 Verify ID Tokens checkbox has been checked-out ?"
}

Write-host "   🔵 Add The following URL in PartnerCenter SaaS Technical Configuration"
Write-host "      ➡️ Landing Page section:       https://$WebAppNamePrefix-portal.azurewebsites.net/"
Write-host "      ➡️ Connection Webhook section: https://$WebAppNamePrefix-portal.azurewebsites.net/api/AzureWebhook"
Write-host "      ➡️ Tenant ID:                  $TenantID"
Write-host "      ➡️ AAD Application ID section: $ADApplicationID"
$duration = (Get-Date) - $startTime
Write-Host "Deployment Complete in $($duration.Minutes)m:$($duration.Seconds)s"
Write-Host "DO NOT CLOSE THIS SCREEN.  Please make sure you copy or perform the actions above before closing."
#endregion