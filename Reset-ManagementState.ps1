# Zertifikatsprüfung deaktivieren
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}

# Dummy List
$clients= @("127.0.0.1")

foreach ($client in $clients)
{

if ( -not (Test-Connection -ComputerName $client -Count 1))
{
    Write-Host ("$client nicht pingbar")
    continue;
    }

# Ziel-URL des Zero Client Login
$baseUrl = "https://$client"   # Zero Client IP
$loginUrl = "$baseUrl/cgi-bin/login"
$managementUrl = "$baseUrl/configuration/management.html"

# Anmeldedaten
$password = "Administrator"
$idleTimeout = "5" # 0 = Never

# Session-Objekt für Cookies
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# POST-Daten für Login
$body = @{
    "password_value" = $password
    "idle_timeout" = $idleTimeout
}

# Login-Request
$response = Invoke-WebRequest -Uri $loginUrl -Method POST -Body $body -WebSession $session -UseBasicParsing

# Prüfen, ob Login erfolgreich war
if ($response.Content -match "The password you entered is incorrect") {
    Write-Host "Login fehlgeschlagen: Passwort ist falsch!"
} else {
    Write-Host "Login erfolgreich!"

    # Management-Seite abrufen
    $managementResponse = Invoke-WebRequest -Uri $managementUrl -WebSession $session -UseBasicParsing -Verbose -Debug

    # Status ausgeben
    Write-Host "Management-Seite geladen. HTTP-Status:" $managementResponse.StatusCode
}

# URL of the management endpoint
$uri = "$baseUrl/cgi-bin/configuration/management"

# Form data to send (match the hidden form inputs)
$form = @{
    ebm_address = ""
    security_level = "0"       # set according to your visible form
    discovery_mode = "0"       # set according to your visible form
    internal_em_uri = ""
    external_em_uri = ""
}

# Send POST request
$response = Invoke-WebRequest -Uri $uri -Method POST -Body $form -UseBasicParsing -WebSession $session -Verbose -Debug
Write-Host "POST request gesendet. HTTP-Status:" $response.StatusCode

# URL of the management endpoint
$uri = "$baseUrl/cgi-bin/ajax/configuration/management?clear_topology="
$response = Invoke-WebRequest -Uri $uri -Method POST -UseBasicParsing -WebSession $session -Verbose -Debug
Write-Host "AJAX POST request gesendet. HTTP-Status:" $response.StatusCode
}