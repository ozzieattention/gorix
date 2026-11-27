# Gorix - "Metni bul" penceresi: bulunan metni gosterir, istenirse duzeltilip kopyalanir.
# Okuma dili Ayarlar'dan secilir; burada sade tutuldu.

function Show-OcrPreview([System.Drawing.Bitmap]$Bitmap, [string]$Text, [string]$Language) {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Metni bul'
    $f.Icon = Get-YAppIcon 32
    $f.TopMost = $true
    $f.KeyPreview = $true
    $f.StartPosition = 'CenterScreen'
    $f.AutoScaleDimensions = New-Object System.Drawing.SizeF 96, 96
    $f.AutoScaleMode = 'Dpi'
    $f.ClientSize = New-Object System.Drawing.Size 640, 380
    $f.MinimumSize = New-Object System.Drawing.Size 420, 240
    $f.MinimizeBox = $false
    $f.BackColor = $script:YT.PanelSolid
    $f.ForeColor = $script:YT.Text
    $f.Font = New-Object System.Drawing.Font $script:YF.Ctl, 9.5
    $f.add_HandleCreated({ param($s, $e) [Yakala.Dwm]::Style($s.Handle, $true, $true) })

    # Metin alani
    $body = New-Object System.Windows.Forms.Panel
    $body.Dock = 'Fill'
    $body.Padding = New-Object System.Windows.Forms.Padding 16, 16, 16, 0
    $frame = New-Object System.Windows.Forms.Panel
    $frame.Dock = 'Fill'
    $frame.BackColor = New-YColor 58 58 66
    $frame.Padding = New-Object System.Windows.Forms.Padding 1
    $inner = New-Object System.Windows.Forms.Panel
    $inner.Dock = 'Fill'
    $inner.BackColor = $script:YT.Field
    $inner.Padding = New-Object System.Windows.Forms.Padding 12, 10, 6, 6
    $box = New-Object System.Windows.Forms.TextBox
    $box.Multiline = $true
    $box.ScrollBars = 'Vertical'
    $box.WordWrap = $true
    $box.Dock = 'Fill'
    $box.BorderStyle = 'None'
    $box.BackColor = $script:YT.Field
    $box.ForeColor = $script:YT.Text
    $box.Font = New-Object System.Drawing.Font $script:YF.Mono, 10.5
    $box.Text = if ($Text) { $Text } else { '' }
    $inner.Controls.Add($box); $frame.Controls.Add($inner); $body.Controls.Add($frame)

    # Alt: bilgi + Kapat / Kopyala
    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = 'Bottom'
    $footer.Height = 64
    $info = New-Object System.Windows.Forms.Label
    $info.AutoSize = $true
    $info.ForeColor = $script:YT.Muted
    $info.Location = New-Object System.Drawing.Point 18, 24
    $updateInfo = {
        if ($box.Text) { $info.Text = "$(($box.Text -split "`r`n").Count) satır · $($box.Text.Length) karakter"; $info.ForeColor = $script:YT.Muted }
        else { $info.Text = 'Seçili alanda metin bulunamadı'; $info.ForeColor = $script:YT.Warn }
    }
    & $updateInfo
    $box.add_TextChanged($updateInfo)
    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Right'
    $buttons.AutoSize = $true
    $buttons.WrapContents = $false
    $buttons.Padding = New-Object System.Windows.Forms.Padding 0, 15, 16, 0
    $close = New-YButton 'Kapat'
    $close.add_Click({ $f.Close() })
    $copy = New-YButton 'Kopyala' -Primary
    $copy.add_Click({
        # Secili kisim varsa onu, yoksa tamamini kopyala
        $t = if ($box.SelectionLength -gt 0) { $box.SelectedText } else { $box.Text }
        if ($t) { [System.Windows.Forms.Clipboard]::SetText($t) }
        $f.Close()
    })
    $buttons.Controls.AddRange(@($close, $copy))
    $footer.Controls.Add($info)
    $footer.Controls.Add($buttons)

    $f.Controls.Add($body)
    $f.Controls.Add($footer)

    $f.add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'Escape') { $f.Close() }
        elseif ($e.Control -and $e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; $copy.PerformClick() }
        elseif ($e.Control -and $e.KeyCode -eq 'A') { $e.SuppressKeyPress = $true; $box.SelectAll() }
    })
    $f.add_Shown({ $f.Activate(); [void]$box.Focus(); $box.SelectionStart = 0; $box.SelectionLength = 0 })

    try { [void]$f.ShowDialog() } finally { $f.Dispose() }
}
