<#
.SYNOPSIS
    Copies files from a network share to a local directory on startup
.DESCRIPTION
    This script is used to copy FSLogix Application Masking rules from a network location to the FSLogix Rule location on the local computer.  the script is intended to be used with
    a GPO that runs the script at startup.  
    The script includes error handling that will write errors to the local Application Event Log.  Modify the Write Event Log variables as needed.
    For more details on writing to the event log see:
    www.ciraltos.com/writing-event-log-powershell/
.NOTES
    Script is offered as-is with no warranty, expressed or implied.
    Test it before you trust it
    Author      : Travis Roberts
    Website     : www.ciraltos.com
    Version     : 1.0.0.0 Initial Build
#>

######## Variables ##########
# Set the source path
$sourcePath = '\\wvd-fileserver\AppMask'
# Destination path for App Masking
$destinationPath = 'C:\Program Files\FSLogix\Apps\Rules'

######## Write Event Log ##########
# Set Variables
$eventLog = 'Application'
$eventSource = 'AppMaskingCopy'
$eventID = 4000
$entryType = 'Error'

# Check if the source exists and create if needed
If ([System.Diagnostics.EventLog]::SourceExists($eventSource) -eq $False) {
    New-EventLog -LogName Application -Source $eventSource
}

# Write EventLog Function
function write-AppEventLog {
    Param($errorMessage)
    Write-EventLog -LogName $eventLog -EventID $eventID -EntryType $entryType -Source $eventSource -Message $errorMessage 
}

# Check the source path
if ((Test-Path $SourcePath) -eq $False) {
    write-AppEventLog 'Source path not found or not accessible'
}

# Check the destination path
if ((Test-Path $destinationPath) -eq $False) {
    write-AppEventLog 'Destination path not found or not accessible'
}

# Copy the files to the destination
try {
    Copy-Item -ErrorAction Stop -Path "$sourcePath\*.fxa" -Destination $destinationPath -Force
    Copy-Item -ErrorAction Stop -Path "$sourcePath\*.fxr" -Destination $destinationPath -Force
    # used for testing:
    #Copy-Item -ErrorAction Stop -Path "$sourcePath\*.txt" -Destination $destinationPath -Force
}
catch {
    $ErrorMessage = $_.Exception.message
    write-AppEventLog $ErrorMessage
}
