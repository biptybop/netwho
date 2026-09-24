// Windows networking via iphlpapi.dll, called directly through FFI rather
// than parsing `ping`/`arp`/`ipconfig` output: that output is translated
// into the system language, and spawning console tools from a GUI app
// flashes windows. Only ever called when Platform.isWindows.
//
// Struct layouts follow the Win32 headers; test/win32_layout_test.dart pins
// their sizes to the documented x64 values.
// ignore_for_file: non_constant_identifier_names, camel_case_types
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ---------------------------------------------------------------- structs

final class IP_OPTION_INFORMATION extends Struct {
  @Uint8()
  external int ttl;
  @Uint8()
  external int tos;
  @Uint8()
  external int flags;
  @Uint8()
  external int optionsSize;
  external Pointer<Uint8> optionsData;
}

final class ICMP_ECHO_REPLY extends Struct {
  @Uint32()
  external int address;
  @Uint32()
  external int status;
  @Uint32()
  external int roundTripTime;
  @Uint16()
  external int dataSize;
  @Uint16()
  external int reserved;
  external Pointer<Void> data;
  external IP_OPTION_INFORMATION options;
}

final class IP_ADDR_STRING extends Struct {
  external Pointer<IP_ADDR_STRING> next;
  @Array(16)
  external Array<Uint8> ipAddress;
  @Array(16)
  external Array<Uint8> ipMask;
  @Uint32()
  external int context;
}

final class IP_ADAPTER_INFO extends Struct {
  external Pointer<IP_ADAPTER_INFO> next;
  @Uint32()
  external int comboIndex;
  @Array(260)
  external Array<Uint8> adapterName;
  @Array(132)
  external Array<Uint8> description;
  @Uint32()
  external int addressLength;
  @Array(8)
  external Array<Uint8> address;
  @Uint32()
  external int index;
  @Uint32()
  external int type;
  @Uint32()
  external int dhcpEnabled;
  external Pointer<IP_ADDR_STRING> currentIpAddress;
  external IP_ADDR_STRING ipAddressList;
  external IP_ADDR_STRING gatewayList;
  external IP_ADDR_STRING dhcpServer;
  @Int32()
  external int haveWins;
  external IP_ADDR_STRING primaryWinsServer;
  external IP_ADDR_STRING secondaryWinsServer;
  @Int64()
  external int leaseObtained;
  @Int64()
  external int leaseExpires;
}

final class MIB_IPNETROW extends Struct {
  @Uint32()
  external int index;
  @Uint32()
  external int physAddrLen;
  @Array(8)
  external Array<Uint8> physAddr;
  @Uint32()
  external int addr;
  @Uint32()
  external int type;
}

// -------------------------------------------------------------- constants

const _ipSuccess = 0;
const _ipTtlExpiredTransit = 11013;
const _errorBufferOverflow = 111;
const _errorInsufficientBuffer = 122;
const ifTypeWifi = 71; // IF_TYPE_IEEE80211
const _mibIpNetTypeInvalid = 2;

// -------------------------------------------------------------- bindings

typedef _IcmpCreateFileC = IntPtr Function();
typedef _IcmpCreateFileD = int Function();
typedef _IcmpCloseHandleC = Int32 Function(IntPtr);
typedef _IcmpCloseHandleD = int Function(int);
typedef _IcmpSendEchoC = Uint32 Function(IntPtr, Uint32, Pointer<Void>, Uint16,
    Pointer<IP_OPTION_INFORMATION>, Pointer<Void>, Uint32, Uint32);
typedef _IcmpSendEchoD = int Function(int, int, Pointer<Void>, int,
    Pointer<IP_OPTION_INFORMATION>, Pointer<Void>, int, int);
typedef _GetAdaptersInfoC = Uint32 Function(Pointer<IP_ADAPTER_INFO>, Pointer<Uint32>);
typedef _GetAdaptersInfoD = int Function(Pointer<IP_ADAPTER_INFO>, Pointer<Uint32>);
typedef _GetIpNetTableC = Uint32 Function(Pointer<Uint8>, Pointer<Uint32>, Int32);
typedef _GetIpNetTableD = int Function(Pointer<Uint8>, Pointer<Uint32>, int);

DynamicLibrary get _lib => DynamicLibrary.open('iphlpapi.dll');

// ------------------------------------------------------------ conversions

/// IPAddr is a DWORD holding the address in network byte order, so on a
/// little-endian machine a.b.c.d reads back as d<<24 | c<<16 | b<<8 | a.
int _toIpAddr(String ip) {
  final p = ip.split('.').map(int.parse).toList();
  return p[0] | (p[1] << 8) | (p[2] << 16) | (p[3] << 24);
}

String _fromIpAddr(int v) =>
    '${v & 0xFF}.${(v >> 8) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 24) & 0xFF}';

String _cString(Array<Uint8> a, int max) {
  final bytes = <int>[];
  for (var i = 0; i < max; i++) {
    final b = a[i];
    if (b == 0) break;
    bytes.add(b);
  }
  return String.fromCharCodes(bytes);
}

// ------------------------------------------------------------------- ping

/// Raw result: (status, replying address, round-trip ms) or null if the
/// call itself failed. Kept to plain values so it can cross isolates.
typedef RawEcho = (int status, String from, int ms);

/// One ICMP echo. IcmpSendEcho blocks, so it runs on a short-lived isolate
/// to keep the UI (and other probes) moving.
Future<RawEcho?> icmpEcho(String ip, {required int timeoutMs, int? ttl}) =>
    Isolate.run(() => _icmpEchoBlocking(ip, timeoutMs, ttl ?? 128));

RawEcho? _icmpEchoBlocking(String ip, int timeoutMs, int ttl) {
  final lib = _lib;
  final create = lib.lookupFunction<_IcmpCreateFileC, _IcmpCreateFileD>('IcmpCreateFile');
  final close = lib.lookupFunction<_IcmpCloseHandleC, _IcmpCloseHandleD>('IcmpCloseHandle');
  final send = lib.lookupFunction<_IcmpSendEchoC, _IcmpSendEchoD>('IcmpSendEcho');

  final handle = create();
  if (handle == -1 || handle == 0) return null;
  const dataSize = 32;
  final replySize = sizeOf<ICMP_ECHO_REPLY>() + dataSize + 8 + 256;
  final data = calloc<Uint8>(dataSize);
  final options = calloc<IP_OPTION_INFORMATION>();
  final reply = calloc<Uint8>(replySize);
  try {
    data.asTypedList(dataSize).setAll(0, Uint8List.fromList(List.generate(dataSize, (i) => 0x61 + i % 23)));
    options.ref.ttl = ttl;
    final r = reply.cast<ICMP_ECHO_REPLY>();
    r.ref.status = 0xFFFFFFFF; // sentinel: untouched buffer
    final count = send(handle, _toIpAddr(ip), data.cast(), dataSize, options,
        reply.cast(), replySize, timeoutMs);
    final status = r.ref.status;
    // A TTL-exceeded reply may come back with count 0; the buffer is still
    // filled in, so trust the status rather than the count.
    if (count == 0 && status != _ipTtlExpiredTransit) return null;
    return (status, _fromIpAddr(r.ref.address), r.ref.roundTripTime);
  } finally {
    close(handle);
    calloc
      ..free(data)
      ..free(options)
      ..free(reply);
  }
}

bool isEchoSuccess(RawEcho e, String target) => e.$1 == _ipSuccess && e.$2 == target;
bool isTtlExceeded(RawEcho e) => e.$1 == _ipTtlExpiredTransit;

// -------------------------------------------------------------- adapters

class WinAdapter {
  WinAdapter({
    required this.description,
    required this.type,
    required this.ip,
    required this.mask,
    this.gateway,
    this.mac,
  });

  final String description;
  final int type;
  final String ip;
  final String mask;
  final String? gateway;
  final String? mac;

  bool get isWifi => type == ifTypeWifi;
}

/// IPv4 adapters with an address, via GetAdaptersInfo.
List<WinAdapter> windowsAdapters() {
  final get = _lib.lookupFunction<_GetAdaptersInfoC, _GetAdaptersInfoD>('GetAdaptersInfo');
  final size = calloc<Uint32>();
  Pointer<IP_ADAPTER_INFO> buf = nullptr;
  try {
    var rc = get(nullptr, size);
    if (rc != _errorBufferOverflow && rc != 0) return const [];
    buf = calloc<Uint8>(size.value).cast();
    rc = get(buf, size);
    if (rc != 0) return const [];
    final out = <WinAdapter>[];
    for (var p = buf; p != nullptr; p = p.ref.next) {
      final a = p.ref;
      final ip = _cString(a.ipAddressList.ipAddress, 16);
      if (ip.isEmpty || ip == '0.0.0.0') continue;
      final gw = _cString(a.gatewayList.ipAddress, 16);
      String? mac;
      if (a.addressLength == 6) {
        mac = [for (var i = 0; i < 6; i++) a.address[i].toRadixString(16).padLeft(2, '0')].join(':');
      }
      out.add(WinAdapter(
        description: _cString(a.description, 132),
        type: a.type,
        ip: ip,
        mask: _cString(a.ipAddressList.ipMask, 16),
        gateway: (gw.isEmpty || gw == '0.0.0.0') ? null : gw,
        mac: mac,
      ));
    }
    return out;
  } finally {
    calloc.free(size);
    if (buf != nullptr) calloc.free(buf);
  }
}

// -------------------------------------------------------------- ARP table

/// IP → MAC from the Windows neighbour cache, via GetIpNetTable.
Map<String, String> windowsArpTable() {
  final get = _lib.lookupFunction<_GetIpNetTableC, _GetIpNetTableD>('GetIpNetTable');
  final size = calloc<Uint32>();
  Pointer<Uint8> buf = nullptr;
  try {
    var rc = get(nullptr, size, 0);
    if (rc != _errorInsufficientBuffer && rc != 0) return const {};
    if (size.value == 0) return const {};
    buf = calloc<Uint8>(size.value);
    rc = get(buf, size, 0);
    if (rc != 0) return const {};
    final count = buf.cast<Uint32>().value;
    final rows = Pointer<MIB_IPNETROW>.fromAddress(buf.address + 4);
    final out = <String, String>{};
    for (var i = 0; i < count; i++) {
      final row = rows[i];
      if (row.type == _mibIpNetTypeInvalid || row.physAddrLen != 6) continue;
      final bytes = [for (var j = 0; j < 6; j++) row.physAddr[j]];
      if (bytes.every((b) => b == 0) || bytes.every((b) => b == 0xFF)) continue;
      final ip = _fromIpAddr(row.addr);
      final first = row.addr & 0xFF;
      if (first >= 224 && first <= 239) continue; // multicast
      out[ip] = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    }
    return out;
  } finally {
    calloc.free(size);
    if (buf != nullptr) calloc.free(buf);
  }
}
