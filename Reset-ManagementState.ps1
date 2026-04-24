[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$ClientList,

    [Parameter(Mandatory = $false)]
    [AllowNull()]
    [Nullable[bool]]$NoSSLCheck = $null,

    [Parameter(Mandatory = $false)]
    [string]$Password = 'Administrator'
)

function ConvertTo-ClientArray {
    <#
    .SYNOPSIS
    Converts raw input values into a cleaned client array.

    .DESCRIPTION
    Accepts a string or string array, splits values by newlines/commas/semicolons,
    trims whitespace, removes empty entries, and validates each entry as IPv4 or
    host/FQDN. Always returns [string[]].

    .PARAMETER InputValues
    Raw values from GUI or from the -ClientList parameter.

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
        throw 'No client addresses were provided.'
    }

    $ipPattern = '^(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)$'
    $fqdnPattern = '^(?=.{1,253}$)(?:(?!-)[A-Za-z0-9-]{1,63}(?<!-)\.)*[A-Za-z0-9-]{1,63}$'

    $invalid = $items | Where-Object { $_ -notmatch $ipPattern -and $_ -notmatch $fqdnPattern }
    if ($invalid) {
        throw "Invalid address(es): $($invalid -join ', ')"
    }

    return [string[]]$items
}

function Get-ClientInputFromGui {
    <#
    .SYNOPSIS
    Opens a GUI dialog for client addresses, password, and SSL option.

    .DESCRIPTION
    Displays a compact Windows Forms dialog with a multiline address textbox
    (default height for ~10 lines), a password input line, an SSL checkbox,
    and OK/Cancel buttons.

    .PARAMETER InitialNoSSLCheck
    Initial checkbox state for SSL validation behavior.

    .PARAMETER InitialPassword
    Initial value shown in the password input textbox.

    .OUTPUTS
    [pscustomobject] with properties:
    - Clients ([string[]])
    - NoSSLCheck ([bool])
    - Password ([string])
    #>
    param(
        [Parameter(Mandatory = $true)]
        [bool]$InitialNoSSLCheck,

        [Parameter(Mandatory = $true)]
        [string]$InitialPassword
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'DELL WYZE P25 (WYZE 3050) Management Status reset'
    $form.StartPosition = 'CenterScreen'
    $form.Size = New-Object System.Drawing.Size(540, 440)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(12, 12)
    $label.Text = 'Device IP or FQDN. One address per line'

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Location = New-Object System.Drawing.Point(12, 36)
    $textBox.Size = New-Object System.Drawing.Size(500, 100)
    $textBox.Multiline = $true
    $textBox.AcceptsReturn = $true
    $textBox.ScrollBars = 'Vertical'
    $textBox.WordWrap = $false

    $font = New-Object System.Drawing.Font('Consolas', 10)
    $textBox.Font = $font
    $lineHeight = [System.Windows.Forms.TextRenderer]::MeasureText('A', $textBox.Font).Height
    $textBox.Height = ($lineHeight * 12) + 10

    $passwordLabel = New-Object System.Windows.Forms.Label
    $passwordLabel.AutoSize = $true
    $passwordLabel.Location = New-Object System.Drawing.Point(12, 258)
    $passwordLabel.Text = 'Enter Administrative password. Factory-Default: Administrator'

    $passwordTextBox = New-Object System.Windows.Forms.TextBox
    $passwordTextBox.Location = New-Object System.Drawing.Point(12, 280)
    $passwordTextBox.Size = New-Object System.Drawing.Size(500, 24)
    $passwordTextBox.Multiline = $false
    $passwordTextBox.PasswordChar = '*'
    $passwordTextBox.Text = $InitialPassword

    $sslCheckBox = New-Object System.Windows.Forms.CheckBox
    $sslCheckBox.AutoSize = $true
    $sslCheckBox.Location = New-Object System.Drawing.Point(12, 315)
    $sslCheckBox.Text = 'Disable SSL certificate validation (-NoSSLCheck)'
    $sslCheckBox.Checked = $InitialNoSSLCheck

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = 'OK'
    $okButton.Location = New-Object System.Drawing.Point(356, 360)
    $okButton.Size = New-Object System.Drawing.Size(75, 28)
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = 'Cancel'
    $cancelButton.Location = New-Object System.Drawing.Point(437, 360)
    $cancelButton.Size = New-Object System.Drawing.Size(75, 28)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $form.Controls.AddRange(@(
            $label,
            $textBox,
            $passwordLabel,
            $passwordTextBox,
            $sslCheckBox,
            $okButton,
            $cancelButton
        ))
    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        throw 'Canceled by user.'
    }

    [pscustomobject]@{
        Clients = (ConvertTo-ClientArray -InputValues @($textBox.Lines))
        NoSSLCheck = [bool]$sslCheckBox.Checked
        Password = $passwordTextBox.Text
    }
}

$defaultNoSSLCheck = $true
$effectiveNoSSLCheck = if ($null -ne $NoSSLCheck) { [bool]$NoSSLCheck } else { $defaultNoSSLCheck }
$effectivePassword = if ([string]::IsNullOrWhiteSpace($Password)) { 'Administrator' } else { $Password }

try {
    if ($PSBoundParameters.ContainsKey('ClientList') -and $null -ne $ClientList -and $ClientList.Count -gt 0) {
        # Only -ClientList suppresses the GUI.
        $clients = ConvertTo-ClientArray -InputValues $ClientList
    }
    else {
        $guiInput = Get-ClientInputFromGui -InitialNoSSLCheck $effectiveNoSSLCheck -InitialPassword $effectivePassword
        $clients = $guiInput.Clients
        $effectiveNoSSLCheck = [bool]$guiInput.NoSSLCheck

        if (-not [string]::IsNullOrWhiteSpace($guiInput.Password)) {
            $effectivePassword = $guiInput.Password
        }
    }
}
catch {
    Write-Error $_
    exit 1
}

if ($effectiveNoSSLCheck) {
    # Disable SSL certificate validation.
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
}
else {
    # Restore default certificate validation behavior.
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
}

foreach ($client in $clients) {
    if (-not (Test-Connection -ComputerName $client -Count 1)) {
        Write-Host ("$client is not reachable via ping")
        continue
    }

    # Target URLs for Zero Client login and management.
    $baseUrl = "https://$client"
    $loginUrl = "$baseUrl/cgi-bin/login"
    $managementUrl = "$baseUrl/configuration/management.html"

    # Login values.
    $idleTimeout = '5' # 0 = Never

    # Session object for cookies.
    $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

    # POST data for login.
    $body = @{
        'password_value' = $effectivePassword
        'idle_timeout' = $idleTimeout
    }

    # Login request.
    $response = Invoke-WebRequest -Uri $loginUrl -Method POST -Body $body -WebSession $session -UseBasicParsing

    # Check if login was successful.
    if ($response.Content -match 'The password you entered is incorrect') {
        Write-Host 'Login failed: Password is incorrect!'
    }
    else {
        Write-Host 'Login successful!'

        # Fetch management page.
        $managementResponse = Invoke-WebRequest -Uri $managementUrl -WebSession $session -UseBasicParsing -Verbose -Debug

        # Print status.
        Write-Host 'Management page loaded. HTTP status:' $managementResponse.StatusCode
    }

    # URL of the management endpoint.
    $uri = "$baseUrl/cgi-bin/configuration/management"

    # Form data to send (match the hidden form inputs).
    $form = @{
        ebm_address = ''
        security_level = '0'       # set according to your visible form
        discovery_mode = '0'       # set according to your visible form
        internal_em_uri = ''
        external_em_uri = ''
    }

    # Send POST request.
    $response = Invoke-WebRequest -Uri $uri -Method POST -Body $form -UseBasicParsing -WebSession $session -Verbose -Debug
    Write-Host 'POST request sent. HTTP status:' $response.StatusCode

    # URL of the AJAX management endpoint.
    $uri = "$baseUrl/cgi-bin/ajax/configuration/management?clear_topology="
    $response = Invoke-WebRequest -Uri $uri -Method POST -UseBasicParsing -WebSession $session -Verbose -Debug
    Write-Host 'AJAX POST request sent. HTTP status:' $response.StatusCode
}