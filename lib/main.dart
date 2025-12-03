import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
// Importamos la nueva pantalla de duelo y quitamos la de chat
import 'screens/duel_screen.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:audioplayers/audioplayers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuración de Audio Global para asegurar que suene en silencio y por altavoz
  final AudioContext audioContext = AudioContext(
    iOS: AudioContextIOS(
      category: AVAudioSessionCategory.playback,
      options: [
        AVAudioSessionOptions.defaultToSpeaker,
        AVAudioSessionOptions.mixWithOthers,
      ],
    ),
    android: AudioContextAndroid(
      isSpeakerphoneOn: true,
      stayAwake: true,
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
  );
  await AudioPlayer.global.setAudioContext(audioContext);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Duelo de Sables WiFi',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        // Un tema oscuro le pega más a los sables de luz
        brightness: Brightness.dark,
      ),
      home: const HomeSelectorScreen(),
    );
  }
}

class HomeSelectorScreen extends StatefulWidget {
  const HomeSelectorScreen({super.key});
  @override
  State<HomeSelectorScreen> createState() => _HomeSelectorScreenState();
}

class _HomeSelectorScreenState extends State<HomeSelectorScreen> {
  String ip = "Cargando...";
  final ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadLocalIP();
  }

  void _requestPermissions() async {
    await [Permission.location, Permission.nearbyWifiDevices].request();
  }

  void _loadLocalIP() async {
    // Obtenemos la IP local para mostrarla en pantalla
    String? wifiIP = await NetworkInfo().getWifiIP();
    setState(() {
      ip = wifiIP ?? "No conectado a WiFi";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Menú de Conexión')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_tethering,
              size: 80,
              color: Colors.blueAccent,
            ),
            const SizedBox(height: 20),
            const Text(
              'Tu IP Local:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              ip,
              style: const TextStyle(fontSize: 24, color: Colors.greenAccent),
            ),
            const SizedBox(height: 40),

            // --- BOTÓN PARA SERVIDOR (HOST) ---
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                icon: const Icon(Icons.phonelink_setup),
                label: const Text("CREAR SALA (HOST)"),
                onPressed: () {
                  // Navega a DuelScreen como Servidor (peerIP es null)
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => const DuelScreen(peerIP: null),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 40),
            const Divider(color: Colors.white54),
            const SizedBox(height: 20),

            // --- INPUT Y BOTÓN PARA CLIENTE ---
            TextField(
              controller: ipController,
              decoration: const InputDecoration(
                labelText: "IP del Host",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.computer),
                hintText: "Ej: 192.168.1.X",
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                icon: const Icon(Icons.login),
                label: const Text("UNIRSE A SALA"),
                onPressed: () {
                  if (ipController.text.isNotEmpty) {
                    // Navega a DuelScreen como Cliente (pasamos la IP)
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => DuelScreen(peerIP: ipController.text),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
