<p align="center">
  <img src="docs/gorix-logo.png" width="128" alt="Gorix logo">
</p>

<h1 align="center">Gorix</h1>
<p align="center"><b>Capture. Extract. Copy.</b></p>
<p align="center">A lightweight Windows screenshot tool that also <b>reads the text</b> inside the area you select.</p>

---

Select an area, then pick an action from the right-click menu. **Copy** puts the screenshot on the clipboard. **Find text** reads the text in the selection with OCR, so you don't have to retype it.

- **No installation, no dependencies.** It is plain PowerShell 5.1 + WinForms, and both ship with Windows 10/11.
- **Offline OCR.** Text is read by Windows' built-in OCR engine (`Windows.Media.Ocr`). No image ever leaves your computer.
- **Turkish-first.** The OCR combines the Turkish and English engines, so Turkish characters (`ç ğ ı ö ş ü İ`) and symbols like `/ - * ? !` come out correctly together.
- **Smooth.** Selecting, resizing and drawing run on a small compiled C# layer that only redraws the changed strips. It feels fluid even on high-refresh-rate monitors.

> The user interface is in **Turkish**.

## Features

| | |
|---|---|
| **Area selection** | Drag to select; resize from the edges and corners; move by dragging the inside. Multi-monitor, DPI-aware. |
| **Right-click menu** | Copy · Find text · Save (PNG/JPG) · Print · Select this monitor · Select all screens · Clear selection · Cancel |
| **Annotations** | Pen, line, arrow, rectangle, highlighter, text (movable, double-click to edit), 8 colors, 3 widths, undo |
| **Find text (OCR)** | Opens the recognized text in an editable window; copy all or only the selection |
| **OCR clean-up** | Fixes common OCR confusions: `Ox7F → 0x7F`, `1O234 → 10234`, `MessagelD → MessageID`, `1.250,OO → 1.250,00` |
| **Remembers your last area** | The next capture opens with the same area selected, so repeated captures are one keystroke |
| **Smart save** | Saving also copies the image to the clipboard, and the save dialog reopens in the folder you used last (the default folder in Settings stays unchanged) |
| **Settings window** | Custom hotkeys (two slots), OCR language, toggles for every feature, save folder, start with Windows |
| **Tray app** | Lives in the system tray: Capture · Settings · Exit |

## Requirements

- Windows 10 or 11
- Windows PowerShell 5.1 (built in)
- OCR language support for **Turkish** and **English**. Check what is installed:

  ```powershell
  Get-WindowsCapability -Online -Name "Language.OCR*" | Where-Object State -eq Installed
  ```

  Install a missing one (from an **administrator** PowerShell):

  ```powershell
  Add-WindowsCapability -Online -Name "Language.OCR~~~tr-TR~0.0.1.0"
  ```

## Getting started

### Installer (recommended)

Download **`Gorix-Setup.exe`** from the [Releases](../../releases) page and run it. The wizard installs Gorix to `%LOCALAPPDATA%\Programs\Gorix` with no admin rights. It adds a Start Menu shortcut, and optionally a desktop shortcut and start-with-Windows. You can uninstall Gorix from **Settings → Apps**.

If Gorix is already installed, the wizard offers **Reinstall**. This removes the existing installation (app files, settings and shortcuts) and installs a clean copy. Your saved screenshots are not touched.

To build the installer yourself, you only need what ships with Windows (the .NET Framework C# compiler):

```powershell
powershell -ExecutionPolicy Bypass -File installer\Build-Setup.ps1
```

### Portable

1. Download the repository (**Code → Download ZIP**) and extract it to any folder.
2. Files downloaded from the internet are blocked by Windows. Unblock them once, from inside the folder:

   ```powershell
   Get-ChildItem -Recurse | Unblock-File
   ```

3. Double-click **`Gorix.vbs`** (no console window). If that is blocked, use `Gorix.cmd`.
4. The Gorix icon appears in the system tray (it may be under the `^` overflow arrow).

## Usage

1. Press **Ctrl + PrintScreen** (default; change it in Settings) or double-click the tray icon.
2. Drag to select an area.
3. **Right-click** inside the selection:

| Menu item | Shortcut | What it does |
|---|---|---|
| Kopyala (Copy) | `Ctrl+C` / `Enter` | Copies the image, with your drawings, to the clipboard |
| Metni bul (Find text) | `T` | Reads the text and shows it in an editable window |
| Kaydet (Save) | `Ctrl+S` | Saves as PNG or JPG and copies the image to the clipboard |
| Yazdır (Print) | `Ctrl+P` | Prints the selection |
| Bu monitörü seç | | Selects the whole monitor you right-clicked on |
| Tüm ekranı seç | `Ctrl+A` | Selects all monitors |
| Seçimi temizle | | Clears the selection and drawings |
| İptal (Cancel) | `Esc` | Closes the overlay |

The drawing toolbar appears at the bottom-right of the selection.

## How it works

```
Gorix.ps1            tray app, settings, hotkeys, main flow
lib/FastCanvas.ps1   compiled C# overlay: screen capture + fast incremental rendering while dragging
lib/Overlay.ps1      selection state, toolbar layout, overlay drawing
lib/OverlayForm.ps1  overlay window, mouse/keyboard handling, right-click menu
lib/Ocr.ps1          Windows OCR wrapper: 2x upscaling, TR+EN word merging, line/column grouping, clean-up rules
lib/OcrPreview.ps1   "Find text" window
lib/Settings.ps1     settings window
lib/Theme.ps1        colors, fonts, icons; the app icon is drawn in code
lib/Toast.ps1        notifications
lib/Native.ps1       Win32 helpers (global hotkeys, DPI, dark title bar)
```

**OCR pipeline:** the selection is padded and upscaled 2x, then read by both the Turkish and the English engine. Words are matched by their bounding boxes. For each word, the Turkish result wins if it contains Turkish characters; otherwise the English result is used, because it reads symbols better. Lines are rebuilt from word positions, and wide gaps become column breaks. Finally, a set of conservative rules fixes the usual `O/0` and `l/I/1` confusions in number-heavy words.

Settings are stored in `settings.json` next to the script. The file is created on first run and is ignored by git.

## Limitations

- OCR is never 100% accurate. Very small text (≈10 px or less) is less reliable; zoom in (Ctrl + mouse wheel) before capturing for much better results. **Always double-check critical values such as IDs after pasting.**
- `=` and `-` can be confused at small sizes.
- The UI is Turkish only.

---

## Türkçe

**Gorix**, Windows için hafif bir ekran görüntüsü aracı. Seçtiğin alanın görüntüsünü almanın yanında içindeki **yazıyı da okuyup kopyalar**. Uzun bir metni ekran görüntüsünden elle yazmana gerek kalmaz.

- Kurulum yok: Windows'ta hazır gelen PowerShell 5.1 ile çalışır.
- Metin okuma tamamen bilgisayarında, Windows'un kendi OCR motoruyla yapılır; görüntü hiçbir yere gönderilmez.
- Türkçe karakterler ve `/ - * ? !` gibi özel karakterler birlikte doğru okunur.
- Çizim araçları, sağ tık menüsü, son seçilen alanı hatırlama, kısayol ayarı ve Windows açılışında başlatma özellikleri var.
- Kaydederken görseli panoya da kopyalar; kaydet penceresi en son kullandığın klasörde açılır.

**Kurulum:** [Releases](../../releases) sayfasından `Gorix-Setup.exe`'yi indirip çalıştır. Gorix zaten kuruluysa sihirbaz **Yeniden kur** seçeneğiyle eski kurulumu silip temiz kurar.

**Kurulumsuz başlatmak için:** ZIP'i indirip aç, klasörde bir kez `Get-ChildItem -Recurse | Unblock-File` çalıştır, sonra `Gorix.vbs`'e çift tıkla. Varsayılan kısayol **Ctrl + PrintScreen**. Alanı seçtikten sonra **sağ tık → Metni bul**.

## License

[MIT](LICENSE)
