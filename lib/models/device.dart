import '../net/ipv4.dart';
import 'device_type.dart';

/// One device on the network: what the latest scan saw plus what the user
/// told us about it (name, type, notes), which is remembered between scans.
class Device {
  Device({required this.ip, this.mac});

  String ip;
  String? mac;

  // Discovered.
  String? vendor;
  String? hostname;
  String? mdnsName;
  String? netbiosName;
  String? upnpName;
  String? model;
  String? upnpManufacturer;
  Set<String> services = {};
  Set<int> openPorts = {};
  double? latencyMs;
  bool isGateway = false;
  bool isSelf = false;
  bool online = false;

  // Remembered.
  DateTime? firstSeen;
  DateTime? lastSeen;
  String? customName;
  DeviceType? typeOverride;
  String? notes;

  /// Seen for the first time in the latest scan (and not on the very first
  /// scan of this network, when everything would be "new").
  bool isNew = false;

  /// Remembering key: MAC when we have one, IP otherwise.
  String get key => mac != null ? 'mac:$mac' : 'ip:$ip';

  String get displayName =>
      _first([customName, upnpName, mdnsName, netbiosName, _shortHost, model]) ??
      (isGateway ? 'Router' : null) ??
      vendor ??
      ip;

  String? get _shortHost {
    final h = hostname;
    if (h == null || h == ip) return null;
    // Drop router-appended domains like ".lan" or ".home" for display.
    final dot = h.indexOf('.');
    return dot > 0 ? h.substring(0, dot) : h;
  }

  DeviceType get type => typeOverride ?? guessDeviceType(this);

  int get sortKey => ipSortKey(ip);

  static String? _first(List<String?> values) {
    for (final v in values) {
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'ip': ip,
        if (mac != null) 'mac': mac,
        if (vendor != null) 'vendor': vendor,
        if (hostname != null) 'hostname': hostname,
        if (mdnsName != null) 'mdnsName': mdnsName,
        if (netbiosName != null) 'netbiosName': netbiosName,
        if (upnpName != null) 'upnpName': upnpName,
        if (model != null) 'model': model,
        if (upnpManufacturer != null) 'upnpManufacturer': upnpManufacturer,
        if (services.isNotEmpty) 'services': services.toList(),
        if (openPorts.isNotEmpty) 'openPorts': openPorts.toList(),
        'isGateway': isGateway,
        if (firstSeen != null) 'firstSeen': firstSeen!.toIso8601String(),
        if (lastSeen != null) 'lastSeen': lastSeen!.toIso8601String(),
        if (customName != null) 'customName': customName,
        if (typeOverride != null) 'type': typeOverride!.name,
        if (notes != null) 'notes': notes,
      };

  factory Device.fromJson(Map<String, dynamic> j) {
    DateTime? date(String k) => j[k] == null ? null : DateTime.tryParse(j[k] as String);
    return Device(ip: j['ip'] as String, mac: j['mac'] as String?)
      ..vendor = j['vendor'] as String?
      ..hostname = j['hostname'] as String?
      ..mdnsName = j['mdnsName'] as String?
      ..netbiosName = j['netbiosName'] as String?
      ..upnpName = j['upnpName'] as String?
      ..model = j['model'] as String?
      ..upnpManufacturer = j['upnpManufacturer'] as String?
      ..services = {...((j['services'] as List?) ?? const []).cast<String>()}
      ..openPorts = {...((j['openPorts'] as List?) ?? const []).cast<int>()}
      ..isGateway = j['isGateway'] as bool? ?? false
      ..firstSeen = date('firstSeen')
      ..lastSeen = date('lastSeen')
      ..customName = j['customName'] as String?
      ..typeOverride = DeviceType.values.asNameMap()[j['type']]
      ..notes = j['notes'] as String?;
  }

  /// Copies what the user set, plus older discovered details this scan
  /// didn't turn up again, from a remembered record.
  void inheritFrom(Device old) {
    firstSeen = old.firstSeen ?? firstSeen;
    customName = old.customName;
    typeOverride = old.typeOverride;
    notes = old.notes;
    mac ??= old.mac;
    vendor ??= old.vendor;
    hostname ??= old.hostname;
    mdnsName ??= old.mdnsName;
    netbiosName ??= old.netbiosName;
    upnpName ??= old.upnpName;
    model ??= old.model;
    upnpManufacturer ??= old.upnpManufacturer;
    if (services.isEmpty) services = old.services;
    if (openPorts.isEmpty) openPorts = old.openPorts;
  }
}
