
<#
.SYNOPSIS
    This script automates the process of creating an image of an Azure VM without destroying the source, or reference VM.
.DESCRIPTION
    This script automates the process of creating an image from an Azure VM without destroying the source during the capture process.  
    At a high-level, the following steps are taken:
    1. Snapshot of source "reference" VM > create a temp "capture" Resource Group.
    2. Create an OS disk from snapshot.
    3. Create a VNet and VM in the capture RG.
    4. Run Sysprep.exe the VM with a Custom Script Extension.
    5. Capture the VM. If using Azure Compute Gallery, add image to the gallery. 
    If not using Azure Compute Gallery, add image to reference VM Resource Group (this option is not supported for Trusted Launch VMs).
    6. Remove capture Resource Group > remove snapshot.

    Managed Images are considered legacy and are not recommended for use.  
    Managed Images are not supported with Trusted Launch VMs. Use Azure Compute Gallery instead.
    
    Confidential VMs are not supported for Sysprep.exe.  See the link below for more information.
    https://learn.microsoft.com/en-us/azure/confidential-computing/create-confidential-vm-from-compute-gallery?WT.mc_id=AZ-MVP-5004159#confidential-vm-images
    
    The following tables show the supported source VM security types and destination image definition security types:

    Source: Standard VM
    Destination Image Definition Security Type:
    Managed Image - Supported
    Standard - Supported
    TrustedLaunchSupported - Supported
    TrustedLaunch - Supported

    Source: TrustedLaunch VM
    Destination Image Definition Security Type:
    Managed Image - Not Supported
    Standard - Not Supported
    TrustedLaunchSupported - Not Supported
    TrustedLaunch - Supported

    This script requires the PowerShell AZ module.
    Log into the target Azure subscription before running the script.
    
.PARAMETER refVmName
    The name of the reference, or source VM used to build the image.

.PARAMETER refVmRg
    The name of the reference VM resource Group, also used for the location

.PARAMETER cseURI
    Optional, the URI for the Sysprep Custom Script Extension.  Default value is located on a public GitHub repo.  
    No guaranty on availability.  Recommend copying the file to your own location.  The file must be 
    publicly available.  Looking for something with more PowerShell Options?  Check out Image Builder.
    https://youtube.com/playlist?list=PLnWpsLZNgHzWeiHA_wG0xuaZMlk1Nag7E

.PARAMETER galName
    Optional, the name of the Azure Compute Gallery.  If not used, the image will be placed in the reference VM resource group.
    This option is required for trusted launch images.  The image definition must be created before running the script.

.PARAMETER galRg
    Required if -galDeploy is used.  The name of the Azure Compute Gallery Resource Group.
    
.PARAMETER galDefName
    Required if -galName is used. The Image Definition name in the Azure Compute Gallery
    Be sure the hardware version (Gen1 or Gen2) and Gallery Image Definition match.
.PARAMETER delSnap
    Optional, indicates if the source snapshot of the reference computer will be 
    deleted as part of the cleanup process. 


.NOTES
    ## Script is offered as-is with no warranty, expressed or implied.  ##
    ## Test it before you trust it!                                     ##
    ## Please see the list below before running the script:             ##
    1. This script assumes the VM's, resource groups and Azure Compute Gallery, if used, are in the same region.
    2. If the script fails, you will need to manually clean up artifacts created (remove snapshot and capture Resource Group).
    3. Update the reference VM or disable updates.  Sysprep won't run with updates pending.
    4. The script will create a new, temporary "Capture" resource group and delete it once finished.
    5. The public IP and NSG is not required and can be commented out (update the NIC config also). It's helpful for troubleshooting.
    Version 1.1.0.0:
    6. Ran into black screen and BitLocker issues with Win11 24H2 Enterprise multi-session. Issue is with 24H2, tested with 23H2. 
       https://answers.microsoft.com/en-us/windows/forum/all/trouble-with-sysprep-on-w11-24h2-sysprep-fails/721c6fed-467a-4c47-b992-5effabb0b4cc
    7. Major updates to the script to add trusted launch support, better error handling, better output and error messages.

    Author      : Travis Roberts, Ciraltos llc
    Website     : www.ciraltos.com
    Version     : 1.1.0.0 Update 5/20/2025
                  1.0.0.0 Initial Build 3/12/2022

.EXAMPLE
    Create an image and add it to the source computers resource group:
    .\SnapImage.ps1 -refVmName "<ComputerName>" -refVmRg '<RGName>'   

    Create an image and add it to an Azure Compute Gallery:
    .\SnapImage.ps1 -refVmName "CITTest" -refVmRg 'AAWPNCITImageTestRG' -galName 'CITGallery1' -galRg 'CITGalleryRG' -galDefName 'SnapImage'
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$refVmName,
    [Parameter(Mandatory = $true)][string]$refVmRg,
    [Parameter(Mandatory = $false)][string]$cseURI = 'https://raw.githubusercontent.com/tsrob50/WVD-Public/master/SysprepCSE.ps1',
    [Parameter(Mandatory = $false)][string]$galName,
    [Parameter(Mandatory = $false)][string]$galRg,
    [parameter(Mandatory = $false)][string]$galDefName,
    [parameter(Mandatory = $false)][string]$delSnap = $true
)

#Set the date, used as unique ID for artifacts and image version
$date = (get-date -Format yyyyMMddHHmm)

#Set the image name, modify as needed
#Default based off reference computer name and date
$imageName = ($refVmName + 'Image' + $date)

#Set the image version (Name)
#Used when adding the image to an Azure Compute Gallery
#Format is 0.yyyyMM.ddHHmm date format for the version to keep unique and increment each new image version
$imageVersion = '0.' + $date.Substring(0, 6) + '.' + $date.Substring(6, 6)

#Disable breaking change warning message
Set-Item -Path Env:\SuppressAzurePowerShellBreakingChangeWarnings -Value $true

#Set the location, based on the reference computer resource group location
$location = (Get-AzResourceGroup -Name $refVmRg).Location

##### Start Script #####

#region Validate the Azure Compute Gallery settings are correct, if used
try {
    if ($galName -and $galDefName) {
        $gallery = Get-AzGallery -ErrorAction Stop -Name $galName -ResourceGroupName $galRg
        $galleryDef = Get-AzGalleryImageDefinition -ErrorAction Stop -ResourceGroupName $galRg -GalleryName $galName -GalleryImageDefinitionName $galDefName
    }
}
catch {
    Write-Error ('Error with Azure Compute Gallery Settings ' + $_.Exception.message)
    Break
}
#endregion

#region Verify the reference VM is shut down
try {
    $refVmStatus = (Get-AzVM -ErrorAction Stop -ResourceGroupName $refVmRg -Name $refVmName -status).Statuses[1].DisplayStatus
    if ($refVmStatus -notlike "VM deallocated") {
        Write-Host "The reference VM $refVmName is not stopped, shut down and deallocated before running the script"
        Break
    }
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error checking reference VM status ' + $ErrorMessage)
    Break
}
#endregion

#region Verify the reference computer and image location parameters are valid
try {
    #Verify if the gallery image definition is Trusted Launch, the reference VM must be Trusted Launch
    $refVm = Get-AzVM -ErrorAction Stop -ResourceGroupName $refVmRg -Name $refVmName
    if (($galName) -and ($refVm.SecurityProfile.SecurityType -eq "TrustedLaunch") -and ($galleryDef.Features[0].Value -ne "TrustedLaunch")  ) {
        Write-Error "The reference Image Definition must be TrustedLaunch when useing a TrustedLaunch reference VM, please verify the security type"
        Break
    }
    #Verify a trusted launch VM is not using a managed image
    elseif (!($galName) -and ($refVm.SecurityProfile.SecurityType -eq "TrustedLaunch") ) {
        Write-Error "Trusted Launch is not supported for managed images, please use an Azure Compute Gallery with a Trusted Launch VM"
        Break
    }
    #Verify the reference VM is not a Confidential VM
    elseif ($refVm.SecurityProfile.SecurityType -eq "ConfidentialVM") {
        Write-Host "Confidential VM detected, sysprep is not supported"
        Break
    }
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error checking reference VM security type ' + $ErrorMessage)
    Break
}
#endregion

#region Create Snapshot of reference VM
try {
    Write-Host "Creating a snapshot of $refVmName"
    $vm = Get-AzVM -ErrorAction Stop -ResourceGroupName $refVmRg -Name $refVmName
    $snapshotConfig = New-AzSnapshotConfig -ErrorAction Stop -SourceUri $vm.StorageProfile.OsDisk.ManagedDisk.Id -Location $vm.Location -CreateOption copy -SkuName Standard_LRS
    $snapshot = New-AzSnapshot -ErrorAction Stop -Snapshot $snapshotConfig -SnapshotName "$refVmName$date" -ResourceGroupName $refVmRg
}
catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error creating snapshot from reference computer ' + $ErrorMessage)
    Break
}
#endregion

#region Create a resource group for the reference VM
Try {
    Write-Host "Creating the capture Resource Group"
    $capVmRg = New-AzResourceGroup -Name ($refVmName + $date + "_ImageRG") -Location $location
    Write-Host "Capture Resource Group $($capVmRg.ResourceGroupName) created"
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error creating the resource group ' + $ErrorMessage)
    Break
}
#endregion

#region Create a VM from the snapshot
#Create the managed disk from the Snapshot
Try {
    $osDiskConfig = @{
        ErrorAction      = 'Stop'
        Location         = $location
        CreateOption     = 'copy'
        SourceResourceID = $snapshot.Id
    }
    write-host "creating the OS disk form the snapshot"
    $osDisk = New-AzDisk -ErrorAction Stop -DiskName 'TempOSDisk' -ResourceGroupName $capVmRg.ResourceGroupName -disk (New-AzDiskConfig @osDiskConfig)
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error creating the managed disk ' + $ErrorMessage)
    Break
}
#Create a new VNet 
Try {
    Write-Host "Creating the VNet and Subnet"
    $singleSubnet = New-AzVirtualNetworkSubnetConfig -ErrorAction Stop -Name ('tempSubnet' + $date) -AddressPrefix '10.0.0.0/24' 
    $vnetConfig = @{
        ErrorAction       = 'Stop'
        Name              = ('tempSubnet' + $date) 
        ResourceGroupName = $capVmRg.ResourceGroupName
        Location          = $location
        AddressPrefix     = "10.0.0.0/16"
        Subnet            = $singleSubnet
    }
    $vnet = New-AzVirtualNetwork @vnetConfig 
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error creating the temp VNet ' + $ErrorMessage)
    Break
}
#Create the NSG
Try {
    $nsgRuleConfig = @{
        Name                     = 'myRdpRule'
        ErrorAction              = 'Stop'
        Description              = 'Allow RDP'
        Access                   = 'allow'  
        Protocol                 = 'Tcp'
        Direction                = 'Inbound'
        Priority                 = '110'
        SourceAddressPrefix      = 'Internet'
        SourcePortRange          = '*'
        DestinationAddressPrefix = '*'
        DestinationPortRange     = '3389'
    }
    write-host "Creating the NSG"
    $rdpRule = New-AzNetworkSecurityRuleConfig @nsgRuleConfig
    $nsg = New-AzNetworkSecurityGroup -ErrorAction Stop -ResourceGroupName $capVmRg.ResourceGroupName -Location $location -Name 'tempNSG' -SecurityRules $rdpRule
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error creating the NSG ' + $ErrorMessage)
    Break
}
#Create the public IP address
Try {
    Write-Host "Creating the public IP address"
    $pip = New-AzPublicIpAddress -ErrorAction Stop -Name 'tempPip' -ResourceGroupName $capVmRg.ResourceGroupName -Location $location -AllocationMethod Static
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error creating the public IP address ' + $ErrorMessage)
    Break
}
#Create the NIC
Try {
    $nicConfig = @{
        ErrorAction            = 'Stop'
        Name                   = 'tempNic'
        ResourceGroupName      = $capVmRg.ResourceGroupName
        Location               = $location
        SubnetId               = $vnet.Subnets[0].Id
        PublicIpAddressId      = $pip.Id
        NetworkSecurityGroupId = $nsg.Id
    }
    Write-Host "Creating the NIC"
    $nic = New-AzNetworkInterface @nicConfig
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error creating the NIC ' + $ErrorMessage)
    Break
}
#Create and start the VM
Try {
    Write-Host "Creating the temporary capture VM, this will take a couple minutes"
    $capVmName = ('tempVM' + $date) 
    $CapVmConfig = New-AzVMConfig -ErrorAction Stop -VMName $CapVmName -VMSize $vm.HardwareProfile.VmSize
    $capVm = Add-AzVMNetworkInterface -ErrorAction Stop -vm $CapVmConfig -id $nic.Id
    $capVm = Set-AzVMOSDisk -vm $CapVm -ManagedDiskId $osDisk.id -StorageAccountType Standard_LRS -DiskSizeInGB 128 -CreateOption Attach -Windows
    $capVM = Set-AzVMBootDiagnostic -vm $CapVm -disable
    $capVm = new-azVM -ResourceGroupName $capVmRg.ResourceGroupName -Location $location -vm $capVm -DisableBginfoExtension
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error creating the VM ' + $ErrorMessage)
    Break
}
#endregion

#region Sysprep the new capture VM (capVm)
#Wait for VM to be ready, display status = VM running
$displayStatus = ""
$count = 0
while ($displayStatus -notlike "VM running") { 
    Write-Host "Waiting for the VM display status to change to VM running"
    $displayStatus = (get-azvm -Name $capVmName -ResourceGroupName $capVmRg.ResourceGroupName -Status).Statuses[1].DisplayStatus
    write-output "starting 30 second sleep"
    start-sleep -Seconds 30
    $count += 1
    if ($count -gt 7) { 
        Write-Error "five minute wait for VM to start ended, canceling script"
        Exit
    }
}
#Run Sysprep from a Custom Script Extension 
try {
    $cseSettings = @{
        ErrorAction       = 'Stop'
        FileUri           = $cseURI 
        ResourceGroupName = $capVmRg.ResourceGroupName
        VMName            = $CapVmName 
        Name              = "Sysprep" 
        location          = $location 
        Run               = './SysprepCSE.ps1'
    }
    Write-Host "Running the Sysprep custom script extension"
    Set-AzVMCustomScriptExtension @cseSettings | Out-Null
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error running the Sysprep Custom Script Extension ' + $ErrorMessage)
    Break
}
<# For testing
$status = Get-AzVMDiagnosticsExtension -ResourceGroupName $capVmRg.ResourceGroupName -VMName $capVmName -name "Sysprep" -status
$status.SubStatuses.message
#>
#endregion

#region Capture VM image
#Wait for Sysprep to finish and deallocate the VM
$displayStatus = ""
$count = 0
Try {
    while ($displayStatus -notlike "VM stopped") {
        Write-Host "Waiting for the VM display status to change to VM stopped"
        $displayStatus = (get-azvm -ErrorAction Stop -Name $capVmName -ResourceGroupName $capVmRg.ResourceGroupName -Status).Statuses[1].DisplayStatus
        write-output "starting 15 second sleep"
        start-sleep -Seconds 15
        $count += 1
        if ($count -gt 11) {
            Write-Error "Three minute wait for VM to stop ended, canceling script.  Verify no updates are required on the source"
            Write-Error "Possible an issue with sysprep, log into the temporary capture VM $capVmName and run the command:"
            Write-Error "c:\Windows\system32\sysprep\sysprep.exe /generalize, /oobe, /mode:vm, /shutdown"
            Write-Error "If the command fails, check the logs in c:\Windows\System32\Sysprep\Panther\setupact.log"
            Write-Error "Verify bitlocker is disabled and no pending updates are required"
            Exit 
        }
    }
    Write-Host "Deallocating the VM and setting to Generalized"
    Stop-AzVM -ErrorAction Stop -ResourceGroupName $capVmRg.ResourceGroupName -Name $capVmName -Force | Out-Null
    Set-AzVM -ErrorAction Stop -ResourceGroupName $capVmRg.ResourceGroupName -Name $capVmName -Generalized | Out-Null
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error deallocating the VM ' + $ErrorMessage)
    Break
}
#Create the image from the captureVM
Try {
    #Create the image in the Azure Compute Gallery if using the gallery
    Write-Host "Capturing the VM image"
    $capVM = Get-AzVM -ErrorAction Stop -Name $capVmName -ResourceGroupName $capVmRg.ResourceGroupName
    if ($galName -and $galDefName) {
        Write-Host 'Adding image to the Azure Compute Gallery, this can take a few minutes'
        $imageSettings = @{
            ErrorAction                = 'Stop'
            ResourceGroupName          = $gallery.ResourceGroupName
            GalleryName                = $gallery.Name
            GalleryImageDefinitionName = $galleryDef.Name
            GalleryImageVersionName    = $imageVersion
            Location                   = $gallery.Location
            SourceImageVMId            = $capVm.Id.ToString()
        }
        $GalImageVer = New-AzGalleryImageVersion @imageSettings
        Write-Host "Image version $($GalImageVer.Name) added to the image definition"
    }
    elseif (!($galName)) {
        #Create the image in the reference VM Resource Group if not using the gallery
        Write-Host "Azure Compute Gallery not used, saving image to the reference VM Resource Group"
        $vmGen = (Get-AzVM -ErrorAction Stop -Name $capVmName -ResourceGroupName $capVmRg.ResourceGroupName -Status).HyperVGeneration
        $image = New-AzImageConfig -ErrorAction Stop -Location $location -SourceVirtualMachineId $capVm.Id -HyperVGeneration $vmGen
        New-AzImage -ErrorAction Stop -Image $image -ImageName $imageName -ResourceGroupName $refVmRg | Out-Null
    }
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error creating the image ' + $ErrorMessage)
    Break
}
#endregion

#region Remove the capture computer RG
Try {
    Write-Host "Removing the capture Resource Group $($capVmRg.ResourceGroupName)"
    Remove-AzResourceGroup -ErrorAction Stop -Name $capVmRg.ResourceGroupName -Force | Out-Null
}
Catch {
    $ErrorMessage = $_.Exception.message
    Write-Error ('Error removing resource group ' + $ErrorMessage)
    Break
}
#Remove the snapshot (Optional)
#Removes reference computer snapshot if $delSnap is set to $true
if ($delSnap -eq $true) {
    Try {
        Write-Host "Removing the snapshot $($snapshot.Name)"
        Remove-AzSnapshot -ErrorAction Stop -ResourceGroupName $refVmRg -SnapshotName $snapshot.Name -Force | Out-Null
    }
    Catch {
        $ErrorMessage = $_.Exception.message
        Write-Error ('Error removing the snapshot ' + $ErrorMessage)
        Break
    }
}
#endregion
