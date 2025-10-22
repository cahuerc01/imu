import 'dart:io';

class BidirectionalSocketService {
  ServerSocket? _server;
  final List<Socket> _connections = [];

  // Inicia el servidor en el puerto 4040
  Future<void> startServer(Function(String) onMessageReceived) async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
    _server?.listen((client) {
      _connections.add(client);
      client.listen((data) {
        onMessageReceived(String.fromCharCodes(data));
      });
    });
  }

  // Se conecta como cliente al peer y escucha mensajes entrantes
  Future<void> connectToPeer(String peerIP, Function(String) onMessageReceived) async {
    final socket = await Socket.connect(peerIP, 4040);
    _connections.add(socket);
    socket.listen((data) {
      onMessageReceived(String.fromCharCodes(data));
    });
  }

  // Envía mensaje a todos los sockets abiertos
  void sendMessage(String msg) {
    for (final sock in _connections) {
      sock.write(msg);
    }
  }
}
