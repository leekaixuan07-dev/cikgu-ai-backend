import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html; // For IFrame
import 'dart:ui' as ui; // For platform view registry
import '../constants.dart';

class StudyRoomScreen extends StatefulWidget {
  final String chapterTitle;
  final int pageNumber;
  final String pdfUrl;

  const StudyRoomScreen({
    super.key,
    required this.chapterTitle,
    required this.pageNumber,
    required this.pdfUrl,
  });

  @override
  State<StudyRoomScreen> createState() => _StudyRoomScreenState();
}

class _StudyRoomScreenState extends State<StudyRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isTyping = false;
  String _currentMode = "Standard"; // Default

  @override
  void initState() {
    super.initState();
    // Register the IFrame view factory
    // Note: detailed implementation would require conditional import for non-web
    // but we are targeting web specifically here.
    final String viewId = 'pdf-viewer-${widget.chapterTitle.hashCode}';
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(
      viewId,
      (int viewId) => html.IFrameElement()
        ..src = widget.pdfUrl
        ..style.border = 'none'
        ..style.height = '100%'
        ..style.width = '100%'
        ..allowFullscreen = true,
    );
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final userMsg = _controller.text;
    setState(() {
      _messages.add({"role": "user", "content": userMsg});
      _isTyping = true;
      _controller.clear();
    });
    
    // Scroll to bottom
    Future.delayed(Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300), 
            curve: Curves.easeOut);
      }
    });

    try {
      // Call Backend
      final response = await http.post(
        Uri.parse('$kBackendUrl/chat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "uid": "test_user_uid", // Replace with actual Auth logic
          "message": userMsg,
          "context": "Page ${widget.pageNumber} content...", // Add mechanism to fetch page text if possible
          "history": _messages.map((m) => {
            "role": m['role'] == 'user' ? 'user' : 'model',
            "content": m['content']
          }).toList() 
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final aiMsg = data['response'];
        final mode = data['mode_used'];

        setState(() {
          _messages.add({"role": "assistant", "content": aiMsg});
          _currentMode = mode;
        });
      } else {
        setState(() {
          _messages.add({"role": "system", "content": "Error: ${response.statusCode}"});
        });
      }
    } catch (e) {
      setState(() {
        _messages.add({"role": "system", "content": "Connection Failed: $e"});
      });
    } finally {
      setState(() => _isTyping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapterTitle),
        actions: [
            Chip(
                label: Text("Mode: $_currentMode"),
                backgroundColor: _currentMode == "Standard" ? Colors.blue[100] : Colors.green[100],
            ),
            const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // LEFT: PDF VIEW
          Expanded(
            flex: 6,
            child: Container(
              color: Colors.grey[200],
              child: HtmlElementView(
                viewType: 'pdf-viewer-${widget.chapterTitle.hashCode}',
              ),
            ),
          ),
          
          // VERTICAL DIVIDER
          const VerticalDivider(width: 1),

          // RIGHT: CHAT INTERFACE
          Expanded(
            flex: 4,
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isUser = msg['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          constraints: const BoxConstraints(maxWidth: 300),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.blueAccent : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: isUser 
                            ? Text(msg['content']!, style: const TextStyle(color: Colors.white))
                            : MarkdownBody(data: msg['content']!),
                        ),
                      );
                    },
                  ),
                ),
                if (_isTyping) const LinearProgressIndicator(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: "Ask CikguAI...",
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
