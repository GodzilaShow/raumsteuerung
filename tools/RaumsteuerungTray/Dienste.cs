// Raumsteuerung Sitzungszimmer 5 - Hintergrunddienste (PowerShell-Skripte) unsichtbar starten und überwachen.
// Die Skripte bleiben, wie sie sind (getestet); das Programm ersetzt nur die Aufgabenplanung.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;

namespace Raumsteuerung
{
    // Alle Kindprozesse hängen an einem Job-Objekt: endet das Programm (auch Absturz/Abmelden), endet Windows sie mit.
    static class Job
    {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr a, string name);
        [DllImport("kernel32.dll")] static extern bool SetInformationJobObject(IntPtr job, int cls, IntPtr info, uint len);
        [DllImport("kernel32.dll")] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr proc);

        [StructLayout(LayoutKind.Sequential)]
        struct BASIC { public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass; }
        [StructLayout(LayoutKind.Sequential)]
        struct IO { public ulong a, b, c, d, e, f; }
        [StructLayout(LayoutKind.Sequential)]
        struct EXT { public BASIC Basic; public IO Io; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }

        static IntPtr handle = IntPtr.Zero;
        public static void Add(Process p)
        {
            try
            {
                if (handle == IntPtr.Zero)
                {
                    handle = CreateJobObject(IntPtr.Zero, null);
                    var ext = new EXT(); ext.Basic.LimitFlags = 0x2000;   // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
                    int len = Marshal.SizeOf(typeof(EXT)); IntPtr ptr = Marshal.AllocHGlobal(len);
                    Marshal.StructureToPtr(ext, ptr, false);
                    SetInformationJobObject(handle, 9, ptr, (uint)len);   // JobObjectExtendedLimitInformation
                    Marshal.FreeHGlobal(ptr);
                }
                AssignProcessToJobObject(handle, p.Handle);
            }
            catch { }
        }
    }

    class Dienst
    {
        public readonly string Name, Skript;
        public Process Proc;
        public string Zustand = "startet …";
        public bool Extern;            // läuft noch über die alte Aufgabenplanung -> nicht doppelt starten
        public bool Aus;               // bewusst angehalten (z. B. Mikrofone testen)
        DateTime naechsterStart = DateTime.MinValue;
        int fehlstarts;
        DateTime gestartet;

        public Dienst(string name, string skript) { Name = name; Skript = skript; }

        public bool Laeuft { get { try { return Proc != null && !Proc.HasExited; } catch { return false; } } }

        public void Pruefen()
        {
            if (Extern || Aus) return;
            if (Laeuft) { if ((DateTime.Now - gestartet).TotalMinutes > 2) fehlstarts = 0; return; }
            if (Proc != null)
            {
                int code = -1; try { code = Proc.ExitCode; } catch { }
                Program.Log(Name + " beendet (Code " + code + "), Neustart folgt");
                Proc = null; fehlstarts++;
                naechsterStart = DateTime.Now.AddSeconds(Math.Min(60, 3 * fehlstarts));
                Zustand = "beendet - Neustart …";
            }
            if (DateTime.Now >= naechsterStart) Starten();
        }

        public void Starten()
        {
            string pfad = Path.Combine(Program.Ordner, Skript);
            if (!File.Exists(pfad)) { Zustand = Skript + " fehlt"; naechsterStart = DateTime.Now.AddSeconds(30); return; }
            var psi = new ProcessStartInfo("powershell.exe",
                "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + pfad + "\"")
            { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Program.Ordner };
            try
            {
                Proc = Process.Start(psi); Job.Add(Proc); gestartet = DateTime.Now; Zustand = "läuft";
                Program.Log(Name + " gestartet (PID " + Proc.Id + ")");
            }
            catch (Exception e) { var m = e.Message.Split('\n')[0]; Zustand = "Start fehlgeschlagen: " + (m.Length > 120 ? m.Substring(0, 120) + " …" : m); Program.Log(Name + ": " + e.Message); naechsterStart = DateTime.Now.AddSeconds(30); }
        }

        public void Stoppen()
        {
            try { if (Laeuft) { Proc.Kill(); Proc.WaitForExit(3000); } } catch { }
            Proc = null; naechsterStart = DateTime.MinValue; fehlstarts = 0;
        }

        public void NeuStarten() { Stoppen(); Aus = false; Starten(); }
    }

    static class Dienste
    {
        public static readonly Dienst Webserver = new Dienst("Webserver", "server.ps1");
        public static readonly Dienst Automatik = new Dienst("Mikrofon-Automatik", "mikro-automatik.ps1");
        public static readonly Dienst Teams = new Dienst("Teams-Steuerung", "teams-steuerung.ps1");
        public static readonly Dienst[] Alle = { Webserver, Automatik, Teams };
        public static bool AlteAufgaben;

        // Vor dem ersten Start: laufen die Skripte noch über die Aufgabenplanung (vor der Umstellung mit installieren.ps1)?
        public static void Erkennen()
        {
            AlteAufgaben = AufgabeVorhanden("Raumsteuerung Webserver") || AufgabeVorhanden("Raumsteuerung Mikrofon-Automatik")
                           || AufgabeVorhanden("Raumsteuerung Teams-Steuerung") || PortBelegt(8080);
            if (!AlteAufgaben) return;
            foreach (var d in Alle) { d.Extern = true; d.Zustand = "läuft über die Aufgabenplanung"; }
            Program.Log("Alte Aufgaben gefunden - Dienste werden nicht doppelt gestartet (installieren.ps1 stellt um)");
        }

        // Nach dem Abschalten der alten Aufgaben selbst übernehmen
        public static void Uebernehmen()
        {
            AlteAufgaben = false;
            foreach (var p in FremdeSkriptProzesse()) { try { p.Kill(); } catch { } }
            foreach (var d in Alle) { d.Extern = false; d.Starten(); }
        }

        public static void Pruefen() { foreach (var d in Alle) d.Pruefen(); }
        public static void AlleNeuStarten() { foreach (var d in Alle) if (!d.Extern) d.NeuStarten(); }
        public static void AlleStoppen() { foreach (var d in Alle) d.Stoppen(); }

        static bool AufgabeVorhanden(string name)
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo("schtasks.exe", "/query /tn \"" + name + "\"")
                { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true });
                p.StandardOutput.ReadToEnd(); p.WaitForExit(5000); return p.ExitCode == 0;
            }
            catch { return false; }
        }

        public static bool PortBelegt(int port)
        {
            try { return IPGlobalProperties.GetIPGlobalProperties().GetActiveTcpListeners().Any(e => e.Port == port); } catch { return false; }
        }

        // PowerShell-Prozesse dieses Benutzers mit einem der Skripte, die nicht von uns stammen
        static IEnumerable<Process> FremdeSkriptProzesse()
        {
            var eigene = new HashSet<int>(Alle.Where(d => d.Proc != null).Select(d => { try { return d.Proc.Id; } catch { return -1; } }));
            var liste = new List<Process>();
            try
            {
                using (var s = new System.Management.ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='powershell.exe'"))
                    foreach (System.Management.ManagementObject o in s.Get())
                    {
                        string cl = (o["CommandLine"] as string) ?? ""; int pid = Convert.ToInt32(o["ProcessId"]);
                        if (eigene.Contains(pid)) continue;
                        if (!Alle.Any(d => cl.IndexOf(d.Skript, StringComparison.OrdinalIgnoreCase) >= 0)) continue;
                        if (cl.IndexOf("-Status", StringComparison.OrdinalIgnoreCase) >= 0 || cl.IndexOf("-Befehl", StringComparison.OrdinalIgnoreCase) >= 0
                            || cl.IndexOf("-Zuordnung", StringComparison.OrdinalIgnoreCase) >= 0) continue;
                        try { liste.Add(Process.GetProcessById(pid)); } catch { }
                    }
            }
            catch { }
            return liste;
        }
    }
}
