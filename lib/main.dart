import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // lets us buzz the phone and copy text
import 'package:flutter_tts/flutter_tts.dart'; // makes the phone talk
import 'package:url_launcher/url_launcher.dart'; // opens the phone dialer

void main() => runApp(const AgniPulseApp());

class AgniPulseApp extends StatelessWidget {
  const AgniPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgniPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------- The emergencies and their steps ----------

class Emergency {
  final String name;
  final IconData icon;
  final Color color;
  final List<String> steps;
  const Emergency(this.name, this.icon, this.color, this.steps);
}

const List<Emergency> emergencies = [
  Emergency('Choking', Icons.warning_amber_rounded, Color(0xFFFFB300), [
    'Ask: "Can you talk?" If NO, tell someone to CALL 911.',
    'Lean them forward. Hit their back between the shoulder blades 5 times. Hit hard.',
    'Stand behind them. Make a fist just above the belly button. Pull IN and UP 5 times.',
    'Repeat 5 back hits, then 5 belly pulls, until the object comes out.',
    'If they pass out, lay them down and start CPR.',
  ]),
  Emergency('Bleeding', Icons.water_drop, Color(0xFFFF5252), [
    'CALL 911 if the blood is spurting or will not stop.',
    'Put a clean cloth on the cut. Press down HARD with both hands.',
    'Do not peek. If blood soaks through, add more cloth on top. Keep pressing.',
    'Keep pressing until help arrives.',
  ]),
  Emergency('Cardiac Arrest', Icons.favorite, Color(0xFFFF4081), [
    'Tap them and shout. No answer and no normal breathing? CALL 911 now.',
    'Send someone to get an AED (a heart-shock machine).',
    'Push HARD and FAST in the middle of the chest, about 2 inches deep. Press the CPR BEAT button and push with the beat.',
    'When the AED comes, turn it on and do what its voice says.',
    'Do not stop until help takes over.',
  ]),
  Emergency('Burns', Icons.local_fire_department, Color(0xFFFF9100), [
    'Move away from the fire or heat.',
    'Run cool (not ice cold) water on the burn for 10 minutes or more.',
    'Cover it loosely with a clean cloth. No butter. No ice.',
    'CALL 911 if the burn is big, on the face or hands, or very deep.',
  ]),
  Emergency('Allergic Reaction', Icons.healing, Color(0xFF69F0AE), [
    'Swollen face or lips, or hard to breathe? CALL 911 now.',
    'If they have an epinephrine pen, push it into the side of the thigh.',
    'Lay them flat and lift their legs. If breathing is hard, let them sit up.',
    'Stay with them until help comes.',
  ]),
  // No steps here on purpose: opening this one starts the Pace Practice trainer.
  Emergency('CPR Pace Practice', Icons.speed, Color(0xFF40C4FF), []),
];

// ---------- Makes a short "beep" sound in memory (no sound file needed) ----------

Uint8List makeBeep() {
  const rate = 22050;
  const n = rate * 80 ~/ 1000; // 80 milliseconds long
  final data = ByteData(44 + n * 2);
  void text(int at, String t) {
    for (var i = 0; i < t.length; i++) {
      data.setUint8(at + i, t.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    final fade = 1 - i / n;
    final v = (sin(2 * pi * 880 * i / rate) * 20000 * fade).toInt();
    data.setInt16(44 + i * 2, v, Endian.little);
  }
  return data.buffer.asUint8List();
}

// ---------- The main screen ----------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 60,000 milliseconds in a minute / 100 beats = 600.
  // Want 110 beats a minute instead? Change 600 to 545.
  static const int beatMs = 600;

  bool stress = false;
  Emergency? current;
  int step = 0;
  bool beating = false;
  bool pulse = false;
  Timer? _timer;
  final AudioPlayer _player = AudioPlayer();
  final Uint8List _beep = makeBeep();
  final List<String> _log = [];
  final Set<String> _done = {};
  int compressions = 0; // how many beats since the CPR Beat started
  final FlutterTts _tts = FlutterTts(); // the voice that reads steps aloud
  bool practicing = false; // true while the Pace Practice screen is open
  final List<DateTime> _padTaps = []; // times of the last taps on the practice pad
  int? padBpm; // the speed we measured (beats per minute)
  final List<DateTime> _taps = []; // times of recent taps (for the panic detector)

  // YOUR TURN: write the real source you checked the steps against.
  // Only keep this if it is true!
  static const String mySource = 'American Red Cross first aid guidance';

  void _addLog(String msg) {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    setState(() {
      _log.insert(0, '${two(n.hour)}:${two(n.minute)}:${two(n.second)}  $msg');
    });
  }

  void _open(Emergency e) {
    if (e.steps.isEmpty) {
      setState(() => practicing = true);
      _addLog('Opened: CPR pace practice');
      return;
    }
    setState(() {
      current = e;
      step = 0;
    });
    _addLog('Opened: ${e.name}');
    if (stress) _speak('${e.name}. Step 1. ${e.steps[0]}');
  }

  void _close() {
    _addLog('Closed: ${current!.name}');
    setState(() => current = null);
  }

  void _tick() {
    _player.play(BytesSource(_beep, mimeType: 'audio/wav')).catchError((_) {});
    HapticFeedback.mediumImpact().catchError((_) {}); // buzz on every beat
    setState(() {
      pulse = !pulse;
      compressions++;
    });
    // At 100 beats a minute, 200 beats is 2 minutes. Tired pushers do worse CPR,
    // so we remind people to switch.
    if (compressions % 200 == 0) {
      _addLog('2 minutes of CPR - switch pushers if someone can take over');
    }
  }

  void _toggleBeat() {
    if (beating) {
      _timer?.cancel();
      setState(() => beating = false);
      _addLog('CPR beat stopped');
    } else {
      compressions = 0;
      _timer = Timer.periodic(const Duration(milliseconds: beatMs), (_) => _tick());
      _tick();
      setState(() => beating = true);
      _addLog('CPR beat started (100 beats per minute)');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  // PANIC DETECTOR: people who panic tap the screen very fast.
  // If we see 6 taps in 3 seconds, we turn Stress Mode ON for them.
  void _watchForPanic() {
    final now = DateTime.now();
    if (practicing) return; // fast taps on the practice pad are not panic
    _taps.add(now);
    _taps.removeWhere((t) => now.difference(t).inMilliseconds > 3000);
    if (_taps.length >= 6 && !stress) {
      _taps.clear();
      setState(() => stress = true);
      _addLog('Fast tapping noticed - Stress Mode turned ON automatically');
    }
  }

  // ---------- Pieces of the screen ----------

  Widget _giant(String label, Color color, VoidCallback onTap, {IconData? icon}) {
    return SizedBox(
      height: 96,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 40), const SizedBox(width: 10)],
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- NEW: voice, 911, and pace practice ----------

  // Reads text out loud. Browsers only allow talking after a tap, so we call this from taps.
  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.setSpeechRate(0.5);
      await _tts.speak(text);
      _addLog('Reading aloud');
    } catch (_) {}
  }

  // The HEAR IT button: reads the current step (Stress Mode) or all steps (Standard Mode).
  Future<void> _readAloud() async {
    final e = current;
    if (e == null) {
      await _speak('Pick an emergency. ${emergencies.map((x) => x.name).join(', ')}.');
    } else if (stress) {
      await _speak('Step ${step + 1}. ${e.steps[step]}');
    } else {
      await _speak(e.steps.join(' Next. '));
    }
  }

  // Opens the phone's dial screen with 911 typed in. The person still presses call.
  Future<void> _call911() async {
    _addLog('Tapped CALL 911');
    final ok = await launchUrl(Uri.parse('tel:911')).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This device cannot dial. Use a phone and call 911.')),
      );
    }
  }

  // PACE TRAINER: measures how fast you tap and says if it is good CPR speed.
  void _padTap() {
    _padTaps.add(DateTime.now());
    if (_padTaps.length > 8) _padTaps.removeAt(0); // only look at the last 8 taps
    if (_padTaps.length >= 4) {
      final ms = _padTaps.last.difference(_padTaps.first).inMilliseconds;
      // 4 taps make 3 gaps. Beats per minute = gaps * 60000 / total milliseconds.
      if (ms > 0) padBpm = ((_padTaps.length - 1) * 60000 / ms).round();
    }
    setState(() {});
  }

  Widget _practice() {
    final b = padBpm;
    final good = b != null && b >= 100 && b <= 120; // the CPR range: 100 to 120 a minute
    final verdict = b == null
        ? 'Keep tapping...'
        : (b < 100 ? 'TOO SLOW - tap faster' : (b > 120 ? 'TOO FAST - slow down' : 'GOOD PACE!'));
    final color = b == null ? Colors.grey : (good ? Colors.greenAccent : Colors.orangeAccent);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  practicing = false;
                  _padTaps.clear();
                  padBpm = null;
                });
                _addLog('Left CPR pace practice');
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
            ),
          ),
          const Text('CPR PACE PRACTICE',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const Text('Tap the circle to the beat. Aim for 100 to 120 a minute.',
              textAlign: TextAlign.center),
          Expanded(
            child: Center(
              child: GestureDetector(
                onTapDown: (_) => _padTap(),
                child: Container(
                  width: 230,
                  height: 230,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  child: Text(b == null ? 'TAP' : '$b',
                      style: const TextStyle(
                          fontSize: 70, fontWeight: FontWeight.w900, color: Colors.black)),
                ),
              ),
            ),
          ),
          Text(verdict,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }

  // Two big buttons that are always on screen: CALL 911 and HEAR IT.
  Widget _helpBar() {
    final h = stress ? 76.0 : 48.0;
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: SizedBox(
              height: h,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, foregroundColor: Colors.white),
                icon: Icon(Icons.call, size: stress ? 36 : 22),
                label: Text('CALL 911',
                    style: TextStyle(fontSize: stress ? 30 : 18, fontWeight: FontWeight.w900)),
                onPressed: _call911,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: h,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightBlueAccent, foregroundColor: Colors.black),
                icon: Icon(Icons.volume_up, size: stress ? 36 : 22),
                label: Text('HEAR IT',
                    style: TextStyle(fontSize: stress ? 26 : 16, fontWeight: FontWeight.w900)),
                onPressed: _readAloud,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stressSwitch() {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              stress ? 'STRESS MODE: ON' : 'STRESS MODE: OFF',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: stress ? Colors.yellow : Colors.white,
              ),
            ),
          ),
          Transform.scale(
            scale: 1.8,
            child: Switch(
              value: stress,
              activeColor: Colors.yellow,
              onChanged: (v) {
                setState(() => stress = v);
                _addLog(v ? 'Stress Mode ON' : 'Stress Mode OFF');
              },
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _home() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (!stress)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Pick an emergency:', style: TextStyle(fontSize: 18)),
          ),
        for (final e in emergencies)
          Padding(
            padding: EdgeInsets.symmetric(vertical: stress ? 8 : 4),
            child: stress
                ? _giant(e.name.toUpperCase(), e.color, () => _open(e), icon: e.icon)
                : Card(
                    color: const Color(0xFF161B22),
                    child: ListTile(
                      leading: Icon(e.icon, color: e.color),
                      title: Text(e.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(e),
                    ),
                  ),
          ),
      ],
    );
  }

  Widget _steps() {
    final e = current!;
    if (stress) {
      final last = step == e.steps.length - 1;
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text('${e.name.toUpperCase()}  -  STEP ${step + 1} OF ${e.steps.length}',
                textAlign: TextAlign.center,
                style: TextStyle(color: e.color, fontSize: 22, fontWeight: FontWeight.w900)),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Text(e.steps[step],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, height: 1.25)),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _giant('BACK', Colors.grey, () {
                    if (step > 0) {
                      setState(() => step--);
                      _addLog('Back to step ${step + 1} of ${e.name}');
                      _speak(e.steps[step]);
                    } else {
                      _close();
                    }
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _giant(last ? 'DONE' : 'NEXT', e.color, () {
                    _addLog('Finished step ${step + 1} of ${e.name}');
                    if (last) {
                      _close();
                    } else {
                      setState(() => step++);
                      _speak(e.steps[step]);
                    }
                  }),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _close,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        ),
        Text(e.name,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: e.color)),
        Text('Source: $mySource', style: const TextStyle(color: Colors.white54)),
        const SizedBox(height: 8),
        for (var i = 0; i < e.steps.length; i++)
          Card(
            color: const Color(0xFF161B22),
            child: CheckboxListTile(
              value: _done.contains('${e.name}$i'),
              title: Text('${i + 1}. ${e.steps[i]}'),
              onChanged: (v) {
                final on = v ?? false;
                setState(() {
                  if (on) {
                    _done.add('${e.name}$i');
                  } else {
                    _done.remove('${e.name}$i');
                  }
                });
                _addLog('${on ? "Checked" : "Unchecked"} step ${i + 1} of ${e.name}');
              },
            ),
          ),
      ],
    );
  }

  Widget _beatBar() {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: double.infinity,
        height: stress ? 84 : 56,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                beating ? (pulse ? Colors.white : Colors.redAccent) : Colors.pinkAccent,
            foregroundColor: Colors.black,
          ),
          icon: Icon(beating ? Icons.stop : Icons.favorite, size: stress ? 40 : 24),
          label: Text(
            beating ? 'STOP  -  $compressions pushes' : 'CPR BEAT (100 BPM)',
            style: TextStyle(fontSize: stress ? 28 : 18, fontWeight: FontWeight.w900),
          ),
          onPressed: _toggleBeat,
        ),
      ),
    );
  }

  // The log is tucked away at the bottom. Tap it to open it.
  Widget _logBox() {
    return Container(
      color: const Color(0xFF010409),
      child: ExpansionTile(
        title: Text('Action Log (${_log.length}) - tap to open',
            style: const TextStyle(fontSize: 14)),
        children: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy log for paramedics'),
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: 'AgniPulse action log (oldest first)\n${_log.reversed.join('\n')}'));
              _addLog('Log copied');
            },
          ),
          Container(
            height: 130,
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: SelectableText(
                _log.isEmpty ? 'Nothing yet.' : _log.join('\n'),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 12, color: Colors.greenAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _watchForPanic(),
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('AgniPulse', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFB71C1C),
            padding: const EdgeInsets.all(8),
            child: const Text(
              'In a real emergency, CALL 911 FIRST. This app is a helper, not a doctor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          _helpBar(),
          _stressSwitch(),
          Expanded(child: practicing ? _practice() : (current == null ? _home() : _steps())),
          _beatBar(),
          _logBox(),
        ],
      ),
    ),
    );
  }
}
