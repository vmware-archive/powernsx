#PowerNSX Test Harness Module.
#Sets up test environment and allows for invocation of tests.

# Must load via manifest file otherwise dep module loads dont occur properly
# Must have separate test manifest for core now :(


#We can drop a connection file that allows future non interactive invocation
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$cxnfile = "$here\Test.cxn"

$ynchoices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
$ynchoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
$ynchoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

$there = Split-Path -Parent $MyInvocation.MyCommand.Path | split-path -parent
$sut = "PowerNSX.psd1"
$pnsxmodule = "$there\$sut"



function Start-Test {
    #Sets up credentials and performs other stuff before invoking pester
    param (
        $testname
    )

    get-module PowerNSX | remove-module
    Import-Module $pnsxmodule -ErrorAction Stop -global

    if ( -not (test-path $cxnfile )) {

        #We allow the user to drop a connection details file with creds
        write-warning "No saved connection details found, prompting user."
        # $PNSXTestNSXManager = read-host "NSX Manager Ip/Name"
        $PNSXTestVC = read-host "vCenter Server Ip/Name"
        $PNSXTestDefMgrUsername = "admin"
        $PNSXTestDefMgrPassword = read-host "NSX Manager admin password"

        ###
        #PowerShell Core has bug in ConvertFrom-SecureString that means we cant persist encrypted credentials to disk.
        #$PNSXTestDefMgrCred = Get-Credential -Message "NSX Manager Credentials" -UserName "admin"
        #$PNSXTestDefViCred = Get-Credential -message "vCenter Credentials" -UserName "administrator@vsphere.local"

        $PNSXTestDefViUsername = read-host "SSO Ent_Admin username"
        $PNSXTestDefViPassword = read-host "SSO Ent_Admin password"
        $PNSXTestDefMgrCred = New-Object System.Management.Automation.PSCredential $PNSXTestDefMgrUsername, ( $PNSXTestDefMgrPassword | ConvertTo-SecureString -AsPlainText -Force )
        $PNSXTestDefViCred = New-Object System.Management.Automation.PSCredential $PNSXTestDefViUsername, ( $PNSXTestDefViPassword | ConvertTo-SecureString -AsPlainText -Force )

        ###

        # $message  = "Connection info and credentials can be saved (securely) for future invocations."
        $message  = "Connection info and credentials can be saved (insecurely!) for future invocations."
        $question = "Save connection info?"
        $decision = $Host.UI.PromptForChoice($message, $question, $ynchoices, 0)
        if ( $decision -eq 0 ) {
            [pscustomobject]$export = @{
                "vc" = $PNSXTestVC;


                ###
                #PowerShell Core has bug in ConvertFrom-SecureString that means we cant persist encrypted credentials to disk.
                "nsxuser" = $PNSXTestDefMgrUsername;
                "nsxpwd" = $PNSXTestDefMgrPassword;
                "viuser" =  $PNSXTestDefViUserName;
                "vipwd" = $PNSXTestDefViPassword

                #"nsxuser" = $PNSXTestDefMgrCred.UserName;
                #"nsxpwd" = $PNSXTestDefMgrCred.Password | ConvertFrom-SecureString;
                #"viuser" =  $PNSXTestDefViCred.UserName;
                #"vipwd" = $PNSXTestDefViPassword | ConvertFrom-SecureString

                ###

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

        if ( -not ( $import.vc -and $import.nsxuser -and $import.nsxpwd -and $import.viuser -and $import.vipwd )) {
            throw "Import file does not contain required connection information.  Delete existing file and try again."
        }

        $PNSXTestVC = $import.vc

        ###
        #PowerShell Core has bug in ConvertFrom-SecureString that means we cant persist encrypted credentials to disk.
        # $PNSXTestDefMgrCred = New-Object System.Management.Automation.PSCredential $import.nsxuser, ( $import.nsxpwd | ConvertTo-SecureString )
        # $PNSXTestDefViCred = New-Object System.Management.Automation.PSCredential $import.viuser, ( $import.vipwd | ConvertTo-SecureString )

        $PNSXTestDefMgrCred = New-Object System.Management.Automation.PSCredential $import.nsxuser, ( $import.nsxpwd | ConvertTo-SecureString -AsPlainText -Force )
        $PNSXTestDefViCred = New-Object System.Management.Automation.PSCredential $import.viuser, ( $import.vipwd | ConvertTo-SecureString -AsPlainText -Force )

        ###
    }

    #Do the needful after testing and validating that the env is suitable for running tests testing.
    $result = invoke-pester -PassThru -Tag "Environment"
    if ( $result.failedcount -eq 0) {
        $pestersplat = @{
            "testname" = $testname
            "ExcludeTag" = "Environment"
        }
        invoke-pester @pestersplat
    }
    else {
        write-error "NSX Environment not suitable to execute PowerNSX test suite."
    }
    #finally remove the module
    get-module PowerNSX | remove-module

}
Export-ModuleMember -Function "Start-Test"