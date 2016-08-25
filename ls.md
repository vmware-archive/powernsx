---
layout: page
permalink: /ls/
---

# Logical Switching

# Retrieving Logical Switches.

Logical Switches are bound to a Transport Zone. The following command runs the Get-NsxTransportZone for transport zone TZ1 and passes the Transport Zone object to Get-NsxLogicalSwitch which will return the logical switch named TSTransit in TZ1

```
PowerCLI C:\> Get-NsxTransportZone TZ1 | Get-NsxLogicalSwitch TSTransit


objectId              : virtualwire-222
objectTypeName        : VirtualWire
vsmUuid               : 4201BAC9-7509-46FD-7813-35D817ADB861
nodeId                : d704f7a1-e9c2-4c7c-bb5e-7116145905bf
revision              : 2
type                  : type
name                  : TSTransit
description           :
clientHandle          :
extendedAttributes    :
isUniversal           : false
universalRevision     : 0
tenantId              :
vdnScopeId            : vdnscope-1
vdsContextWithBacking : vdsContextWithBacking
vdnId                 : 5000
guestVlanAllowed      : false
controlPlaneMode      : UNICAST_MODE
ctrlLsUuid            : fef6c2f3-613e-4531-bd0b-5a74f27dfe43
macLearningEnabled    : false


```

The output details a lot of information about the individual logical switch.

To filter the properties of a Logical Switch output to a subset and view it in a table, we can use Select-Object cmdlet.

```
PowerCLI C:\> Get-NsxTransportZone TZ1 | Get-NsxLogicalSwitch TSTransit | Select-Object Name, vdnscope,vdnid

name                                               vdnScopeId                                        vdnId
----                                               --------                                          -----
TSTransit                                          vdnscope-1                                        5000

```

# Creating a Logical Switch

Using the above method it is quite easy to create a Logical Switch in the transport zone TZ1 using the New-NsxLogicalSwitch command. It only requires the Transport Zone passed on the pipeline, and the Logical Switch name as an input.


```
PowerCLI C:\> Get-NsxTransportZone TZ1 | New-NsxLogicalSwitch -name PowerNSX


objectId              : virtualwire-227
objectTypeName        : VirtualWire
vsmUuid               : 4201BAC9-7509-46FD-7813-35D817ADB861
nodeId                : d704f7a1-e9c2-4c7c-bb5e-7116145905bf
revision              : 2
type                  : type
name                  : PowerNSX
description           :
clientHandle          :
extendedAttributes    :
isUniversal           : false
universalRevision     : 0
tenantId              :
vdnScopeId            : vdnscope-1
vdsContextWithBacking : vdsContextWithBacking
vdnId                 : 5005
guestVlanAllowed      : false
controlPlaneMode      : UNICAST_MODE
ctrlLsUuid            : e3c5d18c-7354-4068-8c93-32dda84b7cbb
macLearningEnabled    : false
```

# Discovering the Backing PortGroup of a given Logical Switch

Each Logical Switch is backed by a port-group on one or more Distributed Switches, and the port group is the entity that a VM is actually attached to.  To retrieve the port group(s) backing a Logical Switch, you can use the Get-NsxBackingPortGroup cmdlet.

```


PowerCLI C:\> Get-NsxTransportZone TZ1 | get-nsxlogicalswitch PowerNSX | Get-NsxBackingPortGroup

Name                           NumPorts PortBinding
----                           -------- -----------
vxw-dvs-64-virtualwire-227-... 0        Static

```

The output is a PowerCLI VdPortGroup object.

```


PowerCLI C:\> Get-NsxTransportZone TZ1 | Get-NsxLogicalSwitch PowerNSX | Get-NsxBackingPortGroup | Format-Table -AutoSize

Name                                          NumPorts PortBinding
----                                          -------- -----------
vxw-dvs-44-virtualwire-516-sid-5000-PowerNSX 8        Static

```

Here we can see the port-group name vxw-dvs-44-virtualwire-516-sid-5000-PowerNSX which is the Logical Switch we created earlier.

# Need help?

For more examples please use get-help command preceding any PowerNSX function. Also use -detailed, -examples, or -full.
