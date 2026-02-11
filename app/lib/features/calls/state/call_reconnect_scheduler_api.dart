abstract class CallReconnectSchedulerApi {
  void cancel();
  Duration get currentDelay;
  int get currentAttemptNumber;
  int get backoffIndex;
  void schedule({required String reason, required void Function() onFire});
}
