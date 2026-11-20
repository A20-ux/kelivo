import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/incoming_call_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('IncomingCallService state machine', () {
    test('start creates a ringing session', () {
      final service = IncomingCallService.instance;
      service.hangUp();
      service.start(
        conversationId: 'conv-1',
        assistantId: 'asst-1',
        assistantName: 'Mira',
        avatar: null,
      );

      final session = service.session.value;
      expect(session, isNotNull);
      expect(session!.phase, CallPhase.ringing);
      expect(session.conversationId, 'conv-1');
      expect(session.assistantName, 'Mira');
      expect(service.hasActiveCall, isTrue);
    });

    test('answer moves ringing to active', () {
      final service = IncomingCallService.instance;
      service.hangUp();
      service.start(
        conversationId: 'conv-2',
        assistantId: 'asst-2',
        assistantName: 'Mira',
      );

      service.answer();
      expect(service.session.value!.phase, CallPhase.active);
      expect(service.hasActiveCall, isTrue);
    });

    test('answer twice does not leave active', () {
      final service = IncomingCallService.instance;
      service.answer();
      expect(service.session.value!.phase, CallPhase.active);
    });

    test('hangUp clears the session', () {
      final service = IncomingCallService.instance;
      service.hangUp();
      expect(service.session.value, isNull);
      expect(service.hasActiveCall, isFalse);
    });

    test('answer invokes onAnswered with the active session', () {
      final service = IncomingCallService.instance;
      service.hangUp();
      CallSession? captured;
      service.onAnswered = (session) => captured = session;
      service.start(
        conversationId: 'conv-3',
        assistantId: 'asst-3',
        assistantName: 'Mira',
      );

      service.answer();

      expect(captured, isNotNull);
      expect(captured!.phase, CallPhase.active);
      expect(captured!.conversationId, 'conv-3');
      service.onAnswered = null;
    });

    test('setOpeningLine backfills the spoken line', () {
      final service = IncomingCallService.instance;
      service.setOpeningLine('  Hey, you there.  ');
      expect(service.session.value!.openingLine, 'Hey, you there.');
    });

    test('answer records answeredAt; hangUp reports duration only if answered',
        () {
      final service = IncomingCallService.instance;
      service.hangUp();
      Duration? captured;
      service.onHangUp = (session, duration) => captured = duration;

      // 未接通直接挂断：时长为 null。
      service.start(
        conversationId: 'conv-4',
        assistantId: 'asst-4',
        assistantName: 'Mira',
      );
      service.hangUp();
      expect(captured, isNull);

      // 接通后挂断：记录接通时刻并给出非 null 时长。
      service.start(
        conversationId: 'conv-5',
        assistantId: 'asst-5',
        assistantName: 'Mira',
      );
      service.answer();
      expect(service.session.value!.answeredAt, isNotNull);
      service.hangUp();
      expect(captured, isNotNull);
      expect(service.lastCallDuration, isNotNull);
      service.onHangUp = null;
    });
  });
}
