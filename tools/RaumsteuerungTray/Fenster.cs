// Fenster + Symbol im Infobereich
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace Raumsteuerung
{
    class Fenster : Form
    {
        static readonly Color Blau = Color.FromArgb(0x00, 0x71, 0xBC), Ink = Color.FromArgb(0x0E, 0x2A, 0x3F),
            Gruen = Color.FromArgb(0x3B, 0x8C, 0x2A), Gelb = Color.FromArgb(0xE0, 0x9A, 0x00), Rot = Color.FromArgb(0xB4, 0x23, 0x18),
            Grau = Color.FromArgb(0x8A, 0x99, 0xA6), Hell = Color.FromArgb(0xEE, 0xF3, 0xF6);

        readonly NotifyIcon tray = new NotifyIcon();
        TabControl tabs;
        public int Seite { set { tabs.SelectedIndex = Math.Max(0, Math.Min(value, tabs.TabCount - 1)); } }
        readonly Icon basis;
        readonly Dictionary<Ampel, Icon> icons = new Dictionary<Ampel, Icon>();
        readonly Label kopfStatus = new Label();
        readonly TableLayoutPanel statusTabelle = new TableLayoutPanel();
        readonly ListBox adressen = new ListBox();
        readonly ToolTip tip = new ToolTip();
        readonly TextBox ausgabe = new TextBox();
        TextBox rmcrIp, link; ComboBox bildschirm; readonly TextBox[] mic = new TextBox[5]; CheckBox autostart;
        Einstellungen cfg = Einstellungen.Laden();
        Ampel letzte = Ampel.Grau;
        bool pruefLaeuft, beenden;
        readonly System.Windows.Forms.Timer dienstTimer = new System.Windows.Forms.Timer { Interval = 2000 };
        readonly System.Windows.Forms.Timer statusTimer = new System.Windows.Forms.Timer { Interval = 5000 };

        public Fenster(EventWaitHandle zeigen)
        {
            Text = "Raumsteuerung Sitzungszimmer 5";
            Font = new Font("Segoe UI", 9.75f);
            AutoScaleMode = AutoScaleMode.Font;
            ClientSize = new Size(620, 640); MinimumSize = new Size(560, 560);
            StartPosition = FormStartPosition.CenterScreen; BackColor = Color.White;
            try { basis = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { basis = SystemIcons.Application; }
            Icon = basis;

            // Kopf
            var kopf = new Panel { Dock = DockStyle.Top, Height = 64, BackColor = Blau };
            kopf.Controls.Add(new Label { Text = "Sitzungszimmer 5 – Raumsteuerung", ForeColor = Color.White, Font = new Font("Segoe UI Semibold", 13f), AutoSize = true, Location = new Point(16, 8) });
            kopfStatus.ForeColor = Color.White; kopfStatus.AutoSize = true; kopfStatus.Location = new Point(18, 38); kopfStatus.Text = "Prüfe …";
            kopf.Controls.Add(kopfStatus);
            var streifen = new Panel { Dock = DockStyle.Top, Height = 5, BackColor = Color.FromArgb(0x8D, 0xC6, 0x3F) };

            tabs = new TabControl { Dock = DockStyle.Fill, Padding = new Point(14, 5) };
            tabs.TabPages.Add(SeiteStatus()); tabs.TabPages.Add(SeiteEinstellungen()); tabs.TabPages.Add(SeiteWerkzeuge());
            Controls.Add(tabs); Controls.Add(streifen); Controls.Add(kopf);

            // Infobereich
            var menu = new ContextMenuStrip();
            menu.Items.Add("Öffnen", null, (s, e) => Zeigen());
            menu.Items.Add("Tablet-Seite öffnen", null, (s, e) => Oeffnen("http://127.0.0.1:8080/"));
            menu.Items.Add("Companion öffnen", null, (s, e) => Oeffnen("http://127.0.0.1:8000/"));
            menu.Items.Add("Dienste neu starten", null, (s, e) => Dienste.AlleNeuStarten());
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Beenden", null, (s, e) => Beenden());
            tray.ContextMenuStrip = menu; tray.Text = "Raumsteuerung Sitzungszimmer 5"; tray.Icon = Symbol(Ampel.Grau); tray.Visible = true;
            tray.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) Zeigen(); };

            // Zweiter Start des Programms -> dieses Fenster zeigen
            var t = new Thread(() => { while (true) { zeigen.WaitOne(); try { BeginInvoke((Action)Zeigen); } catch { } } }) { IsBackground = true };
            t.Start();

            CreateHandle();   // für BeginInvoke, auch wenn das Fenster nie gezeigt wird
            if (!Dienste.AlteAufgaben) foreach (var d in Dienste.Alle) d.Starten();
            dienstTimer.Tick += (s, e) => Dienste.Pruefen(); dienstTimer.Start();
            statusTimer.Tick += (s, e) => StatusHolen(); statusTimer.Start();
            StatusHolen();
        }

        // ---------- Seiten ----------
        TabPage SeiteStatus()
        {
            var p = new TabPage("Status") { BackColor = Color.White, Padding = new Padding(12) };
            statusTabelle.Dock = DockStyle.Top; statusTabelle.AutoSize = true; statusTabelle.ColumnCount = 3;
            statusTabelle.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 26));
            statusTabelle.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
            statusTabelle.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            var unten = new Panel { Dock = DockStyle.Bottom, Height = 170 };
            unten.Controls.Add(new Label { Text = "Adresse für das Tablet (aus dem Netz des Tablets):", AutoSize = true, Location = new Point(0, 8), ForeColor = Ink });
            adressen.Location = new Point(0, 30); adressen.Size = new Size(570, 70); adressen.Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top;
            unten.Controls.Add(adressen);
            var kopie = Knopf("Adresse kopieren", (s, e) => { if (adressen.SelectedItem != null) Clipboard.SetText(adressen.SelectedItem.ToString().Split(' ')[0]); });
            kopie.Location = new Point(0, 108);
            var tablet = Knopf("Tablet-Seite öffnen", (s, e) => Oeffnen("http://127.0.0.1:8080/")); tablet.Location = new Point(150, 108);
            var comp = Knopf("Companion öffnen", (s, e) => Oeffnen("http://127.0.0.1:8000/")); comp.Location = new Point(300, 108);
            unten.Controls.AddRange(new Control[] { kopie, tablet, comp });
            var scroll = new Panel { Dock = DockStyle.Fill, AutoScroll = true };
            scroll.Controls.Add(statusTabelle);
            p.Controls.Add(scroll); p.Controls.Add(unten);
            return p;
        }

        TabPage SeiteEinstellungen()
        {
            var p = new TabPage("Einstellungen") { BackColor = Color.White, Padding = new Padding(12), AutoScroll = true };
            var t = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 2 };
            t.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190)); t.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            Action<string, Control, string> zeile = (text, c, hilfe) =>
            {
                t.Controls.Add(new Label { Text = text, AutoSize = true, Margin = new Padding(0, 9, 8, 4), ForeColor = Ink });
                c.Dock = DockStyle.Fill; c.Margin = new Padding(0, 5, 0, 4); t.Controls.Add(c);
                if (hilfe != null) tip.SetToolTip(c, hilfe);
            };
            rmcrIp = new TextBox(); zeile("RM-CR (IP-Adresse)", rmcrIp, "Yamaha RM-CR, Steuerung über RCP (Port 49280)");
            bildschirm = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList };
            zeile("„Präsentation zeigen“", bildschirm, "Welchen Bildschirm Teams teilt, wenn am Tablet „Präsentation zeigen“ getippt wird");
            link = new TextBox(); zeile("Teams-Meeting-Link", link, "Link des festen Raum-Meetings (wird in teams-link.txt gespeichert)");
            for (int i = 0; i < 5; i++) { mic[i] = new TextBox(); zeile("Tischmikrofon " + (i + 1) + " → Kanal", mic[i], "RM-CR-Kanal(e) dieses Mikrofons, z. B. 1 oder 1, 2 – leer = nicht vorhanden. Herausfinden: Werkzeuge → Mikrofone testen"); }
            autostart = new CheckBox { Text = "Mit Windows starten (dieser Benutzer)", AutoSize = true };
            zeile("", autostart, null);
            var speichern = Knopf("Speichern", (s, e) => Speichern()); speichern.BackColor = Blau; speichern.ForeColor = Color.White;
            var zurueck = Knopf("Verwerfen", (s, e) => EinstellungenAnzeigen());
            var knopfReihe = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
            knopfReihe.Controls.Add(speichern); knopfReihe.Controls.Add(zurueck);
            t.Controls.Add(new Label()); t.Controls.Add(knopfReihe);
            p.Controls.Add(t);
            p.Enter += (s, e) => EinstellungenAnzeigen();
            EinstellungenAnzeigen();
            return p;
        }

        TabPage SeiteWerkzeuge()
        {
            var p = new TabPage("Werkzeuge") { BackColor = Color.White, Padding = new Padding(12) };
            var reihe = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true };
            reihe.Controls.Add(Knopf("Prüfen", (s, e) => Pruefen(), "Wie pruefen.cmd: Companion, OBS, RM-CR, Netzwerk, Firewall, Audio …"));
            reihe.Controls.Add(Knopf("Mikrofone testen", (s, e) => Starten(Path.Combine(Program.Ordner, "mikrofone-testen.cmd")), "Pegel aller RM-CR-Kanäle live: in jedes Tischmikrofon sprechen"));
            reihe.Controls.Add(Knopf("Dienste neu starten", (s, e) => { Dienste.AlleNeuStarten(); Schreib("Dienste neu gestartet."); }));
            reihe.Controls.Add(Knopf("Aktualisieren", (s, e) => Aktualisieren(), "Neuen Stand von GitHub holen (C:\\Raum5) und installieren"));
            var logs = new FlowLayoutPanel { Dock = DockStyle.Top, AutoSize = true };
            foreach (var l in new[] { "teams-steuerung.log", "mikro-automatik.log", "raumsteuerung.log" })
            {
                string datei = l; logs.Controls.Add(Knopf(l, (s, e) => Starten("notepad.exe", Path.Combine(Program.Ordner, datei))));
            }
            ausgabe.Multiline = true; ausgabe.ReadOnly = true; ausgabe.ScrollBars = ScrollBars.Vertical; ausgabe.Dock = DockStyle.Fill;
            ausgabe.Font = new Font("Consolas", 9f); ausgabe.BackColor = Hell;
            p.Controls.Add(ausgabe); p.Controls.Add(new Label { Text = "Ausgabe:", Dock = DockStyle.Top, Height = 22, TextAlign = ContentAlignment.BottomLeft });
            p.Controls.Add(logs); p.Controls.Add(reihe);
            p.Controls.SetChildIndex(ausgabe, 0);
            p.Controls.Add(new Label { Text = "Version " + Program.Version, Dock = DockStyle.Bottom, ForeColor = Grau, Height = 20 });
            return p;
        }

        Button Knopf(string text, EventHandler klick, string hilfe = null)
        {
            var b = new Button { Text = text, AutoSize = true, Height = 32, Padding = new Padding(8, 2, 8, 2), Margin = new Padding(0, 0, 8, 8), FlatStyle = FlatStyle.System };
            b.Click += klick; if (hilfe != null) tip.SetToolTip(b, hilfe);
            return b;
        }

        // ---------- Status ----------
        void StatusHolen()
        {
            var c = cfg;
            Task.Run(() =>
            {
                List<Zeile> z; try { z = Status.Erheben(c); } catch (Exception ex) { z = new List<Zeile> { new Zeile("Prüfung", Ampel.Rot, ex.Message) }; }
                var ad = Status.Adressen();
                try { BeginInvoke((Action)(() => StatusZeigen(z, ad))); } catch { }
            });
        }

        void StatusZeigen(List<Zeile> z, List<string> ad)
        {
            var g = Status.Gesamt(z);
            tray.Icon = Symbol(g);
            int rot = z.Count(x => x.Farbe == Ampel.Rot), gelb = z.Count(x => x.Farbe == Ampel.Gelb);
            string kurz = g == Ampel.Gruen ? "Alles in Ordnung" : rot > 0 ? rot + " Fehler" + (gelb > 0 ? ", " + gelb + " Hinweis(e)" : "") : gelb + " Hinweis(e)";
            kopfStatus.Text = kurz + "   ·   " + DateTime.Now.ToString("HH:mm:ss");
            var probleme = z.Where(x => x.Farbe == Ampel.Rot || x.Farbe == Ampel.Gelb).Select(x => x.Name).ToList();
            string trayText = "Raumsteuerung 5: " + (probleme.Count == 0 ? "OK" : string.Join(", ", probleme));
            tray.Text = trayText.Length > 63 ? trayText.Substring(0, 60) + "…" : trayText;
            if (g == Ampel.Rot && letzte != Ampel.Rot && letzte != Ampel.Grau)
                tray.ShowBalloonTip(5000, "Raumsteuerung", "Problem: " + string.Join(", ", z.Where(x => x.Farbe == Ampel.Rot).Select(x => x.Name)), ToolTipIcon.Warning);
            letzte = g;

            statusTabelle.SuspendLayout(); statusTabelle.Controls.Clear(); statusTabelle.RowCount = 0;
            foreach (var x in z)
            {
                var punkt = new Label { Text = "●", ForeColor = Farbe(x.Farbe), Font = new Font("Segoe UI", 12f), AutoSize = true, Margin = new Padding(0, 4, 0, 0) };
                var name = new Label { Text = x.Name, Font = new Font(Font, FontStyle.Bold), AutoSize = true, ForeColor = Ink, Margin = new Padding(0, 7, 6, 0) };
                var text = new Label { Text = x.Text + (x.Farbe != Ampel.Gruen && x.Farbe != Ampel.Grau && x.Hilfe != "" ? "\n→ " + x.Hilfe : ""), AutoSize = true, MaximumSize = new Size(400, 0), Margin = new Padding(0, 7, 0, 4) };
                statusTabelle.Controls.Add(punkt); statusTabelle.Controls.Add(name); statusTabelle.Controls.Add(text);
            }
            statusTabelle.ResumeLayout();
            var alt = adressen.SelectedIndex;
            if (!adressen.Items.Cast<string>().SequenceEqual(ad)) { adressen.Items.Clear(); foreach (var a in ad) adressen.Items.Add(a); if (adressen.Items.Count > 0) adressen.SelectedIndex = Math.Max(0, Math.Min(alt, adressen.Items.Count - 1)); }
        }

        static Color Farbe(Ampel a) { return a == Ampel.Gruen ? Gruen : a == Ampel.Gelb ? Gelb : a == Ampel.Rot ? Rot : Grau; }

        Icon Symbol(Ampel a)
        {
            Icon i; if (icons.TryGetValue(a, out i)) return i;
            var bmp = new Bitmap(32, 32);
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias; g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                using (var b = new Icon(basis, 32, 32)) g.DrawIcon(b, new Rectangle(0, 0, 32, 32));
                if (a != Ampel.Grau)
                {
                    g.FillEllipse(Brushes.White, 15, 15, 17, 17);
                    using (var br = new SolidBrush(Farbe(a))) g.FillEllipse(br, 17, 17, 13, 13);
                }
            }
            i = Icon.FromHandle(bmp.GetHicon()); icons[a] = i; return i;
        }

        // ---------- Einstellungen ----------
        void EinstellungenAnzeigen()
        {
            cfg = Einstellungen.Laden();
            rmcrIp.Text = cfg.RmcrIp; link.Text = cfg.TeamsLink;
            for (int i = 0; i < 5; i++) mic[i].Text = cfg.Kanaele(i + 1);
            bildschirm.Items.Clear();
            bildschirm.Items.Add(new Wahl("", "Hauptbildschirm (automatisch)"));
            foreach (var s in Screen.AllScreens.OrderBy(s => s.DeviceName))
            {
                string nr = new string(s.DeviceName.Where(char.IsDigit).ToArray());
                bildschirm.Items.Add(new Wahl(nr, "Bildschirm " + nr + " – " + s.Bounds.Width + "×" + s.Bounds.Height + (s.Primary ? " (Hauptbildschirm)" : "")));
            }
            var akt = cfg.TeilenBildschirm;
            var treffer = bildschirm.Items.Cast<Wahl>().FirstOrDefault(w => w.Wert == akt);
            if (treffer == null) { treffer = new Wahl(akt, "„" + akt + "“ (aus mikro-automatik.json, nicht angeschlossen?)"); bildschirm.Items.Add(treffer); }
            bildschirm.SelectedItem = treffer;
            if (Einstellungen.AutostartAlle) { autostart.Checked = true; autostart.Enabled = false; autostart.Text = "Mit Windows starten (für alle Benutzer eingerichtet)"; }
            else autostart.Checked = Einstellungen.AutostartIch;
        }

        void Speichern()
        {
            try
            {
                System.Net.IPAddress ip;
                if (!System.Net.IPAddress.TryParse(rmcrIp.Text.Trim(), out ip)) throw new FormatException("RM-CR: „" + rmcrIp.Text + "“ ist keine IP-Adresse");
                if (link.Text.Trim() != "" && !link.Text.Trim().StartsWith("https://", StringComparison.OrdinalIgnoreCase)) throw new FormatException("Teams-Link muss mit https:// beginnen");
                var neu = Einstellungen.Laden();
                neu.RmcrIp = rmcrIp.Text.Trim();
                neu.TeilenBildschirm = ((Wahl)bildschirm.SelectedItem).Wert;
                for (int i = 0; i < 5; i++) neu.SetKanaele(i + 1, mic[i].Text);
                neu.TeamsLink = link.Text.Trim();
                neu.Speichern(); cfg = neu;
                if (autostart.Enabled) Einstellungen.AutostartIch = autostart.Checked;
                // Skripte lesen die Einstellungen beim Start
                foreach (var d in new[] { Dienste.Automatik, Dienste.Teams }) if (!d.Extern) d.NeuStarten();
                Program.Log("Einstellungen gespeichert");
                MessageBox.Show(this, "Gespeichert. Mikrofon-Automatik und Teams-Steuerung wurden neu gestartet.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "Nicht gespeichert", MessageBoxButtons.OK, MessageBoxIcon.Warning); }
        }

        class Wahl { public string Wert, Text; public Wahl(string w, string t) { Wert = w; Text = t; } public override string ToString() { return Text; } }

        // ---------- Werkzeuge ----------
        void Schreib(string s) { if (InvokeRequired) { BeginInvoke((Action)(() => Schreib(s))); return; } ausgabe.AppendText(s.Replace("\n", Environment.NewLine) + Environment.NewLine); }

        void Pruefen()
        {
            if (pruefLaeuft) return; pruefLaeuft = true; ausgabe.Clear(); Schreib("Prüfe …");
            Task.Run(() =>
            {
                Schreib(Ausfuehren("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(Program.Ordner, "pruefen.ps1") + "\"", 120000));
                pruefLaeuft = false;
            });
        }

        static string Ausfuehren(string exe, string arg, int ms)
        {
            try
            {
                var oem = Encoding.GetEncoding(CultureInfo.CurrentCulture.TextInfo.OEMCodePage);
                var p = Process.Start(new ProcessStartInfo(exe, arg)
                { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = oem, StandardErrorEncoding = oem, WorkingDirectory = Program.Ordner });
                var err = p.StandardError.ReadToEndAsync(); string o = p.StandardOutput.ReadToEnd();
                if (!p.WaitForExit(ms)) { try { p.Kill(); } catch { } o += "\n(abgebrochen nach " + ms / 1000 + " s)"; }
                string e = err.Result; return (o + (e.Trim() != "" ? "\n" + e : "")).TrimEnd();
            }
            catch (Exception ex) { return exe + ": " + ex.Message; }
        }

        void Aktualisieren()
        {
            const string repo = @"C:\Raum5";
            if (!Directory.Exists(Path.Combine(repo, ".git"))) { Schreib(repo + " ist kein Git-Ordner – erst tools\\Raum5_einrichten.ps1 ausführen."); return; }
            if (MessageBox.Show(this, "Neuen Stand von GitHub holen und installieren?\nDie Dienste starten dabei kurz neu (nicht während eines Meetings).", Text,
                MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return;
            ausgabe.Clear(); Schreib("git pull …");
            Task.Run(() =>
            {
                var o = Ausfuehren("git", "-C \"" + repo + "\" pull --ff-only", 120000); Schreib(o);
                if (o.IndexOf("fatal", StringComparison.OrdinalIgnoreCase) >= 0 || o.IndexOf("error", StringComparison.OrdinalIgnoreCase) >= 0) { Schreib("Abgebrochen."); return; }
                bool exeNeu = false;
                try { exeNeu = Kopieren(Path.Combine(repo, "Raumsteuerung"), Program.Ordner); }
                catch (Exception ex) { Schreib("Kopieren fehlgeschlagen: " + ex.Message); return; }
                BeginInvoke((Action)(() =>
                {
                    if (exeNeu)
                    {
                        Schreib("Neue Programmversion – starte neu …"); Program.Log("Update: neue Programmversion, Neustart");
                        Dienste.AlleStoppen();
                        Process.Start(new ProcessStartInfo(Application.ExecutablePath, "--tray --nach-update") { UseShellExecute = false });
                        beenden = true; tray.Visible = false; Application.Exit();
                    }
                    else { Dienste.AlleNeuStarten(); Schreib("Fertig, Dienste neu gestartet."); Program.Log("Update installiert"); }
                }));
            });
        }

        // wie installieren.ps1: alles außer Einstellungen/Protokollen; das laufende Programm wird umbenannt und ersetzt
        bool Kopieren(string von, string nach)
        {
            var behalten = new[] { "mikro-automatik.json", "teams-link.txt", "teilen-eintrag.txt" };
            bool exeNeu = false;
            foreach (var q in Directory.GetFiles(von))
            {
                string n = Path.GetFileName(q), z = Path.Combine(nach, n);
                if (behalten.Contains(n, StringComparer.OrdinalIgnoreCase) && File.Exists(z)) continue;
                if (n.EndsWith(".log", StringComparison.OrdinalIgnoreCase) || n.EndsWith(".bak", StringComparison.OrdinalIgnoreCase)) continue;
                if (File.Exists(z) && File.ReadAllBytes(z).SequenceEqual(File.ReadAllBytes(q))) continue;
                if (string.Equals(z, Application.ExecutablePath, StringComparison.OrdinalIgnoreCase))
                {
                    var alt = z + ".old"; if (File.Exists(alt)) File.Delete(alt);
                    File.Move(z, alt); File.Copy(q, z); exeNeu = true; Schreib("  " + n + " (neue Version)"); continue;
                }
                File.Copy(q, z, true); Schreib("  " + n);
            }
            return exeNeu;
        }

        static void Oeffnen(string url) { try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { } }
        void Starten(string datei, string arg = "")
        {
            try { Process.Start(new ProcessStartInfo(datei, arg) { UseShellExecute = true, WorkingDirectory = Program.Ordner }); }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, Text); }
        }

        // ---------- Fenster / Beenden ----------
        public void Zeigen()
        {
            Show(); if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            Activate(); BringToFront(); StatusHolen();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            // X = nur ausblenden; das Programm läuft im Infobereich weiter
            if (!beenden && e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); return; }
            tray.Visible = false; base.OnFormClosing(e);
        }

        void Beenden()
        {
            if (MessageBox.Show(this, "Raumsteuerung beenden?\nDanach funktionieren Tablet, Teams-Steuerung und Mikrofon-Automatik nicht mehr, bis das Programm wieder läuft.",
                Text, MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes) return;
            beenden = true; tray.Visible = false; Dienste.AlleStoppen(); Application.Exit();
        }
    }
}
