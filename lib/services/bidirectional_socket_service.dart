import 'dart:io';
import 'dart:convert';

class BidirectionalSocketService {
  ServerSocket? _server;
  Socket? _activeSocket;
  Function(Map<String, dynamic>)? onDataReceived;

  Future<void> startServer(Function(Map<String, dynamic>) onData) async {
    onDataReceived = onData;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 4040);
    _server?.listen((client) {
      _handleConnection(client);
    });
  }

  Future<void> connectToPeer(
    String peerIP,
    Function(Map<String, dynamic>) onData,
  ) async {
    onDataReceived = onData;
    final socket = await Socket.connect(peerIP, 4040);
    _handleConnection(socket);
  }

  void _handleConnection(Socket socket) {
    _activeSocket = socket;
    socket.cast<List<int>>().transform(utf8.decoder).listen((dataString) {
      final lines = dataString.split('\n');
      for (var line in lines) {
        if (line.trim().isNotEmpty) {
          try {
            final json = jsonDecode(line);
            if (onDataReceived != null) onDataReceived!(json);
          } catch (e) {
            // print("Error decoding: $e");
          }
        }
      }
    });
  }

  void sendData(Map<String, dynamic> data) {
    if (_activeSocket != null) {
      try {
        _activeSocket!.write('${jsonEncode(data)}\n');
      } catch (e) {
        // print("Error sending: $e");
      }
    }
  }

  void dispose() {
    _activeSocket?.destroy();
    _server?.close();
  }
}
