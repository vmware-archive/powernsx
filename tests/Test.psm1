#PowerNSX Test Harness Module.
#Sets up test environment and allows for invocation of tests.

#We can drop a connection file that allows future non interactive invocation
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cxnfile = "$here\Test.cxn"

$ynchoices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
$ynchoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
$ynchoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

$there = Split-Path -Parent $MyInvocation.MyCommand.Path | split-path -parent
$sut = "PowerNSX.psd1"
$pnsxmodule = "$there\$sut"

#We import the module here to force all dependant modules to load in the global scope.
#It took a while to work out why module unload wasnt working properly in the test scope.
#This resolves it by allowing PowerNSX dependant module resolution to run in global scope.
Import-Module $pnsxmodule -Global -ErrorAction Stop

function Start-Test {
    #Sets up credentials and performs other stuff before invoking pester
    param ( 
        $testname
    )

    if ( -not (test-path $cxnfile )) { 

        #We allow the user to drop a connection details file with creds
        write-warning "No saved connection details found, prompting user."
        $PNSXTestNSXManager = read-host "NSX Manager Ip/Name"
        $PNSXTestDefMgrCred = Get-Credential -Message "NSX Manager Credentials" -UserName "admin"
        $PNSXTestDefViCred = Get-Credential -message "vCenter Credentials" -UserName "administrator@vsphere.local"
        
        $message  = "Connection info and credentials can be saved (securely) for future invocations."
        $question = "Save connection info?"     
        $decision = $Host.UI.PromptForChoice($message, $question, $ynchoices, 0)
        if ( $decision -eq 0 ) { 
            [pscustomobject]$export = @{
                "nsxm" = $PNSXTestNSXManager;
                "nsxuser" = $PNSXTestDefMgrCred.UserName;
                "nsxpwd" = $PNSXTestDefMgrCred.Password | ConvertFrom-SecureString;
                "viuser" =  $PNSXTestDefViCred.UserName;
                "vipwd" = $PNSXTestDefViCred.Password | ConvertFrom-SecureString
            }
            $export | Export-Clixml -NoClobber:$false -Force $cxnfile
        }
    }
    else { 

        #Previously created connection file exists - try to load it.
        try { 
            $import = Import-Clixml $cxnfile
        }
        catch { 
            write-error "Failed to import connection file $cxnfile.  Delete existing file and try again."
            $_
        }

        if ( -not ( $import.nsxm -and $import.nsxuser -and $import.nsxpwd -and $import.viuser -and $import.vipwd )) { 
            throw "Import file does not contain required connection information.  Delete existing file and try again."
        }
        
        $PNSXTestNSXManager = $import.nsxm
        $PNSXTestDefMgrCred = New-Object System.Management.Automation.PSCredential $import.nsxuser, ( $import.nsxpwd | ConvertTo-SecureString ) 
        $PNSXTestDefViCred = New-Object System.Management.Automation.PSCredential $import.viuser, ( $import.vipwd | ConvertTo-SecureString )

    }

    #Do the needful
    $pestersplat = @{ "testname" = $testname}
    invoke-pester @pestersplat
}
Export-ModuleMember -Function "Start-Test" 