import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'providers/user_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

// IMPORTANT: Replace these with your actual Firebase configuration
const firebaseOptions = FirebaseOptions(
  apiKey: "AIzaSyCxWTlWpxfokACdnxiQ9EfQBt7f0ZuNzWw",
  authDomain: "kitahack-1c693.firebaseapp.com",
  projectId: "kitahack-1c693",
  storageBucket: "kitahack-1c693.firebasestorage.app",
  messagingSenderId: "45451906946",
  appId: "1:45451906946:web:bb324e18f9702e3561c99b",
  measurementId: "G-RD1CP8YN3Q",
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print("DEBUG: Application Starting...");
  try {
    print("DEBUG: Initializing Firebase...");
    await Firebase.initializeApp(options: firebaseOptions);
    print("DEBUG: Firebase Initialized Successfully!");
  } catch (e) {
    print("DEBUG: Firebase Init Error: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
      ],
      child: const CikguAIApp(),
    ),
  );
}

class CikguAIApp extends StatelessWidget {
  const CikguAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CikguAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          primary: Colors.blueAccent,
          secondary: Colors.amber, // Friendly secondary color
        ),
        useMaterial3: true,
        fontFamily: GoogleFonts.outfit().fontFamily, // Modern font
        textTheme: GoogleFonts.outfitTextTheme(),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        if (snapshot.hasData) {
            // Update UserProvider with basic info? 
            // Better to do this in dashboard init or post-login, but here is a safe check
            return const DashboardScreen();
        }
        
        return const LoginScreen();
      },
    );
  }
}
