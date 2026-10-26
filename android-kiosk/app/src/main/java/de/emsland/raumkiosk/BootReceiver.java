package de.emsland.raumkiosk;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Nach Neustart oder Update: Raumsteuerung sofort öffnen. */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        try {
            context.startActivity(new Intent(context, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        } catch (Exception ignored) { }
    }
}
