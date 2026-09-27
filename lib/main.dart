import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:frappe_mobile_sdk/frappe_mobile_sdk.dart' show FrappeAppGuard;
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'screens/home.dart';
import 'screens/login.dart';

const appVersion = '1.0.0';
const packageName = 'org.anumati.collect';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const AnumatiCollect()));
  state.boot();
}

class AnumatiCollect extends StatelessWidget {
  const AnumatiCollect({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
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
          : FrappeAppGuard(
              baseUrl: s.sdk!.baseUrl,
              currentPackageName: packageName,
              currentVersion: appVersion,
              child: const HomeScreen(),
            ),
    );
  }
}
