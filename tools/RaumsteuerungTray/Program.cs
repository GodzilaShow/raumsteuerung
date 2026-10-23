// Raumsteuerung Sitzungszimmer 5 - ein Programm statt Aufgabenplanung + Konsolenfenster.
// Startet Webserver und Teams-Steuerung unsichtbar, zeigt den Zustand im Infobereich (Tray),
// Einstellungen ohne JSON-Bearbeitung, Prüfen per Knopf. Aktualisieren: installieren.ps1 erneut ausführen.
// Läuft als angemeldeter Benutzer (Teams-Steuerung braucht den Desktop). Start: Autostart „--tray“.
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace Raumsteuerung
{
    static class Program
    {
        public const string Version = "1.7";
        public static string Ordner;
        static string logPfad;
        static readonly object logSperre = new object();

        [STAThread]
        static void Main(string[] args)
        {
            Ordner = Path.GetDirectoryName(Application.ExecutablePath);
            logPfad = Path.Combine(Ordner, "raumsteuerung.log");
            bool tray = args.Any(a => a.Equals("--tray", StringComparison.OrdinalIgnoreCase));

            bool neu;
            var mutex = new Mutex(true, @"Local\Raumsteuerung5", out neu);
            var zeigen = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\Raumsteuerung5_Zeigen");
            if (!neu) { zeigen.Set(); return; }   // läuft schon -> dessen Fenster zeigen
            try { var alt = Application.ExecutablePath + ".old"; if (File.Exists(alt)) File.Delete(alt); } catch { }   // Rest der früheren Update-Funktion

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Log("Start Raumsteuerung " + Version + " in " + Ordner + ", Benutzer " + Environment.UserName);
            Dienste.Erkennen();
            var f = new Fenster(zeigen);
            int seite; var sa = args.FirstOrDefault(a => a.StartsWith("--seite="));
            if (sa != null && int.TryParse(sa.Substring(8), out seite)) f.Seite = seite;   // zum Testen / Verknüpfungen
            if (!tray) f.Zeigen();
            Application.Run();
            Dienste.AlleStoppen();
            Log("Ende");
            GC.KeepAlive(mutex);
        }

        public static void Log(string msg)
        {
            lock (logSperre)
            {
                try
                {
                    if (File.Exists(logPfad) && new FileInfo(logPfad).Length > 1024 * 1024) File.Copy(logPfad, logPfad + ".alt", true);
                    if (File.Exists(logPfad + ".alt") && File.Exists(logPfad) && new FileInfo(logPfad).Length > 1024 * 1024) File.Delete(logPfad);
                    File.AppendAllText(logPfad, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + msg + Environment.NewLine, Encoding.UTF8);
                }
                catch { }
            }
        }
    }
}
