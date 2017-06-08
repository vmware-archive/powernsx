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
        # Prefix to use for different variables.
        $script:tzPrefix = "pester_tz"
        $script:lsPrefix = "pester_ls"
        $script:ls1_name = "$lsPrefix-ls1"
        $script:ls2_name = "$lsPrefix-ls2"
        $script:tz2_name = "$tzPrefix-tz2"
        $script:tz = Get-NsxTransportZone -LocalOnly | select -first 1
        $script:tz2 = New-NsxTransportZone -Name $tz2_name -cluster (get-cluster | select -first 1) -ControlPlaneMode UNICAST_MODE

        $emptycl = ($tz).clusters.cluster.cluster.name | % {get-cluster $_ } | ? { ($_ | get-vm | measure).count -eq 0 }
        if ( -not $emptycl ) {
            write-warning "No cluster that is a member of an NSX TransportZone but not hosting any VMs could be found for Transport Zone membership addition/removal tests."
            $script:SkipTzMember = $True
        }
        else {
            $script:cl = $emptycl | select -First 1
            $script:SkipTzMember = $False
            write-warning "Using $($tz.Name) and cluster $cl for transportzone membership test"
        }
    }

    AfterAll {

        Get-NsxTransportZone | ? {$_.name -match $tzPrefix } | remove-NsxTransportZone -confirm:$false

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        disconnect-nsxserver
    }

    AfterEach {
        # Cleanup Testing Logical Switches
        Get-NsxTransportZone | Get-NsxLogicalSwitch | ? {$_.name -match $lsPrefix} | Remove-NsxLogicalSwitch -confirm:$false

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
        Get-NsxTransportZone -LocalOnly | select -first 1 | new-nsxlogicalswitch $ls1_name
        get-nsxlogicalswitch $ls1_name | Remove-NsxLogicalSwitch -Confirm:$false
        get-nsxlogicalswitch $ls1_name | should be $null
    }

     it "Can retrive logical switches from a specific transport zone via pipeline" {
        $ls1 = $tz | new-nsxlogicalswitch $ls1_name
        $ls2 = $tz2 | New-NsxLogicalSwitch $ls2_name
        $ls = $tz2 | Get-NsxLogicalSwitch
        $ls | should not be $null
        @($ls).count | should be 1
        $ls.name | should be $ls2_name
    }

    it "Can retrive logical switches from a specific transport zone via vdnscope parameter" {
        $ls1 = $tz | new-nsxlogicalswitch $ls1_name
        $ls2 = $tz2 | New-NsxLogicalSwitch $ls2_name
        $ls = Get-NsxLogicalSwitch -vdnscope $tz2
        $ls | should not be $null
        @($ls).count | should be 1
        $ls.name | should be $ls2_name
    }

    Context "Transport Zones" {

        AfterEach {
            if ( -not $SkipTzMember ) {
                $CurrentTz = Get-NsxTransportZone -objectid $tz.objectId
                if ( $CurrentTz.Clusters.Cluster.Cluster.objectId -notcontains $cl.ExtensionData.MoRef.Value ) {
                    #Cluster has been removed, and needs to be readded...
                    $CurrentTz | Add-NsxTransportZoneMember -Cluster $cl
                }
            }
        }

        Context "Transport Zone Cluster Removal" {

            it "Can remove a transportzone cluster" -skip:$SkipTzMember {
                $tz | Remove-NsxTransportZoneMember -Cluster $cl
                $updatedtz = Get-NsxTransportZone -objectId $tz.objectId
                $updatedtz.clusters.cluster.cluster.name -contains $cl.name | should be $false
            }
        }

        Context "Transport Zone Cluster Addition" {
            BeforeEach {
                if ( -not $SkipTzMember ) {
                    $CurrentTz = Get-NsxTransportZone -objectid $tz.objectId
                    if ( $CurrentTz.Clusters.Cluster.Cluster.objectId -contains $cl.ExtensionData.MoRef.Value ) {
                        #Cluster has been added, and needs to be removed...
                        $CurrentTz | Remove-NsxTransportZoneMember -Cluster $cl
                    }
                }
            }

            it "Can add a transportzone cluster" -skip:$SkipTzMember {
                $tz | Add-NsxTransportZoneMember -Cluster $cl
                $updatedtz = Get-NsxTransportZone -objectId $tz.objectId
                $updatedtz.clusters.cluster.cluster.name -contains $cl.name | should be $true
            }
        }
    }
}

