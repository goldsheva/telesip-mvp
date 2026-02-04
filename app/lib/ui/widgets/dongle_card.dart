import 'package:flutter/material.dart';
import 'package:app/config/app_colors.dart';
import 'package:app/models/dongle.dart';

class DongleCard extends StatelessWidget {
  const DongleCard({super.key, required this.dongle});

  final Dongle dongle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final text2 = isDark ? AppColors.text2Dark : AppColors.text2;
    final border = isDark ? AppColors.borderDark : AppColors.border;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header
            Row(
              children: [
                Expanded(
                  child: Text(
                    dongle.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () {},
                  icon: Icon(Icons.settings, color: text2),
                ),
              ],
            ),
            const SizedBox(height: 6),

            Text(
              dongle.phone,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyMedium?.copyWith(
                color: text2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: _StatusPill(
                    label: dongle.isOnline ? 'Online' : 'Offline',
                    color: dongle.isOnline
                        ? AppColors.success
                        : AppColors.warning,
                    border: border,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatusPill(
                    label: dongle.isEnabled ? 'Hotspot on' : 'Hotspot off',
                    color: dongle.isEnabled
                        ? AppColors.success
                        : AppColors.danger,
                    border: border,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _KV(label: 'Dongle ID', value: '${dongle.id}', text2: text2),
            const SizedBox(height: 8),

            if (dongle.isOnline && dongle.isEnabled) ...[
              _KV(
                label: 'Wi-Fi Name',
                value: dongle.wifiName ?? '—',
                text2: text2,
              ),
              const SizedBox(height: 8),
              _KV(
                label: 'Wi-Fi Password',
                value: dongle.wifiPassword ?? '—',
                text2: text2,
              ),
            ] else if (!dongle.isOnline) ...[
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Please connect the dongle to the network',
                      style: t.bodyMedium?.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.border,
  });

  final String label;
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Container(
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: t.bodyMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV({required this.label, required this.value, required this.text2});

  final String label;
  final String value;
  final Color text2;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(label, style: t.bodyMedium?.copyWith(color: text2)),
        ),
        Text(value, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
