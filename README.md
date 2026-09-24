# NetWho

See who's on your network, on Linux desktop and Android. It's in the spirit
of Fing, minus the ads, nags, accounts and tracking. Scan results stay on
the device.

## Features

- **Device discovery:** sweeps your subnet with ping plus TCP probes, then
  reads the ARP table (Linux), so devices that ignore ping still show up.
- **Names and identities:** router DNS, mDNS/Bonjour (Chromecast, AirPlay,
  printers, HomeKit…), UPnP descriptions, and Windows/Samba NetBIOS names.
- **Manufacturer** from the MAC address (Wireshark's OUI database, bundled).
  Randomized "private" MACs are marked as such.
- **Device type guess** (router, TV, speaker, printer, NAS, phone…) that you
  can override.
- **Remembers devices** per network: custom names, types and notes; offline
  devices with a last-seen time; a **NEW** badge for devices that weren't
  there before.
- **Per device:** ping, port scan (with plain-language service names),
  open its web page, Wake-on-LAN, copy any detail (long-press).
- **Tools tab:** public IP and provider, speed test, ping, traceroute, port
  scan, DNS lookup, Wake-on-LAN.
- Light / dark / follow-system theme (⋮ menu).

### Network use outside your LAN

Only the **public IP lookup** (Cloudflare `1.1.1.1/cdn-cgi/trace`,
`ipinfo.io`) and the **speed test** (`speed.cloudflare.com`) reach the
internet, and only when you tap them. A speed test can use a few hundred MB
on a fast connection.

## Platform notes

| | Linux | Android |
|---|---|---|
| Finds devices | ✔ | ✔ |
| MAC address and vendor | ✔ for every device | Only via NetBIOS/mDNS (Android 10+ blocks the ARP table) |
| Wi-Fi name | ✔ | Tap **Show Wi-Fi name**; Android requires location permission for it |

Android keys remembered devices by IP when it can't get a MAC, so if the
router hands a device a new address, it can show up as a new device.

Large networks (bigger than a /22, about 1,000 addresses) are narrowed to the
/22 around your own address to keep scans quick.

## Development

```bash
flutter pub get
flutter run -d linux
flutter test
```

Code map:

- `lib/net/`: discovery and tools (`prober`, `arp`, `mdns`, `ssdp`,
  `netbios`, `oui`, `ports`, `ping`, `tools`, `wol`).
- `lib/state/scan_controller.dart`: runs a scan and merges it with
  remembered devices (`device_store.dart`, a JSON file in the app's data folder).
- `lib/models/device_type.dart`: type-guessing rules.
- `android/.../MainActivity.kt`: holds a Wi-Fi multicast lock during scans
  so mDNS replies aren't filtered.

Refresh the MAC vendor table:

```bash
curl -sSfLo /tmp/manuf https://www.wireshark.org/download/automated/data/manuf
python3 tool/build_oui.py /tmp/manuf
```

## Installing on Linux

To add it to the application menu (under **Internet**) with its icon, build
it, then run the installer. The menu entry points at the release bundle in
place, so later rebuilds are picked up without reinstalling. Re-run it if the
name, ID or icon changes:

```bash
./packaging/install-linux.sh
```

## Building releases

Linux bundle (output in `build/linux/x64/release/bundle/`):

```bash
flutter build linux --release
```

Android APK (output in `build/app/outputs/flutter-apk/`):

```bash
flutter build apk --release --split-per-abi
```

Use `app-arm64-v8a-release.apk` (~20 MB) on any modern phone, e.g. the
Pixel 8 Pro.

`compileSdk` is pinned to 37 in `android/app/build.gradle.kts` because
`permission_handler` requires it.

A release APK needs a signing key. Without one configured, `--release` falls
back to debug signing. That's fine for sideloading (updates install over the
old version as long as you build on the same machine), but not for the Play
Store; see https://docs.flutter.dev/deployment/android#signing-the-app.

## Credits

MAC vendor data: [Wireshark manuf](https://www.wireshark.org/download/automated/data/manuf)
(GPLv2 data file).
