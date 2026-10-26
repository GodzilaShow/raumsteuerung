package de.emsland.raumkiosk;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.ActivityManager;
import android.app.AlertDialog;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.text.InputType;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Raumsteuerung Kiosk: zeigt nur die Tablet-Seite des Raum-PCs.
 * Als Geräteinhaber (Device Owner) ist der Bildschirm fest gesperrt (Lock Task),
 * die App ist Startbildschirm und startet nach jedem Neustart von selbst.
 * Ausgang: 5× schnell oben links tippen + PIN, oder "Tablet freigeben" am Raum-PC.
 */
public class MainActivity extends Activity {
    private static final int TINTE = Color.parseColor("#0E2A3F");
    private static final int GRUND = Color.parseColor("#EEF3F6");

    private final Handler ui = new Handler(Looper.getMainLooper());
    private FrameLayout root;
    private WebView web;
    private LinearLayout offline;
    private TextView offlineText;
    private LinearLayout pauseLeiste;
    private boolean fehler;
    private boolean pausiert;          // nur bis zum nächsten Neustart
    private boolean dialogOffen;
    private int taps;
    private long ersterTap;
    private volatile boolean laeuft;
    private volatile int runde;

    private DevicePolicyManager dpm() { return (DevicePolicyManager) getSystemService(Context.DEVICE_POLICY_SERVICE); }
    private boolean istGeraeteinhaber() { return dpm().isDeviceOwnerApp(getPackageName()); }

    // ---------------------------------------------------------------- Aufbau

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        richteGeraetEin();

        root = new FrameLayout(this);
        root.setBackgroundColor(GRUND);
        setContentView(root);
        neueWebView();
        baueOffline();
        bauePauseLeiste();
        baueEcke();
        laden();
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void neueWebView() {
        if (web != null) { root.removeView(web); web.destroy(); }
        web = new WebView(this);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);   // nach Updates am PC immer die neue Seite
        s.setTextZoom(100);
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        web.setLongClickable(false);
        web.setOnLongClickListener(v -> true);       // kein Textauswahl-Menü
        web.setWebViewClient(new WebViewClient() {
            @Override public void onPageStarted(WebView v, String u, android.graphics.Bitmap f) { fehler = false; }
            @Override public void onPageFinished(WebView v, String u) { if (!fehler) zeigeOffline(false); }
            @Override public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) {
                if (r.isForMainFrame()) nichtErreichbar();
            }
            @Override public void onReceivedHttpError(WebView v, WebResourceRequest r, WebResourceResponse e) {
                if (r.isForMainFrame()) nichtErreichbar();
            }
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                // Nur Seiten des Raum-PCs öffnen, alles andere bleibt zu
                String ziel = r.getUrl().toString();
                return !ziel.startsWith(Prefs.url(MainActivity.this));
            }
            @Override public boolean onRenderProcessGone(WebView v, RenderProcessGoneDetail d) {
                ui.post(() -> { neueWebView(); laden(); });
                return true;
            }
        });
        root.addView(web, 0, new FrameLayout.LayoutParams(-1, -1));
    }

    private void laden() {
        fehler = false;
        web.loadUrl(Prefs.url(this) + "/");
    }

    private void nichtErreichbar() {
        fehler = true;
        zeigeOffline(true);
        ui.removeCallbacks(neuVersuch);
        ui.postDelayed(neuVersuch, 5000);
    }

    private final Runnable neuVersuch = this::laden;

    private void baueOffline() {
        offline = new LinearLayout(this);
        offline.setOrientation(LinearLayout.VERTICAL);
        offline.setGravity(Gravity.CENTER);
        offline.setBackgroundColor(GRUND);
        ProgressBar p = new ProgressBar(this);
        offline.addView(p, new LinearLayout.LayoutParams(dp(56), dp(56)));
        TextView t = new TextView(this);
        t.setText("Verbinde mit dem Raum-PC …");
        t.setTextColor(TINTE);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setPadding(0, dp(18), 0, dp(6));
        offline.addView(t);
        offlineText = new TextView(this);
        offlineText.setTextColor(Color.parseColor("#52667A"));
        offlineText.setTextSize(TypedValue.COMPLEX_UNIT_SP, 17);
        offlineText.setGravity(Gravity.CENTER);
        offline.addView(offlineText);
        offline.setVisibility(View.GONE);
        root.addView(offline, new FrameLayout.LayoutParams(-1, -1));
    }

    private void zeigeOffline(boolean an) {
        offlineText.setText("Ist der Raum-PC eingeschaltet?\n" + Prefs.url(this) + "\nNeuer Versuch alle 5 Sekunden.");
        offline.setVisibility(an ? View.VISIBLE : View.GONE);
    }

    /** Unsichtbare Fläche oben links: 5 Tipper in 3 Sekunden öffnen das Admin-Menü. Die Seite bekommt die Tipper trotzdem. */
    @SuppressLint("ClickableViewAccessibility")
    private void baueEcke() {
        View ecke = new View(this);
        ecke.setOnTouchListener((v, e) -> {
            if (e.getAction() == MotionEvent.ACTION_DOWN) {
                long jetzt = System.currentTimeMillis();
                if (jetzt - ersterTap > 3000) { ersterTap = jetzt; taps = 0; }
                if (++taps >= 5) { taps = 0; pinAbfrage(); }
            }
            return false;
        });
        root.addView(ecke, new FrameLayout.LayoutParams(dp(110), dp(110), Gravity.TOP | Gravity.START));
    }

    private void bauePauseLeiste() {
        pauseLeiste = new LinearLayout(this);
        pauseLeiste.setOrientation(LinearLayout.HORIZONTAL);
        pauseLeiste.setGravity(Gravity.CENTER_VERTICAL);
        pauseLeiste.setPadding(dp(14), dp(8), dp(8), dp(8));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor("#FEF3C7"));
        bg.setCornerRadius(dp(10));
        bg.setStroke(dp(1), Color.parseColor("#E19A0C"));
        pauseLeiste.setBackground(bg);
        TextView t = new TextView(this);
        t.setText("Kiosk pausiert  ");
        t.setTextColor(TINTE);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        pauseLeiste.addView(t);
        Button einst = new Button(this);
        einst.setText("Android-Einstellungen");
        einst.setOnClickListener(v -> startActivity(new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)));
        pauseLeiste.addView(einst);
        Button weiter = new Button(this);
        weiter.setText("Kiosk fortsetzen");
        weiter.setOnClickListener(v -> { pausiert = false; pauseLeiste.setVisibility(View.GONE); sperren(); });
        pauseLeiste.addView(weiter);
        pauseLeiste.setVisibility(View.GONE);
        FrameLayout.LayoutParams lp = new FrameLayout.LayoutParams(-2, -2, Gravity.TOP | Gravity.END);
        lp.setMargins(0, dp(10), dp(10), 0);
        root.addView(pauseLeiste, lp);
    }

    // ---------------------------------------------------------------- Sperre

    /** Einmalig als Geräteinhaber: Lock Task erlauben, Startbildschirm festlegen, Sperrbildschirm und Statusleiste aus. */
    private void richteGeraetEin() {
        if (!istGeraeteinhaber()) return;
        DevicePolicyManager d = dpm();
        ComponentName a = AdminReceiver.name(this);
        try {
            d.setLockTaskPackages(a, new String[]{getPackageName()});
            d.setLockTaskFeatures(a, DevicePolicyManager.LOCK_TASK_FEATURE_NONE);
            IntentFilter home = new IntentFilter(Intent.ACTION_MAIN);
            home.addCategory(Intent.CATEGORY_HOME);
            home.addCategory(Intent.CATEGORY_DEFAULT);
            d.addPersistentPreferredActivity(a, home, new ComponentName(this, MainActivity.class));
            d.setKeyguardDisabled(a, true);
            d.setStatusBarDisabled(a, true);
            // Bildschirm bleibt an, solange das Tablet lädt (Netzteil, USB, kabellos)
            d.setGlobalSetting(a, Settings.Global.STAY_ON_WHILE_PLUGGED_IN, "7");
        } catch (Exception e) {
            Toast.makeText(this, "Einrichtung: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }

    private void sperren() {
        if (pausiert) return;
        if (istGeraeteinhaber()) {
            try { dpm().setStatusBarDisabled(AdminReceiver.name(this), true); } catch (Exception ignored) { }
        }
        ActivityManager am = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
        if (am.getLockTaskModeState() == ActivityManager.LOCK_TASK_MODE_NONE) {
            try { startLockTask(); } catch (Exception ignored) { }
        }
        vollbild();
    }

    private void entsperren() {
        try { stopLockTask(); } catch (Exception ignored) { }
        if (istGeraeteinhaber()) {
            try { dpm().setStatusBarDisabled(AdminReceiver.name(this), false); } catch (Exception ignored) { }
        }
    }

    @SuppressWarnings("deprecation")
    private void vollbild() {
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.hide(WindowInsets.Type.statusBars() | WindowInsets.Type.navigationBars());
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                    | View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_LAYOUT_STABLE);
        }
    }

    @Override
    public void onWindowFocusChanged(boolean f) {
        super.onWindowFocusChanged(f);
        if (f && !pausiert) vollbild();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (!Prefs.hatPin(this)) pinFestlegen(false);
        sperren();
        if (fehler) laden();
        startePruefung();
    }

    @Override
    protected void onPause() {
        super.onPause();
        laeuft = false;
    }

    @SuppressLint("MissingSuperCall")
    @Override
    public void onBackPressed() { /* Zurück-Taste tut nichts */ }

    // ---------------------------------------------------------------- Freigabe vom Raum-PC

    /** Alle 10 s prüfen, ob am Raum-PC "Tablet freigeben" gedrückt wurde (neue ID in kiosk-freigabe.json). */
    private void startePruefung() {
        if (laeuft) return;
        laeuft = true;
        final int meine = ++runde;
        Thread t = new Thread(() -> {
            boolean erster = true;
            while (laeuft && meine == runde) {
                String id = holeFreigabeId();
                if (id != null && !id.isEmpty()) {
                    String alt = Prefs.freigabeGesehen(this);
                    if (!id.equals(alt)) {
                        Prefs.setFreigabeGesehen(this, id);
                        // Beim allerersten Start nur merken, nicht öffnen (alte Datei)
                        if (!(erster && alt.isEmpty())) ui.post(() -> { if (!dialogOffen) adminMenue(); });
                    }
                }
                erster = false;
                try { Thread.sleep(10000); } catch (InterruptedException e) { return; }
            }
        }, "freigabe");
        t.setDaemon(true);
        t.start();
    }

    private String holeFreigabeId() {
        HttpURLConnection c = null;
        try {
            c = (HttpURLConnection) new URL(Prefs.url(this) + "/kiosk-freigabe.json").openConnection();
            c.setConnectTimeout(3000);
            c.setReadTimeout(3000);
            c.setUseCaches(false);
            if (c.getResponseCode() != 200) return null;
            try (InputStream in = c.getInputStream()) {
                byte[] buf = new byte[512];
                int n = in.read(buf);
                if (n <= 0) return null;
                String s = new String(buf, 0, n, StandardCharsets.UTF_8);
                Matcher m = Pattern.compile("\"id\"\\s*:\\s*\"([^\"]+)\"").matcher(s);
                return m.find() ? m.group(1) : null;
            }
        } catch (Exception e) {
            return null;
        } finally {
            if (c != null) c.disconnect();
        }
    }

    // ---------------------------------------------------------------- Admin

    private void pinAbfrage() {
        if (dialogOffen) return;
        EditText pin = pinFeld("PIN");
        dialogOffen = true;
        AlertDialog d = new AlertDialog.Builder(this)
                .setTitle("Admin-PIN")
                .setView(abstand(pin))
                .setPositiveButton("OK", (x, w) -> {
                    dialogOffen = false;
                    if (Prefs.pinStimmt(this, pin.getText().toString())) adminMenue();
                    else Toast.makeText(this, "Falsche PIN", Toast.LENGTH_SHORT).show();
                })
                .setNegativeButton("Abbrechen", (x, w) -> dialogOffen = false)
                .setOnCancelListener(x -> dialogOffen = false)
                .create();
        d.show();
        // Ohne Eingabe nach 15 s wieder zu
        ui.postDelayed(() -> { if (d.isShowing() && pin.getText().length() == 0) { d.dismiss(); dialogOffen = false; } }, 15000);
    }

    private void adminMenue() {
        dialogOffen = true;
        String[] punkte = {
                "Seite neu laden",
                "Adresse des Raum-PCs ändern",
                "PIN ändern",
                "Kiosk pausieren (Android benutzen)",
                "Kiosk komplett entfernen"
        };
        new AlertDialog.Builder(this)
                .setTitle("Raumsteuerung Kiosk " + version() + (istGeraeteinhaber() ? "" : "  (ohne Geräteinhaber)"))
                .setItems(punkte, (x, i) -> {
                    dialogOffen = false;
                    switch (i) {
                        case 0: neueWebView(); laden(); break;
                        case 1: adresseAendern(); break;
                        case 2: pinFestlegen(true); break;
                        case 3: pausieren(); break;
                        case 4: entfernenFragen(); break;
                    }
                })
                .setNegativeButton("Schließen", (x, w) -> dialogOffen = false)
                .setOnCancelListener(x -> dialogOffen = false)
                .show();
    }

    private void adresseAendern() {
        EditText f = new EditText(this);
        f.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        f.setText(Prefs.url(this));
        dialogOffen = true;
        new AlertDialog.Builder(this)
                .setTitle("Adresse des Raum-PCs")
                .setMessage("z. B. http://192.168.137.1:8080")
                .setView(abstand(f))
                .setPositiveButton("Speichern", (x, w) -> { dialogOffen = false; Prefs.setUrl(this, f.getText().toString()); laden(); })
                .setNegativeButton("Abbrechen", (x, w) -> dialogOffen = false)
                .show();
    }

    private void pinFestlegen(boolean abbrechbar) {
        if (dialogOffen) return;
        EditText p1 = pinFeld("Neue PIN (4–8 Ziffern)");
        EditText p2 = pinFeld("PIN wiederholen");
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        l.addView(p1);
        l.addView(p2);
        dialogOffen = true;
        AlertDialog d = new AlertDialog.Builder(this)
                .setTitle("Admin-PIN festlegen")
                .setMessage("Mit dieser PIN kommt man aus dem Kiosk heraus: 5× schnell oben links tippen.")
                .setView(abstand(l))
                .setCancelable(abbrechbar)
                .setPositiveButton("Speichern", null)
                .setNegativeButton(abbrechbar ? "Abbrechen" : null, (x, w) -> dialogOffen = false)
                .create();
        d.setOnShowListener(x -> d.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String a = p1.getText().toString(), b = p2.getText().toString();
            if (a.length() < 4 || a.length() > 8) { p1.setError("4 bis 8 Ziffern"); return; }
            if (!a.equals(b)) { p2.setError("Stimmt nicht überein"); return; }
            Prefs.setPin(this, a);
            dialogOffen = false;
            d.dismiss();
            Toast.makeText(this, "PIN gespeichert", Toast.LENGTH_SHORT).show();
        }));
        d.show();
    }

    private void pausieren() {
        pausiert = true;
        entsperren();
        pauseLeiste.setVisibility(View.VISIBLE);
        Toast.makeText(this, "Kiosk pausiert – nach einem Neustart ist er wieder an.", Toast.LENGTH_LONG).show();
    }

    private void entfernenFragen() {
        dialogOffen = true;
        new AlertDialog.Builder(this)
                .setTitle("Kiosk komplett entfernen?")
                .setMessage("Das Tablet wird wieder ein normales Android-Gerät. Die App bleibt installiert, kann danach normal deinstalliert werden.")
                .setPositiveButton("Entfernen", (x, w) -> { dialogOffen = false; entfernen(); })
                .setNegativeButton("Abbrechen", (x, w) -> dialogOffen = false)
                .show();
    }

    @SuppressWarnings("deprecation")
    private void entfernen() {
        pausiert = true;
        entsperren();
        if (istGeraeteinhaber()) {
            DevicePolicyManager d = dpm();
            ComponentName a = AdminReceiver.name(this);
            try {
                d.clearPackagePersistentPreferredActivities(a, getPackageName());
                d.setKeyguardDisabled(a, false);
                d.setLockTaskPackages(a, new String[0]);
                d.setGlobalSetting(a, Settings.Global.STAY_ON_WHILE_PLUGGED_IN, "0");
                d.clearDeviceOwnerApp(getPackageName());
            } catch (Exception e) {
                Toast.makeText(this, "Fehler: " + e.getMessage(), Toast.LENGTH_LONG).show();
            }
        }
        Toast.makeText(this, "Kiosk entfernt.", Toast.LENGTH_LONG).show();
        startActivity(new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        finish();
    }

    // ---------------------------------------------------------------- Hilfen

    private EditText pinFeld(String hint) {
        EditText e = new EditText(this);
        e.setHint(hint);
        e.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_VARIATION_PASSWORD);
        e.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        return e;
    }

    private View abstand(View v) {
        FrameLayout f = new FrameLayout(this);
        f.setPadding(dp(22), dp(8), dp(22), 0);
        f.addView(v);
        return f;
    }

    private String version() {
        try { return getPackageManager().getPackageInfo(getPackageName(), 0).versionName; } catch (Exception e) { return ""; }
    }

    private int dp(int v) { return Math.round(v * getResources().getDisplayMetrics().density); }

    @Override
    protected void onDestroy() {
        laeuft = false;
        ui.removeCallbacksAndMessages(null);
        super.onDestroy();
    }
}
