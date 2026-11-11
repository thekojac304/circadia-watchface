# Circadia

A Garmin Connect IQ **watch face** (Monkey C) that shows the time over a live sky for your location. It computes the
sun's and moon's positions on the watch and draws the sun's path across the day, twilight bands, the moon, stars and
a horizon.

## Download

**[Circadia 0.1.0 (preview)](https://github.com/thekojac304/circadia-watchface/releases/tag/v0.1.0)**:

- `Circadia-0.1.0-sideload.zip`: one ready-built `Circadia.prg` per supported watch, with `DEVICES.txt` and
  `INSTALL.txt`.
- `Circadia-0.1.0.iq`: the signed Connect IQ export package the `.prg` files come from.
- `SHA256SUMS.txt`.

Circadia isn't on the Connect IQ Store, so it's installed by sideloading:

1. Find your watch in `DEVICES.txt` (52 models: recent fēnix, epix, Forerunner, Enduro, Descent, D2, Approach and
   tactix/quatix variants).
2. Connect the watch by USB and copy that folder's `Circadia.prg` into `GARMIN\APPS` on the watch.
3. Disconnect and choose Circadia in the watch-face list.

Change its settings on the watch: hold MENU on the watch face, then Watch Face → Circadia → Customize. Delete
`GARMIN\APPS\Circadia.prg` to remove it.

## Features

- **Sky model.** Sun and moon positions, sunrise and sunset, and twilight are computed on
  the watch from GPS or a manual latitude and longitude.
- **Display settings:**
  - Sun path: dim, bright or hidden.
  - Twilight bands: all, civil only or none.
  - Horizon: mountains or flat.
  - Stars and shooting stars, and a moon phase readout.
- **Time display:**
  - Seconds: always, on wrist raise or off.
  - AM/PM marker, or military format for 24-hour time.
  - Extra info on wrist raise.
- **Battery indicator:** low only, always or never.
- **Location:** GPS by default; a manual latitude and longitude can be used instead.

## Building

1. Install the Connect IQ SDK (minimum API level 4.2.0).
2. Run `monkeyc` with `monkey.jungle` and your own developer key. The `.vscode/launch.json` works with the Monkey C
   VS Code extension.

`manifest.xml` lists 52 supported devices.

## Status

Preview. Built with the Connect IQ SDK and developed against its simulator. No test on a physical watch is recorded in
this repository yet, so keep another watch face installed and report problems with your model.

## What's not in the repository

Build outputs (`bin/`, `build/`) and the developer signing key are not committed. The signed package is attached to
the release instead.

## License

MIT ([LICENSE](LICENSE)). Garmin, Connect IQ and the watch names are trademarks of Garmin Ltd.; building the
watch face uses the Connect IQ SDK under Garmin's own SDK license. This project isn't affiliated with Garmin.
