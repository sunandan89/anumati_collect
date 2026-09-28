import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'core/version.dart';
import 'widgets/common.dart';
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
          ? const _Opening()
          : !s.signedIn
          ? const LoginScreen()
          : !s.hasPin
          ? const LockScreen(setup: true)
          : s.updateRequired
          ? const _Blocked(update: true)
          : s.blockedReason != null
          ? const _Blocked()
          : const HomeScreen(),
    );
  }
}

/// Shown while the encrypted store opens and the saved session is restored.
class _Opening extends StatelessWidget {
  const _Opening();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: AC.leaf, borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.verified_user_outlined, color: AC.leafInk, size: 34),
            ),
            const SizedBox(height: 16),
            const Text('Anumati Collect', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 12),
            Text(tr('Opening securely…'), style: const TextStyle(color: AC.ink3)),
          ],
        ),
      ),
    );
  }
}

/// Switched off, under maintenance, or older than Mobile Configuration's Minimum App Version.
class _Blocked extends StatelessWidget {
  const _Blocked({this.update = false});
  final bool update;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(update ? Icons.system_update : Icons.pause_circle_outline, size: 56, color: AC.terra),
              const SizedBox(height: 16),
              Text(
                update ? tr('Please update the app') : tr('The field app is paused'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                update
                    ? tr('This version is no longer supported. Records on this phone are kept.')
                    : s.blockedReason ?? '',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (update)
                FilledButton(
                  onPressed: () => launchUrl(Uri.parse(updateUrl), mode: LaunchMode.externalApplication),
                  child: Text(tr('Update')),
                ),
              TextButton(onPressed: s.checkAppStatus, child: Text(tr('Try again'))),
              if (s.pending > 0) Muted(tr('{0} records on this phone', [s.pending])),
            ],
          ),
        ),
      ),
    );
  }
}
