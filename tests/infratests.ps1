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


#Performs a complete NSX environment build with the following:
#   - Manager Deploy from ovf to vc 1
#   - Configure Manager
#   - Link to VC 2
#   - Deploy Controller cluster to VC 2 Cluster
#   - Configure VC2 Cluster for VXLAN
#   - Configure Segment ID pool and Transport Zone
#
# This is super tied to my test environment, so its unlikely to be able to be run by others. 


$mgrIP = "192.168.100.97"
$DS = "Data"
$Cluster = "mgmt01"
$Folder = "CustA"
$PG = "Pri_Services"
$pwd = "VMware1!VMware1!"
$name = "testmanager"
$mask = "255.255.255.0"
$gw = "192.168.100.1"
$dns = "192.168.100.10"
$dnsdomain = "corp.local"
$ntp = "192.168.100.10"
$ovf = "C:\Users\Administrator\Downloads\VMware-NSX-Manager-6.2.0-2986609.ova"
$syslogip = "1.2.3.4"
$ssoServer = "custa-vcsa.corp.local"
$ssousername = "administrator@custa.local"
$ssopassword = "VMware1!"
$vcenterserver = $ssoServer
$vcusername= $ssousername
$vcpassword = $ssopassword
$NsxManagerWaitStep = 60
$NsxManagerWaitTimeout = 300
$ippoolgw = "192.168.100.1"
$ippoolprefix = 24
$ippoolsuffix = "corp.local"
$ippooldns1 = "192.168.100.10"
$ippooldns2 = "192.168.100.10"
$ippoolName = "ControllerPool"
$ippoolStart = "192.168.100.51"
$ippoolend = "192.168.100.53"
$SyslogServer = "192.168.100.10"
$SyslogPort = 514
$SyslogProtocol = "udp"
$ControllerClusterName = "TestCluster"
$ControllerDatastoreName = "Data"
$ControllerPortGroupName = "Pri_Services"
$DefaultNsxControllerPassword = $pwd
$ControllerWaitStep = 60
$ControllerWaitTimeout = 400
$vtepippoolName = "VtepPool"
$vtepippoolgw = "10.10.0.1"
$vtepippoolprefix = "24"
$vtepippoolStart = "10.10.0.221"
$vtepippoolend = "10.10.0.240"
$segmentpoolstart = 5000
$segmentpoolend = 5999
$transportzoneName = "TestTZ"

$VCSnapshot = Get-VM $vcenterserver | Get-Snapshot
$yesnochoices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
$yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
$yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

write-host "Deploying NSX Manager"
$mgrVM = New-NSXManager -NsxManagerOVF $ovf `
    -Name $Name -ClusterName $cluster -ManagementPortGroupName $PG -DatastoreName $DS -FolderName $folder `
    -CliPassword $pwd -CliEnablePassword $pwd -Hostname $name -IpAddress $mgrIp `
    -Netmask $mask -Gateway $gw -DnsServer $dns -DnsDomain $dnsdomain -NtpServer $ntp -EnableSsh

write-host "Starting NSX Manager"
$mgrVm | set-vm -memoryGb 8 -confirm:$false | start-vm | out-null

    
#Need some wait code - simple scrape of API in timeout governed loop
$startTimer = Get-Date
write-host "Waiting for NSX Manager API to become available"

do {

    #sleep a while, the VM will take time to start fully..
    start-sleep $NsxManagerWaitStep
    try { 
        $tmpConnect = Connect-NsxServer -server $mgrIp -Username 'admin' -password $Pwd -DisableViAutoConnect -DefaultConnection:$False
        break
    }
    catch { 
        write-warning "Waiting for NSX Manager API to become available"
    }

    if ( ((get-date) - $startTimer).Seconds -gt $NsxManagerWaitTimeout ) { 

        #We exceeded the timeout - what does the user want to do? 
        $message  = "Waited more than $NsxManagerWaitTimeout seconds for NSX Manager API to become available.  Recommend checking boot process, network config etc."
        $question = "Continue waiting for NSX Manager?"
        $decision = $Host.UI.PromptForChoice($message, $question, $yesnochoices, 0)
        if ($decision -eq 0) {
           #User waits...
           $startTimer = get-date
        }
        else {
            throw "Failed Deploying Customer NSX Manager appliance"
        }
    }    

    
} while ( $true )

write-host "NSX Manager Started successfully"


#Initial Connection
write-host "Initial connection to NSX Manager"
$Connection = Connect-NsxServer -Server $mgrIp -username "admin" -Password $pwd -DisableVIAutoConnect -DefaultConnection:$false -VIDefaultConnection:$false

write-host "Setting Syslog Server"
Set-NsxManager -SyslogServer $SyslogServer -SyslogPort $SyslogPort -SyslogProtocol $SyslogProtocol -connection $connection | out-null

write-host "Registering SSO on NSX Manager"
Set-NsxManager -ssoserver $ssoServer -ssousername $ssousername -ssopassword $ssopassword -connection $connection | out-null

write-host "Registering vCenter Server on NSX Manager"
Set-NsxManager -vcenterusername $vcusername -vcenterpassword $vcpassword -vcenterserver $vcenterserver -connection $connection | out-null

write-host "Reconnecting to NSX Manager to trigger VC autoconnect"
$Connection = Connect-NsxServer -Server $mgrIp -username "admin" -Password $pwd -DefaultConnection:$false -ViUserName $ssousername -ViPassword $ssopassword -VIDefaultConnection:$false

write-host "Configuring IP Pool for Controllers"
$ippool = New-NsxIpPool -Name $ippoolName -Gateway $ippoolgw -SubnetPrefixLength $ippoolprefix -dnsserver1 $ippooldns1 -dnsserver2 $ippooldns2 `
-dnssuffix $ippoolsuffix -StartAddress $ippoolStart -endaddress $ippoolend -connection $connection


write-host "Getting VC objects for Controller Deployment"
$ControllerCluster = Get-Cluster $ControllerClusterName -server $Connection.VIConnection
$ControllerDatastore = Get-Datastore $ControllerDatastoreName -server $Connection.VIConnection 
$ControllerPortGroup = Get-VDPortGroup $ControllerPortGroupName -server $Connection.VIConnection

for ( $i=0; $i -le 2; $i++ ) { 

    write-host "Deploying NSX Controller $($i+1)"

    try { 
        $Controller = New-NsxController -ipPool $ippool -cluster $ControllerCluster `
    -datastore $ControllerDatastore -PortGroup $ControllerPortGroup -password $DefaultNsxControllerPassword -connection $Connection -confirm:$false

    }
    catch {
        throw "Controller deployment failed.  $_"

    }

    $Timer = 0
    while (  (Get-Nsxcontroller -objectId ($controller.id) -connection $Connection).status -ne 'RUNNING' ) { 
        write-host "Waiting for NSX controller to become available."
        start-sleep $ControllerWaitStep
        $Timer += $ControllerWaitStep
        if ( $Timer -ge $ControllerWaitTimeout ) { 
            
            #We exceeded the timeout - what does the user want to do? 
            $message  = "Waited more than $ControllerWaitTimeout seconds for controller to become available.  Recommend checking boot process, network config etc."
            $question = "Continue waiting for Controller?"
            $decision = $Host.UI.PromptForChoice($message, $question, $yesnochoices, 0)
            if ($decision -eq 0) {
               #User waits...
               $timer = 0
            }
            else {
                throw "Timeout waiting for controller to become available."
            }  
        }
    } 
}

write-host "Configuring IP Pool for VTEPs"
$VTEPippool = New-NsxIpPool -Name $vtepippoolName -Gateway $vtepippoolgw -SubnetPrefixLength $vtepippoolprefix  -StartAddress $vtepippoolStart -endaddress $vtepippoolend -connection $connection

write-host "Preparing VDS for NSX"
$VtepVds = Get-VDSwitch mgmt_transit -server $connection.VIConnection
$vdscontext = New-NsxVdsContext -VirtualDistributedSwitch $VtepVds -Teaming FAILOVER_ORDER -Mtu 1600 -connection $connection | out-null

write-host "Preparing Cluster and configuring VXLAN"
$ControllerCluster | New-NsxClusterVxlanConfig -VirtualDistributedSwitch $VtepVds -IpPool $VTEPippool -VlanId 0 -VtepCount 1 -connection $connection | out-null

write-host "Configuring Segment Id Range"
New-NsxSegmentIdRange -Name TestSegment -Begin $segmentpoolstart -End $segmentpoolend -connection $connection

write-host "Configuring Transport Zone"
New-NsxTransportZone -name $transportzoneName -ControlPlaneMode UNICAST_MODE -Cluster $ControllerCluster -connection $connection

write-host -foregroundcolor Green "Complete"
read-host "Hit enter to tear down..."

write-host "Removing TransportZone"
Get-NsxTransportZone  -connection $connection | remove-nsxTransportZone -connection $connection -confirm:$false

write-host "Unconfiguring SegmentIdRange"
Get-NsxSegmentIdRange -connection $connection | Remove-NsxSegmentIdRange -connection $connection -confirm:$false


write-host "Deleting Controllers"
$ControllerCluster | get-vm  -server $connection.VIConnection| stop-vm -server $connection.VIConnection -confirm:$false | out-null

start-sleep 10
$ControllerCluster | get-vm  -server $connection.VIConnection | remove-vm  -server $connection.VIConnection -confirm:$false -DeletePermanently

write-host "Unconfiguring Cluster"
$ControllerCluster | Remove-NsxClusterVxlanConfig -connection $connection -confirm:$false


#Cant do this yet as we dont have a way to detect and resolve hosts requiring reboot...
#$ControllerCluster | Remove-NsxCluster -connection $connection -confirm:$false

write-host "Removing VDS Context"
$vdscontext | Remove-NsxVdsContext -connection $connection -confirm:$false


Get-VM $vcenterserver | set-vm -snapshot $VCSnapshot -confirm:$false | out-null
get-vm $name | stop-vm -kill -confirm:$false | out-null
start-sleep 10
get-vm $name | remove-vm -DeletePermanently -confirm:$false | out-null

$Name
$mgrIP = "192.168.100.97"
$DS = "Data"
$Cluster = "mgmt01"
$Folder = "CustA"
$PG = "Pri_Services"
$pwd = "VMware1!VMware1!"
$name = "testmanager"
$mask = "255.255.255.0"
$gw = "192.168.100.1"
$dns = "192.168.100.10"
$dnsdomain = "corp.local"
$ntp = "192.168.100.10"
$ovf = "C:\Users\Administrator\Downloads\VMware-NSX-Manager-6.2.0-2986609.ova"
$syslogip = "1.2.3.4"
$ssoServer = "custa-vcsa.corp.local"
$ssousername = "administrator@custa.local"
$ssopassword = "VMware1!"
$vcenterserver = $ssoServer
$vcusername= $ssousername
$vcpassword = $ssopassword
$NsxManagerWaitStep = 60
$NsxManagerWaitTimeout = 300
$ippoolgw = "192.168.100.1"
$ippoolprefix = 24
$ippoolsuffix = "corp.local"
$ippooldns1 = "192.168.100.10"
$ippooldns2 = "192.168.100.10"
$ippoolName = "ControllerPool"
$ippoolStart = "192.168.100.51"
$ippoolend = "192.168.100.53"
$SyslogServer = "192.168.100.10"
$SyslogPort = 514
$SyslogProtocol = "udp"
$ControllerClusterName = "TestCluster"
$ControllerDatastoreName = "Data"
$ControllerPortGroupName = "Pri_Services"
$DefaultNsxControllerPassword = $pwd
$ControllerWaitStep = 60
$ControllerWaitTimeout = 400
$vtepippoolName = "VtepPool"
$vtepippoolgw = "10.10.0.1"
$vtepippoolprefix = "24"
$vtepippoolStart = "10.10.0.221"
$vtepippoolend = "10.10.0.240"
$segmentpoolstart = 5000
$segmentpoolend = 5999
$transportzoneName = "TestTZ"

$VCSnapshot = Get-VM $vcenterserver | Get-Snapshot
$yesnochoices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
$yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
$yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

write-host "Deploying NSX Manager"
$mgrVM = New-NSXManager -NsxManagerOVF $ovf `
    -Name $Name -ClusterName $cluster -ManagementPortGroupName $PG -DatastoreName $DS -FolderName $folder `
    -CliPassword $pwd -CliEnablePassword $pwd -Hostname $name -IpAddress $mgrIp `
    -Netmask $mask -Gateway $gw -DnsServer $dns -DnsDomain $dnsdomain -NtpServer $ntp -EnableSsh

write-host "Starting NSX Manager"
$mgrVm | set-vm -memoryGb 8 -confirm:$false | start-vm | out-null

    
#Need some wait code - simple scrape of API in timeout governed loop
$startTimer = Get-Date
write-host "Waiting for NSX Manager API to become available"

do {

    #sleep a while, the VM will take time to start fully..
    start-sleep $NsxManagerWaitStep
    try { 
        $tmpConnect = Connect-NsxServer -server $mgrIp -Username 'admin' -password $Pwd -DisableViAutoConnect -DefaultConnection:$False
        break
    }
    catch { 
        write-warning "Waiting for NSX Manager API to become available"
    }

    if ( ((get-date) - $startTimer).Seconds -gt $NsxManagerWaitTimeout ) { 

        #We exceeded the timeout - what does the user want to do? 
        $message  = "Waited more than $NsxManagerWaitTimeout seconds for NSX Manager API to become available.  Recommend checking boot process, network config etc."
        $question = "Continue waiting for NSX Manager?"
        $decision = $Host.UI.PromptForChoice($message, $question, $yesnochoices, 0)
        if ($decision -eq 0) {
           #User waits...
           $startTimer = get-date
        }
        else {
            throw "Failed Deploying Customer NSX Manager appliance"
        }
    }    

    
} while ( $true )

write-host "NSX Manager Started successfully"


#Initial Connection
write-host "Initial connection to NSX Manager"
$Connection = Connect-NsxServer -Server $mgrIp -username "admin" -Password $pwd -DisableVIAutoConnect -DefaultConnection:$false -VIDefaultConnection:$false

write-host "Setting Syslog Server"
Set-NsxManager -SyslogServer $SyslogServer -SyslogPort $SyslogPort -SyslogProtocol $SyslogProtocol -connection $connection | out-null

write-host "Registering SSO on NSX Manager"
Set-NsxManager -ssoserver $ssoServer -ssousername $ssousername -ssopassword $ssopassword -connection $connection | out-null

write-host "Registering vCenter Server on NSX Manager"
Set-NsxManager -vcenterusername $vcusername -vcenterpassword $vcpassword -vcenterserver $vcenterserver -connection $connection | out-null

write-host "Reconnecting to NSX Manager to trigger VC autoconnect"
$Connection = Connect-NsxServer -Server $mgrIp -username "admin" -Password $pwd -DefaultConnection:$false -ViUserName $ssousername -ViPassword $ssopassword -VIDefaultConnection:$false

write-host "Configuring IP Pool for Controllers"
$ippool = New-NsxIpPool -Name $ippoolName -Gateway $ippoolgw -SubnetPrefixLength $ippoolprefix -dnsserver1 $ippooldns1 -dnsserver2 $ippooldns2 `
-dnssuffix $ippoolsuffix -StartAddress $ippoolStart -endaddress $ippoolend -connection $connection


write-host "Getting VC objects for Controller Deployment"
$ControllerCluster = Get-Cluster $ControllerClusterName -server $Connection.VIConnection
$ControllerDatastore = Get-Datastore $ControllerDatastoreName -server $Connection.VIConnection 
$ControllerPortGroup = Get-VDPortGroup $ControllerPortGroupName -server $Connection.VIConnection

for ( $i=0; $i -le 2; $i++ ) { 

    write-host "Deploying NSX Controller $($i+1)"

    try { 
        $Controller = New-NsxController -ipPool $ippool -cluster $ControllerCluster `
    -datastore $ControllerDatastore -PortGroup $ControllerPortGroup -password $DefaultNsxControllerPassword -connection $Connection -confirm:$false

    }
    catch {
        throw "Controller deployment failed.  $_"

    }

    $Timer = 0
    while (  (Get-Nsxcontroller -objectId ($controller.id) -connection $Connection).status -ne 'RUNNING' ) { 
        write-host "Waiting for NSX controller to become available."
        start-sleep $ControllerWaitStep
        $Timer += $ControllerWaitStep
        if ( $Timer -ge $ControllerWaitTimeout ) { 
            
            #We exceeded the timeout - what does the user want to do? 
            $message  = "Waited more than $ControllerWaitTimeout seconds for controller to become available.  Recommend checking boot process, network config etc."
            $question = "Continue waiting for Controller?"
            $decision = $Host.UI.PromptForChoice($message, $question, $yesnochoices, 0)
            if ($decision -eq 0) {
               #User waits...
               $timer = 0
            }
            else {
                throw "Timeout waiting for controller to become available."
            }  
        }
    } 
}

write-host "Configuring IP Pool for VTEPs"
$VTEPippool = New-NsxIpPool -Name $vtepippoolName -Gateway $vtepippoolgw -SubnetPrefixLength $vtepippoolprefix  -StartAddress $vtepippoolStart -endaddress $vtepippoolend -connection $connection

write-host "Preparing VDS for NSX"
$VtepVds = Get-VDSwitch mgmt_transit -server $connection.VIConnection
$vdscontext = New-NsxVdsContext -VirtualDistributedSwitch $VtepVds -Teaming FAILOVER_ORDER -Mtu 1600 -connection $connection | out-null

write-host "Preparing Cluster and configuring VXLAN"
$ControllerCluster | New-NsxClusterVxlanConfig -VirtualDistributedSwitch $VtepVds -IpPool $VTEPippool -VlanId 0 -VtepCount 1 -connection $connection | out-null

write-host "Configuring Segment Id Range"
New-NsxSegmentIdRange -Name TestSegment -Begin $segmentpoolstart -End $segmentpoolend -connection $connection | out-null

write-host "Configuring Transport Zone"
New-NsxTransportZone -name $transportzoneName -ControlPlaneMode UNICAST_MODE -Cluster $ControllerCluster -connection $connection | out-null

write-host -foregroundcolor Green "Complete"
read-host "Hit enter to tear down..."

write-host "Removing TransportZone"
Get-NsxTransportZone  -connection $connection | remove-nsxTransportZone -connection $connection -confirm:$false

write-host "Unconfiguring SegmentIdRange"
Get-NsxSegmentIdRange -connection $connection | Remove-NsxSegmentIdRange -connection $connection -confirm:$false


write-host "Deleting Controllers"
$ControllerCluster | get-vm  -server $connection.VIConnection| stop-vm -server $connection.VIConnection -confirm:$false | out-null

start-sleep 10
$ControllerCluster | get-vm  -server $connection.VIConnection | remove-vm  -server $connection.VIConnection -confirm:$false -DeletePermanently

write-host "Unconfiguring Cluster"
$ControllerCluster | Remove-NsxClusterVxlanConfig -connection $connection -confirm:$false


#Cant do this yet as we dont have a way to detect and resolve hosts requiring reboot...
#$ControllerCluster | Remove-NsxCluster -connection $connection -confirm:$false

write-host "Removing VDS Context"
$vdscontext | Remove-NsxVdsContext -connection $connection -confirm:$false


Get-VM $vcenterserver | set-vm -snapshot $VCSnapshot -confirm:$false | out-null
get-vm $name | stop-vm -kill -confirm:$false | remove-vm -DeletePermanently -confirm:$false | out-null
