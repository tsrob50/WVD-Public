<#
.DESCRIPTION
Used to remove a Host Pool from WVD.  
This script will not remove the Session Host VM's from Azure.
Script check that the user is logged in, runs the log in command if not.
This script is offered as is with no warranty.
Test it before you trust it.

.NOTES
Author      : Travis Roberts
Website     : www.ciraltos.com
Version     : 1.0.0.0 Initial Build
#>


# Test if user is logged in to WVD, log them in if not
if ((Get-RdsContext -ErrorAction SilentlyContinue) -eq $null) {
    Write-Output "Use the login window to connect to WVD" -ForegroundColor Red
    Add-RdsAccount -DeploymentUrl "https://rdbroker.wvd.microsoft.com"
}

# Get the tenant name
try {
    $tenantName = (Get-RdsTenant -ErrorAction stop).TenantName
}
catch {
    $ErrorMessage = $_.Exception.message
    write-error ('Error getting the Tenant name ' + $ErrorMessage)
    Exit
}
$message = 'Confirm Tenant Name'
$question = "Please confirm the Tenant name is $tenantName to continue"
$choices = '&Yes', '&No'
$decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
if ($decision -eq 0) {
    Write-Host "Tenant Name $tenantName confirmed"
}
else {
    Write-Host 'Verify that you logged into the correct tenant and try again.'
    exit
}


# Build a list of HostPools
try {
    $hostPools = @(Get-RdsHostPool -ErrorAction stop -TenantName $tenantName)
}
catch {
    $ErrorMessage = $_.Exception.message
    write-error ('Error getting the list of host pools ' + $ErrorMessage)
    Exit
}
if ($hostPools -ne $null) {
    $message = 'Select the Host Pool'
    $question = "Please type the name of the Host Pool to remove"
    $choices = @()
    For ($index = 0; $index -lt $hostPools.Count; $index++) {
        $choices += New-Object System.Management.Automation.Host.ChoiceDescription ($hostPools[$index]).HostPoolName
    }

    $options = [System.Management.Automation.Host.ChoiceDescription[]]$choices
    $result = $host.ui.PromptForChoice($message, $question, $options, 0) 
    $hostPoolName = ($hostPools[$result]).HostPoolName
}
else { 
    write-host 'No Host Pools found, exiting script.'
    exit
}

# Confirm the Host Pool Name

write-host "##### You are about to permanently delete the Host Pool $hostPoolName from the WVD Tenant $tenantName #####" -ForegroundColor red
$message = 'Confirm Host Removal'
$question = "Please confirm that you want to permanently delete Host Pool $hostPoolName from the Tenant $TenantName" 
$choices = '&Yes', '&No'
$decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
if ($decision -eq 0) {
    Write-Host "One more chance to change your mind" -ForegroundColor red -BackgroundColor white
    $message = 'Confirm Host Removal'
    $question = "Please confirm that you want to permanently delete Host Pool $hostPoolName from the Tenant $TenantName" 
    $choices = '&Yes', '&No'
    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 1)
    if ($decision -eq 0) {
        # Remove App Group Users
        $appGroups = Get-RdsAppGroup -TenantName $tenantName -HostPoolName $hostPoolName
        foreach ($appGroup in $appGroups) {
            $appGroupName = $appGroup.AppGroupName
            write-host "Removing Users from App Group $appGroupName"
            try {
                Get-RdsAppGroupUser -ErrorAction Stop -TenantName $tenantName -HostPoolName $hostPoolName -AppGroupName $appGroupName | Remove-RdsAppGroupUser
            }
            catch {
                $ErrorMessage = $_.Exception.message
                write-error ('Error removing App Group User ' + $ErrorMessage)
            }
            # Code to remove remote apps
            try {
                if ($appGroup.ResourceType -eq "RemoteApp") {
                    write-host "Removing published apps from $appGroupName"
                    get-RdsRemoteApp -TenantName $tenantName -HostPoolName $hostpoolname -AppGroupName $appGroupName | Remove-RdsRemoteApp
                }
            }
            catch {
                $ErrorMessage = $_.Exception.message
                write-error ("Error removing Remote App $appGroupName " + $ErrorMessage)
            }
            #####
            write-host "Removing $appGroupName"
            try {
                Remove-RdsAppGroup -ErrorAction Stop -TenantName $tenantName -HostPoolName $hostPoolName -Name $appGroupName
            }
            catch {
                $ErrorMessage = $_.Exception.message
                write-error ("Error removing app group $appGroupName " + $ErrorMessage)
            }
        }
        Write-Host "Removing Session Hosts from Host Pool $hostPoolName"
        try {
            Get-RdsSessionHost -ErrorAction Stop -TenantName $tenantName -HostPoolName $hostPoolName | Remove-RdsSessionHost
        }
        catch {
            $ErrorMessage = $_.Exception.message
            write-error ('Error removing Session Hosts ' + $ErrorMessage)
            Break
        }
        Write-Host "Removing Host Pool $hostPoolName"
        try {
            Remove-RdsHostPool -ErrorAction Stop -TenantName $tenantName -HostPoolName $hostPoolName
        }
        catch {
            $ErrorMessage = $_.Exception.message
            write-error ('Error removing host pool ' + $ErrorMessage)
            Break
        }
    }
    else {
        Write-Host 'Removal canceled'
        exit
    }
}
else {
    Write-Host 'Removal canceled'
    exit
}
