import 'dart:async';

/// Executes [action] in a zone that delegates microtasks and timers to
/// [Zone.root] while preserving the caller's [Zone.errorZone] so real isolate
/// work is never stalled by test `FakeAsync` queues and errors still propagate
/// back to the caller's zone.
T runInRealAsyncZone<T>(T Function() action) {
  final Zone current = Zone.current;
  if (identical(current, Zone.root)) {
    return action();
  }
  final Zone realAsyncZone = current.fork(
    specification: ZoneSpecification(
      scheduleMicrotask:
          (Zone self, ZoneDelegate parent, Zone zone, void Function() f) {
            Zone.root.scheduleMicrotask(() => zone.runGuarded(f));
          },
      createTimer:
          (
            Zone self,
            ZoneDelegate parent,
            Zone zone,
            Duration duration,
            void Function() f,
          ) {
            return Zone.root.createTimer(duration, () => zone.runGuarded(f));
          },
      createPeriodicTimer:
          (
            Zone self,
            ZoneDelegate parent,
            Zone zone,
            Duration period,
            void Function(Timer timer) f,
          ) {
            return Zone.root.createPeriodicTimer(
              period,
              (Timer timer) => zone.runGuarded(() => f(timer)),
            );
          },
    ),
  );
  return realAsyncZone.run<T>(action);
}
