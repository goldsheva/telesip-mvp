import 'package:app/features/calls/call_watchdog.dart';
import 'package:app/services/audio_route_types.dart';

enum CallStatus { dialing, ringing, connected, ended }

class CallInfo {
  const CallInfo({
    required this.id,
    required this.destination,
    required this.status,
    required this.createdAt,
    this.connectedAt,
    this.endedAt,
    this.timeline = const [],
    this.errorMessage,
    this.dongleId,
  });

  final String id;
  final String destination;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final List<String> timeline;
  final String? errorMessage;
  final int? dongleId;

  CallInfo copyWith({
    String? destination,
    CallStatus? status,
    DateTime? connectedAt,
    DateTime? endedAt,
    List<String>? timeline,
    String? errorMessage,
    int? dongleId,
  }) {
    return CallInfo(
      id: id,
      destination: destination ?? this.destination,
      status: status ?? this.status,
      createdAt: createdAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      timeline: timeline ?? this.timeline,
      errorMessage: errorMessage ?? this.errorMessage,
      dongleId: dongleId ?? this.dongleId,
    );
  }
}

class CallState {
  const CallState({
    required this.calls,
    this.activeCallId,
    this.errorMessage,
    required this.watchdogState,
    required this.isRegistered,
    required this.isMuted,
    required this.audioRoute,
    required this.availableAudioRoutes,
  });

  factory CallState.initial() => CallState(
    calls: {},
    errorMessage: null,
    watchdogState: CallWatchdogState.ok(),
    isRegistered: false,
    isMuted: false,
    audioRoute: AudioRoute.systemDefault,
    availableAudioRoutes: const {AudioRoute.systemDefault},
  );

  final Map<String, CallInfo> calls;
  final String? activeCallId;
  final String? errorMessage;
  final CallWatchdogState watchdogState;
  final bool isRegistered;
  final bool isMuted;
  final AudioRoute audioRoute;
  final Set<AudioRoute> availableAudioRoutes;

  CallInfo? get activeCall => activeCallId != null ? calls[activeCallId] : null;

  List<CallInfo> get history =>
      calls.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  CallState copyWith({
    Map<String, CallInfo>? calls,
    String? activeCallId,
    String? errorMessage,
    CallWatchdogState? watchdogState,
    bool? isRegistered,
    bool? isMuted,
    AudioRoute? audioRoute,
    Set<AudioRoute>? availableAudioRoutes,
  }) {
    return CallState(
      calls: calls ?? this.calls,
      activeCallId: activeCallId ?? this.activeCallId,
      errorMessage: errorMessage ?? this.errorMessage,
      watchdogState: watchdogState ?? this.watchdogState,
      isRegistered: isRegistered ?? this.isRegistered,
      isMuted: isMuted ?? this.isMuted,
      audioRoute: audioRoute ?? this.audioRoute,
      availableAudioRoutes: availableAudioRoutes ?? this.availableAudioRoutes,
    );
  }
}
