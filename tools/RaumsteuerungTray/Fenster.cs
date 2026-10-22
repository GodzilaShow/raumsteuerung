// Fenster + Symbol im Infobereich (Aufbau wie Systemeinstellungen: Seitenleiste links, gruppierte Listen rechts)
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
    // Seite: Inhalte untereinander, volle Breite, scrollbar
    class Stapel : Panel
    {
        public Stapel() { AutoScroll = true; BackColor = Theme.Grund; Padding = new Padding(28, 22, 28, 22); Dock = DockStyle.Fill; DoubleBuffered = true; }
        public T Dazu<T>(T c, int abstand = 18) where T : Control { c.Margin = new Padding(0, 0, 0, abstand); Controls.Add(c); return c; }
        protected override void OnLayout(LayoutEventArgs e)
        {
            int y = Padding.Top + AutoScrollPosition.Y, w = ClientSize.Width - Padding.Horizontal;
            foreach (Control c in Controls) { if (!c.Visible) continue; c.SetBounds(Padding.Left, y, w, c.Height); if (c is Gruppe) c.PerformLayout(); y += c.Height + c.Margin.Bottom; }
            base.OnLayout(e);   // berechnet die Scrollfläche aus den Positionen
        }
        // Scrollrad überall auf der Seite (auch über Knöpfen/Listen, die selbst nicht scrollen)
        public void Rad(int delta)
        {
            int y = -AutoScrollPosition.Y - delta / 120 * 60;
            AutoScrollPosition = new Point(0, Math.Max(0, y));
        }
    }

    class Reihe : FlowLayoutPanel
    {
        public Reihe(params Control[] c) { AutoSize = false; Height = 36; WrapContents = false; BackColor = Theme.Grund; foreach (var x in c) { x.Margin = new Padding(0, 0, 10, 0); Controls.Add(x); } }
    }

    class Ueberschrift : Control
    {
        public Ueberschrift(string t, string unter = null) { Text = t; Tag = unter; Height = unter == null ? 34 : 56; SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true); }
        protected override void OnPaint(PaintEventArgs e)
        {
            e.Graphics.Clear(Theme.Grund);
            TextRenderer.DrawText(e.Graphics, Text, Theme.Schrift(17f, FontStyle.Bold, true), new Point(0, 0), Theme.Text);
            if (Tag != null) TextRenderer.DrawText(e.Graphics, (string)Tag, Theme.Schrift(10f), new Point(1, 32), Theme.Leise);
        }
    }

    class Fenster : Form, IMessageFilter
    {
        readonly NotifyIcon tray = new NotifyIcon();
        readonly Icon basis;
        readonly Dictionary<Ampel, Icon> icons = new Dictionary<Ampel, Icon>();
        readonly Navi navi = new Navi();
        readonly Stapel[] seiten = new Stapel[3];
        Stapel werkzeugSeite;
        readonly Lage lage = new Lage();
        readonly StatusListe liste = new StatusListe();
        readonly Gruppe tablet = new Gruppe("Tablet");
        readonly TextBox ausgabe = new TextBox();
        Gruppe ausgabeKarte;
        Feld rmcrIp, link; Auswahl bildschirm; readonly Feld[] mic = new Feld[5]; Schalter autostart;
        Eintrag autostartZeile;
        Einstellungen cfg = Einstellungen.Laden();
        Ampel letzte = Ampel.Grau;
        List<string> letzteAdressen = new List<string>();
        bool pruefLaeuft, beenden;
        readonly System.Windows.Forms.Timer dienstTimer = new System.Windows.Forms.Timer { Interval = 2000 };
        readonly System.Windows.Forms.Timer statusTimer = new System.Windows.Forms.Timer { Interval = 5000 };

        public int Seite { set { navi.Aktiv = Math.Max(0, Math.Min(value, seiten.Length - 1)); } }

        public Fenster(EventWaitHandle zeigen)
        {
            Text = "Raumsteuerung";
            Font = Theme.Schrift(10f); AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(900, 680); MinimumSize = new Size(720, 520);
            StartPosition = FormStartPosition.CenterScreen; BackColor = Theme.Grund;
            try { basis = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { basis = SystemIcons.Application; }
            Icon = basis;

            seiten[0] = SeiteStatus(); seiten[1] = SeiteEinstellungen(); seiten[2] = werkzeugSeite = SeiteWerkzeuge();
            foreach (var s in seiten) { s.Visible = false; Controls.Add(s); }
            navi.Dock = DockStyle.Left; navi.Width = 220;
            navi.Punkte.Add(new[] { "Übersicht", "" }); navi.Punkte.Add(new[] { "Einstellungen", "" }); navi.Punkte.Add(new[] { "Werkzeuge", "" });
            navi.Gewaehlt += i => { for (int k = 0; k < seiten.Length; k++) seiten[k].Visible = k == i; if (i == 1) EinstellungenAnzeigen(); seiten[i].PerformLayout(); };
            Controls.Add(navi);
            navi.Aktiv = 0;

            // Infobereich
            var menu = new ContextMenuStrip { Renderer = new MenueStil(), Font = Theme.Schrift(10f), ShowImageMargin = false, Padding = new Padding(4) };
            menu.Items.Add("Raumsteuerung öffnen", null, (s, e) => Zeigen()).Font = Theme.Schrift(10f, FontStyle.Bold);
            menu.Items.Add("Tablet-Seite öffnen", null, (s, e) => Oeffnen("http://127.0.0.1:8080/"));
            menu.Items.Add("Companion öffnen", null, (s, e) => Oeffnen("http://127.0.0.1:8000/"));
            menu.Items.Add("Dienste neu starten", null, (s, e) => Dienste.AlleNeuStarten());
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Beenden", null, (s, e) => Beenden());
            foreach (ToolStripItem it in menu.Items) it.Padding = new Padding(6, 4, 6, 4);
            tray.ContextMenuStrip = menu; tray.Text = "Raumsteuerung Sitzungszimmer 5"; tray.Icon = Symbol(Ampel.Grau); tray.Visible = true;
            tray.MouseClick += (s, e) => { if (e.Button == MouseButtons.Left) Zeigen(); };

            var t = new Thread(() => { while (true) { zeigen.WaitOne(); try { BeginInvoke((Action)Zeigen); } catch { } } }) { IsBackground = true };
            t.Start();

            CreateHandle();
            Theme.Titelleiste(this);
            Application.AddMessageFilter(this);
            if (!Dienste.AlteAufgaben) foreach (var d in Dienste.Alle) d.Starten();
            dienstTimer.Tick += (s, e) => Dienste.Pruefen(); dienstTimer.Start();
            statusTimer.Tick += (s, e) => StatusHolen(); statusTimer.Start();
            StatusHolen();
        }

        // WM_MOUSEWHEEL an die sichtbare Seite unter dem Mauszeiger
        public bool PreFilterMessage(ref Message m)
        {
            if (m.Msg != 0x020A || !Visible) return false;
            var seite = seiten.FirstOrDefault(s => s.Visible);
            if (seite == null || !seite.RectangleToScreen(seite.ClientRectangle).Contains(Cursor.Position)) return false;
            seite.Rad((short)((long)m.WParam >> 16));
            return true;
        }

        // ---------- Seiten ----------
        Stapel SeiteStatus()
        {
            var p = new Stapel();
            p.Dazu(lage, 14);
            p.Dazu(tablet, 22);
            p.Dazu(new Abschnitt("Technik"), 0);
            p.Dazu(liste, 18);
            p.Dazu(new Reihe(new Knopf("Tablet-Seite öffnen", false, "") { }, new Knopf("Companion öffnen", false, "")), 0);
            foreach (Control c in p.Controls) if (c is Reihe) { var k = c.Controls.Cast<Control>().ToList(); k[0].Click += (s, e) => Oeffnen("http://127.0.0.1:8080/"); k[1].Click += (s, e) => Oeffnen("http://127.0.0.1:8000/"); }
            return p;
        }

        Stapel SeiteEinstellungen()
        {
            var p = new Stapel();
            p.Dazu(new Ueberschrift("Einstellungen", "Änderungen gelten nach „Speichern“ sofort – die Dienste starten dafür kurz neu."), 16);
            var verb = p.Dazu(new Gruppe("Verbindung"));
            rmcrIp = new Feld("z. B. 192.168.137.185"); rmcrIp.Width = 220;
            verb.Zeile(new Eintrag("Audio-Prozessor RM-CR", "IP-Adresse im AV-Netz", rmcrIp, 220));
            link = new Feld("https://teams.microsoft.com/…");
            verb.Zeile(new Eintrag("Teams-Meeting", "Fester Link des Raums", link, 340) { Linie = true });
            var praes = p.Dazu(new Gruppe("Präsentation zeigen"));
            bildschirm = new Auswahl { Width = 320 };
            praes.Zeile(new Eintrag("Bildschirm", "Diesen Bildschirm teilt Teams", bildschirm, 320));
            var mics = p.Dazu(new Gruppe("Tischmikrofone → RM-CR-Kanal"));
            for (int i = 0; i < 5; i++)
            {
                mic[i] = new Feld(i == 0 ? "z. B. 1  oder  1, 2" : "leer = nicht vorhanden"); mic[i].Width = 220;
                mics.Zeile(new Eintrag("Mikrofon " + (i + 1), null, mic[i], 220) { Linie = i > 0 });
            }
            var start = p.Dazu(new Gruppe("Start"));
            autostart = new Schalter();
            autostartZeile = new Eintrag("Mit Windows starten", "Startet bei der Anmeldung im Infobereich", autostart);
            start.Zeile(autostartZeile);
            var speichern = new Knopf("Speichern", true); speichern.Click += (s, e) => Speichern();
            var verwerfen = new Knopf("Verwerfen"); verwerfen.Click += (s, e) => EinstellungenAnzeigen();
            p.Dazu(new Reihe(speichern, verwerfen), 0);
            return p;
        }

        Stapel SeiteWerkzeuge()
        {
            var p = new Stapel();
            p.Dazu(new Ueberschrift("Werkzeuge"), 16);
            var w = p.Dazu(new Gruppe());
            Func<string, bool, EventHandler, Knopf> k = (txt, haupt, h) => { var b = new Knopf(txt, haupt); b.Click += h; return b; };
            w.Zeile(new Eintrag("Anlage prüfen", "Companion, OBS, RM-CR, Netzwerk, Firewall, Audio", k("Prüfen", false, (s, e) => Pruefen())));
            w.Zeile(new Eintrag("Mikrofone testen", "Pegel aller Kanäle live – nacheinander in jedes Mikrofon sprechen",
                k("Öffnen", false, (s, e) => Starten(Path.Combine(Program.Ordner, "mikrofone-testen.cmd")))) { Linie = true });
            w.Zeile(new Eintrag("Dienste neu starten", "Webserver, Mikrofon-Automatik, Teams-Steuerung",
                k("Neu starten", false, (s, e) => { Dienste.AlleNeuStarten(); ausgabeKarte.Visible = true; Schreib("Dienste neu gestartet."); werkzeugSeite.PerformLayout(); })) { Linie = true });
            w.Zeile(new Eintrag("Aktualisieren", "Neuen Stand von GitHub holen und installieren", k("Aktualisieren", false, (s, e) => Aktualisieren())) { Linie = true });
            var logs = p.Dazu(new Gruppe("Protokolle"));
            bool erste = true;
            foreach (var l in new[] { new[] { "Teams-Steuerung", "teams-steuerung.log" }, new[] { "Mikrofon-Automatik", "mikro-automatik.log" }, new[] { "Raumsteuerung", "raumsteuerung.log" } })
            {
                string datei = l[1];
                logs.Zeile(new Eintrag(l[0], datei, k("Öffnen", false, (s, e) => Starten("notepad.exe", Path.Combine(Program.Ordner, datei)))) { Linie = !erste });
                erste = false;
            }
            ausgabeKarte = p.Dazu(new Gruppe("Ausgabe"), 0);
            ausgabe.Multiline = true; ausgabe.ReadOnly = true; ausgabe.ScrollBars = ScrollBars.Vertical; ausgabe.BorderStyle = BorderStyle.None;
            ausgabe.Font = Theme.Mono(9f); ausgabe.BackColor = Color.White; ausgabe.ForeColor = Theme.Text; ausgabe.Height = 260;
            var huelle = new Panel { Height = 280, BackColor = Color.White, Padding = new Padding(16, 10, 10, 10) };
            ausgabe.Dock = DockStyle.Fill; huelle.Controls.Add(ausgabe);
            ausgabeKarte.Zeile(huelle); ausgabeKarte.Visible = false;
            return p;
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
            var probleme = z.Where(x => x.Farbe == Ampel.Rot || x.Farbe == Ampel.Gelb).ToList();
            lage.Farbe = g;
            lage.Satz = g == Ampel.Gruen ? "Alles bereit" : probleme.Count == 1 ? probleme[0].Name + " braucht Aufmerksamkeit" : probleme.Count + " Dinge brauchen Aufmerksamkeit";
            lage.Unter = g == Ampel.Gruen ? "Tablet, Teams und Automatik laufen." : "Was zu tun ist, steht unten bei „Technik“.";
            lage.Zeit = "Geprüft " + DateTime.Now.ToString("HH:mm:ss");
            lage.Invalidate();
            string trayText = "Raumsteuerung 5: " + (probleme.Count == 0 ? "alles bereit" : string.Join(", ", probleme.Select(x => x.Name)));
            tray.Text = trayText.Length > 63 ? trayText.Substring(0, 60) + "…" : trayText;
            if (g == Ampel.Rot && letzte != Ampel.Rot && letzte != Ampel.Grau)
                tray.ShowBalloonTip(5000, "Raumsteuerung", "Problem: " + string.Join(", ", z.Where(x => x.Farbe == Ampel.Rot).Select(x => x.Name)), ToolTipIcon.Warning);
            letzte = g;
            liste.Setzen(z);
            if (!ad.SequenceEqual(letzteAdressen))
            {
                letzteAdressen = ad;
                foreach (var c in tablet.Zeilen.ToList()) { tablet.Controls.Remove(c); c.Dispose(); }
                tablet.Zeilen.Clear();
                bool erste = true;
                foreach (var a in ad)
                {
                    string url = a.Split(' ')[0], netz = a.Substring(url.Length).Trim().Trim('(', ')');
                    var kopie = new Knopf("Kopieren", false, ""); kopie.Click += (s, e) => { try { Clipboard.SetText(url); kopie.Text = "Kopiert"; } catch { } };
                    tablet.Zeile(new Eintrag(url, "Im Browser des Tablets öffnen · " + netz, kopie) { Linie = !erste });
                    erste = false;
                }
                if (ad.Count == 0) tablet.Zeile(new Eintrag("Kein Netzwerk", "Der PC hat keine IP-Adresse"));
            }
            seiten[0].PerformLayout();
        }

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
                    using (var br = new SolidBrush(Theme.Ampel(a))) g.FillEllipse(br, 17, 17, 13, 13);
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
            bildschirm.Eintraege.Clear();
            bildschirm.Eintraege.Add(new KeyValuePair<string, string>("", "Hauptbildschirm (automatisch)"));
            foreach (var s in Screen.AllScreens.OrderBy(s => s.DeviceName))
            {
                string nr = new string(s.DeviceName.Where(char.IsDigit).ToArray());
                bildschirm.Eintraege.Add(new KeyValuePair<string, string>(nr, "Bildschirm " + nr + " – " + s.Bounds.Width + " × " + s.Bounds.Height + (s.Primary ? " (Haupt)" : "")));
            }
            var akt = cfg.TeilenBildschirm;
            if (!bildschirm.Eintraege.Any(w => w.Key == akt)) bildschirm.Eintraege.Add(new KeyValuePair<string, string>(akt, "„" + akt + "“ – nicht angeschlossen?"));
            bildschirm.Wert = akt;
            if (Einstellungen.AutostartAlle) { autostart.An = true; autostart.Enabled = false; autostartZeile.Unter = "Für alle Benutzer eingerichtet (installieren.ps1)"; autostartZeile.Invalidate(); }
            else autostart.An = Einstellungen.AutostartIch;
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
                neu.TeilenBildschirm = bildschirm.Wert;
                for (int i = 0; i < 5; i++) neu.SetKanaele(i + 1, mic[i].Text);
                neu.TeamsLink = link.Text.Trim();
                neu.Speichern(); cfg = neu;
                if (autostart.Enabled) Einstellungen.AutostartIch = autostart.An;
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
            if (pruefLaeuft) return; pruefLaeuft = true; ausgabeKarte.Visible = true; ausgabe.Clear(); Schreib("Prüfe …"); werkzeugSeite.PerformLayout();
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
            ausgabeKarte.Visible = true; ausgabe.Clear(); Schreib("git pull …"); werkzeugSeite.PerformLayout();
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
