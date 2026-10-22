// Einstellungen: mikro-automatik.json (Name historisch; gemeinsam mit den Skripten), teams-link.txt, Autostart
using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace Raumsteuerung
{
    class Einstellungen
    {
        public Dictionary<string, object> Json = new Dictionary<string, object>();
        string JsonPfad { get { return Path.Combine(Program.Ordner, "mikro-automatik.json"); } }
        string LinkPfad { get { return Path.Combine(Program.Ordner, "teams-link.txt"); } }

        public string RmcrIp { get { return Text("rmcrIp", "192.168.137.185"); } set { Json["rmcrIp"] = value; } }
        public int RmcrPort { get { int p; return int.TryParse(Text("rmcrPort", "49280"), out p) ? p : 49280; } }
        // Bildschirm für "Präsentation zeigen": Windows-Nummer oder Teil des Namens, leer = Hauptbildschirm
        public string TeilenBildschirm
        {
            get { return Text("teilenBildschirm", ""); }
            set { if (string.IsNullOrWhiteSpace(value)) Json.Remove("teilenBildschirm"); else Json["teilenBildschirm"] = value.Trim(); }
        }
        // Bildschirm für das Teams-Fenster (Sprecherplatz): Windows-Nummer, Teil des Namens, "aus" = nicht verschieben,
        // leer = automatisch (erster Neben-Bildschirm, der nicht geteilt wird)
        public string TeamsBildschirm
        {
            get { return Text("teamsBildschirm", ""); }
            set { if (string.IsNullOrWhiteSpace(value)) Json.Remove("teamsBildschirm"); else Json["teamsBildschirm"] = value.Trim(); }
        }
        public string TeamsLink = "";
        public string Fehler;   // Datei da, aber nicht lesbar -> nicht speichern (sonst wären alle übrigen Werte weg)

        string Text(string k, string std) { object v; return Json.TryGetValue(k, out v) && v != null ? Convert.ToString(v, CultureInfo.InvariantCulture) : std; }

        public static Einstellungen Laden()
        {
            var e = new Einstellungen();
            try
            {
                if (File.Exists(e.JsonPfad))
                {
                    var o = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(e.JsonPfad, Encoding.UTF8)) as Dictionary<string, object>;
                    if (o != null) e.Json = o;
                }
            }
            catch (Exception ex) { e.Fehler = ex.Message; Program.Log("mikro-automatik.json nicht lesbar: " + ex.Message); }
            try { if (File.Exists(e.LinkPfad)) e.TeamsLink = (File.ReadAllLines(e.LinkPfad, Encoding.UTF8).FirstOrDefault(s => s.Trim() != "") ?? "").Trim(); } catch { }
            return e;
        }

        public void Speichern()
        {
            if (Fehler != null) throw new InvalidOperationException("mikro-automatik.json ist nicht lesbar (" + Fehler + ") – bitte im Editor prüfen oder die .bak-Datei zurückkopieren. Nichts überschrieben.");
            // vorher sichern: die Skripte lesen dieselbe Datei
            if (File.Exists(JsonPfad)) File.Copy(JsonPfad, JsonPfad + ".bak", true);
            File.WriteAllText(JsonPfad, Schreiben(Json, 0) + Environment.NewLine, new UTF8Encoding(false));
            if (TeamsLink.Trim() != "") File.WriteAllText(LinkPfad, TeamsLink.Trim(), new UTF8Encoding(false));
        }

        // Kleines JSON mit Einrückung (wie bisher von Hand bearbeitbar)
        static string Schreiben(object o, int tiefe)
        {
            string ein = new string(' ', tiefe + 1), aus = new string(' ', tiefe);
            if (o == null) return "null";
            if (o is string) return new JavaScriptSerializer().Serialize(o);
            if (o is bool) return (bool)o ? "true" : "false";
            if (o is IDictionary)
            {
                var d = (IDictionary)o; if (d.Count == 0) return "{}";
                var teile = d.Keys.Cast<object>().Select(k => ein + new JavaScriptSerializer().Serialize(k.ToString()) + ": " + Schreiben(d[k], tiefe + 1));
                return "{\n" + string.Join(",\n", teile) + "\n" + aus + "}";
            }
            if (o is IEnumerable)
                return "[" + string.Join(", ", ((IEnumerable)o).Cast<object>().Select(x => Schreiben(x, tiefe + 1))) + "]";
            return Convert.ToString(o, CultureInfo.InvariantCulture);
        }

        // ---------- Autostart ----------
        const string Run = @"Software\Microsoft\Windows\CurrentVersion\Run", Wert = "Raumsteuerung";
        public static bool AutostartAlle { get { try { using (var k = Registry.LocalMachine.OpenSubKey(Run)) return k != null && k.GetValue(Wert) != null; } catch { return false; } } }
        public static bool AutostartIch
        {
            get { try { using (var k = Registry.CurrentUser.OpenSubKey(Run)) return k != null && k.GetValue(Wert) != null; } catch { return false; } }
            set
            {
                using (var k = Registry.CurrentUser.CreateSubKey(Run))
                    if (value) k.SetValue(Wert, "\"" + System.Windows.Forms.Application.ExecutablePath + "\" --tray"); else k.DeleteValue(Wert, false);
            }
        }
    }
}
