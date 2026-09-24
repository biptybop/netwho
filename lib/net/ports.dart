import 'dart:async';
import 'dart:io';

import 'prober.dart';

/// Well-known ports checked by the port scanner, with plain-language names.
const commonPorts = <int, String>{
  20: 'FTP data', 21: 'FTP', 22: 'SSH', 23: 'Telnet', 25: 'SMTP (mail)',
  53: 'DNS', 67: 'DHCP', 80: 'Web (HTTP)', 81: 'Web (alt)', 88: 'Kerberos',
  110: 'POP3 (mail)', 111: 'RPC', 119: 'NNTP', 123: 'NTP (time)',
  135: 'Windows RPC', 139: 'Windows file sharing (NetBIOS)', 143: 'IMAP (mail)',
  161: 'SNMP', 389: 'LDAP', 443: 'Web (HTTPS)', 445: 'Windows file sharing (SMB)',
  465: 'SMTP over TLS', 515: 'Printer (LPD)', 548: 'Apple file sharing (AFP)',
  554: 'Video stream (RTSP)', 587: 'Mail submission', 631: 'Printer (IPP)',
  636: 'LDAP over TLS', 853: 'DNS over TLS', 873: 'rsync', 993: 'IMAP over TLS',
  995: 'POP3 over TLS', 1080: 'SOCKS proxy', 1194: 'OpenVPN', 1400: 'Sonos',
  1433: 'SQL Server', 1723: 'PPTP VPN', 1883: 'MQTT (smart home)',
  1900: 'UPnP', 2049: 'NFS file sharing', 2082: 'cPanel', 2375: 'Docker',
  2376: 'Docker (TLS)', 3000: 'Web app', 3074: 'Xbox Live', 3128: 'Proxy',
  3306: 'MySQL', 3389: 'Remote Desktop', 3478: 'STUN', 3689: 'iTunes sharing',
  4070: 'Spotify Connect', 4443: 'Web (alt HTTPS)', 5000: 'Web app / UPnP',
  5001: 'Synology DSM (HTTPS)', 5060: 'VoIP (SIP)', 5222: 'XMPP chat',
  5353: 'mDNS', 5357: 'Windows discovery', 5432: 'PostgreSQL',
  5555: 'Android debug (ADB)', 5900: 'Screen sharing (VNC)', 6379: 'Redis',
  6443: 'Kubernetes', 6466: 'Android TV remote', 6467: 'Android TV remote',
  7000: 'AirPlay', 7100: 'AirPlay', 7547: 'ISP remote management (TR-069)',
  8000: 'Web (alt)', 8008: 'Chromecast / web', 8009: 'Chromecast',
  8080: 'Web (alt)', 8081: 'Web (alt)', 8088: 'Web (alt)',
  8123: 'Home Assistant', 8200: 'DLNA media', 8443: 'Web (alt HTTPS)',
  8883: 'MQTT over TLS', 8888: 'Web (alt)', 9000: 'Web app', 9080: 'Web (alt)',
  9090: 'Web admin', 9100: 'Printer (raw)', 9200: 'Elasticsearch',
  9443: 'Web (alt HTTPS)', 10000: 'Webmin', 32400: 'Plex',
  49152: 'UPnP', 50000: 'Web app', 51820: 'WireGuard', 62078: 'Apple device sync',
};

String portName(int port) => commonPorts[port] ?? 'Unknown service';

/// True for ports that usually serve a web page the user could open.
bool isWebPort(int port) =>
    const {80, 81, 443, 3000, 4443, 5000, 5001, 8000, 8008, 8080, 8081, 8088,
      8123, 8443, 8888, 9000, 9080, 9090, 9443, 10000, 32400}
        .contains(port);

bool isTlsPort(int port) => const {443, 4443, 5001, 8443, 9443, 10000}.contains(port);

/// TCP connect scan of [ports] on [host]. Calls [onOpen] as ports are found
/// and [onProgress] with the fraction done.
Future<List<int>> scanPorts(
  String host,
  Iterable<int> ports, {
  Duration timeout = const Duration(milliseconds: 1200),
  int concurrency = 64,
  void Function(int port)? onOpen,
  void Function(double fraction)? onProgress,
  bool Function()? cancelled,
}) async {
  final list = ports.toList();
  final open = <int>[];
  var done = 0;
  await runPool<int>(list, concurrency, (port) async {
    try {
      final s = await Socket.connect(host, port, timeout: timeout);
      s.destroy();
      open.add(port);
      onOpen?.call(port);
    } catch (_) {}
    done++;
    onProgress?.call(done / list.length);
  }, cancelled: cancelled);
  open.sort();
  return open;
}
