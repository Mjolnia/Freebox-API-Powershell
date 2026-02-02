. ".\apis\freebox-api.ps1"
$result = FreeboxAPI-Reboot
if($result.success) {
	Write-Output "Internet is restarting, please wait ..."
}