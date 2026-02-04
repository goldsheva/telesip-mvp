/// Shared definitions that describe the available audio routes.
enum AudioRoute { earpiece, speaker, bluetooth, wiredHeadset, systemDefault }

/// Lightweight carrier for the current route state that is transferred
/// over the method/event channels.
class AudioRouteInfo {
  final AudioRoute current;
  final List<AudioRoute> available;
  final bool bluetoothConnected;
  final bool wiredConnected;

  const AudioRouteInfo({
    required this.current,
    required this.available,
    required this.bluetoothConnected,
    required this.wiredConnected,
  });

  factory AudioRouteInfo.fromMap(Map<Object?, Object?> map) {
    final currentRoute = _routeFromValue(map['current']);
    final availableRoutes =
        (map['available'] as List<Object?>?)
            ?.map(_routeFromValue)
            .whereType<AudioRoute>()
            .toList() ??
        [];
    final bluetooth = map['bluetoothConnected'] as bool? ?? false;
    final wired = map['wiredConnected'] as bool? ?? false;

    return AudioRouteInfo(
      current: currentRoute ?? AudioRoute.systemDefault,
      available: availableRoutes.isEmpty
          ? const [AudioRoute.systemDefault]
          : availableRoutes,
      bluetoothConnected: bluetooth,
      wiredConnected: wired,
    );
  }

  static AudioRoute? _routeFromValue(Object? value) {
    if (value is AudioRoute) return value;
    if (value is String) {
      return AudioRoute.values.firstWhere(
        (route) => route.name == value,
        orElse: () => AudioRoute.systemDefault,
      );
    }
    return null;
  }

  Map<String, Object?> toMap() => {
    'current': current.name,
    'available': available.map((route) => route.name).toList(),
    'bluetoothConnected': bluetoothConnected,
    'wiredConnected': wiredConnected,
  };
}
