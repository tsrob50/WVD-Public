<#
.SYNOPSIS
    Adds a Log Analytics workspace to a WVD object Diagnostic Settings.
.DESCRIPTION
    This script adds Log Analytics to WVD objects Diagnostic settings.  It identifies the Host Pool, Application Groups assigned to
    the host pool and the WVD Workspace resource ID and uses Set-AzDiagnosticSetting to configure diagnostic data to a Log Analytics workspace.
    A Log Analytics workspace must be available prior to running this script.
    The PowerShell session must be logged into Azure prior to running this script.
    Full details can be found at:
    http://www.ciraltos.com
    https://docs.microsoft.com/en-us/azure/virtual-desktop/diagnostics-log-analytics
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Test it before you trust it!
    Author      : Travis Roberts, Ciraltos llc
    Website     : www.ciraltos.com
    Version     : 1.0.0.0 Initial Build
#>


######## Variables ##########

# Set the post pool name and resource group
$hostpoolName = 'Host Pool Name'
$rgName = 'Resource Group Name'

# WVD workspace resource group if different from Host Pool RG
# leave Null or blank if the same as the host pool
$wvdWorkspaceRg = ''

# Log Analytics Values
# Set the Lon Analytics Resource Group and Workspace Name
$laWorkspaceRg = 'Log Analytics Resource Group'
$laWorkspaceName = 'Log Analytics Workspace name'


#Functions
function Add-LaDiag {
    param(
        [string]$laWorkspaceID,
        [array]$resourceList
    )
    foreach ($resource in $resourceList) {
        $name = ($resource.Split('/'))[-1] + "-Diagnostics"
        try {

            Set-AzDiagnosticSetting -ErrorAction Stop -Name $name -ResourceId $resource -Enabled $true -WorkspaceId $laWorkspaceID
        }
        catch{
            $ErrorMessage = $_.Exception.message
            Write-Error ("Adding diag settings for $name had the following error: " + $ErrorMessage)
        }
    }
}


# Get the Log Analytics Workspace Resource ID
$laWorkspaceID = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $laWorkspaceRg -Name $laWorkspaceName).resourceId

# Build the list of resource ID's
$resourceIds = @()

# Get the host pool resource ID
$hostpool = Get-AzWvdHostPool -name $hostpoolName -ResourceGroupName $rgName
$resourceIds += $hostpool.Id

# Add the App Groups Resource ID
foreach ($appGroupId in $hostpool.ApplicationGroupReference) {
    $resourceIds += $appGroupId
}

# Get the WVD Workspace Resource ID
if (($wvdWorkspaceRg -eq '') -or ($wvdWorkspaceRg -eq $nul)) {
    $wvdWorkspaceRg = $rgName
}
$wvdWorkspaceId = (Get-AzWvdWorkspace -ResourceGroupName $wvdWorkspaceRg).Id
$resourceIds += $wvdWorkspaceId

# Execute the function

Add-LADiag -laWorkspaceID $laWorkspaceID -resourceList $resourceIds
