#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
Minimal AD + AD FS setup to demonstrate the AWS Advanced JDBC Wrapper's federatedAuth plugin.

.DESCRIPTION
Runs on the Windows Server domain controller deployed by the sample AWS CDK stack. It
configures the Active Directory and AD FS resources needed by the federatedAuth stage.

Each step checks whether its resource already exists and skips completed work, so the script
can be run again after a failure or required Windows restart.

This is a DEMO script for a disposable domain controller. It favours readability over the
production-grade safety checks you would want on a long-lived, shared server.

.EXAMPLE
.\setup-adfs.ps1 -AwsAccountId "123456789012" -SamlProviderName "ADFS"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^\d{12}$')]
    [string]$AwsAccountId,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$SamlProviderName = 'ADFS',

    # Leave empty to use this domain controller's actual domain (recommended). Only set it
    # to override, and it must match the DC's real domain.
    [string]$DomainDnsName    = '',
    [string]$DemoUser         = 'bob',
    [string]$ServiceAccount   = 'adfssvc',
    [string]$AwsGroup         = 'AWS-JDBCDemo',
    [string]$MetadataPath     = "$env:USERPROFILE\Desktop\FederationMetadata.xml",

    # A dcpromo domain controller is its own DNS server and may not resolve external
    # AWS hostnames. The VPC resolver (.2 of the VPC / link-local below) fixes that.
    [string]$VpcDnsForwarder  = '169.254.169.253'
)

$ErrorActionPreference = 'Stop'

# ServerManager is available only to 64-bit Windows PowerShell. Fleet Manager or a
# 32-bit parent process can open the SysWOW64 edition, and PowerShell 7 does not load
# Windows Server modules directly. Relaunch this script in the correct host before any
# setup steps or password prompts run.
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess) {
    $systemDirectory = if ([Environment]::Is64BitProcess) { 'System32' } else { 'Sysnative' }
    $windowsPowerShell = Join-Path $env:WINDIR "$systemDirectory\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path $windowsPowerShell)) {
        throw "Unable to find 64-bit Windows PowerShell at '$windowsPowerShell'."
    }

    $forwardedArguments = @('-NoProfile', '-File', $PSCommandPath)
    $scriptParameterNames = @(
        'AwsAccountId', 'SamlProviderName', 'DomainDnsName', 'DemoUser',
        'ServiceAccount', 'AwsGroup', 'MetadataPath', 'VpcDnsForwarder'
    )
    foreach ($parameterName in $scriptParameterNames) {
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            $forwardedArguments += "-$parameterName"
            $forwardedArguments += [string]$PSBoundParameters[$parameterName]
        }
    }

    Write-Host 'Restarting setup in 64-bit Windows PowerShell...' -ForegroundColor Cyan
    & $windowsPowerShell @forwardedArguments
    exit $LASTEXITCODE
}

Import-Module ServerManager -ErrorAction Stop

$AdfsHostLabel  = 'adfs'
$RoleSuffix     = $AwsGroup -replace '^AWS-', ''          # AWS-JDBCDemo -> JDBCDemo
$IamRoleName    = "ADFS-$RoleSuffix"                      # -> ADFS-JDBCDemo
$RpIdentifier   = 'urn:amazon:webservices'
$AwsSamlUrl     = 'https://signin.aws.amazon.com/saml'
# $DomainDnsName and $FederationName are resolved after the domain controller check (Step 1),
# where Get-ADDomain is available, so they always match this DC's real domain.

function Step { param([string]$n) Write-Host "`n=== $n ===" -ForegroundColor Cyan }
function Done { param([string]$m) Write-Host "  [done] $m" -ForegroundColor Green }
function Skip { param([string]$m) Write-Host "  [skip] $m" -ForegroundColor DarkGray }

# AWS endpoints require TLS 1.2; Windows Server 2016 does not default to it.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Import-Module ActiveDirectory
Import-Module DnsServer

# ----------------------------------------------------------------------------
# Step 1: Confirm we are on a domain controller (the CloudFormation stack ran dcpromo)
# ----------------------------------------------------------------------------
Step '1. Domain controller check'
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.DomainRole -notin 4, 5) {
    throw "This server is not a domain controller. Run this on the DC created by the demo stack."
}
Done "Domain controller in $($cs.Domain)"

# Resolve the domain from THIS DC. If -DomainDnsName was passed, it must match; otherwise
# use the DC's actual domain. This prevents the "zone corp.example.com not found" class of
# error when the DC's real domain differs from a hardcoded default.
$actualDomain = (Get-ADDomain).DNSRoot
if ([string]::IsNullOrWhiteSpace($DomainDnsName)) {
    $DomainDnsName = $actualDomain
}
elseif ($DomainDnsName -ne $actualDomain) {
    throw "This domain controller's domain is '$actualDomain', but -DomainDnsName was '$DomainDnsName'. Omit -DomainDnsName to use the DC's own domain."
}
$FederationName = "adfs.$DomainDnsName"
Done "Using domain $DomainDnsName (federation service $FederationName)"

# Discover this domain controller's primary IPv4 address. The test domain controller has one
# primary interface, so callers do not need to pass the CDK output back into this script.
$primaryNetwork = Get-NetIPConfiguration |
    Where-Object { $null -ne $_.IPv4DefaultGateway -and $null -ne $_.IPv4Address } |
    Select-Object -First 1
$primaryIpv4 = $primaryNetwork.IPv4Address |
    Where-Object { $_.IPAddress -ne '127.0.0.1' -and -not $_.IPAddress.StartsWith('169.254.') } |
    Select-Object -First 1
if ($null -eq $primaryIpv4) {
    throw 'Unable to discover the domain controller private IPv4 address.'
}
$DcPrivateIp = $primaryIpv4.IPAddress
$parsedDcPrivateIp = [Net.IPAddress]::Parse($DcPrivateIp)
if ($parsedDcPrivateIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw "Discovered address '$DcPrivateIp' is not IPv4."
}
Done "Using domain controller private IP $DcPrivateIp"

# ----------------------------------------------------------------------------
# Step 2: Create the demo AD user (bob). Email becomes the SAML RoleSessionName.
# ----------------------------------------------------------------------------
Step '2. Demo user'
if (-not (Get-ADUser -Filter "SamAccountName -eq '$DemoUser'")) {
    $pw = Read-Host "Password for new AD user '$DemoUser'" -AsSecureString
    New-ADUser -Name $DemoUser -SamAccountName $DemoUser `
        -UserPrincipalName "$DemoUser@$DomainDnsName" `
        -EmailAddress "$DemoUser@$DomainDnsName" `
        -GivenName Bob -Surname Smith -DisplayName 'Bob Smith' `
        -AccountPassword $pw -Enabled $true -ChangePasswordAtLogon $false
    Done "Created user $DemoUser"
} else { Skip "User $DemoUser already exists" }

# ----------------------------------------------------------------------------
# Step 3: Create the AWS- group and add bob. Group name (minus AWS-) maps to the IAM role.
# ----------------------------------------------------------------------------
Step '3. AWS group + membership'
if (-not (Get-ADGroup -Filter "Name -eq '$AwsGroup'")) {
    New-ADGroup -Name $AwsGroup -SamAccountName $AwsGroup -GroupCategory Security -GroupScope Global
    Done "Created group $AwsGroup"
} else { Skip "Group $AwsGroup already exists" }

if (-not (Get-ADGroupMember $AwsGroup | Where-Object SamAccountName -eq $DemoUser)) {
    Add-ADGroupMember -Identity $AwsGroup -Members $DemoUser
    Done "Added $DemoUser to $AwsGroup"
} else { Skip "$DemoUser already in $AwsGroup" }

# ----------------------------------------------------------------------------
# Step 4: Create the AD FS service account. The AD FS service runs as this user.
# ----------------------------------------------------------------------------
Step '4. AD FS service account'
$servicePw = $null   # reused by the farm step (Step 8) so it never has to prompt again
if (-not (Get-ADUser -Filter "SamAccountName -eq '$ServiceAccount'")) {
    $servicePw = Read-Host "Password for new AD FS service account '$ServiceAccount'" -AsSecureString
    New-ADUser -Name $ServiceAccount -SamAccountName $ServiceAccount `
        -UserPrincipalName "$ServiceAccount@$DomainDnsName" -DisplayName 'AD FS Service' `
        -AccountPassword $servicePw -Enabled $true -ChangePasswordAtLogon $false
    Done "Created service account $ServiceAccount"
} else { Skip "Service account $ServiceAccount already exists" }

# ----------------------------------------------------------------------------
# Step 5: DNS A record so adfs.<domain> resolves to this DC.
# (Done before the farm so the federation name resolves when the farm is created.)
# ----------------------------------------------------------------------------
Step '5. DNS record for adfs.<domain>'
$existing = Get-DnsServerResourceRecord -ZoneName $DomainDnsName -Name $AdfsHostLabel -RRType A -ErrorAction SilentlyContinue
if (-not $existing) {
    Add-DnsServerResourceRecordA -ZoneName $DomainDnsName -Name $AdfsHostLabel -IPv4Address $DcPrivateIp
    Done "Created A record $FederationName -> $DcPrivateIp"
} else { Skip "A record for $FederationName already exists" }

# ----------------------------------------------------------------------------
# Step 6: DNS forwarder so the DC can resolve external AWS hostnames
# (signin.aws.amazon.com, console.aws.amazon.com). Learned from the built DC: without
# this the browser verification shows a blank page and external lookups fail.
# ----------------------------------------------------------------------------
Step '6. DNS forwarder for external AWS hostnames'
if (-not (Get-DnsServerForwarder | Where-Object { $_.IPAddress.IPAddressToString -eq $VpcDnsForwarder })) {
    Add-DnsServerForwarder -IPAddress $VpcDnsForwarder
    Done "Added DNS forwarder $VpcDnsForwarder"
} else { Skip "DNS forwarder $VpcDnsForwarder already present" }

# ----------------------------------------------------------------------------
# Step 7: Install the AD FS feature. This needs a reboot before the farm can be created.
# ----------------------------------------------------------------------------
Step '7. Install AD FS feature'
$feature = Get-WindowsFeature ADFS-Federation
if (-not $feature.Installed) {
    $r = Install-WindowsFeature ADFS-Federation -IncludeManagementTools
    Done 'Installed AD FS feature'
    if ("$($r.RestartNeeded)" -eq 'Yes') {
        Write-Warning 'REBOOT required. Restart the server, then run this SAME command again to continue.'
        exit 3010
    }
} else { Skip 'AD FS feature already installed' }

Import-Module ADFS

# ----------------------------------------------------------------------------
# Step 8: Create the AD FS farm (self-signed cert, running as the service account).
# A public CA cannot issue for a private domain, so we self-sign.
# ----------------------------------------------------------------------------
Step '8. AD FS farm'
$farm = $null
try { $farm = Get-AdfsProperties -ErrorAction Stop } catch { }
if (-not $farm) {
    $cert = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object { $_.Subject -eq "CN=$FederationName" -and $_.HasPrivateKey } |
        Select-Object -First 1
    if (-not $cert) {
        $cert = New-SelfSignedCertificate -DnsName $FederationName -CertStoreLocation Cert:\LocalMachine\My
        Done "Created self-signed cert $($cert.Thumbprint)"
    }
    # Build the service-account credential without the interactive Get-Credential dialog,
    # which can return null in remote or headless sessions and then fail Install-AdfsFarm with "ServiceAccountCredential ... null or empty".
    # Reuse the password captured in Step 4; if the account already existed, prompt in the
    # console with Read-Host (reliable over remote shells).
    if (-not $servicePw) {
        $servicePw = Read-Host "Password for the existing AD FS service account '$ServiceAccount'" -AsSecureString
    }
    $serviceLogon = "$($cs.Domain.Split('.')[0])\$ServiceAccount"
    $cred = New-Object System.Management.Automation.PSCredential($serviceLogon, $servicePw)
    Install-AdfsFarm -CertificateThumbprint $cert.Thumbprint `
        -FederationServiceName $FederationName `
        -FederationServiceDisplayName 'AWS JDBC Demo' `
        -ServiceAccountCredential $cred
    Done "Created AD FS farm for $FederationName"
} else { Skip "AD FS farm for $($farm.HostName) already exists" }

# ----------------------------------------------------------------------------
# Step 9: Enable Forms authentication. MANDATORY: the plugin parses the HTML sign-in form.
# ----------------------------------------------------------------------------
Step '9. Forms authentication'
$policy = Get-AdfsGlobalAuthenticationPolicy
if ($policy.PrimaryIntranetAuthenticationProvider -notcontains 'FormsAuthentication') {
    Set-AdfsGlobalAuthenticationPolicy `
        -PrimaryIntranetAuthenticationProvider (@($policy.PrimaryIntranetAuthenticationProvider) + 'FormsAuthentication')
    Done 'Enabled Forms authentication for intranet'
} else { Skip 'Forms authentication already enabled' }

# ----------------------------------------------------------------------------
# Step 10: Enable the IdP-initiated sign-on page. Off by default on Server 2016, and
# required for the browser sanity check (IdpInitiatedSignOn.aspx). The federatedAuth
# plugin does not need it, but it is the quickest way to prove federation before JDBC.
# ----------------------------------------------------------------------------
Step '10. IdP-initiated sign-on page'
if (-not (Get-AdfsProperties).EnableIdpInitiatedSignonPage) {
    Set-AdfsProperties -EnableIdpInitiatedSignonPage $true
    Done 'Enabled IdP-initiated sign-on page (for browser verification)'
} else { Skip 'IdP-initiated sign-on page already enabled' }

# ----------------------------------------------------------------------------
# Step 11: AWS relying-party trust + the 4 claim rules.
# ----------------------------------------------------------------------------
Step '11. AWS relying-party trust and claim rules'

$claimRules = @"
@RuleName = "NameId"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname"]
 => issue(Type = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier", Issuer = c.Issuer, OriginalIssuer = c.OriginalIssuer, Value = c.Value, ValueType = c.ValueType, Properties["http://schemas.xmlsoap.org/ws/2005/05/identity/claimproperties/format"] = "urn:oasis:names:tc:SAML:2.0:nameid-format:persistent");

@RuleName = "RoleSessionName"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
 => issue(store = "Active Directory", types = ("https://aws.amazon.com/SAML/Attributes/RoleSessionName"), query = ";mail;{0}", param = c.Value);

@RuleName = "Get AD Groups"
c:[Type == "http://schemas.microsoft.com/ws/2008/06/identity/claims/windowsaccountname", Issuer == "AD AUTHORITY"]
 => add(store = "Active Directory", types = ("http://temp/variable"), query = ";tokenGroups;{0}", param = c.Value);

@RuleName = "Roles"
c:[Type == "http://temp/variable", Value =~ "(?i)^AWS-"]
 => issue(Type = "https://aws.amazon.com/SAML/Attributes/Role", Value = RegExReplace(c.Value, "(?i)^AWS-", "arn:aws:iam::${AwsAccountId}:saml-provider/$SamlProviderName,arn:aws:iam::${AwsAccountId}:role/ADFS-"));
"@

$authRule = '=> issue(Type = "http://schemas.microsoft.com/authorization/claims/permit", Value = "true");'

if (-not (Get-AdfsRelyingPartyTrust -Name 'AWS')) {
    $endpoint = New-AdfsSamlEndpoint -Binding POST -Protocol SAMLAssertionConsumer -Uri $AwsSamlUrl
    Add-AdfsRelyingPartyTrust -Name 'AWS' -Identifier $RpIdentifier -SamlEndpoint $endpoint `
        -IssuanceAuthorizationRules $authRule -IssuanceTransformRules $claimRules
    Done 'Created AWS relying-party trust with 4 claim rules'
} else { Skip 'AWS relying-party trust already exists' }

# ----------------------------------------------------------------------------
# Step 12: Export federation metadata for the AWS IAM SAML provider.
# Built from the token-signing certificate (fetching it over HTTPS is unreliable on 2016).
# ----------------------------------------------------------------------------
Step '12. Export federation metadata'
$props   = Get-AdfsProperties
$signing = (Get-AdfsCertificate -CertificateType Token-Signing | Where-Object IsPrimary | Select-Object -First 1).Certificate
$b64     = [Convert]::ToBase64String($signing.RawData)
$entity  = $props.Identifier.ToString()

$metadata = @"
<?xml version="1.0" encoding="utf-8"?>
<EntityDescriptor xmlns="urn:oasis:names:tc:SAML:2.0:metadata" entityID="$entity">
  <IDPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol">
    <KeyDescriptor use="signing">
      <KeyInfo xmlns="http://www.w3.org/2000/09/xmldsig#"><X509Data><X509Certificate>$b64</X509Certificate></X509Data></KeyInfo>
    </KeyDescriptor>
    <SingleLogoutService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="https://$FederationName/adfs/ls/" />
    <NameIDFormat>urn:oasis:names:tc:SAML:2.0:nameid-format:persistent</NameIDFormat>
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" Location="https://$FederationName/adfs/ls/" />
    <SingleSignOnService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="https://$FederationName/adfs/ls/" />
  </IDPSSODescriptor>
</EntityDescriptor>
"@
[IO.File]::WriteAllText($MetadataPath, $metadata, (New-Object Text.UTF8Encoding($false)))
Done "Wrote federation metadata to $MetadataPath"

# ----------------------------------------------------------------------------
# Quick health check. Learned from the built DC: confirm AD FS is actually serving on
# 443 before blaming the client. TcpTestSucceeded=True means the server is fine and any
# remaining failure is downstream (metadata fetch, claim rules, IAM).
# ----------------------------------------------------------------------------
Step '13. Verify AD FS is reachable'
$check = Test-NetConnection -ComputerName $FederationName -Port 443 -WarningAction SilentlyContinue
if ($check.TcpTestSucceeded) {
    Done "$FederationName is listening on TCP 443"
} else {
    Write-Warning "$FederationName is NOT reachable on 443 yet. If the farm was just created, reboot and re-run."
}

# ----------------------------------------------------------------------------
# Summary + what happens on the AWS side next.
# ----------------------------------------------------------------------------
Step 'AD FS setup complete'
Write-Host "Federation metadata : $MetadataPath"
Write-Host "IAM SAML provider   : arn:aws:iam::${AwsAccountId}:saml-provider/$SamlProviderName"
Write-Host "IAM role from claims : arn:aws:iam::${AwsAccountId}:role/$IamRoleName"
Write-Host ""
Write-Host "Verify in a browser (optional but proves federation end to end):"
Write-Host "  https://$FederationName/adfs/ls/IdpInitiatedSignOn.aspx?loginToRp=$RpIdentifier"
Write-Host "  Sign in as $DemoUser@$DomainDnsName. Reaching the AWS console URL = success."
Write-Host "  (Self-signed cert: expect a certificate warning; continue past it.)"
Write-Host ""
Write-Host "Next (AWS side, not this script):"
Write-Host "  1. Create the IAM SAML provider '$SamlProviderName' from the metadata file above."
Write-Host "  2. Create IAM role $IamRoleName (AssumeRoleWithSAML trust + rds-db:connect)."
Write-Host "  3. Create the Aurora IAM database user, then configure the JDBC federatedAuth stage."
