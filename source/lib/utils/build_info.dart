/// Overwritten by the GitHub Actions workflow at build time with the real
/// commit short-SHA and run number (see build-apk.yml). If you ever see
/// "dev-build (uninjected)" on a real device, it means you're running an
/// APK that did NOT go through the CI pipeline - none of the CI-injected
/// native code (the photo_store MediaStore channel, permissions, etc.)
/// will be present in that build.
const String kBuildId = 'dev-build (uninjected)';
