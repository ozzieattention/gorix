# Gorix - secim ekrani penceresi ve fare/klavye davranisi

# Secim ekrani koordinatindaki noktanin bulundugu monitor (Windows ekran numarasiyla)
function Get-YScreenAt([System.Drawing.Point]$pt) {
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $sc = [System.Windows.Forms.Screen]::FromPoint((New-Object System.Drawing.Point ($pt.X + $vs.X), ($pt.Y + $vs.Y)))
    $no = if ($sc.DeviceName -match '(\d+)\s*$') { $Matches[1] } else { [array]::IndexOf([System.Windows.Forms.Screen]::AllScreens, $sc) + 1 }
    $name = "Ekran $no" + $(if ($sc.Primary) { ' (ana)' } else { '' }) + "  $($sc.Bounds.Width)×$($sc.Bounds.Height)"
    @{ Name = $name; Rect = (New-Object System.Drawing.Rectangle ($sc.Bounds.X - $vs.X), ($sc.Bounds.Y - $vs.Y), $sc.Bounds.Width, $sc.Bounds.Height) }
}

# Noktanin uzerindeki metin cizimi (en ustteki), yoksa $null
function Get-YTextShapeAt($st, [System.Drawing.Point]$pt) {
    for ($i = $st.Shapes.Count - 1; $i -ge 0; $i--) {
        $s = $st.Shapes[$i]
        if ($s.Type -ne 'text') { continue }
        $font = Get-YTextFont $s
        $sz = $st.Measure.MeasureString($s.Text, $font)
        $font.Dispose()
        $r = New-Object System.Drawing.RectangleF ($s.Points[0].X - 4), ($s.Points[0].Y - 4), ($sz.Width + 8), ($sz.Height + 8)
        if ($r.Contains([single]$pt.X, [single]$pt.Y)) { return $s }
    }
    $null
}

# Memory: @{ Rect = 'x,y,w,h' } (ekran koordinati). Acilista bu alan secili gelir, kapanista son secim yazilir.
# Options: @{ Toolbar = $true }  (cizim arac cubugu gosterilsin mi)
function Show-CaptureOverlay([string]$SaveFolder, [hashtable]$Memory, [hashtable]$Options = @{}) {
    $vs = [System.Windows.Forms.SystemInformation]::VirtualScreen
    # Form olusurken ekrani yakalar; secim/cizim surukleme C# icinde akar (FastCanvas.ps1)
    $f = New-Object Yakala.CaptureForm $vs, ([single]$script:YScale), $script:YF.Semi, $script:YT.Dim
    $st = New-YOverlayState $f
    $st.ShowToolbar = -not ($Options.ContainsKey('Toolbar') -and -not $Options.Toolbar)

    # Son secilen alani geri yukle (ekran duzeni degistiyse ve sigmiyorsa yoksay)
    if ($Memory -and $Memory.Rect) {
        $p = @("$($Memory.Rect)" -split ',' | ForEach-Object { $_.Trim() -as [int] })
        if ($p.Count -eq 4 -and $null -notin $p) {
            $mr = New-Object System.Drawing.Rectangle ($p[0] - $vs.X), ($p[1] - $vs.Y), $p[2], $p[3]
            if ((New-Object System.Drawing.Rectangle 0, 0, $vs.Width, $vs.Height).Contains($mr) -and $mr.Width -ge 5 -and $mr.Height -ge 5) { $st.Rect = $mr }
        }
    }
    $f.FormBorderStyle = 'None'
    $f.StartPosition = 'Manual'
    $f.Bounds = $vs
    $f.TopMost = $true
    $f.ShowInTaskbar = $false
    $f.KeyPreview = $true
    $f.Cursor = [System.Windows.Forms.Cursors]::Cross
    $f.Text = 'Gorix'

    # Metin araci icin yerinde yazma kutusu
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.BorderStyle = 'None'
    $tb.Visible = $false
    $tb.BackColor = New-YColor 24 24 28
    $f.Controls.Add($tb)

    $commitText = {
        if (-not $tb.Visible) { return }
        if ($tb.Text.Trim()) {
            $pts = New-Object System.Collections.Generic.List[System.Drawing.Point]
            $pts.Add($tb.Location)
            $st.Shapes.Add(@{ Type = 'text'; Points = $pts; Color = $tb.ForeColor; Width = $tb.Tag; Text = $tb.Text })
        }
        $tb.Visible = $false; $tb.Text = ''
        [void]$f.Focus()
        Invoke-YRefresh $f $st
    }
    $startText = {
        param([System.Drawing.Point]$pt, [string]$text = '', $color = $null, $width = $null)
        $w = if ($width) { $width } else { $script:YWidths[$st.WidthIndex] }
        $tb.Tag = $w
        $tb.Font = Get-YTextFont @{ Width = $w }
        $tb.ForeColor = if ($color) { $color } else { $st.Color }
        $tb.Location = $pt
        $tb.Width = [int](S 140)
        $tb.Text = $text
        $tb.Visible = $true
        [void]$tb.Focus()
        $tb.SelectionStart = $tb.Text.Length
    }

    # Metne cift tikla: yeniden duzenle
    $f.add_MouseDoubleClick({
        param($s, $e)
        if ($e.Button -ne 'Left' -or -not (Test-YRect $st)) { return }
        $ts = Get-YTextShapeAt $st $e.Location
        if (-not $ts) { return }
        $st.Drag = $null
        [void]$st.Shapes.Remove($ts)
        Invoke-YRefresh $f $st
        & $startText $ts.Points[0] $ts.Text $ts.Color $ts.Width
    })
    $tb.add_TextChanged({
        $sz = [System.Windows.Forms.TextRenderer]::MeasureText($tb.Text + 'WW', $tb.Font)
        $tb.Width = [Math]::Max([int](S 140), $sz.Width)
    })
    $tb.add_KeyDown({
        param($s, $e)
        if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; & $commitText }
        elseif ($e.KeyCode -eq 'Escape') { $e.SuppressKeyPress = $true; $tb.Visible = $false; $tb.Text = ''; [void]$f.Focus() }
    })

    $withDialog = {
        param([scriptblock]$body)
        $f.TopMost = $false
        try { & $body } finally { if (-not $st.Result) { $f.TopMost = $true; $f.Activate() } }
    }

    $doAction = {
        param([string]$id, $b)
        switch ($id) {
            { $_ -in 'pen', 'line', 'arrow', 'rect', 'marker', 'text' } {
                & $commitText
                $st.Tool = if ($st.Tool -eq $id) { $null } else { $id }
                $st.PaletteOpen = $false
            }
            'color' { $st.PaletteOpen = -not $st.PaletteOpen }
            'swatch' { $st.Color = $script:YPalette[$b.Index]; $st.PaletteOpen = $false }
            'width' { $st.WidthIndex = ($st.WidthIndex + 1) % $script:YWidths.Count }
            'undo' { if ($st.Shapes.Count) { $st.Shapes.RemoveAt($st.Shapes.Count - 1) } }
            'ocr' {
                & $commitText
                $st.Result = @{ Action = 'text'; Bitmap = (Get-YCrop $st) }
                $f.Close()
            }
            'copy' {
                & $commitText
                $img = Get-YCrop $st -WithShapes
                [System.Windows.Forms.Clipboard]::SetImage($img); $img.Dispose()
                $st.Result = @{ Action = 'done'; Message = 'Görüntü panoya kopyalandı.' }
                $f.Close()
            }
            'save' {
                & $commitText
                & $withDialog {
                    if (-not (Test-Path $SaveFolder)) { New-Item -ItemType Directory -Path $SaveFolder -Force | Out-Null }
                    $sd = New-Object System.Windows.Forms.SaveFileDialog
                    $sd.InitialDirectory = $SaveFolder
                    $sd.FileName = 'Gorix_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.png'
                    $sd.Filter = 'PNG (*.png)|*.png|JPEG (*.jpg)|*.jpg'
                    if ($sd.ShowDialog($f) -eq 'OK') {
                        $fmt = if ($sd.FileName -match '\.jpe?g$') { [System.Drawing.Imaging.ImageFormat]::Jpeg } else { [System.Drawing.Imaging.ImageFormat]::Png }
                        $img = Get-YCrop $st -WithShapes
                        try {
                            $img.Save($sd.FileName, $fmt)
                            [System.Windows.Forms.Clipboard]::SetImage($img)   # kaydedilen gorsel panoya da
                        }
                        finally { $img.Dispose() }
                        $st.Result = @{
                            Action  = 'done'
                            Message = 'Kaydedildi ve panoya kopyalandı: ' + [System.IO.Path]::GetFileName($sd.FileName)
                            SaveDir = [System.IO.Path]::GetDirectoryName($sd.FileName)   # son kayit klasoru hatirlansin
                        }
                        $f.Close()
                    }
                }
            }
            'print' {
                & $commitText
                & $withDialog {
                    $img = Get-YCrop $st -WithShapes
                    $doc = New-Object System.Drawing.Printing.PrintDocument
                    $doc.add_PrintPage({
                            param($s, $e)
                            $m = $e.MarginBounds
                            $k = [Math]::Min(1.0, [Math]::Min($m.Width / $img.Width, $m.Height / $img.Height))
                            $e.Graphics.DrawImage($img, $m.X, $m.Y, [int]($img.Width * $k), [int]($img.Height * $k))
                        })
                    $pd = New-Object System.Windows.Forms.PrintDialog
                    $pd.Document = $doc
                    if ($pd.ShowDialog($f) -eq 'OK') {
                        $doc.Print()
                        $st.Result = @{ Action = 'done'; Message = 'Yazıcıya gönderildi.' }
                        $f.Close()
                    }
                    $img.Dispose()
                }
            }
            'close' { $f.Close() }
            'droptool' { $st.Tool = $null }
            'monitor' { & $commitText; $st.Rect = (Get-YScreenAt $st.MenuPoint).Rect }
            'selectall' { & $commitText; $st.Rect = New-Object System.Drawing.Rectangle 0, 0, $st.Size.Width, $st.Size.Height }
            'clear' { & $commitText; $st.Rect = [System.Drawing.Rectangle]::Empty; $st.Shapes.Clear(); $st.Tool = $null }
        }
        Invoke-YRefresh $f $st
    }

    # Sag tik menusu
    $menu = New-Object System.Windows.Forms.ContextMenuStrip
    $menu.Renderer = New-Object Yakala.DarkRenderer
    $menu.Font = New-Object System.Drawing.Font $script:YF.Ctl, 10
    $menu.ImageScalingSize = New-Object System.Drawing.Size ([int](S 16)), ([int](S 16))
    $menuIcon = {
        param([string]$glyph)
        $sz = [int](S 16)
        $bm = New-Object System.Drawing.Bitmap $sz, $sz
        $mg = [System.Drawing.Graphics]::FromImage($bm)
        Draw-YGlyph $mg $glyph (New-Object System.Drawing.RectangleF 0, 0, $sz, $sz) $script:YT.Text (S 13)
        $mg.Dispose()
        $bm
    }
    $addItem = {
        param([string]$text, [string]$id, [string]$glyph, [string]$keys, [bool]$enabled = $true)
        $it = New-Object System.Windows.Forms.ToolStripMenuItem $text
        $it.Tag = $id
        if ($glyph) { $it.Image = & $menuIcon $glyph }
        if ($keys) { $it.ShortcutKeyDisplayString = $keys }
        $it.Enabled = $enabled
        $it.Padding = New-Object System.Windows.Forms.Padding 0, 3, 0, 3
        [void]$menu.Items.Add($it)
    }
    $showMenu = {
        param([System.Drawing.Point]$pt)
        foreach ($old in @($menu.Items)) { if ($old.Image) { $old.Image.Dispose() } }
        $menu.Items.Clear()
        $has = Test-YRect $st
        if ($st.Tool) { & $addItem 'Çizim aracını bırak' 'droptool' $null $null; [void]$menu.Items.Add('-') }
        & $addItem 'Kopyala' 'copy' $script:YG.Copy 'Ctrl+C' $has
        & $addItem 'Metni bul' 'ocr' $script:YG.Font 'T' $has
        & $addItem 'Kaydet...' 'save' $script:YG.Save 'Ctrl+S' $has
        & $addItem 'Yazdır...' 'print' $script:YG.Print 'Ctrl+P' $has
        [void]$menu.Items.Add('-')
        & $addItem ('Bu monitörü seç   ·   ' + (Get-YScreenAt $pt).Name) 'monitor' $script:YG.Monitor $null
        & $addItem 'Tüm ekranı seç' 'selectall' $script:YG.FullScreen 'Ctrl+A'
        & $addItem 'Seçimi temizle' 'clear' $script:YG.Clear $null $has
        [void]$menu.Items.Add('-')
        & $addItem 'İptal' 'close' $script:YG.Close 'Esc'
        $menu.Show($f, $pt)
    }
    # Eylem menu kapandiktan sonra calissin (kaydet penceresi vb. menunun ustune binmesin)
    $menu.add_ItemClicked({ param($s, $e) $st.Pending = $e.ClickedItem.Tag })
    $menu.add_Closed({
        $id = $st.Pending; $st.Pending = $null
        if ($id) { & $doAction $id $null }
    })

    $f.add_Shown({
        $f.Bounds = $vs; $f.Activate(); Invoke-YRefresh $f $st -Full
        if ($Options.OnShown) { & $Options.OnShown $st $f }   # yalnizca otomatik testler icin
    })
    $f.add_Paint({
        param($s, $e)
        if ($f.Mode -and $f.Mode -ne 'draw') { $st.Rect = $f.Sel }   # surukleme surerken secim C# tarafinda
        Draw-YOverlay $e.Graphics $st $e.ClipRectangle
    })

    $f.add_MouseDown({
        param($s, $e)
        $pt = $e.Location
        if ($e.Button -eq 'Right') {
            if ($st.Drag) { return }
            if ($tb.Visible) { & $commitText }
            $st.PaletteOpen = $false; $st.Hover = $null
            Invoke-YRefresh $f $st
            $st.MenuPoint = $pt
            & $showMenu $pt
            return
        }
        if ($e.Button -ne 'Left') { return }

        $b = Get-YButtonAt $st $pt
        if ($b) { & $doAction $b.Id $b; return }
        $wasTyping = $tb.Visible
        if ($wasTyping) { & $commitText }
        if ($st.PaletteOpen) { $st.PaletteOpen = $false; Invoke-YRefresh $f $st; return }

        # Metin cizimini surukleyerek tasi (arac secili degilken veya metin aracindayken)
        if ((Test-YRect $st) -and ($st.Tool -in @($null, 'text'))) {
            $ts = Get-YTextShapeAt $st $pt
            if ($ts) {
                $st.Drag = 'text'; $st.DragShape = $ts; $st.Start = $pt; $st.StartPos = $ts.Points[0]
                $f.Cursor = [System.Windows.Forms.Cursors]::SizeAll
                return
            }
        }
        if ($wasTyping) { return }

        if (Test-YRect $st) {
            if ($st.Tool) {
                if (-not $st.Rect.Contains($pt)) { return }
                if ($st.Tool -eq 'text') { & $startText $pt; return }
                # Sekil, fare birakilinca $st.Shapes'e eklenir (MouseUp)
                $st.Drag = 'draw'
                $f.BeginShape($st.Tool, $st.Color, [single]$script:YWidths[$st.WidthIndex], $pt)
                return
            }
            $h = Get-YHandleAt $st $pt
            if ($h) {
                $st.Drag = if ($h -eq 'move') { 'move' } else { 'resize' }
                Invoke-YRefresh $f $st; $f.Update()
                $f.BeginDrag($st.Drag, $pt, $h, ($null -eq $st.Tool))
                return
            }
        }
        $st.Shapes.Clear(); $st.Tool = $null
        $st.Drag = 'new'; $st.Rect = [System.Drawing.Rectangle]::Empty
        Invoke-YRefresh $f $st; $f.Update()
        $f.BeginDrag('new', $pt, $null, $false)
    })

    $f.add_MouseMove({
        param($s, $e)
        $pt = $e.Location
        # new / move / resize / draw suruklemeleri Yakala.CaptureForm icinde islenir, buraya gelmez
        switch ($st.Drag) {
            'text' {
                $st.DragShape.Points[0] = New-Object System.Drawing.Point ($st.StartPos.X + $pt.X - $st.Start.X), ($st.StartPos.Y + $pt.Y - $st.Start.Y)
                $dirty = $st.Rect; $dirty.Inflate(4, 4)
                $f.Invalidate($dirty); $f.Update(); return
            }
        }

        $b = Get-YButtonAt $st $pt
        $key = Get-YButtonKey $b
        if ($key -ne $st.Hover) { $st.Hover = $key; Invoke-YRefresh $f $st }

        $cur = [System.Windows.Forms.Cursors]::Cross
        if ($b) { $cur = [System.Windows.Forms.Cursors]::Hand }
        elseif ((Test-YRect $st) -and ($st.Tool -in @($null, 'text')) -and (Get-YTextShapeAt $st $pt)) { $cur = [System.Windows.Forms.Cursors]::SizeAll }
        elseif ((Test-YRect $st) -and $st.Tool) {
            if ($st.Rect.Contains($pt)) { $cur = if ($st.Tool -eq 'text') { [System.Windows.Forms.Cursors]::IBeam } else { [System.Windows.Forms.Cursors]::Cross } }
            else { $cur = [System.Windows.Forms.Cursors]::Default }
        }
        elseif (Test-YRect $st) {
            $cur = switch (Get-YHandleAt $st $pt) {
                { $_ -in 'nw', 'se' } { [System.Windows.Forms.Cursors]::SizeNWSE }
                { $_ -in 'ne', 'sw' } { [System.Windows.Forms.Cursors]::SizeNESW }
                { $_ -in 'n', 's' } { [System.Windows.Forms.Cursors]::SizeNS }
                { $_ -in 'e', 'w' } { [System.Windows.Forms.Cursors]::SizeWE }
                'move' { [System.Windows.Forms.Cursors]::SizeAll }
                default { [System.Windows.Forms.Cursors]::Cross }
            }
        }
        if ($f.Cursor -ne $cur) { $f.Cursor = $cur }
    })

    $f.add_MouseUp({
        param($s, $e)
        if ($e.Button -ne 'Left' -or -not $st.Drag) { return }
        $drag = $st.Drag
        $st.Drag = $null
        if ($drag -in 'new', 'move', 'resize') { $st.Rect = $f.Sel }
        if ($drag -eq 'new' -and -not (Test-YRect $st)) { $st.Rect = [System.Drawing.Rectangle]::Empty }
        if ($drag -eq 'draw') {
            $pts = New-Object System.Collections.Generic.List[System.Drawing.Point]
            foreach ($p in $f.Points) { $pts.Add($p) }
            $tooSmall = if ($f.ShapeType -in 'pen', 'marker') { $pts.Count -lt 2 } else { $pts[0] -eq $pts[1] }
            if (-not $tooSmall) { $st.Shapes.Add(@{ Type = $f.ShapeType; Points = $pts; Color = $f.ShapeColor; Width = $script:YWidths[$st.WidthIndex] }) }
        }
        # Hizli cizim ekrana dogrudan yazdi; son durumu tam olarak yeniden boya
        Invoke-YRefresh $f $st -Full
    })

    $f.add_KeyDown({
        param($s, $e)
        if ($tb.Visible) { return }
        if ($e.KeyCode -eq 'Escape') {
            if ($st.PaletteOpen) { $st.PaletteOpen = $false; Invoke-YRefresh $f $st } else { $f.Close() }
            return
        }
        if ($st.Drag) { return }
        if ($e.Control -and $e.KeyCode -eq 'A') { $e.SuppressKeyPress = $true; & $doAction 'selectall' $null; return }
        if (-not (Test-YRect $st)) { return }
        if ($e.Control) {
            $id = switch ($e.KeyCode) { 'Z' { 'undo' } 'C' { 'copy' } 'S' { 'save' } 'P' { 'print' } }
            if ($id) { $e.SuppressKeyPress = $true; & $doAction $id $null }
            return
        }
        if ($e.KeyCode -eq 'T') { & $doAction 'ocr' $null }
        elseif ($e.KeyCode -eq 'Enter') { & $doAction 'copy' $null }
    })

    try {
        [void]$f.ShowDialog()
        if ($Memory -and (Test-YRect $st)) {
            $r = $st.Rect
            $Memory.Rect = '{0},{1},{2},{3}' -f ($r.X + $vs.X), ($r.Y + $vs.Y), $r.Width, $r.Height
        }
        $st.Result
    }
    finally {
        foreach ($it in @($menu.Items)) { if ($it.Image) { $it.Image.Dispose() } }
        $menu.Dispose(); $f.Dispose(); $st.Measure.Dispose()
    }
}
