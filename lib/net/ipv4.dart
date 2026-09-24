/// Small IPv4 helpers. Addresses are held as unsigned 32-bit ints so ranges
/// and sorting are simple arithmetic.
library;

int? parseIpv4(String text) {
  final parts = text.trim().split('.');
  if (parts.length != 4) return null;
  var value = 0;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    value = (value << 8) | n;
  }
  return value;
}

String formatIpv4(int value) => [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ].join('.');

/// Sort key that orders dotted addresses numerically; non-IPv4 text sorts last.
int ipSortKey(String ip) => parseIpv4(ip) ?? 0xFFFFFFFF + 1;

int prefixFromMask(String mask) {
  final m = parseIpv4(mask);
  if (m == null) return 24;
  var bits = 0;
  for (var i = 31; i >= 0 && (m >> i) & 1 == 1; i--) {
    bits++;
  }
  return bits;
}

class Subnet {
  Subnet(int address, this.prefix)
      : network = address & _mask(prefix);

  final int network;
  final int prefix;

  static int _mask(int prefix) =>
      prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;

  int get broadcast => network | (~_mask(prefix) & 0xFFFFFFFF);
  int get size => 1 << (32 - prefix);

  bool contains(int address) => address & _mask(prefix) == network;

  /// Usable host addresses (skips network and broadcast on normal subnets).
  Iterable<int> get hosts sync* {
    if (prefix >= 31) {
      for (var a = network; a <= broadcast; a++) {
        yield a;
      }
      return;
    }
    for (var a = network + 1; a < broadcast; a++) {
      yield a;
    }
  }

  String get cidr => '${formatIpv4(network)}/$prefix';

  @override
  String toString() => cidr;
}
