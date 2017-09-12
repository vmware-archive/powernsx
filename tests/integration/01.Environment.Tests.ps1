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
            $global:cl = get-cluster | select -first 1
            $cl | should not be $null
            ($cl | get-vmhost | ? { $_.ConnectionState -eq 'Connected'} | measure).count | should BeGreaterThan 0
            write-warning "Subsequent tests that deploy appliances will use cluster $cl"
        }

        it "Can find a VI Datastore to deploy to" {
            $global:ds = $cl | get-datastore | select -first 1
            $ds | should not be $null
            $ds.FreeSpaceGB | should BeGreaterThan 1
            write-warning "Subsequent tests that deploy appliances will use datastore $ds"
        }

        it "Has a running controller"{
            $controllers = Get-NSxController
            $controllers | should not be $null
            $controllers.status -contains 'RUNNING' | should be $true
            ($controllers.status | sort-object -Unique | measure).count | should be 1
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
            #vAPPs
            Get-vApp pester* | Remove-vAPP -confirm:$false -DeletePermanently
            #VMs
            Get-Vm pester* | Remove-VM -Confirm:$false -DeletePermanently
            #Edges
            Get-NsxEdge | ? { $_.name -match 'pester'} | Remove-NsxEdge -confirm:$false
            #DLRs
            Get-NsxLogicalRouter | ? { $_.name -match 'pester'} | Remove-NsxLogicalRouter -confirm:$false
            #FirewallRules
            Get-NsxFirewallSection | ? { $_.name -match 'pester'} | Remove-NsxFirewallSection -Confirm:$false -force
            #Policies
            Get-NsxSecurityPolicy | ? { $_.name -match 'pester'} | Remove-NsxSecurityPolicy -Confirm:$false
            #LogicalSwitches
            Get-NsxLogicalSwitch | ? { $_.name -match 'pester'} | Remove-NsxLogicalSwitch -Confirm:$false
            #SecurityGroup
            Get-NsxSecurityGroup | ? { $_.name -match 'pester'} | Remove-NsxSecurityGroup -confirm:$false
            #IpSets
            Get-NsxIpSet | ? { $_.name -match 'pester'} | Remove-NsxIpSet -confirm:$false
            #Pools
            Get-NsxIpPool | ? { $_.name -match 'pester'} | Remove-NsxIpPool -Confirm:$false
            #Controllers (2/3)
            
            #MacSets
            Get-NsxMacSet | ? { $_.name -match 'pester'} | Remove-NsxMacSet -confirm:$false
            #ServiceGroups
            Get-NsxServiceGroup | ? { $_.name -match 'pester'} | Remove-NsxServicegroup -Confirm:$false
            #Services
            Get-NsxService | ? { $_.name -match 'pester'} | Remove-NsxService -Confirm:$false
            #SecurityTags
            Get-NsxSecurityTag | ? { $_.name -match 'pester'} | Remove-NsxSecurityTag -Confirm:$false
            #ensure dlr/edge is gone properly!
            start-sleep -Seconds 5

            #LogicalSwitches
            Get-NsxLogicalSwitch | ? { $_.name -match 'pester'} | Remove-NsxLogicalSwitch -Confirm:$false
            #PortGroups
            Get-vdportGroup pester* | Remove-VDPortGroup -Confirm:$false
            #TransportZones
            Get-NsxTransportZone | ? { $_.name -match 'pester'} | Remove-NsxTransportZone -confirm:$false

        }

        It "Has a single local TransportZone" {
            $Tz = Get-NsxTransportZone | ? { $_.isUniversal -eq 'false'}
            $tz | should not be $null
            ($tz | measure).count | should be 1
        }

        It "Has a single local SegmentID range defined" {
            $Segment = Get-NsxSegmentIdRange -LocalOnly
            $Segment.isUniversal  | should be "false"
            $Segment | should not be $null
            ($Segment | measure).count | should be 1
        }

        It "Has a single universal TransportZone" {
            $Tz = Get-NsxTransportZone | ? { $_.isUniversal -eq 'true'}
            $tz | should not be $null
            ($tz | measure).count | should be 1
        }

        It "Has a single universal SegmentID range defined" {
            $Segment = Get-NsxSegmentIdRange -UniversalOnly
            $Segment.isUniversal  | should be "true"
            $Segment | should not be $null
            ($Segment | measure).count | should be 1
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