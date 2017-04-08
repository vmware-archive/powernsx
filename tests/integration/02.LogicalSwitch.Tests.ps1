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

    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        disconnect-nsxserver
    }
}

