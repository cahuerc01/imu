import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vibration/vibration.dart';
import 'package:vector_math/vector_math.dart' as vmath;
import '../services/bidirectional_socket_service.dart';
import '../services/audio_manager.dart';
import '../game_logic/saber_config.dart';

class DuelScreen extends StatefulWidget {
  final String? peerIP;
  const DuelScreen({Key? key, this.peerIP}) : super(key: key);

  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> {
  final BidirectionalSocketService _socketService =
      BidirectionalSocketService();
  final AudioManager _audioManager = AudioManager();

  // Estado del Sable Local
  bool isSaberOn = false;
  double localAzimuth = 0.0; // Ángulo (Yaw) en radianes

  // Estado del Peer
  bool isPeerSaberOn = false;
  double peerAzimuth = 0.0;

  // Variables para LEDs y Colisión
  bool isLedOn = false; // Variable requerida para controlar LEDs externos
  bool _isInCollisionWindow = false;

  // Streams
  StreamSubscription? _magnetometerSub;
  StreamSubscription? _accelerometerSub;
  Timer? _networkTimer;

  @override
  void initState() {
    super.initState();
    _setupConnection();
  }

  void _setupConnection() {
    // Callback cuando recibimos datos del otro móvil
    final onData = (Map<String, dynamic> data) {
      if (mounted) {
        setState(() {
          // Invertimos el ángulo del peer porque él nos mira de frente (espejo)
          // Si no tenemos brújula absoluta, esto es una aproximación.
          // Asumimos que ambos "miran al norte" del juego al iniciar.
          if (data.containsKey('azimuth')) {
            peerAzimuth = (data['azimuth'] as num).toDouble();
          }
          if (data.containsKey('isSaberOn')) {
            isPeerSaberOn = data['isSaberOn'] as bool;
          }
        });
        _checkCollision();
      }
    };

    if (widget.peerIP == null) {
      _socketService.startServer(onData);
    } else {
      _socketService.connectToPeer(widget.peerIP!, onData);
    }
  }

  void _toggleSaber() {
    setState(() {
      isSaberOn = !isSaberOn;
      // Lógica de LEDs: Apagar todo si apagamos el sable
      isLedOn = isSaberOn;
    });

    if (isSaberOn) {
      _audioManager.playOn();
      _startSensors();
    } else {
      _audioManager.playOff();
      _stopSensors();
      // Restaurar estado
      isPeerSaberOn = false; // Asumimos desconexión visual
    }

    // Enviar nuevo estado inmediatamente
    _sendDataToPeer();
  }

  void _startSensors() {
    // 1. Leer Magnetómetro para Orientación (Saber Dirección)
    // Usamos MagnetometerEvent para obtener el norte magnético (Azimuth absoluto)
    _magnetometerSub = magnetometerEvents.listen((MagnetometerEvent event) {
      // Cálculo básico de azimuth (brújula 2D)
      // atan2(y, x) da el ángulo respecto al norte
      double azimuth = atan2(event.y, event.x);
      localAzimuth = azimuth;

      // Si quisiéramos usar giroscopio puro sería más suave pero derivaría (drift).
      // Para este ejemplo, magnetómetro es más sencillo para "saber dónde apuntas".
    });

    // 2. Leer Acelerómetro para Sonido de "Swing" (Movimiento)
    _accelerometerSub = userAccelerometerEvents.listen((
      UserAccelerometerEvent event,
    ) {
      if (!isSaberOn) return;

      // Calcular magnitud del movimiento
      double magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      if (magnitude > SaberConfig.swingThreshold) {
        _audioManager.playSwing();
      }
    });

    // 3. Timer de Red: Enviar datos cada 50ms (20 FPS de red)
    _networkTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      _sendDataToPeer();
    });
  }

  void _stopSensors() {
    _magnetometerSub?.cancel();
    _accelerometerSub?.cancel();
    _networkTimer?.cancel();
  }

  void _sendDataToPeer() {
    _socketService.sendData({'azimuth': localAzimuth, 'isSaberOn': isSaberOn});
  }

  // --- LÓGICA CENTRAL: Detección de Colisión ---
  void _checkCollision() {
    if (!isSaberOn || !isPeerSaberOn || _isInCollisionWindow) return;

    // Definimos las coordenadas 2D (Top-Down view)
    // Jugador Local (Yo): Posición (0,0).
    // Jugador Peer: Posición (0, Distance). Asumimos que está a 1.5m frente a mí.

    // Calculamos la punta de MI sable
    // Vector desde (0,0) con longitud SaberLength y ángulo localAzimuth
    vmath.Vector2 myStart = vmath.Vector2(0, 0);
    vmath.Vector2 myEnd = vmath.Vector2(
      SaberConfig.saberLength * cos(localAzimuth),
      SaberConfig.saberLength * sin(localAzimuth),
    );

    // Calculamos la punta del sable del PEER
    // IMPORTANTE: Su posición base es (0, Distance).
    // Su ángulo viene en 'peerAzimuth'. Como él está enfrente, su sistema de coordenadas
    // es relativo. Si ambos apuntamos al "Norte" geográfico, las líneas son paralelas.
    vmath.Vector2 peerStart = vmath.Vector2(
      0,
      SaberConfig.distanceBetweenPlayers,
    );
    vmath.Vector2 peerEnd = vmath.Vector2(
      peerStart.x + SaberConfig.saberLength * cos(peerAzimuth),
      peerStart.y + SaberConfig.saberLength * sin(peerAzimuth),
    );

    // Verificar Intersección de Segmentos
    if (_doLinesIntersect(myStart, myEnd, peerStart, peerEnd)) {
      _triggerCollisionEffect();
    }
  }

  // Matemáticas para intersección de dos segmentos p0-p1 y p2-p3
  bool _doLinesIntersect(
    vmath.Vector2 p0,
    vmath.Vector2 p1,
    vmath.Vector2 p2,
    vmath.Vector2 p3,
  ) {
    double s1_x, s1_y, s2_x, s2_y;
    s1_x = p1.x - p0.x;
    s1_y = p1.y - p0.y;
    s2_x = p3.x - p2.x;
    s2_y = p3.y - p2.y;

    double s, t;
    double denominator = (-s2_x * s1_y + s1_x * s2_y);

    if (denominator == 0) return false; // Paralelas

    s = (-s1_y * (p0.x - p2.x) + s1_x * (p0.y - p2.y)) / denominator;
    t = (s2_x * (p0.y - p2.y) - s2_y * (p0.x - p2.x)) / denominator;

    // Colisión detectada si 0 <= s <= 1 y 0 <= t <= 1
    if (s >= 0 && s <= 1 && t >= 0 && t <= 1) {
      return true;
    }
    return false;
  }

  void _triggerCollisionEffect() async {
    if (_isInCollisionWindow) return; // Evitar re-entradas múltiples
    _isInCollisionWindow = true;

    print("¡CHOQUE DE SABLES!");

    // 1. Sonido y Vibración
    _audioManager.playClash();
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 300);
    }

    // 2. Efecto de LEDs (Parpadeo True/False)
    _flashLeds();

    // 3. Resetear ventana de colisión después del tiempo configurado
    Future.delayed(
      Duration(milliseconds: SaberConfig.postCollisionWindowMs),
      () {
        if (mounted) {
          _isInCollisionWindow = false;
        }
      },
    );
  }

  // Lógica recursiva o loop para parpadear la variable isLedOn
  void _flashLeds() async {
    int count = SaberConfig.collisionFlashCount;
    int duration = SaberConfig.collisionFlashDurationMs;

    for (int i = 0; i < count; i++) {
      if (!mounted || !isSaberOn) break;
      setState(() => isLedOn = false); // Apagar
      await Future.delayed(Duration(milliseconds: duration));

      if (!mounted || !isSaberOn) break;
      setState(() => isLedOn = true); // Encender
      await Future.delayed(Duration(milliseconds: duration));
    }

    // Asegurar que termina en TRUE si el sable sigue encendido
    if (mounted && isSaberOn) {
      setState(() => isLedOn = true);
    }
  }

  @override
  void dispose() {
    _stopSensors();
    _socketService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duelo de Sables WiFi')),
      backgroundColor: isLedOn
          ? Colors.red.shade50
          : Colors.white, // Feedback visual simple
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Visualización DEBUG (Opcional, ayuda a entender)
            Text("Mi Orientación: ${localAzimuth.toStringAsFixed(2)} rad"),
            Text("Peer Orientación: ${peerAzimuth.toStringAsFixed(2)} rad"),
            const SizedBox(height: 20),
            Text(
              isSaberOn ? "SABLE ENCENDIDO" : "SABLE APAGADO",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isSaberOn ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTap: _toggleSaber,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSaberOn ? Colors.red : Colors.blueGrey,
                  boxShadow: [
                    if (isSaberOn)
                      BoxShadow(
                        color: Colors.red.withOpacity(0.6),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                  ],
                ),
                child: Icon(
                  Icons.power_settings_new,
                  size: 80,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(isLedOn ? "LED EXTERNO: ON" : "LED EXTERNO: OFF"),
            if (_isInCollisionWindow)
              const Text(
                "¡IMPACTO!",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 30,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
