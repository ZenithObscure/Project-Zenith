import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Client for Tailscale local API
/// Queries http://127.0.0.1:41641/localapi/v0/status to discover peers
class TailscaleClient {
  static const String _localApiBase = 'http://127.0.0.1:41641';
  static const Duration _timeout = Duration(seconds: 5);

  /// Check if Tailscale is running on this device
  Future<bool> isRunning() async {
    try {
      final response = await http
          .get(Uri.parse('$_localApiBase/localapi/v0/status'))
          .timeout(_timeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Get list of peers on the tailnet
  Future<List<TailscalePeer>> getPeers() async {
    try {
      final response = await http
          .get(Uri.parse('$_localApiBase/localapi/v0/status'))
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw TailscaleException('Status code: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final peersData = data['Peer'] as Map<String, dynamic>? ?? {};

      final peers = <TailscalePeer>[];
      for (final entry in peersData.entries) {
        final peerData = entry.value as Map<String, dynamic>;
        peers.add(TailscalePeer.fromJson(peerData));
      }

      return peers;
    } catch (e) {
      if (e is TailscaleException) rethrow;
      throw TailscaleException('Failed to get peers: $e');
    }
  }

  /// Get self info (this device)
  Future<TailscaleSelf?> getSelf() async {
    try {
      final response = await http
          .get(Uri.parse('$_localApiBase/localapi/v0/status'))
          .timeout(_timeout);

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final selfData = data['Self'] as Map<String, dynamic>?;
      if (selfData == null) return null;

      return TailscaleSelf.fromJson(selfData);
    } catch (_) {
      return null;
    }
  }
}

class TailscalePeer {
  final String id;
  final String hostname;
  final String? dnsName;
  final List<String> tailscaleIps;
  final bool online;
  final DateTime? lastSeen;

  TailscalePeer({
    required this.id,
    required this.hostname,
    this.dnsName,
    required this.tailscaleIps,
    required this.online,
    this.lastSeen,
  });

  factory TailscalePeer.fromJson(Map<String, dynamic> json) {
    final addresses = (json['TailscaleIPs'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return TailscalePeer(
      id: json['ID'] as String? ?? '',
      hostname: json['HostName'] as String? ?? 'Unknown',
      dnsName: json['DNSName'] as String?,
      tailscaleIps: addresses,
      online: json['Online'] as bool? ?? false,
      lastSeen: json['LastSeen'] != null
          ? DateTime.tryParse(json['LastSeen'] as String)
          : null,
    );
  }

  String get displayName => hostname.isNotEmpty ? hostname : dnsName ?? id;

  String? get primaryIp => tailscaleIps.isNotEmpty ? tailscaleIps.first : null;
}

class TailscaleSelf {
  final String id;
  final String hostname;
  final List<String> tailscaleIps;

  TailscaleSelf({
    required this.id,
    required this.hostname,
    required this.tailscaleIps,
  });

  factory TailscaleSelf.fromJson(Map<String, dynamic> json) {
    final addresses = (json['TailscaleIPs'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return TailscaleSelf(
      id: json['ID'] as String? ?? '',
      hostname: json['HostName'] as String? ?? Platform.localHostname,
      tailscaleIps: addresses,
    );
  }

  String? get primaryIp => tailscaleIps.isNotEmpty ? tailscaleIps.first : null;
}

class TailscaleException implements Exception {
  final String message;
  TailscaleException(this.message);

  @override
  String toString() => 'TailscaleException: $message';
}
