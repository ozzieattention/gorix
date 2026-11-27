# Gorix - ayarlar penceresi. Show-YSettings mevcut ayarlarin kopyasini alir; Kaydet'e basilirsa yeni degerleri,
# iptal edilirse $null dondurur. Uygulama (kisayol kaydi, baslangic kisayolu) Gorix.ps1'de yapilir.

# Yumusatilmis yazi: Label yerine GDI+ ile cizilen panel (Windows Label'i karanlik zeminde tirtikli gorunuyor)
# $px: yazi boyu (96 DPI piksel). Boyut olcekleme oncesi (mantiksal) birimle verilir, form DPI'a gore buyutur.
function New-YText([string]$text, [double]$px, [System.Drawing.Color]$color, [string]$weight = 'Ui') {
    $p = New-Object System.Windows.Forms.Panel
    $p.BackColor = [System.Drawing.Color]::Transparent
    Set-DoubleBuffered $p
    $font = New-YFont (S $px) $weight
    $mg = [System.Drawing.Graphics]::FromImage((New-Object System.Drawing.Bitmap 1, 1))
    $mg.TextRenderingHint = 'AntiAliasGridFit'
    $sz = $mg.MeasureString($text, $font); $mg.Dispose()
    $p.Size = New-Object System.Drawing.Size ([int][Math]::Ceiling($sz.Width / $script:YScale + 2)), ([int][Math]::Ceiling($sz.Height / $script:YScale + 1))
    $p.Tag = @{ Text = $text; Font = $font; Color = $color }
    $p.add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.TextRenderingHint = 'AntiAliasGridFit'
        $b = New-Object System.Drawing.SolidBrush $s.Tag.Color
        $g.DrawString($s.Tag.Text, $s.Tag.Font, $b, [single]0, [single]0); $b.Dispose()
    })
    $p.add_Disposed({ param($s, $e) $s.Tag.Font.Dispose() })
    $p
}

# Kayan anahtar ikonu: Ac/Kapa
function New-YToggle([bool]$on) {
    $t = New-Object System.Windows.Forms.Panel
    $t.Size = New-Object System.Drawing.Size 46, 24
    $t.Cursor = [System.Windows.Forms.Cursors]::Hand
    $t.Tag = @{ On = $on }
    Set-DoubleBuffered $t
    $t.add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
        $w = $s.ClientSize.Width; $h = $s.ClientSize.Height
        $on = $s.Tag.On
        $track = New-Object System.Drawing.RectangleF 0.5, 0.5, ($w - 1.5), ($h - 1.5)
        Draw-YRound $g $track (($h - 1) / 2) $(if ($on) { $script:YT.Accent } else { New-YColor 58 58 66 }) $(if ($on) { $null } else { New-YColor 96 96 106 })
        $d = $h - 8
        $x = if ($on) { $w - $d - 4.5 } else { 4 }
        $kb = New-Object System.Drawing.SolidBrush $(if ($on) { [System.Drawing.Color]::White } else { New-YColor 200 200 208 })
        $g.FillEllipse($kb, [single]$x, [single]4, [single]$d, [single]$d); $kb.Dispose()
    })
    $t.add_Click({ param($s, $e) $s.Tag.On = -not $s.Tag.On; $s.Invalidate() })
    $t
}

# Kisayol yakalama kutusu: tiklayip tus kombinasyonuna bas. Geri tusu / Delete temizler.
function New-YHotkeyBox([string]$value) {
    $b = New-Object System.Windows.Forms.TextBox
    $b.ReadOnly = $true
    $b.BorderStyle = 'FixedSingle'
    $b.BackColor = $script:YT.Field
    $b.ForeColor = $script:YT.Text
    $b.Font = New-Object System.Drawing.Font $script:YF.Ctl, 10
    $b.Width = 190
    $b.TextAlign = 'Center'
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.ShortcutsEnabled = $false
    $b.Tag = @{ Value = $value }
    $b.Text = if ($value) { $value -replace '\+', ' + ' } else { 'Yok' }
    $b.add_Enter({ param($s, $e) $s.Text = 'Tuşlara bas...'; $s.BackColor = New-YColor 30 44 70 })
    $b.add_Leave({ param($s, $e) $v = $s.Tag.Value; $s.Text = if ($v) { $v -replace '\+', ' + ' } else { 'Yok' }; $s.BackColor = $script:YT.Field })
    $apply = {
        param($s, [System.Windows.Forms.KeyEventArgs]$e)
        $key = $e.KeyCode
        if ($key -in 'ControlKey', 'ShiftKey', 'Menu', 'LWin', 'RWin', 'Tab') { return }
        $e.SuppressKeyPress = $true; $e.Handled = $true
        if ($key -in 'Back', 'Delete') { $s.Tag.Value = '' }
        elseif ($key -eq 'Escape') { }
        else {
            $parts = @()
            if ($e.Control) { $parts += 'Ctrl' }
            if ($e.Alt) { $parts += 'Alt' }
            if ($e.Shift) { $parts += 'Shift' }
            if ([Yakala.KeyState]::WinDown()) { $parts += 'Win' }
            $s.Tag.Value = (@($parts) + @("$key")) -join '+'
        }
        # Odagi birak: kutu yeni degeri gostersin
        $s.FindForm().ActiveControl = $null
    }
    $b.add_KeyDown($apply)
    # PrintScreen yalnizca KeyUp ile gelir
    $b.add_KeyUp({ param($s, $e) if ($e.KeyCode -eq 'PrintScreen' -and $s.Focused) { & $apply $s $e } }.GetNewClosure())
    $b
}

function Show-YSettings($Current, [string[]]$Languages) {
    $cfg = @{}
    foreach ($k in @($Current.Keys)) { $cfg[$k] = $Current[$k] }
    $hk = @($cfg.Kisayollar) + @('', '')

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Gorix Ayarları'
    $f.Icon = New-YWindowIcon ([char]0xE713)   # cark
    $f.StartPosition = 'CenterScreen'
    $f.AutoScaleDimensions = New-Object System.Drawing.SizeF 96, 96
    $f.AutoScaleMode = 'Dpi'
    $f.ClientSize = New-Object System.Drawing.Size 620, 700
    $f.FormBorderStyle = 'FixedSingle'   # sabit boyut
    $f.MaximizeBox = $false
    $f.BackColor = $script:YT.PanelSolid
    $f.ForeColor = $script:YT.Text
    $f.Font = New-Object System.Drawing.Font $script:YF.Ctl, 9.5
    $f.KeyPreview = $true
    $f.add_HandleCreated({ param($s, $e) [Yakala.Dwm]::Style($s.Handle, $true, $true) })
    $f.Tag = $null

    # Ust baslik
    $header = New-Object System.Windows.Forms.Panel
    $header.Dock = 'Top'; $header.Height = 74
    Set-DoubleBuffered $header
    $header.add_Paint({
        param($s, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $d = S 38
        Draw-YRound $g (New-Object System.Drawing.RectangleF (S 24), (S 18), $d, $d) (S 10) $script:YT.Accent
        Draw-YGlyph $g ([char]0xE713) (New-Object System.Drawing.RectangleF (S 24), (S 18), $d, $d) $script:YT.Text (S 18)
        $ft = New-YFont (S 18) 'Semi'; $fs = New-YFont (S 13)
        $tb = New-Object System.Drawing.SolidBrush $script:YT.Text; $mb = New-Object System.Drawing.SolidBrush $script:YT.Muted
        $g.DrawString('Gorix Ayarları', $ft, $tb, (S 74), (S 15))
        $g.DrawString('Değişiklikler Kaydet''e basınca uygulanır', $fs, $mb, (S 75), (S 41))
        $tb.Dispose(); $mb.Dispose(); $ft.Dispose(); $fs.Dispose()
    })

    # Kaydirilabilir icerik
    $scroll = New-Object System.Windows.Forms.Panel
    $scroll.Dock = 'Fill'
    $scroll.AutoScroll = $true
    $scroll.Padding = New-Object System.Windows.Forms.Padding 0, 0, 0, 10
    $script:ySetY = 4
    $rowW = 560

    $addSection = {
        param([string]$title)
        $l = New-YText $title.ToUpper([Globalization.CultureInfo]::GetCultureInfo('tr-TR')) 11.5 $script:YT.Accent 'Semi'
        $l.Location = New-Object System.Drawing.Point 26, ($script:ySetY + 14)
        $scroll.Controls.Add($l)
        $script:ySetY += 40
    }
    $addRow = {
        param([string]$title, [string]$desc, [System.Windows.Forms.Control[]]$controls)
        $row = New-Object System.Windows.Forms.Panel
        $row.Location = New-Object System.Drawing.Point 18, $script:ySetY
        $row.Size = New-Object System.Drawing.Size $rowW, $(if ($desc) { 58 } else { 46 })
        $row.BackColor = New-YColor 40 40 46
        $t = New-YText $title 14 $script:YT.Text
        $t.Location = New-Object System.Drawing.Point 13, $(if ($desc) { 8 } else { 13 })
        $row.Controls.Add($t)
        if ($desc) {
            $d = New-YText $desc 12 $script:YT.Muted
            $d.Location = New-Object System.Drawing.Point 14, 31
            $row.Controls.Add($d)
        }
        $x = $rowW - 14
        for ($i = $controls.Count - 1; $i -ge 0; $i--) {
            $c = $controls[$i]
            $x -= $c.Width
            $c.Location = New-Object System.Drawing.Point $x, ([int](($row.Height - $c.Height) / 2))
            $row.Controls.Add($c)
            $x -= 8
        }
        $scroll.Controls.Add($row)
        $script:ySetY += $row.Height + 2
    }
    $smallButton = {
        param([string]$text, [switch]$Icon)
        $b = New-YButton $text
        $b.AutoSize = $false
        $b.Height = 30
        $b.Padding = New-Object System.Windows.Forms.Padding 0
        $b.Margin = New-Object System.Windows.Forms.Padding 0
        if ($Icon) { $b.Font = New-Object System.Drawing.Font $script:YF.Icon, 9; $b.Width = 32 }
        else { $b.Width = [System.Windows.Forms.TextRenderer]::MeasureText($text, $b.Font).Width + 24 }
        $b
    }

    # --- Kisayollar ---
    & $addSection 'Kısayollar'
    $hk1 = New-YHotkeyBox $hk[0]
    & $addRow 'Ekran yakalama' 'Kutuya tıklayıp tuşlara bas · Geri tuşu siler' @($hk1)
    $hk2 = New-YHotkeyBox $hk[1]
    $hk2Clear = & $smallButton ([string][char]0xE711) -Icon
    $hk2Clear.add_Click({ $hk2.Tag.Value = ''; $hk2.Text = 'Yok' })
    & $addRow 'İkinci kısayol' 'İsteğe bağlı, ör. Lightshot''ı bırakınca PrintScreen' @($hk2, $hk2Clear)

    # --- Metin okuma ---
    & $addSection 'Metin okuma'
    $lang = New-Object System.Windows.Forms.ComboBox
    $lang.DropDownStyle = 'DropDownList'
    $lang.FlatStyle = 'Flat'
    $lang.BackColor = $script:YT.Field
    $lang.ForeColor = $script:YT.Text
    $lang.Width = 190
    $lang.Font = New-Object System.Drawing.Font $script:YF.Ctl, 10
    foreach ($l in $Languages) { [void]$lang.Items.Add((Get-OcrLanguageName $l)) }
    $li = [array]::IndexOf($Languages, [string]$cfg.OcrDil); $lang.SelectedIndex = [Math]::Max(0, $li)
    & $addRow 'Okuma dili' 'Türkçe karakterler ve / - * ? ! birlikte okunur' @($lang)
    $tPreview = New-YToggle ([bool]$cfg.Onizleme)
    & $addRow 'Okunan metni pencerede göster' 'Kapalıysa metin doğrudan kopyalanır, sadece bildirim çıkar' @($tPreview)
    $tRepair = New-YToggle ([bool]$cfg.KarakterDuzeltme)
    & $addRow 'Karakter düzeltmeleri' 'Ox7F → 0x7F, 1O234 → 10234, pansiyon kodu Al → AI gibi bilinen hatalar' @($tRepair)

    # --- Secim ekrani ---
    & $addSection 'Seçim ekranı'
    $tToolbar = New-YToggle ([bool]$cfg.AracCubugu)
    & $addRow 'Çizim araç çubuğunu göster' 'Kalem, ok, dikdörtgen, metin... Kapalıyken sadece seçim yapılır' @($tToolbar)
    $tRemember = New-YToggle ([bool]$cfg.HatirlaAlan)
    $resetArea = & $smallButton 'Sıfırla'
    $resetArea.Enabled = [bool]$cfg.SonAlan
    $resetArea.add_Click({ $cfg.SonAlan = ''; $resetArea.Enabled = $false; $resetArea.Text = 'Sıfırlandı' })
    & $addRow 'Son seçilen alanı hatırla' 'Sonraki açılışta aynı alan seçili gelir' @($resetArea, $tRemember)

    # --- Kaydetme ---
    & $addSection 'Kaydetme'
    $folder = New-Object System.Windows.Forms.TextBox
    $folder.ReadOnly = $true
    $folder.BorderStyle = 'FixedSingle'
    $folder.BackColor = $script:YT.Field
    $folder.ForeColor = $script:YT.Text
    $folder.Width = 250
    $folder.Text = [Environment]::ExpandEnvironmentVariables($cfg.KayitKlasoru)
    $pick = & $smallButton 'Değiştir'
    $pick.add_Click({
        $fd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fd.SelectedPath = $folder.Text
        $fd.Description = 'Görüntülerin kaydedileceği klasör'
        if ($fd.ShowDialog($f) -eq 'OK') { $folder.Text = $fd.SelectedPath }
    })
    $open = & $smallButton ([string][char]0xE838) -Icon
    $open.add_Click({
        if (-not (Test-Path $folder.Text)) { New-Item -ItemType Directory -Path $folder.Text -Force | Out-Null }
        Start-Process explorer.exe $folder.Text
    })
    & $addRow 'Kayıt klasörü' $null @($folder, $pick, $open)

    # --- Genel ---
    & $addSection 'Genel'
    $tToast = New-YToggle ([bool]$cfg.Bildirimler)
    & $addRow 'Bildirimleri göster' 'Sağ altta çıkan "kopyalandı" bildirimleri (hatalar her zaman gösterilir)' @($tToast)
    $tStartup = New-YToggle ([bool]$cfg.Baslangic)
    & $addRow 'Windows açılışında başlat' 'Oturum açınca Gorix tepside hazır olur' @($tStartup)

    $scroll.AutoScrollMinSize = New-Object System.Drawing.Size 0, ($script:ySetY + 10)
    # Pencere tum ayarlari kaydirmadan gostersin (ekrana sigmiyorsa kaydirma kalir)
    $waH = [System.Windows.Forms.Screen]::FromPoint([System.Windows.Forms.Cursor]::Position).WorkingArea.Height / $script:YScale
    $f.ClientSize = New-Object System.Drawing.Size 620, ([int][Math]::Min(74 + $script:ySetY + 20 + 66, $waH - 60))

    # Alt butonlar
    $footer = New-Object System.Windows.Forms.Panel
    $footer.Dock = 'Bottom'; $footer.Height = 66
    $footer.Padding = New-Object System.Windows.Forms.Padding 0, 1, 0, 0   # ust ayirici cizgi butonlarin altinda kalmasin
    $status = New-Object System.Windows.Forms.Label
    $status.AutoSize = $true
    $status.ForeColor = $script:YT.Warn
    $status.Location = New-Object System.Drawing.Point 24, 25
    $btns = New-Object System.Windows.Forms.FlowLayoutPanel
    $btns.Dock = 'Right'; $btns.AutoSize = $true; $btns.WrapContents = $false
    $btns.Padding = New-Object System.Windows.Forms.Padding 0, 16, 18, 0
    $cancel = New-YButton 'İptal'
    $cancel.add_Click({ $f.Close() })
    $save = New-YButton 'Kaydet' -Primary
    $save.add_Click({
        $keys = @(@($hk1.Tag.Value, $hk2.Tag.Value) | Where-Object { $_ } | Select-Object -Unique)
        foreach ($k in $keys) {
            if ($k -notmatch '\+' -and $k -notin 'PrintScreen', 'Pause', 'Scroll' -and $k -notmatch '^F\d+$') {
                $status.Text = "Tek tuşlu kısayol ($k) yazarken tetiklenir; Ctrl/Alt/Shift ile birlikte seç."
                return
            }
        }
        $cfg.Kisayollar = $keys
        $cfg.OcrDil = $Languages[[Math]::Max(0, $lang.SelectedIndex)]
        $cfg.Onizleme = $tPreview.Tag.On
        $cfg.KarakterDuzeltme = $tRepair.Tag.On
        $cfg.AracCubugu = $tToolbar.Tag.On
        $cfg.HatirlaAlan = $tRemember.Tag.On
        if (-not $cfg.HatirlaAlan) { $cfg.SonAlan = '' }
        $cfg.KayitKlasoru = $folder.Text
        $cfg.Bildirimler = $tToast.Tag.On
        $cfg.Baslangic = $tStartup.Tag.On
        $f.Tag = $cfg
        $f.Close()
    })
    $btns.Controls.AddRange(@($cancel, $save))
    $footer.Controls.Add($status)
    $footer.Controls.Add($btns)
    $footer.add_Paint({ param($s, $e) $p = New-Object System.Drawing.Pen (New-YColor 255 255 255 20); $e.Graphics.DrawLine($p, 0, 0, $s.Width, 0); $p.Dispose() })

    $f.Controls.Add($scroll)
    $f.Controls.Add($header)
    $f.Controls.Add($footer)
    $f.add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape' -and -not ($hk1.Focused -or $hk2.Focused)) { $f.Close() } })
    $f.add_Shown({ $f.Activate(); [void]$save.Focus() })

    try { [void]$f.ShowDialog(); $f.Tag } finally { $f.Dispose() }
}
