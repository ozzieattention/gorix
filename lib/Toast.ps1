# Gorix - sag altta beliren, kendiliginden kaybolan bildirim
# Not: olaylar fonksiyon dondukten sonra calistigi icin durum $script:YToast'ta tutulur.

$script:YToast = $null

function Close-YToast {
    $t = $script:YToast
    if ($null -eq $t) { return }
    $script:YToast = $null
    $t.Timer.Stop(); $t.Timer.Dispose()
    if (-not $t.Form.IsDisposed) { $t.Form.Close(); $t.Form.Dispose() }
    $t.FontTitle.Dispose(); $t.FontMsg.Dispose()
}

function Show-YToast([string]$Message, [string]$Kind = 'ok') {
    # Ayarlardan kapatilabilir; hatalar her zaman gosterilir
    if ($Kind -ne 'error' -and $script:settings -and $script:settings.Contains('Bildirimler') -and -not $script:settings.Bildirimler) { return }
    Close-YToast
    $accent = switch ($Kind) { 'warn' { $script:YT.Warn } 'error' { $script:YT.Error } default { $script:YT.Green } }
    $glyph = switch ($Kind) { 'warn' { $script:YG.Warn } 'error' { $script:YG.Error } default { $script:YG.Check } }
    $title = switch ($Kind) { 'warn' { 'Dikkat' } 'error' { 'Hata' } default { 'Gorix' } }

    $fT = New-YFont (S 14) 'Semi'; $fM = New-YFont (S 13)
    $w = [int](S 380); $textX = S 60; $textW = $w - $textX - (S 20)
    $mg = [System.Drawing.Graphics]::FromImage((New-Object System.Drawing.Bitmap 1, 1))
    $msgH = $mg.MeasureString($Message, $fM, [int]$textW).Height
    $mg.Dispose()
    $h = [int][Math]::Max((S 76), (S 16) + (S 20) + (S 4) + $msgH + (S 16))

    $f = New-Object Yakala.ToastForm
    $f.FormBorderStyle = 'None'
    $f.ShowInTaskbar = $false
    $f.StartPosition = 'Manual'
    $f.BackColor = $script:YT.PanelSolid
    $f.Opacity = 0
    $wa = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea
    $f.Bounds = New-Object System.Drawing.Rectangle ($wa.Right - $w - [int](S 16)), ($wa.Bottom - $h - [int](S 16)), $w, $h

    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 15
    $script:YToast = @{
        Form = $f; Timer = $timer; Phase = 'in'; Born = [DateTime]::Now
        Message = $Message; Title = $title; Glyph = $glyph; Accent = $accent
        FontTitle = $fT; FontMsg = $fM; TextX = $textX; TextW = $textW
    }

    $f.add_HandleCreated({ param($s, $e) [Yakala.Dwm]::Style($s.Handle, $true, $true) })
    $f.add_Click({ if ($script:YToast) { $script:YToast.Phase = 'out' } })
    $f.add_Paint({
        param($s, $e)
        $t = $script:YToast
        if ($null -eq $t) { return }
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $hh = $s.ClientSize.Height
        $d = S 30
        $cb = New-Object System.Drawing.SolidBrush $t.Accent
        $g.FillEllipse($cb, (S 18), ($hh / 2 - $d / 2), $d, $d); $cb.Dispose()
        Draw-YGlyph $g $t.Glyph (New-Object System.Drawing.RectangleF (S 18), ($hh / 2 - $d / 2), $d, $d) $script:YT.Text (S 14)
        $tb = New-Object System.Drawing.SolidBrush $script:YT.Text
        $mb = New-Object System.Drawing.SolidBrush $script:YT.Muted
        $g.DrawString($t.Title, $t.FontTitle, $tb, $t.TextX, (S 16))
        $g.DrawString($t.Message, $t.FontMsg, $mb, (New-Object System.Drawing.RectangleF $t.TextX, (S 40), $t.TextW, ($hh - (S 44))))
        $tb.Dispose(); $mb.Dispose()
    })
    $timer.add_Tick({
        $t = $script:YToast
        if ($null -eq $t) { return }
        switch ($t.Phase) {
            'in' { $t.Form.Opacity = [Math]::Min(0.97, $t.Form.Opacity + 0.12); if ($t.Form.Opacity -ge 0.97) { $t.Phase = 'hold' } }
            'hold' { if (([DateTime]::Now - $t.Born).TotalMilliseconds -gt 3000) { $t.Phase = 'out' } }
            'out' { $t.Form.Opacity -= 0.08; if ($t.Form.Opacity -le 0.02) { Close-YToast } }
        }
    })

    $f.Show()
    $timer.Start()
}
