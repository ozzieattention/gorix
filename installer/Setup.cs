// Gorix kurulum programi (tek dosya). Uygulama dosyalari exe'nin icine gomulu (payload.zip).
// Yonetici izni gerektirmez: %LOCALAPPDATA%\Programs\Gorix altina kurar.
//
// Kullanim:
//   Gorix-Setup.exe                    -> kurulum sihirbazi
//   Gorix-Setup.exe /silent [/launch] [/reinstall] [/nodesktop] [/nostartup] [/nostartmenu] [/noregistry] [/dir:<klasor>]
//   (/reinstall: mevcut kurulum, ayarlar dahil, tamamen silinip bastan kurulur; sihirbazda "Yeniden kur")
//   Uninstall.exe /uninstall [/silent] -> kaldirma (Ayarlar > Uygulamalar'dan da cagrilir)

using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.IO.Compression;
using System.Management;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Gorix Kurulum")]
[assembly: AssemblyProduct("Gorix")]
[assembly: AssemblyDescription("Gorix - Capture. Extract. Copy.")]
[assembly: AssemblyCompany("Oğuzhan Vural")]
[assembly: AssemblyCopyright("Copyright (c) 2026 Oğuzhan Vural, MIT")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace GorixSetup {
    static class Setup {
        public const string AppName = "Gorix";
        public const string Version = "1.0.0";
        public const string Publisher = "Oğuzhan Vural";
        const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\Gorix";

        public static string DefaultDir {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Gorix"); }
        }
        static string DesktopLink { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Gorix.lnk"); } }
        static string StartMenuLink { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Gorix.lnk"); } }
        static string StartupLink { get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Startup), "Gorix.lnk"); } }

        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

        [STAThread]
        static int Main(string[] args) {
            try { SetProcessDPIAware(); } catch { }
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            bool uninstall = false, silent = false, launch = false, reinstall = false;
            bool desktop = true, startup = true, startMenu = true, registry = true;
            string dir = null;
            foreach (string a in args) {
                string l = a.ToLowerInvariant();
                if (l == "/uninstall") uninstall = true;
                else if (l == "/silent") silent = true;
                else if (l == "/launch") launch = true;
                else if (l == "/reinstall") reinstall = true;
                else if (l == "/nodesktop") desktop = false;
                else if (l == "/nostartup") startup = false;
                else if (l == "/nostartmenu") startMenu = false;
                else if (l == "/noregistry") registry = false;
                else if (l.StartsWith("/dir:")) dir = a.Substring(5).Trim('"');
            }

            try {
                if (uninstall) {
                    if (dir == null) dir = Path.GetDirectoryName(Application.ExecutablePath);
                    return Uninstall(dir, silent) ? 0 : 1;
                }
                if (dir == null) dir = InstalledDir() ?? DefaultDir;
                if (silent) {
                    Install(dir, desktop, startup, startMenu, registry, reinstall, null);
                    if (launch) Launch(dir);
                    return 0;
                }
                Application.Run(new Wizard(dir));
                return 0;
            }
            catch (Exception ex) {
                if (!silent) MessageBox.Show(ex.Message, "Gorix Kurulum", MessageBoxButtons.OK, MessageBoxIcon.Error);
                else Console.Error.WriteLine(ex.Message);
                return 1;
            }
        }

        // ---------- Kurulum ----------
        public static bool IsInstalled(string dir) {
            try { return File.Exists(Path.Combine(dir, "Gorix.ps1")); } catch { return false; }
        }

        // Kayitli kurulum klasoru (Ayarlar > Uygulamalar kaydi), icinde Gorix varsa
        static string InstalledDir() {
            try {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(UninstallKey)) {
                    string loc = k == null ? null : k.GetValue("InstallLocation") as string;
                    if (!string.IsNullOrEmpty(loc) && IsInstalled(loc)) return loc;
                }
            } catch { }
            return null;
        }

        public static void Install(string dir, bool desktop, bool startup, bool startMenu, bool registry, bool reinstall, Action<int, string> progress) {
            Report(progress, 0, "Çalışan Gorix kapatılıyor...");
            StopRunning(dir);

            if (reinstall && IsInstalled(dir)) {
                // Yeniden kur: eski kurulum (dosyalar, ayarlar, kisayollar) tamamen silinir
                Report(progress, 2, "Mevcut kurulum siliniyor...");
                DeleteIfOurs(DesktopLink, dir);
                DeleteIfOurs(StartMenuLink, dir);
                DeleteIfOurs(StartupLink, dir);
                string self = Path.GetFullPath(Application.ExecutablePath);
                foreach (string f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories)) {
                    if (string.Equals(Path.GetFullPath(f), self, StringComparison.OrdinalIgnoreCase)) continue;
                    File.SetAttributes(f, FileAttributes.Normal);
                    File.Delete(f);   // silinemezse kurulum durur, yarim kalmis karisik kurulum olmaz
                }
                foreach (string d in Directory.GetDirectories(dir))
                    try { Directory.Delete(d, true); } catch { }
            }

            Directory.CreateDirectory(dir);
            string root = Path.GetFullPath(dir).TrimEnd('\\') + "\\";
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            using (var zip = new ZipArchive(s, ZipArchiveMode.Read)) {
                int n = zip.Entries.Count, i = 0;
                foreach (ZipArchiveEntry e in zip.Entries) {
                    i++;
                    string target = Path.GetFullPath(Path.Combine(dir, e.FullName));
                    if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue;
                    if (e.FullName.EndsWith("/") || e.FullName.EndsWith("\\")) { Directory.CreateDirectory(target); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    e.ExtractToFile(target, true);
                    Report(progress, 5 + 75 * i / n, "Kopyalanıyor: " + e.FullName);
                }
            }

            // Kaldirici: kurulum programinin kendisi
            string uninst = Path.Combine(dir, "Uninstall.exe");
            if (!string.Equals(Path.GetFullPath(Application.ExecutablePath), Path.GetFullPath(uninst), StringComparison.OrdinalIgnoreCase))
                File.Copy(Application.ExecutablePath, uninst, true);

            Report(progress, 85, "Kısayollar oluşturuluyor...");
            if (startMenu) MakeLink(StartMenuLink, dir);
            if (desktop) MakeLink(DesktopLink, dir); else DeleteIfOurs(DesktopLink, dir);
            if (startup) MakeLink(StartupLink, dir); else DeleteIfOurs(StartupLink, dir);

            if (registry) {
                Report(progress, 95, "Kaydediliyor...");
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(UninstallKey)) {
                    k.SetValue("DisplayName", AppName);
                    k.SetValue("DisplayVersion", Version);
                    k.SetValue("Publisher", Publisher);
                    k.SetValue("DisplayIcon", Path.Combine(dir, "Gorix.ico"));
                    k.SetValue("InstallLocation", dir);
                    k.SetValue("UninstallString", "\"" + uninst + "\" /uninstall");
                    k.SetValue("QuietUninstallString", "\"" + uninst + "\" /uninstall /silent");
                    k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                    k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    k.SetValue("EstimatedSize", (int)(DirSize(dir) / 1024), RegistryValueKind.DWord);
                    k.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
                }
            }
            Report(progress, 100, "Tamamlandı.");
        }

        static void Report(Action<int, string> p, int v, string msg) { if (p != null) p(v, msg); }

        public static void Launch(string dir) {
            Process.Start(new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "wscript.exe"), "\"" + Path.Combine(dir, "Gorix.vbs") + "\"") {
                WorkingDirectory = dir, UseShellExecute = false
            });
        }

        static long DirSize(string dir) {
            long t = 0;
            foreach (string f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories)) t += new FileInfo(f).Length;
            return t;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern int GetLongPathName(string s, System.Text.StringBuilder b, int n);

        // Klasorun tam uzun yazilisi (kisa 8.3 parcalari, or. OGUZHA~1, acilir)
        static string LongDir(string dir) {
            string full = Path.GetFullPath(dir).TrimEnd('\\');
            var b = new System.Text.StringBuilder(1024);
            return GetLongPathName(full, b, 1024) > 0 ? b.ToString().TrimEnd('\\') : full;
        }

        static bool InDir(string file, string dir) {
            try { return string.Equals(LongDir(Path.GetDirectoryName(file)), LongDir(dir), StringComparison.OrdinalIgnoreCase); }
            catch { return false; }
        }

        // Komut satiri / kisayol argumanindaki tirnakli yollardan biri bu klasordeki bir dosya mi?
        static bool MentionsDir(string text, string dir) {
            if (string.IsNullOrEmpty(text)) return false;
            foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(text, "\"([^\"]+)\""))
                if (InDir(m.Groups[1].Value, dir)) return true;
            return false;
        }

        // Bu klasorden calisan Gorix (powershell) sureclerini kapat
        static void StopRunning(string dir) {
            try {
                using (var q = new ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'powershell.exe'"))
                    foreach (ManagementObject mo in q.Get()) {
                        string cmd = mo["CommandLine"] as string;
                        if (cmd == null || cmd.IndexOf("Gorix.ps1", StringComparison.OrdinalIgnoreCase) < 0 || !MentionsDir(cmd, dir)) continue;
                        try {
                            Process p = Process.GetProcessById(Convert.ToInt32(mo["ProcessId"]));
                            p.Kill(); p.WaitForExit(5000);
                        } catch { }
                    }
            } catch { }
        }

        // ---------- Kisayollar (WScript.Shell) ----------
        static void MakeLink(string path, string dir) {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            object sh = Activator.CreateInstance(t);
            try {
                object lnk = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, sh, new object[] { path });
                Type lt = lnk.GetType();
                lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, lnk, new object[] { Path.Combine(Environment.SystemDirectory, "wscript.exe") });
                lt.InvokeMember("Arguments", BindingFlags.SetProperty, null, lnk, new object[] { "\"" + Path.Combine(dir, "Gorix.vbs") + "\"" });
                lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, lnk, new object[] { dir });
                lt.InvokeMember("Description", BindingFlags.SetProperty, null, lnk, new object[] { "Gorix - Capture. Extract. Copy." });
                lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, lnk, new object[] { Path.Combine(dir, "Gorix.ico") + ",0" });
                lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, lnk, null);
                Marshal.FinalReleaseComObject(lnk);
            } finally { Marshal.FinalReleaseComObject(sh); }
        }

        // Kisayol bu kurulum klasorunu gosteriyorsa sil (baska bir Gorix kopyasina ait kisayola dokunma)
        static void DeleteIfOurs(string path, string dir) {
            if (!File.Exists(path)) return;
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            object sh = Activator.CreateInstance(t);
            string args = "";
            try {
                object lnk = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, sh, new object[] { path });
                args = (lnk.GetType().InvokeMember("Arguments", BindingFlags.GetProperty, null, lnk, null) as string) ?? "";
                Marshal.FinalReleaseComObject(lnk);
            } finally { Marshal.FinalReleaseComObject(sh); }
            if (MentionsDir(args, dir)) File.Delete(path);
        }

        // ---------- Kaldirma ----------
        static bool Uninstall(string dir, bool silent) {
            dir = Path.GetFullPath(dir).TrimEnd('\\');
            // Guvenlik: yalnizca Gorix klasorunu sil
            if (!File.Exists(Path.Combine(dir, "Gorix.ps1"))) {
                if (!silent) MessageBox.Show("Gorix bu klasörde bulunamadı:\n" + dir, "Gorix Kaldır", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return false;
            }
            if (!silent && MessageBox.Show("Gorix bilgisayarınızdan kaldırılsın mı?\n\nKısayollar ve ayarlarınız da silinecek. Kaydettiğiniz ekran görüntüleri silinmez.",
                    "Gorix Kaldır", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return false;

            StopRunning(dir);
            DeleteIfOurs(DesktopLink, dir);
            DeleteIfOurs(StartMenuLink, dir);
            DeleteIfOurs(StartupLink, dir);
            using (RegistryKey k = Registry.CurrentUser.OpenSubKey(UninstallKey)) {
                string loc = k == null ? null : k.GetValue("InstallLocation") as string;
                if (loc != null && string.Equals(Path.GetFullPath(loc).TrimEnd('\\'), dir, StringComparison.OrdinalIgnoreCase))
                    Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false);
            }

            string self = Path.GetFullPath(Application.ExecutablePath);
            foreach (string f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories))
                if (!string.Equals(f, self, StringComparison.OrdinalIgnoreCase)) { try { File.Delete(f); } catch { } }
            if (InDir(self, dir)) {
                // Calisan Uninstall.exe kendini silemez: kapandiktan sonra klasoru sil
                Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 3 127.0.0.1 >nul & rmdir /s /q \"" + dir + "\"") {
                    CreateNoWindow = true, UseShellExecute = false, WorkingDirectory = Path.GetTempPath()
                });
            } else {
                try { Directory.Delete(dir, true); } catch { }
            }
            if (!silent) MessageBox.Show("Gorix kaldırıldı.", "Gorix Kaldır", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return true;
        }
    }

    // ---------- Kurulum sihirbazi ----------
    // Tum sayfalar baslangicta olusturulur (ekran olceklemesi hepsine uygulansin), sayfa degisince gorunurluk degisir.
    class Wizard : Form {
        static readonly Color Navy = Color.FromArgb(20, 33, 61);
        static readonly Color Muted = Color.FromArgb(96, 96, 106);
        const int TextW = 476;

        readonly string dir;
        readonly bool installed;   // Gorix bu klasorde zaten kurulu: sihirbaz "Yeniden kur" olarak calisir
        int page;
        readonly Panel header;
        readonly Panel[] pages = new Panel[4];
        readonly Button back, next, cancel;
        readonly CheckBox cbDesktop, cbStartup, cbLaunch;
        readonly ProgressBar bar;
        readonly Label status;
        readonly Bitmap logo;
        bool installing, done;

        public Wizard(string dir) {
            this.dir = dir;
            installed = Setup.IsInstalled(dir);
            SuspendLayout();
            AutoScaleDimensions = new SizeF(96, 96);
            AutoScaleMode = AutoScaleMode.Dpi;
            Text = "Gorix Kurulumu";
            Font = new Font("Segoe UI", 9.5f);
            ClientSize = new Size(540, 390);
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.White;
            try {
                Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
                using (var big = new Icon(Icon, 48, 48)) logo = big.ToBitmap();
            } catch { }

            header = new Panel { Dock = DockStyle.Top, Height = 84, BackColor = Navy };
            header.Paint += PaintHeader;

            var footer = new Panel { Dock = DockStyle.Bottom, Height = 58, BackColor = Color.FromArgb(243, 244, 246) };
            footer.Paint += delegate(object s, PaintEventArgs e) {
                using (var p = new Pen(Color.FromArgb(222, 224, 228))) e.Graphics.DrawLine(p, 0, 0, footer.Width, 0);
            };
            back = MakeButton("< Geri", 254);
            next = MakeButton("İleri >", 346);
            cancel = MakeButton("İptal", 440);
            footer.Controls.AddRange(new Control[] { back, next, cancel });
            back.Click += delegate { if (page > 0) ShowPage(page - 1); };
            next.Click += OnNext;
            cancel.Click += delegate { Close(); };
            AcceptButton = next;

            cbDesktop = new CheckBox { Text = "Masaüstüne kısayol oluştur", Checked = true, AutoSize = true };
            cbStartup = new CheckBox { Text = "Windows açılışında otomatik başlat", Checked = true, AutoSize = true };
            cbLaunch = new CheckBox { Text = "Gorix'i şimdi başlat", Checked = true, AutoSize = true };
            bar = new ProgressBar { Width = TextW, Height = 18 };
            status = new Label { AutoSize = false, Width = TextW, Height = 22, ForeColor = Muted };

            for (int i = 0; i < 4; i++) pages[i] = new Panel { Dock = DockStyle.Fill, Visible = false };
            int y;

            // 0: Hos geldiniz
            y = 22;
            if (installed) {
                y = Add(pages[0], Para("Gorix bu bilgisayarda zaten kurulu.", true), y, 8);
                y = Add(pages[0], Para("Yeniden kur seçeneği mevcut kurulumu tamamen siler (uygulama dosyaları, ayarlar ve kısayollar) ve Gorix'i baştan kurar. Kaydettiğiniz ekran görüntüleri silinmez."), y, 14);
            } else {
                y = Add(pages[0], Para("Bu sihirbaz Gorix'i bilgisayarınıza kuracak.", true), y, 8);
                y = Add(pages[0], Para("Gorix ile ekranın bir bölümünü seçip görüntüsünü kopyalayabilir, kaydedebilir ya da içindeki yazıyı metin olarak alabilirsiniz."), y, 14);
            }
            y = Add(pages[0], Para("Kurulum yeri:", true), y, 0);
            var where = Para(dir); where.ForeColor = Muted;
            y = Add(pages[0], where, y, 14);
            Add(pages[0], Para(installed ? "Devam etmek için İleri'ye tıklayın." :"Yönetici izni gerekmez. Devam etmek için İleri'ye tıklayın."), y, 0);

            // 1: Secenekler
            y = 22;
            y = Add(pages[1], Para("Gorix'i nasıl kurmak istersiniz?", true), y, 12);
            cbDesktop.Location = new Point(34, y); pages[1].Controls.Add(cbDesktop); y += 32;
            cbStartup.Location = new Point(34, y); pages[1].Controls.Add(cbStartup); y += 46;
            var note = Para("Başlat menüsüne kısayol her zaman eklenir. Gorix'i daha sonra Ayarlar > Uygulamalar bölümünden kaldırabilirsiniz.");
            note.ForeColor = Muted;
            Add(pages[1], note, y, 0);

            // 2: Kuruluyor
            y = 22;
            y = Add(pages[2], Para(installed ? "Gorix yeniden kuruluyor, lütfen bekleyin." : "Gorix kuruluyor, lütfen bekleyin.", true), y, 16);
            bar.Location = new Point(32, y); pages[2].Controls.Add(bar); y += 28;
            status.Location = new Point(32, y); pages[2].Controls.Add(status);

            // 3: Tamamlandi
            y = 22;
            y = Add(pages[3], Para(installed ? "Gorix başarıyla yeniden kuruldu." : "Gorix başarıyla kuruldu.", true), y, 8);
            y = Add(pages[3], Para("Gorix sağ alttaki sistem tepsisinde çalışır (simge, gizli simgeler ^ alanında olabilir).\r\n\r\n"
                + "Ekran yakalamak için: Ctrl + PrintScreen\r\nAlanı seçtikten sonra sağ tık > Kopyala veya Metni bul.\r\n\r\n"
                + "Kısayolu ve diğer ayarları tepsi simgesine sağ tıklayıp Ayarlar'dan değiştirebilirsiniz."), y, 14);
            cbLaunch.Location = new Point(34, y); pages[3].Controls.Add(cbLaunch);

            foreach (Panel p in pages) Controls.Add(p);
            Controls.Add(header);
            Controls.Add(footer);
            ResumeLayout();
            ShowPage(0);
        }

        static int Add(Panel p, Label l, int y, int gap) {
            l.Location = new Point(32, y);
            p.Controls.Add(l);
            return y + l.Height + gap;
        }

        Button MakeButton(string text, int x) {
            return new Button { Text = text, Location = new Point(x, 14), Size = new Size(86, 30), FlatStyle = FlatStyle.System };
        }

        // Kelime kaydirmali etiket; yukseklik 96 DPI biriminde hesaplanir (form olceklerken buyutur)
        Label Para(string text, bool bold = false) {
            var l = new Label { Text = text, AutoSize = false, Width = TextW, ForeColor = bold ? Color.Black : Color.FromArgb(40, 40, 46) };
            l.Font = bold ? new Font("Segoe UI Semibold", 10f) : Font;
            int h = TextRenderer.MeasureText(text, l.Font, new Size(TextW, 0), TextFormatFlags.WordBreak).Height;
            using (Graphics g = CreateGraphics()) h = (int)Math.Ceiling(h * 96f / g.DpiY);
            l.Height = h + 4;
            return l;
        }

        void PaintHeader(object sender, PaintEventArgs e) {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
            float k = g.DpiX / 96f;
            if (logo != null) g.DrawImage(logo, 22 * k, 18 * k, 48 * k, 48 * k);
            using (var ft = new Font("Segoe UI Semibold", 15f))
            using (var fs = new Font("Segoe UI", 9.5f))
            using (var sb = new SolidBrush(Color.FromArgb(170, 190, 225))) {
                g.DrawString(PageTitle(), ft, Brushes.White, 84 * k, 14 * k);
                g.DrawString("Capture. Extract. Copy.", fs, sb, 86 * k, 48 * k);
            }
        }

        string PageTitle() {
            switch (page) {
                case 0: return installed ? "Gorix Zaten Kurulu" : "Gorix Kurulumuna Hoş Geldiniz";
                case 1: return "Kurulum Seçenekleri";
                case 2: return installed ? "Yeniden Kuruluyor..." : "Kuruluyor...";
                default: return "Kurulum Tamamlandı";
            }
        }

        void ShowPage(int p) {
            page = p;
            for (int i = 0; i < pages.Length; i++) pages[i].Visible = i == p;
            back.Visible = p == 1;
            cancel.Visible = p < 3;
            cancel.Enabled = p != 2;
            next.Enabled = p != 2;
            next.Text = p == 1 ? (installed ? "Yeniden kur" : "Kur") : p == 3 ? "Bitir" : "İleri >";
            header.Invalidate();
            if (next.Enabled) next.Focus();
        }

        void OnNext(object sender, EventArgs e) {
            if (page == 0) { ShowPage(1); return; }
            if (page == 1) {
                ShowPage(2);
                Refresh();
                installing = true;
                try {
                    Setup.Install(dir, cbDesktop.Checked, cbStartup.Checked, true, true, installed, delegate(int v, string msg) {
                        bar.Value = Math.Max(0, Math.Min(100, v)); status.Text = msg; Application.DoEvents();
                    });
                    done = true;
                    installing = false;
                    ShowPage(3);
                } catch (Exception ex) {
                    installing = false;
                    MessageBox.Show(this, "Kurulum tamamlanamadı:\n\n" + ex.Message, "Gorix Kurulum", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    ShowPage(1);
                }
                return;
            }
            if (page == 3) {
                if (cbLaunch.Checked) {
                    try { Setup.Launch(dir); } catch (Exception ex) { MessageBox.Show(this, ex.Message, "Gorix", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
                }
                Close();
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e) {
            if (installing) { e.Cancel = true; return; }
            if (!done && e.CloseReason == CloseReason.UserClosing &&
                MessageBox.Show(this, "Kurulumdan çıkmak istediğinize emin misiniz?", "Gorix Kurulum", MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes)
                e.Cancel = true;
            base.OnFormClosing(e);
        }
    }
}
