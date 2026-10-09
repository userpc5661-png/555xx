import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Loud, distinct sounds with vibration for the scanner and for deliveries,
/// so the driver hears the result without looking at the screen.
class AlertSounds {
  AlertSounds._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _configured = false;

  static Future<void> _play(String asset) async {
    try {
      if (!_configured) {
        _configured = true;
        // Play over the driver's music or navigation without stopping it,
        // and on iOS even when the silent switch is on.
        await _player.setAudioContext(AudioContext(
          android: const AudioContextAndroid(
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ));
        await _player.setVolume(1.0);
      }
      await _player.stop();
      await _player.play(AssetSource(asset));
    } catch (_) {
      // A sound must never break a scan or a delivery.
    }
  }

  /// A shipment was scanned and accepted.
  static void success() {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(_play('sounds/scan_success.wav'));
  }

  /// A wrong shipment or a failed scan.
  static void error() {
    unawaited(HapticFeedback.vibrate());
    unawaited(_play('sounds/scan_error.wav'));
  }

  /// A delivery was accepted by SLS.
  static void delivered() {
    unawaited(HapticFeedback.heavyImpact());
    unawaited(_play('sounds/delivered.wav'));
  }
}
