import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../utils/label_text_parser.dart';

/// Reads a shipment label photo on the phone (Google ML Kit, offline, no
/// key) and extracts its National Addresses and shipment number.
class LabelOcrService {
  LabelOcrService._();

  static Future<LabelScan> readLabel(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return LabelTextParser.parse(result.text);
    } finally {
      await recognizer.close();
    }
  }
}
