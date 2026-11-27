# Gorix - Windows API yardimcilari (global kisayol + DPI)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ('Yakala.ToastForm' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
using System.Runtime.InteropServices;

namespace Yakala {
    public class HotkeyWindow : NativeWindow, IDisposable {
        [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        public const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_WIN = 0x8, MOD_NOREPEAT = 0x4000;
        public event EventHandler Pressed;
        private int lastId = 0;

        public HotkeyWindow() { CreateHandle(new CreateParams()); }

        public bool Register(uint modifiers, uint vk) {
            lastId++;
            return RegisterHotKey(Handle, lastId, modifiers | MOD_NOREPEAT, vk);
        }

        protected override void WndProc(ref Message m) {
            if (m.Msg == 0x0312 && Pressed != null) Pressed(this, EventArgs.Empty);
            base.WndProc(ref m);
        }

        public void Dispose() {
            for (int i = 1; i <= lastId; i++) UnregisterHotKey(Handle, i);
            DestroyHandle();
        }
    }

    public static class Dpi {
        [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

        // Ekran koordinatlari fiziksel piksel olsun (olcekli ekranlarda yanlis kirpmayi onler)
        public static void Enable() {
            try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch { }
            try { SetProcessDPIAware(); } catch { }
        }
    }

    public static class KeyState {
        [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vKey);
        public static bool WinDown() { return (GetAsyncKeyState(0x5B) & 0x8000) != 0 || (GetAsyncKeyState(0x5C) & 0x8000) != 0; }
    }

    // Windows 11: koyu baslik cubugu + yuvarlak kose
    public static class Dwm {
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
        public static void Style(IntPtr hwnd, bool dark, bool round) {
            try {
                int d = dark ? 1 : 0; DwmSetWindowAttribute(hwnd, 20, ref d, 4);
                int c = round ? 2 : 1; DwmSetWindowAttribute(hwnd, 33, ref c, 4);
            } catch { }
        }
    }

    // Odagi calmayan, gorev cubugunda gorunmeyen bildirim penceresi
    public class ToastForm : Form {
        public ToastForm() {
            SetStyle(ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override CreateParams CreateParams {
            get {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= 0x08000000 | 0x00000080 | 0x00000008; // NOACTIVATE | TOOLWINDOW | TOPMOST
                return cp;
            }
        }
    }

    // Koyu tepsi menusu renkleri
    public class DarkColors : ProfessionalColorTable {
        static Color Bg = Color.FromArgb(36, 36, 40), Hover = Color.FromArgb(56, 56, 64), Line = Color.FromArgb(64, 64, 72);
        public override Color ToolStripDropDownBackground { get { return Bg; } }
        public override Color ImageMarginGradientBegin { get { return Bg; } }
        public override Color ImageMarginGradientMiddle { get { return Bg; } }
        public override Color ImageMarginGradientEnd { get { return Bg; } }
        public override Color MenuBorder { get { return Line; } }
        public override Color MenuItemBorder { get { return Hover; } }
        public override Color MenuItemSelected { get { return Hover; } }
        public override Color MenuItemSelectedGradientBegin { get { return Hover; } }
        public override Color MenuItemSelectedGradientEnd { get { return Hover; } }
        public override Color MenuItemPressedGradientBegin { get { return Hover; } }
        public override Color MenuItemPressedGradientEnd { get { return Hover; } }
        public override Color SeparatorDark { get { return Line; } }
        public override Color SeparatorLight { get { return Bg; } }
        public override Color CheckBackground { get { return Color.FromArgb(76, 141, 255); } }
        public override Color CheckSelectedBackground { get { return Color.FromArgb(76, 141, 255); } }
        public override Color CheckPressedBackground { get { return Color.FromArgb(76, 141, 255); } }
    }

    public class DarkRenderer : ToolStripProfessionalRenderer {
        public DarkRenderer() : base(new DarkColors()) { RoundedEdges = false; }
        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) { e.ArrowColor = Color.FromArgb(200, 200, 205); base.OnRenderArrow(e); }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) { e.TextColor = e.Item.Enabled ? Color.FromArgb(235, 235, 240) : Color.Gray; base.OnRenderItemText(e); }
    }
}
'@
}
