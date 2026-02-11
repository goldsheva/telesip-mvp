abstract class ReconnectDecision {
  const ReconnectDecision._();
}

class ReconnectDecisionSkip extends ReconnectDecision {
  const ReconnectDecisionSkip({
    this.disposed = false,
    this.inFlight = false,
    this.message,
  }) : super._();

  final bool disposed;
  final bool inFlight;
  final String? message;
}

class ReconnectDecisionAllow extends ReconnectDecision {
  const ReconnectDecisionAllow() : super._();
}
