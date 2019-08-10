#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Environment" -Tags "Environment" {

    Context "Base Environment Checks" {
        it "Establishes a default PowerNSX Connection" {
            # Using VI based SSO connection now.
            $global:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        }

        it "Can find a VI cluster to deploy to" {
            $global:cl = get-cluster | Select-Object -first 1
            $cl | should not be $null
            ($cl | get-vmhost | Where-Object { $_.ConnectionState -eq 'Connected'} | Measure-Object).count | should BeGreaterThan 0
            write-warning "Subsequent tests that deploy appliances will use cluster $cl"
        }

        it "Can find a VI Datastore to deploy to" {
            $global:ds = $cl | get-datastore | Select-Object -first 1
            $ds | should not be $null
            $ds.FreeSpaceGB | should BeGreaterThan 1
            write-warning "Subsequent tests that deploy appliances will use datastore $ds"
        }

        it "Has a running controller"{
            $controllers = Get-NSxController
            $controllers | should not be $null
            $controllers.status -contains 'RUNNING' | should be $true
            ($controllers.status | sort-object -Unique | Measure-Object).count | should be 1
        }

        It "Has all clusters in healthy state" {
            $status = $cl | Get-NsxClusterStatus
            $status.status -contains 'GREEN' | should be $true
            $status.status -contains 'RED' | should be $false
            # $status.status -contains 'YELLOW' | should be $false
            # $status.status -contains 'UNKNOWN' | should be $false

        }
    }

    Context "Partial test run object cleanup" {

        BeforeAll {
            #cleanup any left over test objects...
            #Edges
            Get-NsxEdge | Where-Object { $_.name -match 'pester'} | Remove-NsxEdge -confirm:$false
            #DLRs
            Get-NsxLogicalRouter | Where-Object { $_.name -match 'pester'} | Remove-NsxLogicalRouter -confirm:$false
            #ensure dlr/edge is gone properly!
            start-sleep -Seconds 5
            #vAPPs
            Get-vApp pester* | Remove-vAPP -confirm:$false -DeletePermanently
            #VMs
            Get-Vm pester* | Remove-VM -Confirm:$false -DeletePermanently
            #FirewallRules
            Get-NsxFirewallSection | Where-Object { $_.name -match 'pester'} | Remove-NsxFirewallSection -Confirm:$false -force
            #Policies
            Get-NsxSecurityPolicy | Where-Object { $_.name -match 'pester'} | Remove-NsxSecurityPolicy -Confirm:$false
            #LogicalSwitches
            Get-NsxLogicalSwitch | Where-Object { $_.name -match 'pester'} | Remove-NsxLogicalSwitch -Confirm:$false
            #SecurityGroup
            Get-NsxSecurityGroup | Where-Object { $_.name -match 'pester'} | Remove-NsxSecurityGroup -confirm:$false
            #IpSets
            Get-NsxIpSet | Where-Object { $_.name -match 'pester'} | Remove-NsxIpSet -confirm:$false
            #Pools
            Get-NsxIpPool | Where-Object { $_.name -match 'pester'} | Remove-NsxIpPool -Confirm:$false
            #Controllers (2/3)

            #MacSets
            Get-NsxMacSet | Where-Object { $_.name -match 'pester'} | Remove-NsxMacSet -confirm:$false
            #ServiceGroups
            Get-NsxServiceGroup | Where-Object { $_.name -match 'pester'} | Remove-NsxServicegroup -Confirm:$false
            #Services
            Get-NsxService | Where-Object { $_.name -match 'pester'} | Remove-NsxService -Confirm:$false
            #SecurityTags
            Get-NsxSecurityTag | Where-Object { $_.name -match 'pester'} | Remove-NsxSecurityTag -Confirm:$false
            #LogicalSwitches
            Get-NsxLogicalSwitch | Where-Object { $_.name -match 'pester'} | Remove-NsxLogicalSwitch -Confirm:$false
            #PortGroups
            Get-vdportGroup pester* | Remove-VDPortGroup -Confirm:$false
            #TransportZones
            Get-NsxTransportZone | Where-Object { $_.name -match 'pester'} | Remove-NsxTransportZone -confirm:$false
            #Datacenters
            Get-Datacenter pester* | remove-datacenter -Confirm:$false
            #Resource Pools
            Get-ResourcePool pester* | remove-resourcepool -Confirm:$false

        }

        It "Has a single local TransportZone" {
            $Tz = Get-NsxTransportZone | Where-Object { $_.isUniversal -eq 'false'}
            $tz | should not be $null
            ($tz | Measure-Object).count | should be 1
        }

        It "Has a single local SegmentID range defined" {
            $Segment = Get-NsxSegmentIdRange -LocalOnly
            $Segment.isUniversal  | should be "false"
            $Segment | should not be $null
            ($Segment | Measure-Object).count | should be 1
        }

        It "Has a single universal TransportZone" {
            $Tz = Get-NsxTransportZone | Where-Object { $_.isUniversal -eq 'true'}
            $tz | should not be $null
            ($tz | Measure-Object).count | should be 1
        }

        It "Has a single universal SegmentID range defined" {
            $Segment = Get-NsxSegmentIdRange -UniversalOnly
            $Segment.isUniversal  | should be "true"
            $Segment | should not be $null
            ($Segment | Measure-Object).count | should be 1
        }

        it "Destroys default NSX connection" {
            disconnect-nsxserver
            $DefaultNsxServer | should be $null
        }
    }

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
        import-module $pnsxmodule
    }
}
