import 'dart:math';
import 'package:audioplayers/audioplayers.dart';

class AudioManager {
  final AudioPlayer _player = AudioPlayer();
  final Random _rng = Random();

  // Placeholders para archivos. Colócalos en assets/sounds/
  // Asegúrate de declararlos en el pubspec.yaml bajo assets
  final String sndOn = 'saber_on.mp3';
  final String sndOff = 'saber_off.mp3';
  final String sndClash = 'clash.mp3';
  final List<String> swings = ['swing1.mp3', 'swing2.mp3', 'swing3.mp3'];

  Future<void> playOn() async {
    await _player.stop();
    await _player.play(AssetSource(sndOn));
  }

  Future<void> playOff() async {
    await _player.stop();
    await _player.play(AssetSource(sndOff));
  }

  Future<void> playClash() async {
    // Forzamos detener anterior para que el choque suene inmediato
    await _player.stop();
    await _player.play(AssetSource(sndClash));
  }

  Future<void> playSwing() async {
    if (_player.state == PlayerState.playing) {
      return; // No interrumpir si ya suena algo
    }
    final file = swings[_rng.nextInt(swings.length)];
    await _player.play(AssetSource(file));
  }
}
