import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

final _log = Logger('limits');

const String forwardedForHeader = 'x-forwarded-for';

const String unknownClientIp = '-';

class IpRange {
  IpRange._(this._network, this.prefixLength, this.text);

  final Uint8List _network;
  final int prefixLength;
  final String text;

  static IpRange? tryParse(String raw) {
    final value = raw.trim();
    final slash = value.indexOf('/');
    final address = InternetAddress.tryParse(
      slash < 0 ? value : value.substring(0, slash),
    );
    if (address == null) return null;
    final bytes = normalizeAddress(address).rawAddress;
    final bits = bytes.length * 8;
    final prefix = slash < 0 ? bits : int.tryParse(value.substring(slash + 1));
    if (prefix == null || prefix < 0 || prefix > bits) return null;
    return IpRange._(_masked(bytes, prefix), prefix, value);
  }

  bool contains(InternetAddress address) {
    final bytes = normalizeAddress(address).rawAddress;
    if (bytes.length != _network.length) return false;
    final masked = _masked(bytes, prefixLength);
    for (var i = 0; i < masked.length; i++) {
      if (masked[i] != _network[i]) return false;
    }
    return true;
  }

  static Uint8List _masked(Uint8List bytes, int prefix) {
    final result = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      final keep = (prefix - i * 8).clamp(0, 8);
      result[i] = bytes[i] & (0xff << (8 - keep)) & 0xff;
    }
    return result;
  }
}

InternetAddress normalizeAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (address.type != InternetAddressType.IPv6 || bytes.length != 16) {
    return address;
  }
  for (var i = 0; i < 10; i++) {
    if (bytes[i] != 0) return address;
  }
  if (bytes[10] != 0xff || bytes[11] != 0xff) return address;
  return InternetAddress.fromRawAddress(
    Uint8List.fromList(bytes.sublist(12)),
    type: InternetAddressType.IPv4,
  );
}

class TrustedProxies {
  const TrustedProxies(this.ranges);

  static const TrustedProxies none = TrustedProxies([]);

  final List<IpRange> ranges;

  bool get isEmpty => ranges.isEmpty;

  static TrustedProxies parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return none;
    final ranges = <IpRange>[];
    final invalid = <String>[];
    for (final entry in raw.split(RegExp(r'[,\s]+'))) {
      if (entry.isEmpty) continue;
      final range = IpRange.tryParse(entry);
      if (range == null) {
        invalid.add('"$entry"');
      } else {
        ranges.add(range);
      }
    }
    if (invalid.isNotEmpty) {
      throw FormatException(
        'invalid entries ${invalid.join(', ')} '
        '(expected IP or CIDR like 172.16.0.0/12, comma-separated)',
      );
    }
    return TrustedProxies(List.unmodifiable(ranges));
  }

  bool contains(InternetAddress address) =>
      ranges.any((range) => range.contains(address));

  String describe() =>
      isEmpty ? 'none' : ranges.map((range) => range.text).join(',');
}

String clientIp(Request request, TrustedProxies trusted) {
  final info = request.context['shelf.io.connection_info'];
  if (info is! HttpConnectionInfo) return unknownClientIp;
  final peer = normalizeAddress(info.remoteAddress);
  final header = request.headers[forwardedForHeader];
  if (header == null || header.trim().isEmpty) return peer.address;
  if (!trusted.contains(peer)) {
    _log.fine(
      'X-Forwarded-For ignored: peer ${peer.address} is not a trusted proxy '
      '(trustedProxies=${trusted.describe()})',
    );
    return peer.address;
  }

  var candidate = peer;
  final hops = header.split(',').map((hop) => hop.trim()).toList();
  for (var i = hops.length - 1; i >= 0; i--) {
    if (!trusted.contains(candidate)) break;
    final hop = _parseHop(hops[i]);
    if (hop == null) {
      _log.fine(
        'X-Forwarded-For hop is not an IP (length=${hops[i].length}) '
        '→ client ip=${candidate.address}',
      );
      break;
    }
    candidate = hop;
  }
  _log.fine(
    'client ip from X-Forwarded-For peer=${peer.address} (trusted) '
    'hops=${hops.length} ip=${candidate.address}',
  );
  return candidate.address;
}

InternetAddress? _parseHop(String hop) {
  var value = hop;
  if (value.startsWith('[')) {
    final end = value.indexOf(']');
    if (end < 0) return null;
    value = value.substring(1, end);
  } else if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}:\d+$').hasMatch(value)) {
    value = value.substring(0, value.indexOf(':'));
  }
  final address = InternetAddress.tryParse(value);
  return address == null ? null : normalizeAddress(address);
}
