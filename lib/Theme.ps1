# Gorix - tema (renkler, fontlar, yuvarlak sekiller, ikonlar) ve cizim sekilleri

function New-YColor([int]$r, [int]$g, [int]$b, [int]$a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $g, $b) }

$script:YT = @{
    Panel       = New-YColor 30 30 34 245
    PanelSolid  = New-YColor 32 32 36
    Hover       = New-YColor 255 255 255 22
    Border      = New-YColor 255 255 255 30
    Text        = New-YColor 242 242 246
    Muted       = New-YColor 160 160 172
    Accent      = New-YColor 76 141 255
    AccentHover = New-YColor 104 160 255
    Green       = New-YColor 38 166 98
    GreenHover  = New-YColor 52 186 114
    Dim         = New-YColor 8 10 16 150
    Field       = New-YColor 22 22 26
    Warn        = New-YColor 242 170 40
    Error       = New-YColor 232 72 72
}

$installed = (New-Object System.Drawing.Text.InstalledFontCollection).Families.Name
$script:YF = @{
    Ui   = if ($installed -contains 'Segoe UI Variable Text') { 'Segoe UI Variable Text' } else { 'Segoe UI' }
    Semi = if ($installed -contains 'Segoe UI Variable Text Semibold') { 'Segoe UI Variable Text Semibold' } else { 'Segoe UI Semibold' }
    Icon = if ($installed -contains 'Segoe Fluent Icons') { 'Segoe Fluent Icons' } else { 'Segoe MDL2 Assets' }
    Mono = if ($installed -contains 'Cascadia Mono') { 'Cascadia Mono' } else { 'Consolas' }
    # Standart pencere kontrolleri (GDI) degisken fontu bozuk ciziyor; onlarda klasik Segoe UI
    Ctl     = 'Segoe UI'
    CtlSemi = 'Segoe UI Semibold'
}
Remove-Variable installed

# Ikon kodlari (Segoe Fluent Icons / MDL2)
$script:YG = @{
    Pen = [char]0xE70F; Marker = [char]0xE7E6; Rect = [char]0xE739; Font = [char]0xE8D2
    Undo = [char]0xE7A7; Copy = [char]0xE8C8; Save = [char]0xE74E; Print = [char]0xE749; Close = [char]0xE711
    Check = [char]0xE73E; Warn = [char]0xE7BA; Error = [char]0xE783
    Monitor = [char]0xE7F4; FullScreen = [char]0xE740; Clear = [char]0xE8E6
}

# Ekran olcegi (125% / 150% ekranlarda arayuz buyusun)
$script:YScale = [Math]::Max(1.0, [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero).DpiX / 96.0)
function S([double]$v) { [single]($v * $script:YScale) }

# Piksel birimli font (ekran olceginden bagimsiz, goruntuye ayni boyutta cizilir)
function New-YFont([double]$px, [string]$kind = 'Ui') {
    $style = if ($kind -eq 'Bold') { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $family = if ($kind -eq 'Bold') { $script:YF.Ui } else { $script:YF[$kind] }
    New-Object System.Drawing.Font $family, ([single]$px), $style, ([System.Drawing.GraphicsUnit]::Pixel)
}

function New-RoundPath([System.Drawing.RectangleF]$r, [single]$rad) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [Math]::Min($rad * 2, [Math]::Min($r.Width, $r.Height))
    if ($d -le 0) { $p.AddRectangle($r); return , $p }
    $p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    $p.AddArc($r.Right - $d, $r.Y, $d, $d, 270, 90)
    $p.AddArc($r.Right - $d, $r.Bottom - $d, $d, $d, 0, 90)
    $p.AddArc($r.X, $r.Bottom - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    , $p
}

function Draw-YRound($g, [System.Drawing.RectangleF]$r, [single]$rad, $fill, $border = $null) {
    $path = New-RoundPath $r $rad
    if ($fill) { $b = New-Object System.Drawing.SolidBrush $fill; $g.FillPath($b, $path); $b.Dispose() }
    if ($border) { $pen = New-Object System.Drawing.Pen $border, 1; $g.DrawPath($pen, $path); $pen.Dispose() }
    $path.Dispose()
}

# Yumusak golge (panellerin altina)
function Draw-YShadow($g, [System.Drawing.RectangleF]$r, [single]$rad) {
    for ($i = 1; $i -le 4; $i++) {
        $o = S ($i * 2)
        $sr = New-Object System.Drawing.RectangleF ($r.X - $o / 2), ($r.Y - $o / 2 + (S 2)), ($r.Width + $o), ($r.Height + $o)
        Draw-YRound $g $sr ($rad + $o / 2) (New-YColor 0 0 0 (34 - $i * 7))
    }
}

function Draw-YText($g, [string]$text, $font, $color, [System.Drawing.RectangleF]$r, [string]$align = 'Center') {
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = $align; $sf.LineAlignment = 'Center'
    $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    $sf.Trimming = 'EllipsisCharacter'
    $b = New-Object System.Drawing.SolidBrush $color
    $g.DrawString($text, $font, $b, $r, $sf)
    $b.Dispose(); $sf.Dispose()
}

function Draw-YGlyph($g, [string]$glyph, [System.Drawing.RectangleF]$r, $color, [double]$px) {
    $font = New-YFont $px 'Icon'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    Draw-YText $g $glyph $font $color $r
    $font.Dispose()
}

# Fontta karsiligi olmayan ikonlar (cizgi, ok, metin)
function Draw-YIcon($g, [string]$name, [System.Drawing.RectangleF]$r, $color) {
    $cx = $r.X + $r.Width / 2; $cy = $r.Y + $r.Height / 2; $k = (S 7)
    $pen = New-Object System.Drawing.Pen $color, (S 1.8)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    switch ($name) {
        'line' { $g.DrawLine($pen, $cx - $k, $cy + $k, $cx + $k, $cy - $k) }
        'arrow' {
            $g.DrawLine($pen, $cx - $k, $cy + $k, $cx + $k, $cy - $k)
            $g.DrawLine($pen, $cx + $k, $cy - $k, $cx + $k - (S 7), $cy - $k)
            $g.DrawLine($pen, $cx + $k, $cy - $k, $cx + $k, $cy - $k + (S 7))
        }
        'text' {
            $g.DrawLine($pen, $cx - $k, $cy - $k, $cx + $k, $cy - $k)
            $g.DrawLine($pen, $cx, $cy - $k, $cx, $cy + $k)
        }
    }
    $pen.Dispose()
}

# --- Cizim sekilleri (secim ekraninda kullanilir) ---
function Get-YTextFont($s) { New-YFont (12 + $s.Width * 3) 'Bold' }

function Write-YShape([System.Drawing.Graphics]$g, $s) {
    $p = $s.Points
    switch ($s.Type) {
        { $_ -in 'pen', 'marker' } {
            if ($p.Count -lt 2) { return }
            $c = if ($s.Type -eq 'marker') { [System.Drawing.Color]::FromArgb(110, $s.Color) } else { $s.Color }
            $w = if ($s.Type -eq 'marker') { $s.Width * 5 } else { $s.Width }
            $pen = New-Object System.Drawing.Pen $c, $w
            $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
            $g.DrawLines($pen, $p.ToArray())
            $pen.Dispose()
        }
        { $_ -in 'line', 'arrow' } {
            if ($p.Count -lt 2) { return }
            $pen = New-Object System.Drawing.Pen $s.Color, $s.Width
            $pen.StartCap = 'Round'
            if ($s.Type -eq 'arrow') { $pen.CustomEndCap = New-Object System.Drawing.Drawing2D.AdjustableArrowCap 4, 4 }
            else { $pen.EndCap = 'Round' }
            $g.DrawLine($pen, $p[0], $p[1])
            $pen.Dispose()
        }
        'rect' {
            if ($p.Count -lt 2) { return }
            $pen = New-Object System.Drawing.Pen $s.Color, $s.Width
            $pen.LineJoin = 'Round'
            $g.DrawRectangle($pen, (New-NormalizedRect $p[0] $p[1]))
            $pen.Dispose()
        }
        'text' {
            $font = Get-YTextFont $s
            $brush = New-Object System.Drawing.SolidBrush $s.Color
            $g.TextRenderingHint = 'AntiAliasGridFit'
            $g.DrawString($s.Text, $font, $brush, [single]$p[0].X, [single]$p[0].Y)
            $brush.Dispose(); $font.Dispose()
        }
    }
}

function New-NormalizedRect([System.Drawing.Point]$a, [System.Drawing.Point]$b) {
    New-Object System.Drawing.Rectangle ([Math]::Min($a.X, $b.X)), ([Math]::Min($a.Y, $b.Y)), ([Math]::Abs($a.X - $b.X)), ([Math]::Abs($a.Y - $b.Y))
}

function Set-DoubleBuffered($Control) {
    $Control.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'NonPublic,Instance').SetValue($Control, $true, $null)
}

# --- Uygulama simgesi: Gorix "G-mercek" (lacivert zemin, mavi secim koseleri, beyaz G, sari mercek sapi) ---
# 32x32 koordinatta cizer. 24px ve altinda koseler cikarilip G buyutulur (tepside net dursun).
function Draw-YAppIcon([System.Drawing.Graphics]$g, [int]$size) {
    $mkColor = { param($hex, $a = 255) [System.Drawing.Color]::FromArgb($a, [System.Drawing.ColorTranslator]::FromHtml($hex)) }
    $mkPen = { param($c, $w, $cap = 'Round') $p = New-Object System.Drawing.Pen $c, ([single]$w); $p.StartCap = $cap; $p.EndCap = $cap; $p.LineJoin = 'Round'; $p }
    $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'
    $bg = New-Object System.Drawing.SolidBrush (& $mkColor '#14213D')
    $path = New-RoundPath (New-Object System.Drawing.RectangleF 1, 1, 30, 30) 7.5
    $g.FillPath($bg, $path); $bg.Dispose(); $path.Dispose()

    $small = $size -le 24
    if ($small) { $cx = 14.2; $cy = 14.2; $r = 7.4; $sw = 4.6; $he = 27.2; $hw = 4.2 }
    else {
        $cx = 15; $cy = 15.2; $r = 6.2; $sw = 4; $he = 25.6; $hw = 3.6
        # Secim koseleri (sag alt kosede mercek sapi oldugu icin uc kose)
        $bp = & $mkPen (& $mkColor '#2F80ED') 2.4
        foreach ($pt in @(@(5, 10.5, 5, 5, 10.5, 5), @(21.5, 5, 27, 5, 27, 10.5), @(5, 21.5, 5, 27, 10.5, 27))) {
            $g.DrawLines($bp, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF $pt[0], $pt[1]), (New-Object System.Drawing.PointF $pt[2], $pt[3]), (New-Object System.Drawing.PointF $pt[4], $pt[5])))
        }
        $bp.Dispose()
    }
    # Mercek sapi: G'nin sag altindan kose yonune
    $hs = $cx + $r * 0.62
    $hp = & $mkPen (& $mkColor '#F5B82E') $hw
    $g.DrawLine($hp, [single]($cx + $r * 0.62), [single]($cy + $r * 0.62), [single]$he, [single]$he); $hp.Dispose()
    # G: sagda acik kalin yay + ortadan saga yatay kol
    $gp = & $mkPen ([System.Drawing.Color]::White) $sw 'Flat'
    $g.DrawArc($gp, [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r), [single]0, [single]318)
    $gp.Dispose()
    $wb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $g.FillRectangle($wb, [single]($cx + 0.2), [single]($cy - $sw / 2), [single]($r + $sw / 2 - 0.2), [single]$sw)
    $wb.Dispose()
}
function New-YAppIconBitmap([int]$size) {
    $b = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.ScaleTransform($size / 32.0, $size / 32.0)
    Draw-YAppIcon $g $size
    $g.Dispose()
    $b
}

# Cok boyutlu .ico dosyasi (32 bit DIB girdileri; Windows ve .NET her boyutu sorunsuz okur)
function Save-YAppIco([string]$path, [int[]]$sizes = @(16, 20, 24, 32, 40, 48, 64)) {
    $images = foreach ($s in $sizes) {
        $bmp = New-YAppIconBitmap $s
        $ms = New-Object System.IO.MemoryStream
        $w = New-Object System.IO.BinaryWriter $ms
        $w.Write([int]40); $w.Write([int]$s); $w.Write([int]($s * 2)); $w.Write([int16]1); $w.Write([int16]32)
        $w.Write([int]0); $w.Write([int]($s * $s * 4)); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0); $w.Write([int]0)
        for ($y = $s - 1; $y -ge 0; $y--) {
            for ($x = 0; $x -lt $s; $x++) { $c = $bmp.GetPixel($x, $y); $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A) }
        }
        $w.Write((New-Object byte[] ([int][Math]::Ceiling($s / 32.0) * 4 * $s)))   # AND maskesi (alfa kullanildigi icin bos)
        $w.Flush(); $bmp.Dispose()
        , $ms.ToArray()
    }
    $fs = [System.IO.File]::Create($path)
    try {
        $w = New-Object System.IO.BinaryWriter $fs
        $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $w.Write([byte]($sizes[$i] -band 255)); $w.Write([byte]($sizes[$i] -band 255)); $w.Write([byte]0); $w.Write([byte]0)
            $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$images[$i].Length); $w.Write([uint32]$offset)
            $offset += $images[$i].Length
        }
        foreach ($img in $images) { $w.Write($img) }
        $w.Flush()
    }
    finally { $fs.Dispose() }
}

# Uygulama simgesi (.ico yoksa uretilir). Size: istenen piksel boyutu
function Get-YAppIcon([int]$Size = 32) {
    $ico = Join-Path (Split-Path $PSScriptRoot) 'Gorix.ico'
    # Cizim kodu (bu dosya) degistiyse simge yeniden uretilir
    if (-not (Test-Path $ico) -or (Get-Item $PSCommandPath).LastWriteTime -gt (Get-Item $ico).LastWriteTime) { Save-YAppIco $ico }
    New-Object System.Drawing.Icon $ico, $Size, $Size
}

# Pencere/baslik cubugu ikonu: mavi yuvarlak kare uzerinde ikon (orn. ayarlar icin cark)
function New-YWindowIcon([string]$glyph) {
    $b = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($b)
    $g.SmoothingMode = 'AntiAlias'
    # Uygulama simgesiyle ayni lacivert zemin
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.Point 0, 0), (New-Object System.Drawing.Point 32, 32), (New-YColor 34 52 92), (New-YColor 14 23 48)
    $path = New-RoundPath (New-Object System.Drawing.RectangleF 1, 1, 30, 30) 8
    $g.FillPath($grad, $path)
    $font = New-Object System.Drawing.Font $script:YF.Icon, 18, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel)
    $g.TextRenderingHint = 'AntiAliasGridFit'
    Draw-YText $g $glyph $font ([System.Drawing.Color]::White) (New-Object System.Drawing.RectangleF 0, 1, 32, 32)
    $g.Dispose(); $grad.Dispose(); $path.Dispose(); $font.Dispose()
    [System.Drawing.Icon]::FromHandle($b.GetHicon())
}

# Standart pencere kontrolleri icin duz, koyu buton
function New-YButton([string]$text, [switch]$Primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = if ($Primary) { $script:YT.Accent } else { New-YColor 56 56 64 }
    $b.FlatAppearance.MouseOverBackColor = if ($Primary) { $script:YT.AccentHover } else { New-YColor 70 70 80 }
    $b.FlatAppearance.MouseDownBackColor = $b.BackColor
    $b.ForeColor = $script:YT.Text
    $b.Font = New-Object System.Drawing.Font $script:YF.Ctl, 9.5
    $b.AutoSize = $true
    $b.Height = 34
    $b.Padding = New-Object System.Windows.Forms.Padding 12, 2, 12, 2
    $b.Margin = New-Object System.Windows.Forms.Padding 6, 0, 0, 0
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b
}
