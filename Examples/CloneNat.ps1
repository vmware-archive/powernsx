#Sample PowerNSX NAT clone script.
#Nick Bradford, nbradford@vmware.com
#


#Requires -Module PowerNSX



function Copy-Nat {

     <#
    .SYNOPSIS
    Removes a Logical Switch

    .DESCRIPTION
    Duplicates the NAT configuration from $SourceEdge to $DestinationEdge.
    Approach could be used for other Edge features as well.  

    Function is pipeline aware, so could be used to duplicate nat from single
    source edge to any destination edges on pipline.

    .EXAMPLE
    PS C:\> get-nsxedge edge01 | get-nsxedgenat | Get-NsxEdgeNatRule                                                           

    ruleId            : 196609                                                                                                                                           
    ruleTag           : 196609                                                                                                                                           
    ruleType          : user                                                                                                                                             
    action            : dnat                                                                                                                                             
    vnic              : 0                                                                                                                                                
    originalAddress   : 1.1.1.1                                                                                                                                          
    translatedAddress : 2.2.2.2                                                                                                                                          
    loggingEnabled    : false                                                                                                                                            
    enabled           : true                                                                                                                                             
    protocol          : any                                                                                                                                              
    originalPort      : any                                                                                                                                              
    translatedPort    : any                                                                                                                                              
    edgeId            : edge-183                                                                                                                                         
                                                                                                                                                                        
    ruleId            : 196610                                                                                                                                           
    ruleTag           : 196610                                                                                                                                           
    ruleType          : user                                                                                                                                             
    action            : dnat                                                                                                                                             
    vnic              : 0                                                                                                                                                
    originalAddress   : 3.3.3.3                                                                                                                                          
    translatedAddress : 4.4.4.4                                                                                                                                          
    loggingEnabled    : false                                                                                                                                            
    enabled           : true                                                                                                                                             
    protocol          : any                                                                                                                                              
    originalPort      : any                                                                                                                                              
    translatedPort    : any                                                                                                                                              
    edgeId            : edge-183                                                                                                                                         
                                                                                                                                                                        
                                                                                                                                                                        
                                                                                                                                                                        
    PS C:\> get-nsxedge test | get-nsxedgenat | Get-NsxEdgeNatRule                                                             
                                                                                                                                                                        
                                                                                                                                                                        
    ruleId            : 196609                                                                                                                                           
    ruleTag           : 196609                                                                                                                                           
    ruleType          : user                                                                                                                                             
    action            : dnat                                                                                                                                             
    vnic              : 0                                                                                                                                                
    originalAddress   : 1.1.1.1                                                                                                                                          
    translatedAddress : 2.2.2.2                                                                                                                                          
    loggingEnabled    : false                                                                                                                                            
    enabled           : true                                                                                                                                             
    protocol          : any                                                                                                                                              
    originalPort      : any                                                                                                                                              
    translatedPort    : any                                                                                                                                              
    edgeId            : edge-185                                                                                                                                         
                                                                                                                                                                                                                 
    PS C:\> get-nsxedge test2 | get-nsxedgenat | Get-NsxEdgeNatRule                                                                                                                                                                                                              
                                                                                                                                                                        
    ruleId            : 196609                                                                                                                                           
    ruleTag           : 196609                                                                                                                                           
    ruleType          : user                                                                                                                                             
    action            : dnat                                                                                                                                             
    vnic              : 0                                                                                                                                                
    originalAddress   : 1.1.1.1                                                                                                                                          
    translatedAddress : 2.2.2.2                                                                                                                                          
    loggingEnabled    : false                                                                                                                                            
    enabled           : true                                                                                                                                             
    protocol          : any                                                                                                                                              
    originalPort      : any                                                                                                                                              
    translatedPort    : any                                                                                                                                              
    edgeId            : edge-186                                                                                                                                                                   
                                                                                                                                                                        
    PS C:\> get-nsxedge | ? { $_.name -match 'test' } | Copy-Nat -SourceEdge (get-nsxedge edge01)                              
                                                                                                                                                                        
    Any existing NAT rules on destination edge Test (edge-185) are about to be overwritten.                                                                              
    Are you sure?                                                                                                                                                        
    [Y] Yes  [N] No  [?] Help (default is "N"): y                                                                                                                        
                                                                                                                                                                        
                                                                                                                                                                        
    id                : edge-185                                                                                                                                         
    version           : 10                                                                                                                                               
    status            : deployed                                                                                                                                         
    tenant            : default                                                                                                                                          
    name              : Test                                                                                                                                             
    fqdn              : Test                                                                                                                                             
    enableAesni       : true                                                                                                                                             
    enableFips        : false                                                                                                                                            
    vseLogLevel       : info                                                                                                                                             
    vnics             : vnics                                                                                                                                            
    appliances        : appliances                                                                                                                                       
    cliSettings       : cliSettings                                                                                                                                      
    features          : features                                                                                                                                         
    autoConfiguration : autoConfiguration                                                                                                                                
    type              : gatewayServices                                                                                                                                  
    isUniversal       : false                                                                                                                                            
    hypervisorAssist  : false                                                                                                                                            
    queryDaemon       : queryDaemon                                                                                                                                      
    edgeSummary       : edgeSummary                                                                                                                                      
                                                                                                                                                                        
                                                                                                                                                                        
    Any existing NAT rules on destination edge Test2 (edge-186) are about to be overwritten.                                                                             
    Are you sure?                                                                                                                                                        
    [Y] Yes  [N] No  [?] Help (default is "N"): y                                                                                                                        
    id                : edge-186                                                                                                                                         
    version           : 4                                                                                                                                                
    status            : deployed                                                                                                                                         
    tenant            : default                                                                                                                                          
    name              : Test2                                                                                                                                            
    fqdn              : Test2                                                                                                                                            
    enableAesni       : true                                                                                                                                             
    enableFips        : false                                                                                                                                            
    vseLogLevel       : info                                                                                                                                             
    vnics             : vnics                                                                                                                                            
    appliances        : appliances                                                                                                                                       
    cliSettings       : cliSettings                                                                                                                                      
    features          : features                                                                                                                                         
    autoConfiguration : autoConfiguration                                                                                                                                
    type              : gatewayServices                                                                                                                                  
    isUniversal       : false                                                                                                                                            
    hypervisorAssist  : false                                                                                                                                            
    queryDaemon       : queryDaemon                                                                                                                                      
    edgeSummary       : edgeSummary                                                                                                                                      
                                                                                                                                                              
    PS C:\> get-nsxedge test | get-nsxedgenat | Get-NsxEdgeNatRule                                                                                                                                                                                                                                     
                                         
    ruleId            : 196609                                                                                                                                           
    ruleTag           : 196609                                                                                                                                           
    ruleType          : user                                                                                                                                             
    action            : dnat                                                                                                                                             
    vnic              : 0                                                                                                                                                
    originalAddress   : 1.1.1.1                                                                                                                                          
    translatedAddress : 2.2.2.2                                                                                                                                          
    loggingEnabled    : false                                                                                                                                            
    enabled           : true                                                                                                                                             
    protocol          : any                                                                                                                                              
    originalPort      : any                                                                                                                                              
    translatedPort    : any                                                                                                                                              
    edgeId            : edge-185                                                                                                                                         
                                                                                                                                                                        
    ruleId            : 196610                                                                                                                                           
    ruleTag           : 196610                                                                                                                                           
    ruleType          : user                                                                                                                                             
    action            : dnat                                                                                                                                             
    vnic              : 0                                                                                                                                                
    originalAddress   : 3.3.3.3                                                                                                                                          
    translatedAddress : 4.4.4.4                                                                                                                                          
    loggingEnabled    : false                                                                                                                                            
    enabled           : true                                                                                                                                             
    protocol          : any                                                                                                                                              
    originalPort      : any                                                                                                                                              
    translatedPort    : any                                                                                                                                              
    edgeId            : edge-185                                                                                                                                                                                  
                                                                                                                                                              
    PS C:\> get-nsxedge test2 | get-nsxedgenat | Get-NsxEdgeNatRule                                                                                                                                                                                                                                    
                                                                                                                                                                        
    ruleId            : 196609                                                                                                                                           
    ruleTag           : 196609                                                                                                                                           
    ruleType          : user                                                                                                                                             
    action            : dnat                                                                                                                                             
    vnic              : 0                                                                                                                                                
    originalAddress   : 1.1.1.1                                                                                                                                          
    translatedAddress : 2.2.2.2                                                                                                                                          
    loggingEnabled    : false                                                                                                                                            
    enabled           : true                                                                                                                                             
    protocol          : any                                                                                                                                              
    originalPort      : any                                                                                                                                              
    translatedPort    : any                                                                                                                                              
    edgeId            : edge-186                                                                                                                                         
                                                                                                                                                                        
    ruleId            : 196610                                                                                                                                           
    ruleTag           : 196610                                                                                                                                           
    ruleType          : user                                                                                                                                             
    action            : dnat                                                                                                                                             
    vnic              : 0                                                                                                                                                
    originalAddress   : 3.3.3.3                                                                                                                                          
    translatedAddress : 4.4.4.4                                                                                                                                          
    loggingEnabled    : false                                                                                                                                            
    enabled           : true                                                                                                                                             
    protocol          : any                                                                                                                                              
    originalPort      : any                                                                                                                                              
    translatedPort    : any                                                                                                                                              
    edgeId            : edge-186                                                                                                                                         

    #>

    #Method:
    # 1) Get Source Edge
    # 2) Copy source nat feature xml and remove edgeid elem (PowerNSX adds this, and NSX API doesnt expect it and will bail if its there)
    # 3) Modify Destination edge xml to:
    #   a) Remove edgeid elem (PowerNSX adds this, and NSX API doesnt expect it and will bail if its there)
    #   b) Remove nat elem
    #   c) import and add source edge nat elem
    # 4) Use set-nsxedge to post modified XML back.

    param(

        [Parameter (Mandatory=$true)]
            [System.Xml.XmlElement]$SourceEdge,
        [Parameter (Mandatory=$true,ValueFromPipeline=$true)]
            [System.Xml.XmlElement]$DestinationEdge,
        [Parameter (Mandatory=$false,ValueFromPipeline=$true)]
            [Switch]$ConfirmOverwrite=$true

    )

    begin{
        #GetSourceEdge Nat config and remove edgeid and version
        $nat = $SourceEdge | Get-NsxEdgeNat
        $null = $nat.RemoveChild($nat.selectsinglenode("child::edgeId"))
        $null = $nat.RemoveChild($nat.selectsinglenode("child::version"))
    
    }
    process{

        #Doing this once for each edge on the pipline so $_ is current pipelin obj..  Clone so we dont modify original xml.
        $_DestinationEdge = $_.cloneNode($true)
        Write-Debug "destedge : $($_DestinationEdge.edgeid)"

        #Remove NAT feature if it already exists.  Probably need a warning here...
        if ( $_DestinationEdge.selectsinglenode("child::features/nat") ) {

            if ( $ConfirmOverwrite ) {
                #Check user wants to drop existing nat rules.

                $message  = "Any existing NAT rules on destination edge $($_DestinationEdge.Name) ($($_DestinationEdge.id)) are about to be overwritten."
                $question = "Are you sure?"

                $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
                $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

                $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)

            }
            else {
                $decision = 0
            }

            if ( $decision -eq 1 ) { 
                throw "Not removing existing NAT rules on destination edge $($_DestinationEdge.Name) ($($_DestinationEdge.id))"
            }

            $null = $_DestinationEdge.features.RemoveChild($_DestinationEdge.features.selectsinglenode("child::nat"))
        }

        #Import and attach NAT node.
        $newnat = $_DestinationEdge.OwnerDocument.ImportNode($nat, $true)
        $null = $_DestinationEdge.features.AppendChild($newnat)

        #Update Edge
        $_DestinationEdge | Set-NsxEdge -Confirm:$false
    }

    end{}
}