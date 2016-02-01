#NSX Visio Mapping script
#Nick Bradford
#nbradford@vmware.com
#Version 0.1


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

# Based on vDiagram script by Alan Renouf - Virtu-Al - Blog: http://teckinfo.blogspot.com/					
#								

#Requires -Version 3.0


set-strictmode -version Latest

#Y Positioning constants
$vmDefaultYPos = 5
$vmAttachedLSDefaultYPos = 10
$dlrDefaultYPos = 15
$dlrAttachedLSDefaultYPos = 20
$esgDefaultYPos = 25
$esgAttachedLSDefaultYPos = 30


#Origin and Step constants
$defaultStartXPos = 5
$defaultXSpacing = 10



$SaveFile = [system.Environment]::GetFolderPath('MyDocuments') + "\NSXTopo.vsd"

$NSXShapeFile = "\\vmware-host\Shared Folders\Documents\Visio Shapes\NSXShapes (Maish)\NSX1.vss"
$VIShapeFile = "\\vmware-host\Shared Folders\Documents\Visio Shapes\VM-Stencil.vss"
$topologyScript = "C:\Users\nbradford.UNIMATRIX\git\misc\support\NSX\visiohacking.ps1"

. $topologyScript


function connect-visioobject ($firstObj, $secondObj)
{
	$Connector = $FirstPage.Drop($FirstPage.Application.ConnectorToolDataObject, 0, 0)

	#// Connect its Begin to the 'From' shape:
	$connectBegin = $Connector.CellsU("BeginX").GlueTo($firstObj.CellsU("PinX"))
	
	#// Connect its End to the 'To' shape:
	$connectEnd = $Connector.CellsU("EndX").GlueTo($secondObj.CellsU("PinX"))
}

function add-visioobject ($mastObj, $item, $x, $y)
{
 		Write-Host "Adding $item"
		# Drop the selected stencil on the active page, with the coordinates x, y
  		$shape = $FirstPage.Drop($mastObj, $x, $y)
		# Enter text for the object
  		$shape.Text = $item
		#Return the visioobject to be used
		return $shape
 }


# Create an instance of Visio and create a document based on the Basic Diagram template.
$AppVisio = New-Object -ComObject Visio.Application
$Documents = $AppVisio.Documents
$Document = $Documents.Add("Basic Diagram.vst")

# Set the active page of the document to page 1
$Pages = $AppVisio.ActiveDocument.Pages
$FirstPage = $Pages.Item(1)


# Load a set of stencils and select one to drop
$NSXStencil = $AppVisio.Documents.Add($NSXShapeFile)
$VIStencil = $AppVisio.Documents.Add($VIShapeFile)

$lsStencil = $NSXStencil.Masters.Item("vSwitch1")
$vmStencil  = $VIStencil.Masters.Item("VM-Basic")
$esgStencil = $NSXStencil.Masters.Item("Edge Node1")
$dlrStencil = $NSXStencil.Masters.Item("Icon3")


$vmhash = @{}
$edgehash = @{}
$lshash = @{}
$dlrhash = @{}

#Init the coordinates for each layer.

$CurrentVmX = $defaultStartXPos
$CurrentVmY = $vmDefaultYPos

$CurrentVmAttachedLsX = $defaultStartXPos
$CurrentVmAttachedLsY = $vmAttachedLSDefaultYPos

$CurrentDlrX = $defaultStartXPos
$CurrentDlrY = $dlrDefaultYPos

$CurrentDlrAttachedLsX = $defaultStartXPos
$CurrentDlrAttachedLsY = $dlrAttachedLSDefaultYPos

$CurrentEsgX = $defaultStartXPos
$CurrentEsgY = $esgDefaultYPos

$CurrentEsgAttachedLsX = $defaultStartXPos
$CurrentEsgAttachedLsY = $esgAttachedLSDefaultYPos


#VMs and any VM Attached Logical Switches

If (($vmarray) -ne $Null){


	#Drawing VM object at the bottom of the page starting at the LHS


	
	#Add all vms.
	ForEach ($virtualmachine in $vmarray){

		$visiovm = add-visioobject $vmStencil $virtualmachine.Name $CurrentVmX $currentVmY
		$vmhash.add($virtualmachine.objectid, $visiovm)

		#As we add VMs, increase the x coord by default spacing 
		$CurrentVmX += $defaultXSpacing

		#Connect VM to LS...
		foreach ( $lsid in $virtualMachine.ConnectedTo.Values ) { 

			if ( -not $lshash.contains($lsid) ) { 
				# Logical switch is not already on page...

				$logicalswitch = $lsarray | ? { $_.objectid -eq $lsid } 

				$visiols = add-visioobject $lsStencil $logicalswitch.Name $CurrentVmAttachedLsX $CurrentVmAttachedLsY
				$lshash.add($logicalswitch.objectid, $visiols)

				$CurrentVmAttachedLsX += $defaultXSpacing

			}

			#connect the objects now
			$visioconnection = connect-visioobject $visiovm $lshash.Item($lsid)
		}
	}
}


#DLRs and any non VM attached networks.
If (($dlrarray) -ne $Null){
	
	#Add all dlr.
	ForEach ($dlr in $dlrarray){

		$visiodlr = add-visioobject $dlrStencil $dlr.Name $CurrentDlrX $CurrentDlrY
		$dlrhash.add($dlr.objectid, $visiodlr)
		$CurrentDlrX += $defaultXSpacing

		#Connect edge to LS...
		foreach ( $lsid in $dlr.ConnectedTo.Values ) { 

			if ( -not $lshash.contains($lsid) ) { 
				# Logical switch is not already on page...
			
				$logicalswitch = $lsarray | ? { $_.objectid -eq $lsid } 

				$visiols = add-visioobject $lsStencil $logicalswitch.Name $CurrentDlrAttachedLsX $CurrentDlrAttachedLsY
				$lshash.add($logicalswitch.objectid, $visiols)

				$CurrentDlrAttachedLsX += $defaultXSpacing

			}

			#connect the objects now
			$visioconnection = connect-visioobject $visiodlr $lshash.Item($lsid)
		}
	}

}

If (($edgearray) -ne $Null){
	
	#Add all edges.
	ForEach ($edge in $edgearray){

		$visioedge = add-visioobject $esgStencil $edge.Name $CurrentEsgX $CurrentEsgY
		$edgehash.add($edge.objectid, $visioedge)
		$CurrentEsgX += $defaultXSpacing

		#Connect edge to LS...
		foreach ( $lsid in $edge.ConnectedTo.Values ) { 

			if ( -not $lshash.contains($lsid) ) { 
				# Logical switch is not already on page...

				$logicalswitch = $lsarray | ? { $_.objectid -eq $lsid } 

				$visiols = add-visioobject $lsStencil $logicalswitch.Name $CurrentEsgAttachedLsX $CurrentEsgAttachedLsY
				$lshash.add($logicalswitch.objectid, $visiols)

				$CurrentEsgAttachedLsX += $defaultXSpacing

			}

			#connect the objects now
			$visioconnection = connect-visioobject $visioedge $lshash.Item($lsid)
		}
	}

}



# Resize to fit page
$FirstPage.ResizeToFitContents()

# Zoom to 50% of the drawing - Not working yet
#$Application.ActiveWindow.Page = $pagObj.NameU
#$AppVisio.ActiveWindow.zoom = [double].5

# Save the diagram
$Document.SaveAs("$Savefile")

# Quit Visio
#$AppVisio.Quit()
Write-Output "Document saved as $savefile"
