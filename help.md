---
layout: page
permalink: /help/
---

# Getting Help

Using the help functions of PowerNSX are key to learning now the commands work. Whilst the examples within this wiki provide enough to get you going the most detailed help is built in.

# Command level help

Within each command there are detailed examples and information regarding how to use the command, its parameters, and the properties that make up the command. If an administrator wants to learn more about the command using the get-help command will reveal what is needed.


get-help can be used against all Powershell commands.

```
#!Powershell

PowerCLI C:\> get-help new-nsxlogicalswitch

NAME
    New-NsxLogicalSwitch

SYNOPSIS
    Creates a new Logical Switch


SYNTAX
    New-NsxLogicalSwitch -TransportZone <XmlElement> [-Name] <String> [-Description <String>] [-TenantId <String>] [-ControlPlaneMode
    <String>] [-Connection <PSObject>] [<CommonParameters>]


DESCRIPTION
    An NSX Logical Switch provides L2 connectivity to VMs attached to it.
    A Logical Switch is 'bound' to a Transport Zone, and only hosts that are
    members of the Transport Zone are able to host VMs connected to a Logical
    Switch that is bound to it.  All Logical Switch operations require a
    Transport Zone.  A new Logical Switch defaults to the control plane mode of
    the Transport Zone it is created in, but CP mode can specified as required.


RELATED LINKS

REMARKS
    To see the examples, type: "get-help New-NsxLogicalSwitch -examples".
    For more information, type: "get-help New-NsxLogicalSwitch -detailed".
    For technical information, type: "get-help New-NsxLogicalSwitch -full".

```

Powershell provides a pretty awesome help menu. Based on what the author has populated there is an explanation about what the command does, what the command will do, and includes the syntax structure of the command.

In the remarks there are three toggles. Examples, Detailed, and Full.

Lets use the -examples on our command:

```
#!Powershell

PowerCLI C:\> get-help new-nsxlogicalswitch -examples

NAME
    New-NsxLogicalSwitch

SYNOPSIS
    Creates a new Logical Switch

    -------------------------- EXAMPLE 1 --------------------------

    C:\PS>Example1: Create a Logical Switch with default control plane mode.


    PS C:\> Get-NsxTransportZone | New-NsxLogicalSwitch -name LS6

    Example2: Create a Logical Switch with a specific control plane mode.
    PS C:\> Get-NsxTransportZone | New-NsxLogicalSwitch -name LS6
        -ControlPlaneMode MULTICAST_MODE

```

Here we can see our examples. These examples outline how the command can be used. Each command has one or more examples to show a number of ways to use the command including the optional parameters.


Lets use the -detailed toggle on our command:

```
#!Powershell



PowerCLI C:\> get-help new-nsxlogicalswitch -detailed

NAME
    New-NsxLogicalSwitch

SYNOPSIS
    Creates a new Logical Switch


SYNTAX
    New-NsxLogicalSwitch -TransportZone <XmlElement> [-Name] <String> [-Description <String>] [-TenantId <String>] [-ControlPlaneMode
    <String>] [-Connection <PSObject>] [<CommonParameters>]


DESCRIPTION
    An NSX Logical Switch provides L2 connectivity to VMs attached to it.
    A Logical Switch is 'bound' to a Transport Zone, and only hosts that are
    members of the Transport Zone are able to host VMs connected to a Logical
    Switch that is bound to it.  All Logical Switch operations require a
    Transport Zone.  A new Logical Switch defaults to the control plane mode of
    the Transport Zone it is created in, but CP mode can specified as required.


PARAMETERS
    -TransportZone <XmlElement>

    -Name <String>

    -Description <String>

    -TenantId <String>

    -ControlPlaneMode <String>

    -Connection <PSObject>
        PowerNSX Connection object.

    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer and OutVariable. For more information, see
        about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

    -------------------------- EXAMPLE 1 --------------------------

    C:\PS>Example1: Create a Logical Switch with default control plane mode.

    PS C:\> Get-NsxTransportZone | New-NsxLogicalSwitch -name LS6

    Example2: Create a Logical Switch with a specific control plane mode.
    PS C:\> Get-NsxTransportZone | New-NsxLogicalSwitch -name LS6
        -ControlPlaneMode MULTICAST_MODE




REMARKS
    To see the examples, type: "get-help New-NsxLogicalSwitch -examples".
    For more information, type: "get-help New-NsxLogicalSwitch -detailed".
    For technical information, type: "get-help New-NsxLogicalSwitch -full".


```

In this output we see the parameters are detailed into what input they take included any supplementary information the author has included.


Below is the full output. The full output provides the most detail.

```
#!Powershell


PowerCLI C:\> get-help new-nsxlogicalswitch -full

NAME
    New-NsxLogicalSwitch

SYNOPSIS
    Creates a new Logical Switch

SYNTAX
    New-NsxLogicalSwitch -TransportZone <XmlElement> [-Name] <String> [-Description <String>] [-TenantId <String>] [-ControlPlaneMode
    <String>] [-Connection <PSObject>] [<CommonParameters>]


DESCRIPTION
    An NSX Logical Switch provides L2 connectivity to VMs attached to it.
    A Logical Switch is 'bound' to a Transport Zone, and only hosts that are
    members of the Transport Zone are able to host VMs connected to a Logical
    Switch that is bound to it.  All Logical Switch operations require a
    Transport Zone.  A new Logical Switch defaults to the control plane mode of
    the Transport Zone it is created in, but CP mode can specified as required.


PARAMETERS
    -TransportZone <XmlElement>

        Required?                    true
        Position?                    named
        Default value
        Accept pipeline input?       true (ByValue)
        Accept wildcard characters?  false

    -Name <String>

        Required?                    true
        Position?                    2
        Default value
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -Description <String>

        Required?                    false
        Position?                    named
        Default value
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -TenantId <String>

        Required?                    false
        Position?                    named
        Default value
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -ControlPlaneMode <String>

        Required?                    false
        Position?                    named
        Default value
        Accept pipeline input?       false
        Accept wildcard characters?  false

    -Connection <PSObject>
        PowerNSX Connection object.

        Required?                    false
        Position?                    named
        Default value                $defaultNSXConnection
        Accept pipeline input?       false
        Accept wildcard characters?  false

    <CommonParameters>
        This cmdlet supports the common parameters: Verbose, Debug,
        ErrorAction, ErrorVariable, WarningAction, WarningVariable,
        OutBuffer and OutVariable. For more information, see
        about_CommonParameters (http://go.microsoft.com/fwlink/?LinkID=113216).

INPUTS

OUTPUTS

    -------------------------- EXAMPLE 1 --------------------------

    C:\PS>Example1: Create a Logical Switch with default control plane mode.


    PS C:\> Get-NsxTransportZone | New-NsxLogicalSwitch -name LS6

    Example2: Create a Logical Switch with a specific control plane mode.
    PS C:\> Get-NsxTransportZone | New-NsxLogicalSwitch -name LS6
        -ControlPlaneMode MULTICAST_MODE


RELATED LINKS

```

The full output includes each parameter and details about the parameter itself
