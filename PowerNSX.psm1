#Powershell NSX module
#Nick Bradford
#nbradford@vmware.com

#This powershell module should be considered entirely experimental and dangerous
#and is likely to kill babies, cause war and pestilence and permanently block all 
#your toilets.  Seriously - Its not tested beyond lab scenarios, and its recommended
#you dont use it for any production environment without testing extensively!
#


###
# To Do
#
# - Check for PS3 min. Install Windows Management Framework 4.0 automatically?
# - Get Vms on LS -> needs get-nsxbackingpg (Get-NsxTransportZone | Get-NsxLogicalSwitch LS1 | get-nsxbackingpg | get-vm)
# - Get Edges on LS -> needs get-nsxedgeservice gateway to accept LS as input object
# - Get Hosts on LS -> needs get-nsxbackingpg (Get-NsxTransportZone | Get-NsxLogicalSwitch LS1 | get-nsxbackingpg | % { $_.vdswitch | get-vmhost } | sort-object -uniq 

#
#

set-strictmode -version Latest

## Custom classes

if ( -not ("TrustAllCertsPolicy" -as [type])) {

    add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@

}

########
########
# Private functions

function Invoke-NsxRestMethod {

    #Internal method to construct the REST call headers including auth as expected by NSX.
    #Accepts either a connection object as produced by connect-nsxserver or explicit
    #parameters.

    [CmdletBinding(DefaultParameterSetName="ConnectionObj")]
  
    param (
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [System.Management.Automation.PSCredential]$cred,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [string]$server,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [int]$port,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [string]$protocol,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [bool]$ValidateCertificate,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            [string]$method,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            [string]$URI,
        [Parameter (Mandatory=$false,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            [string]$body = "",
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            [psObject]$connection,
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            [System.Collections.Hashtable]$extraheader   
    )

    Write-Debug "invoke-nsxrestmethod - ParameterSetName : $($pscmdlet.ParameterSetName)"

    if ($pscmdlet.ParameterSetName -eq "Parameter") {
        if ( -not $ValidateCertificate) { 
            #allow untrusted certificate presented by the remote system to be accepted 
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        }
    }
    else {

        #ensure we were either called with a connection or there is a defaultConnection (user has 
        #called connect-nsxserver) 
        #Little Grr - $connection is a defined variable with no value so we cant use test-path
        if ( $connection -eq $null) {
            
            #Now we need to assume that defaultnsxconnection does not exist...
            if ( -not (test-path variable:global:DefaultNSXConnection) ) { 
                throw "Not connected.  Connect to NSX manager with Connect-NsxServer first." 
            }
            else { 
                Write-Debug "invoke-nsxrestmethod - Using default connection"
                $connection = $DefaultNSXConnection
            }       
        }

        
        if ( -not $connection.ValidateCertificate ) { 
            #allow untrusted certificate presented by the remote system to be accepted 
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        }

        $cred = $connection.credential
        $server = $connection.Server
        $port = $connection.Port
        $protocol = $connection.Protocol

    }

    $headerDictionary = @{}
    $base64cred = [system.convert]::ToBase64String(
        [system.text.encoding]::ASCII.Getbytes(
            "$($cred.GetNetworkCredential().username):$($cred.GetNetworkCredential().password)"
        )
    )
    $headerDictionary.add("Authorization", "Basic $Base64cred")

    if ( $extraHeader ) {
        $extraHeader.GetEnumerator() | % {
            write-debug "Adding extra header $($_.Key ) : $($_.Value)"
            $headerDictionary.add($_.Key, $_.Value)
        }
    }
    $FullURI = "$($protocol)://$($server):$($Port)$($URI)"
    write-debug "invoke-nsxrestmethod:- Method: $method, URI: $FullURI, Body: $($body | Format-Xml)"
    #do rest call
    
    try { 
        if (( $method -eq "put" ) -or ( $method -eq "post" )) { 
            $response = invoke-restmethod -method $method -headers $headerDictionary -ContentType "application/xml" -uri $FullURI -body $body
        } else {
            $response = invoke-restmethod -method $method -headers $headerDictionary -ContentType "application/xml" -uri $FullURI
        }
    }
    catch {
        
        #Get response from the exception
        $response = $_.exception.response
        if ($response) {  
            $responseStream = $_.exception.response.GetResponseStream()
            $reader = New-Object system.io.streamreader($responseStream)
            $responseBody = $reader.readtoend()
            $ErrorString = "invoke-nsxrestmethod : Exception occured calling invoke-restmethod. $($response.StatusCode.value__) : $($response.StatusDescription) : Response Body: $($responseBody)"
            throw $ErrorString
        }
        else { 
            throw $_ 
        } 
        

    }
    switch ( $response ) {
        { $_ -is [xml] } { write-debug "invoke-nsxrestmethod:- Response: $($response.outerxml | Format-Xml)" } 
        { $_ -is [System.String] } { write-debug "invoke-nsxrestmethod:- Response: $($response)" }
        default { write-debug "invoke-nsxrestmethod:- Response type unknown" }

    }
    $response

}

#Export-ModuleMember -Function Invoke-NsxRestMethod


function Invoke-NsxWebRequest {

    #Internal method to construct the REST call headers etc
    #Alternative to Invoke-NsxRestMethod that enables retrieval of response headers
    #as the NSX API is not overly consistent when it comes to methods of returning 
    #information to the caller :|.  Used by edge cmdlets like new/update esg and logicalrouter.

    [CmdletBinding(DefaultParameterSetName="ConnectionObj")]
  
    param (
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [System.Management.Automation.PSCredential]$cred,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [string]$server,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [int]$port,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [string]$protocol,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            [bool]$ValidateCertificate,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            [string]$method,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            [string]$URI,
        [Parameter (Mandatory=$false,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            [string]$body = "",
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            [psObject]$connection,
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            [System.Collections.Hashtable]$extraheader   
    )

    Write-Debug "invoke-nsxwebrequest - ParameterSetName : $($pscmdlet.ParameterSetName)"

    if ($pscmdlet.ParameterSetName -eq "Parameter") {
        if ( -not $ValidateCertificate) { 
            #allow untrusted certificate presented by the remote system to be accepted 
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        }
    }
    else {

        #ensure we were either called with a connection or there is a defaultConnection (user has 
        #called connect-nsxserver) 
        #Little Grr - $connection is a defined variable with no value so we cant use test-path
        if ( $connection -eq $null) {
            
            #Now we need to assume that defaultnsxconnection does not exist...
            if ( -not (test-path variable:global:DefaultNSXConnection) ) { 
                throw "Not connected.  Connect to NSX manager with Connect-NsxServer first." 
            }
            else { 
                Write-Debug "invoke-nsxwebrequest - Using default connection"
                $connection = $DefaultNSXConnection
            }       
        }

        
        if ( -not $connection.ValidateCertificate ) { 
            #allow untrusted certificate presented by the remote system to be accepted 
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        }

        $cred = $connection.credential
        $server = $connection.Server
        $port = $connection.Port
        $protocol = $connection.Protocol

    }

    $headerDictionary = @{}
    $base64cred = [system.convert]::ToBase64String(
        [system.text.encoding]::ASCII.Getbytes(
            "$($cred.GetNetworkCredential().username):$($cred.GetNetworkCredential().password)"
        )
    )
    $headerDictionary.add("Authorization", "Basic $Base64cred")

    if ( $extraHeader ) {
        $extraHeader.GetEnumerator() | % {
            write-debug "Adding extra header $($_.Key ) : $($_.Value)"
            $headerDictionary.add($_.Key, $_.Value)
        }
    }
    $FullURI = "$($protocol)://$($server):$($Port)$($URI)"
    write-debug "invoke-nsxwebrequest:- Method: $method, URI: $FullURI, Body: $($body | Format-Xml)"
    #do rest call
    
    try { 
        if (( $method -eq "put" ) -or ( $method -eq "post" )) { 
            $response = invoke-webrequest -method $method -headers $headerDictionary -ContentType "application/xml" -uri $FullURI -body $body
        } else {
            $response = invoke-webrequest -method $method -headers $headerDictionary -ContentType "application/xml" -uri $FullURI
        }
    }
    catch {
        
        #Get response from the exception
        $response = $_.exception.response
        if ($response) {  
            $responseStream = $_.exception.response.GetResponseStream()
            $reader = New-Object system.io.streamreader($responseStream)
            $responseBody = $reader.readtoend()
            $ErrorString = "invoke-nsxwebrequest : Exception occured calling invoke-restmethod. $($response.StatusCode) : $($response.StatusDescription) : Response Body: $($responseBody)"
            throw $ErrorString
        }
        else { 
            throw $_ 
        } 
        

    }
    switch ( $response.content ) {
        { $_ -is [System.String] } { write-debug "invoke-nsxwebrequest:- Response Body: $($response.content), Response Headers: $($response.Headers)" }
        default { write-debug "invoke-nsxwebrequest:- Response type unknown" }

    }
    $response

}

#Export-ModuleMember -Function Invoke-NsxWebRequest

function Add-XmlElement {

    #Internal function used to simplify the exercise of adding XML text Nodes.
    param ( 

        [System.XML.XMLDocument]$xmlDoc,
        [System.XML.XMLElement]$xmlRoot,
        [String]$xmlElementName,
        [String]$xmlElementText
    )


    write-debug "Add-XmlElement: root is $($xmlroot.outerxml)"
    write-debug "Add-XmlElement: Doc is $($xmlDoc.outerxml)"

    #Create an Element and append it to the root
    [System.XML.XMLElement]$xmlNode = $xmlDoc.CreateElement($xmlElementName)
    [System.XML.XMLNode]$xmlText = $xmlDoc.CreateTextNode($xmlElementText)
    $xmlNode.AppendChild($xmlText) | out-null
    $xmlRoot.AppendChild($xmlNode) | out-null
}


##########
##########
# Helper functions

function Format-XML () {

    #Shamelessly ripped from the web, useful for formatting XML output into a form that 
    #is easily read by humans.  Seriously - how is this not part of the dotnet system.xml classes?

    param ( 
        [Parameter (Mandatory=$false,ValueFromPipeline=$true,Position=1) ]
            [xml]$xml="", 
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [int]$indent=2
    ) 

    $StringWriter = New-Object System.IO.StringWriter 
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter 
    $xmlWriter.Formatting = "indented" 
    $xmlWriter.Indentation = $Indent 
    $xml.WriteContentTo($XmlWriter) 
    $XmlWriter.Flush() 
    $StringWriter.Flush() 
    Write-Output $StringWriter.ToString() 

}
Export-ModuleMember -function Format-Xml

##########
##########
# Core functions

function Connect-NsxServer {

    <#
    .SYNOPSIS
    Connects to the specified NSX server and constructs a connection object.

    .DESCRIPTION
    The Connect-NsxServer cmdlet connects to the specified NSX server and 
    retrieves version details.  Because the underlying REST protocol is not 
    connection oriented, the 'Connection' concept relates to just validating 
    endpoint details and credentials and storing some basic information used to 
    reproduce the same outcome during subsequent NSX operations.

    .EXAMPLE
    This example shows how to start an instance 

    PS C:\> Connect-NsxServer -Server nsxserver -username admin -Password 
        VMware1!


    #>

    [CmdletBinding(DefaultParameterSetName="cred")]
 
    param (
        [Parameter (Mandatory=$true,ParameterSetName="cred",Position=1)]
        [Parameter (ParameterSetName="userpass")]
            [ValidateNotNullOrEmpty()]
            [string]$Server,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]
            [ValidateRange(1,65535)]
            [int]$Port=443,
        [Parameter (Mandatory=$true,ParameterSetName="cred")]
            [PSCredential]$Credential,
        [Parameter (Mandatory=$true,ParameterSetName="userpass")]
            [ValidateNotNullOrEmpty()]
            [string]$Username,
        [Parameter (Mandatory=$true,ParameterSetName="userpass")]
            [ValidateNotNullOrEmpty()]
            [string]$Password,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]
            [ValidateNotNullOrEmpty()]
            [bool]$ValidateCertificate=$false,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]
            [ValidateNotNullOrEmpty()]
            [string]$Protocol="https",
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]
            [ValidateNotNullorEmpty()]
            [bool]$DefaultConnection=$true

    )

    if ($PSCmdlet.ParameterSetName -eq "userpass") {      
        $Credential = new-object System.Management.Automation.PSCredential($Username, $(ConvertTo-SecureString $Password -AsPlainText -Force))
    }

    $URI = "/api/1.0/appliance-management/global/info"
    
    #Test NSX connection
    $response = invoke-nsxrestmethod -cred $Credential -server $Server -port $port -protocol $Protocol -method "get" -uri $URI -ValidateCertificate $ValidateCertificate

    $connection = new-object PSCustomObject
    $Connection | add-member -memberType NoteProperty -name "Version" -value "$($response.VersionInfo.majorVersion).$($response.VersionInfo.minorVersion).$($response.VersionInfo.patchVersion)" -force
    $Connection | add-member -memberType NoteProperty -name "BuildNumber" -value "$($response.VersionInfo.BuildNumber)"
    $Connection | add-member -memberType NoteProperty -name "Credential" -value $Credential -force
    $connection | add-member -memberType NoteProperty -name "Server" -value $Server -force
    $connection | add-member -memberType NoteProperty -name "Port" -value $port -force
    $connection | add-member -memberType NoteProperty -name "Protocol" -value $Protocol -force
    $connection | add-member -memberType NoteProperty -name "ValidateCertificate" -value $ValidateCertificate -force

    if ( $defaultConnection) { set-variable -name DefaultNSXConnection -value $connection -scope Global }

    $connection

}
Export-ModuleMember -Function Connect-NsxServer


#########
#########
# L2 related functions

function Get-NsxTransportZone {

    <#
    .SYNOPSIS
    Retrieves a TransportZone object.

    .DESCRIPTION
    Transport Zones are used to control the scope of logical switches within 
    NSX.  A Logical Switch is 'bound' to a transport zone, and only hosts that 
    are members of the Transport Zone are able to host VMs connected to a 
    Logical Switch that is bound to it.  All Logical Switch operations require a
    Transport Zone.
    
    .EXAMPLE
    PS C:\> Get-NsxTransportZone -name TestTZ
    
    #>


    param (
        [Parameter (Mandatory=$false,Position=1)]
        [string]$name

    )

    $URI = "/api/2.0/vdn/scopes"
    $response = invoke-nsxrestmethod -method "get" -uri $URI
    
    if ( $name ) { 
        $response.vdnscopes.vdnscope | ? { $_.name -eq $name }
    } else {
        $response.vdnscopes.vdnscope
    }

}
Export-ModuleMember -Function Get-NsxTransportZone

function Get-NsxLogicalSwitch {


    <#
    .SYNOPSIS
    Retrieves a Logical Switch object

    .DESCRIPTION
    An NSX Logical Switch provides L2 connectivity to VMs attached to it.
    A Logical Switch is 'bound' to a Transport Zone, and only hosts that are 
    members of the Transport Zone are able to host VMs connected to a Logical 
    Switch that is bound to it.  All Logical Switch operations require a 
    Transport Zone.
    
    .EXAMPLE
    
    Example1: Get a named Logical Switch
    PS C:\> Get-NsxTransportZone | Get-NsxLogicalswitch -name LS1
    
    Example2: Get all logical switches in a given transport zone.
    PS C:\> Get-NsxTransportZone | Get-NsxLogicalswitch
    
    #>

    [CmdletBinding(DefaultParameterSetName="vdnscope")]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="vdnscope")]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$vdnScope,
        [Parameter (Mandatory=$false,Position=1)]
            [string]$name,
        [Parameter (Mandatory=$true,ParameterSetName="virtualWire")]
            [ValidateNotNullOrEmpty()]
            [string]$virtualWireId

    )
    
    begin {

    }

    process {
    
        if ( $psCmdlet.ParameterSetName -eq "virtualWire" ) {

            #Just getting a single named Logical Switch
            $URI = "/api/2.0/vdn/virtualwires/$virtualWireId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            $response.virtualWire

        }
        else { 
            
            #Getting all LS in a given VDNScope
            $lspagesize = 10        
            $URI = "/api/2.0/vdn/scopes/$($vdnScope.objectId)/virtualwires?pagesize=$lspagesize&startindex=00"
            $response = invoke-nsxrestmethod -method "get" -uri $URI

            $logicalSwitches = @()

            #LS XML is returned as paged data, means we have to handle it.  
            #May refactor this later, depending on where else I find this in the NSX API (its not really documented in the API guide)
        
            $itemIndex =  0
            $startingIndex = 0 
            $pagingInfo = $response.virtualWires.dataPage.pagingInfo
        
            
            if ( [int]$paginginfo.totalCount -ne 0 ) {
                 write-debug "Get-LogicalSwitch - Logical Switches count non zero"

                do {
                    write-debug "Get-LogicalSwitch - In paging loop. PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"

                    while (($itemindex -lt ([int]$paginginfo.pagesize + $startingIndex)) -and ($itemIndex -lt [int]$paginginfo.totalCount )) {
            
                        write-debug "Get-LogicalSwitch - In Item Processing Loop: ItemIndex: $itemIndex"
                        write-debug "Get-LogicalSwitch - $(@($response.virtualwires.datapage.virtualwire)[($itemIndex - $startingIndex)].objectId)"
                    
                        #Need to wrap the virtualwire prop of the datapage in case we get exactly 1 item - 
                        #which powershell annoyingly unwraps to a single xml element rather than an array...
                        $logicalSwitches += @($response.virtualwires.datapage.virtualwire)[($itemIndex - $startingIndex)]
                        $itemIndex += 1 
                    }  
                    write-debug "Get-Logicalswitch - Out of item processing - PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                    if ( [int]$paginginfo.totalcount -gt $itemIndex) {
                        write-debug "Get-LogicalSwitch - PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                        $startingIndex += $lspagesize
                        $URI = "/api/2.0/vdn/scopes/$($vdnScope.objectId)/virtualwires?pagesize=$lspagesize&startindex=$startingIndex"
                
                        $response = invoke-nsxrestmethod -method "get" -uri $URI
                        $pagingInfo = $response.virtualWires.dataPage.pagingInfo
                    
    
                    } 
                } until ( [int]$paginginfo.totalcount -le $itemIndex )    
                write-debug "Get-LogicalSwitch - Completed page processing: ItemIndex: $itemIndex"

            }

            if ( $name ) { 
                $logicalSwitches | ? { $_.name -eq $name }
            } else {
                $logicalSwitches
            }
        }
    }
    end {

    }

}
Export-ModuleMember -Function Get-NsxLogicalSwitch

function New-NsxLogicalSwitch  {

    <#
    .SYNOPSIS
    Creates a new Logical Switch

    .DESCRIPTION
    An NSX Logical Switch provides L2 connectivity to VMs attached to it.
    A Logical Switch is 'bound' to a Transport Zone, and only hosts that are 
    members of the Transport Zone are able to host VMs connected to a Logical 
    Switch that is bound to it.  All Logical Switch operations require a 
    Transport Zone.  A new Logical Switch defaults to the control plane mode of 
    the Transport Zone it is created in, but CP mode can specified as required.

    .EXAMPLE

    Example1: Create a Logical Switch with default control plane mode.
    PS C:\> Get-NsxTransportZone | New-NsxLogicalSwitch -name LS6 

    Example2: Create a Logical Switch with a specific control plane mode.
    PS C:\> Get-NsxTransportZone | New-NsxLogicalSwitch -name LS6 
        -ControlPlaneMode MULTICAST_MODE
    
    #>


    [CmdletBinding()]
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateNotNullOrEmpty()]
            [System.XML.XMLElement]$vdnScope,
        [Parameter (Mandatory=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$Description = "",
        [Parameter (Mandatory=$false)]
            [string]$TenantId = "",
        [Parameter (Mandatory=$false)]
            [ValidateSet("UNICAST_MODE","MULTICAST_MODE","HYBRID_MODE")]
            [string]$ControlPlaneMode
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("virtualWireCreateSpec")
        $xmlDoc.appendChild($xmlRoot) | out-null


        #Create an Element and append it to the root
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "tenantId" -xmlElementText $TenantId
        if ( $ControlPlaneMode ) { Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "controlPlaneMode" -xmlElementText $ControlPlaneMode } 
           
        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/vdn/scopes/$($vdnscope.objectId)/virtualwires"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body

        #response only contains the vwire id, we have to query for it to get output consisten with get-nsxlogicalswitch
        Get-NsxLogicalSwitch -virtualWireId $response
    }
    end {}
}
Export-ModuleMember -Function New-NsxLogicalSwitch

function Remove-NsxLogicalSwitch {

    <#
    .SYNOPSIS
    Removes a Logical Switch

    .DESCRIPTION
    An NSX Logical Switch provides L2 connectivity to VMs attached to it.
    A Logical Switch is 'bound' to a Transport Zone, and only hosts that are 
    members of the Transport Zone are able to host VMs connected to a Logical 
    Switch that is bound to it.  All Logical Switch operations require a 
    Transport Zone.

    .EXAMPLE

    Example1: Remove a Logical Switch
    PS C:\> Get-NsxTransportZone | Get-NsxLogicalSwitch LS6 | 
        Remove-NsxLogicalSwitch 

    Example2: Remove a Logical Switch without confirmation. 
    PS C:\> Get-NsxTransportZone | Get-NsxLogicalSwitch LS6 | 
        Remove-NsxLogicalSwitch -confirm:$false
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$virtualWire,
        [Parameter (Mandatory=$False)]
            [switch]$confirm=$true

    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Logical Switch removal is permanent."
            $question = "Proceed with removal of Logical Switch $($virtualWire.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/2.0/vdn/virtualwires/$($virtualWire.ObjectId)"
            Write-Progress -activity "Remove Logical Switch $($virtualWire.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI | out-null
            write-progress -activity "Remove Logical Switch $($virtualWire.Name)" -completed

        }
    }

    end {}

}
Export-ModuleMember -Function Remove-NsxLogicalSwitch

#########
######### 
# Distributed Router functions



function New-NsxLogicalRouterVnicSpec {

    <#
    .SYNOPSIS
    Creates a new NSX Logical Router vNic Spec.

    .DESCRIPTION
    NSX Logical Routers can host up to 1000 vNics, each of which can be 
    configured with multiple properties.  In order to allow creation of Logical 
    Routers with an arbitrary number of vNics, a unique spec for each vNic 
    required must first be created.

    Logical Routers do support interfaces on VLAN backed portgroups, and this 
    cmdlet will support a vNic spec connected to a normal portgroup, however 
    this is not noramlly a recommended scenario.
    
    .EXAMPLE

    PS C:\> $Uplink = New-NsxLogicalRouterVnicSpec -Name Uplink_vNic -Type 
        uplink -ConnectedTo (Get-NsxTransportZone | Get-NsxLogicalSwitch LS1) 
        -PrimaryAddress 192.168.0.1 -SubnetPrefixLength 24

    PS C:\> $Internal = New-NsxLogicalRouterVnicSpec -Name Internal-vNic -Type 
        internal -ConnectedTo (Get-NsxTransportZone | Get-NsxLogicalSwitch LS2) 
        -PrimaryAddress 10.0.0.1 -SubnetPrefixLength 24
    
    #>


     param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateSet ("internal","uplink")]
            [string]$Type,
        [Parameter (Mandatory=$true)]
            [ValidateScript({
                if (-not (
                    ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl] ) -or
                    ($_ -is [VMware.VimAutomation.Vds.Impl.VDObjectImpl] ) -or
                    ($_ -is [System.Xml.XmlElement] )))
                { 
                    throw "Must specify a distributed port group or a logical switch" 
                } else {

                    #Check if we have an ID property
                    if ($_ -is [System.Xml.XmlElement] ) {
                        if ( -not ( $_ | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an objectId property."}
                        if ( -not ( $_ | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                        
                        switch ($_.objectTypeName) {
                            "VirtualWire" {}
                            default { throw "Specified value is not a supported type.  Specify a Distributed PortGroup or Logical Switch object." }
                        }
                    }   
                }
                $true
            })]
            [object]$ConnectedTo,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,9128)]
            [int]$MTU=1500,       
        # [Parameter (Mandatory=$false)]
        #     [ValidateNotNullOrEmpty()]
        #     [switch]$EnableProxyArp=$false,       
        # [Parameter (Mandatory=$false)]
        #     [ValidateNotNullOrEmpty()]
        #     [switch]$EnableSendICMPRedirects=$true,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Connected=$true 


    )

    begin {}
    process { 

        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlVnic = $XMLDoc.CreateElement("interface")
        $xmlDoc.appendChild($xmlVnic) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "type" -xmlElementText $type 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "mtu" -xmlElementText $MTU 
        # Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "enableProxyArp" -xmlElementText $EnableProxyArp 
        # Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "enableSendRedirects" -xmlElementText $EnableSendICMPRedirects 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "isConnected" -xmlElementText $Connected


        switch ($ConnectedTo){

            { ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl]) -or ( $_ -is [VMware.VimAutomation.Vds.Impl.VDObjectImpl] ) }  { $PortGroupID = $_.ExtensionData.MoRef.Value }
            { $_ -is [System.Xml.XmlElement]} { $PortGroupID = $_.objectId }

        }  

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "connectedToId" -xmlElementText $PortGroupID
        
        #For now, only supporting one addressgroup - will refactor later
        [System.XML.XMLElement]$xmlAddressGroups = $XMLDoc.CreateElement("addressGroups")
        $xmlVnic.appendChild($xmlAddressGroups) | out-null
        New-NsxEdgeVnicAddressGroup -xmldoc $xmlDoc -xmlAddressGroups $xmlAddressGroups -PrimaryAddress $PrimaryAddress -SubnetPrefixLength $SubnetPrefixLength
        
        $xmlVnic
    }

    end {}
}
Export-ModuleMember -Function New-NsxLogicalRouterVnicSpec


function Get-NsxLogicalRouter {

    <#
    .SYNOPSIS
    Retrieves a Logical Router object.
    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    This cmdlet returns Logical Router objects.
    
    .EXAMPLE
    PS C:\> Get-NsxLogicalRouter LR1

    #>
    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ParameterSetName="objectId")]
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name

    )

    $pagesize = 10         
    switch ( $psCmdlet.ParameterSetName ) {

        "Name" { 
            $URI = "/api/4.0/edges?pageSize=$pagesize&startIndex=00" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            
            #Edge summary XML is returned as paged data, means we have to handle it.  
            #Then we have to query for full information on a per edge basis.
            $edgesummaries = @()
            $edges = @()
            $itemIndex =  0
            $startingIndex = 0 
            $pagingInfo = $response.pagedEdgeList.edgePage.pagingInfo
            
            if ( [int]$paginginfo.totalCount -ne 0 ) {
                 write-debug "Get-LogicalRouter - Logical Router count non zero"

                do {
                    write-debug "Get-LogicalRouter - In paging loop. PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"

                    while (($itemindex -lt ([int]$paginginfo.pagesize + $startingIndex)) -and ($itemIndex -lt [int]$paginginfo.totalCount )) {
            
                        write-debug "Get-LogicalRouter - In Item Processing Loop: ItemIndex: $itemIndex"
                        write-debug "Get-LogicalRouter - $(@($response.pagedEdgeList.edgePage.edgeSummary)[($itemIndex - $startingIndex)].objectId)"
                    
                        #Need to wrap the edgesummary prop of the datapage in case we get exactly 1 item - 
                        #which powershell annoyingly unwraps to a single xml element rather than an array...
                        $edgesummaries += @($response.pagedEdgeList.edgePage.edgeSummary)[($itemIndex - $startingIndex)]
                        $itemIndex += 1 
                    }  
                    write-debug "Get-LogicalRouter - Out of item processing - PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                    if ( [int]$paginginfo.totalcount -gt $itemIndex) {
                        write-debug "Get-LogicalRouter - PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                        $startingIndex += $pagesize
                        $URI = "/api/4.0/edges?pageSize=$pagesize&startIndex=$startingIndex"
                
                        $response = invoke-nsxrestmethod -method "get" -uri $URI
                        $pagingInfo = $response.pagedEdgeList.edgePage.pagingInfo
                    

                    } 
                } until ( [int]$paginginfo.totalcount -le $itemIndex )    
                write-debug "Get-LogicalRouter - Completed page processing: ItemIndex: $itemIndex"
            }

            #What we got here is...failure to communicate!  In order to get full detail, we have to requery for each edgeid.
            #But... there is information in the SUmmary that isnt in the full detail.  So Ive decided to add the summary as a node 
            #to the returned edge detail. 

            foreach ($edgesummary in $edgesummaries) {

                $URI = "/api/4.0/edges/$($edgesummary.objectID)" 
                $response = invoke-nsxrestmethod -method "get" -uri $URI
                $import = $response.edge.ownerDocument.ImportNode($edgesummary, $true)
                $response.edge.appendChild($import) | out-null                
                $edges += $response.edge

            }

            if ( $name ) { 
                $edges | ? { $_.Type -eq 'distributedRouter' } | ? { $_.name -eq $name }

            } else {
                $edges | ? { $_.Type -eq 'distributedRouter' }

            }

        }

        "objectId" { 

            $URI = "/api/4.0/edges/$objectId" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            $edge = $response.edge
            $URI = "/api/4.0/edges/$objectId/summary" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            $import = $edge.ownerDocument.ImportNode($($response.edgeSummary), $true)
            $edge.AppendChild($import) | out-null
            $edge

        }
    }

}
Export-ModuleMember -Function Get-NsxLogicalRouter

function New-NsxLogicalRouter {

    <#
    .SYNOPSIS
    Creates a new Logical Router object.
    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    This cmdlet creates a new Logical Router.  A Logical router has many 
    configuration options - not all are exposed with New-NsxLogicalRouter.  
    Use Update-NsxLogicalRouter for other configuration.

    Interface configuration is handled by passing vNic spec objects created by 
    the New-NsxLogicalRouterVnicSpec cmdlet.

    A valid PowerCLI session is required to pass required objects as required by 
    cluster/resourcepool and datastore parameters.
    
    .EXAMPLE
    
    Create a new LR with interfaces on existsing Logical switches (LS1,2,3 and 
    Management interface on Mgmt)

    PS C:\> $ls1 = get-nsxtransportzone | get-nsxlogicalswitch LS1

    PS C:\> $ls2 = get-nsxtransportzone | get-nsxlogicalswitch LS2

    PS C:\> $ls3 = get-nsxtransportzone | get-nsxlogicalswitch LS3

    PS C:\> $mgt = get-nsxtransportzone | get-nsxlogicalswitch Mgmt

    PS C:\> $vnic0 = New-NsxLogicalRouterVnicSpec -Type uplink -Name vNic0 
        -ConnectedTo $ls1 -PrimaryAddress 1.1.1.1 -SubnetPrefixLength 24

    PS C:\> $vnic1 = New-NsxLogicalRouterVnicSpec -Type internal -Name vNic1 
        -ConnectedTo $ls2 -PrimaryAddress 2.2.2.1 -SubnetPrefixLength 24

    PS C:\> $vnic2 = New-NsxLogicalRouterVnicSpec -Type internal -Name vNic2 
        -ConnectedTo $ls3 -PrimaryAddress 3.3.3.1 -SubnetPrefixLength 24

    PS C:\> New-NsxLogicalRouter -Name testlr -ManagementPortGroup $mgt 
        -Vnic $vnic0,$vnic1,$vnic2 -Cluster (Get-Cluster) 
        -Datastore (get-datastore)

    #>

    param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateScript({
                if (-not (
                    ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl] ) -or
                    ($_ -is [System.Xml.XmlElement] )))
                { 
                    throw "Must specify a distributed port group or a logical switch" 
                } else {

                    #Check if we have an ID property
                    if ($_ -is [System.Xml.XmlElement] ) {
                        if ( -not ( $_ | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an objectId property."}
                        if ( -not ( $_ | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                        
                        switch ($_.objectTypeName) {
                            "VirtualWire" {}
                            default { throw "Specified value is not a supported type.  Specify a Distributed PortGroup or Logical Switch object." }
                        }
                    }   
                }
                $true
            })]
            [object]$ManagementPortGroup,
        [Parameter (Mandatory=$true)]
            [ValidateScript({

                #temporary - need to script proper validation of a single valid NIC config for DLR (Edge and DLR have different specs :())
                if ( -not $_ ) { 
                    throw "Specify at least one vNIC configuration as produced by New-NsxLogicalRouterVnicSpec.  Pass a collection of vNIC objects to configure more than one vNIC"
                }
                $true
            })]
            [System.Xml.XmlElement[]]$Vnic,       
        [Parameter (Mandatory=$true,ParameterSetName="ResourcePool")]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ResourcePoolImpl]$ResourcePool,
        [Parameter (Mandatory=$true,ParameterSetName="Cluster")]
            [ValidateScript({
                if ( $_ -eq $null ) { throw "Must specify Cluster."}
                if ( -not $_.DrsEnabled ) { throw "Cluster is not DRS enabled."}
                $true
            })]
            [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl]$Cluster,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.DatastoreImpl]$Datastore,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableHA=$false,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.DatastoreImpl]$HADatastore=$datastore

    )


    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("edge")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "type" -xmlElementText "distributedRouter"

        switch ($ManagementPortGroup){

            { $_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl] }  { $PortGroupID = $_.ExtensionData.MoRef.Value }
            { $_ -is [System.Xml.XmlElement]} { $PortGroupID = $_.objectId }

        }

        [System.XML.XMLElement]$xmlMgmtIf = $XMLDoc.CreateElement("mgmtInterface")
        $xmlRoot.appendChild($xmlMgmtIf) | out-null
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMgmtIf -xmlElementName "connectedToId" -xmlElementText $PortGroupID

        [System.XML.XMLElement]$xmlAppliances = $XMLDoc.CreateElement("appliances")
        $xmlRoot.appendChild($xmlAppliances) | out-null
        
        switch ($psCmdlet.ParameterSetName){

            "Cluster"  { $ResPoolId = $($cluster | get-resourcepool | ? { $_.parent.id -eq $cluster.id }).extensiondata.moref.value }
            "ResourcePool"  { $ResPoolId = $ResourcePool.extensiondata.moref.value }

        }

        [System.XML.XMLElement]$xmlAppliance = $XMLDoc.CreateElement("appliance")
        $xmlAppliances.appendChild($xmlAppliance) | out-null
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "resourcePoolId" -xmlElementText $ResPoolId
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "datastoreId" -xmlElementText $datastore.extensiondata.moref.value

        if ( $EnableHA ) {
            [System.XML.XMLElement]$xmlAppliance = $XMLDoc.CreateElement("appliance")
            $xmlAppliances.appendChild($xmlAppliance) | out-null
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "resourcePoolId" -xmlElementText $ResPoolId
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "datastoreId" -xmlElementText $HAdatastore.extensiondata.moref.value
               
        }

        [System.XML.XMLElement]$xmlVnics = $XMLDoc.CreateElement("interfaces")
        $xmlRoot.appendChild($xmlVnics) | out-null
        foreach ( $VnicSpec in $Vnic ) {

            $import = $xmlDoc.ImportNode(($VnicSpec), $true)
            $xmlVnics.AppendChild($import) | out-null

        }

        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/4.0/edges"
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body
        $edgeId = $response.Headers.Location.split("/")[$response.Headers.Location.split("/").GetUpperBound(0)] 

        if ( $EnableHA ) {
            
            [System.XML.XMLElement]$xmlHA = $XMLDoc.CreateElement("highAvailability")
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlHA -xmlElementName "enabled" -xmlElementText "true"
            $body = $xmlHA.OuterXml
            $URI = "/api/4.0/edges/$edgeId/highavailability/config"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body
            
        }
        Get-NsxLogicalRouter -objectID $edgeId

    }
    end {}
 

}
Export-ModuleMember -Function New-NsxLogicalRouter

function Remove-NsxLogicalRouter {

    <#
    .SYNOPSIS
    Deletes a Logical Router object.
    
    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    This cmdlet deletes the specified Logical Router object.
    
    .EXAMPLE
    
    Example1: Remove Logical Router LR1.
    PS C:\> Get-NsxLogicalRouter LR1 | Remove-NsxLogicalRouter

    Example2: No confirmation on delete.
    PS C:\> Get-NsxLogicalRouter LR1 | Remove-NsxLogicalRouter -confirm:$false
    
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if we have an ID property
                if ($_ -is [System.Xml.XmlElement] ) {
                    if ( $_ | get-member -name edgeSummary -memberType Properties) { 
                        if ( -not ( $_.edgeSummary | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.objectId property."}
                        if ( -not ( $_.edgeSummary | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.ObjectTypeName property."}
                        if ( -not ( $_.edgeSummary | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.name property."}
                        if ( -not ( $_ | get-member -name type -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ($_.edgeSummary.objectTypeName -ne "Edge" ) { throw "Specified value is not a supported type.  Specify an NSX Distributed Router." }
                        if ($_.type -ne "distributedRouter" ) { throw "Specified value is not a supported type.  Specify an NSX Distributed Router." }
                    }   
                }
                $true
            })]
            [System.Xml.XmlElement]$LogicalRouter,
        [Parameter (Mandatory=$False)]
            [switch]$confirm=$true

    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Logical Router removal is permanent."
            $question = "Proceed with removal of Logical Router $($LogicalRouter.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/4.0/edges/$($LogicalRouter.Edgesummary.ObjectId)"
            Write-Progress -activity "Remove Logical Router $($LogicalRouter.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI | out-null
            write-progress -activity "Remove Logical Router $($LogicalRouter.Name)" -completed

        }
    }

    end {}

}
Export-ModuleMember -Function Remove-NsxLogicalRouter

#########
#########
# Grouping related Collections

function Get-NsxSecurityGroup {

    <#
    .SYNOPSIS
    Retrieves NSX Security Groups

    .DESCRIPTION
    An NSX Security Group is a grouping construct that provides a powerful
    grouping function that can be used in DFW Firewall Rules and the NSX
    Service Composer.

    This cmdlet returns Security Groups objects.

    .EXAMPLE
    PS C:\> Get-NsxSecurityGroup TestSG

    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$false,ParameterSetName="objectId")]
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$name,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0"

    )
    
    begin {

    }

    process {
     
        if ( -not $objectId ) { 
            #All Security GRoups
            $URI = "/api/2.0/services/securitygroup/scope/$scopeId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            if  ( $Name  ) { 
                $response.list.securitygroup | ? { $_.name -eq $name }
            } else {
                $response.list.securitygroup
            }

        }
        else {

            #Just getting a single Security group
            $URI = "/api/2.0/services/securitygroup/$objectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            $response.securitygroup 
        }
    }

    end {}

}
Export-ModuleMember -Function Get-NsxSecurityGroup

function New-NsxSecurityGroup  {

    <#
    .SYNOPSIS
    Creates a new NSX Security Group.

    .DESCRIPTION
    An NSX Security Group is a grouping construct that provides a powerful
    grouping function that can be used in DFW Firewall Rules and the NSX
    Service Composer.

    This cmdlet creates a new NSX Security Group.

    A Security Group can consist of Static Includes and Excludes as well as 
    dynamic matching properties.  At this time, this cmdlet supports only static 
    include/exclude members.

    A valid PowerCLI session is required to pass certain types of objects 
    supported by the IncludeMember and ExcludeMember parameters.
    

    .EXAMPLE

    Example1: Create a new SG and include App01 and App02 VMs (get-vm requires a
    valid PowerCLI session)

    PS C:\> New-NsxSecurityGroup -Name TestSG -Description "Test creating an NSX
     SecurityGroup" -IncludeMember (get-vm app01),(get-vm app02)

    Example2: Create a new SG and include cluster1 except for App01 and App02 
    VMs (get-vm and get-cluster requires a valid PowerCLI session)

    PS C:\> New-NsxSecurityGroup -Name TestSG -Description "Test creating an NSX
     SecurityGroup" -IncludeMember (get-cluster cluster1) 
        -ExcludeMember (get-vm app01),(get-vm app02)
    #>

    [CmdletBinding()]
    param (

        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$Description = "",
        [Parameter (Mandatory=$false)]
            [ValidateScript({
                #Check types first - This is not 100% complete at this point!
                if (-not (
                     ($_ -is [System.Xml.XmlElement]) -or 
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.DatacenterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ResourcePoolImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.NetworkAdapter] ))) {

                        throw "Source is not a supported type.  Specify a Datacenter, Cluster, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object."
                         
                } else {

                    #Check if we have an ID property
                    if ($_ -is [System.Xml.XmlElement] ) {
                        if ( -not ( $_ | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an objectId property."}
                        if ( -not ( $_ | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                        
                       
                        switch ($_.objectTypeName) {

                            "IPSet"{}
                            "SecurityGroup" {}
                            "VirtualWire" {}
                            default { throw "Source is not a supported type.  Specify a Datacenter, Cluster, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object." }
                            
                        }
                    }   
                }
                $true
            })]
            [object[]]$IncludeMember,
            [Parameter (Mandatory=$false)]
            [ValidateScript({
                #Check types first - This is not 100% complete at this point!
                if (-not (
                     ($_ -is [System.Xml.XmlElement]) -or 
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.DatacenterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ResourcePoolImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.NetworkAdapter] ))) {

                        throw "Source is not a supported type.  Specify a Datacenter, Cluster, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object."
                         
                } else {

                    #Check if we have an ID property
                    if ($_ -is [System.Xml.XmlElement] ) {
                        if ( -not ( $_ | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an objectId property."}
                        if ( -not ( $_ | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                        
                       
                        switch ($_.objectTypeName) {

                            "IPSet"{}
                            "SecurityGroup" {}
                            "VirtualWire" {}
                            default { throw "Source is not a supported type.  Specify a Datacenter, Cluster, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object." }
                            
                        }
                    }   
                }
                $true
            })]
            [object[]]$ExcludeMember,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0"
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("securitygroup")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        if ( $includeMember ) { 
        
            foreach ( $Member in $IncludeMember) { 

                [System.XML.XMLElement]$xmlMember = $XMLDoc.CreateElement("member")
                $xmlroot.appendChild($xmlMember) | out-null

                #This is probably not safe - need to review all possible input types to confirm.
                if ($Member -is [System.Xml.XmlElement] ) {
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "objectId" -xmlElementText $member.objectId
                } else { 
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "objectId" -xmlElementText $member.ExtensionData.MoRef.Value
                }
            }
        }   

        if ( $excludeMember ) { 
        
            foreach ( $Member in $ExcludeMember) { 

                [System.XML.XMLElement]$xmlMember = $XMLDoc.CreateElement("excludeMember")
                $xmlroot.appendChild($xmlMember) | out-null

                #This is probably not safe - need to review all possible input types to confirm.
                if ($Member -is [System.Xml.XmlElement] ) {
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "objectId" -xmlElementText $member.objectId
                } else { 
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "objectId" -xmlElementText $member.ExtensionData.MoRef.Value
                }
            }
        }   

        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/services/securitygroup/bulk/$scopeId"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body

        Get-NsxSecuritygroup -objectId $response
    }
    end {}

}
Export-ModuleMember -Function New-NsxSecurityGroup

function Remove-NsxSecurityGroup {

    <#
    .SYNOPSIS
    Removes the specified NSX Security Group.

    .DESCRIPTION
    An NSX Security Group is a grouping construct that provides a powerful
    grouping function that can be used in DFW Firewall Rules and the NSX
    Service Composer.

    This cmdlet deletes a specified Security Groups object.  If the object 
    is currently in use the api will return an error.  Use -force to override
    but be aware that the firewall rulebase will become invalid and will need
    to be corrected before publish operations will succeed again.

    .EXAMPLE
    Example1: Remove the SecurityGroup TestSG
    PS C:\> Get-NsxSecurityGroup TestSG | Remove-NsxSecurityGroup

    Example2: Remove the SecurityGroup $sg without confirmation.
    PS C:\> $sg | Remove-NsxSecurityGroup -confirm:$false

    
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$SecurityGroup,
        [Parameter (Mandatory=$False)]
            [switch]$confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false


    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Security Group removal is permanent."
            $question = "Proceed with removal of Security group $($SecurityGroup.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            if ( $force ) { 
                $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.objectId)?force=true"
            }
            else {
                $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.ObjectId)?force=false"
            }
            
            Write-Progress -activity "Remove Security Group $($SecurityGroup.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI | out-null
            write-progress -activity "Remove Security Group $($SecurityGroup.Name)" -completed

        }
    }

    end {}

}
Export-ModuleMember -Function Remove-NsxSecurityGroup

function Get-NsxIPSet {

    <#
    .SYNOPSIS
    Retrieves NSX IPSets

    .DESCRIPTION
    An NSX IPSet is a grouping construct that allows for grouping of
    IP adresses, ranges and/or subnets in a sigle container that can 
    be used either in DFW Firewall Rules or as members of a security 
    group.

    This cmdlet returns IP Set objects.

    .EXAMPLE
    PS C:\> Get-NSXIpSet TestIPSet

    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$false,ParameterSetName="objectId")]
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0"

    )
    
    begin {

    }

    process {
     
        if ( -not $objectID ) { 
            #All IPSets
            $URI = "/api/2.0/services/ipset/scope/$scopeId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            if ( $name ) {
                $response.list.ipset | ? { $_.name -eq $name }
            } else {
                $response.list.ipset
            }
        }
        else {

            #Just getting a single named Security group
            $URI = "/api/2.0/services/ipset/$objectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            $response.ipset
        }
    }

    end {}

}
Export-ModuleMember -Function Get-NsxIPSet

function New-NsxIPSet  {
    <#
    .SYNOPSIS
    Creates a new NSX IPSet.

    .DESCRIPTION
    An NSX IPSet is a grouping construct that allows for grouping of
    IP adresses, ranges and/or subnets in a sigle container that can 
    be used either in DFW Firewall Rules or as members of a security 
    group.

    This cmdlet creates a new IP Set with the specified parameters.

    IPAddresses is a string that can contain 1 or more of the following
    separated by commas
    IP address: (eg, 1.2.3.4)
    IP Range: (eg, 1.2.3.4-1.2.3.10)
    IP Subnet (eg, 1.2.3.0/24)


    .EXAMPLE
    PS C:\> New-NsxIPSet -Name TestIPSet -Description "Testing IP Set Creation" 
        -IPAddresses "1.2.3.4,1.2.3.0/24"

    #>

    [CmdletBinding()]
    param (

        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$Description = "",
        [Parameter (Mandatory=$false)]
            [string]$IPAddresses,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0"
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("ipset")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        if ( $IPAddresses ) {
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "value" -xmlElementText $IPaddresses
        }
           
        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/services/ipset/$scopeId"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body

        Get-NsxIPSet -objectid $response
    }
    end {}

}
Export-ModuleMember -Function New-NsxIPSet

function Remove-NsxIPSet {

    <#
    .SYNOPSIS
    Removes the specified NSX IPSet.

    .DESCRIPTION
    An NSX IPSet is a grouping construct that allows for grouping of
    IP adresses, ranges and/or subnets in a sigle container that can 
    be used either in DFW Firewall Rules or as members of a security 
    group.

    This cmdlet removes the specified IP Set. If the object 
    is currently in use the api will return an error.  Use -force to override
    but be aware that the firewall rulebase will become invalid and will need
    to be corrected before publish operations will succeed again.

    .EXAMPLE
    PS C:\> Get-NsxIPSet TestIPSet | Remove-NsxIPSet

    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$IPSet,
        [Parameter (Mandatory=$False)]
            [switch]$confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false


    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "IPSet removal is permanent."
            $question = "Proceed with removal of IP Set $($IPSet.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            if ( $force ) { 
                $URI = "/api/2.0/services/ipset/$($IPSet.objectId)?force=true"
            }
            else {
                $URI = "/api/2.0/services/ipset/$($IPSet.objectId)?force=false"
            }
            
            Write-Progress -activity "Remove IP Set $($IPSet.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI | out-null
            write-progress -activity "Remove IP Set $($IPSet.Name)" -completed

        }
    }

    end {}

}
Export-ModuleMember -Function Remove-NsxIPSet

function Get-NsxService {

    <#
    .SYNOPSIS
    Retrieves NSX Services (aka Applications).

    .DESCRIPTION
    An NSX Service defines a service as configured in the NSX Distributed
    Firewall.  

    This cmdlet retrieves existing services as defined within NSX.

    It also supports searching for services by TCP/UDP port number and will
    locate services that contain the specified port within a range definition
    as well as those explicitly configured with the given port.

    .EXAMPLE
    Example1: Get Service by name
    PS C:\> Get-NsxService -Name TestService 

    Example2: Get Service by port (will match services that include the 
    specified port within a range as well as those explicitly configured with 
    the given port.)
    PS C:\> Get-NsxService -port 1234

    #>    
    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$false,ParameterSetName="objectId")]
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name,
        [Parameter (Mandatory=$false,ParameterSetName="Port",Position=1)]
            [int]$Port,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0"

    )
    
    begin {

    }

    process {

        switch ( $PSCmdlet.ParameterSetName ) {

            "objectId" {

                  #Just getting a single named service group
                $URI = "/api/2.0/services/application/$objectId"
                $response = invoke-nsxrestmethod -method "get" -uri $URI
                $response.application
            }

            "Name" { 
                #All Services
                $URI = "/api/2.0/services/application/scope/$scopeId"
                $response = invoke-nsxrestmethod -method "get" -uri $URI
                if  ( $name ) { 
                    $response.list.application | ? { $_.name -eq $name }
                } else {
                    $response.list.application
                }
            }

            "Port" {

                # Service by port

                $URI = "/api/2.0/services/application/scope/$scopeId"
                $response = invoke-nsxrestmethod -method "get" -uri $URI
                foreach ( $application in $response.list.application ) {

                    if ( $application | get-member -memberType Properties -name element ) {
                        write-debug "Testing service $($application.name) with ports: $($application.element.value)"

                        #The port configured on a service is stored in element.value and can be
                        #either an int, range (expressed as inta-intb, or a comma separated list of ints and/or ranges
                        #So we split the value on comma, the replace the - with .. in a range, and wrap parentheses arount it
                        #Then, lean on PoSH native range handling to force the lot into an int array... 
                        
                        switch -regex ( $application.element.value ) {

                            "^[\d,-]+$" { 

                                [string[]]$valarray = $application.element.value.split(",") 
                                $valarray | % { 

                                    write-debug "Converting range expression and expanding: $_"  
                                    [int[]]$ports = invoke-expression ( $_ -replace '^(\d+)-(\d+)$','($1..$2)' ) 
                                    #Then test if the port int array contains what we are looking for...
                                    if ( $ports.contains($port) ) { 
                                        write-debug "Matched Service $($Application.name)"
                                        $application
                                        break
                                    }
                                }
                            }

                            default { #do nothing, port number is not numeric.... 
                                write-debug "Ignoring $($application.name) - non numeric element: $($application.element.applicationProtocol) : $($application.element.value)"
                            }
                        }
                    }
                    else {
                        write-debug "Ignoring $($application.name) - element not defined"                           
                    }
                }
            }
        }
    }

    end {}

}

Export-ModuleMember -Function Get-NsxService

function New-NsxService  {

    <#
    .SYNOPSIS
    Creates a new NSX Service (aka Application).

    .DESCRIPTION
    An NSX Service defines a service as configured in the NSX Distributed
    Firewall.  

    This cmdlet creates a new service of the specified configuration.

    .EXAMPLE
    PS C:\> New-NsxService -Name TestService -Description "Test creation of a 
     service" -Protocol TCP -port 1234

    #>    

    [CmdletBinding()]
    param (

        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$Description = "",
        [Parameter (Mandatory=$true)]
            [ValidateSet ("TCP","UDP",
            "ORACLE_TNS","FTP","SUN_RPC_TCP",
            "SUN_RPC_UDP","MS_RPC_TCP",
            "MS_RPC_UDP","NBNS_BROADCAST",
            "NBDG_BROADCAST")]
            [string]$Protocol,
        [Parameter (Mandatory=$true)]
            [ValidateScript({
                if ( ($Protocol -eq "TCP" ) -or ( $protocol -eq "UDP")) { 
                    if ( $_ -match "^[\d,-]+$" ) { $true } else { throw "TCP or UDP port numbers must be either an integer, range (nn-nn) or commma separated integers or ranges." }
                } else {
                    #test we can cast to int
                    if ( ($_ -as [int]) -and ( (1..65535) -contains $_) ) { 
                        $true 
                    } else { 
                        throw "Non TCP or UDP port numbers must be a single integer between 1-65535."
                    }
                }
            })]
            [string]$port,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0"
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("application")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        
        #Create the 'element' element ??? :)
        [System.XML.XMLElement]$xmlElement = $XMLDoc.CreateElement("element")
        $xmlRoot.appendChild($xmlElement) | out-null
        
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlElement -xmlElementName "applicationProtocol" -xmlElementText $Protocol
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlElement -xmlElementName "value" -xmlElementText $Port
           
        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/services/application/$scopeId"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body

        Get-NsxService $response
    }
    end {}

}
Export-ModuleMember -Function New-NsxService

function Remove-NsxService {

    <#
    .SYNOPSIS
    Removes the specified NSX Service (aka Application).

    .DESCRIPTION
    An NSX Service defines a service as configured in the NSX Distributed
    Firewall.  

    This cmdlet removes the NSX service specified.

    .EXAMPLE
    PS C:\> New-NsxService -Name TestService -Description "Test creation of a
     service" -Protocol TCP -port 1234

    #>    
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$Service,
        [Parameter (Mandatory=$False)]
            [switch]$confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false
    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Service removal is permanent."
            $question = "Proceed with removal of Service $($Service.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            if ( $force ) { 
                $URI = "/api/2.0/services/application/$($Service.objectId)?force=true"
            }
            else {
                $URI = "/api/2.0/services/application/$($Service.objectId)?force=false"
            }
            
            Write-Progress -activity "Remove Service $($Service.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI | out-null
            write-progress -activity "Remove Service $($Service.Name)" -completed

        }
    }

    end {}

}
Export-ModuleMember -Function Remove-NsxService

#########
#########
# Firewall related functions

###Private functions

function New-NsxSourceDestNode {

    #Internal function - Handles building the source/dest xml node for a given object.

    param (

        [Parameter (Mandatory=$true)]
        [ValidateSet ("source","destination")]
        [string]$itemType,
        [object[]]$itemlist,
        [System.XML.XMLDocument]$xmlDoc,
        [switch]$negateItem

    )

    #The excluded attribute indicates source/dest negation
    $xmlAttrNegated = $xmlDoc.createAttribute("excluded")
    if ( $negateItem ) { 
        $xmlAttrNegated.value = "true"
    } else { 
        $xmlAttrNegated.value = "false"
    }

    #Create return element and append negation attribute.
    if ( $itemType -eq "Source" ) { [System.XML.XMLElement]$xmlReturn = $XMLDoc.CreateElement("sources") }
    if ( $itemType -eq "Destination" ) { [System.XML.XMLElement]$xmlReturn = $XMLDoc.CreateElement("destinations") }
    $xmlReturn.Attributes.Append($xmlAttrNegated) | out-null

    foreach ($item in $itemlist) {
        write-debug "Building source/dest node for $($item.name)"
        #Build the return XML element
        [System.XML.XMLElement]$xmlItem = $XMLDoc.CreateElement($itemType)

        if ( $item -is [system.xml.xmlelement] ) {

            write-debug "Object $($item.name) is specified as xml element"
            #XML representation of NSX object passed - ipset, sec group or logical switch
            #get appropritate name, value.
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText $item.objectId
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText $item.name
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText $item.objectTypeName
            
        } else {

            write-debug "Object $($item.name) is specified as supported powercli object"
            #Proper PowerCLI Object passed
            #If passed object is a NIC, we have to do some more digging
            if (  $item -is [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.NetworkAdapter] ) {
                   
                write-debug "Object $($item.name) is vNic"
                #Naming based on DFW UI standard
                Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText "$($item.parent.name) - $($item.name)"
                Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText "Vnic"

                #Getting the NIC identifier is a bit of hackery at the moment, if anyone can show me a more deterministic or simpler way, then im all ears. 
                $nicIndex = [array]::indexof($item.parent.NetworkAdapters.name,$item.name)
                if ( -not ($nicIndex -eq -1 )) { 
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText "$($item.parent.PersistentId).00$nicINdex"
                } else {
                    throw "Unable to determine nic index in parent object.  Make sure the NIC object is valid"
                }
            }
            else {
                #any other accepted PowerCLI object, we just need to grab details from the moref.
                Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText $item.name
                Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText $item.extensiondata.moref.type
                Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText $item.extensiondata.moref.value 
            }
        }

        
        $xmlReturn.appendChild($xmlItem) | out-null
    }

    $xmlReturn
}

function New-NsxAppliedToListNode {

    #Internal function - Handles building the apliedto xml node for a given object.

    param (

        [object[]]$itemlist,
        [System.XML.XMLDocument]$xmlDoc,
        [switch]$ApplyToDFW

    )


    [System.XML.XMLElement]$xmlReturn = $XMLDoc.CreateElement("appliedToList")
    #Iterate the appliedTo passed and build appliedTo nodes.
    #$xmlRoot.appendChild($xmlReturn) | out-null

    if ( $ApplyToDFW ) {

        [System.XML.XMLElement]$xmlAppliedTo = $XMLDoc.CreateElement("appliedTo")
        $xmlReturn.appendChild($xmlAppliedTo) | out-null
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliedTo -xmlElementName "name" -xmlElementText "DISTRIBUTED_FIREWALL"
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliedTo -xmlElementName "type" -xmlElementText "DISTRIBUTED_FIREWALL"
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliedTo -xmlElementName "value" -xmlElementText "DISTRIBUTED_FIREWALL"

    } else {


        foreach ($item in $itemlist) {
            write-debug "Building appliedTo node for $($item.name)"
            #Build the return XML element
            [System.XML.XMLElement]$xmlItem = $XMLDoc.CreateElement("appliedTo")

            if ( $item -is [system.xml.xmlelement] ) {

                write-debug "Object $($item.name) is specified as xml element"
                #XML representation of NSX object passed - ipset, sec group or logical switch
                #get appropritate name, value.
                Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText $item.objectId
                Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText $item.name
                Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText $item.objectTypeName
                  
            } else {

                write-debug "Object $($item.name) is specified as supported powercli object"
                #Proper PowerCLI Object passed
                #If passed object is a NIC, we have to do some more digging
                if (  $item -is [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.NetworkAdapter] ) {
                   
                    write-debug "Object $($item.name) is vNic"
                    #Naming based on DFW UI standard
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText "$($item.parent.name) - $($item.name)"
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText "Vnic"

                    #Getting the NIC identifier is a bit of hackery at the moment, if anyone can show me a more deterministic or simpler way, then im all ears. 
                    $nicIndex = [array]::indexof($item.parent.NetworkAdapters.name,$item.name)
                    if ( -not ($nicIndex -eq -1 )) { 
                        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText "$($item.parent.PersistentId).00$nicINdex"
                    } else {
                        throw "Unable to determine nic index in parent object.  Make sure the NIC object is valid"
                    }
                }
                else {
                    #any other accepted PowerCLI object, we just need to grab details from the moref.
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText $item.name
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText $item.extensiondata.moref.type
                    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText $item.extensiondata.moref.value 
                }
            }

        
            $xmlReturn.appendChild($xmlItem) | out-null
        }
    }
    $xmlReturn
}

###End Private Functions

function Get-NsxFirewallSection {
   
    <#
    .SYNOPSIS
    Retrieves the specified NSX Distributed Firewall Section.

    .DESCRIPTION
    An NSX Distributed Firewall Section is a named portion of the firewall rule set that contains
    firewall rules.  

    This cmdlet retrieves the specified NSX Distributed Firewall Section.

    .EXAMPLE
    PS C:\> Get-NsxFirewallSection TestSection

    #>

	[CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$false,ParameterSetName="ObjectId")]
            [string]$objectId,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$false,Position=1,ParameterSetName="Name")]
            [string]$Name,
        [Parameter (Mandatory=$false)]
	        [ValidateSet("layer3sections","layer2sections","layer3redirectsections",ignorecase=$false)]
	        [string]$sectionType="layer3sections"

    )
    
    begin {

    }

    process {
     
        if ( -not $objectID ) { 
            #All Sections

            $URI = "/api/4.0/firewall/$scopeID/config"
            $response = invoke-nsxrestmethod -method "get" -uri $URI

			$return = $response.firewallConfiguration.$sectiontype.section

            if ($name) {
                $return | ? {$_.name -eq $name} 
            }else {
            
                $return
            }

        }
        else {
            
            $URI = "/api/4.0/firewall/$scopeID/config/$sectionType/$objectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            $response.section
        }

    }

    end {}

}
Export-ModuleMember -Function Get-NsxFirewallSection

function New-NsxFirewallSection  {


    <#
    .SYNOPSIS
    Creates a new NSX Distributed Firewall Section.

    .DESCRIPTION
    An NSX Distributed Firewall Section is a named portion of the firewall rule 
    set that contains firewall rules.  

    This cmdlet create the specified NSX Distributed Firewall Section.  
    Currently this cmdlet only supports creating a section at the top of the 
    ruleset.

    .EXAMPLE
    PS C:\> New-NsxFirewallSection -Name TestSection

    #>

    [CmdletBinding()]
    param (

        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
        	[ValidateSet("layer3sections","layer2sections","layer3redirectsections",ignorecase=$false)]
        	[string]$sectionType="layer3sections",
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0"
    )

    begin {}
    process { 


        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("section")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
           
        #Do the post
        $body = $xmlroot.OuterXml
        
		$URI = "/api/4.0/firewall/$scopeId/config/$sectionType"
		
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body

        $response.section
        
    }
    end {}

}
Export-ModuleMember -Function New-NsxFirewallSection

function Remove-NsxFirewallSection {

    
    <#
    .SYNOPSIS
    Removes the specified NSX Distributed Firewall Section.

    .DESCRIPTION
    An NSX Distributed Firewall Section is a named portion of the firewall rule 
    set that contains firewall rules.  

    This cmdlet removes the specified NSX Distributed Firewall Section.  If the 
    section contains rules, the removal attempt fails.  Specify -force to 
    override this, but be aware that all firewall rules contained within the 
    section are removed along with it.

    .EXAMPLE
    PS C:\> New-NsxFirewallSection -Name TestSection

    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNull()]
            [System.Xml.XmlElement]$Section,
        [Parameter (Mandatory=$False)]
            [switch]$confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false
    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Firewall Section removal is permanent and cannot be reversed."
            $question = "Proceed with removal of Section $($Section.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            if ( $force ) { 
                $URI = "/api/4.0/firewall/globalroot-0/config/$($Section.ParentNode.name.tolower())/$($Section.Id)"
            }
            else {
                
                if ( $section |  get-member -MemberType Properties -Name rule ) { throw "Section $($section.name) contains rules.  Specify -force to delete this section" }
                else {
                    $URI = "/api/4.0/firewall/globalroot-0/config/$($Section.ParentNode.name.tolower())/$($Section.Id)"
                }
            }
            
            Write-Progress -activity "Remove Section $($Section.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI | out-null
            write-progress -activity "Remove Section $($Section.Name)" -completed

        }
    }

    end {}

}
Export-ModuleMember -Function Remove-NsxFirewallSection 

function Get-NsxFirewallRule {

    <#
    .SYNOPSIS
    Retrieves the specified NSX Distributed Firewall Rule.

    .DESCRIPTION
    An NSX Distributed Firewall Rule defines a typical 5 tuple rule and is 
    enforced on each hypervisor at the point where the VMs NIC connects to the 
    portgroup or logical switch.  

    Additionally, the 'applied to' field allow additional flexibility about 
    where (as in VMs, networks, hosts etc) the rule is actually applied.

    This cmdlet retrieves the specified NSX Distributed Firewall Rule.  It is
    also effective used in conjunction with an NSX firewall section as 
    returned by Get-NsxFirewallSection being passed on the pipeline to retrieve
    all the rules defined within the given section.

    .EXAMPLE
    PS C:\> Get-NsxFirewallSection TestSection | Get-NsxFirewallRule

    #>


    [CmdletBinding(DefaultParameterSetName="Section")]

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="Section")]
        [ValidateNotNull()]
            [System.Xml.XmlElement]$Section,
        [Parameter (Mandatory=$true,ParameterSetName="RuleId")]
        [ValidateNotNullOrEmpty()]
            [string]$RuleId,
        [Parameter (Mandatory=$false)]
            [string]$ScopeId="globalroot-0",
        [Parameter (Mandatory=$false)]
            [ValidateSet("layer3sections","layer2sections","layer3redirectsections",ignorecase=$false)]
        	[string]$RuleType="layer3sections"

    )
    
    begin {

    }

    process {
     
        if ( $PSCmdlet.ParameterSetName -eq "Section" ) { 

			$URI = "/api/4.0/firewall/$scopeID/config/$ruletype/$($Section.Id)"
			
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            if ( $response | get-member -name Section -Membertype Properties){
                if ( $response.Section | get-member -name Rule -Membertype Properties ){
                    $response.section.rule
                }
            }
        }
        else { 

            #SpecificRule - returned xml is firewallconfig -> layer3sections -> section.  
			#In our infinite wisdom, we use a different string here for the section type :|  
			#Kinda considering searching each section type here and returning result regardless of section
			#type if user specifies ruleid...   The I dont have to make the user specify the ruletype...
            switch ($ruleType) {

                "layer3sections" { $URI = "/api/4.0/firewall/$scopeID/config?ruleType=LAYER3&ruleId=$RuleId" }
                "layer2sections" { $URI = "/api/4.0/firewall/$scopeID/config?ruleType=LAYER2&ruleId=$RuleId" }
                "layer3redirectsections" { $URI = "/api/4.0/firewall/$scopeID/config?ruleType=L3REDIRECT&ruleId=$RuleId" }
                default { throw "Invalid rule type" }
            }

            #NSX 6.2 introduced a change in the API wheras the element returned
            #for a query such as we are doing here is now called 
            #'filteredfirewallConfiguration'.  Why? :|

            $response = invoke-nsxrestmethod -method "get" -uri $URI
            if ($response.firewallConfiguration) { 
                $response.firewallConfiguration.layer3Sections.Section.rule

            } 
            elseif ( $response.filteredfirewallConfiguration ) { 
                $response.filteredfirewallConfiguration.layer3Sections.Section.rule
            }
            else { throw "Invalid response from NSX API. $response"}
        }

    }

    end {}

}
Export-ModuleMember -Function Get-NsxFirewallRule

function New-NsxFirewallRule  {

    <#
    .SYNOPSIS
    Creates a new NSX Distributed Firewall Rule.

    .DESCRIPTION
    An NSX Distributed Firewall Rule defines a typical 5 tuple rule and is 
    enforced on each hypervisor at the point where the VMs NIC connects to the 
    portgroup or logical switch.  

    Additionally, the 'applied to' field allows flexibility about 
    where (as in VMs, networks, hosts etc) the rule is actually applied.

    This cmdlet creates the specified NSX Distributed Firewall Rule. The section
    in which to create the rule is mandatory. 

    .EXAMPLE
    PS C:\> Get-NsxFirewallSection TestSection | 
        New-NsxFirewallRule -Name TestRule -Source $LS1 -Destination $LS1 
        -Action allow
        -service (Get-NsxService HTTP) -AppliedTo $LS1 -EnableLogging -Comment 
         "Testing Rule Creation"

    #>

    [CmdletBinding()]
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="Section")]
        [ValidateNotNull()]
            [System.Xml.XmlElement]$Section,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateSet("allow","deny","reject")]
            [string]$Action,
        [Parameter (Mandatory=$false)]
            [ValidateScript({
                #Check types first
                if (-not (
                     ($_ -is [System.Xml.XmlElement]) -or 
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.DatacenterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ResourcePoolImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.NetworkAdapter] ))) {

                        throw "Source is not a supported type.  Specify a Datacenter, Cluster, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object."
                         
                } else {

                    #Check if we have an ID property
                    if ($_ -is [System.Xml.XmlElement] ) {
                        if ( -not ( $_ | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an objectId property."}
                        if ( -not ( $_ | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                        
                       
                        switch ($_.objectTypeName) {

                            "IPSet"{}
                            "SecurityGroup" {}
                            "VirtualWire" {}
                            default { throw "Source is not a supported type.  Specify a Datacenter, Cluster, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object." }
                            
                        }
                    }   
                }
                $true
            })]
            [object[]]$Source,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$NegateSource,
        [Parameter (Mandatory=$false)]
        [ValidateScript({
                #Check types first
                if (-not (
                     ($_ -is [System.Xml.XmlElement]) -or 
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.DatacenterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ResourcePoolImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.NetworkAdapter] ))) {

                        throw "Destination is not a supported source type.  Specify a Datacenter, Cluster, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object."
                         
                } else {

                    #Check if we have an ID property
                    if ($_ -is [System.Xml.XmlElement] ) {
                        if ( -not ( $_ | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an objectId property."}
                        if ( -not ( $_ | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                        
                        switch ($_.objectTypeName) {

                            "IPSet"{}
                            "SecurityGroup" {}
                            "VirtualWire" {}
                            default { throw "Destination is not a supported type.  Specify a Datacenter, Cluster, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object." }
                            
                        }
                    }   
                }
                $true
            })]
            [object[]]$Destination,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$NegateDestination,
        [Parameter (Mandatory=$false)]
        [ValidateScript ({
            if ( -not ($_ | get-member -MemberType Property -Name objectId )) { throw "Invalid service object specified" } else { $true }
        })]
            [System.Xml.XmlElement[]]$Service,
        [Parameter (Mandatory=$false)]
            [string]$Comment="",
        [Parameter (Mandatory=$false)]
            [switch]$EnableLogging,  
        [Parameter (Mandatory=$false)]
        [ValidateScript({
                #Check types first - currently missing edge handling!!!
                if (-not (
                     ($_ -is [System.Xml.XmlElement]) -or 
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.DatacenterImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VMHostImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.VirtualPortGroupImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ResourcePoolImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl] ) -or
                     ($_ -is [VMware.VimAutomation.ViCore.Types.V1.VirtualDevice.NetworkAdapter] ))) {

                        throw "$($_.gettype()) is not a supported type.  Specify a Datacenter, Cluster, Host `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object."
                         
                } else {

                    #Check if we have an ID property
                    if ($_ -is [System.Xml.XmlElement] ) {
                        if ( -not ( $_ | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an objectId property."}
                        if ( -not ( $_ | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                        
                        switch ($_.objectTypeName) {

                            "IPSet"{}
                            "SecurityGroup" {}
                            "VirtualWire" {}
                            default { throw "AppliedTo is not a supported type.  Specify a Datacenter, Cluster, Host, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup or Logical Switch object." }
                            
                        }
                    }   
                }
                $true
            })]
            [object[]]$AppliedTo,
        [Parameter (Mandatory=$false)]
        	[ValidateSet("layer3sections","layer2sections","layer3redirectsections",ignorecase=$false)]
        	[string]$RuleType="layer3sections",
		[Parameter (Mandatory=$false)]
			[ValidateSet("Top","Bottom")]
			[string]$Position="Top",	
        [Parameter (Mandatory=$false)]
            [string]$ScopeId="globalroot-0"
    )

    begin {}
    process { 

		
		$generationNumber = $section.generationNumber           

        write-debug "Preparing rule for section $($section.Name) with generationId $generationNumber"
        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRule = $XMLDoc.CreateElement("rule")
        $xmlDoc.appendChild($xmlRule) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRule -xmlElementName "name" -xmlElementText $Name
        #Add-XmlElement -xmlDoc $xmldoc -xmlRoot $xmlRule -xmlElementName "sectionId" -xmlElementText $($section.Id)
        Add-XmlElement -xmlDoc $xmldoc -xmlRoot $xmlRule -xmlElementName "notes" -xmlElementText $Comment
        Add-XmlElement -xmlDoc $xmldoc -xmlRoot $xmlRule -xmlElementName "action" -xmlElementText $action
        if ( $EnableLogging ) {
            #Enable Logging attribute
            $xmlAttrLog = $xmlDoc.createAttribute("logged")
            $xmlAttrLog.value = "true"
            $xmlRule.Attributes.Append($xmlAttrLog) | out-null
            
        }
                    
        #Build Sources Node
        if ( $source ) {
            $xmlSources = New-NsxSourceDestNode -itemType "source" -itemlist $source -xmlDoc $xmlDoc -negateItem:$negateSource
            $xmlRule.appendChild($xmlSources) | out-null
        }

        #Destinations Node
        if ( $destination ) { 
            $xmlDestinations = New-NsxSourceDestNode -itemType "destination" -itemlist $destination -xmlDoc $xmlDoc -negateItem:$negateDestination
            $xmlRule.appendChild($xmlDestinations) | out-null
        }

        #Services
        if ( $service) {
            [System.XML.XMLElement]$xmlServices = $XMLDoc.CreateElement("services")
            #Iterate the services passed and build service nodes.
            $xmlRule.appendChild($xmlServices) | out-null
            foreach ( $serviceitem in $service ) {
            
                #Services
                [System.XML.XMLElement]$xmlService = $XMLDoc.CreateElement("service")
                $xmlServices.appendChild($xmlService) | out-null
                Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlService -xmlElementName "value" -xmlElementText $serviceItem.objectId   
        
            }
        }

        #Applied To
        if ( -not ( $AppliedTo )) { 
            $xmlAppliedToList = New-NsxAppliedToListNode -xmlDoc $xmlDoc -ApplyToDFW 
        }
        else {
            $xmlAppliedToList = New-NsxAppliedToListNode -itemlist $AppliedTo -xmlDoc $xmlDoc 
        }
        $xmlRule.appendChild($xmlAppliedToList) | out-null
		
		#Append the new rule to the section
		$xmlrule = $Section.ownerDocument.ImportNode($xmlRule, $true)
		switch ($Position) {
			"Top" { $Section.prependchild($xmlRule) | Out-Null }
			"Bottom" { $Section.appendchild($xmlRule) | Out-Null }
		
		}
        #Do the post
        $body = $Section.OuterXml
        
        write-debug $body

		$URI = "/api/4.0/firewall/$scopeId/config/$ruletype/$($section.Id)"
		
        #Need the IfMatch header to specify the current section generation id
	
        $IfMatchHeader = @{"If-Match"=$generationNumber}
        $response = invoke-nsxrestmethod -method "put" -uri $URI -body $body -extraheader $IfMatchHeader

        $response.section
        
    }
    end {}

}
Export-ModuleMember -Function New-NsxFirewallRule


function Remove-NsxFirewallRule {

    <#
    .SYNOPSIS
    Removes the specified NSX Distributed Firewall Rule.

    .DESCRIPTION
    An NSX Distributed Firewall Rule defines a typical 5 tuple rule and is 
    enforced on each hypervisor at the point where the VMs NIC connects to the 
    portgroup or logical switch.  

    This cmdlet removes the specified NSX Distributed Firewall Rule. 

    .EXAMPLE
    PS C:\> Get-NsxFirewallRule -RuleId 1144 | Remove-NsxFirewallRule 
        -confirm:$false 

    #>
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNull()]
            [System.Xml.XmlElement]$Rule,
        [Parameter (Mandatory=$False)]
            [switch]$confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false
    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Firewall Rule removal is permanent and cannot be reversed."
            $question = "Proceed with removal of Rule $($Rule.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
		
			$section = get-nsxFirewallSection $Rule.parentnode.name
			$generationNumber = $section.generationNumber
	        $IfMatchHeader = @{"If-Match"=$generationNumber}
            $URI = "/api/4.0/firewall/globalroot-0/config/$($Section.ParentNode.name.tolower())/$($Section.Id)/rules/$($Rule.id)"
          
            
            Write-Progress -activity "Remove Rule $($Rule.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI  -extraheader $IfMatchHeader | out-null
            write-progress -activity "Remove Rule $($Rule.Name)" -completed

        }
    }

    end {}

}
Export-ModuleMember -Function Remove-NsxFirewallRule


########
########
# ESG related functions

###Private functions

function New-NsxEdgeVnicAddressGroup {

    #Private function that Edge (ESG and LogicalRouter) VNIC creation leverages
    #To create valid address groups (primary and potentially secondary address) 
    #and netmask.

    #ToDo - Implement IP address and netmask validation

    param (
        [Parameter (Mandatory=$true)]
            [System.XML.XMLElement]$xmlAddressGroups,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullorEmpty()]
            [System.XML.XMLDocument]$xmlDoc,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [string[]]$SecondaryAddresses=@()

    )

    [System.XML.XMLElement]$xmlAddressGroup = $xmlDoc.CreateElement("addressGroup")
    $xmlAddressGroups.appendChild($xmlAddressGroup) | out-null
    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAddressGroup -xmlElementName "primaryAddress" -xmlElementText $PrimaryAddress
    Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAddressGroup -xmlElementName "subnetPrefixLength" -xmlElementText $SubnetPrefixLength
    if ( $SecondaryAddresses ) { 
        [System.XML.XMLElement]$xmlSecondaryAddresses = $XMLDoc.CreateElement("secondaryAddresses")
        $xmlAddressGroup.appendChild($xmlSecondaryAddresses) | out-null
        foreach ($Address in $SecondaryAddresses) { 
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlSecondaryAddresses -xmlElementName "ipAddress" -xmlElementText $Address
        }
    }

}

###End Private functions

function New-NsxEdgeVnicSpec {

    <#
    .SYNOPSIS
    Creates a new NSX Edge Service Gateway vNic Spec.

    .DESCRIPTION
    NSX ESGs can host up to 10 vNics and up to 200 subinterfaces, each of which 
    can be configured with multiple properties.  In order to allow creation of 
    ESGs with an arbitrary number of vNics, a unique spec for each 
    vNic required must first be created.

    ESGs support vNics connected to either VLAN backed port groups or NSX
    Logical Switches.
    
    .EXAMPLE

    PS C:\> $Uplink = New-NsxEdgeVnicSpec -Name Uplink_vNic -Type 
        uplink -ConnectedTo (Get-NsxTransportZone | Get-NsxLogicalSwitch LS1) 
        -PrimaryAddress 192.168.0.1 -SubnetPrefixLength 24

    PS C:\> $Internal = New-NsxEdgeVnicSpec -Name Internal-vNic -Type 
        internal -ConnectedTo (Get-NsxTransportZone | Get-NsxLogicalSwitch LS2) 
        -PrimaryAddress 10.0.0.1 -SubnetPrefixLength 24
    
    #>

    param (
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,9)]
            [int]$Index,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateSet ("internal","uplink")]
            [string]$Type,
        [Parameter (Mandatory=$true)]
            [ValidateScript({
                if (-not (
                    ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl] ) -or
                    ($_ -is [VMware.VimAutomation.Vds.Impl.VDObjectImpl] ) -or
                    ($_ -is [System.Xml.XmlElement] )))
                { 
                    throw "Must specify a distributed port group or a logical switch" 
                } else {

                    #Check if we have an ID property
                    if ($_ -is [System.Xml.XmlElement] ) {
                        if ( -not ( $_ | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an objectId property."}
                        if ( -not ( $_ | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                        
                        switch ($_.objectTypeName) {
                            "VirtualWire" {}
                            default { throw "Specified value is not a supported type.  Specify a Distributed PortGroup or Logical Switch object." }
                        }
                    }   
                }
                $true
            })]
            [object]$ConnectedTo,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [string[]]$SecondaryAddresses=@(),
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,9128)]
            [int]$MTU=1500,       
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableProxyArp=$false,       
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableSendICMPRedirects=$true,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Connected=$true 


    )

    begin {}
    process { 

        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlVnic = $XMLDoc.CreateElement("vnic")
        $xmlDoc.appendChild($xmlVnic) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "index" -xmlElementText $index   
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "type" -xmlElementText $type 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "mtu" -xmlElementText $MTU 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "enableProxyArp" -xmlElementText $EnableProxyArp 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "enableSendRedirects" -xmlElementText $EnableSendICMPRedirects 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "isConnected" -xmlElementText $Connected


        switch ($ConnectedTo){

            { ($_ -is [VMware.VimAutomation.ViCore.Impl.V1.Host.Networking.DistributedPortGroupImpl]) -or ( $_ -is [VMware.VimAutomation.Vds.Impl.VDObjectImpl] ) }  { $PortGroupID = $_.ExtensionData.MoRef.Value }
            { $_ -is [System.Xml.XmlElement]} { $PortGroupID = $_.objectId }

        }  

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVnic -xmlElementName "portgroupId" -xmlElementText $PortGroupID
        
        #For now, only supporting one addressgroup - will refactor later
        [System.XML.XMLElement]$xmlAddressGroups = $XMLDoc.CreateElement("addressGroups")
        $xmlVnic.appendChild($xmlAddressGroups) | out-null
        New-NsxEdgeVnicAddressGroup -xmldoc $xmlDoc -xmlAddressGroups $xmlAddressGroups -PrimaryAddress $PrimaryAddress -SubnetPrefixLength $SubnetPrefixLength -SecondaryAddresses $secondaryAddresses
        
        $xmlVnic
    }

    end {}
}
Export-ModuleMember -Function New-NsxEdgeVnicSpec

function Get-NsxEdgeServicesGateway {

    <#
    .SYNOPSIS
    Retrieves an NSX Edge Service Gateway Object.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs support vNics connected to either VLAN backed port groups or NSX
    Logical Switches.

    
    .EXAMPLE
    PS C:\>  Get-NsxEdgeServicesGateway

    #>


    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ParameterSetName="objectId")]
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name

    )

    $pagesize = 10         
    switch ( $psCmdlet.ParameterSetName ) {

        "Name" { 
            $URI = "/api/4.0/edges?pageSize=$pagesize&startIndex=00" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            
            #Edge summary XML is returned as paged data, means we have to handle it.  
            #Then we have to query for full information on a per edge basis.
            $edgesummaries = @()
            $edges = @()
            $itemIndex =  0
            $startingIndex = 0 
            $pagingInfo = $response.pagedEdgeList.edgePage.pagingInfo
            
            if ( [int]$paginginfo.totalCount -ne 0 ) {
                 write-debug "Get-NsxEdgeServicesGateway - ESG count non zero"

                do {
                    write-debug "Get-NsxEdgeServicesGateway - In paging loop. PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"

                    while (($itemindex -lt ([int]$paginginfo.pagesize + $startingIndex)) -and ($itemIndex -lt [int]$paginginfo.totalCount )) {
            
                        write-debug "Get-NsxEdgeServicesGateway - In Item Processing Loop: ItemIndex: $itemIndex"
                        write-debug "Get-NsxEdgeServicesGateway - $(@($response.pagedEdgeList.edgePage.edgeSummary)[($itemIndex - $startingIndex)].objectId)"
                    
                        #Need to wrap the edgesummary prop of the datapage in case we get exactly 1 item - 
                        #which powershell annoyingly unwraps to a single xml element rather than an array...
                        $edgesummaries += @($response.pagedEdgeList.edgePage.edgeSummary)[($itemIndex - $startingIndex)]
                        $itemIndex += 1 
                    }  
                    write-debug "Get-NsxEdgeServicesGateway - Out of item processing - PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                    if ( [int]$paginginfo.totalcount -gt $itemIndex) {
                        write-debug "Get-NsxEdgeServicesGateway - PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                        $startingIndex += $pagesize
                        $URI = "/api/4.0/edges?pageSize=$pagesize&startIndex=$startingIndex"
                
                        $response = invoke-nsxrestmethod -method "get" -uri $URI
                        $pagingInfo = $response.pagedEdgeList.edgePage.pagingInfo
                    

                    } 
                } until ( [int]$paginginfo.totalcount -le $itemIndex )    
                write-debug "Get-NsxEdgeServicesGateway - Completed page processing: ItemIndex: $itemIndex"
            }

            #What we got here is...failure to communicate!  In order to get full detail, we have to requery for each edgeid.
            #But... there is information in the SUmmary that isnt in the full detail.  So Ive decided to add the summary as a node 
            #to the returned edge detail. 

            foreach ($edgesummary in $edgesummaries) {

                $URI = "/api/4.0/edges/$($edgesummary.objectID)" 
                $response = invoke-nsxrestmethod -method "get" -uri $URI
                $import = $response.edge.ownerDocument.ImportNode($edgesummary, $true)
                $response.edge.appendChild($import) | out-null                
                $edges += $response.edge

            }

            if ( $name ) { 
                $edges | ? { $_.Type -eq 'gatewayServices' } | ? { $_.name -eq $name }

            } else {
                $edges | ? { $_.Type -eq 'gatewayServices' }

            }

        }

        "objectId" { 

            $URI = "/api/4.0/edges/$objectId" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            $edge = $response.edge
            $URI = "/api/4.0/edges/$objectId/summary" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI
            $import = $edge.ownerDocument.ImportNode($($response.edgeSummary), $true)
            $edge.AppendChild($import) | out-null
            $edge

        }
    }

}
Export-ModuleMember -Function Get-NsxEdgeServicesGateway

function New-NsxEdgeServicesGateway {

    <#
    .SYNOPSIS
    Creates a new NSX Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs support vNics connected to either VLAN backed port groups or NSX
    Logical Switches.

    PowerCLI cmdlets such as Get-VDPortGroup and Get-Datastore require a valid
    PowerCLI session.
    
    .EXAMPLE
    Create vNic specifications first for each interface that you want on the ESG

    PS C:\> $vnic0 = New-NsxEdgeVnicSpec -Index 0 -Name Uplink -Type Uplink 
        -ConnectedTo (Get-VDPortgroup Corp) -PrimaryAddress "1.1.1.2" 
        -SubnetPrefixLength 24

    PS C:\> $vnic1 = New-NsxEdgeVnicSpec -Index 1 -Name Internal -Type Uplink 
        -ConnectedTo $LogicalSwitch1 -PrimaryAddress "2.2.2.1" 
        -SecondaryAddresses "2.2.2.2" -SubnetPrefixLength 24

    Then create the Edge Services Gateway
    PS C:\> New-NsxEdgeServicesGateway -name DMZ_Edge_2 
        -Cluster (get-cluster Cluster1) -Datastore (get-datastore Datastore1) 
        -Vnic $vnic0,$vnic1 -Password 'Pass'

    #>

    param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true,ParameterSetName="ResourcePool")]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ResourcePoolImpl]$ResourcePool,
        [Parameter (Mandatory=$true,ParameterSetName="Cluster")]
            [ValidateScript({
                if ( $_ -eq $null ) { throw "Must specify Cluster."}
                if ( -not $_.DrsEnabled ) { throw "Cluster is not DRS enabled."}
                $true
            })]
            [VMware.VimAutomation.ViCore.Impl.V1.Inventory.ClusterImpl]$Cluster,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.DatastoreImpl]$Datastore,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [String]$Password,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableHA=$false,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Impl.V1.DatastoreManagement.DatastoreImpl]$HADatastore=$datastore,
        [Parameter (Mandatory=$false)]
            [ValidateSet ("compact","large","xlarge","quadlarge")]
            [string]$FormFactor="compact",
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl]$VMFolder,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [String]$Tenant,
         [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [String]$PrimaryDNSServer,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [String]$SecondaryDNSServer,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [String]$DNSDomainName,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableSSH=$false,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$AutoGenerateRules=$true,
       [Parameter (Mandatory=$true)]
            [ValidateScript({

                #temporary - need to script proper validation of a single valid NIC config
                if ( -not $_ ) { 
                    throw "Specify at least one vNIC configuration as produced by New-NsxEdgeVnicSpec.  Pass a collection of vNIC objects to configure more than one vNIC"
                }
                $true
            })]
            [System.Xml.XmlElement[]]$Vnic       
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("edge")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "type" -xmlElementText "gatewayServices"
        if ( $Tenant ) { Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlRoot -xmlElementName "tenant" -xmlElementText $Tenant}


        [System.XML.XMLElement]$xmlAppliances = $XMLDoc.CreateElement("appliances")
        $xmlRoot.appendChild($xmlAppliances) | out-null
        
        switch ($psCmdlet.ParameterSetName){

            "Cluster"  { $ResPoolId = $($cluster | get-resourcepool | ? { $_.parent.id -eq $cluster.id }).extensiondata.moref.value }
            "ResourcePool"  { $ResPoolId = $ResourcePool.extensiondata.moref.value }

        }

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliances -xmlElementName "applianceSize" -xmlElementText $FormFactor

        [System.XML.XMLElement]$xmlAppliance = $XMLDoc.CreateElement("appliance")
        $xmlAppliances.appendChild($xmlAppliance) | out-null
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "resourcePoolId" -xmlElementText $ResPoolId
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "datastoreId" -xmlElementText $datastore.extensiondata.moref.value
        if ( $VMFolder ) { Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "vmFolderId" -xmlElementText $VMFolder.extensiondata.moref.value}

        if ( $EnableHA ) {
            [System.XML.XMLElement]$xmlAppliance = $XMLDoc.CreateElement("appliance")
            $xmlAppliances.appendChild($xmlAppliance) | out-null
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "resourcePoolId" -xmlElementText $ResPoolId
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "datastoreId" -xmlElementText $HAdatastore.extensiondata.moref.value
            if ( $VMFolder ) { Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlAppliance -xmlElementName "vmFolderId" -xmlElementText $VMFolder.extensiondata.moref.value}
               
        }

        [System.XML.XMLElement]$xmlVnics = $XMLDoc.CreateElement("vnics")
        $xmlRoot.appendChild($xmlVnics) | out-null
        foreach ( $VnicSpec in $Vnic ) {

            $import = $xmlDoc.ImportNode(($VnicSpec), $true)
            $xmlVnics.AppendChild($import) | out-null

        }

        # #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/4.0/edges"
        Write-Progress -activity "Creating Edge Services Gateway $Name"    
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body
        Write-progress -activity "Creating Edge Services Gateway $Name" -completed
        $edgeId = $response.Headers.Location.split("/")[$response.Headers.Location.split("/").GetUpperBound(0)] 

        if ( $EnableHA ) {
            
            [System.XML.XMLElement]$xmlHA = $XMLDoc.CreateElement("highAvailability")
            Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlHA -xmlElementName "enabled" -xmlElementText "true"
            $body = $xmlHA.OuterXml
            $URI = "/api/4.0/edges/$edgeId/highavailability/config"
            
            Write-Progress -activity "Enable HA on edge $Name"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body
            write-progress -activity "Enable HA on edge $Name" -completed

        }
        Get-NsxEdgeServicesGateway -objectID $edgeId

    }
    end {}
 
}
Export-ModuleMember -Function New-NsxEdgeServicesGateway

function Update-NsxEdgeServicesGateway {
    <#
    .SYNOPSIS
    Updates an existing NSX Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs support vNics connected to either VLAN backed port groups or NSX
    Logical Switches.

    PowerCLI cmdlets such as Get-VDPortGroup and Get-Datastore require a valid
    PowerCLI session.

    Note:  This cmdlet is not yet complete.
    
    .EXAMPLE
    Example1: Enable Load Balancing
    PS C:\> Update-NsxEdgeServicesGateway -EnableLoadBalancing 
        -EnableAcceleration

    
    #>

    [CmdletBinding(DefaultParameterSetName="default")]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if we have an ID property
                if ($_ -is [System.Xml.XmlElement] ) {
                    if ( $_ | get-member -name edgeSummary -memberType Properties) { 
                        if ( -not ( $_.edgeSummary | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.objectId property."}
                        if ( -not ( $_.edgeSummary | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.ObjectTypeName property."}
                        if ( -not ( $_.edgeSummary | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.name property."}
                        if ( -not ( $_ | get-member -name type -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ($_.edgeSummary.objectTypeName -ne "Edge" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                        if ($_.type -ne "gatewayServices" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                    }   
                }
                $true
            })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$True,ParameterSetName="LoadBalancer")]
        [switch]$EnableLoadBalancing,
        [Parameter (Mandatory=$False,ParameterSetName="LoadBalancer")]
        [switch]$EnableAcceleration=$true

    )
    
    begin {

    }

    process {

         #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument

        switch  ($pscmdlet.ParameterSetName) {

            "LoadBalancer" {

                $import = $xmlDoc.ImportNode(($edge.features.loadBalancer), $true)
                [System.XML.XMLElement]$xmlLB = $xmlDoc.AppendChild($import)

                if ( $EnableLoadBalancing ) { 
                    $xmlLb.enabled = "true" 
                } else { 
                    $xmlLb.enabled = "false" 
                } 
                if ( $EnableAcceleration ) { 
                    $xmllb.accelerationEnabled = "true" 
                } else { 
                    $xmllb.accelerationEnabled = "false" 
                } 

                
                $URI = "/api/4.0/edges/$($Edge.Edgesummary.ObjectId)/loadbalancer/config"
                $body = $xmlLB.OuterXml 

            }

        }
        
        Write-Progress -activity "Update Edge Services Gateway $($Edge.Name)"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body
        write-progress -activity "Update Edge Services Gateway $($Edge.Name)" -completed

        Get-NsxEdgeServicesGateway -objectId $($Edge.Edgesummary.ObjectId)

    }

    end {}

}
Export-ModuleMember -Function Update-NsxEdgeServicesGateway

function Remove-NsxEdgeServicesGateway {

    <#
    .SYNOPSIS
    Removes an existing NSX Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    This cmdlet removes the specified ESG. 
    .EXAMPLE
   
    PS C:\> Get-NsxEdgeServicesGateway TestESG | Remove-NsxEdgeServicesGateway
        -confirm:$false
    
    #>
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if we have an ID property
                if ($_ -is [System.Xml.XmlElement] ) {
                    if ( $_ | get-member -name edgeSummary -memberType Properties) { 
                        if ( -not ( $_.edgeSummary | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.objectId property."}
                        if ( -not ( $_.edgeSummary | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.ObjectTypeName property."}
                        if ( -not ( $_.edgeSummary | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.name property."}
                        if ( -not ( $_ | get-member -name type -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ($_.edgeSummary.objectTypeName -ne "Edge" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                        if ($_.type -ne "gatewayServices" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                    }   
                }
                $true
            })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$False)]
            [switch]$confirm=$true

    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Edge Services Gateway removal is permanent."
            $question = "Proceed with removal of Edge Services Gateway $($Edge.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/4.0/edges/$($Edge.Edgesummary.ObjectId)"
            Write-Progress -activity "Remove Edge Services Gateway $($Edge.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI | out-null
            write-progress -activity "Remove Edge Services Gateway $($Edge.Name)" -completed

        }
    }

    end {}

}
Export-ModuleMember -Function Remove-NsxEdgeServicesGateway


########
########
# ESG Load Balancing


function Get-NsxLoadBalancer {

    <#
    .SYNOPSIS
    Retrieves the LoadBalancer configuration from a specified Edge.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    This cmdlet retrieves the LoadBalancer configuration from a specified Edge. 
    .EXAMPLE
   
    PS C:\> Get-NsxEdgeServicesGateway TestESG | Get-NsxLoadBalancer
    
    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if we have an ID property
                if ($_ -is [System.Xml.XmlElement] ) {
                    if ( $_ | get-member -name edgeSummary -memberType Properties) { 
                        if ( -not ( $_.edgeSummary | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.objectId property."}
                        if ( -not ( $_.edgeSummary | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.ObjectTypeName property."}
                        if ( -not ( $_.edgeSummary | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.name property."}
                        if ( -not ( $_ | get-member -name type -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ($_.edgeSummary.objectTypeName -ne "Edge" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                        if ($_.type -ne "gatewayServices" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                    }   
                }
                $true
            })]
            [System.Xml.XmlElement]$Edge
    )

    begin {}

    process { 
        $edge.features.loadBalancer        
    }       
}

Export-ModuleMember -Function Get-NsxLoadBalancer

function Get-NsxLoadBalancerMonitor {

    <#
    .SYNOPSIS
    Retrieves the LoadBalancer Monitors from a specified LoadBalancer.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    Load Balancer Monitors are the method by which a Load Balancer determines
    the health of pool members.

    This cmdlet retrieves the LoadBalancer Monitors from a specified 
    LoadBalancer.

    .EXAMPLE
   
    PS C:\> $LoadBalancer | Get-NsxLoadBalancerMonitor default_http_monitor
    
    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if it looks like an LB element
                if ($_ -is [System.Xml.XmlElement] ) {

                    if ( -not ( $_ | get-member -name version -Membertype Properties)) { throw "XML Element specified does not contain an version property."}
                    if ( -not ( $_ | get-member -name enabled -Membertype Properties)) { throw "XML Element specified does not contain an enabled property."}
                }
 
                $true
            })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$true,ParameterSetName="monitorId")]
            [string]$monitorId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name
    )

    begin {}

    process { 
        
        if ( $Name) { 
            $loadbalancer.monitor | ? { $_.name -eq $Name }
        }
        elseif ( $monitorId ) { 
            $loadbalancer.monitor | ? { $_.monitorId -eq $monitorId }
        }
        else { 
            $loadbalancer.monitor 
        }
    }

    end{ }

}
Export-ModuleMember -Function Get-NsxLoadBalancerMonitor

function Get-NsxLoadBalancerApplicationProfile {

    <#
    .SYNOPSIS
    Retrieves LoadBalancer Application Profiles from a specified LoadBalancer.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    Application profiles define the behavior of a particular type of network 
    traffic. After configuring a profile, you associate the profile with a 
    virtual server. The virtual server then processes traffic according to the 
    values specified in the profile. Using profiles enhances your control over 
    managing network traffic, and makes traffic‐management tasks easier and more
    efficient.
    
    This cmdlet retrieves the LoadBalancer Application Profiles from a specified 
    LoadBalancer.

    .EXAMPLE
   
    PS C:\> Get-NsxEdgeServicesGateway LoadBalancer | Get-NsxLoadBalancer | 
        Get-NsxLoadBalancerApplicationProfile HTTP
    
    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if it looks like an LB element
                if ($_ -is [System.Xml.XmlElement] ) {

                    if ( -not ( $_ | get-member -name version -Membertype Properties)) { throw "XML Element specified does not contain an version property."}
                    if ( -not ( $_ | get-member -name enabled -Membertype Properties)) { throw "XML Element specified does not contain an enabled property."}
                }
 
                $true
            })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$true,ParameterSetName="applicationProfileId")]
            [string]$applicationProfileId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name

    )

    begin {}

    process { 
        
        if ( $Name) { 
            $loadbalancer.applicationProfile | ? { $_.name -eq $Name }
        }
        elseif ( $monitorId ) { 
            $loadbalancer.applicationProfile | ? { $_.monitorId -eq $applicationProfileId }
        }
        else { 
            $loadbalancer.applicationProfile 
        }
    }

    end{ }

}
Export-ModuleMember -Function Get-NsxLoadBalancerApplicationProfile

function New-NsxLoadBalancerApplicationProfile {
 
    <#
    .SYNOPSIS
    Creates a new LoadBalancer Application Profile on the specified 
    Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    Application profiles define the behavior of a particular type of network 
    traffic. After configuring a profile, you associate the profile with a 
    virtual server. The virtual server then processes traffic according to the 
    values specified in the profile. Using profiles enhances your control over 
    managing network traffic, and makes traffic‐management tasks easier and more
    efficient.
    
    This cmdlet creates a new LoadBalancer Application Profiles on a specified 
    Edge Services Gateway.

    .EXAMPLE
    
    PS C:\> $ESG | New-NsxLoadBalancerApplicationProfile -Name HTTP 
        -Type HTTP -insertXForwardedFor
    
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if we have an ID property
                if ($_ -is [System.Xml.XmlElement] ) {
                    if ( $_ | get-member -name edgeSummary -memberType Properties) { 
                        if ( -not ( $_.edgeSummary | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.objectId property."}
                        if ( -not ( $_.edgeSummary | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.ObjectTypeName property."}
                        if ( -not ( $_.edgeSummary | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.name property."}
                        if ( -not ( $_ | get-member -name type -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ($_.edgeSummary.objectTypeName -ne "Edge" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                        if ($_.type -ne "gatewayServices" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                    }   
                }
                $true
            })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$True)]
            [ValidateSet("TCP","UDP","HTTP","HTTPS")]
            [string]$Type,  
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [switch]$insertXForwardedFor=$false    
        
    )
    # Lot more to do here - need persistence settings dependant on the type selected... as well as cookie serttings, and cert selection...

    begin {
    }

    process {
        
        #Create the XMLDoc and import the LB node.
        [System.XML.XMLDocument]$xmlDoc = new-object System.XML.XMLDocument
        $import = $xmlDoc.ImportNode(($edge.features.loadBalancer), $true)
        $xmlDoc.AppendChild($import) | out-null
        
        $loadbalancer = $xmlDoc.loadBalancer

        if ( -not $loadBalancer.enabled -eq 'true' ) { throw "Load Balancer feature is not enabled on edge $($edge.Name).  Use Set-NsxEdgeServicesGateway -EnableLoadBalancing to enable."}
     
        [System.XML.XMLElement]$xmlapplicationProfile = $xmlDoc.CreateElement("applicationProfile")
        $loadbalancer.appendChild($xmlapplicationProfile) | out-null
     
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlapplicationProfile -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlapplicationProfile -xmlElementName "template" -xmlElementText $Type
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlapplicationProfile -xmlElementName "insertXForwardedFor" -xmlElementText $insertXForwardedFor 
        
        
        $URI = "/api/4.0/edges/$($Edge.Edgesummary.ObjectId)/loadbalancer/config"
        $body = $loadbalancer.OuterXml 
    
        Write-Progress -activity "Update Edge Services Gateway $($Edge.Name)" -status "Load Balancing Config"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body
        write-progress -activity "Update Edge Services Gateway $($Edge.Name)" -completed

        $return = Get-NsxEdgeServicesGateway -objectId $($Edge.Edgesummary.ObjectId)
        
        $applicationProfiles = $return.features.loadbalancer.applicationProfile
        foreach ($applicationProfile in $applicationProfiles) { 

            #Stupid, Stupid, STUPID NSX API creates an object ID format _that it does not accept back when put FFS!!!_ We have to change on the fly to the 'correct format'
            write-debug "Checking for stupidness in $($applicationProfile.applicationProfileId)"    
            $applicationProfile.applicationProfileId = 
                $applicationProfile.applicationProfileId.replace("edge_load_balancer_application_profiles","applicationProfile-")
            
        }

        $body = $return.features.loadbalancer.OuterXml
        Write-Progress -activity "Update Edge Services Gateway $($Edge.Name)" -status "Load Balancing Config"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body
        write-progress -activity "Update Edge Services Gateway $($Edge.Name)" -completed

        $return = Get-NsxEdgeServicesGateway -objectId $($Edge.Edgesummary.ObjectId)

        #filter output for our newly created app profile - name is safe as it has to be unique.
        $return.features.loadbalancer.applicationProfile | ? { $_.name -eq $name }
    }

    end {}

}
Export-ModuleMember -Function New-NsxLoadBalancerApplicationProfile

function New-NsxLoadBalancerMemberSpec {

    <#
    .SYNOPSIS
    Creates a new LoadBalancer Pool Member specification to be used when 
    updating or creating a LoadBalancer Pool

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    A pool manages load balancer distribution methods and has a service monitor 
    attached to it for health check parameters.  Each Pool has one or more 
    members.  Prior to creating or updating a pool to add a member, a member
    spec describing the member needs to be created.
    
    This cmdlet creates a new LoadBalancer Pool Member specification.

    .EXAMPLE
    
    PS C:\> $WebMember1 = New-NsxLoadBalancerMemberSpec -name Web01 
        -IpAddress 192.168.200.11 -Port 80
    
    PS C:\> $WebMember2 = New-NsxLoadBalancerMemberSpec -name Web02 
        -IpAddress 192.168.200.12 -Port 80 -MonitorPort 8080 
        -MaximumConnections 100
    
    #>


     param (

        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [IpAddress]$IpAddress,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [int]$Weight=1,
        [Parameter (Mandatory=$true)]
            [ValidateRange(1,65535)]
            [int]$Port,   
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,65535)]
            [int]$MonitorPort=$port,   
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [int]$MinimumConnections=0,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [int]$MaximumConnections=0
    )

    begin {}
    process { 

        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlMember = $XMLDoc.CreateElement("member")
        $xmlDoc.appendChild($xmlMember) | out-null

        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "ipAddress" -xmlElementText $IpAddress   
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "weight" -xmlElementText $Weight 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "port" -xmlElementText $port 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "monitorPort" -xmlElementText $port 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "minConn" -xmlElementText $MinimumConnections 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlMember -xmlElementName "maxConn" -xmlElementText $MaximumConnections 
  
        $xmlMember

    }

    end {}
}

Export-ModuleMember -Function New-NsxLoadBalancerMemberSpec

function New-NsxLoadBalancerPool {
 

    <#
    .SYNOPSIS
    Creates a new LoadBalancer Pool on the specified ESG.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    A pool manages load balancer distribution methods and has a service monitor 
    attached to it for health check parameters.  Each Pool has one or more 
    members.  Prior to creating or updating a pool to add a member, a member
    spec describing the member needs to be created.
    
    This cmdlet creates a new LoadBalancer Pool on the specified ESG.

    .EXAMPLE
    Example1: Need to create member specs for each of the pool members first

    PS C:\> $WebMember1 = New-NsxLoadBalancerMemberSpec -name Web01 
        -IpAddress 192.168.200.11 -Port 80
    
    PS C:\> $WebMember2 = New-NsxLoadBalancerMemberSpec -name Web02 
        -IpAddress 192.168.200.12 -Port 80 -MonitorPort 8080 
        -MaximumConnections 100

    PS C:\> $WebPool = $ESG | New-NsxLoadBalancerPool -Name WebPool 
        -Description "WebServer Pool" -Transparent:$false -Algorithm round-robin
        -Monitor $monitor -MemberSpec $WebMember1,$WebMember2
   
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if we have an ID property
                if ($_ -is [System.Xml.XmlElement] ) {
                    if ( $_ | get-member -name edgeSummary -memberType Properties) { 
                        if ( -not ( $_.edgeSummary | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.objectId property."}
                        if ( -not ( $_.edgeSummary | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.ObjectTypeName property."}
                        if ( -not ( $_.edgeSummary | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.name property."}
                        if ( -not ( $_ | get-member -name type -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ($_.edgeSummary.objectTypeName -ne "Edge" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                        if ($_.type -ne "gatewayServices" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                    }   
                }
                $true
            })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$False)]
            [ValidateNotNull()]
            [string]$Description="",
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [switch]$Transparent,
        [Parameter (Mandatory=$True)]
            [ValidateSet("round-robin", "ip-hash", "uri", "leastconn")]
            [string]$Algorithm,
        [Parameter (Mandatory=$true)]
            [ValidateScript({
                #Check if it looks like an LB monitor element
                if ($_ -is [System.Xml.XmlElement] ) {

                    if ( -not ( $_ | get-member -name monitorId -Membertype Properties)) { throw "XML Element specified does not contain a version property."}
                    if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                    if ( -not ( $_ | get-member -name type -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                
                }
 
                $true
            })]
            [System.Xml.XmlElement]$Monitor,
        [Parameter (Mandatory=$true)]
            [ValidateScript({
                #Check if we have an ID property
                if ($_ -is [System.Xml.XmlElement] ) {
                    if ( -not ( $_ | get-member -name name -Membertype Properties)) { 
                            throw "XML Element specified does not contain a name property.  Create with New-NsxLoadbalancerMemberSpec"}
                    if ( -not ( $_ | get-member -name ipAddress -Membertype Properties)) { 
                            throw "XML Element specified does not contain an ipAddress property.  Create with New-NsxLoadbalancerMemberSpec"}
                    if ( -not ( $_ | get-member -name weight -Membertype Properties)) { 
                            throw "XML Element specified does not contain a weight property.  Create with New-NsxLoadbalancerMemberSpec"}
                    if ( -not ( $_ | get-member -name port -Membertype Properties)) { 
                        throw "XML Element specified does not contain a port property.  Create with New-NsxLoadbalancerMemberSpec"}
                    if ( -not ( $_ | get-member -name minConn -Membertype Properties)) { 
                        throw "XML Element specified does not contain a minConn property.  Create with New-NsxLoadbalancerMemberSpec"}
                    if ( -not ( $_ | get-member -name maxConn -Membertype Properties)) { 
                        throw "XML Element specified does not contain a maxConn property.  Create with New-NsxLoadbalancerMemberSpec"}                       
                }
                $true
            })]
            [System.Xml.XmlElement[]]$MemberSpec
        
    )

    begin {
    }

    process {
        
        #Create the XMLDoc and import the LB node.
        [System.XML.XMLDocument]$xmlDoc = new-object System.XML.XMLDocument
        [System.XML.XMLElement]$loadbalancer = $xmlDoc.ImportNode(($edge.features.loadBalancer), $true)

        if ( -not $loadBalancer.enabled -eq 'true' ) { throw "Load Balancer feature is not enabled on edge $($edge.Name).  Use Set-NsxEdgeServicesGateway -EnableLoadBalancing to enable."}

        [System.XML.XMLElement]$xmlPool = $xmlDoc.CreateElement("pool")
        $loadbalancer.appendChild($xmlPool) | out-null

     
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlPool -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlPool -xmlElementName "description" -xmlElementText $Description
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlPool -xmlElementName "transparent" -xmlElementText $Transparent 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlPool -xmlElementName "algorithm" -xmlElementText $algorithm 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlPool -xmlElementName "monitorId" -xmlElementText $Monitor.monitorId 

        foreach ( $Member in $MemberSpec ) { 
            $xmlmember = $xmlPool.OwnerDocument.ImportNode($Member, $true)
            $xmlPool.AppendChild($xmlmember) | out-null
        }
            
        $URI = "/api/4.0/edges/$($Edge.Edgesummary.ObjectId)/loadbalancer/config"
        $body = $loadbalancer.OuterXml 
    
        Write-Progress -activity "Update Edge Services Gateway $($Edge.Name)" -status "Load Balancing Config"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body
        write-progress -activity "Update Edge Services Gateway $($Edge.Name)" -completed

        $edge = Get-NsxEdgeServicesGateway -objectId $($Edge.Edgesummary.ObjectId)
        $edge.features.loadBalancer.pool | ? { $_.name -eq $Name }

    }

    end {}

}
Export-ModuleMember -Function New-NsxLoadBalancerPool

function Get-NsxLoadBalancerPool {

    <#
    .SYNOPSIS
    Retrieves LoadBalancer Pools Profiles from the specified LoadBalancer.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    A pool manages load balancer distribution methods and has a service monitor 
    attached to it for health check parameters.  Each Pool has one or more 
    members.  Prior to creating or updating a pool to add a member, a member
    spec describing the member needs to be created.
    
    This cmdlet retrieves LoadBalancer pools from the specified LoadBalancer.

    .EXAMPLE
   
    PS C:\> Get-NsxEdgeServicesGateway | Get-NsxLoadBalancer | 
        Get-NsxLoadBalancerPool
    
    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if it looks like an LB element
                if ($_ -is [System.Xml.XmlElement] ) {

                    if ( -not ( $_ | get-member -name version -Membertype Properties)) { throw "XML Element specified does not contain an version property."}
                    if ( -not ( $_ | get-member -name enabled -Membertype Properties)) { throw "XML Element specified does not contain an enabled property."}
                }
 
                $true
            })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$true,ParameterSetName="poolId")]
            [string]$PoolId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name

    )

    begin {}

    process { 
        
        if ( $Name) { 
            $loadbalancer.pool | ? { $_.name -eq $Name }
        }
        elseif ( $monitorId ) { 
            $loadbalancer.pool | ? { $_.poolId -eq $PoolId }
        }
        else { 
            $loadbalancer.pool 
        }
    }

    end{ }

}
Export-ModuleMember -Function Get-NsxLoadBalancerPool

function New-NsxLoadBalancerVip {

    <#
    .SYNOPSIS
    Creates a new LoadBalancer Virtual Server on the specified ESG.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    A Virtual Server binds an IP address (must already exist on an ESG vNic as 
    either a Primary or Secondary Address) and a port to a LoadBalancer Pool and 
    Application Profile.

    This cmdlet creates a new Load Balancer VIP.

    .EXAMPLE
    Example1: Need to create member specs for each of the pool members first

    PS C:\> $WebVip = Get-NsxEdgeServicesGateway DMZ_Edge_2 | 
        New-NsxLoadBalancerVip -Name WebVip -Description "Test Creating a VIP" 
        -IpAddress $edge_uplink_ip -Protocol http -Port 80 
        -ApplicationProfile $AppProfile -DefaultPool $WebPool 
        -AccelerationEnabled
   
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({
                #Check if we have an ID property
                if ($_ -is [System.Xml.XmlElement] ) {
                    if ( $_ | get-member -name edgeSummary -memberType Properties) { 
                        if ( -not ( $_.edgeSummary | get-member -name objectId -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.objectId property."}
                        if ( -not ( $_.edgeSummary | get-member -name objectTypeName -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.ObjectTypeName property."}
                        if ( -not ( $_.edgeSummary | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain an edgesummary.name property."}
                        if ( -not ( $_ | get-member -name type -Membertype Properties)) { throw "XML Element specified does not contain a type property."}
                        if ($_.edgeSummary.objectTypeName -ne "Edge" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                        if ($_.type -ne "gatewayServices" ) { throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway." }
                    }   
                }
                $true
            })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$False)]
            [ValidateNotNull()]
            [string]$Description="",
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [IpAddress]$IpAddress,
        [Parameter (Mandatory=$True)]
            [ValidateSet("http", "https", "tcp", "udp")]
            [string]$Protocol,
        [Parameter (Mandatory=$True)]
            [ValidateRange(1,65535)]
            [int]$Port,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullorEmpty()]
            [switch]$Enabled=$true,        
        [Parameter (Mandatory=$true)]
            [ValidateScript({
                #Check if it looks like an LB applicationProfile element
                if ($_ -is [System.Xml.XmlElement] ) {

                    if ( -not ( $_ | get-member -name applicationProfileId -Membertype Properties)) { throw "XML Element specified does not contain an applicationProfileId property."}
                    if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                    if ( -not ( $_ | get-member -name template -Membertype Properties)) { throw "XML Element specified does not contain a template property."}
                }
                $true
            })]
            [System.Xml.XmlElement]$ApplicationProfile,
        [Parameter (Mandatory=$true)]
            [ValidateScript({
                #Check if it looks like an LB pool element
                if ($_ -is [System.Xml.XmlElement] ) {

                    if ( -not ( $_ | get-member -name poolId -Membertype Properties)) { throw "XML Element specified does not contain an poolId property."}
                    if ( -not ( $_ | get-member -name name -Membertype Properties)) { throw "XML Element specified does not contain a name property."}
                }
                $true
            })]
            [System.Xml.XmlElement]$DefaultPool,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [switch]$AccelerationEnabled=$True,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [int]$ConnectionLimit=0,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [int]$ConnectionRateLimit=0
        
    )

    begin {
    }

    process {
        
        #Create the XMLDoc and import the LB node.
        [System.XML.XMLDocument]$xmlDoc = new-object System.XML.XMLDocument
        [System.XML.XMLElement]$loadbalancer = $xmlDoc.ImportNode(($edge.features.loadBalancer), $true)

        if ( -not $loadBalancer.enabled -eq 'true' ) { throw "Load Balancer feature is not enabled on edge $($edge.Name).  Use Set-NsxEdgeServicesGateway -EnableLoadBalancing to enable."}

        [System.XML.XMLElement]$xmlVIip = $xmlDoc.CreateElement("virtualServer")
        $loadbalancer.appendChild($xmlVIip) | out-null

     
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "description" -xmlElementText $Description
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "enabled" -xmlElementText $Enabled 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "ipAddress" -xmlElementText $IpAddress 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "protocol" -xmlElementText $Protocol 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "port" -xmlElementText $Port 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "connectionLimit" -xmlElementText $ConnectionLimit 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "connectionRateLimit" -xmlElementText $ConnectionRateLimit 
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "applicationProfileId" -xmlElementText $ApplicationProfile.applicationProfileId
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "defaultPoolId" -xmlElementText $DefaultPool.poolId
        Add-XmlElement -xmlDoc $xmlDoc -xmlRoot $xmlVIip -xmlElementName "accelerationEnabled" -xmlElementText $AccelerationEnabled

            
        $URI = "/api/4.0/edges/$($Edge.Edgesummary.ObjectId)/loadbalancer/config"
        $body = $loadbalancer.OuterXml 
    
        Write-Progress -activity "Update Edge Services Gateway $($Edge.Name)" -status "Load Balancing Config"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body
        write-progress -activity "Update Edge Services Gateway $($Edge.Name)" -completed

        $edge = Get-NsxEdgeServicesGateway -objectId $($Edge.Edgesummary.ObjectId)
        $edge.features.loadbalancer.virtualServer | ? { $_.Name -eq $name }
    }

    end {}

}
Export-ModuleMember -Function New-NsxLoadBalancerVip

########
########
# Extra functions - here we try to extend on the capability of the base API, rather than just exposing it...


function Get-NsxSecurityGroupEffectiveMembers {

    <#
    .SYNOPSIS
    Determines the effective memebership of a security group including dynamic
    members.

    .DESCRIPTION
    An NSX SecurityGroup can contain members (VMs, IP Addresses, MAC Addresses 
    or vNics) by virtue of static or dynamic inclusion.  This cmdlet determines 
    the static and dynamic membership of a given group.

    .EXAMPLE
   
    PS C:\>  Get-NsxSecurityGroup TestSG | Get-NsxSecurityGroupEffectiveMembers
   
    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateNotNull()]
            [System.Xml.XmlElement]$SecurityGroup

    )
    
    begin {

    }

    process {
     
        if ( $securityGroup| get-member -MemberType Properties -Name member ) { $StaticIncludes = $SecurityGroup.member } else { $StaticIncludes = $null }

        #Have to construct Dynamic Includes:
        #GET https://<nsxmgr-ip>/api/2.0/services/securitygroup/ObjectID/translation/virtualmachines 
        #GET https://<nsxmgr-ip>/api/2.0/services/securitygroup/ObjectID/translation/ipaddresses 
        #GET https://<nsxmgr-ip>/api/2.0/services/securitygroup/ObjectID/translation/macaddresses 
        #GET https://<nsxmgr-ip>/api/2.0/services/securitygroup/ObjectID/translation/vnics

        write-debug "Getting virtualmachine dynamic includes for SG $($SecurityGroup.Name)"
        $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.ObjectId)/translation/virtualmachines"
        $response = invoke-nsxrestmethod -method "get" -uri $URI
        if ( $response.GetElementsByTagName("vmnodes").haschildnodes) { $dynamicVMNodes = $response.GetElementsByTagName("vmnodes")} else { $dynamicVMNodes = $null }

         write-debug "Getting ipaddress dynamic includes for SG $($SecurityGroup.Name)"
        $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.ObjectId)/translation/ipaddresses"
        $response = invoke-nsxrestmethod -method "get" -uri $URI
        if ( $response.GetElementsByTagName("ipNodes").haschildnodes) { $dynamicIPNodes = $response.GetElementsByTagName("ipNodes") } else { $dynamicIPNodes = $null}

         write-debug "Getting macaddress dynamic includes for SG $($SecurityGroup.Name)"
        $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.ObjectId)/translation/macaddresses"
        $response = invoke-nsxrestmethod -method "get" -uri $URI
        if ( $response.GetElementsByTagName("macNodes").haschildnodes) { $dynamicMACNodes = $response.GetElementsByTagName("macNodes")} else { $dynamicMACNodes = $null}

         write-debug "Getting VNIC dynamic includes for SG $($SecurityGroup.Name)"
        $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.ObjectId)/translation/vnics"
        $response = invoke-nsxrestmethod -method "get" -uri $URI
        if ( $response.GetElementsByTagName("vnicNodes").haschildnodes) { $dynamicVNICNodes = $response.GetElementsByTagName("vnicNodes")} else { $dynamicVNICNodes = $null }

        $return = New-Object psobject
        $return | add-member -memberType NoteProperty -Name "StaticInclude" -value $StaticIncludes
        $return | add-member -memberType NoteProperty -Name "DynamicIncludeVM" -value $dynamicVMNodes
        $return | add-member -memberType NoteProperty -Name "DynamicIncludeIP" -value $dynamicIPNodes
        $return | add-member -memberType NoteProperty -Name "DynamicIncludeMAC" -value $dynamicMACNodes
        $return | add-member -memberType NoteProperty -Name "DynamicIncludeVNIC" -value $dynamicVNICNodes
        
        $return

    
    }

    end {}

}
Export-ModuleMember -Function Get-NsxSecurityGroupEffectiveMembers


function Where-NsxVMUsed {

    <#
    .SYNOPSIS
    Determines what what NSX Security Groups or Firewall Rules a given VM is 
    defined in.

    .DESCRIPTION
    Determining what NSX Security Groups or Firewall Rules a given VM is 
    defined in is difficult from the UI.

    This cmdlet provides this simple functionality.


    .EXAMPLE
   
    PS C:\>  Get-VM web01 | Where-NsxVMUsed

    #>


    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl]$VM
    )
    
    begin {

    }

    process {
     
        #Get Firewall rules
        $L3FirewallRules = Get-nsxFirewallSection | Get-NsxFirewallRule 
        $L2FirewallRules = Get-nsxFirewallSection -sectionType layer2sections  | Get-NsxFirewallRule -ruletype layer2sections

        #Get all SGs
        $securityGroups = Get-NsxSecuritygroup
        $MatchedSG = @()
        $MatchedFWL3 = @()
        $MatchedFWL2 = @()
        foreach ( $SecurityGroup in $securityGroups ) {

            $Members = $securityGroup | Get-NsxSecurityGroupEffectiveMembers

            write-debug "Checking securitygroup $($securitygroup.name) for VM $($VM.name)"
                    
            If ( $members.DynamicIncludeVM ) {
                foreach ( $member in $members.DynamicIncludeVM) {
                    if ( $member.vmnode.vmid -eq $VM.ExtensionData.MoRef.Value ) {
                        $MatchedSG += $SecurityGroup
                    }
                }
            }
        }

        write-debug "Checking L3 FirewallRules for VM $($VM.name)"
        foreach ( $FirewallRule in $L3FirewallRules ) {

            write-debug "Checking rule $($FirewallRule.Id) for VM $($VM.name)"
                
            If ( $FirewallRule | Get-Member -MemberType Properties -Name Sources) {
                foreach ( $Source in $FirewallRule.Sources.Source) {
                    if ( $Source.value -eq $VM.ExtensionData.MoRef.Value ) {
                        $MatchedFWL3 += $FirewallRule
                    }
                }
            }   
            If ( $FirewallRule| Get-Member -MemberType Properties -Name Destinations ) {
                foreach ( $Dest in $FirewallRule.Destinations.Destination) {
                    if ( $Dest.value -eq $VM.ExtensionData.MoRef.Value ) {
                        $MatchedFWL3 += $FirewallRule
                    }
                }
            }
            If ( $FirewallRule | Get-Member -MemberType Properties -Name AppliedToList) {
                foreach ( $AppliedTo in $FirewallRule.AppliedToList.AppliedTo) {
                    if ( $AppliedTo.value -eq $VM.ExtensionData.MoRef.Value ) {
                        $MatchedFWL3 += $FirewallRule
                    }
                }
            }
        }

        write-debug "Checking L2 FirewallRules for VM $($VM.name)"
        foreach ( $FirewallRule in $L2FirewallRules ) {

            write-debug "Checking rule $($FirewallRule.Id) for VM $($VM.name)"
                
            If ( $FirewallRule | Get-Member -MemberType Properties -Name Sources) {
                foreach ( $Source in $FirewallRule.Sources.Source) {
                    if ( $Source.value -eq $VM.ExtensionData.MoRef.Value ) {
                        $MatchedFWL2 += $FirewallRule
                    }
                }
            }   
            If ( $FirewallRule | Get-Member -MemberType Properties -Name Destinations ) {
                foreach ( $Dest in $FirewallRule.Destinations.Destination) {
                    if ( $Dest.value -eq $VM.ExtensionData.MoRef.Value ) {
                        $MatchedFWL2 += $FirewallRule
                    }
                }
            }
            If ( $FirewallRule | Get-Member -MemberType Properties -Name AppliedToList) {
                foreach ( $AppliedTo in $FirewallRule.AppliedToList.AppliedTo) {
                    if ( $AppliedTo.value -eq $VM.ExtensionData.MoRef.Value ) {
                        $MatchedFWL2 += $FirewallRule
                    }
                }
            }
        }         

        $return = new-object psobject
        $return | add-member -memberType NoteProperty -Name "MatchedSecurityGroups" -value $MatchedSG
        $return | add-member -memberType NoteProperty -Name "MatchedL3FirewallRules" -value $MatchedFWL3
        $return | add-member -memberType NoteProperty -Name "MatchedL2FirewallRules" -value $MatchedFWL2
          
        $return

    }

    end {}

}
Export-ModuleMember -Function Where-NsxVMUsed



