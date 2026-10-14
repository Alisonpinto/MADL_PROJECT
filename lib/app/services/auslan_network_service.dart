import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class PredictionResult {
  const PredictionResult({
    required this.isSuccess,
    this.label = '',
    this.confidence = 0.0,
    this.hasHand = false,
    this.errorMessage,
    this.latencyMs = 0.0,
    this.connectedUrl,
  });

  final bool isSuccess;
  final String label;
  final double confidence;
  final bool hasHand;
  final String? errorMessage;
  final double latencyMs;
  final String? connectedUrl;
}

class HealthCheckResult {
  const HealthCheckResult({
    required this.isReachable,
    this.url,
    this.errorMessage,
    this.details,
  });

  final bool isReachable;
  final String? url;
  final String? errorMessage;
  final Map<String, dynamic>? details;
}

class AuslanNetworkService {
  AuslanNetworkService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Uri? _lastWorkingUri;

  /// Returns candidate URIs to try based on environment and platform.
  List<Uri> getCandidateUris([String? customUrl]) {
    final configuredUrl = customUrl ?? dotenv.env['AUSLAN_SERVER_URL']?.trim() ?? '';
    final List<String> candidateStrings = [];

    if (configuredUrl.isNotEmpty) {
      candidateStrings.add(configuredUrl);
    }

    // Platform-specific smart defaults:
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 10.0.2.2 is the host loopback alias inside Android Emulator
      candidateStrings.add('http://10.0.2.2:8000/predict_auslan');
    }
    // Standard localhost defaults for desktop / physical LAN
    candidateStrings.add('http://127.0.0.1:8000/predict_auslan');
    candidateStrings.add('http://localhost:8000/predict_auslan');

    final List<Uri> uris = [];
    final Set<String> seen = {};

    // Prioritize last known working URI first if available
    if (_lastWorkingUri != null) {
      uris.add(_lastWorkingUri!);
      seen.add(_lastWorkingUri.toString());
    }

    for (final raw in candidateStrings) {
      final normalized = raw.startsWith('http://') || raw.startsWith('https://')
          ? raw
          : 'http://$raw';
      try {
        final parsed = Uri.parse(normalized);
        final fullUri = parsed.path.isEmpty || parsed.path == '/'
            ? parsed.replace(path: '/predict_auslan')
            : parsed;

        if (seen.add(fullUri.toString())) {
          uris.add(fullUri);
        }

        // If host was localhost or 127.0.0.1 and on Android, ensure 10.0.2.2 is also added
        if (defaultTargetPlatform == TargetPlatform.android &&
            (parsed.host == '127.0.0.1' || parsed.host == 'localhost')) {
          final emulatorUri = fullUri.replace(host: '10.0.2.2');
          if (seen.add(emulatorUri.toString())) {
            uris.add(emulatorUri);
          }
        }
      } catch (_) {}
    }

    return uris;
  }

  /// Sends a health check ping to discover which candidate server is alive.
  Future<HealthCheckResult> checkServerHealth([String? customUrl]) async {
    final candidates = getCandidateUris(customUrl);
    String lastError = 'No recognition server URLs configured.';

    for (final candidate in candidates) {
      final healthUri = candidate.replace(path: '/health');
      try {
        debugPrint('[AuslanNetwork] Pinging health: $healthUri');
        final response = await _client.get(healthUri).timeout(
          const Duration(milliseconds: 2500),
        );

        if (response.statusCode == 200) {
          _lastWorkingUri = candidate;
          Map<String, dynamic>? data;
          try {
            data = jsonDecode(response.body) as Map<String, dynamic>?;
          } catch (_) {}
          return HealthCheckResult(
            isReachable: true,
            url: candidate.toString(),
            details: data,
          );
        } else {
          lastError = 'Server returned HTTP ${response.statusCode} at $healthUri';
        }
      } on SocketException catch (e) {
        lastError = _formatSocketError(e, candidate);
      } on TimeoutException {
        lastError = 'Connection timed out at ${candidate.host}:${candidate.port}';
      } catch (e) {
        lastError = 'Error connecting to ${candidate.host}: $e';
      }
    }

    return HealthCheckResult(
      isReachable: false,
      errorMessage: lastError,
    );
  }

  /// Sends image frame bytes to the server for Auslan gesture prediction.
  Future<PredictionResult> sendFrame(
    Uint8List imageBytes, {
    String? customUrl,
  }) async {
    final candidateUris = getCandidateUris(customUrl);
    if (candidateUris.isEmpty) {
      return const PredictionResult(
        isSuccess: false,
        errorMessage: 'Server URL not configured. Set AUSLAN_SERVER_URL in .env',
      );
    }

    String lastError = '';

    for (final uri in candidateUris) {
      final stopwatch = Stopwatch()..start();
      try {
        final request = http.MultipartRequest('POST', uri);
        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: 'frame.jpg',
          ),
        );

        // 3.5s timeout prevents pipeline starvation or frame pileup
        final streamedResponse = await _client
            .send(request)
            .timeout(const Duration(milliseconds: 3500));

        final response = await http.Response.fromStream(streamedResponse);
        stopwatch.stop();

        if (response.statusCode != 200) {
          lastError = 'Server HTTP ${response.statusCode} from ${uri.host}:${uri.port}';
          debugPrint('[AuslanNetwork] $lastError: ${response.body}');
          continue;
        }

        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          lastError = 'Invalid JSON response from server';
          continue;
        }

        // Cache successful URI
        _lastWorkingUri = uri;

        final label = (decoded['label'] ?? '').toString().trim();
        final confidenceRaw = decoded['confidence'];
        final confidence = switch (confidenceRaw) {
          num() => confidenceRaw.toDouble(),
          String() => double.tryParse(confidenceRaw) ?? 0.0,
          _ => 0.0,
        };

        if (label.isEmpty || label == 'null') {
          return PredictionResult(
            isSuccess: true,
            label: '',
            confidence: 0,
            hasHand: false,
            latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
            connectedUrl: uri.toString(),
          );
        }

        return PredictionResult(
          isSuccess: true,
          label: label,
          confidence: confidence,
          hasHand: true,
          latencyMs: stopwatch.elapsedMilliseconds.toDouble(),
          connectedUrl: uri.toString(),
        );
      } on SocketException catch (e) {
        lastError = _formatSocketError(e, uri);
        debugPrint('[AuslanNetwork] SocketException on $uri: $lastError');
      } on TimeoutException {
        lastError = 'Request timed out (3.5s) on ${uri.host}:${uri.port}';
        debugPrint('[AuslanNetwork] Timeout on $uri');
      } on http.ClientException catch (e) {
        lastError = 'Client connection error: ${e.message}';
        debugPrint('[AuslanNetwork] ClientException on $uri: $e');
      } catch (e) {
        lastError = 'Connection failed: $e';
        debugPrint('[AuslanNetwork] Error on $uri: $e');
      }
    }

    return PredictionResult(
      isSuccess: false,
      errorMessage: lastError,
    );
  }

  String _formatSocketError(SocketException e, Uri uri) {
    final msg = e.message.toLowerCase();
    final osError = e.osError?.message.toLowerCase() ?? '';

    if (msg.contains('refused') || osError.contains('refused') || e.osError?.errorCode == 111 || e.osError?.errorCode == 10061) {
      return 'Connection refused at ${uri.host}:${uri.port}. Make sure uvicorn server is running.';
    } else if (msg.contains('cleartext') || osError.contains('cleartext')) {
      return 'Cleartext HTTP traffic blocked by Android security policy.';
    } else if (msg.contains('unreachable') || osError.contains('unreachable')) {
      return 'Network unreachable (${uri.host}). Check Wi-Fi connection.';
    } else if (msg.contains('failed host lookup')) {
      return 'Could not resolve host ${uri.host}. Check server IP address.';
    }
    return 'Cannot reach ${uri.host}:${uri.port} (${e.message})';
  }

  void dispose() {
    _client.close();
  }
}
