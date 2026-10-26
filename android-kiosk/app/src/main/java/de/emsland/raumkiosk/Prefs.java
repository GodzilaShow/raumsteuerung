package de.emsland.raumkiosk;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.PersistableBundle;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/** Einstellungen des Kiosks: Adresse des Raum-PCs und Admin-PIN (nur als Hash gespeichert). */
final class Prefs {
    static final String STANDARD_URL = "http://192.168.137.1:8080";
    private static final String NAME = "kiosk";

    private Prefs() {}

    static SharedPreferences sp(Context c) {
        // Geräteschutz-Speicher: auch vor der ersten Entsperrung nach dem Start lesbar
        Context dp = c.createDeviceProtectedStorageContext();
        return dp.getSharedPreferences(NAME, Context.MODE_PRIVATE);
    }

    static String url(Context c) { return sp(c).getString("url", STANDARD_URL); }

    static void setUrl(Context c, String url) {
        if (url == null) return;
        url = url.trim();
        if (url.isEmpty()) return;
        if (!url.startsWith("http://") && !url.startsWith("https://")) url = "http://" + url;
        while (url.endsWith("/")) url = url.substring(0, url.length() - 1);
        sp(c).edit().putString("url", url).apply();
    }

    static boolean hatPin(Context c) { return sp(c).contains("pin"); }

    static void setPin(Context c, String pin) { sp(c).edit().putString("pin", hash(pin)).apply(); }

    static boolean pinStimmt(Context c, String pin) { return hash(pin).equals(sp(c).getString("pin", "-")); }

    static String freigabeGesehen(Context c) { return sp(c).getString("freigabe", ""); }

    static void setFreigabeGesehen(Context c, String id) { sp(c).edit().putString("freigabe", id).apply(); }

    /** Zusatzwerte aus dem QR-Code (z. B. "url") übernehmen. */
    static void ausExtras(Context c, Object extras) {
        if (extras instanceof PersistableBundle) setUrl(c, ((PersistableBundle) extras).getString("url"));
        else if (extras instanceof Bundle) setUrl(c, ((Bundle) extras).getString("url"));
    }

    private static String hash(String s) {
        try {
            byte[] h = MessageDigest.getInstance("SHA-256").digest(("raum5:" + s).getBytes(StandardCharsets.UTF_8));
            StringBuilder b = new StringBuilder();
            for (byte x : h) b.append(String.format("%02x", x));
            return b.toString();
        } catch (Exception e) { return s; }
    }
}
