# NetWho

See who's on your network, on Linux desktop and Android. A simple, free
network scanner for keeping an eye on your home network. No account needed,
and scan results stay on your device.

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
- **Range scan:** sweep other subnets or custom ranges, several at once
  (`10.1.0.0/24, 10.2.5.1-120, 172.16.*.*`, single IPs). It keeps recent
  ranges and keeps running if you leave the page. **Export** saves results
  as a CSV file (the share sheet on Android) or copies them to the
  clipboard. Ping-only by default; turn on "Also check common ports" to
  catch hosts that ignore ping.
  Routed subnets get hostnames and Windows names; MACs are only available
  on your own segment.
- **Tools tab:** range scan, public IP and provider, speed test, ping,
  traceroute, port scan, DNS lookup, Wake-on-LAN.
- Scans only when you tap **Scan**; on launch it just shows what it
  remembers.
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
  `netbios`, `oui`, `ports`, `ping`, `tools`, `wol`, `ip_range`).
- `lib/state/range_scan_controller.dart`: the range scanner.
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

### Release signing

Release APKs are signed with NetWho's release key, which never lives in this
repository. On the maintainer's machine it is in `~/.android-keys/`
(created once with `packaging/create-signing-key.sh`), and the build finds
it automatically. Point `NETWHO_KEY_PROPERTIES` at a different
`key.properties` file to use another location.

Without the key, `flutter build apk --release` stops with an error, so a
debug-signed APK can't be published by accident. To build your own copy
from source, either create your own key with the script or opt into debug
signing:

```bash
NETWHO_ALLOW_DEBUG_SIGNING=1 flutter build apk --release --split-per-abi
```

Check which key signed an APK:

```bash
~/Android/Sdk/build-tools/36.0.0/apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Official releases are signed by the certificate with this SHA-256
fingerprint:

```
53:EF:EA:DB:D7:C0:4B:C0:FB:9F:DE:4A:75:5D:50:38:EB:4F:8E:7A:88:B9:27:2D:9C:B4:F0:F2:C1:02:DF:03
```

## Credits

MAC vendor data: [Wireshark manuf](https://www.wireshark.org/download/automated/data/manuf)
(GPLv2 data file).
