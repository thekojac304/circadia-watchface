import Toybox.Lang;
using Toybox.WatchUi as WatchUi;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Math as Math;
using Toybox.Time as Time;
using Toybox.Time.Gregorian as Gregorian;
using Toybox.Application.Storage as Storage;
using Toybox.Application.Properties as Props;
using Toybox.Activity as Act;
using Toybox.Weather as Weather;

// Circadia -- designed at 260 x 260, scales to any round screen. (Began as a port of the Pebble face
// "Fair Circadian" by SetPebble; since rebuilt around real sky data.)
// Ring: day, civil, nautical and astronomical twilight, night, computed
//       for today's date and location.
// Scene: true sky facing the equator. x = azimuth, y = altitude. The sun
//        and moon appear only while actually above the horizon; the
//        dotted line is today's sun path. Moon phase and lit side are real.
class CircadiaView extends WatchUi.WatchFace {

    // ----- Layout ---------------------------------------------------------
    // Values below are in the 260 x 260 design space. onLayout() rescales
    // them all to the actual screen, so the face fits any round display.
    var CX = 130;
    var CY = 130;
    var RING_R = 112;          // Centerline of the ring stroke.
    var RING_W = 25;           // Ring spans roughly r 100..125.
    var R_OUTER = 125;
    var R_INNER = 100;

    var TEMP_Y = 50;
    var DATE_Y = 76;
    var TIME_Y = 120;          // A little above center: the optical center.
    var SEC_GAP = 6;           // Gap between HH:MM and seconds.
    var TIME_MAX_W = 190;      // Widest "12:59" + seconds allowed.
    var AMPM_DY = 0;           // Nudge AM/PM up (-) or down (+) if needed.

    var HORIZON_Y = 198;
    var AZ_PX = 0.52;          // px per degree of azimuth: +-135 deg -> +-70 px.
    var AZ_MAX_PX = 70;
    var ALT_PX = 0.30;         // px per degree of altitude: 90 deg -> 27 px.
    var SUN_R = 7;
    var MOON_R = 8;
    var SLOT_Y = 156;          // Battery (left) and moon (right) readouts,
    var SLOT_DX = 66;          // between the time and the scene.
    var SOLAR_LABEL_Y = 209;   // Labels ~82 px from center, clear of
    var SOLAR_LABEL_DX = 24;   // the pointer tip (which stops at r 97).

    // ----- Palette (all valid on the 64-color MIP display) --------------
    const C_DAY = 0xFFAA00;
    const C_CIVIL = 0xAA55AA;
    const C_NAUTICAL = 0x5555AA;
    const C_ASTRO = 0x0000AA;
    const C_NIGHT = 0x000055;
    const C_GROUND = 0x555555;
    const C_DIM = 0xAAAAAA;
    const C_WARN = 0xFF5500;
    const C_PATH_NIGHT = 0x5555AA;
    const C_SUN_GLOW = 0xAA5500;     // Dim orange halo around the sun.
    const C_FAR_RANGE = 0x0000AA;    // Distant mountains: blue haze.
    const C_ROCK_LIT = 0xAAAAAA;     // Sun-facing slopes.
    const C_ROCK_MOON = 0x5555AA;    // Moon-facing slopes at night.

    const RAD = 0.017453292519943295d;
    const J2000_UNIX = 946728000;    // 2000-01-01 12:00 UTC.
    const LOW_BATTERY = 20;
    const WEATHER_STALE = 3 * 3600;     // Older than this: temperature shown gray.
    const WEATHER_EXPIRED = 12 * 3600;  // Older than this: shown as "--".
    const VISIBLE_ALT = -0.833;      // Upper limb on the horizon, with refraction.
    const SHOOT_CHANCE = 25;         // Shooting star: 1 in N per awake second.
    const SINK_DEG = 3.0;            // Sun/moon sink into the horizon over the last
                                     // 3 deg before setting (~20 min at mid latitudes).

    // ----- State ---------------------------------------------------------
    // Bands, darkest first: [startMin, endMin, state].
    // state 0 = normal, 1 = sun never gets that high today,
    //       2 = sun never drops that low today.
    var _bandAlt as Array<Double> = [] as Array<Double>;
    var _bandColor as Array<Number> = [] as Array<Number>;
    var _bands as Array<Array<Number>> = [] as Array<Array<Number>>;
    var _solarKey = -1;
    var _posKey = -1;

    var _lat = null;
    var _lon = null;
    var _tempC = null;
    var _weatherTime = null;     // Unix time of the observation, if known.
    var _awake = true;           // Faces start in high power, while being looked at.
    var _s = 1.0;                // Screen width / 260.
    var _w = 260;
    var _burnIn = false;         // AMOLED: needs a minimal always-on view.
    var _settingsMin = -1;
    var _locDiag = "";

    // Settings (see resources/settings). List values match settings.xml.
    var _secondsMode = 0;        // 0 always, 1 only on wrist raise, 2 off.
    var _wristInfo = true;
    var _pathMode = 0;           // 0 dim at night, 1 always bright, 2 hidden.
    var _showStars = true;
    var _twilightMode = 0;       // 0 all three bands, 1 civil only, 2 none.
    var _flatHorizon = false;
    var _batteryMode = 0;        // 0 low only, 1 always, 2 never.
    var _partialSeconds = false; // Seconds redrawn by onPartialUpdate.
    var _budgetExceeded = false; // Set if the watch vetoes 1 Hz partial updates.
    var _showAmPm = true;        // Only has an effect in 12-hour mode.
    var _shootingStars = true;
    var _moonReadout = true;
    var _shoot = 0;              // Frames left of the current shooting star.
    var _shootPath = 0;
    var _shootPaths as Array<Array<Number>> = [] as Array<Array<Number>>;
    var _useManual = false;
    var _manLat = 0.0;
    var _manLon = 0.0;
    var _secBox as Array<Number>? = null;
    var _timeFont = Gfx.FONT_NUMBER_HOT;
    var _secFont = Gfx.FONT_SMALL;
    var _ampmFont = Gfx.FONT_XTINY;
    var _colBox as Array<Number>? = null;  // AM/PM + seconds column.
    var _secX = 0;
    var _secY = 0;

    var _mountains as Array<Array<Number>> = [] as Array<Array<Number>>;
    var _farRange as Array<Array<Number>> = [] as Array<Array<Number>>;
    var _winter = false;         // Snowcaps on the high peaks.
    var _peakOrder as Array<Number> = [] as Array<Number>;  // Lowest peak first.
    var _stars as Array<Array<Number>> = [] as Array<Array<Number>>;
    var _sunPath as Array<Array<Number>> = [] as Array<Array<Number>>;
    var _sunAlt = -90.0;
    var _sunAz = 0.0;
    var _moonAlt = -90.0;
    var _moonAz = 0.0;
    var _moonPhase = 0.0;        // 0 new, 0.25 first quarter, 0.5 full.
    var _moonLit = 0.0;          // Illuminated fraction 0..1.

    function initialize() {
        WatchFace.initialize();

        _bandAlt = [-18.0d, -12.0d, -6.0d, VISIBLE_ALT.toDouble()] as Array<Double>;
        _bandColor = [C_ASTRO, C_NAUTICAL, C_CIVIL, C_DAY] as Array<Number>;
        setFallbackBands();

        loadStoredLocation();
        loadSettings();
        Math.srand(Time.now().value());
    }

    // Call from the App's onSettingsChanged() so changes apply immediately.
    function loadSettings() {
        _secondsMode = prop("SecondsMode", 0);
        _wristInfo = prop("WristRaiseInfo", true);
        _pathMode = prop("SunPathMode", 0);
        _showStars = prop("ShowStars", true);
        _twilightMode = prop("TwilightMode", 0);
        _flatHorizon = (prop("HorizonStyle", 0) == 1);
        _batteryMode = prop("BatteryMode", 0);
        _showAmPm = prop("ShowAmPm", true);
        _shootingStars = prop("ShootingStars", true);
        _moonReadout = prop("MoonReadout", true);
        var useManual = prop("UseManualLocation", false);
        var manLat = prop("ManualLatitude", 0.0);
        var manLon = prop("ManualLongitude", 0.0);
        if (useManual != _useManual || manLat != _manLat || manLon != _manLon) {
            _useManual = useManual;
            _manLat = manLat;
            _manLon = manLon;
            loadStoredLocation();    // Manual overrides; auto starts from storage.
            _solarKey = -1;
            _posKey = -1;
        }
    }

    function loadStoredLocation() {
        _lat = null;
        _lon = null;
        if (_useManual) { return; }
        var la = Storage.getValue("lat");
        var lo = Storage.getValue("lon");
        if (la != null && lo != null) {
            _lat = la.toDouble();
            _lon = lo.toDouble();
        }
    }

    function prop(key, fallback) {
        try {
            var v = Props.getValue(key);
            return (v == null) ? fallback : v;
        } catch (e) {
            return fallback;
        }
    }

    function onLayout(dc) {
        // Scale the 260 px design to this screen, centered. Fonts are the
        // watch's own system fonts, already sized for its screen.
        _w = dc.getWidth();
        _s = _w / 260.0;
        CX = _w / 2;
        CY = dc.getHeight() / 2;
        RING_R = sc(112);
        RING_W = sc(25);
        R_OUTER = sc(125);
        R_INNER = sc(100);
        TEMP_Y = sc(50);
        DATE_Y = sc(76);
        TIME_Y = sc(120);
        SEC_GAP = sc(6);
        TIME_MAX_W = sc(190);
        AMPM_DY = sc(0);
        HORIZON_Y = sc(198);
        AZ_PX = 0.52 * _s;
        AZ_MAX_PX = sc(70);
        ALT_PX = 0.30 * _s;
        SUN_R = sc(7);
        MOON_R = sc(8);
        SLOT_Y = sc(156);
        SLOT_DX = sc(66);
        SOLAR_LABEL_Y = sc(209);
        SOLAR_LABEL_DX = sc(24);

        var ds = Sys.getDeviceSettings();
        _burnIn = (ds has :requiresBurnInProtection) && ds.requiresBurnInProtection;

        var shape = [[-64, 0], [-42, -8], [-30, -3], [-16, -12], [0, -4],
                     [16, -10], [30, -2], [42, -7], [64, 0]] as Array<Array<Number>>;
        _mountains = [] as Array<Array<Number>>;
        for (var i = 0; i < shape.size(); i++) {
            _mountains.add([CX + sc(shape[i][0]), HORIZON_Y + sc(shape[i][1])] as Array<Number>);
        }
        // Peak indices (odd points), sorted lowest first (largest y first).
        _peakOrder = [] as Array<Number>;
        for (var pi = 1; pi < _mountains.size() - 1; pi += 2) { _peakOrder.add(pi); }
        for (var si = 1; si < _peakOrder.size(); si++) {
            var j = si;
            while (j > 0 && _mountains[_peakOrder[j - 1]][1] < _mountains[_peakOrder[j]][1]) {
                var t = _peakOrder[j - 1];
                _peakOrder[j - 1] = _peakOrder[j];
                _peakOrder[j] = t;
                j--;
            }
        }

        // Distant range: lower, and peaking where the near range dips.
        var far = [[-70, 0], [-54, -6], [-44, -3], [-28, -9], [-8, -5], [6, -8],
                   [22, -4], [34, -9], [52, -4], [70, 0]] as Array<Array<Number>>;
        _farRange = [] as Array<Array<Number>>;
        for (var fi = 0; fi < far.size(); fi++) {
            _farRange.add([CX + sc(far[fi][0]), HORIZON_Y + sc(far[fi][1])] as Array<Number>);
        }
        var stars = [[78, 52], [190, 58], [96, 38], [166, 38], [58, 90],
                     [202, 88], [104, 160], [158, 158], [52, 180], [208, 178]] as Array<Array<Number>>;
        _stars = [] as Array<Array<Number>>;
        for (var si2 = 0; si2 < stars.size(); si2++) {
            _stars.add([sc(stars[si2][0]), sc(stars[si2][1])] as Array<Number>);
        }

        // Shooting-star paths [x0, y0, x1, y1], in sky clear of all text.
        var paths = [[86, 50, 52, 84], [174, 50, 208, 84],
                     [96, 42, 60, 70], [164, 42, 200, 70]] as Array<Array<Number>>;
        _shootPaths = [] as Array<Array<Number>>;
        for (var pp = 0; pp < paths.size(); pp++) {
            var q = paths[pp];
            _shootPaths.add([sc(q[0]), sc(q[1]), sc(q[2]), sc(q[3])] as Array<Number>);
        }
        _solarKey = -1;                          // Rebuild the sun path at this scale.

        // Biggest time font whose widest reading (plus AM/PM and seconds) fits
        // inside the ring at the time's height; fall back one size if not.
        _timeFont = Gfx.FONT_NUMBER_HOT;
        _secFont = Gfx.FONT_SMALL;
        var col = dc.getTextWidthInPixels("88", _secFont);
        var aw = dc.getTextWidthInPixels("PM", _ampmFont);
        if (aw > col) { col = aw; }
        var w = dc.getTextWidthInPixels("12:59", _timeFont) + SEC_GAP + col;
        if (w > TIME_MAX_W) {
            _timeFont = Gfx.FONT_NUMBER_MEDIUM;
            _secFont = Gfx.FONT_TINY;
        }
    }

    function onExitSleep() {
        _awake = true;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() {
        _awake = false;
        _shoot = 0;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc) {
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        dc.clearClip();
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        var clock = Sys.getClockTime();
        var minutes = clock.hour * 60 + clock.min;
        if (minutes != _settingsMin) {           // Works even without an
            _settingsMin = minutes;              // onSettingsChanged hook.
            loadSettings();
        }
        refreshLocation();
        refreshSolar();
        refreshSky();

        if (_burnIn && !_awake) {                // AMOLED, idle: minimal view.
            drawAlwaysOn(dc, clock, minutes);
            return;
        }

        drawRing(dc);
        drawClock(dc, clock);                    // Sets the seconds box.
        if (_showStars && _lat != null && !bandContains(1, minutes)) {  // Sun below -12 deg.
            drawStars(dc, minutes, clock.sec);
            drawShootingStar(dc);
        }
        drawPointer(dc, minutes);                // Over stars at the rim.
        drawCorners(dc);                         // Sky objects pass in front.
        drawScene(dc, minutes);
        drawTemperature(dc);
        drawDateLine(dc, minutes);
    }

    function onPartialUpdate(dc) {
        // MIP low-power mode: repaint only the seconds box once a second.
        var b = _secBox;
        if (b == null || !_partialSeconds) { return; }
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        dc.setClip(b[0], b[1], b[2], b[3]);
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.fillRectangle(b[0], b[1], b[2], b[3]);
        drawSeconds(dc, Sys.getClockTime().sec);
        dc.clearClip();
    }

    // ----- Location and weather ------------------------------------------

    function refreshLocation() {
        // Diagnostic codes, shown under the horizon while there's no fix:
        //   G = last GPS fix, W = weather observation location
        //   '-' source returned nothing, 'x' returned junk (0,0 / 180,180),
        //   '+' used, 'n' no weather conditions at all.
        var g = "-";
        var w = "-";
        if (_useManual) {
            setLocation(_manLat, _manLon, "manual setting");
            _locDiag = "manual";
        } else {
            var got = false;
            var info = Act.getActivityInfo();
            if (info != null && info.currentLocation != null) {
                var p = info.currentLocation.toDegrees();
                got = setLocation(p[0], p[1], "GPS (activity)");
                g = got ? "+" : "x";
            }
            if (!got && (Toybox has :Weather)) {
                var cc = Weather.getCurrentConditions();
                if (cc == null) {
                    w = "n";
                } else if (cc.observationLocationPosition != null) {
                    var wl = cc.observationLocationPosition.toDegrees();
                    w = setLocation(wl[0], wl[1], "weather") ? "+" : "x";
                }
            }
            _locDiag = "G" + g + " W" + w;
            if (_lat == null) { log("No location: " + _locDiag); }
        }

        if (Toybox has :Weather) {
            var cc2 = Weather.getCurrentConditions();
            if (cc2 == null) {
                _tempC = null;                   // No cached weather at all.
                _weatherTime = null;
            } else {
                _tempC = cc2.temperature;
                _weatherTime = (cc2.observationTime != null)
                               ? cc2.observationTime.value() : null;
            }
        }
    }

    function setLocation(lat, lon, source) {
        lat = lat.toDouble();
        lon = lon.toDouble();
        // Reject the known junk values: [0,0] and [180,180].
        if (lat.abs() > 90.0 || lon.abs() > 180.0 ||
            (lat.abs() < 0.01 && lon.abs() < 0.01)) {
            log("Rejected location from " + source + ": " + lat + ", " + lon);
            return false;
        }
        if (_lat == null || (lat - _lat).abs() > 0.1 || (lon - _lon).abs() > 0.1) {
            _lat = lat;
            _lon = lon;
            log("Location from " + source + ": " + lat + ", " + lon);
            if (!_useManual) {
                Storage.setValue("lat", lat.toFloat());
                Storage.setValue("lon", lon.toFloat());
            }
            _solarKey = -1;
            _posKey = -1;
        }
        return true;
    }

    // ----- Solar day: ring bands and today's sun path ----------------------

    function setFallbackBands() {
        _bands = [[300, 1260, 0] as Array<Number>, [330, 1230, 0] as Array<Number>,
                  [360, 1200, 0] as Array<Number>, [390, 1170, 0] as Array<Number>]
                 as Array<Array<Number>>;
    }

    function refreshSolar() {
        var today = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var key = today.year * 400 + today.month * 32 + today.day;
        if (key == _solarKey) { return; }
        _solarKey = key;
        // Snow season: Dec-Mar north of the equator, Jun-Sep south of it.
        var m = today.month;
        _winter = (_lat != null && _lat < 0) ? (m >= 6 && m <= 9)
                                             : (m == 12 || m <= 3);

        if (_lat == null) {
            setFallbackBands();
            _sunPath = [] as Array<Array<Number>>;
            return;
        }
        var midnight = Time.today().value();
        var jdNoon = (midnight + 43200).toDouble() / 86400.0d + 2440587.5d;
        _bands = [] as Array<Array<Number>>;
        for (var i = 0; i < 4; i++) {
            _bands.add(sunTimes(jdNoon, _bandAlt[i]));
        }

        // Today's sun path, sampled every 20 min. Declination is taken at
        // noon; it moves < 0.4 deg per day, invisible at this scale.
        _sunPath = [] as Array<Array<Number>>;
        var s = sunRaDec(daysJ2000(midnight + 43200));
        for (var t = 0; t < 1440; t += 20) {
            var h = horizontal(daysJ2000(midnight + t * 60), s[0], s[1]);
            if (h[0] > VISIBLE_ALT) { _sunPath.add(skyXY(h[0], h[1], SUN_R)); }
        }
    }

    // Sunrise equation. Returns [riseMin, setMin, state] for the moments
    // the sun's center crosses `altitude`.
    function sunTimes(jdNoon, altitude) as Array<Number> {
        var n = Math.round(jdNoon - 2451545.0d);
        var jStar = n - _lon / 360.0d;
        var m = wrap360(357.5291d + 0.98560028d * jStar);
        var mr = m * RAD;
        var c = 1.9148d * Math.sin(mr) + 0.02d * Math.sin(2 * mr) +
                0.0003d * Math.sin(3 * mr);
        var lambda = wrap360(m + c + 282.9372d);
        var lr = lambda * RAD;
        var transit = 2451545.0d + jStar + 0.0053d * Math.sin(mr) -
                      0.0069d * Math.sin(2 * lr);
        var sinDec = Math.sin(lr) * Math.sin(23.4397d * RAD);
        var cosDec = Math.sqrt(1 - sinDec * sinDec);
        var latR = _lat * RAD;
        var cosW = (Math.sin(altitude * RAD) - Math.sin(latR) * sinDec) /
                   (Math.cos(latR) * cosDec);
        if (cosW > 1) { return [0, 0, 1] as Array<Number>; }
        if (cosW < -1) { return [0, 0, 2] as Array<Number>; }
        var w = Math.acos(cosW) / RAD;
        return [jdToMinutes(transit - w / 360.0d),
                jdToMinutes(transit + w / 360.0d), 0] as Array<Number>;
    }

    // ----- Live sky: sun and moon positions, moon phase --------------------

    function refreshSky() {
        if (_lat == null) { return; }
        var now = Time.now().value();
        var key = now / 60;
        if (key == _posKey) { return; }      // Once per minute is plenty.
        _posKey = key;

        var d = daysJ2000(now);
        var sun = sunRaDec(d);
        var moon = moonRaDecDist(d);

        var sh = horizontal(d, sun[0], sun[1]);
        _sunAlt = sh[0];
        _sunAz = sh[1];

        var mh = horizontal(d, moon[0], moon[1]);
        // The Moon is close enough that parallax lowers it by ~1 deg.
        var parallax = Math.asin(6378.14d / moon[2]) / RAD;
        _moonAlt = mh[0] - parallax * Math.cos(mh[0] * RAD);
        _moonAz = mh[1];

        // Illumination from the Sun-Moon geometry (not a mean cycle).
        var sRa = sun[0] * RAD;
        var sDec = sun[1] * RAD;
        var mRa = moon[0] * RAD;
        var mDec = moon[1] * RAD;
        var cosPhi = Math.sin(sDec) * Math.sin(mDec) +
                     Math.cos(sDec) * Math.cos(mDec) * Math.cos(sRa - mRa);
        if (cosPhi > 1.0) { cosPhi = 1.0; }
        if (cosPhi < -1.0) { cosPhi = -1.0; }
        var phi = Math.acos(cosPhi);
        var sunDist = 149598000.0d;
        var inc = Math.atan2(sunDist * Math.sin(phi), moon[2] - sunDist * Math.cos(phi));
        var ang = Math.atan2(Math.cos(sDec) * Math.sin(sRa - mRa),
                             Math.sin(sDec) * Math.cos(mDec) -
                             Math.cos(sDec) * Math.sin(mDec) * Math.cos(sRa - mRa));
        _moonLit = (1.0 + Math.cos(inc)) / 2.0;
        _moonPhase = 0.5 + 0.5 * inc * ((ang < 0) ? -1 : 1) / Math.PI;
    }

    function daysJ2000(unix) {
        return (unix - J2000_UNIX).toDouble() / 86400.0d;
    }

    // Low-precision solar position. Returns [raDeg, decDeg].
    function sunRaDec(d) as Array<Numeric> {
        var m = wrap360(357.5291d + 0.98560028d * d);
        var mr = m * RAD;
        var c = 1.9148d * Math.sin(mr) + 0.02d * Math.sin(2 * mr) +
                0.0003d * Math.sin(3 * mr);
        return eclToEq(wrap360(m + c + 282.9372d), 0.0d);
    }

    // Lunar position with the main periodic terms (~0.3 deg).
    // Returns [raDeg, decDeg, distanceKm].
    function moonRaDecDist(d) as Array<Numeric> {
        var lm = wrap360(218.316d + 13.176396d * d);           // Mean longitude.
        var mm = wrap360(134.963d + 13.064993d * d) * RAD;     // Mean anomaly.
        var f = wrap360(93.272d + 13.229350d * d) * RAD;       // Arg. of latitude.
        var ms = wrap360(357.5291d + 0.98560028d * d) * RAD;   // Sun mean anomaly.
        var dd = wrap360(lm - (280.466d + 0.98564736d * d)) * RAD; // Elongation.

        var lon = lm + 6.289d * Math.sin(mm)
                     - 1.274d * Math.sin(mm - 2 * dd)          // Evection.
                     + 0.658d * Math.sin(2 * dd)               // Variation.
                     - 0.186d * Math.sin(ms)                   // Yearly equation.
                     - 0.059d * Math.sin(2 * mm - 2 * dd)
                     - 0.057d * Math.sin(mm - 2 * dd + ms)
                     + 0.053d * Math.sin(mm + 2 * dd);
        var lat = 5.128d * Math.sin(f) - 0.173d * Math.sin(f - 2 * dd);
        var dist = 385001.0d - 20905.0d * Math.cos(mm)
                             - 3699.0d * Math.cos(2 * dd - mm)
                             - 2956.0d * Math.cos(2 * dd);
        var eq = eclToEq(wrap360(lon), lat);
        return [eq[0], eq[1], dist] as Array<Numeric>;
    }

    function eclToEq(lDeg, bDeg) as Array<Numeric> {
        var l = lDeg * RAD;
        var b = bDeg * RAD;
        var e = 23.4397d * RAD;
        var ra = Math.atan2(Math.sin(l) * Math.cos(e) - Math.tan(b) * Math.sin(e),
                            Math.cos(l));
        var dec = Math.asin(Math.sin(b) * Math.cos(e) +
                            Math.cos(b) * Math.sin(e) * Math.sin(l));
        return [ra / RAD, dec / RAD] as Array<Numeric>;
    }

    // Returns [altitudeDeg, azimuthDeg]; azimuth from south, + toward west.
    function horizontal(d, raDeg, decDeg) as Array<Numeric> {
        var lst = wrap360(280.16d + 360.9856235d * d + _lon);
        var h = wrap360(lst - raDeg) * RAD;
        var phi = _lat * RAD;
        var dec = decDeg * RAD;
        var alt = Math.asin(Math.sin(phi) * Math.sin(dec) +
                            Math.cos(phi) * Math.cos(dec) * Math.cos(h));
        var az = Math.atan2(Math.sin(h),
                            Math.cos(h) * Math.sin(phi) - Math.tan(dec) * Math.cos(phi));
        return [alt / RAD, az / RAD] as Array<Numeric>;
    }

    // Scene coordinates. North of the equator you face south (east on the
    // left); south of it you face north (east on the right).
    function skyXY(alt, az, r) as Array<Number> {
        var a = az;
        if (_lat < 0) {
            a = az - 180.0;
            if (a <= -180.0) { a += 360.0; }
        }
        var dx = a * AZ_PX;
        if (dx > AZ_MAX_PX) { dx = AZ_MAX_PX; }
        if (dx < -AZ_MAX_PX) { dx = -AZ_MAX_PX; }
        // Above SINK_DEG the body rides its altitude. Below it, the body
        // slides down into the horizon, fully hidden at the moment it sets
        // (the caller clips everything at the horizon line).
        var y;
        if (alt >= SINK_DEG) {
            y = HORIZON_Y - r - (alt - SINK_DEG) * ALT_PX;
        } else {
            var f = (SINK_DEG - alt) / (SINK_DEG - VISIBLE_ALT);
            if (f > 1.0) { f = 1.0; }
            y = HORIZON_Y - r + f * 2 * r;
        }
        return [Math.round(CX + dx).toNumber(), Math.round(y).toNumber()] as Array<Number>;
    }

    function jdToMinutes(jd) as Number {
        var unix = ((jd - 2440587.5d) * 86400.0d).toNumber();
        var info = Gregorian.info(new Time.Moment(unix), Time.FORMAT_SHORT);
        return info.hour * 60 + info.min;
    }

    function wrap360(x) {
        var r = x - (x / 360.0d).toLong() * 360.0d;
        if (r < 0) { r += 360.0d; }
        return r;
    }

    // Design-space pixels (260 px screen) to this screen's pixels.
    function sc(v) as Number {
        return Math.round(v * _s).toNumber();
    }

    // Pen widths and dot radii: scaled, but never below 1 px.
    function pw(v) as Number {
        var n = Math.round(v * _s).toNumber();
        return (n < 1) ? 1 : n;
    }

    // Debug-build logging. The (:release) twin compiles to nothing, so
    // release builds (like "Build for Device", which uses -r) carry no logging.
    (:debug)
    function log(msg) { Sys.println(msg); }

    (:release)
    function log(msg) { }

    // Called by CircadiaDelegate if the watch rules that once-a-second
    // updates cost too much power. Seconds then show only on wrist raise.
    function onBudgetExceeded() {
        _budgetExceeded = true;
        log("Partial update budget exceeded: seconds now wrist-raise only");
        WatchUi.requestUpdate();
    }

    // ----- Time helpers ------------------------------------------------------

    function inWindow(m, start, end) {
        if (start <= end) { return m >= start && m < end; }
        return m >= start || m < end;   // Window wraps past midnight.
    }

    // Is the sun above band i's altitude at minute m?
    function bandContains(i, m) {
        var b = _bands[i];
        if (b[2] == 1) { return false; }
        if (b[2] == 2) { return true; }
        return inWindow(m, b[0], b[1]);
    }

    function formatHM(m) {
        var h = m / 60;
        var mi = m % 60;
        var use24 = Sys.getDeviceSettings().is24Hour;
        if (!use24) {
            h %= 12;
            if (h == 0) { h = 12; }
        }
        return h.format(use24 ? "%02d" : "%d") + ":" + mi.format("%02d");
    }

    // ----- Geometry ------------------------------------------------------------

    // Screen angle: midnight at bottom, noon at top, time runs clockwise.
    function angleFor(m) {
        return (90.0 + m.toFloat() / 4.0) * Math.PI / 180.0;
    }

    function polar(a, r) as Array<Number> {
        return [Math.round(CX + Math.cos(a) * r).toNumber(),
                Math.round(CY + Math.sin(a) * r).toNumber()] as Array<Number>;
    }

    // drawArc degrees: 0 = 3 o'clock, counter-clockwise positive.
    function arcDeg(m) {
        var d = 270.0 - m.toFloat() / 4.0;
        while (d < 0) { d += 360.0; }
        return d;
    }

    // ----- Ring ----------------------------------------------------------------

    function drawRing(dc) {
        dc.setPenWidth(RING_W);
        if (_lat == null) {
            // No location: a plain gray ring rather than fake bands.
            dc.setColor(C_GROUND, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(CX, CY, RING_R);
            drawTicks(dc, false);
            return;
        }
        dc.setColor(C_NIGHT, Gfx.COLOR_TRANSPARENT);
        dc.drawCircle(CX, CY, RING_R);

        // Darkest band first; each lighter band paints over the middle of
        // the one before, leaving graded dusk and dawn on both sides.
        // Twilight setting: 0 draws bands 0-3, 1 skips astro and nautical,
        // 2 draws only the day band.
        var first = (_twilightMode == 2) ? 3 : (_twilightMode == 1 ? 2 : 0);
        for (var i = first; i < 4; i++) {
            var b = _bands[i];
            if (b[2] == 2) {
                dc.setColor(_bandColor[i], Gfx.COLOR_TRANSPARENT);
                dc.drawCircle(CX, CY, RING_R);
            } else if (b[2] == 0 && b[0] != b[1]) {
                dc.setColor(_bandColor[i], Gfx.COLOR_TRANSPARENT);
                dc.drawArc(CX, CY, RING_R, Gfx.ARC_CLOCKWISE,
                           arcDeg(b[0]), arcDeg(b[1]));
            }
        }

        drawTicks(dc, true);
    }

    function drawTicks(dc, useBands) {
        for (var h = 0; h < 24; h++) {
            var major = (h % 6) == 0;
            var a = angleFor(h * 60);
            var p = polar(a, major ? R_INNER - sc(1) : R_OUTER - sc(6));
            var q = polar(a, R_OUTER + sc(1));
            var light = !useBands || bandContains(2, h * 60);
            dc.setColor(light ? Gfx.COLOR_BLACK : C_GROUND, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(major ? pw(3) : pw(1));
            dc.drawLine(p[0], p[1], q[0], q[1]);
        }
    }

    function drawPointer(dc, minutes) {
        var a = angleFor(minutes);
        var s1 = 7.0 * Math.PI / 180.0;
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.fillPolygon([polar(a - s1, R_OUTER + sc(4)), polar(a + s1, R_OUTER + sc(4)),
                        polar(a, R_INNER - sc(3))]);
        var s2 = 5.5 * Math.PI / 180.0;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_WHITE);
        dc.fillPolygon([polar(a - s2, R_OUTER + sc(2)), polar(a + s2, R_OUTER + sc(2)),
                        polar(a, R_INNER)]);
    }

    // AMOLED always-on view. OLED pixels age with use, so while the watch
    // is idle only a small fraction of the screen may be lit (Garmin's limit
    // is 10%). This keeps the face recognizable at well under that: the time
    // in gray, a thin daylight arc, and the pointer.
    function drawAlwaysOn(dc, clock, minutes) {
        if (_lat != null && _bands[3][2] == 0) {
            dc.setPenWidth(pw(2));
            dc.setColor(C_SUN_GLOW, Gfx.COLOR_TRANSPARENT);
            dc.drawArc(CX, CY, R_OUTER - sc(3), Gfx.ARC_CLOCKWISE,
                       arcDeg(_bands[3][0]), arcDeg(_bands[3][1]));
        }
        var a = angleFor(minutes);
        var sp = 4.0 * Math.PI / 180.0;
        dc.setColor(C_DIM, C_DIM);
        dc.fillPolygon([polar(a - sp, R_OUTER), polar(a + sp, R_OUTER),
                        polar(a, R_OUTER - sc(14))]);
        dc.setColor(C_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(CX, CY, _timeFont, formatHM(clock.hour * 60 + clock.min),
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // ----- Sky scene -------------------------------------------------------

    function drawStars(dc, minutes, sec) {
        // Asleep the pattern shifts once a minute; awake (onUpdate runs
        // every second after a wrist raise) the stars visibly twinkle.
        var phase = _awake ? sec : minutes;
        var box = _colBox;
        for (var i = 0; i < _stars.size(); i++) {
            var sx = _stars[i][0];
            var sy = _stars[i][1];
            if (box != null &&
                sx >= box[0] - sc(3) && sx <= box[0] + box[2] + sc(3) &&
                sy >= box[1] - sc(3) && sy <= box[1] + box[3] + sc(3)) {
                continue;   // Keep clear of AM/PM and the partial-update area.
            }
            var state = (i * 7 + phase) % 6;
            if (state == 0) {
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, pw(2));
            } else {
                dc.setColor((state == 3) ? C_GROUND : C_DIM, Gfx.COLOR_TRANSPARENT);
                dc.fillCircle(sx, sy, pw(1));
            }
        }
    }

    // A two-frame meteor, only while awake at night. Watch faces get one
    // redraw per second, so each frame holds for a second: first the streak
    // appears, then it lengthens and fades toward the far end of its path.
    function drawShootingStar(dc) {
        if (!_shootingStars || !_awake) { return; }
        if (_shoot == 0) {
            if ((Math.rand() % SHOOT_CHANCE) != 0) { return; }
            _shoot = 2;
            _shootPath = Math.rand() % _shootPaths.size();
        }
        var p = _shootPaths[_shootPath];
        var head = (_shoot == 2) ? 0.55 : 1.0;
        var tail = (_shoot == 2) ? 0.05 : 0.45;
        var colors = [C_GROUND, C_DIM, Gfx.COLOR_WHITE] as Array<Number>;
        dc.setPenWidth(pw(2));
        for (var k = 0; k < 3; k++) {
            var t0 = tail + (head - tail) * k / 3.0;
            var t1 = tail + (head - tail) * (k + 1) / 3.0;
            dc.setColor(colors[k], Gfx.COLOR_TRANSPARENT);
            dc.drawLine(p[0] + (p[2] - p[0]) * t0, p[1] + (p[3] - p[1]) * t0,
                        p[0] + (p[2] - p[0]) * t1, p[1] + (p[3] - p[1]) * t1);
        }
        _shoot -= 1;
    }

    function drawScene(dc, minutes) {
        // Today's sun path: bright while the sun is up; after sunset either
        // dimmed (default) or left bright, per the setting.
        dc.setClip(0, 0, _w, HORIZON_Y - 1);      // Nothing shows below ground.
        if (_pathMode != 2) {
            var sunUp = (_lat != null && _sunAlt > VISIBLE_ALT);
            var dim = (_pathMode == 0 && !sunUp);
            dc.setColor(dim ? C_PATH_NIGHT : C_DIM, Gfx.COLOR_TRANSPARENT);
            for (var i = 0; i < _sunPath.size(); i++) {
                dc.fillCircle(_sunPath[i][0], _sunPath[i][1], pw(1));
            }
        }

        dc.clearClip();
        if (!_flatHorizon) { drawMountains(dc); }
        dc.setColor(C_GROUND, C_GROUND);
        dc.setPenWidth(pw(2));
        dc.drawLine(CX - sc(70), HORIZON_Y, CX + sc(70), HORIZON_Y);

        if (_lat != null) {
            dc.setClip(0, 0, _w, HORIZON_Y - 1);
            if (_moonAlt > VISIBLE_ALT) {
                var mp = skyXY(_moonAlt, _moonAz, MOON_R);
                drawMoon(dc, mp[0], mp[1], MOON_R);
            }
            if (_sunAlt > VISIBLE_ALT) {
                var sp = skyXY(_sunAlt, _sunAz, SUN_R);
                dc.setColor(C_SUN_GLOW, C_SUN_GLOW);
                dc.fillCircle(sp[0], sp[1], SUN_R + sc(2));
                dc.setColor(C_DAY, C_DAY);
                dc.fillCircle(sp[0], sp[1], SUN_R);
            }
            dc.clearClip();
        }

        if (_lat == null) {
            textCenter(dc, CX, SOLAR_LABEL_Y, Gfx.FONT_XTINY, "Locating...", C_DIM);
            return;
        }
        var riseText = "--";
        var setText = "--";
        if (_bands[3][2] == 0) {
            riseText = formatHM(_bands[3][0]);
            setText = formatHM(_bands[3][1]);
            // Wrist raise: the next event's label becomes a countdown.
            if (_awake && _wristInfo) {
                var up = bandContains(3, minutes);
                var target = up ? _bands[3][1] : _bands[3][0];
                var left = (target - minutes + 1440) % 1440;
                var cd = "in " + (left / 60).format("%d") + ":" + (left % 60).format("%02d");
                if (up) { setText = cd; } else { riseText = cd; }
            }
        }
        textCenter(dc, CX - SOLAR_LABEL_DX, SOLAR_LABEL_Y, Gfx.FONT_XTINY,
                   riseText, C_DAY);
        textCenter(dc, CX + SOLAR_LABEL_DX, SOLAR_LABEL_Y, Gfx.FONT_XTINY,
                   setText, C_DAY);
    }

    // Near range points alternate valley, peak, valley... (even = valley).
    // Each peak is drawn as its own triangle, its slopes extended down to
    // the horizon, split at the summit into a lit face and a shaded face.
    // Lower peaks first, so taller ones stand in front.
    function drawMountains(dc) {
        dc.setColor(C_FAR_RANGE, C_FAR_RANGE);
        dc.fillPolygon(_farRange);

        var light = null;                        // x of the sun, or moon at night.
        var litColor = C_ROCK_LIT;
        if (_lat != null && _sunAlt > VISIBLE_ALT) {
            light = skyXY(_sunAlt, _sunAz, SUN_R)[0];
        } else if (_lat != null && _moonAlt > VISIBLE_ALT) {
            light = skyXY(_moonAlt, _moonAz, MOON_R)[0];
            litColor = C_ROCK_MOON;
        }

        for (var k = 0; k < _peakOrder.size(); k++) {
            var i = _peakOrder[k];
            var peak = _mountains[i];
            var footL = foot(peak, _mountains[i - 1]);
            var footR = foot(peak, _mountains[i + 1]);
            var base = [peak[0], HORIZON_Y] as Array<Number>;
            dc.setColor(C_GROUND, C_GROUND);
            dc.fillPolygon([footL, peak, footR]);
            if (light != null) {
                dc.setColor(litColor, litColor);
                dc.fillPolygon([(light < peak[0]) ? footL : footR, peak, base]);
            }
            // Winter snowcap on peaks at least 10 px tall: the top 3 px.
            if (_winter && (HORIZON_Y - peak[1]) >= sc(10)) {
                var f = sc(3).toFloat() / (HORIZON_Y - peak[1]);
                dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_WHITE);
                dc.fillPolygon([
                    [Math.round(peak[0] + (footL[0] - peak[0]) * f).toNumber(), peak[1] + sc(3)] as Array<Number>,
                    peak,
                    [Math.round(peak[0] + (footR[0] - peak[0]) * f).toNumber(), peak[1] + sc(3)] as Array<Number>,
                    [peak[0] + sc(1), peak[1] + sc(2)] as Array<Number>]);   // Ragged lower edge.
            }
        }
    }

    // Where the slope from `peak` through `valley` meets the horizon.
    function foot(peak as Array<Number>, valley as Array<Number>) as Array<Number> {
        var t = (HORIZON_Y - peak[1]).toFloat() / (valley[1] - peak[1]);
        return [Math.round(peak[0] + (valley[0] - peak[0]) * t).toNumber(), HORIZON_Y] as Array<Number>;
    }

    function drawMoon(dc, x, y, r) {
        // Dim full disc for the dark side, then the lit part row by row.
        dc.setColor(C_NIGHT, C_NIGHT);
        dc.fillCircle(x, y, r);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_WHITE);
        var k = Math.cos(2 * Math.PI * _moonPhase);
        // Lit side faces west: right in the north, left in the south.
        var litRight = (_moonPhase < 0.5) != (_lat < 0);
        for (var row = -r; row <= r; row++) {
            var w = Math.sqrt(r * r - row * row);
            var a;
            var b;
            if (litRight) { a = w * k; b = w; }
            else { a = -w; b = -w * k; }
            var left = Math.round(x + a).toNumber();
            var width = Math.round(b - a).toNumber();
            if (width > 0) { dc.fillRectangle(left, y + row, width, 1); }
        }
    }

    // ----- Text ------------------------------------------------------------

    function textCenter(dc, x, y, font, text, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text,
                    Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    function drawTemperature(dc) {
        // How old is the phone's last weather observation? Unknown counts
        // as fresh, since some providers omit the timestamp.
        var age = 0;
        if (_weatherTime != null) { age = Time.now().value() - _weatherTime; }

        var temp = "--°";
        var color = C_DIM;
        if (_tempC != null && age <= WEATHER_EXPIRED) {
            var v = _tempC.toFloat();
            if (Sys.getDeviceSettings().temperatureUnits == Sys.UNIT_STATUTE) {
                v = v * 9.0 / 5.0 + 32.0;
            }
            temp = Math.round(v).toNumber().format("%d") + "°";
            color = (age > WEATHER_STALE) ? C_DIM : Gfx.COLOR_WHITE;
        }
        // Center on the digits, then hang the degree sign off the right,
        // so "55" sits on the face's centerline rather than "55°".
        var digits = temp.substring(0, temp.length() - 1);
        var dw = dc.getTextWidthInPixels(digits, Gfx.FONT_SMALL);
        var left = CX - dw / 2;
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(left, TEMP_Y, Gfx.FONT_SMALL, temp,
                    Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);

        // Phone disconnected: a crossed-out phone just left of the reading.
        if (!Sys.getDeviceSettings().phoneConnected) {
            var px = left - sc(16);
            var py = TEMP_Y - sc(7);
            dc.setPenWidth(pw(1));
            dc.setColor(C_DIM, Gfx.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(px, py, sc(8), sc(14), sc(2));                // Body.
            dc.drawLine(px + sc(3), py + sc(11), px + sc(5), py + sc(11));        // Home button.
            dc.setPenWidth(pw(2));
            dc.setColor(C_WARN, Gfx.COLOR_TRANSPARENT);
            dc.drawLine(px - sc(2), py + sc(15), px + sc(10), py - sc(1));        // Slash.
        }
    }

    // Mirrored readouts: icons toward the ring, numbers toward the center.
    function drawCorners(dc) {
        var battery = Sys.getSystemStats().battery.toNumber();
        var low = battery <= LOW_BATTERY;
        if ((_batteryMode == 1) || (_batteryMode == 0 && low)) {
            var color = low ? C_WARN : C_DIM;
            var bx = CX - SLOT_DX - sc(22);      // Icon's left edge.
            var by = SLOT_Y - sc(4);
            dc.setColor(color, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(pw(1));
            dc.drawRectangle(bx, by, sc(14), sc(9));              // Body.
            dc.fillRectangle(bx + sc(14), by + sc(2), sc(2), sc(5));   // Terminal.
            var fill = (sc(10) * battery / 100.0 + 0.5).toNumber();
            if (fill < 1 && battery > 0) { fill = 1; }
            if (fill > 0) { dc.fillRectangle(bx + sc(2), by + sc(2), fill, sc(5)); }
            dc.drawText(bx + sc(20), SLOT_Y, Gfx.FONT_XTINY, battery.format("%d") + "%",
                        Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        }

        if (_moonReadout && _lat != null) {
            var mx = CX + SLOT_DX + sc(12);      // Icon center.
            drawMoon(dc, mx, SLOT_Y, sc(5));
            var pct = Math.round(_moonLit * 100).toNumber().format("%d") + "%";
            dc.setColor(C_DIM, Gfx.COLOR_TRANSPARENT);
            dc.drawText(mx - sc(9), SLOT_Y, Gfx.FONT_XTINY, pct,
                        Gfx.TEXT_JUSTIFY_RIGHT | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }

    function drawClock(dc, clock) {
        var text = formatHM(clock.hour * 60 + clock.min);
        var mainW = dc.getTextWidthInPixels(text, _timeFont);
        var top = TIME_Y - dc.getFontHeight(_timeFont) / 2;
        var baseline = top + dc.getFontAscent(_timeFont);

        // Right-hand column beside HH:MM: AM/PM stacked above the seconds.
        // "Wrist raise only" still reserves the seconds slot, so HH:MM
        // doesn't shift sideways every time you look at the watch.
        var secSlot = (_secondsMode != 2);
        var ampm = _showAmPm && !Sys.getDeviceSettings().is24Hour;
        var secW = dc.getTextWidthInPixels("88", _secFont);
        var colW = secSlot ? secW : 0;
        if (ampm) {
            var aw = dc.getTextWidthInPixels("PM", _ampmFont);
            if (aw > colW) { colW = aw; }
        }
        var total = (colW > 0) ? mainW + SEC_GAP + colW : mainW;
        var left = CX - total / 2;

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(left, top, _timeFont, text, Gfx.TEXT_JUSTIFY_LEFT);

        var always = (_secondsMode == 0 && !_budgetExceeded);
        _partialSeconds = always;
        _secBox = null;
        _colBox = null;
        if (colW == 0) { return; }

        // Seconds share the baseline of HH:MM.
        _secX = left + mainW + SEC_GAP;
        _secY = baseline - dc.getFontAscent(_secFont);
        var secH = dc.getFontHeight(_secFont);
        var colTop = _secY;
        if (secSlot) {
            _secBox = [_secX - 1, _secY, secW + 2, secH] as Array<Number>;
            // Awake (after a wrist raise) onUpdate runs every second anyway.
            if (always || _awake) { drawSeconds(dc, clock.sec); }
        }
        if (ampm) {
            // Text box sits directly on top of the seconds' text box.
            var ampmY = _secY - dc.getFontHeight(_ampmFont) + AMPM_DY;
            dc.setColor(C_DIM, Gfx.COLOR_TRANSPARENT);
            dc.drawText(_secX, ampmY, _ampmFont, (clock.hour < 12) ? "AM" : "PM",
                        Gfx.TEXT_JUSTIFY_LEFT);
            colTop = ampmY;
        }
        _colBox = [_secX - 1, colTop, colW + 2, _secY + secH - colTop] as Array<Number>;
    }

    function drawSeconds(dc, sec) {
        dc.setColor(C_DIM, Gfx.COLOR_TRANSPARENT);
        dc.drawText(_secX, _secY, _secFont, sec.format("%02d"),
                    Gfx.TEXT_JUSTIFY_LEFT);
    }

    function drawDateLine(dc, minutes) {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var text = info.day_of_week + " " + info.month + " " + info.day.format("%d");
        textCenter(dc, CX, DATE_Y, Gfx.FONT_TINY, text, C_DIM);
    }
}
