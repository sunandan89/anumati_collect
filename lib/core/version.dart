/// Keep in step with pubspec.yaml `version`. Mobile Configuration's Minimum App Version compares to this.
const appVersion = '1.1.0';
const packageName = 'org.anumati.collect';

/// Where 'Update' sends people: the app's Google Play listing. Never a direct APK download (review M7):
/// a test build is installed by the coordinator, not through the app.
const updateUrl = 'https://play.google.com/store/apps/details?id=$packageName';
