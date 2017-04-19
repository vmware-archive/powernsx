#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Environment" -Tags "Environment" {

    it "Establishes a default PowerNSX Connection" {
        # Using VI based SSO connection now.
        $global:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
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

    It "Has a single local TransportZone" {
        $Tz = Get-NsxTransportZone | ? { $_.isUniversal -eq 'false'}
        $tz | should not be $null
        ($tz | measure).count | should be 1
    }

    It "Has a single global TransportZone" {
        $Tz = Get-NsxTransportZone | ? { $_.isUniversal -eq 'true'}
        $tz | should not be $null
        ($tz | measure).count | should be 1
    }
    it "Destroys default NSX connection" {
        disconnect-nsxserver
        $DefaultNsxServer | should be $null
    }

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
        import-module $pnsxmodule
    }
}