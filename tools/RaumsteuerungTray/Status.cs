// Zustand aller Teile (wie pruefen.ps1, aber laufend und ohne Konsole)
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;

namespace Raumsteuerung
{
    enum Ampel { Grau, Gruen, Gelb, Rot }

    class Zeile
    {
        public string Name, Text, Hilfe = "";
        public Ampel Farbe;
        public Zeile(string n, Ampel f, string t, string h = "") { Name = n; Farbe = f; Text = t; Hilfe = h; }
    }

    static class Status
    {
        const string Companion = "http://127.0.0.1:8000";
        static DateTime rmcrZeit = DateTime.MinValue; static Zeile rmcrZeile;

        public static string Get(string url, int ms = 2000)
        {
            try
            {
                var rq = (HttpWebRequest)WebRequest.Create(url); rq.Timeout = ms; rq.ReadWriteTimeout = ms; rq.Proxy = null;
                using (var rs = (HttpWebResponse)rq.GetResponse()) using (var sr = new StreamReader(rs.GetResponseStream(), Encoding.UTF8))
                    return sr.ReadToEnd();
            }
            catch { return null; }
        }

        static string Var(string name) { var v = Get(Companion + "/api/custom-variable/" + name + "/value"); return v == null ? null : v.Trim(); }

        public static List<Zeile> Erheben(Einstellungen cfg)
        {
            var z = new List<Zeile>();
            // Companion + OBS
            string room = Var("r5_room");
            if (room == null && Get(Companion + "/") != null) room = "not found";   // Companion läuft, Variable fehlt (404)
            if (room == null) z.Add(new Zeile("Companion", Ampel.Rot, "nicht erreichbar (Port 8000)", "Companion starten (Desktop-Symbol), „Run at login“ anhaken"));
            else if (room.IndexOf("not found", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                z.Add(new Zeile("Companion", Ampel.Rot, "läuft, aber die Raum5-Konfiguration fehlt", "Raum5_Companion.companionconfig importieren"));
                room = null;
            }
            else
            {
                z.Add(new Zeile("Companion", Ampel.Gruen, "verbunden"));
                string szene = Get(Companion + "/api/variable/obs/scene_active/value");
                szene = szene == null ? "" : szene.Trim();
                if (szene == "") z.Add(new Zeile("OBS", Ampel.Rot, "Companion ist nicht mit OBS verbunden", "OBS läuft? WebSocket-Passwort in Companion (Verbindung „obs“)"));
                else z.Add(new Zeile("OBS", Ampel.Gruen, "Szene: " + szene));
                string live = Var("r5_live");
                z.Add(new Zeile("Raum", Ampel.Grau, room == "1" ? (live == "1" ? "an, Kamera läuft" : "an") : "aus"));
            }
            // RM-CR (eigene kurze Verbindung nur alle 20 s - der Prozessor nimmt nur wenige Verbindungen an)
            if ((DateTime.Now - rmcrZeit).TotalSeconds >= 20 || rmcrZeile == null)
            {
                rmcrZeit = DateTime.Now;
                bool ok = false;
                try { using (var c = new TcpClient()) { var ar = c.BeginConnect(cfg.RmcrIp, cfg.RmcrPort, null, null); ok = ar.AsyncWaitHandle.WaitOne(1500) && c.Connected; } } catch { }
                rmcrZeile = ok ? new Zeile("RM-CR", Ampel.Gruen, cfg.RmcrIp + " erreichbar")
                               : new Zeile("RM-CR", Ampel.Gelb, cfg.RmcrIp + " nicht erreichbar", "Netzwerkkabel / IP prüfen (Einstellungen)");
            }
            z.Add(rmcrZeile);
            // Dienste
            var web = Get("http://127.0.0.1:8080/manifest.json");
            z.Add(DienstZeile(Dienste.Webserver, web != null, web != null ? "Tablet-Seite erreichbar" : "Port 8080 antwortet nicht"));
            z.Add(LogZeile(Dienste.Automatik, "mikro-automatik.log"));
            var tz = LogZeile(Dienste.Teams, "teams-steuerung.log");
            if (room != null && tz.Farbe == Ampel.Gruen)
            {
                string modus = Var("r5_t_mode"), tin = Var("r5_t_in"), st = Var("r5_t_status") ?? "";
                tz.Text = (tin == "1" ? "im Meeting" : "kein Meeting") + ", Modus " + (modus ?? "?") + (st != "" ? " - " + st : "");
                if (st.StartsWith("fehler", StringComparison.OrdinalIgnoreCase)) tz.Farbe = Ampel.Gelb;
            }
            z.Add(tz);
            bool teams = Process.GetProcessesByName("ms-teams").Length > 0;
            z.Add(new Zeile("Teams", teams ? Ampel.Gruen : Ampel.Gelb, teams ? "läuft" : "nicht gestartet", "Teams starten, „Teams automatisch starten“ anhaken"));
            // Netzwerk
            var nz = Netz();
            if (nz != null) z.Add(nz);
            return z;
        }

        static Zeile DienstZeile(Dienst d, bool ok, string text)
        {
            if (d.Extern) return new Zeile(d.Name, ok ? Ampel.Gelb : Ampel.Rot, text + " (über Aufgabenplanung)", "installieren.ps1 als Administrator ausführen, um auf das Programm umzustellen");
            if (d.Aus) return new Zeile(d.Name, Ampel.Gelb, "angehalten");
            return new Zeile(d.Name, ok && d.Laeuft ? Ampel.Gruen : Ampel.Rot, d.Laeuft ? text : d.Zustand);
        }

        static Zeile LogZeile(Dienst d, string log)
        {
            string letzte = LetzteZeile(Path.Combine(Program.Ordner, log));
            bool lauf = d.Extern || d.Laeuft;
            var z = DienstZeile(d, lauf, letzte == null ? "läuft" : (letzte.Length > 21 ? letzte.Substring(21) : letzte));
            if (z.Farbe == Ampel.Gruen && letzte != null && letzte.IndexOf("Fehler", StringComparison.OrdinalIgnoreCase) >= 0) z.Farbe = Ampel.Gelb;
            return z;
        }

        public static string LetzteZeile(string pfad)
        {
            try
            {
                using (var fs = new FileStream(pfad, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    long start = Math.Max(0, fs.Length - 4096); fs.Seek(start, SeekOrigin.Begin);
                    var t = new StreamReader(fs, Encoding.UTF8).ReadToEnd();
                    var zeilen = t.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
                    return zeilen.Length > 0 ? zeilen[zeilen.Length - 1].Trim() : null;
                }
            }
            catch { return null; }
        }

        // Adressen für das Tablet + Warnung, wenn das Netz "Öffentlich" ist (Firewall-Regeln gelten nur Privat/Domäne)
        public static List<string> Adressen()
        {
            var l = new List<string>();
            try
            {
                foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
                {
                    if (ni.OperationalStatus != OperationalStatus.Up || ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                    foreach (var a in ni.GetIPProperties().UnicastAddresses)
                        if (a.Address.AddressFamily == AddressFamily.InterNetwork && !a.Address.ToString().StartsWith("169.254."))
                            l.Add("http://" + a.Address + ":8080   (" + ni.Name + ")");
                }
            }
            catch { }
            return l;
        }

        static DateTime netzZeit = DateTime.MinValue; static Zeile netzZeile;
        static Zeile Netz()
        {
            if ((DateTime.Now - netzZeit).TotalSeconds < 60 && netzZeile != null) return netzZeile;
            netzZeit = DateTime.Now;
            try
            {
                var p = Process.Start(new ProcessStartInfo("powershell.exe",
                    "-NoProfile -Command \"Get-NetConnectionProfile | ForEach-Object { $_.InterfaceAlias + '|' + $_.NetworkCategory }\"")
                { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true });
                string o = p.StandardOutput.ReadToEnd(); p.WaitForExit(8000);
                var oeff = o.Split('\n').Select(s => s.Trim()).Where(s => s.EndsWith("|Public")).Select(s => s.Split('|')[0]).ToList();
                netzZeile = oeff.Count == 0 ? new Zeile("Netzwerk", Ampel.Gruen, "Profil Privat/Domäne")
                    : new Zeile("Netzwerk", Ampel.Gelb, "„Öffentlich“: " + string.Join(", ", oeff), "Tablet erreicht den PC nicht: Einstellungen → Netzwerk → Netzwerkprofiltyp „Privat“");
            }
            catch { netzZeile = null; }
            return netzZeile;
        }

        public static Ampel Gesamt(List<Zeile> z)
        {
            if (z.Any(x => x.Farbe == Ampel.Rot)) return Ampel.Rot;
            if (z.Any(x => x.Farbe == Ampel.Gelb)) return Ampel.Gelb;
            return Ampel.Gruen;
        }
    }
}
