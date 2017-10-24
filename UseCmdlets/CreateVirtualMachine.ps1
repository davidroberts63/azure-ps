[Cmdletbinding()]
param(
    $resourceGroupName = 'powershell-play',
    $resourcePrefix = 'spider'
)

Write-Host "Importing AzureRm"
Import-Module AzureRm

#
# Login
#

Write-Host "Checking to see if already logged into Azure"
$context = Get-AzureRmContext
if(!$context) {
    Write-Host "Logging in"
    Login-AzureRmAccount | Write-Output
} else {
    Write-Host "Already logged in"
}

Write-Host 'Checking we are on the MSDN subscription'
if($context.Subscription.Name -ne 'Windows Azure  MSDN - Visual Studio Premium') {
    Write-Host 'Switching to MSDN subscription'
    Select-AzureRmSubscription -SubscriptionName 'Windows Azure  MSDN - Visual Studio Premium'

    Write-Host 'Double checking subscription'
    if((Get-AzureRmContext).Subscription.Name -ne 'Windows Azure  MSDN - Visual Studio Premium') {
        Write-Error 'Could not switch to the MSDN subscription, exiting'
    }
}

#
# Get and verify location
#
$location = Get-AzureRmLocation | Where DisplayName -eq 'South Central US' | Select -First 1
if(!$location) { 
    Write-Error 'Could not get and verify the location the resources would be placed within'
    return
}

#
# Create virtual network
#
$subnet = New-AzureRmVirtualNetworkSubnetConfig -Name "$($resourcePrefix)-frontend" -AddressPrefix 192.168.1.0/24
$vnet = New-AzureRmVirtualNetwork -Name $resourcePrefix -AddressPrefix 192.168.0.0/16 -Subnet $subnet -ResourceGroupName $resourceGroupName -Location $location

#
# Create public IP address
#
$publicIp = New-AzureRmPublicIpAddress -Name $resourcePrefix -ResourceGroupName $resourceGroupName -Location $location -AllocationMethod Dynamic -IdleTimeoutInMinutes 2
$publicIp | Select Name, IpAddress

#
# Network Security Group
#
$nsgRdpRule = New-AzureRmNetworkSecurityRuleConfig -Name "RdpRule" -Protocol TCP -Direction Inbound -Priority 1000 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
$nsg = New-AzureRmNetworkSecurityGroup -Name $resourcePrefix -ResourceGroupName $resourceGroupName -Location $location -SecurityRules $nsgRdpRule

#
# Network Card
#
$nic = New-AzureRmNetworkInterface -Name nic1 -ResourceGroupName $resourceGroupName -Location $location -SubNetId $subnet.Id -PublicIpAddressId $publicIp.Id -NetworkSecurityGroupId $nsg.Id

