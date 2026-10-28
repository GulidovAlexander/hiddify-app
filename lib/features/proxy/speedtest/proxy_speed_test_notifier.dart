import 'dart:async';
import 'dart:io';

import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Result of one proxy: download speed in Mbit/s, or the reason the test failed.
typedef SpeedResult = ({double? mbps, String? error});

class ProxySpeedTestState {
  const ProxySpeedTestState({this.running = false, this.current, this.done = 0, this.total = 0, this.results = const {}});

  final bool running;

  /// The proxy under test now.
  final String? current;
  final int done;
  final int total;

  /// Proxy tag to its result. A tag that was not tested yet is absent.
  final Map<String, SpeedResult> results;

  ProxySpeedTestState copyWith({
    bool? running,
    String? Function()? current,
    int? done,
    int? total,
    Map<String, SpeedResult>? results,
  }) => ProxySpeedTestState(
    running: running ?? this.running,
    current: current != null ? current() : this.current,
    done: done ?? this.done,
    total: total ?? this.total,
    results: results ?? this.results,
  );
}

final proxySpeedTestProvider = NotifierProvider<ProxySpeedTestNotifier, ProxySpeedTestState>(
  ProxySpeedTestNotifier.new,
);

/// Tests the download speed of each proxy of a group, one after another.
///
/// For each proxy it selects the proxy in the group, then downloads a file through the local mixed
/// inbound. At the end it selects the proxy that was active before the test.
class ProxySpeedTestNotifier extends Notifier<ProxySpeedTestState> with AppLogger {
  static const _url = 'https://speed.cloudflare.com/__down?bytes=50000000';
  static const _connectTimeout = Duration(seconds: 10);

  /// How long one proxy downloads. The download stops earlier when the file ends.
  static const _measureTime = Duration(seconds: 8);

  bool _stop = false;
  HttpClient? _client;

  @override
  ProxySpeedTestState build() => const ProxySpeedTestState();

  void stop() {
    _stop = true;
    _client?.close(force: true);
  }

  Future<void> run(OutboundGroup group) async {
    if (state.running) return;
    final tags = group.items.where((e) => !e.isGroup).map((e) => e.tag).toList();
    if (tags.isEmpty) return;
    final original = group.selected;
    final repository = ref.read(proxyRepositoryProvider);
    _stop = false;
    state = ProxySpeedTestState(running: true, total: tags.length);
    try {
      for (final tag in tags) {
        if (_stop) break;
        state = state.copyWith(current: () => tag);
        final selected = await repository.selectProxy(group.tag, tag).run();
        var speed = selected.fold<SpeedResult>(
          (failure) => (mbps: null, error: "select: $failure"),
          (_) => (mbps: null, error: null),
        );
        if (speed.error == null) {
          // A new outbound opens its connection on the first request; one retry covers a slow start.
          for (var attempt = 0; attempt < 2 && !_stop; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            speed = await _measure();
            if (speed.mbps != null) break;
          }
        }
        if (_stop) break;
        loggy.debug("speed of [$tag]: $speed");
        state = state.copyWith(done: state.done + 1, results: {...state.results, tag: speed});
      }
    } finally {
      if (original.isNotEmpty) await repository.selectProxy(group.tag, original).run();
      state = state.copyWith(running: false, current: () => null);
    }
  }

  /// Downloads through the local proxy for [_measureTime] and returns the speed in Mbit/s.
  ///
  /// A new HTTP client for each proxy: a kept-alive connection would still go through the
  /// proxy of the previous test.
  Future<SpeedResult> _measure() async {
    final port = ref.read(ConfigOptions.mixedPort);
    final client = HttpClient()
      ..connectionTimeout = _connectTimeout
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$port');
    _client = client;
    try {
      final request = await client.getUrl(Uri.parse(_url)).timeout(_connectTimeout);
      final response = await request.close().timeout(_connectTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return (mbps: null, error: "HTTP ${response.statusCode}");
      }
      // The time starts at the first byte, so the delay of the proxy does not lower the speed.
      final watch = Stopwatch();
      var bytes = 0;
      await for (final chunk in response.timeout(_connectTimeout)) {
        if (!watch.isRunning) watch.start();
        bytes += chunk.length;
        if (watch.elapsed >= _measureTime || _stop) break;
      }
      final seconds = watch.elapsedMicroseconds / Duration.microsecondsPerSecond;
      if (bytes == 0 || seconds == 0) return (mbps: null, error: "no data");
      return (mbps: bytes * 8 / seconds / 1000000, error: null);
    } catch (e) {
      loggy.debug("speed test failed", e);
      return (mbps: null, error: e.toString());
    } finally {
      _client = null;
      client.close(force: true);
    }
  }
}
