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
  const DuelScreen({super.key, this.peerIP});

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
  double baseAzimuth = 0.0; // Ángulo de referencia al encender

  // Estado del Peer
  bool isPeerSaberOn = false;
  double peerDeltaAzimuth = 0.0; // Ángulo relativo del peer

  // Variables para orientación adaptativa
  double _lastAccelY = 0.0;

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
    void onData(Map<String, dynamic> data) {
      if (mounted) {
        setState(() {
          // Invertimos el ángulo del peer porque él nos mira de frente (espejo)
          // Si no tenemos brújula absoluta, esto es una aproximación.
          // Asumimos que ambos "miran al norte" del juego al iniciar.
          // Asumimos que ambos "miran al norte" del juego al iniciar.
          if (data.containsKey('deltaAzimuth')) {
            peerDeltaAzimuth = (data['deltaAzimuth'] as num).toDouble();
          }
          if (data.containsKey('isSaberOn')) {
            isPeerSaberOn = data['isSaberOn'] as bool;
          }
        });
        _checkCollision();
      }
    }

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
      // Calibrar: El ángulo actual es el "frente" (0 grados relativos)
      baseAzimuth = localAzimuth;
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
    _magnetometerSub = magnetometerEventStream().listen((
      MagnetometerEvent event,
    ) {
      double azimuth;
      // Orientación Adaptativa:
      // Si el móvil está vertical (Y > 5.0 aprox, gravedad es 9.8), usamos Z y X.
      // Si está plano (Z > 5.0), usamos Y y X.
      bool isVertical = _lastAccelY.abs() > 5.0;

      if (isVertical) {
        // Modo "Espada" (Vertical)
        azimuth = atan2(event.z, event.x);
      } else {
        // Modo "Mesa" (Plano)
        azimuth = atan2(event.y, event.x);
      }

      setState(() {
        localAzimuth = azimuth;
      });
    });

    // 2. Leer Acelerómetro para Sonido de "Swing" y Orientación Adaptativa
    _accelerometerSub = userAccelerometerEventStream().listen((
      UserAccelerometerEvent event,
    ) {
      // Guardamos para uso en magnetómetro (aunque userAccelerometer quita gravedad,
      // para detectar postura idealmente usaríamos accelerometerEventStream normal.
      // Pero para simplificar, usaremos userAccelerometer asumiendo movimientos o
      // mejor aún, cambiamos a accelerometerEventStream para la gravedad).
    });
    // CORRECCIÓN: Necesitamos la gravedad para saber la postura.
    // Usamos accelerometerEventStream en lugar de userAccelerometerEventStream para esto?
    // No, userAccelerometer es mejor para swings.
    // Vamos a suscribirnos TAMBIÉN al acelerómetro normal para la gravedad.
    // O simplemente asumimos que userAccelerometer ~ 0 es quieto, pero no nos da la gravedad.
    // Haremos un truco: usaremos el sensor de gravedad si está disponible o accelerometer normal.
    // Por simplicidad, cambiamos userAccelerometer a accelerometer normal para TODO.
    _accelerometerSub = accelerometerEventStream().listen((
      AccelerometerEvent event,
    ) {
      _lastAccelY = event.y;

      if (!isSaberOn) return;

      // Calcular magnitud del movimiento (quitando gravedad aprox con filtro paso alto sería ideal,
      // pero magnitud bruta > 15 suele ser un swing fuerte si gravedad es 9.8)
      double magnitude = sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );

      // Umbral ajustado para acelerómetro con gravedad (9.8 base)
      // Swing fuerte será > 13.0 o < 6.0
      if ((magnitude - 9.8).abs() > SaberConfig.swingThreshold) {
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
    // Enviamos la diferencia respecto a nuestra base
    double delta = localAzimuth - baseAzimuth;
    _socketService.sendData({'deltaAzimuth': delta, 'isSaberOn': isSaberOn});
  }

  // --- LÓGICA CENTRAL: Detección de Colisión ---
  void _checkCollision() {
    if (!isSaberOn || !isPeerSaberOn || _isInCollisionWindow) return;

    // Definimos las coordenadas 2D (Top-Down view)
    // Jugador Local (Yo): Posición (0,0).
    // Jugador Peer: Posición (0, Distance). Asumimos que está a 1.5m frente a mí.

    // Calculamos la punta de MI sable
    // Vector desde (0,0) con longitud SaberLength.
    // Ángulo relativo: localAzimuth - baseAzimuth + PI/2 (para que 0 sea hacia arriba +Y)
    double myRelativeAngle = (localAzimuth - baseAzimuth) + (pi / 2);
    vmath.Vector2 myStart = vmath.Vector2(0, 0);
    vmath.Vector2 myEnd = vmath.Vector2(
      SaberConfig.saberLength * cos(myRelativeAngle),
      SaberConfig.saberLength * sin(myRelativeAngle),
    );

    // Calculamos la punta del sable del PEER
    // Posición base (0, Distance).
    // Su ángulo relativo: peerDeltaAzimuth.
    // PERO él está enfrente, rotado 180 grados (PI).
    // Su "frente" apunta hacia -Y (270 grados o -PI/2).
    // Entonces su ángulo efectivo es: peerDeltaAzimuth - PI/2.
    double peerEffectiveAngle = peerDeltaAzimuth - (pi / 2);

    vmath.Vector2 peerStart = vmath.Vector2(
      0,
      SaberConfig.distanceBetweenPlayers,
    );
    vmath.Vector2 peerEnd = vmath.Vector2(
      peerStart.x + SaberConfig.saberLength * cos(peerEffectiveAngle),
      peerStart.y + SaberConfig.saberLength * sin(peerEffectiveAngle),
    );

    // Verificar Intersección de Segmentos
    bool intersection = _doLinesIntersect(myStart, myEnd, peerStart, peerEnd);

    // Verificar Proximidad de Puntas (Tip Proximity)
    // Si las puntas están cerca (< 30cm), cuenta como choque (bloqueo/estocada)
    double tipDistance = myEnd.distanceTo(peerEnd);
    bool tipsClose = tipDistance < 0.3; // 30 cm

    if (intersection || tipsClose) {
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
    double s1X, s1Y, s2X, s2Y;
    s1X = p1.x - p0.x;
    s1Y = p1.y - p0.y;
    s2X = p3.x - p2.x;
    s2Y = p3.y - p2.y;

    double s, t;
    double denominator = (-s2X * s1Y + s1X * s2Y);

    if (denominator == 0) return false; // Paralelas

    s = (-s1Y * (p0.x - p2.x) + s1X * (p0.y - p2.y)) / denominator;
    t = (s2X * (p0.y - p2.y) - s2Y * (p0.x - p2.x)) / denominator;

    // Colisión detectada si 0 <= s <= 1 y 0 <= t <= 1
    if (s >= 0 && s <= 1 && t >= 0 && t <= 1) {
      return true;
    }
    return false;
  }

  void _triggerCollisionEffect() async {
    if (_isInCollisionWindow) return; // Evitar re-entradas múltiples
    _isInCollisionWindow = true;

    // print("¡CHOQUE DE SABLES!");

    // 1. Sonido y Vibración
    _audioManager.playClash();
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 300);
    }

    // 2. Efecto de LEDs (Parpadeo True/False)
    _flashLeds();

    // 3. Mensaje en Pantalla
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "¡COLISIÓN DETECTADA!",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 1),
        ),
      );
    }

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
            Text(
              "Mi Orientación: ${localAzimuth.toStringAsFixed(2)} rad",
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 24,
                color: Colors.black87,
              ),
            ),
            Text(
              "Peer Delta: ${peerDeltaAzimuth.toStringAsFixed(2)} rad",
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 24,
                color: Colors.black54,
              ),
            ),
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
                        color: Colors.red.withValues(alpha: 0.6),
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
            Text(
              isLedOn ? "LED EXTERNO: ON" : "LED EXTERNO: OFF",
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 30,
                color: Colors.black,
              ),
            ),
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
