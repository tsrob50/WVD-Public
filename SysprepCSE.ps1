<#
.SYNOPSIS
    Used as a custom script extension for running Sysprep.ext on Windows VM's in Azure
.DESCRIPTION
    This Custom Script Extension is used to run Sysprep on a VM to prepare it for imaging.
    /mode:vm is used to speed up first boot on VM's by skipping hardware detection.
    Remove "/mode:vm" if the image will be deployed to different VM types then the source VM.
    More info here: https://www.ciraltos.com/please-wait-for-the-windows-modules-installer/

.NOTES
    ## Script is offered as-is with no warranty, expressed or implied.  ##
    ## Test it before you trust it!                                     ##
    Author      : Travis Roberts, Ciraltos llc
    Website     : www.ciraltos.com
    Version     : 1.0.0.0 Initial Build 3/12/2022

.LINK

#>


#Script to run Sysprep on a VM
#Logging is handy when you need it!
if ((test-path c:\logfiles) -eq $false) {
    new-item -ItemType Directory -path 'c:\' -name 'logfiles' | Out-Null
} 
$logFile = "c:\logfiles\" + (get-date -format 'yyyyMMdd') + '_softwareinstall.log'

# Logging function
function Write-Log {
    Param($message)
    Write-Output "$(get-date -format 'yyyyMMdd HH:mm:ss') $message" | Out-File -Encoding utf8 $logFile -Append
}
#Run Sysprep
try{
    write-output "Sysprep Starting"
    Start-Process -filepath 'c:\Windows\system32\sysprep\sysprep.exe' -ErrorAction Stop -ArgumentList '/generalize', '/oobe', '/mode:vm', '/shutdown'
}
catch {
    $ErrorMessage = $_.Exception.message
    write-log "Error running Sysprep: $ErrorMessage"
}
