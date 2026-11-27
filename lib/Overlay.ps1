# Gorix - secim ekrani: alan sec, yerinde ciz, kopyala / kaydet / yazdir veya metni oku
# Donus: @{ Action = 'text'; Bitmap = <kirpilmis> } | @{ Action = 'done'; Message = '...' } | $null

$script:YPalette = @(
    (New-YColor 239 68 68), (New-YColor 249 115 22), (New-YColor 250 204 21), (New-YColor 34 197 94),
    (New-YColor 59 130 246), (New-YColor 168 85 247), (New-YColor 255 255 255), (New-YColor 17 17 17)
)
$script:YWidths = @(2, 4, 7)

# $Form: Yakala.CaptureForm (ekran goruntusunu ve hizli cizimi o tutar, bkz. FastCanvas.ps1)
function New-YOverlayState($Form) {
    $mg = [System.Drawing.Graphics]::FromImage((New-Object System.Drawing.Bitmap 1, 1))
    $mg.TextRenderingHint = 'AntiAliasGridFit'
    @{
        Source = $Form; Size = (New-Object System.Drawing.Size $Form.W, $Form.H); Rect = [System.Drawing.Rectangle]::Empty
        Drag = $null; Start = [System.Drawing.Point]::Empty; StartRect = [System.Drawing.Rectangle]::Empty; Handle = $null
        Tool = $null; Color = $script:YPalette[0]; WidthIndex = 1; Shapes = New-Object System.Collections.Generic.List[object]; Current = $null
        PaletteOpen = $false; Hover = $null; Buttons = @(); Panels = @(); Seps = @(); ToolsVisible = $false
        TipRect = [System.Drawing.RectangleF]::Empty; LastBounds = [System.Drawing.Rectangle]::Empty
        Measure = $mg; Result = $null
    }
}

function Test-YRect($st) { $st.Rect.Width -ge 5 -and $st.Rect.Height -ge 5 }

function Get-YCrop($st, [switch]$WithShapes) {
    $r = $st.Rect
    $out = $st.Source.Crop($r)
    if ($WithShapes) {
        $g = [System.Drawing.Graphics]::FromImage($out)
        $g.SmoothingMode = 'AntiAlias'
        $g.TranslateTransform(-$r.X, -$r.Y)
        foreach ($s in $st.Shapes) { Write-YShape $g $s }
        $g.Dispose()
    }
    $out
}

# --- Yerlesim: arac cubugu, alt cubuk, renk paleti ---
function Update-YLayout($st) {
    $buttons = New-Object System.Collections.Generic.List[object]
    $panels = New-Object System.Collections.Generic.List[object]
    $seps = New-Object System.Collections.Generic.List[object]
    $st.ToolsVisible = (Test-YRect $st) -and ($st.Drag -notin 'new', 'move', 'resize')
    $st.Buttons = $buttons; $st.Panels = $panels; $st.Seps = $seps
    if (-not $st.ToolsVisible -or $st.ShowToolbar -eq $false) { return }

    $r = $st.Rect; $W = $st.Size.Width; $H = $st.Size.Height
    $bs = S 36; $gap = S 2; $pad = S 6; $m = S 10; $sep = S 9; $edge = S 6

    # Dikey arac cubugu
    $tools = @(
        @{ Id = 'pen'; Glyph = $script:YG.Pen; Tip = 'Kalem' }
        @{ Id = 'line'; Icon = 'line'; Tip = 'Çizgi' }
        @{ Id = 'arrow'; Icon = 'arrow'; Tip = 'Ok' }
        @{ Id = 'rect'; Glyph = $script:YG.Rect; Tip = 'Dikdörtgen' }
        @{ Id = 'marker'; Glyph = $script:YG.Marker; Tip = 'Marker' }
        @{ Id = 'text'; Icon = 'text'; Tip = 'Metin' }
        'sep'
        @{ Id = 'color'; Tip = 'Renk' }
        @{ Id = 'width'; Tip = 'Kalınlık' }
        'sep'
        @{ Id = 'undo'; Glyph = $script:YG.Undo; Tip = 'Geri al   Ctrl+Z' }
    )
    $n = @($tools | Where-Object { $_ -is [hashtable] }).Count
    $ns = @($tools | Where-Object { $_ -is [string] }).Count
    $tw = $bs + 2 * $pad
    $th = 2 * $pad + $n * $bs + ($n - 1) * $gap + $ns * $sep
    # Arac cubugu secimin bulundugu monitorde kalsin (yan monitore tasmasin)
    $mon = (Get-YScreenAt (New-Object System.Drawing.Point ($r.X + $r.Width / 2), ($r.Y + $r.Height / 2))).Rect
    $mL = [Math]::Max(0, $mon.Left) + $edge; $mR = [Math]::Min($W, $mon.Right) - $edge
    $mT = [Math]::Max(0, $mon.Top) + $edge; $mB = [Math]::Min($H, $mon.Bottom) - $edge
    # Secimin sag altinda: disarida sag kenara, alt kenarla hizali. Sagda yer yoksa sol, o da yoksa icerde sag alt kose.
    $inside = $false
    $tx = $r.Right + $m
    if ($tx + $tw -gt $mR) { $tx = $r.Left - $m - $tw }
    if ($tx -lt $mL) { $tx = [Math]::Min($r.Right, $mR) - $m - $tw; $inside = $true }
    $bottom = [Math]::Min($r.Bottom, $mB + $edge)
    $ty = if ($inside) { $bottom - $m - $th } else { $bottom - $th }
    $ty = [Math]::Max($mT, [Math]::Min($ty, $mB - $th))
    $toolbar = New-Object System.Drawing.RectangleF $tx, $ty, $tw, $th
    $panels.Add($toolbar)
    $y = $ty + $pad
    foreach ($t in $tools) {
        if ($t -is [string]) {
            $seps.Add(@(($tx + $pad + (S 6)), ($y + ($sep - $gap) / 2 - (S 1)), ($tx + $tw - $pad - (S 6))))
            $y += $sep; continue
        }
        $b = $t.Clone(); $b.Group = 'tool'
        $b.Rect = New-Object System.Drawing.RectangleF ($tx + $pad), $y, $bs, $bs
        $buttons.Add($b)
        $y += $bs + $gap
    }

    # Kopyala / kaydet / yazdir / metin okuma sag tik menusunde (OverlayForm.ps1)

    # Renk paleti
    if ($st.PaletteOpen) {
        $cb = $buttons | Where-Object { $_.Id -eq 'color' } | Select-Object -First 1
        $sw = S 26; $sg = S 6; $sp = S 8
        $pw = 2 * $sp + $script:YPalette.Count * $sw + ($script:YPalette.Count - 1) * $sg
        $ph = $sw + 2 * $sp
        # Once arac cubugunun dis tarafina (secimden uzaga) ac, sigmazsa ic tarafa
        $px = if ($toolbar.X -ge $r.Right) { $toolbar.Right + (S 8) } else { $toolbar.X - (S 8) - $pw }
        if ($px + $pw -gt $mR) { $px = $toolbar.X - (S 8) - $pw }
        if ($px -lt $mL) { $px = $toolbar.Right + (S 8) }
        $py = $cb.Rect.Y + $cb.Rect.Height / 2 - $ph / 2
        $panels.Add((New-Object System.Drawing.RectangleF $px, $py, $pw, $ph))
        for ($i = 0; $i -lt $script:YPalette.Count; $i++) {
            $buttons.Add(@{ Id = 'swatch'; Index = $i; Group = 'swatch'; Rect = (New-Object System.Drawing.RectangleF ($px + $sp + $i * ($sw + $sg)), ($py + $sp), $sw, $sw) })
        }
    }
}

function Get-YButtonAt($st, [System.Drawing.Point]$pt) {
    if (-not $st.ToolsVisible) { return $null }
    for ($i = $st.Buttons.Count - 1; $i -ge 0; $i--) { if ($st.Buttons[$i].Rect.Contains([single]$pt.X, [single]$pt.Y)) { return $st.Buttons[$i] } }
    $null
}

function Get-YButtonKey($b) { if ($null -eq $b) { $null } elseif ($b.Id -eq 'swatch') { "swatch$($b.Index)" } else { $b.Id } }

function Get-YHandleAt($st, [System.Drawing.Point]$pt) {
    if (-not (Test-YRect $st)) { return $null }
    $r = $st.Rect; $t = S 7
    $left = [Math]::Abs($pt.X - $r.Left) -le $t; $right = [Math]::Abs($pt.X - $r.Right) -le $t
    $top = [Math]::Abs($pt.Y - $r.Top) -le $t; $bottom = [Math]::Abs($pt.Y - $r.Bottom) -le $t
    $inX = $pt.X -ge $r.Left - $t -and $pt.X -le $r.Right + $t
    $inY = $pt.Y -ge $r.Top - $t -and $pt.Y -le $r.Bottom + $t
    if ($top -and $left) { return 'nw' }; if ($top -and $right) { return 'ne' }
    if ($bottom -and $left) { return 'sw' }; if ($bottom -and $right) { return 'se' }
    if ($top -and $inX) { return 'n' }; if ($bottom -and $inX) { return 's' }
    if ($left -and $inY) { return 'w' }; if ($right -and $inY) { return 'e' }
    if ($r.Contains($pt)) { return 'move' }
    $null
}

# Yeniden cizilmesi gereken alan (buyuk ekranlarda akici olsun diye)
function Get-YUiBounds($st) {
    if (-not (Test-YRect $st)) { return New-Object System.Drawing.Rectangle ([int]($st.Size.Width / 2 - (S 300))), 0, ([int](S 600)), ([int](S 90)) }
    $b = $st.Rect
    $b.Inflate([int](S 14), [int](S 14))
    $b = [System.Drawing.Rectangle]::Union($b, (New-Object System.Drawing.Rectangle $st.Rect.X, ([int]($st.Rect.Y - (S 40))), ([int](S 320)), ([int](S 42))))
    foreach ($p in $st.Panels) {
        $pr = [System.Drawing.Rectangle]::Ceiling($p); $pr.Inflate([int](S 14), [int](S 14))
        $b = [System.Drawing.Rectangle]::Union($b, $pr)
    }
    # Ipucu, uzerine gelinen butonun yaninda cikar
    $hb = $st.Buttons | Where-Object { (Get-YButtonKey $_) -eq $st.Hover } | Select-Object -First 1
    if ($hb) {
        $tr = [System.Drawing.Rectangle]::Ceiling($hb.Rect); $tr.Inflate([int](S 300), [int](S 60))
        $b = [System.Drawing.Rectangle]::Union($b, $tr)
    }
    $b
}

function Invoke-YRefresh($form, $st, [switch]$Full) {
    $form.Sel = $st.Rect   # arka plan (karartma / secili alan) C# tarafinda cizilir
    Update-YLayout $st
    if ($Full) { $form.Invalidate(); $st.LastBounds = Get-YUiBounds $st; return }
    $now = Get-YUiBounds $st
    $form.Invalidate([System.Drawing.Rectangle]::Union($st.LastBounds, $now))
    $st.LastBounds = $now
}

# --- Cizim ---
function Draw-YOverlay($g, $st, [System.Drawing.Rectangle]$clip) {
    # Arka plan (karartilmis goruntu + secili alan) Yakala.CaptureForm.OnPaint'te cizildi
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $r = $st.Rect

    if (-not (Test-YRect $st) -and $st.Drag -ne 'new') {
        $hint = 'Alanı seçmek için sürükle      Sağ tık  menü      Esc  iptal'
        $f = New-YFont (S 14) 'Semi'
        $sz = $g.MeasureString($hint, $f)
        $hr = New-Object System.Drawing.RectangleF (($st.Size.Width - $sz.Width) / 2 - (S 20)), (S 24), ($sz.Width + (S 40)), (S 44)
        Draw-YShadow $g $hr (S 22)
        Draw-YRound $g $hr (S 22) $script:YT.Panel $script:YT.Border
        Draw-YText $g $hint $f $script:YT.Text $hr
        $f.Dispose()
        return
    }
    if ($r.Width -le 0 -or $r.Height -le 0) { return }

    # Secili alandaki cizimler
    $state = $g.Save()
    $g.SetClip($r, [System.Drawing.Drawing2D.CombineMode]::Intersect)
    foreach ($s in $st.Shapes) { Write-YShape $g $s }
    $g.Restore($state)

    $pen = New-Object System.Drawing.Pen $script:YT.Accent, (S 1.5)
    $g.DrawRectangle($pen, $r.X, $r.Y, $r.Width - 1, $r.Height - 1)
    if ($null -eq $st.Tool -and $st.Drag -ne 'new') {
        $hr = S 4.5
        $hx = @($r.Left, ($r.Left + $r.Width / 2), $r.Right); $hy = @($r.Top, ($r.Top + $r.Height / 2), $r.Bottom)
        foreach ($ix in 0..2) {
            foreach ($iy in 0..2) {
                if ($ix -eq 1 -and $iy -eq 1) { continue }
                $g.FillEllipse([System.Drawing.Brushes]::White, $hx[$ix] - $hr, $hy[$iy] - $hr, 2 * $hr, 2 * $hr)
                $g.DrawEllipse($pen, $hx[$ix] - $hr, $hy[$iy] - $hr, 2 * $hr, 2 * $hr)
            }
        }
    }
    $pen.Dispose()

    # Boyut etiketi
    $f = New-YFont (S 12) 'Semi'
    $label = "$($r.Width) × $($r.Height)"
    if ($st.ToolsVisible) { $label += '     Sağ tık: menü' }
    $lw = $g.MeasureString($label, $f).Width + (S 16)
    $ly = if ($r.Top -ge (S 34)) { $r.Top - (S 32) } else { $r.Top + (S 8) }
    $lr = New-Object System.Drawing.RectangleF ($r.Left + ($(if ($r.Top -ge (S 34)) { 0 } else { S 8 }))), $ly, $lw, (S 24)
    Draw-YRound $g $lr (S 12) $script:YT.Panel
    Draw-YText $g $label $f $script:YT.Text $lr
    $f.Dispose()

    $st.TipRect = [System.Drawing.RectangleF]::Empty
    if (-not $st.ToolsVisible) { return }

    foreach ($p in $st.Panels) {
        Draw-YShadow $g $p (S 12)
        Draw-YRound $g $p (S 12) $script:YT.Panel $script:YT.Border
    }
    $sepPen = New-Object System.Drawing.Pen $script:YT.Border, 1
    foreach ($s in $st.Seps) {
        if ($s.Count -eq 4) { $g.DrawLine($sepPen, $s[0], $s[1], $s[0], $s[2]) } else { $g.DrawLine($sepPen, $s[0], $s[1], $s[2], $s[1]) }
    }
    $sepPen.Dispose()

    $fLabel = New-YFont (S 13) 'Semi'; $fKey = New-YFont (S 11)
    $hoverKey = $st.Hover
    foreach ($b in $st.Buttons) {
        $br = $b.Rect
        $isHover = (Get-YButtonKey $b) -eq $hoverKey
        $inner = New-Object System.Drawing.RectangleF ($br.X + (S 2)), ($br.Y + (S 2)), ($br.Width - (S 4)), ($br.Height - (S 4))
        switch ($b.Group) {
            'swatch' {
                $c = $script:YPalette[$b.Index]
                $cb = New-Object System.Drawing.SolidBrush $c
                $g.FillEllipse($cb, $inner); $cb.Dispose()
                $ring = New-Object System.Drawing.Pen (New-YColor 255 255 255 70), 1
                $g.DrawEllipse($ring, $inner); $ring.Dispose()
                if ($c.ToArgb() -eq $st.Color.ToArgb() -or $isHover) {
                    $sel = New-Object System.Drawing.Pen $script:YT.Text, (S 2)
                    $g.DrawEllipse($sel, $br.X - (S 1), $br.Y - (S 1), $br.Width + (S 2), $br.Height + (S 2)); $sel.Dispose()
                }
            }
            default {
                $active = ($b.Id -eq $st.Tool) -or ($b.Id -eq 'color' -and $st.PaletteOpen)
                if ($active) { Draw-YRound $g $inner (S 8) $script:YT.Accent }
                elseif ($isHover) { Draw-YRound $g $inner (S 8) $script:YT.Hover }
                $fg = $script:YT.Text
                if ($b.Id -eq 'color') {
                    $d = S 18
                    $cb = New-Object System.Drawing.SolidBrush $st.Color
                    $g.FillEllipse($cb, $br.X + ($br.Width - $d) / 2, $br.Y + ($br.Height - $d) / 2, $d, $d); $cb.Dispose()
                    $ring = New-Object System.Drawing.Pen (New-YColor 255 255 255 120), (S 1.5)
                    $g.DrawEllipse($ring, $br.X + ($br.Width - $d) / 2, $br.Y + ($br.Height - $d) / 2, $d, $d); $ring.Dispose()
                }
                elseif ($b.Id -eq 'width') {
                    $d = S (3 + $script:YWidths[$st.WidthIndex] * 1.6)
                    $wb = New-Object System.Drawing.SolidBrush $fg
                    $g.FillEllipse($wb, $br.X + ($br.Width - $d) / 2, $br.Y + ($br.Height - $d) / 2, $d, $d); $wb.Dispose()
                }
                elseif ($b.Icon) { Draw-YIcon $g $b.Icon $br $fg }
                else { Draw-YGlyph $g $b.Glyph $br $fg (S 16) }
            }
        }
    }

    # Ipucu
    $hb = $st.Buttons | Where-Object { (Get-YButtonKey $_) -eq $hoverKey -and $_.Tip } | Select-Object -First 1
    if ($hb -and $st.Drag -ne 'draw') {
        $tw = $g.MeasureString($hb.Tip, $fKey).Width + (S 16); $tht = S 26
        $br = $hb.Rect
        if ($hb.Group -eq 'tool') {
            $tx = if ($br.X -gt $r.Right) { $br.Right + (S 14) } else { $br.X - (S 14) - $tw }
            if ($tx + $tw -gt $st.Size.Width -or $tx -lt 0) { $tx = if ($tx -lt 0) { $br.Right + (S 14) } else { $br.X - (S 14) - $tw } }
            $ty = $br.Y + ($br.Height - $tht) / 2
        }
        else {
            $tx = [Math]::Max(0, [Math]::Min($br.X + ($br.Width - $tw) / 2, $st.Size.Width - $tw))
            $ty = if ($br.Bottom + (S 12) + $tht -lt $st.Size.Height) { $br.Bottom + (S 12) } else { $br.Y - (S 12) - $tht }
        }
        $st.TipRect = New-Object System.Drawing.RectangleF $tx, $ty, $tw, $tht
        Draw-YRound $g $st.TipRect (S 6) (New-YColor 12 12 14 235)
        Draw-YText $g $hb.Tip $fKey $script:YT.Text $st.TipRect
    }
    $fLabel.Dispose(); $fKey.Dispose()
}
