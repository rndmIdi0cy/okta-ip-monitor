<#
.SYNOPSIS
    Function to pull Okta IP ranges and parse for particular cell to monitor
    for address changes. The file will be compared via hash and if there is a change
    an email notification will be sent to the designated recipients.
.EXAMPLE
    .\okta-ipmonitor.ps1 -OutputFolderPath 'C:\ProgramData' -Recipients user1@abcd.com,user2@abcd.com
.PARAMETER OutputFilePath
    The file path where the okta ip range will be saved to
.PARAMETER Recipients
    A comma seperated list of email addresses to send a notification to
.PARAMETER MailServer
    The SMTP mail server to use if not our default
.NOTES
    Place in a scheduled task where the action should be set to start powershell.exe with the argument
    -file "[PATH]\[TO]\okta-ipmonitor.ps1" followed by the other args

    =====>                                              <=====
    =====> This is hardcoded to us_cell_7 at the moment <=====
    =====>                                              <=====
#>

[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true, HelpMessage = 'The folder path for the Okta IP list and temp file')]
    [string] $OutputFolderPath,
    [Parameter(Mandatory = $true, HelpMessage = 'Comma seperated list of email addresses')]
    [string[]] $Recipients,
    [Parameter(Mandatory = $false, HelpMessage = 'Mail server if not using the default')]
    [string] $MailServer = "mail.abcd.com"
)



function Get-StringHash($string) {
    # Borrowed from: https://gallery.technet.microsoft.com/scriptcenter/Get-StringHash-aa843f71
    $hash = ""
    $hasher = New-Object System.Security.Cryptography.SHA256Managed
    $stringToHash = [System.Text.Encoding]::UTF8.GetBytes($string)
    $byteArray = $hasher.ComputeHash($stringToHash)

    foreach ($byte in $byteArray) {
        $hash += $byte.ToString("x2")
    }

    return $hash
}

function Get-OktaRanges($OutputFolderPath) {
    $ranges = Invoke-RestMethod -Method GET -Uri "https://s3.amazonaws.com/okta-ip-ranges/ip_ranges.json"
    $rangesHash = Get-StringHash $ranges.us_cell_7.ip_ranges
    $ranges.us_cell_7.ip_ranges | Set-Content -Path "${OutputFolderPath}\okta_cell7.tmp"

    return $rangesHash
}

function Get-OktaCachedRanges($OutputFolderPath) {
    $currentRanges = Get-Content -Path "${OutputFolderPath}\okta_cell7.txt"
    $currentHash = Get-StringHash $currentRanges

    return $currentHash
}

function SendMail($MailServer, [string[]]$Recipients, $oktaFile) {
    $message = New-Object Net.Mail.MailMessage
    $message.From = "Okta IP Monitor <do_not_reply@abcd.com>"
    $message.Subject = "[ ALERT ] Okta IP Addresses Changes"
    $message.Body = "There was a change in the IP Addresses for our Okta instance. Please find the attached document which contains the refreshed IP list."
    $message.Priority = 2

    foreach ($email in $Recipients) {
        $message.To.Add($email)
    }

    $attachment = New-Object Net.Mail.Attachment($oktaFile)
    $message.Attachments.Add($attachment)

    $smtp = New-Object Net.Mail.SmtpClient($MailServer)
    $smtp.Send($message)
}

$liveHash = Get-OktaRanges $OutputFolderPath
$localHash = Get-OktaCachedRanges $OutputFolderPath

if ($liveHash -ne $localHash) {
    Remove-Item -Path "{$OutputFolderPath}\okta_cell7.txt" -Force
    Rename-Item -Path "{$OutputFolderPath}\okta_cell7.tmp" -NewName "okta_cell7.txt" -Force
    SendMail $MailServer $Recipients "{$OutputFolderPath}\okta_cell7.txt"
}
else {
    Remove-Item -Path "{$OutputFolderPath}\okta_cell7.tmp" -Force
}
