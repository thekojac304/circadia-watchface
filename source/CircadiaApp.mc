import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class CircadiaApp extends Application.AppBase {

    var _view as CircadiaView? = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() {
        var view = new CircadiaView();
        _view = view;
        return [view, new CircadiaDelegate(view)];
    }

    // On-watch settings: hold MENU on the face > Watch Face > Customize.
    function getSettingsView() {
        return [new CircadiaSettingsMenu(), new CircadiaSettingsDelegate()];
    }

    // Called by the system after phone settings change, and by the on-watch
    // settings menu after each edit.
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) { view.loadSettings(); }
        WatchUi.requestUpdate();
    }
}

// Receives system events for the watch face. The one that matters: if the
// once-a-second seconds updates overrun the watch's power budget, the watch
// stops calling onPartialUpdate; this switches seconds to wrist-raise only
// instead of leaving them frozen.
class CircadiaDelegate extends WatchUi.WatchFaceDelegate {

    var _view as CircadiaView;

    function initialize(view as CircadiaView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPowerBudgetExceeded(powerInfo) {
        _view.onBudgetExceeded();
    }
}

// Convenience accessor (the SDK template's global helper).
function getApp() as CircadiaApp {
    return Application.getApp() as CircadiaApp;
}
