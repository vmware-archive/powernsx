#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "Controller" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
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
            $script:pool = Get-NSxIpPool | ? { $_.name -match "controller" }
            write-warning "Using existing controller ds, portgroup and resourcepool config for additional controller deployment"
            $script:SkipCtrlTest = $False
        }
    }

    It "Can deploy a controller - Sync" -Skip:$SkipCtrlTest {
        $newctrl = New-NsxController -IpPool $pool -ControllerName pester_test_ctrl_1 -ResourcePool $rp -Datastore $ds -PortGroup $pg -wait -Confirm:$false
        $currentCtrl = Get-NsxController -ObjectId $newctrl.id
        $currentCtrl | should not be $null
        $currentCtrl.status | should be "RUNNING"
    }

    It "Can remove a controller - Sync" -Skip:$SkipCtrlTest {
        $ctrlToRemove = Get-NSxController | ? { $_.id -ne $ctrl.id }
        {$CtrlToRemove | Remove-NsxController -Wait -Confirm:$false} | should not throw
        Get-NsxController -ObjectId $ctrlToRemove.id  | should be $null
    }
    AfterAll {

        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #We kill the connection to NSX Manager here.
        disconnect-nsxserver
    }
}

