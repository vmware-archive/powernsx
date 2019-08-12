#PowerNSX Test template.
#Nick Bradford : nbradford@vmware.com

#Because PowerNSX is an API consumption tool, its test framework is limited to
#exercising cmdlet functionality against a functional NSX and vSphere API
#If you disagree with this approach - feel free to start writing mocks for all
#potential API reponses... :)

#In the meantime, the test format is not as elegant as normal TDD, but Ive made some effort to get close to this.
#Each functional area in NSX should have a separate test file.

#Try to group related tests in contexts.  Especially ones that rely on configuration done in previous tests
#Try to make tests as standalone as possible, but generally round trips to the API are expensive, so bear in mind
#the time spent recreating configuration created in previous tests just for the sake of keeping test isolation.

#Try to put all non test related setup and tear down in the BeforeAll and AfterAll sections.  ]
#If a failure in here occurs, the Describe block is not executed.

#########################
#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Edge Load Balancer" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:cl = get-cluster | Select-Object -first 1
        write-warning "Using cluster $cl for clustery stuff"
        $script:ds = $cl | get-datastore | Select-Object -first 1
        write-warning "Using datastore $ds for datastorey stuff"

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:lbedge1name = "pester-lb-edge1"
        $script:lbedge1ipuplink = "1.1.1.1"
        $script:password = "VMware1!VMware1!"
        $script:lbuplinklsname = "pester_lb_uplink_ls"
        $script:lbinternallsname = "pester_lb_internal_ls"

        #Create Logical Switch
        $script:lbuplinkls = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $lbuplinklsname
        $script:lbinternalls = Get-NsxTransportZone -LocalOnly | Select-Object -first 1 | New-NsxLogicalSwitch $lbinternallsname

        #Create Edge Interface
        $vnic0 = New-NsxEdgeInterfaceSpec -index 0 -Type uplink -Name "vNic0" -ConnectedTo $lbuplinkls -PrimaryAddress $lbedge1ipuplink -SubnetPrefixLength 24

        #Create Edge
        $script:lbEdge = New-NsxEdge -Name $lbedge1name -Interface $vnic0 -Cluster $cl -Datastore $ds -password $password -enablessh -hostname $lbedge1name

        #Get default monitor.
        $script:monitor =  get-nsxedge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor -Name default_http_monitor

    }
    Context "Load Balancer Pool" {

        it "Add LB Pool (via New-NsxLoadBalancerMemberSpec)" {
            #Add 2 server on LB Pool
            $vmmember1 = New-NsxLoadBalancerMemberSpec -name "VM01" -IpAddress 2.2.2.1 -Port 80
            $vmmember2 = New-NsxLoadBalancerMemberSpec -name "VM02" -IpAddress 2.2.2.2 -Port 80
            #Add Pool to LB
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name pester_lb_pool1 -Description "Pester LB Pool 1" -Transparent:$false -Algorithm round-robin -Memberspec $vmmember1, $vmmember2 -Monitor $Monitor
            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool1
            $lb_pool.name | Should be "pester_lb_pool1"
            $lb_pool.description | Should be "Pester LB Pool 1"
            $lb_pool.algorithm | Should be "round-robin"
            $lb_pool.transparent | Should be "false"
            $lb_pool.member[0].name | Should be "VM01"
            $lb_pool.member[1].name | Should be "VM02"
        }

        it "Configure LB Pool" {
            #Configure Pool to LB
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool -name pester_lb_pool1 | Set-NsxLoadBalancerPool -name pester_lb_pool3 -Description "Pester LB Pool 3" -Transparent:$true -Algorithm ip-hash
            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool3
            $lb_pool.name | Should be "pester_lb_pool3"
            $lb_pool.description | Should be "Pester LB Pool 3"
            $lb_pool.algorithm | Should be "ip-hash"
            $lb_pool.transparent | Should be "true"
        }
        it "Add LB Pool (via Add-NsxLoadBalancerPoolMember)" {
            #Create LB Pool
            $Pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name pester_lb_pool2 -Description "Pester LB Pool 2" -Transparent:$true -Algorithm ip-hash -Monitor $Monitor

            # ... And now add the pool members
            $pool = $pool | Add-NsxLoadBalancerPoolMember -name "VM03" -IpAddress 2.2.2.3 -Port 80
            $pool = $pool | Add-NsxLoadBalancerPoolMember -name "VM04" -IpAddress 2.2.2.4 -Port 80

            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2
            $lb_pool.name | Should be "pester_lb_pool2"
            $lb_pool.description | Should be "Pester LB Pool 2"
            $lb_pool.algorithm | Should be "ip-hash"
            $lb_pool.transparent | Should be "true"
            $lb_pool.member[0].name | Should be "VM03"
            $lb_pool.member[1].name | Should be "VM04"
        }

        it "Remove LB Pool " {
            #Remove LB Pool
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool -name pester_lb_pool1 |  Remove-NsxLoadBalancerPool -confirm:$false
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool -name pester_lb_pool2 |  Remove-NsxLoadBalancerPool -confirm:$false

            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool
            $lb_pool | should be $null
        }

        AfterAll {
            #Remove All LB Pool
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool | Remove-NsxLoadBalancerPool -confirm:$false

        }
    }

    Context "Load Balancer App Profile" {

        it "Add LB AppProfile" {
            #Create LB App Profile
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationProfile -Name pester_lb_app_profile -Type http

            $lb_app_profile = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerApplicationProfile -Name pester_lb_app_profile
            $lb_app_profile.name | Should be "pester_lb_app_profile"
            $lb_app_profile.template | Should be "http"
            $lb_app_profile.insertXForwardedFor | Should be "false"
            $lb_app_profile.sslPassthrough | should be "false"
        }

        AfterAll {
            #Remove All LB App Profile
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerApplicationProfile | Remove-NsxLoadBalancerApplicationProfile -confirm:$false

        }
    }
    Context "Load Balancer" {

        it "Enable Load Balancer" {
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Set-NsxLoadBalancer -Enabled
            $lb = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer
            $lb.enabled | Should be $true
        }



        it "Add LB VIP" {
            #Create LB Pool
            $pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name pester_lb_pool2 -Description "Pester LB Pool 2" -Transparent:$true -Algorithm ip-hash -Monitor $Monitor

            # ... And now add the pool members
            $pool = $pool | Add-NsxLoadBalancerPoolMember -name "VM03" -IpAddress 2.2.2.3 -Port 80
            $pool = $pool | Add-NsxLoadBalancerPoolMember -name "VM04" -IpAddress 2.2.2.4 -Port 80

            #Create LB App Profile
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationProfile -Name pester_lb_app_profile -Type http

            #Finally add VIP
            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2
            $lb_app_profile = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerApplicationProfile -Name pester_lb_app_profile
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Add-NsxLoadBalancerVip -name "pester_vip" -Description "Pester VIP" -ipaddress 1.1.1.1 -Protocol http -Port 80 -ApplicationProfile $lb_app_profile -DefaultPool $lb_pool -AccelerationEnable

            $lb_vip = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerVIP pester_vip
            $lb_vip.name | Should be "pester_vip"
            $lb_vip.description | Should be "Pester VIP"
            $lb_vip.enabled | Should be "true"
            $lb_vip.ipaddress | should be "1.1.1.1"
            $lb_vip.port | Should be "80"
            $lb_vip.enableServiceInsertion | Should be "false"
            $lb_vip.accelerationEnabled | Should be "true"

        }
    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxedge $lbedge1name | remove-nsxedge -confirm:$false
        start-sleep 5

        Get-NsxLogicalSwitch $lbuplinklsname | Remove-NsxLogicalSwitch -Confirm:$false
        Get-NsxLogicalSwitch $lbinternallsname | Remove-NsxLogicalSwitch -Confirm:$false

        disconnect-nsxserver
    }
}
