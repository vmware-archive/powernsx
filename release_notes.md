# PowerNSX v2.0 Release notes

## Overview

Version 2 is a major version enhancement over the initial release of PowerNSX v1.  

It coincides with a move to the VMware github site for the PowerNSX project and also signifies an attempt to move to a more formal and structure release approach.  From the release of v2, incremental updates will be released frequently as .x releases, and Major versions less frequently when there is a significant enhancement over the previous major release.  Review the issues page at the projects github site for any available release details.  

Users are encouraged to submit feature requests and bugs for the team, and they will be categorised into Minor/Major release and have a milestone set by the team appropriately.

## Cmdlets Added since v1

 * Add-NsxEdgeInterfaceAddress
 * Add-NsxFirewallExclusionListMember
 * Add-NsxSecurityGroupMember
 * Add-NsxServiceGroupMember
 * Disable-NsxEdgeSsh
 * Disconnect-NsxServer
 * Enable-NsxEdgeSsh
 * Find-NsxWhereVMUsed
 * Get-NsxController
 * Get-NsxEdgeCertificate
 * Get-NsxEdgeCsr
 * Get-NsxEdgeInterfaceAddress
 * Get-NsxEdgeNat
 * Get-NsxEdgeNatRule
 * Get-NsxFirewallExclusionListMember
 * Get-NsxIpPool
 * Get-NsxManagerBackup
 * Get-NsxManagerComponentSummary
 * Get-NsxManagerNetwork
 * Get-NsxManagerSsoConfig
 * Get-NsxManagerSyslogServer
 * Get-NsxManagerSystemSummary
 * Get-NsxManagerTimeSettings
 * Get-NsxManagerVcenterConfig
 * Get-NsxSecurityTag
 * Get-NsxSecurityTagAssignment
 * Get-NsxSegmentIdRange
 * Get-NsxServiceGroup
 * Get-NsxServiceGroupMember
 * Get-NsxSpoofguardNic
 * Get-NsxSpoofguardPolicy
 * Get-NsxSslVpn
 * Get-NsxSslVpnAuthServer
 * Get-NsxSslVpnClientInstallationPackage
 * Get-NsxSslVpnIpPool
 * Get-NsxSslVpnPrivateNetwork
 * Get-NsxSslVpnUser
 * Get-NsxVdsContext
 * Grant-NsxSpoofguardNicApproval
 * Install-NsxCluster
 * New-NsxAddressSpec
 * New-NsxClusterVxlanConfig
 * New-NsxController
 * New-NsxEdgeCsr
 * New-NsxEdgeNatRule
 * New-NsxIpPool
 * New-NsxLoadBalancerMonitor
 * New-NsxManager
 * New-NsxSecurityTag
 * New-NsxSecurityTagAssignment
 * New-NsxSegmentIdRange
 * New-NsxServiceGroup
 * New-NsxSpoofguardPolicy
 * New-NsxSslVpnAuthServer
 * New-NsxSslVpnClientInstallationPackage
 * New-NsxSslVpnIpPool
 * New-NsxSslVpnPrivateNetwork
 * New-NsxSslVpnUser
 * New-NsxTransportZone
 * New-NsxVdsContext
 * Publish-NsxSpoofguardPolicy
 * Remove-NsxCluster
 * Remove-NsxClusterVxlanConfig
 * Remove-NsxEdgeCertificate
 * Remove-NsxEdgeInterfaceAddress
 * Remove-NsxEdgeNatRule
 * Remove-NsxFirewallExclusionListMember
 * Remove-NsxLoadBalancerApplicationProfile
 * Remove-NsxLoadBalancerMonitor
 * Remove-NsxSecurityGroupMember
 * Remove-NsxSecurityTag
 * Remove-NsxSecurityTagAssignment
 * Remove-NsxSegmentIdRange
 * Remove-NsxServiceGroup
 * Remove-NsxSpoofguardPolicy
 * Remove-NsxSslVpnClientInstallationPackage
 * Remove-NsxSslVpnIpPool
 * Remove-NsxSslVpnPrivateNetwork
 * Remove-NsxSslVpnUser
 * Remove-NsxTransportZone
 * Remove-NsxVdsContext
 * Repair-NsxEdge
 * Revoke-NsxSpoofguardNicApproval
 * Set-NsxEdgeNat
 * Set-NsxManager
 * Set-NsxSslVpn
 * Update-PowerNsx


## Cmdlets removed since v1

 * Get-EasterEgg
 * Where-NsxVMUsed


## Breaking Changes

Breaking changes are kept to a minimum, and future releases will continue this approach.  The following changes were necessary to avoid import warnings for non standard verb use, and in the case of new-nsxfirewall rule changes, to align the cmlet output with expected behaviour (in this case, there is a switch added that will allow continued use of the old behaviour if required for a short period).  The changes required by users to accomodate the changes are expected to be very minor.

 * Renamed Where-NSxVMUsed to Find-NsxWhereVMUsed to avoid import warning on non-standard verbs
 * Refactored 'Redploy-NsxEdge' to 'Repair-NsxEdge -operation Redeploy' to avoid import warning on non-standard verbs, and to support the Resync operation consistently as well
 * NewNsxFirewall-Rule now returns the actual rule that was created, rather than the whole containing section.  A -ReturnRule:$false switch has been added to allow users to work around this change in behaviour for now.  The added switch is deprecated, and will be removed in a subsequent version once users have had a chance to update.  If you are relying on the output of New-NsxFirewallRule to perform futher operations, you must add the -ReturnRule:$false switch to your invocation of New-NsxFirewallRule to continue using it in the current manner.
