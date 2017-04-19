#PowerNSX Test template.
#Nick Bradford : nbradford@vmware.com

#Because PowerNSX is an API consumption tool, its test framework is limited to
#exercising cmdlet functionality against a functional NSX and vSphere API
#If you disagree with this approach - feel free to start writing mocks for all
#potential API reponses... :)

#In the meantime, the test format is not as elegant as normal TDD, but Ive made some effort to get close to this.
#Each functional area in NSX should have a separate test file.

#Try to group related tests in contexts.  Especially ones that rely on configuration done in previous tests
#Try to make tests as standalone as possible, but generally round trips to the API are expensive, so bear in mind
#the time spent recreating configuration created in previous tests just for the sake of keeping test isolation.

#Try to put all non test related setup and tear down in the BeforeAll and AfterAll sections.  ]
#If a failure in here occurs, the Describe block is not executed.

#########################
#Do not remove this - we need to ensure connection setup and module deps preload have occured.
If ( -not $PNSXTestVC ) {
    Throw "Tests must be invoked via Start-Test function from the Test module.  Import the Test module and run Start-Test"
}

Describe "DFW Global Properties" {

    BeforeAll {

        #BeforeAll block runs _once_ at invocation regardless of number of tests/contexts/describes.
        #We load the mod and establish connection to NSX Manager here.

        #Put any setup tasks in here that are required to perform your tests.  Typical defaults:
        import-module $pnsxmodule
        $script:DefaultNsxConnection = Connect-NsxServer -vCenterServer $PNSXTestVC -Credential $PNSXTestDefViCred -ViWarningAction "Ignore"
        # Threshold Variables
        $script:cpuThreshold = "75"
        $script:cpuThreshold1 = "85"
        $script:memoryThreshold = "75"
        $script:memoryThreshold1 = "85"
        $script:cpsThreshold = "125000"
        $script:cpsThreshold1 = "200000"
        $script:cpsDefault = "100000"
        $script:memorydefault = "100"
        $script:cpudefault = "100"

    }

    AfterAll {
        #AfterAll block runs _once_ at completion of invocation regardless of number of tests/contexts/describes.
        #Clean up anything you create in here.  Be forceful - you want to leave the test env as you found it as much as is possible.
        #We kill the connection to NSX Manager here.

        #TODO: This should take existing and honour it on finish
        Set-NsxFirewallThreshold -Cpu 100 -Memory 100 -ConnectionsPerSecond 100000 | out-null
        disconnect-nsxserver
    }

    BeforeEach {

    }

    AfterEach {

    }

    Context "DFW Global options" {
        it "Can validate default DFW event thresholds"{
            #Unsure if this is correct "test"
            $threshold = Get-NsxFirewallThreshold
            $threshold | should not be $null
            $threshold.Cpu.percentValue | should be $cpuDefault
            $threshold.Memory.percentValue | should be $memoryDefault
            $threshold.ConnectionsPerSecond.value | should be $cpsDefault
        }
        it "Can adjust all DFW event thresholds" {
            $threshold = Set-NsxFirewallThreshold -Cpu $cputhreshold -Memory $memorythreshold -ConnectionsPerSecond $cpsThreshold
            $threshold | should not be $null
            $threshold.Cpu.percentValue | should be $cputhreshold
            $threshold.Memory.percentValue | should be $memorythreshold
            $threshold.ConnectionsPerSecond.value | should be $cpsThreshold
        }
        it "Can adjust Memory DFW event threshold" {
            $threshold = Set-NsxFirewallThreshold  -Memory $memorythreshold1
            $threshold | should not be $null

            $threshold.Memory.percentValue | should be $memorythreshold1
        }
        it "Can adjust CPU DFW event threshold" {
            $threshold = Set-NsxFirewallThreshold -Cpu $cputhreshold1
            $threshold | should not be $null
            $threshold.Cpu.percentValue | should be $cputhreshold1
        }
        it "Can adjust ConnectionsPerSecond DFW event thresholds" {
            $threshold = Set-NsxFirewallThreshold -ConnectionsPerSecond $cpsThreshold1
            $threshold | should not be $null
            $threshold.ConnectionsPerSecond.Value | should be $cpsThreshold1
        }

        it "Can adjust Global Containers"{

        }

        it "Can adjust TCP Optimisation"{

        }
    }
}