/// App text in English and Hindi.
///
/// Keys are the English source strings, the same convention Frappe's
/// Translation list uses. Lookup order: a Translation saved on the server (so
/// a reviewer can fix wording in Desk without a new release), then the Hindi
/// bundled here, then English.
///
/// The Hindi below is a first draft and must be reviewed by a native speaker
/// before the Play Store release.
library;

typedef ServerLookup = Map<String, String> Function(String lang);

class Strings {
  static String uiLang = 'en';
  static ServerLookup? server;

  static String t(String en, {String? lang, List<Object>? args}) {
    final l = lang ?? uiLang;
    var out = en;
    if (l != 'en') {
      final fromServer = server?.call(l)[en];
      out = (fromServer != null && fromServer.isNotEmpty) ? fromServer : (_bundled[l]?[en] ?? en);
    }
    if (args != null) {
      for (var i = 0; i < args.length; i++) {
        out = out.replaceAll('{$i}', '${args[i]}');
      }
    }
    return out;
  }

  static const languages = {'en': 'English', 'hi': 'हिन्दी'};

  static const Map<String, Map<String, String>> _bundled = {'hi': _hi};
}

String tr(String en, [List<Object>? args]) => Strings.t(en, args: args);

/// Text shown to the beneficiary follows her language, not the worker's.
String trFor(String lang, String en, [List<Object>? args]) => Strings.t(en, lang: lang, args: args);

const Map<String, String> _hi = {
  // login
  'Sign in': 'साइन इन करें',
  'Organisation address': 'संस्था का पता',
  'e.g. aaroh.frappe.cloud': 'जैसे aaroh.frappe.cloud',
  'User ID': 'यूज़र आईडी',
  'Password': 'पासवर्ड',
  'Could not sign in. Check your user ID and password.': 'साइन इन नहीं हो सका। यूज़र आईडी और पासवर्ड जाँचें।',
  'Could not reach the server. Check the address and your internet.': 'सर्वर तक नहीं पहुँच सके। पता और इंटरनेट जाँचें।',
  'This user is not allowed to use the field app. Ask your admin to add the Mobile User role.':
      'इस यूज़र को फ़ील्ड ऐप की अनुमति नहीं है। एडमिन से Mobile User भूमिका जुड़वाएँ।',
  'Could not start the app: {0}': 'ऐप शुरू नहीं हो सका: {0}',
  'The field app is switched off on this site. In Desk, open Mobile Configuration and tick Enabled.':
      'इस साइट पर फ़ील्ड ऐप बंद है। Desk में Mobile Configuration खोलकर Enabled पर टिक करें।',
  'Frappe Mobile Control is not installed on this site. Ask your admin to install it.':
      'इस साइट पर Frappe Mobile Control इंस्टॉल नहीं है। एडमिन से इंस्टॉल करवाएँ।',
  'The server refused the sign-in: {0}': 'सर्वर ने साइन इन मना किया: {0}',
  'Sign-in failed: {0}': 'साइन इन नहीं हुआ: {0}',
  'Sign out': 'साइन आउट',
  'Sign out and remove all data from this phone?': 'साइन आउट करें और इस फ़ोन से सारा डेटा हटाएँ?',
  '{0} records are not synced yet and will be lost.': '{0} रिकॉर्ड अभी सिंक नहीं हुए हैं और मिट जाएँगे।',
  'Cancel': 'रद्द करें',
  // home
  'Namaste, {0}': 'नमस्ते, {0}',
  '{0} records on this phone': 'इस फ़ोन पर {0} रिकॉर्ड',
  'Sync when you have data': 'डेटा मिलने पर सिंक करें',
  'Everything is signed on the server': 'सब कुछ सर्वर पर हस्ताक्षरित है',
  'Sync': 'सिंक',
  'Syncing…': 'सिंक हो रहा है…',
  'Offline': 'ऑफ़लाइन',
  'Synced': 'सिंक हो गया',
  'Programme': 'कार्यक्रम',
  'Change': 'बदलें',
  'Choose a programme': 'कार्यक्रम चुनें',
  'No programmes yet. Ask your admin to give you access to a programme.':
      'अभी कोई कार्यक्रम नहीं। एडमिन से कार्यक्रम की अनुमति माँगें।',
  'This programme has no published notice yet.': 'इस कार्यक्रम की सूचना अभी प्रकाशित नहीं हुई है।',
  'Take new consent': 'नई सहमति लें',
  'Self, assisted or guardian': 'स्वयं, सहायता से या अभिभावक',
  'Log withdrawal or request': 'वापसी या अनुरोध दर्ज करें',
  'Told in person, slip or letter': 'आमने-सामने, पर्ची या पत्र से',
  'Ask for one more purpose': 'एक और उपयोग के लिए पूछें',
  'Existing beneficiary, new use': 'पुराना लाभार्थी, नया उपयोग',
  'Find beneficiary': 'लाभार्थी खोजें',
  'See consent status offline': 'ऑफ़लाइन सहमति की स्थिति देखें',
  'Needs attention': 'ध्यान दें',
  '{0} records could not be saved on the server. Open to see why.':
      '{0} रिकॉर्ड सर्वर पर सेव नहीं हो सके। कारण देखने के लिए खोलें।',
  'Sync finished': 'सिंक पूरा हुआ',
  'No internet. Records stay safe on this phone.': 'इंटरनेट नहीं है। रिकॉर्ड इस फ़ोन पर सुरक्षित हैं।',
  'Your session has ended. Sign in again to sync.': 'आपका सत्र समाप्त हो गया। सिंक के लिए फिर से साइन इन करें।',
  'App language': 'ऐप की भाषा',
  // principal
  'Step {0} of {1}': 'चरण {0} / {1}',
  'Who is giving consent?': 'सहमति कौन दे रहा है?',
  'Beneficiary ID': 'लाभार्थी आईडी',
  'Leave blank to create one': 'खाली छोड़ें, नई आईडी बनेगी',
  'Name': 'नाम',
  'Mobile (optional)': 'मोबाइल (वैकल्पिक)',
  'Tick all that apply': 'जो लागू हों, उन पर टिक करें',
  'Needs help reading the notice': 'सूचना पढ़ने में मदद चाहिए',
  'Phone is shared in the household': 'फ़ोन घर में साझा है',
  'No phone': 'फ़ोन नहीं है',
  'Under 18 — guardian will consent': '18 से कम — अभिभावक सहमति देंगे',
  'Has a lawful guardian (disability)': 'क़ानूनी अभिभावक हैं (दिव्यांगता)',
  'Language for notice, SMS and calls': 'सूचना, SMS और कॉल की भाषा',
  'Continue': 'आगे बढ़ें',
  'Enter a name': 'नाम लिखें',
  'Enter a 10-digit mobile number, or tick No phone': '10 अंकों का मोबाइल नंबर लिखें, या "फ़ोन नहीं है" पर टिक करें',
  // guardian
  'Who consents on their behalf?': 'उनकी ओर से सहमति कौन देगा?',
  'For {0} · under 18': '{0} के लिए · 18 से कम',
  'For {0} · lawful guardian': '{0} के लिए · क़ानूनी अभिभावक',
  'Guardian type': 'अभिभावक का प्रकार',
  'Parent': 'माता-पिता',
  'Legal guardian': 'क़ानूनी अभिभावक',
  'Family guardian (disability)': 'पारिवारिक अभिभावक (दिव्यांगता)',
  'Court / committee': 'न्यायालय / समिति',
  'Guardian name': 'अभिभावक का नाम',
  'Relation': 'रिश्ता',
  "Guardian's mobile": 'अभिभावक का मोबाइल',
  'Order or authority reference': 'आदेश या प्राधिकरण संदर्भ',
  'Verify the guardian': 'अभिभावक की पुष्टि करें',
  "SMS code to guardian's phone": 'अभिभावक के फ़ोन पर SMS कोड',
  'Signal, no data': 'सिग्नल है, डेटा नहीं',
  'Photo of ID or order': 'पहचान पत्र या आदेश की फ़ोटो',
  'School ID, ration card, court order': 'स्कूल आईडी, राशन कार्ड, न्यायालय आदेश',
  'Profiling and research are hidden for minors. Nothing is processed until the guardian is verified.':
      'नाबालिगों के लिए प्रोफ़ाइलिंग और शोध छिपे हैं। अभिभावक की पुष्टि तक कुछ भी प्रोसेस नहीं होगा।',
  'Continue to notice': 'सूचना पर जाएँ',
  'Guardian verified': 'अभिभावक की पुष्टि हुई',
  'Take photo': 'फ़ोटो लें',
  'Photo saved': 'फ़ोटो सेव हुई',
  // notice
  'Play the full notice': 'पूरी सूचना सुनें',
  'Notice played in full': 'सूचना पूरी सुनाई गई',
  'Why we need this': 'हम यह क्यों ले रहे हैं',
  'What we collect': 'कौन सी जानकारी',
  'Your rights': 'आपके अधिकार',
  'How to withdraw': 'सहमति कैसे वापस लें',
  'Complaints': 'शिकायत',
  'Choices unlock when the notice has played through': 'पूरी सूचना सुनने के बाद आगे बढ़ सकते हैं',
  'Choices unlock when you have read to the end': 'अंत तक पढ़ने के बाद आगे बढ़ सकते हैं',
  'This language has no reviewed notice yet. Read the English notice aloud and explain it.':
      'इस भाषा में समीक्षित सूचना अभी नहीं है। अंग्रेज़ी सूचना पढ़कर समझाएँ।',
  'Data may be sent outside India: {0}': 'डेटा भारत से बाहर भेजा जा सकता है: {0}',
  // purposes
  'What do you agree to?': 'आप किसके लिए हाँ कहते हैं?',
  'Needed for the service': 'सेवा के लिए ज़रूरी',
  'Required': 'ज़रूरी',
  'optional': 'वैकल्पिक',
  'Yes to all': 'सब के लिए हाँ',
  'No to all': 'सब के लिए नहीं',
  'Some uses are not offered to minors.': 'कुछ उपयोग नाबालिगों के लिए नहीं हैं।',
  // evidence
  'Record her consent': 'सहमति दर्ज करें',
  'At least one, plus a witness for assisted consent': 'कम से कम एक, और सहायता वाली सहमति के लिए एक गवाह',
  'She chose on this phone herself': 'उन्होंने ख़ुद इस फ़ोन पर चुना',
  'No help was needed to read or choose': 'पढ़ने या चुनने में मदद नहीं लगी',
  'Voice — record her “haan”': 'आवाज़ — उनकी “हाँ” रिकॉर्ड करें',
  'Tap to record': 'रिकॉर्ड करने के लिए दबाएँ',
  'Recording… tap to stop': 'रिकॉर्ड हो रहा है… रोकने के लिए दबाएँ',
  '{0} saved': '{0} सेव हुआ',
  'Checking what she said…': 'देख रहे हैं उन्होंने क्या कहा…',
  'Sounds like yes': 'हाँ जैसा लगा',
  'Sounds like no': 'ना जैसा लगा',
  'Not clear — listen again and decide': 'साफ़ नहीं — फिर से सुनें और तय करें',
  'Heard: “{0}”': 'सुना: “{0}”',
  'You decide; this is only a hint.': 'फ़ैसला आपका है; यह सिर्फ़ एक संकेत है।',
  'Thumbprint on slip': 'पर्ची पर अँगूठे का निशान',
  'Photo of the impression': 'निशान की फ़ोटो',
  'Tap to capture': 'फ़ोटो लेने के लिए दबाएँ',
  'Witness name': 'गवाह का नाम',
  'Relation / role': 'रिश्ता / भूमिका',
  'I played the full notice in her language, answered her questions, and she chose freely. Nothing was pre-selected.':
      'मैंने पूरी सूचना उनकी भाषा में सुनाई, उनके सवालों के जवाब दिए, और उन्होंने अपनी मर्ज़ी से चुना। कुछ भी पहले से चुना हुआ नहीं था।',
  'Continue to verification': 'पुष्टि पर जाएँ',
  'Microphone permission is needed to record.': 'रिकॉर्ड करने के लिए माइक्रोफ़ोन की अनुमति चाहिए।',
  // verify
  'Verify the phone': 'फ़ोन की पुष्टि करें',
  'SMS code from this phone': 'इस फ़ोन से SMS कोड',
  'Opens your SMS app with a code for her number. She reads it back.':
      'उनके नंबर के लिए कोड के साथ SMS ऐप खुलेगा। वे कोड पढ़कर बताएँगी।',
  'Best now': 'अभी सबसे अच्छा',
  'Confirm later': 'बाद में पुष्टि',
  'SMS after sync: “Reply STOP to withdraw”.': 'सिंक के बाद SMS: “वापस लेने के लिए STOP भेजें”।',
  'No phone — evidence only': 'फ़ोन नहीं — केवल सबूत',
  'Uses the voice, thumbprint and witness.': 'आवाज़, अँगूठे के निशान और गवाह का उपयोग।',
  'Open SMS app with code': 'कोड के साथ SMS ऐप खोलें',
  'Code they read back': 'वे जो कोड पढ़कर बताएँ',
  'Verify and save': 'पुष्टि करें और सेव करें',
  'Save': 'सेव करें',
  'Code matched': 'कोड मेल खाता है',
  'The server is under maintenance. Your records stay safe on this phone.':
      'सर्वर पर रखरखाव चल रहा है। आपके रिकॉर्ड इस फ़ोन पर सुरक्षित हैं।',
  'Please update the app': 'कृपया ऐप अपडेट करें',
  'The field app is paused': 'फ़ील्ड ऐप रोका गया है',
  'This version is no longer supported. Records on this phone are kept.':
      'यह संस्करण अब समर्थित नहीं है। इस फ़ोन के रिकॉर्ड सुरक्षित रहेंगे।',
  'Update': 'अपडेट करें',
  'Opening securely…': 'सुरक्षित रूप से खुल रहा है…',
  'This phone was reported lost. Its data has been deleted. Sign in again to use it.':
      'इस फ़ोन को खोया हुआ बताया गया था। इसका डेटा मिटा दिया गया है। इस्तेमाल के लिए फिर से साइन इन करें।',
  'Too many wrong PINs. This phone was signed out and its data deleted.':
      'बहुत बार ग़लत PIN। यह फ़ोन साइन आउट हो गया और इसका डेटा मिटा दिया गया।',
  'The PINs did not match. Start again.': 'PIN मेल नहीं खाए। फिर से शुरू करें।',
  'Wrong PIN. {0} tries left.': 'ग़लत PIN। {0} कोशिशें बाकी।',
  'Choose a 4-digit PIN for this app': 'इस ऐप के लिए 4 अंकों का PIN चुनें',
  'Enter the PIN again': 'PIN फिर से डालें',
  'Enter your PIN': 'अपना PIN डालें',
  'The app locks when you leave it for 5 minutes. Names and evidence stay protected.':
      'ऐप छोड़ने के 5 मिनट बाद ऐप लॉक हो जाता है। नाम और सबूत सुरक्षित रहते हैं।',
  'Forgot PIN? Sign out': 'PIN भूल गए? साइन आउट करें',
  'Send receipt by SMS': 'रसीद SMS से भेजें',
  'Opens your SMS app with their receipt. You tap Send.': 'उनकी रसीद के साथ SMS ऐप खुलेगा। आप Send दबाएँ।',
  'Anumati receipt {0}. Agreed: {1}. To withdraw: SMS STOP {0}, give a missed call, or tell any worker.':
      'अनुमति रसीद {0}। सहमति: {1}। वापस लेने के लिए: SMS में STOP {0} भेजें, मिस्ड कॉल दें, या किसी भी कार्यकर्ता को बताएँ।',
  'From the office': 'दफ़्तर से',
  'Record the guardian saying yes (optional when the guardian is verified)':
      'अभिभावक की “हाँ” रिकॉर्ड करें (अभिभावक की पुष्टि हो चुकी हो तो वैकल्पिक)',
  'Witness name (optional)': 'गवाह का नाम (वैकल्पिक)',
  "Guardian's mobile (optional)": 'अभिभावक का मोबाइल (वैकल्पिक)',
  'Listen to the notice': 'सूचना सुनें',
  'Stop': 'रोकें',
  'Phone voice · the notice is read aloud by this phone': 'फ़ोन की आवाज़ · यह फ़ोन सूचना पढ़कर सुनाएगा',
  'Reviewed recording': 'समीक्षित रिकॉर्डिंग',
  'Natural voice · Powered by Sarvam AI': 'प्राकृतिक आवाज़ · Sarvam AI द्वारा',
  'This phone has no voice for this language. Read the notice aloud yourself.':
      'इस फ़ोन में इस भाषा की आवाज़ नहीं है। सूचना ख़ुद पढ़कर सुनाएँ।',
  'That code does not match. Try again.': 'कोड मेल नहीं खाता। फिर से कोशिश करें।',
  'Too many wrong codes. Choose another method.': 'बहुत बार ग़लत कोड। कोई और तरीका चुनें।',
  'Your Anumati consent code is {0}. Read it back to the field worker.':
      'आपका अनुमति सहमति कोड {0} है। इसे फ़ील्ड कार्यकर्ता को पढ़कर बताएँ।',
  'This programme allows none of the methods available on the phone.':
      'यह कार्यक्रम फ़ोन पर उपलब्ध किसी भी तरीके की अनुमति नहीं देता।',
  // receipt
  'Saved on this phone': 'इस फ़ोन पर सेव हुआ',
  'Signed and chained when this phone syncs': 'फ़ोन सिंक होने पर हस्ताक्षरित और जुड़ जाएगा',
  'Consent code — write it on their slip': 'सहमति कोड — इसे उनकी पर्ची पर लिखें',
  'Granted': 'हाँ कहा',
  'Refused': 'मना किया',
  'Verified by': 'पुष्टि',
  'Device SMS code': 'फ़ोन से SMS कोड',
  'Confirm later (SMS after sync)': 'बाद में पुष्टि (सिंक के बाद SMS)',
  'Evidence only': 'केवल सबूत',
  'Tell them: SMS STOP with this code, a missed call, or tell any worker to withdraw.':
      'उन्हें बताएँ: इस कोड के साथ SMS में STOP, मिस्ड कॉल, या किसी भी कार्यकर्ता को बताकर सहमति वापस ले सकते हैं।',
  'Done — next beneficiary': 'हो गया — अगला लाभार्थी',
  'Nothing': 'कुछ नहीं',
  // withdraw
  'Log what they asked for': 'उन्होंने क्या माँगा, दर्ज करें',
  'Withdrawal or request': 'वापसी या अनुरोध',
  'How did it reach you?': 'यह आप तक कैसे पहुँचा?',
  'In person': 'आमने-सामने',
  'Paper slip': 'काग़ज़ की पर्ची',
  'Letter': 'पत्र',
  'Consent code, name or ID': 'सहमति कोड, नाम या आईडी',
  'Found on this phone': 'इस फ़ोन पर मिला',
  'Not on this phone. It goes to the office inbox with the code.':
      'इस फ़ोन पर नहीं है। यह कोड के साथ दफ़्तर के इनबॉक्स में जाएगा।',
  'What do they want?': 'वे क्या चाहते हैं?',
  'Stop all optional uses': 'सभी वैकल्पिक उपयोग रोकें',
  'Stop only: {0}': 'केवल रोकें: {0}',
  'Delete my data': 'मेरा डेटा हटाएँ',
  'See or correct my data': 'मेरा डेटा देखें या सुधारें',
  'Complaint': 'शिकायत',
  'Saved on this phone. It takes effect now and reaches the office on sync.':
      'इस फ़ोन पर सेव हुआ। यह अभी लागू है और सिंक पर दफ़्तर पहुँचेगा।',
  'Paper slip number (optional)': 'पर्ची नंबर (वैकल्पिक)',
  // add purpose
  'Later visit · {0}': 'बाद की मुलाक़ात · {0}',
  'Already decided — not asked again': 'पहले ही तय — दोबारा नहीं पूछा जाएगा',
  'A guardian must consent for this person. Take a new consent with the guardian.':
      'इनके लिए अभिभावक को सहमति देनी होगी। अभिभावक के साथ नई सहमति लें।',
  'Notice': 'सूचना',
  'Nothing new to ask on this notice.': 'इस सूचना में पूछने के लिए कुछ नया नहीं है।',
  'New use': 'नया उपयोग',
  'Read this part of the notice to them': 'सूचना का यह हिस्सा उन्हें सुनाएँ',
  'I have read it to them': 'मैंने उन्हें सुना दिया',
  'Yes': 'हाँ',
  'No': 'नहीं',
  'Verified with the same method as last time: {0}.': 'पिछली बार वाले तरीके से पुष्टि: {0}।',
  'Pick a beneficiary on this phone': 'इस फ़ोन पर मौजूद लाभार्थी चुनें',
  // find
  'Search by name, ID or code': 'नाम, आईडी या कोड से खोजें',
  'No one on this phone matches.': 'इस फ़ोन पर कोई मेल नहीं खाता।',
  'granted': 'हाँ',
  'refused': 'मना',
  'withdrawn': 'वापस लिया',
  'not asked': 'नहीं पूछा',
  'waiting to sync': 'सिंक बाकी',
  // sync issues
  'Records that need attention': 'जिन रिकॉर्ड पर ध्यान देना है',
  'Try again': 'फिर से कोशिश करें',
  'Discard': 'हटा दें',
  'Discard this record? It was never saved on the server.': 'यह रिकॉर्ड हटाएँ? यह सर्वर पर कभी सेव नहीं हुआ।',

  // three-screen consent journeys
  '(optional)': '(वैकल्पिक)',
  '0 of 1': '0 में से 1',
  'About the person': 'व्यक्ति के बारे में',
  'Agreed: {0}': 'हाँ: {0}',
  'An SMS goes to {0} after sync: “Reply STOP to withdraw”.':
      'सिंक के बाद {0} पर SMS जाएगा: “वापस लेने के लिए STOP भेजें”।',
  'Back': 'पीछे',
  'Born in {0}: already 18. Choose “The person, for themself”.':
      'जन्म {0} में: 18 साल पूरे। “व्यक्ति, अपने लिए” चुनें।',
  'Both needed: the phone check and their recorded yes.': 'दोनों ज़रूरी: फ़ोन की जाँच और उनकी रिकॉर्ड की हुई हाँ।',
  "Can't get the code now? Confirm later by SMS": 'अभी कोड नहीं मिल रहा? बाद में SMS से पुष्टि करें',
  'Checking what was said…': 'जाँच रहे हैं कि क्या कहा गया…',
  "Child's name": 'बच्चे का नाम',
  "Child's year of birth": 'बच्चे के जन्म का साल',
  'Choices unlock when the whole notice has been heard or read': 'पूरी सूचना सुनने या पढ़ने के बाद ही चुनाव खुलेंगे',
  'Choose for each use': 'हर उपयोग के लिए चुनें',
  'Confirm and save': 'पुष्टि करें और सेव करें',
  "Consent can't be taken yet": 'अभी सहमति नहीं ली जा सकती',
  'Enter a 10-digit mobile number, or choose No': '10 अंकों का मोबाइल नंबर डालें, या ‘नहीं’ चुनें',
  "Enter the child's year of birth, e.g. {0}": 'बच्चे के जन्म का साल डालें, जैसे {0}',
  'Enter the name': 'नाम डालें',
  "For an adult who can't decide alone, only a guardian appointed by a court or the Local Level Committee can give consent.":
      'जो वयस्क खुद फ़ैसला नहीं कर सकते, उनके लिए केवल अदालत या स्थानीय स्तर समिति द्वारा नियुक्त अभिभावक ही सहमति दे सकते हैं।',
  "For {0} · adult who can't decide alone": '{0} के लिए · वयस्क जो खुद फ़ैसला नहीं कर सकते',
  'Guardian appointed by': 'अभिभावक किसने नियुक्त किया',
  "Guardian's details": 'अभिभावक का विवरण',
  "Guardian's name": 'अभिभावक का नाम',
  'I have read the whole notice to them': 'मैंने उन्हें पूरी सूचना पढ़कर सुना दी',
  "I played the full notice in the person's language, answered their questions, and they chose freely. Nothing was pre-selected.":
      'मैंने व्यक्ति की भाषा में पूरी सूचना सुनाई, उनके सवालों के जवाब दिए, और उन्होंने अपनी मर्ज़ी से चुना। कुछ भी पहले से चुना नहीं था।',
  'I played the full notice to the guardian, answered their questions, and they chose freely. Nothing was pre-selected.':
      'मैंने अभिभावक को पूरी सूचना सुनाई, उनके सवालों के जवाब दिए, और उन्होंने अपनी मर्ज़ी से चुना। कुछ भी पहले से चुना नहीं था।',
  'Inform coordinator': 'समन्वयक को बताएँ',
  'Language': 'भाषा',
  'Mobile number': 'मोबाइल नंबर',
  'More: phone shared in the household': 'और: घर में साझा फ़ोन',
  'Needed because the notice was read to them': 'ज़रूरी, क्योंकि सूचना उन्हें पढ़कर सुनाई गई',
  "Needs help reading: at the end you record their “haan” or thumbprint and a witness's name, and check their phone by SMS code.":
      'पढ़ने में मदद चाहिए: आख़िर में उनकी “हाँ” या अँगूठे का निशान और गवाह का नाम दर्ज करें, और SMS कोड से उनका फ़ोन जाँचें।',
  "No phone and needs help reading: at the end you record their “haan” or thumbprint and a witness's name. They get a paper slip with their code.":
      'फ़ोन नहीं और पढ़ने में मदद चाहिए: आख़िर में उनकी “हाँ” या अँगूठे का निशान और गवाह का नाम दर्ज करें। उन्हें कोड वाली पर्ची मिलेगी।',
  "No phone or reading questions for the child. The parent's mobile is asked on the next screen, where it is verified.":
      'बच्चे से फ़ोन या पढ़ने के सवाल नहीं। माता/पिता का मोबाइल अगली स्क्रीन पर पूछा और जाँचा जाएगा।',
  'No phone: at the end you record their “haan” or a photo of their signature or thumbprint. They get a paper slip with their code.':
      'फ़ोन नहीं: आख़िर में उनकी “हाँ” या उनके हस्ताक्षर या अँगूठे के निशान की फ़ोटो दर्ज करें। उन्हें कोड वाली पर्ची मिलेगी।',
  'No phone? Then the ID photo is required, because it becomes the proof.':
      'फ़ोन नहीं? तब पहचान पत्र की फ़ोटो ज़रूरी है, क्योंकि वही सबूत बनेगी।',
  'No witness: they read the notice themselves.': 'गवाह नहीं: उन्होंने सूचना खुद पढ़ी।',
  "Nothing is saved. Your coordinator gets a note to follow up, without the person's details.":
      'कुछ भी सेव नहीं होगा। आपके समन्वयक को आगे की कार्रवाई के लिए सूचना जाएगी, व्यक्ति के विवरण के बिना।',
  'Notice and choices': 'सूचना और चुनाव',
  'Order number': 'आदेश संख्या',
  "Parent's details": 'माता/पिता का विवरण',
  "Parent's mobile": 'माता/पिता का मोबाइल',
  "Parent's name": 'माता/पिता का नाम',
  "Person's name": 'व्यक्ति का नाम',
  "Photo of the guardian's ID": 'अभिभावक के पहचान पत्र की फ़ोटो',
  "Photo of the guardian's ID (optional)": 'अभिभावक के पहचान पत्र की फ़ोटो (वैकल्पिक)',
  'Photo of the order (optional)': 'आदेश की फ़ोटो (वैकल्पिक)',
  "Photo of the parent's ID": 'माता/पिता के पहचान पत्र की फ़ोटो',
  "Photo of the parent's ID (optional)": 'माता/पिता के पहचान पत्र की फ़ोटो (वैकल्पिक)',
  'Photo of their signature or thumbprint on the slip': 'पर्ची पर उनके हस्ताक्षर या अँगूठे के निशान की फ़ोटो',
  'Read the full notice (data, rights, how to withdraw)': 'पूरी सूचना पढ़ें (डेटा, अधिकार, वापस कैसे लें)',
  'Record their yes · choose at least one': 'उनकी हाँ दर्ज करें · कम से कम एक चुनें',
  'Refused: {0}': 'मना: {0}',
  'Relation (optional)': 'रिश्ता (वैकल्पिक)',
  'Saved': 'सेव हुआ',
  'Some of these are sensitive. The person may choose “Prefer not to say”.':
      'इनमें से कुछ संवेदनशील हैं। व्यक्ति “नहीं बताना चाहते” चुन सकते हैं।',
  'Some uses are not offered for children.': 'कुछ उपयोग बच्चों के लिए नहीं पूछे जाते।',
  'The beneficiary ID is created automatically.': 'लाभार्थी आईडी अपने-आप बनती है।',
  "The family can apply to the Local Level Committee (National Trust) or a court. The person can still be helped today; their data just isn't recorded under consent.":
      'परिवार स्थानीय स्तर समिति (नेशनल ट्रस्ट) या अदालत में आवेदन कर सकता है। व्यक्ति की मदद आज भी हो सकती है; बस उनका डेटा सहमति के तहत दर्ज नहीं होगा।',
  "The guardian's details, their appointment order and their mobile are asked on the next screen.":
      'अभिभावक का विवरण, नियुक्ति आदेश और मोबाइल अगली स्क्रीन पर पूछा जाएगा।',
  "These are listed in the notice under “What we collect”. Reports show only totals, never one person's answers.":
      'ये सूचना में “हम क्या जानकारी लेते हैं” में लिखे हैं। रिपोर्ट में केवल कुल संख्या दिखती है, किसी एक व्यक्ति के जवाब नहीं।',
  'They have read the whole notice': 'उन्होंने पूरी सूचना पढ़ ली',
  'Thumbprint on their slip': 'उनकी पर्ची पर अँगूठे का निशान',
  'To save: {0}': 'सेव करने के लिए: {0}',
  'Use a code now': 'अभी कोड से जाँचें',
  'Used only to ask for fresh consent when the child turns 18.':
      'केवल बच्चे के 18 साल का होने पर नई सहमति माँगने के लिए।',
  'Uses that need a phone are not offered.': 'जिन उपयोगों के लिए फ़ोन चाहिए, वे नहीं पूछे गए।',
  'Verify the parent': 'माता/पिता की पुष्टि करें',
  'Verify their phone': 'उनका फ़ोन जाँचें',
  'Voice: their “haan”': 'आवाज़: उनकी “हाँ”',
  'Who is consenting?': 'सहमति कौन दे रहे हैं?',
  'Witness (needed because the notice was read to them)': 'गवाह (ज़रूरी, क्योंकि सूचना उन्हें पढ़कर सुनाई गई)',
  'Your coordinator will be told. Nothing about the person was saved.':
      'आपके समन्वयक को बताया जाएगा। व्यक्ति के बारे में कुछ भी सेव नहीं हुआ।',
  "a photo of the guardian's ID (no phone)": 'अभिभावक के पहचान पत्र की फ़ोटो (फ़ोन नहीं)',
  'a voice “haan” or a photo': 'आवाज़ में “हाँ” या फ़ोटो',
  'answer the required questions': 'ज़रूरी सवालों के जवाब',
  'needs help reading': 'पढ़ने में मदद चाहिए',
  'no phone': 'फ़ोन नहीं',
  'play the whole notice': 'पूरी सूचना सुनाएँ',
  'the SMS code': 'SMS कोड',
  'the name': 'नाम',
  'a 10-digit mobile number': '10 अंकों का मोबाइल नंबर',
  'the order number': 'आदेश संख्या',
  'the relation': 'रिश्ता',
  "the witness's name": 'गवाह का नाम',
  'tick the declaration': 'घोषणा पर टिक करें',
  '✓ Done': '✓ हो गया',
  'The person, for themself': 'व्यक्ति, अपने लिए',
  'A parent, for a child under 18': 'माता/पिता, 18 साल से छोटे बच्चे के लिए',
  "A guardian, for an adult who can't decide alone": 'अभिभावक, ऐसे वयस्क के लिए जो खुद फ़ैसला नहीं कर सकते',
  'Has a mobile phone?': 'मोबाइल फ़ोन है?',
  'Can read the notice?': 'सूचना पढ़ सकते हैं?',
  'Needs help': 'मदद चाहिए',
  'Mother': 'माँ',
  'Father': 'पिता',
  'Other guardian': 'अन्य अभिभावक',
  'Local Level Committee': 'स्थानीय स्तर समिति',
  'Court': 'अदालत',
  'Other authority': 'अन्य प्राधिकरण',
  'No order yet': 'अभी आदेश नहीं',
  'Brother / sister': 'भाई / बहन',
  'Spouse': 'पति / पत्नी',
  'Other': 'अन्य',
  // server-sent codes
  'After Save, a code is sent to this number from the server. They read it out to confirm.':
      'सेव करने के बाद सर्वर इस नंबर पर एक कोड भेजेगा। पुष्टि के लिए वे उसे पढ़कर बताएँगे।',
  'After Save, you can send a code to their phone from the server. They read it out to confirm.':
      'सेव करने के बाद आप सर्वर से उनके फ़ोन पर कोड भिजवा सकते हैं। पुष्टि के लिए वे उसे पढ़कर बताएँगे।',
  'Code from the server (below)': 'सर्वर से भेजा कोड (नीचे)',
  'Code from the server, after Save': 'सेव के बाद सर्वर से भेजा कोड',
  'Code matched · consent confirmed': 'कोड मिल गया · सहमति की पुष्टि हुई',
  'Code sent to {0}. Ask them to read it out.': '{0} पर कोड भेजा गया। उनसे पढ़कर बताने को कहें।',
  "Confirm with a code to the guardian's phone": 'अभिभावक के फ़ोन पर कोड से पुष्टि करें',
  'Confirm with a code to their phone': 'उनके फ़ोन पर कोड से पुष्टि करें',
  'Could not send the code. Try again in a minute.': 'कोड नहीं भेजा जा सका। एक मिनट बाद फिर कोशिश करें।',
  'How this is confirmed: {0}.': 'पुष्टि कैसे होगी: {0}।',
  'No internet now. The consent is saved and will be confirmed later.':
      'अभी इंटरनेट नहीं है। सहमति सेव है और बाद में पुष्टि होगी।',
  'SMS codes are not set up yet. The consent is saved and will be confirmed later.':
      'SMS कोड अभी चालू नहीं हैं। सहमति सेव है और बाद में पुष्टि होगी।',
  'Send a new code': 'नया कोड भेजें',
  'Send code': 'कोड भेजें',
  'That code does not match. {0} tries left.': 'कोड मेल नहीं खाता। {0} कोशिशें बाकी।',
  'The code is sent by the server, not from this phone. They read it out to you.':
      'कोड सर्वर भेजता है, इस फ़ोन से नहीं। वे उसे पढ़कर आपको बताएँगे।',
  'The server did not accept this record. See Sync issues on Home.':
      'सर्वर ने यह रिकॉर्ड नहीं लिया। होम पर सिंक की समस्याएँ देखें।',
  // code route: worker's phone plus voice
  'Check their phone · both needed': 'उनका फ़ोन जाँचें · दोनों ज़रूरी',
  'Code from your phone, with their voice “haan”': 'आपके फ़ोन से कोड, साथ में उनकी आवाज़ में “हाँ”',
  'Confirm later: an SMS goes to {0} after sync.': 'बाद में पुष्टि: सिंक के बाद {0} पर SMS जाएगा।',
  "No internet: the code goes from your phone. The guardian's voice “haan” is needed with it.":
      'इंटरनेट नहीं है: कोड आपके फ़ोन से जाएगा। साथ में अभिभावक की आवाज़ में “हाँ” ज़रूरी है।',
  'No internet: the code goes from your phone. Their voice “haan” is needed with it.':
      'इंटरनेट नहीं है: कोड आपके फ़ोन से जाएगा। साथ में उनकी आवाज़ में “हाँ” ज़रूरी है।',
  "This programme sends codes from your phone. The guardian's voice “haan” is needed with the code.":
      'यह कार्यक्रम कोड आपके फ़ोन से भेजता है। कोड के साथ अभिभावक की आवाज़ में “हाँ” ज़रूरी है।',
  'This programme sends codes from your phone. Their voice “haan” is needed with the code.':
      'यह कार्यक्रम कोड आपके फ़ोन से भेजता है। कोड के साथ उनकी आवाज़ में “हाँ” ज़रूरी है।',
  'Voice: the guardian’s “haan”': 'आवाज़: अभिभावक की “हाँ”',
  'their voice “haan”': 'उनकी आवाज़ में “हाँ”',
};
