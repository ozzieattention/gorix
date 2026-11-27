# Gorix - Windows OCR (Windows.Media.Ocr). Tamamen yerel calisir, internete cikmaz.
#
# Dogruluk icin yapilanlar (11-18px, acik/gri/koyu tema test setinde ortalama %95,6 -> %98,1):
#  1) Goruntu kenar boslugu eklenip 2x buyutulur. Yazi boyutuna gore uyarlamali olcek denendi, 2x'ten iyi degildi.
#  2) 'auto' modunda TR ve EN motoru birlikte calisir; kelime bazinda Turkce harf iceren icin TR,
#     digerleri (kod, ID, sembol) icin EN sonucu alinir. TR motoru '=' -> 'z', '_' kaybi gibi hatalar yapiyor.
#  3) Bilinen karakter karisikliklari duzeltilir: Ox -> 0x, lD -> ID, rakam agirlikli kelimelerde O -> 0, l/I -> 1,
#     pansiyon kodunda Al -> AI.
Add-Type -AssemblyName System.Runtime.WindowsRuntime

$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics, ContentType = WindowsRuntime]

$script:AsTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
} | Select-Object -First 1

$script:YOcrEngines = @{}
$script:YTurkishChars = '[çğıöşüÇĞİÖŞÜ]'
$script:YOddChars = '[^\x00-\x7FçğıöşüÇĞİÖŞÜ]'

function Wait-WinRT($Operation, [Type]$ResultType) {
    $task = $script:AsTaskGeneric.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    $null = $task.Wait(-1)
    $task.Result
}

# 'auto' = TR + EN birlikte (TR ve en az bir Ingilizce motor kuruluysa)
function Get-OcrLanguages {
    $tags = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag })
    if (($tags -contains 'tr') -and ($tags | Where-Object { $_ -like 'en*' })) { $tags = @('auto') + $tags }
    $tags
}

function Get-OcrLanguageName([string]$tag) {
    switch ($tag) {
        'auto' { 'Türkçe' }   # TR motoru + ozel karakterler icin EN destegi
        'tr' { 'Türkçe (yalnız TR motoru)' }
        'en-US' { 'İngilizce' }
        'en-GB' { 'İngilizce (UK)' }
        default { $tag }
    }
}

function Get-YOcrEngine([string]$tag) {
    if (-not $script:YOcrEngines.ContainsKey($tag)) {
        $e = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage([Windows.Globalization.Language]::new($tag))
        if ($null -eq $e) { throw "OCR motoru olusturulamadi ($tag)." }
        $script:YOcrEngines[$tag] = $e
    }
    $script:YOcrEngines[$tag]
}

# Kenarlara arka plan rengiyle bosluk ekleyip olcekler (kenara yapisik yazi da okunsun)
function New-YOcrImage([System.Drawing.Bitmap]$src, [double]$k, [int]$pad = 8) {
    $max = [Windows.Media.Ocr.OcrEngine]::MaxImageDimension
    while ($k -gt 1 -and ((($src.Width + 2 * $pad) * $k) -gt $max -or (($src.Height + 2 * $pad) * $k) -gt $max)) { $k -= 0.5 }
    $bg = $src.GetPixel(0, 0)
    $w = [int](($src.Width + 2 * $pad) * $k); $h = [int](($src.Height + 2 * $pad) * $k)
    $out = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.Clear($bg)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $dest = New-Object System.Drawing.Rectangle ([int]($pad * $k)), ([int]($pad * $k)), ([int]($src.Width * $k)), ([int]($src.Height * $k))
    $g.DrawImage($src, $dest, 0, 0, $src.Width, $src.Height, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    @{ Bitmap = $out; Scale = $k }
}

function Invoke-YOcrEngine([System.Drawing.Bitmap]$bmp, [string]$tag) {
    $engine = Get-YOcrEngine $tag
    $ms = New-Object System.IO.MemoryStream
    try {
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $null = $ms.Seek(0, [System.IO.SeekOrigin]::Begin)
        $stream = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($ms)
        $decoder = Wait-WinRT ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $soft = Wait-WinRT ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $result = Wait-WinRT ($engine.RecognizeAsync($soft)) ([Windows.Media.Ocr.OcrResult])
        $soft.Dispose()
        # Kelimeleri konumlariyla dondur
        $words = New-Object System.Collections.Generic.List[object]
        foreach ($line in $result.Lines) {
            foreach ($w in $line.Words) {
                $r = $w.BoundingRect
                $words.Add(@{ Text = $w.Text; X = $r.X; Y = $r.Y; W = $r.Width; H = $r.Height; Src = $tag })
            }
        }
        , $words
    }
    finally { $ms.Dispose() }
}

# Iki motorun kelimelerini konuma gore eslestirip birlestirir, satir satir metin dondurur
function Merge-YOcrWords($primary, $secondary) {
    $all = New-Object System.Collections.Generic.List[object]
    foreach ($w in $primary) { $all.Add($w) }
    foreach ($w in $secondary) { $all.Add($w) }
    $n = $all.Count
    if ($n -eq 0) { return '' }
    $parent = 0..($n - 1)
    $find = { param($i) while ($parent[$i] -ne $i) { $parent[$i] = $parent[$parent[$i]]; $i = $parent[$i] }; $i }
    for ($i = 0; $i -lt $primary.Count; $i++) {
        $a = $all[$i]
        for ($j = $primary.Count; $j -lt $n; $j++) {
            $b = $all[$j]
            $ix = [Math]::Min($a.X + $a.W, $b.X + $b.W) - [Math]::Max($a.X, $b.X)
            $iy = [Math]::Min($a.Y + $a.H, $b.Y + $b.H) - [Math]::Max($a.Y, $b.Y)
            if ($ix -le 0 -or $iy -le 0) { continue }
            # Kucuk olanin yarisindan fazlasi ortusuyorsa ayni kelime grubu
            if ($ix * $iy -ge 0.5 * [Math]::Min($a.W * $a.H, $b.W * $b.H)) {
                $ra = & $find $i; $rb = & $find $j
                if ($ra -ne $rb) { $parent[$rb] = $ra }
            }
        }
    }
    $groups = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $r = & $find $i
        if (-not $groups.ContainsKey($r)) { $groups[$r] = New-Object System.Collections.Generic.List[object] }
        $groups[$r].Add($all[$i])
    }
    $clusters = foreach ($grp in $groups.Values) {
        $p = @($grp | Where-Object { $_.Src -eq $primary[0].Src } | Sort-Object { $_.X })
        $s = @($grp | Where-Object { $_.Src -ne $primary[0].Src } | Sort-Object { $_.X })
        $pt = ($p | ForEach-Object { $_.Text }) -join ' '
        $stx = ($s | ForEach-Object { $_.Text }) -join ' '
        # -cmatch: Turkce kulturde buyuk/kucuk harf duyarsiz eslesme 'I' ile 'ı'yi esit sayiyor
        # EN sonucunda Turkce/ASCII disi harf (orn. Æ, é) varsa EN yanlis okumustur, TR'yi al
        $text = if ($pt -cmatch $script:YTurkishChars) { $pt }
        elseif ($stx -cmatch $script:YTurkishChars) { $stx }
        elseif ($pt -and $stx -cmatch $script:YOddChars -and $pt -cnotmatch $script:YOddChars) { $pt }
        elseif ($stx) { $stx } else { $pt }
        $x1 = ($grp | ForEach-Object { $_.X } | Measure-Object -Minimum).Minimum
        $x2 = ($grp | ForEach-Object { $_.X + $_.W } | Measure-Object -Maximum).Maximum
        $y1 = ($grp | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum
        $y2 = ($grp | ForEach-Object { $_.Y + $_.H } | Measure-Object -Maximum).Maximum
        @{ Text = $text; X = $x1; X2 = $x2; Y = $y1; Y2 = $y2 }
    }
    Join-YOcrLines $clusters
}

# Kelime kutularini satirlara dizer
function Join-YOcrLines($items) {
    $lines = New-Object System.Collections.Generic.List[object]
    foreach ($c in ($items | Sort-Object { ($_.Y + $_.Y2) / 2 })) {
        $placed = $false
        foreach ($l in $lines) {
            $ov = [Math]::Min($l.Y2, $c.Y2) - [Math]::Max($l.Y, $c.Y)
            if ($ov -ge 0.5 * [Math]::Min($l.Y2 - $l.Y, $c.Y2 - $c.Y)) {
                $l.Items.Add($c); $l.Y = [Math]::Min($l.Y, $c.Y); $l.Y2 = [Math]::Max($l.Y2, $c.Y2); $placed = $true; break
            }
        }
        if (-not $placed) {
            $nl = @{ Y = $c.Y; Y2 = $c.Y2; Items = (New-Object System.Collections.Generic.List[object]) }
            $nl.Items.Add($c); $lines.Add($nl)
        }
    }
    # Yan yana sutunlar (orn. menu + icerik) ayni satira yapismasin: buyuk yatay boslukta satiri bol
    $segments = foreach ($l in $lines) {
        $gapLimit = 2.5 * ($l.Y2 - $l.Y)
        $seg = $null
        foreach ($it in ($l.Items | Sort-Object { $_.X })) {
            if ($null -ne $seg -and ($it.X - $seg.X2) -gt $gapLimit) { $seg; $seg = $null }
            if ($null -eq $seg) { $seg = @{ Y = $l.Y; X = $it.X; X2 = $it.X2; Texts = (New-Object System.Collections.Generic.List[string]) } }
            $seg.Texts.Add($it.Text); $seg.X2 = [Math]::Max($seg.X2, $it.X2)
        }
        if ($seg) { $seg }
    }
    ($segments | Sort-Object { $_.Y }, { $_.X } | ForEach-Object { $_.Texts -join ' ' }) -join "`r`n"
}

# Bilinen karakter karisikliklarini duzeltir
function Repair-YOcrText([string]$text) {
    $text = [regex]::Replace($text, '(?<![A-Za-z0-9])[Oo][xX](?=[0-9A-Fa-f]{2})', '0x')        # Ox7F -> 0x7F
    $text = [regex]::Replace($text, '(?<=[a-z])lD(?![A-Za-z])', 'ID')                           # MessagelD -> MessageID
    $text = [regex]::Replace($text, '(?<=\d[.,])[Oo]{1,3}(?![A-Za-z])', { param($m) '0' * $m.Value.Length })  # 1.250,OO -> 1.250,00
    $text = [regex]::Replace($text, '(?<=\b(?:pansiyon|board|meal)\s*:?\s*)(U?)Al\b', '$1AI', 'IgnoreCase, CultureInvariant')  # Pansiyon: Al -> AI
    # Rakam agirlikli kelimelerde O -> 0, l/I/| -> 1 (orn. 1O234 -> 10234)
    [regex]::Replace($text, '[0-9A-Za-z|]+', {
            param($m)
            $w = $m.Value
            $digits = ([regex]::Matches($w, '[0-9]')).Count
            $letters = ([regex]::Matches($w, '[A-Za-z|]')).Count
            if ($digits -ge 2 -and $digits -gt $letters -and $w -match '[OolI|]') {
                $w = $w -creplace '[Oo]', '0' -creplace '[lI|]', '1'
            }
            $w
        })
}

# Bitmap icindeki metni dondurur (satirlar korunur). Bulamazsa bos string.
# LanguageTag: 'auto' (TR+EN) veya tek bir motor ('tr', 'en-US'...). ForceScale > 0 ise sabit olcek.
function Convert-BitmapToText([System.Drawing.Bitmap]$Bitmap, [string]$LanguageTag = 'auto', [double]$ForceScale = 0, [switch]$NoRepair) {
    $available = @([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages | ForEach-Object { $_.LanguageTag })
    if ($LanguageTag -eq 'auto') {
        $primary = if ($available -contains 'tr') { 'tr' } else { $available[0] }
        $secondary = @($available | Where-Object { $_ -like 'en*' -and $_ -ne $primary }) | Select-Object -First 1
    }
    else {
        $primary = if ($available -contains $LanguageTag) { $LanguageTag } else { $available[0] }
        $secondary = $null
    }

    $k = if ($ForceScale -gt 0) { $ForceScale } else { 2 }
    $img = New-YOcrImage $Bitmap $k
    try {
        $pw = Invoke-YOcrEngine $img.Bitmap $primary
        if ($secondary) {
            $sw = Invoke-YOcrEngine $img.Bitmap $secondary
            $text = if ($pw.Count -eq 0 -and $sw.Count -eq 0) { '' } elseif ($pw.Count -eq 0) { Join-YOcrLines (Convert-YWordsToItems $sw) } else { Merge-YOcrWords $pw $sw }
        }
        else { $text = Join-YOcrLines (Convert-YWordsToItems $pw) }
    }
    finally { $img.Bitmap.Dispose() }

    if ($NoRepair -or -not $text) { return $text }
    Repair-YOcrText $text
}

function Convert-YWordsToItems($words) {
    foreach ($w in $words) { @{ Text = $w.Text; X = $w.X; X2 = $w.X + $w.W; Y = $w.Y; Y2 = $w.Y + $w.H } }
}
