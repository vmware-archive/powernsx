#PowerNSX Service Tests.
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

Describe "Services" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred

        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:svcPrefix = "pester_svc_"

        #Clean up any existing services from previous runs...
        get-nsxservice | ? { $_.name -match $svcPrefix } | remove-nsxservice -confirm:$false

        #Define valid services to align with PowerNSX
        $Script:AllValidServices = @("AARP", "AH", "ARPATALK", "ATMFATE", "ATMMPOA",
                    "BPQ", "CUST", "DEC", "DIAG", "DNA_DL", "DNA_RC", "DNA_RT", "ESP",
                    "FR_ARP", "FTP", "GRE", "ICMP", "IEEE_802_1Q", "IGMP", "IPCOMP",
                    "IPV4", "IPV6", "IPV6FRAG", "IPV6ICMP", "IPV6NONXT", "IPV6OPTS",
                    "IPV6ROUTE", "IPX", "L2_OTHERS", "L2TP", "L3_OTHERS", "LAT", "LLC",
                    "LOOP", "MS_RPC_TCP", "MS_RPC_UDP", "NBDG_BROADCAST",
                    "NBNS_BROADCAST", "NETBEUI", "ORACLE_TNS", "PPP", "PPP_DISC",
                    "PPP_SES", "RARP", "RAW_FR", "RSVP", "SCA", "SCTP", "SUN_RPC_TCP",
                    "SUN_RPC_UDP", "TCP", "UDP", "X25")

        $Script:AllServicesRequiringPort = @( "FTP", "L2_OTHERS", "L3_OTHERS",
        "MS_RPC_TCP", "MS_RPC_UDP", "NBDG_BROADCAST", "NBNS_BROADCAST", "ORACLE_TNS",
        "SUN_RPC_TCP", "SUN_RPC_UDP" )

        $script:AllServicesNotRequiringPort = $Script:AllValidServices | ? { $AllServicesRequiringPort -notcontains $_ }

        $Script:AllValidIcmpTypes = @("echo-reply", "destination-unreachable",
            "source-quench", "redirect", "echo-request", "time-exceeded",
            "parameter-problem", "timestamp-request", "timestamp-reply",
            "address-mask-request", "address-mask-reply"
        )

    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        get-nsxservice | ? { $_.name -match $svcPrefix } | remove-nsxservice -confirm:$false

        disconnect-nsxserver
    }

    Context "Service retrieval" {
        BeforeAll {
            $script:svcName = "$svcPrefix-get"
            $svcDesc = "PowerNSX Pester Test get service"
            $svcPort = 1234
            $svcProto = "TCP"
            $script:get = New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto -port $svcPort

        }

        it "Can retreive a service by name" {
            {Get-NsxService -Name $svcName} | should not throw
            $svc = Get-NsxService -Name $svcName
            $svc | should not be $null
            $svc.name | should be $svcName

         }

        it "Can retreive a service by id" {
            {Get-NsxService -objectId $get.objectId } | should not throw
            $svc = Get-NsxService -objectId $get.objectId
            $svc | should not be $null
            $svc.objectId | should be $get.objectId
         }


    }

    Context "Successful Service Creation" {

        AfterAll {
            get-nsxservice | ? { $_.name -match $svcPrefix } | remove-nsxservice -confirm:$false
        }

        foreach ( $svc in ($AllServicesRequiringPort | ? {"ICMP", "L2_OTHERS", "L3_OTHERS" -notcontains $_ } ) ) {
            it "Can create $svc service with port" {
                $svcName = "$svcPrefix-$svc-1234"
                $svcDesc = "PowerNSX Pester Test $svc service"
                $svcPort = 1234
                $svcProto = $Svc
                $svc = New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto -port $svcPort
                $svc.Name | Should be $svcName
                $svc.Description | should be $svcDesc
                $svc.element.value | should be $svcPort
                $svc.element.applicationProtocol | should be $svcProto
                $get = Get-NsxService -Name $svcName
                $get.name | should be $svc.name
                $get.description | should be $svc.description
                $get.element.value | should be $svc.element.value
                $get.element.protocol | should be $svc.element.protocol

            }
        }

        it "Can create an ICMP-all service" {

            $svcName = "$svcPrefix-icmp-all"
            $svcDesc = "PowerNSX Pester Test ICMP-all service"
            $svcProto = "ICMP"
            $svc = New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto
            $svc.Name | Should be $svcName
            $svc.Description | should be $svcDesc
            $svc.element.applicationProtocol | should be $svcProto
            $get = Get-NsxService -Name $svcName
            $get.name | should be $svc.name
            $get.description | should be $svc.description
            $get.element.protocol | should be $svc.element.protocol

        }

        foreach ( $icmptype in $AllValidICMPTypes ) {
            it "Can create an ICMP-$icmptype service" {

                $svcName = "$svcPrefix-icmp-$icmptype"
                $svcDesc = "PowerNSX Pester Test ICMP-$icmptype service"
                $svcProto = "ICMP"
                $svc = New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto -port $icmptype
                $svc.Name | Should be $svcName
                $svc.Description | should be $svcDesc
                $svc.element.applicationProtocol | should be $svcProto
                $get = Get-NsxService -Name $svcName
                $get.name | should be $svc.name
                $get.description | should be $svc.description
                $get.element.protocol | should be $svc.element.protocol

            }
        }

        it "Can create a service and return an objectId only" {
            $svcName = "$svcPrefix-objonly-1234"
            $svcDesc = "PowerNSX Pester Test objectidonly service"
            $svcPort = 1234
            $svcProto = "TCP"
            $id = New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto -port $svcPort -ReturnObjectIdOnly
            $id | should BeOfType System.String
            $id | should match "^application-\d*$"

         }

         it "Can create a service using a lowercase servicename" {
            $svcName = "$svcPrefix-lowercase-1234"
            $svcDesc = "PowerNSX Pester Test lowercase service"
            $svcPort = 1234
            $svcProto = "tcp"
            $id = New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto -port $svcPort -ReturnObjectIdOnly
            $id | should BeOfType System.String
            $id | should match "^application-\d*$"

         }
    }

    Context "Unsuccessful Service Creation" {

        BeforeAll {
            get-nsxservice | ? { $_.name -match $svcPrefix } | remove-nsxservice -confirm:$false
        }

        it "Fails to create a service with an invalid protocol" {

            $svcName = "$svcPrefix-invalid"
            $svcDesc = "PowerNSX Pester Test Invalid service"
            $svcProto = "bob"
            {New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto} | should throw
        }

        foreach ( $svc in ($AllServicesRequiringPort)) {
            it "Fails to create $svc service with no port number" {

                $svcName = "$svcPrefix-invalid"
                $svcDesc = "PowerNSX Pester Test Invalid service"
                $svcProto = $svc
                {New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto} | should throw
            }
        }

        foreach ( $svc in $AllServicesRequiringPort ) {
            it "Fails to create a $svc service with an invalid port number" {

                $svcName = "$svcPrefix-invalid"
                $svcDesc = "PowerNSX Pester Test Invalid service"
                $svcProto = $svc
                {New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto -port 70000 } | should throw
            }
        }

        foreach ( $svc in $AllServicesNotRequiringPort | ? { $_ -notmatch "ICMP|TCP|UDP" }) {
            it "Fails to create a non port defined service - $svc - when specifying a port number" {
                $svcName = "$svcPrefix-invalid"
                $svcDesc = "PowerNSX Pester Test Invalid service"
                $svcProto = $svc
                {New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto -port 1234 } | should throw
            }
        }

        it "Fails to create an ICMP service with invalid icmptype" {

            $svcName = "$svcPrefix-icmp-invalid"
            $svcDesc = "PowerNSX Pester Test ICMP-invalid service"
            $svcProto = "ICMP"
            {New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto -port "invalid"} | should throw
        }

    }

    Context "Service Deletion" {

        BeforeEach {
            $svcName = "$svcPrefix-delete"
            $svcDesc = "PowerNSX Pester Test delete service"
            $svcPort = 1234
            $svcProto = "TCP"
            $script:delete = New-NsxService -Name $svcName -Description $svcDesc -Protocol $svcProto -port $svcPort

        }

        it "Can delete a service by object" {

            $delete | Remove-NsxService -confirm:$false
            {Get-NsxService -objectId $delete.objectId} | should throw
        }

    }
}