import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

// グローバルな AudioPlayer インスタンス（BGM用）
final AudioPlayer _bgmPlayer = AudioPlayer();
// グローバルな AudioPlayer インスタンス（リング音用）
final AudioPlayer _ringPlayer = AudioPlayer();

// アプリ全体の状態にアクセスするためのグローバルキー
final GlobalKey<_HourglassTimerAppState> hourglassKey = GlobalKey<_HourglassTimerAppState>();

/// セッション時間に応じた動画資産のパスを返す関数（通常フォーカスセッション用）
/// ※ 45分と60分は削除（選択可能な時間は5,10,15,20,30分）
String getVideoAssetForDuration(int duration) {
  switch (duration) {
    case 5:
      return "assets/5min.mp4";
    case 10:
      return "assets/10min.mp4";
    case 15:
      return "assets/15min.mp4";
    case 20:
      return "assets/20min.mp4";
    case 30:
      return "assets/30min.mp4";
    default:
      return "assets/hourglass.mp4";
  }
}

/// アプリのエントリーポイント
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  bool isDark = prefs.getBool('isDark') ?? false;
  await FocusLogManager.loadSessions();
  runApp(HourglassTimerApp(initialDarkMode: isDark));
}

/// -----------------------
/// アプリウィジェット（テーマサポート付き）
/// -----------------------
class HourglassTimerApp extends StatefulWidget {
  final bool initialDarkMode;
  HourglassTimerApp({required this.initialDarkMode}) : super(key: hourglassKey);

  @override
  _HourglassTimerAppState createState() => _HourglassTimerAppState();
}

class _HourglassTimerAppState extends State<HourglassTimerApp> {
  late bool _isDarkMode;
  bool get currentDarkMode => _isDarkMode;

  @override
  void initState() {
    super.initState();
    _isDarkMode = widget.initialDarkMode;
    // BGM は設定画面で管理するため、ここでは自動再生しません。
  }

  void toggleDarkMode(bool value) async {
    setState(() {
      _isDarkMode = value;
    });
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isDark', _isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '砂時計タイマーアプリ',
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
      ),
      home: HomeScreen(toggleDarkMode: toggleDarkMode, isDarkMode: _isDarkMode),
    );
  }
}

/// -----------------------
/// フォーカスログマネージャー（永続化付き）
/// -----------------------
class SessionLogEntry {
  final DateTime timestamp;
  final int durationSeconds;
  final String task;

  SessionLogEntry({
    required this.timestamp,
    required this.durationSeconds,
    required this.task,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'durationSeconds': durationSeconds,
    'task': task,
  };

  factory SessionLogEntry.fromJson(Map<String, dynamic> json) {
    return SessionLogEntry(
      timestamp: DateTime.parse(json['timestamp']),
      durationSeconds: json['durationSeconds'],
      task: json['task'],
    );
  }
}

class FocusLogManager {
  static List<SessionLogEntry> _sessions = [];

  static Future<void> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('sessions');
    if (data != null) {
      List<dynamic> jsonList = jsonDecode(data);
      _sessions = jsonList.map((jsonEntry) => SessionLogEntry.fromJson(jsonEntry)).toList();
    }
  }

  static Future<void> saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    String data = jsonEncode(_sessions.map((entry) => entry.toJson()).toList());
    await prefs.setString('sessions', data);
  }

  static Future<void> addSession(SessionLogEntry entry) async {
    _sessions.add(entry);
    await saveSessions();
  }

  static Duration totalFocusedTimeForPeriod(Duration period) {
    DateTime now = DateTime.now();
    DateTime cutoff = now.subtract(period);
    int totalSeconds = _sessions
        .where((entry) => entry.timestamp.isAfter(cutoff))
        .fold(0, (sum, entry) => sum + entry.durationSeconds);
    return Duration(seconds: totalSeconds);
  }

  static List<SessionLogEntry> get sessions => _sessions;
}

/// -----------------------
/// サウンド＆音楽ヘルパー
/// -----------------------
/// "bgm.mp3" をループ再生してBGMを再生
Future<void> playBackgroundMusic(String musicAsset) async {
  await _bgmPlayer.setReleaseMode(ReleaseMode.LOOP);
  await _bgmPlayer.play("assets/$musicAsset", isLocal: true);
  print("バックグラウンド音楽再生: $musicAsset");
}

/// BGM を停止
Future<void> stopBackgroundMusic() async {
  await _bgmPlayer.stop();
  print("バックグラウンド音楽停止");
}

/// タイマー終了時に "ring.mp3" のリング音を一度だけ再生
Future<void> playRingSound() async {
  await _ringPlayer.play("assets/ring.mp3", isLocal: true);
  print("リング音再生");
}

void playClickSound() {
  // クリック音再生ロジック（必要なら実装）
  print("クリック音再生");
}

/// -----------------------
/// フェードトランジションのためのルート作成
/// -----------------------
Route createFadeRoute(Widget page) {
  return PageRouteBuilder(
    transitionDuration: Duration(milliseconds: 400),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: animation,
        child: child,
      );
    },
  );
}

/// -----------------------
/// 共通の設定ボタンウィジェット
/// -----------------------
class SettingsButton extends StatelessWidget {
  const SettingsButton({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final state = hourglassKey.currentState;
    return IconButton(
      icon: Icon(Icons.settings),
      onPressed: () {
        playClickSound();
        Navigator.push(
          context,
          createFadeRoute(SettingsScreen(
            toggleDarkMode: state!.toggleDarkMode,
            isDarkMode: state.currentDarkMode,
          )),
        );
      },
    );
  }
}

/// -----------------------
/// ホーム画面
/// -----------------------
class HomeScreen extends StatelessWidget {
  // 選択可能な時間は 5, 10, 15, 20, 30 分
  final List<int> durations = [5, 10, 15, 20, 30];
  final Function(bool) toggleDarkMode;
  final bool isDarkMode;

  HomeScreen({required this.toggleDarkMode, required this.isDarkMode});

  final ButtonStyle largeButtonStyle = ElevatedButton.styleFrom(
    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 20),
    textStyle: TextStyle(fontSize: 20),
  );

  @override
  Widget build(BuildContext context) {
    // BGM は設定画面でのみ管理するので、ここでは再生／停止しません。
    return Scaffold(
      appBar: AppBar(
        title: Text("砂時計タイマー"),
        actions: [SettingsButton()],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.red, Colors.orange],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 通常のフォーカスセッション
                ...durations.map((duration) => Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ElevatedButton(
                    style: largeButtonStyle,
                    onPressed: () {
                      playClickSound();
                      Navigator.push(
                        context,
                        createFadeRoute(TaskInputScreen(duration: duration)),
                      );
                    },
                    child: Text("$duration 分間セッション"),
                  ),
                )),
                SizedBox(height: 20),
                // ポモドーロモード
                ElevatedButton(
                  style: largeButtonStyle,
                  onPressed: () {
                    playClickSound();
                    Navigator.push(
                      context,
                      createFadeRoute(PomodoroTaskInputScreen()),
                    );
                  },
                  child: Text("ポモドーロモード（２５分間）"),
                ),
                SizedBox(height: 20),
                // フォーカスログ
                ElevatedButton(
                  style: largeButtonStyle,
                  onPressed: () {
                    playClickSound();
                    Navigator.push(
                      context,
                      createFadeRoute(FocusLogScreen()),
                    );
                  },
                  child: Text("作業記録"),
                ),
                SizedBox(height: 20),
                // シンプルタイマー機能
                ElevatedButton(
                  style: largeButtonStyle,
                  onPressed: () {
                    playClickSound();
                    Navigator.push(
                      context,
                      createFadeRoute(CustomTimerInputScreen()),
                    );
                  },
                  child: Text("タイマー（時間自由）"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// -----------------------
/// 設定画面（ダークモード＆BGMオン/オフ）
/// -----------------------
class SettingsScreen extends StatefulWidget {
  final Function(bool) toggleDarkMode;
  final bool isDarkMode;

  SettingsScreen({required this.toggleDarkMode, required this.isDarkMode});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isBgmOn = true;

  @override
  void initState() {
    super.initState();
    _loadBgmPreference();
  }

  Future<void> _loadBgmPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isBgmOn = prefs.getBool('isBgmOn') ?? true;
    });
  }

  Future<void> _toggleBgm(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isBgmOn = value;
    });
    prefs.setBool('isBgmOn', _isBgmOn);
    // BGM のファイルは "bgm.mp3" です。オンなら再生、オフなら停止。
    if (_isBgmOn) {
      playBackgroundMusic("bgm.mp3");
    } else {
      stopBackgroundMusic();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("設定"),
        actions: [SettingsButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Text("ダークモード", style: TextStyle(fontSize: 20)),
                Switch(
                  value: widget.isDarkMode,
                  onChanged: (value) {
                    playClickSound();
                    widget.toggleDarkMode(value);
                  },
                ),
              ],
            ),
            Row(
              children: [
                Text("BGMオン/オフ", style: TextStyle(fontSize: 20)),
                Switch(
                  value: _isBgmOn,
                  onChanged: (value) {
                    playClickSound();
                    _toggleBgm(value);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// -----------------------
/// タスク入力画面（通常フォーカスセッション用）
/// -----------------------
class TaskInputScreen extends StatefulWidget {
  final int duration;

  TaskInputScreen({required this.duration});

  @override
  _TaskInputScreenState createState() => _TaskInputScreenState();
}

class _TaskInputScreenState extends State<TaskInputScreen> {
  final TextEditingController _taskController = TextEditingController();
  final ButtonStyle largeButtonStyle = ElevatedButton.styleFrom(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      textStyle: TextStyle(fontSize: 20));

  @override
  void initState() {
    super.initState();
    // タスク入力画面では、BGM は設定画面で管理するため、ここでは再生しません。
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  void _startSession() {
    playClickSound();
    String task = _taskController.text.trim();
    if (task.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("タスクを入力してください。"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      createFadeRoute(CountdownScreen(duration: widget.duration, task: task)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("タスク入力"),
        actions: [SettingsButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              "${widget.duration} 分間で何をしますか？",
              style: TextStyle(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            TextField(
              controller: _taskController,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: "タスク内容",
              ),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  style: largeButtonStyle,
                  onPressed: () {
                    playClickSound();
                    Navigator.pop(context);
                  },
                  child: Text("キャンセル"),
                ),
                ElevatedButton(
                  style: largeButtonStyle,
                  onPressed: _startSession,
                  child: Text("セッション開始"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

/// -----------------------
/// カウントダウン画面（3-2-1）
/// -----------------------
class CountdownScreen extends StatefulWidget {
  final int duration;
  final String task;

  CountdownScreen({required this.duration, required this.task});

  @override
  _CountdownScreenState createState() => _CountdownScreenState();
}

class _CountdownScreenState extends State<CountdownScreen> {
  int countdown = 3;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    // カウントダウン中は BGM は設定画面で管理するので、ここでは再生しません。
    timer = Timer.periodic(Duration(seconds: 1), (t) {
      setState(() {
        if (countdown > 1) {
          countdown--;
        } else {
          t.cancel();
          Navigator.pushReplacement(
            context,
            createFadeRoute(TimerScreen(duration: widget.duration, task: widget.task)),
          );
        }
      });
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 全画面のカウントダウン、右上に設定ボタンオーバーレイ
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Text(
              "$countdown",
              style: TextStyle(fontSize: 100, color: Colors.white),
            ),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              color: Colors.black45,
              child: SettingsButton(),
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------
/// タイマー画面（通常フォーカスセッション用）
/// -----------------------
class TimerScreen extends StatefulWidget {
  final int duration;
  final String task;

  TimerScreen({required this.duration, required this.task});

  @override
  _TimerScreenState createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  late int remainingSeconds;
  Timer? timer;
  bool isPaused = false;
  VideoPlayerController? _videoController;
  final ButtonStyle largeButtonStyle = ElevatedButton.styleFrom(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      textStyle: TextStyle(fontSize: 20));

  @override
  void initState() {
    super.initState();
    remainingSeconds = widget.duration * 60;
    // セッション時間に応じた動画資産を使用
    String videoAsset = getVideoAssetForDuration(widget.duration);
    _videoController = VideoPlayerController.asset(videoAsset)
      ..initialize().then((_) {
        setState(() {});
        _videoController!.setLooping(true);
        _videoController!.play();
      });
    startTimer();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    timer?.cancel();
    super.dispose();
  }

  void startTimer() {
    timer = Timer.periodic(Duration(seconds: 1), (t) {
      if (!isPaused) {
        setState(() {
          if (remainingSeconds > 0) {
            remainingSeconds--;
          } else {
            t.cancel();
            playRingSound(); // タイマー終了時にリング音を鳴らす
            _onTimerComplete();
          }
        });
      }
    });
  }

  void pauseTimer() {
    setState(() {
      isPaused = true;
    });
    _videoController?.pause();
  }

  void resumeTimer() {
    setState(() {
      isPaused = false;
    });
    _videoController?.play();
  }

  String get formattedTime {
    int minutes = remainingSeconds ~/ 60;
    int seconds = remainingSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  Future<bool> confirmExit() async {
    playClickSound();
    bool? exitConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("終了確認"),
        content: Text("このセッションを終了してもよろしいですか？"),
        actions: [
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop(false);
            },
            child: Text("いいえ"),
          ),
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop(true);
            },
            child: Text("はい"),
          ),
        ],
      ),
    );
    return exitConfirmed ?? false;
  }

  void _onTimerComplete() async {
    await FocusLogManager.addSession(SessionLogEntry(
      timestamp: DateTime.now(),
      durationSeconds: widget.duration * 60,
      task: widget.task,
    ));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text("おめでとうございます！"),
        content: Text("${widget.duration} 分間のセッションが完了しました。"),
        actions: [
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                createFadeRoute(TaskInputScreen(duration: widget.duration)),
              );
            },
            child: Text("新しいセッション"),
          ),
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop();
              Navigator.pushAndRemoveUntil(
                context,
                createFadeRoute(HomeScreen(
                  toggleDarkMode: (val) {},
                  isDarkMode: false,
                )),
                    (route) => false,
              );
            },
            child: Text("ホームメニュー"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("タスク: ${widget.task}", style: TextStyle(fontSize: 22)),
            Text("フォーカスタイマー", style: TextStyle(fontSize: 26)),
          ],
        ),
        actions: [SettingsButton()],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple, Colors.deepPurple],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: _videoController != null && _videoController!.value.isInitialized
                  ? AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              )
                  : Center(child: CircularProgressIndicator()),
            ),
          ),
          // 画面上部中央にタイマー表示
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                formattedTime,
                style: TextStyle(fontSize: 48, color: Colors.white),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: largeButtonStyle,
                    onPressed: () {
                      playClickSound();
                      if (isPaused) {
                        resumeTimer();
                      } else {
                        pauseTimer();
                      }
                    },
                    child: Text(isPaused ? "再開" : "一時停止"),
                  ),
                  ElevatedButton(
                    style: largeButtonStyle,
                    onPressed: () async {
                      if (await confirmExit()) {
                        timer?.cancel();
                        Navigator.pushAndRemoveUntil(
                          context,
                          createFadeRoute(HomeScreen(
                            toggleDarkMode: (val) {},
                            isDarkMode: false,
                          )),
                              (route) => false,
                        );
                      }
                    },
                    child: Text("終了"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------
/// ポモドーロモード：タスク入力画面
/// -----------------------
class PomodoroTaskInputScreen extends StatefulWidget {
  @override
  _PomodoroTaskInputScreenState createState() => _PomodoroTaskInputScreenState();
}

class _PomodoroTaskInputScreenState extends State<PomodoroTaskInputScreen> {
  final TextEditingController _taskController = TextEditingController();
  final ButtonStyle largeButtonStyle = ElevatedButton.styleFrom(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      textStyle: TextStyle(fontSize: 20));

  @override
  void initState() {
    super.initState();
    // ポモドーロモードでは、BGM は設定画面で管理するため、ここでは再生しません。
  }

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  void _startPomodoro() {
    playClickSound();
    String task = _taskController.text.trim();
    if (task.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("ポモドーロセッションのタスクを入力してください。"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      createFadeRoute(PomodoroTimerScreen(task: task)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("ポモドーロ - タスク入力"),
        actions: [SettingsButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              "このポモドーロで何に取り組みますか？",
              style: TextStyle(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            TextField(
              controller: _taskController,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: "タスク内容",
              ),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  style: largeButtonStyle,
                  onPressed: () {
                    playClickSound();
                    Navigator.pop(context);
                  },
                  child: Text("キャンセル"),
                ),
                ElevatedButton(
                  style: largeButtonStyle,
                  onPressed: _startPomodoro,
                  child: Text("ポモドーロ開始"),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

/// -----------------------
/// ポモドーロモード：タイマー画面
/// -----------------------
/// この画面では、25分のフォーカスセッションの後に5分の休憩が自動的に実行されます。
/// ポモドーロモードでは、背景動画として "assets/pom.mp4" を使用します。
class PomodoroTimerScreen extends StatefulWidget {
  final String task;
  PomodoroTimerScreen({required this.task});

  @override
  _PomodoroTimerScreenState createState() => _PomodoroTimerScreenState();
}

class _PomodoroTimerScreenState extends State<PomodoroTimerScreen> {
  late int remainingSeconds;
  Timer? timer;
  bool isPaused = false;
  bool inBreak = false; // false = フォーカスセッション, true = 休憩
  final int focusDuration = 25 * 60;
  final int breakDuration = 5 * 60;
  VideoPlayerController? _videoController;
  final ButtonStyle largeButtonStyle = ElevatedButton.styleFrom(
      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      textStyle: TextStyle(fontSize: 20));

  @override
  void initState() {
    super.initState();
    remainingSeconds = focusDuration;
    // ポモドーロモードでは、背景動画として "assets/pom.mp4" を使用
    _videoController = VideoPlayerController.asset("assets/pom.mp4")
      ..initialize().then((_) {
        setState(() {});
        _videoController!.setLooping(true);
        _videoController!.play();
      });
    startTimer();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    timer?.cancel();
    super.dispose();
  }

  void startTimer() {
    timer = Timer.periodic(Duration(seconds: 1), (t) {
      if (!isPaused) {
        setState(() {
          if (remainingSeconds > 0) {
            remainingSeconds--;
          } else {
            t.cancel();
            playRingSound(); // タイマー終了時にリング音を鳴らす
            _onPhaseComplete();
          }
        });
      }
    });
  }

  void pauseTimer() {
    setState(() {
      isPaused = true;
    });
    _videoController?.pause();
  }

  void resumeTimer() {
    setState(() {
      isPaused = false;
    });
    _videoController?.play();
  }

  String get formattedTime {
    int minutes = remainingSeconds ~/ 60;
    int seconds = remainingSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  Future<bool> confirmExit() async {
    playClickSound();
    bool? exitConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("終了確認"),
        content: Text("このポモドーロを終了してもよろしいですか？"),
        actions: [
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop(false);
            },
            child: Text("いいえ"),
          ),
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop(true);
            },
            child: Text("はい"),
          ),
        ],
      ),
    );
    return exitConfirmed ?? false;
  }

  void _onPhaseComplete() async {
    if (!inBreak) {
      await FocusLogManager.addSession(SessionLogEntry(
        timestamp: DateTime.now(),
        durationSeconds: focusDuration,
        task: widget.task,
      ));
      setState(() {
        inBreak = true;
        remainingSeconds = breakDuration;
      });
      startTimer();
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text("ポモドーロ完了！"),
          content: Text("フォーカスセッションと休憩が完了しました。\n「${widget.task}」に取り組みお疲れ様です！"),
          actions: [
            TextButton(
              onPressed: () {
                playClickSound();
                Navigator.of(context).pop();
                Navigator.pushReplacement(
                  context,
                  createFadeRoute(PomodoroTaskInputScreen()),
                );
              },
              child: Text("新しいポモドーロ"),
            ),
            TextButton(
              onPressed: () {
                playClickSound();
                Navigator.of(context).pop();
                Navigator.pushAndRemoveUntil(
                  context,
                  createFadeRoute(HomeScreen(
                    toggleDarkMode: (val) {},
                    isDarkMode: false,
                  )),
                      (route) => false,
                );
              },
              child: Text("ホームメニュー"),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    String phaseText = inBreak ? "休憩" : "フォーカス";
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("タスク: ${widget.task}", style: TextStyle(fontSize: 22)),
            Text("ポモドーロ $phaseText セッション", style: TextStyle(fontSize: 26)),
          ],
        ),
        actions: [SettingsButton()],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: inBreak
                      ? [Colors.green, Colors.lightGreen]
                      : [Colors.purple, Colors.deepPurple],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: _videoController != null && _videoController!.value.isInitialized
                  ? AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              )
                  : Center(child: CircularProgressIndicator()),
            ),
          ),
          // 画面上部中央にタイマー表示
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                formattedTime,
                style: TextStyle(fontSize: 48, color: Colors.white),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    style: largeButtonStyle,
                    onPressed: () {
                      playClickSound();
                      if (isPaused) {
                        resumeTimer();
                      } else {
                        pauseTimer();
                      }
                    },
                    child: Text(isPaused ? "再開" : "一時停止"),
                  ),
                  ElevatedButton(
                    style: largeButtonStyle,
                    onPressed: () async {
                      if (await confirmExit()) {
                        timer?.cancel();
                        Navigator.pushAndRemoveUntil(
                          context,
                          createFadeRoute(HomeScreen(
                            toggleDarkMode: (val) {},
                            isDarkMode: false,
                          )),
                              (route) => false,
                        );
                      }
                    },
                    child: Text("終了"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------
/// シンプルタイマー用：タイマー入力画面
/// -----------------------
class CustomTimerInputScreen extends StatefulWidget {
  @override
  _CustomTimerInputScreenState createState() => _CustomTimerInputScreenState();
}

class _CustomTimerInputScreenState extends State<CustomTimerInputScreen> {
  final TextEditingController _timeController = TextEditingController();

  void _startCustomTimer() {
    playClickSound();
    String input = _timeController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("タイマーの分数を入力してください。"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    int? minutes = int.tryParse(input);
    if (minutes == null || minutes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("有効な分数を入力してください。"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      createFadeRoute(CustomTimerScreen(minutes: minutes)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("タイマー時間入力"),
        actions: [SettingsButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              "タイマーの分数を入力してください。",
              style: TextStyle(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20),
            TextField(
              controller: _timeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: "分数",
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _startCustomTimer,
              child: Text("開始"),
            ),
          ],
        ),
      ),
    );
  }
}

/// -----------------------
/// シンプルタイマー用：タイマー画面（動画なし）
/// -----------------------
class CustomTimerScreen extends StatefulWidget {
  final int minutes;
  CustomTimerScreen({required this.minutes});

  @override
  _CustomTimerScreenState createState() => _CustomTimerScreenState();
}

class _CustomTimerScreenState extends State<CustomTimerScreen> {
  late int remainingSeconds;
  Timer? timer;
  bool isPaused = false;

  @override
  void initState() {
    super.initState();
    remainingSeconds = widget.minutes * 60;
    startTimer();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void startTimer() {
    timer = Timer.periodic(Duration(seconds: 1), (t) {
      if (!isPaused) {
        setState(() {
          if (remainingSeconds > 0) {
            remainingSeconds--;
          } else {
            t.cancel();
            playRingSound();
            _onTimerComplete();
          }
        });
      }
    });
  }

  void pauseTimer() {
    setState(() {
      isPaused = true;
    });
  }

  void resumeTimer() {
    setState(() {
      isPaused = false;
    });
  }

  String get formattedTime {
    int minutes = remainingSeconds ~/ 60;
    int seconds = remainingSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  Future<bool> confirmExit() async {
    playClickSound();
    bool? exitConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("終了確認"),
        content: Text("このタイマーを終了してもよろしいですか？"),
        actions: [
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop(false);
            },
            child: Text("いいえ"),
          ),
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop(true);
            },
            child: Text("はい"),
          ),
        ],
      ),
    );
    return exitConfirmed ?? false;
  }

  void _onTimerComplete() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text("おめでとうございます！"),
        content: Text("タイマーが終了しました。"),
        actions: [
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop();
              Navigator.pushReplacement(
                context,
                createFadeRoute(CustomTimerInputScreen()),
              );
            },
            child: Text("新しいタイマー"),
          ),
          TextButton(
            onPressed: () {
              playClickSound();
              Navigator.of(context).pop();
              Navigator.pushAndRemoveUntil(
                context,
                createFadeRoute(HomeScreen(
                  toggleDarkMode: (val) {},
                  isDarkMode: false,
                )),
                    (route) => false,
              );
            },
            child: Text("ホームメニュー"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("タイマー"),
        actions: [SettingsButton()],
      ),
      body: Stack(
        children: [
          // シンプルなグラデーション背景
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blueAccent, Colors.lightBlue],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          // 画面上部中央にタイマー表示
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                formattedTime,
                style: TextStyle(fontSize: 48, color: Colors.white),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      playClickSound();
                      if (isPaused) {
                        resumeTimer();
                      } else {
                        pauseTimer();
                      }
                    },
                    child: Text(isPaused ? "再開" : "一時停止"),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      if (await confirmExit()) {
                        timer?.cancel();
                        Navigator.pushAndRemoveUntil(
                          context,
                          createFadeRoute(HomeScreen(
                            toggleDarkMode: (val) {},
                            isDarkMode: false,
                          )),
                              (route) => false,
                        );
                      }
                    },
                    child: Text("終了"),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// -----------------------
/// フォーカスログ画面
/// -----------------------
class FocusLogScreen extends StatelessWidget {
  const FocusLogScreen({Key? key}) : super(key: key);

  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    int minutes = d.inMinutes;
    int seconds = d.inSeconds % 60;
    return "$minutes:${twoDigits(seconds)}";
  }

  @override
  Widget build(BuildContext context) {
    Duration dayDuration = FocusLogManager.totalFocusedTimeForPeriod(Duration(days: 1));
    Duration weekDuration = FocusLogManager.totalFocusedTimeForPeriod(Duration(days: 7));
    Duration monthDuration = FocusLogManager.totalFocusedTimeForPeriod(Duration(days: 30));
    final focusLogs = FocusLogManager.sessions;

    return Scaffold(
      appBar: AppBar(
        title: Text("作業記録"),
        actions: [SettingsButton()],
      ),
      body: focusLogs.isEmpty
          ? Center(
        child: Text(
          "作業記録がありません。",
          style: TextStyle(fontSize: 18),
        ),
      )
          : ListView.builder(
        itemCount: focusLogs.length,
        itemBuilder: (context, index) {
          final entry = focusLogs[index];
          String formattedDate =
              "${entry.timestamp.year}年${entry.timestamp.month}月${entry.timestamp.day}日 "
              "${entry.timestamp.hour}:${entry.timestamp.minute.toString().padLeft(2, '0')}";
          String duration = "${entry.durationSeconds ~/ 60}分${entry.durationSeconds % 60}秒";
          return ListTile(
            leading: Icon(Icons.access_time),
            title: Text("タスク: ${entry.task}"),
            subtitle: Text("日付: $formattedDate\n時間: $duration"),
          );
        },
      ),
    );
  }
}
