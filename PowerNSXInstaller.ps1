#PowerNSX Installer Script
#Nick Bradford
#nbradford@vmware.com



<#
Copyright © 2015 VMware, Inc. All Rights Reserved.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License version 2, as published by the Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTIBILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License version 2 for more details.

You should have received a copy of the General Public License version 2 along with this program.
If not, see https://www.gnu.org/licenses/gpl-2.0.html.

The full text of the General Public License 2.0 is provided in the COPYING file.
Some files may be comprised of various open source software components, each of which
has its own license that is located in the source code of the respective component.
#>


param (
    [switch]$Upgrade,
    [switch]$Confirm=$true,
    [switch]$Quiet=$false,
    [ValidateSet("CurrentUser","AllUsers")][string]$InstallType="CurrentUser"
    )

#Control which branch is installed.  Latest commit in this branch is used.
$Branch = "master"

#PowerCLI 6.0 R3
$PowerCLI_Download="https://my.vmware.com/group/vmware/details?downloadGroup=PCLI650R1&productId=615"
$PowerCLI_Core_Download = "https://labs.vmware.com/flings/powercli-core"
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

#Minimum PowerCLI versions (Major).
$CorePCLIMinVersion = 1
$DesktopPCLIMinVersion = 6

#PowerNSX (branch latest)
$PowerNSXMod = "https://raw.githubusercontent.com/vmware/powernsx/$Branch/PowerNSX.psm1"
$PowerNSXManifest = "https://raw.githubusercontent.com/vmware/powernsx/$Branch/PowerNSX.psd1"


#Module Path
$ModulePath = "PowerNSX\PowerNSX.psm1"
$ManifestPath = "PowerNSX\PowerNSX.psd1"

$CoreRequiredModules = @("PowerCLI.Vds","PowerCLI.ViCore")
$DesktopRequiredModules = @("VMware.VimAutomation.Core","VMware.VimAutomation.Vds")

function Download-File($url, $targetFile) {

    if ($psversiontable.PSVersion.Major -ge 3 ) {
        #If on Posh 3 or greater, we know we can just use invoke-webrequest -outfile.
        Invoke-WebRequest -Uri $url -outfile $targetFile
    }
    else {
        #Do this the hard way - earlier versions of PoSH dont have iwr

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

    if ( $confirm ) {
        $message  = "The version of dotNet framework on this system is too old to install WMF."
        $question = "Would you like to resolve this? (Will download and install dotNet Framework 4.5.)"

        $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

        $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    }
    else { $decision = 0 }

    if ( $decision -ne 0 ) {
        throw "dotNet Framework 4.5 install rejected. Unable to continue."
    }

    $file = "$($env:temp)\DotNet452.exe"
    Write-Progress -Activity "Installing PowerNSX" -Status "install-dotNet45" -CurrentOperation "Downloading $dotNet_45_Download"
    try {
        download-file $dotNet_45_Download $file
    }
    catch {
        throw "Failed downloading $dotNet_45_Download.  Please check your internet connection and run this script again. _$"
    }

    Write-Progress -Activity "Installing PowerNSX" -Status "install-dotNet45" -CurrentOperation "Installing"

    try {
        $InstallDotNet = Start-Process -Wait -PassThru $file -ArgumentList "/q /norestart"
    }
    catch {

        throw "Failed installing $file. $_"

    }
    Write-Progress -Activity "Installing PowerNSX for" -Status "install-dotNet45" -Completed
}

function install-wmf($version, $uri) {

    Write-Progress -Activity "Installing PowerNSX" -Status "install-wmf" -CurrentOperation "Downloading Windows Management Framework $version"


    $localfile = "$($env:temp)\$($uri.split("/")[-1])"
    try {
        Download-File $uri $localfile
    }
    catch {

        throw "Failed downloading $uri.  $_"

    }

    Write-Progress -Activity "Installing PowerNSX" -Status "install-wmf" -CurrentOperation "Installing Windows Management Framework $version"

    try {
        $InstallWMF = Start-Process -Wait -PassThru "wusa.exe" -ArgumentList "$localfile /quiet /norestart"
    }
    catch {

        throw "An error occured installing WMF. $_"

    }


    if ( $confirm ) {
        $message  = "The system must be rebooted to complete installation."
        $question = "Reboot Now?"

        $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

        $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    }
    else { $decision = 0 }
    if ( $decision -ne 0 ) {
        Throw "Reboot rejected. Restart the system manually and rerun this script."
    }
    else {
        restart-computer
        return
    }

    Write-Progress -Activity "Installing PowerNSX" -Status "install-wmf" -completed
}

function check-powershell {

    #Validate at least PS3
    Write-Progress -Activity "Installing PowerNSX" -Status "check-powershell" -CurrentOperation "Checking for suitable PowerShell version"

    if ( $PSVersionTable.PSVersion.Major -lt $PsMinVersion ) {

        if ( $confirm ) {
                    $message  = "PowerShell version detected is $($PSVersionTable.PSVersion).  A minimum version of PowerShell $PsMinVersion is required."
                    $question = "Would you like to resolve this? (Will download and install appropriate Windows Management Framework update.)"

                    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 }

        if ( $decision -ne 0 ) {
            Throw "Windows Management Framework upgrade rejected. Unable to continue."

        }
        else {
            switch ( [System.Environment]::OSVersion.Version.Major ) {
                6 {
                    switch ( [System.Environment]::OSVersion.Version.Minor ) {
                        0 {
                            Write-Progress -Activity "Installing PowerNSX" -Status "check-powershell" -CurrentOperation "Checking for WMF 3 compatible dotNet framework version"
                            $dotNetVersion = get-dotNetVersion
                            if ( $dotNetVersion.Major -lt 4 ) {
                                install-dotNet45
                            }

                            if ( [System.Environment]::Is64BitOperatingSystem ) {
                                install-wmf -version 3 -uri $WMF_3_60_64_Download
                            }
                            else {

                                install-wmf -version 3 -uri $WMF_3_60_32_Download
                            }
                        }

                        1 {
                            Write-Progress -Activity "Installing PowerNSX" -Status "check-powershell" -CurrentOperation "Checking for WMF 4 compatible dotNet framework version"
                            $dotNetVersion = get-dotNetVersion
                            if ( ($dotNetVersion.Major -lt 4) -or (($dotNetVersion.Major -eq 4) -and ($dotNetVersion.Minor -lt 5))) {
                                install-dotNet45
                            }

                            if ( [System.Environment]::Is64BitOperatingSystem ) {
                                install-wmf -version 4 -uri $WMF_3_61_64_Download
                            }
                            else {

                                install-wmf -version 4 -uri $WMF_3_61_32_Download
                            }
                        }
                    }
                }
            }
        }

        if ( $unsupportedPlatform ) {
            write-host -ForegroundColor Yellow "Unsupported Windows version for automated installation of WMF."
            Throw "Please manually install Windows Management Framework 3 (if supported) or above and run this script again."
        }
    }
    Write-Progress -Activity "Installing PowerNSX" -Status "check-powershell" -Completed
}

function check-powercli {


    #PowerCLI 6 required now.  Module support makes this simple...
    Write-Progress -Activity "Installing PowerNSX" -Status "check-powercli" -CurrentOperation "Checking for compatible PowerCLI version"

    if ( $PSVersionTable.PSEdition -eq "Core") {
        $mods = $CoreRequiredModules
        $RequiredPowerCliVersion = $CorePCLIMinVersion

    }
    else {
        $Mods = $DesktopRequiredModules
        $RequiredPowerCliVersion = $DesktopPCLIMinVersion
    }

    foreach ( $mod in $mods ) {
        #working on the shaky assumption here that all module versions are the same... What could possibly go wrong...:)
        $PowerCLI = Get-Module -ListAvailable -Name $mod
    }

    if ( -not $PowerCli ) {
        install-powercli
    }
    else {
        if ( $PowerCLI.Version.Major -lt $RequiredPowerCliVersion ) {
            install-powercli
        }
    }
    Write-Progress -Activity "Installing PowerNSX" -Status "check-powercli" -Completed
}

function install-powercli {

    if ( -not ( $PSVersionTable.PSEdition -eq "Core" ) ) {
        if ( $confirm ){
            $message  = "PowerCLI is required for full functionality of PowerNSX and it is either not installed or the installed version is too old."
            $question = "Would you like to resolve this? (Opens PowerCLI download page.)"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 }
        if ( $decision -ne 0 ) {
            throw "PowerCLI rejected. Unable to continue."
        }
        else {

            Start-Process -pspath $PowerCLI_Download
            Throw "Rerun this script when the PowerCLI installation is complete."
        }
    }
    else {
        write-warning "Automated PowerCLI installation not supported on PowerShell Core.  Visit $PowerCLI_Core_Download and follow the instructions to install PowerCLI on this system."
        Throw "Rerun this script when the PowerCLI installation is complete."

    }
}

function check-PowerNSX {
    Write-Progress -Activity "Installing PowerNSX" -Status "check-powernsx" -CurrentOperation "Checking for PowerNSX Module"

    if (-not ((Test-Path $ModulePath) -and (test-path $ManifestPath )) -or ( $Upgrade )) {
        if ( $confirm -and (-not $upgrade)) {
            $message  = "PowerNSX module not found."
            $question = "Download and install PowerNSX?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else {
            Write-Progress -Activity "Installing PowerNSX" -Status "check-powernsx" -CurrentOperation "Upgrading"
            $decision = 0
        }

        if ( $decision -ne 0 ) {
            throw "Install rejected. Rerun this script at a later date if you change your mind."
        }
        else {
            $doInstall = $true
        }

    }
    else {

        #Module already exists and user didnt specify upgrade switch prompt user to upgrade.
        $message  = "PowerNSX module is already installed."
        $question = "Do you want to upgrade to the latest available PowerNSX?"

        $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

        $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)

        if ( $decision -eq 0 ) {
            $doInstall = $true
        }
    }

    if ( $doInstall ) {
        $ModuleDir = split-path $ModulePath -parent
        if (-not (test-path $ModuleDir )) {

            Write-Progress -Activity "Installing PowerNSX for" -Status "check-powernsx" -CurrentOperation "Creating directory $ModuleDir"
            new-item -Type Directory $ModuleDir | out-null
        }
        Write-Progress -Activity "Installing PowerNSX" -Status "check-powernsx" -CurrentOperation "Installing PowerNSX"
        Download-File $PowerNSXManifest $ManifestPath
        Download-File $PowerNSXMod $ModulePath
        if (-not ((Test-Path $ModulePath) -and (test-path $ManifestPath ))) {
            throw "Unable to download/install PowerNSX. $_"

        }
    }

    Write-Progress -Activity "Installing PowerNSX" -Status "check-powernsx" -Completed
}

function _set-executionpolicy {

    if ( $confirm ) {
        $message  = "Execution Policy Change."
        $question = "The execution policy helps protect you from scripts that you do not trust.  " +
            "Changing the execution policy might expose you to the security risks described in the " +
            "about_Execution_Policies help topic. Do you want to change the execution policy?"

        $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

        $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    }
    else { $decision = 0 }
    if ( $decision -ne 0 ) {
        throw "ExecutionPolicy change rejected."
    }
    else {

        Write-Progress -Activity "Installing PowerNSX" -Status "check-powernsx" -CurrentOperation "Setting ExecutionPolicy to RemoteSigned"
        set-executionPolicy "RemoteSigned" -confirm:$false

    }
}

function check-executionpolicy {

    Write-Progress -Activity "Installing PowerNSX" -Status "check-powernsx" -CurrentOperation "Checking ExecutionPolicy"
    switch ( get-executionpolicy){

        "AllSigned" {
            _set-executionpolicy

        }
        "Restricted" {
            _set-executionpolicy

        }
        "Default" {
            _set-executionpolicy

        }
    }
}

function init {

    #Perform environment check, and guided dependancy installation for PowerNSX.

    #UserIntro:
    if ( -not $quiet ) {
        write-host
        write-host -ForegroundColor Green "`nPowerNSX Installation Tool"
        write-host
        write-host "PowerNSX is a PowerShell module for VMware NSX (NSX for vSphere)."
        write-host
        write-host "PowerNSX requires PowerShell 3.0 or better and VMware PowerCLI 6.0"
        write-host "or better to function."
        write-host
        write-host "This installation script will automatically guide you through the"
        write-host "download and installation of PowerNSX and its dependancies.  A reboot"
        write-host "may be required during the installation."
        write-host
    }
    if ( $confirm ){
        $message  = "Performing automated installation of PowerNSX."
        $question = "Continue?"
        $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
        $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

        $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        write-host
    }
    else { $decision = 0 }

    if ( $decision -ne 0 ) {
        write-host -ForegroundColor Yellow "Automated installation rejected."
        write-host
        write-host "If you wish to perform the installation manually, ensure the minimum"
        write-host "requirements for PowerNSX are met, place the module file and manifest"
        write-host "in a PowerShell Module directory and run Import-Module PowerNSX from"
        write-host "a PowerCLI session."
        write-host
        return
    }
    else {

        If ( $PSVersionTable.PsEdition -eq "Core" ) {
            Switch ( $InstallType ) {
                "CurrentUser" {
                    $ModDir = "$($env:HOME)/.local/share/powershell/Modules"
                    # $ModDir = $env:PSModulePath.split(";") | ? { $_ -like "$($env:HOMEDRIVE)$($env:HOMEPATH)*" } | select -first 1
                    if ( -not (test-path $ModDir) ) {
                        write-host -ForegroundColor Yellow "Default current user PowerShell Module directory not found. Create the path $moddir or specify -AllUsers when invoking the PowerNSX installation script."
                        return
                    }
                }

                "AllUsers" {
                    $ModDir = "/usr/local/share/powershell/Modules"
                    if ( -not (test-path $ModDir) ) {
                        write-host -ForegroundColor Yellow "Default system PowerShell Module directory not found. Create the path $moddir or specify -CurrentUser when invoking the PowerNSX installation script."
                        return
                    }
                }
            }
        }
        else {
            #assuming Desktop here.  PSEdition prop doesnt exist pre PoSH 5, so we cant test for it.
            Switch ( $InstallType ) {
                "CurrentUser" {
                    $ModDir = $env:PSModulePath.split(";") | ? { $_ -like "$($env:HOMEDRIVE)$($env:HOMEPATH)*" } | select -first 1
                    if ( -not $ModDir ) {
                        write-host -ForegroundColor Yellow "Unable to determine the current users PowerShell Module directory.  Check the `$env:PSModule variable and add a directory located in the users home directory ($($env:HOMEDRIVE)$($env:HOMEPATH)) or specify -AllUsers when invoking the PowerNSX installation script."
                        return
                    }

                    $AllUserModDir = "$($env:ProgramFiles)\Common Files\Modules"
                    if (get-module -ListAvailable -Name PowerNsx | ? { $_.path -like "$AllUserModDir*" }) {
                        write-warning "Existing PowerNSX Installation found in machine wide module directory ($AllUserModDir).  This may cause unexpected results.  Please remove this PowerNSX install manually."
                    }
                }

                "AllUsers" {

                    #All Users install on Windows requires elevation.
                    Write-Progress -Activity "Installing PowerNSX" -Status "Initialising" -CurrentOperation "Checking for Administrator role"
                    if ( -not ( ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
                        [Security.Principal.WindowsBuiltInRole] "Administrator"))) {

                        write-host -ForegroundColor Yellow "The PowerNSX installer requires Administrative rights."
                        write-host -ForegroundColor Yellow "Please restart PowerShell with right click, 'Run As Administrator' or install PowerNSX for the current user only."
                        return
                    }

                    $ModDir = "$($env:ProgramFiles)\Common Files\Modules"
                    if ( -not (test-path $ModDir) ) {

                        #Previous version of the PowerNSX installer created the standard PoSH modules dir on PoSH 2 installs (not created by default), so Ive retained that functionality.
                        #Need to use registry here as the PowerCLI installation changes will not have propogated to the current host.
                        $envModulePath = (Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Session Manager\Environment').PSModulePath
                        if (-not ( $envModulePath.Contains( $ModDir ))) {

                            Write-Progress -Activity "Installing PowerNSX" -Status "check-powernsx" -CurrentOperation "Adding common files module directory to PSModulePath env variable"

                            $envModulePath += ";$ModDir"
                            try {
                                [Environment]::SetEnvironmentVariable("PSModulePath",$envModulePath, "Machine")
                                #We do the following so subsequent runs of the script in the same PowerShell session succeed.
                                $env:PSModulePath = $envModulePath
                            }
                            catch {
                                write-host -ForegroundColor Yellow "Unable to add module path to PSModulePath environment variable. $_"
                                return
                            }
                        }
                    }
                }
            }
        }

        $script:ModulePath = $ModDir + "\$ModulePath"
        $script:ManifestPath = $ModDir +"\$ManifestPath"

        if ( -not ($PSVersionTable.PSEdition -eq "Core" )) {
            try {
                check-executionpolicy
            }

            catch {
                write-host -ForegroundColor Yellow $_
                return
            }
        }
        try {
            check-powershell
        }
        catch {
            write-host -ForegroundColor Yellow $_
            return
        }
        try {
            check-powercli
        }
        catch {
            write-host -ForegroundColor Yellow $_
            return
        }
        try {
            check-PowerNSX
        }
        catch {
            write-host -ForegroundColor Yellow $_
            return
        }

        if ( -not $quiet ) {
            write-host
            write-host -ForegroundColor Green "PowerNSX installation complete."
            write-host
            write-host "PowerNSX requires PowerCLI to function fully!"
            write-host "To get started with PowerNSX, start a new PowerCLI session."
            write-host
            write-host "You can view the cmdlets supported by PowerNSX as follows:"
            write-host "    get-command -module PowerNSX"
            write-host
            write-host "You can connect to NSX and vCenter with Connect-NsxServer."
            write-host
            write-host "Head to https://vmware.github.io/powernsx for documentation,"
            write-host "updates and further assistance."
            write-host
            write-host -ForegroundColor Green "Enjoy!"
            write-host
        }
        return
    }
}

init




