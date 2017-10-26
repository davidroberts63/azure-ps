[CmdletBinding()]
param(
    $groupName = 'TestRG',
    $locationName = 'South Central US',
    $planName = 'SomeApp',
    $webAppName = 'SomeAppUi',
    $apiAppName = 'SomeAppApi',
    $webNetName = 'WebNet'
)

<#

Thanks to the authors of the following articles:

https://blogs.msdn.microsoft.com/benjaminperkins/2017/10/02/create-an-azure-app-service-web-app-using-powershell/
https://codehollow.com/2016/12/connect-azure-app-service-to-virtual-network/
https://docs.microsoft.com/en-us/azure/app-service/web-sites-integrate-with-vnet

This one has a good comparison of App Service Plans and App Service Environments
https://blog.kloud.com.au/2016/04/05/when-to-use-an-azure-app-service-environment/

Here are some on VPN Gateways
https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-create-site-to-site-rm-powershell
https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpn-devices

Creating an internal only App Service Environment
https://docs.microsoft.com/en-us/azure/app-service/environment/create-ilb-ase
#>

$ErrorActionPreference = 'STOP'
Write-Host 'Importing AzureRm'
Import-Module AzureRm

#
# Login
#

Write-Host 'Checking to see if already logged into Azure'
$context = Get-AzureRmContext
if(-not $context.Account) {
    Write-Host 'Logging into Azure'
    Login-AzureRmAccount
} else {
    Write-Host 'Already logged into Azure'
}

Write-Host 'Checking we are in the MSDN subscription'
if($context.Subscription.Name -ne 'Windows Azure  MSDN - Visual Studio Premium') {
    Write-Host "Switching to MSDN subscription (from $($context.Subscription.Name))"
    Set-AzureRmContext -Subscription 'Windows Azure  MSDN - Visual Studio Premium'

    Write-Host 'Double checking subscription'
    if((Get-AzureRmContext).Subscription.Name -ne 'Windows Azure  MSDN - Visual Studio Premium') {
        Write-Error 'Unable to switch to MSDN subscription. Stopping'
        return
    }
}

#
# Location
#
Write-Host 'Verifying location is valid'
$location = Get-AzureRmLocation | Where DisplayName -eq $locationName | Select -First 1
if(-not $location) {
    Write-Error "The $locationName is unknown. Stopping"
    return
}

#
# Resource group
#

Write-Host "Ensuring the $groupName resource group exists"
if(-not (Get-AzureRmResourceGroup -Name $groupName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating $groupName resource group"
    New-AzureRmResourceGroup -Name $groupName -Location $location.Location
}

#
# App Service Plan
#
Write-Host "Ensuring the $planName app service plan exists"
$plan = Get-AzureRmAppServicePlan -Name $planName -ResourceGroupName $groupName -ErrorAction SilentlyContinue
if(-not $plan) {
    Write-Host "Creating $planName app service plan"
    $plan = New-AzureRmAppServicePlan -Name $planName -ResourceGroupName $groupName -Location $location.Location -Tier Standard -WorkerSize Small
}
#
# Web App
#
Write-Host "Ensuring the $webAppName web app exists in the $planName app service plan"
$webApp = (Get-AzureRmWebApp -AppServicePlan $plan) | Where Name -eq $webAppName | Select -First 1
if(-not $webApp) {
    Write-Host "Creating the $webAppName web app in the $planName app service plan"
    New-AzureRmWebApp -AppServicePlan $plan.Name -ResourceGroupName $groupName -Name $webAppName -Location $location.Location
}

#
# Api App
#
Write-Host "Ensuring the $apiAppName api app exists in the $planName app service plan"
$apiApp = (Get-AzureRmWebApp -AppServicePlan $plan) | Where Name -eq $apiAppName | Select -First 1
if(-not $apiApp) {
    Write-Host "Creating the $apiAppName web app in the $planName app service plan"
    New-AzureRmWebApp -AppServicePlan $plan.Name -ResourceGroupName $groupName -Name $apiAppName -Location $location.Location
}