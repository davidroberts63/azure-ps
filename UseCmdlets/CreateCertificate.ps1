<#
Used the following article, many thanks. Well written:

https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-certificates-point-to-site
#>

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
