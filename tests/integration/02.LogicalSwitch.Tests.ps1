#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Logical Switching" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:ls1_name = "pester_ls_ls1"

    }

    it "Can retrieve a transport zone" {
        $tz1 = Get-NsxTransportZone | select -first 1
        $tz1 | should not be $null
    }

    it "Can create a logical switch" {
        Get-NsxTransportZone -LocalOnly | select -first 1 | new-nsxlogicalswitch $ls1_name
        get-nsxlogicalswitch $ls1_name | should not be $null
    }

    it "Can remove a logical switch"{
        get-nsxlogicalswitch $ls1_name | Remove-NsxLogicalSwitch -Confirm:$false
        get-nsxlogicalswitch $ls1_name | should be $null
    }

    Context "Transport Zone Tests" {
        BeforeAll {
            $script:tz = Get-NsxTransportZone | select -first 1
            $emptycl = ($tz).clusters.cluster.cluster.name | % {get-cluster $_ } | ? { ($_ | get-vm | measure).count -eq 0 }
            if ( -not $emptycl ) {
                write-warning "No cluster that is a member of an NSX TransportZone but not hosting any VMs could be found for Transport Zone membership addition/removal tests."
                $script:SkipTzMember = $True
            }
            else {
                $script:cl = $emptycl | select -First 1
                $script:SkipTzMember = $False
                write-warning "Using cluster $cl for transportzone membership test"
            }
        }

        AfterEach {
            if ( -not $SkipTzMember ) {
                $CurrentTz = Get-NsxTransportZone -objectid $tz.objectId
                if ( $CurrentTz.Clusters.Cluster.Cluster.objectId -notcontains $cl.objectId ) {
                    #Cluster has been removed, and needs to be readded...
                    $CurrentTz | Add-NsxTransportZoneMember -Cluster $cl -Wait
                }
            }
        }

        Context "Transport Zone Cluster Addition" {

            it "Can remove a transportzone cluster - async" -skip:$SkipTzMember {
                $result = $tz | Remove-NsxTransportZoneMember -Cluster $cl -wait:$false
                $result | should be $null
                $CurrentTz = Get-NsxTransportZone -objectid $tz.objectId
                $CurrentTz.clusters.cluster.cluster.name -contains $cl.name | should be $false
            }

            it "Can remove a transportzone cluster - synch" -skip:$SkipTzMember {
                $tz | Remove-NsxTransportZoneMember -Cluster $cl
                $updatedtz = Get-NsxTransportZone -objectId $tz.objectId
                $updatedtz.clusters.cluster.cluster.name -contains $cl.name | should be $false
            }
        }

        Context "Transport Zone Cluster Addition" {
            BeforeEach {
                if ( $SkipTzMember ) {
                    $CurrentTz = Get-NsxTransportZone -objectid $tz.objectId
                    if ( $CurrentTz.Clusters.Cluster.Cluster.objectId -contains $cl.objectId ) {
                        #Cluster has been added, and needs to be removed...
                        $CurrentTz | Remove-NsxTransportZoneMember -Cluster $cl -Wait
                    }
                }
            }

            it "Can add a transportzone cluster - async" -skip:$SkipTzMember {
                $result = $tz | Add-NsxTransportZoneMember -Cluster $cl -wait:$false
                $result | should be $null
                $CurrentTz = Get-NsxTransportZone -objectid $tz.objectId
                $CurrentTz.clusters.cluster.cluster.name -contains $cl.name | should be $true

            }

            it "Can add a transportzone cluster - synch" -skip:$SkipTzMember {
                $tz | Add-NsxTransportZoneMember -Cluster $cl
                $updatedtz = Get-NsxTransportZone -objectId $tz.objectId
                $updatedtz.clusters.cluster.cluster.name -contains $cl.name | should be $true
            }
        }

    }

    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        disconnect-nsxserver
    }
}

