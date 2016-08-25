---
layout: page
permalink: /example/
---

# Introduction

This script highlights how to deploy an entire three tier application stack. This is example application that can be deployed using both PowerNSX and functionality provided by PowerCLI. It uses numerous networking function provided by VMware's NSX for vSphere platform.

# Features

The application topology includes the following:

- Logical Switching
- Logical Distributed Router
- NSX Edge gateway
- NSX Edge Load Balancing
- Dynamic Routing
- Distributed Firewall
- Security Groups

# Requirements

The following is required before this script will function:

- vCenter 6
- NSX for vSphere 6.2
- PowerCLI 6
- PowerNSX v1

This assumes that vCenter and NSX are installed, registered and setup. This also assumes that NSX for vSphere has been configured, NSX Controllers deployed, and relevent clusters used have been prepared.

# Topology

The entire application topology include all other functions looks like this:
![Screenshot 2016-01-21 13.56.33.png](https://bitbucket.org/repo/ppbXEb/images/466928483-Screenshot%202016-01-21%2013.56.33.png)

The only element existing is a network or port-group noted external. This example has this network represented with the subnet 192.168.100.0/24. This is the subnet which the NSX Edge gateway's primary and secondary interfaces for the uplink derive their IP addresses from.

The vAPP OVA used in this script is [located here](http://goo.gl/oBAFgq)


# Breaking down the script

This section takes the key building blocks of the script and breaks them down. It does not cover every line of code.

At any time if you're unsure of the switches or options of a commandlet then run 'get-help <command> -examples'

# Variables in the paramter block
This paramter block defines global variables which a user can override with switches on execution. By default these are set for the test environment.

```
#!powershell

param (
    #Names
    $TsTransitLsName = "TSTransit",
    $TsWebLsName = "TSWeb",
    $TsAppLsName = "TSApp",
    $TsDbLsName = "TSDb",
    $TsMgmtLsName = "TSMgmt",
    $TsEdgeName = "TsEdge01",
    $TsLdrName = "TsLdr01",
	#Infrastructure
    $EdgeUplinkPrimaryAddress = "192.168.100.192",
    $EdgeUplinkSecondaryAddress = "192.168.100.193",
    $EdgeInternalPrimaryAddress = "172.16.1.1",
    $EdgeInternalSecondaryAddress = "172.16.1.6",
```
If there are substantial changes required for this script then it is suggested that you edit the script itself. If only a handful of variables ned to be changed then switches would be fine.


# Creating Logical Switches

Below creates a logical switch. It hass a $Global: prefix to denote that it can be used again outside of the function "Build-LogicalSwitches"

```

#!powershell

    $Global:TsTransitLs = Get-NsxTransportZone | New-NsxLogicalSwitch $TsTransitLsName

```

Get-NsxTransportZone retrieves the single transport zone in this environement. The output of it is Tz-Global. The New-NsxLogicalSwitch function creates a new Logical Switch on this transport zone.

The output of this is subsequently saved to the variable $Global:TsTransitLs.

This is repeated for Web, App, DB, and Mgmt Logical Switches.

# Creating Logical Distributed Router

Next step is to connect the four Logical Switches in each step together. The DLR provides in-host routing and an uplink to an NSX edge.

The first step is to create the DLR. The DLR requires a single interface on during deployment.

```

#!powershell

 $TsLdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $TsTransitLsName -ConnectedTo $TsTransitLs -PrimaryAddress $LdrUplinkPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits

 $TsLdr = New-NsxLogicalRouter -name $TsLdrName -ManagementPortGroup $TsMgmtLs -interface $TsLdrvNic0 -cluster $cluster -datastore $DataStore

```

The first variable $TsLdrvNic0 stores the creation of the uplink interface. This references strings stored in our parameter block at the start such as IP address, secondary IP address, subnet length and connected switch.

$TsLdr stores the result of creating the DLR. It selects the management port-group, desired interfaces (in this case it is the newly created $TsLdrvNic0) and the destination cluster and datastore.

Three more interfaces need to be created. They are for Web, App, and Db networks. This method shows how appending new interfaces to an existing DLR can be done.

```

#!powershell
$TsLdr | New-NsxLogicalRouterInterface -Type Internal -name $TsWebLsName  -ConnectedTo $TsWebLs -PrimaryAddress $LdrWebPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null

```

Because the DLR in question is still stored in the variable $TsLdr we can use it within this function. New-NsxLogicalRouterInterface is used to create a new Logical Interface (LIF) on the DLR in question. out-null hides the output for the script.

This is repeated again for the two other interfaces.

# Default Routing

A default route is configured from the DLR to the NSX edge. This is created so ensure any traffic northbound is sent to the NSX edge.

```

#!powershell

$TsLdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TsTransitLsName}
    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $TsLdrTransitInt.index -DefaultGatewayAddress $EdgeInternalPrimaryAddress -confirm:$false | out-null

```

This code is a little more involved. Due to the fact a user can create an uplink that is not always on vNic0 a lookup is performed to match the uplink name (created earlier) to the uplink logical switch. This ensures the default route is pointing out the correct interface. Using variables defined in the paramter block the default route gets the correct information.

# NSX Edge gateway

In a similar fashion to the DLR the NSX Edge gateway is deployed.

Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs

```

#!powershell

    $edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $EdgeUplinkPrimaryAddress -SecondaryAddress $EdgeUplinkSecondaryAddress -SubnetPrefixLength $DefaultSubnetBits

  $Global:TSEdge1 = New-NsxEdge -name $TsEdgeName -cluster $Cluster -datastore $DataStore -Interface $edgevnic0,$edgevnic1 -Password $Password

```

Next step is to change the default FW policy of the edge. At the time of writing there is not an explicit cmdlet to do this, so we create the XML manually and push it back down using Set-NsxEdge

```

#!powershell

  $TsEdge1 = get-nsxedge $TsEdge1.name
    $TsEdge1.features.firewall.defaultPolicy.action = "accept"
    $TsEdge1 | Set-NsxEdge -confirm:$false | out-null

```

# NAT - Range to IP DNAT

Destination NAT is used to allow the range that is assigned to the external network to reach the DB-VM on 10.0.3.0/24 network. This will allow the opening of MYSQL tools to this port. It can also be validated as an open-port using Nmap or ZenMap.

```

#!powershell

Get-NsxEdge $TsEdgeName | Get-NsxEdgeNat | Set-NsxEdgeNat -enabled -confirm:$false | out-null
    $DbNat = get-NsxEdge $TsEdgeName | Get-NsxEdgeNat | New-NsxEdgeNatRule -vNic 0 -OriginalAddress $SourceTestNetwork -TranslatedAddress $Db01Ip -action dnat -Protocol tcp -OriginalPort $SrcNatPort -TranslatedPort $TranNatPort -LoggingEnabled -Enabled -Description "Open SSH on port $SrcNatPort to $TranNatPort"


```

The authors note that this is FAR from a good practice - purely just testing a feature. The relevent firewall rules are made later.




# Dynamic or static routing

There is an ability to use the switch -topologytype when deploying this script. This allows choice in how the Edge and DLR advertise networks to each other. Depending on requirements you can choose Static routes or OSPF. (Note: BGP coming soon). If not specified it uses Static routes.

```

#!powershell

    write-host -foregroundcolor Green "Configuring Edge OSPF"
    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $EdgeUplinkPrimaryAddress -confirm:$false | out-null

    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false

    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

    Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $TransitOspfAreaId -vNic 1 -confirm:$false | out-null

```

 This removes the dopey area 51 NSSA and shows an example of complete OSPF configuration including area creation. All variables references are within the parameter block.

 The code is very similar for the DLR and much like the existing default route uses a name match and index ID to ensure the uplink is selected.

```

#!powershell

  	Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea -confirm:$false

    #Create new Area
    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

    #Area to interface mapping
    $TsLdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TsTransitLsName}

    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId $TransitOspfAreaId -vNic $TsLdrTransitInt.index -confirm:$false | out-null

    #Enable Redistribution into OSPF of connected routes.
    Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -Learner ospf -FromConnected -Action permit -confirm:$false | out-null

```
# Load Balancing

Now the NSX Edge gateway is deployed the loadbalancer is next. This is designed to include the VMs that get deployed in the later OVF configuration.


```

#!powershell

  Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | Set-NsxLoadBalancer -Enabled | out-null

```

# Server Pools

Creating the service pools is a two step process. These local function variables are created for later use. First step is to create the pool members. Creating the pool members requires IP address of VM and port. This is then used when creating $WebPool. $WebPool defines the required LB settings for the pool.


```

#!powershell

   $webpoolmember1 = New-NsxLoadBalancerMemberSpec -name $Web01Name -IpAddress $Web01Ip -Port $HttpPort

   $WebPool =  Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name $WebPoolName -Description "Web Tier Pool" -Transparent:$false -Algorithm $LbAlgo -Memberspec $webpoolmember1,$webpoolmember2

```

    This process is repeated for the Application pool and App VMs.

# Application profile

The next step is to create the Web App profile into a function specific variable $WebAppProfile. It will be used during creation of the overall LB service.

```

#!powershell

   $WebAppProfile = Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationProfile -Name $WebAppProfileName  -Type $VipProtocol

```

Saved to the variable $WebAppProfile is the new Application profile. It draws on $VipProtocol stored in the param block. This process is repeated for the App Tiers Application profile.

# Creating the LB VIP

With all the pre-requisites done and using the selected edge each switch uses a pre-created variable to define the required settings for the LB service. The VIP is the last piece that draws upon all previously created or stored variables.

```

#!powershell

  Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name $WebVipName -Description $WebVipName -ipaddress $EdgeUplinkSecondaryAddress -Protocol $VipProtocol -Port $HttpPort -ApplicationProfile $WebAppProfile -DefaultPool $WebPool -AccelerationEnabled | out-null

```
This is repeated for the App VIP. Check code for more details.


# Deploying the application

First step is to load the desired OVA file. This allows viewing and the subsequent definition of OVFs properties. Defining the properties is done by referencing param block with variables declared at the start of the code.

Case in point is  ``` $ovfConfiguration.common.Web01_IP.Value = $Web01Ip ``` which passes along the contents of $Web01Ip as a string.

Each mandatory OVF property must be addresses and any others should be addresses to ensure the deployed application functions correctly.

# Deplying and starting the vAPP

Deploying the vApp will deploy 5 virtual machines and configure their host files with DNS entries for the IP addresses set in the OVF configuration properties.

**Tip**

The following code will select a host from within the defined cluster assigned to $cluster and select the first result. This will assign the host with the lowest Memory usage to the variable $VMhost which the vApp deployment uses.

```

#!powershell

  $VMHost = $cluster | Get-VMHost | Sort MemoryUsageGB | Select -first 1



  Import-vApp -Source $BooksvAppLocation -OvfConfiguration $ovfConfiguration -Name Books -Location $Cluster -VMHost $Vmhost -Datastore $Datastore | out-null

  Start-vApp $vAppName | out-null

```

 This wil deploy the vApp sourced at $BooksvAppLocation and pass along to the OvfConfiguration all the OVF properties stored in $OvfConfiguration.

 It will then start the vApp named $vAppName (Books).

**Important**

PowerCLI and get-ovfconfiguration only accepts port-groups or distributed port-groups for settings. To find out what port-group name is backing a Logical Switch (after all, all LS's are port-groups) the following is used. It is then wrapped into a new variable.


```
#!powershell

  $WebNetwork = get-nsxtransportzone | get-nsxlogicalswitch $TsWebLsName | Get-NsxBackingPortGroup

```

$WebNetwork now has the port-group for the OVA to deploy the VM on.


# Applying Security

Next section will focus on creating and deploying security to achieve micro-sementation of the application.

# Creating services and objects

First step is to get the existing HTTP and MySQL service and assigning to variables.

```

#!powershell

    $httpservice = Get-NsxService HTTP

```

$AppVIP_IpSet is assigned the information from creating a New-NsxIpSet that represents the App VIP. This is the destination for traffic from the Web Tier.

```

#!powershell

  $AppVIP_IpSet = New-NsxIPSet -Name AppVIP_IpSet -IPAddresses $EdgeInternalSecondaryAddress

```

**Important**

IP address that hits the App VIP is NAT'd to the vNic and uses the Ip address assigned $InternalESG_IpSet. This needs to be the rules source for traffic going to App Tier.


# Creating Security Groups

Security Groups are a container in which workloads reside. Due to current limitations (see: note yet coded) the only way to match on include member is at creation. This example uses get-vm. It will match all VMs that have "Web0" in the VM name.


```

#!powershell

    $WebSg = New-NsxSecurityGroup -name $WebSgName -description $WebSgDescription -includemember (get-vm | ? {$_.name -match "Web0"})
```

# Creating rules

Now with the Security Groups and objects assigned to variables we can make rules. Once we get the relevent Firewall section the new rule is made from all the variables we have populated.

```

#!powershell

   $WebToAppVIP = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "$WebSgName to App VIP" -Source $WebSg -Destination $AppVIP_IpSet -Service $HttpService -Action $AllowTraffic -AppliedTo $WebSg,$AppSg -position bottom

```

# Checking the application

Now we navigate to the web VIP and lets what we see.


![Screenshot 2016-01-21 17.32.49.png](https://bitbucket.org/repo/ppbXEb/images/3407717768-Screenshot%202016-01-21%2017.32.49.png)


Congratulations. A working application topology that takes only minutes to deploy.

# Need help?

For more examples please use get-help command preceding any PowerNSX function. Also use -detailed, -examples, or -full.
