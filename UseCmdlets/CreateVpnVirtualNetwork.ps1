[CmdletBinding()]
param(
    $subscriptionName = 'Windows Azure  MSDN - Visual Studio Premium',
    $vnetName = 'VNet1',
    $vnetSpace = '10.10.0.0/25',
    $subnetName = 'default',
    $subnetSpace = '10.10.0.0/26',
    $groupName = 'TestRG',
    $location = 'South Central US',
    $gatewaySpace = '10.10.0.96/27',
    $gatewayName = 'VNet1GW',
    $gatewayIpName = 'VNet1GWIP',
    $gatewayType = 'VPN',
    $vpnType = 'Route-Based',
    $publicIpName = 'VNet1GWpip',
    $connectionType = 'Point-to-site',
    $clientPool = '10.10.0.128/26'
)

<#
https://codehollow.com/2016/12/connect-azure-app-service-to-virtual-network/

Azure address space: 10.10.0.0/24 (10.10.0.0 – 10.10.0.255)
Virtual network: 10.10.0.0/25 (10.10.0.0 – 10.10.0.127)
Default subnet: 10.10.0.0/26 (10.10.0.0 – 10.10.0.63)
Free space: 10.10.0.64/27 (10.10.0.64 – 10.10.0.95) – for future use like backend subnet or any others
Gateway subnet: 10.10.0.96/27 (10.10.0.96 – 10.10.0.127)
Point-to-site space: 10.10.0.128/26 (10.10.0.128 – 10.10.0.191)
Free space: 10.10.0.192/26 (10.10.0.192 – 10.10.0.255) – fur future use – can be added to virtual network or for additional virtual network gateways
#>

$ErrorActionPreference = 'STOP'
Write-Host 'Importing AzureRM'
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
    Write-Host 'Already logged in'
}

#
# Subscription
#
Write-Host 'Verifying subscription in use'
if($context.Subscription.Name -ne $subscriptionName) {
    Set-AzureRmContext -Subscription $subscriptionName
    $context = Get-AzureRmContext
    if($context.Subscription.Name -ne $subscriptionName) {
        Write-Error 'Unable to switch to the subscription'
        return;
    }
}

#
# Location
#
Write-Host 'Verifying location is valid'
$location = Get-AzureRmLocation | Where DisplayName -eq $location | Select -First 1
if(-not $location) {
    Write-Error 'The location is not known.'
    return;
}

#
# Resource group
#
Write-Host 'Ensuring the resource group exists'
if(-not (Get-AzureRmResourceGroup -Name $groupName -ErrorAction SilentlyContinue)) {
    Write-Host "  Creating the $groupName resource group"
    New-AzureRmResourceGroup -Name $groupName -Location $location.Location
}

#
# Virtual Network
#
Write-Host "Ensuring the $vnetName virtual network exists"
$vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $groupName -ErrorAction SilentlyContinue
if(-not $vnet) {
    Write-Host "  Creating the $subnetName subnet configuration"
    $subnet = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetName -AddressPrefix $subnetSpace
    
    Write-Host "  Creating the GatewaySubnet configuration"
    $gatewaySubnet = New-AzureRmVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -AddressPrefix $gatewaySpace

    Write-Host "  Creating the $vnetName vnet"
    $vnet = New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $groupName -Location $location.Location -AddressPrefix $vnetSpace -Subnet @($subnet,$gatewaySubnet) -WarningAction SilentlyContinue
}

$gatewaySubnet = $vnet.Subnets | Where Name -eq 'GatewaySubnet' | Select -First 1
if(-not $gatewaySubnet) {
    Write-Error "  Couldn't get the 'GatewaySubnet'"
    return;
}

#
# IP address for VPN Gateway
#
Write-Host "Ensuring the $publicIpName public ip address exists"
$pip = Get-AzureRmPublicIpAddress -Name $publicIpName -ResourceGroupName $groupName -ErrorAction SilentlyContinue
if(-not $pip) {
    Write-Host "  Creating the $publicIpName public ip address"
    $pip = New-AzureRmPublicIpAddress -Name $publicIpName -ResourceGroupName $groupName -Location $location.location -AllocationMethod Dynamic -WarningAction SilentlyContinue
}

#
# VPN Gateway
#
Write-Host "Ensuring the $gatewayName vpn gateway exists"
$gateway = Get-AzureRmVirtualNetworkGateway -Name $gatewayName -ResourceGroupName $groupName -ErrorAction SilentlyContinue
if(-not $gateway) {
    Write-Host "  Creating the $gatewayIpName vpn gateway ip configuration"
    $gatewayIpConfig = New-AzureRmVirtualNetworkGatewayIpConfig -Name $gatewayIpName -Subnet $gatewaySubnet -PublicIpAddress $pip
    
    Write-Host "  Creating the $gatewayname vpn gateway (this *WILL* take a while, 30 minutes, maybe 45, so wait. Yes, keep waiting.)"
    $gateway = New-AzureRmVirtualNetworkGateway -Name $gatewayName -ResourceGroupName $groupName -Location $location.location -IpConfiguration $gatewayIpConfig -GatewayType Vpn -VpnType RouteBased -EnableBgp $false -GatewaySku VpnGw1 -VpnClientProtocol SSTP -WarningAction SilentlyContinue

    Write-Host 'Setting client address pool for VPN gateway'
    Set-AzureRmVirtualNetworkGateway -VirtualNetworkGateway $gateway -VpnClientAddressPool $clientPool
}

#
# Root certificate
#
Write-Host 'Ensuring self signed root certificate exists'
$rootCert = DIR 'Cert:\CurrentUser\My' | Where Subject -eq 'CN=P2SRootCertDJR' | Select -First 1
if(-not $rootCert) {
    Write-Host '  Creating new self signed root certificate'
    $rootCert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
        -Subject 'CN=P2SRootCertDJR' -KeyExportPolicy Exportable `
        -HashAlgorithm sha256 -KeyLength 2048 `
        -CertStoreLocation 'Cert:\CurrentUser\My' -KeyUsageProperty Sign -KeyUsage CertSign
}

Write-Host '  Exporting root certificate'
$base64 = '-----BEGIN CERTIFICATE-----' `
    + [Convert]::ToBase64String( $rootCert.Export('Cert') ) `
    + '-----END CERTIFICATE-----'
Set-Content -Path .\root-cert.cer -Encoding ascii -Value $base64 -Force

#
# Client Certificate
#
Write-Host 'Ensuring client certificate exists'
$clientCert = DIR 'Cert:\CurrentUser\My' | Where Subject -eq 'CN=P2SClientCertMercury' | Select -First 1
if(-not $clientCert) {
    Write-Host '  Creating client cert using root cert'
    $clientCert = New-SelfSignedCertificate -Type Custom -KeySpec Signature `
        -Subject 'CN=P2SClientCertMercury' -KeyExportPolicy Exportable `
        -HashAlgorithm sha256 -KeyLength 2048 `
        -CertStoreLocation 'Cert:\CurrentUser\My' `
        -Signer $rootCert -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.2')
}

#
# Root cert public key to VPN gateway
#
Write-Host 'Ensuring vpn root certificate exists'
$vpnRootCert = Get-AzureRmVpnClientRootCertificate -VpnClientRootCertificateName $rootCert.Subject.Replace('CN=','') -VirtualNetworkGatewayName $gatewayName -ResourceGroupName $groupName -ErrorAction SilentlyContinue
if(-not $vpnRootCert) {
    Write-Host '  Uploading root certificate public key to vpn'
    $vpnRootCert = Add-AzureRmVpnClientRootCertificate -VpnClientRootCertificateName $rootCert.Subject.Replace('CN=','') `
        -PublicCertData ([Convert]::ToBase64String($rootCert.RawData)) `
        -VirtualNetworkGatewayName $gatewayName `
        -ResourceGroupName $groupName
}

#
# VPN client configuration
#
Write-Host 'Generating vpn client configuration files'
$profile = New-AzureRmVpnClientConfiguration -ResourceGroupName $groupname -Name $gatewayName -AuthenticationMethod EAPTLS
Invoke-WebRequest $profile.VPNProfileSAsUrl -OutFile .\vpnconfig.zip
Expand-Archive -Path .\vpnconfig.zip -DestinationPath .\VpnConfiguration

Write-Host 'Done'