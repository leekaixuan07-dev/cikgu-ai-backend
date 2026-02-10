import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:html' as html; // For IFrame
import 'dart:ui_web' as ui_web; // For platform view registry
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';

class StudyScreen extends StatefulWidget {
  final String chapterTitle;
  final String pdfUrl;

  const StudyScreen({
    super.key,
    required this.chapterTitle,
    required this.pdfUrl,
  });

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isTyping = false;
  String? _modeBadge; // To track if mode changed

  @override
  void initState() {
    super.initState();
    // Register the IFrame view factory
    final String viewId = 'pdf-viewer-${widget.chapterTitle.hashCode}';
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(
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
    final provider = Provider.of<UserProvider>(context, listen: false);
    
    setState(() {
      _messages.add({"role": "user", "content": userMsg});
      _isTyping = true;
      _controller.clear();
    });
    
    _scrollToBottom();

    try {
      final response = await http.post(
        Uri.parse('${provider.backendUrl}/chat'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "uid": provider.uid,
          "message": userMsg,
          "current_chapter_name": widget.chapterTitle,
          "history": [] 
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final aiMsg = data['response'];
        final modeUsed = data['mode_used'];

        // Update mode if changed
        if (modeUsed != provider.currentMode) {
             provider.setMode(modeUsed);
             _showModeChangeSnackBar(modeUsed);
        }

        setState(() {
          _messages.add({"role": "assistant", "content": aiMsg});
        });
      } else {
        setState(() => _messages.add({"role": "system", "content": "Error: ${response.statusCode}"}));
      }
    } catch (e) {
      setState(() => _messages.add({"role": "system", "content": "Connection Failed: $e"}));
    } finally {
      setState(() => _isTyping = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), 
            curve: Curves.easeOut);
      }
    });
  }

  void _showModeChangeSnackBar(String newMode) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  newMode == "Remedial" 
                  ? "Don't worry, switching to Santai Mode! (Abang Persona Activated)" 
                  : "Great progress! Switching back to Cikgu Mode."
              ),
              backgroundColor: newMode == "Remedial" ? Colors.orange : Colors.blue,
              duration: const Duration(seconds: 4),
          )
      );
  }

  void _startQuiz() {
      showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => QuizDialog(chapterTitle: widget.chapterTitle)
      );
  }

  @override
  Widget build(BuildContext context) {
    final mode = Provider.of<UserProvider>(context).currentMode;
    final isRemedial = mode == "Remedial";

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chapterTitle),
        actions: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: isRemedial ? Colors.orange[100] : Colors.blue[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isRemedial ? Colors.orange : Colors.blue)
                ),
                child: Row(
                    children: [
                        Icon(isRemedial ? Icons.coffee : Icons.school, size: 18, color: isRemedial ? Colors.orange[800] : Colors.blue[800]),
                        const SizedBox(width: 8),
                        Text(
                            isRemedial ? "Santai Mode" : "Cikgu Mode",
                            style: TextStyle(
                                color: isRemedial ? Colors.orange[900] : Colors.blue[900],
                                fontWeight: FontWeight.bold
                            ),
                        ),
                    ],
                ),
            ),
            const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // LEFT: PDF VIEW (60%)
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

          // RIGHT: CHAT INTERFACE (40%)
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
                            color: isUser ? Colors.blueAccent : (isRemedial ? Colors.orange[50] : Colors.grey[100]),
                            borderRadius: BorderRadius.circular(12).copyWith(
                                topLeft: isUser ? const Radius.circular(12) : Radius.zero,
                                topRight: isUser ? Radius.zero : const Radius.circular(12)
                            ),
                            border: isUser ? null : Border.all(color: Colors.grey[300]!)
                          ),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  if (!isUser) 
                                    Text(
                                        isRemedial ? "Abang Cikgu" : "CikguAI",
                                        style: TextStyle(
                                            fontSize: 10, 
                                            fontWeight: FontWeight.bold,
                                            color: isRemedial ? Colors.orange : Colors.blue
                                        )
                                    ),
                                  if (!isUser) const SizedBox(height: 4),
                                  isUser 
                                    ? Text(msg['content']!, style: const TextStyle(color: Colors.white))
                                    : MarkdownBody(data: msg['content']!),
                              ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_isTyping) const LinearProgressIndicator(minHeight: 2),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey[200]!))
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: isRemedial ? "Tak faham? Tanya je..." : "Ask a question...",
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                            filled: true,
                            fillColor: Colors.grey[50],
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20)
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton(
                        mini: true,
                        onPressed: _sendMessage,
                        child: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _startQuiz,
          label: const Text("Take Quiz"),
          icon: const Icon(Icons.quiz),
          backgroundColor: isRemedial ? Colors.orange : Colors.indigo,
          foregroundColor: Colors.white,
      ),
    );
  }
}

// --- QUIZ DIALOG COMPONENT ---
class QuizDialog extends StatefulWidget {
    final String chapterTitle;
    const QuizDialog({super.key, required this.chapterTitle});

    @override
    State<QuizDialog> createState() => _QuizDialogState();
}

class _QuizDialogState extends State<QuizDialog> {
    List<dynamic> _questions = [];
    bool _loading = true;
    final Map<int, String> _answers = {};
    bool _submitted = false;
    double? _score;

    @override
    void initState() {
        super.initState();
        _generateQuiz();
    }

    Future<void> _generateQuiz() async {
        final provider = Provider.of<UserProvider>(context, listen: false);
        try {
            final response = await http.post(
                Uri.parse('${provider.backendUrl}/quiz/generate'),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                    "uid": provider.uid,
                    "chapter_name": widget.chapterTitle
                })
            );
            
            if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                setState(() {
                    _questions = data['questions'];
                    _loading = false;
                });
            }
        } catch (e) {
            print("Quiz Error: $e");
            Navigator.pop(context); // Close on error
        }
    }

    Future<void> _submitQuiz() async {
        if (_answers.length < _questions.length) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please answer all questions")));
            return;
        }

        int correct = 0;
        for (int i = 0; i < _questions.length; i++) {
            if (_answers[i] == _questions[i]['answer']) {
                correct++;
            }
        }

        final scorePercent = (correct / _questions.length) * 100;
        final provider = Provider.of<UserProvider>(context, listen: false);

        setState(() {
            _submitted = true;
            _score = scorePercent;
        });

        // Send to Backend
        try {
            final response = await http.post(
                Uri.parse('${provider.backendUrl}/quiz/submit'),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                    "uid": provider.uid,
                    "score_percent": scorePercent
                })
            );

            if (response.statusCode == 200) {
                final data = jsonDecode(response.body);
                final newMode = data['new_mode'];
                
                if (newMode != provider.currentMode) {
                    provider.setMode(newMode);
                     // Show snackbar main screen effectively handles this via provider update? 
                     // No, need to show it here or upon close.
                }
            }
        } catch (e) {
            print("Submit Error: $e");
        }
    }

    @override
    Widget build(BuildContext context) {
        return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
                width: 600,
                padding: const EdgeInsets.all(24),
                child: _loading 
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Generating Quiz...")],
                      )
                    : SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text("Quiz: ${widget.chapterTitle}", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                                const Divider(),
                                ...List.generate(_questions.length, (index) {
                                    final q = _questions[index];
                                    return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                                Text("${index + 1}. ${q['question']}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                                const SizedBox(height: 8),
                                                ...List<Widget>.from(q['options'].map((opt) {
                                                    final isSelected = _answers[index] == opt;
                                                    final isCorrect = q['answer'] == opt;
                                                    
                                                    Color? color;
                                                    if (_submitted) {
                                                        if (isCorrect) color = Colors.green[100];
                                                        if (isSelected && !isCorrect) color = Colors.red[100];
                                                    } else if (isSelected) {
                                                        color = Colors.blue[50];
                                                    }

                                                    return RadioListTile<String>(
                                                        title: Text(opt),
                                                        value: opt,
                                                        groupValue: _answers[index],
                                                        tileColor: color,
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                        onChanged: _submitted ? null : (val) {
                                                            setState(() => _answers[index] = val!);
                                                        },
                                                    );
                                                }))
                                            ],
                                        ),
                                    );
                                }),
                                const SizedBox(height: 24),
                                if (_submitted)
                                    Container(
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                            color: (_score! >= 50) ? Colors.green[50] : Colors.orange[50],
                                            borderRadius: BorderRadius.circular(8)
                                        ),
                                        child: Row(
                                            children: [
                                                Icon((_score! >= 50) ? Icons.check_circle : Icons.info, color: (_score! >= 50) ? Colors.green : Colors.orange),
                                                const SizedBox(width: 12),
                                                Text(
                                                    "Score: ${_score!.toStringAsFixed(0)}% - ${(_score! >= 50) ? 'Great Job!' : 'Lets review this.'}",
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                                ),
                                            ],
                                        ),
                                    ),
                                const SizedBox(height: 16),
                                Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: Text(_submitted ? "Close" : "Cancel")
                                        ),
                                        if (!_submitted)
                                            ElevatedButton(
                                                onPressed: _submitQuiz,
                                                child: const Text("Submit Answers")
                                            )
                                    ],
                                )
                            ],
                        ),
                    ),
            ),
        );
    }
}
