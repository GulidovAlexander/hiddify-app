import 'package:flutter/material.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/proxy/speedtest/proxy_speed_test_notifier.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(this.proxy, {super.key, required this.selected, required this.onTap});

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final speedTest = ref.watch(proxySpeedTestProvider);

    return ListTile(
      // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        proxy.tagDisplay,
        overflow: TextOverflow.ellipsis,
        style: PlatformUtils.isWindows ? const TextStyle(fontFamily: FontFamily.emoji) : null,
      ),
      leading: IPCountryFlag(
        countryCode: proxy.ipinfo.countryCode,
        organization: proxy.ipinfo.org,
        size: 40,
        padding: const EdgeInsetsDirectional.only(end: 8),
      ),
      subtitle: Text.rich(
        TextSpan(
          text: proxy.type,
          children: [
            if (proxy.isGroup)
              TextSpan(
                text: ' (${proxy.groupSelectedTagDisplay.trim()})',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (proxy.urlTestDelay != 0)
            Text(
              ConnectionConst.isValidDelay(proxy.urlTestDelay) ? proxy.urlTestDelay.toString() : "×",
              style: TextStyle(color: delayColor(context, proxy.urlTestDelay)),
            ),

          if (speedTest.current == proxy.tag)
            const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2))
          else if (speedTest.results[proxy.tag] case (:final mbps, :final error))
            Tooltip(
              // tap on the result shows why the test failed
              message: error ?? "",
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 10),
              child: Text(
                mbps != null ? "${mbps.toStringAsFixed(mbps < 10 ? 1 : 0)} Mb/s" : "× Mb/s",
                style: theme.textTheme.bodySmall?.copyWith(color: speedColor(context, mbps)),
              ),
            ),
          if (proxy.download > 0) Text("⬩", style: Theme.of(context).textTheme.bodySmall),
        ],
      ),

      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer,
      onTap: onTap,
      onLongPress: () async => await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
      horizontalTitleGap: 4,
    );
  }

  Color speedColor(BuildContext context, double? speed) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (speed) {
      null => dark ? Colors.redAccent : Colors.red,
      < 5 => dark ? Colors.orange : Colors.deepOrangeAccent,
      _ => dark ? Colors.lightGreen : Colors.green,
    };
  }

  Color delayColor(BuildContext context, int delay) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return switch (delay) {
        < 800 => Colors.lightGreen,
        < 1500 => Colors.orange,
        _ => Colors.redAccent,
      };
    }
    return switch (delay) {
      < 800 => Colors.green,
      < 1500 => Colors.deepOrangeAccent,
      _ => Colors.red,
    };
  }
}
