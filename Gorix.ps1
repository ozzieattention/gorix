# Gorix - Capture. Extract. Copy. (ekran goruntusu + ekrandan metin bulma)
# Baslatmak icin: Gorix.vbs (konsolsuz) veya Gorix.cmd

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$logPath = Join-Path $root 'Gorix.log'

. (Join-Path $root 'lib\Native.ps1')
[Yakala.Dpi]::Enable()
try { [System.Windows.Forms.Application]::EnableVisualStyles() } catch { }
. (Join-Path $root 'lib\Theme.ps1')
. (Join-Path $root 'lib\Ocr.ps1')
. (Join-Path $root 'lib\FastCanvas.ps1')
. (Join-Path $root 'lib\Overlay.ps1')
. (Join-Path $root 'lib\OverlayForm.ps1')
. (Join-Path $root 'lib\Toast.ps1')
. (Join-Path $root 'lib\OcrPreview.ps1')
. (Join-Path $root 'lib\Settings.ps1')

function Write-YLog([string]$msg) {
    try { Add-Content -Path $logPath -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg) -Encoding UTF8 } catch { }
}

# --- Tek kopya ---
$created = $false
$script:mutex = New-Object System.Threading.Mutex($true, 'Local\Gorix_App', [ref]$created)
if (-not $created) {
    [void][System.Windows.Forms.MessageBox]::Show('Gorix zaten çalışıyor. Sağ alttaki sistem tepsisine bak.', 'Gorix')
    return
}

# --- Ayarlar ---
$settingsPath = Join-Path $root 'settings.json'
$script:settings = [ordered]@{
    OcrDil           = 'auto'   # auto = TR + EN birlikte
    Onizleme         = $true
    KarakterDuzeltme = $true
    AracCubugu       = $true
    HatirlaAlan      = $true
    Bildirimler      = $true
    KayitKlasoru     = '%USERPROFILE%\Pictures\Gorix'
    SonKayitKlasoru  = ''   # Kaydet penceresinde en son secilen klasor (otomatik yazilir, genel ayari degistirmez)
    Kisayollar       = @('Ctrl+PrintScreen')
    SonAlan          = ''   # son secilen alan: x,y,genislik,yukseklik (otomatik yazilir)
}
if (Test-Path $settingsPath) {
    try {
        $saved = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @($script:settings.Keys)) { if ($null -ne $saved.$k) { $script:settings[$k] = $saved.$k } }
    }
    catch { Write-YLog "settings.json okunamadi: $($_.Exception.Message)" }
}
$script:settings.Kisayollar = @($script:settings.Kisayollar | Where-Object { $_ })
function Save-YSettings {
    try { $script:settings | ConvertTo-Json | Set-Content -Path $settingsPath -Encoding UTF8 } catch { Write-YLog "settings.json yazilamadi: $($_.Exception.Message)" }
}
Save-YSettings   # yeni eklenen ayarlar dosyaya yazilsin
function Get-SaveFolder {
    # Kaydet penceresi en son kullanilan klasorde acilir; yoksa (veya silindiyse) Ayarlar'daki genel klasorde
    $last = [string]$script:settings.SonKayitKlasoru
    if ($last -and (Test-Path -LiteralPath $last -PathType Container)) { return $last }
    [Environment]::ExpandEnvironmentVariables($script:settings.KayitKlasoru)
}

# --- Windows acilisinda baslatma (Baslangic klasorunde kisayol) ---
$script:startupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Gorix.lnk'
function Test-YStartup { Test-Path $script:startupLink }
function Set-YStartup([bool]$on) {
    if ($on) {
        $sh = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut($script:startupLink)
        $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
        $lnk.Arguments = '"' + (Join-Path $root 'Gorix.vbs') + '"'
        $lnk.WorkingDirectory = $root
        $lnk.Description = 'Gorix - Capture. Extract. Copy.'
        $lnk.IconLocation = (Join-Path $root 'Gorix.ico') + ',0'
        $lnk.Save()
    }
    elseif (Test-YStartup) { Remove-Item $script:startupLink -Force }
}

# --- Tepsi ikonu (uygulama simgesi: Mercek) ---
$script:tray = New-Object System.Windows.Forms.NotifyIcon
$script:tray.Icon = Get-YAppIcon ([System.Windows.Forms.SystemInformation]::SmallIconSize.Width)
# Acilis kisayolu varsa yeni simgeyle guncelle
if (Test-YStartup) { try { Set-YStartup $true } catch { Write-YLog "Baslangic kisayolu guncellenemedi: $($_.Exception.Message)" } }
$script:tray.Text = 'Gorix · Capture. Extract. Copy.'
$script:tray.Visible = $true

# --- Ana akis ---
function Invoke-YOcr([System.Drawing.Bitmap]$bmp) {
    $text = Convert-BitmapToText $bmp $script:settings.OcrDil -NoRepair:(-not $script:settings.KarakterDuzeltme)
    # Pencere aciksa kopyalama oradan yapilir; kapaliysa metin dogrudan panoya
    if ($script:settings.Onizleme) { Show-OcrPreview $bmp $text $script:settings.OcrDil; return }
    if ($text) { [System.Windows.Forms.Clipboard]::SetText($text) }
    if ($text) {
        $lines = ($text -split "`r`n").Count
        Show-YToast "Metin panoya kopyalandı · $lines satır, $($text.Length) karakter"
    }
    else { Show-YToast 'Seçili alanda metin bulunamadı.' 'warn' }
}

$script:busy = $false
function Start-YCapture {
    if ($script:busy) { return }
    $script:busy = $true
    try {
        Close-YToast
        $remember = [bool]$script:settings.HatirlaAlan
        $mem = @{ Rect = $(if ($remember) { $script:settings.SonAlan } else { '' }) }
        $res = Show-CaptureOverlay (Get-SaveFolder) $mem @{ Toolbar = [bool]$script:settings.AracCubugu }
        if ($remember -and $mem.Rect -ne $script:settings.SonAlan) { $script:settings.SonAlan = $mem.Rect; Save-YSettings }
        if (-not $res) { return }
        if ($res.SaveDir -and $res.SaveDir -ne $script:settings.SonKayitKlasoru) {
            $script:settings.SonKayitKlasoru = $res.SaveDir   # bir sonraki kayit ayni klasorde acilsin
            Save-YSettings
        }
        if ($res.Action -eq 'done') { Show-YToast $res.Message; return }
        if ($res.Action -eq 'text') {
            try { Invoke-YOcr $res.Bitmap } finally { $res.Bitmap.Dispose() }
        }
    }
    catch {
        Write-YLog ("HATA: " + $_.Exception.Message + "`r`n" + $_.ScriptStackTrace)
        Show-YToast ($_.Exception.Message + '  (ayrıntı: Gorix.log)') 'error'
    }
    finally { $script:busy = $false }
}

# --- Kisayollar ---
function ConvertTo-YHotkey([string]$text) {
    $mods = [uint32]0; $vk = $null
    foreach ($part in ($text -split '\+') | ForEach-Object { $_.Trim() }) {
        switch ($part) {
            'Ctrl' { $mods = $mods -bor [Yakala.HotkeyWindow]::MOD_CONTROL }
            'Alt' { $mods = $mods -bor [Yakala.HotkeyWindow]::MOD_ALT }
            'Shift' { $mods = $mods -bor [Yakala.HotkeyWindow]::MOD_SHIFT }
            'Win' { $mods = $mods -bor [Yakala.HotkeyWindow]::MOD_WIN }
            default { $vk = [uint32][int][System.Enum]::Parse([System.Windows.Forms.Keys], $part, $true) }
        }
    }
    if ($null -eq $vk) { throw "Geçersiz kısayol: $text" }
    @{ Mods = $mods; Vk = $vk }
}

$script:hotkeys = $null
$script:activeKeys = @()
function Unregister-YHotkeys {
    if ($script:hotkeys) { $script:hotkeys.Dispose(); $script:hotkeys = $null }
    $script:activeKeys = @()
}
# Ayarlardaki kisayollari kaydeder; kaydedilemeyenleri dondurur
function Register-YHotkeys {
    Unregister-YHotkeys
    $script:hotkeys = New-Object Yakala.HotkeyWindow
    $script:hotkeys.add_Pressed({ Start-YCapture })
    $failed = @()
    foreach ($hk in $script:settings.Kisayollar) {
        try {
            $h = ConvertTo-YHotkey $hk
            if ($script:hotkeys.Register($h.Mods, $h.Vk)) { $script:activeKeys += $hk } else { $failed += $hk }
        }
        catch { $failed += $hk; Write-YLog $_.Exception.Message }
    }
    if ($failed) { Write-YLog ("Kaydedilemeyen kisayollar (baska program kullaniyor olabilir): " + ($failed -join ', ')) }
    if ($script:captureItem) { $script:captureItem.ShortcutKeyDisplayString = ($script:activeKeys -join ' / ') }
    , $failed
}

# --- Ayarlar penceresi ---
$script:settingsOpen = $false
function Open-YSettings {
    if ($script:settingsOpen -or $script:busy) { return }
    $script:settingsOpen = $true
    try {
        Unregister-YHotkeys   # kisayol kutusu tuslari yakalayabilsin
        $cur = [ordered]@{}; foreach ($k in $script:settings.Keys) { $cur[$k] = $script:settings[$k] }
        $cur.Baslangic = Test-YStartup
        # Sade dil secenekleri: Turkce (TR + ozel karakterler icin EN destegi) ve Ingilizce
        $langs = @(Get-OcrLanguages | Where-Object { $_ -in 'auto', 'en-US' })
        if (-not $langs) { $langs = @(Get-OcrLanguages) }
        $new = Show-YSettings $cur $langs
        if ($new) {
            if ([bool]$new.Baslangic -ne (Test-YStartup)) {
                try { Set-YStartup ([bool]$new.Baslangic) } catch { Write-YLog "Baslangic kisayolu: $($_.Exception.Message)"; Show-YToast 'Windows açılışı ayarı uygulanamadı.' 'error' }
            }
            # Genel kayit klasoru degistiyse hatirlanan son klasor birakilir, yeni ayar gecerli olur
            $oldDir = [Environment]::ExpandEnvironmentVariables($script:settings.KayitKlasoru).TrimEnd('\')
            $newDir = [Environment]::ExpandEnvironmentVariables([string]$new.KayitKlasoru).TrimEnd('\')
            if ($new.ContainsKey('KayitKlasoru') -and $oldDir -ne $newDir) { $new.SonKayitKlasoru = '' }
            foreach ($k in @($script:settings.Keys)) { if ($new.ContainsKey($k)) { $script:settings[$k] = $new[$k] } }
            $script:settings.Kisayollar = @($script:settings.Kisayollar)
            Save-YSettings
        }
    }
    catch {
        Write-YLog ("HATA (ayarlar): " + $_.Exception.Message + "`r`n" + $_.ScriptStackTrace)
        Show-YToast ($_.Exception.Message + '  (ayrıntı: Gorix.log)') 'error'
    }
    finally {
        $failed = Register-YHotkeys
        if ($failed.Count) { Show-YToast ('Kısayol kaydedilemedi: ' + ($failed -join ', ') + ' (başka program kullanıyor olabilir)') 'warn' }
        elseif ($new) { Show-YToast 'Ayarlar kaydedildi.' }
        $script:settingsOpen = $false
    }
}

# --- Tepsi menusu: Yakala / Ayarlar / Cikis ---
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Renderer = New-Object Yakala.DarkRenderer
$menu.Font = New-Object System.Drawing.Font $script:YF.Ctl, 10
$menu.ImageScalingSize = New-Object System.Drawing.Size ([int](S 16)), ([int](S 16))
function New-YMenuIcon([string]$glyph) {
    $sz = [int](S 16)
    $bm = New-Object System.Drawing.Bitmap $sz, $sz
    $mg = [System.Drawing.Graphics]::FromImage($bm)
    Draw-YGlyph $mg $glyph (New-Object System.Drawing.RectangleF 0, 0, $sz, $sz) $script:YT.Text (S 13)
    $mg.Dispose()
    $bm
}
# Menu kapanmadan yakalama baslamasin (menu goruntuye girmesin)
$delayed = New-Object System.Windows.Forms.Timer
$delayed.Interval = 250
$delayed.add_Tick({ $delayed.Stop(); if ($script:pendingTray -eq 'capture') { Start-YCapture } else { Open-YSettings } })

$script:captureItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Yakala'
$script:captureItem.Image = New-YAppIconBitmap ([int](S 16))   # uygulama simgesi
$script:captureItem.Font = New-Object System.Drawing.Font $script:YF.CtlSemi, 10
$script:captureItem.add_Click({ $script:pendingTray = 'capture'; $delayed.Start() })
$settingsItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Ayarlar'
$settingsItem.Image = New-YMenuIcon ([char]0xE713)
$settingsItem.add_Click({ $script:pendingTray = 'settings'; $delayed.Start() })
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem 'Çıkış'
$exitItem.Image = New-YMenuIcon ([char]0xE7E8)
$exitItem.add_Click({
        $script:tray.Visible = $false
        Unregister-YHotkeys
        [System.Windows.Forms.Application]::Exit()
    })
foreach ($it in @($script:captureItem, $settingsItem)) { [void]$menu.Items.Add($it) }
[void]$menu.Items.Add('-')
[void]$menu.Items.Add($exitItem)
foreach ($it in $menu.Items) { $it.Padding = New-Object System.Windows.Forms.Padding 0, 3, 0, 3 }
$script:tray.ContextMenuStrip = $menu
$script:tray.add_MouseDoubleClick({ Start-YCapture })

$failed = Register-YHotkeys
if ($script:activeKeys) { Show-YToast ('Hazır. Kısayol: ' + ($script:activeKeys -join ' veya ')) }
else { Show-YToast 'Kısayol kaydedilemedi (başka program kullanıyor olabilir). Tepsi ikonuna çift tıklayarak ya da Ayarlar''dan başka kısayol seçerek kullanabilirsin.' 'warn' }
Write-YLog ("Basladi. Aktif kisayollar: " + ($script:activeKeys -join ', '))

[System.Windows.Forms.Application]::Run()
$script:tray.Dispose()
$script:mutex.ReleaseMutex()
