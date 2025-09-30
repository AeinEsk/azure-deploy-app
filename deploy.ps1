# Azure AD App Registration Creation Script
# This script requires Global Administrator or Application Administrator privileges
# Run this script with elevated privileges in Azure Cloud Shell or with proper permissions

param(
    [Parameter(Mandatory=$false)]
    [string]$WebAppNamePrefix = "mp-subscription",
    
    [Parameter(Mandatory=$false)]
    [string]$TenantId,
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$LogoURLpng = ""
)

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Host "🚀 Starting Azure AD App Registration Creation" -ForegroundColor Green
Write-Host "Web App Name Prefix: $WebAppNamePrefix" -ForegroundColor Yellow
Write-Host "Environment: $Environment" -ForegroundColor Yellow

try {
    # Get current context
    $currentContext = az account show | ConvertFrom-Json
    $currentTenant = $currentContext.tenantId
    $currentSubscription = $currentContext.id
    
    # Get TenantID if not set as argument
    if(!($TenantId)) {    
        Write-Host "🔑 Tenant ID not provided, using current tenant: $currentTenant" -ForegroundColor Blue
        $TenantId = $currentTenant
    }
    else {
        Write-Host "🔑 Tenant provided: $TenantId" -ForegroundColor Blue
    }
    
    Write-Host "Tenant ID: $TenantId" -ForegroundColor Yellow
    
    # Set tenant context if different from current
    if ($currentTenant -ne $TenantId) {
        Write-Host "🏢 Switching to tenant: $TenantId" -ForegroundColor Blue
        az login --tenant $TenantId --use-device-code
    } else {
        Write-Host "✅ Already authenticated with correct tenant" -ForegroundColor Green
    }
    
    # Function to create FulfilmentAPI app registration (simple method)
    function Create-FulfilmentAPI {
        param(
            [string]$DisplayName
        )
        
        Write-Host "🔑 Creating $DisplayName App Registration..." -ForegroundColor Blue
        
        try {
            $ADApplication = az ad app create --only-show-errors --sign-in-audience AzureADMYOrg --display-name $DisplayName | ConvertFrom-Json
            $ADObjectID = $ADApplication.id
            $ADApplicationID = $ADApplication.appId
            sleep 5 # Give time to AAD to register
            
            # Create service principal
            az ad sp create --id $ADApplicationID
            $ADApplicationSecret = az ad app credential reset --id $ADObjectID --append --display-name 'SaaSAPI' --years 2 --query password --only-show-errors --output tsv
            
            Write-Host "   🔵 $DisplayName App Registration created." -ForegroundColor Green
            Write-Host "      ➡️ Application ID: $ADApplicationID" -ForegroundColor Cyan
            
            return @{
                AppId = $ADApplicationID
                ObjectId = $ADObjectID
                ClientSecret = $ADApplicationSecret
            }
        }
        catch {
            Write-Host "   ❌ Failed to create $DisplayName App Registration" -ForegroundColor Red
            Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    
    # Function to create SSO app registration (Graph API method)
    function Create-SSOAppRegistration {
        param(
            [string]$DisplayName,
            [string]$SignInAudience,
            [string]$RedirectUris,
            [string]$LogoutUrl
        )
        
        Write-Host "🔑 Creating $DisplayName App Registration..." -ForegroundColor Blue
        
        try {
            $appCreateRequestBodyJson = @"
{
    "displayName" : "$DisplayName",
    "api": 
    {
        "requestedAccessTokenVersion" : 2
    },
    "signInAudience" : "$SignInAudience",
    "web":
    { 
        "redirectUris": 
        [
            $RedirectUris
        ],
        "logoutUrl": "$LogoutUrl",
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
                # On Windows, escape quotes and remove new lines
                $appCreateRequestBodyJson = $appCreateRequestBodyJson.replace('"','\"').replace("`r`n","")
            }
            
            $appReg = $(az rest --method POST --headers "Content-Type=application/json" --uri https://graph.microsoft.com/v1.0/applications --body $appCreateRequestBodyJson) | ConvertFrom-Json
            
            $AppId = $appReg.appId
            $ObjectId = $appReg.id
            
            Write-Host "   🔵 $DisplayName App Registration created." -ForegroundColor Green
            Write-Host "      ➡️ Application ID: $AppId" -ForegroundColor Cyan
            
            # Set logo if provided
            if ($LogoURLpng) {
                Write-Host "      ➡️ Setting application logo..." -ForegroundColor Blue
                $token = (az account get-access-token --resource "https://graph.microsoft.com" --query accessToken --output tsv)
                $logoWeb = Invoke-WebRequest $LogoURLpng
                $logoContentType = $logoWeb.Headers["Content-Type"]
                $logoContent = $logoWeb.Content
                
                $uploaded = Invoke-WebRequest `
                    -Uri "https://graph.microsoft.com/v1.0/applications/$ObjectId/logo" `
                    -Method "PUT" `
                    -Header @{"Authorization"="Bearer $token";"Content-Type"="$logoContentType";} `
                    -Body $logoContent
                
                Write-Host "      ➡️ Application logo set." -ForegroundColor Green
            }
            
            return @{
                AppId = $AppId
                ObjectId = $ObjectId
                ClientSecret = "" # SSO apps don't need client secrets
            }
        }
        catch {
            Write-Host "   ❌ Failed to create $DisplayName App Registration" -ForegroundColor Red
            Write-Host "      Error: $($_.Exception.Message)" -ForegroundColor Red
            return $null
        }
    }
    
    # Create app registrations
    $apps = @()
    
    # 1. Fulfilment API App Registration (simple method)
    $fulfilmentApi = Create-FulfilmentAPI -DisplayName "$WebAppNamePrefix-FulfillmentAppReg"
    if ($fulfilmentApi) {
        $apps += @{
            Name = "FulfilmentAPI"
            AppId = $fulfilmentApi.AppId
            ClientSecret = $fulfilmentApi.ClientSecret
        }
    }
    
    # 2. Admin Portal SSO App Registration (Graph API method)
    $adminRedirectUris = @"
            "https://$WebAppNamePrefix-admin.azurewebsites.net",
            "https://$WebAppNamePrefix-admin.azurewebsites.net/",
            "https://$WebAppNamePrefix-admin.azurewebsites.net/Home/Index",
            "https://$WebAppNamePrefix-admin.azurewebsites.net/Home/Index/"
"@
    $adminPortal = Create-SSOAppRegistration -DisplayName "$WebAppNamePrefix-AdminPortalAppReg" -SignInAudience "AzureADMyOrg" -RedirectUris $adminRedirectUris -LogoutUrl "https://$WebAppNamePrefix-admin.azurewebsites.net/logout"
    if ($adminPortal) {
        $apps += @{
            Name = "AdminPortal-SSO"
            AppId = $adminPortal.AppId
            ClientSecret = $adminPortal.ClientSecret
        }
    }
    
    # 3. Landing Page SSO App Registration (Graph API method)
    $landingRedirectUris = @"
            "https://$WebAppNamePrefix-portal.azurewebsites.net",
            "https://$WebAppNamePrefix-portal.azurewebsites.net/",
            "https://$WebAppNamePrefix-portal.azurewebsites.net/Home/Index",
            "https://$WebAppNamePrefix-portal.azurewebsites.net/Home/Index/"
"@
    $landingPage = Create-SSOAppRegistration -DisplayName "$WebAppNamePrefix-LandingpageAppReg" -SignInAudience "AzureADandPersonalMicrosoftAccount" -RedirectUris $landingRedirectUris -LogoutUrl "https://$WebAppNamePrefix-portal.azurewebsites.net/logout"
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
        WebAppNamePrefix = $WebAppNamePrefix
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
    Write-Host "Web App Name Prefix: $WebAppNamePrefix" -ForegroundColor Yellow
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
