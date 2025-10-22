import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'screens/chat_bidirectional_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat Bidireccional',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeSelectorScreen(),
    );
  }
}

class HomeSelectorScreen extends StatefulWidget {
  const HomeSelectorScreen({Key? key}) : super(key: key);
  @override
  State<HomeSelectorScreen> createState() => _HomeSelectorScreenState();
}

class _HomeSelectorScreenState extends State<HomeSelectorScreen> {
  String ip = "";
  final ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLocalIP();
  }

  void _loadLocalIP() async {
    ip = (await NetworkInfo().getWifiIP()) ?? "No conectado";
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modo de Chat')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('Tu IP Local: $ip'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context,
                  MaterialPageRoute(builder: (c) => ChatBidirectionalScreen(peerIP: null)));
              },
              child: const Text("INICIAR COMO SERVIDOR"),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: ipController,
              decoration: const InputDecoration(labelText: "IP del Servidor"),
            ),
            ElevatedButton(
              onPressed: () {
                if (ipController.text.isNotEmpty) {
                  Navigator.push(context,
                    MaterialPageRoute(builder: (c) =>
                      ChatBidirectionalScreen(peerIP: ipController.text)));
                }
              },
              child: const Text("CONECTAR COMO CLIENTE"),
            ),
          ],
        ),
      ),
    );
  }
}
