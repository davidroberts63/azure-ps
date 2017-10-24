[CmdletBinding()]
param(
    $groupName = 'SomeApp-Dev',
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

#
# Create virtual network
#
Write-Host "Ensuring the $planName virtual network exists"
$vnet = Get-AzureRmVirtualNetwork -Name $planName -ResourceGroupName $groupName -ErrorAction SilentlyContinue
if(-not $vnet) {
    Write-Host "Creating the web subnet configuration for the $planName virtual network"
    $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name "web" -AddressPrefix 192.168.1.0/24
    
    Write-Host "Creating the gateway subnet configuration for the $planName virtual network"
    $gatewaySubnet = New-AzureRmVirtualNetworkSubnetConfig -Name 'gateway' -AddressPrefix 192.168.2.0/27

    Write-Host "Creating the $planName vnet"
    $vnet = New-AzureRmVirtualNetwork -Name $planName -AddressPrefix 192.168.0.0/16 -Subnet @($subnet,$gatewaySubnet) -ResourceGroupName $groupName -Location $location.location
}

Write-Host "Ensuring the web subnet exists"
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name "web" -VirtualNetwork $vnet -ErrorAction SilentlyContinue
if(-not $subnet) {
    Write-Error "The web subnet was not in the $planName virtual network. Stopping"
    return
}

Write-Host 'Ensuring the gateway subnet exists'
$gatewaySubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name 'gateway' -VirtualNetwork $vnet -ErrorAction SilentlyContinue
if(-not $gatewaySubnet) {
    Write-Host "Adding the gateway subnet to the $planName virtual network"
    $gatewaySubnet = Add-AzureRmVirtualNetworkSubnetConfig -Name 'gateway' -VirtualNetwork $vnet -AddressPrefix 192.168.2.0/27
    $vnet | Set-AzureRmVirtualNetwork
}

#
# Create public IP address
#
Write-Host "Ensuring the $groupName public ip exists"
$publicIp = Get-AzureRmPublicIpAddress -Name $groupName -ResourceGroupName $groupName -ErrorAction SilentlyContinue
if(-not $publicIp) {
    Write-Host "Creating $groupName public ip"
    $publicIp = New-AzureRmPublicIpAddress -Name $groupName -ResourceGroupName $groupName -Location $location.location -AllocationMethod Dynamic -IdleTimeoutInMinutes 4
}
$publicIp | Select Name, IpAddress

#
# Network Security Group
#
Write-Host "Ensuring the $groupName network security group exists"
$nsg = Get-AzureRmNetworkSecurityGroup -Name $groupName -ResourceGroupName $groupName -ErrorAction SilentlyContinue
if(-not $nsg) {
    Write-Host "Creating RdpRule nsg rule configuration for $groupName network security group"
    $nsgRdpRule = New-AzureRmNetworkSecurityRuleConfig -Name "RdpRule" -Protocol TCP -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow

    Write-Host "Creating the $groupName network security group"
    $nsg = New-AzureRmNetworkSecurityGroup -Name $groupName -ResourceGroupName $groupName -Location $location.location -SecurityRules $nsgRdpRule
}

#
# Network Card
#
Write-Host "Ensuring the nic1 network interface exists"
$nic = Get-AzureRmNetworkInterface -Name nic1 -ResourceGroupName $groupName -ErrorAction SilentlyContinue
if(-not $nic) {
    Write-Host 'Creating nic1 network interface'
    $nic = New-AzureRmNetworkInterface -Name nic1 -ResourceGroupName $groupName -Location $location.location -SubNetId $subnet.Id -PublicIpAddressId $publicIp.Id -NetworkSecurityGroupId $nsg.Id
}