#We have to do this to ensure we are testing the right module.  We load the module in the BeforeAll section
get-module PowerNSX | remove-module

#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestNSXManager ) { 
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
} 

Describe "PowerNSX Module" { 

    it "The module loads" {
        import-module $pnsxmodule
    }
}