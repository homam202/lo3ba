import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

// عدّل الأسماء هنا
const names = ['الشاب', 'الصغير', 'الأب', 'الجد', 'الولد'];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  ErrorWidget.builder = (d) => Material(
      color: Colors.white,
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
              child: Text('ERROR: ${d.exceptionAsString()}\n${d.stack}',
                  style: const TextStyle(color: Colors.red, fontSize: 11)))));
  runApp(const MaterialApp(
      debugShowCheckedModeBanner: false, home: MenuScreen()));
}

Future<ui.Image> loadFace(int i) async {
  final data = await rootBundle.load('assets/faces/face${i + 1}.png');
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5C94FC),
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('اختر شخصيتك',
              style: TextStyle(
                  fontSize: 30,
                  color: Colors.white,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(5, (i) {
              return GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => GameScreen(i))),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        image: DecorationImage(
                            image: AssetImage('assets/faces/face${i + 1}.png'),
                            fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(names[i],
                        style: const TextStyle(
                            color: Colors.white, fontSize: 16)),
                  ]),
                ),
              );
            }),
          ),
        ]),
      ),
    );
  }
}

class LevelData {
  final int w;
  final List<List<int>> gaps; // [from, to) columns without ground
  final List<List<int>> platforms; // x, y, len
  final List<List<int>> coins; // x, y
  final List<int> enemies; // x on ground
  LevelData(this.w, this.gaps, this.platforms, this.coins, this.enemies);
}

final levels = <LevelData>[
  LevelData(
      50,
      [[14, 17], [30, 33]],
      [[8, 5, 3], [20, 5, 4], [25, 4, 3], [38, 5, 4]],
      [[8, 4], [9, 4], [10, 4], [21, 4], [22, 4], [26, 3], [27, 3], [15, 5],
        [31, 5], [39, 4], [40, 4], [44, 6]],
      [11, 24, 36, 43]),
  LevelData(
      60,
      [[10, 13], [20, 24], [34, 37], [44, 47]],
      [[6, 5, 3], [16, 5, 2], [26, 5, 3], [30, 3, 3], [40, 5, 3], [50, 5, 4]],
      [[6, 4], [7, 4], [8, 4], [21, 4], [22, 4], [30, 2], [31, 2], [35, 5],
        [45, 5], [51, 4], [52, 4]],
      [8, 18, 28, 39, 48, 54]),
  LevelData(
      70,
      [[8, 11], [16, 20], [26, 29], [36, 40], [48, 51], [58, 61]],
      [[13, 5, 2], [22, 5, 3], [32, 4, 3], [44, 5, 3], [54, 5, 3], [64, 5, 3]],
      [[9, 5], [18, 4], [27, 5], [38, 4], [49, 5], [59, 4], [14, 4], [23, 4],
        [33, 3], [45, 4], [55, 4], [65, 4]],
      [6, 14, 24, 31, 42, 46, 56, 63]),
];

class Enemy {
  double x, y, dir = -1;
  bool alive = true;
  Enemy(this.x, this.y);
}

class Game extends ChangeNotifier {
  Game(this.face);
  final ui.Image? face;
  static const rows = 9;
  static const pw = 0.8, ph = 0.95;
  int levelIdx = 0, score = 0, lives = 3;
  bool left = false, right = false, jump = false;
  String state = 'play'; // play, over, win
  double viewW = 16;
  late List<List<bool>> solid;
  late List<List<int>> coins;
  late List<Enemy> enemies;
  double px = 2, py = 5, vx = 0, vy = 0, camX = 0;
  bool onGround = false;
  double time = 0;

  LevelData get lv => levels[levelIdx];
  int get flagX => lv.w - 3;

  void loadLevel() {
    final l = lv;
    solid = List.generate(l.w, (_) => List.filled(rows, false));
    for (var x = 0; x < l.w; x++) {
      final gap = l.gaps.any((g) => x >= g[0] && x < g[1]);
      if (!gap) {
        solid[x][7] = true;
        solid[x][8] = true;
      }
    }
    for (final p in l.platforms) {
      for (var i = 0; i < p[2]; i++) {
        solid[p[0] + i][p[1]] = true;
      }
    }
    coins = l.coins.map((c) => [c[0], c[1]]).toList();
    enemies = l.enemies.map((x) => Enemy(x.toDouble(), 6.2)).toList();
    respawn();
  }

  void respawn() {
    px = 1.5;
    py = 5.5;
    vx = vy = 0;
  }

  void restart() {
    levelIdx = 0;
    score = 0;
    lives = 3;
    state = 'play';
    loadLevel();
  }

  bool solidAt(int tx, int ty) {
    if (tx < 0) return true;
    if (tx >= lv.w) return true;
    if (ty < 0 || ty >= rows) return false;
    return solid[tx][ty];
  }

  void hurt() {
    lives--;
    if (lives <= 0) {
      state = 'over';
    } else {
      respawn();
    }
  }

  void update(double dt) {
    if (state != 'play') return;
    dt = min(dt, 0.033);
    time += dt;
    vx = ((left ? -1 : 0) + (right ? 1 : 0)) * 6.5;
    if (jump && onGround) {
      vy = -12.5;
      onGround = false;
    }
    vy = min(vy + 30 * dt, 20);

    // horizontal
    px += vx * dt;
    for (var tx = px.floor(); tx <= (px + pw - 0.001).floor(); tx++) {
      for (var ty = py.floor(); ty <= (py + ph - 0.001).floor(); ty++) {
        if (solidAt(tx, ty)) {
          px = vx > 0 ? tx - pw - 0.001 : tx + 1.001;
        }
      }
    }
    // vertical
    py += vy * dt;
    onGround = false;
    for (var tx = px.floor(); tx <= (px + pw - 0.001).floor(); tx++) {
      for (var ty = py.floor(); ty <= (py + ph - 0.001).floor(); ty++) {
        if (solidAt(tx, ty)) {
          if (vy > 0) {
            py = ty - ph;
            onGround = true;
          } else {
            py = ty + 1.0;
          }
          vy = 0;
        }
      }
    }
    if (py > rows + 1) hurt();

    // coins
    coins.removeWhere((c) {
      final hit = (c[0] + 0.5 - (px + pw / 2)).abs() < 0.7 &&
          (c[1] + 0.5 - (py + ph / 2)).abs() < 0.8;
      if (hit) score += 10;
      return hit;
    });

    // enemies
    for (final e in enemies.where((e) => e.alive)) {
      e.x += e.dir * 1.5 * dt;
      final front = e.dir > 0 ? (e.x + 0.8).floor() : e.x.floor();
      if (solidAt(front, 6) || !solidAt(front, 7)) e.dir = -e.dir;
      final overlap = px < e.x + 0.8 &&
          px + pw > e.x &&
          py < e.y + 0.8 &&
          py + ph > e.y;
      if (overlap) {
        if (vy > 0 && py + ph < e.y + 0.6) {
          e.alive = false;
          vy = -9;
          score += 100;
        } else {
          hurt();
          break;
        }
      }
    }

    // flag
    if (px > flagX) {
      score += 200;
      if (levelIdx + 1 >= levels.length) {
        state = 'win';
      } else {
        levelIdx++;
        loadLevel();
      }
    }
    camX = (px - viewW / 2).clamp(0.0, max(0.0, lv.w - viewW));
    notifyListeners();
  }
}

class GameScreen extends StatefulWidget {
  final int index;
  const GameScreen(this.index, {super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  Game? game;
  String? error;
  late Ticker ticker;
  Duration last = Duration.zero;

  @override
  void initState() {
    super.initState();
    loadFace(widget.index).then((img) {
      final g = Game(img)..loadLevel();
      setState(() => game = g);
    }).catchError((e, st) {
      setState(() => error = '$e\n$st');
    });
    ticker = createTicker((d) {
      final dt = (d - last).inMicroseconds / 1e6;
      last = d;
      try {
        game?.update(dt);
      } catch (e, st) {
        if (error == null) setState(() => error = 'UPDATE: $e\n$st');
      }
    })..start();
  }

  @override
  void dispose() {
    ticker.dispose();
    super.dispose();
  }

  Widget btn(String t, void Function(bool) set, {double size = 76}) {
    return Listener(
      onPointerDown: (_) => set(true),
      onPointerUp: (_) => set(false),
      onPointerCancel: (_) => set(false),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white54, width: 2)),
        alignment: Alignment.center,
        child: Text(t,
            style: const TextStyle(fontSize: 30, color: Colors.white)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    if (error != null) {
      return Scaffold(
          body: SingleChildScrollView(
              child: Text('ERROR: $error',
                  style: const TextStyle(color: Colors.red, fontSize: 11))));
    }
    if (g == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        g.viewW = c.maxWidth / (c.maxHeight / Game.rows);
        return Stack(children: [
          Positioned.fill(child: CustomPaint(painter: GamePainter(g))),
          Positioned(
              left: 20,
              bottom: 20,
              child: Row(children: [
                btn('◀', (v) => g.left = v),
                const SizedBox(width: 16),
                btn('▶', (v) => g.right = v),
              ])),
          Positioned(
              right: 30, bottom: 20, child: btn('▲', (v) => g.jump = v, size: 90)),
          Positioned(
              top: 10,
              left: 16,
              child: AnimatedBuilder(
                  animation: g,
                  builder: (_, __) => Text(
                      '♥ ${g.lives}   ★ ${g.score}   مرحلة ${g.levelIdx + 1}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)))),
          Positioned(
              top: 6,
              right: 10,
              child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context))),
          AnimatedBuilder(
              animation: g,
              builder: (_, __) {
                if (g.state == 'play') return const SizedBox();
                return Container(
                  color: Colors.black54,
                  alignment: Alignment.center,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(g.state == 'win' ? 'ربحت! 🎉' : 'انتهت اللعبة',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold)),
                    Text('النقاط: ${g.score}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 22)),
                    const SizedBox(height: 12),
                    ElevatedButton(
                        onPressed: g.restart, child: const Text('العب مجدداً')),
                  ]),
                );
              }),
        ]);
      }),
    );
  }
}

class GamePainter extends CustomPainter {
  final Game g;
  GamePainter(this.g) : super(repaint: g);

  @override
  void paint(Canvas canvas, Size size) {
    try {
      _paint(canvas, size);
    } catch (e, st) {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
      final tp = TextPainter(
          text: TextSpan(
              text: 'PAINT ERROR: $e\n$st',
              style: const TextStyle(color: Colors.red, fontSize: 11)),
          textDirection: TextDirection.ltr)
        ..layout(maxWidth: size.width);
      tp.paint(canvas, Offset.zero);
    }
  }

  void _paint(Canvas canvas, Size size) {
    final s = size.height / Game.rows;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF5C94FC));
    canvas.save();
    canvas.scale(s);
    canvas.translate(-g.camX, 0);
    final x0 = max(0, g.camX.floor() - 1);
    final x1 = min(g.lv.w, (g.camX + g.viewW).ceil() + 1);
    final ground = Paint()..color = const Color(0xFFC84C0C);
    final top = Paint()..color = const Color(0xFF3CB043);
    final line = Paint()
      ..color = Colors.black26
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.04;
    for (var x = x0; x < x1; x++) {
      for (var y = 0; y < Game.rows; y++) {
        if (!g.solid[x][y]) continue;
        final r = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
        canvas.drawRect(r, ground);
        if (y == 0 || !g.solid[x][y - 1]) {
          canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 0.25), top);
        }
        canvas.drawRect(r, line);
      }
    }
    // coins
    final coin = Paint()..color = const Color(0xFFFFD700);
    for (final c in g.coins) {
      canvas.drawOval(
          Rect.fromLTWH(c[0] + 0.25, c[1] + 0.15, 0.5, 0.7), coin);
    }
    // flag
    final fx = g.flagX.toDouble();
    canvas.drawRect(Rect.fromLTWH(fx + 0.4, 2, 0.12, 5), Paint()..color = Colors.white);
    final flag = Path()
      ..moveTo(fx + 0.52, 2)
      ..lineTo(fx + 1.6, 2.5)
      ..lineTo(fx + 0.52, 3)
      ..close();
    canvas.drawPath(flag, Paint()..color = Colors.red);
    // enemies
    for (final e in g.enemies.where((e) => e.alive)) {
      canvas.drawOval(Rect.fromLTWH(e.x, e.y, 0.8, 0.8),
          Paint()..color = const Color(0xFF8B4513));
      final w = Paint()..color = Colors.white;
      final b = Paint()..color = Colors.black;
      canvas.drawCircle(Offset(e.x + 0.28, e.y + 0.3), 0.12, w);
      canvas.drawCircle(Offset(e.x + 0.52, e.y + 0.3), 0.12, w);
      canvas.drawCircle(Offset(e.x + 0.28, e.y + 0.32), 0.05, b);
      canvas.drawCircle(Offset(e.x + 0.52, e.y + 0.32), 0.05, b);
    }
    // player
    final x = g.px, y = g.py;
    final step = (g.vx != 0 && g.onGround) ? sin(g.time * 18) * 0.08 : 0.0;
    canvas.drawRect(Rect.fromLTWH(x + 0.12 + step, y + 0.75, 0.22, 0.2),
        Paint()..color = const Color(0xFF1E3EA8));
    canvas.drawRect(Rect.fromLTWH(x + 0.46 - step, y + 0.75, 0.22, 0.2),
        Paint()..color = const Color(0xFF1E3EA8));
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x + 0.1, y + 0.45, 0.6, 0.38), const Radius.circular(0.08)),
        Paint()..color = const Color(0xFFE52521));
    final c = Offset(x + 0.4, y + 0.32);
    const r = 0.32;
    final face = g.face;
    if (face != null) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
      canvas.drawImageRect(
          face,
          Rect.fromLTWH(0, 0, face.width.toDouble(), face.height.toDouble()),
          Rect.fromCircle(center: c, radius: r),
          Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();
    }
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.05);
    // red cap
    canvas.drawArc(Rect.fromCircle(center: c, radius: r + 0.02), pi * 1.1,
        pi * 0.8, false, Paint()
          ..color = const Color(0xFFE52521)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.1);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GamePainter old) => true;
}
