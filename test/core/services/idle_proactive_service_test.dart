import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/idle_proactive_settings.dart';
import 'package:Kelivo/core/services/idle_proactive_service.dart';

void main() {
  final now = DateTime(2026, 11, 19, 12, 0, 0);
  final idle = const Duration(minutes: 30);

  IdleProactiveSettings settings({
    bool enabled = true,
    int callProbability = 30,
    bool allowMessage = true,
    bool allowCall = true,
  }) {
    return IdleProactiveSettings(
      enabled: enabled,
      idleMinutes: 30,
      callProbability: callProbability,
      allowMessage: allowMessage,
      allowCall: allowCall,
    );
  }

  IdleProactiveAction resolve(
    IdleProactiveSettings s,
    DateTime? lastActive,
    int random,
  ) {
    return IdleProactiveService.resolveAction(
      settings: s,
      now: now,
      lastActiveAt: lastActive,
      idleDuration: idle,
      random0to99: random,
    );
  }

  group('IdleProactiveService.resolveAction', () {
    test('disabled -> none', () {
      expect(
        resolve(settings(enabled: false), now.subtract(idle), 0),
        IdleProactiveAction.none,
      );
    });

    test('not idle yet -> none', () {
      expect(
        resolve(settings(), now.subtract(const Duration(minutes: 5)), 0),
        IdleProactiveAction.none,
      );
    });

    test('idle, call probability misses -> message', () {
      final last = now.subtract(const Duration(minutes: 40));
      expect(
        resolve(settings(callProbability: 30), last, 50),
        IdleProactiveAction.message,
      );
    });

    test('idle, call probability hits -> call', () {
      final last = now.subtract(const Duration(minutes: 40));
      expect(
        resolve(settings(callProbability: 30), last, 10),
        IdleProactiveAction.call,
      );
    });

    test('random equal to probability does not hit call', () {
      final last = now.subtract(const Duration(minutes: 40));
      expect(
        resolve(settings(callProbability: 30), last, 30),
        IdleProactiveAction.message,
      );
    });

    test('message disabled but call allowed -> call', () {
      final last = now.subtract(const Duration(minutes: 40));
      expect(
        resolve(settings(allowMessage: false, callProbability: 0), last, 99),
        IdleProactiveAction.call,
      );
    });

    test('both disabled -> none', () {
      final last = now.subtract(const Duration(minutes: 40));
      expect(
        resolve(settings(allowMessage: false, allowCall: false), last, 0),
        IdleProactiveAction.none,
      );
    });

    test('never interacted (null lastActive) does not trigger', () {
      expect(resolve(settings(), null, 0), IdleProactiveAction.none);
    });
  });
}
