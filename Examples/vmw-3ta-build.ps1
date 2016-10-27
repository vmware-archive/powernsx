## VMware Build - 3 Tier App ##
## Author: Anthony Burke t:@pandom_ b:networkinferno.net
## Revisions: Nick Bradford, Dimtri Desmidt
## version 1.5
## October 2016
#-------------------------------------------------- 
# ____   __   _  _  ____  ____  __ _  ____  _  _ 
# (  _ \ /  \ / )( \(  __)(  _ \(  ( \/ ___)( \/ )
#  ) __/(  O )\ /\ / ) _)  )   //    /\___ \ )  ( 
# (__)   \__/ (_/\_)(____)(__\_)\_)__)(____/(_/\_)
#     PowerShell extensions for NSX for vSphere
#--------------------------------------------------

<#
Copyright © 2015 VMware, Inc. All Rights Reserved.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2, as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTIBILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 2 for more details.

You should have received a copy of the General Public License version 2 along with this program.
If not, see https://www.gnu.org/licenses/gpl-2.0.html.

The full text of the General Public License 2.0 is provided in the COPYING file.
Some files may be comprised of various open source software components, each of which
has its own license that is located in the source code of the respective component.”
#>

## Note: The OvfConfiguration portion of this example relies on this OVA. The securityGroup and Firewall configuration have a MANDATORY DEPENDANCY on this OVA being deployed at runtime. The script will fail if the conditions are not met. This OVA can be found here http://goo.gl/oBAFgq

# This paramter block defines global variables which a user can override with switches on execution.
param (
    #Names
    $TransitLsName = "Transit",
    $WebLsName = "Web",
    $AppLsName = "App",
    $DbLsName = "Db",
    $MgmtLsName = "Mgmt",
    $EdgeName = "Edge01",
    $LdrName = "Ldr01",

    #Infrastructure
    $EdgeUplinkPrimaryAddress = "192.168.100.192",
    $EdgeUplinkSecondaryAddress = "192.168.100.193",
    $EdgeInternalPrimaryAddress = "172.16.1.1",
    $EdgeInternalSecondaryAddress = "172.16.1.6",
    $LdrUplinkPrimaryAddress = "172.16.1.2",
    $LdrUplinkProtocolAddress = "172.16.1.3",
    $LdrWebPrimaryAddress = "10.0.1.1",
    $WebNetwork = "10.0.1.0/24",
    $LdrAppPrimaryAddress = "10.0.2.1",
    $AppNetwork = "10.0.2.0/24",
    $LdrDbPrimaryAddress = "10.0.3.1",
    $DbNetwork = "10.0.3.0/24",
    $TransitOspfAreaId = "10",

    #WebTier
    $Web01Name = "Web01",
    $Web01Ip = "10.0.1.11",
    $Web02Name = "Web02",
    $Web02Ip = "10.0.1.12",

    #AppTier
    $App01Name = "App01",
    $App01Ip = "10.0.2.11",
    $App02Name = "App02",
    $App02Ip = "10.0.2.12",
    $Db01Name = "Db01",
    $Db01Ip = "10.0.3.11",

    #DB Tier
    $Db02Name = "Db02",
    $Db02Ip = "10.0.3.12",

    #Subnet
    $DefaultSubnetMask = "255.255.255.0",
    $DefaultSubnetBits = "24",

    #Port
    $HttpPort = "80",

    #Management
    $ClusterName = "Management & Edge Cluster",
    $DatastoreName = "ds-site-a-nfs01",
    $Password = "VMware1!VMware1!",
    #Compute
    $ComputeClusterName = "Compute Cluster A",
    $EdgeUplinkNetworkName = "vds-mgt_Management Network",
    $computevdsname = "vds-site-a",
    #3Tier App
    $vAppName = "Books",
    $BooksvAppLocation = "C:\3_Tier-App-v1.6.ova",

    ##LoadBalancer
    $LbAlgo = "round-robin",
    $WebpoolName = "WebPool1",
    $ApppoolName = "AppPool1",
    $WebVipName = "WebVIP",
    $AppVipName = "AppVIP",
    $WebAppProfileName = "WebAppProfile",
    $AppAppProfileName = "AppAppProfile",
    $VipProtocol = "http",
    ##Edge NAT
    $SourceTestNetwork = "192.168.100.0/24",

    ## Securiry Groups
    $WebSgName = "SGTSWeb",
    $WebSgDescription = "Web Security Group",
    $AppSgName = "SGTSApp",
    $AppSgDescription = "App Security Group",
    $DbSgName = "SGTSDb",
    $DbSgDescription = "DB Security Group",
    $BooksSgName = "SGTSBooks",
    $BooksSgDescription = "Books ALL Security Group",
    #Security Tags
    $StWebName = "ST-3TA-Web",
    $StAppName = "ST-3TA-App",
    $StDbName = "ST-3TA-Db,",
    #DFW
    $FirewallSectionName = "Bookstore",

    $DefaultHttpMonitorName = "default_http_monitor",

    #Script control
    $BuildTopology=$true,
    $DeployvApp=$true,
    [Parameter (Mandatory=$false)]
    [ValidateSet("static","ospf")]
    $TopologyType="static"

)


###
# Do Not modify below this line! :)
###

Set-StrictMode -Version latest

## Validation of PowerCLI version. PowerCLI 6 is requried due to OvfConfiguration commands.

[int]$PowerCliMajorVersion = (Get-PowerCliVersion).major

if ( -not ($PowerCliMajorVersion -ge 6 ) ) { throw "OVF deployment tools requires PowerCLI version 6 or above" }

try {
    $Cluster = get-cluster $ClusterName -errorAction Stop
    $DataStore = get-datastore $DatastoreName -errorAction Stop
    $EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkName -errorAction Stop
}
catch {
    throw "Failed getting vSphere Inventory Item: $_"
}

## Creates four logical switches
$TransitLs = Get-NsxTransportZone | New-NsxLogicalSwitch $TransitLsName
$WebLs = Get-NsxTransportZone | New-NsxLogicalSwitch $WebLsName
$AppLs = Get-NsxTransportZone | New-NsxLogicalSwitch $AppLsName
$DbLs = Get-NsxTransportZone | New-NsxLogicalSwitch $DbLsName
$MgmtLs = Get-NsxTransportZone | New-NsxLogicalSwitch $MgmtLsName


######################################
# DLR

# DLR Appliance has the uplink router interface created first.
write-host -foregroundcolor "Green" "Creating DLR"
$LdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $TransitLsName -ConnectedTo $TransitLs -PrimaryAddress $LdrUplinkPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits

# The DLR is created with the first vnic defined, and the datastore and cluster on which the Control VM will be deployed.
$Ldr = New-NsxLogicalRouter -name $LdrName -ManagementPortGroup $MgmtLs -interface $LdrvNic0 -cluster $EdgeCluster -datastore $EdgeDataStore

## Adding DLR interfaces after the DLR has been deployed. This can be done any time if new interfaces are required.
write-host -foregroundcolor Green "Adding Web LIF to DLR"
$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $WebLsName  -ConnectedTo $WebLs -PrimaryAddress $LdrWebPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
write-host -foregroundcolor Green "Adding App LIF to DLR"
$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $AppLsName  -ConnectedTo $AppLs -PrimaryAddress $LdrAppPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
write-host -foregroundcolor Green "Adding DB LIF to DLR"
$Ldr | New-NsxLogicalRouterInterface -Type Internal -name $DbLsName  -ConnectedTo $DbLs -PrimaryAddress $LdrDbPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null

## DLR Routing - default route from DLR with a next-hop of the Edge.
write-host -foregroundcolor Green "Setting default route on DLR to $EdgeInternalPrimaryAddress"

##The first line pulls the uplink name coz we cant assume we know the index ID
$LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TransitLsName}
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $LdrTransitInt.index -DefaultGatewayAddress $EdgeInternalPrimaryAddress -confirm:$false | out-null


######################################
# EDGE

## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $EdgeUplinkPrimaryAddress -SecondaryAddress $EdgeUplinkSecondaryAddress -SubnetPrefixLength $DefaultSubnetBits
$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TransitLsName -type Internal -ConnectedTo $TransitLs -PrimaryAddress $EdgeInternalPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits -SecondaryAddress $EdgeInternalSecondaryAddress

## Deploy appliance with the defined uplinks
write-host -foregroundcolor "Green" "Creating Edge"
$Edge1 = New-NsxEdge -name $EdgeName -cluster $EdgeCluster -datastore $EdgeDataStore -Interface $edgevnic0, $edgevnic1 -Password $AppliancePassword -FwDefaultPolicyAllow


#####################################
# Load LoadBalancer

# Enanble Loadbalancing on $edgeName
write-host -foregroundcolor "Green" "Enabling LoadBalancing on $EdgeName"
Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | Set-NsxLoadBalancer -Enabled | out-null

#Get default monitor.
$monitor =  get-nsxedge | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor -Name $LBMonitorName


# Define pool members.  By way of example we will use two different methods for defining pool membership.  Webpool via predefine memberspec first...
write-host -foregroundcolor "Green" "Creating Web Pool"
$webpoolmember1 = New-NsxLoadBalancerMemberSpec -name $Web01Name -IpAddress $Web01Ip -Port $HttpPort
$webpoolmember2 = New-NsxLoadBalancerMemberSpec -name $Web02Name -IpAddress $Web02Ip -Port $HttpPort

# ... And create the web pool
$WebPool =  Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name $WebPoolName -Description "Web Tier Pool" -Transparent:$false -Algorithm $LbAlgo -Memberspec $webpoolmember1, $webpoolmember2 -Monitor $Monitor

# Now method two for the App Pool  Create the pool with empty membership.
write-host -foregroundcolor "Green" "Creating App Pool"
$AppPool = Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name $AppPoolName -Description "App Tier Pool" -Transparent:$false -Algorithm $LbAlgo -Monitor $Monitor

# ... And now add the pool members
$AppPool = $AppPool | Add-NsxLoadBalancerPoolMember -name $App01Name -IpAddress $App01Ip -Port $HttpPort
$AppPool = $AppPool | Add-NsxLoadBalancerPoolMember -name $App02Name -IpAddress $App02Ip -Port $HttpPort

# Create App Profiles. It is possible to use the same but for ease of operations this will be two here.
write-host -foregroundcolor "Green" "Creating Application Profiles for Web and App"
$WebAppProfile = Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationProfile -Name $WebAppProfileName  -Type $VipProtocol
$AppAppProfile = Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | new-NsxLoadBalancerApplicationProfile -Name $AppAppProfileName  -Type $VipProtocol

# Create the VIPs for the relevent WebPools. Using the Secondary interfaces.
write-host -foregroundcolor "Green" "Creating VIPs"
Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name $WebVipName -Description $WebVipName -ipaddress $EdgeUplinkSecondaryAddress -Protocol $VipProtocol -Port $HttpPort -ApplicationProfile $WebAppProfile -DefaultPool $WebPool -AccelerationEnabled | out-null
Get-NsxEdge $EdgeName | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name $AppVipName -Description $AppVipName -ipaddress $EdgeInternalSecondaryAddress -Protocol $VipProtocol -Port $HttpPort -ApplicationProfile $AppAppProfile -DefaultPool $AppPool -AccelerationEnabled | out-null


####################################
# OSPF

write-host -foregroundcolor Green "Configuring Edge OSPF"
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $EdgeUplinkPrimaryAddress -confirm:$false | out-null

#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false

#Create new Area 0 for OSPF
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

#Area to interface mapping
Get-NsxEdge $EdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $TransitOspfAreaId -vNic 1 -confirm:$false | out-null

write-host -foregroundcolor Green "Configuring Logicalrouter OSPF"
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableOspf -EnableOspfRouteRedistribution -RouterId $LdrUplinkPrimaryAddress -ProtocolAddress $LdrUplinkProtocolAddress -ForwardingAddress $LdrUplinkPrimaryAddress  -confirm:$false | out-null

#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea -confirm:$false

#Create new Area
Get-NsxLogicalRouter $LdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

#Area to interface mapping
$LdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TransitLsName}
Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId $TransitOspfAreaId -vNic $TsLdrTransitInt.index -confirm:$false | out-null


####################################
# OVF Application

write-host -foregroundcolor "Green" "Deploying 'The Bookstore' application "

# vCenter and the VDS have no understanding of a "Logical Switch". It only sees it as a VDS portgroup. 
# This step uses Get-NsxBackingPortGroup to determine the actual PG name that the VM attaches to.
# Also - realise that a single LS could be (and is here) backed by multiple PortGroups, so we need to 
# get the PG in the right VDS (compute)
# First work out the VDS used in the compute cluster (This assumes you only have a single VDS per cluster.
# If that isnt the case, we need to get the VDS by name....:

$ComputeVDS = Get-Cluster $ComputeClusterName | Get-VMHost | Get-VDSWitch
$WebNetwork = get-nsxtransportzone | get-nsxlogicalswitch $WebLsName | Get-NsxBackingPortGroup | Where { $_.VDSwitch -eq $ComputeVDS }
$AppNetwork = get-nsxtransportzone | get-nsxlogicalswitch $AppLsName | Get-NsxBackingPortGroup | Where { $_.VDSwitch -eq $ComputeVDS }
$DbNetwork = get-nsxtransportzone | get-nsxlogicalswitch $DbLsName | Get-NsxBackingPortGroup | Where { $_.VDSwitch -eq $ComputeVDS }

# Compute details - finds the host with the least used memory for deployment.
$VMHost = $Computecluster | Get-VMHost | Sort MemoryUsageGB | Select -first 1

# Get OVF configuration so we can modify it.
$OvfConfiguration = Get-OvfConfiguration -Ovf $BooksvAppLocation

# Network attachment.
$OvfConfiguration.networkmapping.vxw_dvs_24_universalwire_1_sid_50000_Universal_Web01.value = $WebNetwork.name
$OvfConfiguration.networkmapping.vxw_dvs_24_universalwire_2_sid_50001_Universal_App01.value = $AppNetwork.name
$OvfConfiguration.networkmapping.vxw_dvs_24_universalwire_3_sid_50002_Universal_Db01.value = $DbNetwork.name

# VM details.
$OvfConfiguration.common.app_ip.Value = $EdgeInternalSecondaryAddress
$OvfConfiguration.common.Web01_IP.Value = $Web01Ip
$OvfConfiguration.common.Web02_IP.Value = $Web02Ip
$OvfConfiguration.common.Web_Subnet.Value = $DefaultSubnetMask
$OvfConfiguration.common.Web_Gateway.Value = $LdrWebPrimaryAddress
$OvfConfiguration.common.App01_IP.Value = $App01Ip
$OvfConfiguration.common.App02_IP.Value = $App02Ip
$OvfConfiguration.common.App_Subnet.Value = $DefaultSubnetMask
$OvfConfiguration.common.App_Gateway.Value = $LdrAppPrimaryAddress
$OvfConfiguration.common.DB01_IP.Value = $DB01Ip
$OvfConfiguration.common.DB_Subnet.Value = $DefaultSubnetMask
$OvfConfiguration.common.DB_Gateway.Value = $LdrDbPrimaryAddress

# Run the deployment.
Import-vApp -Source $BooksvAppLocation -OvfConfiguration $OvfConfiguration -Name Books -Location $ComputeCluster -VMHost $Vmhost -Datastore $ComputeDatastore | out-null
write-host -foregroundcolor "Green" "Starting $vAppName vApp components"
Start-vApp $vAppName | out-null


#####################################
# Microseg config

write-host -foregroundcolor Green "Getting Services"

# Assume these services exist which they do in a default NSX deployment.
$httpservice = New-NsxService -name "tcp-80" -protocol tcp -port "80"
$mysqlservice = New-NsxService -name "tcp-3306" -protocol tcp -port "3306"

#Create Security Tags

$WebSt = New-NsxSecurityTag -name $WebStName
$AppSt = New-NsxSecurityTag -name $AppStName
$DbSt = New-NsxSecurityTag -name $DbStName


# Create IP Sets

write-host -foregroundcolor "Green" "Creating Source IP Groups"
$AppVIP_IpSet = New-NsxIPSet -Name AppVIP_IpSet -IPAddresses $EdgeInternalSecondaryAddress
$InternalESG_IpSet = New-NsxIPSet -name InternalESG_IpSet -IPAddresses $EdgeInternalPrimaryAddress

write-host -foregroundcolor "Green" "Creating Security Groups"

#Create SecurityGroups and with static includes
$WebSg = New-NsxSecurityGroup -name $WebSgName -description $WebSgDescription -includemember $WebSt
$AppSg = New-NsxSecurityGroup -name $AppSgName -description $AppSgDescription -includemember $AppSt
$DbSg = New-NsxSecurityGroup -name $DbSgName -description $DbSgDescription -includemember $DbSt
$BooksSg = New-NsxSecurityGroup -name $BooksSgName -description $BooksSgName -includemember $WebSg, $AppSg, $DbSg

# Apply Security Tag to VM's for Security Group membership

$WebVMs = Get-Vm | ? {$_.name -match ("Web0")}
$AppVMs = Get-Vm | ? {$_.name -match ("App0")}
$DbVMs = Get-Vm | ? {$_.name -match ("Db0")}


Get-NsxSecurityTag $WebStName | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine $WebVMs | Out-Null
Get-NsxSecurityTag $AppStName | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine $AppVMs | Out-Null
Get-NsxSecurityTag $DbStName | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine $DbVMs | Out-Null

#Building firewall section with value defined in $FirewallSectionName
write-host -foregroundcolor "Green" "Creating Firewall Section"

$FirewallSection = new-NsxFirewallSection $FirewallSectionName

#Actions
$AllowTraffic = "allow"
$DenyTraffic = "deny"

#Allows Web VIP to reach WebTier
write-host -foregroundcolor "Green" "Creating Web Tier rule"
$SourcesRule = get-nsxfirewallsection $FirewallSectionName | New-NSXFirewallRule -Name "VIP to Web" -Source $InternalESG_IpSet -Destination $WebSg -Service $HttpService -Action $AllowTraffic -AppliedTo $WebSg -position bottom

#Allows Web tier to reach App Tier via the APP VIP and then the NAT'd vNIC address of the Edge
write-host -foregroundcolor "Green" "Creating Web to App Tier rules"
$WebToAppVIP = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "$WebSgName to App VIP" -Source $WebSg -Destination $AppVIP_IpSet -Service $HttpService -Action $AllowTraffic -AppliedTo $WebSg, $AppSg -position bottom
$ESGToApp = get-NsxFirewallSection $FirewallSectionName | New-NsxFirewallRule -Name "App ESG interface to $AppSgName" -Source $InternalEsg_IpSet -Destination $appSg -service $HttpService -Action $Allowtraffic -AppliedTo $AppSg -position bottom

#Allows App tier to reach DB Tier directly
write-host -foregroundcolor "Green" "Creating Db Tier rules"
$AppToDb = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "$AppSgName to $DbSgName" -Source $AppSg -Destination $DbSg -Service $MySqlService -Action $AllowTraffic -AppliedTo $AppSg, $DbSG -position bottom

write-host -foregroundcolor "Green" "Creating deny all applied to $BooksSgName"
#Default rule that wraps around all VMs within the topolgoy - application specific DENY ALL
$BooksDenyAll = get-nsxfirewallsection $FirewallSectionName | New-NsxFirewallRule -Name "Deny All Books" -Action $DenyTraffic -AppliedTo $BooksSg -position bottom -EnableLogging -tag "$BooksSG"
write-host -foregroundcolor "Green" "Books application deployment complete."



