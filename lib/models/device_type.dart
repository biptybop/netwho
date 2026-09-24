import 'package:flutter/material.dart';

import 'device.dart';

enum DeviceType {
  router('Router', Icons.router_outlined),
  accessPoint('Wi-Fi extender', Icons.wifi_outlined),
  computer('Computer', Icons.computer_outlined),
  laptop('Laptop', Icons.laptop_outlined),
  phone('Phone', Icons.smartphone_outlined),
  tablet('Tablet', Icons.tablet_outlined),
  tv('TV / streamer', Icons.tv_outlined),
  speaker('Speaker', Icons.speaker_outlined),
  printer('Printer', Icons.print_outlined),
  camera('Camera', Icons.videocam_outlined),
  nas('Storage / NAS', Icons.dns_outlined),
  server('Server', Icons.storage_outlined),
  gameConsole('Game console', Icons.sports_esports_outlined),
  smartHome('Smart home', Icons.home_outlined),
  lighting('Light', Icons.lightbulb_outline),
  plug('Smart plug', Icons.power_outlined),
  watch('Watch', Icons.watch_outlined),
  car('Car', Icons.directions_car_outlined),
  other('Other', Icons.devices_other_outlined),
  unknown('Unknown', Icons.device_unknown_outlined);

  const DeviceType(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Best guess from vendor, names, advertised services and open ports.
/// Deliberately simple — the user can always correct it.
DeviceType guessDeviceType(Device d) {
  if (d.isGateway) return DeviceType.router;

  final s = d.services;
  bool svc(String prefix) => s.any((x) => x.startsWith(prefix));
  final text = [
    d.vendor, d.hostname, d.mdnsName, d.netbiosName, d.upnpName, d.model,
    d.upnpManufacturer,
  ].whereType<String>().join(' ').toLowerCase().replaceAll(_nonWord, ' ');
  // Whole-word matching, so "ring" doesn't match "sharing".
  bool has(List<String> words) => words.any((w) => _wordRe(w).hasMatch(text));

  // Services are the most reliable signal.
  if (svc('_ipp') || svc('_printer') || svc('_pdl-datastream') || svc('_uscan')) {
    return DeviceType.printer;
  }
  if (svc('_googlecast') || svc('_airplay') || svc('_androidtvremote') ||
      svc('_amzn-wplay') || svc('_roku') || svc('_ecp') || svc('_viziocast') ||
      svc('_mediaremotetv')) {
    if (has(['speaker', 'home mini', 'nest mini', 'nest audio', 'homepod', 'audio'])) {
      return DeviceType.speaker;
    }
    if (has(['macbook', 'imac', 'mac mini', 'macmini'])) return DeviceType.laptop;
    return DeviceType.tv;
  }
  if (svc('_sonos') || svc('_spotify-connect') || svc('_raop')) {
    if (has(['macbook'])) return DeviceType.laptop;
    return DeviceType.speaker;
  }
  if (svc('_hue') || svc('_nanoleaf') || has(['hue bridge', 'lifx', 'nanoleaf', 'wiz'])) {
    return DeviceType.lighting;
  }
  if (svc('_hap') || svc('_matter') || svc('_esphome') || svc('_home-assistant') ||
      svc('_miio')) {
    return DeviceType.smartHome;
  }
  if (svc('_adisk') || svc('_afpovertcp')) return DeviceType.nas;

  if (has(['iphone', 'pixel', 'galaxy', 'android', 'oneplus', 'xiaomi', 'redmi',
      'motorola', 'oppo', 'vivo', 'huawei'])) {
    return DeviceType.phone;
  }
  if (has(['ipad', 'tablet', 'kindle', 'fire hd'])) return DeviceType.tablet;
  if (has(['watch'])) return DeviceType.watch;
  if (has(['macbook', 'laptop', 'thinkpad', 'zenbook', 'xps', 'surface'])) {
    return DeviceType.laptop;
  }
  if (has(['synology', 'qnap', 'diskstation', 'western digital', 'wd my', 'truenas',
      'unraid', 'asustor', 'buffalo', 'drobo', 'terramaster', 'xserve'])) {
    return DeviceType.nas;
  }
  if (has(['playstation', 'xbox', 'nintendo', 'sony interactive', 'steam deck', 'valve'])) {
    return DeviceType.gameConsole;
  }
  if (has(['roku', 'chromecast', 'fire tv', 'firetv', 'apple tv', 'appletv', 'shield',
      'bravia', 'lg electronics', 'tcl', 'hisense', 'vizio', 'samsung tv',
      'webos', 'tizen', 'smarttv', 'smart tv', 'television'])) {
    return DeviceType.tv;
  }
  if (has(['sonos', 'bose', 'echo', 'homepod', 'nest audio', 'home mini'])) {
    return DeviceType.speaker;
  }
  if (has(['ring', 'arlo', 'wyze', 'hikvision', 'dahua', 'reolink', 'amcrest',
      'blink', 'eufy', 'camera', 'ipcam', 'axis communications'])) {
    return DeviceType.camera;
  }
  if (has(['epson', 'brother', 'canon', 'lexmark', 'kyocera', 'xerox', 'hp',
      'hewlett', 'printer', 'officejet', 'laserjet', 'deskjet'])) {
    return DeviceType.printer;
  }
  if (has(['plug', 'tp link kasa', 'kasa', 'meross', 'shelly', 'tuya', 'smart life',
      'switch'])) {
    return DeviceType.plug;
  }
  if (has(['nest', 'ecobee', 'espressif', 'philips lighting', 'signify', 'ikea',
      'amazon technologies', 'google home', 'smartthings', 'thermostat',
      'tuya', 'broadlink', 'sonoff'])) {
    return DeviceType.smartHome;
  }
  if (has(['tesla', 'rivian'])) return DeviceType.car;
  if (has(['eero', 'orbi', 'deco', 'extender', 'repeater', 'access point', 'unifi',
      'ubiquiti', 'mesh'])) {
    return DeviceType.accessPoint;
  }

  final p = d.openPorts;
  if (p.contains(62078)) return DeviceType.phone; // Apple lockdownd
  // A networking brand answering DNS on the LAN is almost always a mesh node.
  if (p.contains(53) &&
      has(['netgear', 'linksys', 'tp link', 'asustek', 'eero', 'orbi', 'ubiquiti',
          'mikrotik', 'd link', 'zyxel', 'arris', 'technicolor', 'sagemcom', 'plume'])) {
    return DeviceType.accessPoint;
  }
  if (p.contains(3389) || p.contains(445) || p.contains(139) || d.netbiosName != null ||
      svc('_workstation') || svc('_smb') || svc('_rfb') || svc('_companion-link') ||
      has(['desktop', 'windows', 'intel corporate', 'micro-star', 'asustek',
          'gigabyte', 'dell', 'lenovo', 'imac', 'mac mini'])) {
    return DeviceType.computer;
  }
  if (p.contains(22) || svc('_ssh') || has(['raspberry', 'server', 'proxmox'])) {
    return DeviceType.server;
  }
  if (has(['apple'])) return DeviceType.phone;
  if (d.isSelf) return DeviceType.computer;
  return DeviceType.unknown;
}

final _nonWord = RegExp('[^a-z0-9]+');
final _wordCache = <String, RegExp>{};
RegExp _wordRe(String w) =>
    _wordCache[w] ??= RegExp('(^| )${RegExp.escape(w)}( |\$)');
