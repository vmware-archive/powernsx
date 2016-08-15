<#
 VMworld 2016 NET7514 demo script
 Nick Bradford, nbradford@vmware.com
 The reason this script is structured the way it is is purely to aid in 
 demonstration of the individual commands in front of a large audience of people
 where my typing is not likely to be at its best! :)

 A global 'steps' array is defined that contains each of the commands as they 
 would be typed (minus the {} script block wrapper) by an operator doing each 
 step manually.

 ShowTheAwesome is the function that, when executed, shows the command being run
 on screen, and then executes it within the global scope (so variables can be 
 used without scope modifiers.)

 Anyone who is starting with PoSH/PowerNSX might not understand exactly what I 
 mean above, but suffice to say, if you copy each command within the {}'s and run 
 it, sequentially, you will get the same result.

#>


$steps = @(
    {connect-nsxserver -server "nsx-m-01a-local.corp.local" -username admin -password VMware1! -viusername administrator@vsphere.local -vipassword VMware1! -ViWarningAction "Ignore"},
    {$tz = Get-NsxTransportZone },
    {$webls = New-NsxLogicalSwitch -TransportZone $tz -Name webls},
    {$appls = New-NsxLogicalSwitch -TransportZone $tz -Name appls},
    {$dbls = New-NsxLogicalSwitch -TransportZone $tz -Name dbls},
    {$transitls = New-NsxLogicalSwitch -TransportZone $tz -Name transitls},
    {$uplink = New-NsxEdgeInterfaceSpec -Index 0 -Name uplink -type uplink -ConnectedTo (Get-VDPortgroup internal) -PrimaryAddress 192.168.100.20 -SubnetPrefixLength 24},
    {$transit = New-NsxEdgeInterfaceSpec -Index 1 -Name transit -type internal -ConnectedTo (Get-nsxlogicalswitch transitls) -PrimaryAddress 172.16.100.1 -SubnetPrefixLength 29},
    {new-nsxedge -Name edge01 -Cluster (get-cluster mgmt01) -Datastore (get-datastore mgmtdata) -Password VMware1!VMware1! -FormFactor compact -Interface $uplink,$transit -FwDefaultPolicyAllow},
    {get-nsxedge edge01 | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayAddress 192.168.100.1 -confirm:$false},
<<<<<<< HEAD
    {get-nsxedge edge01 | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgp -LocalAS 100 -RouterId 192.168.100.20 -confirm:$false},
    {get-nsxedge edge01 | Get-NsxEdgeRouting | Set-NsxEdgeBgp -DefaultOriginate -confirm:$false},
    {get-nsxedge edge01 | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgpRouteRedistribution -confirm:$false},
    {get-nsxedge edge01 | Get-NsxEdgeRouting | New-NsxEdgeBgpNeighbour -IpAddress 172.16.100.3 -RemoteAS 200 -confirm:$false},
=======
    {get-nsxedge edge01 | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBgp -LocalAS 100 -RouterId 192.168.100.200 -confirm:$false},
    {get-nsxedge | Get-NsxEdgeRouting | Set-NsxEdgeBgp -DefaultOriginate -confirm:$false},
    {get-nsxedge edge01 | Get-NsxEdgeRouting |Set-NsxEdgeRouting -EnableBgpRouteRedistribution -confirm:$false},
    {get-nsxedge | Get-NsxEdgeRouting | New-NsxEdgeBgpNeighbour -IpAddress 172.16.100.3 -RemoteAS 200 -confirm:$false},
>>>>>>> 7c699b3c716299170b4cd59fa1f613d9a75ab65f
    {get-nsxedge edge01 | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -Learner bgp -FromStatic -confirm:$false},
    {$uplinklif = New-NsxLogicalRouterInterfaceSpec -Name Uplink -Type uplink -ConnectedTo (Get-NsxLogicalSwitch transitls) -PrimaryAddress 172.16.100.2 -SubnetPrefixLength 29},
    {$weblif = New-NsxLogicalRouterInterfaceSpec -Name web -Type internal -ConnectedTo (Get-NsxLogicalSwitch webls) -PrimaryAddress 172.16.1.1 -SubnetPrefixLength 24},
    {$applif = New-NsxLogicalRouterInterfaceSpec -Name app -Type internal -ConnectedTo (Get-NsxLogicalSwitch appls) -PrimaryAddress 172.16.2.1 -SubnetPrefixLength 24},
    {$dblif = New-NsxLogicalRouterInterfaceSpec -Name db -Type internal -ConnectedTo (Get-NsxLogicalSwitch dbls) -PrimaryAddress 172.16.3.1 -SubnetPrefixLength 24},
    {New-NsxLogicalRouter -Name LogicalRouter01 -ManagementPortGroup (Get-VDPortgroup internal) -Interface $uplinklif,$weblif,$applif,$dblif -Cluster (get-cluster mgmt01) -Datastore (get-datastore mgmtdata)},
    {get-nsxlogicalrouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgp -ProtocolAddress 172.16.100.3 -ForwardingAddress 172.16.100.2 -LocalAS 200 -RouterId 172.16.100.3 -confirm:$false},
    {get-nsxlogicalrouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBgpRouteRedistribution -confirm:$false},
    {Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -FromConnected -Learner bgp -confirm:$false},
    {Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress 172.16.100.1 -RemoteAS 100 -ForwardingAddress 172.16.100.2 -ProtocolAddress 172.16.100.3 -confirm:$false}
)


function ShowTheAwesome { 

    foreach ( $step in $steps ) { 

        #Show me first
        write-host -foregroundcolor yellow ">>> $step"

        write-host "Press a key to run the command..."
        #wait for a keypress to continue
        $junk = [console]::ReadKey($true)

        #execute (dot source) me in global scope
        . $step
    }
}