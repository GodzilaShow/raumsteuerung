package de.emsland.raumkiosk;

import android.app.admin.DeviceAdminReceiver;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;

public class AdminReceiver extends DeviceAdminReceiver {
    static ComponentName name(Context c) { return new ComponentName(c, AdminReceiver.class); }

    @Override
    public void onProfileProvisioningComplete(Context context, Intent intent) {
        // Einrichtung per QR-Code bis Android 11: Zusatzwerte übernehmen und starten
        Prefs.ausExtras(context, intent.getParcelableExtra(DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE));
        Intent i = new Intent(context, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        context.startActivity(i);
    }
}
