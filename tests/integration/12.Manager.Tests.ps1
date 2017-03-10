#PowerNSX Manager cmdlet tests.
#Nick Bradford : nbradford@vmware.com

#########################
#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestNSXManager ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "NSXManager" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -Server $PNSXTestNSXManager -Credential $PNSXTestDefMgrCred -DisableVIAutoConnect


        #Put any script scope variables you need to reference in your tests.
        #For naming items that will be created in NSX, use a unique prefix
        #pester_<testabbreviation>_<objecttype><uid>.  example:
        $script:NTPServer1 = "1.1.1.1"
        $script:NTPServer2 = "2.2.2.2"
        $Script:TimeZone = "Australia/Melbourne"

        #Try to preserve existing state...
        $Script:PreExistingConfig = Get-NsxManagerTimeSettings
    }

    Context "Time" {

        #Group related tests together.

        it "Can get existing time configuration" {

            $TimeConfig = Get-NsxManagerTimeSettings
            $TimeConfig.datetime | should not be $null

            #Not 100% on this, but I think tz always exists, and defaults to UTC.
            $TimeConfig.timezone | should not be $null

        }

        it "Can get configured SSL Certificates" {
            $certificates = Get-NsxManagerCertificate
            $( $certificates | measure ).count | should BeGreaterThan 0 
            $certificates | should not be $null
        }

        it "Can clear existing NTP configuration" {
            $TimeConfig = Clear-NsxManagerTimeSettings
            $TimeConfig | should be $null
            $GetTimeConfig = Get-NsxManagerTimeSettings
            $GetTimeConfig.NtpServer | should be $null
        }

        it "Can configure NTP servers" {
            $TimeConfig = Set-NsxManagerTimeSettings -NtpServer $NTPServer1, $NTPServer2
            $TimeConfig.ntpserver | should not be $null
            $GetTimeConfig = Get-NsxManagerTimeSettings
            $GetTimeConfig.ntpserver.string -contains $NTPServer1 | should be $true
            $GetTimeConfig.ntpserver.string -contains $NTPServer2 | should be $true
        }

        it "Can configure timezone configuration" {
            $TimeConfig = Set-NsxManagerTimeSettings -TimeZone $TimeZone
            $TimeConfig.timezone | should be $Timezone
            $GetTimeConfig = Get-NsxManagerTimeSettings
            $TimeConfig.timezone | should be $Timezone
        }
    }


    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        if ($PreExistingConfig.ntpserver.string) {
            Clear-NsxManagerTimeSettings
            Set-NsxManagerTimeSettings -NtpServer $PreExistingConfig.ntpserver.string
        }
        Set-NsxManagerTimeSettings -TimeZone $PreExistingConfig.timezone

        disconnect-nsxserver
    }
}