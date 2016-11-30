#We have to do this to ensure we are testing the right module.  We load the module in the BeforeAll section
get-module PowerNSX | remove-module

#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestNSXManager ) { 
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
} 

Describe "Logical Thingy" { 

    BeforeAll { 

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
       
        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:Conn = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -VICred $PNSXTestDefViCred -ViWarningAction "Ignore" -DefaultConnection:$false -VIDefaultConnection:$false
        $script:cl = get-cluster | select -first 1
        write-warning "Using cluster $cl for clustery stuff"
        $script:ds = $cl | get-datastore | select -first 1
        write-warning "Using datastore $ds for datastorey stuff"

        #Put any script scope variables you need to reference in your tests.  
        #For naming items that will be created in NSX, use a unique prefix 
        #pester_<testabbreviation>_<objecttype><uid>.  example: 
        $script:mynsxthing = "pester_lt_thing1"
    }

    it "Can do something" { 

        #do something and then make an assertion about what it should be
        $thing = new-nsxthingy $mynsxthing

        #remember to get from api rather than use returned val - this test successful creation, not just return
        get-nsxthingy $mynsxthing | should not be $null

        #can make multiple assertions to improve test value.
        $thing.ears | should be pointy
    }

    AfterAll { 
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.

        disconnect-nsxserver 
        Remove-Variable -scope global -name "conn"
    }
}