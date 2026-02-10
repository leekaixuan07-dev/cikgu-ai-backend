import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../providers/user_provider.dart';
import 'study_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _chapters = [];
  bool _isLoading = true;
  String _pdfLink = "";

  @override
  void initState() {
    super.initState();
    _fetchChapters();
    
    // Also sync user data if needed (e.g. on page refresh)
    WidgetsBinding.instance.addPostFrameCallback((_) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
            final provider = Provider.of<UserProvider>(context, listen: false);
            provider.setUser(user.uid, user.email!, user.displayName);
        }
    });
  }

  Future<void> _fetchChapters() async {
    final provider = Provider.of<UserProvider>(context, listen: false);
    try {
      final response = await http.get(Uri.parse('${provider.backendUrl}/chapters'));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final chaptersMap = data['chapters'] as Map<String, dynamic>;
        _pdfLink = data['pdf_drive_link'] ?? "";

        final List<Map<String, dynamic>> loadedChapters = [];
        chaptersMap.forEach((key, value) {
            loadedChapters.add({
                "title": key,
                "page": value, // Page number
            });
        });
        
        // Sort by page number
        loadedChapters.sort((a, b) => (a['page'] as int).compareTo(b['page'] as int));

        setState(() {
          _chapters = loadedChapters;
          _isLoading = false;
        });
      } else {
        // Handle error
        setState(() => _isLoading = false);
      }
    } catch (e) {
      print("Error fetching chapters: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("CikguAI Dashboard"),
        actions: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(child: Text(FirebaseAuth.instance.currentUser?.email ?? "")),
            ),
            IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () {
                    FirebaseAuth.instance.signOut();
                    Provider.of<UserProvider>(context, listen: false).clearUser();
                }
            )
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Padding(
            padding: const EdgeInsets.all(24.0),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 300,
                childAspectRatio: 1.5,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
              ),
              itemCount: _chapters.length,
              itemBuilder: (context, index) {
                final chapter = _chapters[index];
                return Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => StudyScreen(
                                    chapterTitle: chapter['title'],
                                    pdfUrl: _pdfLink,
                                )
                            )
                        );
                    },
                    child: Container(
                        decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: Theme.of(context).primaryColor, width: 6))
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Text(
                                    "Chapter ${index + 1}",
                                    style: TextStyle(
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.bold
                                    ),
                                ),
                                const Spacer(),
                                Text(
                                    chapter['title'],
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                    children: [
                                        const Icon(Icons.book_outlined, size: 16, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text("Page ${chapter['page']}", style: const TextStyle(color: Colors.grey)),
                                    ],
                                )
                            ],
                        ),
                    ),
                  ),
                );
              },
            ),
          ),
    );
  }
}
