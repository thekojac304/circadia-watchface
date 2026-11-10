import Toybox.Lang;
using Toybox.WatchUi as WatchUi;
using Toybox.Application as App;
using Toybox.Application.Properties as Props;
using Toybox.Application.Storage as Storage;

// On-watch settings. Reach them on the fenix by holding MENU (middle left)
// on the watch face > Watch Face > select this face > Customize.
// In the simulator: Settings > Trigger App Settings.
//
// Both this menu and the phone settings (settings.xml) read and write the
// same Application.Properties, so they always agree.
module CircadiaPrefs {

    // Multiple-choice settings: property key => labels in value order.
    // Keep in sync with the listEntry values in settings.xml.
    function choices() as Dictionary<String, Array<String> > {
        return {
            "SecondsMode"  => ["Always", "Wrist raise", "Off"] as Array<String>,
            "SunPathMode"  => ["Dim at night", "Always bright", "Hidden"] as Array<String>,
            "TwilightMode" => ["All three", "Civil only", "None"] as Array<String>,
            "HorizonStyle" => ["Mountains", "Flat"] as Array<String>,
            "BatteryMode"  => ["When low", "Always", "Never"] as Array<String>
        } as Dictionary<String, Array<String> >;
    }

    function options(key as String) as Array<String> {
        return choices()[key] as Array<String>;
    }

    function readNum(key as String) as Number {
        var v = null;
        try { v = Props.getValue(key); } catch (e) { }
        var n = (v instanceof Number) ? v as Number : 0;
        var max = options(key).size() - 1;
        return (n < 0) ? 0 : ((n > max) ? max : n);
    }

    function readBool(key as String, fallback as Boolean) as Boolean {
        var v = null;
        try { v = Props.getValue(key); } catch (e) { }
        return (v instanceof Boolean) ? v as Boolean : fallback;
    }

    function locationLabel() as String {
        if (!readBool("UseManualLocation", false)) { return "Auto"; }
        var la = Props.getValue("ManualLatitude");
        var lo = Props.getValue("ManualLongitude");
        if (la == null || lo == null) { return "Locked"; }
        return la.format("%.2f") + ", " + lo.format("%.2f");
    }
}

class CircadiaSettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => "Circadia"});
        addChoice("SecondsMode", "Seconds");
        addToggle("ShowAmPm", "AM/PM (12h)");
        addToggle("WristRaiseInfo", "Rise/set countdown");
        addChoice("SunPathMode", "Sun path");
        addToggle("ShowStars", "Stars");
        addToggle("ShootingStars", "Shooting stars");
        addToggle("MoonReadout", "Moon phase %");
        addChoice("TwilightMode", "Twilight");
        addChoice("HorizonStyle", "Horizon");
        addChoice("BatteryMode", "Battery");
        // Locks the face to the last known location (useful when you
        // don't want GPS or weather to move it). Off = automatic.
        addItem(new WatchUi.ToggleMenuItem("Lock location",
            CircadiaPrefs.locationLabel(), "LockLocation",
            CircadiaPrefs.readBool("UseManualLocation", false), null));
    }

    // Multiple choice: the sublabel shows the current value; each press
    // advances to the next option.
    function addChoice(key as String, label as String) as Void {
        var opts = CircadiaPrefs.options(key);
        addItem(new WatchUi.MenuItem(label, opts[CircadiaPrefs.readNum(key)], key, null));
    }

    function addToggle(key as String, label as String) as Void {
        addItem(new WatchUi.ToggleMenuItem(label, null, key,
            CircadiaPrefs.readBool(key, true), null));
    }
}

class CircadiaSettingsDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item) {
        var key = item.getId() as String;
        if (key.equals("LockLocation")) {
            lockLocation(item as WatchUi.ToggleMenuItem);
        } else if (item instanceof WatchUi.ToggleMenuItem) {
            // The toggle has already flipped by the time onSelect runs.
            Props.setValue(key, (item as WatchUi.ToggleMenuItem).isEnabled());
        } else {
            var opts = CircadiaPrefs.options(key);
            var next = (CircadiaPrefs.readNum(key) + 1) % opts.size();
            Props.setValue(key, next);
            item.setSubLabel(opts[next]);
        }
        App.getApp().onSettingsChanged();   // Apply to the face right away.
        WatchUi.requestUpdate();
    }

    function lockLocation(item as WatchUi.ToggleMenuItem) as Void {
        if (item.isEnabled()) {
            // The view saves every automatic fix to Storage; lock that one.
            var la = Storage.getValue("lat");
            var lo = Storage.getValue("lon");
            if (la == null || lo == null) {
                item.setEnabled(false);
                item.setSubLabel("No location yet");
                return;
            }
            Props.setValue("ManualLatitude", la.toFloat());
            Props.setValue("ManualLongitude", lo.toFloat());
            Props.setValue("UseManualLocation", true);
        } else {
            Props.setValue("UseManualLocation", false);
        }
        item.setSubLabel(CircadiaPrefs.locationLabel());
    }
}
