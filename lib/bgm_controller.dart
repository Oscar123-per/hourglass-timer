import 'package:audioplayers/audioplayers.dart';

class BgmController {
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> playBgm() async {
    // Setting looping is not needed if the version doesn't support it
    _audioPlayer.setReleaseMode(ReleaseMode.LOOP); // Ensures continuous playback
    await _audioPlayer.play('assets/bgm.mp3', isLocal: true);
  }

  void stopBgm() {
    _audioPlayer.stop();
  }
}
