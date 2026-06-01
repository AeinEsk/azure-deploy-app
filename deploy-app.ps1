# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE file in the project root for license information.

#
# PowerShell script to deploy application code and run database migrations
# This script assumes all Azure resources already exist
#

Param(  
   [string][Parameter(Mandatory)]$WebAppNamePrefix, # Prefix used for web applications
   [string][Parameter()]$ResourceGroupForDeployment, # Name of the resource group
   [string][Parameter()]$SQLServerName, # Name of the database server (without database.windows.net)
   [string][Parameter()]$SQLDatabaseName, # Name of the database (Defaults to AMPSaaSDB)
   [string][Parameter()]$KeyVault, # Name of KeyVault
   [string][Parameter()]$AzureSubscriptionID, # Subscription where the resources are deployed
   [switch][Parameter()]$Quiet #if set, only show error / warning output from script commands
)

$ErrorActionPreference = "Stop"
$startTime = Get-Date

Write-Host "🚀 Starting Application Deployment and Database Migration..." -ForegroundColor Green

#region Set up Variables and Default Parameters

if ($ResourceGroupForDeployment -eq "") {
    $ResourceGroupForDeployment = $WebAppNamePrefix 
}
if ($SQLServerName -eq "") {
    $SQLServerName = $WebAppNamePrefix + "-sql"
}
if ($SQLDatabaseName -eq "") {
    $SQLDatabaseName = $WebAppNamePrefix + "AMPSaaSDB"
}
if ($KeyVault -eq "") {
    $KeyVault = $WebAppNamePrefix + "-kv"
}

# Get current context if subscription not provided
if(!($AzureSubscriptionID)) {
    $currentContext = az account show | ConvertFrom-Json
    $AzureSubscriptionID = $currentContext.id
    Write-Host "🔑 Using current Azure Subscription: $AzureSubscriptionID" -ForegroundColor Yellow
} else {
    Write-Host "🔑 Azure Subscription provided: $AzureSubscriptionID" -ForegroundColor Yellow
    az account set -s $AzureSubscriptionID
}

$azCliOutput = if($Quiet){'none'} else {'json'}

# Set up resource name variables
$WebAppNameService = $WebAppNamePrefix + "-asp"
$WebAppNameAdmin = $WebAppNamePrefix + "-admin"
$WebAppNamePortal = $WebAppNamePrefix + "-portal"
$ServerUri = $SQLServerName + ".database.windows.net"
$ServerUriPrivate = $SQLServerName + ".privatelink.database.windows.net"

Write-Host "📋 Deployment Configuration:" -ForegroundColor Cyan
Write-Host "   Resource Group: $ResourceGroupForDeployment" -ForegroundColor Yellow
Write-Host "   Admin WebApp: $WebAppNameAdmin" -ForegroundColor Yellow
Write-Host "   Portal WebApp: $WebAppNamePortal" -ForegroundColor Yellow
Write-Host "   SQL Server: $SQLServerName" -ForegroundColor Yellow
Write-Host "   SQL Database: $SQLDatabaseName" -ForegroundColor Yellow
Write-Host "   KeyVault: $KeyVault" -ForegroundColor Yellow

#endregion

#region Verify Resources Exist

Write-Host "`n🔍 Verifying resources exist..." -ForegroundColor Blue

$resourcesToCheck = @(
    @{Type="Resource Group"; Name=$ResourceGroupForDeployment; Command="az group show --name $ResourceGroupForDeployment"},
    @{Type="Admin WebApp"; Name=$WebAppNameAdmin; Command="az webapp show --name $WebAppNameAdmin --resource-group $ResourceGroupForDeployment"},
    @{Type="Portal WebApp"; Name=$WebAppNamePortal; Command="az webapp show --name $WebAppNamePortal --resource-group $ResourceGroupForDeployment"},
    @{Type="SQL Server"; Name=$SQLServerName; Command="az sql server show --name $SQLServerName --resource-group $ResourceGroupForDeployment"},
    @{Type="SQL Database"; Name=$SQLDatabaseName; Command="az sql db show --name $SQLDatabaseName --server $SQLServerName --resource-group $ResourceGroupForDeployment"},
    @{Type="KeyVault"; Name=$KeyVault; Command="az keyvault show --name $KeyVault --resource-group $ResourceGroupForDeployment"}
)

foreach ($resource in $resourcesToCheck) {
    Write-Host "   ➡️ Checking $($resource.Type) '$($resource.Name)'..." -ForegroundColor Blue
    $result = Invoke-Expression "$($resource.Command) 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   ❌ $($resource.Type) '$($resource.Name)' not found!" -ForegroundColor Red
        Write-Host "      Error: $result" -ForegroundColor Red
        throw "$($resource.Type) '$($resource.Name)' does not exist. Please ensure all resources are created first."
    } else {
        Write-Host "   ✅ $($resource.Type) found" -ForegroundColor Green
    }
}

#endregion

#region Pre-checks

Write-Host "`n🔍 Running pre-checks..." -ForegroundColor Blue

# Check if dotnet 8 is installed
$dotnetversion = dotnet --version
if(!$dotnetversion.StartsWith('8.')) {
    Throw "🛑 Dotnet 8 not installed. Install dotnet8 and re-run the script."
    Exit
}
Write-Host "   ✅ .NET 8 found: $dotnetversion" -ForegroundColor Green

# Refresh Azure CLI tokens
Write-Host "   🔑 Refreshing Azure CLI tokens..." -ForegroundColor Blue
az account get-access-token --resource https://database.windows.net/ --output none
az account get-access-token --resource https://management.azure.com/ --output none
az account get-access-token --resource https://graph.microsoft.com/ --output none
Write-Host "   ✅ Azure CLI tokens refreshed" -ForegroundColor Green

#endregion

#region Prepare Code Packages

Write-Host "`n📜 Preparing publish files for the application..." -ForegroundColor Blue

if (!(Test-Path '../Publish')) {
    New-Item -ItemType Directory -Path '../Publish' -Force | Out-Null
}

Write-Host "   🔵 Preparing Admin Site..." -ForegroundColor Blue
dotnet publish ../src/AdminSite/AdminSite.csproj -c release -o ../Publish/AdminSite/ -v q
if ($LASTEXITCODE -ne 0) {
    throw "Failed to publish Admin Site"
}
Write-Host "   ✅ Admin Site prepared" -ForegroundColor Green

Write-Host "   🔵 Preparing Metered Scheduler..." -ForegroundColor Blue
dotnet publish ../src/MeteredTriggerJob/MeteredTriggerJob.csproj -c release -o ../Publish/AdminSite/app_data/jobs/triggered/MeteredTriggerJob/ -v q --runtime win-x64 --self-contained true
if ($LASTEXITCODE -ne 0) {
    throw "Failed to publish Metered Scheduler"
}
Write-Host "   ✅ Metered Scheduler prepared" -ForegroundColor Green

Write-Host "   🔵 Preparing Customer Site..." -ForegroundColor Blue
dotnet publish ../src/CustomerSite/CustomerSite.csproj -c release -o ../Publish/CustomerSite/ -v q
if ($LASTEXITCODE -ne 0) {
    throw "Failed to publish Customer Site"
}
Write-Host "   ✅ Customer Site prepared" -ForegroundColor Green

Write-Host "   🔵 Zipping packages..." -ForegroundColor Blue
if (Test-Path '../Publish/AdminSite.zip') {
    Remove-Item '../Publish/AdminSite.zip' -Force
}
if (Test-Path '../Publish/CustomerSite.zip') {
    Remove-Item '../Publish/CustomerSite.zip' -Force
}
Compress-Archive -Path ../Publish/AdminSite/* -DestinationPath ../Publish/AdminSite.zip -Force
Compress-Archive -Path ../Publish/CustomerSite/* -DestinationPath ../Publish/CustomerSite.zip -Force
Write-Host "   ✅ Packages zipped" -ForegroundColor Green

#endregion

#region Deploy Code

Write-Host "`n📦 Deploying Code..." -ForegroundColor Blue

Write-Host "   🔵 Deploying code to Admin Portal..." -ForegroundColor Blue
az webapp deploy --resource-group $ResourceGroupForDeployment --name $WebAppNameAdmin --src-path "../Publish/AdminSite.zip" --type zip --output $azCliOutput
if ($LASTEXITCODE -ne 0) {
    throw "Failed to deploy Admin Portal code"
}
Write-Host "   ✅ Admin Portal code deployed" -ForegroundColor Green
Write-Host "      ⏳ Waiting 10 seconds for deployment to complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

Write-Host "   🔵 Deploying code to Customer Portal..." -ForegroundColor Blue
az webapp deploy --resource-group $ResourceGroupForDeployment --name $WebAppNamePortal --src-path "../Publish/CustomerSite.zip" --type zip --output $azCliOutput
if ($LASTEXITCODE -ne 0) {
    throw "Failed to deploy Customer Portal code"
}
Write-Host "   ✅ Customer Portal code deployed" -ForegroundColor Green
Write-Host "      ⏳ Waiting 10 seconds for deployment to complete..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

#endregion

#region Configure Database

Write-Host "`n🗄️ Configuring Database..." -ForegroundColor Blue

Write-Host "   🔵 Deploying Database Schema and Migrations..." -ForegroundColor Blue

# Get connection string from KeyVault or use default
Write-Host "      ➡️ Retrieving connection string..." -ForegroundColor Blue
try {
    $defaultConnection = az keyvault secret show --vault-name $KeyVault --name DefaultConnection --query value -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or !$defaultConnection) {
        Write-Host "      ⚠️ Could not retrieve connection string from KeyVault, using SQL Server authentication..." -ForegroundColor Yellow
        $ConnectionString = "Server=tcp:" + $ServerUri + ";Database=" + $SQLDatabaseName + ";User Id=sqladmin;Password=YourSecurePassword123!;TrustServerCertificate=True;"
    } else {
        Write-Host "      ✅ Retrieved connection string from KeyVault" -ForegroundColor Green
        # Extract connection string from KeyVault reference or use as-is
        if ($defaultConnection -like "*KeyVault*") {
            # If it's a KeyVault reference, we need to use SQL Server auth for migrations
            $ConnectionString = "Server=tcp:" + $ServerUri + ";Database=" + $SQLDatabaseName + ";User Id=sqladmin;Password=YourSecurePassword123!;TrustServerCertificate=True;"
            Write-Host "      ⚠️ KeyVault reference found, using SQL Server authentication for migrations..." -ForegroundColor Yellow
        } else {
            $ConnectionString = $defaultConnection
        }
    }
} catch {
    Write-Host "      ⚠️ Error retrieving from KeyVault, using SQL Server authentication..." -ForegroundColor Yellow
    $ConnectionString = "Server=tcp:" + $ServerUri + ";Database=" + $SQLDatabaseName + ";User Id=sqladmin;Password=YourSecurePassword123!;TrustServerCertificate=True;"
}

Write-Host "      ➡️ Generating SQL migration script..." -ForegroundColor Blue
# Create temporary appsettings for EF migrations
Set-Content -Path ../src/AdminSite/appsettings.Development.json -value "{`"ConnectionStrings`": {`"DefaultConnection`":`"$ConnectionString`"}}"

# Generate migration script
dotnet-ef migrations script --output script.sql --idempotent --context SaaSKitContext --project ../src/DataAccess/DataAccess.csproj --startup-project ../src/AdminSite/AdminSite.csproj
if ($LASTEXITCODE -ne 0) {
    throw "Failed to generate migration script"
}
Write-Host "      ✅ Migration script generated" -ForegroundColor Green

Write-Host "      ➡️ Executing SQL migration script..." -ForegroundColor Blue
# Use Azure AD authentication for executing migrations
$AzureADConnectionString = "Server=tcp:" + $ServerUri + ";Database=" + $SQLDatabaseName + ";Authentication=Active Directory Default;TrustServerCertificate=True;"
Write-Host "      ➡️ Using Azure AD authentication..." -ForegroundColor Blue

try {
    Invoke-Sqlcmd -InputFile ./script.sql -ConnectionString $AzureADConnectionString
    Write-Host "      ✅ Database migrations executed successfully" -ForegroundColor Green
} catch {
    Write-Host "      ❌ Failed to execute migrations: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -like "*Login failed*" -or $_.Exception.Message -like "*token-identified*") {
        Write-Host "      💡 Your Azure AD account needs to be added as an Azure AD admin on the SQL Server" -ForegroundColor Yellow
        Write-Host "      💡 To add yourself as admin, run:" -ForegroundColor Yellow
        $userId = az ad signed-in-user show --query id -o tsv
        Write-Host "         az sql server ad-admin create --resource-group $ResourceGroupForDeployment --server-name $SQLServerName --display-name 'Current User' --object-id $userId" -ForegroundColor Cyan
        Write-Host "      💡 Or add yourself via Azure Portal: SQL Server '$SQLServerName' > Azure Active Directory > Set admin" -ForegroundColor Yellow
    }
    Write-Host "      💡 Alternatively, run the migrations manually using Azure Data Studio or SSMS with Azure AD auth" -ForegroundColor Yellow
    throw
}

Write-Host "      ➡️ Configuring database users for WebApps..." -ForegroundColor Blue
$AddAppsIdsToDB = "CREATE USER [$WebAppNameAdmin] FROM EXTERNAL PROVIDER;ALTER ROLE db_datareader ADD MEMBER  [$WebAppNameAdmin];ALTER ROLE db_datawriter ADD MEMBER  [$WebAppNameAdmin]; GRANT EXEC TO [$WebAppNameAdmin]; CREATE USER [$WebAppNamePortal] FROM EXTERNAL PROVIDER;ALTER ROLE db_datareader ADD MEMBER [$WebAppNamePortal];ALTER ROLE db_datawriter ADD MEMBER [$WebAppNamePortal]; GRANT EXEC TO [$WebAppNamePortal];"

# Try Azure AD authentication first
$AzureADConnectionString = "Server=tcp:" + $ServerUri + ";Database=" + $SQLDatabaseName + ";Authentication=Active Directory Default;TrustServerCertificate=True;"
try {
    Write-Host "      ➡️ Attempting Azure AD authentication..." -ForegroundColor Blue
    Invoke-Sqlcmd -Query $AddAppsIdsToDB -ConnectionString $AzureADConnectionString
    Write-Host "      ✅ WebApp users created successfully with Azure AD authentication" -ForegroundColor Green
} catch {
    Write-Host "      ⚠️ Azure AD authentication failed: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "      ➡️ Users may already exist or need to be created manually" -ForegroundColor Yellow
    Write-Host "      💡 You can verify users in SQL Server Management Studio" -ForegroundColor Yellow
    # Don't throw here - users might already exist
}

# Cleanup temporary files
Write-Host "      ➡️ Cleaning up temporary files..." -ForegroundColor Blue
if (Test-Path "../src/AdminSite/appsettings.Development.json") {
    Remove-Item -Path "../src/AdminSite/appsettings.Development.json" -Force
}
if (Test-Path "script.sql") {
    Remove-Item -Path "script.sql" -Force
}
Write-Host "      ✅ Cleanup completed" -ForegroundColor Green

Write-Host "   ✅ Database configuration completed" -ForegroundColor Green

#endregion

#region Summary

$duration = (Get-Date) - $startTime
Write-Host "`n✅ Deployment Complete!" -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "⏱️  Duration: $($duration.Minutes)m:$($duration.Seconds)s" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "`n📋 Deployment Summary:" -ForegroundColor Cyan
Write-Host "   ✅ Admin Portal deployed: https://$WebAppNameAdmin.azurewebsites.net" -ForegroundColor Green
Write-Host "   ✅ Customer Portal deployed: https://$WebAppNamePortal.azurewebsites.net" -ForegroundColor Green
Write-Host "   ✅ Database migrations executed" -ForegroundColor Green
Write-Host "`n💡 Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Verify the applications are running correctly" -ForegroundColor White
Write-Host "   2. Check application logs if you encounter any issues" -ForegroundColor White
Write-Host "   3. Verify database users have proper permissions" -ForegroundColor White

#endregion

