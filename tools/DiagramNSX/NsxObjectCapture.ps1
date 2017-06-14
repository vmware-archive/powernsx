#NSX Object Capture Script
#Nick Bradford
#nbradford@vmware.com
#Version 0.1


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


#Requires -Version 3.0
#Requires -Modules PowerNSX

#This script captures the necessary objects information from NSX and persists
#them to disk in order for topology reconstruction to be done by a sister script
#NSXDiagram.ps1.

param (

    [pscustomobject]$Connection=$DefaultNsxConnection
)

If ( (-not $Connection) -and ( -not $Connection.ViConnection.IsConnected ) ) {

    throw "No valid NSX Connection found.  Connect to NSX and vCenter using Connect-NsxServer first.  You can specify a non default PowerNSX Connection using the -connection parameter."

}

Set-StrictMode -Off

#########################
$TempDir = "$($env:Temp)\VMware\NSXObjectCapture"
$ExportPath = "$([system.Environment]::GetFolderPath('MyDocuments'))\VMware\NSXObjectCapture"
$ExportFile = "$ExportPath\NSX-ObjectCapture-$($Connection.Server)-$(get-date -format "yyyy_MM_dd_HH_mm_ss").zip"

$maxdepth = 5
$maxCaptures = 10

if ( -not ( test-path $TempDir )) {
    New-Item -Type Directory $TempDir | out-null
}
else {
    Get-ChildItem $TempDir | Remove-Item -force -recurse
}

if ( -not ( test-path $ExportPath )) {
    New-Item -Type Directory $ExportPath | out-null
}

$LsExportFile = "$TempDir\LsExport.xml"
$VdPgExportFile = "$TempDir\VdPgExport.xml"
$StdPgExportFile = "$TempDir\StdPgExport.xml"
$LrExportFile = "$TempDir\LrExport.xml"
$EdgeExportFile = "$TempDir\EdgeExport.xml"
$VmExportFile = "$TempDir\VmExport.xml"
$CtrlExportFile = "$TempDir\CtrlExport.xml"
$MacAddressExportFile = "$TempDir\MacExport.xml"


$LsHash = @{}
$VdPortGroupHash = @{}
$StdPgHash = @{}
$LrHash = @{}
$EdgeHash = @{}
$VmHash = @{}
$CtrlHash = @{}
$MacHash = @{}

write-host -ForeGroundColor Green "PowerNSX Object Capture Script"

write-host -ForeGroundColor Green "`nGetting NSX Objects"
write-host "  Getting LogicalSwitches"
Get-NsxLogicalSwitch -connection $connection | % {
    $LsHash.Add($_.objectId, $_.outerXml)
}

write-host "  Getting DV PortGroups"
Get-VDPortGroup -server $connection.ViConnection | % {

    if ( $_.VlanConfiguration ) {
        if (  $_.VlanConfiguration.VlanId ) {
            $VlanID = $_.VlanConfiguration.VlanId
        }
        else {
            $VlanId = "0"
        }
    }
    else {
        $VlanId = "0"
    }
    $VdPortGroupHash.Add( $_.ExtensionData.Moref.Value, [pscustomobject]@{ "MoRef" = $_.ExtensionData.Moref.Value; "Name" = $_.Name; "VlanId" = $VlanId } )

}

write-host "  Getting VSS PortGroups"
Get-VirtualPortGroup -server $connection.ViConnection | ? { $_.key -match 'key-vim.host.PortGroup'} | Sort-Object -Unique | % {
    $StdPgHash.Add( $_.Name, [pscustomobject]@{ "Name" = $_.Name; "VlanId" = $VlanId } )

}

write-host "  Getting Logical Routers"
$LogicalRouters = Get-NsxLogicalRouter -connection $connection
$LogicalRouters | % {
    $LrHash.Add($_.Id, $_.outerXml)
}
write-host "  Getting Edges"
$edges = Get-NsxEdge -connection $connection
$edges | % {
    $EdgeHash.Add($_.id, $_.outerxml)
}

write-host "  Getting NSX Controllers"
$Controllers = Get-NsxController -connection $connection
$Controllers | % {
    $CtrlHash.Add($_.id, $_.outerxml)
}


write-host "  Getting VMs"
Get-Vm -server $connection.ViConnection| % {

    $IsManager = $false
    $IsEdge = $false
    $IsLogicalRouter = $false
    $IsController = $false
    $Nics = @()

    #Tag any edge, DLR or controller vms...
    $moref = $_.id.replace("VirtualMachine-","")
    if ( $Edges.appliances.appliance.vmid ) {
        if ( $Edges.appliances.appliance.vmid.Contains($moref) ) {
            $IsEdge = $true
        }
    }
    if ( $LogicalRouters.appliances.appliance.vmid ) {
        if ( $LogicalRouters.appliances.appliance.vmid.Contains($moref) ) {
            $IsLogicalRouter = $true
        }
    }
    if ( $Controllers.virtualMachineInfo.objectId ) {
        if ( $Controllers.virtualMachineInfo.objectId.Contains($moref) ) {
            $IsController = $true
        }
    }

    #NSX Keeps some metadata about Managers and Edges (not controllers) in the extraconfig data of the associated VMs.
    $configview = $_ | Get-View -Property Config
    $NSXAppliance = ($configview.Config.ExtraConfig | ? { $_.key -eq "vshield.vmtype" }).Value
    If ( $NSXAppliance -eq "Manager" )  {
        $IsManager = $true
    }

    $_ | Get-NetworkAdapter -server $connection.ViConnection | % {
        If ( $_.ExtensionData.Backing.Port.PortgroupKey ) {
            $PortGroup = $_.ExtensionData.Backing.Port.PortgroupKey;
        }
        elseif ( $_.NetworkName ) {
            $PortGroup = $_.NetworkName;
        }
        else {
            #No nic attachment
            Break
        }
        $Nics += [pscustomobject]@{
            "PortGroup" = $PortGroup
            "MacAddress" = $_.MacAddress
        }
    }

    $VmHash.Add($Moref, [pscustomobject]@{
        "MoRef" = $MoRef;
        "Name" = $_.name ;
        "Nics" = $Nics;
        "IsManager" = $IsManager;
        "IsEdge" = $IsEdge;
        "IsLogicalRouter" = $IsLogicalRouter;
        "IsController" = $IsController;
        "ToolsIp" = $_.Guest.Ipaddress })
}

write-host "  Getting IP and MAC details from Spoofguard"
Get-NsxSpoofguardPolicy -connection $connection | Get-NsxSpoofguardNic -connection $connection | % {
    if ($MacHash.ContainsKey($_.detectedmacAddress)) {
        write-warning "Duplicate MAC ($($_.detectedMacAddress) - $($_.nicname)) found.  Skipping NIC!"
    }
    else {
        $MacHash.Add($_.detectedmacaddress, $_)
    }
}


write-host  -ForeGroundColor Green "`nCreating Object Export Bundle"

#Export files
$LsHash | export-clixml -depth $maxdepth $LsExportFile
$VdPortGroupHash | export-clixml -depth $maxdepth $VdPgExportFile
$StdPgHash | export-clixml -depth $maxdepth $StdPgExportFile
$LrHash | export-clixml -depth $maxdepth $LrExportFile
$EdgeHash | export-clixml -depth $maxdepth $EdgeExportFile
$VmHash | export-clixml -depth $maxdepth $VmExportFile
$CtrlHash | export-clixml -depth $maxdepth $CtrlExportFile
$MacHash | export-clixml -depth $maxdepth $MacAddressExportFile

Add-Type -assembly "system.io.compression.filesystem"
[io.compression.zipfile]::CreateFromDirectory($TempDir, $ExportFile)
$Captures = Get-ChildItem $ExportPath -filter 'NSX-ObjectCapture-*.zip'
while ( ( $Captures | measure ).count -ge $maxCaptures ) {

    write-warning "Maximum number of captures reached.  Removing oldest capture."
    $captures | sort-object -property LastWriteTime | select-object -first 1 | remove-item -confirm:$false
    $Captures = Get-ChildItem $ExportPath

}

write-host -ForeGroundColor Green "`nCapture Bundle created at $ExportFile"
