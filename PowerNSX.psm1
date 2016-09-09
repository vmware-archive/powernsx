#Powershell NSX module
#Nick Bradford
#nbradford@vmware.com
#Version - See Manifest for version details.


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

#More sophisticated requirement checking done at module load time.

#My installer home and valid PNSX branches (releases) (used in Update-Powernsx.)
$PNsxUrlBase = "https://raw.githubusercontent.com/vmware/powernsx"
$ValidBranches = @("master","v1","v2")


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
        "VMware.VimAutomation.Vds.Types"
    )


    $CurrentAsmName = foreach( $asm in ([AppDomain]::CurrentDomain.GetAssemblies())) { $asm.getName() } 
    $CurrentAsmDict = $CurrentAsmName | Group-Object -AsHashTable -Property Name

    foreach( $req in $RequiredAsm ) { 

        if ( -not $CurrentAsmDict.Contains($req) ) { 
            write-warning "PowerNSX requires PowerCLI."
            throw "Assembly $req not found.  Some required PowerCli types are not available in this PowerShell session.  Please ensure you are running PowerNSX in a PowerCLI session, or have manually loaded the required assemblies."}
    }
}

#Check required PowerCLI assemblies are loaded.
Check-PowerCliAsemblies

########
########
# Private functions

Function Test-WebServerSSL {  
    # Function original location: http://en-us.sysadmins.lv/Lists/Posts/Post.aspx?List=332991f0-bfed-4143-9eea-f521167d287c&ID=60  
    # Ref : https://communities.vmware.com/thread/501913?start=0&tstart=0 - Thanks Alan ;)


    [CmdletBinding()]  

    param(  
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]  
        [string]$URL,  
        [Parameter(Position = 1)]  
        [ValidateRange(1,65535)]  
        [int]$Port = 443,  
        [Parameter(Position = 2)]  
        [Net.WebProxy]$Proxy,  
        [Parameter(Position = 3)]  
        [int]$Timeout = 15000,  
        [switch]$UseUserContext  
    )  

Add-Type @"  
using System;  
using System.Net;  
using System.Security.Cryptography.X509Certificates;  
namespace PKI {  
    namespace Web {  
        public class WebSSL {  
            public Uri OriginalURi;  
            public Uri ReturnedURi;  
            public X509Certificate2 Certificate;  
            //public X500DistinguishedName Issuer;  
            //public X500DistinguishedName Subject;  
            public string Issuer;  
            public string Subject;  
            public string[] SubjectAlternativeNames;  
            public bool CertificateIsValid;  
            //public X509ChainStatus[] ErrorInformation;  
            public string[] ErrorInformation;  
            public HttpWebResponse Response;  
        }  
    }  
}  
"@  

    $ConnectString = "https://$url`:$port"  
    $WebRequest = [Net.WebRequest]::Create($ConnectString)  
    $WebRequest.Proxy = $Proxy  
    $WebRequest.Credentials = $null  
    $WebRequest.Timeout = $Timeout  
    $WebRequest.AllowAutoRedirect = $true  
    [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}  
    try {$Response = $WebRequest.GetResponse()}  
    catch {}  
    if ($WebRequest.ServicePoint.Certificate -ne $null) {  
        $Cert = [Security.Cryptography.X509Certificates.X509Certificate2]$WebRequest.ServicePoint.Certificate.Handle  
        try {$SAN = ($Cert.Extensions | Where-Object {$_.Oid.Value -eq "2.5.29.17"}).Format(0) -split ", "}  
        catch {$SAN = $null}  
        $chain = New-Object Security.Cryptography.X509Certificates.X509Chain -ArgumentList (!$UseUserContext)  
        [void]$chain.ChainPolicy.ApplicationPolicy.Add("1.3.6.1.5.5.7.3.1")  
        $Status = $chain.Build($Cert)  
        New-Object PKI.Web.WebSSL -Property @{  
            OriginalUri = $ConnectString;  
            ReturnedUri = $Response.ResponseUri;  
            Certificate = $WebRequest.ServicePoint.Certificate;  
            Issuer = $WebRequest.ServicePoint.Certificate.Issuer;  
            Subject = $WebRequest.ServicePoint.Certificate.Subject;  
            SubjectAlternativeNames = $SAN;  
            CertificateIsValid = $Status;  
            Response = $Response;  
            ErrorInformation = $chain.ChainStatus | ForEach-Object {$_.Status}  
        }  
        $chain.Reset()  
        [Net.ServicePointManager]::ServerCertificateValidationCallback = $null  
        $ServicePoint = [System.Net.ServicePointManager]::FindServicePoint($ConnectString)
        $ServicePoint.CloseConnectionGroup("") | out-null
        write-debug "$($MyInvocation.MyCommand.Name) : Closing connections to $ConnectString."
    } else {  
        Write-Error $Error[0]  
    }  
}  

function Add-XmlElement {

    #Internal function used to simplify the exercise of adding XML text Nodes.
    param ( 

        [System.XML.XMLElement]$xmlRoot,
        [String]$xmlElementName,
        [String]$xmlElementText
    )

    #Create an Element and append it to the root
    [System.XML.XMLElement]$xmlNode = $xmlRoot.OwnerDocument.CreateElement($xmlElementName)
    [System.XML.XMLNode]$xmlText = $xmlRoot.OwnerDocument.CreateTextNode($xmlElementText)
    $xmlNode.AppendChild($xmlText) | out-null
    $xmlRoot.AppendChild($xmlNode) | out-null
}

function Get-FeatureStatus { 

    param ( 

        [string]$featurestring,
        [system.xml.xmlelement[]]$statusxml
        )

    [system.xml.xmlelement]$feature = $statusxml | ? { $_.featureId -eq $featurestring } | select -first 1
    [string]$statusstring = $feature.status
    $message = $feature.SelectSingleNode('message')
    if ( $message -and ( $message | get-member -membertype Property -Name '#Text')) { 
        $statusstring += " ($($message.'#text'))"
    }
    $statusstring
}

function Parse-CentralCliResponse {

    param (
        [Parameter ( Mandatory=$True, Position=1)]
            [String]$response
    )


    #Response is straight text unfortunately, so there is no structure.  Having a crack at writing a very simple parser though the formatting looks.... challenging...
    
    #Control flags for handling list and table processing.
    $TableHeaderFound = $false
    $MatchedVnicsList = $false
    $MatchedRuleset = $false
    $MatchedAddrSet = $false

    $RuleSetName = ""
    $AddrSetName = ""

    $KeyValHash = @{}
    $KeyValHashUsed = $false

    #Defined this as variable as the swtich statement does not let me concat strings, which makes for a verrrrry long line...
    $RegexDFWRule = "^(?<Internal>#\sinternal\s#\s)?(?<RuleSetMember>rule\s)?(?<RuleId>\d+)\sat\s(?<Position>\d+)\s(?<Direction>in|out|inout)\s" + 
            "(?<Type>protocol|ethertype)\s(?<Service>.*?)\sfrom\s(?<Source>.*?)\sto\s(?<Destination>.*?)(?:\sport\s(?<Port>.*))?\s" + 
            "(?<Action>accept|reject|drop)(?:\swith\s(?<Log>log))?(?:\stag\s(?<Tag>'.*'))?;"



    foreach ( $line in ($response -split '[\r\n]')) { 

        #Init EntryHash hashtable
        $EntryHash= @{}

        switch -regex ($line.trim()) {

            #C CLI appears to emit some error conditions as ^ Error:<digits> 
            "^Error \d+:.*$" {

                write-debug "$($MyInvocation.MyCommand.Name) : Matched Error line. $_ "
                
                Throw "CLI command returned an error: ( $_ )"

            }

            "^\s*$" { 
                #Blank line, ignore...
                write-debug "$($MyInvocation.MyCommand.Name) : Ignoring blank line: $_"
                break

            }

            "^# Filter rules$" { 
                #Filter line encountered in a ruleset list, ignore...
                if ( $MatchedRuleSet ) { 
                    write-debug "$($MyInvocation.MyCommand.Name) : Ignoring meaningless #Filter rules line in ruleset: $_"
                    break
                }
                else {
                    throw "Error parsing Centralised CLI command output response.  Encountered #Filter rules line when not processing a ruleset: $_"
                }

            }
            #Matches a single integer of 1 or more digits at the start of the line followed only by a fullstop.
            #Example is the Index in a VNIC list.  AFAIK, the index should only be 1-9. but just in case we are matching 1 or more digit...
            "^(\d+)\.$" { 

                write-debug "$($MyInvocation.MyCommand.Name) : Matched Index line.  Discarding value: $_ "
                If ( $MatchedVnicsList ) { 
                    #We are building a VNIC list output and this is the first line.
                    #Init the output object to static kv props, but discard the value (we arent outputing as it appears superfluous.)
                    write-debug "$($MyInvocation.MyCommand.Name) : Processing Vnic List, initialising new Vnic list object"

                    $VnicListHash = @{}
                    $VnicListHash += $KeyValHash
                    $KeyValHashUsed = $true

                }
                break
            } 

            #Matches the start of a ruleset list.  show dfw host host-xxx filter xxx rules will output in rulesets like this
            "ruleset\s(\S+) {" {

                #Set a flag to say we matched a ruleset List, and create the output object.
                write-debug "$($MyInvocation.MyCommand.Name) : Matched start of DFW Ruleset output.  Processing following lines as DFW Ruleset: $_"
                $MatchedRuleset = $true 
                $RuleSetName = $matches[1].trim()
                break        
            }

            #Matches the start of a addrset list.  show dfw host host-xxx filter xxx addrset will output in addrsets like this
            "addrset\s(\S+) {" {

                #Set a flag to say we matched a addrset List, and create the output object.
                write-debug "$($MyInvocation.MyCommand.Name) : Matched start of DFW Addrset output.  Processing following lines as DFW Addrset: $_"
                $MatchedAddrSet = $true 
                $AddrSetName = $matches[1].trim()
                break        
            }

            #Matches a addrset entry.  show dfw host host-xxx filter xxx addrset will output in addrsets.
            "^(?<Type>ip|mac)\s(?<Address>.*),$" {

                #Make sure we were expecting it...
                if ( -not $MatchedAddrSet ) {
                    Throw "Error parsing Centralised CLI command output response.  Unexpected dfw addrset entry : $_" 
                }

                #We are processing a RuleSet, so we need to emit an output object that contains the ruleset name.
                [PSCustomobject]@{
                    "AddrSet" = $AddrSetName;
                    "Type" = $matches.Type;
                    "Address" = $matches.Address
                }

                break
            }

            #Matches a rule, either within a ruleset, or individually listed.  show dfw host host-xxx filter xxx rules will output in rulesets, 
            #or show dfw host-xxx filter xxx rule 1234 will output individual rule that should match.
            $RegexDFWRule {

                #Check if the rule is individual or part of ruleset...
                if ( $Matches.ContainsKey("RuleSetMember") -and (-not $MatchedRuleset )) {
                    Throw "Error parsing Centralised CLI command output response.  Unexpected dfw ruleset entry : $_" 
                }

                $Type = switch ( $matches.Type ) { "protocol" { "Layer3" } "ethertype" { "Layer2" }}
                $Internal = if ( $matches.ContainsKey("Internal")) { $true } else { $false }
                $Port = if ( $matches.ContainsKey("Port") ) { $matches.port } else { "Any" } 
                $Log = if ( $matches.ContainsKey("Log") ) { $true } else { $false } 
                $Tag = if ( $matches.ContainsKey("Tag") ) { $matches.Tag } else { "" } 

                If ( $MatchedRuleset ) {

                    #We are processing a RuleSet, so we need to emit an output object that contains the ruleset name.
                    [PSCustomobject]@{
                        "RuleSet" = $RuleSetName;
                        "InternalRule" = $Internal;
                        "RuleID" = $matches.RuleId;
                        "Position" = $matches.Position;
                        "Direction" = $matches.Direction;
                        "Type" = $Type;
                        "Service" = $matches.Service;
                        "Source" = $matches.Source;
                        "Destination" = $matches.Destination;
                        "Port" = $Port;
                        "Action" = $matches.Action;
                        "Log" = $Log;
                        "Tag" = $Tag

                    }
                }

                else {
                    #We are not processing a RuleSet; so we need to emit an output object without a ruleset name.
                    [PSCustomobject]@{
                        "InternalRule" = $Internal;
                        "RuleID" = $matches.RuleId;
                        "Position" = $matches.Position;
                        "Direction" = $matches.Direction;
                        "Type" = $Type;
                        "Service" = $matches.Service;
                        "Source" = $matches.Source;
                        "Destination" = $matches.Destination;
                        "Port" = $Port;
                        "Action" = $matches.Action;
                        "Log" = $Log;
                        "Tag" = $Tag
                    }
                }

                break
            }

            #Matches the end of a ruleset and addr lists.  show dfw host host-xxx filter xxx rules will output in lists like this
            "^}$" {

                if ( $MatchedRuleset ) { 

                    #Clear the flag to say we matched a ruleset List
                    write-debug "$($MyInvocation.MyCommand.Name) : Matched end of DFW ruleset."
                    $MatchedRuleset = $false
                    $RuleSetName = ""
                    break     
                }

                if ( $MatchedAddrSet ) { 
                   
                    #Clear the flag to say we matched an addrset List
                    write-debug "$($MyInvocation.MyCommand.Name) : Matched end of DFW addrset."
                    $MatchedAddrSet = $false
                    $AddrSetName = ""
                    break     
                }

                throw "Error parsing Centralised CLI command output response.  Encountered unexpected list completion character in line: $_"
            }

            #More Generic matches

            #Matches the generic KV case where we have _only_ two strings separated by more than one space.
            #This will do my head in later when I look at it, so the regex explanation is:
            #    - (?: gives non capturing group, we want to leverage $matches later, so dont want polluting groups.
            #    - (\S|\s(?!\s)) uses negative lookahead assertion to 'Match a non whitespace, or a single whitespace, as long as its not followed by another whitespace.
            #    - The rest should be self explanatory.
            "^((?:\S|\s(?!\s))+\s{2,}){1}((?:\S|\s(?!\s))+)$" { 

                write-debug "$($MyInvocation.MyCommand.Name) : Matched Key Value line (multispace separated): $_ )"
                
                $key = $matches[1].trim()
                $value = $matches[2].trim()
                If ( $MatchedVnicsList ) { 
                    #We are building a VNIC list output and this is one of the lines.
                    write-debug "$($MyInvocation.MyCommand.Name) : Processing Vnic List, Adding $key = $value to current VnicListHash"

                    $VnicListHash.Add($key,$value)

                    if ( $key -eq "Filters" ) {

                        #Last line in a VNIC List...
                        write-debug "$($MyInvocation.MyCommand.Name) : VNIC List :  Outputing VNIC List Hash."
                        [PSCustomobject]$VnicListHash
                    }
                }
                else {
                    #Add KV to hash table that we will append to output object
                    $KeyValHash.Add($key,$value)
                }     
                break
            }

            #Matches a general case output line containing Key: Value for properties that are consistent accross all entries in a table. 
            #This will match a line with multiple colons in it, not sure if thats an issue yet...
            "^((?:\S|\s(?!\s))+):((?:\S|\s(?!\s))+)$" {
                if ( $TableHeaderFound ) { Throw "Error parsing Centralised CLI command output response.  Key Value line found after header: ( $_ )" }
                write-debug "$($MyInvocation.MyCommand.Name) : Matched Key Value line (Colon Separated) : $_"
                
                #Add KV to hash table that we will append to output object
                $KeyValHash.Add($matches[1].trim(),$matches[2].trim())

                break
            }

            #Matches a Table header line.  This is a special case of the table entry line match, with the first element being ^No\.  Hoping that 'No.' start of the line is consistent :S
            "^No\.\s{2,}(.+\s{2,})+.+$" {
                if ( $TableHeaderFound ) { 
                    throw "Error parsing Centralised CLI command output response.  Matched header line more than once: ( $_ )"
                }
                write-debug "$($MyInvocation.MyCommand.Name) : Matched Table Header line: $_"
                $TableHeaderFound = $true
                $Props = $_.trim() -split "\s{2,}"
                break
            }

            #Matches the start of a Virtual Nics List output.  We process the output lines following this as a different output object
            "Virtual Nics List:" {
                #When central cli outputs a NIC 'list' it does so with a vertical list of Key Value rather than a table format, 
                #and with multi space as the KV separator, rather than a : like normal KV output.  WTF?
                #So Now I have to go forth and collate my nic object over the next few lines...
                #Example looks like this:

                #Virtual Nics List:
                #1.
                #Vnic Name      test-vm - Network adapter 1
                #Vnic Id        50012d15-198c-066c-af22-554aed610579.000
                #Filters        nic-4822904-eth0-vmware-sfw.2

                #Set a flag to say we matched a VNic List, and create the output object initially with just the KV's matched already.
                write-debug "$($MyInvocation.MyCommand.Name) : Matched VNIC List line.  Processing remaining lines as Vnic List: $_"
                $MatchedVnicsList = $true 
                break                       

            }

            #Matches a table entry line.  At least three properties (that may contain a single space) separated by more than one space.
            "^((?:\S|\s(?!\s))+\s{2,}){2,}((?:\S|\s(?!\s))+)$" {
                if ( -not $TableHeaderFound ) { 
                    throw "Error parsing Centralised CLI command output response.  Matched table entry line before header: ( $_ )"
                }
                write-debug "$($MyInvocation.MyCommand.Name) : Matched Table Entry line: $_"
                $Vals = $_.trim() -split "\s{2,}"
                if ($Vals.Count -ne $Props.Count ) { 
                    Throw "Error parsing Centralised CLI command output response.  Table entry line contains different value count compared to properties count: ( $_ )"
                }

                #Build the output hashtable with the props returned in the table entry line
                for ( $i= 0; $i -lt $props.count; $i++ ) {

                    #Ordering is hard, and No. entry is kinda superfluous, so removing it from output (for now)
                    if ( -not ( $props[$i] -eq "No." )) {
                        $EntryHash[$props[$i].trim()]=$vals[$i].trim()
                    }
                }

                #Add the KV pairs that were parsed before the table.
                try {

                    #This may fail if we have a key of the same name.  For the moment, Im going to assume that this wont happen...
                    $EntryHash += $KeyValHash
                    $KeyValHashUsed = $true
                }
                catch {
                    throw "Unable to append static Key Values to EntryHash output object.  Possibly due to a conflicting key"
                }

                #Emit the entry line as a PSCustomobject :)
                [PSCustomObject]$EntryHash
                break
            }
            default { throw "Unable to parse Centralised CLI output line : $($_ -replace '\s','_')" } 
        }
    }

    if ( (-not $KeyValHashUsed) -and $KeyValHash.count -gt 0 ) {

        #Some output is just key value, so, if it hasnt been appended to output object already, we will just emit it.
        #Not sure how this approach will work long term, but it works for show dfw vnic <>
        write-debug "$($MyInvocation.MyCommand.Name) : KeyValHash has not been used after all line processing, outputing as is: $_"
        [PSCustomObject]$KeyValHash
    }
}


########
########
# Validation Functions

function Validate-UpdateBranch {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    if ( $ValidBranches -contains $argument ) { 
        $true
    } else { 
        throw "Invalid Branch.  Specify one of the valid branches : $($Validbranches -join ", ")"
    } 
   
}
Function Validate-TransportZone {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    if ( $argument -is [system.xml.xmlelement] ) 
    {
        if ( -not ($argument | get-member -MemberType Property -Name objectId )) { 
            throw "Invalid Transport Zone object specified" 
        }
        if ( -not ($argument | get-member -MemberType Property -Name objectTypeName )) { 
            throw "Invalid Transport Zone object specified" 
        } 
        if ( -not ($argument.objectTypeName -eq "VdnScope")) { 
            throw "Invalid Transport Zone object specified" 
        }
        $true 
    }
    else { 
        throw "Invalid Transport Zone object specified"
    }
}

Function Validate-LogicalSwitchOrDistributedPortGroup {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )      

    if (-not (
        ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.DistributedPortGroupInterop] ) -or
        ($argument -is [System.Xml.XmlElement] )))
    { 
        throw "Must specify a distributed port group or a logical switch" 
    } 
    else {

        #Do we Look like XML describing a Logical Switch
        if ($argument -is [System.Xml.XmlElement] ) {
            if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
                throw "Object specified does not contain an objectId property.  Specify a Distributed PortGroup or Logical Switch object."
            }
            if ( -not ( $argument | get-member -name objectTypeName -Membertype Properties)) { 
                throw "Object specified does not contain a type property.  Specify a Distributed PortGroup or Logical Switch object."
            }
            if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
                throw "Object specified does not contain a name property.  Specify a Distributed PortGroup or Logical Switch object."
            }
            switch ($argument.objectTypeName) {
                "VirtualWire" { }
                default { throw "Object specified is not a supported type.  Specify a Distributed PortGroup or Logical Switch object." }
            }
        }
        else { 
            #Its a VDS type - no further Checking
        }   
    }
    $true
}

Function Validate-LogicalSwitchOrDistributedPortGroupOrStandardPortGroup {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )      

    if (-not (
        ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.VirtualPortGroupBaseInterop] ) -or
        ($argument -is [System.Xml.XmlElement] )))
    { 
        throw "Must specify a distributed port group, logical switch or standard port group" 
    } 


    #Do we Look like XML describing a Logical Switch
    if ($argument -is [System.Xml.XmlElement] ) {
        if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
            throw "Object specified does not contain an objectId property.  Specify a Distributed PortGroup, Standard PortGroup or Logical Switch object."
        }
        if ( -not ( $argument | get-member -name objectTypeName -Membertype Properties)) { 
            throw "Object specified does not contain a type property.  Specify a Distributed PortGroup, Standard PortGroup or Logical Switch object."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "Object specified does not contain a name property.  Specify a Distributed PortGroup, Standard PortGroup or Logical Switch object."
        }
        switch ($argument.objectTypeName) {
            "VirtualWire" { }
            default { throw "Object specified is not a supported type.  Specify a Distributed PortGroup, Standard PortGroup or Logical Switch object." }
        }
    }

    $true
}

Function Validate-IpPool {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an OSPF Area element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
            throw "XML Element specified does not contain an objectId property."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        if ( -not ( $argument | get-member -name usedPercentage -Membertype Properties)) { 
            throw "XML Element specified does not contain a usedPercentage property."
        }
        $true
    }
    else { 
        throw "Specify a valid IP Pool object."
    }
}

Function Validate-VdsContext {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name switch -Membertype Properties)) { 
            throw "XML Element specified does not contain a switch property."
        }
        if ( -not ( $argument | get-member -name mtu -Membertype Properties)) { 
            throw "XML Element specified does not contain an mtu property."
        }
        if ( -not ( $argument | get-member -name uplinkPortName -Membertype Properties)) { 
            throw "XML Element specified does not contain an uplinkPortName property."
        }
        if ( -not ( $argument | get-member -name promiscuousMode -Membertype Properties)) { 
            throw "XML Element specified does not contain a promiscuousMode property."
        }
        $true
    }
    else { 
        throw "Specify a valid Vds Context object."
    }
}

Function Validate-SegmentIdRange {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name Id -Membertype Properties)) { 
            throw "XML Element specified does not contain an Id property."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        if ( -not ( $argument | get-member -name begin -Membertype Properties)) { 
            throw "XML Element specified does not contain a begin property."
        }
        if ( -not ( $argument | get-member -name end -Membertype Properties)) { 
            throw "XML Element specified does not contain an end property."
        }
        $true
    }
    else { 
        throw "Specify a valid Segment Id Range object."
    }
}

Function Validate-DistributedSwitch {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )      

    if (-not ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.DistributedSwitchInterop] ))
    { 
        throw "Must specify a distributed switch" 
    } 
   
    $true
}

Function Validate-LogicalSwitch {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )      

    if (-not ($argument -is [System.Xml.XmlElement] ))
    { 
        throw "Must specify a logical switch" 
    } 
    else {

        #Do we Look like XML describing a Logical Switch
        
        if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
            throw "Object specified does not contain an objectId property.  Specify a Logical Switch object."
        }
        if ( -not ( $argument | get-member -name objectTypeName -Membertype Properties)) { 
            throw "Object specified does not contain a type property.  Specify a Logical Switch object."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "Object specified does not contain a name property.  Specify a Logical Switch object."
        }
        switch ($argument.objectTypeName) {
            "VirtualWire" { }
            default { throw "Object specified is not a supported type.  Specify a Logical Switch object." }
        }   
    }
    $true
}

Function Validate-LogicalRouterInterfaceSpec {

    Param (

        [Parameter (Mandatory=$true)]
        [object]$argument

    )     

    #temporary - need to script proper validation of a single valid NIC config for DLR (Edge and DLR have different specs :())
    if ( -not $argument ) { 
        throw "Specify at least one interface configuration as produced by New-NsxLogicalRouterInterfaceSpec.  Pass a collection of interface objects to configure more than one interface"
    }
    $true
}

Function Validate-EdgeInterfaceSpec {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #temporary - need to script proper validation of a single valid NIC config for DLR (Edge and DLR have different specs :())
    if ( -not $argument ) { 
        throw "Specify at least one interface configuration as produced by New-NsxLogicalRouterInterfaceSpec.  Pass a collection of interface objects to configure more than one interface"
    }
    $true
}

Function Validate-EdgeInterfaceAddress {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name primaryAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain a primaryAddress property."
        }
        if ( -not ( $argument | get-member -name subnetPrefixLength -Membertype Properties)) { 
            throw "XML Element specified does not contain a subnetPrefixLength property."
        }
        if ( -not ( $argument | get-member -name subnetMask -Membertype Properties)) { 
            throw "XML Element specified does not contain a subnetMask property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        if ( -not ( $argument | get-member -name interfaceIndex -Membertype Properties)) { 
            throw "XML Element specified does not contain an interfaceIndex property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge Interface Address."
    }
}

Function Validate-AddressGroupSpec {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name primaryAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain a primaryAddress property."
        }
        if ( -not ( $argument | get-member -name subnetPrefixLength -Membertype Properties)) { 
            throw "XML Element specified does not contain a subnetPrefixLength property."
        }
        $true
    }
    else { 
        throw "Specify a valid Interface Spec."
    }
}

Function Validate-LogicalRouter {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if we are an XML element
    if ($argument -is [System.Xml.XmlElement] ) {
        if ( $argument | get-member -name edgeSummary -memberType Properties) { 
            if ( -not ( $argument.edgeSummary | get-member -name objectId -Membertype Properties)) { 
                throw "XML Element specified does not contain an edgesummary.objectId property.  Specify a valid Logical Router Object"
            }
            if ( -not ( $argument.edgeSummary | get-member -name objectTypeName -Membertype Properties)) { 
                throw "XML Element specified does not contain an edgesummary.ObjectTypeName property.  Specify a valid Logical Router Object"
            }
            if ( -not ( $argument.edgeSummary | get-member -name name -Membertype Properties)) { 
                throw "XML Element specified does not contain an edgesummary.name property.  Specify a valid Logical Router Object"
            }
            if ( -not ( $argument | get-member -name type -Membertype Properties)) { 
                throw "XML Element specified does not contain a type property.  Specify a valid Logical Router Object"
            }
            if ($argument.edgeSummary.objectTypeName -ne "Edge" ) { 
                throw "Specified value is not a supported type.  Specify a valid Logical Router Object." 
            }
            if ($argument.type -ne "distributedRouter" ) { 
                throw "Specified value is not a supported type.  Specify a valid Logical Router Object." 
            }
            $true
        }
        else {
            throw "Specify a valid Logical Router Object"
        }   
    }
    else {
        throw "Specify a valid Logical Router Object"
    }
}

Function Validate-Edge {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if we are an XML element
    if ($argument -is [System.Xml.XmlElement] ) {
        if ( $argument | get-member -name edgeSummary -memberType Properties) { 
            if ( -not ( $argument.edgeSummary | get-member -name objectId -Membertype Properties)) { 
                throw "XML Element specified does not contain an edgesummary.objectId property.  Specify an NSX Edge Services Gateway object"
            }
            if ( -not ( $argument.edgeSummary | get-member -name objectTypeName -Membertype Properties)) { 
                throw "XML Element specified does not contain an edgesummary.ObjectTypeName property.  Specify an NSX Edge Services Gateway object"
            }
            if ( -not ( $argument.edgeSummary | get-member -name name -Membertype Properties)) { 
                throw "XML Element specified does not contain an edgesummary.name property.  Specify an NSX Edge Services Gateway object"
            }
            if ( -not ( $argument | get-member -name type -Membertype Properties)) { 
                throw "XML Element specified does not contain a type property.  Specify an NSX Edge Services Gateway object"
            }
            if ($argument.edgeSummary.objectTypeName -ne "Edge" ) { 
                throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway object." 
            }
            if ($argument.type -ne "gatewayServices" ) { 
                throw "Specified value is not a supported type.  Specify an NSX Edge Services Gateway object." 
            }
            $true
        }
        else {
            throw "Specify a valid Edge Services Gateway Object"
        }   
    }
    else {
        throw "Specify a valid Edge Services Gateway Object"
    }
}

Function Validate-EdgeRouting {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name routingGlobalConfig -Membertype Properties)) { 
            throw "XML Element specified does not contain a routingGlobalConfig property."
        }
        if ( -not ( $argument | get-member -name enabled -Membertype Properties)) { 
            throw "XML Element specified does not contain an enabled property."
        }
        if ( -not ( $argument | get-member -name version -Membertype Properties)) { 
            throw "XML Element specified does not contain a version property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge Routing object."
    }
}

Function Validate-EdgeStaticRoute {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name type -Membertype Properties)) { 
            throw "XML Element specified does not contain a type property."
        }
        if ( -not ( $argument | get-member -name network -Membertype Properties)) { 
            throw "XML Element specified does not contain a network property."
        }
        if ( -not ( $argument | get-member -name nextHop -Membertype Properties)) { 
            throw "XML Element specified does not contain a nextHop property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge Static Route object."
    }
}

Function Validate-EdgeBgpNeighbour {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name ipAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain an ipAddress property."
        }
        if ( -not ( $argument | get-member -name remoteAS -Membertype Properties)) { 
            throw "XML Element specified does not contain a remoteAS property."
        }
        if ( -not ( $argument | get-member -name weight -Membertype Properties)) { 
            throw "XML Element specified does not contain a weight property."
        }
        if ( -not ( $argument | get-member -name holdDownTimer -Membertype Properties)) { 
            throw "XML Element specified does not contain a holdDownTimer property."
        }
        if ( -not ( $argument | get-member -name keepAliveTimer -Membertype Properties)) { 
            throw "XML Element specified does not contain a keepAliveTimer property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge BGP Neighbour object."
    }
}

Function Validate-EdgeOspfArea {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an OSPF Area element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name areaId -Membertype Properties)) { 
            throw "XML Element specified does not contain an areaId property."
        }
        if ( -not ( $argument | get-member -name type -Membertype Properties)) { 
            throw "XML Element specified does not contain a type property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge OSPF Area object."
    }
}

Function Validate-EdgeOspfInterface {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an OSPF Area element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name areaId -Membertype Properties)) { 
            throw "XML Element specified does not contain an areaId property."
        }
        if ( -not ( $argument | get-member -name vnic -Membertype Properties)) { 
            throw "XML Element specified does not contain a vnic property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge OSPF Interface object."
    }
}

Function Validate-EdgeRedistributionRule {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an OSPF Area element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name learner -Membertype Properties)) { 
            throw "XML Element specified does not contain an areaId property."
        }
        if ( -not ( $argument | get-member -name id -Membertype Properties)) { 
            throw "XML Element specified does not contain an id property."
        }
        if ( -not ( $argument | get-member -name action -Membertype Properties)) { 
            throw "XML Element specified does not contain an action property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge Redistribution Rule object."
    }
}

Function Validate-LogicalRouterRouting {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an LogicalRouter routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name routingGlobalConfig -Membertype Properties)) { 
            throw "XML Element specified does not contain a routingGlobalConfig property."
        }
        if ( -not ( $argument | get-member -name enabled -Membertype Properties)) { 
            throw "XML Element specified does not contain an enabled property."
        }
        if ( -not ( $argument | get-member -name version -Membertype Properties)) { 
            throw "XML Element specified does not contain a version property."
        }
        if ( -not ( $argument | get-member -name logicalrouterId -Membertype Properties)) { 
            throw "XML Element specified does not contain an logicalrouterId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LogicalRouter Routing object."
    }
}

Function Validate-LogicalRouterStaticRoute {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an LogicalRouter routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name type -Membertype Properties)) { 
            throw "XML Element specified does not contain a type property."
        }
        if ( -not ( $argument | get-member -name network -Membertype Properties)) { 
            throw "XML Element specified does not contain a network property."
        }
        if ( -not ( $argument | get-member -name nextHop -Membertype Properties)) { 
            throw "XML Element specified does not contain a nextHop property."
        }
        if ( -not ( $argument | get-member -name logicalrouterId -Membertype Properties)) { 
            throw "XML Element specified does not contain an logicalrouterId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LogicalRouter Static Route object."
    }
}

Function Validate-LogicalRouterBgpNeighbour {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an LogicalRouter routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name ipAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain an ipAddress property."
        }
        if ( -not ( $argument | get-member -name remoteAS -Membertype Properties)) { 
            throw "XML Element specified does not contain a remoteAS property."
        }
        if ( -not ( $argument | get-member -name weight -Membertype Properties)) { 
            throw "XML Element specified does not contain a weight property."
        }
        if ( -not ( $argument | get-member -name holdDownTimer -Membertype Properties)) { 
            throw "XML Element specified does not contain a holdDownTimer property."
        }
        if ( -not ( $argument | get-member -name keepAliveTimer -Membertype Properties)) { 
            throw "XML Element specified does not contain a keepAliveTimer property."
        }
        if ( -not ( $argument | get-member -name logicalrouterId -Membertype Properties)) { 
            throw "XML Element specified does not contain an logicalrouterId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LogicalRouter BGP Neighbour object."
    }
}

Function Validate-LogicalRouterOspfArea {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an OSPF Area element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name areaId -Membertype Properties)) { 
            throw "XML Element specified does not contain an areaId property."
        }
        if ( -not ( $argument | get-member -name type -Membertype Properties)) { 
            throw "XML Element specified does not contain a type property."
        }
        if ( -not ( $argument | get-member -name logicalrouterId -Membertype Properties)) { 
            throw "XML Element specified does not contain an logicalrouterId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LogicalRouter OSPF Area object."
    }
}

Function Validate-LogicalRouterOspfInterface {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an OSPF Area element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name areaId -Membertype Properties)) { 
            throw "XML Element specified does not contain an areaId property."
        }
        if ( -not ( $argument | get-member -name vnic -Membertype Properties)) { 
            throw "XML Element specified does not contain a vnic property."
        }
        if ( -not ( $argument | get-member -name logicalrouterId -Membertype Properties)) { 
            throw "XML Element specified does not contain an logicalrouterId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LogicalRouter OSPF Interface object."
    }
}

Function Validate-LogicalRouterRedistributionRule {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an OSPF Area element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name learner -Membertype Properties)) { 
            throw "XML Element specified does not contain an areaId property."
        }
        if ( -not ( $argument | get-member -name id -Membertype Properties)) { 
            throw "XML Element specified does not contain an id property."
        }
        if ( -not ( $argument | get-member -name action -Membertype Properties)) { 
            throw "XML Element specified does not contain an action property."
        }
        if ( -not ( $argument | get-member -name logicalrouterId -Membertype Properties)) { 
            throw "XML Element specified does not contain an logicalrouterId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LogicalRouter Redistribution Rule object."
    }
}

Function Validate-EdgePrefix {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge prefix element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        if ( -not ( $argument | get-member -name ipAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain an ipAddress property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge Prefix object."
    }
}

Function Validate-LogicalRouterPrefix {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge prefix element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        if ( -not ( $argument | get-member -name ipAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain an ipAddress property."
        }
        if ( -not ( $argument | get-member -name logicalRouterId -Membertype Properties)) { 
            throw "XML Element specified does not contain an logicalRouterId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LogicalRouter Prefix object."
    }
}

Function Validate-EdgeInterface {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )    

    #Accepts an interface Object.
    if ($argument -is [System.Xml.XmlElement] ) {
        If ( $argument | get-member -name index -memberType Properties ) {

            #Looks like an interface object
            if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
                throw "XML Element specified does not contain a name property.  Specify a valid Edge Services Gateway Interface object."
            }
            if ( -not ( $argument | get-member -name label -Membertype Properties)) {
                throw "XML Element specified does not contain a label property.  Specify a valid Edge Services Gateway Interface object."
            }
            if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) {
                throw "XML Element specified does not contain an edgeId property.  Specify a valid Edge Services Gateway Interface object."
            }
        }
        else { 
            throw "Specify a valid Edge Services Gateway Interface object."
        }
    }
    else { 
        throw "Specify a valid Edge Services Gateway Interface object." 
    }
    $true
}

Function Validate-LogicalRouterInterface {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )    

    #Accepts an interface Object.
    if ($argument -is [System.Xml.XmlElement] ) {
        If ( $argument | get-member -name index -memberType Properties ) {

            #Looks like an interface object
            if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
                throw "XML Element specified does not contain a name property.  Specify a valid Logical Router Interface object"
            }
            if ( -not ( $argument | get-member -name label -Membertype Properties)) { 
                throw "XML Element specified does not contain a label property.  Specify a valid Logical Router Interface object"
            }
            if ( -not ( $argument | get-member -name logicalRouterId -Membertype Properties)) { 
                throw "XML Element specified does not contain an logicalRouterId property.  Specify a valid Logical Router Interface object"
            }
        }
        else { 
            throw "Specify a valid Logical Router Interface object."
        }
    }
    else { 
        throw "Specify a valid Logical Router Interface object." 
    }
    $true
}

Function Validate-EdgeSubInterface {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )  

    #Accepts a Subinterface Object.
    if ($argument -is [System.Xml.XmlElement] ) {
        If ( $argument | get-member -name vnicId -memberType Properties ) {

            #Looks like a Subinterface object
            if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
                throw "XML Element specified does not contain a edgeId property."
            }
            if ( -not ( $argument | get-member -name vnicId -Membertype Properties)) { 
                throw "XML Element specified does not contain a vnicId property."
            }
            if ( -not ( $argument | get-member -name index -Membertype Properties)) { 
                throw "XML Element specified does not contain an index property."
            }
            if ( -not ( $argument | get-member -name label -Membertype Properties)) { 
                throw "XML Element specified does not contain a label property."
            }
        }
        else { 
            throw "Object on pipeline is not a SubInterface object."
        }
    }
    else { 
        throw "Pipeline object was not a SubInterface object." 
    }
    $true
}

Function Validate-EdgeNat {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    #Check if it looks like an EdgeNAT element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name version -Membertype Properties)) { 
            throw "XML Element specified does not contain an version property."
        }
        if ( -not ( $argument | get-member -name enabled -Membertype Properties)) { 
            throw "XML Element specified does not contain an enabled property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        if ( -not ( $argument | get-member -name natRules -Membertype Properties)) { 
            throw "XML Element specified does not contain a natRules property."
        }
        $true
    }
    else { 
        throw "Specify a valid LoadBalancer object."
    }
}

Function Validate-EdgeNatRule {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    #Check if it looks like an EdgeNAT element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name ruleId -Membertype Properties)) { 
            throw "XML Element specified does not contain a ruleId property."
        }
        if ( -not ( $argument | get-member -name ruleType -Membertype Properties)) { 
            throw "XML Element specified does not contain a ruleType property."
        }
        if ( -not ( $argument | get-member -name action -Membertype Properties)) { 
            throw "XML Element specified does not contain an action property."
        }
        if ( -not ( $argument | get-member -name vnic -Membertype Properties)) { 
            throw "XML Element specified does not contain a vnic property."
        }
        if ( -not ( $argument | get-member -name translatedAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain a translatedAddress property."
        }
        if ( -not ( $argument | get-member -name originalAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain an originalAddress property."
        }
        if ( -not ( $argument | get-member -name enabled -Membertype Properties)) { 
            throw "XML Element specified does not contain an enabled property."
        }
        $true
    }
    else { 
        throw "Specify a valid LoadBalancer object."
    }
}

Function Validate-EdgeSslVpn {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name enabled -Membertype Properties)) { 
            throw "XML Element specified does not contain an enabled property."
        }
        if ( -not ( $argument | get-member -name logging -Membertype Properties)) { 
            throw "XML Element specified does not contain a logging property."
        }
        if ( -not ( $argument | get-member -name advancedConfig -Membertype Properties)) { 
            throw "XML Element specified does not contain an advancedConfig property."
        }
        if ( -not ( $argument | get-member -name clientConfiguration -Membertype Properties)) { 
            throw "XML Element specified does not contain a clientConfiguration property."
        }
        if ( -not ( $argument | get-member -name layoutConfiguration -Membertype Properties)) { 
            throw "XML Element specified does not contain a layoutConfiguration property."
        }
        if ( -not ( $argument | get-member -name authenticationConfiguration -Membertype Properties)) { 
            throw "XML Element specified does not contain a authenticationConfiguration property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge SSL VPN object."
    }
}

Function Validate-EdgeCsr { 

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name subject -Membertype Properties)) { 
            throw "XML Element specified does not contain a subject property."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        if ( -not ( $argument | get-member -name algorithm -Membertype Properties)) { 
            throw "XML Element specified does not contain an algorithm property."
        }
        if ( -not ( $argument | get-member -name keysize -Membertype Properties)) { 
            throw "XML Element specified does not contain a keysize property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge CSR object."
    }
}

Function Validate-EdgeCertificate { 

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name issuerCn -Membertype Properties)) { 
            throw "XML Element specified does not contain an issuerCn property."
        }
        if ( -not ( $argument | get-member -name subjectCn -Membertype Properties)) { 
            throw "XML Element specified does not contain a subjectCn property."
        }
        if ( -not ( $argument | get-member -name certificateType -Membertype Properties)) { 
            throw "XML Element specified does not contain a certificateType property."
        }
        if ( -not ( $argument | get-member -name x509Certificate -Membertype Properties)) { 
            throw "XML Element specified does not contain an x509Certificate property."
        }
        $true
    }
    else { 
        throw "Specify a valid Edge Certificate object."
    }
}

Function Validate-EdgeSslVpnUser { 

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
            throw "XML Element specified does not contain an objectId property."
        }
        if ( -not ( $argument | get-member -name userId -Membertype Properties)) { 
            throw "XML Element specified does not contain a userId property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeID property."
        }

        $true
    }
    else { 
        throw "Specify a valid Edge SSL VPN User object."
    }
}

Function Validate-EdgeSslVpnIpPool { 

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
            throw "XML Element specified does not contain an objectId property."
        }
        if ( -not ( $argument | get-member -name ipRange -Membertype Properties)) { 
            throw "XML Element specified does not contain a userId property."
        }
        if ( -not ( $argument | get-member -name netmask -Membertype Properties)) { 
            throw "XML Element specified does not contain a netmask property."
        }
        if ( -not ( $argument | get-member -name gateway -Membertype Properties)) { 
            throw "XML Element specified does not contain a gateway property."
        }
        if ( -not ( $argument | get-member -name enabled -Membertype Properties)) { 
            throw "XML Element specified does not contain an enabled property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeID property."
        }

        $true
    }
    else { 
        throw "Specify a valid Edge SSL VPN Ip Pool object."
    }
}

Function Validate-EdgeSslVpnPrivateNetwork { 

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
            throw "XML Element specified does not contain an objectId property."
        }
        if ( -not ( $argument | get-member -name network -Membertype Properties)) { 
            throw "XML Element specified does not contain a network property."
        }
        if ( -not ( $argument | get-member -name enabled -Membertype Properties)) { 
            throw "XML Element specified does not contain an enabled property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeID property."
        }

        $true
    }
    else { 
        throw "Specify a valid Edge SSL VPN Private Network object."
    }
}

Function Validate-EdgeSslVpnClientPackage { 

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )     

    #Check if it looks like an Edge routing element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
            throw "XML Element specified does not contain an objectId property."
        }
        if ( -not ( $argument | get-member -name profileName -Membertype Properties)) { 
            throw "XML Element specified does not contain a profileName property."
        }
        if ( -not ( $argument | get-member -name enabled -Membertype Properties)) { 
            throw "XML Element specified does not contain an enabled property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeID property."
        }

        $true
    }
    else { 
        throw "Specify a valid Edge SSL VPN Client Installation Package object."
    }
}

Function Validate-SecurityGroupMember { 
    
    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )  

    #Check types first - This is not 100% complete at this point!
    if (-not (
         ($argument -is [System.Xml.XmlElement]) -or 
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.DatacenterInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.VirtualPortGroupBaseInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ResourcePoolInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.VirtualDevice.NetworkAdapterInterop] ))) {

            throw "Member is not a supported type.  Specify a Datacenter, Cluster, `
            DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
            IPSet, SecurityGroup, SecurityTag or Logical Switch object."      
    } 
    else {

        #Check if we have an ID property
        if ($argument -is [System.Xml.XmlElement] ) {
            if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
                throw "XML Element specified does not contain an objectId property."
            }
            if ( -not ( $argument | get-member -name objectTypeName -Membertype Properties)) { 
                throw "XML Element specified does not contain a type property."
            }
            if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
                throw "XML Element specified does not contain a name property."
            }
            
            switch ($argument.objectTypeName) {

                "IPSet"{}
                "MacSet"{}
                "SecurityGroup" {}
                "VirtualWire" {}
                "SecurityTag" {}
                default { 
                    throw "Member is not a supported type.  Specify a Datacenter, Cluster, `
                         DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                         IPSet, MacSet, SecurityGroup, SecurityTag or Logical Switch object." 
                }
            }
        }   
    }
    $true
}

Function Validate-FirewallRuleSourceDest {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    
    #Same requirements for SG membership.
    Validate-SecurityGroupMember $argument    
}


Function Validate-ServiceGroup {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    if ( $argument -is [system.xml.xmlelement] ){ 
        if ( -not ($argument | get-member -MemberType Property -Name objectId )) {
            throw "Invalid service group specified"
        }
        if ( -not ($argument | get-member -MemberType Property -Name objectTypeName )) {
            throw "Invalid service group specified"
        }
        if ( -not ($argument.objectTypeName -eq "ApplicationGroup")){
            throw "Invalid service group specified"
        }
        $true
    }
    else {
        throw "Invalid Service Group specified"
    }
}


Function Validate-Service {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    if ( $argument -is [system.xml.xmlelement] ){ 
        if ( -not ($argument | get-member -MemberType Property -Name objectId )) {
            throw "Invalid service specified"
        }
        if ( -not ($argument | get-member -MemberType Property -Name objectTypeName )) {
            throw "Invalid service specified"
        }
        if ( -not ($argument.objectTypeName -eq "Application")){
            throw "Invalid service specified"
        }
        $true
    }
    else {
        throw "Invalid Service specified"
    }
}

Function Validate-ServiceOrServiceGroup {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    try {
        Validate-Service -argument $argument
    }
    catch {
        try {
            Validate-ServiceGroup -argument $argument 
        }
        catch {
            throw "Invalid Service or Service Group specific"
        }

    }
    $true
}
Function Validate-ServiceGroup {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    if ( $argument -is [system.xml.xmlelement] ){ 
        if ( -not ($argument | get-member -MemberType Property -Name objectId )) {
            throw "Invalid service group specified"
        }
        if ( -not ($argument | get-member -MemberType Property -Name objectTypeName )) {
            throw "Invalid service group specified"
        }
        if ( -not ($argument.objectTypeName -eq "ApplicationGroup")){
            throw "Invalid service group specified"
        }
        $true
    }
    else {
        throw "Invalid Service Group specified"
    }
}


Function Validate-Service {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    if ( $argument -is [system.xml.xmlelement] ){ 
        if ( -not ($argument | get-member -MemberType Property -Name objectId )) {
            throw "Invalid service specified"
        }
        if ( -not ($argument | get-member -MemberType Property -Name objectTypeName )) {
            throw "Invalid service specified"
        }
        if ( -not ($argument.objectTypeName -eq "Application")){
            throw "Invalid service specified"
        }
        $true
    }
    else {
        throw "Invalid Service specified"
    }
}

Function Validate-ServiceOrServiceGroup {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    try {
        Validate-Service -argument $argument
    }
    catch {
        try {
            Validate-ServiceGroup -argument $argument 
        }
        catch {
            throw "Invalid Service or Service Group specific"
        }

    }
    $true
}

Function Validate-FirewallAppliedTo {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    #Check types first
    if (-not (
         ($argument -is [System.Xml.XmlElement]) -or 
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.DatacenterInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VMHostInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.VirtualPortGroupBaseInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ResourcePoolInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop] ) -or
         ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.VirtualDevice.NetworkAdapterInterop] ))) {

            throw "$($_.gettype()) is not a supported type.  Specify a Datacenter, Cluster, Host `
            DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
            IPSet, SecurityGroup, Logical Switch or Edge object."
             
    } else {

        #Check if we have an ID property
        if ($argument -is [System.Xml.XmlElement] ) {

            if ( $argument | get-member -name edgeSummary ) {

                #Looks like an Edge, get the summary details... I KNEW this would come in handy when I wrote the Get-NSxEdge cmdlet... FIGJAM...
                $argument = $argument.edgeSummary
            }

            if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
                throw "XML Element specified does not contain an objectId property."
            }
            if ( -not ( $argument | get-member -name objectTypeName -Membertype Properties)) { 
                throw "XML Element specified does not contain a type property."
            }
            if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
                throw "XML Element specified does not contain a name property."
            }
            
            switch ($argument.objectTypeName) {

                "IPSet"{}
                "SecurityGroup" {}
                "VirtualWire" {}
                "Edge" {}
                default { 
                    throw "AppliedTo is not a supported type.  Specify a Datacenter, Cluster, Host, `
                        DistributedPortGroup, PortGroup, ResourcePool, VirtualMachine, NetworkAdapter, `
                        IPSet, SecurityGroup, Logical Switch or Edge object." 
                }
            }
        }   
    }
    $true
}

Function Validate-LoadBalancer {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    #Check if it looks like an LB element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name version -Membertype Properties)) { 
            throw "XML Element specified does not contain an version property."
        }
        if ( -not ( $argument | get-member -name enabled -Membertype Properties)) { 
            throw "XML Element specified does not contain an enabled property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LoadBalancer object."
    }
}

Function Validate-LoadBalancerMonitor {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    #Check if it looks like an LB monitor element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name monitorId -Membertype Properties)) { 
            throw "XML Element specified does not contain a version property."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        if ( -not ( $argument | get-member -name type -Membertype Properties)) { 
            throw "XML Element specified does not contain a type property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LoadBalancer Monitor object."
    }
}

Function Validate-LoadBalancerVip {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    #Check if it looks like an LB monitor element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name virtualServerId -Membertype Properties)) { 
            throw "XML Element specified does not contain a virtualServerId property."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        if ( -not ( $argument | get-member -name ipAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain an ipAddress property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        $true
    }
    else { 
        throw "Specify a valid LoadBalancer VIP object."
    }
}

Function Validate-LoadBalancerMemberSpec {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    if ($argument -is [System.Xml.XmlElement] ) {
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property.  Create with New-NsxLoadbalancerMemberSpec"
        }
        if ( -not ( $argument | get-member -name ipAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain an ipAddress property.  Create with New-NsxLoadbalancerMemberSpec"
        }
        if ( -not ( $argument | get-member -name weight -Membertype Properties)) { 
            throw "XML Element specified does not contain a weight property.  Create with New-NsxLoadbalancerMemberSpec"
        }
        if ( -not ( $argument | get-member -name port -Membertype Properties)) { 
            throw "XML Element specified does not contain a port property.  Create with New-NsxLoadbalancerMemberSpec"
        }
        if ( -not ( $argument | get-member -name minConn -Membertype Properties)) { 
            throw "XML Element specified does not contain a minConn property.  Create with New-NsxLoadbalancerMemberSpec"
        }
        if ( -not ( $argument | get-member -name maxConn -Membertype Properties)) { 
            throw "XML Element specified does not contain a maxConn property.  Create with New-NsxLoadbalancerMemberSpec"
        }            
        $true           
    }
    else { 
        throw "Specify a valid Member Spec object as created by New-NsxLoadBalancerMemberSpec."
    }
}

Function Validate-LoadBalancerApplicationProfile {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    #Check if it looks like an LB applicationProfile element
    if ($argument -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name applicationProfileId -Membertype Properties)) { 
            throw "XML Element specified does not contain an applicationProfileId property."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        if ( -not ( $argument | get-member -name template -Membertype Properties)) { 
            throw "XML Element specified does not contain a template property."
        }
        $True
    }
    else { 
        throw "Specify a valid LoadBalancer Application Profile object."
    }
}

Function Validate-LoadBalancerPool {
 
    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    #Check if it looks like an LB pool element
    if ($_ -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name poolId -Membertype Properties)) { 
            throw "XML Element specified does not contain an poolId property."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        $True
    }
    else { 
        throw "Specify a valid LoadBalancer Pool object."
    }
}

Function Validate-LoadBalancerPoolMember {
 
    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    #Check if it looks like an LB pool element
    if ($_ -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name poolId -Membertype Properties)) { 
            throw "XML Element specified does not contain an poolId property."
        }
        if ( -not ( $argument | get-member -name edgeId -Membertype Properties)) { 
            throw "XML Element specified does not contain an edgeId property."
        }
        if ( -not ( $argument | get-member -name ipAddress -Membertype Properties)) { 
            throw "XML Element specified does not contain an ipAddress property."
        }
        if ( -not ( $argument | get-member -name port -Membertype Properties)) { 
            throw "XML Element specified does not contain a port property."
        }
        if ( -not ( $argument | get-member -name name -Membertype Properties)) { 
            throw "XML Element specified does not contain a name property."
        }
        $True
    }
    else { 
        throw "Specify a valid LoadBalancer Pool Member object."
    }
}

Function Validate-SecurityTag {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    
    #Check if it looks like Security Tag element
    if ($_ -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name objectId -Membertype Properties)) { 
            throw "XML Element specified does not contain an objectId property."
        }
        if ( -not ( $argument | get-member -name Name -Membertype Properties)) { 
            throw "XML Element specified does not contain a Name property."
        }
        if ( -not ( $argument | get-member -name type -Membertype Properties)) { 
            throw "XML Element specified does not contain a type property."
        }
        if ( -not ( $argument.Type.TypeName -eq 'SecurityTag' )) { 
            throw "XML Element specifies a type other than SecurityTag."
        }
        $True
    }
    else { 
        throw "Specify a valid Security Tag object."
    }
}

Function Validate-SpoofguardPolicy {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    
    #Check if it looks like Security Tag element
    if ($_ -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name policyId -Membertype Properties)) { 
            throw "XML Element specified does not contain an policyId property."
        }
        if ( -not ( $argument | get-member -name Name -Membertype Properties)) { 
            throw "XML Element specified does not contain a Name property."
        }
        if ( -not ( $argument | get-member -name operationMode -Membertype Properties)) { 
            throw "XML Element specified does not contain an OperationMode property."
        }
        if ( -not ( $argument | get-member -name defaultPolicy -Membertype Properties)) { 
            throw "XML Element specified does not contain a defaultPolicy property."
        }
        $True
    }
    else { 
        throw "Specify a valid Spoofguard Policy object."
    }
}

Function Validate-SpoofguardNic {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    
    #Check if it looks like Security Tag element
    if ($_ -is [System.Xml.XmlElement] ) {

        if ( -not ( $argument | get-member -name id -Membertype Properties)) { 
            throw "XML Element specified does not contain an id property."
        }
        if ( -not ( $argument | get-member -name vnicUuid -Membertype Properties)) { 
            throw "XML Element specified does not contain a vnicUuid property."
        }
        if ( -not ( $argument | get-member -name policyId -Membertype Properties)) { 
            throw "XML Element specified does not contain a policyId property."
        }
        $True
    }
    else { 
        throw "Specify a valid Spoofguard Nic object."
    }
}

Function Validate-VirtualMachine {

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )

    if (-not ($argument -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop] )) {
            throw "Object is not a supported type.  Specify a VirtualMachine object."
    }

    $true
}

Function Validate-TagAssignment { 

    Param (
        [Parameter (Mandatory=$true)]
        [object]$argument
    )
    
    #Check if it looks like Security Tag Assignmenbt
    if ($argument -is [PSCustomObject] ) {

        if ( -not ( $argument | get-member -name SecurityTag -Membertype Properties)) { 
            throw "Specify a valid Security Tag Assignment. Specified object does not contain a SecurityTag property object."
        }
        if ( -not ( $argument | get-member -name VirtualMachine -Membertype Properties)) { 
            throw "Specify a valid Security Tag Assignment. Specified object does not contain a VirtualMachine property object."
        }
        if ( -not ( $argument.SecurityTag -is [System.Xml.XmlElement] )) { 
            throw "Specify a valid Security Tag Assignment."
        }
        if ( -not ( $argument.VirtualMachine -is [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop])) { 
            throw "Specify a valid Security Tag Assignment."
        }
        $True
    }
    else { 
        throw "Specify a valid Security Tag Assignment."
    }
}



##########
##########
# Helper functions

function Format-XML () {

    <#
    .SYNOPSIS
    Accepts a string containing valid XML tags or an XMLElement object and 
    outputs it as a formatted string including newline and indentation of child
    nodes.

    .DESCRIPTION 
    Valid XML returned by the NSX API is a single string with no newlines or 
    indentation.  While PowerNSX cmdlets typicallly emit an XMLElement object, 
    which PowerShell outputs as formatted tables or lists when outputing to host,
    making normal human interaction easy, for output to file or debug stream, 
    format-xml converts the API returned XML to more easily read formated XML
    complete with linebreaks and indentation.

    As a side effect, this has the added benefit of being useable as an 
    additional format handler on the PowerShell pipeline, so rather than 
    displaying output objects using familiar table and list output formats, the
    user now has the option of displaying the native XML in a human readable 
    format.


    .EXAMPLE
    Get-NsxTransportZone | Format-Xml

    Displays the XMLElement object returned by Get-NsxTransportZone as formatted
    XML.

    #>

    #NB: Find where I got this to reference...
    #Shamelessly ripped from the web with some modification, useful for formatting XML output into a form that 
    #is easily read by humans.  Seriously - how is this not part of the dotnet system.xml classes?

    param ( 
        [Parameter (Mandatory=$false,ValueFromPipeline=$true,Position=1) ]
            [ValidateNotNullorEmpty()]

            #String object containing valid XML, or XMLElement or XMLDocument object
            $xml="", 
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]

            #Number of whitespace charaters to indent child nodes by when formatting
            [int]$indent=2
    ) 

    begin {}

    process {
        if ( ($xml -is [System.Xml.XmlElement]) -or ( $xml -is [System.Xml.XmlDocument] ) ) { 
            try {
                [xml]$_xml = $xml.OuterXml 
            }
            catch {
                throw "Specified XML element cannot be cast to an XML document."
            }
        }
        elseif ( $xml -is [string] ) {
            try { 
                [xml]$_xml = $xml
            }
            catch {
                throw "Specified string cannot be cast to an XML document."
            } 
        }
        else{

            throw "Unknown data type specified as xml to Format-Xml."
        }


        $StringWriter = New-Object System.IO.StringWriter 
        $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter 
        $xmlWriter.Formatting = "indented" 
        $xmlWriter.Indentation = $Indent 
        $_xml.WriteContentTo($XmlWriter) 
        $XmlWriter.Flush() 
        $StringWriter.Flush() 
        Write-Output $StringWriter.ToString() 
    }

    end{}
}

##########
##########
# Core functions

function Invoke-NsxRestMethod {

    <#
    .SYNOPSIS
    Constructs and performs a valid NSX REST call.

    .DESCRIPTION 
    Invoke-NsxRestMethod uses either a specified connection object as returned 
    by Connect-NsxServer, or the $DefaultNsxConnection global variable if 
    defined to construct a REST api call to the NSX API.  

    Invoke-NsxRestMethod constructs the appropriate request headers required by 
    the NSX API, including authentication details (built from the connection 
    object), required content type and includes any custom headers specified by 
    the caller that might be required by a specific API resource, before making 
    the rest call and returning the appropriate XML object to the caller. 

    .EXAMPLE
    Invoke-NsxRestMethod -Method get -Uri "/api/2.0/vdn/scopes"

    Performs a 'Get' against the URI /api/2.0/vdn/scopes and returns the xml
    object respresenting the NSX API XML reponse.  This call requires the 
    $DefaultNsxServer variable to exist and be populated with server and 
    authentiation details as created by Connect-NsxServer -DefaultConnection

    .EXAMPLE
    $MyConnection = Connect-NsxServer -Server OtherNsxManager -DefaultConnection:$false
    
    Invoke-NsxRestMethod -Method get -Uri "/api/2.0/vdn/scopes" -connection $MyConnection

    Creates a connection variable for a non default NSX server, performs a 
    'Get' against the URI /api/2.0/vdn/scopes and returns the xml
    object respresenting the NSX API XML reponse.
    
    #>

    [CmdletBinding(DefaultParameterSetName="ConnectionObj")]
  
    param (
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #PSCredential object containing authentication details to be used for connection to NSX Manager API
            [System.Management.Automation.PSCredential]$cred,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #NSX Manager ip address or FQDN
            [string]$server,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #TCP Port on -server to connect to
            [int]$port,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #Protocol - HTTP/HTTPS
            [string]$protocol,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #Validates the certificate presented by NSX Manager for HTTPS connections
            [bool]$ValidateCertificate,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            #REST method of call.  Get, Put, Post, Delete, Patch etc 
            [string]$method,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            #URI of resource (/api/1.0/myresource).  Should not include protocol, server or port.
            [string]$URI,
        [Parameter (Mandatory=$false,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            #Content to be sent to server when method is Put/Post/Patch
            [string]$body = "",
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            #Pre-populated connection object as returned by Connect-NsxServer
            [psObject]$connection,
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            #Hashtable collection of KV pairs representing additional headers to send to the NSX Manager during REST call
            [System.Collections.Hashtable]$extraheader,
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            #Request timeout value - passed directly to underlying invoke-restmethod call 
            [int]$Timeout=600
    )

    Write-Debug "$($MyInvocation.MyCommand.Name) : ParameterSetName : $($pscmdlet.ParameterSetName)"

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
                Write-Debug "$($MyInvocation.MyCommand.Name) : Using default connection"
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
        foreach ($header in $extraHeader.GetEnumerator()) {
            write-debug "$($MyInvocation.MyCommand.Name) : Adding extra header $($header.Key ) : $($header.Value)"
            if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) {
                if ( $connection.DebugLogging ) { 
                    Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  Extra Header being added to following REST call.  Key: $($Header.Key), Value: $($Header.Value)"
                }
            }
            $headerDictionary.add($header.Key, $header.Value)
        }
    }
    $FullURI = "$($protocol)://$($server):$($Port)$($URI)"
    write-debug "$($MyInvocation.MyCommand.Name) : Method: $method, URI: $FullURI, Body: `n$($body | Format-Xml)"

    if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) {
        if ( $connection.DebugLogging ) { 
            Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  REST Call to NSX Manager via invoke-restmethod : Method: $method, URI: $FullURI, Body: `n$($body | Format-Xml)"
        }
    }

    #do rest call
    try { 
        if ( $PsBoundParameters.ContainsKey('Body')) { 
            $response = invoke-restmethod -method $method -headers $headerDictionary -ContentType "application/xml" -uri $FullURI -body $body -TimeoutSec $Timeout
        } else {
            $response = invoke-restmethod -method $method -headers $headerDictionary -ContentType "application/xml" -uri $FullURI -TimeoutSec $Timeout
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
            
            if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) {
                if ( $connection.DebugLogging ) { 
                    Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  REST Call to NSX Manager failed: $ErrorString"
                }
            }
    
            throw $ErrorString
        }
        else { 
            if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) {
                if ( $connection.DebugLogging ) { 
                    Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  REST Call to NSX Manager failed with exception: $($_.Exception.Message).  ScriptStackTrace:`n $($_.ScriptStackTrace)"
                }
            }
            throw $_ 
        } 
        

    }
    switch ( $response ) {
        { $_ -is [xml] } { $FormattedResponse = "`n$($response.outerxml | Format-Xml)" } 
        { $_ -is [System.String] } { $FormattedResponse = $response }
        default { $formattedResponse = "Response type unknown" }
    }

    write-debug "$($MyInvocation.MyCommand.Name) : Response: $FormattedResponse"  
    if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) { 
        if ( $connection.DebugLogging ) { 
            Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  Response: $FormattedResponse"
        }
    }

    #Workaround for bug in invoke-restmethod where it doesnt complete the tcp session close to our server after certain calls. 
    #We end up with connectionlimit number of tcp sessions in close_wait and future calls die with a timeout failure.
    #So, we are getting and killing active sessions after each call.  Not sure of performance impact as yet - to test
    #and probably rewrite over time to use invoke-webrequest for all calls... PiTA!!!! :|

    $ServicePoint = [System.Net.ServicePointManager]::FindServicePoint($FullURI)
    $ServicePoint.CloseConnectionGroup("") | out-null
    write-debug "$($MyInvocation.MyCommand.Name) : Closing connections to $FullURI."

    #Return
    $response
}

function Invoke-NsxWebRequest {

    <#
    .SYNOPSIS
    Constructs and performs a valid NSX REST call and returns a response object
    including response headers.

    .DESCRIPTION 
    Invoke-NsxWebRequest uses either a specified connection object as returned 
    by Connect-NsxServer, or the $DefaultNsxConnection global variable if 
    defined to construct a REST api call to the NSX API.  

    Invoke-NsxWebRequest constructs the appropriate request headers required by 
    the NSX API, including authentication details (built from the connection 
    object), required content type and includes any custom headers specified by 
    the caller that might be required by a specific API resource, before making 
    the rest call and returning the resulting response object to the caller.

    The Response object includes the response headers unlike 
    Invoke-NsxRestMethod.

    .EXAMPLE
    $MyConnection = Connect-NsxServer -Server OtherNsxManager -DefaultConnection:$false
    $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $MyConnection
    $edgeId = $response.Headers.Location.split("/")[$response.Headers.Location.split("/").GetUpperBound(0)] 

    Creates a connection variable for a non default NSX server, performs a 'Post'
    against the URI $URI and then retrieves details from the Location header
    included in the response object. 

    #>

    [CmdletBinding(DefaultParameterSetName="ConnectionObj")]
  
    param (
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #PSCredential object containing authentication details to be used for connection to NSX Manager API
            [System.Management.Automation.PSCredential]$cred,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #NSX Manager ip address or FQDN
            [string]$server,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #TCP Port on -server to connect to
            [int]$port,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #Protocol - HTTP/HTTPS
            [string]$protocol,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
            #Validates the certificate presented by NSX Manager for HTTPS connections
            [bool]$ValidateCertificate,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            #REST method of call.  Get, Put, Post, Delete, Patch etc 
            [string]$method,
        [Parameter (Mandatory=$true,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            #URI of resource (/api/1.0/myresource).  Should not include protocol, server or port.
            [string]$URI,
        [Parameter (Mandatory=$false,ParameterSetName="Parameter")]
        [Parameter (ParameterSetName="ConnectionObj")]
            #Content to be sent to server when method is Put/Post/Patch
            [string]$body = "",
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            #Pre-populated connection object as returned by Connect-NsxServer
            [psObject]$connection,
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            #Hashtable collection of KV pairs representing additional headers to send to the NSX Manager during REST call
            [System.Collections.Hashtable]$extraheader,
        [Parameter (Mandatory=$false,ParameterSetName="ConnectionObj")]
            #Request timeout value - passed directly to underlying invoke-restmethod call 
            [int]$Timeout=600
    )

    Write-Debug "$($MyInvocation.MyCommand.Name) : ParameterSetName : $($pscmdlet.ParameterSetName)"

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
                Write-Debug "$($MyInvocation.MyCommand.Name) : Using default connection"
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
        foreach ($header in $extraHeader.GetEnumerator()) {
            write-debug "$($MyInvocation.MyCommand.Name) : Adding extra header $($header.Key ) : $($header.Value)"
            if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) {
                if ( $connection.DebugLogging ) { 
                    Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  Extra Header being added to following REST call.  Key: $($Header.Key), Value: $($Header.Value)"
                }
            }
            $headerDictionary.add($header.Key, $header.Value)
        }
    }
    $FullURI = "$($protocol)://$($server):$($Port)$($URI)"
    write-debug "$($MyInvocation.MyCommand.Name) : Method: $method, URI: $FullURI, Body: `n$($body | Format-Xml)"
    
    if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) { 
        if ( $connection.DebugLogging ) { 
            Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  REST Call to NSX Manager via invoke-webrequest : Method: $method, URI: $FullURI, Body: `n$($body | Format-Xml)"
        }
    }

    #do rest call
    
    try { 
        if (( $method -eq "put" ) -or ( $method -eq "post" )) { 
            $response = invoke-webrequest -method $method -headers $headerDictionary -ContentType "application/xml" -uri $FullURI -body $body -TimeoutSec $Timeout
        } else {
            $response = invoke-webrequest -method $method -headers $headerDictionary -ContentType "application/xml" -uri $FullURI -TimeoutSec $Timeout
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
            
            if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) { 
                if ( $connection.DebugLogging ) { 
                    Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  REST Call to NSX Manager failed: $ErrorString"
                }
            }

            throw $ErrorString
        }
        else { 

            if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) { 
                if ( $connection.DebugLogging ) { 
                    Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  REST Call to NSX Manager failed with exception: $($_.Exception.Message).  ScriptStackTrace:`n $($_.ScriptStackTrace)"
                }
            }
            throw $_ 
        } 
        

    }

    #Output the response header dictionary
    foreach ( $key in $response.Headers.Keys) {
        write-debug "$($MyInvocation.MyCommand.Name) : Response header item : $Key = $($Response.Headers.Item($key))"
        if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) {
            if ( $connection.DebugLogging ) { 
                Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  Response header item : $Key = $($Response.Headers.Item($key))"
            }
        }
    } 

    #And if there is response content...
    if ( $response.content ) {
        switch ( $response.content ) {
            { $_ -is [System.String] } { 
                
                write-debug "$($MyInvocation.MyCommand.Name) : Response Body: $($response.content)" 
            
                if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) {
                    if ( $connection.DebugLogging ) { 
                        Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  Response Body: $($response.content)"
                    }
                }
            }
            default { 
                write-debug "$($MyInvocation.MyCommand.Name) : Response type unknown"

                if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) { 
                    if ( $connection.DebugLogging ) { 
                        Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  Response type unknown ( $($Response.Content.gettype()) )."
                    } 
                }
            }
        }
    }
    else { 
        write-debug "$($MyInvocation.MyCommand.Name) : No response content"

        if ( $pscmdlet.ParameterSetName -eq "ConnectionObj" ) { 
            if ( $connection.DebugLogging ) { 
                Add-Content -Path $Connection.DebugLogfile -Value "$(Get-Date -format s)  No response content."
            } 
        }
    }

    $response
}

function Connect-NsxServer {

    <#
    .SYNOPSIS
    Connects to the specified NSX server and constructs a connection object.

    .DESCRIPTION
    The Connect-NsxServer cmdlet connects to the specified NSX server and 
    retrieves version details.  Because the underlying REST protocol is not 
    connection oriented, the 'Connection' concept relates to just validating 
    endpoint details and credentials and storing some basic information used 
    to reproduce the same outcome during subsequent NSX operations.

    .EXAMPLE
    Connect-NsxServer -Server nsxserver -username admin -Password VMware1!
        
    Connects to the nsxserver 'nsxserver' with the specified credentials.  If a
    registered vCenter server is configured in NSX manager, you are prompted to
    establish a PowerCLI session to that vCenter along with required 
    authentication details.

    .EXAMPLE
    Connect-NsxServer -Server nsxserver -username admin -Password VMware1! -DisableViAutoConnect
        
    Connects to the nsxserver 'nsxserver' with the specified credentials and 
    supresses the prompt to establish a PowerCLI connection with the registered 
    vCenter.

    .EXAMPLE
    Connect-NsxServer -Server nsxserver -username admin -Password VMware1! -ViUserName administrator@vsphere.local -ViPassword VMware1! 
        
    Connects to the nsxserver 'nsxserver' with the specified credentials and 
    automatically establishes a PowerCLI connection with the registered 
    vCenter using the credentials specified.

    .EXAMPLE
    $MyConnection = Connect-NsxServer -Server nsxserver -username admin -Password VMware1! -DefaultConnection:$false
    Get-NsxTransportZone 'TransportZone1' -connection $MyConnection 

    Connects to the nsxserver 'nsxserver' with the specified credentials and 
    then uses the returned connection object in a subsequent call to 
    Get-NsxTransportZone.  The $DefaultNsxConnection parameter is not populated
    
    Note: Any PowerNSX cmdlets will fail if the -connection parameters is not 
    specified and the $DefaultNsxConnection variable is not populated.

    Note:  Pipline operations involving multiple PowerNSX commands that interact
    with the NSX API (not all) require that all cmdlets specify the -connection 
    parameter (not just the fist one.) 



    #>

    [CmdletBinding(DefaultParameterSetName="cred")]
 
    param (
        [Parameter (Mandatory=$true,ParameterSetName="cred",Position=1)]
        [Parameter (Mandatory=$true,ParameterSetName="userpass",Position=1)]
            #NSX Manager address or FQDN 
            [ValidateNotNullOrEmpty()] 
            [string]$Server,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]
            #TCP Port to connect to on -Server
            [ValidateRange(1,65535)]
            [int]$Port=443,
        [Parameter (Mandatory=$true,ParameterSetName="cred")]
            #PSCredential object containing NSX API authentication credentials
            [PSCredential]$Credential,
        [Parameter (Mandatory=$true,ParameterSetName="userpass")]
            #Username used to authenticate to NSX API
            [ValidateNotNullOrEmpty()]
            [string]$Username,
        [Parameter (Mandatory=$true,ParameterSetName="userpass")]
            #Password used to authenticate to NSX API
            [ValidateNotNullOrEmpty()]
            [string]$Password,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]
            #Validates the certificate presented by NSX Manager for HTTPS connections.  Defaults to False
            [ValidateNotNullOrEmpty()]
            [switch]$ValidateCertificate=$false,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]
            #NSX API transport protocol - HTTPS / HTTP .  Defaults to HTTPS
            [ValidateNotNullOrEmpty()]
            [string]$Protocol="https",
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]
            #If True, the $DefaultNsxConnection global variable is created and populated with connection details.  
            #All PowerNSX commands that use the NSX API will utilise this connection unless they are called with the -connection parameter.
            #Defaults to True
            [bool]$DefaultConnection=$true,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]
            #If False, and a PowerCLI connection needs to be established to the registered vCenter, the Connect-ViServer call made by PowerNSX will specify the -NotDefault switch (see Get-Help Connect-ViServer)
            #Defaults to True
            [bool]$VIDefaultConnection=$true,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]  
            #If True, and the PowerNSX connection attempt is successful, an automatic PowerCLI connection to the registered vCenter server is not attempted.  Defaults to False.
            [switch]$DisableVIAutoConnect=$false,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")] 
            #UserName used in PowerCLI connection to registered vCenter.   
            [string]$VIUserName,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]    
            #Password used in PowerCLI connection to registered vCenter.   
            [string]$VIPassword,
        [Parameter (Mandatory=$false,ParameterSetName="cred")]
        [Parameter (ParameterSetName="userpass")]    
            #PSCredential object containing credentials used in PowerCLI connection to registered vCenter.   
            [PSCredential]$VICred,
        [Parameter (Mandatory=$false)]
            #Enable DebugLogging of all API calls to $DebugLogFile.  Can be enabled on esisting connections with $connection.DebugLogging = $true.  Defaults to False.  
            [switch]$DebugLogging=$false,
        [Parameter (Mandatory=$false)]    
            #If DebugLogging is enabled, specifies the file to which output is written.  Defaults to $Env:temp\PowerNSXLog-<user>@<server>-<datetime>.log
            [string]$DebugLogFile,
        [Parameter (Mandatory=$false)]
            #Supresses warning output from PowerCLI connection attempts (typically invalid Certificate warnings)
            [ValidateSet("Continue","Ignore")]
            [string]$ViWarningAction="Continue"   
    )

    if ($PSCmdlet.ParameterSetName -eq "userpass") {      
        $Credential = new-object System.Management.Automation.PSCredential($Username, $(ConvertTo-SecureString $Password -AsPlainText -Force))
    }

    $URI = "/api/1.0/appliance-management/global/info"
    
    #Test NSX connection
    try {
        $response = invoke-nsxrestmethod -cred $Credential -server $Server -port $port -protocol $Protocol -method "get" -uri $URI -ValidateCertificate:$ValidateCertificate
    } 
    catch {

        Throw "Unable to connect to NSX Manager at $Server.  $_"
    }
    $connection = new-object PSCustomObject
    # NSX-v 6.2.3 changed the output of the following API from JSON to XML.
    #
    # /api/1.0/appliance-management/global/info"
    #
    # Along with the return JSON/XML change, the data structure also received a
    # new base element named globalInfo.
    #
    # So what we do is try for the new format, and if it fails, lets default to
    # the old JSON format.
    try {
        $Connection | add-member -memberType NoteProperty -name "Version" -value "$($response.globalInfo.versionInfo.majorVersion).$($response.globalInfo.versionInfo.minorVersion).$($response.globalInfo.versionInfo.patchVersion)" -force
        $Connection | add-member -memberType NoteProperty -name "BuildNumber" -value "$($response.globalInfo.versionInfo.BuildNumber)"
    }
    catch {
        try { 
            $Connection | add-member -memberType NoteProperty -name "Version" -value "$($response.VersionInfo.majorVersion).$($response.VersionInfo.minorVersion).$($response.VersionInfo.patchVersion)" -force
            $Connection | add-member -memberType NoteProperty -name "BuildNumber" -value "$($response.VersionInfo.BuildNumber)"
        }
        catch { 
            write-warning "Unable to determine version information.  This may be due to a restriction in the rights the current user has to read the appliance-management API and may not represent an issue."
        }
    }
    $Connection | add-member -memberType NoteProperty -name "Credential" -value $Credential -force
    $connection | add-member -memberType NoteProperty -name "Server" -value $Server -force
    $connection | add-member -memberType NoteProperty -name "Port" -value $port -force
    $connection | add-member -memberType NoteProperty -name "Protocol" -value $Protocol -force
    $connection | add-member -memberType NoteProperty -name "ValidateCertificate" -value $ValidateCertificate -force
    $connection | add-member -memberType NoteProperty -name "VIConnection" -force -Value ""
    $connection | add-member -memberType NoteProperty -name "DebugLogging" -force -Value $DebugLogging
    
    #Debug log will contain all rest calls, request and response bodies, and response headers.
    if ( -not $PsBoundParameters.ContainsKey('DebugLogFile' )) {

        #Generating logfile name regardless of initial user pref on debug.  They can just flip the prop on the connection object at a later date to start logging...
        $dtstring = get-date -format "yyyy_MM_dd_HH_mm_ss"
        $DebugLogFile = "$($env:TEMP)\PowerNSXLog-$($Credential.UserName)@$Server-$dtstring.log"

    }

    #If debug is on, need to test we can create the debug file first and throw if not... 
    if ( $DebugLogging -and (-not ( new-item -path $DebugLogFile -Type file ))) { Throw "Unable to create logfile $DebugLogFile.  Disable debugging or specify a valid DebugLogFile name."}

    $connection | add-member -memberType NoteProperty -name "DebugLogFile" -force -Value $DebugLogFile    

    #More and more functionality requires PowerCLI connection as well, so now pushing the user in that direction.  Will establish connection to vc the NSX manager 
    #is registered against.

    $vcInfo = Invoke-NsxRestMethod -method get -URI "/api/2.0/services/vcconfig" -connection $connection
    if ( $DebugLogging ) { Add-Content -Path $DebugLogfile -Value "$(Get-Date -format s)  New PowerNSX Connection to $($credential.UserName)@$($Protocol)://$($Server):$port, version $($Connection.Version)" }

    if ( -not $vcInfo.SelectSingleNode('descendant::vcInfo/ipAddress')) { 
        if ( $DebugLogging ) { Add-Content -Path $DebugLogfile -Value "$(Get-Date -format s)  NSX Manager $Server is not currently connected to any vCenter..." }
        write-warning "NSX Manager does not currently have a vCenter registration.  Use Set-NsxManager to register a vCenter server."
    }
    else {
        $RegisteredvCenterIP = $vcInfo.vcInfo.ipAddress
        $ConnectedToRegisteredVC=$false

        if ((test-path variable:global:DefaultVIServer )) {

            #Already have a PowerCLI connection - is it to the right place?

            #the 'ipaddress' in vcinfo from NSX api can be fqdn, 
            #Resolve to ip so we can compare to any existing connection.  
            #Resolution can result in more than one ip so we have to iterate over it.
            
            $RegisteredvCenterIPs = ([System.Net.Dns]::GetHostAddresses($RegisteredvCenterIP))

            #Remembering we can have multiple vCenter connections too :|
            :outer foreach ( $VIServerConnection in $global:DefaultVIServer ) {
                $ExistingVIConnectionIPs =  [System.Net.Dns]::GetHostAddresses($VIServerConnection.Name)
                foreach ( $ExistingVIConnectionIP in [IpAddress[]]$ExistingVIConnectionIPs ) {
                    foreach ( $RegisteredvCenterIP in [IpAddress[]]$RegisteredvCenterIPs ) {
                        if ( $ExistingVIConnectionIP -eq $RegisteredvCenterIP ) {
                            if ( $VIServerConnection.IsConnected ) { 
                                $ConnectedToRegisteredVC = $true
                                write-host -foregroundcolor Green "Using existing PowerCLI connection to $($ExistingVIConnectionIP.IPAddresstoString)"
                                $connection.VIConnection = $VIServerConnection
                                break outer
                            }
                            else {
                                write-host -foregroundcolor Yellow "Existing PowerCLI connection to $($ExistingVIConnectionIP.IPAddresstoString) is not connected."
                            }
                        }
                    }
                }
            }
        } 

        if ( -not $ConnectedToRegisteredVC ) {
            if ( -not (($VIUserName -and $VIPassword) -or ( $VICred ) )) {
                #We assume that if the user did not specify VI creds, then they may want a connection to VC, but we will ask.
                $decision = 1
                if ( -not $DisableVIAutoConnect) {
                  
                    #Ask the question and get creds.

                    $message  = "PowerNSX requires a PowerCLI connection to the vCenter server NSX is registered against for proper operation."
                    $question = "Automatically create PowerCLI connection to $($RegisteredvCenterIP)?"

                    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 0)

                }

                if ( $decision -eq 0 ) { 
                    write-host 
                    write-warning "Enter credentials for vCenter $RegisteredvCenterIP"
                    $VICred = get-credential
                    $connection.VIConnection = Connect-VIServer -Credential $VICred $RegisteredvCenterIP -NotDefault:(-not $VIDefaultConnection) -WarningAction:$ViWarningAction

                }
                else {
                    write-host
                    write-warning "Some PowerNSX cmdlets will not be fully functional without a valid PowerCLI connection to vCenter server $RegisteredvCenterIP"
                }
            }
            else { 
                #User specified VI username/pwd or VI cred.  Connect automatically to the registered vCenter
                write-host "Creating PowerCLI connection to vCenter server $RegisteredvCenterIP"

                if ( $VICred ) { 
                    $connection.VIConnection = Connect-VIServer -Credential $VICred $RegisteredvCenterIP -NotDefault:(-not $VIDefaultConnection) -WarningAction:$ViWarningAction
                }
                else {
                    $connection.VIConnection = Connect-VIServer -User $VIUserName -Password $VIPassword $RegisteredvCenterIP -NotDefault:(-not $VIDefaultConnection) -WarningAction:$ViWarningAction
                }
            }
        }

        if ( $DebugLogging ) { Add-Content -Path $DebugLogfile -Value "$(Get-Date -format s)  NSX Manager $Server is registered against vCenter server $RegisteredvCenterIP.  PowerCLI connection established to registered vCenter : $(if ($Connection.ViConnection ) { $connection.VIConnection.IsConnected } else { "False" })" }
    }


    #Set the default connection is required.
    if ( $DefaultConnection) { set-variable -name DefaultNSXConnection -value $connection -scope Global }

    #Return the connection
    $connection
}

function Disconnect-NsxServer {

    <#
    .SYNOPSIS
    Destroys the $DefaultNSXConnection global variable if it exists.

    .DESCRIPTION
    REST is not connection oriented, so there really isnt a connect/disconnect 
    concept.  Disconnect-NsxServer, merely removes the $DefaultNSXConnection 
    variable that PowerNSX cmdlets default to using.

    .EXAMPLE
    Connect-NsxServer -Server nsxserver -username admin -Password VMware1!

    #>
    if (Get-Variable -Name DefaultNsxConnection -scope global ) {
        Remove-Variable -name DefaultNsxConnection -scope global
    }
}

function Get-PowerNsxVersion {

    <#
    .SYNOPSIS
    Retrieves the version of PowerNSX.
    
    .EXAMPLE
    Get-PowerNsxVersion

    Get the installed version of PowerNSX

    #>

    #Updated to take advantage of Manifest info.
    Get-Module PowerNsx | select version, path, author, companyName 
}

function Update-PowerNsx {
    
    <#
    .SYNOPSIS
    Updates PowerNSX to the latest version available in the specified branch.
    
    .EXAMPLE
    Update-PowerNSX -Branch Dev

    #>

    param (

        [Parameter (Mandatory = $True, Position=1)]
            #Valid Branches supported for upgrading to.
            [ValidateScript({ Validate-UpdateBranch $_ })]
            [string]$Branch
    )

    $PNsxUrl = "$PNsxUrlBase/$Branch/PowerNSXInstaller.ps1"
    
    if ( -not ( ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole] "Administrator"))) { 

        write-host -ForegroundColor Yellow "Update-PowerNsx requires Administrative rights."
        write-host -ForegroundColor Yellow "Please restart PowerCLI with right click, 'Run As Administrator' and try again."
        return
    }

    if ( $Branch -eq "Dev" ) {
        write-warning "Updating to latest Dev branch commit.  Stability is not guaranteed."
    }

    #Installer doesnt play nice in strict mode...
    set-strictmode -Off
    try { 
        $wc = new-object Net.WebClient
        $scr = try { 
            $filename = split-path $PNsxUrl -leaf
            $wc.Downloadfile($PNsxUrl, "$($env:Temp)\$filename") 
        } 
        catch { 
            if ( $_.exception.innerexception -match "(407)") { 
                $wc.proxy.credentials = Get-Credential -Message "Proxy Authentication Required"
                $wc.Downloadfile($PNsxUrl, "$($env:Temp)\$filename") 
            } 
            else { 
                throw $_ 
            }
        }
        invoke-expression "& `"$($env:Temp)\$filename`" -Upgrade"
    } 
    catch { 
        throw $_ 
    }

    Remove-Module PowerNSX
    Import-Module PowerNSX

    set-strictmode -Version Latest
}

#########
#########
# Infra functions

function Get-NsxClusterStatus {

    <#
    .SYNOPSIS
    Retrieves the resource status from NSX for the given cluster.

    .DESCRIPTION
    All clusters visible to NSX manager (managed by the vCenter that NSX Manager
    is synced with) can have the status of NSX related resources queried.

    This cmdlet returns the resource status of all registered NSX resources for 
    the given cluster.

    .EXAMPLE
    This example shows how to query the status for the cluster MyCluster 

    PS C:\> get-cluster MyCluster | Get-NsxClusterStatus

    .EXAMPLE
    This example shows how to query the status for all clusters

    PS C:\> get-cluster MyCluster | Get-NsxClusterStatus

    #>

    param (

        [Parameter ( Mandatory=$true,ValueFromPipeline=$true)]
            #Cluster Object to retreive status details for.
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop]$Cluster,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    begin {}

    process{
        #Get resource status for given cluster
        write-debug "$($MyInvocation.MyCommand.Name) : Query status for cluster $($cluster.name) ($($cluster.ExtensionData.Moref.Value))"
        $uri = "/api/2.0/nwfabric/status-without-alarms?resource=$($cluster.ExtensionData.Moref.Value)"
        try {
            $response = invoke-nsxrestmethod -connection $connection -method get -uri $uri
            $response.resourceStatuses.resourceStatus.nwFabricFeatureStatus

        }
        catch {
            throw "Unable to query resource status for cluster $($cluster.Name) ($($cluster.ExtensionData.Moref.Value)).  $_"
        }
    }
    end{}
}

function Invoke-NsxCli {

    <#
    .SYNOPSIS
    Provides access to the NSX Centralised CLI.

    .DESCRIPTION
    The NSX Centralised CLI is a feature first introduced in NSX 6.2.  It
    provides centralised means of performing read only operations against
    various aspects of the dataplane including Logical Switching, Logical
    Routing, Distributed Firewall and Edge Services Gateways.

    The results returned by the Centralised CLI are actual (realised) state
    as opposed to configured state.  They should you how the dataplane actually
    is configured at the time the query is run.

    WARNING: The Centralised CLI is primarily a trouble shooting tool and
    it and the PowerNSX cmdlets that expose it should not be used for any other
    purpose.  All the PowerNSX cmdlets that expose the central cli rely on a
    bespoke text parser to interpret the results as powershell objects, and have
    not been extensively tested.
    .INPUTS
    System.String
    .PARAMETER Query
    string text of Central CLI command to execute
    .PARAMETER SupressWarning
    Switch parameter to ignore the experimental warning
    .PARAMETER Connection
    Proper NSX connection [PSCustomObject]
    .PARAMETER RawOutput
    Switch parameter that will not try to parse the output
    .NOTES
    Version: 1.2
    Updated: 7/29/16
    Updated By: Kevin Kirkpatrick (vScripter)
    Update Notes:
    - Added '-RawOutput' parameter
    - Added support for '-Verbose'
    - Expanded support for '-Debug'
    #>

    param (

        [Parameter ( Mandatory=$true, Position=1) ]
            #Free form query string that is sent to the NSX Central CLI API
            [ValidateNotNullOrEmpty()]
            [String]$Query,
        [Parameter ( Mandatory=$false) ]
            #Supress warning about experimental feature.  Defaults to False
            [switch]$SupressWarning,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection = $defaultNSXConnection,
        [Parameter(Mandatory = $false)]
            # switch param to support throwing raw output to avoid errors with the parser
            [switch]$RawOutput

    )

    begin {

        if ( -not $SupressWarning ) {

            Write-Warning -Message "This cmdlet is experimental and has not been well tested.  Its use should be limited to troubleshooting purposes only."

        } # end if

    } # end begin block

    process {

        Write-Verbose -Message "[$($MyInvocation.MyCommand.Name)] Executing Central CLI Query {$Query}"

        Write-Debug -Message "[$($MyInvocation.MyCommand.Name)] Building XML"

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlCli = $XMLDoc.CreateElement("nsxcli")
        $xmlDoc.appendChild($xmlCli) | out-null

        Add-XmlElement -xmlRoot $xmlCli -xmlElementName "command" -xmlElementText $Query

        #<nsxcli><command>show cluster all</command></nsxcli>

        $Body = $xmlCli.OuterXml
        $uri = "/api/1.0/nsx/cli?action=execute"

        Write-Debug -Message "[$($MyInvocation.MyCommand.Name)] Invoking POST method. Entering 'try/catch' block"
        try {

            $response = Invoke-NsxRestMethod -Connection $connection -Method post -Uri $uri -Body $Body

            if ($RawOutput) {

                Write-Verbose -Message "[$($MyInvocation.MyCommand.Name)] Returning Raw Output"
                $response

            } else {

                Write-Verbose -Message "[$($MyInvocation.MyCommand.Name)] Parsing Output"
                Parse-CentralCliResponse $response

            } # end if/else

        } catch {

            throw "[$($MyInvocation.MyCommand.Name)][ERROR] Unable to execute Centralized CLI query. $_.Exception.Message. Try re-running command with the -RawOutput parameter."

        } # end try/catch

    } # end process block

    end {

        Write-Verbose -Message "[$($MyInvocation.MyCommand.Name)] Processing Complete"

    } # end block

} # end function Invoke-NsxCli


function Get-NsxCliDfwFilter {

    <#
    .SYNOPSIS
    Uses the NSX Centralised CLI to retreive the VMs VNIC filters.

    .DESCRIPTION
    The NSX Centralised CLI is a feature first introduced in NSX 6.2.  It
    provides centralised means of performing read only operations against
    various aspects of the dataplane including Logical Switching, Logical
    Routing, Distributed Firewall and Edge Services Gateways.

    The results returned by the Centralised CLI are actual (realised) state
    as opposed to configured state.  They show you how the dataplane actually
    is configured at the time the query is run.

    This cmdlet accepts a VM object, and leverages the Invoke-NsxCli cmdlet by
    constructing the appropriate Centralised CLI command without requiring the
    user to do the show cluster all -> show cluster domain-xxx -> show host
    host-xxx -> show vm vm-xxx dance -> show dfw host host-xxx filter xxx rules
    dance.  It returns objects representing the Filters defined on each vnic of
    the VM

    #>

    Param (
        [Parameter (Mandatory=$True, ValueFromPipeline=$True)]
            #PowerCLI Virtual Machine object.
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop]$VirtualMachine,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin{}

    process{

        $query = "show vm $($VirtualMachine.ExtensionData.Moref.Value)"
        $filters = Invoke-NsxCli $query -SupressWarning -connection $connection
        
        foreach ( $filter in $filters ) { 
            #Execute the appropriate CLI query against the VMs host for the current filter...
            $query = "show vnic $($Filter."Vnic Id")"
            Invoke-NsxCli $query -connection $connection
        }
    }

    end{}
}

function Get-NsxCliDfwRule {

    <#
    .SYNOPSIS
    Uses the NSX Centralised CLI to retreive the rules configured for the 
    specified VMs vnics.

    .DESCRIPTION
    The NSX Centralised CLI is a feature first introduced in NSX 6.2.  It 
    provides centralised means of performing read only operations against 
    various aspects of the dataplane including Logical Switching, Logical 
    Routing, Distributed Firewall and Edge Services Gateways.

    The results returned by the Centralised CLI are actual (realised) state
    as opposed to configured state.  They show you how the dataplane actually
    is configured at the time the query is run.

    This cmdlet accepts a VM object, and leverages the Invoke-NsxCli cmdlet by 
    constructing the appropriate Centralised CLI command without requiring the 
    user to do the show cluster all -> show cluster domain-xxx -> show host 
    host-xxx -> show vm vm-xxx dance -> show dfw host host-xxx filter xxx
    dance.  It returns objects representing the DFW rules instantiated on 
    the VMs vnics dfw filters.

    #>

    Param ( 
        [Parameter (Mandatory=$True, ValueFromPipeline=$True)]
            #PowerCLI VirtualMachine object
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop]$VirtualMachine,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin{}

    process{

        if ( $VirtualMachine.PowerState -eq 'PoweredOn' ) { 
            #First we retrieve the filter names from the host that the VM is running on
            try { 
                $query = "show vm $($VirtualMachine.ExtensionData.Moref.Value)"
                $VMs = Invoke-NsxCli $query -connection $connection
            }
            catch {
                #Invoke-nsxcli threw an exception.  There are a couple we want to handle here...
                switch -regex ($_.tostring()) {
                    "\( Error 100: \)" { 
                        write-warning "Virtual Machine $($VirtualMachine.Name) has no DFW Filter active."; 
                        return                    }
                    default {throw}
                } 
            }

            #Potentially there are multiple 'VMs' (VM with more than one NIC).
            foreach ( $VM in $VMs ) { 
                #Execute the appropriate CLI query against the VMs host for the current filter...
                $query = "show dfw host $($VirtualMachine.VMHost.ExtensionData.MoRef.Value) filter $($VM.Filters) rules"
                $rule = Invoke-NsxCli $query -SupressWarning -connection $connection
                $rule | add-member -memberType NoteProperty -Name "VirtualMachine" -Value $VirtualMachine
                $rule | add-member -memberType NoteProperty -Name "Filter" -Value $($VM.Filters)
                $rule
            }
        } else {
            write-warning "Virtual Machine $($VirtualMachine.Name) is not powered on."
        }
    }
    end{}
}

function Get-NsxCliDfwAddrSet {

    <#
    .SYNOPSIS
    Uses the NSX Centralised CLI to retreive the address sets configured
    for the specified VMs vnics.

    .DESCRIPTION
    The NSX Centralised CLI is a feature first introduced in NSX 6.2.  It 
    provides centralised means of performing read only operations against 
    various aspects of the dataplane including Logical Switching, Logical 
    Routing, Distributed Firewall and Edge Services Gateways.

    The results returned by the Centralised CLI are actual (realised) state
    as opposed to configured state.  They show you how the dataplane actually
    is configured at the time the query is run.

    This cmdlet accepts a VM object, and leverages the Invoke-NsxCli cmdlet by 
    constructing the appropriate Centralised CLI command without requiring the 
    user to do the show cluster all -> show cluster domain-xxx -> show host 
    host-xxx -> show vm vm-xxx dance -> show dfw host host-xxx filter xxx
    dance.  It returns object representing the Address Sets defined on the 
    VMs vnics DFW filters. 

    #>

    Param ( 
        [Parameter (Mandatory=$True, ValueFromPipeline=$True)]
            #PowerCLI VirtualMachine object
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop]$VirtualMachine,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin{}

    process{

        #First we retrieve the filter names from the host that the VM is running on
        $query = "show vm $($VirtualMachine.ExtensionData.Moref.Value)"
        $Filters = Invoke-NsxCli $query -connection $connection

        #Potentially there are multiple filters (VM with more than one NIC).
        foreach ( $filter in $filters ) { 
            #Execute the appropriate CLI query against the VMs host for the current filter...
            $query = "show dfw host $($VirtualMachine.VMHost.ExtensionData.MoRef.Value) filter $($Filter.Filters) addrset"
            Invoke-NsxCli $query -SupressWarning -connection $connection
        }
    }
    end{}
}

function Get-NsxHostUvsmLogging {

    <#
    .SYNOPSIS
    Retrieves the Uvsm Logging level from the specified host.

    .DESCRIPTION

    
    .EXAMPLE

    #>


    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VMHostInterop]$VMHost,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    begin {

    }

    process {

        #UVSM Logging URI
        $URI = "/api/1.0/usvmlogging/$($VMHost.Extensiondata.Moref.Value)/root"
        try { 
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
           [PSCustomobject]@{
                "LoggerName"=$response.LoggingLevel.LoggerName;
                "LogLevel"=$response.LoggingLevel.Level;
                "HostName"=$VMhost.Name;
                "HostId"=$VMhost.Extensiondata.Moref.Value
            }
        }
        catch {
            write-warning "Error querying host $($VMhost.Name) for UVSM logging status.  Check Guest Introspection is enabled, and USVM is available." 
        }

    }

    end {}
}

function Set-NsxHostUvsmLogging {

    <#
    .SYNOPSIS
    Sets the Uvsm Logging on the specified host.

    .DESCRIPTION

    
    .EXAMPLE

    #>


    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VMHostInterop]$VMHost,
        [Parameter (Mandatory=$true)]
            [ValidateSet("OFF", "FATAL", "ERROR", "WARN", "INFO", "DEBUG", "TRACE",IgnoreCase=$false)]
            [string]$LogLevel,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )


    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("logginglevel")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "loggerName" -xmlElementText "root"
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "level" -xmlElementText $LogLevel

        # #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/1.0/usvmlogging/$($VMhost.Extensiondata.Moref.Value)/changelevel"
        Write-Progress -activity "Updating log level on host $($VMhost.Name)"    
        invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection| out-null
        Write-progress -activity "Updating log level on host $($VMhost.Name)" -completed

    }
    end {}
}

function New-NsxManager{

    <#
    .SYNOPSIS
    Uses an existing PowerCLI connection to deploy and configure the NSX
    Manager VM from OVA.

    .DESCRIPTION
    The NSX management plane is provided by NSX Manager, the centralized
    network management component of NSX. It provides the single point of
    configuration for NSX operations, and provides NSX's REST API.

    The New-NsxManager cmdlet deploys and configures a new NSX Manager appliance
    using PowerCLI

    .INPUTS
    System.String
    System.Int32
    System.RuntimeType

    .EXAMPLE
    New-NSXManager -NsxManagerOVF ".\VMware-NSX-Manager-6.2.0-2986609.ova"
        -Name TestingNSXM -ClusterName Cluster1 -ManagementPortGroupName Net1
        -DatastoreName DS1 -FolderName Folder1 -CliPassword VMware1!VMware1!
        -CliEnablePassword VMware1!VMware1! -Hostname NSXManagerHostName
        -IpAddress 1.2.3.4 -Netmask 255.255.255.0 -Gateway 1.2.3.1
        -DnsServer 1.2.3.5 -DnsDomain corp.local -NtpServer 1.2.3.5 -EnableSsh
        -StartVm -wait

    Deploys a new NSX Manager, starts the VM, and blocks until the API becomes
    available.

    .EXAMPLE
    $nsxManagerBuildParams = @{
        NsxManagerOVF           = ".\VMware-NSX-Manager-6.2.0-2986609.ova"
        Name                    = TestingNSXM
        ClusterName             = Cluster1
        ManagementPortGroupName = Net1
        DatastoreName           = DS1
        FolderName              = Folder1
        CliPassword             = VMware1!VMware1!
        CliEnablePassword       = VMware1!VMware1!
        Hostname                = NSXManagerHostName
        IpAddress               = 1.2.3.4
        Netmask                 = 255.255.255.0
        Gateway                 = 1.2.3.1
        DnsServer               = 1.2.3.5
        DnsDomain               = corp.local
        NtpServer               = 1.2.3.5
        EnableSsh               = $true
        StartVm                 = $true
        Wait                    = $true
    } # end $nsxManagerBuildParams

    New-NSXManager @nsxManagerBuildParams

    Uses 'splatting' technique to specify build configuration and then deploys a new NSX Manager, starts the VM, and blocks until the API becomes
    available.

    .NOTES
		Version: 1.2
		Last Updated: 20150908
		Last Updated By: Kevin Kirkpatrick (github.com/vScripter)
		Last Update Notes:
        - added a filter when selecting VMHost to only select a host that is reporting a 'Connected' status
        - added logic to throw an error if there are no hosts available in the cluster (either there are none or they are all in maint. mode, etc.)
		- added Begin/Process/End blocks for language consistency
        - expanded support for -Verbose
        - added logic to check for vCenter server 'IsConnected' status; ran into some cases where $global:defaultviserver variable is populated but connection is stale/timedout
        - misc spacing/formatting to improve readability a little bit

    #>

    [CmdletBinding(DefaultParameterSetName="Default")]
    param (

        [Parameter ( Mandatory=$True )]
            #Local Path to NSX MAnager OVA
            [ValidateScript({
                if ( -not (test-path $_)) {
                    throw "NSX Manager OVF file not found: $_."
                }
                $true
            })]
            [string]$NsxManagerOVF,
        [Parameter ( Mandatory=$True )]
            #The name of the deployed VM.
            [ValidateNotNullOrEmpty()]
            [String]$Name,
        [Parameter ( Mandatory=$True )]
            #Name of the vSphere Cluster to which the VM will be deployed.
            [ValidateNotNullOrEmpty()]
            [string]$ClusterName,
        [Parameter ( Mandatory=$True )]
            #Name of the portgroup to which the management interface of the VM will be connected.
            [ValidateNotNullOrEmpty()]
            [string]$ManagementPortGroupName,
        [Parameter ( Mandatory=$True )]
            #Name of the Datastore to which the VM will be deployed.
            [ValidateNotNullOrEmpty()]
            [string]$DatastoreName,
        [Parameter ( Mandatory=$True )]
            #Name of the vSphere VM Inventory folder to which the VM will be deployed.
            [ValidateNotNullOrEmpty()]
            [string]$FolderName,
        [Parameter ( Mandatory=$True )]
            #CLI Password for the deployed NSX Manager.
            [ValidateNotNullOrEmpty()]
            [string]$CliPassword,
        [Parameter ( Mandatory=$True )]
            #Enable password for the deployed NSX Manager.
            [ValidateNotNullOrEmpty()]
            [string]$CliEnablePassword,
        [Parameter ( Mandatory=$True )]
            #Guest Hostname for the deployed NSX Manager.
            [ValidateNotNullOrEmpty()]
            [string]$Hostname,
        [Parameter ( Mandatory=$True )]
            #IP Address assigned to the management interface.
            [ValidateNotNullOrEmpty()]
            [ipaddress]$IpAddress,
        [Parameter ( Mandatory=$True )]
            #Netmask for the management interface.
            [ValidateNotNullOrEmpty()]
            [ipaddress]$Netmask,
        [Parameter ( Mandatory=$True )]
            #Gateway Address for the deployed NSX Manager.
            [ValidateNotNullOrEmpty()]
            [ipaddress]$Gateway,
        [Parameter ( Mandatory=$True )]
            #DNS Server for the deployed NSX Manager (One only.)
            [ValidateNotNullOrEmpty()]
            [ipaddress]$DnsServer,
        [Parameter ( Mandatory=$True )]
            #DNS Domain Name for the deployed NSX Manager.
            [ValidateNotNullOrEmpty()]
            [string]$DnsDomain,
        [Parameter ( Mandatory=$True )]
            #NTP Server for the deployed NSX Manager (One only.)
            [ValidateNotNullOrEmpty()]
            [ipAddress]$NtpServer,
        [Parameter ( Mandatory=$False)]
            #Configured Memory for the deployed VM.  Overrides default in OVA.  Non-Production use only!
            [ValidateRange(8,16)]
            [int]$ManagerMemoryGB,
        [Parameter ( Mandatory=$True, ParameterSetName = "StartVM" )]
            #Start the VM once deployment is completed.
            [switch]$StartVM=$false,
        [Parameter ( Mandatory=$False, ParameterSetName = "StartVM")]
            #Wait for the NSX Manager API to become available once deployment is complete and the appliance is started.  Requires -StartVM, and network reachability between this machine and the management interface of the NSX Manager.
            [ValidateScript({
                If ( -not $StartVM ) { throw "Cant wait for Manager API unless -StartVM is enabled."}
                $true
                })]
            [switch]$Wait=$false,
        [Parameter ( Mandatory=$False, ParameterSetName = "StartVM")]
            #How long to wait before timeout for NSX MAnager API to become available once the VM has been started.
            [int]$WaitTimeout = 600,
        [Parameter ( Mandatory=$False )]
            #Enable SSH on the deployed NSX Manager.
            [switch]$EnableSsh=$false
    )

    BEGIN {

        # Check that we have a PowerCLI connection open...
        Write-Verbose -Message "Verifying PowerCLI connection"

        If ( -not (Test-Path Variable:Global:defaultVIServer) ) {

            throw "Unable to deploy NSX Manager OVA without a valid PowerCLI connection.  Use Connect-VIServer or Connect-NsxServer to extablish a PowerCLI connection and try again."

        } elseif (Test-Path Variable:Global:defaultVIServer) {

            Write-Verbose -Message "PowerCLI connection discovered; validating connection state"

            if (($Global:defaultViServer).IsConnected -eq $true) {

                 Write-Verbose -Message "Currently connected to VI Server: $Global:defaultViServer"

            } else {

                throw "Connection to VI Server: $Global:defaultViServer is present, but not connected. You must be connected to a VI Server to continue."

            } # end if/else

        } # end if/elseif


        Write-Verbose -Message "Selecting VMHost for deployment in Cluster: $ClusterName"
        # Chose a target host that is not in Maintenance Mode and select based on available memory
        $TargetVMHost = Get-Cluster $ClusterName | Get-VMHost | Where-Object {$_.ConnectionState -eq 'Connected'} | Sort-Object MemoryUsageGB | Select -first 1

        # throw an error if there are not any hosts suitable for deployment (ie: all hosts are in maint. mode)
        if ($targetVmHost.Count = 0) {

            throw "Unable to deploy NSX Manager to cluster: $ClusterName. There are no VMHosts suitable for deployment. Check the selected cluster to ensure hosts exist and that at least one is not in Maintenance Mode."

        } else {

            Write-Verbose -Message "Deploying to Cluster: $ClusterName and VMHost: $($TargetVMHost.Name)"

        } # end if/else $targetVmHost.Count

    } # end BEGIN block

    PROCESS {

        Write-Verbose -Message "Setting up OVF configuration"
        ## Using the PowerCLI command, get OVF draws on the location of the OVA from the defined variable.
        $OvfConfiguration = Get-OvfConfiguration -Ovf $NsxManagerOVF

        #Network Mapping to portgroup need to be defined.
        $OvfConfiguration.NetworkMapping.VSMgmt.Value = $ManagementPortGroupName

        # OVF Configuration values.
        $OvfConfiguration.common.vsm_cli_passwd_0.value    = $CliPassword
        $OvfConfiguration.common.vsm_cli_en_passwd_0.value = $CliEnablePassword
        $OvfConfiguration.common.vsm_hostname.value        = $Hostname
        $OvfConfiguration.common.vsm_ip_0.value            = $IpAddress
        $OvfConfiguration.common.vsm_netmask_0.value       = $Netmask
        $OvfConfiguration.common.vsm_gateway_0.value       = $Gateway
        $OvfConfiguration.common.vsm_dns1_0.value          = $DnsServer
        $OvfConfiguration.common.vsm_domain_0.value        = $DnsDomain
        $OvfConfiguration.common.vsm_ntp_0.value           = $NtpServer
        $OvfConfiguration.common.vsm_isSSHEnabled.value    = $EnableSsh

        # Deploy the OVA.
        Write-Progress -Activity "Deploying NSX Manager OVA"
        $VM = Import-vApp -Source $NsxManagerOvf -OvfConfiguration $OvfConfiguration -Name $Name -Location $ClusterName -VMHost $TargetVMHost -Datastore $DatastoreName

        If ( $PSBoundParameters.ContainsKey('FolderName')) {

            Write-Progress -Activity "Moving NSX Manager VM to folder: $folderName"
            $VM | Move-VM -Location $FolderName
            Write-Progress -Activity "Moving NSX Manager VM to folder: $folderName" -Completed

        } # end if

        if ( $PSBoundParameters.ContainsKey('ManagerMemoryGB') ) {

            # Hack VM to reduce Ram for constrained environments.  This is NOT SUITABLE FOR PRODUCTION!!!
            Write-Warning -Message "Changing Memory configuration of NSX Manager VM to $ManagerMemoryGB GB.  Not supported for Production Use!"
            # start
            Get-VM $Name |
            Set-VM -MemoryGB $ManagerMemoryGB -confirm:$false | 
            Get-VMResourceConfiguration |
            Set-VMResourceConfiguration -MemReservationMB 0 -CpuReservationMhz 0 |
            Out-Null
            # end

        } # end if

        Write-Progress -Activity "Deploying NSX Manager OVA" -Completed

        if ( $StartVM )  {

            Write-Progress -Activity "Starting NSX Manager"
            $VM | Start-VM
            Write-Progress -Activity "Starting NSX Manager" -Completed

        } # end if

        if ( $PSBoundParameters.ContainsKey('Wait')) {

            # User wants to wait for Manager API to start.
            $waitStep = 30
            $Timer = 0
            Write-Progress -Activity "Waiting for NSX Manager api to become available" -PercentComplete $(($Timer/$WaitTimeout)*100)

            do {

                # sleep a while, the VM will take time to start fully..
                start-sleep $WaitStep
                $Timer += $WaitStep
                try {

                    # use splatting to keep the line width in-check/make it easier to read parameters
                    $connectParams = $null
                    $connectParams = @{
                        Server               = $ipAddress
                        UserName             = 'admin'
                        Password             = $cliPassword
                        DisableViAutoConnect = $true
                        DefaultConnection    = $false
                    } # end $connectParams

                    # casting to [void]; it inches some performance out by not having to process anything through the pipeline; sans | Out-Null
                    Connect-NsxServer @connectParams | Out-Null
                    break

                } catch {

                    Write-Progress -Activity "Waiting for NSX Manager api to become available" -PercentComplete $(($Timer/$WaitTimeout)*100)

                } # end try/catch

                if ( $Timer -ge $WaitTimeout ) {

                    # We exceeded the timeout - what does the user want to do?
                    $message      = "Waited more than $WaitTimeout seconds for NSX Manager API to become available.  Recommend checking boot process, network config etc."
                    $question     = "Continue waiting for NSX Manager?"
                    $yesnochoices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                    $yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                    $yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
                    $decision     = $Host.UI.PromptForChoice($message, $question, $yesnochoices, 0)

                    if ($decision -eq 0) {

                        # User waits...
                        $Timer = 0

                    } else {

                        throw "Timeout waiting for NSX Manager appliance API to become available."

                    } # end if/else $decision

                } # end if $Timer -ge $WaitTimeout

            } while ( $true )

            Write-Progress -Activity "Waiting for NSX Manager api to become available" -Completed

        } # end if $PSBoundParameters.ContainsKey('Wait')

    } # end PROCESS block

    END {

    } # end END block

} # end function New-NsxManager


function Set-NsxManager {
 
    <#
    .SYNOPSIS
    Configures appliance settings for an existing NSX Manager appliance. 

    .DESCRIPTION
    The NSX management plane is provided by NSX Manager, the centralized 
    network management component of NSX. It provides the single point of 
    configuration for NSX operations, and provides NSX's REST API.

    The Set-NsxManager cmdlet allows configuration of the applaince settings 
    such as syslog, vCenter registration and SSO configuration.

    .EXAMPLE
    Set-NsxManager -SyslogServer syslog.corp.local -SyslogPort 514 -SyslogProtocol tcp

    Configures NSX Manager Syslog destination.

    .EXAMPLE
    Set-NsxManager -ssoserver sso.corp.local -ssousername administrator@vsphere.local -ssopassword VMware1! 

    Configures the SSO Server registration of NSX Manager.

    .EXAMPLE
    Set-NsxManager -vcenterusername administrator@vsphere.local -vcenterpassword VMware1! -vcenterserver vcenter.corp.local

    Configures the vCenter registration of NSX Manager.

    #>

    Param (

        [Parameter (Mandatory=$True, ParameterSetName="Syslog")]
            #Syslog server to which syslogs will be forwarded.
            [ValidateNotNullOrEmpty()]
            [string]$SyslogServer,
        [Parameter (Mandatory=$False, ParameterSetName="Syslog")]
            #TCP/UDP port on destination syslog server to connect to.
            [ValidateRange (1,65535)]
            [int]$SyslogPort=514,
        [Parameter (Mandatory=$False, ParameterSetName="Syslog")]
            #Syslog Protocol - either TCP or UDP.
            [ValidateSet ("tcp","udp")]
            [string]$SyslogProtocol="udp",
        [Parameter (Mandatory=$True, ParameterSetName="Sso")]
            #SSO Server to register this NSX Manager with.
            [ValidateNotNullOrEmpty()]
            [string]$SsoServer,
        [Parameter (Mandatory=$False, ParameterSetName="Sso")]
            #TCP Port on SSO server to connect to when registering.
            [ValidateNotNullOrEmpty()]
            [string]$SsoPort=443,
        [Parameter (Mandatory=$True, ParameterSetName="Sso")]
            #SSO Username used for registration.
            [ValidateNotNullOrEmpty()]
            [string]$SsoUserName,
        [Parameter (Mandatory=$True, ParameterSetName="Sso")]
            #SSO Password used for registration.
            [ValidateNotNullOrEmpty()]
            [string]$SsoPassword,
        [Parameter (Mandatory=$True, ParameterSetName="vCenter")]
            #vCenter server to register this NSX Manager with.
            [ValidateNotNullOrEmpty()]
            [string]$vCenterServer,
        [Parameter (Mandatory=$True, ParameterSetName="vCenter")]
            #UserName used for vCenter connection.
            [ValidateNotNullOrEmpty()]
            [string]$vCenterUserName,
        [Parameter (Mandatory=$True, ParameterSetName="vCenter")]
            #Password used for vCenter connection.
            [ValidateNotNullOrEmpty()]
            [string]$vCenterPassword,
        [Parameter (Mandatory=$False, ParameterSetName="vCenter")]
        [Parameter (Mandatory=$False, ParameterSetName="Sso")]
            #SSL Thumbprint to validate certificate presented by SSO/vCenter server against.
            [ValidateNotNullOrEmpty()]
            [string]$SslThumbprint,
        [Parameter (Mandatory=$False, ParameterSetName="vCenter")]
        [Parameter (Mandatory=$False, ParameterSetName="Sso")]
            #Accept any SSL certificate presented by SSO/vCenter. 
            [switch]$AcceptAnyThumbprint=$True,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
        
    )


 
    [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
    
    switch ( $PsCmdlet.ParameterSetName ) { 

        "Syslog" {

            #Create the XMLRoot

            [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("syslogserver")
            $xmlDoc.appendChild($xmlRoot) | out-null

            #Create an Element and append it to the root
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "syslogServer" -xmlElementText $syslogServer.ToString()
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "port" -xmlElementText $SyslogPort.ToString()
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "protocol" -xmlElementText $SyslogProtocol
            
            $uri = "/api/1.0/appliance-management/system/syslogserver"
            $method = "put"
        }

        "Sso" {


            If ( (-not  $PsBoundParameters.ContainsKey('SslThumbprint')) -and
                (-not $AcceptAnyThumbprint )) {
                Throw "Must specify an SSL Thumbprint or AcceptAnyThumbprint"
            }

            #Need to get the SSL thumbprint for vCenter to send it in the request.
            if ( $AcceptAnyThumbprint ) { 
                try { 
                    $Cert = Test-WebServerSSL $SsoServer -erroraction Stop
                    #The cert thumprint comes back without colons separating the bytes, so we add them
                    $Thumbprint = $Cert.Certificate.Thumbprint -replace '(..(?!$))','$1:'
                }
                catch { 
                    Throw "An error occured retrieving the SSO SSL certificate.  $_"
                }
            }
            else { 
                $Thumbprint = $SslThumbprint
            }

            #Create the XMLRoot

            [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("ssoConfig")
            $xmlDoc.appendChild($xmlRoot) | out-null

            #Create an Element and append it to the root
            $SsoLookupServiceUrl = "https://$($SsoServer.ToString()):$($SsoPort.ToString())/lookupservice/sdk"
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "ssoLookupServiceUrl" -xmlElementText $SsoLookupServiceUrl
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "ssoAdminUsername" -xmlElementText $SsoUserName.ToString()
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "ssoAdminUserpassword" -xmlElementText $SsoPassword
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "certificateThumbprint" -xmlElementText $Thumbprint
            
            $method = "post"
            $uri = "/api/2.0/services/ssoconfig"
        }

        "vCenter" {


            If ( (-not  $PsBoundParameters.ContainsKey('SslThumbprint')) -and
                (-not $AcceptAnyThumbprint )) {
                Throw "Must specify an SSL Thumbprint or AcceptAnyThumbprint"
            }

            #Need to get the SSL thumbprint for vCenter to send it in the request.
            if ( $AcceptAnyThumbprint ) { 
                try { 
                    $VcCert = Test-WebServerSSL $vCenterServer -erroraction Stop
                    #The cert thumprint comes back without colons separating the bytes, so we add them
                    $Thumbprint = $VcCert.Certificate.Thumbprint -replace '(..(?!$))','$1:'
                }
                catch { 
                    Throw "An error occured retrieving the vCenter SSL certificate.  $_"
                }
            }
            else { 
                $Thumbprint = $SslThumbprint
            }

            #Build the XML
            [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("vcInfo")
            $xmlDoc.appendChild($xmlRoot) | out-null

            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "ipAddress" -xmlElementText $vCenterServer.ToString()
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "userName" -xmlElementText $vCenterUserName.ToString()
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "password" -xmlElementText $vCenterPassword.ToString()
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "certificateThumbprint" -xmlElementText $Thumbprint
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "assignRoleToUser" -xmlElementText "true"
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "pluginDownloadServer" -xmlElementText ""
            $method = "put"
            $uri = "/api/2.0/services/vcconfig"

        }
    }

    Invoke-NsxRestMethod -Method $method -body $xmlRoot.outerXml -uri $uri -Connection $Connection
}

function Get-NsxManagerSsoConfig {

    <#
    .SYNOPSIS
    Retrieves NSX Manager SSO Configuration.

    .DESCRIPTION
    The NSX Manager is the central management component of VMware NSX for 
    vSphere.  

    The SSO configuration of NSX Manager controls its registration with VMware
    SSO server for authentication purposes.

    The Get-NsxManagerSsoConfig cmdlet retrieves the SSO configuration and 
    status of the NSX Manager against which the command is run.
    
    .EXAMPLE
    Get-NsxManagerSsoConfig
    
    Retreives the SSO configuration from the connected NSX Manager 
    #>


    param (
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $URI = "/api/2.0/services/ssoconfig"

    [System.Xml.XmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
    
    if ($response.SelectsingleNode('descendant::ssoConfig/vsmSolutionName')) { 
        $ssoConfig = $response.ssoConfig

        #Only if its configured do we get status
        $URI = "/api/2.0/services/ssoconfig/status"
        [System.Xml.XmlDocument]$status = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        Add-XmlElement -xmlRoot $ssoConfig -xmlElementName "Connected" -xmlElementText $status.boolean
        #really?  Boolean?  What bonehead wrote this API?

        $ssoConfig
        
    }
}

function Get-NsxManagerVcenterConfig {
    <#
    .SYNOPSIS
    Retrieves NSX Manager vCenter Configuration.

    .DESCRIPTION
    The NSX Manager is the central management component of VMware NSX for 
    vSphere.  

    The vCenter configuration of NSX Manager controls its registration with 
    VMware vCenter server for authentication purposes.

    The Get-NsxManagerVcenterConfig cmdlet retrieves the vCenterconfiguration 
    and status of the NSX Manager against which the command is run.
    
    .EXAMPLE
    Get-NsxManagerSsoConfig
    
    Retreives the SSO configuration from the connected NSX Manager 
    #>


    param (
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $URI = "/api/2.0/services/vcconfig"

    [System.Xml.XmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
    
    if ($response.SelectsingleNode('descendant::vcInfo/ipAddress')) { 
        $vcConfig = $response.vcInfo

        #Only if its configured do we get status
        $URI = "/api/2.0/services/vcconfig/status"
        [System.Xml.XmlDocument]$status = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        Add-XmlElement -xmlRoot $vcConfig -xmlElementName "Connected" -xmlElementText $status.vcConfigStatus.Connected

        $vcConfig        
    }
}

function Get-NsxManagerTimeSettings {
    <#
    .SYNOPSIS
    Retrieves NSX Manager Time Configuration.

    .DESCRIPTION
    The NSX Manager is the central management component of VMware NSX for 
    vSphere.  

    The Get-NsxManagerTimeSettings cmdlet retrieves the time related
    configuration of the NSX Manager against which the command is run.
    
    .EXAMPLE
    Get-NsxManagerTimeSettings
    
    Retreives the time configuration from the connected NSX Manager 
    #>


    param (
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $URI = "/api/1.0/appliance-management/system/timesettings"

    $result = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
    #NSX 6.2.3/4 changed API schema here! :( Grrrr.  Have to test and return consistent object

    if ( $result -is [System.Xml.XmlDocument]) {
        #Assume the timesettings child exists.
        $result.timeSettings
    }
    elseif ( $result -is [pscustomobject] ) { 
        #Pre 6.2.3 manager response.
        [System.XML.XMLDocument]$xmldoc = New-Object System.Xml.XmlDocument
        [System.XML.XMLElement]$xmlTimeSettings = $xmlDoc.CreateElement('timeSettings')
        $xmldoc.AppendChild($xmlTimeSettings) | out-null

        [System.XML.XMLElement]$xmlNTPServerString = $xmlDoc.CreateElement('ntpServer')
        $xmlTimeSettings.Appendchild($xmlNTPServerString) | out-null
        
        Add-XmlElement -xmlRoot $xmlNTPServerString -xmlElementName "string" -xmlElementText $result.ntpServer
        Add-XmlElement -xmlRoot $xmlTimeSettings -xmlElementName "datetime" -xmlElementText $result.datetime
        Add-XmlElement -xmlRoot $xmlTimeSettings -xmlElementName "timezone" -xmlElementText $result.timezone
        $xmlTimeSettings
    }  
}

function Get-NsxManagerSyslogServer {
    <#
    .SYNOPSIS
    Retrieves NSX Manager Syslog Configuration.

    .DESCRIPTION
    The NSX Manager is the central management component of VMware NSX for 
    vSphere.  

    The Get-NsxManagerSyslog cmdlet retrieves the time related
    configuration of the NSX Manager against which the command is run.
    
    .EXAMPLE
    Get-NsxManagerSyslogServer
    
    Retreives the Syslog server configuration from the connected NSX Manager 
    #>


    param (
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $URI = "/api/1.0/appliance-management/system/syslogserver"

    $result = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection 

    #NSX 6.2.3/4 changed API schema here! :( Grrrr.  Have to test and return consistent object
    if ( $result -is [System.Xml.XmlDocument]) {
        #Assume the timesettings child exists.
        $result.syslogserver
    }
    elseif ( $result -is [pscustomobject] ) { 
        #Pre 6.2.3 manager response.
        [System.XML.XMLDocument]$xmldoc = New-Object System.Xml.XmlDocument
        [System.XML.XMLElement]$xmlSyslog = $xmlDoc.CreateElement('syslogserver')
        $xmldoc.AppendChild($xmlSyslog) | out-null

        Add-XmlElement -xmlRoot $xmlSyslog -xmlElementName "syslogServer" -xmlElementText $result.syslogServer
        Add-XmlElement -xmlRoot $xmlSyslog -xmlElementName "port" -xmlElementText $result.port
        Add-XmlElement -xmlRoot $xmlSyslog -xmlElementName "protocol" -xmlElementText $result.protocol
        $xmlSyslog
    }  
}

function Get-NsxManagerNetwork {
    <#
    .SYNOPSIS
    Retrieves NSX Manager Network Configuration.

    .DESCRIPTION
    The NSX Manager is the central management component of VMware NSX for 
    vSphere.  

    The Get-NsxManagerNetwork cmdlet retrieves the network related
    configuration of the NSX Manager against which the command is run.
    
    .EXAMPLE
    Get-NsxManagerNetwork
    
    Retreives the Syslog server configuration from the connected NSX Manager 
    #>


    param (
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $URI = "/api/1.0/appliance-management/system/network"

    $result = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection 

    if ( $result -is [System.Xml.XmlDocument]) {
        #Assume the child exists.
        $result.network
    }
    elseif ( $result -is [pscustomobject] ) { 
        #Pre 6.2.3 manager response.
        #This hacky attempt to return a consistent object is definately not that universal - but there is fidelity lost in the API reponse that 
        #prevents me from easily reconsructing the correct XML.  So I had to reverse engineer based on a 6.2.3 example response.  Hopefully this 
        #will just go away quietly...

        [System.XML.XMLDocument]$xmldoc = New-Object System.Xml.XmlDocument
        [System.XML.XMLElement]$xmlnetwork = $xmlDoc.CreateElement('network')
        [System.XML.XMLElement]$xmlnetworkIPv4AddressDto = $xmlDoc.CreateElement('networkIPv4AddressDto')
        $xmldoc.AppendChild($xmlnetwork) | out-null

        if ( $result.networkIPv4AddressDto) { 
            $xmlnetwork.AppendChild($xmlnetworkIPv4AddressDto) | out-null
            Add-XmlElement -xmlRoot $xmlnetworkIPv4AddressDto -xmlElementName "ipv4Address" -xmlElementText $result.networkIPv4AddressDto.ipv4Address
            Add-XmlElement -xmlRoot $xmlnetworkIPv4AddressDto -xmlElementName "ipv4NetMask" -xmlElementText $result.networkIPv4AddressDto.ipv4NetMask
            Add-XmlElement -xmlRoot $xmlnetworkIPv4AddressDto -xmlElementName "ipv4Gateway" -xmlElementText $result.networkIPv4AddressDto.ipv4Gateway
        }
        
        if ( $result.hostname ) { 
            Add-XmlElement -xmlRoot $xmlnetwork -xmlElementName "hostName" -xmlElementText $result.hostname
        }

        if ( $result.domainName ) {
            Add-XmlElement -xmlRoot $xmlnetwork -xmlElementName "domainName" -xmlElementText $result.domainName
        }

        if ( $result.networkIPv6AddressDto) { 

            [System.XML.XMLElement]$xmlnetworkIPv6AddressDto = $xmlDoc.CreateElement('networkIPv6AddressDto')
            $xmlnetwork.AppendChild($xmlnetworkIPv6AddressDto) | out-null
            Add-XmlElement -xmlRoot $xmlnetworkIPv6AddressDto -xmlElementName "ipv6Address" -xmlElementText $result.networkIPv4AddressDto.ipv6Address
            Add-XmlElement -xmlRoot $xmlnetworkIPv6AddressDto -xmlElementName "ipv6NetMask" -xmlElementText $result.networkIPv4AddressDto.ipv6NetMask
            Add-XmlElement -xmlRoot $xmlnetworkIPv6AddressDto -xmlElementName "ipv6Gateway" -xmlElementText $result.networkIPv4AddressDto.ipv6Gateway
        }

        if ( $result.dns ) { 
            
            [System.XML.XMLElement]$xmldns = $xmlDoc.CreateElement('dns')
            $xmlnetwork.AppendChild($xmldns) | out-null
            foreach ( $server in $result.dns.ipv4Dns ) { 
                Add-XmlElement -xmlRoot $xmldns -xmlElementName "ipv4Address" -xmlElementText $server
            }
            foreach ( $server in $result.dns.ipv6Dns ) { 
                Add-XmlElement -xmlRoot $xmldns -xmlElementName "ipv6Address" -xmlElementText $server
            }
            if ( $result.dns.domainList ) { 
                Add-XmlElement -xmlRoot $xmldns -xmlElementName "domainList" -xmlElementText $result.dns.domainList
            }

        }

        $xmlnetwork
    }  
}

function Get-NsxManagerBackup {
    <#
    .SYNOPSIS
    Retrieves NSX Manager Backup Configuration.

    .DESCRIPTION
    The NSX Manager is the central management component of VMware NSX for 
    vSphere.  

    The Get-NsxManagerBackup cmdlet retrieves the backup related
    configuration of the NSX Manager against which the command is run.
    
    .EXAMPLE
    Get-NsxManagerBackup
    
    Retreives the Backup server configuration from the connected NSX Manager 
    #>


    param (
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $URI = "/api/1.0/appliance-management/backuprestore/backupsettings"

    $result = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection

    if ( $result -is [System.Xml.XmlDocument]) {
        #Assume the child exists.
        $result.backupRestoreSettings
    }
    elseif ( $result -is [pscustomobject] ) { 
        #Pre 6.2.3 manager response.
        #This hacky attempt to return a consistent object is definately not that universal - but there is fidelity lost in the API reponse that 
        #prevents me from easily reconsructing the correct XML.  So I had to reverse engineer based on a 6.2.3 example response.  Hopefully this 
        #will just go away quietly...

        [System.XML.XMLDocument]$xmldoc = New-Object System.Xml.XmlDocument
        [System.XML.XMLElement]$xmlbackupRestoreSettings = $xmlDoc.CreateElement('backupRestoreSettings')



        foreach ( $Property in ($result |  get-member -MemberType NoteProperty )) { 
            if ( $result."$($Property.Name)" -is [string]) {  
                Add-XmlElement -xmlRoot $xmlbackupRestoreSettings -xmlElementName "$($Property.Name)" -xmlElementText $result."$($Property.Name)"
            }
            elseif ( $result."$($Property.Name)" -is [system.object]) {  
                [System.XML.XMLElement]$xmlObjElement = $xmlDoc.CreateElement($Property.Name)
                $xmlbackupRestoreSettings.AppendChild($xmlObjElement) | out-null
                foreach ( $ElementProp in ($result."$($Property.Name)" | get-member -MemberType NoteProperty )) { 
                    Add-XmlElement -xmlRoot $xmlObjElement -xmlElementName "$($ElementProp.Name)" -xmlElementText $result."$($Property.Name)"."$($ElementProp.Name)"
                }
            }
        }
        $xmlbackupRestoreSettings
    }  
}

function Get-NsxManagerComponentSummary {
    <#
    .SYNOPSIS
    Retrieves NSX Manager Component Summary Information.

    .DESCRIPTION
    The NSX Manager is the central management component of VMware NSX for 
    vSphere.  

    The Get-NsxManagerComponentSummary cmdlet retrieves the component summary
    related information of the NSX Manager against which the command is run.
    
    .EXAMPLE
    Get-NsxManagerComponentSummary
    
    Retreives the component summary information from the connected NSX Manager 
    #>


    param (
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $URI = "/api/1.0/appliance-management/summary/components"

    $result = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
    
    if ( $result -is [System.Xml.XmlDocument]) {
        #Assume the child exists.
        $result.ComponentsSummary
    }
    elseif ( $result -is [pscustomobject] ) { 
        #Pre 6.2.3 manager response.
        #This hacky attempt to return a consistent object is definately not that universal - but there is fidelity lost in the API reponse that 
        #prevents me from easily reconsructing the correct XML.  So I had to reverse engineer based on a 6.2.3 example response.  Hopefully this 
        #will just go away quietly...

        [System.XML.XMLDocument]$xmldoc = New-Object System.Xml.XmlDocument
        [System.XML.XMLElement]$xmlComponentsSummary = $xmlDoc.CreateElement('componentsSummary')
        [System.XML.XMLElement]$xmlComponentsByGroup = $xmlDoc.CreateElement('componentsByGroup')
        $xmldoc.AppendChild($xmlComponentsSummary) | out-null
        $xmlComponentsSummary.AppendChild($xmlComponentsByGroup) | out-null

        foreach ( $NamedProperty in (get-member -InputObject $result.componentsByGroup -MemberType NoteProperty)) { 

            [System.XML.XMLElement]$xmlEntry = $xmlDoc.CreateElement('entry')
            $xmlComponentsByGroup.AppendChild($xmlEntry) | out-null

            Add-XmlElement -xmlRoot $xmlEntry -xmlElementName "string" -xmlElementText $NamedProperty.Name

            [System.XML.XMLElement]$xmlComponents = $xmlDoc.CreateElement('components')
            $xmlEntry.AppendChild($xmlComponents) | out-null

            foreach ( $component in $result.componentsByGroup.($NamedProperty.name).components) { 
            
                [System.XML.XMLElement]$xmlComponent = $xmlDoc.CreateElement('component')
                $xmlComponents.AppendChild($xmlComponent) | out-null

                foreach ( $NoteProp in ($component | Get-Member -Membertype NoteProperty) ) { 

                    #Check if I actually have a value
                    if ( $component.($NoteProp.Name) ) { 
                        
                        $Property = $component.($NoteProp.Name)
                        write-debug "GetType: $($Property.gettype())"
                        write-debug "Is: $($Property -is [array])"

                        #Switch on my value 
                        switch ( $Property.gettype() )  { 

                            "System.Object[]" { 
                                write-debug "In: Array"
                                [System.XML.XMLElement]$xmlCompArray = $xmlDoc.CreateElement($NoteProp.Name)
                                $xmlComponent.AppendChild($xmlCompArray) | out-null
                                foreach ( $member in $Property ) { 
                                    #All examples ive seen have strings, but not sure if this will stand up to scrutiny...
                                    Add-XmlElement -xmlRoot $xmlCompArray -xmlElementName $member.GetType().Name.tolower() -xmlElementText $member.ToString()
                                }
                            }

                            "string" { 
                                write-debug "In: String"
                                Add-XmlElement -xmlRoot $xmlComponent -xmlElementName $NoteProp.Name -xmlElementText $Property
                            }

                            "bool" {
                                write-debug "In: Bool"
                                Add-XmlElement -xmlRoot $xmlComponent -xmlElementName $NoteProp.Name -xmlElementText $Property.ToString().tolower()
                            }
                            default { write-debug "Fuck it : $_" }
                        }
                    }
                }
            }
        }
        $xmlComponentsSummary
    }  
}

function Get-NsxManagerSystemSummary {
    <#
    .SYNOPSIS
    Retrieves NSX Manager System Summary Information.

    .DESCRIPTION
    The NSX Manager is the central management component of VMware NSX for 
    vSphere.  

    The Get-NsxManagerSystemSummary cmdlet retrieves the component summary
    related information of the NSX Manager against which the command is run.
    
    .EXAMPLE
    Get-NsxManagerSystemSummary
    
    Retreives the system summary information from the connected NSX Manager 
    #>


    param (
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $URI = "/api/1.0/appliance-management/summary/system"

    $result = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection

    if ( $result -is [System.Xml.XmlDocument]) {
        #Assume the child exists.
        $result.systemSummary
    }
    elseif ( $result -is [pscustomobject] ) { 
        #Pre 6.2.3 manager response.
        #This hacky attempt to return a consistent object is definately not that universal - but there is fidelity lost in the API reponse that 
        #prevents me from easily reconsructing the correct XML.  So I had to reverse engineer based on a 6.2.3 example response.  Hopefully this 
        #will just go away quietly...

        [System.XML.XMLDocument]$xmldoc = New-Object System.Xml.XmlDocument
        [System.XML.XMLElement]$xmlsystemSummary = $xmlDoc.CreateElement('systemSummary')



        foreach ( $Property in ($result |  get-member -MemberType NoteProperty )) { 
            if ( $result."$($Property.Name)" -is [string]) {  
                Add-XmlElement -xmlRoot $xmlsystemSummary -xmlElementName "$($Property.Name)" -xmlElementText $result."$($Property.Name)"
            }
            elseif ( $result."$($Property.Name)" -is [system.object]) {  
                [System.XML.XMLElement]$xmlObjElement = $xmlDoc.CreateElement($Property.Name)
                $xmlsystemSummary.AppendChild($xmlObjElement) | out-null
                foreach ( $ElementProp in ($result."$($Property.Name)" | get-member -MemberType NoteProperty )) { 
                    Add-XmlElement -xmlRoot $xmlObjElement -xmlElementName "$($ElementProp.Name)" -xmlElementText $result."$($Property.Name)"."$($ElementProp.Name)"
                }
            }
        }

        $xmlsystemSummary
    }  
}

function New-NsxController {
    
    <#
    .SYNOPSIS
    Deploys a new NSX Controller.

    .DESCRIPTION
    An NSX Controller is a member of the NSX Controller Cluster, and forms the 
    highly available distributed control plane for NSX Logical Switching and NSX
    Logical Routing.

    The New-NsxController cmdlet deploys a new NSX Controller.
    
    .EXAMPLE
    $ippool = New-NsxIpPool -Name ControllerPool -Gateway 192.168.0.1 -SubnetPrefixLength 24 -StartAddress 192.168.0.10 -endaddress 192.168.0.20
    $ControllerCluster = Get-Cluster vSphereCluster
    $ControllerDatastore = Get-Datastore $ControllerDatastoreName -server $Connection.VIConnection 
    $ControllerPortGroup = Get-VDPortGroup $ControllerPortGroupName -server $Connection.VIConnection
    New-NsxController -ipPool $ippool -cluster $ControllerCluster -datastore $ControllerDatastore -PortGroup $ControllerPortGroup -password $DefaultNsxControllerPassword -connection $Connection -confirm:$false

    
    #>

 
    param (

        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$True)]
            [ValidateScript({ Validate-IpPool $_ })]
            [System.Xml.XmlElement]$IpPool,
        [Parameter (Mandatory=$true,ParameterSetName="ResourcePool")]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ResourcePoolInterop]$ResourcePool,
        [Parameter (Mandatory=$true,ParameterSetName="Cluster")]
            [ValidateScript({
                if ( $_ -eq $null ) { throw "Must specify Cluster."}
                if ( -not $_.DrsEnabled ) { throw "Cluster is not DRS enabled."}
                $true
            })]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop]$Cluster,    
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.DatastoreManagement.DatastoreInterop]$Datastore,  
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-LogicalSwitchOrDistributedPortGroup $_ })]
            [object]$PortGroup,
        [Parameter (Mandatory=$True)]
            [string]$Password,
        [Parameter ( Mandatory=$False)]
            [switch]$Wait=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
        
    )
    
    begin {
    }

    process {

        [System.Xml.XmlDocument]$xmlDoc = New-Object System.Xml.XmlDocument
        #Create the new route element.
        $ControllerSpec = $xmlDoc.CreateElement('controllerSpec')

        Add-XmlElement -xmlRoot $ControllerSpec -xmlElementName "ipPoolId" -xmlElementText $IpPool.objectId.ToString()

        #The following is required (or error is thrown), but is ignored, as the
        #OVF options end up setting the VM spec... :|
        Add-XmlElement -xmlRoot $ControllerSpec -xmlElementName "deployType" -xmlElementText "small"

        switch ( $PsCmdlet.ParameterSetName ) {

            "Cluster" { 
                Add-XmlElement -xmlRoot $ControllerSpec -xmlElementName "resourcePoolId" -xmlElementText $Cluster.ExtensionData.Moref.Value.ToString()
            }
            "ResourcePool" { 
                Add-XmlElement -xmlRoot $ControllerSpec -xmlElementName "resourcePoolId" -xmlElementText $ResourcePool.ExtensionData.Moref.Value.ToString()
            }
        }

        Add-XmlElement -xmlRoot $ControllerSpec -xmlElementName "datastoreId" -xmlElementText $DataStore.ExtensionData.Moref.value.ToString()
        Add-XmlElement -xmlRoot $ControllerSpec -xmlElementName "networkId" -xmlElementText $PortGroup.ExtensionData.Moref.Value.ToString()
        Add-XmlElement -xmlRoot $ControllerSpec -xmlElementName "password" -xmlElementText $Password.ToString()
        
        $URI = "/api/2.0/vdn/controller"
        $body = $ControllerSpec.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "Adding a new controller to the NSX controller cluster.  ONLY three controllers are supported.  Then shalt thou count to three, no more, no less. Three shall be the number thou shalt count, and the number of the counting shall be three. Four shalt thou not count, neither count thou two, excepting that thou then proceed to three. Five is right out. Once the number three, being the third number, be reached, then lobbest thou thy Holy Hand Grenade of Antioch towards thy foe, who being naughty in My sight, shall snuff it."
            $question = "Proceed with controller deployment?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Deploying NSX Controller"
            $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
            write-progress -activity "Deploying NSX Controller" -completed
            $Controller = Get-NsxController -connection $connection | Sort-Object -Property id | Select-Object -last 1
            
            if ( $Wait ) {
                
                #User wants to wait for Controller API to start.
                $waitStep = 30
                $WaitTimeout = 600
                
                $Timer = 0
                while ( $Controller.status -ne 'RUNNING' ) {

                    #Loop while the controller is deploying (not RUNNING)
                    Write-Progress "Waiting for NSX controller to enter a running state. (Current state: $($Controller.Status)) "
                    start-sleep $WaitStep
                    $Timer += $WaitStep

                    if ( $Timer -ge $WaitTimeout ) { 
                        #We exceeded the timeout - what does the user want to do? 
                        $message  = "Waited more than $WaitTimeout seconds for controller to become available.  Recommend checking boot process, network config etc."
                        $question = "Continue waiting for Controller?"
                        $yesnochoices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                        $yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                        $yesnochoices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))
                        $decision = $Host.UI.PromptForChoice($message, $question, $yesnochoices, 0)
                        if ($decision -eq 0) {
                           #User waits...
                           $timer = 0
                        }
                        else {
                            throw "Timeout waiting for controller $($controller.id) to become available."
                        }  
                    }

                    $Controller = Get-Nsxcontroller -connection $connection -objectId ($controller.id)
                }
                Write-Progress "Waiting for NSX controller to enter a running state. (Current state: $($Controller.Status))" -Completed
            }
            $controller
        }
    }

    end {}
}

function Get-NsxController {

    <#
    .SYNOPSIS
    Retrieves NSX Controllers.

    .DESCRIPTION
    An NSX Controller is a member of the NSX Controller Cluster, and forms the 
    highly available distributed control plane for NSX Logical Switching and NSX
    Logical Routing.

    The Get-NsxController cmdlet deploys a new NSX Controller via the NSX API.
    
    .EXAMPLE
    Get-NsxController
    
    Retreives all controller objects from NSX manager

    .EXAMPLE
    Get-NsxController -objectId Controller-1

    Returns a specific NSX Controller object from NSX manager 
    #>


    param (
        [Parameter (Mandatory=$false,Position=1)]
            #ObjectId of the NSX Controller to return.
            [string]$ObjectId,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $URI = "/api/2.0/vdn/controller"

    [System.Xml.XmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
    
        if ($response.SelectsingleNode('descendant::controllers/controller')) { 
        if ( $PsBoundParameters.containsKey('objectId')) { 
            $response.controllers.controller | ? { $_.Id -eq $ObjectId }
        } else {
            $response.controllers.controller
        }
    }
}

function New-NsxIpPool {
    
    <#
    .SYNOPSIS
    Creates a new IP Pool.

    .DESCRIPTION
    An IP Pool is a simple IPAM construct in NSX that simplifies automated IP 
    address asignment for multiple NSX technologies including VTEP interfaces 
    NSX Controllers.

    The New-NsxIpPool cmdlet creates a new IP Pool on the connected NSX manager.
    
    #>

      
     param (

        [Parameter (Mandatory=$true, Position=1)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ipAddress]$Gateway,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [ipAddress]$DnsServer1,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [ipAddress]$DnsServer2,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$DnsSuffix,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ipaddress]$StartAddress,       
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [ipaddress]$EndAddress, 
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 


            
        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlPool = $XMLDoc.CreateElement("ipamAddressPool")
        $xmlDoc.Appendchild($xmlPool) | out-null

        #Mandatory and default params 
        Add-XmlElement -xmlRoot $xmlPool -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlPool -xmlElementName "prefixLength" -xmlElementText $SubnetPrefixLength
        Add-XmlElement -xmlRoot $xmlPool -xmlElementName "gateway" -xmlElementText $Gateway

        #Start/End of range
        $xmlIpRanges = $xmlDoc.CreateElement("ipRanges")
        $xmlIpRange = $xmlDoc.CreateElement("ipRangeDto")
        $xmlPool.Appendchild($xmlIpRanges) | out-null
        $xmlIpRanges.Appendchild($xmlIpRange) | out-null

        Add-XmlElement -xmlRoot $xmlIpRange -xmlElementName "startAddress" -xmlElementText $StartAddress
        Add-XmlElement -xmlRoot $xmlIpRange -xmlElementName "endAddress" -xmlElementText $EndAddress


        #Optional params
        if ( $PsBoundParameters.ContainsKey('DnsServer1')) { 
            Add-XmlElement -xmlRoot $xmlPool -xmlElementName "dnsServer1" -xmlElementText $DnsServer1
        }
        if ( $PsBoundParameters.ContainsKey('DnsServer2')) { 
            Add-XmlElement -xmlRoot $xmlPool -xmlElementName "dnsServer2" -xmlElementText $DnsServer2
        }
        if ( $PsBoundParameters.ContainsKey('DnsSuffix')) { 
            Add-XmlElement -xmlRoot $xmlPool -xmlElementName "dnsSuffix" -xmlElementText $DnsSuffix
        }


        # #Do the post
        $body = $xmlPool.OuterXml
        $URI = "/api/2.0/services/ipam/pools/scope/globalroot-0"
        Write-Progress -activity "Creating IP Pool."
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection
        Write-progress -activity "Creating IP Pool." -completed

        Get-NsxIpPool -objectId $response -connection $connection

    }

    end {}
}

function Get-NsxIpPool {

    <#
    .SYNOPSIS
    Retrieves NSX Ip Pools.

    .DESCRIPTION
    An IP Pool is a simple IPAM construct in NSX that simplifies automated IP 
    address asignment for multiple NSX technologies including VTEP interfaces 
    NSX Controllers.


    The Get-IpPool cmdlet retreives an NSX IP Pools
    
    #>

    [CmdletBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$false,Position=1,ParameterSetName = "Name")]
            [string]$Name,
        [Parameter (Mandatory=$false, ParameterSetName = "ObjectId")]
            [string]$ObjectId,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    if ( $PsBoundParameters.ContainsKey('ObjectId')) { 

        $URI = "/api/2.0/services/ipam/pools/$ObjectId"
        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        $response.ipamAddressPool
    }
    else { 

        $URI = "/api/2.0/services/ipam/pools/scope/globalroot-0"
        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        If ( $PsBoundParameters.ContainsKey("Name")) { 

            $response.ipamAddressPools.ipamAddressPool | ? { $_.name -eq $Name }
        }
        else {     
            $response.ipamAddressPools.ipamAddressPool
        }
    }
}

function Get-NsxVdsContext {

    <#
    .SYNOPSIS
    Retrieves a VXLAN Prepared Virtual Distributed Switch.

    .DESCRIPTION
    Before it can be used for VXLAN, a VDS must be configured with appropriate 
    teaming and MTU configuration.

    The Get-NsxVdsContext cmdlet retreives VDS's that have been prepared for 
    VXLAN configuration.

    #>

    [CmdletBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$false,Position=1,ParameterSetName = "Name")]
            [string]$Name,
        [Parameter (Mandatory=$false, ParameterSetName = "ObjectId")]
            [string]$ObjectId,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    if ( $PsBoundParameters.ContainsKey('ObjectId')) { 

        $URI = "/api/2.0/vdn/switches/$ObjectId"
        [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        If ( $response | get-member -memberType properties vdsContext ) { 
            $response.vdsContext
        }
    }
    else { 

        $URI = "/api/2.0/vdn/switches"
        [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        If ( $PsBoundParameters.ContainsKey("Name")) { 

            If ( $response | get-member -memberType properties vdsContexts ) { 
                if ( $response.vdsContexts.SelectSingleNode("descendant::vdsContext")) { 
                    $response.vdsContexts.vdsContext | ? { $_.switch.name -eq $Name }
                }
            }
        }
        else {
            If ( $response | get-member -memberType properties vdsContexts ) { 
                if ( $response.vdsContexts.SelectSingleNode("descendant::vdsContext")) { 
                    $response.vdsContexts.vdsContext
                }
            }
        }
    }
}

function New-NsxVdsContext {
    
    <#
    .SYNOPSIS
    Creates a VXLAN Prepared Virtual Distributed Switch.

    .DESCRIPTION
    Before it can be used for VXLAN, a VDS must be configured with appropriate 
    teaming and MTU configuration.

    The New-NsxVdsContext cmdlet configures the specified VDS for use with 
    VXLAN. 

    #>

      
     param (

        [Parameter (Mandatory=$true, Position=1)]
            [ValidateScript({ Validate-DistributedSwitch $_ })]
            [object]$VirtualDistributedSwitch,
        [Parameter (Mandatory=$true)]
            [ValidateSet("FAILOVER_ORDER", "ETHER_CHANNEL", "LACP_ACTIVE", "LACP_PASSIVE","LOADBALANCE_LOADBASED", "LOADBALANCE_SRCID", "LOADBALANCE_SRCMAC", "LACP_V2",IgnoreCase=$false)]
            [string]$Teaming,
        [Parameter (Mandatory=$true)]
            [ValidateRange(1600,9000)]
            [int]$Mtu,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 


            
        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlContext = $XMLDoc.CreateElement("nwFabricFeatureConfig")
        $xmlDoc.Appendchild($xmlContext) | out-null


        Add-XmlElement -xmlRoot $xmlContext -xmlElementName "featureId" -xmlElementText "com.vmware.vshield.vsm.vxlan"

        #configSpec
        $xmlResourceConfig = $xmlDoc.CreateElement("resourceConfig")
        $xmlConfigSpec = $xmlDoc.CreateElement("configSpec")
        $xmlConfigSpec.SetAttribute("class","vdsContext")
        $xmlContext.Appendchild($xmlResourceConfig) | out-null
        $xmlResourceConfig.Appendchild($xmlConfigSpec) | out-null

        Add-XmlElement -xmlRoot $xmlConfigSpec -xmlElementName "teaming" -xmlElementText $Teaming.toString()
        Add-XmlElement -xmlRoot $xmlConfigSpec -xmlElementName "mtu" -xmlElementText $Mtu.ToString()

        $xmlSwitch = $xmlDoc.CreateElement("switch")
        $xmlConfigSpec.Appendchild($xmlSwitch) | out-null

        Add-XmlElement -xmlRoot $xmlSwitch -xmlElementName "objectId" -xmlElementText $VirtualDistributedSwitch.Extensiondata.Moref.Value.ToString()

        Add-XmlElement -xmlRoot $xmlResourceConfig -xmlElementName "resourceId" -xmlElementText $VirtualDistributedSwitch.Extensiondata.Moref.Value.ToString()



        # #Do the post
        $body = $xmlContext.OuterXml
        $URI = "/api/2.0/nwfabric/configure"
        Write-Progress -activity "Configuring VDS context on VDS $($VirtualDistributedSwitch.Name)."
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection
        Write-progress -activity "Configuring VDS context on VDS $($VirtualDistributedSwitch.Name)." -completed

        Get-NsxVdsContext -objectId $VirtualDistributedSwitch.Extensiondata.Moref.Value -connection $connection


    }

    end {}
}

function Remove-NsxVdsContext {

    <#
    .SYNOPSIS
    Removes the VXLAN preparation of a Virtual Distributed Switch.

    .DESCRIPTION
    Before it can be used for VXLAN, a VDS must be configured with appropriate 
    teaming and MTU configuration.

    The Remove-NsxVdsContext cmdlet unconfigures the specified VDS for use with 
    VXLAN. 

    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-VdsContext $_ })]
            [System.Xml.XmlElement]$VdsContext,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Vds Context removal is permanent."
            $question = "Proceed with removal of Vds Context for Vds $($VdsContext.Switch.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/2.0/vdn/switches/$($VdsContext.Switch.ObjectId)"
            Write-Progress -activity "Remove Vds Context for Vds $($VdsContext.Switch.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
            Write-Progress -activity "Remove Vds Context for Vds $($VdsContext.Switch.Name)" -completed

        }
    }

    end {}
}

function New-NsxClusterVxlanConfig { 
    
    <#
    .SYNOPSIS
    Configures a vSphere cluster for VXLAN.

    .DESCRIPTION
    VXLAN configuration of a vSphere cluster involves associating the cluster 
    with an NSX prepared VDS, and configuration of VLAN id for the atuomatically 
    created VTEP portgroup, VTEP count and VTEP addressing.

    If the VDS specified is not configured for VXLAN, then an error is thrown.
    Use New-NsxVdsContext to configure a VDS for use with NSX.

    If the specified cluster is not prepared with the necessary VIBs installed,
    then installation occurs automatically.  Use Install-NsxClusterVibs to 
    prepare a clusters hosts for use with NSX without configuring VXLAN

    If an IP Pool is not specified, DHCP will be used to configure the host 
    VTEPs.

    The New-NsxClusterVxlan cmdlet will perform the VXLAN configuration of all 
    hosts within the specified cluster.

    #>

      
    param (

        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop]$Cluster,
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-DistributedSwitch $_ })]
            [object]$VirtualDistributedSwitch,
        [Parameter (Mandatory=$False)]
            [ValidateScript({ Validate-IpPool $_ })]
            [System.Xml.XmlElement]$IpPool,
        [Parameter (Mandatory=$False)]
            [int]$VlanId="",
        [Parameter (Mandatory=$False)]
            [ValidateNotNullorEmpty()]
            [int]$VtepCount,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullorEmpty()]
            [int]$VxlanPrepTimeout=120,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 
            
        $VxlanWaitTime = 10 #seconds 

        #Check that the VDS has a VDS context in NSX and is configured.
        try { 
            $vdscontext = Get-NsxVdsContext -objectId $VirtualDistributedSwitch.Extensiondata.MoRef.Value -connection $connection 
        }
        catch {
            throw "Specified VDS is not configured for NSX.  Use New-NsxVdsContext to configure the VDS and try again."
        }

        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlContext = $XMLDoc.CreateElement("nwFabricFeatureConfig")
        $xmlDoc.Appendchild($xmlContext) | out-null


        Add-XmlElement -xmlRoot $xmlContext -xmlElementName "featureId" -xmlElementText "com.vmware.vshield.vsm.vxlan"

        #configSpec
        $xmlResourceConfig = $xmlDoc.CreateElement("resourceConfig")
        $xmlConfigSpec = $xmlDoc.CreateElement("configSpec")
        $xmlConfigSpec.SetAttribute("class","clusterMappingSpec")
        $xmlContext.Appendchild($xmlResourceConfig) | out-null
        $xmlResourceConfig.Appendchild($xmlConfigSpec) | out-null

        if ( $PSBoundParameters.ContainsKey('IpPool')) { 
            Add-XmlElement -xmlRoot $xmlConfigSpec -xmlElementName "ipPoolId" -xmlElementText $IpPool.objectId.toString()
        }
        Add-XmlElement -xmlRoot $xmlConfigSpec -xmlElementName "vlanId" -xmlElementText $VlanId.ToString()
        Add-XmlElement -xmlRoot $xmlConfigSpec -xmlElementName "vmknicCount" -xmlElementText $VtepCount.ToString()

        $xmlSwitch = $xmlDoc.CreateElement("switch")
        $xmlConfigSpec.Appendchild($xmlSwitch) | out-null

        Add-XmlElement -xmlRoot $xmlSwitch -xmlElementName "objectId" -xmlElementText $VirtualDistributedSwitch.Extensiondata.Moref.Value.ToString()
        Add-XmlElement -xmlRoot $xmlResourceConfig -xmlElementName "resourceId" -xmlElementText $Cluster.Extensiondata.Moref.Value.ToString()

        Write-Progress -id 1 -activity "Configuring VXLAN on cluster $($Cluster.Name)." -status "In Progress..."

        # #Do the post
        $body = $xmlContext.OuterXml
        $URI = "/api/2.0/nwfabric/configure"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection

        #Get Initial Status 
        $status = $cluster | get-NsxClusterStatus -connection $connection
        $hostprep = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.nwfabric.hostPrep' -statusxml $status
        $fw = Get-FeatureStatus -featurestring 'com.vmware.vshield.firewall' -statusxml $status
        $messagingInfra = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.messagingInfra' -statusxml $status
        $VxlanConfig = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.vxlan' -statusxml $status

        $timer = 0
        while ( ($hostprep -ne 'GREEN') -or
                ($fw -ne 'GREEN') -or
                ($messagingInfra -ne 'GREEN') -or
                ($VxlanConfig -ne 'GREEN')) {

            start-sleep $VxlanWaitTime
            $timer += $VxlanWaitTime
            
            #Get Status
            $status = $cluster | get-NsxClusterStatus -connection $connection
            $hostprep = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.nwfabric.hostPrep' -statusxml $status
            $fw = Get-FeatureStatus -featurestring 'com.vmware.vshield.firewall' -statusxml $status
            $messagingInfra = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.messagingInfra' -statusxml $status
            $VxlanConfig = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.vxlan' -statusxml $status

            #Check Status
            if ( $hostprep -eq 'GREEN' ) { $status = "Complete"} else { $status = "Waiting" }
            Write-Progress -parentid 1 -id 2 -activity "Vib Install Status: $hostprep" -status $status

            if ( $fw -eq 'GREEN' ) { $status = "Complete"} else { $status = "Waiting" }
            Write-Progress -parentid 1 -id 3 -activity "Firewall Install Status: $fw" -status $status

            if ( $messagingInfra -eq 'GREEN' ) { $status = "Complete"} else { $status = "Waiting" }
            Write-Progress -parentid 1 -id 4 -activity "Messaging Infra Status: $messagingInfra" -status $status

            if ( $VxlanConfig -eq 'GREEN' ) { $status = "Complete"} else { $status = "Waiting" }
            Write-Progress -parentid 1 -id 5 -activity "VXLAN Config Status: $VxlanConfig" -status $status

            if ($Timer -ge $VxlanPrepTimeout) {

                $message  = "Cluster $($cluster.name) preparation has not completed within the timeout period."
                $question = "Continue waiting (y) or quit (n)?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 0)
                if ( $decision -eq 1 ) {
                    Throw "$($cluster.name) cluster preparation failed or timed out."
                }
                $Timer = 0
            }
        }

        Write-Progress -parentid 1 -id 2 -activity "Vib Install Status: $hostprep" -completed
        Write-Progress -parentid 1 -id 3 -activity "Firewall Install Status: $fw" -completed
        Write-Progress -parentid 1 -id 4 -activity "Messaging Infra Status: $messagingInfra" -completed
        Write-Progress -parentid 1 -id 5 -activity "VXLAN Config Status: $VxlanConfig" -completed
        Write-Progress -id 1 -activity "Configuring VXLAN on cluster $($Cluster.Name)." -completed
        $cluster | get-NsxClusterStatus -connection $connection
        
    }

    end {}
}

function Install-NsxCluster { 
    
    <#
    .SYNOPSIS
    Prepares a vSphere cluster for use with NSX.

    .DESCRIPTION
    Preparation of a vSphere cluster involves installation of the vibs required
    for VXLAN, Logical routing and Distributed Firewall.

    The Install-NsxCluster cmdlet will perform the vib installation of all hosts 
    within the specified cluster.

    #>

      
    param (

        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop]$Cluster,
        [PArameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [int]$VxlanPrepTimeout=120,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

            
        $VxlanWaitTime = 10 #seconds 

        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlContext = $XMLDoc.CreateElement("nwFabricFeatureConfig")
        $xmlDoc.Appendchild($xmlContext) | out-null


        #configSpec
        $xmlResourceConfig = $xmlDoc.CreateElement("resourceConfig")
        $xmlContext.Appendchild($xmlResourceConfig) | out-null

        Add-XmlElement -xmlRoot $xmlResourceConfig -xmlElementName "resourceId" -xmlElementText $Cluster.Extensiondata.Moref.Value.ToString()

        Write-Progress -id 1 -activity "Preparing cluster $($Cluster.Name)." -status "In Progress..."

        # #Do the post
        $body = $xmlContext.OuterXml
        $URI = "/api/2.0/nwfabric/configure"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection
         
        #Get Initial Status 
        $status = $cluster | get-NsxClusterStatus -connection $Connection
        $hostprep = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.nwfabric.hostPrep' -statusxml $status
        $fw = Get-FeatureStatus -featurestring 'com.vmware.vshield.firewall' -statusxml $status
        $messagingInfra = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.messagingInfra' -statusxml $status
      
        $timer = 0
        while ( ($hostprep -ne 'GREEN') -or
                ($fw -ne 'GREEN') -or
                ($messagingInfra -ne 'GREEN') ) {

            start-sleep $VxlanWaitTime
            $timer += $VxlanWaitTime

            #Get Status
            $status = $cluster | get-NsxClusterStatus -connection $Connection
            $hostprep = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.nwfabric.hostPrep' -statusxml $status
            $fw = Get-FeatureStatus -featurestring 'com.vmware.vshield.firewall' -statusxml $status
            $messagingInfra = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.messagingInfra' -statusxml $status

            #Check Status
            if ( $hostprep -eq 'GREEN' ) { $status = "Complete"} else { $status = "Waiting" }
            Write-Progress -parentid 1 -id 2 -activity "Vib Install Status: $hostprep" -status $status

            if ( $fw -eq 'GREEN' ) { $status = "Complete"} else { $status = "Waiting" }
            Write-Progress -parentid 1 -id 3 -activity "Firewall Install Status: $fw" -status $status

            if ( $messagingInfra -eq 'GREEN' ) { $status = "Complete"} else { $status = "Waiting" }
            Write-Progress -parentid 1 -id 4 -activity "Messaging Infra Status: $messagingInfra" -status $status

            if ($Timer -ge $VxlanPrepTimeout) { 
                $message  = "Cluster $($cluster.name) preparation has not completed within the timeout period."
                $question = "Continue waiting (y) or quit (n)?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 0)
                if ( $decision -eq 1 ) {
                    Throw "$($cluster.name) cluster preparation failed or timed out."
                }
                $Timer = 0            }
        }

        Write-Progress -parentid 1 -id 2 -activity "Vib Install Status: $hostprep" -completed
        Write-Progress -parentid 1 -id 3 -activity "Firewall Install Status: $fw" -completed
        Write-Progress -parentid 1 -id 4 -activity "Messaging Infra Status: $messagingInfra" -completed
        Write-Progress -id 1 -activity "Preparing cluster $($Cluster.Name)." -status "In Progress..." -completed
        $cluster | get-NsxClusterStatus -connection $connection
    }

    end {}
}

function Remove-NsxCluster { 
    
    <#
    .SYNOPSIS
    Unprepares a vSphere cluster for use with NSX.

    .DESCRIPTION
    Preparation of a vSphere cluster involves installation of the vibs required
    for VXLAN, Logical routing and Distributed Firewall.

    The Remove-NsxCluster cmdlet will perform the vib removal of all hosts 
    within the specified cluster and will also unconfigure VXLAN if configured.

    #>

      
    param (

        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop]$Cluster,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [int]$VxlanPrepTimeout=120,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

            
        $VxlanWaitTime = 10 #seconds 

        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlContext = $XMLDoc.CreateElement("nwFabricFeatureConfig")
        $xmlDoc.Appendchild($xmlContext) | out-null


        #configSpec
        $xmlResourceConfig = $xmlDoc.CreateElement("resourceConfig")
        $xmlContext.Appendchild($xmlResourceConfig) | out-null

        Add-XmlElement -xmlRoot $xmlResourceConfig -xmlElementName "resourceId" -xmlElementText $Cluster.Extensiondata.Moref.Value.ToString()


        if ( $confirm ) { 
            $message  = "Unpreparation of cluster $($Cluster.Name) will result in unconfiguration of VXLAN, removal of Distributed Firewall and uninstallation of all NSX VIBs."
            $question = "Proceed with un-preparation of cluster $($Cluster.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {

            ###############
            #Even though it *usually* unconfigures VXLAN automatically, ive had several instances where an unprepped 
            #cluster had VXLAN config still present, and prevented future prep attempts from succeeding.  
            #This may not resolve this issue, but hopefully will... 
            $cluster | Remove-NsxClusterVxlanConfig -confirm:$false -connection $connection| out-null

            #Now we actually do the unprep...
            ##############
            Write-Progress -id 1 -activity "Unpreparing cluster $($Cluster.Name)." -status "In Progress..."

            # #Do the post
            $body = $xmlContext.OuterXml
            $URI = "/api/2.0/nwfabric/configure"
            $response = invoke-nsxrestmethod -method "delete" -uri $URI -body $body -connection $connection

            #Get Initial Status 
            $status = $cluster | get-NsxClusterStatus -connection $connection
            $hostprep = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.nwfabric.hostPrep' -statusxml $status
            $fw = Get-FeatureStatus -featurestring 'com.vmware.vshield.firewall' -statusxml $status
            $messagingInfra = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.messagingInfra' -statusxml $status
          
            $timer = 0
            while ( ($hostprep -ne 'UNKNOWN') -or
                    ($fw -ne 'UNKNOWN') -or
                    ($messagingInfra -ne 'UNKNOWN') ) {

                start-sleep $VxlanWaitTime
                $timer += $VxlanWaitTime
               
                #Get Status
                $status = $cluster | get-NsxClusterStatus -connection $connection
                $hostprep = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.nwfabric.hostPrep' -statusxml $status
                $fw = Get-FeatureStatus -featurestring 'com.vmware.vshield.firewall' -statusxml $status
                $messagingInfra = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.messagingInfra' -statusxml $status

                #Check Status
                if ( $hostprep -eq 'UNKNOWN' ) { $status = "Complete"} else { $status = "Waiting" }
                Write-Progress -parentid 1 -id 2 -activity "Vib Install Status: $hostprep" -status $status

                if ( $fw -eq 'UNKNOWN' ) { $status = "Complete"} else { $status = "Waiting" }
                Write-Progress -parentid 1 -id 3 -activity "Firewall Install Status: $fw" -status $status

                if ( $messagingInfra -eq 'UNKNOWN' ) { $status = "Complete"} else { $status = "Waiting" }
                Write-Progress -parentid 1 -id 4 -activity "Messaging Infra Status: $messagingInfra" -status $status

                if ($Timer -ge $VxlanPrepTimeout) { 

                    #Need to do some detection of hosts needing reboot here and prompt to do it automatically...

                    $message  = "Cluster $($cluster.name) unpreparation has not completed within the timeout period."
                    $question = "Continue waiting (y) or quit (n)?"

                    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 0)
                    if ( $decision -eq 1 ) {
                        Throw "$($cluster.name) cluster unpreparation failed or timed out."
                    }
                    $Timer = 0            }
            }

            Write-Progress -parentid 1 -id 2 -activity "Vib Install Status: $hostprep" -completed
            Write-Progress -parentid 1 -id 3 -activity "Firewall Install Status: $fw" -completed
            Write-Progress -parentid 1 -id 4 -activity "Messaging Infra Status: $messagingInfra" -completed
            Write-Progress -id 1 -activity "Unpreparing cluster $($Cluster.Name)." -status "In Progress..." -completed
            $cluster | get-NsxClusterStatus -connection $connection
        }
    }

    end {}
}

function Remove-NsxClusterVxlanConfig { 
    
    <#
    .SYNOPSIS
    Unconfigures VXLAN on an NSX prepared cluster.

    .DESCRIPTION
    VXLAN configuration of a vSphere cluster involves associating the cluster 
    with an NSX prepared VDS, and configuration of VLAN id for the atuomatically 
    created VTEP portgroup, VTEP count and VTEP addressing.

    The Remove-NsxClusterVxlan cmdlet will perform the unconfiguration of VXLAN
    on all hosts within the specified cluster only.  VIBs will remain installed.

    #>

      
    param (

        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop]$Cluster,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [int]$VxlanPrepTimeout=120,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

            
        $VxlanWaitTime = 10 #seconds 

        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlContext = $XMLDoc.CreateElement("nwFabricFeatureConfig")
        $xmlDoc.Appendchild($xmlContext) | out-null

        #ResourceID (must specific explicitly VXLAN)
        Add-XmlElement -xmlRoot $xmlContext -xmlElementName "featureId" -xmlElementText "com.vmware.vshield.vsm.vxlan"

        #configSpec
        $xmlResourceConfig = $xmlDoc.CreateElement("resourceConfig")
        $xmlContext.Appendchild($xmlResourceConfig) | out-null

        Add-XmlElement -xmlRoot $xmlResourceConfig -xmlElementName "resourceId" -xmlElementText $Cluster.Extensiondata.Moref.Value.ToString()


        if ( $confirm ) { 
            $message  = "Unconfiguration of VXLAN for cluster $($Cluster.Name) will result in loss of communication for any VMs connected to logical switches running in this cluster."
            $question = "Proceed with unconfiguration of VXLAN for cluster $($Cluster.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {

            Write-Progress -id 1 -activity "Unconfiguring VXLAN on $($Cluster.Name)." -status "In Progress..."

            # #Do the post
            $body = $xmlContext.OuterXml
            $URI = "/api/2.0/nwfabric/configure"
            $response = invoke-nsxrestmethod -method "delete" -uri $URI -body $body -connection $connection

            #Get Initial Status 
            $status = $cluster | get-NsxClusterStatus -connection $connection
            $VxlanConfig = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.vxlan' -statusxml $status

            $timer = 0
            while ( $VxlanConfig -ne 'UNKNOWN' ) {

                start-sleep $VxlanWaitTime
                $timer += $VxlanWaitTime
               
                #Get Status
                $status = $cluster | get-NsxClusterStatus -connection $connection
                $VxlanConfig = Get-FeatureStatus -featurestring 'com.vmware.vshield.vsm.vxlan' -statusxml $status

                #Check Status
                if ( $VxlanConfig -eq 'UNKNOWN' ) { $status = "Complete"} else { $status = "Waiting" }
                Write-Progress -parentid 1 -id 5 -activity "VXLAN Config Status: $VxlanConfig" -status $status

                if ($Timer -ge $VxlanPrepTimeout) { 
                    $message  = "Cluster $($cluster.name) VXLAN unconfiguration has not completed within the timeout period."
                    $question = "Continue waiting (y) or quit (n)?"

                    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 0)
                    if ( $decision -eq 1 ) {
                        Throw "$($cluster.name) cluster VXLAN unconfiguration failed or timed out."
                    }
                    $Timer = 0   
                }
            }
            
            Write-Progress -parentid 1 -id 5 -activity "VXLAN Config Status: $VxlanConfig" -completed
            Write-Progress -id 1 -activity "Unconfiguring VXLAN on $($Cluster.Name)." -status "In Progress..." -completed
            $cluster | get-NsxClusterStatus -connection $connection | ? { $_.featureId -eq "com.vmware.vshield.vsm.vxlan" }
        }
    }

    end {}
}

function New-NsxSegmentIdRange {
    
    <#
    .SYNOPSIS
    Creates a new VXLAN Segment ID Range.

    .DESCRIPTION
    Segment ID Ranges provide a method for NSX to allocate a unique identifier 
    (VNI) to each logical switch created within NSX.  

    The New-NsxSegmentIdRange cmdlet creates a new Segment range on the 
    connected NSX manager.
    
    #>

      
     param (

        [Parameter (Mandatory=$true, Position=1)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$Description,       
        [Parameter (Mandatory=$true)]
            [ValidateRange(5000,16777215)]
            [int]$Begin,
        [Parameter (Mandatory=$true)]
            [ValidateRange(5000,16777215)]
            [int]$End,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 


            
        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRange = $XMLDoc.CreateElement("segmentRange")
        $xmlDoc.Appendchild($xmlRange) | out-null

        #Mandatory and default params 
        Add-XmlElement -xmlRoot $xmlRange -xmlElementName "name" -xmlElementText $Name.ToString()
        Add-XmlElement -xmlRoot $xmlRange -xmlElementName "begin" -xmlElementText $Begin.ToString()
        Add-XmlElement -xmlRoot $xmlRange -xmlElementName "end" -xmlElementText $End.ToString()

        #Optional params
        if ( $PsBoundParameters.ContainsKey('Description')) { 
            Add-XmlElement -xmlRoot $xmlRange -xmlElementName "description" -xmlElementText $Description.ToString()
        }

        # #Do the post
        $body = $xmlRange.OuterXml
        $URI = "/api/2.0/vdn/config/segments"
        Write-Progress -activity "Creating Segment Id Range"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection
        Write-progress -activity "Creating Segment Id Range" -completed

        Get-NsxSegmentIdRange -objectId $response.segmentRange.id -connection $connection

    }

    end {}
}

function Get-NsxSegmentIdRange {

    <#
    .SYNOPSIS
    Reieves VXLAN Segment ID Ranges.

    .DESCRIPTION
    Segment ID Ranges provide a method for NSX to allocate a unique identifier 
    (VNI) to each logical switch created within NSX.  

    The Get-NsxSegmentIdRange cmdlet retreives Segment Ranges from the 
    connected NSX manager.
    
    #>

    [CmdletBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$false,Position=1,ParameterSetName = "Name")]
            [string]$Name,
        [Parameter (Mandatory=$false, ParameterSetName = "ObjectId")]
            [string]$ObjectId,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    if ( $PsBoundParameters.ContainsKey('ObjectId')) { 

        $URI = "/api/2.0/vdn/config/segments/$ObjectId"
        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        $response.segmentRange
    }
    else { 

        $URI = "/api/2.0/vdn/config/segments"
        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        If ( $PsBoundParameters.ContainsKey("Name")) { 

            $response.segmentRanges.segmentRange | ? { $_.name -eq $Name }
        }
        else {     
            $response.segmentRanges.segmentRange
        }
    }
}

function Remove-NsxSegmentIdRange {

    <#
    .SYNOPSIS
    Removes a Segment Id Range

    .DESCRIPTION
    Segment ID Ranges provide a method for NSX to allocate a unique identifier 
    (VNI) to each logical switch created within NSX.  

    The Remove-NsxSegmentIdRange cmdlet removes the specified Segment Id Range
    from the connected NSX manager.

    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-SegmentIdRange $_ })]
            [System.Xml.XmlElement]$SegmentIdRange,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Segment Id Range removal is permanent."
            $question = "Proceed with removal of Segment Id Range $($SegmentIdRange.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/2.0/vdn/config/segments/$($SegmentIdRange.Id)"
            Write-Progress -activity "Remove Segment Id Range $($SegmentIdRange.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
            Write-Progress -activity "Remove Segment Id Range $($SegmentIdRange.Name)" -completed

        }
    }

    end {}
}

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


 [CmdLetBinding(DefaultParameterSetName="Name")]

    param (

        [Parameter (Mandatory=$false,Position=1,ParameterSetName = "Name")]
            [string]$name,
        [Parameter (Mandatory=$true,ParameterSetName="objectId")]
            [ValidateNotNullOrEmpty()]
            [string]$objectId,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    if ( $psCmdlet.ParameterSetName -eq "objectId" ) {

        #Just getting a single Transport Zone by ID
        $URI = "/api/2.0/vdn/scopes/$objectId"
        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        $response.vdnscope
    }
    else { 

        #Getting all TZ and optionally filtering on name
        $URI = "/api/2.0/vdn/scopes"
        [system.xml.xmldocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        
        if ( $response.SelectsingleNode("child::vdnScopes/vdnScope")) {
            if ( $PsBoundParameters.containsKey('name') ) { 
                $response.vdnscopes.vdnscope | ? { $_.name -eq $name }
            } else {
                $response.vdnscopes.vdnscope
            }
        }
    }
}

function New-NsxTransportZone {
    
    <#
    .SYNOPSIS
    Creates a new Nsx Transport Zone.

    .DESCRIPTION
    An NSX Transport Zone defines the maximum scope for logical switches that 
    are bound to it.  NSX Prepared clusters are added to Transport Zones which
    allows VMs on them to attach to any logical switch bound to the transport 
    zone.  

    The New-NsxTransportZone cmdlet creates a new Transport Zone on the 
    connected NSX manager.
    
    At least one cluster is required to be a member of the Transport Zone at 
    creation time.

    #>

      
     param (

        [Parameter (Mandatory=$true, Position=1)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$Description,       
        [Parameter (Mandatory=$true)]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop[]]$Cluster,
        [Parameter (Mandatory=$true)]
            [ValidateSet("UNICAST_MODE","MULTICAST_MODE","HYBRID_MODE",IgnoreCase=$false)]
            [string]$ControlPlaneMode,
        [Parameter (Mandatory=$false)]
            [switch]$Universal=$false,       
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 


            
        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlScope = $XMLDoc.CreateElement("vdnScope")
        $xmlDoc.Appendchild($xmlScope) | out-null

        #Mandatory and default params 
        Add-XmlElement -xmlRoot $xmlScope -xmlElementName "name" -xmlElementText $Name.ToString()
        Add-XmlElement -xmlRoot $xmlScope -xmlElementName "controlPlaneMode" -xmlElementText $ControlPlaneMode.ToString()
        
        #Dont ask me, I just work here :|
        [System.XML.XMLElement]$xmlClusters = $XMLDoc.CreateElement("clusters")
        $xmlScope.Appendchild($xmlClusters) | out-null
        foreach ( $instance in $cluster ) { 
            [System.XML.XMLElement]$xmlCluster1 = $XMLDoc.CreateElement("cluster")
            $xmlClusters.Appendchild($xmlCluster1) | out-null
            [System.XML.XMLElement]$xmlCluster2 = $XMLDoc.CreateElement("cluster")
            $xmlCluster1.Appendchild($xmlCluster2) | out-null
            Add-XmlElement -xmlRoot $xmlCluster2 -xmlElementName "objectId" -xmlElementText $Instance.ExtensionData.Moref.Value
        }

        #Optional params
        if ( $PsBoundParameters.ContainsKey('Description')) { 
            Add-XmlElement -xmlRoot $xmlScope -xmlElementName "description" -xmlElementText $Description.ToString()
        }

        # #Do the post
        $body = $xmlScope.OuterXml
        $URI = "/api/2.0/vdn/scopes?isUniversal=$($Universal.ToString().ToLower())"
        Write-Progress -activity "Creating Transport Zone."
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection
        Write-progress -activity "Creating Transport Zone." -completed

        Get-NsxTransportZone -objectId $response -connection $connection

    }

    end {}
}

function Remove-NsxTransportZone {

    <#
    .SYNOPSIS
    Removes an NSX Transport Zone.

    .DESCRIPTION
    An NSX Transport Zone defines the maximum scope for logical switches that 
    are bound to it.  NSX Prepared clusters are added to Transport Zones which
    allows VMs on them to attach to any logical switch bound to the transport 
    zone.  

    The Remove-NsxTransportZone cmdlet removes an existing Transport Zone on the 
    connected NSX manager.
    
    If any logical switches are bound to the Transport Zone, the attempt to 
    remove the Transport Zone will fail.

    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-TransportZone $_ })]
            [System.Xml.XmlElement]$TransportZone,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Transport Zone removal is permanent."
            $question = "Proceed with removal of Transport Zone $($TransportZone.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/2.0/vdn/scopes/$($TransportZone.objectId)"
            Write-Progress -activity "Remove Transport Zone $($TransportZone.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
            Write-Progress -activity "Remove Transport Zone $($TransportZone.Name)" -completed

        }
    }

    end {}
}

#########
#########
# L2 related functions



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

        [Parameter (Mandatory=$false,ValueFromPipeline=$true,ParameterSetName="vdnscope")]
            [ValidateNotNullOrEmpty()]
            [alias("vdnScope")]
            [System.Xml.XmlElement]$TransportZone,
        [Parameter (Mandatory=$false,Position=1)]
            [string]$Name,
        [Parameter (Mandatory=$true,ParameterSetName="virtualWire")]
            [ValidateNotNullOrEmpty()]
            [alias("virtualWireId")]
            [string]$ObjectId,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {
    
        if ( $psCmdlet.ParameterSetName -eq "virtualWire" ) {

            #Just getting a single named Logical Switch
            $URI = "/api/2.0/vdn/virtualwires/$ObjectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            $response.virtualWire

        }
        else { 
            
            #Getting all LS in a given VDNScope
            $lspagesize = 10        
            if ( $PSBoundParameters.ContainsKey('vndScope')) { 
                $URI = "/api/2.0/vdn/scopes/$($TransportZone.objectId)/virtualwires?pagesize=$lspagesize&startindex=00"
            }
            else { 
                $URI = "/api/2.0/vdn/virtualwires?pagesize=$lspagesize&startindex=00"
            }
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection

            $logicalSwitches = @()

            #LS XML is returned as paged data, means we have to handle it.  
            #May refactor this later, depending on where else I find this in the NSX API (its not really documented in the API guide)
        
            $itemIndex =  0
            $startingIndex = 0 
            $pagingInfo = $response.virtualWires.dataPage.pagingInfo
        
            
            if ( [int]$paginginfo.totalCount -ne 0 ) {
                 write-debug "$($MyInvocation.MyCommand.Name) : Logical Switches count non zero"

                do {
                    write-debug "$($MyInvocation.MyCommand.Name) : In paging loop. PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"

                    while (($itemindex -lt ([int]$paginginfo.pagesize + $startingIndex)) -and ($itemIndex -lt [int]$paginginfo.totalCount )) {
            
                        write-debug "$($MyInvocation.MyCommand.Name) : In Item Processing Loop: ItemIndex: $itemIndex"
                        write-debug "$($MyInvocation.MyCommand.Name) : $(@($response.virtualwires.datapage.virtualwire)[($itemIndex - $startingIndex)].objectId)"
                    
                        #Need to wrap the virtualwire prop of the datapage in case we get exactly 1 item - 
                        #which powershell annoyingly unwraps to a single xml element rather than an array...
                        $logicalSwitches += @($response.virtualwires.datapage.virtualwire)[($itemIndex - $startingIndex)]
                        $itemIndex += 1 
                    }  
                    write-debug "$($MyInvocation.MyCommand.Name) : Out of item processing - PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                    if ( [int]$paginginfo.totalcount -gt $itemIndex) {
                        write-debug "$($MyInvocation.MyCommand.Name) : PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                        $startingIndex += $lspagesize
                        if ( $PSBoundParameters.ContainsKey('vndScope')) { 
                            $URI = "/api/2.0/vdn/scopes/$($TransportZone.objectId)/virtualwires?pagesize=$lspagesize&startindex=$startingIndex"
                        }
                        else {
                            $URI = "/api/2.0/vdn/virtualwires?pagesize=$lspagesize&startindex=$startingIndex"
                        }
                        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
                        $pagingInfo = $response.virtualWires.dataPage.pagingInfo
                    
    
                    } 
                } until ( [int]$paginginfo.totalcount -le $itemIndex )    
                write-debug "$($MyInvocation.MyCommand.Name) : Completed page processing: ItemIndex: $itemIndex"

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
            [alias("vdnScope")]
            [System.XML.XMLElement]$TransportZone,
        [Parameter (Mandatory=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$Description = "",
        [Parameter (Mandatory=$false)]
            [string]$TenantId = "",
        [Parameter (Mandatory=$false)]
            [ValidateSet("UNICAST_MODE","MULTICAST_MODE","HYBRID_MODE",IgnoreCase=$false)]
            [string]$ControlPlaneMode,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("virtualWireCreateSpec")
        $xmlDoc.appendChild($xmlRoot) | out-null


        #Create an Element and append it to the root
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "tenantId" -xmlElementText $TenantId
        if ( $ControlPlaneMode ) { Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "controlPlaneMode" -xmlElementText $ControlPlaneMode } 
           
        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/vdn/scopes/$($TransportZone.objectId)/virtualwires"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection

        #response only contains the vwire id, we have to query for it to get output consisten with get-nsxlogicalswitch
        Get-NsxLogicalSwitch -virtualWireId $response -connection $connection
    }
    end {}
}

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
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

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
            invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
            write-progress -activity "Remove Logical Switch $($virtualWire.Name)" -completed

        }
    }

    end {}
}

#########
#########
# Spoofguard related functions

function Get-NsxSpoofguardPolicy {
    
    <#
    .SYNOPSIS
    Retreives Spoofguard policy objects from NSX.

    .DESCRIPTION
    If a virtual machine has been compromised, its IP address can be spoofed 
    and malicious transmissions can bypass firewall policies. You create a 
    SpoofGuard policy for specific networks that allows you to authorize the IP
    addresses reported by VMware Tools and alter them if necessary to prevent 
    spoofing. SpoofGuard inherently trusts the MAC addresses of virtual machines
    collected from the VMX files and vSphere SDK. Operating separately from 
    Firewall rules, you can use SpoofGuard to block traffic determined to be
    spoofed.

    Use the Get-NsxSpoofguardPolicy cmdlet to retreive existing SpoofGuard 
    Policy objects from NSX.

    .EXAMPLE
    Get-NsxSpoofguardPolicy

    Get all Spoofguard policies

    .EXAMPLE
    Get-NsxSpoofguardPolicy Test

    Get a specific Spoofguard policy

    
    #>
    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$false, ParameterSetName="Name", Position=1)]
            [ValidateNotNullorEmpty()]
            [String]$Name,
        [Parameter (Mandatory=$false, ParameterSetName="ObjectId")]
            [ValidateNotNullorEmpty()]
            [string]$objectId,
        [Parameter (Mandatory=$false, ParameterSetName="ObjectId")]
        [Parameter (Mandatory=$false, ParameterSetName="Name")]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {}

    process {
     
        if ( $PsCmdlet.ParameterSetName -eq 'Name' ) { 
            #All SG Policies
            $URI = "/api/4.0/services/spoofguard/policies/"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response ) { 
                if ( $response.SelectSingleNode('descendant::spoofguardPolicies/spoofguardPolicy')) { 
                    if  ( $Name  ) { 
                        $polcollection = $response.spoofguardPolicies.spoofguardPolicy | ? { $_.name -eq $Name }
                    } else {
                        $polcollection = $response.spoofguardPolicies.spoofguardPolicy
                    }
                    foreach ($pol in $polcollection ) { 
                        #Note that when you use the objectid URI, the NSX API actually reutrns additional information (statistics element),
                        #so, without doing this, to the PowerNSX users, get-nsxsgpolicy <name> would return a subset of info compared to 
                        #get-nsxsgpolicy which I dont like.

                        $URI = "/api/4.0/services/spoofguard/policies/$($pol.policyId)"
                        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
                        if ( $response ) {
                            $response.spoofguardPolicy
                        } 
                        else {
                            throw "Unable to retreive SpoofGuard policy $($pol.policyId)."
                        }
                    }
                }
            }
        }
        else {

            #Just getting a single SG Policy

            $URI = "/api/4.0/services/spoofguard/policies/$objectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response ) {
                $response.spoofguardPolicy
            } 
        }
    }
    end {}
}

function New-NsxSpoofguardPolicy {

    <#
    .SYNOPSIS
    Creates a new Spoofguard policy in NSX.

    .DESCRIPTION
    If a virtual machine has been compromised, its IP address can be spoofed 
    and malicious transmissions can bypass firewall policies. You create a 
    SpoofGuard policy for specific networks that allows you to authorize the IP
    addresses reported by VMware Tools and alter them if necessary to prevent 
    spoofing. SpoofGuard inherently trusts the MAC addresses of virtual machines
    collected from the VMX files and vSphere SDK. Operating separately from 
    Firewall rules, you can use SpoofGuard to block traffic determined to be
    spoofed.

    Use the New-NsxSpoofguardPolicy cmdlet to create a new SpoofGuard 
    Policy in NSX.

    Policies are not published (enforced) automatically.  Use the -publish 
    switch to automatically publish a newly created policy.  Note that this 
    could impact VM communications depending on the policy settings.

    .EXAMPLE
    $ls = Get-NsxTransportZone | Get-NsxLogicalSwitch LSTemp
    New-NsxSpoofguardPolicy -Name Test -Description Testing -OperationMode tofu -Network $ls
    
    Create a new Trust on First Use Spoofguard policy protecting the Logical 
    Switch LSTemp

    .EXAMPLE
    $vss_pg = Get-VirtualPortGroup -Name "VM Network" | select -First 1
    $vds_pg = Get-VDPortgroup -Name "Internet"
    $ls = Get-NsxTransportZone | Get-NsxLogicalSwitch -Name LSTemp
    New-NsxSpoofguardPolicy -Name Test -Description Testing -OperationMode manual -Network $vss_pg, $vds_pg, $ls

    Create a new manual approval policy for three networks (a VSS PG, VDS PG and
    Logical switch)

    .EXAMPLE 
    $ls = Get-NsxTransportZone | Get-NsxLogicalSwitch LSTemp
    New-NsxSpoofguardPolicy -Name Test -Description Testing -OperationMode tofu -Network $ls -publish
    
    Create a new Trust on First Use Spoofguard policy protecting the Logical 
    Switch LSTemp and publish it immediately.  
    Publishing causes the policy to be enforced on the data plane immediately 
    (and potentially block all communication, so use with care!) 

    .EXAMPLE 
    $ls = Get-NsxTransportZone | Get-NsxLogicalSwitch LSTemp
    New-NsxSpoofguardPolicy -Name Test -Description Testing -OperationMode tofu -Network $ls -AllowLocalIps
    
    Create a new Trust on First Use Spoofguard policy protecting the Logical 
    Switch LSTemp and allow local IPs to be approved (169.254/16 and fe80::/64)


    #>


    [CmdletBinding()]
    param (

        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$Description,
        [Parameter (Mandatory=$true)]
            [ValidateSet("tofu","manual","disable")]
            [string]$OperationMode,
        [Parameter (Mandatory=$false)]
            [switch]$AllowLocalIps,
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-LogicalSwitchOrDistributedPortGroupOrStandardPortGroup $_ })]
            [object[]]$Network,
        [Parameter (Mandatory=$False)]
            [switch]$Publish=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("spoofguardPolicy")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "operationMode" -xmlElementText $OperationMode.ToUpper()
        if ( $PSBoundParameters.ContainsKey('description')) {
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        }
        if ( $PSBoundParameters.ContainsKey('AllowLocalIps')) {
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "allowLocalIPs" -xmlElementText $AllowLocalIps.ToString().ToLower()
        }

        foreach ( $Net in $Network) { 

            [System.XML.XMLElement]$xmlEnforcementPoint = $XMLDoc.CreateElement("enforcementPoint")
            $xmlroot.appendChild($xmlEnforcementPoint) | out-null

            switch ( $Net ) { 

                { $_ -is [System.Xml.XmlElement]  } {
                    
                    $id = $_.objectId
                }

                { $_ -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.DistributedPortGroupInterop] } {
                    
                    $id = $_.ExtensionData.MoRef.Value
                }

                { $_ -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.VirtualPortGroupInterop] } {
                    
                    #Standard Port Group specified... Hope you appreciate this, coz the vSphere API and PowerCLI niceness dissapear a bit here.
                    #and it took me a while to work out how to get around it.
                    #You dont seem to be able to get a standard Moref outa the PowerCLI network object that represents a VSS PG.
                    #You also dont seem to be able to do a get-view on it :|
                    #So, I have get a hasthtable of all morefs that represent VSS based PGs and search it for the name of the PG the user specified.  Im fairly (not 100%) sure this is safe as networkname should be unique at least within VSS portgroups...

                    $StandardPgHash = Get-View -ViewType Network -Property Name | ? { $_.Moref.Type -match 'Network' } | select name, moref | Sort-Object -Property Name -Unique | Group-Object -AsHashTable -Property Name

                    $Item = $StandardPgHash.Item($_.name)
                    if ( -not $item ) { throw "PortGroup $($_.name) not found." }

                    $id = $Item.MoRef.Value
                }
            }

            Add-XmlElement -xmlRoot $xmlEnforcementPoint -xmlElementName "id" -xmlElementText $id
        }
    
        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/4.0/services/spoofguard/policies/"
        $policyId = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
        
        #Now we Publish...
        if ( $publish ) { 
            $URI = "/api/4.0/services/spoofguard/$($policyId)?action=publish"
            $response = invoke-nsxwebrequest -method "post" -uri $URI -connection $connection
        }

        Get-NsxSpoofguardPolicy -objectId $policyId -connection $connection
        
    }
    end {}
   
}

function Remove-NsxSpoofguardPolicy {
    
    <#
    .SYNOPSIS
    Removes the specified Spoofguard policy object from NSX.

    .DESCRIPTION
    If a virtual machine has been compromised, its IP address can be spoofed 
    and malicious transmissions can bypass firewall policies. You create a 
    SpoofGuard policy for specific networks that allows you to authorize the IP
    addresses reported by VMware Tools and alter them if necessary to prevent 
    spoofing. SpoofGuard inherently trusts the MAC addresses of virtual machines
    collected from the VMX files and vSphere SDK. Operating separately from 
    Firewall rules, you can use SpoofGuard to block traffic determined to be
    spoofed.

    Use the Remnove-NsxSpoofguardPolicy cmdlet to remove the specified
    SpoofGuard Policy from NSX.

    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Remove-NsxSpoofguardPolicy

    Remove the policy Test.

    .EXAMPLE
    Get-NsxSpoofguardPolicy | Remove-NsxSpoofguardPolicy

    Remove all policies.

    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Remove-NsxSpoofguardPolicy -confirm:$false

    Remove the policy Test without confirmation.


    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$SpoofguardPolicy,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {}

    process {

        if ( $SpoofguardPolicy.defaultPolicy -eq 'true') {
            write-warning "Cant delete the default Spoofguard policy"
        }
        else { 
            if ( $confirm ) { 
                $message  = "Spoofguard Policy removal is permanent."
                $question = "Proceed with removal of Spoofguard Policy $($SpoofguardPolicy.Name)?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }
            else { $decision = 0 } 
            if ($decision -eq 0) {
                $URI = "/api/4.0/services/spoofguard/policies/$($SpoofguardPolicy.policyId)"
                
                Write-Progress -activity "Remove Spoofguard Policy $($SpoofguardPolicy.Name)"
                invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
                write-progress -activity "Remove Spoofguard Policy $($SpoofguardPolicy.Name)" -completed
            }
        }
    }

    end {}
}

function Publish-NsxSpoofguardPolicy {
    
    <#
    .SYNOPSIS
    Publishes the specified Spoofguard policy object.

    .DESCRIPTION
    If a virtual machine has been compromised, its IP address can be spoofed 
    and malicious transmissions can bypass firewall policies. You create a 
    SpoofGuard policy for specific networks that allows you to authorize the IP
    addresses reported by VMware Tools and alter them if necessary to prevent 
    spoofing. SpoofGuard inherently trusts the MAC addresses of virtual machines
    collected from the VMX files and vSphere SDK. Operating separately from 
    Firewall rules, you can use SpoofGuard to block traffic determined to be
    spoofed.

    Use the Publish-NsxSpoofguardPolicy cmdlet to publish the specified
    SpoofGuard Policy.  This causes it to be enforced.

    .EXAMPLE
    New-NsxSpoofguardPolicy -Name Test -Description Testing -OperationMode manual -Network $vss_pg, $vds_pg, $ls
    Get-NsxSpoofguardPolicy test | Publish-NsxSpoofguardPolicy

    Create and then separately publish a new policy.

    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Get-NsxSpoofguardNic -NetworkAdapter (Get-Vm TestVm | get-NetworkAdapter | select -first 1) | Grant-NsxSpoofguardNicApproval -IpAddress 1.2.3.4
    Get-NsxSpoofguardPolicy test | Publish-NsxSpoofguardPolicy

    Grant an approval to the first nic on the VM TestVM for ip 1.2.3.4 and publish it

    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$SpoofguardPolicy,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {}

    process {


        if ( $confirm ) { 
            $message  = "Spoofguard Policy publishing will cause the current policy to be enforced."
            $question = "Proceed with publish operation on Spoofguard Policy $($SpoofguardPolicy.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/4.0/services/spoofguard/$($SpoofguardPolicy.policyId)?action=publish"
            
            Write-Progress -activity "Publish Spoofguard Policy $($SpoofguardPolicy.Name)"
            invoke-nsxrestmethod -method "post" -uri $URI -connection $connection | out-null
            write-progress -activity "Publish Spoofguard Policy $($SpoofguardPolicy.Name)" -completed

            Get-NsxSpoofguardPolicy -objectId $($SpoofguardPolicy.policyId) -connection $connection
        }
    }

    end {}
}

function Get-NsxSpoofguardNic {
    
    <#
    .SYNOPSIS
    Retreives Spoofguard NIC details for the specified Spoofguard policy.

    .DESCRIPTION
    If a virtual machine has been compromised, its IP address can be spoofed 
    and malicious transmissions can bypass firewall policies. You create a 
    SpoofGuard policy for specific networks that allows you to authorize the IP
    addresses reported by VMware Tools and alter them if necessary to prevent 
    spoofing. SpoofGuard inherently trusts the MAC addresses of virtual machines
    collected from the VMX files and vSphere SDK. Operating separately from 
    Firewall rules, you can use SpoofGuard to block traffic determined to be
    spoofed.

    Use the Get-NsxSpoofguardNic cmdlet to retreive Spoofguard NIC details for 
    the specified Spoofguard policy


    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Get-NsxSpoofguardNic -NetworkAdapter (Get-vm evil-vm | Get-NetworkAdapter|  select -First 1)

    Get the Spoofguard settings for the first NIC on vM Evil-Vm

    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Get-NsxSpoofguardNic -VirtualMachine (Get-vm evil-vm)

    Get the Spoofguard settings for all nics on vM Evil-Vm

    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Get-NsxSpoofguardNic -MacAddress 00:50:56:81:04:28
    
    Get the Spoofguard settings for the MAC address 00:50:56:81:04:28

    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Get-NsxSpoofguardNic -Filter Inactive

    Get all Inactive spoofguard Nics

    

    #>
    [CmdLetBinding(DefaultParameterSetName="Default")]
 
    param (

        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName = "Default")]
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName = "MAC")]
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName = "VM")]
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName = "NIC")]
            [ValidateScript( { Validate-SpoofguardPolicy $_ } )]
            [System.xml.xmlElement]$SpoofguardPolicy,
        [Parameter (Mandatory=$false, ParameterSetName = "Default")]
        [Parameter (Mandatory=$false, ParameterSetName = "MAC")]
        [Parameter (Mandatory=$false, ParameterSetName = "VM")]
        [Parameter (Mandatory=$false, ParameterSetName = "NIC")]
            [Validateset("Active", "Inactive", "Published", "Unpublished", "Review_Pending", "Duplicate")]
            [string]$Filter,
        [Parameter (Mandatory=$false, ParameterSetName = "MAC")]
            [ValidateScript({
                if ( $_ -notmatch "[a-f,A-F,0-9]{2}:[a-f,A-F,0-9]{2}:[a-f,A-F,0-9]{2}:[a-f,A-F,0-9]{2}:[a-f,A-F,0-9]{2}:[a-f,A-F,0-9]{2}" ) {
                    throw "Specify a valid MAC address (0 must be specified as 00)"
                }
                $true
                })]
            [string]$MacAddress,
        [Parameter (Mandatory=$false, ParameterSetName = "VM")]
            #PowerCLI VirtualMachine object
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop]$VirtualMachine,
        [Parameter (Mandatory=$false, ParameterSetName = "NIC")]
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.VirtualDevice.NetworkAdapterInterop]$NetworkAdapter,            
        [Parameter (Mandatory=$false, ParameterSetName = "Default")]
        [Parameter (Mandatory=$false, ParameterSetName = "MAC")]
        [Parameter (Mandatory=$false, ParameterSetName = "VM")]
        [Parameter (Mandatory=$false, ParameterSetName = "NIC")]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {}

    process {

        if ( $PsBoundParameters.ContainsKey('Filter')) {
            $URI = "/api/4.0/services/spoofguard/$($SpoofguardPolicy.policyId)?list=$($Filter.ToUpper())" 
        }
        else {

            #Not documented in the API guide but appears to work ;)
            $URI = "/api/4.0/services/spoofguard/$($SpoofguardPolicy.policyId)?list=ALL"
        }

        [system.xml.xmldocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
 
        if ( $response.SelectsingleNode('descendant::spoofguardList/spoofguard')) {
        
            switch ( $PsCmdlet.ParameterSetName  ) { 

                "MAC" { $outcollection = $response.spoofguardList.Spoofguard | ? { $_.detectedMacAddress -eq $MacAddress } }
                "NIC" { 
                    $MacAddress = $NetworkAdapter.MacAddress
                    $outcollection = $response.spoofguardList.Spoofguard | ? { $_.detectedMacAddress -eq $MacAddress } 
                }

                "VM" { 
                    foreach ( $Nic in ($virtualmachine | Get-NetworkAdapter )) { 
                        $MacAddress = $Nic.MacAddress
                        $outcollection = $response.spoofguardList.Spoofguard | ? { $_.detectedMacAddress -eq $MacAddress }
                    }
                }
                default { $outcollection = $response.spoofguardList.Spoofguard }
            }

            #Add the policyId to the XML so we can pipline to grant/revoke cmdlets.
            foreach ( $out in $outcollection ) {

                Add-XmlElement -xmlRoot $out -xmlElementName "policyId" -xmlElementText $($SpoofguardPolicy.policyId)
            }
            $outcollection
        }
        else { 
            write-debug "$($MyInvocation.MyCommand.Name) : No results found."
        }
    }
    end {}
}

function Grant-NsxSpoofguardNicApproval { 

    <#
    .SYNOPSIS
    Approves a new IP for the specified Spoofguard NIC.

    .DESCRIPTION
    If a virtual machine has been compromised, its IP address can be spoofed 
    and malicious transmissions can bypass firewall policies. You create a 
    SpoofGuard policy for specific networks that allows you to authorize the IP
    addresses reported by VMware Tools and alter them if necessary to prevent 
    spoofing. SpoofGuard inherently trusts the MAC addresses of virtual machines
    collected from the VMX files and vSphere SDK. Operating separately from 
    Firewall rules, you can use SpoofGuard to block traffic determined to be
    spoofed.

    Use the Grant-NsxSpoofguardNicApproval cmdlet to add the specified IP
    to the list of approved IPs for the specified Spoofguard NIC.

    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Get-NsxSpoofguardNic -NetworkAdapter (Get-vm evil-vm | Get-NetworkAdapter|  select -First 1) | Grant-NsxSpoofguardNicApproval -IpAddress 1.2.3.4 -Publish
    
    Grant approval for the first NIC on VM Evil-VM to use the IP 1.2.3.4 and 
    publish immediately

    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Get-NsxSpoofguardNic -NetworkAdapter (Get-vm evil-vm | Get-NetworkAdapter|  select -First 1) | Grant-NsxSpoofguardNicApproval --ApproveAllDetectedIps -Publish
    
    Grant approval for the first NIC on VM Evil-VM to use all IPs detected by 
    whatever IP detction methods are available and publish immediately.
    
    Note:  This *may* include 'local' IPs (such as fe80::/64) which may not be 
    allowed if the policy is not enabled with 'AllowLocalIps'.  In this case
    this operation will throw a cryptic error (Valid values are {2}) and not 
    succeed.  In this case you must either change the policy to allow local IPs,
    or manually approve the specific IPs you want.  This issue affects the NSX 
    UI as well.

    
    #>

    [CmdLetBinding(DefaultParameterSetName="ipAddress")]

    param (

        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
            [ValidateScript( { Validate-SpoofguardNic $_ } )]
            [System.xml.xmlElement]$SpoofguardNic,
        [Parameter (Mandatory=$True, ParameterSetName="ipAddress")]
            [ValidateNotNullOrEmpty()]
            [string[]]$IpAddress,
        [Parameter (Mandatory=$True, ParameterSetName="ApproveAll")]
            [ValidateNotNullOrEmpty()]
            [switch]$ApproveAllDetectedIps=$False,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$Publish=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #We need to modify the spoofguardNic XML element, so we need to clone it.
        $_SpoofguardNic = $SpoofguardNic.CloneNode($true)

        [System.XML.XMLDocument]$xmlDoc = $_SpoofguardNic.OwnerDocument
        [System.XML.XMLElement]$spoofguardList = $XMLDoc.CreateElement("spoofguardList")
        $spoofguardList.appendChild($_SpoofguardNic) | out-null

        #Get and Remove the policyId element we put there...
        $policyId = $_SpoofguardNic.policyId
        $_SpoofguardNic.RemoveChild($_SpoofguardNic.SelectSingleNode('descendant::policyId')) | out-null

        #if approvedIpAddress element does not exist, create it
        [system.xml.xmlElement]$approvedIpAddressNode = $_SpoofguardNic.SelectsingleNode('descendant::approvedIpAddress')
        if ( -not $approvedIpAddressNode ) { 

            [System.XML.XMLElement]$approvedIpAddressNode = $XMLDoc.CreateElement("approvedIpAddress")
            $_SpoofguardNic.appendChild($approvedIpAddressNode) | out-null
        }

        #If they are, Add the ip(s) specified
        if ( $PsBoundParameters.ContainsKey('ipAddress') ) {
            foreach ( $ip in $ipAddress ) { 

                if ( $approvedIpAddressNode.selectNodes("descendant::ipAddress") | ? { $_.'#Text' -eq $ip }) {                            
                    write-warning "Not adding duplicate IP Address $ip as it is already added."
                }
                else { 
                    Add-XmlElement -xmlRoot $approvedIpAddressNode -xmlElementName "ipAddress" -xmlElementText $ip
                }
            }
        }

        #If there are IPs detected, and approve all is on, ensure user understands consequence.
        If ( $ApproveAllDetectedIps -and ( $_SpoofguardNic.SelectSingleNode('descendant::detectedIpAddress/ipAddress'))) { 

            If ($confirm ) { 

                $message  = "Do you want to automatically approve all IP Addresses detected on the NIC $($_SpoofguardNic.nicName)?."
                $question = "Validate the detected IP addresses before continuing.  Proceed?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }
            else { $decision = 0 } 
            if ($decision -eq 0) {

                foreach ( $ip in $_SpoofguardNic.detectedIpAddress.ipAddress )  {
                    #Have to ensure we dont add a duplicate here...
                    
                    if ( $approvedIpAddressNode.selectNodes("descendant::ipAddress") | ? { $_.'#Text' -eq $ip }) {                            
                        write-warning "Not adding duplicate IP Address $ip as it is already added."
                    }
                    else { 
                        Add-XmlElement -xmlRoot $approvedIpAddressNode -xmlElementName "ipAddress" -xmlElementText $ip
                    }
                }
            }
        }

        # Had bad thoughts about allowing manual specification of MAC.  I might come back to this...

        # if ( $PsCmdlet.ParameterSetName -eq "ManualMac" ) { 
        #     if ( -not ( $_SpoofguardNic.SelectsingleNode('descendant::approvedMacAddress'))){
        #         Add-XmlElement -xmlRoot $_SpoofguardNic -xmlElementName "approvedMacAddress" -xmlElementText $MacAddress
        #     }
        #     else { 

        #         #Assume user wants to overwrite... should we confirm on this?
        #         $_SpoofguardNic.approvedMacAddress = $MacAddress

        #     }

        # }
        # else { 
        #     if ( -not ( $_SpoofguardNic.SelectsingleNode('descendant::approvedMacAddress'))){
        #        Add-XmlElement -xmlRoot $_SpoofguardNic -xmlElementName "approvedMacAddress" -xmlElementText $_SpoofguardNic.detectedMacAddress
        #     }
        #     else { 

        #         #Assume user wants to overwrite... should we confirm on this?
        #         $_SpoofguardNic.approvedMacAddress = $MacAddress
        #     }
        # }

        #Do the post
        $body = $spoofguardList.OuterXml
        $URI = "/api/4.0/services/spoofguard/$($policyId)?action=approve"
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection

        #Now we Publish...
        if ( $publish ) { 
            $URI = "/api/4.0/services/spoofguard/$($policyId)?action=publish"
            $response = invoke-nsxwebrequest -method "post" -uri $URI -connection $connection
        }
        
        Get-NsxSpoofguardPolicy -objectId $policyId -connection $connection | Get-NsxSpoofguardNic -MAC $_SpoofguardNic.detectedMacAddress -connection $connection
        
    }
    end {}
}

function Revoke-NsxSpoofguardNicApproval { 

    <#
    .SYNOPSIS
    Removes an approved IP from the specified Spoofguard NIC.

    .DESCRIPTION
    If a virtual machine has been compromised, its IP address can be spoofed 
    and malicious transmissions can bypass firewall policies. You create a 
    SpoofGuard policy for specific networks that allows you to authorize the IP
    addresses reported by VMware Tools and alter them if necessary to prevent 
    spoofing. SpoofGuard inherently trusts the MAC addresses of virtual machines
    collected from the VMX files and vSphere SDK. Operating separately from 
    Firewall rules, you can use SpoofGuard to block traffic determined to be
    spoofed.

    Use the Revoke-NsxSpoofguardNicApproval cmdlet to remove the specified IP
    from the list of approved IPs for the specified Spoofguard NIC.

    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Get-NsxSpoofguardNic -NetworkAdapter (Get-vm evil-vm | Get-NetworkAdapter|  select -First 1) | Revoke-NsxSpoofguardNicApproval -RevokeAllApprovedIps -publish
    
    Revoke all approved IPs for vm evil-vm and immediately publish the policy.
    
    .EXAMPLE
    Get-NsxSpoofguardPolicy test | Get-NsxSpoofguardNic -NetworkAdapter (Get-vm evil-vm | Get-NetworkAdapter|  select -First 1) | Revoke-NsxSpoofguardNicApproval -IpAddress 1.2.3.4

    Revoke the approval for IP 1.2.3.4 from the first nic on vm evil-vm.


    #>
    [CmdLetBinding(DefaultParameterSetName="IpList")]

    param (

        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
            [ValidateScript( { Validate-SpoofguardNic $_ } )]
            [System.xml.xmlElement]$SpoofguardNic,
        [Parameter (Mandatory=$True, ParameterSetName="IpList")]
            [ValidateNotNullOrEmpty()]
            [string[]]$IpAddress,
        [Parameter (Mandatory=$True, ParameterSetName="RevokeAll")]
            [ValidateNotNullOrEmpty()]
            [switch]$RevokeAllApprovedIps,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$False)]
            [switch]$Publish=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #We need to modify the spoofguardNic XML element, so we need to clone it.
        $_SpoofguardNic = $SpoofguardNic.CloneNode($true)

        [System.XML.XMLDocument]$xmlDoc = $_SpoofguardNic.OwnerDocument
        [System.XML.XMLElement]$spoofguardList = $XMLDoc.CreateElement("spoofguardList")
        $spoofguardList.appendChild($_SpoofguardNic) | out-null

        #Get and Remove the policyId element we put there...
        $policyId = $_SpoofguardNic.policyId
        $_SpoofguardNic.RemoveChild($_SpoofguardNic.SelectSingleNode('descendant::policyId')) | out-null

        #if approvedIpAddress element does not exist, bail
        [system.xml.xmlElement]$approvedIpAddressNode = $_SpoofguardNic.SelectsingleNode('descendant::approvedIpAddress')
        if ( -not $approvedIpAddressNode -or (-not ($approvedIpAddressNode.SelectSingleNode('descendant::ipAddress')))) { 

            Write-Warning "Nic $($_SpoofguardNic.NicName) has no approved IPs"
        }
        else {
        
            [system.xml.xmlElement]$publishedIpAddressNode = $_SpoofguardNic.SelectsingleNode('descendant::publishedIpAddress')

            $approvedIpCollection = $approvedIpAddressNode.selectNodes("descendant::ipAddress")
            $publishedIpCollection = $publishedIpAddressNode.selectNodes("descendant::ipAddress")

            #If there are IPs detected, and revoke all is on, kill em all...
            If ( $PSCmdlet.ParameterSetName -eq "RevokeAll" ) {
                
                foreach ( $node in $approvedIpCollection ) { 
                    $approvedIpAddressNode.RemoveChild($node) | out-null
                }                
            } 

            else {
                #$IPAddress is mandatory...
                foreach ( $ip in $ipAddress ) { 

                    $currentApprovedIpNode = $approvedIpCollection | ? { $_.'#Text' -eq $ip }
                    $currentPublishedIpNode = $publishedIpCollection | ? { $_.'#Text' -eq $ip }

                    if ( -not $currentApprovedIpNode ) {                            
                        write-warning "IP Address $ip is not currently approved on Nic $($_SpoofguardNic.NicName)."
                    }
                    else { 
                        $approvedIpAddressNode.RemoveChild($currentApprovedIpNode) | out-null
                        if ( $currentPublishedIpNode ) { 

                            $publishedIpAddressNode.RemoveChild($currentPublishedIpNode) | out-null
                        }
                    }
                }
            }

            If ($confirm ) { 

                $message  = "Do you want to remove the specified IP Addresses from the approved list of the NIC $($_SpoofguardNic.nicName)?."
                $question = "Removal is permenant.  Proceed?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }
            else { $decision = 0 } 
            if ($decision -eq 0) {

                #Do the post
                $body = $spoofguardList.OuterXml
                $URI = "/api/4.0/services/spoofguard/$($policyId)?action=approve"
                $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection

                #Now we Publish...
                if ( $publish) { 
                    $URI = "/api/4.0/services/spoofguard/$($policyId)?action=publish"
                    $response = invoke-nsxwebrequest -method "post" -uri $URI -connection $connection
                }

                Get-NsxSpoofguardPolicy -objectId $policyId -connection $connection | Get-NsxSpoofguardNic -MAC $_SpoofguardNic.detectedMacAddress -connection $connection
            }
        }
    }
    end {}
}


#########
######### 
# Distributed Router functions


function New-NsxLogicalRouterInterfaceSpec {

    <#
    .SYNOPSIS
    Creates a new NSX Logical Router Interface Spec.

    .DESCRIPTION
    NSX Logical Routers can host up to 1000 interfaces, each of which can be 
    configured with multiple properties.  In order to allow creation of Logical 
    Routers with an arbitrary number of interfaces, a unique spec for each interface 
    required must first be created.

    Logical Routers do support interfaces on VLAN backed portgroups, and this 
    cmdlet will support a interface spec connected to a normal portgroup, however 
    this is not noramlly a recommended scenario.
    
    .EXAMPLE

    PS C:\> $Uplink = New-NsxLogicalRouterinterfaceSpec -Name Uplink_interface -Type 
        uplink -ConnectedTo (Get-NsxTransportZone | Get-NsxLogicalSwitch LS1) 
        -PrimaryAddress 192.168.0.1 -SubnetPrefixLength 24

    PS C:\> $Internal = New-NsxLogicalRouterinterfaceSpec -Name Internal-interface -Type 
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
        [Parameter (Mandatory=$false)]
            [ValidateScript({Validate-LogicalSwitchOrDistributedPortGroup $_ })]
            [object]$ConnectedTo,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,9128)]
            [int]$MTU=1500,       
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Connected=$true,
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,1000)]
            [int]$Index 
    )

    begin {

        if ( $Connected -and ( -not $connectedTo ) ) { 
            #Not allowed to be connected without a connected port group.
            throw "Interfaces that are connected must be connected to a distributed Portgroup or Logical Switch."
        }

        if (( $PsBoundParameters.ContainsKey("PrimaryAddress") -and ( -not $PsBoundParameters.ContainsKey("SubnetPrefixLength"))) -or 
            (( -not $PsBoundParameters.ContainsKey("PrimaryAddress")) -and  $PsBoundParameters.ContainsKey("SubnetPrefixLength"))) {

            #Not allowed to have subnet without primary or vice versa.
            throw "Interfaces with a Primary address must also specify a prefix length and vice versa."   
        }
    }

    process { 

        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlVnic = $XMLDoc.CreateElement("interface")
        $xmlDoc.appendChild($xmlVnic) | out-null

        if ( $PsBoundParameters.ContainsKey("Name")) { Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "name" -xmlElementText $Name }
        if ( $PsBoundParameters.ContainsKey("Type")) { Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "type" -xmlElementText $type }
        if ( $PsBoundParameters.ContainsKey("Index")) { Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "index" -xmlElementText $Index }
        Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "mtu" -xmlElementText $MTU 
        Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "isConnected" -xmlElementText $Connected

        switch ($ConnectedTo){
            { $_ -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.DistributedPortGroupInterop] }  { $PortGroupID = $_.ExtensionData.MoRef.Value }
            { $_ -is [System.Xml.XmlElement]} { $PortGroupID = $_.objectId }
        }  

        if ( $PsBoundParameters.ContainsKey("ConnectedTo")) { Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "connectedToId" -xmlElementText $PortGroupID }

        if ( $PsBoundParameters.ContainsKey("PrimaryAddress")) {

            #For now, only supporting one addressgroup - will refactor later
            [System.XML.XMLElement]$xmlAddressGroups = $XMLDoc.CreateElement("addressGroups")
            $xmlVnic.appendChild($xmlAddressGroups) | out-null
            $AddressGroupParameters = @{
                xmlAddressGroups = $xmlAddressGroups
            }

            if ( $PsBoundParameters.ContainsKey("PrimaryAddress" )) { $AddressGroupParameters.Add("PrimaryAddress",$PrimaryAddress) }
            if ( $PsBoundParameters.ContainsKey("SubnetPrefixLength" )) { $AddressGroupParameters.Add("SubnetPrefixLength",$SubnetPrefixLength) }
             
            PrivateAdd-NsxEdgeVnicAddressGroup @AddressGroupParameters
        
        }
        $xmlVnic
    }
    end {}
}

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
            [string]$Name,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $pagesize = 10         
    switch ( $psCmdlet.ParameterSetName ) {

        "Name" { 
            $URI = "/api/4.0/edges?pageSize=$pagesize&startIndex=00" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            
            #Edge summary XML is returned as paged data, means we have to handle it.  
            #Then we have to query for full information on a per edge basis.
            $edgesummaries = @()
            $edges = @()
            $itemIndex =  0
            $startingIndex = 0 
            $pagingInfo = $response.pagedEdgeList.edgePage.pagingInfo
            
            if ( [int]$paginginfo.totalCount -ne 0 ) {
                 write-debug "$($MyInvocation.MyCommand.Name) : Logical Router count non zero"

                do {
                    write-debug "$($MyInvocation.MyCommand.Name) : In paging loop. PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"

                    while (($itemindex -lt ([int]$paginginfo.pagesize + $startingIndex)) -and ($itemIndex -lt [int]$paginginfo.totalCount )) {
            
                        write-debug "$($MyInvocation.MyCommand.Name) : In Item Processing Loop: ItemIndex: $itemIndex"
                        write-debug "$($MyInvocation.MyCommand.Name) : $(@($response.pagedEdgeList.edgePage.edgeSummary)[($itemIndex - $startingIndex)].objectId)"
                    
                        #Need to wrap the edgesummary prop of the datapage in case we get exactly 1 item - 
                        #which powershell annoyingly unwraps to a single xml element rather than an array...
                        $edgesummaries += @($response.pagedEdgeList.edgePage.edgeSummary)[($itemIndex - $startingIndex)]
                        $itemIndex += 1 
                    }  
                    write-debug "$($MyInvocation.MyCommand.Name) : Out of item processing - PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                    if ( [int]$paginginfo.totalcount -gt $itemIndex) {
                        write-debug "$($MyInvocation.MyCommand.Name) : PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                        $startingIndex += $pagesize
                        $URI = "/api/4.0/edges?pageSize=$pagesize&startIndex=$startingIndex"
                
                        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
                        $pagingInfo = $response.pagedEdgeList.edgePage.pagingInfo
                    

                    } 
                } until ( [int]$paginginfo.totalcount -le $itemIndex )    
                write-debug "$($MyInvocation.MyCommand.Name) : Completed page processing: ItemIndex: $itemIndex"
            }

            #What we got here is...failure to communicate!  In order to get full detail, we have to requery for each edgeid.
            #But... there is information in the SUmmary that isnt in the full detail.  So Ive decided to add the summary as a node 
            #to the returned edge detail. 

            foreach ($edgesummary in $edgesummaries) {

                $URI = "/api/4.0/edges/$($edgesummary.objectID)" 
                $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
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
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            $edge = $response.edge
            $URI = "/api/4.0/edges/$objectId/summary" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            $import = $edge.ownerDocument.ImportNode($($response.edgeSummary), $true)
            $edge.AppendChild($import) | out-null
            $edge

        }
    }
}

function New-NsxLogicalRouter {

    <#
    .SYNOPSIS
    Creates a new Logical Router object.
    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    This cmdlet creates a new Logical Router.  A Logical router has many 
    configuration options - not all are exposed with New-NsxLogicalRouter.  
    Use Set-NsxLogicalRouter for other configuration.

    Interface configuration is handled by passing interface spec objects created by 
    the New-NsxLogicalRouterInterfaceSpec cmdlet.

    A valid PowerCLI session is required to pass required objects as required by 
    cluster/resourcepool and datastore parameters.
    
    .EXAMPLE
    
    Create a new LR with interfaces on existsing Logical switches (LS1,2,3 and 
    Management interface on Mgmt)

    PS C:\> $ls1 = get-nsxtransportzone | get-nsxlogicalswitch LS1

    PS C:\> $ls2 = get-nsxtransportzone | get-nsxlogicalswitch LS2

    PS C:\> $ls3 = get-nsxtransportzone | get-nsxlogicalswitch LS3

    PS C:\> $mgt = get-nsxtransportzone | get-nsxlogicalswitch Mgmt

    PS C:\> $vnic0 = New-NsxLogicalRouterInterfaceSpec -Type uplink -Name vNic0 
        -ConnectedTo $ls1 -PrimaryAddress 1.1.1.1 -SubnetPrefixLength 24

    PS C:\> $vnic1 = New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic1 
        -ConnectedTo $ls2 -PrimaryAddress 2.2.2.1 -SubnetPrefixLength 24

    PS C:\> $vnic2 = New-NsxLogicalRouterInterfaceSpec -Type internal -Name vNic2 
        -ConnectedTo $ls3 -PrimaryAddress 3.3.3.1 -SubnetPrefixLength 24

    PS C:\> New-NsxLogicalRouter -Name testlr -ManagementPortGroup $mgt 
        -Interface $vnic0,$vnic1,$vnic2 -Cluster (Get-Cluster) 
        -Datastore (get-datastore)

    #>

    param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-LogicalSwitchOrDistributedPortGroup $_ })]
            [object]$ManagementPortGroup,
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-LogicalRouterInterfaceSpec $_ })]
            [System.Xml.XmlElement[]]$Interface,       
        [Parameter (Mandatory=$true,ParameterSetName="ResourcePool")]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ResourcePoolInterop]$ResourcePool,
        [Parameter (Mandatory=$true,ParameterSetName="Cluster")]
            [ValidateScript({
                if ( $_ -eq $null ) { throw "Must specify Cluster."}
                if ( -not $_.DrsEnabled ) { throw "Cluster is not DRS enabled."}
                $true
            })]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop]$Cluster,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.DatastoreManagement.DatastoreInterop]$Datastore,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableHA=$false,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.DatastoreManagement.DatastoreInterop]$HADatastore=$datastore,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )


    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("edge")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "type" -xmlElementText "distributedRouter"

        switch ($ManagementPortGroup){

            { $_ -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.DistributedPortGroupInterop] }  { $PortGroupID = $_.ExtensionData.MoRef.Value }
            { $_ -is [System.Xml.XmlElement]} { $PortGroupID = $_.objectId }

        }

        [System.XML.XMLElement]$xmlMgmtIf = $XMLDoc.CreateElement("mgmtInterface")
        $xmlRoot.appendChild($xmlMgmtIf) | out-null
        Add-XmlElement -xmlRoot $xmlMgmtIf -xmlElementName "connectedToId" -xmlElementText $PortGroupID

        [System.XML.XMLElement]$xmlAppliances = $XMLDoc.CreateElement("appliances")
        $xmlRoot.appendChild($xmlAppliances) | out-null
        
        switch ($psCmdlet.ParameterSetName){

            "Cluster"  { $ResPoolId = $($cluster | get-resourcepool | ? { $_.parent.id -eq $cluster.id }).extensiondata.moref.value }
            "ResourcePool"  { $ResPoolId = $ResourcePool.extensiondata.moref.value }

        }

        [System.XML.XMLElement]$xmlAppliance = $XMLDoc.CreateElement("appliance")
        $xmlAppliances.appendChild($xmlAppliance) | out-null
        Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "resourcePoolId" -xmlElementText $ResPoolId
        Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "datastoreId" -xmlElementText $datastore.extensiondata.moref.value

        if ( $EnableHA ) {
            [System.XML.XMLElement]$xmlAppliance = $XMLDoc.CreateElement("appliance")
            $xmlAppliances.appendChild($xmlAppliance) | out-null
            Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "resourcePoolId" -xmlElementText $ResPoolId
            Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "datastoreId" -xmlElementText $HAdatastore.extensiondata.moref.value
               
        }

        [System.XML.XMLElement]$xmlVnics = $XMLDoc.CreateElement("interfaces")
        $xmlRoot.appendChild($xmlVnics) | out-null
        foreach ( $VnicSpec in $Interface ) {

            $import = $xmlDoc.ImportNode(($VnicSpec), $true)
            $xmlVnics.AppendChild($import) | out-null

        }

        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/4.0/edges"

        Write-Progress -activity "Creating Logical Router $Name"    
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
        Write-Progress -activity "Creating Logical Router $Name"  -completed
        $edgeId = $response.Headers.Location.split("/")[$response.Headers.Location.split("/").GetUpperBound(0)] 

        if ( $EnableHA ) {
            
            [System.XML.XMLElement]$xmlHA = $XMLDoc.CreateElement("highAvailability")
            Add-XmlElement -xmlRoot $xmlHA -xmlElementName "enabled" -xmlElementText "true"
            $body = $xmlHA.OuterXml
            $URI = "/api/4.0/edges/$edgeId/highavailability/config"
            Write-Progress -activity "Enable HA on Logical Router $Name"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Enable HA on Logical Router $Name" -completed

        }
        Get-NsxLogicalRouter -objectID $edgeId -connection $connection

    }
    end {}
}

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
            [ValidateScript({ Validate-LogicalRouter $_ })]
            [System.Xml.XmlElement]$LogicalRouter,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

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
            invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
            write-progress -activity "Remove Logical Router $($LogicalRouter.Name)" -completed

        }
    }

    end {}
}

function Set-NsxLogicalRouterInterface {

    <#
    .SYNOPSIS
    Configures an existing NSX LogicalRouter interface.

    .DESCRIPTION
    NSX Logical Routers can host up to 8 uplink and 1000 internal interfaces, each of which 
    can be configured with multiple properties.  

    Logical Routers support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches, although connection to VLAN backed PortGroups is not a recommended 
    configuration.

    Use Set-NsxLogicalRouterInterface to overwrite the configuration of an existing
    interface.

    #>

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterInterface $_ })]
            [System.Xml.XmlElement]$Interface,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateSet ("internal","uplink")]
            [string]$Type,
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-LogicalSwitchOrDistributedPortGroup $_ })]
            [object]$ConnectedTo,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,9128)]
            [int]$MTU=1500,       
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Connected=$true,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Check if there is already configuration 
        if ( $confirm ) { 

            $message  = "Interface configuration will be overwritten."
            $question = "Proceed with reconfiguration for $($Interface.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            if ( $decision -eq 1 ) {
                return
            }
        }

        #generate the vnic XML 
        $vNicSpecParams = @{ 
            Index = $Interface.index 
            Name = $name 
            Type = $type 
            ConnectedTo = $connectedTo                      
            MTU = $MTU 
            Connected = $connected
        }
        if ( $PsBoundParameters.ContainsKey("PrimaryAddress" )) { $vNicSpecParams.Add("PrimaryAddress",$PrimaryAddress) }
        if ( $PsBoundParameters.ContainsKey("SubnetPrefixLength" )) { $vNicSpecParams.Add("SubnetPrefixLength",$SubnetPrefixLength) }
        if ( $PsBoundParameters.ContainsKey("SecondaryAddresses" )) { $vNicSpecParams.Add("SecondaryAddresses",$SecondaryAddresses) }

        $VnicSpec = New-NsxLogicalRouterInterfaceSpec @vNicSpecParams
        write-debug "$($MyInvocation.MyCommand.Name) : vNic Spec is $($VnicSpec.outerxml | format-xml) "

        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlVnics = $XMLDoc.CreateElement("interfaces")
        $import = $xmlDoc.ImportNode(($VnicSpec), $true)
        $xmlVnics.AppendChild($import) | out-null

        # #Do the post
        $body = $xmlVnics.OuterXml
        $URI = "/api/4.0/edges/$($Interface.logicalRouterId)/interfaces/?action=patch"
        Write-Progress -activity "Updating Logical Router interface configuration for interface $($Interface.Index)."
        invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection
        Write-progress -activity "Updating Logical Router interface configuration for interface $($Interface.Index)." -completed

    }

    end {}
}

function New-NsxLogicalRouterInterface {

    <#
    .SYNOPSIS
    Configures an new NSX LogicalRouter interface.

    .DESCRIPTION
    NSX Logical Routers can host up to 8 uplink and 1000 internal interfaces, each of which 
    can be configured with multiple properties.  

    Logical Routers support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches, although connection to VLAN backed PortGroups is not a recommended 
    configuration.

    Use New-NsxLogicalRouterInterface to create a new Logical Router interface.

    #>

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouter $_ })]
            [System.Xml.XmlElement]$LogicalRouter,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateSet ("internal","uplink")]
            [string]$Type,
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-LogicalSwitchOrDistributedPortGroup $_ })]
            [object]$ConnectedTo,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,9128)]
            [int]$MTU=1500,       
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Connected=$true,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection 
    )

    begin {}
    process { 

        #generate the vnic XML 
        $vNicSpecParams = @{ 
            Name = $name 
            Type = $type 
            ConnectedTo = $connectedTo                      
            MTU = $MTU 
            Connected = $connected
        }
        if ( $PsBoundParameters.ContainsKey("PrimaryAddress" )) { $vNicSpecParams.Add("PrimaryAddress",$PrimaryAddress) }
        if ( $PsBoundParameters.ContainsKey("SubnetPrefixLength" )) { $vNicSpecParams.Add("SubnetPrefixLength",$SubnetPrefixLength) }
        if ( $PsBoundParameters.ContainsKey("SecondaryAddresses" )) { $vNicSpecParams.Add("SecondaryAddresses",$SecondaryAddresses) }

        $VnicSpec = New-NsxLogicalRouterInterfaceSpec @vNicSpecParams
        write-debug "$($MyInvocation.MyCommand.Name) : vNic Spec is $($VnicSpec.outerxml | format-xml) "

        #Construct the XML
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlVnics = $XMLDoc.CreateElement("interfaces")
        $import = $xmlDoc.ImportNode(($VnicSpec), $true)
        $xmlVnics.AppendChild($import) | out-null

        # #Do the post
        $body = $xmlVnics.OuterXml
        $URI = "/api/4.0/edges/$($LogicalRouter.Id)/interfaces/?action=patch"
        Write-Progress -activity "Creating Logical Router interface."
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection
        Write-progress -activity "Creating Logical Router interface." -completed
        $response.interfaces
    }

    end {}
}
function Remove-NsxLogicalRouterInterface {

    <#
    .SYNOPSIS
    Deletes an NSX Logical router interface.

    .DESCRIPTION
    NSX Logical Routers can host up to 8 uplink and 1000 internal interfaces, each of which 
    can be configured with multiple properties.  

    Logical Routers support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches, although connection to VLAN backed PortGroups is not a recommended 
    configuration.

    Use Remove-NsxLogicalRouterInterface to remove an existing Logical Router Interface.
    
    #>

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterInterface $_ })]
            [System.Xml.XmlElement]$Interface,       
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection   
    )

    begin {
    }

    process { 

        if ( $confirm ) { 

            $message  = "Interface ($Interface.Name) will be deleted."
            $question = "Proceed with deletion of interface $($Interface.index)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            if ( $decision -eq 1 ) {
                return
            }
        }
        

        # #Do the delete
        $URI = "/api/4.0/edges/$($Interface.logicalRouterId)/interfaces/$($Interface.Index)"
        Write-Progress -activity "Deleting interface $($Interface.Index) on logical router $($Interface.logicalRouterId)."
        invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection
        Write-progress -activity "Deleting interface $($Interface.Index) on logical router $($Interface.logicalRouterId)." -completed

    }

    end {}
}

function Get-NsxLogicalRouterInterface {

    <#
    .SYNOPSIS
    Retrieves the specified interface configuration on a specified Logical Router.

    .DESCRIPTION
    NSX Logical Routers can host up to 8 uplink and 1000 internal interfaces, each of which 
    can be configured with multiple properties.  

    Logical Routers support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches, although connection to VLAN backed PortGroups is not a recommended 
    configuration.

    Use Get-NsxLogicalRouterInterface to retrieve the configuration of a interface.

    .EXAMPLE
    Get all Interfaces on a Logical Router.

    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouter $_ })]
            [System.Xml.XmlElement]$LogicalRouter,
        [Parameter (Mandatory=$False,ParameterSetName="Name",Position=1)]
            [string]$Name,
        [Parameter (Mandatory=$True,ParameterSetName="Index")]
            [ValidateRange(1,1000)]
            [int]$Index,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {}

    process {     

        if ( -not ($PsBoundParameters.ContainsKey("Index") )) { 
            #All Interfaces on LR
            $URI = "/api/4.0/edges/$($LogicalRouter.Id)/interfaces/"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $PsBoundParameters.ContainsKey("name") ) {
                $return = $response.interfaces.interface | ? { $_.name -eq $name }
                if ( $return ) { 
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$return.OwnerDocument) -xmlRoot $return -xmlElementName "logicalRouterId" -xmlElementText $($LogicalRouter.Id)
                }
            } 
            else {
                $return = $response.interfaces.interface
                foreach ( $interface in $return ) { 
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$interface.OwnerDocument) -xmlRoot $interface -xmlElementName "logicalRouterId" -xmlElementText $($LogicalRouter.Id)
                }
            }
        }
        else {

            #Just getting a single named Interface
            $URI = "/api/4.0/edges/$($LogicalRouter.Id)/interfaces/$Index"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            $return = $response.interface
            if ( $return ) {
                Add-XmlElement -xmlDoc ([system.xml.xmldocument]$return.OwnerDocument) -xmlRoot $return -xmlElementName "logicalRouterId" -xmlElementText $($LogicalRouter.Id)
            }
        }
        $return
    }
    end {}
}



########
########
# ESG related functions

###Private functions

function PrivateAdd-NsxEdgeVnicAddressGroup {

    #Private function that Edge (ESG and LogicalRouter) VNIC creation leverages
    #To create valid address groups (primary and potentially secondary address) 
    #and netmask.

    #ToDo - Implement IP address and netmask validation

    param (
        [Parameter (Mandatory=$true)]
            [System.XML.XMLElement]$xmlAddressGroups,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [string[]]$SecondaryAddresses=@()

    )

    begin {}

    process {

        [System.XML.XMLDocument]$xmlDoc = $xmlAddressGroups.OwnerDocument
        [System.XML.XMLElement]$xmlAddressGroup = $xmlDoc.CreateElement("addressGroup")
        $xmlAddressGroups.appendChild($xmlAddressGroup) | out-null
        Add-XmlElement -xmlRoot $xmlAddressGroup -xmlElementName "primaryAddress" -xmlElementText $PrimaryAddress
        Add-XmlElement -xmlRoot $xmlAddressGroup -xmlElementName "subnetPrefixLength" -xmlElementText $SubnetPrefixLength
        if ( $SecondaryAddresses ) { 
            [System.XML.XMLElement]$xmlSecondaryAddresses = $XMLDoc.CreateElement("secondaryAddresses")
            $xmlAddressGroup.appendChild($xmlSecondaryAddresses) | out-null
            foreach ($Address in $SecondaryAddresses) { 
                Add-XmlElement -xmlRoot $xmlSecondaryAddresses -xmlElementName "ipAddress" -xmlElementText $Address
            }
        }
    }

    end{}
}

###End Private functions

function New-NsxAddressSpec {
 
    <#
    .SYNOPSIS
    Creates a new NSX Address Group Spec.

    .DESCRIPTION
    NSX ESGs and DLRs interfaces can be configured with multiple 'Address 
    Groups'.  This allows a single interface to have IP addresses defined in 
    different subnets, each complete with their own Primary Address, Netmask and
    zero or more Secondary Addresses.  

    In order to configure an interface in this way with PowerNSX, multiple 
    'AddressGroupSpec' objects can be created using New-NsxAddressSpec,
    and then specified when calling New/Set cmdlets for the associated 
    interfaces. 
    

    #>
  
    param (
         [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [int]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [string[]]$SecondaryAddresses=@()

    )

    begin {}

    process {

        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlAddressGroup = $xmlDoc.CreateElement("addressGroup")
        Add-XmlElement -xmlRoot $xmlAddressGroup -xmlElementName "primaryAddress" -xmlElementText $PrimaryAddress
        Add-XmlElement -xmlRoot $xmlAddressGroup -xmlElementName "subnetPrefixLength" -xmlElementText $SubnetPrefixLength.ToString()
        if ( $SecondaryAddresses ) { 
            [System.XML.XMLElement]$xmlSecondaryAddresses = $XMLDoc.CreateElement("secondaryAddresses")
            $xmlAddressGroup.appendChild($xmlSecondaryAddresses) | out-null
            foreach ($Address in $SecondaryAddresses) { 
                Add-XmlElement -xmlRoot $xmlSecondaryAddresses -xmlElementName "ipAddress" -xmlElementText $Address
            }
        }

        $xmlAddressGroup
    }

    end{}
}

function New-NsxEdgeInterfaceSpec {

    <#
    .SYNOPSIS
    Creates a new NSX Edge Service Gateway interface Spec.

    .DESCRIPTION
    NSX ESGs can host up to 10 interfaces and up to 200 subinterfaces, each of which 
    can be configured with multiple properties.  In order to allow creation of 
    ESGs with an arbitrary number of interfaces, a unique spec for each 
    interface required must first be created.

    ESGs support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches.
    
    .EXAMPLE

    PS C:\> $Uplink = New-NsxEdgeInterfaceSpec -Name Uplink_interface -Type 
        uplink -ConnectedTo (Get-NsxTransportZone | Get-NsxLogicalSwitch LS1) 
        -PrimaryAddress 192.168.0.1 -SubnetPrefixLength 24

    PS C:\> $Internal = New-NsxEdgeInterfaceSpec -Name Internal-interface -Type 
        internal -ConnectedTo (Get-NsxTransportZone | Get-NsxLogicalSwitch LS2) 
        -PrimaryAddress 10.0.0.1 -SubnetPrefixLength 24
    
    #>

    param (
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,9)]
            [int]$Index,
        [Parameter (Mandatory=$false)]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateSet ("internal","uplink","trunk")]
            [string]$Type,
        [Parameter (Mandatory=$false)]
            [ValidateScript({ Validate-LogicalSwitchOrDistributedPortGroup $_ })]
            [object]$ConnectedTo,
        [Parameter (Mandatory=$false)]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$false)]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [string[]]$SecondaryAddresses=@(),
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,9128)]
            [int]$MTU=1500,       
        [Parameter (Mandatory=$false)]
            [switch]$EnableProxyArp=$false,       
        [Parameter (Mandatory=$false)]
            [switch]$EnableSendICMPRedirects=$true,
        [Parameter (Mandatory=$false)]
            [switch]$Connected=$true 

    )

    begin {

        #toying with the idea of using dynamicParams for this, but decided on standard validation code for now.
        if ( ($Type -eq "trunk") -and ( $ConnectedTo -is [System.Xml.XmlElement])) { 
            #Not allowed to have a trunk interface connected to a Logical Switch.
            throw "Interfaces of type Trunk must be connected to a distributed port group."
        }

        if ( $Connected -and ( -not $connectedTo ) ) { 
            #Not allowed to be connected without a connected port group.
            throw "Interfaces that are connected must be connected to a distributed Portgroup or Logical Switch."
        }

        if (( $PsBoundParameters.ContainsKey("PrimaryAddress") -and ( -not $PsBoundParameters.ContainsKey("SubnetPrefixLength"))) -or 
            (( -not $PsBoundParameters.ContainsKey("PrimaryAddress")) -and  $PsBoundParameters.ContainsKey("SubnetPrefixLength"))) {

            #Not allowed to have subnet without primary or vice versa.
            throw "Interfaces with a Primary address must also specify a prefix length and vice versa."   
        }
                
    }
    process { 

        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlVnic = $XMLDoc.CreateElement("vnic")
        $xmlDoc.appendChild($xmlVnic) | out-null

        if ( $PsBoundParameters.ContainsKey("Name")) { Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "name" -xmlElementText $Name }
        if ( $PsBoundParameters.ContainsKey("Index")) { Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "index" -xmlElementText $Index }  
        if ( $PsBoundParameters.ContainsKey("Type")) { 
            Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "type" -xmlElementText $Type 
        }
        else {
            Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "type" -xmlElementText "internal" 

        }
        Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "mtu" -xmlElementText $MTU
        Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "enableProxyArp" -xmlElementText $EnableProxyArp
        Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "enableSendRedirects" -xmlElementText $EnableSendICMPRedirects
        Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "isConnected" -xmlElementText $Connected

        if ( $PsBoundParameters.ContainsKey("ConnectedTo")) { 
            switch ($ConnectedTo){

                { $_ -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.DistributedPortGroupInterop] }  { $PortGroupID = $_.ExtensionData.MoRef.Value }
                { $_ -is [System.Xml.XmlElement]} { $PortGroupID = $_.objectId }
            }  
            Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "portgroupId" -xmlElementText $PortGroupID
        }

        [System.XML.XMLElement]$xmlAddressGroups = $XMLDoc.CreateElement("addressGroups")
        $xmlVnic.appendChild($xmlAddressGroups) | out-null
        if ( $PsBoundParameters.ContainsKey("PrimaryAddress")) {
            #Only supporting one addressgroup - User must use New-NsxAddressSpec to specify multiple.

            $AddressGroupParameters = @{
                xmlAddressGroups = $xmlAddressGroups
            }

            if ( $PsBoundParameters.ContainsKey("PrimaryAddress" )) { $AddressGroupParameters.Add("PrimaryAddress",$PrimaryAddress) }
            if ( $PsBoundParameters.ContainsKey("SubnetPrefixLength" )) { $AddressGroupParameters.Add("SubnetPrefixLength",$SubnetPrefixLength) }
            if ( $PsBoundParameters.ContainsKey("SecondaryAddresses" )) { $AddressGroupParameters.Add("SecondaryAddresses",$SecondaryAddresses) }
             

            PrivateAdd-NsxEdgeVnicAddressGroup @AddressGroupParameters
        }

        $xmlVnic

    }

    end {}
}

function New-NsxEdgeSubInterfaceSpec {

    <#
    .SYNOPSIS
    Creates a new NSX Edge Service Gateway SubInterface Spec.

    .DESCRIPTION
    NSX ESGs can host up to 10 interfaces and up to 200 subinterfaces, each of which 
    can be configured with multiple properties.  In order to allow creation of 
    ESGs with an arbitrary number of interfaces, a unique spec for each 
    interface required must first be created.

    ESGs support Subinterfaces that specify either VLAN ID (VLAN Type) or  NSX
    Logical Switch/Distributed Port Group (Network Type).
    
    #>

    [CmdLetBinding(DefaultParameterSetName="None")]

    param (
        [Parameter (Mandatory=$true)]
            [string]$Name,
        [Parameter (Mandatory=$true)]
            [ValidateRange(1,4094)]
            [int]$TunnelId,
        [Parameter (Mandatory=$false,ParameterSetName="Network")]
            [ValidateScript({ Validate-LogicalSwitchOrDistributedPortGroup $_ })]
            [object]$Network,
        [Parameter (Mandatory=$false,ParameterSetName="VLAN")]
            [ValidateRange(0,4094)]
            [int]$VLAN,
        [Parameter (Mandatory=$false)]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$false)]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [string[]]$SecondaryAddresses=@(),
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,9128)]
            [int]$MTU,              
        [Parameter (Mandatory=$false)]
            [switch]$EnableSendICMPRedirects,
        [Parameter (Mandatory=$false)]
            [switch]$Connected=$true 

    )

    begin {


        if (( $PsBoundParameters.ContainsKey("PrimaryAddress") -and ( -not $PsBoundParameters.ContainsKey("SubnetPrefixLength"))) -or 
            (( -not $PsBoundParameters.ContainsKey("PrimaryAddress")) -and  $PsBoundParameters.ContainsKey("SubnetPrefixLength"))) {

            #Not allowed to have subnet without primary or vice versa.
            throw "Interfaces with a Primary address must also specify a prefix length and vice versa."   
        }
                
    }
    process { 

        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlVnic = $XMLDoc.CreateElement("subInterface")
        $xmlDoc.appendChild($xmlVnic) | out-null

        Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "name" -xmlElementText $Name 
        Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "tunnelId" -xmlElementText $TunnelId
        Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "isConnected" -xmlElementText $Connected

        if ( $PsBoundParameters.ContainsKey("MTU")) { Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "mtu" -xmlElementText $MTU }
        if ( $PsBoundParameters.ContainsKey("EnableSendICMPRedirects")) { Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "enableSendRedirects" -xmlElementText $EnableSendICMPRedirects } 
        if ( $PsBoundParameters.ContainsKey("Network")) { 
            switch ($Network){

                { $_ -is [VMware.VimAutomation.ViCore.Interop.V1.Host.Networking.DistributedPortGroupInterop] }  { $PortGroupID = $_.ExtensionData.MoRef.Value }
                { $_ -is [System.Xml.XmlElement]} { $PortGroupID = $_.objectId }
            }  

            #Even though the element name is logicalSwitchId, subinterfaces support VDPortGroup as well as Logical Switch.
            Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "logicalSwitchId" -xmlElementText $PortGroupID
        }

        if ( $PsBoundParameters.ContainsKey("VLAN")) {

            Add-XmlElement -xmlRoot $xmlVnic -xmlElementName "vlanId" -xmlElementText $VLAN
        }


        if ( $PsBoundParameters.ContainsKey("PrimaryAddress")) {
            #For now, only supporting one addressgroup - will refactor later
            [System.XML.XMLElement]$xmlAddressGroups = $XMLDoc.CreateElement("addressGroups")
            $xmlVnic.appendChild($xmlAddressGroups) | out-null
            $AddressGroupParameters = @{
                xmlAddressGroups = $xmlAddressGroups
            }

            if ( $PsBoundParameters.ContainsKey("PrimaryAddress" )) { $AddressGroupParameters.Add("PrimaryAddress",$PrimaryAddress) }
            if ( $PsBoundParameters.ContainsKey("SubnetPrefixLength" )) { $AddressGroupParameters.Add("SubnetPrefixLength",$SubnetPrefixLength) }
            if ( $PsBoundParameters.ContainsKey("SecondaryAddresses" )) { $AddressGroupParameters.Add("SecondaryAddresses",$SecondaryAddresses) }
             
            PrivateAdd-NsxEdgeVnicAddressGroup @AddressGroupParameters
        }

        $xmlVnic

    }

    end {}
}

function Set-NsxEdgeInterface {

    <#
    .SYNOPSIS
    Conigures an NSX Edge Services Gateway Interface.

    .DESCRIPTION
    NSX ESGs can host up to 10 interfaces and up to 200 subinterfaces, each of 
    which can be configured with multiple properties.  

    ESGs support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches.

    Use Set-NsxEdgeInterface to change (including overwriting) the configuration
    of an interface.

    .EXAMPLE
    $interface = Get-NsxEdge testesg | Get-NsxEdgeInterface -Index 4
    $interface | Set-NsxEdgeInterface -Name "vNic4" -Type internal 
        -ConnectedTo $ls4 -PrimaryAddress $ip4 -SubnetPrefixLength 24

    Get an interface, then update it.
    
    .EXAMPLE
    $add1 = New-NsxAddressSpec -PrimaryAddress 11.11.11.11 -SubnetPrefixLength 24 -SecondaryAddresses 11.11.11.12, 11.11.11.13
    $add2 = New-NsxAddressSpec -PrimaryAddress 22.22.22.22 -SubnetPrefixLength 24 -SecondaryAddresses 22.22.22.23

    Get-NsxEdge testesg | Get-NsxEdgeInterface -index 5 | Set-NSxEdgeInterface -ConnectedTo $ls4 -AddressSpec $add1,$add2

    Adds two addresses, precreated via New-AddressSpec to ESG testesg vnic 5
    
    #>

    [CmdLetBinding(DefaultParameterSetName="DirectAddress")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$true,ValueFromPipeline=$true, ParameterSetName="AddressGroupSpec")]
            [ValidateScript({ Validate-EdgeInterface $_ })]
            [System.Xml.XmlElement]$Interface,
        [Parameter (Mandatory=$true, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$true, ParameterSetName="AddressGroupSpec")]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$true, ParameterSetName="AddressGroupSpec")]
            [ValidateSet ("internal","uplink","trunk")]
            [string]$Type,
        [Parameter (Mandatory=$true, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$true, ParameterSetName="AddressGroupSpec")]
            [ValidateScript({ Validate-LogicalSwitchOrDistributedPortGroup $_ })]
            [object]$ConnectedTo,
        [Parameter (Mandatory=$false, ParameterSetName="DirectAddress")]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$false, ParameterSetName="DirectAddress")]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false, ParameterSetName="DirectAddress")]
            [string[]]$SecondaryAddresses=@(),
        [Parameter (Mandatory=$true, ParameterSetName="AddressGroupSpec")]
            [ValidateScript({ Validate-AddressGroupSpec $_ })]
            [System.Xml.XmlElement[]]$AddressSpec,
        [Parameter (Mandatory=$false, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$false, ParameterSetName="AddressGroupSpec")]
            [ValidateRange(1,9128)]
            [int]$MTU=1500,       
        [Parameter (Mandatory=$false, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$false, ParameterSetName="AddressGroupSpec")]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableProxyArp=$false,       
        [Parameter (Mandatory=$false, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$false, ParameterSetName="AddressGroupSpec")]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableSendICMPRedirects=$true,
        [Parameter (Mandatory=$false, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$false, ParameterSetName="AddressGroupSpec")]
            [ValidateNotNullOrEmpty()]
            [switch]$Connected=$true,
        [Parameter (Mandatory=$false, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$false, ParameterSetName="AddressGroupSpec")]
            [ValidateNotNullOrEmpty()]
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$false, ParameterSetName="AddressGroupSpec")]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Check if there is already configuration 
        if ( $confirm ) { 

            If ( ($Interface | get-member -memberType properties PortGroupID ) -or ( $Interface.addressGroups ) ) {

                $message  = "Interface $($Interface.Name) appears to already be configured.  Config will be overwritten."
                $question = "Proceed with reconfiguration for $($Interface.Name)?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
                if ( $decision -eq 1 ) {
                    return
                }
            }
        }

        #generate the vnic XML 
        $vNicSpecParams = @{ 
            Index = $Interface.index 
            Name = $name 
            Type = $type 
            ConnectedTo = $connectedTo                      
            MTU = $MTU 
            EnableProxyArp = $EnableProxyArp
            EnableSendICMPRedirects = $EnableSendICMPRedirects 
            Connected = $connected
        }
        if ( $PsBoundParameters.ContainsKey("PrimaryAddress" )) { $vNicSpecParams.Add("PrimaryAddress",$PrimaryAddress) }
        if ( $PsBoundParameters.ContainsKey("SubnetPrefixLength" )) { $vNicSpecParams.Add("SubnetPrefixLength",$SubnetPrefixLength) }
        if ( $PsBoundParameters.ContainsKey("SecondaryAddresses" )) { $vNicSpecParams.Add("SecondaryAddresses",$SecondaryAddresses) }

        $VnicSpec = New-NsxEdgeInterfaceSpec @vNicSpecParams
        write-debug "$($MyInvocation.MyCommand.Name) : vNic Spec is $($VnicSpec.outerxml | format-xml) "


        #Construct the vnics XML Element
        [System.XML.XMLElement]$xmlVnics = $VnicSpec.OwnerDocument.CreateElement("vnics")
        $xmlVnics.AppendChild($VnicSpec) | out-null

        #Import any user specified address groups.
        if ( $PsBoundParameters.ContainsKey('AddressSpec')) { 

            [System.Xml.XmlElement]$AddressGroups = $VnicSpec.SelectSingleNode('descendant::addressGroups') 
            foreach ( $spec in $AddressSpec ) { 
                $import = $VnicSpec.OwnerDocument.ImportNode(($spec), $true)
                $AddressGroups.AppendChild($import) | out-null
            }
        }

        # #Do the post
        $body = $xmlVnics.OuterXml
        $URI = "/api/4.0/edges/$($Interface.edgeId)/vnics/?action=patch"
        Write-Progress -activity "Updating Edge Services Gateway interface configuration for interface $($Interface.Index)."
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection
        Write-progress -activity "Updating Edge Services Gateway interface configuration for interface $($Interface.Index)." -completed

        write-debug "$($MyInvocation.MyCommand.Name) : Getting updated interface"
        Get-NsxEdge -objectId $($Interface.edgeId) -connection $connection | Get-NsxEdgeInterface -index "$($Interface.Index)" -connection $connection
    }

    end {}
}

function Clear-NsxEdgeInterface {

    <#
    .SYNOPSIS
    Clears the configuration on an NSX Edge Services Gateway interface.

    .DESCRIPTION
    NSX ESGs can host up to 10 interfaces and up to 200 subinterfaces, each of which 
    can be configured with multiple properties.  

    ESGs support itnerfaces connected to either VLAN backed port groups or NSX
    Logical Switches.

    Use Clear-NsxEdgeInterface to set the configuration of an interface back to default 
    (disconnected, not attached to any portgroup, and no defined addressgroup).
    
    .EXAMPLE
    Get an interface and then clear its configuration.

    PS C:\> $interface = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic4"

    PS C:\> $interface | Clear-NsxEdgeInterface -confirm:$false

    #>

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeInterface $_ })]
            [System.Xml.XmlElement]$Interface,       
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    begin {
    }

    process { 

        if ( $confirm ) { 

            $message  = "Interface ($Interface.Name) config will be cleared."
            $question = "Proceed with interface reconfiguration for interface $($interface.index)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            if ( $decision -eq 1 ) {
                return
            }
        }
        

        # #Do the delete
        $URI = "/api/4.0/edges/$($interface.edgeId)/vnics/$($interface.Index)"
        Write-Progress -activity "Clearing Edge Services Gateway interface configuration for interface $($interface.Index)."
        invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection
        Write-progress -activity "Clearing Edge Services Gateway interface configuration for interface $($interface.Index)." -completed

    }

    end {}
}

function Get-NsxEdgeInterface {

    <#
    .SYNOPSIS
    Retrieves the specified interface configuration on a specified Edge Services 
    Gateway.

    .DESCRIPTION
    NSX ESGs can host up to 10 interfaces and up to 200 subinterfaces, each of which 
    can be configured with multiple properties.  

    ESGs support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches.

    Use Get-NsxEdgeInterface to retrieve the configuration of an interface.

    .EXAMPLE
    Get all interface configuration for ESG named EsgTest
    PS C:\> Get-NsxEdge EsgTest | Get-NsxEdgeInterface

    .EXAMPLE
    Get interface configuration for interface named vNic4 on ESG named EsgTest
    PS C:\> Get-NsxEdge EsgTest | Get-NsxEdgeInterface vNic4


    .EXAMPLE
    Get interface configuration for interface number 4 on ESG named EsgTest
    PS C:\> Get-NsxEdge EsgTest | Get-NsxEdgeInterface -index 4

    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$False,ParameterSetName="Name",Position=1)]
            [string]$Name,
        [Parameter (Mandatory=$True,ParameterSetName="Index")]
            [ValidateRange(0,9)]
            [int]$Index,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {}

    process {     

        if ( -not ($PsBoundParameters.ContainsKey("Index") )) { 
            #All interfaces on Edge
            $URI = "/api/4.0/edges/$($Edge.Id)/vnics/"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $PsBoundParameters.ContainsKey("name") ) {

               write-debug "$($MyInvocation.MyCommand.Name) : Getting vNic by Name"

                $return = $response.vnics.vnic | ? { $_.name -eq $name }
                if ( $return ) {
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$return.OwnerDocument) -xmlRoot $return -xmlElementName "edgeId" -xmlElementText $($Edge.Id)
                }
            } 
            else {

                write-debug "$($MyInvocation.MyCommand.Name) : Getting all vNics"

                $return = $response.vnics.vnic
                foreach ( $vnic in $return ) { 
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$vnic.OwnerDocument) -xmlRoot $vnic -xmlElementName "edgeId" -xmlElementText $($Edge.Id)
                }
            }
        }
        else {

            write-debug "$($MyInvocation.MyCommand.Name) : Getting vNic by Index"

            #Just getting a single vNic by index
            $URI = "/api/4.0/edges/$($Edge.Id)/vnics/$Index"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            $return = $response.vnic
            Add-XmlElement -xmlDoc ([system.xml.xmldocument]$return.OwnerDocument) -xmlRoot $return -xmlElementName "edgeId" -xmlElementText $($Edge.Id)
        }
        $return
    }
    end {}
}

function New-NsxEdgeSubInterface {

    <#
    .SYNOPSIS
    Adds a new subinterface to an existing NSX Edge Services Gateway trunk mode 
    interface.

    .DESCRIPTION
    NSX ESGs can host up to 10 interfaces and up to 200 subinterfaces, each of which 
    can be configured with multiple properties.  

    ESGs support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches.

    Use New-NsxEdgeSubInterface to add a new subinterface.

    .EXAMPLE
    Get an NSX Edge interface and configure a new subinterface in VLAN mode.

    PS C:\> $trunk = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3"

    PS C:\> $trunk | New-NsxEdgeSubinterface  -Name "sub1" -PrimaryAddress $ip5 
        -SubnetPrefixLength 24 -TunnelId 1 -Vlan 123

    .EXAMPLE
    Get an NSX Edge interface and configure a new subinterface in Network mode.

    PS C:\> $trunk = Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3"

    PS C:\> $trunk | New-NsxEdgeSubinterface  -Name "sub1" -PrimaryAddress $ip5 
        -SubnetPrefixLength 24 -TunnelId 1 -Network $LS2
    
    #>

    [CmdLetBinding(DefaultParameterSetName="None")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeInterface $_ })]
            [System.Xml.XmlElement]$Interface,
        [Parameter (Mandatory=$true)]
            [ValidateRange(1,4094)]
            [int]$TunnelId,
        [Parameter (Mandatory=$false,ParameterSetName="Network")]
            [ValidateScript({ Validate-LogicalSwitchOrDistributedPortGroup $_ })]
            [object]$Network,
        [Parameter (Mandatory=$false,ParameterSetName="VLAN")]
            [ValidateRange(0,4094)]
            [int]$VLAN,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false)]
            [string[]]$SecondaryAddresses=@(),
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,9128)]
            [int]$MTU,             
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableSendICMPRedirects,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$Connected=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )


    #Validate interfaceindex is trunk
    if ( -not $Interface.type -eq 'trunk' ) {
        throw "Specified interface $($interface.Name) is of type $($interface.type) but must be of type trunk to host a subinterface. "
    }

    #Create private xml element
    $_Interface = $Interface.CloneNode($true)

    #Store the edgeId and remove it from the XML as we need to post it...
    $edgeId = $_Interface.edgeId
    $NodetoRemove = $($_Interface.SelectSingleNode('descendant::edgeId'))
    write-debug "Node to remove parent: $($nodetoremove.ParentNode | format-xml)"

    $_Interface.RemoveChild( $NodeToRemove ) | out-null
    

    #Get or create the subinterfaces node. 
    [System.XML.XMLDocument]$xmlDoc = $_Interface.OwnerDocument
    if ( $_Interface | get-member -memberType Properties -Name subInterfaces) { 
        [System.XML.XMLElement]$xmlSubInterfaces = $_Interface.subInterfaces
    }
    else {
        [System.XML.XMLElement]$xmlSubInterfaces = $xmlDoc.CreateElement("subInterfaces")
        $_Interface.AppendChild($xmlSubInterfaces) | out-null
    }

    #generate the vnic XML 
    $vNicSpecParams = @{    
        TunnelId = $TunnelId 
        Connected = $connected
        Name = $Name
    }

    switch ($psCmdlet.ParameterSetName) {

        "Network" { if ( $PsBoundParameters.ContainsKey("Network" )) { $vNicSpecParams.Add("Network",$Network) } }
        "VLAN" { if ( $PsBoundParameters.ContainsKey("VLAN" )) { $vNicSpecParams.Add("VLAN",$VLAN) } }
        "None" {}
        Default { throw "An invalid parameterset was found.  This should never happen." }
    }

    if ( $PsBoundParameters.ContainsKey("PrimaryAddress" )) { $vNicSpecParams.Add("PrimaryAddress",$PrimaryAddress) }
    if ( $PsBoundParameters.ContainsKey("SubnetPrefixLength" )) { $vNicSpecParams.Add("SubnetPrefixLength",$SubnetPrefixLength) }
    if ( $PsBoundParameters.ContainsKey("SecondaryAddresses" )) { $vNicSpecParams.Add("SecondaryAddresses",$SecondaryAddresses) }
    if ( $PsBoundParameters.ContainsKey("MTU" )) { $vNicSpecParams.Add("MTU",$MTU) }
    if ( $PsBoundParameters.ContainsKey("EnableSendICMPRedirects" )) { $vNicSpecParams.Add("EnableSendICMPRedirects",$EnableSendICMPRedirects) }

    $VnicSpec = New-NsxEdgeSubInterfaceSpec @vNicSpecParams
    write-debug "$($MyInvocation.MyCommand.Name) : vNic Spec is $($VnicSpec.outerxml | format-xml) "
    $import = $xmlDoc.ImportNode(($VnicSpec), $true)
    $xmlSubInterfaces.AppendChild($import) | out-null

    # #Do the post
    $body = $_Interface.OuterXml
    $URI = "/api/4.0/edges/$($EdgeId)/vnics/$($_Interface.Index)"
    Write-Progress -activity "Updating Edge Services Gateway interface configuration for $($_Interface.Name)."
    invoke-nsxrestmethod -method "put" -uri $URI -body $body -connection $connection
    Write-progress -activity "Updating Edge Services Gateway interface configuration for $($_Interface.Name)." -completed
}

function Remove-NsxEdgeSubInterface {

    <#
    .SYNOPSIS
    Removes the specificed subinterface from an NSX Edge Services Gateway  
    interface.

    .DESCRIPTION
    NSX ESGs can host up to 10 interfaces and up to 200 subinterfaces, each of which 
    can be configured with multiple properties.  

    ESGs support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches.

    Use Remove-NsxEdgeSubInterface to remove a subinterface configuration from 
    and ESG trunk interface.  

    .EXAMPLE
    Get a subinterface and then remove it.

    PS C:\> $interface =  Get-NsxEdge $name | Get-NsxEdgeInterface "vNic3" 

    PS C:\> $interface | Get-NsxEdgeSubInterface "sub1" | Remove-NsxEdgeSubinterface 
 
    
    #>

    [CmdLetBinding(DefaultParameterSetName="None")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSubInterface $_ })]
            [System.Xml.XmlElement]$Subinterface,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    Begin {}

    Process { 
        if ( $confirm ) { 

            $message  = "Interface $($Subinterface.Name) will be removed."
            $question = "Proceed with interface reconfiguration for interface $($Subinterface.index)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            if ( $decision -eq 1 ) {
                return
            }
        }

        #Get the vnic xml
        $ParentVnic = $(Get-NsxEdge -connection $connection -objectId $SubInterface.edgeId).vnics.vnic | ? { $_.index -eq $subInterface.vnicId }

        #Remove the node using xpath query.
        $NodeToRemove = $ParentVnic.subInterfaces.SelectSingleNode("descendant::subInterface[index=$($subInterface.Index)]")
        write-debug "$($MyInvocation.MyCommand.Name) : XPath query for node to delete returned $($NodetoRemove.OuterXml | format-xml)"
        $ParentVnic.Subinterfaces.RemoveChild($NodeToRemove) | out-null

        #Put the modified VNIC xml
        $body = $ParentVnic.OuterXml
        $URI = "/api/4.0/edges/$($SubInterface.edgeId)/vnics/$($ParentVnic.Index)"
        Write-Progress -activity "Updating Edge Services Gateway interface configuration for interface $($ParentVnic.Name)."
        invoke-nsxrestmethod -method "put" -uri $URI -body $body -connection $connection
        Write-progress -activity "Updating Edge Services Gateway interface configuration for interface $($ParentVnic.Name)." -completed

    }
    End {}
}

function Get-NsxEdgeSubInterface {

    <#
    .SYNOPSIS
    Retrieves the subinterface configuration for the specified interface

    .DESCRIPTION
    NSX ESGs can host up to 10 interfaces and up to 200 subinterfaces, each of which 
    can be configured with multiple properties.  

    ESGs support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches.

    Use Get-NsxEdgeSubInterface to retrieve the subinterface configuration of an 
    interface.
    
    .EXAMPLE
    Get an NSX Subinterface called sub1 from any interface on esg testesg

    PS C:\> Get-NsxEdge testesg | Get-NsxEdgeInterface | 
        Get-NsxEdgeSubInterface "sub1"


    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeInterface $_ })]
            [System.Xml.XmlElement]$Interface,   
        [Parameter (Mandatory=$False,ParameterSetName="Name",Position=1)]
            [string]$Name,
        [Parameter (Mandatory=$True,ParameterSetName="Index")]
            [ValidateRange(10,200)]
            [int]$Index
    )
    
    begin {}

    process {    

        #Not throwing error if no subinterfaces defined.    
        If ( $interface | get-member -name subInterfaces -Membertype Properties ) {  

            if ($PsBoundParameters.ContainsKey("Index")) { 

                $subint = $Interface.subInterfaces.subinterface | ? { $_.index -eq $Index }

                if ( $subint ) {
                    $_subint = $subint.CloneNode($true)
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$Interface.OwnerDocument) -xmlRoot $_subint -xmlElementName "edgeId" -xmlElementText $($Interface.edgeId)
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$Interface.OwnerDocument) -xmlRoot $_subint -xmlElementName "vnicId" -xmlElementText $($Interface.index)
                    $_subint
                }
            }
            elseif ( $PsBoundParameters.ContainsKey("name")) {
                    
                $subint = $Interface.subInterfaces.subinterface | ? { $_.name -eq $name }
                if ($subint) { 
                    $_subint = $subint.CloneNode($true)
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$Interface.OwnerDocument) -xmlRoot $_subint -xmlElementName "edgeId" -xmlElementText $($Interface.edgeId)
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$Interface.OwnerDocument) -xmlRoot $_subint -xmlElementName "vnicId" -xmlElementText $($Interface.index)
                    $_subint
                }
            } 
            else {
                #All Subinterfaces on interface
                foreach ( $subint in $Interface.subInterfaces.subInterface ) {
                    $_subint = $subint.CloneNode($true)
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$Interface.OwnerDocument) -xmlRoot $_subint -xmlElementName "edgeId" -xmlElementText $($Interface.edgeId)
                    Add-XmlElement -xmlDoc ([system.xml.xmldocument]$Interface.OwnerDocument) -xmlRoot $_subint -xmlElementName "vnicId" -xmlElementText $($Interface.index)
                    $_subint
                }
            }
        }
    }
    end {}
}

function Get-NsxEdgeInterfaceAddress {
    
    <#
   .SYNOPSIS
    Retrieves the address configuration for the specified interface

    .DESCRIPTION
    NSX ESGs interfaces can be configured with multiple 'Address Groups'.  This 
    allows a single interface to have IP addresses defined in different subnets,
    each complete with their own Primary Address, Netmask and zero or more 
    Secondary Addresses.  

    The Get-NsxEdgeInterfaceAddress cmdlet retrieves the addresses for
    the specific interface.
    
    .EXAMPLE
    Get-NsxEdge esgtest | Get-NsxEdgeInterface -Index 9 | Get-NsxEdgeInterfaceAddress

    Retrieves all the address groups defined on vNic 9 of the ESG esgtest.

    .EXAMPLE
    Get-NsxEdge esgtest | Get-NsxEdgeInterface -Index 9 | Get-NsxEdgeInterfaceAddress -PrimaryAddress 1.2.3.4

    Retrieves the address config with primary address 1.2.3.4 defined on vNic 9 of the ESG esgtest.
    
    #>

    param (

         [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeInterface $_ })]
            [System.Xml.XmlElement]$Interface,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$PrimaryAddress  
        
    )
    
    begin {
    }

    process {

        $_Interface = ($Interface.CloneNode($True))
        [System.Xml.XmlElement]$AddressGroups = $_Interface.SelectSingleNode('descendant::addressGroups')

        #Need to use an xpath query here, as dot notation will throw in strict mode if there is no childnode.
        If ( $AddressGroups.SelectSingleNode('descendant::addressGroup')) { 

            $GroupCollection = $AddressGroups.addressGroup
            if ( $PsBoundParameters.ContainsKey('PrimaryAddress')) {
                $GroupCollection = $GroupCollection | ? { $_.primaryAddress -eq $PrimaryAddress }
            }

            foreach ( $AddressGroup in $GroupCollection ) { 
                Add-XmlElement -xmlRoot $AddressGroup -xmlElementName "edgeId" -xmlElementText $Interface.EdgeId
                Add-XmlElement -xmlRoot $AddressGroup -xmlElementName "interfaceIndex" -xmlElementText $Interface.Index

            }

            $GroupCollection
        }
    }

    end {}
}

function Add-NsxEdgeInterfaceAddress {
    
    <#
   .SYNOPSIS
    Adds a new address to the specified ESG interface

    .DESCRIPTION
    NSX ESGs interfaces can be configured with multiple 'Address Groups'.  This 
    allows a single interface to have IP addresses defined in different subnets,
    each complete with their own Primary Address, Netmask and zero or more 
    Secondary Addresses.  

    The Add-NsxEdgeInterfaceAddress cmdlet adds a new address to an
    existing ESG interface.
    
    .EXAMPLE
    get-nsxedge esgtest | Get-NsxEdgeInterface -Index 9 | Add-NsxEdgeInterfaceAddress -PrimaryAddress 44.44.44.44 -SubnetPrefixLength 24  -SecondaryAddresses 44.44.44.45,44.44.44.46
    
    Adds a new primary address and multiple secondary addresses to vNic 9 on edge esgtest
    
    .EXAMPLE
    $add2 = New-NsxAddressSpec -PrimaryAddress 22.22.22.22 -SubnetPrefixLength 24 -SecondaryAddresses 22.22.22.23
    $add3 = New-NsxAddressSpec -PrimaryAddress 33.33.33.33 -SubnetPrefixLength 24 -SecondaryAddresses 33.33.33.34

    get-nsxedge testesg | Get-NsxEdgeInterface -Index 9 | Add-NsxEdgeInterfaceAddress -AddressSpec $add2,$add3

    Adds two new addresses to testesg's vnic9 using address specs.
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$true,ValueFromPipeline=$true, ParameterSetName="AddressGroupSpec")]
            [ValidateScript({ Validate-EdgeInterface $_ })]
            [System.Xml.XmlElement]$Interface,
        [Parameter (Mandatory=$true, ParameterSetName="DirectAddress")]
            [ValidateNotNullOrEmpty()]
            [string]$PrimaryAddress,
        [Parameter (Mandatory=$true, ParameterSetName="DirectAddress")]
            [ValidateNotNullOrEmpty()]
            [string]$SubnetPrefixLength,       
        [Parameter (Mandatory=$false, ParameterSetName="DirectAddress")]
            [string[]]$SecondaryAddresses=@(),
        [Parameter (Mandatory=$true, ParameterSetName="AddressGroupSpec")]
            [ValidateScript({ Validate-AddressGroupSpec $_ })]
            [System.Xml.XmlElement[]]$AddressSpec,
        [Parameter (Mandatory=$False, ParameterSetName="DirectAddress")]
        [Parameter (Mandatory=$false, ParameterSetName="AddressGroupSpec")]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {}
    process { 

        [System.Xml.XmlElement]$_Interface = $Interface.CloneNode($True)

        #Store the edgeId and remove it from the XML as we need to put it...
        $edgeId = $_Interface.edgeId
        $NodetoRemove = $($_Interface.SelectSingleNode('descendant::edgeId'))
        $_Interface.RemoveChild( $NodeToRemove ) | out-null

        [System.Xml.XmlElement]$AddressGroups = $_Interface.SelectSingleNode('descendant::addressGroups')

        if ( $PSCmdlet.ParameterSetName -eq "DirectAddress") { 
            if ( $PsBoundParameters.ContainsKey('SecondaryAddresses')) { 
                PrivateAdd-NsxEdgeVnicAddressGroup -xmlAddressGroups $AddressGroups -PrimaryAddress $PrimaryAddress -SubnetPrefixLength $SubnetPrefixLength -SecondaryAddresses $SecondaryAddresses 
            }
            else {
                PrivateAdd-NsxEdgeVnicAddressGroup -xmlAddressGroups $AddressGroups -PrimaryAddress $PrimaryAddress -SubnetPrefixLength $SubnetPrefixLength -SecondaryAddresses $SecondaryAddresses 
            }
        }

        else { 
            #Import any user specified address groups.
            foreach ( $spec in $AddressSpec ) { 
                $import = $_Interface.OwnerDocument.ImportNode(($spec), $true)
                $AddressGroups.AppendChild($import) | out-null
            }
        }

        #Do the post
        $body = $_Interface.OuterXml
        $URI = "/api/4.0/edges/$($edgeId)/vnics/$($_Interface.Index)"
        Write-Progress -activity "Updating Edge Services Gateway interface configuration for interface $($_Interface.Index)."
        $response = invoke-nsxrestmethod -method "put" -uri $URI -body $body -connection $connection
        Write-progress -activity "Updating Edge Services Gateway interface configuration for interface $($_Interface.Index)." -completed

        write-debug "$($MyInvocation.MyCommand.Name) : Getting updated interface"
        Get-NsxEdge -objectId $($edgeId) -connection $connection | Get-NsxEdgeInterface -index "$($_Interface.Index)" -connection $connection
    }

    end {}
}

function Remove-NsxEdgeInterfaceAddress {
    
    <#
   .SYNOPSIS
    Removes the specified address configuration for the specified interface

    .DESCRIPTION
    NSX ESGs interfaces can be configured with multiple 'Address Groups'.  This 
    allows a single interface to have IP addresses defined in different subnets,
    each complete with their own Primary Address, Netmask and zero or more 
    Secondary Addresses.  

    The Remove-NsxEdgeInterfaceAddress cmdlet removes the address specified
    from the specified interface.
    
    .EXAMPLE
    Get-NsxEdge esgtest | Get-NsxEdgeInterface -Index 9 | Get-NsxEdgeInterfaceAddress -PrimaryAddress 1.2.3.4 | Remove-NsxEdgeInterfaceAddress

    Removes the address group with primary address 1.2.3.4 defined on vNic 9 of the ESG esgtest.
    
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeInterfaceAddress $_ })]
            [System.Xml.XmlElement]$InterfaceAddress,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our Edge
        $edgeId = $InterfaceAddress.edgeId
        $InterfaceIndex = $InterfaceAddress.interfaceIndex
        $Edge = Get-NsxEdge -objectId $edgeId -connection $connection 
        $Interface = $Edge | Get-NsxEdgeInterface -index $InterfaceIndex -connection $connection
        if ( -not $Interface ) { Throw "Interface index $InterfaceIndex was not found on edge $edgeId."}

        #Remove the edgeId and interfaceIndex elements from the XML as we need to post it...
        $Interface.RemoveChild( $($Interface.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Need to do an xpath query here to query for an address that matches the one passed in.  
        $xpathQuery = "//addressGroups/addressGroup[primaryAddress=`"$($InterfaceAddress.primaryAddress)`"]"
        write-debug "$($MyInvocation.MyCommand.Name) : XPath query for addressgroup nodes to remove is: $xpathQuery"
        $addressGroupToRemove = $Interface.SelectSingleNode($xpathQuery)

        if ( $addressGroupToRemove ) { 

            write-debug "$($MyInvocation.MyCommand.Name) : addressGroupToRemove Element is: `n $($addressGroupToRemove.OuterXml | format-xml) "
            $Interface.AddressGroups.RemoveChild($addressGroupToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($EdgeId)/vnics/$InterfaceIndex"
            $body = $Interface.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            }
        }
        else {
            Throw "Address $($InterfaceAddress.PrimaryAddress) was not found in the configuration for interface $InterfaceIndex on Edge $edgeId"
        }
    }

    end {}
}

function Get-NsxEdge {

    <#
    .SYNOPSIS
    Retrieves an NSX Edge Service Gateway Object.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches.

    
    .EXAMPLE
    PS C:\>  Get-NsxEdge

    #>


    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ParameterSetName="objectId")]
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    $pagesize = 10         
    switch ( $psCmdlet.ParameterSetName ) {

        "Name" { 
            $URI = "/api/4.0/edges?pageSize=$pagesize&startIndex=00" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            
            #Edge summary XML is returned as paged data, means we have to handle it.  
            #Then we have to query for full information on a per edge basis.
            $edgesummaries = @()
            $edges = @()
            $itemIndex =  0
            $startingIndex = 0 
            $pagingInfo = $response.pagedEdgeList.edgePage.pagingInfo
            
            if ( [int]$paginginfo.totalCount -ne 0 ) {
                 write-debug "$($MyInvocation.MyCommand.Name) : ESG count non zero"

                do {
                    write-debug "$($MyInvocation.MyCommand.Name) : In paging loop. PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"

                    while (($itemindex -lt ([int]$paginginfo.pagesize + $startingIndex)) -and ($itemIndex -lt [int]$paginginfo.totalCount )) {
            
                        write-debug "$($MyInvocation.MyCommand.Name) : In Item Processing Loop: ItemIndex: $itemIndex"
                        write-debug "$($MyInvocation.MyCommand.Name) : $(@($response.pagedEdgeList.edgePage.edgeSummary)[($itemIndex - $startingIndex)].objectId)"
                    
                        #Need to wrap the edgesummary prop of the datapage in case we get exactly 1 item - 
                        #which powershell annoyingly unwraps to a single xml element rather than an array...
                        $edgesummaries += @($response.pagedEdgeList.edgePage.edgeSummary)[($itemIndex - $startingIndex)]
                        $itemIndex += 1 
                    }  
                    write-debug "$($MyInvocation.MyCommand.Name) : Out of item processing - PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                    if ( [int]$paginginfo.totalcount -gt $itemIndex) {
                        write-debug "$($MyInvocation.MyCommand.Name) : PagingInfo: PageSize: $($pagingInfo.PageSize), StartIndex: $($paginginfo.startIndex), TotalCount: $($paginginfo.totalcount)"
                        $startingIndex += $pagesize
                        $URI = "/api/4.0/edges?pageSize=$pagesize&startIndex=$startingIndex"
                
                        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
                        $pagingInfo = $response.pagedEdgeList.edgePage.pagingInfo
                    

                    } 
                } until ( [int]$paginginfo.totalcount -le $itemIndex )    
                write-debug "$($MyInvocation.MyCommand.Name) : Completed page processing: ItemIndex: $itemIndex"
            }

            #What we got here is...failure to communicate!  In order to get full detail, we have to requery for each edgeid.
            #But... there is information in the SUmmary that isnt in the full detail.  So Ive decided to add the summary as a node 
            #to the returned edge detail. 

            foreach ($edgesummary in $edgesummaries) {

                $URI = "/api/4.0/edges/$($edgesummary.objectID)" 
                $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
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
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            $edge = $response.edge
            $URI = "/api/4.0/edges/$objectId/summary" 
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            $import = $edge.ownerDocument.ImportNode($($response.edgeSummary), $true)
            $edge.AppendChild($import) | out-null
            $edge

        }
    }
}

function New-NsxEdge {

    <#
    .SYNOPSIS
    Creates a new NSX Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches.

    PowerCLI cmdlets such as Get-VDPortGroup and Get-Datastore require a valid
    PowerCLI session.
    
    .EXAMPLE
    Create interface specifications first for each interface that you want on the ESG

    PS C:\> $vnic0 = New-NsxEdgeInterfaceSpec -Index 0 -Name Uplink -Type Uplink 
        -ConnectedTo (Get-VDPortgroup Corp) -PrimaryAddress "1.1.1.2" 
        -SubnetPrefixLength 24

    PS C:\> $vnic1 = New-NsxEdgeInterfaceSpec -Index 1 -Name Internal -Type Uplink 
        -ConnectedTo $LogicalSwitch1 -PrimaryAddress "2.2.2.1" 
        -SecondaryAddresses "2.2.2.2" -SubnetPrefixLength 24

    Then create the Edge Services Gateway
    PS C:\> New-NsxEdge -name DMZ_Edge_2 
        -Cluster (get-cluster Cluster1) -Datastore (get-datastore Datastore1) 
        -Interface $vnic0,$vnic1 -Password 'Pass'

    #>

    param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true,ParameterSetName="ResourcePool")]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ResourcePoolInterop]$ResourcePool,
        [Parameter (Mandatory=$true,ParameterSetName="Cluster")]
            [ValidateScript({
                if ( $_ -eq $null ) { throw "Must specify Cluster."}
                if ( -not $_.DrsEnabled ) { throw "Cluster is not DRS enabled."}
                $true
            })]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.ClusterInterop]$Cluster,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.DatastoreManagement.DatastoreInterop]$Datastore,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [String]$Username="admin",
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [String]$Password,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.DatastoreManagement.DatastoreInterop]$HADatastore=$datastore,
        [Parameter (Mandatory=$false)]
            [ValidateSet ("compact","large","xlarge","quadlarge")]
            [string]$FormFactor="compact",
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.FolderInterop]$VMFolder,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [String]$Tenant,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [String]$Hostname=$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableSSH=$false,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$AutoGenerateRules=$true,
        [Parameter (Mandatory=$false)]
            [switch]$FwEnabled=$true,
        [Parameter (Mandatory=$false)]
            [switch]$FwDefaultPolicyAllow=$false,
        [Parameter (Mandatory=$false)]
            [switch]$FwLoggingEnabled=$true,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$EnableHa=$false,
        [Parameter (Mandatory=$false)]
            [ValidateRange(6,900)]
            [int]$HaDeadTime,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,9)]
            [int]$HaVnic,
        [Parameter (Mandatory=$false)]
            [switch]$EnableSyslog=$false,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string[]]$SyslogServer,
        [Parameter (Mandatory=$false)]
            [ValidateSet("udp","tcp",IgnoreCase=$true)]
            [string]$SyslogProtocol,
       [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-EdgeInterfaceSpec $_ })]
            [System.Xml.XmlElement[]]$Interface,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection  
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("edge")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "fqdn" -xmlElementText $Hostname

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "type" -xmlElementText "gatewayServices"
        if ( $Tenant ) { Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "tenant" -xmlElementText $Tenant }

        #Appliances element
        [System.XML.XMLElement]$xmlAppliances = $XMLDoc.CreateElement("appliances")
        $xmlRoot.appendChild($xmlAppliances) | out-null
        
        switch ($psCmdlet.ParameterSetName){

            "Cluster"  { $ResPoolId = $($cluster | get-resourcepool | ? { $_.parent.id -eq $cluster.id }).extensiondata.moref.value }
            "ResourcePool"  { $ResPoolId = $ResourcePool.extensiondata.moref.value }

        }

        Add-XmlElement -xmlRoot $xmlAppliances -xmlElementName "applianceSize" -xmlElementText $FormFactor

        [System.XML.XMLElement]$xmlAppliance = $XMLDoc.CreateElement("appliance")
        $xmlAppliances.appendChild($xmlAppliance) | out-null
        Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "resourcePoolId" -xmlElementText $ResPoolId
        Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "datastoreId" -xmlElementText $datastore.extensiondata.moref.value
        if ( $VMFolder ) { Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "vmFolderId" -xmlElementText $VMFolder.extensiondata.moref.value}

        #Create the features element.
        [System.XML.XMLElement]$xmlFeatures = $XMLDoc.CreateElement("features")
        $xmlRoot.appendChild($xmlFeatures) | out-null

        if ( $EnableHA ) {
          
            #Define the HA appliance
            [System.XML.XMLElement]$xmlAppliance = $XMLDoc.CreateElement("appliance")
            $xmlAppliances.appendChild($xmlAppliance) | out-null
            Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "resourcePoolId" -xmlElementText $ResPoolId
            Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "datastoreId" -xmlElementText $HAdatastore.extensiondata.moref.value
            if ( $VMFolder ) { Add-XmlElement -xmlRoot $xmlAppliance -xmlElementName "vmFolderId" -xmlElementText $VMFolder.extensiondata.moref.value}
            
            #configure HA
            [System.XML.XMLElement]$xmlHA = $XMLDoc.CreateElement("highAvailability")
            $xmlFeatures.appendChild($xmlHA) | out-null

            Add-XmlElement -xmlRoot $xmlHA -xmlElementName "enabled" -xmlElementText "true"
            if ( $PsBoundParameters.containsKey('HaDeadTime')) { 
                Add-XmlElement -xmlRoot $xmlHA -xmlElementName "declareDeadTime" -xmlElementText $HaDeadTime.ToString()
            }    

            if ( $PsBoundParameters.containsKey('HaVnic')) { 
                Add-XmlElement -xmlRoot $xmlHA -xmlElementName "vnic" -xmlElementText $HaVnic.ToString()
            }    
        }

        #Create the syslog element
        [System.XML.XMLElement]$xmlSyslog = $XMLDoc.CreateElement("syslog")
        $xmlFeatures.appendChild($xmlSyslog) | out-null
        Add-XmlElement -xmlRoot $xmlSyslog -xmlElementName "enabled" -xmlElementText $EnableSyslog.ToString().ToLower()
        
        if ( $PsBoundParameters.containsKey('SyslogProtocol')) { 
            Add-XmlElement -xmlRoot $xmlSyslog -xmlElementName "protocol" -xmlElementText $SyslogProtocol.ToString()
        }

        if ( $PsBoundParameters.containsKey('SyslogServer')) { 

            [System.XML.XMLElement]$xmlServerAddresses = $XMLDoc.CreateElement("serverAddresses")
            $xmlSyslog.appendChild($xmlServerAddresses) | out-null
            foreach ( $server in $SyslogServer ) { 
                Add-XmlElement -xmlRoot $xmlServerAddresses -xmlElementName "ipAddress" -xmlElementText $server.ToString()
            }
        }

        #Create the fw element 
        [System.XML.XMLElement]$xmlFirewall = $XMLDoc.CreateElement("firewall")
        $xmlFeatures.appendChild($xmlFirewall) | out-null
        Add-XmlElement -xmlRoot $xmlFirewall -xmlElementName "enabled" -xmlElementText $FwEnabled.ToString().ToLower()

        [System.XML.XMLElement]$xmlDefaultPolicy = $XMLDoc.CreateElement("defaultPolicy")
        $xmlFirewall.appendChild($xmlDefaultPolicy) | out-null
        Add-XmlElement -xmlRoot $xmlDefaultPolicy -xmlElementName "loggingEnabled" -xmlElementText $FwLoggingEnabled.ToString().ToLower()

        if ( $FwDefaultPolicyAllow ) { 
            Add-XmlElement -xmlRoot $xmlDefaultPolicy -xmlElementName "action" -xmlElementText "accept"
        } 
        else {
            Add-XmlElement -xmlRoot $xmlDefaultPolicy -xmlElementName "action" -xmlElementText "deny"
        }            

        #Rule Autoconfiguration
        if ( $AutoGenerateRules ) { 
            [System.XML.XMLElement]$xmlAutoConfig = $XMLDoc.CreateElement("autoConfiguration")
            $xmlRoot.appendChild($xmlAutoConfig) | out-null
            Add-XmlElement -xmlRoot $xmlAutoConfig -xmlElementName "enabled" -xmlElementText $AutoGenerateRules.ToString().ToLower()

        }

        #CLI Settings
        if ( $PsBoundParameters.ContainsKey('EnableSSH') -or $PSBoundParameters.ContainsKey('Password') ) {

            [System.XML.XMLElement]$xmlCliSettings = $XMLDoc.CreateElement("cliSettings")
            $xmlRoot.appendChild($xmlCliSettings) | out-null
            
            if ( $PsBoundParameters.ContainsKey('Password') ) { 
                Add-XmlElement -xmlRoot $xmlCliSettings -xmlElementName "userName" -xmlElementText $UserName
                Add-XmlElement -xmlRoot $xmlCliSettings -xmlElementName "password" -xmlElementText $Password

            }
            if ( $PsBoundParameters.ContainsKey('EnableSSH') ) { Add-XmlElement -xmlRoot $xmlCliSettings -xmlElementName "remoteAccess" -xmlElementText $EnableSsh.ToString().ToLower() }
        }

        #DNS Settings
        if ( $PsBoundParameters.ContainsKey('PrimaryDnsServer') -or $PSBoundParameters.ContainsKey('SecondaryDNSServer') -or $PSBoundParameters.ContainsKey('DNSDomainName') ) {

            [System.XML.XMLElement]$xmlDnsClient = $XMLDoc.CreateElement("dnsClient")
            $xmlRoot.appendChild($xmlDnsClient) | out-null
            
            if ( $PsBoundParameters.ContainsKey('PrimaryDnsServer') ) { Add-XmlElement -xmlRoot $xmlDnsClient -xmlElementName "primaryDns" -xmlElementText $PrimaryDnsServer }
            if ( $PsBoundParameters.ContainsKey('SecondaryDNSServer') ) { Add-XmlElement -xmlRoot $xmlDnsClient -xmlElementName "secondaryDns" -xmlElementText $SecondaryDNSServer }
            if ( $PsBoundParameters.ContainsKey('DNSDomainName') ) { Add-XmlElement -xmlRoot $xmlDnsClient -xmlElementName "domainName" -xmlElementText $DNSDomainName }
        }

        #Nics
        [System.XML.XMLElement]$xmlVnics = $XMLDoc.CreateElement("vnics")
        $xmlRoot.appendChild($xmlVnics) | out-null
        foreach ( $VnicSpec in $Interface ) {

            $import = $xmlDoc.ImportNode(($VnicSpec), $true)
            $xmlVnics.AppendChild($import) | out-null

        }


        # #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/4.0/edges"
        Write-Progress -activity "Creating Edge Services Gateway $Name"    
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
        Write-progress -activity "Creating Edge Services Gateway $Name" -completed
        $edgeId = $response.Headers.Location.split("/")[$response.Headers.Location.split("/").GetUpperBound(0)] 

        Get-NsxEdge -objectID $edgeId -connection $connection

    }
    end {}
}

function Repair-NsxEdge {

    <#
    .SYNOPSIS
    Resyncs or Redploys the specified NSX Edge Services Gateway appliance.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    The Repair-NsxEdge cmdlet allows a Resync or Redploy operation to be 
    performed on the specified Edges appliance.

    WARNING: Repair operations can cause connectivity loss.  Use with caution.

    .EXAMPLE
    Get-NsxEdge Edge01 | Repair-NsxEdge -Operation Redeploy

    Redeploys the ESG Edge01.

    .EXAMPLE
    Get-NsxEdge Edge01 | Repair-NsxEdge -Operation ReSync -Confirm:$false

    Resyncs the ESG Edge01 without confirmation.
    
    #>

    [CmdletBinding()]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            #The Edge object to be repaired.  Accepted on pipline
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$True)]
            #WARNING: This operation can potentially cause a datapath outage depending on the deployment architecture.
            #Specify the repair operation to be performed on the Edge.  
            #If ForceSync - The edge appliance is rebooted 
            #If Redeploy - The Edge is removed and redeployed (if the edge is HA this causes failover, otherwise, an outage.)
            [ValidateSet("ForceSync", "Redeploy")]
            [switch]$Operation,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {

    }

    process {

        $URI = "/api/4.0/edges/$($Edge.Id)?action=$($Operation.ToLower())"
               
        if ( $confirm ) { 
            $message  = "WARNING: An Edge Services Gateway $Operation is disruptive to Edge services and may cause connectivity loss depending on the deployment architecture."
            $question = "Proceed with Redeploy of Edge Services Gateway $($Edge.Name)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Repairing Edge Services Gateway $($Edge.Name)"
            $response = invoke-nsxwebrequest -method "post" -uri $URI -connection $connection
            write-progress -activity "Reparing Edge Services Gateway $($Edge.Name)" -completed
            Get-NsxEdge -objectId $($Edge.Id) -connection $connection
        }
    }

    end {}
}

function Set-NsxEdge {

    <#
    .SYNOPSIS
    Configures an existing NSX Edge Services Gateway Raw configuration.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs support interfaces connected to either VLAN backed port groups or NSX
    Logical Switches.

    Use the Set-NsxEdge to perform updates to the Raw XML config for an ESG
    to enable basic support for manipulating Edge features that arent supported
    by specific PowerNSX cmdlets.

    .EXAMPLE
    Disable the Edge Firewall on ESG Edge01

    PS C:\> $edge = Get-NsxEdge Edge01
    PS C:\> $edge.features.firewall.enabled = "false"
    PS C:\> $edge | Set-NsxEdge
    
    #>

    [CmdletBinding()]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {

    }

    process {

            
        #Clone the Edge Element so we can modify without barfing up the source object.
        $_Edge = $Edge.CloneNode($true)

        #Remove EdgeSummary...
        $edgeSummary = $_Edge.SelectSingleNode('descendant::edgeSummary')
        if ( $edgeSummary ) {
            $_Edge.RemoveChild($edgeSummary) | out-null
        }

        $URI = "/api/4.0/edges/$($_Edge.Id)"
        $body = $_Edge.OuterXml     
        
        if ( $confirm ) { 
            $message  = "Edge Services Gateway update will modify existing Edge configuration."
            $question = "Proceed with Update of Edge Services Gateway $($Edge.Name)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $($Edge.Name)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $($Edge.Name)" -completed
            Get-NsxEdge -objectId $($Edge.Id) -connection $connection
        }
    }

    end {}
}

function Remove-NsxEdge {

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
   
    PS C:\> Get-NsxEdge TestESG | Remove-NsxEdge
        -confirm:$false
    
    #>
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

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
            invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection| out-null
            write-progress -activity "Remove Edge Services Gateway $($Edge.Name)" -completed

        }
    }

    end {}
}

function Enable-NsxEdgeSsh { 

    <#
    .SYNOPSIS
    Enables the SSH server on an existing NSX Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    This cmdlet enables the ssh server on the specified Edge Services Gateway.  
    If rule autogeneration is configured on the Edge, the Edge firewall is 
    automatically configured to allow incoming connections.

    .EXAMPLE
    Enable SSH on edge Edge01

    C:\PS> Get-NsxEdge Edge01 | Enable-NsxEdgeSsh
    
    #>
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        $URI = "/api/4.0/edges/$($Edge.Edgesummary.ObjectId)/cliremoteaccess?enable=true"
        Write-Progress -activity "Enable SSH on Edge Services Gateway $($Edge.Name)"
        invoke-nsxrestmethod -method "post" -uri $URI -connection $connection| out-null
        write-progress -activity "Enable SSH on Edge Services Gateway $($Edge.Name)" -completed

    }

    end {}
}

function Disable-NsxEdgeSsh {

    <#
    .SYNOPSIS
    Disables the SSH server on an existing NSX Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    This cmdlet disables the ssh server on the specified Edge Services Gateway.  

    .EXAMPLE
    Disable SSH on edge Edge01

    C:\PS> Get-NsxEdge Edge01 | Disable-NsxEdgeSsh
    
    #>
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Disabling SSH will prevent remote SSH connections to this edge."
            $question = "Proceed with disabling SSH service on $($Edge.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/4.0/edges/$($Edge.Edgesummary.ObjectId)/cliremoteaccess?enable=false"
            Write-Progress -activity "Disable SSH on Edge Services Gateway $($Edge.Name)"
            invoke-nsxrestmethod -method "post" -uri $URI -connection $connection| out-null
            write-progress -activity "Disable SSH on Edge Services Gateway $($Edge.Name)" -completed
        }
    }

    end {}

}

#########
#########
# Edge NAT related functions
function Set-NsxEdgeNat {
    
    <#
    .SYNOPSIS
    Configures global NAT configuration of an existing NSX Edge Services 
    Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    NSX Edge provides network address translation (NAT) service to protect the 
    IP addresses of internal (private)  networks from the public network.

    You can configure NAT rules to provide access to services running on 
    privately addressed virtual machines.  There are two types of NAT rules that
    can be configured: SNAT and DNAT. 

    The Set-NsxEdgeNat cmdlet configures the global NAT configuration of
    the specified Edge Services Gateway.
    
    
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeNat $_ })]
            [System.Xml.XmlElement]$EdgeNat,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$Enabled,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        #Create private xml element
        $_EdgeNat = $EdgeNat.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeNat.edgeId
        $_EdgeNat.RemoveChild( $($_EdgeNat.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        if ( $PsBoundParameters.ContainsKey('Enabled') ) { 
            if ( $Enabled ) { 
                $_EdgeNat.enabled = 'true'
            }
            else {
                $_EdgeNat.enabled = 'false'
            }
        }

        $URI = "/api/4.0/edges/$($EdgeId)/nat/config"
        $body = $_EdgeNat.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "Edge Services Gateway NAT update will modify existing Edge configuration."
            $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxEdgeNat
        }
    }

    end {}
}

function Get-NsxEdgeNat {
    
    <#
    .SYNOPSIS
    Gets global NAT configuration of an existing NSX Edge Services 
    Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    NSX Edge provides network address translation (NAT) service to protect the 
    IP addresses of internal (private)  networks from the public network.

    You can configure NAT rules to provide access to services running on 
    privately addressed virtual machines.  There are two types of NAT rules that
    can be configured: SNAT and DNAT. 

    The Get-NsxEdgeNat cmdlet retreives the global NAT configuration of
    the specified Edge Services Gateway.

    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeNat = $Edge.features.nat.CloneNode($True)
        Add-XmlElement -xmlRoot $_EdgeNat -xmlElementName "edgeId" -xmlElementText $Edge.Id
        $_EdgeNat
    }

    end {}
}

function Get-NsxEdgeNatRule {
    
    <#
    .SYNOPSIS
    Retreives NAT rules from the spcified NSX Edge Services Gateway NAT 
    configuration.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    NSX Edge provides network address translation (NAT) service to protect the 
    IP addresses of internal (private)  networks from the public network.

    The Get-NsxEdgeNatRule cmdlet retreives the nat rules from the 
    nat configuration specified.
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeNat $_ })]
            [System.Xml.XmlElement]$EdgeNat,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$RuleId,
        [Parameter (Mandatory=$false)]
            [switch]$ShowInternal=$false    
        
    )
    
    begin {
    }

    process {
    
        #We append the Edge-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeNat = ($EdgeNat.CloneNode($True))
        $_EdgeNatRules = $_EdgeNat.SelectSingleNode('descendant::natRules')

        #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called natRule.
        If ( $_EdgeNatRules.SelectSingleNode('descendant::natRule')) { 

            $RuleCollection = $_EdgeNatRules.natRule
            if ( $PsBoundParameters.ContainsKey('RuleId')) {
                $RuleCollection = $RuleCollection | ? { $_.ruleId -eq $RuleId }
            }

            if ( -not $ShowInternal ) {
                $RuleCollection = $RuleCollection | ? { $_.ruleType -eq 'user' }
            }

            foreach ( $Rule in $RuleCollection ) { 
                Add-XmlElement -xmlRoot $Rule -xmlElementName "edgeId" -xmlElementText $EdgeNat.EdgeId
            }

            $RuleCollection
        }
    }

    end {}
}

function New-NsxEdgeNatRule {
    
    <#
    .SYNOPSIS
    Creates a new NAT rule and adds it to the specified ESGs NAT configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    NSX Edge provides network address translation (NAT) service to protect the 
    IP addresses of internal (private)  networks from the public network.

    The New-NsxEdgeNatRule cmdlet creates a new NAT rule in the nat 
    configuration specified.

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeNat $_ })]
            [System.Xml.XmlElement]$EdgeNat,       
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,200)]
            [int]$Vnic,                  
        [Parameter (Mandatory=$True)]
            [string]$OriginalAddress,
        [Parameter (Mandatory=$True)]
            [string]$TranslatedAddress,
        [Parameter (Mandatory=$True)]
            [Validateset("dnat","snat",ignorecase=$false)]
            [string]$action,
        [Parameter (Mandatory=$false)]
            [string]$Protocol,
        [Parameter (Mandatory=$False)]
            [string]$Description,   
        [Parameter (Mandatory=$False)]
            [switch]$LoggingEnabled=$false,
        [Parameter (Mandatory=$False)]
            [switch]$Enabled=$true, 
        [Parameter (Mandatory=$false)]
            [string]$OriginalPort,        
        [Parameter (Mandatory=$false)]
            [string]$TranslatedPort,
        [Parameter (Mandatory=$false)]
            [string]$IcmpType,
        [Parameter (Mandatory=$false)]
            [int]$AboveRuleId, 
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
        
    )
    
    begin {
    }

    process {

        #Store the edgeId and remove it from the XML as we need to post it...
        $EdgeId = $EdgeNat.edgeId
       
        #Create the new rules + rule element.
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        if ( -not $PsBoundParameters.ContainsKey('AboveRuleId') ) { 
            $Rules = $xmlDoc.CreateElement('natRules') 
            $Rule = $xmlDoc.CreateElement('natRule') 
            $xmlDoc.AppendChild($Rules) | out-null
            $Rules.AppendChild($Rule)  | out-null
            $URI = "/api/4.0/edges/$EdgeId/nat/config/rules"

        }
        else { 
            $Rule = $xmlDoc.CreateElement('natRule') 
            $xmlDoc.AppendChild($Rule) | out-null
            $URI = "/api/4.0/edges/$EdgeId/nat/config/rules?aboveRuleId=$($AboveRuleId.toString())"
        }

        #Append the mandatory props
        Add-XmlElement -xmlRoot $Rule -xmlElementName "vnic" -xmlElementText $Vnic.ToString()
        Add-XmlElement -xmlRoot $Rule -xmlElementName "originalAddress" -xmlElementText $OriginalAddress.ToString()
        Add-XmlElement -xmlRoot $Rule -xmlElementName "translatedAddress" -xmlElementText $TranslatedAddress.ToString()
        Add-XmlElement -xmlRoot $Rule -xmlElementName "action" -xmlElementText $Action.ToString()
        Add-XmlElement -xmlRoot $Rule -xmlElementName "loggingEnabled" -xmlElementText $LoggingEnabled.ToString().tolower()
        Add-XmlElement -xmlRoot $Rule -xmlElementName "enabled" -xmlElementText $Enabled.ToString().tolower()

        #Now the optional ones
        if ( $PsBoundParameters.ContainsKey("Protocol") ) { 
            Add-XmlElement -xmlRoot $Rule -xmlElementName "protocol" -xmlElementText $Protocol.ToString()
        }

        if ( $PsBoundParameters.ContainsKey("Description") ) { 
            Add-XmlElement -xmlRoot $Rule -xmlElementName "description" -xmlElementText $Description.ToString()
        }

        if ( $PsBoundParameters.ContainsKey("OriginalPort") ) { 
            Add-XmlElement -xmlRoot $Rule -xmlElementName "originalPort" -xmlElementText $OriginalPort.ToString()
        }

        if ( $PsBoundParameters.ContainsKey("TranslatedPort") ) { 
            Add-XmlElement -xmlRoot $Rule -xmlElementName "translatedPort" -xmlElementText $TranslatedPort.ToString()
        }
    
        if ( $PsBoundParameters.ContainsKey("IcmpType") ) { 
            Add-XmlElement -xmlRoot $Rule -xmlElementName "icmpType" -xmlElementText $IcmpType.ToString()
        }

        if ( -not $PsBoundParameters.ContainsKey('AboveRuleId') ) { 
            $body = $Rules.OuterXml 
        }
        else {
            $body = $Rule.OuterXml 
        }

        Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
        $ruleid = $response.Headers.location -replace "/api/4.0/edges/$edgeid/nat/config/rules/","" 
        Get-NsxEdge -objectId $EdgeId -connection $connection| Get-NsxEdgeNat | Get-NsxEdgeNatRule -ruleid $ruleid
    }

    end {}
}

function Remove-NsxEdgeNatRule {
    
    <#
    .SYNOPSIS
    Removes a NAT Rule from the specified ESGs NAT configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    NSX Edge provides network address translation (NAT) service to protect the 
    IP addresses of internal (private)  networks from the public network.

    The Remove-NsxEdgeNatRule cmdlet removes a specific NAT rule from the NAT
    configuration of the specified Edge Services Gateway.

    Rules to be removed can be constructed via a PoSH pipline filter outputing
    rule objects as produced by Get-NsxEdgeNatRule and passing them on the
    pipeline to Remove-NsxEdgeNatRule.

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeNatRule $_ })]
            [System.Xml.XmlElement]$NatRule,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the rule config for our Edge
        $edgeId = $NatRule.edgeId
        $ruleId = $NatRule.ruleId

    
        $URI = "/api/4.0/edges/$EdgeId/nat/config/rules/$ruleId"
       
            
        if ( $confirm ) { 
            $message  = "Edge Services Gateway nat rule update will modify existing Edge configuration."
            $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $EdgeId"
            $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
            write-progress -activity "Update Edge Services Gateway $EdgeId" -completed
        }
    }

    end {}
}



#########
#########
# Edge Certificate related functions

function Get-NsxEdgeCsr {
 
    <#
    .SYNOPSIS
    Gets SSL Certificate Signing Requests from an existing NSX Edge Services 
    Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    SSL Certificates are used by a variety of services within NSX, including SSL
    VPN and Load Balancing.

    Certificate Signing Requests define the subject details to be included in
    an SSL certificate and are the object that is signed by a Certificate 
    Authority in order to provide a valid certificate

    The Get-NsxEdgeCsr cmdlet retreives csr's definined on the specified Edge 
    Services Gateway, or with the specified objectId

    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="Edge")]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$true,ParameterSetName="objectId")]
            [string]$objectId,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {}

    process {

        if ( $PsBoundParameters.ContainsKey('objectId')) {

            #Just getting a single named csr by id group
            $URI = "/api/2.0/services/truststore/csr/$objectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response ) {
                if ( $response.SelectSingleNode('descendant::csr')) {
                    $response.csr
                }
            }
            
        }
        else {

            $URI = "/api/2.0/services/truststore/csr/scope/$($Edge.Id)"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection

            if ( $response ) { 
                if ( $response.SelectSingleNode('descendant::csrs/csr')) {
                    $response.csrs.csr
                }
            }
        }
    }

    end {}
}

function New-NsxEdgeCsr{

    <#
    .SYNOPSIS
    Creates a new SSL Certificate Signing Requests on an existing NSX Edge 
    Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    SSL Certificates are used by a variety of services within NSX, including SSL
    VPN and Load Balancing.

    Certificate Signing Requests define the subject details to be included in
    an SSL certificate and are the object that is signed by a Certificate 
    Authority in order to provide a valid certificate

    The New-NsxEdgeCsr cmdlet creates a new csr on the specified Edge Services 
    Gateway.

    
    #>
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge,                              
        [Parameter (Mandatory=$True)]
            [string]$CommonName,   
        [Parameter (Mandatory=$True)]
            [string]$Organisation,   
        [Parameter (Mandatory=$True)]
            [string]$Country,   
        [Parameter (Mandatory=$True)]
            [string]$OrganisationalUnit, 
        [Parameter (Mandatory=$False)]
            [ValidateSet(2048,3072)]
            [int]$Keysize=2048, 
        [Parameter (Mandatory=$False)]
            [ValidateSet("RSA", "DSA", IgnoreCase=$false )]
            [string]$Algorithm="RSA",
        [Parameter (Mandatory=$False)]
            [string]$Description, 
        [Parameter (Mandatory=$False)]
            [string]$Name,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {


        $edgeId = $Edge.Id

        #Create the new csr element and subject child element.
        [System.Xml.XmlDocument] $xmlDoc = New-Object System.Xml.XmlDocument
        $csr = $xmlDoc.CreateElement('csr')
        $subject = $xmlDoc.CreateElement('subject')
        $csr.AppendChild($subject) | out-null

        #Common Name
        $CnAttribute = $xmlDoc.CreateElement('attribute') 
        $subject.AppendChild($CnAttribute) | out-null
        Add-XmlElement -xmlRoot $CnAttribute -xmlElementName "key" -xmlElementText "CN"
        Add-XmlElement -xmlRoot $CnAttribute -xmlElementName "value" -xmlElementText $CommonName.ToString()

        #Organisation
        $OAttribute = $xmlDoc.CreateElement('attribute') 
        $subject.AppendChild($OAttribute) | out-null
        Add-XmlElement -xmlRoot $OAttribute -xmlElementName "key" -xmlElementText "O"
        Add-XmlElement -xmlRoot $OAttribute -xmlElementName "value" -xmlElementText $Organisation.ToString()

        #OU
        $OuAttribute = $xmlDoc.CreateElement('attribute') 
        $subject.AppendChild($OuAttribute) | out-null
        Add-XmlElement -xmlRoot $OuAttribute -xmlElementName "key" -xmlElementText "OU"
        Add-XmlElement -xmlRoot $OuAttribute -xmlElementName "value" -xmlElementText $OrganisationalUnit.ToString()

        #Country
        $CAttribute = $xmlDoc.CreateElement('attribute') 
        $subject.AppendChild($CAttribute) | out-null
        Add-XmlElement -xmlRoot $CAttribute -xmlElementName "key" -xmlElementText "C"
        Add-XmlElement -xmlRoot $CAttribute -xmlElementName "value" -xmlElementText $Country.ToString()

        #Algo
        Add-XmlElement -xmlRoot $csr -xmlElementName "algorithm" -xmlElementText $Algorithm.ToString()

        #KeySize
        Add-XmlElement -xmlRoot $csr -xmlElementName "keySize" -xmlElementText $Keysize.ToString()
       
        #Name
        if ( $PsBoundParameters.ContainsKey('Name')) { 
            Add-XmlElement -xmlRoot $csr -xmlElementName "name" -xmlElementText $Name.ToString()
        }

        #Description
        if ( $PsBoundParameters.ContainsKey('Description')) { 
            Add-XmlElement -xmlRoot $csr -xmlElementName "description" -xmlElementText $Description.ToString()
        }


        $URI = "/api/2.0/services/truststore/csr/$edgeId"
        $body = $csr.OuterXml 
       
        Write-Progress -activity "Update Edge Services Gateway $EdgeId"
        $response = Invoke-NsxRestMethod -method "post" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $EdgeId" -completed
        $response.csr
        
    }

    end {}
}

function Remove-NsxEdgeCsr{

    <#
    .SYNOPSIS
    Remvoves the specificed SSL Certificate Signing Request from an existing NSX
    Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    SSL Certificates are used by a variety of services within NSX, including SSL
    VPN and Load Balancing.

    Certificate Signing Requests define the subject details to be included in
    an SSL certificate and are the object that is signed by a Certificate 
    Authority in order to provide a valid certificate

    The Remove-NsxEdgeCsr cmdlet removes a csr from the specified Edge Services 
    Gateway.

    CSRs to be removed can be constructed via a PoSH pipline filter outputing
    csr objects as produced by Get-NsxEdgeCsr and passing them on the
    pipeline to Remove-NsxEdgeCsr.

    #>
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeCsr $_ })]
            [System.Xml.XmlElement]$Csr,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "CSR removal is permanent."
            $question = "Proceed with removal of CSR $($Csr.objectId)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/2.0/services/truststore/csr/$($csr.objectId)"
            
            Write-Progress -activity "Remove CSR $($Csr.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
            write-progress -activity "Remove CSR $($Csr.Name)" -completed

        }
    }

    end {}
}

function Get-NsxEdgeCertificate{
    
    <#
    .SYNOPSIS
    Gets SSL Certificate from an existing NSX Edge Services 
    Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    SSL Certificates are used by a variety of services within NSX, including SSL
    VPN and Load Balancing.

    SSL Certificates are used to provide encyption and trust validation for the 
    services that use them.

    The Get-NsxEdgeCertificate cmdlet retreives certificates definined on the 
    specified Edge Services Gateway, or with the specified objectId

    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,ParameterSetName="Edge")]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge,
        [Parameter (Mandatory=$true,ParameterSetName="objectId")]
            [string]$objectId,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {}

    process {

        if ( $PsBoundParameters.ContainsKey('objectId')) {

            #Just getting a single named csr by id group
            $URI = "/api/2.0/services/truststore/certificate/$objectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response ) {
                if ( $response.SelectSingleNode('descendant::certificate')) {
                    $response.certificate
                }
            }
            
        }
        else {

            $URI = "/api/2.0/services/truststore/certificate/scope/$($Edge.Id)"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection

            if ( $response ) { 
                if ( $response.SelectSingleNode('descendant::certificates/certificate')) {
                    $response.certificates.certificate
                }
            }
        }
    }

    end {}
}

function New-NsxEdgeSelfSignedCertificate{

    <#
    .SYNOPSIS
    Signs an NSX Edge Certificate Signing Request on an existing NSX Edge 
    Services Gateway to create a new Self Signed Certificate

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    SSL Certificates are used by a variety of services within NSX, including SSL
    VPN and Load Balancing.

    Certificate Signing Requests define the subject details to be included in
    an SSL certificate and are the object that is signed by a Certificate 
    Authority in order to provide a valid certificate.

    The New-NsxEdgeCertificate cmdlet signs an existing csr on the specified 
    Edge Services Gateway to create a Self Signed Certificate.
    
    #>
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeCSR $_ })]
            [System.Xml.XmlElement]$CSR,                              
        [Parameter (Mandatory=$False)]
            [int]$NumberOfDays=365,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {


        $edgeId = $Csr.Scope.Id


        $URI = "/api/2.0/services/truststore/csr/$($csr.objectId)?noOfDays=$NumberOfDays"
       
        Write-Progress -activity "Update Edge Services Gateway $EdgeId"
        $response = Invoke-NsxRestMethod -method "Put" -uri $URI -connection $connection
        write-progress -activity "Update Edge Services Gateway $EdgeId" -completed
        $response.Certificate
        
    }

    end {}
}

function Remove-NsxEdgeCertificate{
    
    <#
    .SYNOPSIS
    Remvoves the specificed SSL Certificate from an existing NSX Edge Services 
    Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    SSL Certificates are used by a variety of services within NSX, including SSL
    VPN and Load Balancing.

    SSL Certificates are used to provide encyption and trust validation for the 
    services that use them.

    The Remove-NsxEdgeCertificate cmdlet removes a certificate from the 
    specified Edge Services Gateway.

    Certificates to be removed can be constructed via a PoSH pipeline filter 
    outputing certificate objects as produced by Get-NsxEdgeCertificate and 
    passing them on the pipeline to Remove-NsxEdgeCertificate.

    #>
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeCertificate $_ })]
            [System.Xml.XmlElement]$Certificate,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {

    }

    process {

        if ( $confirm ) { 
            $message  = "Certificate removal is permanent."
            $question = "Proceed with removal of Certificate $($Certificate.objectId)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            $URI = "/api/2.0/services/truststore/certificate/$($certificate.objectId)"
            
            Write-Progress -activity "Remove Certificate $($Csr.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
            write-progress -activity "Remove Certificate $($Csr.Name)" -completed

        }
    }

    end {}
}


#########
#########
# Edge SSL VPN related functions

function Get-NsxSslVpn {
  
    <#
    .SYNOPSIS
    Gets global SSLVPN configuration of an existing NSX Edge Services 
    Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    SSL VPN allows remote users to connect securely to private networks behind an
    NSX Edge Services gateway and access servers and applications 
    in the private networks.

    The Get-NsxSslVpn cmdlet retreives the global SSLVPN configuration of
    the specified Edge Services Gateway.

    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeSslVpn = $Edge.features.sslvpnConfig.CloneNode($True)
        Add-XmlElement -xmlRoot $_EdgeSslVpn -xmlElementName "edgeId" -xmlElementText $Edge.Id
        $_EdgeSslVpn
    }

    end {}
}

function Set-NsxSslVpn {

    #To do, portal customisation, server ip config...

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$Enabled,
        [Parameter (Mandatory=$False)]
            [switch]$EnableCompression,
        [Parameter (Mandatory=$False)]
            [switch]$ForceVirtualKeyboard,
        [Parameter (Mandatory=$False)]
            [switch]$RandomizeVirtualkeys,
        [Parameter (Mandatory=$False)]
            [switch]$PreventMultipleLogon,
        [Parameter (Mandatory=$False)]
            [string]$ClientNotification,
        [Parameter (Mandatory=$False)]
            [switch]$EnablePublicUrlAccess,
        [Parameter (Mandatory=$False)]
            [int]$ForcedTimeout,
        [Parameter (Mandatory=$False)]
            [int]$SessionIdleTimeout,
        [Parameter (Mandatory=$False)]
            [switch]$ClientAutoReconnect,
        [Parameter (Mandatory=$False)]
            [switch]$ClientUpgradeNotification,
        [Parameter (Mandatory=$False)]
            [switch]$EnableLogging,
        [Parameter (Mandatory=$False)]
            [ValidateSet("emergency","alert","critical","error","warning","notice","info","debug")]
            [string]$LogLevel,
        [Parameter (Mandatory=$False)]
            [ipaddress]$ServerAddress,
        [Parameter (Mandatory=$False)]
            [int]$ServerPort,
        [Parameter (Mandatory=$False)]
            [string]$CertificateID,    
        [Parameter (Mandatory=$False)]
            [switch]$Enable_AES128_SHA,
        [Parameter (Mandatory=$False)]
            [switch]$Enable_AES256_SHA,
        [Parameter (Mandatory=$False)]
            [switch]$Enable_DES_CBC3_SHA,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

         #Create private xml element
        $_EdgeSslVpn = $SslVpn.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeSslVpn.edgeId

        $_EdgeSslVpn.RemoveChild( $($_EdgeSslVpn.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        if ( $PsBoundParameters.ContainsKey('Enabled')) { 
            $_EdgeSslVpn.enabled = $Enabled.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('EnableCompression')) { 
            $_EdgeSslVpn.advancedConfig.enableCompression = $EnableCompression.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('ForceVirtualKeyboard')) { 
            $_EdgeSslVpn.advancedConfig.ForceVirtualKeyboard = $ForceVirtualKeyboard.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('RandomizeVirtualkeys')) { 
            $_EdgeSslVpn.advancedConfig.RandomizeVirtualkeys = $RandomizeVirtualkeys.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('PreventMultipleLogon')) { 
            $_EdgeSslVpn.advancedConfig.PreventMultipleLogon = $PreventMultipleLogon.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('EnablePublicUrlAccess')) { 
            $_EdgeSslVpn.advancedConfig.EnablePublicUrlAccess = $EnablePublicUrlAccess.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('ClientNotification')) { 
            $_EdgeSslVpn.advancedConfig.ClientNotification = $ClientNotification.toString()
        }
        if ( $PsBoundParameters.ContainsKey('ForcedTimeout')) { 
            $_EdgeSslVpn.advancedConfig.timeout.ForcedTimeout = $ForcedTimeout.ToString()
        }
        if ( $PsBoundParameters.ContainsKey('SessionIdleTimeout')) { 
            $_EdgeSslVpn.advancedConfig.timeout.SessionIdleTimeout = $SessionIdleTimeout.ToString()
        }
        if ( $PsBoundParameters.ContainsKey('ClientAutoReconnect')) { 
            $_EdgeSslVpn.clientConfiguration.AutoReconnect = $ClientAutoReconnect.ToString()
        }
        if ( $PsBoundParameters.ContainsKey('ClientUpgradeNotification')) { 
            $_EdgeSslVpn.clientConfiguration.UpgradeNotification = $ClientUpgradeNotification.ToString().tolower()
        }
        if ( $PsBoundParameters.ContainsKey("EnableLogging")) { 
            $_EdgeSslVpn.logging.enable = $EnableLogging.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey("LogLevel")) { 
            $_EdgeSslVpn.logging.logLevel = $LogLevel.ToString().ToLower()
        }


        if ( $PsBoundParameters.ContainsKey("ServerAddress") -or
            $PsBoundParameters.ContainsKey("ServerPort") -or
            $PsBoundParameters.ContainsKey("Enable_DES_CBC3_SHA") -or
            $PsBoundParameters.ContainsKey("Enable_AES128_SHA") -or
            $PsBoundParameters.ContainsKey("Enable_AES256_SHA")) 
        {
            
            if ( -not $_EdgeSslVpn.SelectSingleNode('descendant::serverSettings') ) {
                [System.Xml.XmlElement]$serverSettings = $_EdgeSslVpn.ownerDocument.CreateElement('serverSettings') 
                $_EdgeSslVpn.AppendChild($serverSettings) | out-null
            }
            else { 
                [System.Xml.XmlElement]$ServerSettings = $_EdgeSslVpn.serverSettings
            }

            if ( $PsBoundParameters.ContainsKey("ServerAddress")) { 
                #Set ServerAddress
                if ( -not $serverSettings.SelectSingleNode('descendant::serverAddresses') ) {
                    [System.Xml.XmlElement]$serverAddresses = $_EdgeSslVpn.ownerDocument.CreateElement('serverAddresses') 
                    $serverSettings.AppendChild($serverAddresses) | out-null
                }
                else { 
                    [System.Xml.XmlElement]$serverAddresses = $serverSettings.serverAddresses
                }

                if ( -not $serverAddresses.SelectSingleNode('descendant::ipAddress') ) {
                    Add-XmlElement -xmlRoot $serverAddresses -xmlElementName "ipAddress" -xmlElementText $($ServerAddress.IPAddresstoString)
                }
                else {
                    $serverAddresses.ipAddress = [string]$ServerAddress.IPAddresstoString
                }
            }

            if ( $PsBoundParameters.ContainsKey("ServerPort")) { 
                
                if ( -not $serverSettings.SelectSingleNode('descendant::port') ) {
                    Add-XmlElement -xmlRoot $serverSettings -xmlElementName "port" -xmlElementText $ServerPort.ToString()
                }
                else {
                    $serverSettings.port = $ServerPort.ToString()
                }
            }

            if ( $PsBoundParameters.ContainsKey("CertificateID")) { 

                if ( -not $serverSettings.SelectSingleNode('descendant::certificateId') ) {
                    Add-XmlElement -xmlRoot $serverSettings -xmlElementName "certificateId" -xmlElementText $CertificateID
                }
                else {
                    $serverSettings.certificateId = $CertificateID
                }
            }

            if ( $PsBoundParameters.ContainsKey("Enable_DES_CBC3_SHA") -or
                $PsBoundParameters.ContainsKey("Enable_AES128_SHA") -or
                $PsBoundParameters.ContainsKey("Enable_AES256_SHA")) { 

                if ( -not $_EdgeSslVpn.serverSettings.SelectSingleNode('descendant::cipherList') ) {
                    [System.Xml.XmlElement]$cipherList = $serverSettings.ownerDocument.CreateElement('cipherList') 
                    $serverSettings.AppendChild($cipherList) | out-null
                }
                else { 
                    [System.Xml.XmlElement]$cipherList = $serverSettings.cipherList
                }

                if ( $PsBoundParameters.ContainsKey("Enable_DES_CBC3_SHA") ) { 
                    $cipher = $cipherList.SelectNodes("descendant::cipher") | ? { $_.'#Text' -eq 'DES-CBC3-SHA'}
                    if ( ( -not $cipher ) -and $Enable_DES_CBC3_SHA ) {
                        Add-XmlElement -xmlRoot $cipherList -xmlElementName "cipher" -xmlElementText "DES-CBC3-SHA"
                    }
                    elseif ( $cipher -and ( -not $Enable_DES_CBC3_SHA )) { 
                        $cipherList.RemoveChild( $cipher )| out-null
                    }
                }


                if ( $PsBoundParameters.ContainsKey("Enable_AES128_SHA") ) { 
                    $cipher = $cipherList.SelectNodes("descendant::cipher") | ? { $_.'#Text' -eq 'AES128-SHA'}
                    if ( ( -not $cipher ) -and $Enable_AES128_SHA ) {
                        Add-XmlElement -xmlRoot $cipherList -xmlElementName "cipher" -xmlElementText "AES128-SHA"
                    }
                    elseif ( $cipher -and ( -not $Enable_AES128_SHA )) { 
                        $CipherList.RemoveChild( $cipher )| out-null
                    }
                }

                if ( $PsBoundParameters.ContainsKey("Enable_AES256_SHA") ) { 
                    $cipher = $cipherList.SelectNodes("descendant::cipher") | ? { $_.'#Text' -eq 'AES256-SHA'}
                    if ( ( -not $cipher ) -and $Enable_AES256_SHA ) {
                        Add-XmlElement -xmlRoot $cipherList -xmlElementName "cipher" -xmlElementText "AES256-SHA"
                    }
                    elseif ( $cipher -and ( -not $Enable_AES256_SHA )) { 
                        $CipherList.RemoveChild( $cipher ) | out-null
                    }
                }
            }
        }

        $URI = "/api/4.0/edges/$EdgeId/sslvpn/config"
        $body = $_EdgeSslVpn.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "Edge Services Gateway SSL VPN update will modify existing Edge configuration."
            $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxSslVpn
        }
    }

    end {}
}

function New-NsxSslVpnAuthServer {



    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$False)]
            [ValidateRange(1,63)]
            [int]$PasswordMinLength=1,
        [Parameter (Mandatory=$False)]
            [ValidateRange(1,63)]
            [int]$PasswordMaxLength=63,
        [Parameter (Mandatory=$False)]
            [ValidateRange(1,63)]
            [int]$PasswordMinAlphabet=0,
        [Parameter (Mandatory=$False)]
            [ValidateRange(1,63)]
            [int]$PasswordMinDigit=0,
        [Parameter (Mandatory=$False)]
            [ValidateRange(1,63)]
            [int]$PasswordMinSpecialChar=0,
        [Parameter (Mandatory=$False)]
            [switch]$PasswordAllowUsernameInPassword=$false,
        [Parameter (Mandatory=$False)]
            [int]$PasswordLifetime=30,
        [Parameter (Mandatory=$False)]
            [int]$PasswordExpiryNotificationTime=25,
        [Parameter (Mandatory=$False)]
            [int]$PasswordLockoutRetryCount=3,
        [Parameter (Mandatory=$False)]
            [int]$PasswordLockoutRetryDuration=2,
        [Parameter (Mandatory=$False)]
            [int]$PasswordLockoutDuration=2,
        [Parameter (Mandatory=$False)]
            [ValidateSet("Local")]
            [string]$ServerType="Local",
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    Begin{}

    Process {

        #Create private xml element
        $_EdgeSslVpn = $SslVpn.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeSslVpn.edgeId

        $_EdgeSslVpn.RemoveChild( $($_EdgeSslVpn.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Get the AuthServers node, and create a new PrimaryAuthServer in it.
        $PrimaryAuthServers = $_EdgeSslVpn.SelectSingleNode('descendant::authenticationConfiguration/passwordAuthentication/primaryAuthServers')

        Switch ( $ServerType ) { 

            "Local" { 

                #Like highlander, there can be only one! :)

                if ( $PrimaryAuthServers.SelectsingleNode('descendant::localAuthServer') ) { 

                    throw "Local Authentication source already exists.  Use Set-NsxEdgeSslVpnAuthServer to modify an existing server."
                }
                else { 

                    #Construct the Local Server XML Element.  
                    $AuthServer = $PrimaryAuthServers.ownerDocument.CreateElement('com.vmware.vshield.edge.sslvpn.dto.LocalAuthServerDto')
                    $PrimaryAuthServers.AppendChild($AuthServer) | out-null

                    $PasswordPolicy = $AuthServer.ownerDocument.CreateElement('passwordPolicy')
                    $AccountLockoutPolicy = $AuthServer.ownerDocument.CreateElement('accountLockoutPolicy')
                    $AuthServer.AppendChild($PasswordPolicy) | out-null
                    $AuthServer.AppendChild($AccountLockoutPolicy) | out-null

                    #No need to check if user specified as we are defaulting to the documented defaults for all props as per API guide.

                    Add-XmlElement -xmlRoot $PasswordPolicy -xmlElementName "minLength" -xmlElementText $PasswordMinLength.ToString()
                    Add-XmlElement -xmlRoot $PasswordPolicy -xmlElementName "maxLength" -xmlElementText $PasswordMaxLength.ToString()
                    Add-XmlElement -xmlRoot $PasswordPolicy -xmlElementName "minAlphabets" -xmlElementText $PasswordMinAlphabet.ToString()
                    Add-XmlElement -xmlRoot $PasswordPolicy -xmlElementName "minDigits" -xmlElementText $PasswordMinDigit.ToString()
                    Add-XmlElement -xmlRoot $PasswordPolicy -xmlElementName "minSpecialChar" -xmlElementText $PasswordMinSpecialChar.ToString()
                    Add-XmlElement -xmlRoot $PasswordPolicy -xmlElementName "allowUserIdWithinPassword" -xmlElementText $PasswordAllowUsernameInPassword.ToString()
                    Add-XmlElement -xmlRoot $PasswordPolicy -xmlElementName "passwordLifeTime" -xmlElementText $PasswordLifetime.ToString()
                    Add-XmlElement -xmlRoot $PasswordPolicy -xmlElementName "expiryNotification" -xmlElementText $PasswordExpiryNotificationTime.ToString()
                    Add-XmlElement -xmlRoot $AccountLockoutPolicy -xmlElementName "retryCount" -xmlElementText $PasswordLockoutRetryCount.ToString()
                    Add-XmlElement -xmlRoot $AccountLockoutPolicy -xmlElementName "retryDuration" -xmlElementText $PasswordLockoutRetryDuration.ToString()
                    Add-XmlElement -xmlRoot $AccountLockoutPolicy -xmlElementName "lockoutDuration" -xmlElementText $PasswordLockoutDuration.ToString()
                }
            }
            default { Throw "Server type not supported." }
        }

        $URI = "/api/4.0/edges/$EdgeId/sslvpn/config"
        $body = $_EdgeSslVpn.OuterXml 
       
        Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed

        #Totally cheating here while we only support local auth server. Will have to augment this later...
        Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxSslVpn | Get-NsxSslVpnAuthServer -Servertype local
    }

    end{}
}

function Get-NsxSslVpnAuthServer {
  
    <#
    .SYNOPSIS
    Gets SSLVPN Authentication Servers from an existing NSX Edge Services 
    Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    SSL VPN allows remote users to connect securely to private networks behind an
    NSX Edge Services gateway and access servers and applications 
    in the private networks.

    Authentication Servers define how the SSL VPN server authenticates user
    connections

    The Get-NsxSslVpnAuthServer cmdlet retreives the SSL VPN authentication 
    sources configured on the specified Edge Services Gateway.

    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$false,Position=1)]
            [ValidateSet("local",IgnoreCase=$false)]
            [string]$ServerType
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeSslVpn = $SslVpn.CloneNode($True)
        $PrimaryAuthenticationServers = $_EdgeSslVpn.SelectNodes('descendant::authenticationConfiguration/passwordAuthentication/primaryAuthServers/*')
        if ( $PrimaryAuthenticationServers ) { 

            foreach ( $Server in $PrimaryAuthenticationServers ) { 
                Add-XmlElement -xmlRoot $Server -xmlElementName "edgeId" -xmlElementText $SslVpn.EdgeId
                if ( $PsBoundParameters.ContainsKey('ServerType')) { 
                    $Server | ? { $_.authServerType -eq $ServerType }
                } else {
                    $Server
                }
            }
        }
        $SecondaryAuthenticationServers = $_EdgeSslVpn.SelectNodes('descendant::authenticationConfiguration/passwordAuthentication/secondaryAuthServers/*')
        if ( $SecondaryAuthenticationServers ) { 

            foreach ( $Server in $SecondaryAuthenticationServers ) { 
                Add-XmlElement -xmlRoot $Server -xmlElementName "edgeId" -xmlElementText $SslVpn.EdgeId
                $Server
            }
        }
    }

    end {}
}

function New-NsxSslVpnUser{

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [string]$UserName,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [string]$Password,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [string]$FirstName,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [string]$LastName,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [string]$Description,
        [Parameter (Mandatory=$False)]
            [switch]$DisableUser=$False,
        [Parameter (Mandatory=$False)]
            [switch]$PasswordNeverExpires=$False,
        [Parameter (Mandatory=$False)]
            [switch]$AllowPasswordChange=$True,
        [Parameter (Mandatory=$False)]
            [switch]$ForcePasswordChangeOnNextLogin,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    Begin{}

    Process {

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $SslVpn.edgeId

        #Create the user element
        $User = $SslVpn.ownerDocument.CreateElement('user')

        #Mandatory and defaults
        Add-XmlElement -xmlRoot $User -xmlElementName "userId" -xmlElementText $UserName.ToString()
        Add-XmlElement -xmlRoot $User -xmlElementName "password" -xmlElementText $Password.ToString()
        Add-XmlElement -xmlRoot $User -xmlElementName "disableUserAccount" -xmlElementText $DisableUser.ToString().ToLower()
        Add-XmlElement -xmlRoot $User -xmlElementName "passwordNeverExpires" -xmlElementText $PasswordNeverExpires.ToString().ToLower()
        if ( $AllowPasswordChange ) {
            $xmlAllowChangePassword = $User.OwnerDocument.CreateElement('allowChangePassword')
            $User.AppendChild($xmlAllowChangePassword) | out-null
            Add-XmlElement -xmlRoot $xmlAllowChangePassword -xmlElementName "changePasswordOnNextLogin" -xmlElementText $AllowPasswordChange.ToString().ToLower()
        }
        elseif ( $ForcePasswordChangeOnNextLogin ) { 
            throw "Must enable allow password change to force user to change on next logon."
        }

        # Optionals...
        if ( $PsBoundParameters.ContainsKey('FirstName')) {
            Add-XmlElement -xmlRoot $User -xmlElementName "firstName" -xmlElementText $FirstName.ToString()
        }
        if ( $PsBoundParameters.ContainsKey('LastName')) {
            Add-XmlElement -xmlRoot $User -xmlElementName "lastName" -xmlElementText $LastName.ToString()
        }
        if ( $PsBoundParameters.ContainsKey('Description')) {
            Add-XmlElement -xmlRoot $User -xmlElementName "description" -xmlElementText $Description.ToString()
        }

        $URI = "/api/4.0/edges/$edgeId/sslvpn/config/auth/localserver/users/"
        $body = $User.OuterXml 
       
        Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed

        Get-NsxEdge -objectId $EdgeId -connection $connection| Get-NsxSslVpn | Get-NsxSslVpnUser -UserName $UserName
    }
}

function Get-NsxSslVpnUser {

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$false,Position=1)]
            [string]$UserName
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeSslVpn = $SslVpn.CloneNode($True)

        $Users = $_EdgeSslVpn.SelectNodes('descendant::users/*')
        if ( $Users ) { 
            foreach ( $User in $Users ) { 
                Add-XmlElement -xmlRoot $User -xmlElementName "edgeId" -xmlElementText $SslVpn.EdgeId
                if ( $PsBoundParameters.ContainsKey('UserName')) { 
                    $User | ? { $_.UserId -eq $UserName }
                } 
                else {
                    $User
                }
            }
        }
    }

    end {}
}

function Remove-NsxSslVpnUser {
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpnUser $_ })]
            [System.Xml.XmlElement]$SslVpnUser,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our Edge
        $edgeId = $SslVpnUser.edgeId
        $userId = $SslVpnUser.objectId

        $URI = "/api/4.0/edges/$edgeId/sslvpn/config/auth/localserver/users/$userId"
   
        if ( $confirm ) { 
            $message  = "User deletion is permanent."
            $question = "Proceed with deletion of user $($SslVpnUser.UserId) ($($userId)) from edge $($edgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Deleting user $($SslVpnUser.UserId) ($($userId)) from edge $edgeId"
            $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
            write-progress -activity "Deleting user $($SslVpnUser.UserId) ($($userId)) from edge $edgeId" -completed
        }
    }

    end {}
}

function New-NsxSslVpnIpPool {

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [string]$IpRange,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [ipaddress]$Netmask,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [ipaddress]$Gateway,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [ipAddress]$PrimaryDnsServer,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [ipAddress]$SecondaryDnsServer,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [string]$DnsSuffix,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [ipAddress]$WinsServer,
        [Parameter (Mandatory=$False)]
            [switch]$Enabled=$True,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    Begin{}

    Process {

        #Store the edgeId.
        $edgeId = $SslVpn.edgeId

        #Create the ipAddressPool element
        $IpAddressPool = $SslVpn.ownerDocument.CreateElement('ipAddressPool')

        #Mandatory and defaults
        Add-XmlElement -xmlRoot $IpAddressPool -xmlElementName "ipRange" -xmlElementText $IpRange.ToString()
        Add-XmlElement -xmlRoot $IpAddressPool -xmlElementName "netmask" -xmlElementText $($NetMask.IpAddressToString)
        Add-XmlElement -xmlRoot $IpAddressPool -xmlElementName "gateway" -xmlElementText $($Gateway.IpAddressToString)

        # Optionals...
        if ( $PsBoundParameters.ContainsKey('Description')) {      
                Add-XmlElement -xmlRoot $IpAddressPool -xmlElementName "description" -xmlElementText $Description.ToString()
        }
        if ( $PsBoundParameters.ContainsKey('PrimaryDNSServer')) {
            Add-XmlElement -xmlRoot $IpAddressPool -xmlElementName "primaryDns" -xmlElementText $($PrimaryDnsServer.IpAddressToString)
        }
        if ( $PsBoundParameters.ContainsKey('SecondaryDNSServer')) {
            Add-XmlElement -xmlRoot $IpAddressPool -xmlElementName "secondaryDns" -xmlElementText $($SecondaryDNSServer.IpAddressToString)
        }
        if ( $PsBoundParameters.ContainsKey('DnsSuffix')) {
            Add-XmlElement -xmlRoot $IpAddressPool -xmlElementName "dnsSuffix" -xmlElementText $DnsSuffix.ToString()
        }
        if ( $PsBoundParameters.ContainsKey('WinsServer')) {
            Add-XmlElement -xmlRoot $IpAddressPool -xmlElementName "winsServer" -xmlElementText $($WinsServer.IpAddressToString)
        }

        if ( -not $Enabled ) { 
            Add-XmlElement -xmlRoot $IpAddressPool -xmlElementName "enabled" -xmlElementText "false"
        }


        $URI = "/api/4.0/edges/$edgeId/sslvpn/config/client/networkextension/ippools/"
        $body = $IpAddressPool.OuterXml 
       
        Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed

        Get-NsxEdge -objectId $EdgeId -connection $connection| Get-NsxSslVpn | Get-NsxSslVpnIpPool -IpRange $IpRange
    }
}


function Get-NsxSslVpnIpPool {

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$false,Position=1)]
            [string]$IpRange
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeSslVpn = $SslVpn.CloneNode($True)

        $IpPools = $_EdgeSslVpn.SelectNodes('descendant::ipAddressPools/*')
        if ( $IpPools ) { 
            foreach ( $IpPool in $IpPools ) { 
                Add-XmlElement -xmlRoot $IpPool -xmlElementName "edgeId" -xmlElementText $SslVpn.EdgeId
                if ( $PsBoundParameters.ContainsKey('IpRange')) { 
                    $IpPool | ? { $_.ipRange -eq $IpRange }
                } 
                else {
                    $IpPool
                }
            }
        }
    }

    end {}
}


function Remove-NsxSslVpnIpPool {
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpnIpPool $_ })]
            [System.Xml.XmlElement]$SslVpnIpPool,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        $edgeId = $SslVpnIpPool.edgeId
        $poolId = $SslVpnIpPool.objectId

        $URI = "/api/4.0/edges/$edgeId/sslvpn/config/client/networkextension/ippools/$poolId"
   
        if ( $confirm ) { 
            $message  = "Ip Pool deletion is permanent."
            $question = "Proceed with deletion of pool $($SslVpnIpPool.IpRange) ($($poolId)) from edge $($edgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Deleting pool $($SslVpnIpPool.IpRange) ($($poolId)) from edge $edgeId"
            $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
            write-progress -activity "Deleting pool $($SslVpnIpPool.IpRange) ($($poolId)) from edge $edgeId" -completed
        }
    }

    end {}
}


function New-NsxSslVpnPrivateNetwork {

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [string]$Network,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [string]$Ports,
        [Parameter (Mandatory=$False)]
            [switch]$BypassTunnel=$False,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [string]$Description,
        [Parameter (Mandatory=$False)]
            [switch]$OptimiseTcp=$True,
        [Parameter (Mandatory=$False)]
            [switch]$Enabled=$True,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    Begin{}

    Process {

        #Store the edgeId.
        $edgeId = $SslVpn.edgeId

        #Create the ipAddressPool element
        $PrivateNetwork = $SslVpn.ownerDocument.CreateElement('privateNetwork')

        #Mandatory and defaults
        Add-XmlElement -xmlRoot $PrivateNetwork -xmlElementName "network" -xmlElementText $Network.ToString()
        
        # Optionals...
        if ( $PsBoundParameters.ContainsKey('Description')) {      
                Add-XmlElement -xmlRoot $PrivateNetwork -xmlElementName "description" -xmlElementText $Description.ToString()
        }
        if ( -not $BypassTunnel ) {
            [system.Xml.XmlElement]$sendOverTunnel = $PrivateNetwork.ownerDocument.CreateElement('sendOverTunnel')
            $PrivateNetwork.AppendChild($SendOverTunnel) | out-null
            Add-XmlElement -xmlRoot $SendOverTunnel -xmlElementName "optimize" -xmlElementText $OptimiseTcp.ToString().ToLower()
            if ( $PsBoundParameters.ContainsKey('Ports')) { 
                Add-XmlElement -xmlRoot $SendOverTunnel -xmlElementName "ports" -xmlElementText $Ports.ToString()
            }
        }
        elseif ( $OptimiseTcp ) { 
            write-warning "TCP Optimisation is not applicable when tunnel bypass is enabled."
        }
        elseif ( $PsBoundParameters.ContainsKey('Ports') ) { 
            throw "Unable to specify ports when tunnel bypass is enabled."
        }

        if ( -not $Enabled ) { 
            Add-XmlElement -xmlRoot $PrivateNetwork -xmlElementName "enabled" -xmlElementText "false"
        }


        $URI = "/api/4.0/edges/$edgeId/sslvpn/config/client/networkextension/privatenetworks"
        $body = $PrivateNetwork.OuterXml 
       
        Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed

        Get-NsxEdge -objectId $EdgeId -connection $connection| Get-NsxSslVpn | Get-NsxSslVpnPrivateNetwork -Network $Network
    }
}


function Get-NsxSslVpnPrivateNetwork {

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$false,Position=1)]
            [string]$Network
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeSslVpn = $SslVpn.CloneNode($True)

        $Networks = $_EdgeSslVpn.SelectNodes('descendant::privateNetworks/*')
        if ( $Networks ) { 
            foreach ( $Net in $Networks ) { 
                Add-XmlElement -xmlRoot $Net -xmlElementName "edgeId" -xmlElementText $SslVpn.EdgeId
                if ( $PsBoundParameters.ContainsKey('Network')) { 
                    $Net | ? { $_.Network -eq $Network }
                } 
                else {
                    $Net
                }
            }
        }
    }

    end {}
}


function Remove-NsxSslVpnPrivateNetwork {
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpnPrivateNetwork $_ })]
            [System.Xml.XmlElement]$SslVpnPrivateNetwork,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection 
    )
    
    begin {
    }

    process {

        $edgeId = $SslVpnPrivateNetwork.edgeId
        $networkId = $SslVpnPrivateNetwork.objectId

        $URI = "/api/4.0/edges/$edgeId/sslvpn/config/client/networkextension/privatenetworks/$networkId"
   
        if ( $confirm ) { 
            $message  = "Private network deletion is permanent."
            $question = "Proceed with deletion of network $($SslVpnPrivateNetwork.Network) ($($networkId)) from edge $($edgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Deleting network $($SslVpnPrivateNetwork.Network) ($($networkId)) from edge $edgeId"
            $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
            write-progress -activity "Deleting network $($SslVpnPrivateNetwork.Network) ($($networkId)) from edge $edgeId" -completed
        }
    }

    end {}
}


function New-NsxSslVpnClientInstallationPackage {

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$True)]
            [string]$Name,
        [Parameter (Mandatory=$True)]
            [ipAddress[]]$Gateway,
        [Parameter (Mandatory=$False)]
            [ValidateRange(1,65535)]
            [Int]$Port,
        [Parameter (Mandatory=$False)]
            [switch]$CreateLinuxClient,
        [Parameter (Mandatory=$False)]
            [switch]$CreateMacClient,
        [Parameter (Mandatory=$False)]
            [string]$Description, 
        [Parameter (Mandatory=$False)]
            [switch]$StartClientOnLogon,
        [Parameter (Mandatory=$False)]
            [switch]$HideSystrayIcon,
        [Parameter (Mandatory=$False)]
            [switch]$RememberPassword,
        [Parameter (Mandatory=$False)]
            [switch]$SilentModeOperation,
        [Parameter (Mandatory=$False)]
            [switch]$SilentModeInstallation,
        [Parameter (Mandatory=$False)]
            [switch]$HideNetworkAdaptor,
        [Parameter (Mandatory=$False)]
            [switch]$CreateDesktopIcon,
        [Parameter (Mandatory=$False)]
            [switch]$EnforceServerSecurityCertValidation,
        [Parameter (Mandatory=$False)]
            [switch]$Enabled=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    Begin{}

    Process {

        #Store the edgeId.
        $edgeId = $SslVpn.edgeId

        #Create the ipAddressPool element
        $clientInstallPackage = $SslVpn.ownerDocument.CreateElement('clientInstallPackage')
 
        #gatewayList element
        [system.Xml.XmlElement]$gatewayList = $clientInstallPackage.ownerDocument.CreateElement('gatewayList')
        $clientInstallPackage.AppendChild($gatewayList) | out-null
        foreach ($gatewayitem in $gateway) { 
            [system.Xml.XmlElement]$gatewayNode = $gatewayList.ownerDocument.CreateElement('gateway')
            $gatewayList.AppendChild($gatewayNode) | out-null
            Add-XmlElement -xmlRoot $gatewayNode -xmlElementName "hostName" -xmlElementText $gatewayitem
            if ( $PSBoundParameters.ContainsKey('port')) { 
                Add-XmlElement -xmlRoot $gatewayNode -xmlElementName "port" -xmlElementText $Port
            }
        }


        #Mandatory and defaults
        Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "profileName" -xmlElementText $Name
        Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "enabled" -xmlElementText $Enabled.ToString().ToLower()

        # Optionals...
        if ( $PsBoundParameters.ContainsKey('StartClientOnLogon')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "startClientOnLogon" -xmlElementText $StartClientOnLogon.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('hideSystrayIcon')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "hideSystrayIcon" -xmlElementText $hideSystrayIcon.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('rememberPassword')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "rememberPassword" -xmlElementText $rememberPassword.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('silentModeOperation')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "silentModeOperation" -xmlElementText $silentModeOperation.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('silentModeInstallation')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "silentModeInstallation" -xmlElementText $silentModeInstallation.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('hideNetworkAdaptor')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "hideNetworkAdaptor" -xmlElementText $hideNetworkAdaptor.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('createDesktopIcon')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "createDesktopIcon" -xmlElementText $createDesktopIcon.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('enforceServerSecurityCertValidation')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "enforceServerSecurityCertValidation" -xmlElementText $enforceServerSecurityCertValidation.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('createLinuxClient')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "createLinuxClient" -xmlElementText $createLinuxClient.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('createMacClient')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "createMacClient" -xmlElementText $createMacClient.ToString().ToLower()
        }
        if ( $PsBoundParameters.ContainsKey('description')) {      
                Add-XmlElement -xmlRoot $clientInstallPackage -xmlElementName "description" -xmlElementText $description.ToString().ToLower()
        }


        $URI = "/api/4.0/edges/$edgeId/sslvpn/config/client/networkextension/installpackages/"
        $body = $clientInstallPackage.OuterXml 
       
        Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed

        Get-NsxEdge -objectId $EdgeId -connection $connection| Get-NsxSslVpn | Get-NsxSslVpnClientInstallationPackage -Name $Name
    }
}


function Get-NsxSslVpnClientInstallationPackage {

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpn $_ })]
            [System.Xml.XmlElement]$SslVpn,
        [Parameter (Mandatory=$false,Position=1)]
            [string]$Name
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeSslVpn = $SslVpn.CloneNode($True)

        $Packages = $_EdgeSslVpn.SelectNodes('descendant::clientInstallPackages/*')
        if ( $Packages ) { 
            foreach ( $Package in $Packages ) { 
                Add-XmlElement -xmlRoot $Package -xmlElementName "edgeId" -xmlElementText $SslVpn.EdgeId
                if ( $PsBoundParameters.ContainsKey('Name')) { 
                    $Package | ? { $_.ProfileName -eq $Name }
                } 
                else {
                    $Package
                }
            }
        }
    }

    end {}
}


function Remove-NsxSslVpnClientInstallationPackage {
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeSslVpnClientPackage $_ })]
            [System.Xml.XmlElement]$EdgeSslVpnClientPackage,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection 
    )
    
    begin {
    }

    process {

        $edgeId = $EdgeSslVpnClientPackage.edgeId
        $packageId = $EdgeSslVpnClientPackage.objectId

        $URI = "/api/4.0/edges/$edgeId/sslvpn/config/client/networkextension/installpackages/$packageId"
   
        if ( $confirm ) { 
            $message  = "Installation Package deletion is permanent."
            $question = "Proceed with deletion of installation package $($EdgeSslVpnClientPackage.profileName) ($($packageId)) from edge $($edgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Deleting install package $($EdgeSslVpnClientPackage.profileName) ($($packageId)) from edge $edgeId"
            $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
            write-progress -activity "Deleting install package $($EdgeSslVpnClientPackage.profileName) ($($packageId)) from edge $edgeId" -completed
        }
    }

    end {}
}


#########
#########
# Edge Routing related functions

function Set-NsxEdgeRouting {
    
    <#
    .SYNOPSIS
    Configures global routing configuration of an existing NSX Edge Services 
    Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Set-NsxEdgeRouting cmdlet configures the global routing configuration of
    the specified Edge Services Gateway.
    
    .EXAMPLE
    Configure the default route of the ESG
    
    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Set-NsxEdgeRouting -DefaultGatewayVnic 0 -DefaultGatewayAddress 10.0.0.101

    .EXAMPLE
    Enable ECMP
    
    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableECMP
    

    .EXAMPLE
    Enable OSPF

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOSPF -RouterId 1.1.1.1

    .EXAMPLE
    Enable BGP
    
    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdge | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableBGP -RouterId 1.1.1.1 -LocalAS 1234

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Set-NsxEdgeRouting -EnableOspfRouteRedistribution:$false -Confirm:$false

    Disable OSPF Route Redistribution without confirmation.
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$EnableOspf,
        [Parameter (Mandatory=$False)]
            [switch]$EnableBgp,
        [Parameter (Mandatory=$False)]
            [IpAddress]$RouterId,
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,65535)]
            [int]$LocalAS,
        [Parameter (Mandatory=$False)]
            [switch]$EnableEcmp,
        [Parameter (Mandatory=$False)]
            [switch]$EnableOspfRouteRedistribution,
        [Parameter (Mandatory=$False)]
            [switch]$EnableBgpRouteRedistribution,
        [Parameter (Mandatory=$False)]
            [switch]$EnableLogging,
        [Parameter (Mandatory=$False)]
            [ValidateSet("emergency","alert","critical","error","warning","notice","info","debug")]
            [string]$LogLevel,
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,200)]
            [int]$DefaultGatewayVnic,        
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,9128)]
            [int]$DefaultGatewayMTU,        
        [Parameter (Mandatory=$False)]
            [string]$DefaultGatewayDescription,       
        [Parameter (Mandatory=$False)]
            [ipAddress]$DefaultGatewayAddress,
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,255)]
            [int]$DefaultGatewayAdminDistance,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection  

    )
    
    begin {

    }

    process {

        #Create private xml element
        $_EdgeRouting = $EdgeRouting.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeRouting.edgeId
        $_EdgeRouting.RemoveChild( $($_EdgeRouting.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        if ( $PsBoundParameters.ContainsKey('EnableOSPF') -or $PsBoundParameters.ContainsKey('EnableBGP') ) { 
            $xmlGlobalConfig = $_EdgeRouting.routingGlobalConfig
            $xmlRouterId = $xmlGlobalConfig.SelectSingleNode('descendant::routerId')
            if ( $EnableOSPF -or $EnableBGP ) {
                if ( -not ($xmlRouterId -or $PsBoundParameters.ContainsKey("RouterId"))) {
                    #Existing config missing and no new value set...
                    throw "RouterId must be configured to enable dynamic routing"
                }

                if ($PsBoundParameters.ContainsKey("RouterId")) {
                    #Set Routerid...
                    if ($xmlRouterId) {
                        $xmlRouterId = $RouterId.IPAddresstoString
                    }
                    else{
                        Add-XmlElement -xmlRoot $xmlGlobalConfig -xmlElementName "routerId" -xmlElementText $RouterId.IPAddresstoString
                    }
                }
            }
        }

        if ( $PsBoundParameters.ContainsKey('EnableOSPF')) { 
            $ospf = $_EdgeRouting.SelectSingleNode('descendant::ospf') 
            if ( -not $ospf ) {
                #ospf node does not exist.
                [System.XML.XMLElement]$ospf = $_EdgeRouting.ownerDocument.CreateElement("ospf")
                $_EdgeRouting.appendChild($ospf) | out-null
            }

            if ( $ospf.SelectSingleNode('descendant::enabled')) {
                #Enabled element exists.  Update it.
                $ospf.enabled = $EnableOSPF.ToString().ToLower()
            }
            else {
                #Enabled element does not exist...
                Add-XmlElement -xmlRoot $ospf -xmlElementName "enabled" -xmlElementText $EnableOSPF.ToString().ToLower()
            }
        
        }

        if ( $PsBoundParameters.ContainsKey('EnableBGP')) {

            $bgp = $_EdgeRouting.SelectSingleNode('descendant::bgp') 

            if ( -not $bgp ) {
                #bgp node does not exist.
                [System.XML.XMLElement]$bgp = $_EdgeRouting.ownerDocument.CreateElement("bgp")
                $_EdgeRouting.appendChild($bgp) | out-null
            }

            if ( $bgp.SelectSingleNode('descendant::enabled')) {
                #Enabled element exists.  Update it.
                $bgp.enabled = $EnableBGP.ToString().ToLower()
            }
            else {
                #Enabled element does not exist...
                Add-XmlElement -xmlRoot $bgp -xmlElementName "enabled" -xmlElementText $EnableBGP.ToString().ToLower()
            }

            if ( $PsBoundParameters.ContainsKey("LocalAS")) { 
                if ( $bgp.SelectSingleNode('descendant::localAS')) {
                #LocalAS element exists, update it.
                    $bgp.localAS = $LocalAS.ToString()
                }
                else {
                    #LocalAS element does not exist...
                    Add-XmlElement -xmlRoot $bgp -xmlElementName "localAS" -xmlElementText $LocalAS.ToString()
                }
            }
            elseif ( (-not ( $bgp.SelectSingleNode('descendant::localAS')) -and $EnableBGP  )) {
                throw "Existing configuration has no Local AS number specified.  Local AS must be set to enable BGP."
            }
            

        }

        if ( $PsBoundParameters.ContainsKey("EnableECMP")) { 
            $_EdgeRouting.routingGlobalConfig.ecmp = $EnableECMP.ToString().ToLower()
        }

        if ( $PsBoundParameters.ContainsKey("EnableOspfRouteRedistribution")) { 

            $_EdgeRouting.ospf.redistribution.enabled = $EnableOspfRouteRedistribution.ToString().ToLower()
        }

        if ( $PsBoundParameters.ContainsKey("EnableBgpRouteRedistribution")) { 
            if ( -not $_EdgeRouting.SelectSingleNode('child::bgp/redistribution/enabled') ) {
                throw "BGP must have been configured at least once to enable or disable BGP route redistribution.  Enable BGP and try again."
            }

            $_EdgeRouting.bgp.redistribution.enabled = $EnableBgpRouteRedistribution.ToString().ToLower()
        }

        if ( $PsBoundParameters.ContainsKey("EnableLogging")) { 
            $_EdgeRouting.routingGlobalConfig.logging.enable = $EnableLogging.ToString().ToLower()
        }

        if ( $PsBoundParameters.ContainsKey("LogLevel")) { 
            $_EdgeRouting.routingGlobalConfig.logging.logLevel = $LogLevel.ToString().ToLower()
        }

        if ( $PsBoundParameters.ContainsKey("DefaultGatewayVnic") -or $PsBoundParameters.ContainsKey("DefaultGatewayAddress") -or 
            $PsBoundParameters.ContainsKey("DefaultGatewayDescription") -or $PsBoundParameters.ContainsKey("DefaultGatewayMTU") -or
            $PsBoundParameters.ContainsKey("DefaultGatewayAdminDistance") ) { 

            #Check for and create if required the defaultRoute element. first.
            if ( -not $_EdgeRouting.staticRouting.SelectSingleNode('descendant::defaultRoute')) {
                #defaultRoute element does not exist
                $defaultRoute = $_EdgeRouting.ownerDocument.CreateElement('defaultRoute')
                $_EdgeRouting.staticRouting.AppendChild($defaultRoute) | out-null
            }
            else {
                #defaultRoute element exists
                $defaultRoute = $_EdgeRouting.staticRouting.defaultRoute
            }

            if ( $PsBoundParameters.ContainsKey("DefaultGatewayVnic") ) { 
                if ( -not $defaultRoute.SelectSingleNode('descendant::vnic')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "vnic" -xmlElementText $DefaultGatewayVnic.ToString()
                }
                else {
                    #element exists
                    $defaultRoute.vnic = $DefaultGatewayVnic.ToString()
                }
            }

            if ( $PsBoundParameters.ContainsKey("DefaultGatewayAddress") ) { 
                if ( -not $defaultRoute.SelectSingleNode('descendant::gatewayAddress')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "gatewayAddress" -xmlElementText $DefaultGatewayAddress.ToString()
                }
                else {
                    #element exists
                    $defaultRoute.gatewayAddress = $DefaultGatewayAddress.ToString()
                }
            }

            if ( $PsBoundParameters.ContainsKey("DefaultGatewayDescription") ) { 
                if ( -not $defaultRoute.SelectSingleNode('descendant::description')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "description" -xmlElementText $DefaultGatewayDescription
                }
                else {
                    #element exists
                    $defaultRoute.description = $DefaultGatewayDescription
                }
            }
            if ( $PsBoundParameters.ContainsKey("DefaultGatewayMTU") ) { 
                if ( -not $defaultRoute.SelectSingleNode('descendant::mtu')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "mtu" -xmlElementText $DefaultGatewayMTU.ToString()
                }
                else {
                    #element exists
                    $defaultRoute.mtu = $DefaultGatewayMTU.ToString()
                }
            }
            if ( $PsBoundParameters.ContainsKey("DefaultGatewayAdminDistance") ) { 
                if ( -not $defaultRoute.SelectSingleNode('descendant::adminDistance')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "adminDistance" -xmlElementText $DefaultGatewayAdminDistance.ToString()
                }
                else {
                    #element exists
                    $defaultRoute.adminDistance = $DefaultGatewayAdminDistance.ToString()
                }
            }
        }


        $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
        $body = $_EdgeRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
            $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxEdgeRouting
        }
    }

    end {}
}


function Get-NsxEdgeRouting {
    
    <#
    .SYNOPSIS
    Retreives routing configuration for the spcified NSX Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Get-NsxEdgeRouting cmdlet retreives the routing configuration of
    the specified Edge Services Gateway.
    
    .EXAMPLE
    Get routing configuration for the ESG Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeRouting = $Edge.features.routing.CloneNode($True)
        Add-XmlElement -xmlRoot $_EdgeRouting -xmlElementName "edgeId" -xmlElementText $Edge.Id
        $_EdgeRouting
    }

    end {}
}


# Static Routing

function Get-NsxEdgeStaticRoute {
    
    <#
    .SYNOPSIS
    Retreives Static Routes from the spcified NSX Edge Services Gateway Routing 
    configuration.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Get-NsxEdgeStaticRoute cmdlet retreives the static routes from the 
    routing configuration specified.

    .EXAMPLE
    Get static routes defining on ESG Edge01

    PS C:\> Get-NsxEdge | Get-NsxEdgeRouting | Get-NsxEdgeStaticRoute
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$Network,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$NextHop       
        
    )
    
    begin {
    }

    process {
    
        #We append the Edge-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_EdgeStaticRouting = ($EdgeRouting.staticRouting.CloneNode($True))
        $EdgeStaticRoutes = $_EdgeStaticRouting.SelectSingleNode('descendant::staticRoutes')

        #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called route.
        If ( $EdgeStaticRoutes.SelectSingleNode('descendant::route')) { 

            $RouteCollection = $EdgeStaticRoutes.route
            if ( $PsBoundParameters.ContainsKey('Network')) {
                $RouteCollection = $RouteCollection | ? { $_.network -eq $Network }
            }

            if ( $PsBoundParameters.ContainsKey('NextHop')) {
                $RouteCollection = $RouteCollection | ? { $_.nextHop -eq $NextHop }
            }

            foreach ( $StaticRoute in $RouteCollection ) { 
                Add-XmlElement -xmlRoot $StaticRoute -xmlElementName "edgeId" -xmlElementText $EdgeRouting.EdgeId
            }

            $RouteCollection
        }
    }

    end {}
}


function New-NsxEdgeStaticRoute {
    
    <#
    .SYNOPSIS
    Creates a new static route and adds it to the specified ESGs routing
    configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The New-NsxEdgeStaticRoute cmdlet adds a new static route to the routing
    configuration of the specified Edge Services Gateway.

    .EXAMPLE
    Add a new static route to ESG Edge01 for 1.1.1.0/24 via 10.0.0.200

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | New-NsxEdgeStaticRoute -Network 1.1.1.0/24 -NextHop 10.0.0.200
    
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,200)]
            [int]$Vnic,        
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,9128)]
            [int]$MTU,        
        [Parameter (Mandatory=$False)]
            [string]$Description,       
        [Parameter (Mandatory=$True)]
            [ipAddress]$NextHop,
        [Parameter (Mandatory=$True)]
            [string]$Network,
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,255)]
            [int]$AdminDistance,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Create private xml element
        $_EdgeRouting = $EdgeRouting.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeRouting.edgeId
        $_EdgeRouting.RemoveChild( $($_EdgeRouting.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        #Create the new route element.
        $Route = $_EdgeRouting.ownerDocument.CreateElement('route')

        #Need to do an xpath query here rather than use PoSH dot notation to get the static route element,
        #as it might be empty, and PoSH silently turns an empty element into a string object, which is rather not what we want... :|
        $StaticRoutes = $_EdgeRouting.staticRouting.SelectSingleNode('descendant::staticRoutes')
        $StaticRoutes.AppendChild($Route) | Out-Null

        Add-XmlElement -xmlRoot $Route -xmlElementName "network" -xmlElementText $Network.ToString()
        Add-XmlElement -xmlRoot $Route -xmlElementName "nextHop" -xmlElementText $NextHop.ToString()

        if ( $PsBoundParameters.ContainsKey("Vnic") ) { 
            Add-XmlElement -xmlRoot $Route -xmlElementName "vnic" -xmlElementText $Vnic.ToString()
        }

        if ( $PsBoundParameters.ContainsKey("MTU") ) { 
            Add-XmlElement -xmlRoot $Route -xmlElementName "mtu" -xmlElementText $MTU.ToString()
        }

        if ( $PsBoundParameters.ContainsKey("Description") ) { 
            Add-XmlElement -xmlRoot $Route -xmlElementName "description" -xmlElementText $Description.ToString()
        }
    
        if ( $PsBoundParameters.ContainsKey("AdminDistance") ) { 
            Add-XmlElement -xmlRoot $Route -xmlElementName "adminDistance" -xmlElementText $AdminDistance.ToString()
        }


        $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
        $body = $_EdgeRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
            $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxEdgeRouting | Get-NsxEdgeStaticRoute -Network $Network -NextHop $NextHop
        }
    }

    end {}
}


function Remove-NsxEdgeStaticRoute {
    
    <#
    .SYNOPSIS
    Removes a static route from the specified ESGs routing configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Remove-NsxEdgeStaticRoute cmdlet removes a static route from the routing
    configuration of the specified Edge Services Gateway.

    Routes to be removed can be constructed via a PoSH pipline filter outputing
    route objects as produced by Get-NsxEdgeStaticRoute and passing them on the
    pipeline to Remove-NsxEdgeStaticRoute.

    .EXAMPLE
    Remove a route to 1.1.1.0/24 via 10.0.0.100 from ESG Edge01
    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeStaticRoute | ? { $_.network -eq '1.1.1.0/24' -and $_.nextHop -eq '10.0.0.100' } | Remove-NsxEdgeStaticRoute

    .EXAMPLE
    Remove all routes to 1.1.1.0/24 from ESG Edge01
    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeStaticRoute | ? { $_.network -eq '1.1.1.0/24' } | Remove-NsxEdgeStaticRoute

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeStaticRoute $_ })]
            [System.Xml.XmlElement]$StaticRoute,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our Edge
        $edgeId = $StaticRoute.edgeId
        $routing = Get-NsxEdge -objectId $edgeId -connection $connection | Get-NsxEdgeRouting

        #Remove the edgeId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Need to do an xpath query here to query for a route that matches the one passed in.  
        #Union of nextHop and network should be unique
        $xpathQuery = "//staticRoutes/route[nextHop=`"$($StaticRoute.nextHop)`" and network=`"$($StaticRoute.network)`"]"
        write-debug "XPath query for route nodes to remove is: $xpathQuery"
        $RouteToRemove = $routing.staticRouting.SelectSingleNode($xpathQuery)

        if ( $RouteToRemove ) { 

            write-debug "RouteToRemove Element is: `n $($RouteToRemove.OuterXml | format-xml) "
            $routing.staticRouting.staticRoutes.RemoveChild($RouteToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            }
        }
        else {
            Throw "Route for network $($StaticRoute.network) via $($StaticRoute.nextHop) was not found in routing configuration for Edge $edgeId"
        }
    }

    end {}
}


# Prefixes

function Get-NsxEdgePrefix {
    
    <#
    .SYNOPSIS
    Retreives IP Prefixes from the spcified NSX Edge Services Gateway Routing 
    configuration.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Get-NsxEdgePrefix cmdlet retreives IP prefixes from the 
    routing configuration specified.
    
    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgePrefix

    Retrieve prefixes from Edge Edge01

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgePrefix -Network 1.1.1.0/24

    Retrieve prefix 1.1.1.0/24 from Edge Edge01

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgePrefix -Name CorpNet

    Retrieve prefix CorpNet from Edge Edge01
      
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$Network       
        
    )
    
    begin {
    }

    process {
    
        #We append the Edge-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_GlobalRoutingConfig = ($EdgeRouting.routingGlobalConfig.CloneNode($True))
        $IpPrefixes = $_GlobalRoutingConfig.SelectSingleNode('child::ipPrefixes')

        #IPPrefixes may not exist...
        if ( $IPPrefixes ) { 
            #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called ipPrefix.
            If ( $IpPrefixes.SelectSingleNode('child::ipPrefix')) { 

                $PrefixCollection = $IPPrefixes.ipPrefix
                if ( $PsBoundParameters.ContainsKey('Network')) {
                    $PrefixCollection = $PrefixCollection | ? { $_.ipAddress -eq $Network }
                }

                if ( $PsBoundParameters.ContainsKey('Name')) {
                    $PrefixCollection = $PrefixCollection | ? { $_.name -eq $Name }
                }

                foreach ( $Prefix in $PrefixCollection ) { 
                    Add-XmlElement -xmlRoot $Prefix -xmlElementName "edgeId" -xmlElementText $EdgeRouting.EdgeId
                }

                $PrefixCollection
            }
        }
    }

    end {}
}


function New-NsxEdgePrefix {
    
    <#
    .SYNOPSIS
    Creates a new IP prefix and adds it to the specified ESGs routing
    configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The New-NsxEdgePrefix cmdlet adds a new IP prefix to the routing
    configuration of the specified Edge Services Gateway.

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxEdgeRouting | New-NsxEdgePrefix -Name test -Network 1.1.1.0/24

    Create a new prefix called test for network 1.1.1.0/24 on ESG Edge01
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullorEmpty()]
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$True)]
            [ValidateNotNullorEmpty()]
            [string]$Name,       
        [Parameter (Mandatory=$True)]
            [ValidateNotNullorEmpty()]
            [string]$Network,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Create private xml element
        $_EdgeRouting = $EdgeRouting.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeRouting.edgeId
        $_EdgeRouting.RemoveChild( $($_EdgeRouting.SelectSingleNode('child::edgeId')) ) | out-null


        #Need to do an xpath query here rather than use PoSH dot notation to get the IP prefix element,
        #as it might be empty or not exist, and PoSH silently turns an empty element into a string object, which is rather not what we want... :|
        $ipPrefixes = $_EdgeRouting.routingGlobalConfig.SelectSingleNode('child::ipPrefixes')
        if ( -not $ipPrefixes ) { 
            #Create the ipPrefixes element
            $ipPrefixes = $_EdgeRouting.ownerDocument.CreateElement('ipPrefixes')
            $_EdgeRouting.routingGlobalConfig.AppendChild($ipPrefixes) | Out-Null
        }

        #Create the new ipPrefix element.
        $ipPrefix = $_EdgeRouting.ownerDocument.CreateElement('ipPrefix')
        $ipPrefixes.AppendChild($ipPrefix) | Out-Null

        Add-XmlElement -xmlRoot $ipPrefix -xmlElementName "name" -xmlElementText $Name.ToString()
        Add-XmlElement -xmlRoot $ipPrefix -xmlElementName "ipAddress" -xmlElementText $Network.ToString()


        $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
        $body = $_EdgeRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
            $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxEdgeRouting | Get-NsxEdgePrefix -Network $Network -Name $Name
        }
    }

    end {}
}


function Remove-NsxEdgePrefix {
    
    <#
    .SYNOPSIS
    Removes an IP prefix from the specified ESGs routing configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Remove-NsxEdgePrefix cmdlet removes a IP prefix from the routing
    configuration of the specified Edge Services Gateway.

    Prefixes to be removed can be constructed via a PoSH pipline filter outputing
    prefix objects as produced by Get-NsxEdgePrefix and passing them on the
    pipeline to Remove-NsxEdgePrefix.

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgePrefix -Network 1.1.1.0/24 | Remove-NsxEdgePrefix

    Remove any prefixes for network 1.1.1.0/24 from ESG Edge01


    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgePrefix $_ })]
            [System.Xml.XmlElement]$Prefix,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our Edge
        $edgeId = $Prefix.edgeId
        $routing = Get-NsxEdge -objectId $edgeId -connection $connection | Get-NsxEdgeRouting

        #Remove the edgeId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('child::edgeId')) ) | out-null

        #Need to do an xpath query here to query for a prefix that matches the one passed in.  
        #Union of nextHop and network should be unique
        $xpathQuery = "/routingGlobalConfig/ipPrefixes/ipPrefix[name=`"$($Prefix.name)`" and ipAddress=`"$($Prefix.ipAddress)`"]"
        write-debug "XPath query for prefix nodes to remove is: $xpathQuery"
        $PrefixToRemove = $routing.SelectSingleNode($xpathQuery)

        if ( $PrefixToRemove ) { 

            write-debug "PrefixToRemove Element is: `n $($PrefixToRemove.OuterXml | format-xml) "
            $routing.routingGlobalConfig.ipPrefixes.RemoveChild($PrefixToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            }
        }
        else {
            Throw "Prefix $($Prefix.Name) for network $($Prefix.network) was not found in routing configuration for Edge $edgeId"
        }
    }

    end {}
}


# BGP

function Get-NsxEdgeBgp {
    
    <#
    .SYNOPSIS
    Retreives BGP configuration for the spcified NSX Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Get-NsxEdgeBgp cmdlet retreives the bgp configuration of
    the specified Edge Services Gateway.
    
    .EXAMPLE
    Get the BGP configuration for Edge01

    PS C:\> Get-NsxEdge Edg01 | Get-NsxEdgeRouting | Get-NsxEdgeBgp   
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        if ( $EdgeRouting.SelectSingleNode('descendant::bgp')) { 
            $bgp = $EdgeRouting.SelectSingleNode('child::bgp').CloneNode($True)
            Add-XmlElement -xmlRoot $bgp -xmlElementName "edgeId" -xmlElementText $EdgeRouting.EdgeId
            $bgp
        }
    }

    end {}
}


function Set-NsxEdgeBgp {
    
    <#
    .SYNOPSIS
    Manipulates BGP specific base configuration of an existing NSX Edge Services 
    Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Set-NsxEdgeBgp cmdlet allows manipulation of the BGP specific configuration
    of a given ESG.
    
   
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$EnableBGP,
        [Parameter (Mandatory=$False)]
            [IpAddress]$RouterId,
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,65535)]
            [int]$LocalAS,
        [Parameter (Mandatory=$False)]
            [switch]$GracefulRestart,
        [Parameter (Mandatory=$False)]
            [switch]$DefaultOriginate,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        #Create private xml element
        $_EdgeRouting = $EdgeRouting.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeRouting.edgeId
        $_EdgeRouting.RemoveChild( $($_EdgeRouting.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        if ( $PsBoundParameters.ContainsKey('EnableBGP') ) { 
            $xmlGlobalConfig = $_EdgeRouting.routingGlobalConfig
            $xmlRouterId = $xmlGlobalConfig.SelectSingleNode('descendant::routerId')
            if ( $EnableBGP ) {
                if ( -not ($xmlRouterId -or $PsBoundParameters.ContainsKey("RouterId"))) {
                    #Existing config missing and no new value set...
                    throw "RouterId must be configured to enable dynamic routing"
                }

                if ($PsBoundParameters.ContainsKey("RouterId")) {
                    #Set Routerid...
                    if ($xmlRouterId) {
                        $xmlRouterId = $RouterId.IPAddresstoString
                    }
                    else{
                        Add-XmlElement -xmlRoot $xmlGlobalConfig -xmlElementName "routerId" -xmlElementText $RouterId.IPAddresstoString
                    }
                }
            }

            $bgp = $_EdgeRouting.SelectSingleNode('descendant::bgp') 

            if ( -not $bgp ) {
                #bgp node does not exist.
                [System.XML.XMLElement]$bgp = $_EdgeRouting.ownerDocument.CreateElement("bgp")
                $_EdgeRouting.appendChild($bgp) | out-null
            }

            if ( $bgp.SelectSingleNode('descendant::enabled')) {
                #Enabled element exists.  Update it.
                $bgp.enabled = $EnableBGP.ToString().ToLower()
            }
            else {
                #Enabled element does not exist...
                Add-XmlElement -xmlRoot $bgp -xmlElementName "enabled" -xmlElementText $EnableBGP.ToString().ToLower()
            }

            if ( $PsBoundParameters.ContainsKey("LocalAS")) { 
                if ( $bgp.SelectSingleNode('descendant::localAS')) {
                    #LocalAS element exists, update it.
                    $bgp.localAS = $LocalAS.ToString()
                }
                else {
                    #LocalAS element does not exist...
                    Add-XmlElement -xmlRoot $bgp -xmlElementName "localAS" -xmlElementText $LocalAS.ToString()
                }
            }
            elseif ( (-not ( $bgp.SelectSingleNode('descendant::localAS')) -and $EnableBGP  )) {
                throw "Existing configuration has no Local AS number specified.  Local AS must be set to enable BGP."
            }

            if ( $PsBoundParameters.ContainsKey("GracefulRestart")) { 
                if ( $bgp.SelectSingleNode('descendant::gracefulRestart')) {
                    #element exists, update it.
                    $bgp.gracefulRestart = $GracefulRestart.ToString().ToLower()
                }
                else {
                    #element does not exist...
                    Add-XmlElement -xmlRoot $bgp -xmlElementName "gracefulRestart" -xmlElementText $GracefulRestart.ToString().ToLower()
                }
            }

            if ( $PsBoundParameters.ContainsKey("DefaultOriginate")) { 
                if ( $bgp.SelectSingleNode('descendant::defaultOriginate')) {
                    #element exists, update it.
                    $bgp.defaultOriginate = $DefaultOriginate.ToString().ToLower()
                }
                else {
                    #element does not exist...
                    Add-XmlElement -xmlRoot $bgp -xmlElementName "defaultOriginate" -xmlElementText $DefaultOriginate.ToString().ToLower()
                }
            }
        }

        $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
        $body = $_EdgeRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
            $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxEdgeRouting | Get-NsxEdgeBgp
        }
    }

    end {}
}


function Get-NsxEdgeBgpNeighbour {
    
    <#
    .SYNOPSIS
    Returns BGP neighbours from the spcified NSX Edge Services Gateway BGP 
    configuration.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Get-NsxEdgeBgpNeighbour cmdlet retreives the BGP neighbours from the 
    BGP configuration specified.

    .EXAMPLE
    Get all BGP neighbours defined on Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeBgpNeighbour
    
    .EXAMPLE
    Get BGP neighbour 1.1.1.1 defined on Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeBgpNeighbour -IpAddress 1.1.1.1

    .EXAMPLE
    Get all BGP neighbours with Remote AS 1234 defined on Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeBgpNeighbour | ? { $_.RemoteAS -eq '1234' }

    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$Network,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$IpAddress,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,65535)]
            [int]$RemoteAS              
    )
    
    begin {
    }

    process {
    
        $bgp = $EdgeRouting.SelectSingleNode('descendant::bgp')

        if ( $bgp ) {

            $_bgp = $bgp.CloneNode($True)
            $BgpNeighbours = $_bgp.SelectSingleNode('descendant::bgpNeighbours')


            #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called bgpNeighbour.
            if ( $BgpNeighbours.SelectSingleNode('descendant::bgpNeighbour')) { 

                $NeighbourCollection = $BgpNeighbours.bgpNeighbour
                if ( $PsBoundParameters.ContainsKey('IpAddress')) {
                    $NeighbourCollection = $NeighbourCollection | ? { $_.ipAddress -eq $IpAddress }
                }

                if ( $PsBoundParameters.ContainsKey('RemoteAS')) {
                    $NeighbourCollection = $NeighbourCollection | ? { $_.remoteAS -eq $RemoteAS }
                }

                foreach ( $Neighbour in $NeighbourCollection ) { 
                    #We append the Edge-id to the associated neighbour config XML to enable pipeline workflows and 
                    #consistent readable output
                    Add-XmlElement -xmlRoot $Neighbour -xmlElementName "edgeId" -xmlElementText $EdgeRouting.EdgeId
                }

                $NeighbourCollection
            }
        }
    }

    end {}
}


function New-NsxEdgeBgpNeighbour {
    
    <#
    .SYNOPSIS
    Creates a new BGP neighbour and adds it to the specified ESGs BGP
    configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The New-NsxEdgeBgpNeighbour cmdlet adds a new BGP neighbour to the bgp
    configuration of the specified Edge Services Gateway.

    .EXAMPLE
    Add a new neighbour 1.2.3.4 with remote AS number 1234 with defaults.

    PS C:\> Get-NsxEdge | Get-NsxEdgeRouting | New-NsxEdgeBgpNeighbour -IpAddress 1.2.3.4 -RemoteAS 1234

    .EXAMPLE
    Add a new neighbour 1.2.3.4 with remote AS number 22235 specifying weight, holddown and keepalive timers and dont prompt for confirmation.

    PowerCLI C:\> Get-NsxEdge | Get-NsxEdgeRouting | New-NsxEdgeBgpNeighbour -IpAddress 1.2.3.4 -RemoteAS 22235 -Confirm:$false -Weight 90 -HoldDownTimer 240 -KeepAliveTimer 90 -confirm:$false

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$true)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$IpAddress,
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,65535)]
            [int]$RemoteAS,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,65535)]
            [int]$Weight,
        [Parameter (Mandatory=$false)]
            [ValidateRange(2,65535)]
            [int]$HoldDownTimer,
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,65534)]
            [int]$KeepAliveTimer,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [string]$Password,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Create private xml element
        $_EdgeRouting = $EdgeRouting.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeRouting.edgeId
        $_EdgeRouting.RemoveChild( $($_EdgeRouting.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Create the new bgpNeighbour element.
        $Neighbour = $_EdgeRouting.ownerDocument.CreateElement('bgpNeighbour')

        #Need to do an xpath query here rather than use PoSH dot notation to get the bgp element,
        #as it might not exist which wil cause PoSH to throw in stric mode.
        $bgp = $_EdgeRouting.SelectSingleNode('descendant::bgp')
        if ( $bgp ) { 
            $bgp.selectSingleNode('descendant::bgpNeighbours').AppendChild($Neighbour) | Out-Null

            Add-XmlElement -xmlRoot $Neighbour -xmlElementName "ipAddress" -xmlElementText $IpAddress.ToString()
            Add-XmlElement -xmlRoot $Neighbour -xmlElementName "remoteAS" -xmlElementText $RemoteAS.ToString()

            #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
            #If the user did not specify a given parameter, we dont want to modify from the existing value.
            if ( $PsBoundParameters.ContainsKey("Weight") ) { 
                Add-XmlElement -xmlRoot $Neighbour -xmlElementName "weight" -xmlElementText $Weight.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("HoldDownTimer") ) { 
                Add-XmlElement -xmlRoot $Neighbour -xmlElementName "holdDownTimer" -xmlElementText $HoldDownTimer.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("KeepAliveTimer") ) { 
                Add-XmlElement -xmlRoot $Neighbour -xmlElementName "keepAliveTimer" -xmlElementText $KeepAliveTimer.ToString()
            }


            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $_EdgeRouting.OuterXml 
           
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
                Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxEdgeRouting | Get-NsxEdgeBgpNeighbour -IpAddress $IpAddress -RemoteAS $RemoteAS
            }
        }
        else {
            throw "BGP is not enabled on edge $edgeID.  Enable BGP using Set-NsxEdgeRouting or Set-NsxEdgeBGP first."
        }
    }

    end {}
}


function Remove-NsxEdgeBgpNeighbour {
    
    <#
    .SYNOPSIS
    Removes a BGP neigbour from the specified ESGs BGP configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Remove-NsxEdgeBgpNeighbour cmdlet removes a BGP neighbour route from the 
    bgp configuration of the specified Edge Services Gateway.

    Neighbours to be removed can be constructed via a PoSH pipline filter outputing
    neighbour objects as produced by Get-NsxEdgeBgpNeighbour and passing them on the
    pipeline to Remove-NsxEdgeBgpNeighbour.

    .EXAMPLE
    Remove the BGP neighbour 1.1.1.2 from the the edge Edge01's bgp configuration

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeBgpNeighbour | ? { $_.ipaddress -eq '1.1.1.2' } |  Remove-NsxEdgeBgpNeighbour 
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeBgpNeighbour $_ })]
            [System.Xml.XmlElement]$BgpNeighbour,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our Edge
        $edgeId = $BgpNeighbour.edgeId
        $routing = Get-NsxEdge -objectId $edgeId | Get-NsxEdgeRouting

        #Remove the edgeId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Validate the BGP node exists on the edge 
        if ( -not $routing.SelectSingleNode('descendant::bgp')) { throw "BGP is not enabled on ESG $edgeId.  Enable BGP and try again." }

        #Need to do an xpath query here to query for a bgp neighbour that matches the one passed in.  
        #Union of ipaddress and remote AS should be unique (though this is not enforced by the API, 
        #I cant see why having duplicate neighbours with same ip and AS would be useful...maybe 
        #different filters?)
        #Will probably need to include additional xpath query filters here in the query to include 
        #matching on filters to better handle uniquness amongst bgp neighbours with same ip and remoteAS

        $xpathQuery = "//bgpNeighbours/bgpNeighbour[ipAddress=`"$($BgpNeighbour.ipAddress)`" and remoteAS=`"$($BgpNeighbour.remoteAS)`"]"
        write-debug "XPath query for neighbour nodes to remove is: $xpathQuery"
        $NeighbourToRemove = $routing.bgp.SelectSingleNode($xpathQuery)

        if ( $NeighbourToRemove ) { 

            write-debug "NeighbourToRemove Element is: `n $($NeighbourToRemove.OuterXml | format-xml) "
            $routing.bgp.bgpNeighbours.RemoveChild($NeighbourToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            }
        }
        else {
            Throw "Neighbour $($BgpNeighbour.ipAddress) with Remote AS $($BgpNeighbour.RemoteAS) was not found in routing configuration for Edge $edgeId"
        }
    }

    end {}
}


# OSPF

function Get-NsxEdgeOspf {
    
    <#
    .SYNOPSIS
    Retreives OSPF configuration for the spcified NSX Edge Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Get-NsxEdgeOspf cmdlet retreives the OSPF configuration of
    the specified Edge Services Gateway.
    
    .EXAMPLE
    Get the OSPF configuration for Edge01

    PS C:\> Get-NsxEdge Edg01 | Get-NsxEdgeRouting | Get-NsxEdgeOspf
    
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting
    )
    
    begin {

    }

    process {
    
        #We append the Edge-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        if ( $EdgeRouting.SelectSingleNode('descendant::ospf')) { 
            $ospf = $EdgeRouting.ospf.CloneNode($True)
            Add-XmlElement -xmlRoot $ospf -xmlElementName "edgeId" -xmlElementText $EdgeRouting.EdgeId
            $ospf
        }
    }

    end {}
}


function Set-NsxEdgeOspf {
    
    <#
    .SYNOPSIS
    Manipulates OSPF specific base configuration of an existing NSX Edge 
    Services Gateway.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Set-NsxEdgeOspf cmdlet allows manipulation of the OSPF specific 
    configuration of a given ESG.
    
   
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$EnableOSPF,
        [Parameter (Mandatory=$False)]
            [IpAddress]$RouterId,
        [Parameter (Mandatory=$False)]
            [switch]$GracefulRestart,
        [Parameter (Mandatory=$False)]
            [switch]$DefaultOriginate,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        #Create private xml element
        $_EdgeRouting = $EdgeRouting.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeRouting.edgeId
        $_EdgeRouting.RemoveChild( $($_EdgeRouting.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        if ( $PsBoundParameters.ContainsKey('EnableOSPF') ) { 
            $xmlGlobalConfig = $_EdgeRouting.routingGlobalConfig
            $xmlRouterId = $xmlGlobalConfig.SelectSingleNode('descendant::routerId')
            if ( $EnableOSPF ) {
                if ( -not ($xmlRouterId -or $PsBoundParameters.ContainsKey("RouterId"))) {
                    #Existing config missing and no new value set...
                    throw "RouterId must be configured to enable dynamic routing"
                }

                if ($PsBoundParameters.ContainsKey("RouterId")) {
                    #Set Routerid...
                    if ($xmlRouterId) {
                        $xmlRouterId = $RouterId.IPAddresstoString
                    }
                    else{
                        Add-XmlElement -xmlRoot $xmlGlobalConfig -xmlElementName "routerId" -xmlElementText $RouterId.IPAddresstoString
                    }
                }
            }

            $ospf = $_EdgeRouting.SelectSingleNode('descendant::ospf') 

            if ( -not $ospf ) {
                #ospf node does not exist.
                [System.XML.XMLElement]$ospf = $_EdgeRouting.ownerDocument.CreateElement("ospf")
                $_EdgeRouting.appendChild($ospf) | out-null
            }

            if ( $ospf.SelectSingleNode('descendant::enabled')) {
                #Enabled element exists.  Update it.
                $ospf.enabled = $EnableOSPF.ToString().ToLower()
            }
            else {
                #Enabled element does not exist...
                Add-XmlElement -xmlRoot $ospf -xmlElementName "enabled" -xmlElementText $EnableOSPF.ToString().ToLower()
            }

            if ( $PsBoundParameters.ContainsKey("GracefulRestart")) { 
                if ( $ospf.SelectSingleNode('descendant::gracefulRestart')) {
                    #element exists, update it.
                    $ospf.gracefulRestart = $GracefulRestart.ToString().ToLower()
                }
                else {
                    #element does not exist...
                    Add-XmlElement -xmlRoot $ospf -xmlElementName "gracefulRestart" -xmlElementText $GracefulRestart.ToString().ToLower()
                }
            }

            if ( $PsBoundParameters.ContainsKey("DefaultOriginate")) { 
                if ( $ospf.SelectSingleNode('descendant::defaultOriginate')) {
                    #element exists, update it.
                    $ospf.defaultOriginate = $DefaultOriginate.ToString().ToLower()
                }
                else {
                    #element does not exist...
                    Add-XmlElement -xmlRoot $ospf -xmlElementName "defaultOriginate" -xmlElementText $DefaultOriginate.ToString().ToLower()
                }
            }
        }

        $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
        $body = $_EdgeRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
            $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxEdgeRouting | Get-NsxEdgeBgp
        }
    }

    end {}
}


function Get-NsxEdgeOspfArea {
    
    <#
    .SYNOPSIS
    Returns OSPF Areas defined in the spcified NSX Edge Services Gateway OSPF 
    configuration.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Get-NsxEdgeOspfArea cmdlet retreives the OSPF Areas from the OSPF 
    configuration specified.

    .EXAMPLE
    Get all areas defined on Edge01.

    PS C:\> C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeOspfArea 
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,4294967295)]
            [int]$AreaId              
    )
    
    begin {
    }

    process {
    
        $ospf = $EdgeRouting.SelectSingleNode('descendant::ospf')

        if ( $ospf ) {

            $_ospf = $ospf.CloneNode($True)
            $OspfAreas = $_ospf.SelectSingleNode('descendant::ospfAreas')


            #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called ospfArea.
            if ( $OspfAreas.SelectSingleNode('descendant::ospfArea')) { 

                $AreaCollection = $OspfAreas.ospfArea
                if ( $PsBoundParameters.ContainsKey('AreaId')) {
                    $AreaCollection = $AreaCollection | ? { $_.areaId -eq $AreaId }
                }

                foreach ( $Area in $AreaCollection ) { 
                    #We append the Edge-id to the associated Area config XML to enable pipeline workflows and 
                    #consistent readable output
                    Add-XmlElement -xmlRoot $Area -xmlElementName "edgeId" -xmlElementText $EdgeRouting.EdgeId
                }

                $AreaCollection
            }
        }
    }

    end {}
}


function Remove-NsxEdgeOspfArea {
    
    <#
    .SYNOPSIS
    Removes an OSPF area from the specified ESGs OSPF configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Remove-NsxEdgeOspfArea cmdlet removes a BGP neighbour route from the 
    bgp configuration of the specified Edge Services Gateway.

    Areas to be removed can be constructed via a PoSH pipline filter outputing
    area objects as produced by Get-NsxEdgeOspfArea and passing them on the
    pipeline to Remove-NsxEdgeOspfArea.
    
    .EXAMPLE
    Remove area 51 from ospf configuration on Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeOspfArea -AreaId 51 | Remove-NsxEdgeOspfArea
    
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeOspfArea $_ })]
            [System.Xml.XmlElement]$OspfArea,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our Edge
        $edgeId = $OspfArea.edgeId
        $routing = Get-NsxEdge -objectId $edgeId -connection $connection | Get-NsxEdgeRouting

        #Remove the edgeId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Validate the OSPF node exists on the edge 
        if ( -not $routing.SelectSingleNode('descendant::ospf')) { throw "OSPF is not enabled on ESG $edgeId.  Enable OSPF and try again." }
        if ( -not ($routing.ospf.enabled -eq 'true') ) { throw "OSPF is not enabled on ESG $edgeId.  Enable OSPF and try again." }

        

        $xpathQuery = "//ospfAreas/ospfArea[areaId=`"$($OspfArea.areaId)`"]"
        write-debug "XPath query for area nodes to remove is: $xpathQuery"
        $AreaToRemove = $routing.ospf.SelectSingleNode($xpathQuery)

        if ( $AreaToRemove ) { 

            write-debug "AreaToRemove Element is: `n $($AreaToRemove.OuterXml | format-xml) "
            $routing.ospf.ospfAreas.RemoveChild($AreaToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            }
        }
        else {
            Throw "Area $($OspfArea.areaId) was not found in routing configuration for Edge $edgeId"
        }
    }

    end {}
}


function New-NsxEdgeOspfArea {
    
    <#
    .SYNOPSIS
    Creates a new OSPF Area and adds it to the specified ESGs OSPF 
    configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The New-NsxEdgeOspfArea cmdlet adds a new OSPF Area to the ospf
    configuration of the specified Edge Services Gateway.

    .EXAMPLE
    Create area 50 as a normal type on ESG Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | New-NsxEdgeOspfArea -AreaId 50

    .EXAMPLE
    Create area 10 as a nssa type on ESG Edge01 with password authentication

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | New-NsxEdgeOspfArea -AreaId 10 -Type password -Password "Secret"


   
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,4294967295)]
            [uint32]$AreaId,
        [Parameter (Mandatory=$false)]
            [ValidateSet("normal","nssa",IgnoreCase = $false)]
            [string]$Type,
        [Parameter (Mandatory=$false)]
            [ValidateSet("none","password","md5",IgnoreCase = $false)]
            [string]$AuthenticationType="none",
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [string]$Password,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Create private xml element
        $_EdgeRouting = $EdgeRouting.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeRouting.edgeId
        $_EdgeRouting.RemoveChild( $($_EdgeRouting.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Create the new ospfArea element.
        $Area = $_EdgeRouting.ownerDocument.CreateElement('ospfArea')

        #Need to do an xpath query here rather than use PoSH dot notation to get the ospf element,
        #as it might not exist which wil cause PoSH to throw in stric mode.
        $ospf = $_EdgeRouting.SelectSingleNode('descendant::ospf')
        if ( $ospf ) { 
            $ospf.selectSingleNode('descendant::ospfAreas').AppendChild($Area) | Out-Null

            Add-XmlElement -xmlRoot $Area -xmlElementName "areaId" -xmlElementText $AreaId.ToString()

            #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
            #If the user did not specify a given parameter, we dont want to modify from the existing value.
            if ( $PsBoundParameters.ContainsKey("Type") ) { 
                Add-XmlElement -xmlRoot $Area -xmlElementName "type" -xmlElementText $Type.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("AuthenticationType") -or $PsBoundParameters.ContainsKey("Password") ) { 
                switch ($AuthenticationType) {

                    "none" { 
                        if ( $PsBoundParameters.ContainsKey('Password') ) { 
                            throw "Authentication type must be other than none to specify a password."
                        }
                        #Default value - do nothing
                    }

                    default { 
                        if ( -not ( $PsBoundParameters.ContainsKey('Password')) ) {
                            throw "Must specify a password if Authentication type is not none."
                        }
                        $Authentication = $Area.ownerDocument.CreateElement("authentication")
                        $Area.AppendChild( $Authentication ) | out-null

                        Add-XmlElement -xmlRoot $Authentication -xmlElementName "type" -xmlElementText $AuthenticationType
                        Add-XmlElement -xmlRoot $Authentication -xmlElementName "value" -xmlElementText $Password
                    }
                }
            }

            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $_EdgeRouting.OuterXml 
           
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
                Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxEdgeRouting | Get-NsxEdgeOspfArea -AreaId $AreaId
            }
        }
        else {
            throw "OSPF is not enabled on edge $edgeID.  Enable OSPF using Set-NsxEdgeRouting or Set-NsxEdgeOSPF first."
        }
    }

    end {}
}


function Get-NsxEdgeOspfInterface {
    
    <#
    .SYNOPSIS
    Returns OSPF Interface mappings defined in the spcified NSX Edge Services 
    Gateway OSPF configuration.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Get-NsxEdgeOspfInterface cmdlet retreives the OSPF Area to interfaces 
    mappings from the OSPF configuration specified.

    .EXAMPLE
    Get all OSPF Area to Interface mappings on ESG Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeOspfInterface
   
    .EXAMPLE
    Get OSPF Area to Interface mapping for Area 10 on ESG Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeOspfInterface -AreaId 10
   
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,4294967295)]
            [int]$AreaId,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,200)]
            [int]$vNicId    
    )
    
    begin {
    }

    process {
    
        $ospf = $EdgeRouting.SelectSingleNode('descendant::ospf')

        if ( $ospf ) {

            $_ospf = $ospf.CloneNode($True)
            $OspfInterfaces = $_ospf.SelectSingleNode('descendant::ospfInterfaces')


            #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called ospfArea.
            if ( $OspfInterfaces.SelectSingleNode('descendant::ospfInterface')) { 

                $InterfaceCollection = $OspfInterfaces.ospfInterface
                if ( $PsBoundParameters.ContainsKey('AreaId')) {
                    $InterfaceCollection = $InterfaceCollection | ? { $_.areaId -eq $AreaId }
                }

                if ( $PsBoundParameters.ContainsKey('vNicId')) {
                    $InterfaceCollection = $InterfaceCollection | ? { $_.vnic -eq $vNicId }
                }

                foreach ( $Interface in $InterfaceCollection ) { 
                    #We append the Edge-id to the associated Area config XML to enable pipeline workflows and 
                    #consistent readable output
                    Add-XmlElement -xmlRoot $Interface -xmlElementName "edgeId" -xmlElementText $EdgeRouting.EdgeId
                }

                $InterfaceCollection
            }
        }
    }

    end {}
}


function Remove-NsxEdgeOspfInterface {
    
    <#
    .SYNOPSIS
    Removes an OSPF Interface from the specified ESGs OSPF configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Remove-NsxEdgeOspfInterface cmdlet removes a BGP neighbour route from 
    the bgp configuration of the specified Edge Services Gateway.

    Interfaces to be removed can be constructed via a PoSH pipline filter 
    outputing interface objects as produced by Get-NsxEdgeOspfInterface and 
    passing them on the pipeline to Remove-NsxEdgeOspfInterface.
    
    .EXAMPLE
    Remove Interface to Area mapping for area 51 from ESG Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeOspfInterface -AreaId 51 | Remove-NsxEdgeOspfInterface

    .EXAMPLE
    Remove all Interface to Area mappings from ESG Edge01 without confirmation.

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeOspfInterface | Remove-NsxEdgeOspfInterface -confirm:$false

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeOspfInterface $_ })]
            [System.Xml.XmlElement]$OspfInterface,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our Edge
        $edgeId = $OspfInterface.edgeId
        $routing = Get-NsxEdge -objectId $edgeId -connection $connection | Get-NsxEdgeRouting

        #Remove the edgeId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Validate the OSPF node exists on the edge 
        if ( -not $routing.SelectSingleNode('descendant::ospf')) { throw "OSPF is not enabled on ESG $edgeId.  Enable OSPF and try again." }
        if ( -not ($routing.ospf.enabled -eq 'true') ) { throw "OSPF is not enabled on ESG $edgeId.  Enable OSPF and try again." }

        

        $xpathQuery = "//ospfInterfaces/ospfInterface[areaId=`"$($OspfInterface.areaId)`"]"
        write-debug "XPath query for interface nodes to remove is: $xpathQuery"
        $InterfaceToRemove = $routing.ospf.SelectSingleNode($xpathQuery)

        if ( $InterfaceToRemove ) { 

            write-debug "InterfaceToRemove Element is: `n $($InterfaceToRemove.OuterXml | format-xml) "
            $routing.ospf.ospfInterfaces.RemoveChild($InterfaceToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            }
        }
        else {
            Throw "Interface $($OspfInterface.areaId) was not found in routing configuration for Edge $edgeId"
        }
    }

    end {}  
}


function New-NsxEdgeOspfInterface {
    
    <#
    .SYNOPSIS
    Creates a new OSPF Interface to Area mapping and adds it to the specified 
    ESGs OSPF configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The New-NsxEdgeOspfInterface cmdlet adds a new OSPF Area to Interface 
    mapping to the ospf configuration of the specified Edge Services Gateway.

    .EXAMPLE
    Add a mapping for Area 10 to Interface 0 on ESG Edge01

    PS C:\> Get-NsxEdge Edge01 | Get-NsxEdgeRouting | New-NsxEdgeOspfInterface -AreaId 10 -Vnic 0
   
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,4294967295)]
            [uint32]$AreaId,
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,200)]
            [int]$Vnic,
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,255)]
            [int]$HelloInterval,
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,65535)]
            [int]$DeadInterval,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,255)]
            [int]$Priority,
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,65535)]
            [int]$Cost,
        [Parameter (Mandatory=$false)]
            [switch]$IgnoreMTU,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    
    begin {
    }

    process {

        #Create private xml element
        $_EdgeRouting = $EdgeRouting.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeRouting.edgeId
        $_EdgeRouting.RemoveChild( $($_EdgeRouting.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Create the new ospfInterface element.
        $Interface = $_EdgeRouting.ownerDocument.CreateElement('ospfInterface')

        #Need to do an xpath query here rather than use PoSH dot notation to get the ospf element,
        #as it might not exist which wil cause PoSH to throw in stric mode.
        $ospf = $_EdgeRouting.SelectSingleNode('descendant::ospf')
        if ( $ospf ) { 
            $ospf.selectSingleNode('descendant::ospfInterfaces').AppendChild($Interface) | Out-Null

            Add-XmlElement -xmlRoot $Interface -xmlElementName "areaId" -xmlElementText $AreaId.ToString()
            Add-XmlElement -xmlRoot $Interface -xmlElementName "vnic" -xmlElementText $Vnic.ToString()

            #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
            #If the user did not specify a given parameter, we dont want to modify from the existing value.
            if ( $PsBoundParameters.ContainsKey("HelloInterval") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "helloInterval" -xmlElementText $HelloInterval.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("DeadInterval") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "deadInterval" -xmlElementText $DeadInterval.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("Priority") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "priority" -xmlElementText $Priority.ToString()
            }
            
            if ( $PsBoundParameters.ContainsKey("Cost") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "cost" -xmlElementText $Cost.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("IgnoreMTU") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "mtuIgnore" -xmlElementText $IgnoreMTU.ToString().ToLower()
            }

            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $_EdgeRouting.OuterXml 
           
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
                Get-NsxEdge -objectId $EdgeId -connection $connection | Get-NsxEdgeRouting | Get-NsxEdgeOspfInterface -AreaId $AreaId
            }
        }
        else {
            throw "OSPF is not enabled on edge $edgeID.  Enable OSPF using Set-NsxEdgeRouting or Set-NsxEdgeOSPF first."
        }
    }

    end {}
}


# Redistribution Rules

function Get-NsxEdgeRedistributionRule {
    
    <#
    .SYNOPSIS
    Returns dynamic route redistribution rules defined in the spcified NSX Edge
    Services Gateway routing configuration.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Get-NsxEdgeRedistributionRule cmdlet retreives the route redistribution
    rules defined in the ospf and bgp configurations for the specified ESG.

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf

    Get all Redistribution rules for ospf on ESG Edge01
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,
        [Parameter (Mandatory=$false)]
            [ValidateSet("ospf","bgp")]
            [string]$Learner,
        [Parameter (Mandatory=$false)]
            [int]$Id
    )
    
    begin {
    }

    process {
    
        #Rules can be defined in either ospf or bgp (isis as well, but who cares huh? :) )
        if ( ( -not $PsBoundParameters.ContainsKey('Learner')) -or ($PsBoundParameters.ContainsKey('Learner') -and $Learner -eq 'ospf')) {

            $ospf = $EdgeRouting.SelectSingleNode('child::ospf')

            if ( $ospf ) {

                $_ospf = $ospf.CloneNode($True)
                if ( $_ospf.SelectSingleNode('child::redistribution/rules/rule') ) { 

                    $OspfRuleCollection = $_ospf.redistribution.rules.rule

                    foreach ( $rule in $OspfRuleCollection ) { 
                        #We append the Edge-id to the associated rule config XML to enable pipeline workflows and 
                        #consistent readable output
                        Add-XmlElement -xmlRoot $rule -xmlElementName "edgeId" -xmlElementText $EdgeRouting.EdgeId

                        #Add the learner to be consistent with the view the UI gives
                        Add-XmlElement -xmlRoot $rule -xmlElementName "learner" -xmlElementText "ospf"

                    }

                    if ( $PsBoundParameters.ContainsKey('Id')) {
                        $OspfRuleCollection = $OspfRuleCollection | ? { $_.id -eq $Id }
                    }

                    $OspfRuleCollection
                }
            }
        }

        if ( ( -not $PsBoundParameters.ContainsKey('Learner')) -or ($PsBoundParameters.ContainsKey('Learner') -and $Learner -eq 'bgp')) {

            $bgp = $EdgeRouting.SelectSingleNode('child::bgp')
            if ( $bgp ) {

                $_bgp = $bgp.CloneNode($True)
                if ( $_bgp.SelectSingleNode('child::redistribution/rules/rule') ) { 

                    $BgpRuleCollection = $_bgp.redistribution.rules.rule

                    foreach ( $rule in $BgpRuleCollection ) { 
                        #We append the Edge-id to the associated rule config XML to enable pipeline workflows and 
                        #consistent readable output
                        Add-XmlElement -xmlRoot $rule -xmlElementName "edgeId" -xmlElementText $EdgeRouting.EdgeId

                        #Add the learner to be consistent with the view the UI gives
                        Add-XmlElement -xmlRoot $rule -xmlElementName "learner" -xmlElementText "bgp"
                    }

                    if ( $PsBoundParameters.ContainsKey('Id')) {
                        $BgpRuleCollection = $BgpRuleCollection | ? { $_.id -eq $Id }
                    }
                    $BgpRuleCollection
                }
            }
        }
    }

    end {}
}


function Remove-NsxEdgeRedistributionRule {
    
    <#
    .SYNOPSIS
    Removes a route redistribution rule from the specified ESGs  configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The Remove-NsxEdgeRedistributionRule cmdlet removes a route redistribution
    rule from the configuration of the specified Edge Services Gateway.

    Interfaces to be removed can be constructed via a PoSH pipline filter 
    outputing interface objects as produced by Get-NsxEdgeRedistributionRule and 
    passing them on the pipeline to Remove-NsxEdgeRedistributionRule.
  
    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner ospf | Remove-NsxEdgeRedistributionRule

    Remove all ospf redistribution rules from Edge01
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRedistributionRule $_ })]
            [System.Xml.XmlElement]$RedistributionRule,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our Edge
        $edgeId = $RedistributionRule.edgeId
        $routing = Get-NsxEdge -objectId $edgeId -connection $connection | Get-NsxEdgeRouting

        #Remove the edgeId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('child::edgeId')) ) | out-null

        #Validate the learner protocol node exists on the edge 
        if ( -not $routing.SelectSingleNode("child::$($RedistributionRule.learner)")) {
            throw "Rule learner protocol $($RedistributionRule.learner) is not enabled on ESG $edgeId.  Use Get-NsxEdge <this edge> | Get-NsxEdgerouting | Get-NsxEdgeRedistributionRule to get the rule you want to remove." 
        }

        #Make XPath do all the hard work... Wish I was able to just compare the from node, but id doesnt appear possible with xpath 1.0
        $xpathQuery = "child::$($RedistributionRule.learner)/redistribution/rules/rule[action=`"$($RedistributionRule.action)`""
        $xPathQuery += " and from/connected=`"$($RedistributionRule.from.connected)`" and from/static=`"$($RedistributionRule.from.static)`""
        $xPathQuery += " and from/ospf=`"$($RedistributionRule.from.ospf)`" and from/bgp=`"$($RedistributionRule.from.bgp)`""
        $xPathQuery += " and from/isis=`"$($RedistributionRule.from.isis)`""

        if ( $RedistributionRule.SelectSingleNode('child::prefixName')) { 

            $xPathQuery += " and prefixName=`"$($RedistributionRule.prefixName)`""
        }
        
        $xPathQuery += "]"

        write-debug "XPath query for rule node to remove is: $xpathQuery"
        
        $RuleToRemove = $routing.SelectSingleNode($xpathQuery)

        if ( $RuleToRemove ) { 

            write-debug "RuleToRemove Element is: `n $($RuleToRemove | format-xml) "
            $routing.$($RedistributionRule.Learner).redistribution.rules.RemoveChild($RuleToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
            }
        }
        else {
            Throw "Rule Id $($RedistributionRule.Id) was not found in the $($RedistributionRule.Learner) routing configuration for Edge $edgeId"
        }
    }

    end {}
}


function New-NsxEdgeRedistributionRule {
    
    <#
    .SYNOPSIS
    Creates a new route redistribution rule and adds it to the specified ESGs 
    configuration. 

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. Each NSX Edge virtual
    appliance can have a total of ten uplink and internal network interfaces and
    up to 200 subinterfaces.  Multiple external IP addresses can be configured 
    for load balancer, site‐to‐site VPN, and NAT services.

    ESGs perform ipv4 and ipv6 routing functions for connected networks and 
    support both static and dynamic routing via OSPF, ISIS and BGP.

    The New-NsxEdgeRedistributionRule cmdlet adds a new route redistribution 
    rule to the configuration of the specified Edge Services Gateway.

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxEdgeRouting | New-NsxEdgeRedistributionRule -PrefixName test -Learner ospf -FromConnected -FromStatic -Action permit

    Create a new permit Redistribution Rule for prefix test (note, prefix must already exist, and is case sensistive) for ospf.
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-EdgeRouting $_ })]
            [System.Xml.XmlElement]$EdgeRouting,    
        [Parameter (Mandatory=$True)]
            [ValidateSet("ospf","bgp",IgnoreCase=$false)]
            [String]$Learner,
        [Parameter (Mandatory=$false)]
            [String]$PrefixName,    
        [Parameter (Mandatory=$false)]
            [switch]$FromConnected,
        [Parameter (Mandatory=$false)]
            [switch]$FromStatic,
        [Parameter (Mandatory=$false)]
            [switch]$FromOspf,
        [Parameter (Mandatory=$false)]
            [switch]$FromBgp,
        [Parameter (Mandatory=$False)]
            [ValidateSet("permit","deny",IgnoreCase=$false)]
            [String]$Action="permit",  
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    
    begin {
    }

    process {

        #Create private xml element
        $_EdgeRouting = $EdgeRouting.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_EdgeRouting.edgeId
        $_EdgeRouting.RemoveChild( $($_EdgeRouting.SelectSingleNode('child::edgeId')) ) | out-null

        #Need to do an xpath query here rather than use PoSH dot notation to get the protocol element,
        #as it might not exist which wil cause PoSH to throw in stric mode.
        $ProtocolElement = $_EdgeRouting.SelectSingleNode("child::$Learner")

        if ( (-not $ProtocolElement) -or ($ProtocolElement.Enabled -ne 'true')) { 

            throw "The $Learner protocol is not enabled on Edge $edgeId.  Enable it and try again."
        }
        else {
        
            #Create the new rule element. 
            $Rule = $_EdgeRouting.ownerDocument.CreateElement('rule')
            $ProtocolElement.selectSingleNode('child::redistribution/rules').AppendChild($Rule) | Out-Null

            Add-XmlElement -xmlRoot $Rule -xmlElementName "action" -xmlElementText $Action
            if ( $PsBoundParameters.ContainsKey("PrefixName") ) { 
                Add-XmlElement -xmlRoot $Rule -xmlElementName "prefixName" -xmlElementText $PrefixName.ToString()
            }


            #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
            #If the user did not specify a given parameter, we dont want to modify from the existing value.
            if ( $PsBoundParameters.ContainsKey('FromConnected') -or $PsBoundParameters.ContainsKey('FromStatic') -or
                 $PsBoundParameters.ContainsKey('FromOspf') -or $PsBoundParameters.ContainsKey('FromBgp') ) {

                $FromElement = $Rule.ownerDocument.CreateElement('from')
                $Rule.AppendChild($FromElement) | Out-Null

                if ( $PsBoundParameters.ContainsKey("FromConnected") ) { 
                    Add-XmlElement -xmlRoot $FromElement -xmlElementName "connected" -xmlElementText $FromConnected.ToString().ToLower()
                }

                if ( $PsBoundParameters.ContainsKey("FromStatic") ) { 
                    Add-XmlElement -xmlRoot $FromElement -xmlElementName "static" -xmlElementText $FromStatic.ToString().ToLower()
                }
    
                if ( $PsBoundParameters.ContainsKey("FromOspf") ) { 
                    Add-XmlElement -xmlRoot $FromElement -xmlElementName "ospf" -xmlElementText $FromOspf.ToString().ToLower()
                }

                if ( $PsBoundParameters.ContainsKey("FromBgp") ) { 
                    Add-XmlElement -xmlRoot $FromElement -xmlElementName "bgp" -xmlElementText $FromBgp.ToString().ToLower()
                }
            }

            $URI = "/api/4.0/edges/$($EdgeId)/routing/config"
            $body = $_EdgeRouting.OuterXml 
           
            
            if ( $confirm ) { 
                $message  = "Edge Services Gateway routing update will modify existing Edge configuration."
                $question = "Proceed with Update of Edge Services Gateway $($EdgeId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update Edge Services Gateway $($EdgeId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
                (Get-NsxEdge -objectId $EdgeId  -connection $connection | Get-NsxEdgeRouting | Get-NsxEdgeRedistributionRule -Learner $Learner)[-1]
                
            }
        }
    }

    end {}
}


#########
#########
# DLR Routing related functions

function Set-NsxLogicalRouterRouting {
    
    <#
    .SYNOPSIS
    Configures global routing configuration of an existing NSX Logical Router

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Set-NsxLogicalRouterRouting cmdlet configures the global routing 
    configuration of the specified LogicalRouter.
    
    .EXAMPLE
    Get-NsxLogicalRouter | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -DefaultGatewayVnic 0 -DefaultGatewayAddress 10.0.0.101
    
    Configure the default route of the LogicalRouter.
    
    .EXAMPLE
    Get-NsxLogicalRouter | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableECMP
    
    Enable ECMP

    .EXAMPLE
    Get-NsxLogicalRouter | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOSPF -RouterId 1.1.1.1 -ForwardingAddress 1.1.1.1 -ProtocolAddress 1.1.1.2

    Enable OSPF

    .EXAMPLE
    Get-NsxLogicalRouter | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouter | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableBGP -RouterId 1.1.1.1 -LocalAS 1234

    Enable BGP

    .EXAMPLE
    Get-NsxLogicalRouter | Get-NsxLogicalRouterRouting | Set-NsxLogicalRouterRouting -EnableOspfRouteRedistribution:$false -Confirm:$false

    Disable OSPF Route Redistribution without confirmation.
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$EnableOspf,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$ProtocolAddress,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$ForwardingAddress,
        [Parameter (Mandatory=$False)]
            [switch]$EnableBgp,
        [Parameter (Mandatory=$False)]
            [IpAddress]$RouterId,
        [Parameter (MAndatory=$False)]
            [ValidateRange(0,65535)]
            [int]$LocalAS,
        [Parameter (Mandatory=$False)]
            [switch]$EnableEcmp,
        [Parameter (Mandatory=$False)]
            [switch]$EnableOspfRouteRedistribution,
        [Parameter (Mandatory=$False)]
            [switch]$EnableBgpRouteRedistribution,
        [Parameter (Mandatory=$False)]
            [switch]$EnableLogging,
        [Parameter (Mandatory=$False)]
            [ValidateSet("emergency","alert","critical","error","warning","notice","info","debug")]
            [string]$LogLevel,
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,200)]
            [int]$DefaultGatewayVnic,        
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,9128)]
            [int]$DefaultGatewayMTU,        
        [Parameter (Mandatory=$False)]
            [string]$DefaultGatewayDescription,       
        [Parameter (Mandatory=$False)]
            [ipAddress]$DefaultGatewayAddress,
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,255)]
            [int]$DefaultGatewayAdminDistance,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        #Create private xml element
        $_LogicalRouterRouting = $LogicalRouterRouting.CloneNode($true)

        #Store the logicalrouterId and remove it from the XML as we need to post it...
        $logicalrouterId = $_LogicalRouterRouting.logicalrouterId
        $_LogicalRouterRouting.RemoveChild( $($_LogicalRouterRouting.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        if ( $PsBoundParameters.ContainsKey('EnableOSPF') -or $PsBoundParameters.ContainsKey('EnableBGP') ) { 
            $xmlGlobalConfig = $_LogicalRouterRouting.routingGlobalConfig
            $xmlRouterId = $xmlGlobalConfig.SelectSingleNode('child::routerId')
            if ( $EnableOSPF -or $EnableBGP ) {
                if ( -not ($xmlRouterId -or $PsBoundParameters.ContainsKey("RouterId"))) {
                    #Existing config missing and no new value set...
                    throw "RouterId must be configured to enable dynamic routing"
                }

                if ($PsBoundParameters.ContainsKey("RouterId")) {
                    #Set Routerid...
                    if ($xmlRouterId) {
                        $xmlRouterId = $RouterId.IPAddresstoString
                    }
                    else{
                        Add-XmlElement -xmlRoot $xmlGlobalConfig -xmlElementName "routerId" -xmlElementText $RouterId.IPAddresstoString
                    }
                }
            }
        }

        if ( $PsBoundParameters.ContainsKey('EnableOSPF')) { 
            $ospf = $_LogicalRouterRouting.SelectSingleNode('child::ospf') 
            if ( -not $ospf ) {
                #ospf node does not exist.
                [System.XML.XMLElement]$ospf = $_LogicalRouterRouting.ownerDocument.CreateElement("ospf")
                $_LogicalRouterRouting.appendChild($ospf) | out-null
            }

            if ( $ospf.SelectSingleNode('child::enabled')) {
                #Enabled element exists.  Update it.
                $ospf.enabled = $EnableOSPF.ToString().ToLower()
            }
            else {
                #Enabled element does not exist...
                Add-XmlElement -xmlRoot $ospf -xmlElementName "enabled" -xmlElementText $EnableOSPF.ToString().ToLower()
            }

            if ( $EnableOSPF -and (-not ($ProtocolAddress -or ($ospf.SelectSingleNode('child::protocolAddress'))))) {
                throw "ProtocolAddress and ForwardingAddress are required to enable OSPF"
            }

            if ( $EnableOSPF -and (-not ($ForwardingAddress -or ($ospf.SelectSingleNode('child::forwardingAddress'))))) {
                throw "ProtocolAddress and ForwardingAddress are required to enable OSPF"
            }

            if ( $PsBoundParameters.ContainsKey('ProtocolAddress') ) { 
                if ( $ospf.SelectSingleNode('child::protocolAddress')) {
                    # element exists.  Update it.
                    $ospf.protocolAddress = $ProtocolAddress.ToString().ToLower()
                }
                else {
                    #Enabled element does not exist...
                    Add-XmlElement -xmlRoot $ospf -xmlElementName "protocolAddress" -xmlElementText $ProtocolAddress.ToString().ToLower()
                }
            }

            if ( $PsBoundParameters.ContainsKey('ForwardingAddress') ) { 
                if ( $ospf.SelectSingleNode('child::forwardingAddress')) {
                    # element exists.  Update it.
                    $ospf.forwardingAddress = $ForwardingAddress.ToString().ToLower()
                }
                else {
                    #Enabled element does not exist...
                    Add-XmlElement -xmlRoot $ospf -xmlElementName "forwardingAddress" -xmlElementText $ForwardingAddress.ToString().ToLower()
                }
            }
        
        }

        if ( $PsBoundParameters.ContainsKey('EnableBGP')) {

            $bgp = $_LogicalRouterRouting.SelectSingleNode('child::bgp') 

            if ( -not $bgp ) {
                #bgp node does not exist.
                [System.XML.XMLElement]$bgp = $_LogicalRouterRouting.ownerDocument.CreateElement("bgp")
                $_LogicalRouterRouting.appendChild($bgp) | out-null

            }

            if ( $bgp.SelectSingleNode('child::enabled')) {
                #Enabled element exists.  Update it.
                $bgp.enabled = $EnableBGP.ToString().ToLower()
            }
            else {
                #Enabled element does not exist...
                Add-XmlElement -xmlRoot $bgp -xmlElementName "enabled" -xmlElementText $EnableBGP.ToString().ToLower()
            }

            if ( $PsBoundParameters.ContainsKey("LocalAS")) { 
                if ( $bgp.SelectSingleNode('child::localAS')) {
                #LocalAS element exists, update it.
                    $bgp.localAS = $LocalAS.ToString()
                }
                else {
                    #LocalAS element does not exist...
                    Add-XmlElement -xmlRoot $bgp -xmlElementName "localAS" -xmlElementText $LocalAS.ToString()
                }
            }
            elseif ( (-not ( $bgp.SelectSingleNode('child::localAS')) -and $EnableBGP  )) {
                throw "Existing configuration has no Local AS number specified.  Local AS must be set to enable BGP."
            }
            

        }

        if ( $PsBoundParameters.ContainsKey("EnableECMP")) { 
            $_LogicalRouterRouting.routingGlobalConfig.ecmp = $EnableECMP.ToString().ToLower()
        }


        if ( $PsBoundParameters.ContainsKey("EnableOspfRouteRedistribution")) { 

            $_LogicalRouterRouting.ospf.redistribution.enabled = $EnableOspfRouteRedistribution.ToString().ToLower()
        }

        if ( $PsBoundParameters.ContainsKey("EnableBgpRouteRedistribution")) { 
            if ( -not $_LogicalRouterRouting.SelectSingleNode('child::bgp/redistribution/enabled') ) {
                throw "BGP must have been configured at least once to enable/disable BGP route redistribution.  Enable BGP and try again."
            }

            $_LogicalRouterRouting.bgp.redistribution.enabled = $EnableBgpRouteRedistribution.ToString().ToLower()
        }


        if ( $PsBoundParameters.ContainsKey("EnableLogging")) { 
            $_LogicalRouterRouting.routingGlobalConfig.logging.enable = $EnableLogging.ToString().ToLower()
        }

        if ( $PsBoundParameters.ContainsKey("LogLevel")) { 
            $_LogicalRouterRouting.routingGlobalConfig.logging.logLevel = $LogLevel.ToString().ToLower()
        }

        if ( $PsBoundParameters.ContainsKey("DefaultGatewayVnic") -or $PsBoundParameters.ContainsKey("DefaultGatewayAddress") -or 
            $PsBoundParameters.ContainsKey("DefaultGatewayDescription") -or $PsBoundParameters.ContainsKey("DefaultGatewayMTU") -or
            $PsBoundParameters.ContainsKey("DefaultGatewayAdminDistance") ) { 

            #Check for and create if required the defaultRoute element. first.
            if ( -not $_LogicalRouterRouting.staticRouting.SelectSingleNode('child::defaultRoute')) {
                #defaultRoute element does not exist
                $defaultRoute = $_LogicalRouterRouting.ownerDocument.CreateElement('defaultRoute')
                $_LogicalRouterRouting.staticRouting.AppendChild($defaultRoute) | out-null
            }
            else {
                #defaultRoute element exists
                $defaultRoute = $_LogicalRouterRouting.staticRouting.defaultRoute
            }

            if ( $PsBoundParameters.ContainsKey("DefaultGatewayVnic") ) { 
                if ( -not $defaultRoute.SelectSingleNode('child::vnic')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "vnic" -xmlElementText $DefaultGatewayVnic.ToString()
                }
                else {
                    #element exists
                    $defaultRoute.vnic = $DefaultGatewayVnic.ToString()
                }
            }

            if ( $PsBoundParameters.ContainsKey("DefaultGatewayAddress") ) { 
                if ( -not $defaultRoute.SelectSingleNode('child::gatewayAddress')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "gatewayAddress" -xmlElementText $DefaultGatewayAddress.ToString()
                }
                else {
                    #element exists
                    $defaultRoute.gatewayAddress = $DefaultGatewayAddress.ToString()
                }
            }

            if ( $PsBoundParameters.ContainsKey("DefaultGatewayDescription") ) { 
                if ( -not $defaultRoute.SelectSingleNode('child::description')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "description" -xmlElementText $DefaultGatewayDescription
                }
                else {
                    #element exists
                    $defaultRoute.description = $DefaultGatewayDescription
                }
            }
            if ( $PsBoundParameters.ContainsKey("DefaultGatewayMTU") ) { 
                if ( -not $defaultRoute.SelectSingleNode('child::mtu')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "mtu" -xmlElementText $DefaultGatewayMTU.ToString()
                }
                else {
                    #element exists
                    $defaultRoute.mtu = $DefaultGatewayMTU.ToString()
                }
            }
            if ( $PsBoundParameters.ContainsKey("DefaultGatewayAdminDistance") ) { 
                if ( -not $defaultRoute.SelectSingleNode('child::adminDistance')) {
                    #element does not exist
                    Add-XmlElement -xmlRoot $defaultRoute -xmlElementName "adminDistance" -xmlElementText $DefaultGatewayAdminDistance.ToString()
                }
                else {
                    #element exists
                    $defaultRoute.adminDistance = $DefaultGatewayAdminDistance.ToString()
                }
            }
        }


        $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
        $body = $_LogicalRouterRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
            $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            Get-NsxLogicalRouter -objectId $LogicalRouterId -connection $connection | Get-NsxLogicalRouterRouting
        }
    }

    end {}
}


function Get-NsxLogicalRouterRouting {
    
    <#
    .SYNOPSIS
    Retreives routing configuration for the spcified NSX LogicalRouter.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Get-NsxLogicalRouterRouting cmdlet retreives the routing configuration of
    the specified LogicalRouter.
    
    .EXAMPLE
    Get routing configuration for the LogicalRouter LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LogicalRouter $_ })]
            [System.Xml.XmlElement]$LogicalRouter
    )
    
    begin {

    }

    process {
    
        #We append the LogicalRouter-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_LogicalRouterRouting = $LogicalRouter.features.routing.CloneNode($True)
        Add-XmlElement -xmlRoot $_LogicalRouterRouting -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouter.Id
        $_LogicalRouterRouting
    }

    end {}
}


# Static Routing

function Get-NsxLogicalRouterStaticRoute {
    
    <#
    .SYNOPSIS
    Retreives Static Routes from the spcified NSX LogicalRouter Routing 
    configuration.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Get-NsxLogicalRouterStaticRoute cmdlet retreives the static routes from the 
    routing configuration specified.

    .EXAMPLE
    Get static routes defining on LogicalRouter LogicalRouter01

    PS C:\> Get-NsxLogicalRouter | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterStaticRoute
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$Network,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$NextHop       
        
    )
    
    begin {
    }

    process {
    
        #We append the LogicalRouter-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_LogicalRouterStaticRouting = ($LogicalRouterRouting.staticRouting.CloneNode($True))
        $LogicalRouterStaticRoutes = $_LogicalRouterStaticRouting.SelectSingleNode('child::staticRoutes')

        #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called route.
        If ( $LogicalRouterStaticRoutes.SelectSingleNode('child::route')) { 

            $RouteCollection = $LogicalRouterStaticRoutes.route
            if ( $PsBoundParameters.ContainsKey('Network')) {
                $RouteCollection = $RouteCollection | ? { $_.network -eq $Network }
            }

            if ( $PsBoundParameters.ContainsKey('NextHop')) {
                $RouteCollection = $RouteCollection | ? { $_.nextHop -eq $NextHop }
            }

            foreach ( $StaticRoute in $RouteCollection ) { 
                Add-XmlElement -xmlRoot $StaticRoute -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouterRouting.LogicalRouterId
            }

            $RouteCollection
        }
    }

    end {}
}


function New-NsxLogicalRouterStaticRoute {
    
    <#
    .SYNOPSIS
    Creates a new static route and adds it to the specified ESGs routing
    configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The New-NsxLogicalRouterStaticRoute cmdlet adds a new static route to the routing
    configuration of the specified LogicalRouter.

    .EXAMPLE
    Add a new static route to LogicalRouter LogicalRouter01 for 1.1.1.0/24 via 10.0.0.200

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterStaticRoute -Network 1.1.1.0/24 -NextHop 10.0.0.200
    
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,200)]
            [int]$Vnic,        
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,9128)]
            [int]$MTU,        
        [Parameter (Mandatory=$False)]
            [string]$Description,       
        [Parameter (Mandatory=$True)]
            [ipAddress]$NextHop,
        [Parameter (Mandatory=$True)]
            [string]$Network,
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,255)]
            [int]$AdminDistance,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Create private xml element
        $_LogicalRouterRouting = $LogicalRouterRouting.CloneNode($true)

        #Store the logicalrouterId and remove it from the XML as we need to post it...
        $logicalrouterId = $_LogicalRouterRouting.logicalrouterId
        $_LogicalRouterRouting.RemoveChild( $($_LogicalRouterRouting.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        #Create the new route element.
        $Route = $_LogicalRouterRouting.ownerDocument.CreateElement('route')

        #Need to do an xpath query here rather than use PoSH dot notation to get the static route element,
        #as it might be empty, and PoSH silently turns an empty element into a string object, which is rather not what we want... :|
        $StaticRoutes = $_LogicalRouterRouting.staticRouting.SelectSingleNode('child::staticRoutes')
        $StaticRoutes.AppendChild($Route) | Out-Null

        Add-XmlElement -xmlRoot $Route -xmlElementName "network" -xmlElementText $Network.ToString()
        Add-XmlElement -xmlRoot $Route -xmlElementName "nextHop" -xmlElementText $NextHop.ToString()

        if ( $PsBoundParameters.ContainsKey("Vnic") ) { 
            Add-XmlElement -xmlRoot $Route -xmlElementName "vnic" -xmlElementText $Vnic.ToString()
        }

        if ( $PsBoundParameters.ContainsKey("MTU") ) { 
            Add-XmlElement -xmlRoot $Route -xmlElementName "mtu" -xmlElementText $MTU.ToString()
        }

        if ( $PsBoundParameters.ContainsKey("Description") ) { 
            Add-XmlElement -xmlRoot $Route -xmlElementName "description" -xmlElementText $Description.ToString()
        }
    
        if ( $PsBoundParameters.ContainsKey("AdminDistance") ) { 
            Add-XmlElement -xmlRoot $Route -xmlElementName "adminDistance" -xmlElementText $AdminDistance.ToString()
        }


        $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
        $body = $_LogicalRouterRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
            $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            Get-NsxLogicalRouter -objectId $LogicalRouterId -connection $connection | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterStaticRoute -Network $Network -NextHop $NextHop
        }
    }

    end {}
}


function Remove-NsxLogicalRouterStaticRoute {
    
    <#
    .SYNOPSIS
    Removes a static route from the specified ESGs routing configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Remove-NsxLogicalRouterStaticRoute cmdlet removes a static route from the routing
    configuration of the specified LogicalRouter.

    Routes to be removed can be constructed via a PoSH pipline filter outputing
    route objects as produced by Get-NsxLogicalRouterStaticRoute and passing them on the
    pipeline to Remove-NsxLogicalRouterStaticRoute.

    .EXAMPLE
    Remove a route to 1.1.1.0/24 via 10.0.0.100 from LogicalRouter LogicalRouter01
    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterStaticRoute | ? { $_.network -eq '1.1.1.0/24' -and $_.nextHop -eq '10.0.0.100' } | Remove-NsxLogicalRouterStaticRoute

    .EXAMPLE
    Remove all routes to 1.1.1.0/24 from LogicalRouter LogicalRouter01
    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterStaticRoute | ? { $_.network -eq '1.1.1.0/24' } | Remove-NsxLogicalRouterStaticRoute

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterStaticRoute $_ })]
            [System.Xml.XmlElement]$StaticRoute,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our LogicalRouter
        $logicalrouterId = $StaticRoute.logicalrouterId
        $routing = Get-NsxLogicalRouter -objectId $logicalrouterId -connection $connection | Get-NsxLogicalRouterRouting

        #Remove the logicalrouterId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Need to do an xpath query here to query for a route that matches the one passed in.  
        #Union of nextHop and network should be unique
        $xpathQuery = "//staticRoutes/route[nextHop=`"$($StaticRoute.nextHop)`" and network=`"$($StaticRoute.network)`"]"
        write-debug "XPath query for route nodes to remove is: $xpathQuery"
        $RouteToRemove = $routing.staticRouting.SelectSingleNode($xpathQuery)

        if ( $RouteToRemove ) { 

            write-debug "RouteToRemove Element is: `n $($RouteToRemove.OuterXml | format-xml) "
            $routing.staticRouting.staticRoutes.RemoveChild($RouteToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            }
        }
        else {
            Throw "Route for network $($StaticRoute.network) via $($StaticRoute.nextHop) was not found in routing configuration for LogicalRouter $logicalrouterId"
        }
    }

    end {}
}


# Prefixes

function Get-NsxLogicalRouterPrefix {
    
    <#
    .SYNOPSIS
    Retreives IP Prefixes from the spcified NSX LogicalRouter Routing 
    configuration.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Get-NsxLogicalRouterPrefix cmdlet retreives IP prefixes from the 
    routing configuration specified.
    
    .EXAMPLE
    Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterPrefix

    Retrieve prefixes from LogicalRouter LogicalRouter01

    .EXAMPLE
    Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterPrefix -Network 1.1.1.0/24

    Retrieve prefix 1.1.1.0/24 from LogicalRouter LogicalRouter01

    .EXAMPLE
    Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterPrefix -Name CorpNet

    Retrieve prefix CorpNet from LogicalRouter LogicalRouter01
      
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$Network       
        
    )
    
    begin {
    }

    process {
    
        #We append the LogicalRouter-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        $_GlobalRoutingConfig = ($LogicalRouterRouting.routingGlobalConfig.CloneNode($True))
        $IpPrefixes = $_GlobalRoutingConfig.SelectSingleNode('child::ipPrefixes')

        #IPPrefixes may not exist...
        if ( $IPPrefixes ) { 
            #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called ipPrefix.
            If ( $IpPrefixes.SelectSingleNode('child::ipPrefix')) { 

                $PrefixCollection = $IPPrefixes.ipPrefix
                if ( $PsBoundParameters.ContainsKey('Network')) {
                    $PrefixCollection = $PrefixCollection | ? { $_.ipAddress -eq $Network }
                }

                if ( $PsBoundParameters.ContainsKey('Name')) {
                    $PrefixCollection = $PrefixCollection | ? { $_.name -eq $Name }
                }

                foreach ( $Prefix in $PrefixCollection ) { 
                    Add-XmlElement -xmlRoot $Prefix -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouterRouting.LogicalRouterId
                }

                $PrefixCollection
            }
        }
    }

    end {}
}


function New-NsxLogicalRouterPrefix {
    
    <#
    .SYNOPSIS
    Creates a new IP prefix and adds it to the specified ESGs routing
    configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The New-NsxLogicalRouterPrefix cmdlet adds a new IP prefix to the routing
    configuration of the specified LogicalRouter .

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullorEmpty()]
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$True)]
            [ValidateNotNullorEmpty()]
            [string]$Name,       
        [Parameter (Mandatory=$True)]
            [ValidateNotNullorEmpty()]
            [string]$Network,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Create private xml element
        $_LogicalRouterRouting = $LogicalRouterRouting.CloneNode($true)

        #Store the logicalrouterId and remove it from the XML as we need to post it...
        $logicalrouterId = $_LogicalRouterRouting.logicalrouterId
        $_LogicalRouterRouting.RemoveChild( $($_LogicalRouterRouting.SelectSingleNode('child::logicalrouterId')) ) | out-null


        #Need to do an xpath query here rather than use PoSH dot notation to get the IP prefix element,
        #as it might be empty or not exist, and PoSH silently turns an empty element into a string object, which is rather not what we want... :|
        $ipPrefixes = $_LogicalRouterRouting.routingGlobalConfig.SelectSingleNode('child::ipPrefixes')
        if ( -not $ipPrefixes ) { 
            #Create the ipPrefixes element
            $ipPrefixes = $_LogicalRouterRouting.ownerDocument.CreateElement('ipPrefixes')
            $_LogicalRouterRouting.routingGlobalConfig.AppendChild($ipPrefixes) | Out-Null
        }

        #Create the new ipPrefix element.
        $ipPrefix = $_LogicalRouterRouting.ownerDocument.CreateElement('ipPrefix')
        $ipPrefixes.AppendChild($ipPrefix) | Out-Null

        Add-XmlElement -xmlRoot $ipPrefix -xmlElementName "name" -xmlElementText $Name.ToString()
        Add-XmlElement -xmlRoot $ipPrefix -xmlElementName "ipAddress" -xmlElementText $Network.ToString()


        $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
        $body = $_LogicalRouterRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
            $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            Get-NsxLogicalRouter -objectId $LogicalRouterId -connection $connection | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterPrefix -Network $Network -Name $Name
        }
    }

    end {}
}


function Remove-NsxLogicalRouterPrefix {
    
    <#
    .SYNOPSIS
    Removes an IP prefix from the specified ESGs routing configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Remove-NsxLogicalRouterPrefix cmdlet removes a IP prefix from the routing
    configuration of the specified LogicalRouter .

    Prefixes to be removed can be constructed via a PoSH pipline filter outputing
    prefix objects as produced by Get-NsxLogicalRouterPrefix and passing them on the
    pipeline to Remove-NsxLogicalRouterPrefix.

 

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterPrefix $_ })]
            [System.Xml.XmlElement]$Prefix,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection 
    )
    
    begin {
    }

    process {

        #Get the routing config for our LogicalRouter
        $logicalrouterId = $Prefix.logicalrouterId
        $routing = Get-NsxLogicalRouter -objectId $logicalrouterId -connection $connection | Get-NsxLogicalRouterRouting

        #Remove the logicalrouterId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Need to do an xpath query here to query for a prefix that matches the one passed in.  
        #Union of nextHop and network should be unique
        $xpathQuery = "/routingGlobalConfig/ipPrefixes/ipPrefix[name=`"$($Prefix.name)`" and ipAddress=`"$($Prefix.ipAddress)`"]"
        write-debug "XPath query for prefix nodes to remove is: $xpathQuery"
        $PrefixToRemove = $routing.SelectSingleNode($xpathQuery)

        if ( $PrefixToRemove ) { 

            write-debug "PrefixToRemove Element is: `n $($PrefixToRemove.OuterXml | format-xml) "
            $routing.routingGlobalConfig.ipPrefixes.RemoveChild($PrefixToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            }
        }
        else {
            Throw "Prefix $($Prefix.Name) for network $($Prefix.network) was not found in routing configuration for LogicalRouter $logicalrouterId"
        }
    }

    end {}
}



# BGP

function Get-NsxLogicalRouterBgp {
    
    <#
    .SYNOPSIS
    Retreives BGP configuration for the specified NSX LogicalRouter.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Get-NsxLogicalRouterBgp cmdlet retreives the bgp configuration of
    the specified LogicalRouter.
    
    .EXAMPLE
    Get the BGP configuration for LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgp   
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting
    )
    
    begin {

    }

    process {
    
        #We append the LogicalRouter-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        if ( $LogicalRouterRouting.SelectSingleNode('child::bgp')) { 
            $bgp = $LogicalRouterRouting.SelectSingleNode('child::bgp').CloneNode($True)
            Add-XmlElement -xmlRoot $bgp -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouterRouting.LogicalRouterId
            $bgp
        }
    }

    end {}
}


function Set-NsxLogicalRouterBgp {
    
    <#
    .SYNOPSIS
    Manipulates BGP specific base configuration of an existing NSX LogicalRouter.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Set-NsxLogicalRouterBgp cmdlet allows manipulation of the BGP specific configuration
    of a given ESG.
    
   
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$EnableBGP,
        [Parameter (Mandatory=$False)]
            [IpAddress]$RouterId,
        [Parameter (Mandatory=$False)]
            [ValidateRange(0,65535)]
            [int]$LocalAS,
        [Parameter (Mandatory=$False)]
            [switch]$GracefulRestart,
        [Parameter (Mandatory=$False)]
            [switch]$DefaultOriginate,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        #Create private xml element
        $_LogicalRouterRouting = $LogicalRouterRouting.CloneNode($true)

        #Store the logicalrouterId and remove it from the XML as we need to post it...
        $logicalrouterId = $_LogicalRouterRouting.logicalrouterId
        $_LogicalRouterRouting.RemoveChild( $($_LogicalRouterRouting.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        if ( $PsBoundParameters.ContainsKey('EnableBGP') ) { 
            $xmlGlobalConfig = $_LogicalRouterRouting.routingGlobalConfig
            $xmlRouterId = $xmlGlobalConfig.SelectSingleNode('child::routerId')
            if ( $EnableBGP ) {
                if ( -not ($xmlRouterId -or $PsBoundParameters.ContainsKey("RouterId"))) {
                    #Existing config missing and no new value set...
                    throw "RouterId must be configured to enable dynamic routing"
                }

                if ($PsBoundParameters.ContainsKey("RouterId")) {
                    #Set Routerid...
                    if ($xmlRouterId) {
                        $xmlRouterId = $RouterId.IPAddresstoString
                    }
                    else{
                        Add-XmlElement -xmlRoot $xmlGlobalConfig -xmlElementName "routerId" -xmlElementText $RouterId.IPAddresstoString
                    }
                }
            }

            $bgp = $_LogicalRouterRouting.SelectSingleNode('child::bgp') 

            if ( -not $bgp ) {
                #bgp node does not exist.
                [System.XML.XMLElement]$bgp = $_LogicalRouterRouting.ownerDocument.CreateElement("bgp")
                $_LogicalRouterRouting.appendChild($bgp) | out-null
            }

            if ( $bgp.SelectSingleNode('child::enabled')) {
                #Enabled element exists.  Update it.
                $bgp.enabled = $EnableBGP.ToString().ToLower()
            }
            else {
                #Enabled element does not exist...
                Add-XmlElement -xmlRoot $bgp -xmlElementName "enabled" -xmlElementText $EnableBGP.ToString().ToLower()
            }

            if ( $PsBoundParameters.ContainsKey("LocalAS")) { 
                if ( $bgp.SelectSingleNode('child::localAS')) {
                    #LocalAS element exists, update it.
                    $bgp.localAS = $LocalAS.ToString()
                }
                else {
                    #LocalAS element does not exist...
                    Add-XmlElement -xmlRoot $bgp -xmlElementName "localAS" -xmlElementText $LocalAS.ToString()
                }
            }
            elseif ( (-not ( $bgp.SelectSingleNode('child::localAS')) -and $EnableBGP  )) {
                throw "Existing configuration has no Local AS number specified.  Local AS must be set to enable BGP."
            }

            if ( $PsBoundParameters.ContainsKey("GracefulRestart")) { 
                if ( $bgp.SelectSingleNode('child::gracefulRestart')) {
                    #element exists, update it.
                    $bgp.gracefulRestart = $GracefulRestart.ToString().ToLower()
                }
                else {
                    #element does not exist...
                    Add-XmlElement -xmlRoot $bgp -xmlElementName "gracefulRestart" -xmlElementText $GracefulRestart.ToString().ToLower()
                }
            }

            if ( $PsBoundParameters.ContainsKey("DefaultOriginate")) { 
                if ( $bgp.SelectSingleNode('child::defaultOriginate')) {
                    #element exists, update it.
                    $bgp.defaultOriginate = $DefaultOriginate.ToString().ToLower()
                }
                else {
                    #element does not exist...
                    Add-XmlElement -xmlRoot $bgp -xmlElementName "defaultOriginate" -xmlElementText $DefaultOriginate.ToString().ToLower()
                }
            }
        }

        $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
        $body = $_LogicalRouterRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
            $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection 
            write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            Get-NsxLogicalRouter -objectId $LogicalRouterId -connection $connection | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgp
        }
    }

    end {}
}


function Get-NsxLogicalRouterBgpNeighbour {
    
    <#
    .SYNOPSIS
    Returns BGP neighbours from the spcified NSX LogicalRouter BGP 
    configuration.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Get-NsxLogicalRouterBgpNeighbour cmdlet retreives the BGP neighbours from the 
    BGP configuration specified.

    .EXAMPLE
    Get all BGP neighbours defined on LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour
    
    .EXAMPLE
    Get BGP neighbour 1.1.1.1 defined on LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour -IpAddress 1.1.1.1

    .EXAMPLE
    Get all BGP neighbours with Remote AS 1234 defined on LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour | ? { $_.RemoteAS -eq '1234' }

    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [String]$Network,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$IpAddress,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,65535)]
            [int]$RemoteAS              
    )
    
    begin {
    }

    process {
    
        $bgp = $LogicalRouterRouting.SelectSingleNode('child::bgp')

        if ( $bgp ) {

            $_bgp = $bgp.CloneNode($True)
            $BgpNeighbours = $_bgp.SelectSingleNode('child::bgpNeighbours')


            #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called bgpNeighbour.
            if ( $BgpNeighbours.SelectSingleNode('child::bgpNeighbour')) { 

                $NeighbourCollection = $BgpNeighbours.bgpNeighbour
                if ( $PsBoundParameters.ContainsKey('IpAddress')) {
                    $NeighbourCollection = $NeighbourCollection | ? { $_.ipAddress -eq $IpAddress }
                }

                if ( $PsBoundParameters.ContainsKey('RemoteAS')) {
                    $NeighbourCollection = $NeighbourCollection | ? { $_.remoteAS -eq $RemoteAS }
                }

                foreach ( $Neighbour in $NeighbourCollection ) { 
                    #We append the LogicalRouter-id to the associated neighbour config XML to enable pipeline workflows and 
                    #consistent readable output
                    Add-XmlElement -xmlRoot $Neighbour -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouterRouting.LogicalRouterId
                }

                $NeighbourCollection
            }
        }
    }

    end {}
}


function New-NsxLogicalRouterBgpNeighbour {
    
    <#
    .SYNOPSIS
    Creates a new BGP neighbour and adds it to the specified ESGs BGP
    configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The New-NsxLogicalRouterBgpNeighbour cmdlet adds a new BGP neighbour to the 
    bgp configuration of the specified LogicalRouter.

    .EXAMPLE
    Add a new neighbour 1.2.3.4 with remote AS number 1234 with defaults.

    PS C:\> Get-NsxLogicalRouter | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress 1.2.3.4 -RemoteAS 1234 -ForwardingAddress 1.2.3.1 -ProtocolAddress 1.2.3.2

    .EXAMPLE
    Add a new neighbour 1.2.3.4 with remote AS number 22235 specifying weight, holddown and keepalive timers and dont prompt for confirmation.

    PS C:\> Get-NsxLogicalRouter | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterBgpNeighbour -IpAddress 1.2.3.4 -RemoteAS 22235 -ForwardingAddress 1.2.3.1 -ProtocolAddress 1.2.3.2 -Confirm:$false -Weight 90 -HoldDownTimer 240 -KeepAliveTimer 90 -confirm:$false

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$true)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$IpAddress,
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,65535)]
            [int]$RemoteAS,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$ForwardingAddress,
        [Parameter (Mandatory=$true)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$ProtocolAddress,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,65535)]
            [int]$Weight,
        [Parameter (Mandatory=$false)]
            [ValidateRange(2,65535)]
            [int]$HoldDownTimer,
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,65534)]
            [int]$KeepAliveTimer,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [string]$Password,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Create private xml element
        $_LogicalRouterRouting = $LogicalRouterRouting.CloneNode($true)

        #Store the logicalrouterId and remove it from the XML as we need to post it...
        $logicalrouterId = $_LogicalRouterRouting.logicalrouterId
        $_LogicalRouterRouting.RemoveChild( $($_LogicalRouterRouting.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Create the new bgpNeighbour element.
        $Neighbour = $_LogicalRouterRouting.ownerDocument.CreateElement('bgpNeighbour')

        #Need to do an xpath query here rather than use PoSH dot notation to get the bgp element,
        #as it might not exist which wil cause PoSH to throw in stric mode.
        $bgp = $_LogicalRouterRouting.SelectSingleNode('child::bgp')
        if ( $bgp ) { 
            $bgp.selectSingleNode('child::bgpNeighbours').AppendChild($Neighbour) | Out-Null

            Add-XmlElement -xmlRoot $Neighbour -xmlElementName "ipAddress" -xmlElementText $IpAddress.ToString()
            Add-XmlElement -xmlRoot $Neighbour -xmlElementName "remoteAS" -xmlElementText $RemoteAS.ToString()
            Add-XmlElement -xmlRoot $Neighbour -xmlElementName "forwardingAddress" -xmlElementText $ForwardingAddress.ToString()
            Add-XmlElement -xmlRoot $Neighbour -xmlElementName "protocolAddress" -xmlElementText $ProtocolAddress.ToString()


            #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
            #If the user did not specify a given parameter, we dont want to modify from the existing value.
            if ( $PsBoundParameters.ContainsKey("Weight") ) { 
                Add-XmlElement -xmlRoot $Neighbour -xmlElementName "weight" -xmlElementText $Weight.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("HoldDownTimer") ) { 
                Add-XmlElement -xmlRoot $Neighbour -xmlElementName "holdDownTimer" -xmlElementText $HoldDownTimer.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("KeepAliveTimer") ) { 
                Add-XmlElement -xmlRoot $Neighbour -xmlElementName "keepAliveTimer" -xmlElementText $KeepAliveTimer.ToString()
            }


            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $_LogicalRouterRouting.OuterXml 
           
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
                Get-NsxLogicalRouter -objectId $LogicalRouterId -connection $connection | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour -IpAddress $IpAddress -RemoteAS $RemoteAS
            }
        }
        else {
            throw "BGP is not enabled on logicalrouter $logicalrouterID.  Enable BGP using Set-NsxLogicalRouterRouting or Set-NsxLogicalRouterBGP first."
        }
    }

    end {}
}


function Remove-NsxLogicalRouterBgpNeighbour {
    
    <#
    .SYNOPSIS
    Removes a BGP neigbour from the specified ESGs BGP configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Remove-NsxLogicalRouterBgpNeighbour cmdlet removes a BGP neighbour route from the 
    bgp configuration of the specified LogicalRouter Services Gateway.

    Neighbours to be removed can be constructed via a PoSH pipline filter outputing
    neighbour objects as produced by Get-NsxLogicalRouterBgpNeighbour and passing them on the
    pipeline to Remove-NsxLogicalRouterBgpNeighbour.

    .EXAMPLE
    Remove the BGP neighbour 1.1.1.2 from the the logicalrouter LogicalRouter01's bgp configuration

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterBgpNeighbour | ? { $_.ipaddress -eq '1.1.1.2' } |  Remove-NsxLogicalRouterBgpNeighbour 
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterBgpNeighbour $_ })]
            [System.Xml.XmlElement]$BgpNeighbour,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our LogicalRouter
        $logicalrouterId = $BgpNeighbour.logicalrouterId
        $routing = Get-NsxLogicalRouter -objectId $logicalrouterId -connection $connection | Get-NsxLogicalRouterRouting

        #Remove the logicalrouterId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Validate the BGP node exists on the logicalrouter 
        if ( -not $routing.SelectSingleNode('child::bgp')) { throw "BGP is not enabled on ESG $logicalrouterId.  Enable BGP and try again." }

        #Need to do an xpath query here to query for a bgp neighbour that matches the one passed in.  
        #Union of ipaddress and remote AS should be unique (though this is not enforced by the API, 
        #I cant see why having duplicate neighbours with same ip and AS would be useful...maybe 
        #different filters?)
        #Will probably need to include additional xpath query filters here in the query to include 
        #matching on filters to better handle uniquness amongst bgp neighbours with same ip and remoteAS

        $xpathQuery = "//bgpNeighbours/bgpNeighbour[ipAddress=`"$($BgpNeighbour.ipAddress)`" and remoteAS=`"$($BgpNeighbour.remoteAS)`"]"
        write-debug "XPath query for neighbour nodes to remove is: $xpathQuery"
        $NeighbourToRemove = $routing.bgp.SelectSingleNode($xpathQuery)

        if ( $NeighbourToRemove ) { 

            write-debug "NeighbourToRemove Element is: `n $($NeighbourToRemove.OuterXml | format-xml) "
            $routing.bgp.bgpNeighbours.RemoveChild($NeighbourToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            }
        }
        else {
            Throw "Neighbour $($BgpNeighbour.ipAddress) with Remote AS $($BgpNeighbour.RemoteAS) was not found in routing configuration for LogicalRouter $logicalrouterId"
        }
    }

    end {}
}


# OSPF

function Get-NsxLogicalRouterOspf {
    
    <#
    .SYNOPSIS
    Retreives OSPF configuration for the spcified NSX LogicalRouter.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Get-NsxLogicalRouterOspf cmdlet retreives the OSPF configuration of
    the specified LogicalRouter.
    
    .EXAMPLE
    Get the OSPF configuration for LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspf
    
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting
    )
    
    begin {

    }

    process {
    
        #We append the LogicalRouter-id to the associated Routing config XML to enable pipeline workflows and 
        #consistent readable output

        if ( $LogicalRouterRouting.SelectSingleNode('child::ospf')) { 
            $ospf = $LogicalRouterRouting.ospf.CloneNode($True)
            Add-XmlElement -xmlRoot $ospf -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouterRouting.LogicalRouterId
            $ospf
        }
    }

    end {}
}


function Set-NsxLogicalRouterOspf {
    
    <#
    .SYNOPSIS
    Manipulates OSPF specific base configuration of an existing NSX 
    LogicalRouter.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Set-NsxLogicalRouterOspf cmdlet allows manipulation of the OSPF specific 
    configuration of a given ESG.
    
   
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$EnableOSPF,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$ProtocolAddress,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullorEmpty()]
            [ipAddress]$ForwardingAddress,
        [Parameter (Mandatory=$False)]
            [IpAddress]$RouterId,
        [Parameter (Mandatory=$False)]
            [switch]$GracefulRestart,
        [Parameter (Mandatory=$False)]
            [switch]$DefaultOriginate,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        #Create private xml element
        $_LogicalRouterRouting = $LogicalRouterRouting.CloneNode($true)

        #Store the logicalrouterId and remove it from the XML as we need to post it...
        $logicalrouterId = $_LogicalRouterRouting.logicalrouterId
        $_LogicalRouterRouting.RemoveChild( $($_LogicalRouterRouting.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        if ( $PsBoundParameters.ContainsKey('EnableOSPF') ) { 
            $xmlGlobalConfig = $_LogicalRouterRouting.routingGlobalConfig
            $xmlRouterId = $xmlGlobalConfig.SelectSingleNode('child::routerId')
            if ( $EnableOSPF ) {
                if ( -not ($xmlRouterId -or $PsBoundParameters.ContainsKey("RouterId"))) {
                    #Existing config missing and no new value set...
                    throw "RouterId must be configured to enable dynamic routing"
                }

                if ($PsBoundParameters.ContainsKey("RouterId")) {
                    #Set Routerid...
                    if ($xmlRouterId) {
                        $xmlRouterId = $RouterId.IPAddresstoString
                    }
                    else{
                        Add-XmlElement -xmlRoot $xmlGlobalConfig -xmlElementName "routerId" -xmlElementText $RouterId.IPAddresstoString
                    }
                }
            }


            $ospf = $_LogicalRouterRouting.SelectSingleNode('child::ospf') 

            if ( $EnableOSPF -and (-not ($ProtocolAddress -or ($ospf.SelectSingleNode('child::protocolAddress'))))) {
                throw "ProtocolAddress and ForwardingAddress are required to enable OSPF"
            }

            if ( $EnableOSPF -and (-not ($ForwardingAddress -or ($ospf.SelectSingleNode('child::forwardingAddress'))))) {
                throw "ProtocolAddress and ForwardingAddress are required to enable OSPF"
            }

            if ( $PsBoundParameters.ContainsKey('ProtocolAddress') ) { 
                if ( $ospf.SelectSingleNode('child::protocolAddress')) {
                    # element exists.  Update it.
                    $ospf.protocolAddress = $ProtocolAddress.ToString().ToLower()
                }
                else {
                    #Enabled element does not exist...
                    Add-XmlElement -xmlRoot $ospf -xmlElementName "protocolAddress" -xmlElementText $ProtocolAddress.ToString().ToLower()
                }
            }

            if ( $PsBoundParameters.ContainsKey('ForwardingAddress') ) { 
                if ( $ospf.SelectSingleNode('child::forwardingAddress')) {
                    # element exists.  Update it.
                    $ospf.forwardingAddress = $ForwardingAddress.ToString().ToLower()
                }
                else {
                    #Enabled element does not exist...
                    Add-XmlElement -xmlRoot $ospf -xmlElementName "forwardingAddress" -xmlElementText $ForwardingAddress.ToString().ToLower()
                }
            }

            if ( -not $ospf ) {
                #ospf node does not exist.
                [System.XML.XMLElement]$ospf = $_LogicalRouterRouting.ownerDocument.CreateElement("ospf")
                $_LogicalRouterRouting.appendChild($ospf) | out-null
            }

            if ( $ospf.SelectSingleNode('child::enabled')) {
                #Enabled element exists.  Update it.
                $ospf.enabled = $EnableOSPF.ToString().ToLower()
            }
            else {
                #Enabled element does not exist...
                Add-XmlElement -xmlRoot $ospf -xmlElementName "enabled" -xmlElementText $EnableOSPF.ToString().ToLower()
            }

            if ( $PsBoundParameters.ContainsKey("GracefulRestart")) { 
                if ( $ospf.SelectSingleNode('child::gracefulRestart')) {
                    #element exists, update it.
                    $ospf.gracefulRestart = $GracefulRestart.ToString().ToLower()
                }
                else {
                    #element does not exist...
                    Add-XmlElement -xmlRoot $ospf -xmlElementName "gracefulRestart" -xmlElementText $GracefulRestart.ToString().ToLower()
                }
            }

            if ( $PsBoundParameters.ContainsKey("DefaultOriginate")) { 
                if ( $ospf.SelectSingleNode('child::defaultOriginate')) {
                    #element exists, update it.
                    $ospf.defaultOriginate = $DefaultOriginate.ToString().ToLower()
                }
                else {
                    #element does not exist...
                    Add-XmlElement -xmlRoot $ospf -xmlElementName "defaultOriginate" -xmlElementText $DefaultOriginate.ToString().ToLower()
                }
            }
        }

        $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
        $body = $_LogicalRouterRouting.OuterXml 
       
        
        if ( $confirm ) { 
            $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
            $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }    
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            Get-NsxLogicalRouter -objectId $LogicalRouterId -connection $connection | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspf
        }
    }

    end {}
}


function Get-NsxLogicalRouterOspfArea {
    
    <#
    .SYNOPSIS
    Returns OSPF Areas defined in the spcified NSX LogicalRouter OSPF 
    configuration.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Get-NsxLogicalRouterOspfArea cmdlet retreives the OSPF Areas from the OSPF 
    configuration specified.

    .EXAMPLE
    Get all areas defined on LogicalRouter01.

    PS C:\> C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea 
    
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,4294967295)]
            [int]$AreaId              
    )
    
    begin {
    }

    process {
    
        $ospf = $LogicalRouterRouting.SelectSingleNode('child::ospf')

        if ( $ospf ) {

            $_ospf = $ospf.CloneNode($True)
            $OspfAreas = $_ospf.SelectSingleNode('child::ospfAreas')


            #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called ospfArea.
            if ( $OspfAreas.SelectSingleNode('child::ospfArea')) { 

                $AreaCollection = $OspfAreas.ospfArea
                if ( $PsBoundParameters.ContainsKey('AreaId')) {
                    $AreaCollection = $AreaCollection | ? { $_.areaId -eq $AreaId }
                }

                foreach ( $Area in $AreaCollection ) { 
                    #We append the LogicalRouter-id to the associated Area config XML to enable pipeline workflows and 
                    #consistent readable output
                    Add-XmlElement -xmlRoot $Area -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouterRouting.LogicalRouterId
                }

                $AreaCollection
            }
        }
    }

    end {}
}


function Remove-NsxLogicalRouterOspfArea {
    
    <#
    .SYNOPSIS
    Removes an OSPF area from the specified ESGs OSPF configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Remove-NsxLogicalRouterOspfArea cmdlet removes a BGP neighbour route from the 
    bgp configuration of the specified LogicalRouter.

    Areas to be removed can be constructed via a PoSH pipline filter outputing
    area objects as produced by Get-NsxLogicalRouterOspfArea and passing them on the
    pipeline to Remove-NsxLogicalRouterOspfArea.
    
    .EXAMPLE
    Remove area 51 from ospf configuration on LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId 51 | Remove-NsxLogicalRouterOspfArea
    
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterOspfArea $_ })]
            [System.Xml.XmlElement]$OspfArea,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our LogicalRouter
        $logicalrouterId = $OspfArea.logicalrouterId
        $routing = Get-NsxLogicalRouter -objectId $logicalrouterId -connection $connection | Get-NsxLogicalRouterRouting

        #Remove the logicalrouterId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Validate the OSPF node exists on the logicalrouter 
        if ( -not $routing.SelectSingleNode('child::ospf')) { throw "OSPF is not enabled on ESG $logicalrouterId.  Enable OSPF and try again." }
        if ( -not ($routing.ospf.enabled -eq 'true') ) { throw "OSPF is not enabled on ESG $logicalrouterId.  Enable OSPF and try again." }

        

        $xpathQuery = "//ospfAreas/ospfArea[areaId=`"$($OspfArea.areaId)`"]"
        write-debug "XPath query for area nodes to remove is: $xpathQuery"
        $AreaToRemove = $routing.ospf.SelectSingleNode($xpathQuery)

        if ( $AreaToRemove ) { 

            write-debug "AreaToRemove Element is: `n $($AreaToRemove.OuterXml | format-xml) "
            $routing.ospf.ospfAreas.RemoveChild($AreaToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            }
        }
        else {
            Throw "Area $($OspfArea.areaId) was not found in routing configuration for LogicalRouter $logicalrouterId"
        }
    }

    end {}
}


function New-NsxLogicalRouterOspfArea {
    
    <#
    .SYNOPSIS
    Creates a new OSPF Area and adds it to the specified ESGs OSPF 
    configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The New-NsxLogicalRouterOspfArea cmdlet adds a new OSPF Area to the ospf
    configuration of the specified LogicalRouter.

    .EXAMPLE
    Create area 50 as a normal type on ESG LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId 50

    .EXAMPLE
    Create area 10 as a nssa type on ESG LogicalRouter01 with password authentication

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfArea -AreaId 10 -Type password -Password "Secret"


   
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,4294967295)]
            [uint32]$AreaId,
        [Parameter (Mandatory=$false)]
            [ValidateSet("normal","nssa",IgnoreCase = $false)]
            [string]$Type,
        [Parameter (Mandatory=$false)]
            [ValidateSet("none","password","md5",IgnoreCase = $false)]
            [string]$AuthenticationType="none",
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [string]$Password,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Create private xml element
        $_LogicalRouterRouting = $LogicalRouterRouting.CloneNode($true)

        #Store the logicalrouterId and remove it from the XML as we need to post it...
        $logicalrouterId = $_LogicalRouterRouting.logicalrouterId
        $_LogicalRouterRouting.RemoveChild( $($_LogicalRouterRouting.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Create the new ospfArea element.
        $Area = $_LogicalRouterRouting.ownerDocument.CreateElement('ospfArea')

        #Need to do an xpath query here rather than use PoSH dot notation to get the ospf element,
        #as it might not exist which wil cause PoSH to throw in stric mode.
        $ospf = $_LogicalRouterRouting.SelectSingleNode('child::ospf')
        if ( $ospf ) { 
            $ospf.selectSingleNode('child::ospfAreas').AppendChild($Area) | Out-Null

            Add-XmlElement -xmlRoot $Area -xmlElementName "areaId" -xmlElementText $AreaId.ToString()

            #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
            #If the user did not specify a given parameter, we dont want to modify from the existing value.
            if ( $PsBoundParameters.ContainsKey("Type") ) { 
                Add-XmlElement -xmlRoot $Area -xmlElementName "type" -xmlElementText $Type.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("AuthenticationType") -or $PsBoundParameters.ContainsKey("Password") ) { 
                switch ($AuthenticationType) {

                    "none" { 
                        if ( $PsBoundParameters.ContainsKey('Password') ) { 
                            throw "Authentication type must be other than none to specify a password."
                        }
                        #Default value - do nothing
                    }

                    default { 
                        if ( -not ( $PsBoundParameters.ContainsKey('Password')) ) {
                            throw "Must specify a password if Authentication type is not none."
                        }
                        $Authentication = $Area.ownerDocument.CreateElement("authentication")
                        $Area.AppendChild( $Authentication ) | out-null

                        Add-XmlElement -xmlRoot $Authentication -xmlElementName "type" -xmlElementText $AuthenticationType
                        Add-XmlElement -xmlRoot $Authentication -xmlElementName "value" -xmlElementText $Password
                    }
                }
            }

            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $_LogicalRouterRouting.OuterXml 
           
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
                Get-NsxLogicalRouter -objectId $LogicalRouterId -connection $connection | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfArea -AreaId $AreaId
            }
        }
        else {
            throw "OSPF is not enabled on logicalrouter $logicalrouterID.  Enable OSPF using Set-NsxLogicalRouterRouting or Set-NsxLogicalRouterOSPF first."
        }
    }

    end {}
}


function Get-NsxLogicalRouterOspfInterface {
    
    <#
    .SYNOPSIS
    Returns OSPF Interface mappings defined in the spcified NSX LogicalRouter 
    OSPF configuration.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Get-NsxLogicalRouterOspfInterface cmdlet retreives the OSPF Area to interfaces 
    mappings from the OSPF configuration specified.

    .EXAMPLE
    Get all OSPF Area to Interface mappings on LogicalRouter LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfInterface
   
    .EXAMPLE
    Get OSPF Area to Interface mapping for Area 10 on LogicalRouter LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfInterface -AreaId 10
   
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,4294967295)]
            [int]$AreaId,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,200)]
            [int]$vNicId    
    )
    
    begin {
    }

    process {
    
        $ospf = $LogicalRouterRouting.SelectSingleNode('child::ospf')

        if ( $ospf ) {

            $_ospf = $ospf.CloneNode($True)
            $OspfInterfaces = $_ospf.SelectSingleNode('child::ospfInterfaces')


            #Need to use an xpath query here, as dot notation will throw in strict mode if there is not childnode called ospfArea.
            if ( $OspfInterfaces.SelectSingleNode('child::ospfInterface')) { 

                $InterfaceCollection = $OspfInterfaces.ospfInterface
                if ( $PsBoundParameters.ContainsKey('AreaId')) {
                    $InterfaceCollection = $InterfaceCollection | ? { $_.areaId -eq $AreaId }
                }

                if ( $PsBoundParameters.ContainsKey('vNicId')) {
                    $InterfaceCollection = $InterfaceCollection | ? { $_.vnic -eq $vNicId }
                }

                foreach ( $Interface in $InterfaceCollection ) { 
                    #We append the LogicalRouter-id to the associated Area config XML to enable pipeline workflows and 
                    #consistent readable output
                    Add-XmlElement -xmlRoot $Interface -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouterRouting.LogicalRouterId
                }

                $InterfaceCollection
            }
        }
    }

    end {}
}


function Remove-NsxLogicalRouterOspfInterface {
    
    <#
    .SYNOPSIS
    Removes an OSPF Interface from the specified ESGs OSPF configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Remove-NsxLogicalRouterOspfInterface cmdlet removes a BGP neighbour route from 
    the bgp configuration of the specified LogicalRouter.

    Interfaces to be removed can be constructed via a PoSH pipline filter 
    outputing interface objects as produced by Get-NsxLogicalRouterOspfInterface and 
    passing them on the pipeline to Remove-NsxLogicalRouterOspfInterface.
    
    .EXAMPLE
    Remove Interface to Area mapping for area 51 from LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfInterface -AreaId 51 | Remove-NsxLogicalRouterOspfInterface

    .EXAMPLE
    Remove all Interface to Area mappings from LogicalRouter01 without confirmation.

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfInterface | Remove-NsxLogicalRouterOspfInterface -confirm:$false

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterOspfInterface $_ })]
            [System.Xml.XmlElement]$OspfInterface,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our LogicalRouter
        $logicalrouterId = $OspfInterface.logicalrouterId
        $routing = Get-NsxLogicalRouter -objectId $logicalrouterId -connection $connection | Get-NsxLogicalRouterRouting

        #Remove the logicalrouterId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Validate the OSPF node exists on the logicalrouter 
        if ( -not $routing.SelectSingleNode('child::ospf')) { throw "OSPF is not enabled on ESG $logicalrouterId.  Enable OSPF and try again." }
        if ( -not ($routing.ospf.enabled -eq 'true') ) { throw "OSPF is not enabled on ESG $logicalrouterId.  Enable OSPF and try again." }

        

        $xpathQuery = "//ospfInterfaces/ospfInterface[areaId=`"$($OspfInterface.areaId)`"]"
        write-debug "XPath query for interface nodes to remove is: $xpathQuery"
        $InterfaceToRemove = $routing.ospf.SelectSingleNode($xpathQuery)

        if ( $InterfaceToRemove ) { 

            write-debug "InterfaceToRemove Element is: `n $($InterfaceToRemove.OuterXml | format-xml) "
            $routing.ospf.ospfInterfaces.RemoveChild($InterfaceToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            }
        }
        else {
            Throw "Interface $($OspfInterface.areaId) was not found in routing configuration for LogicalRouter $logicalrouterId"
        }
    }

    end {}
}


function New-NsxLogicalRouterOspfInterface {
    
    <#
    .SYNOPSIS
    Creates a new OSPF Interface to Area mapping and adds it to the specified 
    LogicalRouters OSPF configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The New-NsxLogicalRouterOspfInterface cmdlet adds a new OSPF Area to Interface 
    mapping to the ospf configuration of the specified LogicalRouter.

    .EXAMPLE
    Add a mapping for Area 10 to Interface 0 on ESG LogicalRouter01

    PS C:\> Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterOspfInterface -AreaId 10 -Vnic 0
   
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,        
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,4294967295)]
            [uint32]$AreaId,
        [Parameter (Mandatory=$true)]
            [ValidateRange(0,200)]
            [int]$Vnic,
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,255)]
            [int]$HelloInterval,
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,65535)]
            [int]$DeadInterval,
        [Parameter (Mandatory=$false)]
            [ValidateRange(0,255)]
            [int]$Priority,
        [Parameter (Mandatory=$false)]
            [ValidateRange(1,65535)]
            [int]$Cost,
        [Parameter (Mandatory=$false)]
            [switch]$IgnoreMTU,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    
    begin {
    }

    process {

        #Create private xml element
        $_LogicalRouterRouting = $LogicalRouterRouting.CloneNode($true)

        #Store the logicalrouterId and remove it from the XML as we need to post it...
        $logicalrouterId = $_LogicalRouterRouting.logicalrouterId
        $_LogicalRouterRouting.RemoveChild( $($_LogicalRouterRouting.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Create the new ospfInterface element.
        $Interface = $_LogicalRouterRouting.ownerDocument.CreateElement('ospfInterface')

        #Need to do an xpath query here rather than use PoSH dot notation to get the ospf element,
        #as it might not exist which wil cause PoSH to throw in stric mode.
        $ospf = $_LogicalRouterRouting.SelectSingleNode('child::ospf')
        if ( $ospf ) { 
            $ospf.selectSingleNode('child::ospfInterfaces').AppendChild($Interface) | Out-Null

            Add-XmlElement -xmlRoot $Interface -xmlElementName "areaId" -xmlElementText $AreaId.ToString()
            Add-XmlElement -xmlRoot $Interface -xmlElementName "vnic" -xmlElementText $Vnic.ToString()

            #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
            #If the user did not specify a given parameter, we dont want to modify from the existing value.
            if ( $PsBoundParameters.ContainsKey("HelloInterval") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "helloInterval" -xmlElementText $HelloInterval.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("DeadInterval") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "deadInterval" -xmlElementText $DeadInterval.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("Priority") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "priority" -xmlElementText $Priority.ToString()
            }
            
            if ( $PsBoundParameters.ContainsKey("Cost") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "cost" -xmlElementText $Cost.ToString()
            }

            if ( $PsBoundParameters.ContainsKey("IgnoreMTU") ) { 
                Add-XmlElement -xmlRoot $Interface -xmlElementName "mtuIgnore" -xmlElementText $IgnoreMTU.ToString().ToLower()
            }

            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $_LogicalRouterRouting.OuterXml 
           
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
                Get-NsxLogicalRouter -objectId $LogicalRouterId -connection $connection | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterOspfInterface -AreaId $AreaId
            }
        }
        else {
            throw "OSPF is not enabled on logicalrouter $logicalrouterID.  Enable OSPF using Set-NsxLogicalRouterRouting or Set-NsxLogicalRouterOSPF first."
        }
    }

    end {}
}


# Redistribution Rules

function Get-NsxLogicalRouterRedistributionRule {
    
    <#
    .SYNOPSIS
    Returns dynamic route redistribution rules defined in the spcified NSX 
    LogicalRouter routing configuration.

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.
    The Get-NsxLogicalRouterRedistributionRule cmdlet retreives the route 
    redistribution rules defined in the ospf and bgp configurations for the 
    specified LogicalRouter.

    .EXAMPLE
    Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf

    Get all Redistribution rules for ospf on LogicalRouter LogicalRouter01
    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,
        [Parameter (Mandatory=$false)]
            [ValidateSet("ospf","bgp")]
            [string]$Learner,
        [Parameter (Mandatory=$false)]
            [int]$Id
    )
    
    begin {
    }

    process {
    
        #Rules can be defined in either ospf or bgp (isis as well, but who cares huh? :) )
        if ( ( -not $PsBoundParameters.ContainsKey('Learner')) -or ($PsBoundParameters.ContainsKey('Learner') -and $Learner -eq 'ospf')) {

            $ospf = $LogicalRouterRouting.SelectSingleNode('child::ospf')

            if ( $ospf ) {

                $_ospf = $ospf.CloneNode($True)
                if ( $_ospf.SelectSingleNode('child::redistribution/rules/rule') ) { 

                    $OspfRuleCollection = $_ospf.redistribution.rules.rule

                    foreach ( $rule in $OspfRuleCollection ) { 
                        #We append the LogicalRouter-id to the associated rule config XML to enable pipeline workflows and 
                        #consistent readable output
                        Add-XmlElement -xmlRoot $rule -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouterRouting.LogicalRouterId

                        #Add the learner to be consistent with the view the UI gives
                        Add-XmlElement -xmlRoot $rule -xmlElementName "learner" -xmlElementText "ospf"

                    }

                    if ( $PsBoundParameters.ContainsKey('Id')) {
                        $OspfRuleCollection = $OspfRuleCollection | ? { $_.id -eq $Id }
                    }

                    $OspfRuleCollection
                }
            }
        }

        if ( ( -not $PsBoundParameters.ContainsKey('Learner')) -or ($PsBoundParameters.ContainsKey('Learner') -and $Learner -eq 'bgp')) {

            $bgp = $LogicalRouterRouting.SelectSingleNode('child::bgp')
            if ( $bgp ) {

                $_bgp = $bgp.CloneNode($True)
                if ( $_bgp.SelectSingleNode('child::redistribution/rules') ) { 

                    $BgpRuleCollection = $_bgp.redistribution.rules.rule

                    foreach ( $rule in $BgpRuleCollection ) { 
                        #We append the LogicalRouter-id to the associated rule config XML to enable pipeline workflows and 
                        #consistent readable output
                        Add-XmlElement -xmlRoot $rule -xmlElementName "logicalrouterId" -xmlElementText $LogicalRouterRouting.LogicalRouterId

                        #Add the learner to be consistent with the view the UI gives
                        Add-XmlElement -xmlRoot $rule -xmlElementName "learner" -xmlElementText "bgp"
                    }

                    if ( $PsBoundParameters.ContainsKey('Id')) {
                        $BgpRuleCollection = $BgpRuleCollection | ? { $_.id -eq $Id }
                    }
                    $BgpRuleCollection
                }
            }
        }
    }

    end {}
}


function Remove-NsxLogicalRouterRedistributionRule {
    
    <#
    .SYNOPSIS
    Removes a route redistribution rule from the specified LogicalRouters
    configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The Remove-NsxLogicalRouterRedistributionRule cmdlet removes a route 
    redistribution rule from the configuration of the specified LogicalRouter.

    Interfaces to be removed can be constructed via a PoSH pipline filter 
    outputing interface objects as produced by 
    Get-NsxLogicalRouterRedistributionRule and passing them on the pipeline to 
    Remove-NsxLogicalRouterRedistributionRule.
  
    .EXAMPLE
    Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner ospf | Remove-NsxLogicalRouterRedistributionRule

    Remove all ospf redistribution rules from LogicalRouter01
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRedistributionRule $_ })]
            [System.Xml.XmlElement]$RedistributionRule,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {
    }

    process {

        #Get the routing config for our LogicalRouter
        $logicalrouterId = $RedistributionRule.logicalrouterId
        $routing = Get-NsxLogicalRouter -objectId $logicalrouterId -connection $connection | Get-NsxLogicalRouterRouting

        #Remove the logicalrouterId element from the XML as we need to post it...
        $routing.RemoveChild( $($routing.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Validate the learner protocol node exists on the logicalrouter 
        if ( -not $routing.SelectSingleNode("child::$($RedistributionRule.learner)")) {
            throw "Rule learner protocol $($RedistributionRule.learner) is not enabled on LogicalRouter $logicalrouterId.  Use Get-NsxLogicalRouter <this logicalrouter> | Get-NsxLogicalRouterrouting | Get-NsxLogicalRouterRedistributionRule to get the rule you want to remove." 
        }

        #Make XPath do all the hard work... Wish I was able to just compare the from node, but id doesnt appear possible with xpath 1.0
        $xpathQuery = "child::$($RedistributionRule.learner)/redistribution/rules/rule[action=`"$($RedistributionRule.action)`""
        $xPathQuery += " and from/connected=`"$($RedistributionRule.from.connected)`" and from/static=`"$($RedistributionRule.from.static)`""
        $xPathQuery += " and from/ospf=`"$($RedistributionRule.from.ospf)`" and from/bgp=`"$($RedistributionRule.from.bgp)`""
        $xPathQuery += " and from/isis=`"$($RedistributionRule.from.isis)`""

        if ( $RedistributionRule.SelectSingleNode('child::prefixName')) { 

            $xPathQuery += " and prefixName=`"$($RedistributionRule.prefixName)`""
        }
        
        $xPathQuery += "]"

        write-debug "XPath query for rule node to remove is: $xpathQuery"
        
        $RuleToRemove = $routing.SelectSingleNode($xpathQuery)

        if ( $RuleToRemove ) { 

            write-debug "RuleToRemove Element is: `n $($RuleToRemove | format-xml) "
            $routing.$($RedistributionRule.Learner).redistribution.rules.RemoveChild($RuleToRemove) | Out-Null

            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $routing.OuterXml 
       
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
            }
        }
        else {
            Throw "Rule Id $($RedistributionRule.Id) was not found in the $($RedistributionRule.Learner) routing configuration for LogicalRouter $logicalrouterId"
        }
    }

    end {}
}


function New-NsxLogicalRouterRedistributionRule {
    
    <#
    .SYNOPSIS
    Creates a new route redistribution rule and adds it to the specified 
    LogicalRouters configuration. 

    .DESCRIPTION
    An NSX Logical Router is a distributed routing function implemented within
    the ESXi kernel, and optimised for east west routing.

    Logical Routers perform ipv4 and ipv6 routing functions for connected
    networks and support both static and dynamic routing via OSPF and BGP.

    The New-NsxLogicalRouterRedistributionRule cmdlet adds a new route 
    redistribution rule to the configuration of the specified LogicalRouter.

    .EXAMPLE
    Get-NsxLogicalRouter LogicalRouter01 | Get-NsxLogicalRouterRouting | New-NsxLogicalRouterRedistributionRule -PrefixName test -Learner ospf -FromConnected -FromStatic -Action permit

    Create a new permit Redistribution Rule for prefix test (note, prefix must already exist, and is case sensistive) for ospf.
    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LogicalRouterRouting $_ })]
            [System.Xml.XmlElement]$LogicalRouterRouting,    
        [Parameter (Mandatory=$True)]
            [ValidateSet("ospf","bgp",IgnoreCase=$false)]
            [String]$Learner,
        [Parameter (Mandatory=$false)]
            [String]$PrefixName,    
        [Parameter (Mandatory=$false)]
            [switch]$FromConnected,
        [Parameter (Mandatory=$false)]
            [switch]$FromStatic,
        [Parameter (Mandatory=$false)]
            [switch]$FromOspf,
        [Parameter (Mandatory=$false)]
            [switch]$FromBgp,
        [Parameter (Mandatory=$False)]
            [ValidateSet("permit","deny",IgnoreCase=$false)]
            [String]$Action="permit",  
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    
    begin {
    }

    process {

        #Create private xml element
        $_LogicalRouterRouting = $LogicalRouterRouting.CloneNode($true)

        #Store the logicalrouterId and remove it from the XML as we need to post it...
        $logicalrouterId = $_LogicalRouterRouting.logicalrouterId
        $_LogicalRouterRouting.RemoveChild( $($_LogicalRouterRouting.SelectSingleNode('child::logicalrouterId')) ) | out-null

        #Need to do an xpath query here rather than use PoSH dot notation to get the protocol element,
        #as it might not exist which wil cause PoSH to throw in stric mode.
        $ProtocolElement = $_LogicalRouterRouting.SelectSingleNode("child::$Learner")

        if ( (-not $ProtocolElement) -or ($ProtocolElement.Enabled -ne 'true')) { 

            throw "The $Learner protocol is not enabled on LogicalRouter $logicalrouterId.  Enable it and try again."
        }
        else {
        
            #Create the new rule element. 
            $Rule = $_LogicalRouterRouting.ownerDocument.CreateElement('rule')
            $ProtocolElement.selectSingleNode('child::redistribution/rules').AppendChild($Rule) | Out-Null

            Add-XmlElement -xmlRoot $Rule -xmlElementName "action" -xmlElementText $Action
            if ( $PsBoundParameters.ContainsKey("PrefixName") ) { 
                Add-XmlElement -xmlRoot $Rule -xmlElementName "prefixName" -xmlElementText $PrefixName.ToString()
            }


            #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
            #If the user did not specify a given parameter, we dont want to modify from the existing value.
            if ( $PsBoundParameters.ContainsKey('FromConnected') -or $PsBoundParameters.ContainsKey('FromStatic') -or
                 $PsBoundParameters.ContainsKey('FromOspf') -or $PsBoundParameters.ContainsKey('FromBgp') ) {

                $FromElement = $Rule.ownerDocument.CreateElement('from')
                $Rule.AppendChild($FromElement) | Out-Null

                if ( $PsBoundParameters.ContainsKey("FromConnected") ) { 
                    Add-XmlElement -xmlRoot $FromElement -xmlElementName "connected" -xmlElementText $FromConnected.ToString().ToLower()
                }

                if ( $PsBoundParameters.ContainsKey("FromStatic") ) { 
                    Add-XmlElement -xmlRoot $FromElement -xmlElementName "static" -xmlElementText $FromStatic.ToString().ToLower()
                }
    
                if ( $PsBoundParameters.ContainsKey("FromOspf") ) { 
                    Add-XmlElement -xmlRoot $FromElement -xmlElementName "ospf" -xmlElementText $FromOspf.ToString().ToLower()
                }

                if ( $PsBoundParameters.ContainsKey("FromBgp") ) { 
                    Add-XmlElement -xmlRoot $FromElement -xmlElementName "bgp" -xmlElementText $FromBgp.ToString().ToLower()
                }
            }

            $URI = "/api/4.0/edges/$($LogicalRouterId)/routing/config"
            $body = $_LogicalRouterRouting.OuterXml 
           
            
            if ( $confirm ) { 
                $message  = "LogicalRouter routing update will modify existing LogicalRouter configuration."
                $question = "Proceed with Update of LogicalRouter $($LogicalRouterId)?"
                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }    
            else { $decision = 0 } 
            if ($decision -eq 0) {
                Write-Progress -activity "Update LogicalRouter $($LogicalRouterId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
                write-progress -activity "Update LogicalRouter $($LogicalRouterId)" -completed
                (Get-NsxLogicalRouter -objectId $LogicalRouterId -connection $connection | Get-NsxLogicalRouterRouting | Get-NsxLogicalRouterRedistributionRule -Learner $Learner)[-1]
                
            }
        }
    }

    end {}
}


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
            #Get SecurityGroups by objectid
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            #Get SecurityGroups by name
            [string]$name,
        [Parameter (Mandatory=$false)]
            #Scopeid - default globalroot-0
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$false)]
            #Include default system security group
            [switch]$IncludeSystem=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {
     
        if ( -not $objectId ) { 
            #All Security GRoups
            $URI = "/api/2.0/services/securitygroup/scope/$scopeId"
            [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response.SelectSingleNode('descendant::list/securitygroup')) {
                if  ( $Name  ) { 
                    $sg = $response.list.securitygroup | ? { $_.name -eq $name }
                } else {
                    $sg = $response.list.securitygroup
                }
                #Filter default if switch not set
                if ( -not $IncludeSystem ) { 
                    $sg| ? { ( $_.objectId -ne 'securitygroup-1') }
                }
                else { 
                    $sg
                }
            }
        }
        else {

            #Just getting a single Security group
            $URI = "/api/2.0/services/securitygroup/$objectId"
            [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response.SelectSingleNode('descendant::securitygroup')) {
                $sg = $response.securitygroup 
            }
            #Filter default if switch not set
            if ( -not $IncludeSystem ) { 
                $sg | ? { ( $_.objectId -ne 'securitygroup-1') }
            }
            else { 
                $sg
            }
        }
    }

    end {}
}


function New-NsxSecurityGroup   {

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
            [ValidateScript({ Validate-SecurityGroupMember $_ })]
            [object[]]$IncludeMember,
            [Parameter (Mandatory=$false)]
            [ValidateScript({ Validate-SecurityGroupMember $_ })]
            [object[]]$ExcludeMember,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("securitygroup")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        if ( $includeMember ) { 
        
            foreach ( $Member in $IncludeMember) { 

                [System.XML.XMLElement]$xmlMember = $XMLDoc.CreateElement("member")
                $xmlroot.appendChild($xmlMember) | out-null

                #This is probably not safe - need to review all possible input types to confirm.
                if ($Member -is [System.Xml.XmlElement] ) {
                    Add-XmlElement -xmlRoot $xmlMember -xmlElementName "objectId" -xmlElementText $member.objectId
                } else { 
                    Add-XmlElement -xmlRoot $xmlMember -xmlElementName "objectId" -xmlElementText $member.ExtensionData.MoRef.Value
                }
            }
        }   

        if ( $excludeMember ) { 
        
            foreach ( $Member in $ExcludeMember) { 

                [System.XML.XMLElement]$xmlMember = $XMLDoc.CreateElement("excludeMember")
                $xmlroot.appendChild($xmlMember) | out-null

                #This is probably not safe - need to review all possible input types to confirm.
                if ($Member -is [System.Xml.XmlElement] ) {
                    Add-XmlElement -xmlRoot $xmlMember -xmlElementName "objectId" -xmlElementText $member.objectId
                } else { 
                    Add-XmlElement -xmlRoot $xmlMember -xmlElementName "objectId" -xmlElementText $member.ExtensionData.MoRef.Value
                }
            }
        }   

        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/services/securitygroup/bulk/$scopeId"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection

        Get-NsxSecuritygroup -objectId $response -connection $connection
    }
    end {}
}


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
    Get-NsxSecurityGroup TestSG | Remove-NsxSecurityGroup

    Remove the SecurityGroup TestSG
    
    .EXAMPLE
    $sg | Remove-NsxSecurityGroup -confirm:$false

    Remove the SecurityGroup $sg without confirmation.
    
    
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            #SecurityGroup object as returned by get-nsxsecuritygroup
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$SecurityGroup,
        [Parameter (Mandatory=$False)]
            #Disable confirmation prompt
            [switch]$confirm=$true,
        [Parameter (Mandatory=$False)]
            #Force deletion of in use or system objects
            [switch]$force=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection


    )
    
    begin {

    }

    process {

        if (($SecurityGroup.ObjectId -eq 'securitygroup-1') -and ( -not $force)) {
            write-warning "Not removing $($SecurityGroup.Name) as it is a default SecurityGroup.  Use -Force to force deletion." 
        }
        else {
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
                invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
                write-progress -activity "Remove Security Group $($SecurityGroup.Name)" -completed

            }
        }
    }

    end {}
}


function Add-NsxSecurityGroupMember {
    
    <#
    .SYNOPSIS
    Adds a new member to an existing NSX Security Group.

    .DESCRIPTION
    An NSX Security Group is a grouping construct that provides a powerful
    grouping function that can be used in DFW Firewall Rules and the NSX
    Service Composer.

    This cmdlet adds a new member to an existing NSX Security Group.

    A Security Group can consist of Static Includes and Excludes as well as 
    dynamic matching properties.  At this time, this cmdlet supports only static 
    include/exclude members.

    A valid PowerCLI session is required to pass certain types of objects 
    supported by the IncludeMember and ExcludeMember parameters.

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$SecurityGroup,
        [Parameter (Mandatory=$False)]
            [switch]$FailIfExists=$false,
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-SecurityGroupMember $_ })]
            [object[]]$Member,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {
    }

    process {

        if ( $PsBoundParameters.ContainsKey('Member') ) { 
            foreach ( $_Member in $Member) { 

                #This is probably not safe - need to review all possible input types to confirm.
                if ($_Member -is [System.Xml.XmlElement] ) {
                    $MemberMoref = $_Member.objectId
                } else { 
                    $MemberMoref = $_Member.ExtensionData.MoRef.Value
                }

                $URI = "/api/2.0/services/securitygroup/$($securityGroup.objectId)/members/$($MemberMoref)?failIfExists=$($FailIfExists.ToString().ToLower())"
                Write-Progress -activity "Adding member $MemberMoref to Security Group $($securityGroup.objectId)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -connection $connection
                write-progress -activity "Adding member $MemberMoref to Security Group $($securityGroup.objectId)" -completed   
            }
        }   
        Get-NsxSecurityGroup -objectId $SecurityGroup.objectId -connection $connection
    }

    end {}
}


function Remove-NsxSecurityGroupMember {
    
    <#
    .SYNOPSIS
    Removes a member from an existing NSX Security Group.

    .DESCRIPTION
    An NSX Security Group is a grouping construct that provides a powerful
    grouping function that can be used in DFW Firewall Rules and the NSX
    Service Composer.

    This cmdlet removes a member from an existing NSX Security Group.

    A Security Group can consist of Static Includes and Excludes as well as 
    dynamic matching properties.  At this time, this cmdlet supports only static 
    include/exclude members.

    A valid PowerCLI session is required to pass certain types of objects 
    supported by the IncludeMember and ExcludeMember parameters.

    #>

 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$SecurityGroup,
        [Parameter (Mandatory=$False)]
            [switch]$FailIfAbsent=$true,
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-SecurityGroupMember $_ })]
            [object[]]$Member,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {
    }

    process {

        if ( $PsBoundParameters.ContainsKey('Member') ) { 
            foreach ( $_Member in $Member) { 

                #This is probably not safe - need to review all possible input types to confirm.
                if ($_Member -is [System.Xml.XmlElement] ) {
                    $MemberMoref = $_Member.objectId
                } else { 
                    $MemberMoref = $_Member.ExtensionData.MoRef.Value
                }

                $URI = "/api/2.0/services/securitygroup/$($securityGroup.objectId)/members/$($MemberMoref)?failIfAbsent=$($FailIfAbsent.ToString().ToLower())"
                Write-Progress -activity "Deleting member $MemberMoref from Security Group $($securityGroup.objectId)"
                $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
                write-progress -activity "Deleting member $MemberMoref from Security Group $($securityGroup.objectId)" -completed   
            }
        }   
        Get-NsxSecurityGroup -objectId $SecurityGroup.objectId -connection $connection
    }

    end {}
}


function New-NsxSecurityTag {

    <#
    .SYNOPSIS
    Creates a new NSX Security Tag

    .DESCRIPTION
    A NSX Security Tag is a arbitrary string. It is used in other functions of 
    NSX such as Security Groups match criteria. Security Tags are applied to a 
    Virtual Machine.

    This cmdlet creates a new NSX Security Tag

    .EXAMPLE
    PS C:\> New-NSXSecurityTag -name ST-Web-DMZ -description Security Tag for 
    the Web Tier

    #>
    param (

        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [string]$Description,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {

    }
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("securityTag")
        [System.XML.XMLElement]$XmlNodes = $Xmldoc.CreateElement("type")
        $xmlDoc.appendChild($xmlRoot) | out-null
        $xmlRoot.appendChild($xmlnodes) | out-null
        
    
        #Mandatory fields
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "objectTypeName" -xmlElementText "SecurityTag"
        Add-XmlElement -xmlRoot $xmlnodes -xmlElementName "typeName" -xmlElementText "SecurityTag"
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name

        #Optional fields
        if ( $PsBoundParameters.ContainsKey('Description')) {
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText "$Description"
        }

        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/services/securitytags/tag"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection

        #Return our shiny new tag...
        Get-NsxSecurityTag -name $Name -connection $connection
    }
        
    end {}
}


function Get-NsxSecurityTag {

    <#
    .SYNOPSIS
    Retrieves an NSX Security Tag

    .DESCRIPTION
    A NSX Security Tag is a arbitrary string. It is used in other functions of 
    NSX such as Security Groups match criteria. Security Tags are applied to a 
    Virtual Machine.

    This cmdlet retrieves existing NSX Security Tags
    
    .EXAMPLE
    Get-NSXSecurityTag

    Gets all Security Tags
    
    .EXAMPLE
    Get-NSXSecurityTag -name ST-Web-DMZ 

    Gets a specific Security Tag by name
    #>

   param (

        [Parameter (Mandatory=$false, Position=1)]
            #Get Security Tag by name
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            #Get security tag by objectId
            [string]$objectId,
        [Parameter (Mandatory=$false)]
            #Include system security tags
            [switch]$IncludeSystem=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    ) 

 


    process {
     
        if ( -not $PsBoundParameters.ContainsKey('objectId')) { 
            #either all or by name
            $URI = "/api/2.0/services/securitytags/tag"
            [System.Xml.XmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response.SelectSingleNode('descendant::securityTags/securityTag')) { 
                if  ( $PsBoundParameters.ContainsKey('Name')) { 
                    $tags = $response.securitytags.securitytag | ? { $_.name -eq $name }
                } else {
                    $tags = $response.securitytags.securitytag
                }

                if ( -not $IncludeSystem ) { 
                    $tags | ? { ( $_.systemResource -ne 'true') }
                }
                else { 
                    $tags
                }
            }
        }
        else {

            #Just getting a single Security group by object id
            $URI = "/api/2.0/services/securitytags/tag/$objectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response.SelectSingleNode('descendant::securityTag')) { 
                $tags = $response.securitytag
            }

            if ( -not $IncludeSystem ) { 
                $tags | ? { ( $_.systemResource -ne 'true') }
            }
            else { 
                $tags
            }
        }
    }

    end {}
}


function Remove-NsxSecurityTag {

    <#
    .SYNOPSIS
    Removes the specified NSX Security Tag.

    .DESCRIPTION
    A NSX Security Tag is a arbitrary string. It is used in other functions of 
    NSX such as Security Groups match criteria. Security Tags are applied to a 
    Virtual Machine.

    This cmdlet removes the specified NSX Security Tag

    If the object is currently in use the api will return an error.  Use -force 
    to override but be aware that the firewall rulebase will become invalid and 
    will need to be corrected before publish operations will succeed again.

    .EXAMPLE
    PS C:\> Get-NsxSecurityTag TestSecurityTag | Remove-NsxSecurityTag

    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript( { Validate-SecurityTag $_ })]
            [System.Xml.XmlElement]$SecurityTag,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        if (($SecurityTag.systemResource -eq 'true') -and ( -not $force)) {
            write-warning "Not removing $($SecurityTag.Name) as it is a default SecurityTag.  Use -Force to force deletion." 
        }
        else {
            if ( $confirm ) { 
                $message  = "Removal of Security Tags may impact desired Security Posture and expose your infrastructure. Please understand the impact of this change"
                $question = "Proceed with removal of Security Tag $($SecurityTag.Name)?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }
            else { $decision = 0 } 
            if ($decision -eq 0) {
                $URI = "/api/2.0/services/securitytags/tag/$($SecurityTag.objectId)?force=$($Force.ToString().ToLower())"
                
                Write-Progress -activity "Remove Security Tag $($SecurityTag.Name)"
                invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
                write-progress -activity "Remove Security Tag $($SecurityTag.Name)" -completed

            }
        }
    }

    end {}
}


function Get-NsxSecurityTagAssignment {

    <#
    .SYNOPSIS
    This cmdlet is used to retrive a list of virtual machines assigned a
    particular NSX Security Tag.

    .DESCRIPTION
    A NSX Security Tag is a arbitrary string. It is used in other functions of
    NSX such as Security Groups match criteria. Security Tags are applied to a
    Virtual Machine.

    This cmdlet is used to retrive a list of virtual machines assigned a
    particular NSX Security Tag.

    .EXAMPLE
    Get-NsxSecurityTag ST-Web-DMZ | Get-NsxSecurityTagAssignment
    
    Specify a single security tag to find all virtual machines the tag is assigned to.


    .EXAMPLE
    Get-NsxSecurityTag | ? { $_.name -like "*dmz*" } | Get-NsxSecurityTagAssignment
    
    Retrieve all virtual machines that are assigned a security tag containing 'dmz' in the security tag name


    .EXAMPLE
    Get-VM Web-01 | Get-NsxSecurityTagAssignment
    
    Specify a virtual machine to retrieve all the assigned security tags

    #>

    [CmdLetBinding(DefaultParameterSetName="Tag")]

    param (

        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName = "Tag")]
            [ValidateScript( { Validate-SecurityTag $_ })]
            [System.Xml.XmlElement]$SecurityTag,
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName = "VirtualMachine")]
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop]$VirtualMachine,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )


    begin {}
    process {

        switch ( $PSCmdlet.ParameterSetName ) {

            'Tag' {

                $URI = "/api/2.0/services/securitytags/tag/$($SecurityTag.objectId)/vm"
                [System.Xml.XmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection

                if ( $response.SelectSingleNode('descendant::basicinfolist/basicinfo') ) {
                    $nodes = $response.SelectNodes('descendant::basicinfolist/basicinfo')

                    foreach ($node in $nodes) {

                        #Get the VI VM object...
                        $vm = Get-Vm -Server $Connection.VIConnection -id "VirtualMachine-$($node.objectId)"
                        [pscustomobject]@{
                            "SecurityTag" = $SecurityTag;
                            "VirtualMachine" = $vm
                        }
                    }
                }
            }

            'VirtualMachine' {

                #I know this is inneficient, but attempt at refactoring has led down a rabbit hole I dont have time for at the moment.
                # 'Ill be back...''
                $vmMoid = $VirtualMachine.ExtensionData.MoRef.Value
                Write-Progress -activity "Fetching Security Tags assigned to Virtual Machine $($vmMoid)"
                Get-NsxSecurityTag -connection $connection | Get-NsxSecurityTagAssignment -connection $connection | Where-Object {($_.VirtualMachine.id -replace "VirtualMachine-","") -eq $($vmMoid)}
            }
        }
    }

    end {}
}


function New-NsxSecurityTagAssignment {

    <#
    .SYNOPSIS
    This cmdlet assigns is used to assign NSX Security Tags to a virtual machine.

    .DESCRIPTION
    A NSX Security Tag is an arbitrary string. It is used in other functions of
    NSX such as Security Groups match criteria. Security Tags are applied to a
    Virtual Machine.

    This cmdlet is used to assign NSX Security Tags to a virtual machine.

    .EXAMPLE
    Get-VM Web-01 | New-NsxSecurityTagAssignment -ApplyTag -SecurityTag (Get-NsxSecurityTag ST-Web-DMZ)
    
    Assign a single security tag to a virtual machine

    .EXAMPLE
    Get-NsxSecurityTag ST-Web-DMZ | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine (Get-VM Web-01)
    
    Assign a single security tag to a virtual machine

    .EXAMPLE
    Get-VM Web-01 | New-NsxSecurityTagAssignment -ApplyTag -SecurityTag $( Get-NsxSecurityTag | ? {$_.name -like "*prod*"} )
    
    Assign all security tags containing "prod" in the name to a virtual machine

    .EXAMPLE
    Get-NsxSecurityTag | ? { $_.name -like "*dmz*" } | New-NsxSecurityTagAssignment -ApplyToVm -VirtualMachine (Get-VM web01,app01,db01)
    
    Assign all security tags containing "DMZ" in the name to multiple virtual machines

    #>
    [CmdLetBinding(DefaultParameterSetName="VirtualMachine")]

    param (
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName = "VirtualMachine")]
        [Parameter (Mandatory=$true, Position = 1, ParameterSetName = "SecurityTag")]
            [ValidateNotNullorEmpty()]
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop[]]$VirtualMachine,
        [Parameter (Mandatory=$true, Position = 1, ParameterSetName = "VirtualMachine")]
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName = "SecurityTag")]
            [ValidateScript( { Validate-SecurityTag $_ })]
            [System.Xml.XmlElement[]]$SecurityTag,
        [Parameter (Mandatory=$true, ParameterSetName = "VirtualMachine")]
            [switch]$ApplyTag,
        [Parameter (Mandatory=$true, ParameterSetName = "SecurityTag")]
            [switch]$ApplyToVm,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )



    begin {}

    process {

        foreach ( $tag in $SecurityTag) {

            $TagIdentifierString = $Tag.objectid

            foreach ( $vm in $VirtualMachine) { 
                $vmMoid = $vm.ExtensionData.MoRef.Value

                $URI = "/api/2.0/services/securitytags/tag/$($TagIdentifierString)/vm/$($vmMoid)"
                Write-Progress -activity "Adding Security Tag $($TagIdentifierString) to Virtual Machine $($vmMoid)"
                $response = invoke-nsxwebrequest -method "put" -uri $URI -connection $connection
                Write-Progress -activity "Adding Security Tag $TagIdentifierString to Virtual Machine $($vmMoid)" -completed
            }
        }
    }

    end{}
}


function Remove-NsxSecurityTagAssignment {

    <#
    .SYNOPSIS
    This cmdlet is used to remove NSX Security Tags assigned to a virtual machine

    .DESCRIPTION
    A NSX Security Tag is a arbitrary string. It is used in other functions of
    NSX such as Security Groups match criteria. Security Tags are applied to a
    Virtual Machine.

    This cmdlet assigns is used to remove NSX Security Tags assigned to a virtual machine

    .EXAMPLE
    Get-NsxSecurityTag ST-WEB-DMZ | Get-NsxSecurityTagAssigment | Remove-NsxSecurityTagAssignment 
    
    Gets all assigment of Security Tag ST-WEB-DMZ and removes its assignment from all VMs with confirmation.

    .EXAMPLE
    Get-VM Web01 | Get-NsxSecurityTagAssigment | Remove-NsxSecurityTagAssignment 
    
    Removes all security tags assigned to Web01 virtual machine.



    #>
       [CmdLetBinding()]

    param (
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
            [ValidateScript ({ Validate-TagAssignment $_ })]
            [PSCustomObject]$TagAssignment,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}

    process {
    
        if ( $confirm ) { 
            $message  = "Removing Security Tag $($TagAssignment.SecurityTag.Name) from $($TagAssignment.VirtualMachine.name) may impact desired Security Posture and expose your infrastructure."
            $question = "Proceed with removal of Security Tag?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)

        } 
        else { $decision = 0 }

        if ($decision -eq 0) {  

            $URI = "/api/2.0/services/securitytags/tag/$($TagAssignment.SecurityTag.ObjectId)/vm/$($TagAssignment.VirtualMachine.ExtensionData.Moref.Value)"
            Write-Progress -activity "Removing Security Tag $($TagAssignment.SecurityTag.ObjectId) to Virtual Machine $($TagAssignment.VirtualMachine.ExtensionData.Moref.Value)"
            $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
            Write-Progress -activity "Adding Security Tag $($TagAssignment.SecurityTag.ObjectId) to Virtual Machine $($TagAssignment.VirtualMachine.ExtensionData.Moref.Value)" -completed
        }
    }


    end{}
}


function Get-NsxIpSet {

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
            #Objectid of IPSet
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            #Name of IPSet
            [string]$Name,
        [Parameter (Mandatory=$false)]
            #ScopeId of IPSet - default is globalroot-0
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$false)]
            #Return 'Readonly' (system) ipsets as well
            [switch]$IncludeReadOnly=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {
     
        if ( -not $objectID ) { 
            #All IPSets
            $URI = "/api/2.0/services/ipset/scope/$scopeId"
            [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response.SelectSingleNode('descendant::list/ipset')) {
                if ( $name ) {
                    $ipsets = $response.list.ipset | ? { $_.name -eq $name } 
                } else {
                    $ipsets = $response.list.ipset 
                }
            }

            if ( -not $IncludeReadOnly ) { 
                $ipsets | ? { -not ( $_.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]")) }
            }
            else { 
                $ipsets
            }
        }
        else {

            #Just getting a single named Security group
            $URI = "/api/2.0/services/ipset/$objectId"
            [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response.SelectSingleNode('descendant::ipset')) {
                $ipsets = $response.ipset 
            }

            if ( -not $IncludeReadOnly ) { 
                $ipsets | ? { -not ( $_.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]")) }
            }
            else { 
                $ipsets
            }
        }
    }

    end {}
}


function New-NsxIpSet  {
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
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("ipset")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        if ( $IPAddresses ) {
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "value" -xmlElementText $IPaddresses
        }
           
        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/services/ipset/$scopeId"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection

        Get-NsxIPSet -objectid $response -connection $connection
    }
    end {}
}


function Remove-NsxIpSet {

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
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection


    )
    
    begin {

    }

    process {

        if ($ipset.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]") -and ( -not $force)) {
            write-warning "Not removing $($Ipset.Name) as it is set as read-only.  Use -Force to force deletion." 
        }
        else { 
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
                invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
                write-progress -activity "Remove IP Set $($IPSet.Name)" -completed
            }
        }
    }

    end {}
}


function Get-NsxMacSet {

    <#
    .SYNOPSIS
    Retrieves NSX MACSets

    .DESCRIPTION
    An NSX MACSet is a grouping construct that allows for grouping of
    MAC Addresses in a sigle container that can 
    be used either in DFW Firewall Rules or as members of a security 
    group.

    This cmdlet returns MAC Set objects.

    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$false,ParameterSetName="objectId")]
            #Get Mac sets by objectid
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            #Get mac sets by name
            [string]$Name,
        [Parameter (Mandatory=$false)]
            #ScopeId - defaults to globalroot-0
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$false)]
            #Include mac sets with readonly attribute
            [switch]$IncludeReadOnly=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {
     
        if ( -not $objectID ) { 
            #All IPSets
            $URI = "/api/2.0/services/macset/scope/$scopeId"
            [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response.SelectSingleNode('descendant::list/macset')) {
                if ( $name ) {
                    $macsets = $response.list.macset | ? { $_.name -eq $name }
                } else {
                    $macsets = $response.list.macset
                }

                #Filter readonly if switch not set
                if ( -not $IncludeReadOnly ) { 
                    $macsets| ? { -not ( $_.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]")) }
                }
                else { 
                    $macsets
                }
            }
        }
        else {

            #Just getting a single named MACset
            $URI = "/api/2.0/services/macset/$objectId"
            [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response.SelectSingleNode('descendant::macset')) {
                $macsets = $response.macset
            }

            #Filter readonly if switch not set
            if ( -not $IncludeReadOnly ) { 
                $macsets| ? { -not ( $_.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]")) }
            }
            else { 
                $macsets
            }
        }
    }

    end {}
}


function New-NsxMacSet  {
    <#
    .SYNOPSIS
    Creates a new NSX MACSet.

    .DESCRIPTION
    An NSX MACSet is a grouping construct that allows for grouping of
    MAC Addresses in a sigle container that can 
    be used either in DFW Firewall Rules or as members of a security 
    group.

    This cmdlet creates a new MAC Set with the specified parameters.

    MacAddresses is a string that can contain 1 or more MAC Addresses the following
    separated by commas
    Mac address: (eg, 00:00:00:00:00:00)
    

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
            [string]$MacAddresses,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("macset")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        if ( $MacAddresses ) {
            Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "value" -xmlElementText $MacAddresses
        }
           
        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/services/macset/$scopeId"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection

        Get-NsxMacSet -objectid $response -connection $connection
    }
    end {}
}


function Remove-NsxMacSet {

    <#
    .SYNOPSIS
    Removes the specified NSX MacSet.

    .DESCRIPTION
    An NSX MacSet is a grouping construct that allows for grouping of
    Mac Addresses in a sigle container that can 
    be used either in DFW Firewall Rules or as members of a security 
    group.

    This cmdlet removes the specified MAC Set. If the object 
    is currently in use the api will return an error.  Use -force to override
    but be aware that the firewall rulebase will become invalid and will need
    to be corrected before publish operations will succeed again.


    #>
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            #Macset as retrieved by get-nsxmacset to remove
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$MacSet,
        [Parameter (Mandatory=$False)]
            #Set to false to disable prompt on deletion
            [switch]$confirm=$true,
        [Parameter (Mandatory=$False)]
            #Enable force to remove objects in use, or set to readonly (system)
            [switch]$force=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {
    }

    process {

        if ($macset.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]") -and ( -not $force)) {
            write-warning "Not removing $($MacSet.Name) as it is set as read-only.  Use -Force to force deletion." 
        }
        else { 
            if ( $confirm ) { 
                $message  = "MACSet removal is permanent."
                $question = "Proceed with removal of MAC Set $($MACSet.Name)?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }
            else { $decision = 0 } 
            if ($decision -eq 0) {
                if ( $force ) { 
                    $URI = "/api/2.0/services/macset/$($MACSet.objectId)?force=true"
                }
                else {
                    $URI = "/api/2.0/services/macset/$($MACSet.objectId)?force=false"
                }
                
                Write-Progress -activity "Remove MAC Set $($MACSet.Name)"
                invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
                write-progress -activity "Remove MAC Set $($MACSet.Name)" -completed

            }
        }
    }

    end {}
}


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
            #Return service by objectId
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            #Return service by name
            [string]$Name,
        [Parameter (Mandatory=$false,ParameterSetName="Port",Position=1)]
            #Return services that have a either a matching port, or are defiuned by a range into which the specified port falls
            [int]$Port,
        [Parameter (Mandatory=$false)]
            #Scopeid - default is globalroot-0
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$false)]
            #Include services with readonly attribute
            [switch]$IncludeReadOnly=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {

        switch ( $PSCmdlet.ParameterSetName ) {

            "objectId" {

                #Just getting a single named service group
                $URI = "/api/2.0/services/application/$objectId"
                [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
                if ( $response.SelectSingleNode('descendant::application')) {
                    $svcs = $response.application
                    #Filter readonly if switch not set
                    if ( -not $IncludeReadOnly ) { 
                        $svcs| ? { -not ( $_.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]")) }
                    }
                    else { 
                        $svcs
                    }
                }
            }

            "Name" { 
                #All Services
                $URI = "/api/2.0/services/application/scope/$scopeId"
                [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
                if ( $response.SelectSingleNode('descendant::list/application')) {
                    if  ( $name ) { 
                        $svcs = $response.list.application | ? { $_.name -eq $name }
                    } else {
                        $svcs = $response.list.application
                    }
                    #Filter readonly if switch not set
                    if ( -not $IncludeReadOnly ) { 
                        $svcs| ? { -not ( $_.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]")) }
                    }
                    else { 
                        $svcs
                    }
                }
            }

            "Port" {

                # Service by port

                $URI = "/api/2.0/services/application/scope/$scopeId"
                [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
                if ( $response.SelectSingleNode('descendant::list/application')) {        
                    foreach ( $application in $response.list.application ) {

                        if ( $application | get-member -memberType Properties -name element ) {
                            write-debug "$($MyInvocation.MyCommand.Name) : Testing service $($application.name) with ports: $($application.element.value)"

                            #The port configured on a service is stored in element.value and can be
                            #either an int, range (expressed as inta-intb, or a comma separated list of ints and/or ranges
                            #So we split the value on comma, the replace the - with .. in a range, and wrap parentheses arount it
                            #Then, lean on PoSH native range handling to force the lot into an int array... 
                            
                            switch -regex ( $application.element.value ) {

                                "^[\d,-]+$" { 

                                    [string[]]$valarray = $application.element.value.split(",") 
                                    foreach ($val in $valarray)  { 

                                        write-debug "$($MyInvocation.MyCommand.Name) : Converting range expression and expanding: $val"  
                                        [int[]]$ports = invoke-expression ( $val -replace '^(\d+)-(\d+)$','($1..$2)' ) 
                                        #Then test if the port int array contains what we are looking for...
                                        if ( $ports.contains($port) ) { 
                                            write-debug "$($MyInvocation.MyCommand.Name) : Matched Service $($Application.name)"
                                            #Filter readonly if switch not set
                                            if ( -not $IncludeReadOnly ) { 
                                                $application| ? { -not ( $_.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]")) }
                                            }
                                            else { 
                                                $application
                                            }
                                            break
                                        }
                                    }
                                }

                                default { #do nothing, port number is not numeric.... 
                                    write-debug "$($MyInvocation.MyCommand.Name) : Ignoring $($application.name) - non numeric element: $($application.element.applicationProtocol) : $($application.element.value)"
                                }
                            }
                        }
                        else {
                            write-debug "$($MyInvocation.MyCommand.Name) : Ignoring $($application.name) - element not defined"                           
                        }
                    }
                }
            }
        }
    }

    end {}
}


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
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("application")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description
        
        #Create the 'element' element ??? :)
        [System.XML.XMLElement]$xmlElement = $XMLDoc.CreateElement("element")
        $xmlRoot.appendChild($xmlElement) | out-null
        
        Add-XmlElement -xmlRoot $xmlElement -xmlElementName "applicationProtocol" -xmlElementText $Protocol
        Add-XmlElement -xmlRoot $xmlElement -xmlElementName "value" -xmlElementText $Port
           
        #Do the post
        $body = $xmlroot.OuterXml
        $URI = "/api/2.0/services/application/$scopeId"
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection

        Get-NsxService -objectId $response -connection $connection
    }
    end {}
}


function Remove-NsxService {

    <#
    .SYNOPSIS
    Removes the specified NSX Service (aka Application).

    .DESCRIPTION
    An NSX Service defines a service as configured in the NSX Distributed
    Firewall.  

    This cmdlet removes the NSX service specified.

    .EXAMPLE
    Get-NsxService -Name TestService | Remove-NsxService

    Removes the service TestService
    #>    
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$Service,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {

    }

    process {

        if ($Service.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isReadOnly`" and value=`"true`"]") -and ( -not $force)) {
            write-warning "Not removing $($Service.Name) as it is set as read-only.  Use -Force to force deletion." 
        }
        else {
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
                invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
                write-progress -activity "Remove Service $($Service.Name)" -completed

            }
        }
    }

    end {}
}


Function Get-NsxServiceGroup {


    <#
    .SYNOPSIS
    Retrieves a list of NSX Service Groups.

    .DESCRIPTION
    Lists all created NSX Service Groups. Service groups contain a mixture of 
    selected ports to represent a potential grouping of like ports.

    This cmdlet retrieves the service group of the specified configuration.

    .EXAMPLE
    Get-NsxServiceGroup

    Retrieves all NSX Service Groups

    .EXAMPLE
    Get-NsxServiceGroup Heartbeat

    Retrieves the default NSX Service Group called Heartbeat

    .EXAMPLE
    Get-NsxServiceGroup | ? {$_.name -match ("Exchange")} | select name

    Retrieves all Services Groups that have the string "Exchange" in their 
    name property
    e.g:
    ----
    Microsoft Exchange 2003
    MS Exchange 2007 Transport Servers
    MS Exchange 2007 Unified Messaging Centre
    MS Exchange 2007 Client Access Server
    Microsoft Exchange 2007
    MS Exchange 2007 Mailbox Servers
    Microsoft Exchange 2010
    MS Exchange 2010 Client Access Servers
    MS Exchange 2010 Transport Servers
    MS Exchange 2010 Mailbox Servers
    MS Exchange 2010 Unified Messaging Server

    #>
    [CmdLetBinding(DefaultParameterSetName="Name")]
    param (

    [Parameter (Mandatory=$false,Position=1,ParameterSetName="Name")]
        [ValidateNotNullorEmpty()]
        [string]$Name,
    [Parameter (Mandatory=$false)]
        [string]$scopeId="globalroot-0",
    [Parameter (Mandatory=$false,ParameterSetName="objectId")]
        [string]$objectId,
    [Parameter (Mandatory=$False)]
        #PowerNSX Connection object.
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Connection=$defaultNSXConnection

    )

    begin {

    }

    process {

        if ( -not $objectId ) {
            #All Sections

            $URI = "/api/2.0/services/applicationgroup/scope/$scopeId"
            [system.xml.xmlDocument]$response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection


            if ($response.SelectSingleNode("child::list/applicationGroup")){
                $servicegroup = $response.list.applicationGroup
            
                if ($PsBoundParameters.ContainsKey("Name")){
                    $servicegroup | ? {$_.name -eq $name}
                }
                else {
    
                    $servicegroup
                }
            }

        }
        else {

            $URI = "/api/2.0/services/applicationgroup/$objectid"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            
            $response.applicationGroup
        }

    }

    end {}
}


function Get-NsxServiceGroupMember {

    <#
    .SYNOPSIS
    Retrieves a list of services within an NSX Service Groups.

    .DESCRIPTION
    Lists all serivces associated to an NSX Service Groups. Service groups 
    contain a mixture of selected ports to represent a potential grouping 
    of like ports.

    This cmdlet retrieves the member services within a Service Group for 
    specific or all Service Groups

    .EXAMPLE
    Get-NsxServiceGroup | Get-NsxServiceGroupMember

    Retrieves all members of all Service Groups. You are brave.
    
    .EXAMPLE
    Get-NsxServiceGroup Heartbeat | Get-NsxServiceGroupMember

    Retrieves all members of the Service Group Heartbeat
    e.g:

    objectId           : application-70
    objectTypeName     : Application
    vsmUuid            : 42019B98-63EC-995F-6CBB-FF738D027F92
    nodeId             : 0dd7c0dd-a194-4df1-a14b-56a1617c2f0f
    revision           : 2
    type               : type
    name               : Vmware-VCHeartbeat
    scope              : scope
    clientHandle       :
    extendedAttributes :
    isUniversal        : false
    universalRevision  : 0

    objectId           : application-180
    objectTypeName     : Application
    vsmUuid            : 42019B98-63EC-995F-6CBB-FF738D027F92
    nodeId             : 0dd7c0dd-a194-4df1-a14b-56a1617c2f0f
    revision           : 2
    type               : type
    name               : Vmware-Heartbeat-PrimarySecondary
    scope              : scope
    clientHandle       :
    extendedAttributes :
    isUniversal        : false
    universalRevision  : 0



    #>

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-ServiceOrServiceGroup $_ })]
            [System.Xml.XmlElement]$ServiceGroup,
        [Parameter (Mandatory=$false)]
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$false)]
            [string]$objectId,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin{

    }
    process{

        if ($ServiceGroup.SelectSingleNode("child::member")){
            $ServiceGroup.member
        }

    }

    end{}
}


function Remove-NsxServiceGroup {

    <#
    .SYNOPSIS
    Removes the specified NSX Service Group.

    .DESCRIPTION
     A service group is a container that includes Services and other Service
    Groups. These Service Groups are used by the NSX Distributed Firewall 
    when creating firewall rules. They can also be referenced by Service 
    Composer's Security Policies.

    This cmdlet removes the specified Service Group.

    .EXAMPLE
    Get-NsxServiceGroup Heartbeat | Remove-NsxServiceGroup

    This will remove the Service Group Heartbeat. All members of the Service 
    Group are not affected.

    .EXAMPLE
    Get-NsxServiceGroup | Remove-NsxServiceGroup -confirm:$false

    This will retrieve and remove ALL Service Groups without confirmation 
    prompt. 

    #>
    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-ServiceGroup $_ })]
            [System.Xml.XmlElement]$ServiceGroup,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
        )



    begin{

    }
    process{


        if ( $confirm ) {
            $message  = "Service Group removal is permanent."
            $question = "Proceed with removal of Service group $($ServiceGroup.Name)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 }
        if ($decision -eq 0) {
            if ( $force ) {
                $URI = "/api/2.0/services/applicationgroup/$($ServiceGroup.objectid)?force=true"
            }
            else {
                $URI = "/api/2.0/services/applicationgroup/$($ServiceGroup.objectid)?force=false"
            }

            Write-Progress -activity "Remove Service Group $($ServiceGroup.Name)"
            Invoke-NsxRestMethod -method "delete" -uri $URI -connection $connection | out-null
            Write-progress -activity "Remove Service Group $($ServiceGroup.Name)" -completed
        }
    }

    end {}
}


function New-NsxServiceGroup {

    <#
    .SYNOPSIS
    Creates a new Service Group to which new Services or Service Groups can 
    be added.

    .DESCRIPTION
    A service group is a container that includes Services and other Service
    Groups. These Service Groups are used by the NSX Distributed Firewall 
    when creating firewall rules. They can also be referenced by Service 
    Composer's Security Policies.

    .EXAMPLE
    New-NsxServiceGroup PowerNSX-SVG

    Creates a new Service Group called PowerNSX-SVG


    objectId           : applicationgroup-53
    objectTypeName     : ApplicationGroup
    vsmUuid            : 42019B98-63EC-995F-6CBB-FF738D027F92
    nodeId             : 0dd7c0dd-a194-4df1-a14b-56a1617c2f0f
    revision           : 1
    type               : type
    name               : PowerNSX-SVG
    description        :
    scope              : scope
    clientHandle       :
    extendedAttributes :
    isUniversal        : false
    universalRevision  : 0
    inheritanceAllowed : false

    #>

    [CmdletBinding()]
    param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$Description = "",
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {

    }

    process {

        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("applicationGroup")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "description" -xmlElementText $Description

        $body = $xmlroot.OuterXml

        $method = "POST"
        $uri = "/api/2.0/services/applicationgroup/globalroot-0"
        $response = invoke-nsxrestmethod -uri $uri -method $method -body $body -connection $connection

        Get-NsxServiceGroup $Name

    }

    end {}
}


function Add-NsxServiceGroupMember {

    <#
    .SYNOPSIS
    Adds a single Service, numerous Services, or a Service Group to a Service 
    Group

    .DESCRIPTION
    Adds the defined Service or Service Group to an NSX Service Groups. Service
    groups contain a mixture of selected ports to represent a potential 
    grouping of like ports.

    This cmdlet adds the defined Services or Service Groups within a Service 
    Group for specific or all Service Groups

    .EXAMPLE
    PS C:\> Get-NsxServiceGroup Heartbeat | Add-NsxServiceGroupMember -Member $Service1


    PS C:\> get-nsxservicegroup Service-Group-4 | Add-NsxServiceGroupMember $Service1,$Service2

    #>

    param (
        #Mastergroup added from Get-NsxServiceGroup
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-ServiceGroup $_ })]
            [System.Xml.XmlElement]$ServiceGroup,
        [Parameter (Mandatory=$true,Position=1)]
            [ValidateScript({ Validate-ServiceOrServiceGroup $_ })]
            #The [] in XmlElement means it can expect more than one object!
            [System.Xml.XmlElement[]]$Member,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process {

        foreach ($Mem in $Member){
            $URI = "/api/2.0/services/applicationgroup/$($ServiceGroup.objectId)/members/$($Mem.objectId)"
            $response = invoke-nsxrestmethod -method "PUT" -uri $URI -connection $connection
            Write-Progress -activity "Adding Service or Service Group $($Mem) to Service Group $($ServiceGroup)"
        }

    }
    end {}
}

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
        write-debug "$($MyInvocation.MyCommand.Name) : Building source/dest node for $($item.name)"
        #Build the return XML element
        [System.XML.XMLElement]$xmlItem = $XMLDoc.CreateElement($itemType)

        if ( $item -is [system.xml.xmlelement] ) {

            write-debug "$($MyInvocation.MyCommand.Name) : Object $($item.name) is specified as xml element"
            #XML representation of NSX object passed - ipset, sec group or logical switch
            #get appropritate name, value.
            Add-XmlElement -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText $item.objectId
            Add-XmlElement -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText $item.name
            Add-XmlElement -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText $item.objectTypeName
            
        } else {

            write-debug "$($MyInvocation.MyCommand.Name) : Object $($item.name) is specified as supported powercli object"
            #Proper PowerCLI Object passed
            #If passed object is a NIC, we have to do some more digging
            if (  $item -is [VMware.VimAutomation.ViCore.Interop.V1.VirtualDevice.NetworkAdapterInterop] ) {
                   
                write-debug "$($MyInvocation.MyCommand.Name) : Object $($item.name) is vNic"
                #Naming based on DFW UI standard
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText "$($item.parent.name) - $($item.name)"
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText "Vnic"

                #Getting the NIC identifier is a bit of hackery at the moment, if anyone can show me a more deterministic or simpler way, then im all ears. 
                $nicIndex = [array]::indexof($item.parent.NetworkAdapters.name,$item.name)
                if ( -not ($nicIndex -eq -1 )) { 
                    Add-XmlElement -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText "$($item.parent.PersistentId).00$nicINdex"
                } else {
                    throw "Unable to determine nic index in parent object.  Make sure the NIC object is valid"
                }
            }
            else {
                #any other accepted PowerCLI object, we just need to grab details from the moref.
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText $item.name
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText $item.extensiondata.moref.type
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText $item.extensiondata.moref.value 
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
        [switch]$ApplyToDFW,
        [switch]$ApplyToAllEdges

    )


    [System.XML.XMLElement]$xmlReturn = $XMLDoc.CreateElement("appliedToList")
    #Iterate the appliedTo passed and build appliedTo nodes.
    #$xmlRoot.appendChild($xmlReturn) | out-null


    foreach ($item in $itemlist) {
        write-debug "$($MyInvocation.MyCommand.Name) : Building appliedTo node for $($item.name)"
        #Build the return XML element
        [System.XML.XMLElement]$xmlItem = $XMLDoc.CreateElement("appliedTo")

        if ( $item -is [system.xml.xmlelement] ) {

            write-debug "$($MyInvocation.MyCommand.Name) : Object $($item.name) is specified as xml element"
            
            if ( $item.SelectSingleNode('descendant::edgeSummary')) { 

                write-debug "$($MyInvocation.MyCommand.Name) : Object $($item.name) is an edge object"

                if ( $ApplyToAllEdges ) {
                    #Apply to all edges is default off, so this means the user asked for something stupid
                    throw "Cant specify Edge Object in applied to list and ApplyToAllEdges simultaneously."
                }

                #We have an edge, and edges have the details we need in their EdgeSummary element:
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText $item.edgeSummary.objectId
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText $item.edgeSummary.name
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText $item.edgeSummary.objectTypeName


            }
            else {

                #Something specific passed in applied to list, turn off Apply to DFW.
                $ApplyToDFW = $false

                #XML representation of NSX object passed - ipset, sec group or logical switch
                #get appropritate name, value.
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText $item.objectId
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText $item.name
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText $item.objectTypeName
            }   
        } 
        else {

            write-debug "$($MyInvocation.MyCommand.Name) : Object $($item.name) is specified as supported powercli object"
            #Proper PowerCLI Object passed
            #If passed object is a NIC, we have to do some more digging
            if (  $item -is [VMware.VimAutomation.ViCore.Interop.V1.VirtualDevice.NetworkAdapterInterop] ) {
               
                write-debug "$($MyInvocation.MyCommand.Name) : Object $($item.name) is vNic"
                #Naming based on DFW UI standard
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText "$($item.parent.name) - $($item.name)"
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText "Vnic"

                #Getting the NIC identifier is a bit of hackery at the moment, if anyone can show me a more deterministic or simpler way, then im all ears. 
                $nicIndex = [array]::indexof($item.parent.NetworkAdapters.name,$item.name)
                if ( -not ($nicIndex -eq -1 )) { 
                    Add-XmlElement -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText "$($item.parent.PersistentId).00$nicINdex"
                } else {
                    throw "Unable to determine nic index in parent object.  Make sure the NIC object is valid"
                }
            }
            else {
                #any other accepted PowerCLI object, we just need to grab details from the moref.
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "name" -xmlElementText $item.name
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "type" -xmlElementText $item.extensiondata.moref.type
                Add-XmlElement -xmlRoot $xmlItem -xmlElementName "value" -xmlElementText $item.extensiondata.moref.value 
            }
        }

        $xmlReturn.appendChild($xmlItem) | out-null
    }

    if ( $ApplyToDFW ) {

        [System.XML.XMLElement]$xmlAppliedTo = $XMLDoc.CreateElement("appliedTo")
        $xmlReturn.appendChild($xmlAppliedTo) | out-null
        Add-XmlElement -xmlRoot $xmlAppliedTo -xmlElementName "name" -xmlElementText "DISTRIBUTED_FIREWALL"
        Add-XmlElement -xmlRoot $xmlAppliedTo -xmlElementName "type" -xmlElementText "DISTRIBUTED_FIREWALL"
        Add-XmlElement -xmlRoot $xmlAppliedTo -xmlElementName "value" -xmlElementText "DISTRIBUTED_FIREWALL"
    }

    if ( $ApplyToAllEdges ) {
    
        [System.XML.XMLElement]$xmlAppliedTo = $XMLDoc.CreateElement("appliedTo")
        $xmlReturn.appendChild($xmlAppliedTo) | out-null
        Add-XmlElement -xmlRoot $xmlAppliedTo -xmlElementName "name" -xmlElementText "ALL_EDGES"
        Add-XmlElement -xmlRoot $xmlAppliedTo -xmlElementName "type" -xmlElementText "ALL_EDGES"
        Add-XmlElement -xmlRoot $xmlAppliedTo -xmlElementName "value" -xmlElementText "ALL_EDGES"
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
            [string]$sectionType="layer3sections",
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {
     
        if ( -not $objectID ) { 
            #All Sections

            $URI = "/api/4.0/firewall/$scopeID/config"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection

            $return = $response.firewallConfiguration.$sectiontype.section

            if ($name) {
                $return | ? {$_.name -eq $name} 
            }else {
            
                $return
            }

        }
        else {
            
            $URI = "/api/4.0/firewall/$scopeID/config/$sectionType/$objectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            $response.section
        }

    }

    end {}
}


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
            [string]$scopeId="globalroot-0",
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 


        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRoot = $XMLDoc.CreateElement("section")
        $xmlDoc.appendChild($xmlRoot) | out-null

        Add-XmlElement -xmlRoot $xmlRoot -xmlElementName "name" -xmlElementText $Name
           
        #Do the post
        $body = $xmlroot.OuterXml
        
        $URI = "/api/4.0/firewall/$scopeId/config/$sectionType"
        
        $response = invoke-nsxrestmethod -method "post" -uri $URI -body $body -connection $connection

        $response.section
        
    }
    end {}
}


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
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
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
            if ( $Section.Name -match 'Default Section' ) {
                write-warning "Will not delete $($Section.Name)."
            }
                else { 
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
                invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
                write-progress -activity "Remove Section $($Section.Name)" -completed
            }
        }
    }

    end {}
}


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
        [Parameter (Mandatory=$false, Position=1)]
            [ValidateNotNullorEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true,ParameterSetName="RuleId")]
        [ValidateNotNullOrEmpty()]
            [string]$RuleId,
        [Parameter (Mandatory=$false)]
            [string]$ScopeId="globalroot-0",
        [Parameter (Mandatory=$false)]
            [ValidateSet("layer3sections","layer2sections","layer3redirectsections",ignorecase=$false)]
            [string]$RuleType="layer3sections",
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {
     
        if ( $PSCmdlet.ParameterSetName -eq "Section" ) { 

            $URI = "/api/4.0/firewall/$scopeID/config/$ruletype/$($Section.Id)"
            
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ( $response | get-member -name Section -Membertype Properties){
                if ( $response.Section | get-member -name Rule -Membertype Properties ){
                    if ( $PsBoundParameters.ContainsKey("Name") ) { 
                        $response.section.rule | ? { $_.name -eq $Name }
                    }
                    else {
                        $response.section.rule
                    }
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

            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ($response.firewallConfiguration) { 
                if ( $PsBoundParameters.ContainsKey("Name") ) { 
                    $response.firewallConfiguration.layer3Sections.Section.rule | ? { $_.name -eq $Name }
                }
                else {
                    $response.firewallConfiguration.layer3Sections.Section.rule
                }

            } 
            elseif ( $response.filteredfirewallConfiguration ) { 
                if ( $PsBoundParameters.ContainsKey("Name") ) { 
                    $response.filteredfirewallConfiguration.layer3Sections.Section.rule | ? { $_.name -eq $Name }
                }
                else {
                    $response.filteredfirewallConfiguration.layer3Sections.Section.rule
                }
            }
            else { throw "Invalid response from NSX API. $response"}
        }
    }

    end {}
}


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
            [ValidateScript({ Validate-FirewallRuleSourceDest $_ })]
            [object[]]$Source,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$NegateSource,
        [Parameter (Mandatory=$false)]
            [ValidateScript({ Validate-FirewallRuleSourceDest $_ })]
            [object[]]$Destination,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [switch]$NegateDestination,
        [Parameter (Mandatory=$false)]
            [ValidateScript ({ Validate-Service $_ })]
            [System.Xml.XmlElement[]]$Service,
        [Parameter (Mandatory=$false)]
            [string]$Comment="",
        [Parameter (Mandatory=$false)]
            [switch]$EnableLogging,  
        [Parameter (Mandatory=$false)]
            [ValidateScript({ Validate-FirewallAppliedTo $_ })]
            [object[]]$AppliedTo,
        [Parameter (Mandatory=$false)]
            [switch]$ApplyToDfw=$true,
        [Parameter (Mandatory=$false)]
            [switch]$ApplyToAllEdges=$false,
        [Parameter (Mandatory=$false)]
            [ValidateSet("layer3sections","layer2sections","layer3redirectsections",ignorecase=$false)]
            [string]$RuleType="layer3sections",
        [Parameter (Mandatory=$false)]
            [ValidateSet("Top","Bottom")]
            [string]$Position="Top",    
        [Parameter (Mandatory=$false)]
            [ValidateNotNullorEmpty()]
            [string]$Tag,
        [Parameter (Mandatory=$false)]
            [string]$ScopeId="globalroot-0",
        [Parameter (Mandatory=$false)]
            #Specifies that New-NsxFirewall rule will return the actual rule that was created rather than the deprecated behaviour of returning the complete containing section
            #This option exists to allow existing scripts that use this function to be easily updated to set it to $false and continue working (For now!).
            #This option is deprecated and will be removed in a future version.
            [switch]$ReturnRule=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        
        $generationNumber = $section.generationNumber           

        write-debug "$($MyInvocation.MyCommand.Name) : Preparing rule for section $($section.Name) with generationId $generationNumber"
        #Create the XMLRoot
        [System.XML.XMLDocument]$xmlDoc = New-Object System.XML.XMLDocument
        [System.XML.XMLElement]$xmlRule = $XMLDoc.CreateElement("rule")
        $xmlDoc.appendChild($xmlRule) | out-null

        Add-XmlElement -xmlRoot $xmlRule -xmlElementName "name" -xmlElementText $Name
        #Add-XmlElement -xmlRoot $xmlRule -xmlElementName "sectionId" -xmlElementText $($section.Id)
        Add-XmlElement -xmlRoot $xmlRule -xmlElementName "notes" -xmlElementText $Comment
        Add-XmlElement -xmlRoot $xmlRule -xmlElementName "action" -xmlElementText $action
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
                Add-XmlElement -xmlRoot $xmlService -xmlElementName "value" -xmlElementText $serviceItem.objectId   
        
            }
        }

        #Applied To
        if ( -not $PsBoundParameters.ContainsKey('AppliedTo')) { 
            $xmlAppliedToList = New-NsxAppliedToListNode -xmlDoc $xmlDoc -ApplyToDFW:$ApplyToDfw -ApplyToAllEdges:$ApplyToAllEdges 
        }
        else {
            $xmlAppliedToList = New-NsxAppliedToListNode -itemlist $AppliedTo -xmlDoc $xmlDoc -ApplyToDFW:$ApplyToDfw -ApplyToAllEdges:$ApplyToAllEdges
        }
        $xmlRule.appendChild($xmlAppliedToList) | out-null

        #Tag
        if ( $tag ) {

            Add-XmlElement -xmlRoot $xmlRule -xmlElementName "tag" -xmlElementText $tag
        }


        #GetThe existing rule Ids and store them - we check for a rule that isnt contained here in the response so we can presnet back to user with rule id
        if ( $Section.SelectSingleNode("child::rule") )  { 
            $ExistingIds = @($Section.rule.id)
        }
        else {
            $ExistingIds = @()
        }


        #Append the new rule to the section
        $xmlrule = $Section.ownerDocument.ImportNode($xmlRule, $true)
        switch ($Position) {
            "Top" { $Section.prependchild($xmlRule) | Out-Null }
            "Bottom" { $Section.appendchild($xmlRule) | Out-Null }
        
        }
        #Do the post
        $body = $Section.OuterXml
        $URI = "/api/4.0/firewall/$scopeId/config/$ruletype/$($section.Id)"
        
        #Need the IfMatch header to specify the current section generation id
    
        $IfMatchHeader = @{"If-Match"=$generationNumber}
        $response = invoke-nsxrestmethod -method "put" -uri $URI -body $body -extraheader $IfMatchHeader -connection $connection

        if ( $ReturnRule ) { 
            $response.section.rule | where { ( -not ($ExistingIds.Contains($_.id))) }
        }
        else {
            $response.section
            write-warning 'The -ReturnRule:$false option is deprecated and will be removed in a future version.  Please update your scripts so that they accept the return object of New-NsxFirewallRule to be the newly created rule rather than the full section.'
        }
    }
    end {}
}



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
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
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
        
            $section = get-nsxFirewallSection $Rule.parentnode.name -connection $connection
            $generationNumber = $section.generationNumber
            $IfMatchHeader = @{"If-Match"=$generationNumber}
            $URI = "/api/4.0/firewall/globalroot-0/config/$($Section.ParentNode.name.tolower())/$($Section.Id)/rules/$($Rule.id)"
          
            
            Write-Progress -activity "Remove Rule $($Rule.Name)"
            invoke-nsxrestmethod -method "delete" -uri $URI  -extraheader $IfMatchHeader -connection $connection | out-null
            write-progress -activity "Remove Rule $($Rule.Name)" -completed

        }
    }

    end {}
}

function Get-NsxFirewallExclusionListMember {

    <#
    .SYNOPSIS
    Gets the virtual machines that are excluded from the distributed firewall

    .DESCRIPTION
    The 'Exclusion List' is a list of virtual machines which are excluded from
    the distributed firewall rules. They are not protected and/or limited by it.

    If a virtual machine has multiple vNICs, all of them are excluded from 
    protection.

    VMware recommends that you place the following service virtual machines in 
    the Exclusion List
    * vCenter Server.
    * Partner service virtual machines.
    * Virtual machines that require promiscuous mode.

    This cmdlet retrieves all VMs on the exclusion list and returns PowerCLI VM
    objects.

    .EXAMPLE
    Get-NsxFirewallExclusionListMember

    Retreives the entire contents of the exclusion list

    .EXAMPLE
    Get-NsxFirewallExclusionListMember | ? { $_.name -match 'myvm'}

    Retreives a specific vm from the exclusion list if it exists.

    #>

    param (
        [Parameter (Mandatory=$False)]
        #PowerNSX Connection object.
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process{
        # Build URL and catch response into XML format
        $URI = "/api/2.1/app/excludelist"
        [System.Xml.XmlDocument]$response = invoke-nsxrestmethod -method "GET" -uri $URI -connection $Connection

        # If there are any VMs found, iterate and return them
        #Martijn - I removed the array build here, as:
        #### a) I preferred to just output VM objects so that the get- | remove- pipline works
        #### b) outputting the VM obj immediately works nicer in a pipeline (object appears immediately) 
        ####   as opposed to building the array internally where the whole pipeline has to be processed before the user gets any output.
        #### c) Its also less lines :)

        $nodes = $response.SelectNodes('descendant::VshieldAppConfiguration/excludeListConfiguration/excludeMember')
        if ($nodes){
            foreach ($node in $nodes){
                # output the VI VM object...
                Get-VM -Server $Connection.VIConnection -id "VirtualMachine-$($node.member.objectId)"
            }
        }
    }

    end {}
}


function Add-NsxFirewallExclusionListMember {

    <#
    .SYNOPSIS
    Adds a virtual machine to the exclusion list, which are excluded from the 
    distributed firewall

    .DESCRIPTION
    The 'Exclusion List' is a list of virtual machines which are excluded from
    the distributed firewall rules. They are not protected and/or limited by it.

    If a virtual machine has multiple vNICs, all of them are excluded from 
    protection.

    VMware recommends that you place the following service virtual machines in 
    the Exclusion List
    * vCenter Server.
    * Partner service virtual machines.
    * Virtual machines that require promiscuous mode.

    This cmdlet adds a VM to the exclusion list

    .EXAMPLE
    Add-NsxFirewallExclusionListMember -VirtualMachine (Get-VM -Name myVM)

    Adds the VM myVM to the exclusion list
    .EXAMPLE
    Get-VM | ? { $_.name -match 'mgt'} | Add-NsxFirewallExclusionListMember

    Adds all VMs with mgt in their name to the exclusion list.
    #>

    param (
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullorEmpty()]
        [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop]$VirtualMachine,
        [Parameter (Mandatory=$False)]
        #PowerNSX Connection object.
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process {
        # Get VM MOID
        $vmMoid = $VirtualMachine.ExtensionData.MoRef.Value
        # Build URL
        $URI = "/api/2.1/app/excludelist/$vmMoid"

        try {
            $response = invoke-nsxrestmethod -method "PUT" -uri $URI -connection $connection
        }
        catch {
            Throw "Unable to add VM $VirtualMachine to Exclusion list. $_"
        }
    }

end {}
}


function Remove-NsxFirewallExclusionListMember {

    <#
    .SYNOPSIS
    Removes a virtual machine from the exclusion list, which are excluded from 
    the distributed firewall

    .DESCRIPTION
    The 'Exclusion List' is a list of virtual machines which are excluded from
    the distributed firewall rules. They are not protected and/or limited by it.

    If a virtual machine has multiple vNICs, all of them are excluded from 
    protection.

    VMware recommends that you place the following service virtual machines in 
    the Exclusion List
    * vCenter Server.
    * Partner service virtual machines.
    * Virtual machines that require promiscuous mode.

    This cmdlet removes a VM to the exclusion list

    .EXAMPLE
    Remove-NsxFirewallExclusionListMember -VirtualMachine (Get-VM -Name myVM)

    Removes the VM myVM from the exclusion list

    .EXAMPLE
    Get-NsxFirewallExclusionListMember | Remove-NsxFirewallExclusionlistMember

    Removes all vms from the exclusion list.
    #>

    param (
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullorEmpty()]
        [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop]$VirtualMachine,
        [Parameter (Mandatory=$False)]
        #PowerNSX Connection object.
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process {
        # Get VM MOID
        $vmMoid = $VirtualMachine.ExtensionData.MoRef.Value
        # Build URL
        $URI = "/api/2.1/app/excludelist/$vmMoid"

        try {
            $response = invoke-nsxrestmethod -method "DELETE" -uri $URI -connection $connection
        }
        catch {
            Throw "Unable to remove VM $VirtualMachine from Exclusion list. $_"
        }
    }

    end {}
}

function Get-NsxFirewallSavedConfiguration {
    
     <#
    .SYNOPSIS
    Retrieves saved Distributed Firewall configuration.

    .DESCRIPTION
    Retireves saved Distributed Firewall configuration.

    A copy of every published configuration is also saved as a draft. A 
    maximum of 100 configurations can be saved at a time. 90 out of 
    these 100 can be auto saved configurations from a publish operation. 
    When the limit is reached,the oldest configuration that is not marked for
    preserve is purged to make way for a new one.

    .EXAMPLE
    Get-NsxFirewallSavedConfiguration

    Retrieves all saved Distributed Firewall configurations

    .EXAMPLE
    Get-NsxFirewallSavedConfiguration -ObjectId 403

    Retrieves a Distributed Firewall configuration by ObjectId

    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
    
    param (

        [Parameter (Mandatory=$false,ParameterSetName="ObjectId")]
            [string]$ObjectId,
        [Parameter (Mandatory=$false,Position=1,ParameterSetName="Name")]
            [string]$Name,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )
    
    begin {

    }

    process {
    
        if ( -not ($PsBoundParameters.ContainsKey("ObjectId"))) { 
            #All Sections

            $URI = "/api/4.0/firewall/globalroot-0/drafts"
            [system.xml.xmldocument]$Response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if ($response.SelectSingleNode("child::firewallDrafts")){
                
                $Return = $Response

                if ($PsBoundParameters.ContainsKey("Name")){
                    $Return.firewallDrafts.firewallDraft | ? {$_.name -eq $Name} 
                }
                else {
            
                    $Return.firewallDrafts.firewallDraft
                }
            }
        }
        else {
            
            $URI = "/api/4.0/firewall/globalroot-0/drafts/$ObjectId"
            [system.xml.xmldocument]$Response = Invoke-NsxRestMethod -method "get" -uri $URI -connection $connection
            
            if ($Response.SelectSingleNode("child::firewallDraft")){
                $Response.firewallDraft
            }
        }
    }
    end {}
}


########
########
# Load Balancing


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
   
    PS C:\> Get-NsxEdge TestESG | Get-NsxLoadBalancer
    
    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-Edge $_ })]
            [System.Xml.XmlElement]$Edge
    )

    begin {}

    process { 

        #We append the Edge-id to the associated LB XML to enable pipeline workflows and 
        #consistent readable output (PSCustom object approach results in 'edge and 
        #LoadBalancer' props of the output which is not pretty for the user)

        $_LoadBalancer = $Edge.features.loadBalancer.CloneNode($True)
        Add-XmlElement -xmlRoot $_LoadBalancer -xmlElementName "edgeId" -xmlElementText $Edge.Id
        $_LoadBalancer

    }      
}


function Set-NsxLoadBalancer {

    <#
    .SYNOPSIS
    Configures an NSX LoadBalancer.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    This cmdlet sets the basic LoadBalancer configuration of an NSX Load Balancer. 

    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$False)]
            [switch]$Enabled,
        [Parameter (Mandatory=$False)]
            [switch]$EnableAcceleration,
        [Parameter (Mandatory=$False)]
            [switch]$EnableLogging,
        [Parameter (Mandatory=$False)]
            [ValidateSet("emergency","alert","critical","error","warning","notice","info","debug")]
            [string]$LogLevel,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

    )

    begin {
    }

    process {

        #Create private xml element
        $_LoadBalancer = $LoadBalancer.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_LoadBalancer.edgeId
        $_LoadBalancer.RemoveChild( $($_LoadBalancer.SelectSingleNode('descendant::edgeId')) ) | out-null

        #Using PSBoundParamters.ContainsKey lets us know if the user called us with a given parameter.
        #If the user did not specify a given parameter, we dont want to modify from the existing value.

        if ( $PsBoundParameters.ContainsKey('Enabled') ) {
            if ( $Enabled ) { 
                $_LoadBalancer.enabled = "true" 
            } else { 
                $_LoadBalancer.enabled = "false" 
            } 
        }

        if ( $PsBoundParameters.ContainsKey('EnableAcceleration') ) {
            if ( $EnableAcceleration ) { 
                $_LoadBalancer.accelerationEnabled = "true" 
            } else { 
                $_LoadBalancer.accelerationEnabled = "false" 
            } 
        }

        if ( $PsBoundParameters.ContainsKey('EnableLogging') ) {
            if ( $EnableLogging ) { 
                $_LoadBalancer.logging.enable = "true" 
            } else { 
                $_LoadBalancer.logging.enable = "false" 
            } 
        }

        if ( $PsBoundParameters.ContainsKey('LogLevel') ) {
            $_LoadBalancer.logging.logLevel = $LogLevel
        }

        $URI = "/api/4.0/edges/$($edgeId)/loadbalancer/config"
        $body = $_LoadBalancer.OuterXml 

        Write-Progress -activity "Update Edge Services Gateway $($edgeId)"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection 
        write-progress -activity "Update Edge Services Gateway $($edgeId)" -completed
        Get-NsxEdge -objectId $($edgeId)  -connection $connection | Get-NsxLoadBalancer
    }

    end{
    }
}


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
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [PSCustomObject]$LoadBalancer,
        [Parameter (Mandatory=$true,ParameterSetName="monitorId")]
            [string]$monitorId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name
    )

    begin {}

    process { 
        
        if ( $Name) { 
            $Monitors = $loadbalancer.monitor | ? { $_.name -eq $Name }
        }
        elseif ( $monitorId ) { 
            $Monitors = $loadbalancer.monitor | ? { $_.monitorId -eq $monitorId }
        }
        else { 
            $Monitors = $loadbalancer.monitor 
        }

        foreach ( $Monitor in $Monitors ) { 
            $_Monitor = $Monitor.CloneNode($True)
            Add-XmlElement -xmlRoot $_Monitor -xmlElementName "edgeId" -xmlElementText $LoadBalancer.edgeId
            $_Monitor
        }
    }
    end{ }
}


function New-NsxLoadBalancerMonitor {
 
    <#
    .SYNOPSIS
    Creates a new LoadBalancer Service Monitor on the specified 
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

    Service monitors define health check parameters for a particular type of 
    network traffic. When you associate a service monitor with a pool, the pool 
    members are monitored according to the service monitor parameters.
    
    This cmdlet creates a new LoadBalancer Service monitor on a specified 
    Load Balancer
    
    .EXAMPLE
    
    PS C:\> Get-NsxEdge LB2 | Get-NsxLoadBalancer | New-NsxLoadBalancerMonitor 
    -Name Web-Monitor -interval 10 -Timeout 10 -MaxRetries 3 -Type 
    HTTPS -Method GET -Url "/WAPI/api/status" -Expected "200 OK"

    #>
    [CmdLetBinding(DefaultParameterSetName="HTTP")]

    param (
   

        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="HTTPS")]
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="TCP")]
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="ICMP")]
        [Parameter (Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="UDP")]
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$true, ParameterSetName="HTTP")]
            [switch]$TypeHttp,
        [Parameter (Mandatory=$true, ParameterSetName="HTTPS")]
            [switch]$TypeHttps,
        [Parameter (Mandatory=$true, ParameterSetName="TCP")]
            [switch]$TypeTcp,
        [Parameter (Mandatory=$true, ParameterSetName="ICMP")]
            [switch]$TypeIcmp,
        [Parameter (Mandatory=$true, ParameterSetName="UDP")]
            [switch]$TypeUdp,
        [Parameter (Mandatory=$true, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$true, ParameterSetName="HTTPS")]
        [Parameter (Mandatory=$true, ParameterSetName="TCP")]
        [Parameter (Mandatory=$true, ParameterSetName="ICMP")]
        [Parameter (Mandatory=$true, ParameterSetName="UDP")]
           [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$true, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$true, ParameterSetName="HTTPS")]
        [Parameter (Mandatory=$true, ParameterSetName="TCP")]
        [Parameter (Mandatory=$true, ParameterSetName="ICMP")]
        [Parameter (Mandatory=$true, ParameterSetName="UDP")]
            [ValidateNotNullOrEmpty()]
            [string]$Interval,
        [Parameter (Mandatory=$true, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$true, ParameterSetName="HTTPS")]
        [Parameter (Mandatory=$true, ParameterSetName="TCP")]
        [Parameter (Mandatory=$true, ParameterSetName="ICMP")]
        [Parameter (Mandatory=$true, ParameterSetName="UDP")]
            [ValidateNotNullOrEmpty()]
            [string]$Timeout,
        [Parameter (Mandatory=$true, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$true, ParameterSetName="HTTPS")]
        [Parameter (Mandatory=$true, ParameterSetName="TCP")]
        [Parameter (Mandatory=$true, ParameterSetName="ICMP")]
        [Parameter (Mandatory=$true, ParameterSetName="UDP")]
            [ValidateNotNullOrEmpty()]
            [string]$MaxRetries,
        [Parameter (Mandatory=$true, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$true, ParameterSetName="HTTPS")]
            [ValidateSet("GET","POST","OPTIONS", IgnoreCase=$False)]
            [string]$Method,
        [Parameter (Mandatory=$true, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$true, ParameterSetName="HTTPS")]
            [ValidateNotNullOrEmpty()]
            [string]$Url,
        [Parameter (Mandatory=$false, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$false, ParameterSetName="HTTPS")]
            [ValidateNotNullOrEmpty()]
            [string]$Expected,
        [Parameter (Mandatory=$false, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$false, ParameterSetName="HTTPS")]
        [Parameter (Mandatory=$false, ParameterSetName="TCP")]
        [Parameter (Mandatory=$false, ParameterSetName="ICMP")]
        [Parameter (Mandatory=$false, ParameterSetName="UDP")]
            [ValidateNotNullOrEmpty()]
            [string]$Send,
        [Parameter (Mandatory=$false, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$false, ParameterSetName="HTTPS")]
        [Parameter (Mandatory=$false, ParameterSetName="TCP")]
        [Parameter (Mandatory=$false, ParameterSetName="ICMP")]
        [Parameter (Mandatory=$false, ParameterSetName="UDP")]
            [ValidateNotNullOrEmpty()]
            [string]$Receive,
        [Parameter (Mandatory=$false, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$false, ParameterSetName="HTTPS")]
        [Parameter (Mandatory=$false, ParameterSetName="TCP")]
        [Parameter (Mandatory=$false, ParameterSetName="ICMP")]
        [Parameter (Mandatory=$false, ParameterSetName="UDP")]
            [ValidateNotNullOrEmpty()]
            [string]$Extension,
        [Parameter (Mandatory=$false, ParameterSetName="HTTP")]
        [Parameter (Mandatory=$false, ParameterSetName="HTTPS")]
        [Parameter (Mandatory=$false, ParameterSetName="TCP")]
        [Parameter (Mandatory=$false, ParameterSetName="ICMP")]
        [Parameter (Mandatory=$false, ParameterSetName="UDP")]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {
    }

    process {
        

        #Store the edgeId
        $edgeId = $LoadBalancer.edgeId

        if ( -not $LoadBalancer.enabled -eq 'true' ) { 
            write-warning "Load Balancer feature is not enabled on edge $($edgeId).  Use Set-NsxLoadBalancer -EnableLoadBalancing to enable."
        }
     
        [System.XML.XMLElement]$xmlmonitor = $LoadBalancer.OwnerDocument.CreateElement("monitor")
     
        #Common Elements
        Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "interval" -xmlElementText $Interval
        Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "timeout" -xmlElementText $Timeout
        Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "maxRetries" -xmlElementText $MaxRetries
        
        #Optional
        if ( $PSBoundParameters.ContainsKey('Send')) {
            Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "send" -xmlElementText $Send
        }
        
        if ( $PSBoundParameters.ContainsKey('Receive')) {
            Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "receive" -xmlElementText $Receive
        }

        if ( $PSBoundParameters.ContainsKey('Extension')) {
            Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "extension" -xmlElementText $Extension
        }

        #Type specific
        switch -regex ( $PsCmdlet.ParameterSetName ) {

            "HTTP" {
                #will match both HTTP and HTTPS due to regex switch handling...
                if ( $TypeHttp ) { 
                    Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "type" -xmlElementText "http" 
                } else {
                    Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "type" -xmlElementText "https" 
                }

                if ( $PSBoundParameters.ContainsKey('Method')) {
                    Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "method" -xmlElementText $Method
                }

                if ( $PSBoundParameters.ContainsKey('Url')) {
                    Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "url" -xmlElementText $Url
                }

                if ( $PSBoundParameters.ContainsKey('Expected')) {
                    Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "expected" -xmlElementText $Expected
                }
            }

            "ICMP" {
                Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "type" -xmlElementText "icmp" 
            }

            "TCP" {
                Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "type" -xmlElementText "tcp" 
            }

            "UDP" {
                Add-XmlElement -xmlRoot $xmlmonitor -xmlElementName "type" -xmlElementText "udp" 
            }
        }


        
        $URI = "/api/4.0/edges/$edgeId/loadbalancer/config/monitors"
        $body = $xmlmonitor.OuterXml 
    
        Write-Progress -activity "Update Edge Services Gateway $($edgeId)" -status "Load Balancer Monitor Config"
        $response = invoke-nsxwebrequest -method "post" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($edgeId)" -completed

        get-nsxedge -objectId $edgeId -connection $connection | Get-NsxLoadBalancer | Get-NsxLoadBalancerMonitor -name $Name
    }

    end {}
}


function Remove-NsxLoadBalancerMonitor {

    <#
    .SYNOPSIS
    Removes the specified LoadBalancer Monitor.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    Service monitors define health check parameters for a particular type of 
    network traffic. When you associate a service monitor with a pool, the pool 
    members are monitored according to the service monitor parameters.
    
    This cmdlet removes the specified LoadBalancer Monitor.
   
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LoadBalancerMonitor $_ })]
            [System.Xml.XmlElement]$Monitor,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $Monitor.edgeId
        $MonitorId = $Monitor.monitorId
            
        $URI = "/api/4.0/edges/$edgeId/loadbalancer/config/monitors/$MonitorId" 
        
        if ( $confirm ) { 
            $message  = "Monitor removal is permanent."
            $question = "Proceed with removal of Load Balancer Monitor $($MonitorId)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $EdgeId" -status "Removing Monitor $MonitorId"
            $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
            write-progress -activity "Update Edge Services Gateway $EdgeId" -completed

        }
    }

    end {}
}


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
   
    PS C:\> Get-NsxEdge LoadBalancer | Get-NsxLoadBalancer | 
        Get-NsxLoadBalancerApplicationProfile HTTP
    
    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$true,ParameterSetName="applicationProfileId")]
            [alias("applicationProfileId")]
            [string]$objectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name

    )

    begin {}

    process { 
        
        if ( $LoadBalancer.SelectSingleNode('descendant::applicationProfile')) { 
            if ( $PsBoundParameters.ContainsKey('Name')) { 
                $AppProfiles = $loadbalancer.applicationProfile | ? { $_.name -eq $Name }
            }
            elseif ( $PsBoundParameters.ContainsKey('objectId') ) { 
                $AppProfiles = $loadbalancer.applicationProfile | ? { $_.applicationProfileId -eq $objectId }
            }
            else { 
                $AppProfiles = $loadbalancer.applicationProfile 
            }

            foreach ( $AppProfile in $AppProfiles ) { 
                $_AppProfile = $AppProfile.CloneNode($True)
                Add-XmlElement -xmlRoot $_AppProfile -xmlElementName "edgeId" -xmlElementText $LoadBalancer.edgeId
                $_AppProfile
            }
        }
    }

    end{ }
}


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
    
    This cmdlet creates a new LoadBalancer Application Profile on a specified 
    Load Balancer

    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$True)]
            [ValidateSet("TCP","UDP","HTTP","HTTPS")]
            [string]$Type,  
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [switch]$InsertXForwardedFor=$false,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [switch]$SslPassthrough=$false,
        [Parameter (Mandatory=$False)]
            [ValidateSet("ssl_sessionid", "cookie", "sourceip",  "msrdp", IgnoreCase=$false)]
            [string]$PersistenceMethod,
        [Parameter (Mandatory=$False)]
            [int]$PersistenceExpiry,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [string]$CookieName,
        [Parameter (Mandatory=$False)]
            [ValidateSet("insert", "prefix", "app")]
            [string]$CookieMode,           
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
        
    )
    # Still a bit to do here - need cert selection...
    # Also - There are many combinations of valid (and invalid) options.  Unfortunately.
    # the NSX API does not perform the validation of these combinations (It will
    # accept combinations of params that the UI will not), the NSX UI does
    # So I need to be doing validation in here as well - this is still to be done, but required
    # so user has sane experience...


    begin {
    }

    process {
        
        #Create private xml element
        $_LoadBalancer = $LoadBalancer.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_LoadBalancer.edgeId
        $_LoadBalancer.RemoveChild( $($_LoadBalancer.SelectSingleNode('descendant::edgeId')) ) | out-null

        if ( -not $_LoadBalancer.enabled -eq 'true' ) { 
            write-warning "Load Balancer feature is not enabled on edge $($edgeId).  Use Set-NsxLoadBalancer -EnableLoadBalancing to enable."
        }
     
        [System.XML.XMLElement]$xmlapplicationProfile = $_LoadBalancer.OwnerDocument.CreateElement("applicationProfile")
        $_LoadBalancer.appendChild($xmlapplicationProfile) | out-null
     
        #Mandatory Params and those with Default values
        Add-XmlElement -xmlRoot $xmlapplicationProfile -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlapplicationProfile -xmlElementName "template" -xmlElementText $Type
        Add-XmlElement -xmlRoot $xmlapplicationProfile -xmlElementName "insertXForwardedFor" -xmlElementText $insertXForwardedFor 
        Add-XmlElement -xmlRoot $xmlapplicationProfile -xmlElementName "sslPassthrough" -xmlElementText $SslPassthrough 

        #Optionals.
        If ( $PsBoundParameters.ContainsKey('PersistenceMethod')) {
            [System.XML.XMLElement]$xmlPersistence = $_LoadBalancer.OwnerDocument.CreateElement("persistence")
            $xmlapplicationProfile.appendChild($xmlPersistence) | out-null
            Add-XmlElement -xmlRoot $xmlPersistence -xmlElementName "method" -xmlElementText $PersistenceMethod 
            If ( $PsBoundParameters.ContainsKey('CookieName')) {
                Add-XmlElement -xmlRoot $xmlPersistence -xmlElementName "cookieName" -xmlElementText $CookieName 
            }
            If ( $PsBoundParameters.ContainsKey('CookieMode')) {
                Add-XmlElement -xmlRoot $xmlPersistence -xmlElementName "cookieMode" -xmlElementText $CookieMode 
            }
            If ( $PsBoundParameters.ContainsKey('PersistenceExpiry')) {
                Add-XmlElement -xmlRoot $xmlPersistence -xmlElementName "expire" -xmlElementText $PersistenceExpiry 
            }
        }
        
        $URI = "/api/4.0/edges/$edgeId/loadbalancer/config"
        $body = $_LoadBalancer.OuterXml 
    
        Write-Progress -activity "Update Edge Services Gateway $($edgeId)" -status "Load Balancer Config"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($edgeId)" -completed

        $updatedEdge = Get-NsxEdge -objectId $($edgeId) -connection $connection
        
        $applicationProfiles = $updatedEdge.features.loadbalancer.applicationProfile
        foreach ($applicationProfile in $applicationProfiles) { 

            #6.1 Bug? NSX API creates an object ID format that it does not accept back when put. We have to change on the fly to the 'correct format'.
            write-debug "$($MyInvocation.MyCommand.Name) : Checking for stupidness in $($applicationProfile.applicationProfileId)"    
            $applicationProfile.applicationProfileId = 
                $applicationProfile.applicationProfileId.replace("edge_load_balancer_application_profiles","applicationProfile-")
            
        }

        $body = $updatedEdge.features.loadbalancer.OuterXml
        Write-Progress -activity "Update Edge Services Gateway $($edgeId)" -status "Load Balancer Config"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($edgeId)" -completed

        #filter output for our newly created app profile - name is safe as it has to be unique.
        $return = $updatedEdge.features.loadbalancer.applicationProfile | ? { $_.name -eq $name }
        Add-XmlElement -xmlroot $return -xmlElementName "edgeId" -xmlElementText $edgeId
        $return
    }

    end {}
}


function Remove-NsxLoadBalancerApplicationProfile {

    <#
    .SYNOPSIS
    Removes the specified LoadBalancer Application Profile.

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
    
    This cmdlet removes the specified LoadBalancer Application Profile.
   
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LoadBalancerApplicationProfile $_ })]
            [System.Xml.XmlElement]$ApplicationProfile,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $ApplicationProfile.edgeId
        $AppProfileId = $ApplicationProfile.applicationProfileId

            
        $URI = "/api/4.0/edges/$edgeId/loadbalancer/config/applicationprofiles/$AppProfileId" 
        
        if ( $confirm ) { 
            $message  = "Application Profile removal is permanent."
            $question = "Proceed with removal of Application Profile $($AppProfileId)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $EdgeId" -status "Removing Application Profile $AppProfileId"
            $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
            write-progress -activity "Update Edge Services Gateway $EdgeId" -completed

        }
    }

    end {}
}


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

        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "ipAddress" -xmlElementText $IpAddress   
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "weight" -xmlElementText $Weight 
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "port" -xmlElementText $port 
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "monitorPort" -xmlElementText $port 
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "minConn" -xmlElementText $MinimumConnections 
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "maxConn" -xmlElementText $MaximumConnections 
  
        $xmlMember

    }

    end {}
}


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
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$True)]
            [ValidateNotNullOrEmpty()]
            [string]$Name,
        [Parameter (Mandatory=$False)]
            [ValidateNotNull()]
            [string]$Description="",
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [switch]$Transparent=$false,
        [Parameter (Mandatory=$True)]
            [ValidateSet("round-robin", "ip-hash", "uri", "leastconn")]
            [string]$Algorithm,
        [Parameter (Mandatory=$false)]
            [ValidateScript({ Validate-LoadBalancerMonitor $_ })]
            [System.Xml.XmlElement]$Monitor,
        [Parameter (Mandatory=$false)]
            [ValidateScript({ Validate-LoadBalancerMemberSpec $_ })]
            [System.Xml.XmlElement[]]$MemberSpec,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {
    }

    process {
        
        #Create private xml element
        $_LoadBalancer = $LoadBalancer.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_LoadBalancer.edgeId
        $_LoadBalancer.RemoveChild( $($_LoadBalancer.SelectSingleNode('descendant::edgeId')) ) | out-null

        if ( -not $_LoadBalancer.enabled -eq 'true' ) { 
            write-warning "Load Balancer feature is not enabled on edge $($edgeId).  Use Set-NsxLoadBalancer -EnableLoadBalancing to enable."
        }

        [System.XML.XMLElement]$xmlPool = $_LoadBalancer.OwnerDocument.CreateElement("pool")
        $_LoadBalancer.appendChild($xmlPool) | out-null

     
        Add-XmlElement -xmlRoot $xmlPool -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlPool -xmlElementName "description" -xmlElementText $Description
        Add-XmlElement -xmlRoot $xmlPool -xmlElementName "transparent" -xmlElementText $Transparent 
        Add-XmlElement -xmlRoot $xmlPool -xmlElementName "algorithm" -xmlElementText $algorithm 
        
        if ( $PsBoundParameters.ContainsKey('Monitor')) { 
            Add-XmlElement -xmlRoot $xmlPool -xmlElementName "monitorId" -xmlElementText $Monitor.monitorId 
        }

        if ( $PSBoundParameters.ContainsKey('MemberSpec')) {
            foreach ( $Member in $MemberSpec ) { 
                $xmlmember = $xmlPool.OwnerDocument.ImportNode($Member, $true)
                $xmlPool.AppendChild($xmlmember) | out-null
            }
        }

        $URI = "/api/4.0/edges/$EdgeId/loadbalancer/config"
        $body = $_LoadBalancer.OuterXml 
    
        Write-Progress -activity "Update Edge Services Gateway $($EdgeId)" -status "Load Balancer Config"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed

        $UpdatedEdge = Get-NsxEdge -objectId $($EdgeId) -connection $connection
        $return = $UpdatedEdge.features.loadBalancer.pool | ? { $_.name -eq $Name }
        Add-XmlElement -xmlroot $return -xmlElementName "edgeId" -xmlElementText $edgeId
        $return
    }

    end {}
}


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
   
    PS C:\> Get-NsxEdge | Get-NsxLoadBalancer | 
        Get-NsxLoadBalancerPool
    
    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$true,ParameterSetName="poolId")]
            [string]$PoolId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name

    )

    begin {}

    process { 
        
        if ( $loadbalancer.SelectSingleNode('child::pool')) { 
            if ( $PsBoundParameters.ContainsKey('Name')) {  
                $pools = $loadbalancer.pool | ? { $_.name -eq $Name }
            }
            elseif ( $PsBoundParameters.ContainsKey('PoolId')) {  
                $pools = $loadbalancer.pool | ? { $_.poolId -eq $PoolId }
            }
            else { 
                $pools = $loadbalancer.pool 
            }

            foreach ( $Pool in $Pools ) { 
                $_Pool = $Pool.CloneNode($True)
                Add-XmlElement -xmlRoot $_Pool -xmlElementName "edgeId" -xmlElementText $LoadBalancer.edgeId
                $_Pool
            }
        }
    }

    end{ }
}


function Remove-NsxLoadBalancerPool {

    <#
    .SYNOPSIS
    Removes a Pool from the specified Load Balancer.

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
    members.
    
    This cmdlet removes the specified pool from the Load Balancer pool and returns
    the updated LoadBalancer.
   
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LoadBalancerPool $_ })]
            [System.Xml.XmlElement]$LoadBalancerPool,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $LoadBalancerPool.edgeId
        $poolId = $LoadBalancerPool.poolId

        #Get and remove the edgeId element
        $LoadBalancer = Get-nsxEdge -objectId $edgeId -connection $connection | Get-NsxLoadBalancer
        $LoadBalancer.RemoveChild( $($LoadBalancer.SelectSingleNode('child::edgeId')) ) | out-null

        $PoolToRemove = $LoadBalancer.SelectSingleNode("child::pool[poolId=`"$poolId`"]")
        if ( -not $PoolToRemove ) {
            throw "Pool $poolId is not defined on Load Balancer $edgeid."
        } 
        
        $LoadBalancer.RemoveChild( $PoolToRemove ) | out-null
            
        $URI = "/api/4.0/edges/$edgeId/loadbalancer/config"
        $body = $LoadBalancer.OuterXml 
        
        if ( $confirm ) { 
            $message  = "Pool removal is permanent."
            $question = "Proceed with removal of Pool $($poolId)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $EdgeId" -status "Removing pool $poolId"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $EdgeId" -completed

            Get-NSxEdge -objectID $edgeId -connection $connection | Get-NsxLoadBalancer
        }
    }

    end {}
}


function Get-NsxLoadBalancerPoolMember {

    <#
    .SYNOPSIS
    Retrieves the members of the specified LoadBalancer Pool.

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
    
    This cmdlet retrieves the members of the specified LoadBalancer Pool.

    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancerPool $_ })]
            [System.Xml.XmlElement]$LoadBalancerPool,
        [Parameter (Mandatory=$true,ParameterSetName="MemberId")]
            [string]$MemberId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name

    )

    begin {}

    process { 
        
        

        if ( $PsBoundParameters.ContainsKey('Name')) {  
            $Members = $LoadBalancerPool.SelectNodes('descendant::member') | ? { $_.name -eq $Name }
        }
        elseif ( $PsBoundParameters.ContainsKey('MemberId')) {  
            $Members = $LoadBalancerPool.SelectNodes('descendant::member') | ? { $_.memberId -eq $MemberId }
        }
        else { 
            $Members = $LoadBalancerPool.SelectNodes('descendant::member') 
        }

        foreach ( $Member in $Members ) { 
            $_Member = $Member.CloneNode($True)
            Add-XmlElement -xmlRoot $_Member -xmlElementName "edgeId" -xmlElementText $LoadBalancerPool.edgeId
            Add-XmlElement -xmlRoot $_Member -xmlElementName "poolId" -xmlElementText $LoadBalancerPool.poolId

            $_Member
        }
    }

    end{ }
}


function Add-NsxLoadBalancerPoolMember {

    <#
    .SYNOPSIS
    Adds a new Pool Member to the specified Load Balancer Pool.

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
    members.
    
    This cmdlet adds a new member to the specified LoadBalancer Pool and
    returns the updated Pool.
   
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancerPool $_ })]
            [System.Xml.XmlElement]$LoadBalancerPool,
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
            [int]$MaximumConnections=0,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 


        #Create private xml element
        $_LoadBalancerPool = $LoadBalancerPool.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_LoadBalancerPool.edgeId
        $_LoadBalancerPool.RemoveChild( $($_LoadBalancerPool.SelectSingleNode('descendant::edgeId')) ) | out-null

        [System.XML.XMLElement]$xmlMember = $_LoadBalancerPool.OwnerDocument.CreateElement("member")
        $_LoadBalancerPool.appendChild($xmlMember) | out-null

        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "ipAddress" -xmlElementText $IpAddress   
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "weight" -xmlElementText $Weight 
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "port" -xmlElementText $port 
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "monitorPort" -xmlElementText $port 
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "minConn" -xmlElementText $MinimumConnections 
        Add-XmlElement -xmlRoot $xmlMember -xmlElementName "maxConn" -xmlElementText $MaximumConnections 
  
            
        $URI = "/api/4.0/edges/$edgeId/loadbalancer/config/pools/$($_LoadBalancerPool.poolId)"
        $body = $_LoadBalancerPool.OuterXml 
    
        Write-Progress -activity "Update Edge Services Gateway $($EdgeId)" -status "Pool config for $($_LoadBalancerPool.poolId)"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed

        #Get updated pool
        $URI = "/api/4.0/edges/$edgeId/loadbalancer/config/pools/$($_LoadBalancerPool.poolId)"
        Write-Progress -activity "Retrieving Updated Pool for $($EdgeId)" -status "Pool $($_LoadBalancerPool.poolId)"
        $return = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        $Pool = $return.pool
        Add-XmlElement -xmlroot $Pool -xmlElementName "edgeId" -xmlElementText $edgeId
        $Pool

    }

    end {}
}


function Remove-NsxLoadBalancerPoolMember {

    <#
    .SYNOPSIS
    Removes a Pool Member from the specified Load Balancer Pool.

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
    members.
    
    This cmdlet removes the specified member from the specified pool and returns
     the updated Pool.
   
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LoadBalancerPoolMember $_ })]
            [System.Xml.XmlElement]$LoadBalancerPoolMember,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {}
    process { 

        #Store the edgeId and remove it from the XML as we need to post it...
        $MemberId = $LoadBalancerPoolMember.memberId
        $edgeId = $LoadBalancerPoolMember.edgeId
        $poolId = $LoadBalancerPoolMember.poolId

        #Get and remove the edgeId and poolId elements
        $LoadBalancer = Get-nsxEdge -objectId $edgeId -connection $connection | Get-NsxLoadBalancer
        $LoadBalancer.RemoveChild( $($LoadBalancer.SelectSingleNode('child::edgeId')) ) | out-null

        $LoadBalancerPool = $loadbalancer.SelectSingleNode("child::pool[poolId=`"$poolId`"]")

        $MemberToRemove = $LoadBalancerPool.SelectSingleNode("child::member[memberId=`"$MemberId`"]")
        if ( -not $MemberToRemove ) {
            throw "Member $MemberId is not a member of pool $PoolId."
        } 
        
        $LoadBalancerPool.RemoveChild( $MemberToRemove ) | out-null
            
        $URI = "/api/4.0/edges/$edgeId/loadbalancer/config"
        $body = $LoadBalancer.OuterXml 
        
        if ( $confirm ) { 
            $message  = "Pool Member removal is permanent."
            $question = "Proceed with removal of Pool Member $($memberId)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $EdgeId" -status "Pool config for $poolId"
            $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
            write-progress -activity "Update Edge Services Gateway $EdgeId" -completed

            Get-NSxEdge -objectID $edgeId -connection $connection | Get-NsxLoadBalancer | Get-NsxLoadBalancerPool -poolId $poolId
        }
    }

    end {}
}


function Get-NsxLoadBalancerVip {

    <#
    .SYNOPSIS
    Retrieves the Virtual Servers configured on the specified LoadBalancer.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    A Virtual Server binds an IP address (must already exist on an ESG iNterface as 
    either a Primary or Secondary Address) and a port to a LoadBalancer Pool and 
    Application Profile.

    This cmdlet retrieves the configured Virtual Servers from the specified Load 
    Balancer.

    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$true,ParameterSetName="VirtualServerId")]
            [string]$VirtualServerId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            [string]$Name
    )

    begin {}

    process { 
        

        if ( $PsBoundParameters.ContainsKey('Name')) {  
            $Vips = $LoadBalancer.SelectNodes('descendant::virtualServer') | ? { $_.name -eq $Name }
        }
        elseif ( $PsBoundParameters.ContainsKey('MemberId')) {  
            $Vips = $LoadBalancer.SelectNodes('descendant::virtualServer') | ? { $_.virtualServerId -eq $VirtualServerId }
        }
        else { 
            $Vips = $LoadBalancer.SelectNodes('descendant::virtualServer') 
        }

        foreach ( $Vip in $Vips ) { 
            $_Vip = $VIP.CloneNode($True)
            Add-XmlElement -xmlRoot $_Vip -xmlElementName "edgeId" -xmlElementText $LoadBalancer.edgeId
            $_Vip
        }
    }

    end{ }
}


function Add-NsxLoadBalancerVip {

    <#
    .SYNOPSIS
    Adds a new LoadBalancer Virtual Server to the specified ESG.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    A Virtual Server binds an IP address (must already exist on an ESG iNterface as 
    either a Primary or Secondary Address) and a port to a LoadBalancer Pool and 
    Application Profile.

    This cmdlet creates a new Load Balancer VIP.

    .EXAMPLE
    Example1: Need to create member specs for each of the pool members first

    PS C:\> $WebVip = Get-NsxEdge DMZ_Edge_2 | 
        New-NsxLoadBalancerVip -Name WebVip -Description "Test Creating a VIP" 
        -IpAddress $edge_uplink_ip -Protocol http -Port 80 
        -ApplicationProfile $AppProfile -DefaultPool $WebPool 
        -AccelerationEnabled
   
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
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
            [ValidateScript({ Validate-LoadBalancerApplicationProfile $_ })]
            [System.Xml.XmlElement]$ApplicationProfile,
        [Parameter (Mandatory=$true)]
            [ValidateScript({ Validate-LoadBalancerPool $_ })]
            [System.Xml.XmlElement]$DefaultPool,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [switch]$AccelerationEnabled=$True,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [int]$ConnectionLimit=0,
        [Parameter (Mandatory=$False)]
            [ValidateNotNullOrEmpty()]
            [int]$ConnectionRateLimit=0,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
        
    )

    begin {
    }

    process {
        

        #Create private xml element
        $_LoadBalancer = $LoadBalancer.CloneNode($true)

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $_LoadBalancer.edgeId
        $_LoadBalancer.RemoveChild( $($_LoadBalancer.SelectSingleNode('descendant::edgeId')) ) | out-null

        if ( -not $_LoadBalancer.enabled -eq 'true' ) { 
            write-warning "Load Balancer feature is not enabled on edge $($edgeId).  Use Set-NsxLoadBalancer -EnableLoadBalancing to enable."
        }

        [System.XML.XMLElement]$xmlVIip = $_LoadBalancer.OwnerDocument.CreateElement("virtualServer")
        $_LoadBalancer.appendChild($xmlVIip) | out-null

     
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "description" -xmlElementText $Description
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "enabled" -xmlElementText $Enabled 
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "ipAddress" -xmlElementText $IpAddress 
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "protocol" -xmlElementText $Protocol 
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "port" -xmlElementText $Port 
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "connectionLimit" -xmlElementText $ConnectionLimit 
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "connectionRateLimit" -xmlElementText $ConnectionRateLimit 
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "applicationProfileId" -xmlElementText $ApplicationProfile.applicationProfileId
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "defaultPoolId" -xmlElementText $DefaultPool.poolId
        Add-XmlElement -xmlRoot $xmlVIip -xmlElementName "accelerationEnabled" -xmlElementText $AccelerationEnabled

            
        $URI = "/api/4.0/edges/$($EdgeId)/loadbalancer/config"
        $body = $_LoadBalancer.OuterXml 
    
        Write-Progress -activity "Update Edge Services Gateway $EdgeId" -status "Load Balancer Config"
        $response = invoke-nsxwebrequest -method "put" -uri $URI -body $body -connection $connection
        write-progress -activity "Update Edge Services Gateway $EdgeId" -completed

        $UpdatedLB = Get-NsxEdge -objectId $EdgeId  -connection $connection | Get-NsxLoadBalancer
        $UpdatedLB

    }

    end {}
}


function Remove-NsxLoadBalancerVip {

    <#
    .SYNOPSIS
    Removes a VIP from the specified Load Balancer.

    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as firewall,
    NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple paths
    to a specific destination. It distributes incoming service requests evenly 
    among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    A Virtual Server binds an IP address (must already exist on an ESG iNterface as 
    either a Primary or Secondary Address) and a port to a LoadBalancer Pool and 
    Application Profile.

    This cmdlet remove a VIP from the specified Load Balancer.

    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({ Validate-LoadBalancerVip $_ })]
            [System.Xml.XmlElement]$LoadBalancerVip,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )

    begin {
    }

    process {

        #Store the virtualserverid and edgeId
        $VipId = $LoadBalancerVip.VirtualServerId
        $edgeId = $LoadBalancerVip.edgeId

        $URI = "/api/4.0/edges/$edgeId/loadbalancer/config/virtualservers/$VipId"
    
        if ( $confirm ) { 
            $message  = "VIP removal is permanent."
            $question = "Proceed with removal of VIP $VipID on Edge $($edgeId)?"

            $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
            $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

            $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
        }
        else { $decision = 0 } 
        if ($decision -eq 0) {
            Write-Progress -activity "Update Edge Services Gateway $($EdgeId)" -status "Removing VIP $VipId"
            $response = invoke-nsxwebrequest -method "delete" -uri $URI -connection $connection
            write-progress -activity "Update Edge Services Gateway $($EdgeId)" -completed
        }
    }

    end {}
}



function Get-NsxLoadBalancerStats{

    <#
    .SYNOPSIS
    Retrieves NSX Edge Load Balancer statistics for the specified load 
    balancer


    .DESCRIPTION
    An NSX Edge Service Gateway provides all NSX Edge services such as 
    firewall, NAT, DHCP, VPN, load balancing, and high availability. 

    The NSX Edge load balancer enables network traffic to follow multiple 
    paths to a specific destination. It distributes incoming service requests 
    evenly among multiple servers in such a way that the load distribution is 
    transparent to users. Load balancing thus helps in achieving optimal 
    resource utilization, maximizing throughput, minimizing response time, and 
    avoiding overload. NSX Edge provides load balancing up to Layer 7.

    This cmdlet retrieves NSX Edge Load Balancer statistics from the specified
    enabled NSX loadbalancer.

    .EXAMPLE
    Get-nsxedge edge01 | Get-NsxLoadBalancer | Get-NsxLoadBalancerStats
    
    Retrieves the LB stats for the LB service on Edge01

    #>

    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            #Load Balancer from which to retrieve stats.  Must be enabled.
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection


        )

    begin {}
    process {

        #Test that LB is enabled (otherwise there are no results.)
        if ( $LoadBalancer.Enabled -ne 'true' ) { 
            Throw "Load balancer feature is not enabled on $($LoadBalancer.EdgeId)"
        }

        $URI = "/api/4.0/edges/$($LoadBalancer.EdgeId)/loadbalancer/statistics"
        [system.xml.xmldocument]$response = invoke-nsxrestmethod -method "GET" -uri $URI -connection $connection
        if ( $response.SelectSingleNode("child::loadBalancerStatusAndStats")) { 
            $response.loadBalancerStatusAndStats
        }
    }
    end {}
}

function Get-NsxLoadBalancerApplicationRule {

    <#
    .SYNOPSIS
    Retrieves LoadBalancer Application Rules from the specified LoadBalancer.

    .DESCRIPTION
    Retrieves LoadBalancer Application Rules from the specified LoadBalancer.

    You can write an application rule to directly manipulate and manage 
    IP application traffic.

    .EXAMPLE
    Get-NsxEdge | Get-NsxLoadBalancer | 
    Get-NsxLoadBalancerApplicationRule

    Retrieves all Application Rules across all NSX Edges.

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxLoadBalancer | 
    Get-NsxLoadBalancerApplicationRule

    Retrieves all Application Rules the NSX Edge named Edge01.

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxLoadBalancer | 
    Get-NsxLoadBalancerApplicationRule -name AR-Redirect-VMware

    Retrieves the Application Rule named AR-Redirect-VMware on NSX Edge
    named Edge01.

    .EXAMPLE
    Get-NsxEdge Edge01 | Get-NsxLoadBalancer | 
    Get-NsxLoadBalancerApplicationRule -objectId applicationRule-2

    Retrieves the Application Rule on NSX Edge with the objectId of
    applicationRule-2.

    #>

[CmdLetBinding(DefaultParameterSetName="Name")]
    
    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$false,ParameterSetName="ObjectId")]
            [string]$ObjectId,
        [Parameter (Mandatory=$false,Position=1,ParameterSetName="Name")]
            [string]$Name
    
    )
    
    begin {

    }

    process {
    
    
        if ( -not ($PsBoundParameters.ContainsKey("ObjectId"))) { 
            if ($LoadBalancer.SelectSingleNode("child::applicationRule")){
                if ($PsBoundParameters.ContainsKey("Name")){
                    $LoadBalancer.applicationRule | ? {$_.name -eq $Name} 
                }
                else {
                    $LoadBalancer.applicationRule
                }
            }
        }
        else {
            if ($LoadBalancer.SelectSingleNode("child::applicationRule/applicationRuleId")){
                $LoadBalancer.applicationRule | ? {$_.applicationRuleId -eq $ObjectId}
            }
        }
    }
    end {}
}


function New-NsxLoadBalancerApplicationRule {
    
    <#
    .SYNOPSIS
    Retrieves LoadBalancer Application Rules from the specified LoadBalancer.

    .DESCRIPTION
    Retrieves LoadBalancer Application Rules from the specified LoadBalancer.

    You can write an application rule to directly manipulate and manage 
    IP application traffic.

    .EXAMPLE
    Get-NsxEdge | Get-NsxLoadBalancer | New-NsxLoadBalancerApplicationRule
    -name AR-Redirect-VMware -script $script

    Applies a new Application Rule across all NSX Edges.

    .EXAMPLE
    Get-NsxEdge PowerNSX | Get-NsxLoadBalancer | 
    New-NsxLoadBalancerApplicationRule -name AR-Redirect-VMware 
    -script $script

    Applies a new Application Rule to the defined NSX Edge.

    #>

[CmdLetBinding(DefaultParameterSetName="Name")]
    
    param (
        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateScript({ Validate-LoadBalancer $_ })]
            [System.Xml.XmlElement]$LoadBalancer,
        [Parameter (Mandatory=$True)]
            [string]$Script,
        [Parameter (Mandatory=$True,Position=1)]
            [string]$Name,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
   
    )

    begin {

    }

    process {
    

        #Store the edgeId and remove it from the XML as we need to post it...
        $edgeId = $LoadBalancer.edgeId

        if ( -not $_LoadBalancer.enabled -eq 'true' ) { 
            write-warning "Load Balancer feature is not enabled on edge $($edgeId).  Use Set-NsxLoadBalancer -EnableLoadBalancing to enable."
        }
        #Create a new XML document. Use applicationRule as root.
        [System.XML.XmlDocument]$xmldoc = New-Object System.XML.XmlDocument
        [System.XML.XMLElement]$xmlAr = $xmldoc.CreateElement("applicationRule")
        [void]$xmldoc.appendChild($xmlAr)

        # Create children and add to $xmlXR
        Add-XmlElement -xmlRoot $xmlAr -xmlElementName "name" -xmlElementText $Name
        Add-XmlElement -xmlRoot $xmlAr -xmlElementName "script" -xmlElementText $Script
        
        #Construct Rest Call
        $URI = "/api/4.0/edges/$($EdgeId)/loadbalancer/config/applicationrules"
        $body = $xmlAr.OuterXml 

        $Response = Invoke-NsxWebRequest -method "POST" -uri $URI -body $body -connection $Connection
        
        [System.XML.XmlDocument]$ApplicationRule = Invoke-NsxRestMethod -method "GET" -URI $Response.headers.location
        
        if ($ApplicationRule.SelectSingleNode("child::applicationRule")){
            $ApplicationRule.applicationRule
        }
    }
    
    end {}
}


########
########
# Service Composer functions

function Get-NsxSecurityPolicy {

    <#
    .SYNOPSIS
    Retrieves NSX Security Policy

    .DESCRIPTION
    An NSX Security Policy is a set of Endpoint, firewall, and network 
    introspection services that can be applied to a security group.

    This cmdlet returns Security Policy objects.

    .EXAMPLE
    PS C:\> Get-NsxSecurityPolicy SecPolicy_WebServers

    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$false,ParameterSetName="objectId")]
            #Set Security Policies by objectId
            [string]$ObjectId,
        [Parameter (Mandatory=$false,ParameterSetName="Name",Position=1)]
            #Get Security Policies by name
            [string]$Name,
        [Parameter (Mandatory=$false)]
            #Include the readonly (system) Security Policies in results.
            [alias("ShowHidden")]      
            [switch]$IncludeHidden=$False,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {}

    process {
     
        if ( -not $objectId ) { 
            #All Security Policies
            $URI = "/api/2.0/services/policy/securitypolicy/all"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            if  ( $Name  ) { 
                $FinalSecPol = $response.securityPolicies.securityPolicy | ? { $_.name -eq $Name }
            } else {
                $FinalSecPol = $response.securityPolicies.securityPolicy
            }

        }
        else {

            #Just getting a single Security group
            $URI = "/api/2.0/services/policy/securitypolicy/$objectId"
            $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
            $FinalSecPol = $response.securityPolicy 
        }

        if ( -not $IncludeHidden ) { 
            foreach ( $CurrSecPol in $FinalSecPol ) { 
                if ( $CurrSecPol.SelectSingleNode('child::extendedAttributes/extendedAttribute')) {
                    $hiddenattr = $CurrSecPol.extendedAttributes.extendedAttribute | ? { $_.name -eq 'isHidden'}
                    if ( -not ($hiddenAttr.Value -eq 'true')){
                        $CurrSecPol
                    }
                }
                else { 
                    $CurrSecPol
                }
            }
        }
        else {
            $FinalSecPol
        }
    }
    end {}
}


function Remove-NsxSecurityPolicy {

    <#
    .SYNOPSIS
    Removes the specified NSX Security Policy.

    .DESCRIPTION
    An NSX Security Policy is a set of Endpoint, firewall, and network 
    introspection services that can be applied to a security group.

    This cmdlet removes the specified Security Policy object.


    .EXAMPLE
    Example1: Remove the SecurityPolicy TestSP
    PS C:\> Get-NsxSecurityPolicy TestSP | Remove-NsxSecurityPolicy

    Example2: Remove the SecurityPolicy $sp without confirmation.
    PS C:\> $sp | Remove-NsxSecurityPolicy -confirm:$false

    
    #>

    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true,Position=1)]
            [ValidateNotNullOrEmpty()]
            [System.Xml.XmlElement]$SecurityPolicy,
        [Parameter (Mandatory=$False)]
            #Prompt for confirmation.  Specify as -confirm:$false to disable confirmation prompt
            [switch]$Confirm=$true,
        [Parameter (Mandatory=$False)]
            [switch]$force=$false,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {}

    process {


        if ($SecurityPolicy.SelectSingleNode("descendant::extendedAttributes/extendedAttribute[name=`"isHidden`" and value=`"true`"]") -and ( -not $force)) {
            write-warning "Not removing $($SecurityPolicy.Name) as it is set as hidden.  Use -Force to force deletion." 
        }
        else { 

            if ( $confirm ) { 
                $message  = "Security Policy removal is permanent."
                $question = "Proceed with removal of Security Policy $($SecurityPolicy.Name)?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
            }
            else { $decision = 0 } 
            if ($decision -eq 0) {
                if ( $force ) { 
                    $URI = "/api/2.0/services/policy/securitypolicy/$($SecurityPolicy.objectId)?force=true"
                }
                else {
                    $URI = "/api/2.0/services/policy/securitypolicy/$($SecurityPolicy.ObjectId)?force=false"
                }
                
                Write-Progress -activity "Remove Security Policy $($SecurityPolicy.Name)"
                invoke-nsxrestmethod -method "delete" -uri $URI -connection $connection | out-null
                write-progress -activity "Remove Security Policy $($SecurityPolicy.Name)" -completed

            }
        }
    }

    end {}
}


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
    or interfaces) by virtue of static or dynamic inclusion.  This cmdlet determines 
    the static and dynamic membership of a given group.

    .EXAMPLE
   
    PS C:\>  Get-NsxSecurityGroup TestSG | Get-NsxSecurityGroupEffectiveMembers
   
    #>

    [CmdLetBinding(DefaultParameterSetName="Name")]
 
    param (

        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateNotNull()]
            [System.Xml.XmlElement]$SecurityGroup,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection

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

        write-debug "$($MyInvocation.MyCommand.Name) : Getting virtualmachine dynamic includes for SG $($SecurityGroup.Name)"
        $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.ObjectId)/translation/virtualmachines"
        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        if ( $response.GetElementsByTagName("vmnodes").haschildnodes) { $dynamicVMNodes = $response.GetElementsByTagName("vmnodes")} else { $dynamicVMNodes = $null }

         write-debug "$($MyInvocation.MyCommand.Name) : Getting ipaddress dynamic includes for SG $($SecurityGroup.Name)"
        $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.ObjectId)/translation/ipaddresses"
        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        if ( $response.GetElementsByTagName("ipNodes").haschildnodes) { $dynamicIPNodes = $response.GetElementsByTagName("ipNodes") } else { $dynamicIPNodes = $null}

         write-debug "$($MyInvocation.MyCommand.Name) : Getting macaddress dynamic includes for SG $($SecurityGroup.Name)"
        $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.ObjectId)/translation/macaddresses"
        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection
        if ( $response.GetElementsByTagName("macNodes").haschildnodes) { $dynamicMACNodes = $response.GetElementsByTagName("macNodes")} else { $dynamicMACNodes = $null}

         write-debug "$($MyInvocation.MyCommand.Name) : Getting VNIC dynamic includes for SG $($SecurityGroup.Name)"
        $URI = "/api/2.0/services/securitygroup/$($SecurityGroup.ObjectId)/translation/vnics"
        $response = invoke-nsxrestmethod -method "get" -uri $URI -connection $connection 
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



function Find-NsxWhereVMUsed {

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
            [VMware.VimAutomation.ViCore.Interop.V1.Inventory.VirtualMachineInterop]$VM,
        [Parameter (Mandatory=$False)]
            #PowerNSX Connection object.
            [ValidateNotNullOrEmpty()]
            [PSCustomObject]$Connection=$defaultNSXConnection
    )
    
    begin {

    }

    process {
     
        #Get Firewall rules
        $L3FirewallRules = Get-nsxFirewallSection -connection $connection | Get-NsxFirewallRule -connection $connection
        $L2FirewallRules = Get-nsxFirewallSection -sectionType layer2sections -connection $connection  | Get-NsxFirewallRule -ruletype layer2sections -connection $connection

        #Get all SGs
        $securityGroups = Get-NsxSecuritygroup -connection $connection
        $MatchedSG = @()
        $MatchedFWL3 = @()
        $MatchedFWL2 = @()
        foreach ( $SecurityGroup in $securityGroups ) {

            $Members = $securityGroup | Get-NsxSecurityGroupEffectiveMembers -connection $connection

            write-debug "$($MyInvocation.MyCommand.Name) : Checking securitygroup $($securitygroup.name) for VM $($VM.name)"
                    
            If ( $members.DynamicIncludeVM ) {
                foreach ( $member in $members.DynamicIncludeVM) {
                    if ( $member.vmnode.vmid -eq $VM.ExtensionData.MoRef.Value ) {
                        $MatchedSG += $SecurityGroup
                    }
                }
            }
        }

        write-debug "$($MyInvocation.MyCommand.Name) : Checking L3 FirewallRules for VM $($VM.name)"
        foreach ( $FirewallRule in $L3FirewallRules ) {

            write-debug "$($MyInvocation.MyCommand.Name) : Checking rule $($FirewallRule.Id) for VM $($VM.name)"
                
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

        write-debug "$($MyInvocation.MyCommand.Name) : Checking L2 FirewallRules for VM $($VM.name)"
        foreach ( $FirewallRule in $L2FirewallRules ) {

            write-debug "$($MyInvocation.MyCommand.Name) : Checking rule $($FirewallRule.Id) for VM $($VM.name)"
                
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


function Get-NsxBackingPortGroup{

    <#
    .SYNOPSIS
    Gets the PortGroups backing an NSX Logical Switch.

    .DESCRIPTION
    NSX Logical switches are backed by one or more Virtual Distributed Switch 
    portgroups that are the connection point in vCenter for VMs that connect to 
    the logical switch.

    In simpler environments, a logical switch may only be backed by a single 
    portgroup on a single Virtual Distributed Switch, but the scope of a logical
    switch is governed by the transport zone it is created in.  The transport 
    zone may span multiple vSphere clusters that have hosts that belong to 
    multiple different Virtual Distributed Switches and in this situation, a 
    logical switch would be backed by a unique portgroup on each Virtual 
    Distributed Switch.

    This cmdlet requires an active and correct PowerCLI connection to the 
    vCenter server that is registered to NSX.  It returns PowerCLI VDPortgroup 
    objects for each backing portgroup.
    
    .EXAMPLE

    
    #>


     param (
        
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({Validate-LogicalSwitch $_ })]
            [object]$LogicalSwitch
    )

    begin {

        if ( -not ( $global:DefaultVIServer.IsConnected )) {
            throw "This cmdlet requires a valid PowerCLI connection.  Use Connect-VIServer to connect to vCenter and try again."
        }
    }

    process { 

        $BackingVDS = $_.vdsContextWithBacking
        foreach ( $vDS in $BackingVDS ) { 

            write-debug "$($MyInvocation.MyCommand.Name) : Backing portgroup id $($vDS.backingValue)"

            try {
                Get-VDPortgroup -Id "DistributedVirtualPortgroup-$($vDS.backingValue)"
            }
            catch {
                throw "VDPortgroup not found on connected vCenter $($global:DefaultVIServer.Name).  $_"
            }
        }
    }

    end {}

}


function Get-NsxBackingDVSwitch{

    <#
    .SYNOPSIS
    Gets the Virtual Distributed Switches backing an NSX Logical Switch.

    .DESCRIPTION
    NSX Logical switches are backed by one or more Virtual Distributed Switch 
    portgroups that are the connection point in vCenter for VMs that connect to 
    the logical switch.

    In simpler environments, a logical switch may only be backed by a single 
    portgroup on a single Virtual Distributed Switch, but the scope of a logical
    switch is governed by the transport zone it is created in.  The transport 
    zone may span multiple vSphere clusters that have hosts that belong to 
    multiple different Virtual Distributed Switches and in this situation, a 
    logical switch would be backed by a unique portgroup on each Virtual 
    Distributed Switch.

    This cmdlet requires an active and correct PowerCLI connection to the 
    vCenter server that is registered to NSX.  It returns PowerCLI VDSwitch 
    objects for each backing VDSwitch.
    
    .EXAMPLE

    
    #>


     param (
        
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [ValidateScript({Validate-LogicalSwitch $_ })]
            [object]$LogicalSwitch
    )

    begin {

        if ( -not ( $global:DefaultVIServer.IsConnected )) {
            throw "This cmdlet requires a valid PowerCLI connection.  Use Connect-VIServer to connect to vCenter and try again."
        }
    }

    process { 

        $BackingVDS = $_.vdsContextWithBacking
        foreach ( $vDS in $BackingVDS ) { 

            write-debug "$($MyInvocation.MyCommand.Name) : Backing vDS id $($vDS.switch.objectId)"

            try {
                Get-VDSwitch -Id "VmwareDistributedVirtualSwitch-$($vDS.switch.objectId)"
            }
            catch {
                throw "VDSwitch not found on connected vCenter $($global:DefaultVIServer.Name).  $_"
            }
        }
    }

    end {}

}



