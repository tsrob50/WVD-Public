<#
.SYNOPSIS
    Adds a list of Windows Performance Counters to a Log Analytics workspace.
.DESCRIPTION
    This script adds a list of Windows Performance Counters to a Log Analytics workspace.
    The counters in the list are required for the ARM-based Windows Virtual Desktop, Log Analytics
    solution available at the link below.  This script automates the process of adding the counters to 
    Log Analytics Workspace.  
    The PowerShell session must be logged into Azure prior to running this script.
    Full details can be found at:
    http://www.ciraltos.com
    https://techcommunity.microsoft.com/t5/windows-it-pro-blog/proactively-monitor-arm-based-windows-virtual-desktop-with-azure/ba-p/1508735
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Test it before you trust it!
    Author      : Travis Roberts, Ciraltos llc
    Website     : www.ciraltos.com
    Version     : 1.0.0.0 Initial Build
#>


######## Variables ##########

# The Workspace Resource Group
$rg = "temploganalyticsrg"

# The Workspace Name
$wsName = "TempLogAnalyticsforwvd"



$perfCounters = 'Terminal Services Session(*)\% Processor Time',
'Terminal Services(*)\Active Sessions',
'Terminal Services(*)\Inactive Sessions',
'Terminal Services(*)\Total Sessions',
'LogicalDisk(*)\% Free Space',
'LogicalDisk(*)\Avg. Disk sec/Read',
'LogicalDisk(*)\Avg. Disk sec/Write',
'LogicalDisk(*)\Current Disk Queue Length',
'LogicalDisk(*)\Disk Reads/sec',
'LogicalDisk(*)\Disk Transfers/sec',
'LogicalDisk(*)\Disk Writes/sec',
'LogicalDisk(*)\Free Megabytes',
'Processor(_Total)\% Processor Time',
'Memory(*)\% Committed Bytes In Use',
'Network Adapter(*)\Bytes Received/sec',
'Network Adapter(*)\Bytes Sent/sec',
'Process(*)\% Processor Time',
'Process(*)\% User Time',
'Process(*)\IO Read Operations/sec',
'Process(*)\IO Write Operations/sec',
'Process(*)\Thread Count',
'Process(*)\Working Set',
'RemoteFX Graphics(*)\Average Encoding Time',
'RemoteFX Graphics(*)\Frames Skipped/Second - Insufficient Client Resources',
'RemoteFX Graphics(*)\Frames Skipped/Second - Insufficient Network Resources',
'RemoteFX Graphics(*)\Frames Skipped/Second - Insufficient Server Resources',
'RemoteFX Network(*)\Current TCP Bandwidth',
'RemoteFX Network(*)\Current TCP RTT',
'RemoteFX Network(*)\Current UDP Bandwidth',
'RemoteFX Network(*)\Current UDP RTT',
'PhysicalDisk(*)\Avg. Disk Bytes/Read',
'PhysicalDisk(*)\Avg. Disk Bytes/Write',
'PhysicalDisk(*)\Avg. Disk sec/Write',
'PhysicalDisk(*)\Avg. Disk sec/Read',
'PhysicalDisk(*)\Avg. Disk Bytes/Transfer',
'PhysicalDisk(*)\Avg. Disk sec/Transfer'


# Add perf counters to Log Analytics Workspace
foreach ($perfCounter in $perfCounters) {
    $perfArray = $perfCounter.split("\").split("(").split(")")
    $objectName = $perfArray[0]
    $instanceName = $perfArray[1]
    $counterName = $perfArray[3]
    $name = ("$objectName-$counterName") -replace "/", "Per" -replace "%", "Percent" 
    write-output $name
    try {
        New-AzOperationalInsightsWindowsPerformanceCounterDataSource -ErrorAction Stop -ResourceGroupName $rg `
            -WorkspaceName $wsName -ObjectName $objectName -InstanceName $instanceName -CounterName $counterName `
            -IntervalSeconds 60  -Name $name -Force
    }
    catch {
        $ErrorMessage = $_.Exception.message
        Write-Error ("Adding PerfCounter $name had the following error: " + $ErrorMessage)
    }
}
