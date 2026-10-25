import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

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

  void _addLog(String msg) {
    final n = DateTime.now();
    String two(int x) => x.toString().padLeft(2, '0');
    setState(() {
      _log.insert(0, '${two(n.hour)}:${two(n.minute)}:${two(n.second)}  $msg');
    });
  }

  void _open(Emergency e) {
    setState(() {
      current = e;
      step = 0;
    });
    _addLog('Opened: ${e.name}');
  }

  void _close() {
    _addLog('Closed: ${current!.name}');
    setState(() => current = null);
  }

  void _tick() {
    _player.play(BytesSource(_beep, mimeType: 'audio/wav')).catchError((_) {});
    setState(() => pulse = !pulse);
  }

  void _toggleBeat() {
    if (beating) {
      _timer?.cancel();
      setState(() => beating = false);
      _addLog('CPR beat stopped');
    } else {
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
            beating ? 'STOP BEAT' : 'CPR BEAT (100 BPM)',
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
    return Scaffold(
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
          _stressSwitch(),
          Expanded(child: current == null ? _home() : _steps()),
          _beatBar(),
          _logBox(),
        ],
      ),
    );
  }
}
