import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:netwho/net/windows/iphlpapi.dart';

/// The Windows FFI structs must match the Win32 headers byte for byte.
/// These are the documented sizeof() values on 64-bit Windows; x64 and
/// arm64 Linux lay these types out the same way, so this also runs here.
void main() {
  test('Win32 struct sizes match 64-bit Windows', () {
    expect(sizeOf<IP_OPTION_INFORMATION>(), 16);
    expect(sizeOf<ICMP_ECHO_REPLY>(), 40);
    expect(sizeOf<IP_ADDR_STRING>(), 48);
    expect(sizeOf<IP_ADAPTER_INFO>(), 704);
    expect(sizeOf<MIB_IPNETROW>(), 24);
  });
}
