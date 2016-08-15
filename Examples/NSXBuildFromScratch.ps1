########################################
# Simple NSX environment standup script.
# Nick Bradford
# Nbradford@vmware.com
#

#Requires -version 3.0
#Requires -modules PowerNSX, VMware.VimAutomation.Core

#############################################
#############################################
# NSX Infrastructure Configuration.  Adjust to suit environment.

#NSX Details
$NsxManagerOVF = "C:\Temp\VMware-NSX-Manager-6.2.2-3604087.ova"
$NsxManagerName = "nsx-m-01a"
$NsxManagerPassword = "VMware1!"
$NsxManagerIpAddress = "192.168.100.201"
$ControllerPoolStartIp = "192.168.100.202"
$ControllerPoolEndIp = "192.168.100.204"
$ControllerPassword = "VMware1!VMware1!"
$SegmentPoolStart = "5000"
$SegmentPoolEnd = "5999"
$TransportZoneName = "TransportZone1"

#vSphereDetails
$VcenterServer = "vc-01a.corp.local"
$vCenterUserName = "administrator@vsphere.local"
$vCenterPassword = "VMware1!"
$MgmtClusterName = "Mgmt01"
$ManagementDatastoreName = "MgmtData"
$MgmtVdsName = "Mgt_Trans_Vds"
$ComputeClusterName = "Compute01" 
$ComputeVdsName = "Comp_Trans_Vds"
$EdgeClusterName = $MgmtClusterName
$EdgeDatastoreName = $ManagementDatastoreName
$ComputeDatastoreName = "CompData"

#Network Details
$ManagementNetworkPortGroupName = "Internal"
$ManagementNetworkSubnetMask = "255.255.255.0"
$ManagementNetworkSubnetPrefixLength = "24"
$ManagementNetworkGateway = "192.168.100.1"

$VxlanMtuSize = 1600

$MgmtVdsVxlanNetworkSubnetMask = "255.255.255.0"
$MgmtVdsVxlanNetworkSubnetPrefixLength = "24"
$MgmtVdsVxlanNetworkGateway = "172.16.110.1"
$MgmtVdsVxlanNetworkVlanId = "0"
$MgmtVdsVxlanVlanID = "0"
$MgmtVdsHostVtepCount = 1
$MgmtVdsVtepPoolStartIp = "172.16.110.201"
$MgmtVdsVtepPoolEndIp = "172.16.110.204"


$ComputeVdsVxlanNetworkSubnetMask = "255.255.255.0"
$ComputeVdsVxlanNetworkSubnetPrefixLength = "24"
$ComputeVdsVxlanNetworkGateway = "172.16.111.1"
$ComputeVdsVxlanNetworkVlanId = "0"
$ComputeVdsVxlanVlanID = "0"
$ComputeVdsHostVtepCount = 1
$ComputeVdsVtepPoolStartIp = "172.16.111.201"
$ComputeVdsVtepPoolEndIp = "172.16.111.204"


#Misc
$SyslogServer = "192.168.100.254"
$SysLogPort = 514
$SysLogProtocol = "TCP"
$NtpServer = "192.168.100.10"
$DnsServer1 = "192.168.100.10"
$DnsServer2 = "192.168.100.10"
$DnsSuffix = "corp.local"

#Reduce NSX Manager Memory - in GB.  Comment variable out for default.
$NsxManagerMem = 12

#############################################
#############################################
# Logical Topology environment 

$EdgeUplinkPrimaryAddress = "192.168.100.192"
$EdgeUplinkSecondaryAddress = "192.168.100.193"
$EdgeUplinkNetworkName = "Internal"
$AppliancePassword = "VMware1!VMware1!"
$BooksvAppLocation = "C:\Temp\3_Tier-App-v1.5.ova"
#Get v1.5 of the vApp from http://goo.gl/oBAFgq


############################################
############################################
# Topology Details.  No need to modify below here 

#Names
$TsTransitLsName = "Transit"
$TsWebLsName = "Web"
$TsAppLsName = "App"
$TsDbLsName = "Db"
$TsMgmtLsName = "Mgmt"
$TsEdgeName = "Edge01"
$TsLdrName = "Dlr01"

#Topology
$EdgeInternalPrimaryAddress = "172.16.1.1"
$EdgeInternalSecondaryAddress = "172.16.1.6"
$LdrUplinkPrimaryAddress = "172.16.1.2"
$LdrUplinkProtocolAddress = "172.16.1.3"
$LdrWebPrimaryAddress = "10.0.1.1"
$WebNetwork = "10.0.1.0/24"
$LdrAppPrimaryAddress = "10.0.2.1"
$AppNetwork = "10.0.2.0/24"
$LdrDbPrimaryAddress = "10.0.3.1"
$DbNetwork = "10.0.3.0/24"
$TransitOspfAreaId = "10"
$DefaultSubnetMask = "255.255.255.0"
$DefaultSubnetBits = "24"

#3Tier App
$vAppName = "Books"

#WebTier VMs
$Web01Name = "Web01"
$Web01Ip = "10.0.1.11"
$Web02Name = "Web02"
$Web02Ip = "10.0.1.12"

#AppTier VMs
$App01Name = "App01"
$App01Ip = "10.0.2.11"
$App02Name = "App02"
$App02Ip = "10.0.2.12"
$Db01Name = "Db01"
$Db01Ip = "10.0.3.11"

#DB Tier VMs
$Db02Name = "Db02"
$Db02Ip = "10.0.3.12"

##LoadBalancer
$LbAlgo = "round-robin"
$WebpoolName = "WebPool1"
$ApppoolName = "AppPool1"
$WebVipName = "WebVIP"
$AppVipName = "AppVIP"
$WebAppProfileName = "WebAppProfile"
$AppAppProfileName = "AppAppProfile"
$VipProtocol = "http"
$HttpPort = "80"

## Securiry Groups
$WebSgName = "SGWeb"
$WebSgDescription = "Web Security Group"
$AppSgName = "SGApp"
$AppSgDescription = "App Security Group"
$DbSgName = "SGDb"
$DbSgDescription = "DB Security Group"
$BooksSgName = "SGBooks"
$BooksSgDescription = "Books ALL Security Group"

#DFW
$FirewallSectionName = "Bookstore"
$LBMonitorName = "default_http_monitor"

###############################################
# Do Not modify below here.
###############################################

###############################################
###############################################
# Constants

$WaitStep = 30
$WaitTimeout = 600
$yesnochoices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
$yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
$yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

###############################
# Validation
# Connect to vCenter
# Check for PG, DS, Cluster

write-Host -foregroundcolor Green "Connecting to vCenter..."
if ( -not $DefaultViConnection.IsConnected ) { 
    connect-ViServer -Server $VcenterServer -User $vCenterUserName -Password $vCenterPassword -WarningAction Ignore | out-null
}

If ( -not ( test-path $BooksvAppLocation )) { throw "$BooksvAppLocation not found."}

try { 
    $MgmtCluster = Get-Cluster $MgmtClusterName -errorAction Stop
    $ComputeCluster = Get-Cluster $ComputeClusterName -errorAction Stop
    $EdgeCluster = get-cluster $EdgeClusterName -errorAction Stop
    $EdgeDatastore = get-datastore $EdgeDatastoreName -errorAction Stop
    $MgmtDatastore = Get-Datastore $ManagementDatastoreName -errorAction Stop
    $ManagementPortGroup = Get-VdPortGroup $ManagementNetworkPortGroupName -errorAction Stop
    $MgmtVds = Get-VdSwitch $MgmtVdsName -errorAction Stop
    $CompVds = Get-VdSwitch $ComputeVdsName -errorAction Stop
    $ComputeDatastore = get-datastore $ComputeDatastoreName -errorAction Stop
    $EdgeUplinkNetwork = get-vdportgroup $EdgeUplinkNetworkName -errorAction Stop

}
catch { 

    Throw "Failed validating vSphere Environment. $_"

}

#PowerCLI 6 is requried due to OvfConfiguration commands.
[int]$PowerCliMajorVersion = (Get-PowerCliVersion).major
if ( -not ($PowerCliMajorVersion -ge 6 ) ) { throw "OVF deployment tools requires PowerCLI version 6 or above" }


# 
###############################
# Deploy NSX Manager appliance.

write-Host -foregroundcolor Green "Deploying NSX Manager..."
try { 
    New-NsxManager -NsxManagerOVF $NsxManagerOVF -Name $NsxManagerName -ClusterName $MgmtClusterName -ManagementPortGroupName $ManagementNetworkPortGroupName -DatastoreName $ManagementDatastoreName -CliPassword $NsxManagerPassword -CliEnablePassword $NsxManagerPassword -Hostname $NsxManagerName -IpAddress $NsxManagerIpAddress -Netmask $ManagementNetworkSubnetMask -Gateway $ManagementNetworkGateway -DnsServer $DnsServer1 -DnsDomain $DnsSuffix -NtpServer $NtpServer -EnableSsh -StartVM -Wait -FolderName vm -ManagerMemoryGB $NsxManagerMem | out-null

    Connect-NsxServer -server $NsxManagerIpAddress -Username 'admin' -password $NsxManagerPassword -DisableViAutoConnect -ViWarningAction Ignore | out-null
      
}
catch {

    Throw "An error occured during NSX Manager deployment.  $_"
}
write-host -foregroundcolor Green "Complete`n"

###############################
# Configure NSX Manager appliance.

try { 
    write-host -foregroundcolor Green "Configuring NSX Manager`n"

    write-host "   -> Performing NSX Manager Syslog configuration."
    Set-NsxManager -SyslogServer $SyslogServer -SyslogPort $SysLogPort -SyslogProtocol $SysLogProtocol | out-null

    write-host "   -> Performing NSX Manager SSO configuration."
    Set-NsxManager -SsoServer $VcenterServer -SsoUserName $vCenterUserName -SsoPassword $vCenterPassword | out-null

    write-host "   -> Performing NSX Manager vCenter registration with account $vCenterUserName."
    Set-NsxManager -vCenterServer $VcenterServer -vCenterUserName $vCenterUserName -vCenterPassword $vCenterPassword | out-null

    write-host "   -> Establishing full connection to NSX Manager and vCenter."
    #Update the connection with VI connection details...
    Connect-NsxServer -server $NsxManagerIpAddress -Username 'admin' -password $NsxManagerPassword -VIUsername $vCenterUserName -VIPassword $vCenterPassword -ViWarningAction Ignore -DebugLogging | out-null

}
catch {

    Throw "Exception occured configuring NSX Manager.  $_"
    
}

write-host -foregroundcolor Green "Complete`n"


###############################
# Deploy NSX Controllers

write-host -foregroundcolor Green "Deploying NSX Controllers..."

try {

    write-host "   -> Creating IP Pool for Controller addressing"
 
    $ControllerPool = New-NsxIpPool -Name "Controller Pool" -Gateway $ManagementNetworkGateway -SubnetPrefixLength $ManagementNetworkSubnetPrefixLength -DnsServer1 $DnsServer1 -DnsServer2 $DnsServer2 -DnsSuffix $DnsSuffix -StartAddress $ControllerPoolStartIp -EndAddress $ControllerPoolEndIp

    for ( $i=0; $i -le 2; $i++ ) { 

        write-host "   -> Deploying NSX Controller $($i+1)"
        try {

            $Controller = New-NsxController -ipPool $ControllerPool -Cluster $MgmtCluster -datastore $MgmtDatastore -PortGroup $ManagementPortGroup -password $ControllerPassword -confirm:$false -wait
        }
        catch {
            throw "Controller $($i+1) deployment failed. $_"
        }
        write-host "   -> Controller $($i+1) online." 
    }
}
catch {

    Throw  "Failed deploying controller Cluster.  $_"
}

write-host -foregroundcolor Green "Complete`n"


##############################
# Prep VDS

write-host -foregroundcolor Green "Configuring VDS for use with NSX..."

try {
    #This is assuming two or more NICs on the uplink PG on this VDS.  No LAG required, and results in load balance accross multiple uplink NICs 
    New-NsxVdsContext -VirtualDistributedSwitch $MgmtVds -Teaming "LOADBALANCE_SRCID" -Mtu $VxlanMtuSize | out-null
    New-NsxVdsContext -VirtualDistributedSwitch $CompVds -Teaming "LOADBALANCE_SRCID" -Mtu $VxlanMtuSize | out-null

}
catch {
    Throw  "Failed configuring VDS.  $_"

}

write-host -foregroundcolor Green "Complete`n"

##############################
# Prep Clusters

write-host -foregroundcolor Green "Preparing clusters to run NSX..."


try {

    write-host "   -> Creating IP Pools for VTEP addressing"
 
    $MgmtVtepPool = New-NsxIpPool -Name "Management Vtep Pool" -Gateway $MgmtVdsVxlanNetworkGateway -SubnetPrefixLength $MgmtVdsVxlanNetworkSubnetPrefixLength -DnsServer1 $DnsServer1 -DnsServer2 $DnsServer2 -DnsSuffix $DnsSuffix -StartAddress $MgmtVdsVtepPoolStartIp -EndAddress $MgmtVdsVtepPoolEndIp

    $Compute01VtepPool = New-NsxIpPool -Name "Compute01 Vtep Pool" -Gateway $ComputeVdsVxlanNetworkGateway -SubnetPrefixLength $ComputeVdsVxlanNetworkSubnetPrefixLength -DnsServer1 $DnsServer1 -DnsServer2 $DnsServer2 -DnsSuffix $DnsSuffix -StartAddress $ComputeVdsVtepPoolStartIp -EndAddress $ComputeVdsVtepPoolEndIp
    
    write-host "   -> Preparing cluster Mgmt01 and configuring VXLAN."
    Get-Cluster $MgmtCluster | New-NsxClusterVxlanConfig -VirtualDistributedSwitch $MgmtVds -Vlan $MgmtVdsVxlanVlanID -VtepCount $MgmtVdsHostVtepCount -ipPool $MgmtVtepPool| out-null

    write-host "   -> Preparing cluster Compute01 and configuring VXLAN."
    Get-Cluster $ComputeCluster | New-NsxClusterVxlanConfig -VirtualDistributedSwitch $CompVds -Vlan $ComputeVdsVxlanVlanID -VtepCount $ComputeVdsHostVtepCount -ipPool $Compute01VtepPool | out-null


}
catch {
    Throw  "Failed preparing clusters for NSX.  $_"

}
write-host -foregroundcolor Green "Complete`n"


##############################
# Configure Segment Pool

write-host -foregroundcolor Green "Configuring SegmentId Pool..."

try {

        write-host "   -> Creating Segment Id Pool."
        New-NsxSegmentIdRange -Name "SegmentIDPool" -Begin $SegmentPoolStart -end $SegmentPoolEnd | out-null
}
catch {
    Throw  "Failed configuring SegmentId Pool.  $_"
}

write-host -foregroundcolor Green "Complete`n"

##############################
# Create Transport Zone
 
write-host -foregroundcolor Green "Configuring Transport Zone..."

try {

    write-host "   -> Creating Transport Zone $TransportZoneName."
    #Configure TZ and add clusters.
    New-NsxTransportZone -Name $TransportZoneName -Cluster $MgmtCluster, $ComputeCluster -ControlPlaneMode "UNICAST_MODE" | out-null

}
catch {
    Throw  "Failed configuring Transport Zone.  $_"

}

write-host -foregroundcolor Green "`nNSX Infrastructure Config Complete`n"


######################################
######################################
## Topology Deployment

write-host -foregroundcolor Green "NSX Books application deployment beginning.`n"


######################################
#Logical Switches

write-host -foregroundcolor "Green" "Creating Logical Switches..."

## Creates four logical switches
$TsTransitLs = Get-NsxTransportZone | New-NsxLogicalSwitch $TsTransitLsName
$TsWebLs = Get-NsxTransportZone | New-NsxLogicalSwitch $TsWebLsName
$TsAppLs = Get-NsxTransportZone | New-NsxLogicalSwitch $TsAppLsName
$TsDbLs = Get-NsxTransportZone | New-NsxLogicalSwitch $TsDbLsName
$TsMgmtLs = Get-NsxTransportZone | New-NsxLogicalSwitch $TsMgmtLsName


######################################
# DLR

# DLR Appliance has the uplink router interface created first.
write-host -foregroundcolor "Green" "Creating DLR"
$TsLdrvNic0 = New-NsxLogicalRouterInterfaceSpec -type Uplink -Name $TsTransitLsName -ConnectedTo $TsTransitLs -PrimaryAddress $LdrUplinkPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits

# The DLR is created with the first vnic defined, and the datastore and cluster on which the Control VM will be deployed.
$TsLdr = New-NsxLogicalRouter -name $TsLdrName -ManagementPortGroup $TsMgmtLs -interface $TsLdrvNic0 -cluster $EdgeCluster -datastore $EdgeDataStore

## Adding DLR interfaces after the DLR has been deployed. This can be done any time if new interfaces are required.
write-host -foregroundcolor Green "Adding Web LIF to DLR"
$TsLdr | New-NsxLogicalRouterInterface -Type Internal -name $TsWebLsName  -ConnectedTo $TsWebLs -PrimaryAddress $LdrWebPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
write-host -foregroundcolor Green "Adding App LIF to DLR"
$TsLdr | New-NsxLogicalRouterInterface -Type Internal -name $TsAppLsName  -ConnectedTo $TsAppLs -PrimaryAddress $LdrAppPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null
write-host -foregroundcolor Green "Adding DB LIF to DLR"
$TsLdr | New-NsxLogicalRouterInterface -Type Internal -name $TsDbLsName  -ConnectedTo $TsDbLs -PrimaryAddress $LdrDbPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits | out-null

## DLR Routing - default route from DLR with a next-hop of the Edge.
write-host -foregroundcolor Green "Setting default route on DLR to $EdgeInternalPrimaryAddress"

##The first line pulls the uplink name coz we cant assume we know the index ID
$TsLdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TsTransitLsName}
Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic $TsLdrTransitInt.index -DefaultGatewayAddress $EdgeInternalPrimaryAddress -confirm:$false | out-null


######################################
# EDGE

## Defining the uplink and internal interfaces to be used when deploying the edge. Note there are two IP addreses on these interfaces. $EdgeInternalSecondaryAddress and $EdgeUplinkSecondaryAddress are the VIPs
$edgevnic0 = New-NsxEdgeinterfacespec -index 0 -Name "Uplink" -type Uplink -ConnectedTo $EdgeUplinkNetwork -PrimaryAddress $EdgeUplinkPrimaryAddress -SecondaryAddress $EdgeUplinkSecondaryAddress -SubnetPrefixLength $DefaultSubnetBits
$edgevnic1 = New-NsxEdgeinterfacespec -index 1 -Name $TsTransitLsName -type Internal -ConnectedTo $TsTransitLs -PrimaryAddress $EdgeInternalPrimaryAddress -SubnetPrefixLength $DefaultSubnetBits -SecondaryAddress $EdgeInternalSecondaryAddress

## Deploy appliance with the defined uplinks
write-host -foregroundcolor "Green" "Creating Edge"
$TSEdge1 = New-NsxEdge -name $TsEdgeName -cluster $EdgeCluster -datastore $EdgeDataStore -Interface $edgevnic0, $edgevnic1 -Password $AppliancePassword -FwDefaultPolicyAllow


#####################################
# Load LoadBalancer

# Enanble Loadbalancing on $TSedgeName
write-host -foregroundcolor "Green" "Enabling LoadBalancing on $TsEdgeName"
Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | Set-NsxLoadBalancer -Enabled | out-null

#Get default monitor.
$monitor =  get-nsxedge | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor -Name $LBMonitorName


# Define pool members.  By way of example we will use two different methods for defining pool membership.  Webpool via predefine memberspec first...
write-host -foregroundcolor "Green" "Creating Web Pool"
$webpoolmember1 = New-NsxLoadBalancerMemberSpec -name $Web01Name -IpAddress $Web01Ip -Port $HttpPort
$webpoolmember2 = New-NsxLoadBalancerMemberSpec -name $Web02Name -IpAddress $Web02Ip -Port $HttpPort

# ... And create the web pool
$WebPool =  Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name $WebPoolName -Description "Web Tier Pool" -Transparent:$false -Algorithm $LbAlgo -Memberspec $webpoolmember1, $webpoolmember2 -Monitor $Monitor

# Now method two for the App Pool  Create the pool with empty membership.
write-host -foregroundcolor "Green" "Creating App Pool"
$AppPool = Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name $AppPoolName -Description "App Tier Pool" -Transparent:$false -Algorithm $LbAlgo -Monitor $Monitor

# ... And now add the pool members
$AppPool = $AppPool | Add-NsxLoadBalancerPoolMember -name $App01Name -IpAddress $App01Ip -Port $HttpPort
$AppPool = $AppPool | Add-NsxLoadBalancerPoolMember -name $App02Name -IpAddress $App02Ip -Port $HttpPort

# Create App Profiles. It is possible to use the same but for ease of operations this will be two here.
write-host -foregroundcolor "Green" "Creating Application Profiles for Web and App"
$WebAppProfile = Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationProfile -Name $WebAppProfileName  -Type $VipProtocol
$AppAppProfile = Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | new-NsxLoadBalancerApplicationProfile -Name $AppAppProfileName  -Type $VipProtocol

# Create the VIPs for the relevent WebPools. Using the Secondary interfaces.
write-host -foregroundcolor "Green" "Creating VIPs"
Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name $WebVipName -Description $WebVipName -ipaddress $EdgeUplinkSecondaryAddress -Protocol $VipProtocol -Port $HttpPort -ApplicationProfile $WebAppProfile -DefaultPool $WebPool -AccelerationEnabled | out-null
Get-NsxEdge $TsEdgeName | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name $AppVipName -Description $AppVipName -ipaddress $EdgeInternalSecondaryAddress -Protocol $VipProtocol -Port $HttpPort -ApplicationProfile $AppAppProfile -DefaultPool $AppPool -AccelerationEnabled | out-null


####################################
# OSPF

write-host -foregroundcolor Green "Configuring Edge OSPF"
Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | set-NsxEdgeRouting -EnableOspf -RouterId $EdgeUplinkPrimaryAddress -confirm:$false | out-null

#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea -confirm:$false

#Create new Area 0 for OSPF
Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

#Area to interface mapping
Get-NsxEdge $TsEdgeName | Get-NsxEdgerouting | New-NsxEdgeOspfInterface -AreaId $TransitOspfAreaId -vNic 1 -confirm:$false | out-null

write-host -foregroundcolor Green "Configuring Logicalrouter OSPF"
Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | set-NsxLogicalRouterRouting -EnableOspf -EnableOspfRouteRedistribution -RouterId $LdrUplinkPrimaryAddress -ProtocolAddress $LdrUplinkProtocolAddress -ForwardingAddress $LdrUplinkPrimaryAddress  -confirm:$false | out-null

#Remove the dopey area 51 NSSA - just to show example of complete OSPF configuration including area creation.
Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea -confirm:$false

#Create new Area
Get-NsxLogicalRouter $TsLdrName | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId $TransitOspfAreaId -Type normal -confirm:$false | out-null

#Area to interface mapping
$TsLdrTransitInt = get-nsxlogicalrouter | get-nsxlogicalrouterinterface | ? { $_.name -eq $TsTransitLsName}
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
$WebNetwork = get-nsxtransportzone | get-nsxlogicalswitch $TsWebLsName | Get-NsxBackingPortGroup | Where { $_.VDSwitch -eq $ComputeVDS }
$AppNetwork = get-nsxtransportzone | get-nsxlogicalswitch $TsAppLsName | Get-NsxBackingPortGroup | Where { $_.VDSwitch -eq $ComputeVDS }
$DbNetwork = get-nsxtransportzone | get-nsxlogicalswitch $TsDbLsName | Get-NsxBackingPortGroup | Where { $_.VDSwitch -eq $ComputeVDS }

# Compute details - finds the host with the least used memory for deployment.
$VMHost = $Computecluster | Get-VMHost | Sort MemoryUsageGB | Select -first 1

# Get OVF configuration so we can modify it.
$OvfConfiguration = Get-OvfConfiguration -Ovf $BooksvAppLocation

# Network attachment.
$OvfConfiguration.vxw_dvs_24_universalwire_1_sid_50000_Universal_Web01 = $WebNetwork.Name
$OvfConfiguration.vxw_dvs_24_universalwire_2_sid_50001_Universal_App01 = $AppNetwork.Name
$OvfConfiguration.vxw_dvs_24_universalwire_3_sid_50002_Universal_Db01 = $DbNetwork.Name

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
$httpservice = Get-NsxService HTTP
$mysqlservice = Get-NsxService MySQL

write-host -foregroundcolor "Green" "Creating Source IP Groups"
$AppVIP_IpSet = New-NsxIPSet -Name AppVIP_IpSet -IPAddresses $EdgeInternalSecondaryAddress
$InternalESG_IpSet = New-NsxIPSet -name InternalESG_IpSet -IPAddresses $EdgeInternalPrimaryAddress

write-host -foregroundcolor "Green" "Creating Security Groups"

#Create SecurityGroups and with static includes
$WebSg = New-NsxSecurityGroup -name $WebSgName -description $WebSgDescription -includemember (get-vm | ? {$_.name -match "Web0"})
$AppSg = New-NsxSecurityGroup -name $AppSgName -description $AppSgDescription -includemember (get-vm | ? {$_.name -match "App0"})
$DbSg = New-NsxSecurityGroup -name $DbSgName -description $DbSgDescription -includemember (get-vm | ? {$_.name -match "Db0"})
$BooksSg = New-NsxSecurityGroup -name $BooksSgName -description $BooksSgName -includemember $WebSg, $AppSg, $DbSg

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


