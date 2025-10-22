import 'package:flutter/material.dart';
import '../services/bidirectional_socket_service.dart';

class ChatBidirectionalScreen extends StatefulWidget {
  final String? peerIP; // Si es null, será servidor
  const ChatBidirectionalScreen({Key? key, this.peerIP}) : super(key: key);

  @override
  State<ChatBidirectionalScreen> createState() => _ChatBidirectionalScreenState();
}

class _ChatBidirectionalScreenState extends State<ChatBidirectionalScreen> {
  final BidirectionalSocketService svc = BidirectionalSocketService();
  final List<String> messages = [];
  final controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.peerIP == null) {
      svc.startServer((msg) {
        setState(() {
          messages.add('Peer: $msg');
        });
      });
    } else {
      svc.connectToPeer(widget.peerIP!, (msg) {
        setState(() {
          messages.add('Peer: $msg');
        });
      });
    }
  }

  void sendMsg() {
    final txt = controller.text;
    if (txt.isNotEmpty) {
      svc.sendMessage(txt);
      setState(() {
        messages.add('Yo: $txt');
      });
      controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Bidireccional'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: messages.length,
              itemBuilder: (ctx, i) => ListTile(title: Text(messages[i])),
            ),
          ),
          Row(
            children: [
              Expanded(child: TextField(controller: controller)),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: sendMsg,
              )
            ],
          ),
        ],
      ),
    );
  }
}
