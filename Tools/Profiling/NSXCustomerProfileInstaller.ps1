#############################
# Bootstrap script for installing customer profiling scripts and prereqs
# 
# Nick Bradford, nbradford@vmware.com


#Copyright © 2015 VMware, Inc. All Rights Reserved.

#Permission is hereby granted, free of charge, to any person obtaining a copy of
#this software and associated documentation files (the "Software"), to deal in 
#the Software without restriction, including without limitation the rights to 
#use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies 
#of the Software, and to permit persons to whom the Software is furnished to do 
#so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all 
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
#SOFTWARE.

### Note
#This powershell module should be considered entirely experimental and dangerous
#and is likely to kill babies, cause war and pestilence and permanently block all 
#your toilets.  Seriously - It's still in development,  not tested beyond lab 
#scenarios, and its recommended you dont use it for any production environment 
#without testing extensively!


$temppath = "$env:temp\VMware\VMware NSX Support Utility Installer"
$InstallPath = "$($env:ProgramData)\VMware\VMware NSX Support Utility"
$targetPNSXVersion = New-Object System.Version("2.0.0")
$repo = "https://bitbucket.org/nbradford/powernsx/raw/Dev"
$CuProfilingScript = "$repo/Tools/Profiling/NSXCustomerProfile.ps1"
$PowerNSXInstaller = "$repo/PowerNSXInstaller.ps1"
$PowerCLIInitScript = "$(${env:ProgramFiles(x86)})\VMware\Infrastructure\vSphere PowerCLI\Scripts\Initialize-PowerCLIEnvironment.ps1"


#########################
#From PowerNSx Installer
#Control which branch is installed.  Latest commit in this branch is used.
$Branch = "Dev"

#PowerCLI 6.0 R3 
$PowerCLI_Download="https://my.vmware.com/group/vmware/get-download?downloadGroup=PCLI600R3"

#WMF3 - for Windows 6.0
$WMF_3_61_64_Download="https://download.microsoft.com/download/E/7/6/E76850B8-DA6E-4FF5-8CCE-A24FC513FD16/Windows6.1-KB2506143-x64.msu"
$WMF_3_60_64_Download="https://download.microsoft.com/download/E/7/6/E76850B8-DA6E-4FF5-8CCE-A24FC513FD16/Windows6.0-KB2506146-x64.msu"
$WMF_3_61_32_Download="https://download.microsoft.com/download/E/7/6/E76850B8-DA6E-4FF5-8CCE-A24FC513FD16/Windows6.1-KB2506143-x86.msu"
$WMF_3_60_32_Download="https://download.microsoft.com/download/E/7/6/E76850B8-DA6E-4FF5-8CCE-A24FC513FD16/Windows6.0-KB2506146-x86.msu"

#WMF4 - for Windows 6.1
$WMF_4_61_64_Download="https://download.microsoft.com/download/3/D/6/3D61D262-8549-4769-A660-230B67E15B25/Windows6.1-KB2819745-x64-MultiPkg.msu"
$WMF_4_61_32_Download="https://download.microsoft.com/download/3/D/6/3D61D262-8549-4769-A660-230B67E15B25/Windows6.1-KB2819745-x86-MultiPkg.msu"

#dotNet framework 45 
$dotNet_45_Download="https://download.microsoft.com/download/E/2/1/E21644B5-2DF2-47C2-91BD-63C560427900/NDP452-KB2901907-x86-x64-AllOS-ENU.exe"

#Minimum version of PS required.
$PSMinVersion = "3"


#PowerNSX (branch latest)
$PowerNSXMod = "https://bitbucket.org/nbradford/powernsx/raw/$Branch/PowerNSX.psm1"
$PowerNSXManifest = "https://bitbucket.org/nbradford/powernsx/raw/$Branch/PowerNSX.psd1"

#Module Path
$ModulePath = "$($env:ProgramFiles)\Common Files\Modules\PowerNSX\PowerNSX.psm1"
$ManifestPath = "$($env:ProgramFiles)\Common Files\Modules\PowerNSX\PowerNSX.psd1"

function Download-File($url, $targetFile) {

   $uri = New-Object "System.Uri" "$url"
   $request = [System.Net.HttpWebRequest]::Create($uri)
   $request.set_Timeout(15000) #15 second timeout
   $response = $request.GetResponse()
   $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
   $responseStream = $response.GetResponseStream()
   $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
   $buffer = new-object byte[] 512KB
   $count = $responseStream.Read($buffer,0,$buffer.length)
   $downloadedBytes = $count
   while ($count -gt 0)
   {
       $targetStream.Write($buffer, 0, $count)
       $count = $responseStream.Read($buffer,0,$buffer.length)
       $downloadedBytes = $downloadedBytes + $count
       Write-Progress -activity "Downloading file '$($url.split('/') | Select -Last 1)'" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes/1024)) / $totalLength)  * 100)

   }
   Write-Progress -activity "Downloading file '$($url.split('/') | Select -Last 1)'" -status "Download Complete" -completed

   $targetStream.Flush()
   $targetStream.Close()
   $targetStream.Dispose()
   $responseStream.Dispose()
}

function get-dotNetVersion {

    $dotNetVersionString = gci 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse | Get-ItemProperty -name Version -EA 0 |  Sort-Object -Descending -Property Version | select -ExpandProperty version -First 1
    $dotNETVersionsArray = $dotNETVersionString.Split(".")

    $dotNETVersions = New-Object PSObject
    $dotNETVersions | add-member -membertype NoteProperty -Name VersionString -Value $dotNetVersionString
    $dotNETVersions | add-member -membertype NoteProperty -Name Major -Value $dotNETVersionsArray[0]
    $dotNETVersions | add-member -membertype NoteProperty -Name Minor -Value $dotNETVersionsArray[1]
    $dotNETVersions | add-member -membertype NoteProperty -Name Build -Value $dotNETVersionsArray[2]

    return $dotNETVersions
}

function install-dotNet45 {

    $message  = "The version of dotNet framework on this system is too old to install WMF."
    $question = "Would you like to resolve this? (Will download and install dotNet Framework 4.5.)"

    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    write-host

    if ( $decision -ne 0 ) {
        throw "dotNet Framework 4.5 install rejected. Unable to continue." 
        
    }

    Write-Host -NoNewline "Downloading dotNet 4.5..." 
    $file = "$($env:temp)\DotNet452.exe"
    try {
        download-file $dotNet_45_Download $file
    }
    catch { 
        Write-Host -ForegroundColor Yellow "Failed."
        write-host
        throw "Unable to continue.  Please check your internet connection and run this script again." 

    }

    Write-Host -ForegroundColor Green "Ok."
    write-host -NoNewline "Installing dotNet 4.5..."

    try { 
        $InstallDotNet = Start-Process -Wait -PassThru $file -ArgumentList "/q /norestart" 
    }
    catch {
        Write-Host -ForegroundColor Yellow "Failed."
        write-host 
        throw "Resolve the cause of failure, or manually perform dotNet 4.5 installation and run this script again."

    }
    Write-Host -ForegroundColor Green  "Ok." 
}
    
function install-wmf($version, $uri) {

    Write-Host -NoNewline "Downloading Windows Management Framework $version..." 
    
    $localfile = "$($env:temp)\$($uri.split("/")[-1])"
    try { 
        Download-File $uri $localfile
    }
    catch {

        Write-Host -ForegroundColor Yellow "Failed."
        write-host
        throw "Unable to continue.  Please check your internet connection and run this script again." 

    }

    Write-Host -ForegroundColor Green "Ok."
    write-host -NoNewline "Installing Windows Management Framework $version..."
    
    try {
        $InstallWMF = Start-Process -Wait -PassThru "wusa.exe" -ArgumentList "$localfile /quiet /norestart" 
    } 
    catch {
        Write-Host -ForegroundColor Red  "Error."
        write-host 
        write-host -ForegroundColor Yellow "An error occured installing WMF. $_"
        throw "Unable to continue.  Resolve the issue and run this script again."
        
    }
    Write-Host -ForegroundColor Green  "Ok."

    write-Host
    $message  = "The system must be rebooted to complete installation."
    $question = "Reboot Now?"

    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    write-host

    if ( $decision -ne 0 ) { 

        Throw "Reboot rejected. Restart the system manually and rerun this script." 
        
    }
    else {
        restart-computer
        exit 1
    } 
}

function check-powershell {

    #Validate at least PS3
    write-host -NoNewline "Checking for compatible PowerShell version..."

    if ( $PSVersionTable.PSVersion.Major -lt $PsMinVersion ) {

        write-host -ForegroundColor Yellow "Failed."
        $message  = "PowerShell version detected is $($PSVersionTable.PSVersion).  A minimum version of PowerShell $PsMinVersion is required."
        $question = "Would you like to resolve this? (Will download and install appropriate Windows Management Framework update.)"

        $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

        $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        write-host  

        if ( $decision -ne 0 ) {
            Throw "Windows Management Framework upgrade rejected. Unable to continue." 
            
        }
        else {
            switch ( [System.Environment]::OSVersion.Version.Major ) {
                6 {
                    switch ( [System.Environment]::OSVersion.Version.Minor ) {
                        0 { 
                            write-host -NoNewline "Checking for WMF 3 compatible dotNet framework version..."
                            $dotNetVersion = get-dotNetVersion
                            if ( $dotNetVersion.Major -lt 4 ) {
                                write-host -ForegroundColor Yellow "Failed."
                                install-dotNet45
                            }
                            else {
                                write-host -ForegroundColor Green "Ok."
                            }
                            
                            if ( (gwmi win32_operatingsystem).OSArchitecture -eq "64-Bit") {
                                install-wmf -version 3 -uri $WMF_3_60_64_Download
                            }
                            else {

                                install-wmf -version 3 -uri $WMF_3_60_32_Download
                            }
                        }

                        1 {
                            write-host
                            write-host -NoNewline "Checking for WMF 4 compatible dotNet framework version..."
                            $dotNetVersion = get-dotNetVersion
                            if ( ($dotNetVersion.Major -lt 4) -or (($dotNetVersion.Major -eq 4) -and ($dotNetVersion.Minor -lt 5))) {
                                write-host -ForegroundColor Yellow "Failed."
                                install-dotNet45
                            }
                            else {
                                write-host -ForegroundColor Green "Ok."
                            }

                            if ( (gwmi win32_operatingsystem).OSArchitecture -eq "64-Bit") {
                                install-wmf -version 4 -uri $WMF_3_61_64_Download
                            }
                            else {

                                install-wmf -version 4 -uri $WMF_3_61_32_Download
                            }
                        }
                      
                        2 {
                            #windows 2k12 / Windows 8 
                            write-host -ForegroundColor Red "PowerShell 3.0 should already be installed on Windows 6.2, but was not found which was unexpected."
                        }
                    }
                }
            }
        } 

        if ( $unsupportedPlatform ) {
            write-host  
            write-host -ForegroundColor Yellow "Unsupported Windows version for automated installation of WMF."
            Throw "Please manually install Windows Management Framework 3 (if supported) or above and run this script again." 
            
        }
    }
    else{
        write-host -ForegroundColor Green "Ok."
    }
}

function check-powercli {


    #Validate at least PowerCLI 5.5 via uninstall reg key
    write-host -NoNewline "Checking for compatible PowerCLI version..."
    if ((gwmi win32_operatingsystem).osarchitecture -eq "64-bit") { 
        $PowerCli = get-childitem "HKLM:Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" | % { $_ | get-itemproperty | ? { $_.displayName -match 'PowerCLI' }}

    }else {
        $PowerCli = get-childitem "HKLM:Software\Microsoft\Windows\CurrentVersion\Uninstall" | % { $_ | get-itemproperty | ? { $_.displayName -match 'PowerCLI' }}
    }

    if ( -not $PowerCli ) {
        write-host -ForegroundColor Yellow "Failed."
        write-host -ForegroundColor Yellow "PowerCLI is not installed on this system."

        install-powercli
        
    }
    else {
        switch ($PowerCli.VersionMajor) {

            { $_ -lt 5 } {

                write-host -ForegroundColor Yellow "Failed."
                write-host -ForegroundColor Yellow "The version of PowerCLI installed on this system is too old."

                install-powercli
            
            }

            { $_ -eq 5 } { 
                if ( $PowerCLi.VersionMinor -lt 5 ) { 
                    write-host -ForegroundColor Yellow "Failed."
                    write-host -ForegroundColor Yellow "The version of PowerCLI installed on this system is too old."

                    install-powercli

                }
                else {
                    write-host -ForegroundColor Green "Ok."
                    write-host -NoNewline "Checking for compatible PowerCLI version..."

                }
            }
            { $_ -gt 5 }  { write-host -ForegroundColor Green "Ok." }   
        }
    }
}

function install-powercli {

    $message  = "PowerCLI is required for full functionality of PowerNSX."
    $question = "Would you like to resolve this? (Opens PowerCLI download page.)"

    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    write-host

    if ( $decision -ne 0 ) { 
        throw "PowerCLI rejected. Unable to continue." 
        write-host
    }
    else {

        Start-Process -pspath $PowerCLI_Download
        Throw "Rerun this script when the PowerCLI installation is complete."
    }
}

function check-PowerNSX {

    write-host -NoNewline "Checking for PowerNSX Module..."
    
    if (-not ((Test-Path $ModulePath) -and (test-path $ManifestPath )) -or ( $Upgrade )) { 
        if ( -not $upgrade) { 
            write-host -ForegroundColor Yellow "Failed."
            $message  = "PowerNSX module not found."
            $question = "Download and install PowerNSX?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else {
            write-host -ForegroundColor Yellow "Upgrading."
            $decision = 0

        }
        write-host

        if ( $decision -ne 0 ) { 
            throw "PowerNSX install rejected. Rerun this script at a later date if you change your mind." 

        }
        else {

            $ModuleDir = split-path $ModulePath -parent
            if (-not (test-path $ModuleDir )) {

                write-host -NoNewline "Creating directory $ModuleDir..."
                new-item -Type Directory $ModuleDir | out-null
                write-host -ForegroundColor Green "Ok."
            }
            write-host -NoNewline "Installing PowerNSX..."
            Download-File $PowerNSXManifest $ManifestPath
            Download-File $PowerNSXMod $ModulePath
            if (-not ((Test-Path $ModulePath) -and (test-path $ManifestPath ))) { 
                write-host -ForegroundColor Yellow "Failed."
                write-host 
                throw "Unable to download/install PowerNSX."

            }
            else{
                write-host -ForegroundColor Green "Ok."
            }
        }

    } else {
        write-host -ForegroundColor Green "Ok."
    }

    write-host -NoNewline "Checking PSModulePath for PowerNSX..."

    #Need to use registry here as the PowerCLI installation changes will not have propogated to the current host.
    $envModulePath = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\Environment').PSModulePath
    $ParentModulePath = split-path -parent (split-path -parent $ModulePath)
    if (-not ( $envModulePath.Contains( $ParentModulePath ))) { 

        write-host -ForegroundColor Yellow "Failed."
        write-host -NoNewline "Adding common files module directory to PSModulePath env variable..."
        
        $envModulePath += ";$(split-path (split-path $ModulePath -Parent) -parent)"
        try {
            [Environment]::SetEnvironmentVariable("PSModulePath",$envModulePath, "Machine")
            #We do the following so subsequent runs of the script in the same PowerShell session succeed.
            $env:PSModulePath = $envModulePath
        }
        catch {
            write-host -ForegroundColor Yellow "Failed."
            write-host
            write-host -ForegroundColor Yellow "Unable to add module path to PSModulePath environment variable. $_"
            write-host -ForegroundColor Yellow "Resolve the problem and run this script again."

        }
        write-host -ForegroundColor Green "Ok."

    }
    else {
        write-host -ForegroundColor Green "Ok."

    }

}

function _set-executionpolicy {

    $message  = "Execution Policy Change."
    $question = "The execution policy helps protect you from scripts that you do not trust.  " + 
        "Changing the execution policy might expose you to the security risks described in the " + 
        "about_Execution_Policies help topic. Do you want to change the execution policy?"

    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    write-host

    if ( $decision -ne 0 ) { 
        throw "ExecutionPolicy change rejected."

    }
    else {

        set-executionPolicy "RemoteSigned" -confirm:$false
        write-host 
        write-host -ForegroundColor Yellow "Changed ExecutionPolicy to RemoteSigned"
        write-host   
    }
}

function check-executionpolicy {

    write-host -NoNewline "Checking ExecutionPolicy..."
    switch ( get-executionpolicy){

        "AllSigned" { 
            write-host -ForegroundColor Yellow "Failed. (Allsigned)"
            _set-executionpolicy

        }
        "Restricted" { 
            write-host -ForegroundColor Yellow "Failed. (Restricted)"
            _set-executionpolicy
     
        }
        "Default" { 
            write-host -ForegroundColor Yellow "Failed. (Default)"
            _set-executionpolicy
           
        }
        default { write-host -ForegroundColor Green "Ok." }

    }
}

function install-powernsx {

    #Perform environment check, and guided dependancy installation for PowerNSX.

    #UserIntro:
    write-host 
    write-host -ForegroundColor Green "`nPowerNSX Installation Tool"
    write-host 
    write-host "PowerNSX is a PowerShell module for VMware NSX (NSX for vSphere)."
    write-host
    write-host "PowerNSX requires PowerShell 3.0 or better and VMware PowerCLI 5.5"
    write-host "or better to function."
    write-host 
    write-host "This installation script will automatically guide you through the"
    write-host "download and installation of PowerNSX and its dependancies.  A reboot"
    write-host "may be required during the installation."
    write-host 

    $message  = "Performing automated installation of PowerNSX."
    $question = "Continue?"
    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    write-host

    if ( $decision -ne 0 ) { 
        write-host -ForegroundColor Yellow "Automated installation rejected."
        write-host 
        write-host "If you wish to perform the installation manually, ensure the minimum"
        write-host "requirements for PowerNSX are met, place the module file in a"
        write-host "PowerShell Module directory and run Import-Module PowerNSX from"
        write-host "a PowerCLI session." 
        write-host  
        throw "User Cancelled"
    }
    else {
        write-host -ForegroundColor Yellow "Performing automated installation of PowerNSX.`n"
        check-executionpolicy  
        check-powershell
        check-powercli
        check-PowerNSX

        write-host -ForegroundColor Green "`nPowerNSX installation complete.`n"

    }
}

################
###################


function Download-TextFile { 

    #Stupidly simple text file downloader.
    param (

        [string]$source,
        [string]$destination
        
    )
    
    $wc = new-object Net.WebClient

    write-debug "Download: $source, $destination"
    try {
        write-progress -Activity "Downloading file" -Status "$source -> $destination"
        [string]$text = $wc.DownloadString($source)
    }
    catch { 
        if ( $_.exception.innerexception -match "(407)" ) {
            $wc.proxy.credentials = Get-Credential -Message "Proxy Authentication Required"
            $wc.DownloadString($labModule) 
        } 
        else { 
            throw $_ 
        }
    }

    try { 
        $text | set-content $destination
    } 
    catch { 
        throw $_ 
    }
    write-progress -Activity "Downloading file" -Status "$source -> $destination" -completed
    write-host "Downloaded $destination"

}

function Check-PowerCliAsemblies {

    #Checks for known assemblies loaded by PowerCLI.
    #PowerNSX uses a variety of types, and full operation requires 
    #extensive PowerCLI usage.  
    #As of v2, we now _require_ PowerCLI assemblies to be available.
    #This method works for both PowerCLI 5.5 and 6 (snapin vs module), 
    #shouldnt be as heavy as loading each required type explicitly to check 
    #and should function in a modified PowerShell env, as well as normal 
    #PowerCLI.
    
    $RequiredAsm = (
        "VMware.VimAutomation.ViCore.Cmdlets", 
        "VMware.Vim",
        "VMware.VimAutomation.Sdk.Util10Ps",
        "VMware.VimAutomation.Sdk.Util10",
        "VMware.VimAutomation.Sdk.Interop",
        "VMware.VimAutomation.Sdk.Impl",
        "VMware.VimAutomation.Sdk.Types",
        "VMware.VimAutomation.ViCore.Types",
        "VMware.VimAutomation.ViCore.Interop",
        "VMware.VimAutomation.ViCore.Util10",
        "VMware.VimAutomation.ViCore.Util10Ps",
        "VMware.VimAutomation.ViCore.Impl",
        "VMware.VimAutomation.Vds.Commands",
        "VMware.VimAutomation.Vds.Impl",
        "VMware.VimAutomation.Vds.Interop",
        "VMware.VimAutomation.Vds.Types",
        "VMware.VimAutomation.Storage.Commands",
        "VMware.VimAutomation.Storage.Impl",
        "VMware.VimAutomation.Storage.Types",
        "VMware.VimAutomation.Storage.Interop",
        "VMware.DeployAutomation",
        "VMware.ImageBuilder"
    )


    $CurrentAsmName = foreach( $asm in ([AppDomain]::CurrentDomain.GetAssemblies())) { $asm.getName() } 
    $CurrentAsmDict = $CurrentAsmName | Group-Object -AsHashTable -Property Name

    foreach( $req in $RequiredAsm ) { 

        if ( -not $CurrentAsmDict.Contains($req) ) { 
            write-warning "PowerNSX requires PowerCLI."
            throw "Assembly $req not found.  Some required PowerCli types are not available in this PowerShell session.  Please ensure you are running PowerNSX in a PowerCLI session, or have manually loaded the required assemblies."}
    }
}


###################################
# 

clear-host

write-host -foregroundcolor green "`n##################################################"
write-host -foregroundcolor green "VMware Customer Profiling Tool installation script`n"
write-host -foregroundcolor green "Checking environment.`n"

#Check for Admin privs
if ( -not ( ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))) { 

    write-host -ForegroundColor Yellow "The installer requires Administrative rights."
    write-host -ForegroundColor Yellow "Please restart PowerCLI with right click, 'Run As Administrator'"
    return
}

try { 
    check-executionpolicy
}
catch {
    return
}

if ( -not ( test-path $temppath)) { 
    write-host "Creating path $temppath"
    new-item $temppath -Type dir | out-null
}

if ( -not (test-path $InstallPath )) { 
    write-host "Creating path $InstallPath"
    New-Item -Type Directory -Path $InstallPath | out-null
}


do {
    
    try {
        install-powernsx
    }
    catch { 
        Write-Warning "PowerNSX Installation not complete.  Rerun me to try again." 
        return
    }
    else { 

        #We know now that PowerCLI is installed.   Need to get user over to it...
        try { 
            Check-PowerCliAsemblies 
        }
        catch {

            write-warning "Please relaunch this installer in a PowerCLI session to continue."
            return
        }
    } 

    #If an update was done, unload and reload mod to make sure we are using new version.
    if ( Get-Module PowerNsx ) { 
        remove-module PowerNsx
    }

    import-module powernsx -ErrorAction "silentlycontinue"
    if ( -not ( Get-Module PowerNsx )  ) { 
        $version = 0
    }
    else { 
        $version = (Get-PowerNsxVersion).Version
    }

    #Upgrade / Install if required.  Temp hack to deal with the supid v1 string...
    if ( -not ($version -is [System.Version] )) { 
        $UpdateRequired = $true
        Write-Host "PowerNSX installation or upgrade required (Current version $version, Required version $targetPNSXVersion.)"
    }
    else { 
        if ( $version.CompareTo($targetPNSXVersion) -lt 0 ) {
            $UpdateRequired = $true
            Write-Host "PowerNSX installation or upgrade required (Current version $version, Required version $targetPNSXVersion.)"
        }
        else {
            $UpdateRequired = $false
        }
    }
} while ( $UpdateRequired ) 

if ( -not $UpdateRequired ) {    
    #Only continue once PowerNSX is installed..
    #Get the profiling script.
    write-host -foregroundcolor green "`nRetrieving customer profiling tool.`n"
    $CuProfilingScript_filename = split-path $CuProfilingScript -leaf
    Download-TextFile $CuProfilingScript "$InstallPath\$CuProfilingScript_filename"
    write-host -foregroundcolor green "`nExecuting Script and running Setup for the first time.`n"
    & "$InstallPath\$CuProfilingScript_filename" | invoke-expression

}
