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
        public readonly string Name, Skript, Aufgabe;   // Aufgabe = Name der früheren Aufgabe in der Aufgabenplanung
        public readonly int Port;                       // > 0: belegter Port heißt "läuft schon woanders"
        public Process Proc;
        public string Zustand = "startet …";
        public bool Extern;            // läuft noch über die alte Aufgabenplanung -> nicht doppelt starten
        public bool Aus;               // bewusst angehalten
        DateTime naechsterStart = DateTime.MinValue;
        int fehlstarts;
        DateTime gestartet;

        public Dienst(string name, string skript, string aufgabe, int port = 0) { Name = name; Skript = skript; Aufgabe = aufgabe; Port = port; }

        // Läuft dieser Dienst schon außerhalb des Programms (alte Aufgabe oder Port belegt)?
        public bool Fremd() { return Dienste.AufgabeVorhanden(Aufgabe) || (Port > 0 && Dienste.PortBelegt(Port)); }

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
        public static readonly Dienst Webserver = new Dienst("Webserver", "server.ps1", "Raumsteuerung Webserver", 8080);
        public static readonly Dienst Teams = new Dienst("Teams-Steuerung", "teams-steuerung.ps1", "Raumsteuerung Teams-Steuerung");
        public static readonly Dienst[] Alle = { Webserver, Teams };   // Mikrofon-Automatik entfällt (Publikum-Kamera fest, 22.10.2026)
        // Vor dem ersten Start, je Dienst: läuft er noch über die Aufgabenplanung (vor der Umstellung mit installieren.ps1)
        // oder ist sein Port belegt? Dann nicht doppelt starten. Früher galt das für alle Dienste zugleich – ein fremdes
        // Programm auf Port 8080 hielt so auch die Teams-Steuerung für immer an.
        public static void Erkennen()
        {
            foreach (var d in Alle)
                if (d.Fremd()) { d.Extern = true; d.Zustand = "läuft außerhalb des Programms"; Program.Log(d.Name + " läuft schon (Aufgabenplanung oder Port belegt) - nicht doppelt gestartet"); }
        }

        // Externe Dienste jede Minute nachsehen; ist die Aufgabe weg und der Port frei, selbst übernehmen
        static DateTime naechsteSuche = DateTime.Now.AddMinutes(1);
        static volatile bool sucht;
        public static void Pruefen()
        {
            foreach (var d in Alle) d.Pruefen();
            if (sucht || DateTime.Now < naechsteSuche || !Alle.Any(d => d.Extern)) return;
            sucht = true; naechsteSuche = DateTime.Now.AddMinutes(1);
            var fremde = Alle.Where(d => d.Extern).ToList();
            System.Threading.Tasks.Task.Run(() =>
            {
                try { foreach (var d in fremde) if (!d.Fremd()) { Program.Log(d.Name + " läuft nicht mehr außerhalb - übernehme"); d.Extern = false; } }
                finally { sucht = false; }
            });
        }

        public static void AlleNeuStarten() { foreach (var d in Alle) if (!d.Extern) d.NeuStarten(); }
        public static void AlleStoppen() { foreach (var d in Alle) d.Stoppen(); }

        public static bool AufgabeVorhanden(string name)
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
    }
}
