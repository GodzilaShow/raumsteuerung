package de.emsland.raumkiosk;

import android.app.Activity;
import android.app.admin.DevicePolicyManager;
import android.content.Intent;
import android.os.Bundle;

/** Einrichtung per QR-Code ab Android 12: Modus "vollständig verwaltetes Gerät" wählen, dann bestätigen. */
public class ProvisioningActivity extends Activity {
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        Intent in = getIntent();
        Prefs.ausExtras(this, in.getParcelableExtra(DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE));
        Intent res = new Intent();
        if (DevicePolicyManager.ACTION_GET_PROVISIONING_MODE.equals(in.getAction())) {
            res.putExtra(DevicePolicyManager.EXTRA_PROVISIONING_MODE, DevicePolicyManager.PROVISIONING_MODE_FULLY_MANAGED_DEVICE);
        }
        setResult(RESULT_OK, res);
        finish();
    }
}
