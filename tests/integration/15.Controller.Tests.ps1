#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe -Tag 'Slow' "Controller" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -NsxServerHint $PNSXTestNSX -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        $script:ctrl = Get-NsxController
        if ( @($ctrl).count -ne 1) {
            $script:SkipCtrlTest = $True
            write-warning "NSX Controller tests disabled.  Ensure only a single controller is deployed to enable controller tests."
        }
        else {
            $ctrlview = Get-View "$($Ctrl.virtualMachineInfo.objectTypeName)-$($Ctrl.virtualMachineInfo.objectId)" -Property Network,Datastore,resourcepool
            $script:rp = Get-ResourcePool -Id ("$($ctrlview.ResourcePool.type)-$($ctrlview.ResourcePool.Value)")
            $script:pg = Get-VdPortGroup -Id ("$($ctrlview.Network.type)-$($ctrlview.Network.Value)")
            $script:ds = Get-Datastore -Id ("$($ctrlview.Datastore.type)-$($ctrlview.Datastore.Value)")

            #Yup - this is dodgy... going to create Find-NsxControllerIpPool using ip matchs to search existing pools one of these days, as you cant reverse engineer this from the controller API response. :(
            $script:pool = Get-NSxIpPool | Where-Object { $_.name -match "controller" }
            write-warning "Using existing controller ds, portgroup and resourcepool config for additional controller deployment"
            $script:SkipCtrlTest = $False
        }
    }

    It "Can deploy a second controller - test warning" -Skip:$SkipCtrlTest {
        #Test that an expected warning is output to the warning stream...
        (( $newctrl = New-NsxController -IpPool $pool -ControllerName pester_test_ctrl_1 -ResourcePool $rp -Datastore $ds -PortGroup $pg -wait -Confirm:$false -password "rubbish" ) 3>&1) -match "A controller is already deployed but a password argument was specified to New-NsxController." | should be $true
        $currentCtrl = Get-NsxController -ObjectId $newctrl.id
        $currentCtrl | should not be $null
        $currentCtrl.status | should be "RUNNING"
    }

    It "Can deploy a third controller - test warning" -Skip:$SkipCtrlTest {
        #Test that an expected warning is output to the warning stream...
        (( $newctrl = New-NsxController -IpPool $pool -ControllerName pester_test_ctrl_1 -ResourcePool $rp -Datastore $ds -PortGroup $pg -wait -Confirm:$false -password "rubbish" ) 3>&1) -match "A controller is already deployed but a password argument was specified to New-NsxController." | should be $true
        $currentCtrl = Get-NsxController -ObjectId $newctrl.id
        $currentCtrl | should not be $null
        $currentCtrl.status | should be "RUNNING"
    }
    It "Can remove a controllers" -Skip:$SkipCtrlTest {
        $ctrlToRemove = @(Get-NSxController | Where-Object { $_.id -ne $ctrl.id })
        {$CtrlToRemove | Remove-NsxController -Wait -Confirm:$false} | should not throw
        foreach ( $ctrl in $ctrlToRemove ) {
            Get-NsxController -ObjectId $ctrl.id  | should be $null
        }
    }

    It "Can update controller state" {
        {Invoke-NsxControllerStateUpdate -Wait -WaitTimeout 300} | should not throw
    }

    It "Can set controller syslog configuration" {
        {$script:ControllerSyslog = Get-NSXController -ObjectId $ctrl.id | Set-NsxControllerSyslog -syslogServer "192.168.1.20" -Port "514" -Protocol "UDP" -Level "INFO" } | should not throw
        $ControllerSyslog | should not be $null
        $ControllerSyslog.syslogServer | should be "192.168.1.20"
        $ControllerSyslog.port | should be "514"
        $ControllerSyslog.protocol | should be "UDP"
        $ControllerSyslog.level | should be "INFO"
    }

    It "Can get controller syslog configuration" {
        {$script:ControllerSyslog = Get-NSXControllerSyslog -ObjectId $ctrl.id} | should not throw
        $ControllerSyslog | should not be $null
        $ControllerSyslog.syslogServer | should be "192.168.1.20"
        $ControllerSyslog.port | should be "514"
        $ControllerSyslog.protocol | should be "UDP"
        $ControllerSyslog.level | should be "INFO"
    }

    It "Can update controller syslog configuration" {
        {$script:ControllerSyslog = Get-NSXController -ObjectId $ctrl.id | Set-NsxControllerSyslog -syslogServer "192.168.1.21" -Port "515" -Protocol "TCP" -Level "WARN" } | should not throw
        $ControllerSyslog | should not be $null
        $ControllerSyslog.syslogServer | should be "192.168.1.21"
        $ControllerSyslog.port | should be "515"
        $ControllerSyslog.protocol | should be "TCP"
        $ControllerSyslog.level | should be "WARN"
    }

    It "Can delete controller syslog configuration" {
        {Get-NsxControllerSyslog -ObjectId $ctrl.id | Remove-NSXControllerSyslog} | should not throw
        Get-NSXControllerSyslog -ObjectId $ctrl.id | should be $null
    }


    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.

        disconnect-nsxserver

    }

}

