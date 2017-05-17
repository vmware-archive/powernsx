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

        $script:tz2_name = "$tzPrefix-tz2"

        $script:ls1_name = "$lsPrefix-ls1"
        $script:ls2_name = "$lsPrefix-ls2"

        $script:tz2 = New-NsxTransportZone -Name $tz2_name -cluster (get-cluster | select -first 1) -ControlPlaneMode UNICAST_MODE

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
        $ls1 = Get-NsxTransportZone -LocalOnly | select -first 1 | new-nsxlogicalswitch $ls1_name
        $ls2 = Get-NsxTransportZone $tz2 | New-NsxLogicalSwitch $ls2_name
        $ls = Get-NsxTransportZone $tz2_name | Get-NsxLogicalSwitch
        $ls | should not be $null
        @($ls).count | should be 1
        $ls.name | should be $ls2_name
    }

    it "Can retrive logical switches from a specific transport zone via vdnscope parameter" {
        $ls1 = Get-NsxTransportZone -LocalOnly | select -first 1 | new-nsxlogicalswitch $ls1_name
        $ls2 = Get-NsxTransportZone $tz2 | New-NsxLogicalSwitch $ls2_name
        $ls = Get-NsxLogicalSwitch -vdnscope $tz2
        $ls | should not be $null
        @($ls).count | should be 1
        $ls.name | should be $ls2_name
    }

    AfterEach {
        # Cleanup Testing Logical Switches
        Get-NsxTransportZone | Get-NsxLogicalSwitch | ? {$_.name -match $lsPrefix} | Remove-NsxLogicalSwitch -confirm:$false

    }

    AfterAll {

        Get-NsxTransportZone | ? {$_.name -match $tzPrefix } | remove-NsxTransportZone -confirm:$false

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        disconnect-nsxserver
    }
}

