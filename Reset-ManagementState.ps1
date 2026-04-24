# Zertifikatsprüfung deaktivieren
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$ClientList
)

function ConvertTo-ClientArray {
    <#
    .SYNOPSIS
    Konvertiert Eingabewerte in ein bereinigtes Client-Array.

    .DESCRIPTION
    Diese Funktion nimmt einen String oder ein String-Array entgegen, trennt die Werte
    robust an Zeilenumbrüchen, Kommas oder Semikolons und entfernt leere Einträge.
    Zusätzlich wird geprüft, ob jeder Eintrag wie eine IPv4-Adresse oder ein FQDN/Hostname
    aussieht. Das Ergebnis wird immer als [string[]] zurückgegeben.

    .PARAMETER InputValues
    Die Rohwerte aus GUI oder Startparameter "-ClientList".

    .OUTPUTS
    [string[]]
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$InputValues
    )

    $joined = ($InputValues -join [Environment]::NewLine)
    $items = $joined -split "[\r\n,;]+" |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if (-not $items) {
        throw "Es wurden keine Client-Adressen angegeben."
    }

    $ipPattern = '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$'
    $fqdnPattern = '^(?=.{1,253}$)(?:(?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)*[A-Za-z0-9-]{1,63}$'

    $invalid = $items | Where-Object { $_ -notmatch $ipPattern -and $_ -notmatch $fqdnPattern }
    if ($invalid) {
        throw "Ungültige Adresse(n): $($invalid -join ', ')"
    }

    return [string[]]$items
}

function Get-ClientsFromGui {
    <#
    .SYNOPSIS
    Öffnet ein GUI-Fenster zur Eingabe von Client-Adressen.

    .DESCRIPTION
    Zeigt ein kompaktes Dialogfenster mit einer mehrzeiligen Textbox (Standardhöhe für
    ca. 10 Zeilen), einer Beschriftung sowie OK/Abbrechen-Buttons. Die eingegebenen Daten
    werden nach Bestätigung über ConvertTo-ClientArray als [string[]] zurückgegeben.

    .OUTPUTS
    [string[]]
    #>

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Client addresses'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(540, 340)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(12, 12)
    $label.Text = 'Insert IP or FQDN; One address per line'

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(12, 36)
    $textBox.Size = New-Object System.Drawing.Size(500, 200)
    $textBox.Multiline = $true
    $textBox.AcceptsReturn = $true
    $textBox.ScrollBars = 'Vertical'
    $textBox.WordWrap = $false

    $font = New-Object System.Drawing.Font('Consolas', 10)
    $textBox.Font = $font
    $lineHeight = [System.Windows.Forms.TextRenderer]::MeasureText('A', $textBox.Font).Height
    $textBox.Height = ($lineHeight * 10) + 10

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = 'OK'
    $okButton.Location = New-Object System.Drawing.Point(356, 260)
    $okButton.Size = New-Object System.Drawing.Size(75, 28)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Abbrechen'
    $cancelButton.Location = New-Object System.Drawing.Point(437, 260)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 28)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@($label, $textBox, $okButton, $cancelButton))
    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        throw 'Abbruch durch Benutzer.'
    }

    return ConvertTo-ClientArray -InputValues @($textBox.Lines)
}

try {
    if ($PSBoundParameters.ContainsKey('ClientList') -and $null -ne $ClientList -and $ClientList.Count -gt 0) {
        $clients = ConvertTo-ClientArray -InputValues $ClientList
    }
    else {
        $clients = Get-ClientsFromGui
    }
}
catch {
    Write-Error $_
    exit 1
}

foreach ($client in $clients) {
    if (-not (Test-Connection -ComputerName $client -Count 1)) {
        Write-Host ("$client nicht pingbar")
        continue
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
    }
    else {
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
