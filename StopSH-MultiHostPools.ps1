
<#
.SYNOPSIS
    Automated process to stop unused session hosts in a WVD personal or pooled host pool.
.DESCRIPTION
    This script is intended to automatically stop pooled or personal host pool session hosts in an Azure Virtual Desktop
    host pool. The script will evaluate session hosts in a host pool and create a list of session hosts with
    active connections. The script will then compare all session hosts in the personal host pool that are 
    powered on and not in drain mode, and shut down the session hosts that have no active connections.

    Requirements:
    WVD personal host pool with Start on Connect enabled 
    https://docs.microsoft.com/en-us/azure/virtual-desktop/start-virtual-machine-connect?WT.mc_id=AZ-MVP-5004159
    An Azure Function App
        Use System Assigned Managed ID
        Give Virtual Machine Contributor and Desktop Virtualization Reader rights for the Session Host VM Resource Group to the Managed ID
        Az powershell modules enabled
    For best results set a GPO to log out disconnected and idle sessions (Users have to disconnect or the session hosts won't shut down)
    For help with setting the schedule:
    https://docs.microsoft.com/en-us/azure/azure-functions/functions-bindings-timer?tabs=csharp&WT.mc_id=AZ-MVP-5004159#ncrontab-expressions
    For full  details, check here:
    TBD
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Test it before you trust it
    Author      : Travis Roberts, Ciraltos llc
    Website     : www.ciraltos.com
    Version     :1.1.0.0 Add support for pooled host pools and multiple pooled and/or personal host pools 
                 1.0.0.0 Initial Build
#>

# Input bindings are passed in via param block.
# For the Function App
param($Timer)

######## Variables ##########
## Update "HostPool" value with your host pool, and "HostPoolRG" with the value of the host pool resource group.
## See the next step if working with multiple host pools.
$allHostPools = @()
$allHostPools += (@{
        HostPool   = "<HostPoolName>";
        HostPoolRG = "<HostPoolResourceGroup>"
    })

# If using multiple host pools, Copy the block the code below and pasted it above this line.  Update with the host pool name and resource group.
# Repeat for each additional host pool.
<#
$allHostPools += (@{
        HostPool   = "<HostPoolName>";
        HostPoolRG = "<HostPoolResourceGroup>"
    })
#>

########## Script Execution ##########
$count = 0
while ($count -lt $allHostPools.Count) {
    $pool = $allHostPools[$count].HostPool
    $poolRg = $allHostPools[$count].HostPoolRG
    Write-Output "This is the key (pool) $pool"
    write-output "this is the value (rg) $poolRg"
    # Get the active Session hosts
    $activeShs = (Get-AzWvdUserSession -HostPoolName $pool -ResourceGroupName $poolRg).name
    $allActive = @()
    foreach ($activeSh in $activeShs) {
        $activeSh = ($activeSh -split { $_ -eq '.' -or $_ -eq '/' })[1]
        if ($activeSh -notin $allActive) {
            $allActive += $activeSh
        }
    }
    # Get the Session Hosts
    # Exclude servers in drain mode and do not allow new connections
    $runningSessionHosts = (Get-AzWvdSessionHost -HostPoolName $Pool -ResourceGroupName $PoolRg | Where-Object { $_.AllowNewSession -eq $true } )
    $availableSessionHosts = ($runningSessionHosts | Where-Object { $_.Status -eq "Available" })
    #Evaluate the list of running session hosts against 
    foreach ($sessionHost in $availableSessionHosts) {
        $sessionHostName = (($sessionHost).name -split { $_ -eq '.' -or $_ -eq '/' })[1]
        if ($sessionHostName -notin $allActive) {
            Write-Host "Server $sessionHostName is not active, shut down"
            try {
                # Stop the VM
                Write-Output "Stopping Session Host $sessionHostName"
                Get-azvm -ErrorAction Stop -Name $sessionHostName | Stop-AzVM -ErrorAction Stop -Force -NoWait
            }
            catch {
                $ErrorMessage = $_.Exception.message
                Write-Error ("Error stopping the VM: " + $ErrorMessage)
                Break
            }
        }
        else {
            write-host "Server $sessionHostName has an active session, won't shut down"
        }
    }
    $count += 1
}

