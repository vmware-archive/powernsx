---
layout: page
permalink: /connect/
---
# NSX Manager and Controller operations

PowerNSX provides the ability to configure a deployed NSX Manager. It is possible to use PowerCLI and Get-OvfConfiguration to deploy the NSX Manager OVA to begin the end to end bootstrap.


# Connecting to NSX Manager

The NSX Manager commands allows the following:

* SSO configuration
* vCenter registration
* Syslog settings

It requires connection to NSX Manager first. To connect just define the NSX manager and credentials you want to use.

```
!#Powershell

PowerCLI C:\> connect-nsxserver nsx-m-01a.corp.local -Username admin -password VMware1!

Version             : 6.2.2
BuildNumber         : 3604087
Credential          : System.Management.Automation.PSCredential
Server              : nsx-m-01a.corp.local
Port                : 443
Protocol            : https
ValidateCertificate : False
VIConnection        : vc-01a.corp.local
DebugLogging        : False
DebugLogFile        : C:\Users\ADMINI~1\AppData\Local\Temp\2\PowerNSXLog-admin@nsx-m-01a.corp.local-2016_08_19_16_16_50.log

```

NSX Manager has been connected to. If NSX Manager has a vCenter already registered to it, PowerNSX is programmed to prompt the user to connect to vCenter.

A new connection to NSX Manager is established. The user is prompted if an automatic connection to vCenter should be created.

```

!#Powershell


PowerCLI C:\> Connect-NsxServer 192.168.100.201

cmdlet Connect-NsxServer at command pipeline position 1
Supply values for the following parameters:
Credential

PowerNSX requires a PowerCLI connection to the vCenter server NSX is registered against for proper operation.
Automatically create PowerCLI connection to vc-01a.corp.local?
[Y] Yes  [N] No  [?] Help (default is "Y"): y

WARNING: Enter credentials for vCenter vc-01a.corp.local

cmdlet Get-Credential at command pipeline position 1
Supply values for the following parameters:
Credential
WARNING: There were one or more problems with the server certificate for the server vc-01a.corp.local:443:

* The X509 chain could not be built up to the root certificate.

Certificate: [Subject]
  C=US, CN=vc-01a.corp.local

[Issuer]
  O=win2k8r2, C=US, DC=local, DC=vsphere, CN=CA

[Serial Number]
  00CB775FB809E19A79

[Not Before]
  9/29/2015 5:36:07 PM

[Not After]
  9/23/2025 5:35:59 PM

[Thumbprint]
  F648110EACF793A31B608FA253C488773FCDB181



The server certificate is not valid.

WARNING: THE DEFAULT BEHAVIOR UPON INVALID SERVER CERTIFICATE WILL CHANGE IN A FUTURE RELEASE. To ensure scripts are not affected by the
change, use Set-PowerCLIConfiguration to set a value for the InvalidCertificateAction option.



Version             : 6.2.2
BuildNumber         : 3604087
Credential          : System.Management.Automation.PSCredential
Server              : 192.168.100.201
Port                : 443
Protocol            : https
ValidateCertificate : False
VIConnection        : vc-01a.corp.local
DebugLogging        : False
DebugLogFile        : C:\Users\ADMINI~1\AppData\Local\Temp\2\PowerNSXLog-admin@192.168.100.201-2016_08_19_16_20_11.log



PowerCLI C:\>

```

Note that if a credential for either NSX Manager or vCenter is not defined then PowerNSX will fall back to use Windows Secure Credentials to store an encrypted user session for that user. Nothing is stored in plain text unlike passing a value in a string.

# Need help?

For more examples please use get-help command preceding any PowerNSX function. Also use -detailed, -examples, or -full.
