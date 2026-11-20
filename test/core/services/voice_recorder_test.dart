import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/services/voice_recorder_service.dart';

void main() {
  group('VoiceRecording', () {
    test('reports whole seconds for the bubble', () {
      const recording = VoiceRecording(
        path: '/tmp/voice_1.m4a',
        fileName: 'voice_1.m4a',
        mime: 'audio/mp4',
        duration: Duration(seconds: 7, milliseconds: 400),
      );
      expect(recording.durationSeconds, 7);
      expect(recording.mime, 'audio/mp4');
    });

    test('flags recordings shorter than the useful threshold', () {
      const tooShort = VoiceRecording(
        path: '/tmp/short.m4a',
        fileName: 'short.m4a',
        mime: 'audio/mp4',
        duration: Duration(milliseconds: 500),
      );
      const longEnough = VoiceRecording(
        path: '/tmp/long.m4a',
        fileName: 'long.m4a',
        mime: 'audio/mp4',
        duration: Duration(seconds: 2),
      );
      expect(tooShort.isTooShort, isTrue);
      expect(longEnough.isTooShort, isFalse);
    });
  });
}
