# Gorix - secim ekraninin hizli cizim katmani (C#)
# Alan secme / tasima / boyutlandirma ve sekil cizerken fare hareketleri PowerShell'e hic ugramaz:
# yalnizca degisen ince seritler bellekte birlestirilip ekrana kopyalanir (yuksek Hz monitorde akici).
# Diger her sey (arac cubugu, menu, ipuclari, cizimler) Paint olayinda PowerShell tarafinda cizilir.

if (-not ('Yakala.CaptureForm' -as [type])) {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Yakala {
    public class CaptureForm : Form {
        [StructLayout(LayoutKind.Sequential)]
        struct BMIH { public int biSize, biWidth, biHeight; public short biPlanes, biBitCount; public int biCompression, biSizeImage, biXPels, biYPels, biClrUsed, biClrImportant; }
        [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
        [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
        [DllImport("gdi32.dll")] static extern IntPtr CreateDIBSection(IntPtr dc, ref BMIH bmi, uint usage, out IntPtr bits, IntPtr sec, uint off);
        [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
        [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
        [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll")] static extern bool GdiFlush();
        [DllImport("gdi32.dll")] static extern bool BitBlt(IntPtr d, int x, int y, int w, int h, IntPtr s, int sx, int sy, int rop);
        const int SRCCOPY = 0x00CC0020;

        class Surf { public IntPtr DC, Bmp, Old, Bits; public Bitmap Img; }
        Surf shot, dim, back, baseS;

        public int W, H;
        public Rectangle Sel = Rectangle.Empty;
        public string Mode;          // null | new | move | resize | draw
        public string Grip;          // resize yonu: n, s, e, w, ne, nw, se, sw
        public bool ShowHandles;
        public Point Start;
        public Rectangle StartSel;
        public string ShapeType;
        public Color ShapeColor;
        public float ShapeWidth;
        public List<Point> Points = new List<Point>();

        float sc;
        Font labelFont;
        Graphics measure; Bitmap measureBmp;
        Rectangle prevLabel = Rectangle.Empty;
        List<Rectangle> prevShape = new List<Rectangle>();
        static readonly Color Accent = Color.FromArgb(76, 141, 255);
        static readonly Color PanelC = Color.FromArgb(245, 30, 30, 34);
        static readonly Color TextC = Color.FromArgb(242, 242, 246);

        Surf NewSurf(IntPtr screen) {
            var s = new Surf();
            var bi = new BMIH { biSize = 40, biWidth = W, biHeight = -H, biPlanes = 1, biBitCount = 32 };
            s.DC = CreateCompatibleDC(screen);
            s.Bmp = CreateDIBSection(screen, ref bi, 0, out s.Bits, IntPtr.Zero, 0);
            s.Old = SelectObject(s.DC, s.Bmp);
            s.Img = new Bitmap(W, H, W * 4, PixelFormat.Format32bppRgb, s.Bits);
            return s;
        }
        static void FreeSurf(Surf s) {
            if (s == null) return;
            s.Img.Dispose(); SelectObject(s.DC, s.Old); DeleteObject(s.Bmp); DeleteDC(s.DC);
        }

        public CaptureForm(Rectangle vs, float scale, string labelFamily, Color dimColor) {
            W = vs.Width; H = vs.Height; sc = scale;
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.Opaque, true);
            SetStyle(ControlStyles.OptimizedDoubleBuffer, false);
            labelFont = new Font(labelFamily, 12f * scale, FontStyle.Regular, GraphicsUnit.Pixel);
            measureBmp = new Bitmap(1, 1); measure = Graphics.FromImage(measureBmp); measure.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            IntPtr scr = GetDC(IntPtr.Zero);
            try {
                shot = NewSurf(scr); dim = NewSurf(scr); back = NewSurf(scr);
                BitBlt(shot.DC, 0, 0, W, H, scr, vs.X, vs.Y, SRCCOPY);
            } finally { ReleaseDC(IntPtr.Zero, scr); }
            BitBlt(dim.DC, 0, 0, W, H, shot.DC, 0, 0, SRCCOPY);
            GdiFlush();
            using (var g = Graphics.FromImage(dim.Img)) using (var b = new SolidBrush(dimColor)) g.FillRectangle(b, 0, 0, W, H);
        }

        // Kirpilmis ekran goruntusu (cizimsiz)
        public Bitmap Crop(Rectangle r) {
            var bmp = new Bitmap(r.Width, r.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp)) {
                g.CompositingMode = CompositingMode.SourceCopy;
                g.InterpolationMode = InterpolationMode.NearestNeighbor;
                g.PixelOffsetMode = PixelOffsetMode.Half;
                g.DrawImage(shot.Img, new Rectangle(0, 0, r.Width, r.Height), r, GraphicsUnit.Pixel);
            }
            return bmp;
        }

        void BlitBg(IntPtr dst, Rectangle c, Rectangle sel) {
            BitBlt(dst, c.X, c.Y, c.Width, c.Height, dim.DC, c.X, c.Y, SRCCOPY);
            Rectangle i = Rectangle.Intersect(c, sel);
            if (i.Width > 0 && i.Height > 0) BitBlt(dst, i.X, i.Y, i.Width, i.Height, shot.DC, i.X, i.Y, SRCCOPY);
        }

        protected override void OnPaintBackground(PaintEventArgs e) { }

        // Normal boyama: arka plan burada, ustundeki her sey PowerShell Paint olayinda cizilir
        protected override void OnPaint(PaintEventArgs e) {
            Rectangle c = Rectangle.Intersect(e.ClipRectangle, new Rectangle(0, 0, W, H));
            if (c.Width <= 0 || c.Height <= 0) return;
            BlitBg(back.DC, c, Sel);
            GdiFlush();
            using (var g = Graphics.FromImage(back.Img)) {
                g.SetClip(c);
                base.OnPaint(new PaintEventArgs(g, c));
            }
            IntPtr hdc = e.Graphics.GetHdc();
            try { BitBlt(hdc, c.X, c.Y, c.Width, c.Height, back.DC, c.X, c.Y, SRCCOPY); }
            finally { e.Graphics.ReleaseHdc(hdc); }
        }

        // ---------- Secim surukleme (new / move / resize) ----------
        public void BeginDrag(string mode, Point start, string grip, bool handles) {
            Start = start; StartSel = Sel; Grip = grip; ShowHandles = handles;
            if (mode == "new") Sel = Rectangle.Empty;
            prevLabel = LabelRect(Sel);
            Mode = mode;
        }

        static int Clamp(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
        static Rectangle Norm(Point a, Point b) {
            return new Rectangle(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));
        }

        protected override void OnMouseMove(MouseEventArgs e) {
            if (Mode == null) { base.OnMouseMove(e); return; }
            Point p = e.Location;
            if (Mode == "draw") { DragShape(p); return; }
            Rectangle old = Sel, r = StartSel;
            if (Mode == "new") {
                Sel = Norm(Start, new Point(Clamp(p.X, 0, W), Clamp(p.Y, 0, H)));
            } else if (Mode == "move") {
                int x = Clamp(r.X + p.X - Start.X, 0, W - r.Width), y = Clamp(r.Y + p.Y - Start.Y, 0, H - r.Height);
                Sel = new Rectangle(x, y, r.Width, r.Height);
            } else if (Mode == "resize") {
                int dx = p.X - Start.X, dy = p.Y - Start.Y;
                int l = r.Left, t = r.Top, ri = r.Right, bo = r.Bottom;
                if (Grip.Contains("w")) l += dx;
                if (Grip.Contains("e")) ri += dx;
                if (Grip.Contains("n")) t += dy;
                if (Grip.Contains("s")) bo += dy;
                Sel = Norm(new Point(Clamp(l, 0, W), Clamp(t, 0, H)), new Point(Clamp(ri, 0, W), Clamp(bo, 0, H)));
            }
            if (Sel == old) return;
            var rs = new List<Rectangle>();
            using (var xr = new Region(old)) using (var m = new Matrix()) {
                xr.Xor(Sel);
                foreach (RectangleF f in xr.GetRegionScans(m)) rs.Add(Rectangle.Round(f));
            }
            AddBands(rs, old, (int)Math.Ceiling(7 * sc) + 2);
            rs.Add(prevLabel);
            AddBands(rs, Sel, (int)Math.Ceiling(7 * sc) + 2);
            prevLabel = LabelRect(Sel);
            rs.Add(prevLabel);
            Compose(rs, false);
        }

        protected override void OnMouseUp(MouseEventArgs e) {
            if (e.Button == MouseButtons.Left) Mode = null;
            base.OnMouseUp(e);
        }

        static void AddBands(List<Rectangle> rs, Rectangle r, int t) {
            if (r.Width <= 0 || r.Height <= 0) return;
            rs.Add(new Rectangle(r.Left - t, r.Top - t, r.Width + 2 * t, 2 * t));
            rs.Add(new Rectangle(r.Left - t, r.Bottom - t, r.Width + 2 * t, 2 * t));
            rs.Add(new Rectangle(r.Left - t, r.Top - t, 2 * t, r.Height + 2 * t));
            rs.Add(new Rectangle(r.Right - t, r.Top - t, 2 * t, r.Height + 2 * t));
        }

        string LabelText(Rectangle r) { return r.Width + " × " + r.Height; }
        RectangleF LabelRectF(Rectangle r) {
            float lw = measure.MeasureString(LabelText(r), labelFont).Width + 16 * sc;
            bool above = r.Top >= 34 * sc;
            float ly = above ? r.Top - 32 * sc : r.Top + 8 * sc;
            float lx = r.Left + (above ? 0 : 8 * sc);
            return new RectangleF(lx, ly, lw, 24 * sc);
        }
        Rectangle LabelRect(Rectangle r) {
            if (r.Width <= 0 || r.Height <= 0) return Rectangle.Empty;
            Rectangle o = Rectangle.Ceiling(LabelRectF(r)); o.Inflate(4, 4); o.X -= 1; o.Y -= 1;
            return o;
        }

        static GraphicsPath RoundPath(RectangleF r, float rad) {
            var p = new GraphicsPath();
            float d = Math.Min(rad * 2, Math.Min(r.Width, r.Height));
            if (d <= 0) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        // Secim cercevesi, tutamaclar ve boyut etiketi (PowerShell tarafindaki Draw-YOverlay ile ayni gorunum)
        void DrawFrame(Graphics g, Rectangle r) {
            if (r.Width <= 0 || r.Height <= 0) return;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            using (var pen = new Pen(Accent, 1.5f * sc)) {
                g.DrawRectangle(pen, r.X, r.Y, r.Width - 1, r.Height - 1);
                if (ShowHandles && Mode != "new") {
                    float hr = 4.5f * sc;
                    float[] hx = { r.Left, r.Left + r.Width / 2f, r.Right };
                    float[] hy = { r.Top, r.Top + r.Height / 2f, r.Bottom };
                    for (int ix = 0; ix < 3; ix++)
                        for (int iy = 0; iy < 3; iy++) {
                            if (ix == 1 && iy == 1) continue;
                            g.FillEllipse(Brushes.White, hx[ix] - hr, hy[iy] - hr, 2 * hr, 2 * hr);
                            g.DrawEllipse(pen, hx[ix] - hr, hy[iy] - hr, 2 * hr, 2 * hr);
                        }
                }
            }
            RectangleF lr = LabelRectF(r);
            using (var path = RoundPath(lr, 12 * sc)) using (var b = new SolidBrush(PanelC)) g.FillPath(b, path);
            using (var sf = new StringFormat()) using (var tb = new SolidBrush(TextC)) {
                sf.Alignment = StringAlignment.Center; sf.LineAlignment = StringAlignment.Center;
                sf.FormatFlags = StringFormatFlags.NoWrap;
                g.DrawString(LabelText(r), labelFont, tb, lr, sf);
            }
        }

        // Kirli seritleri arka bellekte yeniden olustur ve ekrana kopyala
        void Compose(List<Rectangle> rs, bool fromBase) {
            var screen = new Rectangle(0, 0, W, H);
            var list = new List<Rectangle>();
            foreach (var r0 in rs) {
                Rectangle r = Rectangle.Intersect(r0, screen);
                if (r.Width > 0 && r.Height > 0) list.Add(r);
            }
            if (list.Count == 0) return;
            foreach (var r in list) {
                if (fromBase) BitBlt(back.DC, r.X, r.Y, r.Width, r.Height, baseS.DC, r.X, r.Y, SRCCOPY);
                else BlitBg(back.DC, r, Sel);
            }
            GdiFlush();
            using (var clip = new Region(list[0])) {
                for (int i = 1; i < list.Count; i++) clip.Union(list[i]);
                using (var g = Graphics.FromImage(back.Img)) {
                    if (fromBase) {
                        clip.Intersect(Sel);
                        g.Clip = clip;
                        g.SmoothingMode = SmoothingMode.AntiAlias;
                        DrawShape(g);
                    } else {
                        g.Clip = clip;
                        DrawFrame(g, Sel);
                    }
                }
            }
            IntPtr dc = GetDC(Handle);
            try { foreach (var r in list) BitBlt(dc, r.X, r.Y, r.Width, r.Height, back.DC, r.X, r.Y, SRCCOPY); }
            finally { ReleaseDC(Handle, dc); }
        }

        // ---------- Sekil cizme (kalem, marker, cizgi, ok, dikdortgen) ----------
        public void BeginShape(string type, Color color, float width, Point start) {
            ShapeType = type; ShapeColor = color; ShapeWidth = width;
            Points = new List<Point> { start };
            if (type != "pen" && type != "marker") Points.Add(start);
            prevShape = new List<Rectangle>();
            // Mevcut tam kareyi (cizimler, arac cubugu dahil) taban olarak al
            if (baseS == null) {
                IntPtr scr = GetDC(IntPtr.Zero);
                try { baseS = NewSurf(scr); } finally { ReleaseDC(IntPtr.Zero, scr); }
            }
            var full = new Rectangle(0, 0, W, H);
            BlitBg(baseS.DC, full, Sel);
            GdiFlush();
            using (var g = Graphics.FromImage(baseS.Img)) {
                g.SetClip(full);
                base.OnPaint(new PaintEventArgs(g, full));
            }
            Mode = "draw";
        }

        float StrokeWidth() { return ShapeType == "marker" ? ShapeWidth * 5 : ShapeWidth; }

        static void AddSegment(List<Rectangle> rs, Point a, Point b, int inf) {
            double dx = b.X - a.X, dy = b.Y - a.Y;
            int n = Math.Max(1, (int)Math.Ceiling(Math.Sqrt(dx * dx + dy * dy) / 48.0));
            for (int i = 0; i < n; i++) {
                var pa = new Point((int)(a.X + dx * i / n), (int)(a.Y + dy * i / n));
                var pb = new Point((int)(a.X + dx * (i + 1) / n), (int)(a.Y + dy * (i + 1) / n));
                Rectangle r = Norm(pa, pb); r.Inflate(inf, inf); r.Width += 1; r.Height += 1;
                rs.Add(r);
            }
        }

        List<Rectangle> ShapeDirty() {
            var rs = new List<Rectangle>();
            if (Points.Count < 2) return rs;
            int inf = (int)Math.Ceiling(StrokeWidth() / 2) + 3;
            if (ShapeType == "rect") AddBands(rs, Norm(Points[0], Points[1]), inf);
            else {
                AddSegment(rs, Points[0], Points[1], inf);
                if (ShapeType == "arrow") {
                    int a = (int)Math.Ceiling(ShapeWidth * 4) + 4;
                    rs.Add(new Rectangle(Points[1].X - a, Points[1].Y - a, 2 * a + 1, 2 * a + 1));
                }
            }
            return rs;
        }

        void DragShape(Point p) {
            var rs = new List<Rectangle>();
            if (ShapeType == "pen" || ShapeType == "marker") {
                Point last = Points[Points.Count - 1];
                if (p == last) return;
                Points.Add(p);
                AddSegment(rs, last, p, (int)Math.Ceiling(StrokeWidth() / 2) + 3);
            } else {
                if (Points[1] == p) return;
                Points[1] = p;
                var now = ShapeDirty();
                rs.AddRange(prevShape); rs.AddRange(now);
                prevShape = now;
            }
            Compose(rs, true);
        }

        void DrawShape(Graphics g) {
            if (Points.Count < 2) return;
            switch (ShapeType) {
                case "pen":
                case "marker": {
                    Color c = ShapeType == "marker" ? Color.FromArgb(110, ShapeColor) : ShapeColor;
                    using (var pen = new Pen(c, StrokeWidth())) {
                        pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; pen.LineJoin = LineJoin.Round;
                        g.DrawLines(pen, Points.ToArray());
                    }
                    break;
                }
                case "line":
                case "arrow":
                    using (var pen = new Pen(ShapeColor, ShapeWidth)) {
                        pen.StartCap = LineCap.Round;
                        if (ShapeType == "arrow") pen.CustomEndCap = new AdjustableArrowCap(4, 4);
                        else pen.EndCap = LineCap.Round;
                        g.DrawLine(pen, Points[0], Points[1]);
                    }
                    break;
                case "rect":
                    using (var pen = new Pen(ShapeColor, ShapeWidth)) {
                        pen.LineJoin = LineJoin.Round;
                        g.DrawRectangle(pen, Norm(Points[0], Points[1]));
                    }
                    break;
            }
        }

        protected override void Dispose(bool disposing) {
            if (disposing) {
                FreeSurf(shot); FreeSurf(dim); FreeSurf(back); FreeSurf(baseS);
                shot = dim = back = baseS = null;
                labelFont.Dispose(); measure.Dispose(); measureBmp.Dispose();
            }
            base.Dispose(disposing);
        }
    }
}
'@
}
