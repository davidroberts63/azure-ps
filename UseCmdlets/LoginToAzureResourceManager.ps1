[CmdletBinding()]
param(
    $name = 'powershell-play'
)

Write-Host "Importing AzureRm"
Import-Module AzureRm

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

Write-Host "Done"