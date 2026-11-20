import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/models/message_part.dart';
import 'package:Kelivo/core/services/tts/tts_audio_exporter.dart';
import 'package:Kelivo/core/services/tts/voice_message_builder.dart';

void main() {
  group('VoiceMessageBuilder', () {
    test('partFromResult maps export to an audio FilePart', () {
      const result = TtsExportResult(
        path: '/uploads/tts_20261120_103000.mp3',
        fileName: 'tts_20261120_103000.mp3',
        mime: 'audio/mpeg',
        bytes: 12345,
      );

      final part = VoiceMessageBuilder.partFromResult(result);

      expect(part, isA<FilePart>());
      expect(part.uri, result.path);
      expect(part.name, result.fileName);
      expect(part.mime, result.mime);
      expect(part.kind, 'file');
    });
  });
}
