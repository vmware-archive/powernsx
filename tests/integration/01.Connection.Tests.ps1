#We have to do this to ensure we are testing the right module.  We load the module in the BeforeAll section
get-module PowerNSX | remove-module

#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestNSXManager ) { 
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
} 

Describe "PowerNSX Connection" { 

     it "Establishes a default connection to NSX Manager" {
        $global:DefaultNsxConnection = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore"
    }

    it "Establishes a nondefault connection to NSX Manager" {
        $global:Conn = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore" -DefaultConnection:$false -VIDefaultConnection:$false
    }

    it "Can find a VI cluster to deploy to" { 
        $global:cl = get-cluster | select -first 1
        $cl | should not be $null
        write-warning "Using cluster $cl"
    }

    it "Can find a VI Datastore to deploy to" { 
        $global:ds = $cl | get-datastore | select -first 1
        $ds | should not be $null
        write-warning "Using datastore $ds"
    }

    it "Destroys default NSX connection" { 
        disconnect-nsxserver 
        $DefaultNsxServer | should be $null
    }

    it "Destroys non default connection" { 
        Remove-Variable -scope global -name "conn"
        $conn | should be $null
    }

    BeforeAll { 

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
        import-module $pnsxmodule
    }
}