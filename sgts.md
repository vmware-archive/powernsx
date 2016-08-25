---
layout: page
permalink: /sgts/
---

# Security Groups, Security Tags, and Services

Security Groups and Security Tags provide a powerful asset to the Distributed Firewall.

# Creating Security Tags and listing Groups

It is easy and quick to create a Security Tag.

```


PowerCLI C:\> New-NsxSecurityTag PowerNSX-Tag


objectId           : securitytag-329
objectTypeName     : SecurityTag
vsmUuid            : 42011E64-766E-616B-0401-5C68CF27B466
nodeId             : 0509160a-0cfb-4cc2-811a-3193e8b45b95
revision           : 0
type               : type
name               : PowerNSX-Tag
clientHandle       :
extendedAttributes :
isUniversal        : false
universalRevision  : 0
systemResource     : false
vmCount            : 0

```

How about listing all created Security Groups, selecting the desired properties to list and formatting it to a nice table.


```


PowerCLI C:\> Get-NsxSecurityGroup | select name, objectid | ft -auto

name                        objectId
----                        --------
SG-Provider-NTP             securitygroup-493
SG-Consumer-Internal-SSH    securitygroup-503
SG-Consumer-DNS             securitygroup-498
SG-Provider-Internal-RDP    securitygroup-494
SG-NSX-Components           securitygroup-480
SG-Consumer-Internal-RDP    securitygroup-502
SG-SDDC-Management-Internal securitygroup-486
SG-Provider-SMTP            securitygroup-491
SG-SMTP-Servers             securitygroup-484
SG-LogInsight-Cluster       securitygroup-477
PowerNSX-SG                 securitygroup-505
SG-Provider-Internal-Web    securitygroup-496
SG-Provider-Syslog          securitygroup-492
SG-vSphere-Hosts            securitygroup-479
SG-Consumer-Internal-Web    securitygroup-504
SG-DNS-Servers              securitygroup-481
SG-NTP-Servers              securitygroup-483
SG-AD-Servers               securitygroup-482
SG-vCenter-Appliances       securitygroup-478
SG-Consumer-Syslog          securitygroup-500
SG-DHCP-Servers             securitygroup-485
SG-Provider-DNS             securitygroup-490
SG-Consumer-SMTP            securitygroup-499
SG-Provider-Internal-SSH    securitygroup-495
SG-Provider-ActiveDirectory securitygroup-489
SG-Consumer-NTP             securitygroup-501
SG-Linux-Corporate          securitygroup-488
SG-Windows-Corporate        securitygroup-487
SG-Consumer-ActiveDirectory securitygroup-497

```

A nice simple output of the current Security Groups created and the object IDs. Anything property in the Get-NsxSecurityGroup | Get-member can be used with select.

# Creating a new Security Group

Creating a new Security Group is simple with PowerNSX. Either blank groups or groups with included or excluded members can be done. The object passed to -IncludeMember or -ExcludeMember can be the vCenter objects references in the UI.

Lets use the tag we just created.

```


PowerCLI C:\> $Tag = Get-NsxSecurityTag PowerNSX-Tag

PowerCLI C:\> New-NsxSecurityGroup PowerNSX-SG -Description 'SG for PowerNSX-Tag VMs' -IncludeMember $tag


objectId           : securitygroup-505
objectTypeName     : SecurityGroup
vsmUuid            : 42011E64-766E-616B-0401-5C68CF27B466
nodeId             : 0509160a-0cfb-4cc2-811a-3193e8b45b95
revision           : 2
type               : type
name               : PowerNSX-SG
description        : SG for PowerNSX-Tag VMs
scope              : scope
clientHandle       :
extendedAttributes :
isUniversal        : false
universalRevision  : 0
inheritanceAllowed : false
member             : member

```

Now to apply the Security Tag to a given VM. The first is to find the Virtual Machine Web-02.

```


PowerCLI C:\> Get-VM | ? {$_.name -eq ("Web-01")} | New-NsxSecurityTagAssignment -ApplyTag $tag
PowerCLI C:\> Get-VM | ? {$_.name -eq ("Web-01")} | Get-NsxSecurityTagAssignment

SecurityTag                                                    VirtualMachine
-----------                                                    --------------
securityTag                                                          web-01

```

# Service and Service Groups

Whilst NSX includes lots of services out of the box due to naming or security reasons an administrator may not want to use the existing services.

A quick purge of all services can be done to start fresh.

```


Get-NsxService | Remove-NsxService -force -confirm:$false

```
**Achtung!**

The above command will remove all services and those included in the default permit rule. Be mindful!

Starting fresh an administrator can create the desired services. Creating a service requires very basic information.

```


PowerCLI C:\> New-NsxService -name 'tcp-666' -protocol tcp -port 666


objectId           : application-1404
objectTypeName     : Application
vsmUuid            : 42011E64-766E-616B-0401-5C68CF27B466
nodeId             : 0509160a-0cfb-4cc2-811a-3193e8b45b95
revision           : 1
type               : type
name               : tcp-666
description        :
scope              : scope
clientHandle       :
extendedAttributes :
isUniversal        : false
universalRevision  : 0
inheritanceAllowed : false
element            : element
```

Lets look at all the services that are created. The below command will search all custom created Services using the RegEx matches "tcp-". The select field will output just the name property.

```


PowerCLI C:\> get-nsxservice | ? {$_.name -match ("tcp-")} | select name | ft

name
----
tcp-666
tcp-22
tcp-3389
tcp-636
tcp-1433
tcp-80
tcp-443
tcp-389
tcp-88
tcp-3268
tcp-3269
tcp-25
tcp-465
tcp-53
tcp-514
tcp-1514
tcp-7000
tcp-9042
tcp-9160
tcp-59778
tcp-16520-16580
tcp-9000
tcp-9543

```

Quick ways to pool the environment are welcomed.

# Service Groups

Service Groups are a container that holds other Services or Service Groups

```


PowerCLI C:\> New-NsxServiceGroup SVG-PowerNSX


objectId           : applicationgroup-311
objectTypeName     : ApplicationGroup
vsmUuid            : 42011E64-766E-616B-0401-5C68CF27B
nodeId             : 0509160a-0cfb-4cc2-811a-3193e8b45
revision           : 1
type               : type
name               : SVG-PowerNSX
description        :
scope              : scope
clientHandle       :
extendedAttributes :
isUniversal        : false
universalRevision  : 0
inheritanceAllowed : false

```

Now that the Service Group has been made it is time to add some members to it. This example uses two services - tcp-80 and tcp-443.

```

$web = get-nsxservice tcp-80
$webs = get-nsxservice tcp-443
Get-NsxServiceGroup SVG-PowerNSX | Add-NsxServiceGroupMember $web,$WebSg

```

But what about Services included inside a Service Group? We have you covered. The first step is to poll the Service Group SVG-Web-Management and then Get-NsxServiceGroupMembers.

```


  PS C:\> Get-NsxServiceGroup SVG-PowerNSX | Get-NsxServiceGroupMembers


  objectId           : application-413
  objectTypeName     : Application
  vsmUuid            : 42019B98-63EC-995F-6CBB-FF738D027F92
  nodeId             : 0dd7c0dd-a194-4df1-a14b-56a1617c2f0f
  revision           : 2
  type               : type
  name               : tcp-80
  scope              : scope
  clientHandle       :
  extendedAttributes :
  isUniversal        : false
  universalRevision  : 0

  objectId           : application-290
  objectTypeName     : Application
  vsmUuid            : 42019B98-63EC-995F-6CBB-FF738D027F92
  nodeId             : 0dd7c0dd-a194-4df1-a14b-56a1617c2f0f
  revision           : 2
  type               : type
  name               : tcp-443
  scope              : scope
  clientHandle       :
  extendedAttributes :
  isUniversal        : false
  universalRevision  : 0

```
