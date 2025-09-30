# Azure AD App Registration Creation Script
# This script requires Global Administrator or Application Administrator privileges
# Run this script with elevated privileges in Azure Cloud Shell or with proper permissions

param(
    [Parameter(Mandatory=$true)]
    # [string]$SubscriptionId ="a2314f4b-7f4d-4222-9561-5e56999d1807",
    [string]$SubscriptionId ="f29144a9-edfd-4457-addf-467bfe4b36a7",

    [Parameter(Mandatory=$false)]
    [string]$TenantId = "5039811d-facd-4588-be65-44a2ecd7fae1",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev"
)

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting Azure AD App Registration Creation" -ForegroundColor Green
Write-Host "Subscription ID: $SubscriptionId" -ForegroundColor Yellow
Write-Host "Environment: $Environment" -ForegroundColor Yellow

try {
    # Set the subscription context
    Write-Host "📋 Setting Azure subscription context..." -ForegroundColor Blue
    az account set --subscription $SubscriptionId
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to set subscription context"
    }
    
    # Get current subscription info
    $subscriptionInfo = az account show --query "{name:name, id:id}" -o json | ConvertFrom-Json
    Write-Host "✅ Connected to subscription: $($subscriptionInfo.name)" -ForegroundColor Green
    
    # Set tenant context if provided
    if ($TenantId) {
        Write-Host "🏢 Setting tenant context..." -ForegroundColor Blue
        az account set --subscription $SubscriptionId --tenant $TenantId
    }
    
    # Function to create app registration
    function Create-AppRegistration {
        param(
            [string]$DisplayName,
            [string]$IdentifierUri,
            [string]$ReplyUrl = "",
            [string]$LogoutUrl = "",
            [string]$Description = ""
        )
        
        Write-Host "🔑 Creating $DisplayName App Registration..." -ForegroundColor Blue
        
        # Build the command
        $createCommand = "az ad app create --display-name `"$DisplayName`" --identifier-uris `"$IdentifierUri`""
        
        if ($ReplyUrl) {
            $createCommand += " --reply-urls `"$ReplyUrl`""
        }
        
        if ($LogoutUrl) {
            $createCommand += " --logout-url `"$LogoutUrl`""
        }
        
        if ($Description) {
            $createCommand += " --description `"$Description`""
        }
        
        # Execute the command
        $result = Invoke-Expression $createCommand
        
        if ($LASTEXITCODE -eq 0) {
            $appInfo = $result | ConvertFrom-Json
            Write-Host "✅ $DisplayName App Registration created successfully" -ForegroundColor Green
            Write-Host "   ➡️ Application ID: $($appInfo.appId)" -ForegroundColor Cyan
            Write-Host "   ➡️ Object ID: $($appInfo.id)" -ForegroundColor Cyan
            
            # Create client secret
            Write-Host "🔐 Creating client secret for $DisplayName..." -ForegroundColor Blue
            $secretResult = az ad app credential reset --id $appInfo.appId --query "{appId:appId, password:password}" -o json | ConvertFrom-Json
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Client secret created for $DisplayName" -ForegroundColor Green
                Write-Host "   ➡️ Client Secret: $($secretResult.password)" -ForegroundColor Red
                Write-Host "   ⚠️  IMPORTANT: Save this secret securely!" -ForegroundColor Yellow
            } else {
                Write-Host "❌ Failed to create client secret for $DisplayName" -ForegroundColor Red
            }
            
            return @{
                AppId = $appInfo.appId
                ObjectId = $appInfo.id
                ClientSecret = $secretResult.password
            }
        } else {
            Write-Host "❌ Failed to create $DisplayName App Registration" -ForegroundColor Red
            return $null
        }
    }
    
    # Create app registrations
    $apps = @()
    
    # 1. Fulfilment API App Registration
    $fulfilmentApi = Create-AppRegistration -DisplayName "FulfilmentAPI-$Environment" -IdentifierUri "api://fulfilment-$Environment" -Description "Fulfilment API for $Environment environment"
    if ($fulfilmentApi) {
        $apps += @{
            Name = "FulfilmentAPI"
            AppId = $fulfilmentApi.AppId
            ClientSecret = $fulfilmentApi.ClientSecret
        }
    }
    
    # 2. Admin Portal SSO App Registration
    $adminPortal = Create-AppRegistration -DisplayName "AdminPortal-SSO-$Environment" -IdentifierUri "https://admin-portal-$Environment" -ReplyUrl "https://admin-portal-$Environment/auth/callback" -LogoutUrl "https://admin-portal-$Environment/auth/logout" -Description "Admin Portal SSO for $Environment environment"
    if ($adminPortal) {
        $apps += @{
            Name = "AdminPortal-SSO"
            AppId = $adminPortal.AppId
            ClientSecret = $adminPortal.ClientSecret
        }
    }
    
    # 3. Landing Page SSO App Registration
    $landingPage = Create-AppRegistration -DisplayName "LandingPage-SSO-$Environment" -IdentifierUri "https://landing-page-$Environment" -ReplyUrl "https://landing-page-$Environment/auth/callback" -LogoutUrl "https://landing-page-$Environment/auth/logout" -Description "Landing Page SSO for $Environment environment"
    if ($landingPage) {
        $apps += @{
            Name = "LandingPage-SSO"
            AppId = $landingPage.AppId
            ClientSecret = $landingPage.ClientSecret
        }
    }
    
    # Generate configuration file
    Write-Host "📄 Generating configuration file..." -ForegroundColor Blue
    $config = @{
        Environment = $Environment
        SubscriptionId = $SubscriptionId
        TenantId = $TenantId
        Apps = $apps
        CreatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    
    $configJson = $config | ConvertTo-Json -Depth 3
    $configFile = "azure-apps-config-$Environment.json"
    $configJson | Out-File -FilePath $configFile -Encoding UTF8
    
    Write-Host "✅ Configuration saved to: $configFile" -ForegroundColor Green
    
    # Summary
    Write-Host "`n🎉 Azure AD App Registration Creation Complete!" -ForegroundColor Green
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "Environment: $Environment" -ForegroundColor Yellow
    Write-Host "Subscription: $($subscriptionInfo.name)" -ForegroundColor Yellow
    Write-Host "Total Apps Created: $($apps.Count)" -ForegroundColor Yellow
    Write-Host "=" * 60 -ForegroundColor Cyan
    
    foreach ($app in $apps) {
        Write-Host "`n📱 $($app.Name):" -ForegroundColor Blue
        Write-Host "   App ID: $($app.AppId)" -ForegroundColor Cyan
        Write-Host "   Client Secret: $($app.ClientSecret)" -ForegroundColor Red
    }
    
    Write-Host "`n⚠️  IMPORTANT SECURITY NOTES:" -ForegroundColor Yellow
    Write-Host "1. Store client secrets securely (Azure Key Vault recommended)" -ForegroundColor Yellow
    Write-Host "2. Rotate secrets regularly" -ForegroundColor Yellow
    Write-Host "3. Use environment-specific configurations" -ForegroundColor Yellow
    Write-Host "4. Review and configure API permissions as needed" -ForegroundColor Yellow
    
} catch {
    Write-Host "❌ Error occurred: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ Script completed successfully!" -ForegroundColor Green
