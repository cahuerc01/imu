import 'dart:math';
import 'package:audioplayers/audioplayers.dart';

class AudioManager {
  final AudioPlayer _player = AudioPlayer();
  final Random _rng = Random();

  // Placeholders para archivos. Colócalos en assets/sounds/
  // Asegúrate de declararlos en el pubspec.yaml bajo assets
  final String sndOn = 'sounds/encendido_laser.mp3';
  final String sndOff = 'sounds/apagado_laser.mp3';
  final String sndClash = 'sounds/choque1.mp3';
  final List<String> swings = [
    'sounds/movimiento_laser1.mp3',
    'sounds/movimiento_laser2.mp3',
  ];

  Future<void> playOn() async {
    try {
      await _player.stop();
      await _player.play(AssetSource(sndOn));
    } catch (e) {
      // print("Error playing sound: $e");
    }
  }

  Future<void> playOff() async {
    try {
      await _player.stop();
      await _player.play(AssetSource(sndOff));
    } catch (e) {
      // print("Error playing sound: $e");
    }
  }

  Future<void> playClash() async {
    try {
      // Forzamos detener anterior para que el choque suene inmediato
      await _player.stop();
      await _player.play(AssetSource(sndClash));
    } catch (e) {
      // print("Error playing sound: $e");
    }
  }

  Future<void> playSwing() async {
    if (_player.state == PlayerState.playing) {
      return; // No interrumpir si ya suena algo
    }
    try {
      final file = swings[_rng.nextInt(swings.length)];
      await _player.play(AssetSource(file));
    } catch (e) {
      // print("Error playing sound: $e");
    }
  }
}
