import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/device.dart';

/// Remembered devices, grouped per network, in one JSON file in the app's
/// private data folder. Nothing leaves the device.
class DeviceStore {
  File? _file;
  Map<String, dynamic> _data = {'networks': <String, dynamic>{}};

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/devices.json');
      if (await _file!.exists()) {
        _data = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        _data['networks'] ??= <String, dynamic>{};
      }
    } catch (_) {
      // A corrupt file shouldn't stop the app; start fresh.
      _data = {'networks': <String, dynamic>{}};
    }
  }

  Map<String, dynamic> get _networks => _data['networks'] as Map<String, dynamic>;

  bool hasNetwork(String key) => _networks.containsKey(key);

  List<Device> devicesFor(String key) {
    final net = _networks[key] as Map<String, dynamic>?;
    final list = (net?['devices'] as List?) ?? const [];
    return [for (final d in list) Device.fromJson(d as Map<String, dynamic>)];
  }

  DateTime? lastScan(String key) {
    final v = (_networks[key] as Map<String, dynamic>?)?['lastScan'] as String?;
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<void> save(String key, List<Device> devices, {DateTime? scannedAt}) async {
    final prev = _networks[key] as Map<String, dynamic>?;
    _networks[key] = {
      'lastScan': scannedAt?.toIso8601String() ?? prev?['lastScan'],
      'devices': [for (final d in devices) d.toJson()],
    };
    await _write();
  }

  Future<void> forgetNetwork(String key) async {
    _networks.remove(key);
    await _write();
  }

  Future<void> _write() async {
    final f = _file;
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data));
    await tmp.rename(f.path);
  }
}
