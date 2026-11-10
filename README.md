# Circadia

A Garmin Connect IQ **watch face** (Monkey C) that shows the time over a live sky for your location. It computes the
sun's and moon's positions on the watch and draws the sun's path across the day, twilight bands, the moon, stars and
a horizon.

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

## What's not in the repository

Build outputs (`bin/`, `build/`), the signed store package (`publish/Circadia.iq`) and the developer signing key are
not committed.

## License

No license has been chosen.
