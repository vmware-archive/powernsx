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
        $script:monitor = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor -Name default_http_monitor

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
            #Add LB Pool
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name pester_lb_pool1 -Description "Pester LB Pool 1" -Transparent:$false -Algorithm round-robin -Monitor $Monitor

            #Configure Pool to LB
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool -name pester_lb_pool1 | Set-NsxLoadBalancerPool -name pester_lb_pool2 -Description "Pester LB Pool 2" -Transparent:$true -Algorithm ip-hash
            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2
            $lb_pool.name | Should be "pester_lb_pool2"
            $lb_pool.description | Should be "Pester LB Pool 2"
            $lb_pool.algorithm | Should be "ip-hash"
            $lb_pool.transparent | Should be "true"
        }

        it "Remove LB Pool " {
            #Add LB Pool
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name pester_lb_pool1 -Description "Pester LB Pool 1" -Transparent:$false -Algorithm round-robin -Monitor $Monitor
            #Remove LB Pool
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool -name pester_lb_pool1 | Remove-NsxLoadBalancerPool -confirm:$false

            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool
            $lb_pool | should be $null
        }

        AfterEach {
            #Remove All LB Pool
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool | Remove-NsxLoadBalancerPool -confirm:$false
        }

    }

    Context 'Load Balancer Pool Member' {
        BeforeAll {
            #Create LB Pool
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name pester_lb_pool2 -Description "Pester LB Pool 2" -Transparent:$true -Algorithm ip-hash -Monitor $Monitor
        }

        it "Add (First) LB Pool Member (via Add-NsxLoadBalancerPoolMember)" {

            $pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2
            $pool | Add-NsxLoadBalancerPoolMember -name "VM03" -IpAddress 2.2.2.3 -Port 80

            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2

            $lb_pool.name | Should be "pester_lb_pool2"
            $lb_pool.description | Should be "Pester LB Pool 2"
            $lb_pool.algorithm | Should be "ip-hash"
            $lb_pool.transparent | Should be "true"
            $lb_pool_member = $lb_pool | Get-NsxLoadBalancerPoolMember VM03
            $lb_pool_member.name | Should be "VM03"
        }

        it "Add (Second) LB Pool Member (via Add-NsxLoadBalancerPoolMember)" {

            $pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2
            $pool | Add-NsxLoadBalancerPoolMember -name "VM04" -IpAddress 2.2.2.4 -Port 80

            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2
            $lb_pool.name | Should be "pester_lb_pool2"
            $lb_pool.description | Should be "Pester LB Pool 2"
            $lb_pool.algorithm | Should be "ip-hash"
            $lb_pool.transparent | Should be "true"
            $lb_pool_member = $lb_pool | Get-NsxLoadBalancerPoolMember VM03
            $lb_pool_member.name | Should be "VM03"
            $lb_pool_member = $lb_pool | Get-NsxLoadBalancerPoolMember VM04
            $lb_pool_member.name | Should be "VM04"
        }

        it "Remove (Second) LB Pool Member" {

            $pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2
            $pool | Get-NsxLoadBalancerPoolMember -name "VM04" | Remove-NsxLoadBalancerPoolMember -confirm:$false

            $lb_pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2
            $lb_pool.name | Should be "pester_lb_pool2"
            $lb_pool.description | Should be "Pester LB Pool 2"
            $lb_pool.algorithm | Should be "ip-hash"
            $lb_pool.transparent | Should be "true"
            $lb_pool_member = $lb_pool | Get-NsxLoadBalancerPoolMember VM03
            $lb_pool_member.name | Should be "VM03"
            $lb_pool_member = $lb_pool | Get-NsxLoadBalancerPoolMember VM04
            $lb_pool_member.name | Should be $null
        }

        it "Configure LB Pool Member" {

            $pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2
            $pool | Get-NsxLoadBalancerPoolMember -name "VM03" | Set-NsxLoadBalancerPoolMember -confirm:$false -weight 2 -port 81 -state disabled

            $lb_pool_member = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool pester_lb_pool2 | Get-NsxLoadBalancerPoolMember VM03
            $lb_pool_member.name | Should be "VM03"
            $lb_pool_member.ipaddress | Should be "2.2.2.3"
            $lb_pool_member.weight | Should be 2
            $lb_pool_member.port | Should be 81
            $lb_pool_member.condition | Should be "disabled"
        }

        AfterAll {
            #Remove All LB Pool (and LB Pool Member...)
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

        it "Remove LB AppProfile" {
            #Remove LB App Profile
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerApplicationProfile -Name pester_lb_app_profile | Remove-NsxLoadBalancerApplicationProfile -confirm:$false

            $lb_app_profile = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerApplicationProfile -Name pester_lb_app_profile
            $lb_app_profile | Should be $null
        }

        AfterAll {
            #Remove All LB App Profile
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerApplicationProfile | Remove-NsxLoadBalancerApplicationProfile -confirm:$false

        }
    }

    Context "Load Balancer Monitor" {

        it "Add LB Monitor" {
            #Create LB Monitor
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerMonitor -Name pester_lb_monitor -Typehttps -interval 10 -Timeout 10 -maxretries 2 -Method GET -url "api/status" -Expected "200 OK"

            $lb_monitor = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor -Name pester_lb_monitor
            $lb_monitor.name | Should be "pester_lb_monitor"
            $lb_monitor.type | Should be "https"
            $lb_monitor.interval | Should be 10
            $lb_monitor.timeout | Should be 10
            $lb_monitor.maxretries | Should be 2
            $lb_monitor.method | Should be "GET"
            $lb_monitor.url | Should be "api/status"
        }

        it "Remove LB Monitor" {
            #Remove LB Monitor
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor -Name pester_lb_monitor | Remove-NsxLoadBalancerMonitor -confirm:$false

            $lb_monitor = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor -Name pester_lb_monitor
            $lb_monitor | Should be $null
        }

    }
    Context "Load Balancer VIP" {
        BeforeAll {

            #Create LB Pool
            $pool = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerPool -name pester_lb_pool2 -Description "Pester LB Pool 2" -Transparent:$true -Algorithm ip-hash -Monitor $Monitor

            # ... And now add the pool members
            $pool = $pool | Add-NsxLoadBalancerPoolMember -name "VM03" -IpAddress 2.2.2.3 -Port 80
            $pool = $pool | Add-NsxLoadBalancerPoolMember -name "VM04" -IpAddress 2.2.2.4 -Port 80

            #Create LB App Profile
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationProfile -Name pester_lb_app_profile -Type http
        }

        it "Add LB VIP" {

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


        it "Remove LB VIP" {

            $lb_vip = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerVIP pester_vip | Remove-NsxLoadBalancerVIP -confirm:$false
            $lb_vip = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerVIP pester_vip
            $lb_vip.name | Should be $null
        }

        AfterAll {

            #Remove ALL LB VIP
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerVIP | Remove-NsxLoadBalancerVIP -confirm:$false
            #Remove All LB App Profile
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerApplicationProfile | Remove-NsxLoadBalancerApplicationProfile -confirm:$false
            #Remove All LB Pool
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool | Remove-NsxLoadBalancerPool -confirm:$false
        }
    }

    Context "Load Balancer" {

        it "Configure Load Balancer" {
            #by default, LB, Service Insertion, Acceleration, debug (info) is disabled
            $lb = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer
            $lb.enabled | Should be "false"
            $lb.enableServiceInsertion | should be "false"
            $lb.accelerationEnabled | should be "false"
            $lb.logging.logLevel | should be "info"
            $lb.logging.enable | should be "false"
            Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer | Set-NsxLoadBalancer -Enabled -EnableAcceleration -EnableLogging -LogLevel "debug"
            $lb = Get-NsxEdge $lbedge1name | Get-NsxLoadBalancer
            $lb.enabled | Should be "true"
            $lb.enableServiceInsertion | should be "false"
            $lb.accelerationEnabled | should be "true"
            $lb.logging.logLevel | should be "debug"
            $lb.logging.enable | should be "true"
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
