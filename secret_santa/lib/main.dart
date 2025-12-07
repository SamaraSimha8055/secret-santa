import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'firebase_options.dart';

const String ADMIN_EMAIL = "bhaskark301@gmail.com";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Secret Santa',
      home: AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (!snap.hasData) return LoginPage();
        return HomePage(user: snap.data!);
      },
    );
  }
}

//
// 🎄 LOGIN PAGE WITH CHRISTMAS BACKGROUND
//
class LoginPage extends StatefulWidget {
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(), password: _pass.text.trim());
    } on FirebaseAuthException catch (e) {
      setState(() {
        _error = e.message;
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              color: Colors.white.withOpacity(0.85),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Secret Santa Login",
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.bold)),
                    SizedBox(height: 12),
                    TextField(
                        controller: _email,
                        decoration: InputDecoration(labelText: 'Email')),
                    TextField(
                        controller: _pass,
                        decoration: InputDecoration(labelText: 'Password'),
                        obscureText: true),
                    SizedBox(height: 12),
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(color: Colors.red, fontSize: 14)),
                    SizedBox(height: 12),
                    ElevatedButton(
                        onPressed: _loading ? null : signIn,
                        child: _loading
                            ? CircularProgressIndicator()
                            : Text('Login')),
                    SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => SuperAdminLoginPage()));
                      },
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightGreenAccent),
                      child: Text('Super Admin Login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

//
// 🎁 HOME PAGE + WISHLIST PAGE
//
class HomePage extends StatefulWidget {
  final User user;
  HomePage({required this.user});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _wishCtrl = TextEditingController();
  bool _saved = false;
  bool _isAdmin = false;
  bool _allDone = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _isAdmin = widget.user.email == ADMIN_EMAIL;
    _loadMyData();
    _checkAllDone();
  }

  Future<void> _loadMyData() async {
    final docRef =
    FirebaseFirestore.instance.collection('users').doc(widget.user.uid);
    final doc = await docRef.get();
    if (doc.exists) {
      final data = doc.data()!;
      _wishCtrl.text = (data['wishlist'] ?? '');
      setState(() {
        _saved = data['done'] == true;
      });
    } else {
      await docRef.set({
        'email': widget.user.email,
        'name': widget.user.email?.split('@').first ?? widget.user.uid,
        'wishlist': '',
        'done': false,
      });
    }
  }

  Future<void> _checkAllDone() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();
    final docs = snap.docs;
    final bool allDone =
        docs.isNotEmpty && docs.every((d) => (d.data()['done'] == true));
    setState(() {
      _allDone = allDone;
    });
  }

  Future<void> _saveWishlist() async {
    final docRef =
    FirebaseFirestore.instance.collection('users').doc(widget.user.uid);
    await docRef.set({
      'email': widget.user.email,
      'name': widget.user.email!.split('@').first,
      'wishlist': _wishCtrl.text.trim(),
      'done': true,
    }, SetOptions(merge: true));
    setState(() {
      _saved = true;
      _status = "Wishlist saved.";
    });
    await _checkAllDone();
  }

  Future<void> _callShuffle() async {
    setState(() {
      _status = "Shuffling...";
    });
    try {
      final HttpsCallable callable =
      FirebaseFunctions.instance.httpsCallable('shuffleAndSend');
      final res = await callable();
      final data = res.data;
      setState(() {
        _status = 'Shuffled ${data['count']} users and emails sent.';
      });
    } catch (e) {
      setState(() {
        _status = 'Shuffle failed: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.user.email?.split('@').first ?? 'User';
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome $name 🎄'),
        backgroundColor: Colors.red.shade700,
        actions: [
          IconButton(
              icon: Icon(Icons.logout),
              onPressed: () => FirebaseAuth.instance.signOut())
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
              image: AssetImage("assets/images/background.png"),
              fit: BoxFit.cover),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _saved ? _savedBody() : _formBody(),
        ),
      ),
    );
  }

  Widget _formBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter your wishlist 🎁',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Expanded(
            child: TextField(
              controller: _wishCtrl,
              maxLines: null,
              expands: true,
              decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white70,
                  border: OutlineInputBorder()),
            )),
        SizedBox(height: 12),
        ElevatedButton(onPressed: _saveWishlist, child: Text('Done')),
      ],
    );
  }

  Widget _savedBody() {
    return Center(
      child: Card(
        color: Colors.white.withOpacity(0.85),
        margin: EdgeInsets.all(30),
        child: Padding(
            padding: const EdgeInsets.all(20),
            child: _isAdmin
                ? Column(
              children: [
                Text("All users done: ${_allDone ? "Yes" : "No"}",
                    style: TextStyle(fontSize: 18)),
                SizedBox(height: 12),
                ElevatedButton(
                    onPressed: _allDone ? _callShuffle : null,
                    child: Text("Shuffle & Send Emails")),
                if (_status != null) ...[
                  SizedBox(height: 12),
                  Text(_status!)
                ]
              ],
            )
                : Text("Thanks! 🎄 Your wishlist is submitted.\n"
                "Wait for the Secret Santa surprise!")),
      ),
    );
  }
}

//
// 🎅 SUPER ADMIN LOGIN + DASHBOARD
//
class SuperAdminLoginPage extends StatefulWidget {
  @override
  State<SuperAdminLoginPage> createState() => _SuperAdminLoginPageState();
}

class _SuperAdminLoginPageState extends State<SuperAdminLoginPage> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _loginAndFetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final callable = FirebaseFunctions.instance
          .httpsCallable('getAssignmentsForSuperAdmin');

      final res = await callable.call({
        'username': _userCtrl.text.trim(),
        'password': _passCtrl.text.trim(),
      });

      final data = res.data as Map<String, dynamic>;
      final List assignments = data['assignments'] ?? [];

      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SuperAdminDashboard(assignments: assignments)));
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
                image: AssetImage("assets/images/background.png"),
                fit: BoxFit.cover),
          ),
          child: Center(
            child: Card(
              color: Colors.white.withOpacity(0.85),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text("Super Admin Login 🎅",
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  TextField(
                      controller: _userCtrl,
                      decoration:
                      InputDecoration(labelText: "Username (Samara805589)")),
                  TextField(
                      controller: _passCtrl,
                      decoration: InputDecoration(labelText: "Password"),
                      obscureText: true),
                  SizedBox(height: 12),
                  if (_error != null)
                    Text(_error!, style: TextStyle(color: Colors.red)),
                  ElevatedButton(
                      onPressed: _loading ? null : _loginAndFetch,
                      child: _loading
                          ? CircularProgressIndicator()
                          : Text("Login")),
                ]),
              ),
            ),
          ),
        ));
  }
}

class SuperAdminDashboard extends StatelessWidget {
  final List assignments;
  SuperAdminDashboard({required this.assignments});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Assignments 🎁'),
        backgroundColor: Colors.red.shade700,
      ),
      body: Container(
        decoration: BoxDecoration(
            image: DecorationImage(
                image: AssetImage("assets/images/background.png"),
                fit: BoxFit.cover)),
        child: assignments.isEmpty
            ? Center(child: Text("No assignments found"))
            : ListView.builder(
          itemCount: assignments.length,
          itemBuilder: (ctx, i) {
            final a = Map<String, dynamic>.from(assignments[i]);
            final giver = a['giverName'] ?? a['giverUid'];
            final receiver = a['receiverName'] ?? a['receiverUid'];
            final wishlist = a['receiverWishlist'] ?? '';

            return Card(
              child: ListTile(
                title: Text("$giver → $receiver"),
                subtitle: wishlist.isNotEmpty
                    ? Text(wishlist)
                    : Text("(no wishlist)"),
              ),
            );
          },
        ),
      ),
    );
  }
}