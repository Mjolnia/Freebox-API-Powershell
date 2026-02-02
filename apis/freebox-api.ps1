$DOMAIN_NAME = "mafreebox.freebox.fr"
$BOX_INFO = Invoke-RestMethod -Method "GET" -Uri ($DOMAIN_NAME + "/api_version")
$BASE_URL = $BOX_INFO.api_base_url + "v" + $BOX_INFO.api_version.split(".")[0] + "/"


$SCRIPT_PATH = (Get-Item $PSCommandPath).DirectoryName
$TOKEN_API_PATH = "$($SCRIPT_PATH)\..\token"
$TRACKID_API_PATH = "$($SCRIPT_PATH)\..\track_id"
$SESSION_API_PATH = "$($SCRIPT_PATH)\..\session"

$sessionExists = (Test-Path $SESSION_API_PATH -PathType leaf)
if(-NOT($sessionExists)) {
	New-Item -ItemType File -Path $SESSION_API_PATH -Value "" -Force | Out-Null
}
$SESSION_TOKEN = (Get-Content $SESSION_API_PATH -Raw)

$APP_ID = "freebox-local-api"
$APP_NAME = "Freebox Local API"
$APP_VERSION = "1.0"

function FreeboxAPI-SendRequest {
	param(
		[Parameter(Mandatory=$true)][string]$wsMethod,
		[Parameter(Mandatory=$true)][string]$wsUrl,
		[string]$wsBody,
		[string]$sessionToken
	)

	$WS_FULL_URL = $DOMAIN_NAME + $BASE_URL + $wsUrl
	Write-Output "$WS_FULL_URL"
	if($sessionToken -eq "") {
		if($wsBody -eq "") {
			$wsResult = Invoke-RestMethod -Method $wsMethod -Uri $WS_FULL_URL
		} else {
			$wsResult = Invoke-RestMethod -Method $wsMethod -Uri $WS_FULL_URL -Body $wsBody
		}
	} else {
		$headers = @{
			"X-Fbx-App-Auth" = $sessionToken
		}
		if($wsBody -eq "") {
			$wsResult = Invoke-RestMethod -Headers $headers -Method $wsMethod -Uri $WS_FULL_URL
		} else {
			$wsResult = Invoke-RestMethod -Headers $headers -Method $wsMethod -Uri $WS_FULL_URL -Body $wsBody
		}
	}

	return $wsResult
}

function FreeboxAPI-CurrentSession {
	$response = FreeboxAPI-SendRequest -wsMethod "GET" -wsUrl "login/" -sessionToken $SESSION_TOKEN
	return $response
}

function FreeboxAPI-Authorize {
	param(
		[Parameter(Mandatory=$true)][string]$deviceName
	)
	$data = @{
		"app_id" = $APP_ID
		"app_name" = $APP_NAME
		"app_version" = $APP_VERSION
		"device_name" = $deviceName
	}

	$json = $data | ConvertTo-Json
	Write-Output "Authorize Webservice..."
	$response = FreeboxAPI-SendRequest -wsMethod "POST" -wsUrl "login/authorize/" -wsBody $json
	New-Item -ItemType File -Path $TOKEN_API_PATH -Value $response.result.app_token -Force | Out-Null
	New-Item -ItemType File -Path $TRACKID_API_PATH -Value $response.result.track_id -Force | Out-Null

	Write-Output "You have 30 seconds to go to your web interface, to 'Params', 'Access Management', 'Applications' and you must authorize 'Edit Settings' for the app $APP_NAME."
	Start-Sleep -Seconds 30 
}

function FreeboxAPI-TrackAuthorize {
	$trackId = (Get-Content $TRACKID_API_PATH -Raw)
	$url = "login/authorize/" + $trackId
	$response = FreeboxAPI-SendRequest -wsMethod "GET" -wsUrl $url

	return $response.result
}

function FreeboxAPI-OpenSession {
	param(
		[Parameter(Mandatory=$true)][string]$challenge
	)

	$token = (Get-Content $TOKEN_API_PATH -Raw)

	$hmacsha1 = New-Object System.Security.Cryptography.HMACSHA1;
	$hmacsha1.key = [Text.Encoding]::UTF8.GetBytes($token)
	$password = $hmacsha1.ComputeHash([Text.Encoding]::UTF8.GetBytes($challenge))
	$password = ($password | ForEach-Object ToString x2 ) -join ''

	$data = @{
		"app_id" = $APP_ID
		"password" = $password
	}

	$json = $data | ConvertTo-Json
	$response = FreeboxAPI-SendRequest -wsMethod "POST" -wsUrl "login/session/" -wsBody $json
	Set-Variable -Name "SESSION_TOKEN" -Value ($response.result.session_token) -Scope Script
	New-Item -ItemType File -Path $SESSION_API_PATH -Value $SESSION_TOKEN -Force | Out-Null
}

function FreeboxAPI-Login {
	$trackIdExists = (Test-Path $TRACKID_API_PATH -PathType leaf)
	if(-NOT($trackIdExists)) {
		$deviceName = Read-Host 'What is the name of the device where you use this script ?'
		FreeboxAPI-Authorize -deviceName $deviceName
	}
	do {
		Write-Output "Checking Authorization..."
		$result = FreeboxAPI-TrackAuthorize
		Start-Sleep -Seconds 1
	} while ($result.status -eq "pending")
	
	Write-Output "Authorized  !"
	$challengeArray = $result.challenge
	$challenge = "$challengeArray"
	FreeboxAPI-OpenSession -challenge $challenge
	Start-Sleep -Seconds 1
}

function FreeboxAPI-Reboot {
	try {
		$response = FreeboxAPI-SendRequest -wsMethod "POST" -wsUrl "/system/reboot/" -sessionToken $SESSION_TOKEN
	} catch {
		if($_.Exception.Response.StatusCode.value__ -eq 403) {
			FreeboxAPI-Login
			$response = FreeboxAPI-SendRequest -wsMethod "POST" -wsUrl "/system/reboot/" -sessionToken $SESSION_TOKEN
		}
	}

	return $response
}