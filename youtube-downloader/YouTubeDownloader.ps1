Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$binDir  = Join-Path $root 'bin'
$ytdlp   = Join-Path $binDir 'yt-dlp.exe'
$ffmpeg  = Join-Path $binDir 'ffmpeg.exe'
$logFile = Join-Path $env:TEMP 'ytdl_output.log'
$script:proc = $null
$script:logPos = 0

# ---------- Interface ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'YouTube Downloader'
$form.Size = New-Object System.Drawing.Size(640, 470)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

function New-Label($text, $x, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.AutoSize = $true
    $form.Controls.Add($l); $l
}

New-Label 'Lien de la vidéo YouTube :' 20 15 | Out-Null
$txtUrl = New-Object System.Windows.Forms.TextBox
$txtUrl.Location = New-Object System.Drawing.Point(20, 40)
$txtUrl.Size = New-Object System.Drawing.Size(485, 28)
$form.Controls.Add($txtUrl)

$btnPaste = New-Object System.Windows.Forms.Button
$btnPaste.Text = 'Coller'
$btnPaste.Location = New-Object System.Drawing.Point(515, 38)
$btnPaste.Size = New-Object System.Drawing.Size(90, 30)
$btnPaste.Add_Click({ if ([System.Windows.Forms.Clipboard]::ContainsText()) { $txtUrl.Text = [System.Windows.Forms.Clipboard]::GetText().Trim() } })
$form.Controls.Add($btnPaste)

New-Label 'Format :' 20 85 | Out-Null
$rbMp3 = New-Object System.Windows.Forms.RadioButton
$rbMp3.Text = 'MP3 (audio)'; $rbMp3.Checked = $true
$rbMp3.Location = New-Object System.Drawing.Point(90, 83); $rbMp3.AutoSize = $true
$form.Controls.Add($rbMp3)
$rbMp4 = New-Object System.Windows.Forms.RadioButton
$rbMp4.Text = 'MP4 (vidéo)'
$rbMp4.Location = New-Object System.Drawing.Point(220, 83); $rbMp4.AutoSize = $true
$form.Controls.Add($rbMp4)

New-Label 'Dossier de destination :' 20 120 | Out-Null
$txtDir = New-Object System.Windows.Forms.TextBox
$txtDir.Location = New-Object System.Drawing.Point(20, 145)
$txtDir.Size = New-Object System.Drawing.Size(485, 28)
$txtDir.Text = [Environment]::GetFolderPath('MyVideos')
$form.Controls.Add($txtDir)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Parcourir...'
$btnBrowse.Location = New-Object System.Drawing.Point(515, 143)
$btnBrowse.Size = New-Object System.Drawing.Size(90, 30)
$btnBrowse.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.SelectedPath = $txtDir.Text
    if ($d.ShowDialog() -eq 'OK') { $txtDir.Text = $d.SelectedPath }
})
$form.Controls.Add($btnBrowse)

$chkPlaylist = New-Object System.Windows.Forms.CheckBox
$chkPlaylist.Text = 'Télécharger toute la playlist (si le lien en contient une)'
$chkPlaylist.Location = New-Object System.Drawing.Point(20, 185); $chkPlaylist.AutoSize = $true
$form.Controls.Add($chkPlaylist)

$btnGo = New-Object System.Windows.Forms.Button
$btnGo.Text = 'Télécharger'
$btnGo.Location = New-Object System.Drawing.Point(20, 220)
$btnGo.Size = New-Object System.Drawing.Size(585, 38)
$btnGo.BackColor = [System.Drawing.Color]::FromArgb(200, 30, 30)
$btnGo.ForeColor = [System.Drawing.Color]::White
$btnGo.FlatStyle = 'Flat'
$form.Controls.Add($btnGo)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(20, 270)
$bar.Size = New-Object System.Drawing.Size(585, 20)
$form.Controls.Add($bar)

$lblStatus = New-Label 'Prêt.' 20 295
$lblStatus.Text = 'Prêt.'

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Location = New-Object System.Drawing.Point(20, 322)
$txtLog.Size = New-Object System.Drawing.Size(585, 100)
$form.Controls.Add($txtLog)

function Log($msg) { $txtLog.AppendText($msg + "`r`n") }
function Status($msg) { $lblStatus.Text = $msg; $form.Refresh() }

# ---------- Installation des outils (premier lancement) ----------
function Ensure-Tools {
    if ((Test-Path $ytdlp) -and (Test-Path $ffmpeg)) { return $true }
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Premier lancement : il faut télécharger 2 outils dans le dossier 'bin' :`n`n" +
        "- yt-dlp (~15 Mo, depuis github.com/yt-dlp)`n- ffmpeg (~130 Mo, depuis github.com/yt-dlp/FFmpeg-Builds)`n`nContinuer ?",
        'Installation', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return $false }
    New-Item -ItemType Directory -Force $binDir | Out-Null
    try {
        if (-not (Test-Path $ytdlp)) {
            Status 'Téléchargement de yt-dlp...'
            Invoke-WebRequest 'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe' -OutFile $ytdlp -UseBasicParsing
        }
        if (-not (Test-Path $ffmpeg)) {
            Status 'Téléchargement de ffmpeg (patientez, ~130 Mo)...'
            $zip = Join-Path $env:TEMP 'ffmpeg-dl.zip'
            Invoke-WebRequest 'https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip' -OutFile $zip -UseBasicParsing
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $arc = [System.IO.Compression.ZipFile]::OpenRead($zip)
            try {
                $entry = $arc.Entries | Where-Object { $_.FullName -like '*/bin/ffmpeg.exe' } | Select-Object -First 1
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $ffmpeg, $true)
            } finally { $arc.Dispose() }
            Remove-Item $zip -Force
        }
        Status 'Outils installés.'
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Echec du téléchargement :`n$($_.Exception.Message)", 'Erreur', 'OK', 'Error') | Out-Null
        Status 'Erreur d''installation.'
        return $false
    }
}

# ---------- Suivi du processus ----------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    if (Test-Path $logFile) {
        $fs = [System.IO.File]::Open($logFile, 'Open', 'Read', 'ReadWrite')
        try {
            $fs.Seek($script:logPos, 'Begin') | Out-Null
            $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
            $chunk = $sr.ReadToEnd()
            $script:logPos = $fs.Position
        } finally { $fs.Dispose() }
        foreach ($line in ($chunk -split "`r?`n")) {
            if ($line.Trim() -eq '') { continue }
            if ($line -match '\[download\]\s+([\d\.]+)%') {
                $bar.Value = [Math]::Min(100, [int][double]$matches[1])
                Status ($line -replace '^\[download\]\s*', '')
            } else {
                Log $line
            }
        }
    }
    if ($script:proc -and $script:proc.HasExited) {
        $timer.Stop()
        if ($script:proc.ExitCode -eq 0) {
            $bar.Value = 100
            Status 'Terminé !'
            Log "Terminé -> $($txtDir.Text)"
            Start-Process explorer.exe $txtDir.Text
        } else {
            Status 'Erreur (voir le journal).'
        }
        $btnGo.Enabled = $true
        $script:proc = $null
    }
})

$btnGo.Add_Click({
    $url = $txtUrl.Text.Trim()
    if ($url -notmatch '^https?://(www\.|m\.|music\.)?(youtube\.com|youtu\.be)/') {
        [System.Windows.Forms.MessageBox]::Show('Entrez un lien YouTube valide.', 'Lien invalide', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not (Test-Path $txtDir.Text)) { New-Item -ItemType Directory -Force $txtDir.Text | Out-Null }
    $btnGo.Enabled = $false
    if (-not (Ensure-Tools)) { $btnGo.Enabled = $true; return }

    $out = Join-Path $txtDir.Text '%(title)s.%(ext)s'
    $ytArgs = @('--newline', '--no-colors', '--encoding', 'utf-8', '--windows-filenames', '--ffmpeg-location', "`"$binDir`"", '-o', "`"$out`"")
    if ($chkPlaylist.Checked) { $ytArgs += '--yes-playlist' } else { $ytArgs += '--no-playlist' }
    if ($rbMp3.Checked) {
        $ytArgs += @('-x', '--audio-format', 'mp3', '--audio-quality', '0')
    } else {
        $ytArgs += @('-f', '"bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b"', '--merge-output-format', 'mp4')
    }
    $ytArgs += "`"$url`""

    Set-Content $logFile '' -Encoding UTF8
    $script:logPos = 0
    $txtLog.Clear(); $bar.Value = 0
    Status 'Démarrage...'
    $script:proc = Start-Process $ytdlp -ArgumentList $ytArgs -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $logFile -RedirectStandardError (Join-Path $env:TEMP 'ytdl_err.log')
    $timer.Start()
})

# yt-dlp ecrit aussi les erreurs sur stderr : on les ajoute au journal a la fin
$timer.Add_Tick({
    if ($script:proc -and $script:proc.HasExited) {
        $e = Join-Path $env:TEMP 'ytdl_err.log'
        if ((Test-Path $e) -and (Get-Item $e).Length -gt 0) { Log (Get-Content $e -Raw); Clear-Content $e }
    }
})

$form.Add_FormClosing({ if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill() } })
[void]$form.ShowDialog()
