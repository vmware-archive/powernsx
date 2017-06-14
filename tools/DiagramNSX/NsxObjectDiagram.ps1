#NSX Object Diagramming Script
#Nick Bradford
#nbradford@vmware.com
#Version 0.2


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

#Requires -Version 3.0
#Requires -Modules PowerNSX

#This script is a sister script to NSXObjectCapture.ps1.  It reads the export
#file created by NSXObjectCapture.ps1 and generates Topology and configuration
#Documentation.

#v0.1 includes just topology diagramming in Visio, but additional functionality will follow.

#TODO: Deal with relative paths in cap document
#TODO: Specify output filename
#TODO: start visio minimised (performance)
#TODO: implement object type specific explusion (and inclusion?) regex as per discussion with KO


Param (

	[parameter ( Mandatory = $true, Position = 1 )]
		[string]$CaptureBundle,
	[parameter ( Mandatory = $false, Position = 2 )]
		[ValidateScript ({ if ( -not (test-path $_) ) { throw "OutputDir $_ does not exist." } else { $true } })]
		[string]$OutputDir = $([system.Environment]::GetFolderPath('MyDocuments')),
	[parameter ( Mandatory = $false )]
		[switch]$IgnoreLinkLocal = $true,
	[Parameter (Mandatory = $false )]
		[switch]$IncludeVms = $true,
	[Parameter (Mandatory = $false)]
		[string]$TenantRegex,
	[Parameter (Mandatory = $False)]
		[switch]$EyeCandy = $false
)


Function Get-NicIpAddresses {

	param (
		$MacAddress
	)

	$NicIpAddresses = ""
	if ( $MacHash.ContainsKey($MacAddress) ) {
		if ( $IgnoreLinkLocal ) {
			$NicIpAddresses = ($MacHash.Item($MacAddress).detectedipaddress.ipaddress | ? { $_ -notmatch "^fe80:" }) -join ", "
		}
		else {
			$NicIpAddresses = $MacHash.Item($MacAddress).detectedipaddress.ipaddress
		}
	}
	$NicIpAddresses
}

Function VisConnectTo-LogicalSwitch {

	param (

		$LogicalSwitch,
		$ConnectionText,
		$VisioObj,
		[switch]$WarnOnNewPG

	)
	if ( -not $DrawnLogicalSwitchHash.contains($LogicalSwitch.ObjectId) ) {
		# Logical switch is not already on page...

		if ( $TenantRegex -and $WarnOnNewPG ) {
			# If the Tenant Regex is set, we already expect to have switch or portgroup on the page (assuming the vm is connected to LS with a DLR or Edge on it.)
			write-warning "Logical Switch $($LogicalSwitch.Name) does not exist on diagram and a TenantRegex is specified.  This implies that either the Logical Switch is isolated (no Edge/DLR), or it is connected to a LogicalRouter or Edge not matched by the TenantRegex."
			write-warning "This may indicate a VM connected to two different Tenants logical infrastructure, or just that you need to modify your TenantRegex."
		}
		$VisioLs = add-visioobject $lsStencil $logicalswitch.Name @{
			"ObjectId" = $LogicalSwitch.ObjectId;
			"XmlConfig" = ($LogicalSwitch | format-xml);
			"Vni" = $LogicalSwitch.vdnId;
			"ControlPlaneMode" = $LogicalSwitch.ControlPlaneMode
		}
		$DrawnLogicalSwitchHash.add($LogicalSwitch.objectid, $VisioLs)

	}


	$VisioConnection = Connect-VisioObject $VisioObj $DrawnLogicalSwitchHash.Item($LogicalSwitch.objectid) $ConnectionText
}

Function VisConnectTo-VdPortGroup {

	Param(
		$VdPortGroup,
		$ConnectionText,
		$VisioObj,
		[switch]$WarnOnNewPG
	)


	if ( -not $DrawnVDPortGroupHash.ContainsKey($VdPortGroup.MoRef) ) {
		# PortGroup is not already on page...

		if ( $TenantRegex -and $WarnOnNewPG ) {
			# If the Tenant Regex is set, we already expect to have switch or portgroup on the page (assuming the vm is connected to LS with a DLR or Edge on it.)
			write-warning "Distributed PortGroup $($VdPortGroup.Name) does not exist on diagram and a TenantRegex is specified.  This implies that either the Distributed PortGroup is isolated (no Edge/DLR), or it is connected to a LogicalRouter or Edge not matched by the TenantRegex."
			write-warning "This may indicate a VM connected to two different Tenants logical infrastructure, or just that you need to modify your TenantRegex."
		}

		$VisioDvPg = add-visioobject $dvpgStencil $VdPortGroup.Name @{
			"MoRef" = $VdPortGroup.MoRef;
			"VlanId" = $VdPortGroup.VlanId
		}
		$DrawnVDPortGroupHash.add($VdPortGroup.MoRef, $VisioDvPg)
	}

	$VisioConnection = Connect-VisioObject $VisioObj $DrawnVDPortGroupHash.Item($VdPortGroup.MoRef) $ConnectionText
}

Function VisConnectTo-StdPortGroup {

	Param(
		$StdPortGroup,
		$ConnectionText,
		$VisioObj,
		[switch]$WarnOnNewPG
	)


	if ( -not $DrawnStdPortGroupHash.ContainsKey($StdPortGroup.Name) ) {
		# PortGroup is not already on page...

		if ( $TenantRegex -and $WarnOnNewPG ) {
			# If the Tenant Regex is set, we already expect to have switch or portgroup on the page (assuming the vm is connected to LS with a DLR or Edge on it.)
			write-warning "Standard PortGroup $($StdPortGroup.Name) does not exist on diagram and a TenantRegex is specified.  This implies that either the PortGroup is isolated (no Edge/DLR), or it is connected to a LogicalRouter or Edge not matched by the TenantRegex."
			write-warning "This may indicate a VM connected to two different Tenants logical infrastructure, or just that you need to modify your TenantRegex."
		}

		$VisioStdPg = add-visioobject $stdpgStencil $StdPortGroup.Name @{
			"VlanId" = $StdPortGroup.VlanId
		}
		$DrawnStdPortGroupHash.add($StdPortGroup.Name, $VisioStdPg)
	}

	$VisioConnection = Connect-VisioObject $VisioObj $DrawnStdPortGroupHash.Item($StdPortGroup.Name) $ConnectionText
}


function connect-visioobject {
	param (
		[object]$firstObj,
		[object]$secondObj,
		[string]$text,
		[System.Collections.Hashtable]$shapedata
	)

	Write-Host "  Connecting $($FirstObj.Name) with $($SecondObj.Name) with text: $text"
	$Connector = $FirstPage.Drop($FirstPage.Application.ConnectorToolDataObject, 0, 0)

	$Connector.Text = $text
	#// Connect its Begin to the 'From' shape:
	$connectBegin = $Connector.CellsU("BeginX").GlueTo($firstObj.CellsU("PinX"))

	#// Connect its End to the 'To' shape:
	$connectEnd = $Connector.CellsU("EndX").GlueTo($secondObj.CellsU("PinX"))

	#Set ShapeData if exists...
	foreach ( $cell in $shapedata.keys ) {

		if ( -not ($Connector.CellExists($cell, $visExistsAnywhere ) -eq -1)) {
			$newrow = $Connector.AddNamedRow($visSectionProp,$cell, $visTagDefault )
		}
		$Connector.Cells("Prop.$cell").Formula = [char]34 + $ShapeData.Item($cell) + [char]34

	}
}

function add-visioobject{

	param (

		[object]$mastobj,
		[string]$item,
		[System.Collections.Hashtable]$shapedata

	)
	Write-Host "  Adding $item to diagram with stencil $($mastObj.Name)"
	# Drop the selected stencil on the active page at 0,0
	$shape = $FirstPage.Drop($mastObj, 0,0)
	# Enter text for the object
	$shape.Text = $item

	foreach ( $cell in $shapedata.keys ) {

		if ( -not ($shape.CellExists($cell, $visExistsAnywhere ) -eq -1)) {
			$newrow = $shape.AddNamedRow($visSectionProp,$cell, $visTagDefault )
		}
		$value = $ShapeData.Item($cell)

		if ( $value -match  "`"") {
			#if config string contains double quotes (such as in a CN) then we have to swallow it...
			Write-Warning "Removed `" characters from xmlconfig for object $item"

			$value = $value -replace "`"", ""
		}

		$shape.Cells("Prop.$cell").Formula = [char]34 + $value + [char]34
	}

	#Return the visioobject to be used
	return $shape
}

write-host -ForeGroundColor Green "PowerNSX Object Diagram Script"

###################
# Init and Validate

if ( -not ( test-path $CaptureBundle )) {

	throw "Specified File $CaptureBundle not found."
}
$RelTempDir = [io.path]::GetFileNameWithoutExtension($CaptureBundle)
$TempDir = "$($env:Temp)\VMware\NSXObjectDiagram\$RelTempDir"

if ( test-path $TempDir) { remove-item $TempDir -confirm:$false -recurse }

try {
	Add-Type -assembly "system.io.compression.filesystem"
	[io.compression.zipfile]::ExtractToDirectory($CaptureBundle, $TempDir)
}
catch {
	Throw "Unable to extract capture bundle. $_"
}

$LsExportFile = "$TempDir\LsExport.xml"
$VdPgExportFile = "$TempDir\VdPgExport.xml"
$StdPgExportFile = "$TempDir\StdPgExport.xml"
$LrExportFile = "$TempDir\LrExport.xml"
$EdgeExportFile = "$TempDir\EdgeExport.xml"
$VmExportFile = "$TempDir\VmExport.xml"
$CtrlExportFile = "$TempDir\CtrlExport.xml"
$MacAddressExportFile = "$TempDir\MacExport.xml"

try {
	$LsHash = Import-CliXml $LsExportFile
	$VdPortGroupHash = Import-CliXml $VdPgExportFile
	$StdPortGroupHash = Import-CliXml $StdPgExportFile
	$LrHash = Import-CliXml $LrExportFile
	$EdgeHash = Import-CliXml $EdgeExportFile
	$VmHash = Import-CliXml $VmExportFile
	$CtrlHash = Import-CliXml $CtrlExportFile
	$MacHash = Import-CliXml $MacAddressExportFile
}
catch {

	Throw "Unable to import capture bundle content.  Is this a valid capture bundle? $_"

}

# Init control hashtables
$DrawnCtrlHash = @{}
$DrawnVmHash = @{}
$DrawnEdgeHash = @{}
$DrawnLogicalSwitchHash = @{}
$DrawnVDPortGroupHash = @{}
$DrawnStdPortGroupHash = @{}
$DrawnLogicalRouterHash = @{}

#Visio Enums
[int]$visAddHidden = 64
[int]$visMSDefault = 0
[int]$visLOPlaceRadial = 3
[int]$visLORouteStraight = 2
[int]$visExistsAnywhere = 0
[int]$visSectionProp = 243
[int]$visTagDefault = 0

$OutputFile = join-path $OutputDir "$( [io.path]::GetFileNameWithoutExtension($CaptureBundle)).vsdx"
$MyDir = split-path $myinvocation.MyCommand.Path
$NSXShapeFile = "$MyDir\nsxdiagram.vssx"
if ( -not (test-path $NSXShapeFile) ) { throw "Visio Shape file not found.  Ensure it exists in the same directory as this script." }

#Get an Xml Collection of LS so we can filter on backing vals later on.
[System.Xml.XmlDocument[]]$LogicalSwitches = $lshash.Values


#######################
# Launch Visio and ensure we can get the required template.

write-host -ForeGroundColor Green "`nLaunching Microsoft Visio."

# Create an instance of Visio and create a document based on the Basic Diagram template.

try {
	$AppVisio = New-Object -ComObject Visio.Application

	if ( -not $EyeCandy ) {
		#Lets not draw all the stuff as its placed on the screen
		$AppVisio.ScreenUpdating = $False
		$AppVisio.EventsEnabled = $False
	}

	$Documents = $AppVisio.Documents
	$Document = $Documents.Add("Basic Diagram.vst")

	# Set the active page of the document to page 1
	$Pages = $AppVisio.ActiveDocument.Pages
	$FirstPage = $Pages.Item(1)

}
catch {
	write-warning "Error instantiating Microsoft Visio. Ensure Visio is installed.  $_"
	return
}


# Load a set of stencils and select one to drop
try {
	$NSXStencil = $AppVisio.Documents.AddEx($NSXShapeFile,$visMSDefault,$visAddHidden)
}
catch {
	write-warning "Error occured loading Visio Stencil $NSXShapeFile.  $_"
	return
}

try {
	$lsStencil = $NSXStencil.Masters.Item("Logical Switch")
	$vmStencil  = $NSXStencil.Masters.Item("VM Basic")
	$esgStencil = $NSXStencil.Masters.Item("Edge")
	$dlrStencil = $NSXStencil.Masters.Item("Logical Router")
	$dvpgStencil = $NSXStencil.Masters.Item("PortGroup")
	$stdpgStencil = $NSXStencil.Masters.Item("PortGroup")
	$mgrStencil = $NSXStencil.Masters.Item("Manager")
	$ctrlstencil = $NSXStencil.Masters.Item("Controller")
}
catch {

	write-warning "Error occured loading Visio Stencil Item.  $_"
	return
}

try {
	#Set default shape layout style :
	$FirstPage.PageSheet.Cells("PlaceStyle").ResultIU = $visLOPlaceRadial

	#ConnectorStyle :
	$FirstPage.PageSheet.Cells("RouteStyle").ResultIU = $visLORouteStraight

	#And Spacing
	$FirstPage.PageSheet.Cells("AvenueSizeX").Formula = "20 mm"
	$FirstPage.PageSheet.Cells("AvenueSizeY").Formula = "20 mm"
}
catch {
	write-warning "Error occured setting Visio page defaults.  $_"
	return
}

###################################
# Build the diagram now.

write-host -ForeGroundColor Green "`nBuilding Diagram"

[System.Xml.XmlDocument[]]$CtrlDoc = $CtrlHash.Values
$Controllers = $CtrlDoc.controller



#Add all dlr.
ForEach ($LrId in $LrHash.Keys){
	[System.Xml.XmlDocument]$Doc = $LrHash.Item($LrId)
	$logicalrouter = $Doc.edge
	if ( ( -not $TenantRegex) -or ( $logicalrouter.Tenant -match $TenantRegex ) ) {

		$VisioLr = add-visioobject $dlrStencil $LogicalRouter.Name @{
			"ObjectId" = $LrId
			"XmlConfig" = ($LogicalRouter.OuterXml);
		}
		$DrawnLogicalRouterHash.add($LrId, $VisioLr)

		#Connect DLR to Network
		foreach ( $Interface in ( $LogicalRouter.interfaces.interface | ? { $_.isConnected -eq 'true' } ) ) {

			#get concat list of ip addresses
			$IpAddresses = @()
			$Interface.addressGroups.addressGroup | % {
				$ipaddresses += $_.PrimaryAddress
				$_.secondaryaddresses | % {
					$ipaddresses += $_.ipaddress
				}
			}
			#Check if its VLAN backed (PG) or Logical Switch (virtualwire)
			If ( $Interface.connectedToId -match 'virtualwire') {

				[System.Xml.XmlDocument]$LogicalSwitch = $LsHash.item($Interface.connectedToId)
				VisConnectTo-LogicalSwitch -LogicalSwitch $LogicalSwitch.virtualWire -ConnectionText ("$($InterFace.Type): $IpAddresses") -VisioObj $VisioLr
			}
			else {
				$VdPortGroup = $VdPortGroupHash.Item($Interface.connectedToId)
				if ( $VdPortGroup ) {
					#Entity is connected to a DV PortGroup
					VisConnectTo-VdPortGroup -VdPortGroup $VdPortGroupHash.Item($Interface.connectedToId) -ConnectionText ("$($InterFace.Type): $IpAddresses") -VisioObj $VisioLr
				}
				else {
					write-warning "No LS or DV portgroup found for $($Interface.connectedToId)"
				}
			}
		}
	}
	else {
		write-host -ForegroundColor DarkGray "Skipping DLR $($logicalrouter.Name) with tenant property $($logicalrouter.Tenant)"
	}
}


#Add all edges.
ForEach ($EdgeId in $EdgeHash.Keys){
	[System.Xml.XmlDocument]$Doc = $EdgeHash.Item($EdgeId)
	$Edge = $Doc.Edge
	if ( (-not $TenantRegex) -or ( $Edge.Tenant -match $TenantRegex ) ) {

		$VisioEdge = add-visioobject $esgStencil $Edge.Name @{
			"ObjectId" = $EdgeId
			"XmlConfig" = ($Edge.OuterXml);
		}
		$DrawnEdgeHash.add($EdgeId, $VisioEdge)

		#Connect edge to Network
		foreach ( $Interface in ( $Edge.vnics.vnic | ? { $_.isConnected -eq 'true' } ) ) {

			#get concat list of ip addresses
			$IpAddresses = @()
			$Interface.addressGroups.addressGroup | % {
				$ipaddresses += $_.PrimaryAddress
				$_.secondaryaddresses | % {
					$ipaddresses += $_.ipaddress
				}
			}

			#Check if its VLAN backed (PG) or Logical Switch (virtualwire)
			If ( $Interface.portgroupId -match 'virtualwire') {

				[System.Xml.XmlDocument]$LogicalSwitch = $LsHash.item($Interface.portgroupId)
				VisConnectTo-LogicalSwitch -LogicalSwitch $LogicalSwitch.virtualWire -ConnectionText ("$($InterFace.Type): $IpAddresses") -VisioObj $VisioEdge
			}
			else {
				$VdPortGroup = $VdPortGroupHash.Item($Interface.portgroupId)
				if ( $VdPortGroup ) {
					#Entity is connected to a DV PortGroup
					VisConnectTo-VdPortGroup -VdPortGroup $VdPortGroupHash.Item($Interface.portgroupId) -ConnectionText ("$($InterFace.Type): $IpAddresses") -VisioObj $VisioEdge
				}
				else {
					write-warning "No LS or DV portgroup found for $($Interface.portgroupId)"
				}
			}
		}
	}
	else {
		write-host -ForegroundColor DarkGray "Skipping Edge $($Edge.Name) with tenant property $($edge.Tenant)"
	}
}

#Add vms.
if ( $IncludeVms ) {
	ForEach ( $vmid in $VmHash.Keys ){

		if ( $TenantRegex ) {
			$TenantVM = $False
			foreach ( $Nic in ($vmhash.Item($vmid).Nics) ) {
				#We are doing this if the user has specified TenantRegex, to ensure that the VM is attached to a portgroup or LS already drawn on the page.  Otherwise, we skip it.
				$LS = $LogicalSwitches.VirtualWire | ? { $_.vdscontextwithbacking.backingValue -eq $Nic.Portgroup }
				if ( $LS ) {
					#Entity is connected to a Logical Switch.
					if ( $DrawnLogicalSwitchHash.ContainsKey($LS.objectId)) {
						#Entity is connected to a drawn Logical Switch
						$TenantVM = $true
						Break
					}
				}
				#check VDPortGroup and StdPg separately.
				if ( $DrawnVDPortGroupHash.ContainsKey($nic.PortGroup) -or $DrawnStdPortGroupHash.ContainsKey($nic.PortGroup) ) {
					#Entity is connected to a drawn Portgroup
					$TenantVM = $true
					Break
				}
			}
		}

		if ( (-not $TenantRegex) -or ( $TenantVM )) {
			#Only add the VM if there is not tenant filter, or if the VM has been found to have a NIC on an already drawn LS or PG.
			$applianceIp = ""
			if ( $vmhash.Item($vmid).IsLogicalRouter -or $vmhash.Item($vmid).IsEdge ) {
				#Get out, we dont want to diagram edge or DLR here....
				Continue
			}
			elseif ( $vmhash.Item($vmid).IsManager ) {
				$VisioVm = Add-VisioObject $mgrStencil $vmhash.Item($vmid).Name @{ "MoRef" = $vmid }
				if ( $IgnoreLinkLocal ) {
					$ApplianceIp = $vmhash.Item($vmid).ToolsIp | ? { $_ -notmatch "^fe80:" }
				}
				else {
					$ApplianceIp = $vmhash.Item($vmid).ToolsIp
				}
			}
			elseif ( $vmhash.Item($vmid).IsController ) {
				$controller = $Controllers | ? {  $_.virtualMachineInfo.objectId -eq $vmid }
				$VisioVm = Add-VisioObject $ctrlstencil $vmhash.Item($vmid).Name @{ "MoRef" = $vmid}
				$ApplianceIp = $Controller.IpAddress

			}
			else {
				$VisioVm = Add-VisioObject $vmStencil $vmhash.Item($vmid).Name @{ "MoRef" = $vmid }
			}
			$DrawnVmHash.add($vmid, $VisioVm)

			#Connect VM to Network...
			foreach ( $Nic in ($vmhash.Item($vmid).Nics) ) {

				$NicIpAddresses = Get-NicIpAddresses -MacAddress ($nic.MacAddress)
				if ( $NicIpAddresses ) {
					$ConnIp = $NicIpAddresses
				}
				elseif ( $applianceIp ) {
					$ConnIp = $ApplianceIp
				}
				else {
					$ConnIp = ""
				}

				#Try to get the LS Associated with the VMs attached PG.
				$LS = $LogicalSwitches.VirtualWire | ? { $_.vdscontextwithbacking.backingValue -eq $Nic.Portgroup }
				if ( $LS) {
					#Entity is connected to a Logical Switch
					VisConnectTo-LogicalSwitch -LogicalSwitch $LS -ConnectionText $ConnIp -VisioObj $VisioVm -WarnOnNewPG
				}
				else {
					if ( $VdPortGroupHash.ContainsKey($Nic.Portgroup) ) {
						#Entity is connected to a DV PortGroup
						$VdPortGroup = $VdPortGroupHash.Item($Nic.Portgroup)
						VisConnectTo-VdPortGroup -VdPortGroup $VdPortGroup -ConnectionText $ConnIp -VisioObj $VisioVm -WarnOnNewPG
					}
					elseif ( $StdPortGroupHash.ContainsKey($Nic.Portgroup) ) {
						$StdPortGroup = $StdPortGroupHash.Item($Nic.Portgroup)
						VisConnectTo-StdPortGroup -StdPortGroup $StdPortGroup -ConnectionText $ConnIp -VisioObj $VisioVm -WarnOnNewPG
					}
					else {
						write-warning "No LS DV or Standard portgroup found for $($Nic.Portgroup)"
					}
				}
			}
		}
		else {
			write-host -ForegroundColor DarkGray "Skipping VM $($vmhash.Item($vmid).Name) as it has no NICs connected to already drawn Logical Switches or Port Groups."

		}
	}
}



# Final Layout and Resize to fit page
$FirstPage.Layout()
$FirstPage.ResizeToFitContents()

# Save the diagram
try {
	$Document.SaveAs("$OutputFile") | out-null
	write-host -ForeGroundColor Green "`nSaved diagram at $OutputFile"
}
catch {
	write-warning "Unable to save output file, please re-run this script to try again.  $_"
}
