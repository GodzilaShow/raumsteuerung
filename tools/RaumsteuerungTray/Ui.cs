// Eigene, flache Bedienelemente (Stil: Systemeinstellungen macOS / Windows 11, Farben Landkreis Emsland)
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Linq;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Raumsteuerung
{
    static class Theme
    {
        public static readonly Color Grund = Hex("#F3F5F7"), Seite = Hex("#E8ECF0"), Karte = Color.White, Linie = Hex("#E2E7EB"),
            Text = Hex("#1C2833"), Leise = Hex("#6A7884"), Blau = Hex("#0071BC"), BlauHell = Hex("#E3F0FA"),
            Ok = Hex("#4FA52B"), Warn = Hex("#E19A0C"), Fehler = Hex("#D2382B"), Aus = Hex("#A7B2BC"), Knopf2 = Hex("#E9EDF1");

        public static Color Hex(string h) { return ColorTranslator.FromHtml(h); }
        public static Color Ampel(Ampel a) { return a == Raumsteuerung.Ampel.Gruen ? Ok : a == Raumsteuerung.Ampel.Gelb ? Warn : a == Raumsteuerung.Ampel.Rot ? Fehler : Aus; }

        static HashSet<string> familien;
        static bool Hat(string f)
        {
            if (familien == null) using (var ifc = new InstalledFontCollection()) familien = new HashSet<string>(ifc.Families.Select(x => x.Name), StringComparer.OrdinalIgnoreCase);
            return familien.Contains(f);
        }
        static readonly Dictionary<string, Font> cache = new Dictionary<string, Font>();
        // Segoe UI Variable (Windows 11) – sonst Segoe UI (Windows 10)
        public static Font Schrift(float pt, FontStyle st = FontStyle.Regular, bool display = false)
        {
            string fam = Hat(display ? "Segoe UI Variable Display" : "Segoe UI Variable Text") ? (display ? "Segoe UI Variable Display" : "Segoe UI Variable Text")
                       : Hat("Segoe UI") ? "Segoe UI" : Hat("Inter") ? "Inter" : SystemFonts.MessageBoxFont.FontFamily.Name;
            if (st.HasFlag(FontStyle.Bold) && Hat(fam + " Semibold")) { fam += " Semibold"; st &= ~FontStyle.Bold; }
            else if (st.HasFlag(FontStyle.Bold) && fam == "Segoe UI" && Hat("Segoe UI Semibold")) { fam = "Segoe UI Semibold"; st &= ~FontStyle.Bold; }
            string k = fam + pt + st;
            Font f; if (!cache.TryGetValue(k, out f)) { f = new Font(fam, pt, st); cache[k] = f; }
            return f;
        }
        public static Font Mono(float pt) { return new Font(Hat("Cascadia Mono") ? "Cascadia Mono" : "Consolas", pt); }
        // Symbole aus der Systemschrift (Windows 11: Segoe Fluent Icons, Windows 10: Segoe MDL2 Assets); ohne: kein Symbol
        public static Font Symbole(float pt)
        {
            string fam = Hat("Segoe Fluent Icons") ? "Segoe Fluent Icons" : Hat("Segoe MDL2 Assets") ? "Segoe MDL2 Assets" : null;
            return fam == null ? null : new Font(fam, pt);
        }

        public static GraphicsPath Rund(RectangleF r, float rad)
        {
            var p = new GraphicsPath(); float d = rad * 2;
            if (rad <= 0) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure(); return p;
        }
        // Rechteck, nur oben und/oder unten abgerundet (Zeilen in einer Gruppe)
        public static GraphicsPath Ecken(RectangleF r, float rad, bool oben, bool unten)
        {
            var p = new GraphicsPath(); float d = rad * 2;
            if (oben) { p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90); } else { p.AddLine(r.X, r.Y, r.Right, r.Y); }
            if (unten) { p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); } else { p.AddLine(r.Right, r.Bottom, r.X, r.Bottom); }
            p.CloseFigure(); return p;
        }
        public static void Gut(Graphics g) { g.SmoothingMode = SmoothingMode.AntiAlias; g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit; g.PixelOffsetMode = PixelOffsetMode.HighQuality; }

        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int val, int size);
        // Windows 11: Titelleiste in Grundfarbe, runde Ecken
        public static void Titelleiste(Form f)
        {
            try { int c = Grund.R | (Grund.G << 8) | (Grund.B << 16); DwmSetWindowAttribute(f.Handle, 35, ref c, 4); int t = Text.R | (Text.G << 8) | (Text.B << 16); DwmSetWindowAttribute(f.Handle, 36, ref t, 4); int r = 2; DwmSetWindowAttribute(f.Handle, 33, ref r, 4); } catch { }
        }
    }

    class Glatt : Control
    {
        public Glatt() { SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true); }
    }

    // Knopf: gefüllt (Haupt-Aktion) oder hellgrau; Tastatur: Tab + Leertaste/Enter
    class Knopf : Glatt
    {
        public bool Haupt; public string Symbol;
        bool ueber, unten;
        public Knopf(string text, bool haupt = false, string symbol = null)
        {
            Text = text; Haupt = haupt; Symbol = symbol; Cursor = Cursors.Hand; TabStop = true; Font = Theme.Schrift(10f, FontStyle.Bold);
            Height = 34; Width = Mass();
            SetStyle(ControlStyles.Selectable, true);
        }
        int Mass() { using (var g = CreateGraphics()) return (int)Math.Ceiling(g.MeasureString(Text, Font).Width) + 32 + (Symbol != null && Theme.Symbole(10) != null ? 22 : 0); }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Width = Mass(); Invalidate(); }
        protected override void OnMouseEnter(EventArgs e) { ueber = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { ueber = false; unten = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { unten = true; Focus(); Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { unten = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnKeyUp(KeyEventArgs e) { if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) OnClick(EventArgs.Empty); base.OnKeyUp(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g); g.Clear(Parent != null ? Parent.BackColor : Theme.Grund);
            Color bg = Haupt ? Theme.Blau : Theme.Knopf2, fg = Haupt ? Color.White : Theme.Text;
            if (!Enabled) { bg = Theme.Knopf2; fg = Theme.Aus; }
            else if (unten) bg = ControlPaint.Dark(bg, 0.08f); else if (ueber) bg = Haupt ? ControlPaint.Light(bg, 0.12f) : ControlPaint.Dark(bg, 0.03f);
            var r = new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f);
            using (var p = Theme.Rund(r, 8)) using (var b = new SolidBrush(bg)) g.FillPath(b, p);
            if (Focused && ShowFocusCues) using (var p = Theme.Rund(new RectangleF(1.5f, 1.5f, Width - 3.5f, Height - 3.5f), 7)) using (var pen = new Pen(Haupt ? Color.White : Theme.Blau, 2)) g.DrawPath(pen, p);
            float x = 16; var sf = Theme.Symbole(10);
            if (Symbol != null && sf != null) { using (var b = new SolidBrush(fg)) g.DrawString(Symbol, sf, b, x - 2, (Height - 16) / 2f + 1); x += 22; }
            TextRenderer.DrawText(g, Text, Font, new Rectangle((int)x, 0, Width - (int)x - 12, Height), fg, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.NoPadding);
        }
    }

    // Schalter wie in iOS/macOS
    class Schalter : Glatt
    {
        bool an; public event EventHandler Geaendert;
        public bool An { get { return an; } set { if (an == value) return; an = value; Invalidate(); if (Geaendert != null) Geaendert(this, EventArgs.Empty); } }
        public Schalter() { Size = new Size(44, 26); Cursor = Cursors.Hand; TabStop = true; SetStyle(ControlStyles.Selectable, true); }
        protected override void OnClick(EventArgs e) { if (Enabled) An = !An; Focus(); base.OnClick(e); }
        protected override void OnKeyUp(KeyEventArgs e) { if (e.KeyCode == Keys.Space) An = !An; base.OnKeyUp(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g); g.Clear(Parent != null ? Parent.BackColor : Theme.Karte);
            var r = new RectangleF(1, 1, Width - 3, Height - 3);
            using (var p = Theme.Rund(r, r.Height / 2)) using (var b = new SolidBrush(!Enabled ? Theme.Linie : an ? Theme.Ok : Theme.Hex("#D3DAE0"))) g.FillPath(b, p);
            float d = r.Height - 4, x = an ? r.Right - d - 2 : r.X + 2;
            using (var s = new SolidBrush(Color.FromArgb(40, 0, 0, 0))) g.FillEllipse(s, x, r.Y + 3, d, d);
            g.FillEllipse(Brushes.White, x, r.Y + 2, d, d);
            if (Focused && ShowFocusCues) using (var p = Theme.Rund(new RectangleF(0, 0, Width - 1, Height - 1), (Height - 1) / 2f)) using (var pen = new Pen(Theme.Blau, 1.5f)) g.DrawPath(pen, p);
        }
    }

    // Eingabefeld ohne alte 3D-Kante: Textfeld in einer runden, hellen Fläche; Fokus = blauer Rand
    class Feld : Glatt
    {
        public readonly TextBox Box = new TextBox { BorderStyle = BorderStyle.None };
        public override string Text { get { return Box.Text; } set { Box.Text = value; } }
        public Feld(string platzhalter = null)
        {
            Height = 34; BackColor = Theme.Grund; Box.BackColor = Theme.Grund; Box.ForeColor = Theme.Text; Box.Font = Theme.Schrift(10.5f);
            Controls.Add(Box); Box.GotFocus += (s, e) => Invalidate(); Box.LostFocus += (s, e) => Invalidate();
            Cursor = Cursors.IBeam; Click += (s, e) => Box.Focus();
            if (platzhalter != null) SetCue(platzhalter);
        }
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, string l);
        void SetCue(string t) { Box.HandleCreated += (s, e) => { try { SendMessage(Box.Handle, 0x1501, (IntPtr)1, t); } catch { } }; }
        protected override void OnLayout(LayoutEventArgs e) { base.OnLayout(e); Box.SetBounds(12, (Height - Box.PreferredHeight) / 2 + 1, Width - 24, Box.PreferredHeight); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g); g.Clear(Parent != null ? Parent.BackColor : Theme.Karte);
            using (var p = Theme.Rund(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 8))
            {
                using (var b = new SolidBrush(Theme.Grund)) g.FillPath(b, p);
                using (var pen = new Pen(Box.Focused ? Theme.Blau : Theme.Linie, Box.Focused ? 1.6f : 1f)) g.DrawPath(pen, p);
            }
        }
    }

    // Weiße, gruppierte Liste (wie iOS-Einstellungen): eine Karte, Zeilen mit feinen Trennlinien
    class Gruppe : Glatt
    {
        public string Titel;
        public readonly List<Control> Zeilen = new List<Control>();
        const int Kopf = 26;
        public Gruppe(string titel = null) { Titel = titel; BackColor = Theme.Grund; }
        public void Zeile(Control c) { Zeilen.Add(c); Controls.Add(c); c.BackColor = Theme.Karte; PerformLayout(); }
        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e); int y = Titel != null ? Kopf : 0;
            var sicht = Zeilen.Where(c => c.Visible).ToList();
            for (int i = 0; i < sicht.Count; i++)
            {
                var c = sicht[i]; c.SetBounds(1, y + 1, Width - 2, c.Height); y += c.Height;
                c.Region = new Region(Theme.Ecken(new RectangleF(0, 0, c.Width, c.Height), 11, i == 0, i == sicht.Count - 1));
            }
            Height = y + 2;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g); g.Clear(BackColor);
            int top = Titel != null ? Kopf : 0;
            if (Titel != null) TextRenderer.DrawText(g, Titel, Theme.Schrift(9.5f, FontStyle.Bold), new Point(4, 4), Theme.Leise);
            var r = new RectangleF(0.5f, top + 0.5f, Width - 1.5f, Height - top - 1.5f);
            using (var p = Theme.Rund(r, 12)) { g.FillPath(Brushes.White, p); using (var pen = new Pen(Theme.Linie)) g.DrawPath(pen, p); }
        }
    }

    // Eine Zeile in einer Gruppe: Titel (+ Untertitel) links, Bedienelement rechts, Trennlinie oben
    class Eintrag : Glatt
    {
        public string Titel, Unter; public Control Rechts; public bool Linie; public int RechtsBreite;
        public Eintrag(string titel, string unter = null, Control rechts = null, int rechtsBreite = 0)
        {
            Titel = titel; Unter = unter; Rechts = rechts; RechtsBreite = rechtsBreite;
            Height = unter != null ? 60 : 50; BackColor = Theme.Karte;
            if (rechts != null) { rechts.BackColor = Theme.Karte; Controls.Add(rechts); }
        }
        protected override void OnLayout(LayoutEventArgs e)
        {
            base.OnLayout(e); if (Rechts == null) return;
            int w = RechtsBreite > 0 ? Math.Min(RechtsBreite, Width - 200) : Rechts.Width;
            if (RechtsBreite < 0) w = Width - 16 - 190;   // füllt bis zur Titelspalte
            Rechts.SetBounds(Width - 16 - w, (Height - Rechts.Height) / 2, w, Rechts.Height);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g); g.Clear(BackColor);
            if (Linie) using (var pen = new Pen(Theme.Linie)) g.DrawLine(pen, 16, 0, Width, 0);
            int maxW = (Rechts != null ? Rechts.Left - 24 : Width - 32);
            if (Unter == null) TextRenderer.DrawText(g, Titel, Theme.Schrift(10.5f), new Rectangle(16, 0, maxW, Height), Theme.Text, TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis);
            else
            {
                TextRenderer.DrawText(g, Titel, Theme.Schrift(10.5f), new Rectangle(16, 10, maxW, 22), Theme.Text, TextFormatFlags.EndEllipsis);
                TextRenderer.DrawText(g, Unter, Theme.Schrift(9f), new Rectangle(16, 32, maxW, 20), Theme.Leise, TextFormatFlags.EndEllipsis);
            }
        }
    }

    // Statusliste: Punkt, Name, Zustand rechts; bei Problemen darunter, was zu tun ist
    class StatusListe : Glatt
    {
        List<Zeile> zeilen = new List<Zeile>();
        public StatusListe() { BackColor = Theme.Karte; }
        public void Setzen(List<Zeile> z) { zeilen = z; Height = Hoehe(); Invalidate(); }
        static bool MitHilfe(Zeile z) { return (z.Farbe == Ampel.Rot || z.Farbe == Ampel.Gelb) && !string.IsNullOrEmpty(z.Hilfe); }
        int Hoehe() { return zeilen.Sum(z => MitHilfe(z) ? 64 : 44) + 2; }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g); g.Clear(Theme.Grund);
            using (var p = Theme.Rund(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 12)) { g.FillPath(Brushes.White, p); using (var pen = new Pen(Theme.Linie)) g.DrawPath(pen, p); }
            int y = 1; bool erste = true;
            var fName = Theme.Schrift(10.5f); var fWert = Theme.Schrift(10f); var fHilfe = Theme.Schrift(9f);
            foreach (var z in zeilen)
            {
                int h = MitHilfe(z) ? 64 : 44;
                if (!erste) using (var pen = new Pen(Theme.Linie)) g.DrawLine(pen, 40, y, Width - 1, y);
                erste = false;
                using (var b = new SolidBrush(Theme.Ampel(z.Farbe))) g.FillEllipse(b, 17, y + 17, 10, 10);
                TextRenderer.DrawText(g, z.Name, fName, new Rectangle(40, y, 170, 44), Theme.Text, TextFormatFlags.VerticalCenter);
                TextRenderer.DrawText(g, z.Text, fWert, new Rectangle(200, y, Width - 216, 44), z.Farbe == Ampel.Rot ? Theme.Fehler : Theme.Leise,
                    TextFormatFlags.VerticalCenter | TextFormatFlags.Right | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
                if (MitHilfe(z)) TextRenderer.DrawText(g, z.Hilfe, fHilfe, new Rectangle(40, y + 34, Width - 56, 22), Theme.Leise, TextFormatFlags.EndEllipsis);
                y += h;
            }
        }
    }

    // Seitenleiste
    class Navi : Glatt
    {
        public readonly List<string[]> Punkte = new List<string[]>();   // { Text, Symbol }
        int aktiv, ueber = -1; public event Action<int> Gewaehlt;
        public int Aktiv { get { return aktiv; } set { aktiv = value; Invalidate(); if (Gewaehlt != null) Gewaehlt(value); } }
        public Navi() { BackColor = Theme.Seite; }   // Hand nur über den Punkten (siehe OnMouseMove), sonst Pfeil
        Rectangle R(int i) { return new Rectangle(10, 66 + i * 40, Width - 20, 34); }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            int u = Enumerable.Range(0, Punkte.Count).FirstOrDefault(i => R(i).Contains(e.Location)); if (!R(u).Contains(e.Location)) u = -1;
            if (u != ueber) { ueber = u; Cursor = u >= 0 ? Cursors.Hand : Cursors.Default; Invalidate(); }
        }
        protected override void OnMouseLeave(EventArgs e) { ueber = -1; Cursor = Cursors.Default; Invalidate(); }
        protected override void OnMouseClick(MouseEventArgs e) { for (int i = 0; i < Punkte.Count; i++) if (R(i).Contains(e.Location)) Aktiv = i; }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g); g.Clear(BackColor);
            // Kopf: Raumname
            TextRenderer.DrawText(g, "Sitzungszimmer 5", Theme.Schrift(11f, FontStyle.Bold, true), new Point(18, 18), Theme.Text);
            TextRenderer.DrawText(g, "Landkreis Emsland", Theme.Schrift(8.5f), new Point(19, 38), Theme.Leise);
            var sf = Theme.Symbole(11);
            for (int i = 0; i < Punkte.Count; i++)
            {
                var r = R(i);
                if (i == aktiv || i == ueber)
                    using (var p = Theme.Rund(r, 8)) using (var b = new SolidBrush(i == aktiv ? Color.White : Color.FromArgb(120, 255, 255, 255))) g.FillPath(b, p);
                int x = r.X + 12;
                if (sf != null) { TextRenderer.DrawText(g, Punkte[i][1], sf, new Rectangle(x, r.Y, 22, r.Height), i == aktiv ? Theme.Blau : Theme.Leise, TextFormatFlags.VerticalCenter); x += 28; }
                TextRenderer.DrawText(g, Punkte[i][0], Theme.Schrift(10.5f, i == aktiv ? FontStyle.Bold : FontStyle.Regular), new Rectangle(x, r.Y, r.Width - x, r.Height), Theme.Text, TextFormatFlags.VerticalCenter);
            }
            TextRenderer.DrawText(g, "Version " + Program.Version, Theme.Schrift(8f), new Rectangle(18, Height - 30, Width - 20, 20), Theme.Aus, TextFormatFlags.Left);
        }
    }

    // Großer Zustand oben auf der Startseite: Ring + ein Satz
    class Lage : Glatt
    {
        public Ampel Farbe = Ampel.Grau; public string Satz = "Prüfe …", Unter = "", Zeit = "";
        public Lage() { BackColor = Theme.Grund; Height = 84; }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g); g.Clear(BackColor);
            var c = Theme.Ampel(Farbe); var r = new RectangleF(4, 12, 56, 56);
            using (var b = new SolidBrush(Color.FromArgb(38, c))) g.FillEllipse(b, r);
            using (var pen = new Pen(c, 4)) g.DrawEllipse(pen, r.X + 6, r.Y + 6, r.Width - 12, r.Height - 12);
            using (var pen = new Pen(c, 3.2f) { StartCap = LineCap.Round, EndCap = LineCap.Round, LineJoin = LineJoin.Round })
            {
                float cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2;
                if (Farbe == Ampel.Gruen) g.DrawLines(pen, new[] { new PointF(cx - 8, cy), new PointF(cx - 2, cy + 6), new PointF(cx + 9, cy - 6) });
                else if (Farbe == Ampel.Grau) { }
                else { g.DrawLine(pen, cx, cy - 9, cx, cy + 2); using (var b = new SolidBrush(c)) g.FillEllipse(b, cx - 2.2f, cy + 6, 4.4f, 4.4f); }
            }
            TextRenderer.DrawText(g, Satz, Theme.Schrift(17f, FontStyle.Bold, true), new Point(76, Unter == "" ? 26 : 14), Theme.Text);   // ohne Unterzeile mittig
            TextRenderer.DrawText(g, Unter, Theme.Schrift(10f), new Rectangle(77, 46, Width - 77 - 110, 22), Theme.Leise, TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            TextRenderer.DrawText(g, Zeit, Theme.Schrift(9f), new Rectangle(Width - 110, Unter == "" ? 33 : 22, 110, 20), Theme.Aus, TextFormatFlags.Right);
        }
    }

    // Kontextmenü im Infobereich: weiß, runde Auswahl, ohne 2000er-Verläufe
    class MenueStil : ToolStripProfessionalRenderer
    {
        class Farben : ProfessionalColorTable
        {
            public override Color ToolStripDropDownBackground { get { return Color.White; } }
            public override Color MenuBorder { get { return Theme.Linie; } }
            public override Color ImageMarginGradientBegin { get { return Color.White; } }
            public override Color ImageMarginGradientMiddle { get { return Color.White; } }
            public override Color ImageMarginGradientEnd { get { return Color.White; } }
            public override Color SeparatorDark { get { return Theme.Linie; } }
            public override Color SeparatorLight { get { return Color.White; } }
        }
        public MenueStil() : base(new Farben()) { RoundedEdges = false; }
        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            if (!e.Item.Selected || !e.Item.Enabled) return;
            var g = e.Graphics; Theme.Gut(g);
            using (var p = Theme.Rund(new RectangleF(3, 1, e.Item.Width - 6, e.Item.Height - 2), 6)) using (var b = new SolidBrush(Theme.BlauHell)) g.FillPath(b, p);
        }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) { e.TextColor = Theme.Text; base.OnRenderItemText(e); }
    }

    // Auswahlliste im Stil der Eingabefelder (statt der alten ComboBox): Klick öffnet ein Menü
    class Auswahl : Glatt
    {
        public readonly List<KeyValuePair<string, string>> Eintraege = new List<KeyValuePair<string, string>>();   // Wert, Text
        string wert = "";
        public string Wert { get { return wert; } set { wert = value ?? ""; Invalidate(); } }
        public Auswahl() { Height = 34; Cursor = Cursors.Hand; TabStop = true; SetStyle(ControlStyles.Selectable, true); }
        string Anzeige { get { var e = Eintraege.FirstOrDefault(x => x.Key == wert); return e.Value ?? wert; } }
        ContextMenuStrip offen; DateTime zuDurchKlick = DateTime.MinValue;
        protected override void OnClick(EventArgs e)
        {
            Focus(); base.OnClick(e);
            // Klick auf die offene Liste = zuklappen. Windows schließt sie schon beim Drücken, das Loslassen käme
            // danach hier als neuer Klick an und würde sie gleich wieder öffnen.
            if ((DateTime.Now - zuDurchKlick).TotalMilliseconds < 1000) { zuDurchKlick = DateTime.MinValue; return; }
            if (offen != null) { offen.Close(); return; }
            var m = new ContextMenuStrip { Renderer = new MenueStil(), Font = Theme.Schrift(10.5f), ShowImageMargin = false, ShowCheckMargin = true };
            m.Closed += (s, a) =>
            {
                offen = null;
                if (a.CloseReason == ToolStripDropDownCloseReason.AppClicked && ClientRectangle.Contains(PointToClient(Cursor.Position))) zuDurchKlick = DateTime.Now;
                BeginInvoke((Action)m.Dispose);
            };
            offen = m;
            foreach (var kv in Eintraege)
            {
                var k = kv; var it = new ToolStripMenuItem(k.Value) { Checked = k.Key == wert, Padding = new Padding(4, 4, 4, 4) };
                it.Click += (s, a) => Wert = k.Key; m.Items.Add(it);
            }
            m.MinimumSize = new Size(Width, 0);
            m.Show(this, new Point(0, Height + 2));
        }
        protected override void OnKeyUp(KeyEventArgs e) { if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter || e.KeyCode == Keys.F4) { zuDurchKlick = DateTime.MinValue; OnClick(EventArgs.Empty); } base.OnKeyUp(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g); g.Clear(Parent != null ? Parent.BackColor : Theme.Karte);
            using (var p = Theme.Rund(new RectangleF(0.5f, 0.5f, Width - 1.5f, Height - 1.5f), 8))
            {
                using (var b = new SolidBrush(Theme.Grund)) g.FillPath(b, p);
                using (var pen = new Pen(Focused ? Theme.Blau : Theme.Linie, Focused ? 1.6f : 1f)) g.DrawPath(pen, p);
            }
            TextRenderer.DrawText(g, Anzeige, Theme.Schrift(10.5f), new Rectangle(12, 0, Width - 40, Height), Theme.Text, TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.SingleLine);
            float cx = Width - 18, cy = Height / 2f;
            using (var pen = new Pen(Theme.Leise, 1.6f) { StartCap = LineCap.Round, EndCap = LineCap.Round })
                g.DrawLines(pen, new[] { new PointF(cx - 5, cy - 2.5f), new PointF(cx, cy + 2.5f), new PointF(cx + 5, cy - 2.5f) });
        }
    }

    // Kleiner Abschnittstitel über einer Liste (wie der Titel einer Gruppe)
    class Abschnitt : Glatt
    {
        public Abschnitt(string t) { Text = t; Height = 26; BackColor = Theme.Grund; }
        protected override void OnPaint(PaintEventArgs e) { e.Graphics.Clear(BackColor); TextRenderer.DrawText(e.Graphics, Text, Theme.Schrift(9.5f, FontStyle.Bold), new Point(4, 4), Theme.Leise); }
    }

    // Großes Schild mitten auf einem Bildschirm: Nummer, Name, Aufgabe ("Nummern zeigen" in den Einstellungen)
    class SchirmNummer : Form
    {
        readonly string nr, name, rolle;
        public SchirmNummer(Screen s, string nr, string name, string rolle)
        {
            this.nr = nr; this.name = name; this.rolle = rolle;
            FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true; StartPosition = FormStartPosition.Manual;
            BackColor = Theme.Blau; DoubleBuffered = true;
            var b = s.Bounds; Size = new Size(Math.Min(520, b.Width), Math.Min(360, b.Height));
            Location = new Point(b.X + (b.Width - Width) / 2, b.Y + (b.Height - Height) / 2);
            Click += (x, e) => Close();
        }
        protected override bool ShowWithoutActivation { get { return true; } }
        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics; Theme.Gut(g);
            var f = TextFormatFlags.HorizontalCenter | TextFormatFlags.SingleLine;
            TextRenderer.DrawText(g, nr, Theme.Schrift(110f, FontStyle.Bold, true), new Rectangle(0, 10, Width, 210), Color.White, f | TextFormatFlags.VerticalCenter);
            TextRenderer.DrawText(g, name, Theme.Schrift(16f), new Rectangle(0, 228, Width, 36), Color.White, f);
            TextRenderer.DrawText(g, rolle, Theme.Schrift(20f, FontStyle.Bold), new Rectangle(0, 270, Width, 44), Color.White, f);
        }
    }
}
