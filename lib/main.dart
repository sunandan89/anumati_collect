import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart' show FrappeAppGuard;
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'core/version.dart';
import 'screens/home.dart';
import 'screens/lock.dart';
import 'screens/login.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const AnumatiCollect()));
  state.boot();
}

class AnumatiCollect extends StatefulWidget {
  const AnumatiCollect({super.key});
  @override
  State<AnumatiCollect> createState() => _AnumatiCollectState();
}

class _AnumatiCollectState extends State<AnumatiCollect> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = context.read<AppState>();
    if (state == AppLifecycleState.paused) s.appPaused();
    if (state == AppLifecycleState.resumed) s.appResumed();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      // A new navigator when signing in or out, so no screen from the old session stays open.
      key: ValueKey('${s.signedIn}-${s.hasPin}'),
      // The lock covers whatever is open (a half-taken consent stays as it was underneath).
      builder: (context, child) => Stack(
        children: [
          ?child,
          if (s.ready && s.signedIn && s.hasPin && s.locked)
            Positioned.fill(
              child: Navigator(onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => const LockScreen())),
            ),
        ],
      ),
      title: 'Anumati Collect',
      debugShowCheckedModeBanner: false,
      theme: anumatiTheme(),
      locale: Locale(Strings.uiLang),
      supportedLocales: const [Locale('en'), Locale('hi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: !s.ready
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : !s.signedIn
          ? const LoginScreen()
          : !s.hasPin
          ? const LockScreen(setup: true)
          : FrappeAppGuard(
              baseUrl: s.sdk!.baseUrl,
              currentPackageName: packageName,
              currentVersion: appVersion,
              child: const HomeScreen(),
            ),
    );
  }
}
