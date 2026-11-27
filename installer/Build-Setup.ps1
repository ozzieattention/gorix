# Gorix-Setup.exe uretir: uygulama dosyalarini zip'leyip Setup.cs ile birlikte tek exe'ye derler.
# Ek arac gerekmez; Windows'ta hazir gelen .NET Framework derleyicisi (csc.exe) kullanilir.
# Calistirma:  powershell -ExecutionPolicy Bypass -File installer\Build-Setup.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$out = Join-Path $repo 'dist'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe bulunamadi (.NET Framework 4.x gerekli).' }

# 1) Kurulacak dosyalar
$stage = Join-Path ([IO.Path]::GetTempPath()) ('gorix-build-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage, (Join-Path $stage 'lib') | Out-Null
foreach ($f in 'Gorix.ps1', 'Gorix.vbs', 'Gorix.cmd', 'Gorix.ico', 'LICENSE', 'README.md') { Copy-Item (Join-Path $repo $f) $stage }
Copy-Item (Join-Path $repo 'lib\*.ps1') (Join-Path $stage 'lib')

# 2) Zip
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path ([IO.Path]::GetTempPath()) ('gorix-payload-' + [guid]::NewGuid().ToString('N') + '.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)

# 3) Derle
New-Item -ItemType Directory -Force -Path $out | Out-Null
$exe = Join-Path $out 'Gorix-Setup.exe'
$args = @('/nologo', '/target:winexe', '/optimize+', '/codepage:65001', "/out:$exe",
    "/win32icon:$(Join-Path $repo 'Gorix.ico')", "/resource:$zip,payload.zip",
    '/r:System.Windows.Forms.dll', '/r:System.Drawing.dll', '/r:System.IO.Compression.dll',
    '/r:System.IO.Compression.FileSystem.dll', '/r:System.Management.dll',
    (Join-Path $PSScriptRoot 'Setup.cs'))
& $csc $args
$code = $LASTEXITCODE
Remove-Item $stage -Recurse -Force; Remove-Item $zip -Force
if ($code -ne 0) { throw "Derleme basarisiz (csc cikis kodu $code)" }
"Olusturuldu: $exe ({0:N0} KB)" -f ((Get-Item $exe).Length / 1KB)
