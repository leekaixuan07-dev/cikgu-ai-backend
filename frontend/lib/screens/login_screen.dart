import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../providers/user_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      GoogleAuthProvider googleProvider = GoogleAuthProvider();
      // On web this will redirect or popup
      final userCredential = await FirebaseAuth.instance.signInWithPopup(googleProvider);
      
      if (userCredential.user != null) {
        final user = userCredential.user!;
        
        // Sync with Backend
        final provider = Provider.of<UserProvider>(context, listen: false);
        final url = Uri.parse('${provider.backendUrl}/auth/login');
        
        try {
            final response = await http.post(
                url,
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                    "uid": user.uid,
                    "email": user.email,
                    "name": user.displayName
                })
            );
            
            if (response.statusCode == 200) {
                 // Update Provider
                 provider.setUser(user.uid, user.email!, user.displayName);
            } else {
                 print("Backend Sync Failed: ${response.body}");
            }
        } catch (e) {
            print("Backend Connection Error: $e");
            // Still allow login even if backend sync fails (offline mode?) 
            // but for this app critical features need backend.
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Login Failed: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.school, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                "Welcome to CikguAI",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Your Personal AI Study Companion",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  icon: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: const Text("Sign in with Google"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
