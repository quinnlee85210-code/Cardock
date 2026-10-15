# Cardock platform boundary for file_picker 10.3.10

Source: https://github.com/miguelpruivo/flutter_file_picker, pub.dev package 10.3.10, MIT license (retained in LICENSE).

This private source dependency retains the upstream Dart, Android and macOS runtime files byte-for-byte. The only upstream manifest change removes the iOS plugin registration; the unused iOS implementation and example/test distributions are not included. Web, Windows and Linux Dart implementations are unchanged. UPSTREAM_FILES.json records the original file hashes, including the unmodified manifest hash.

Cardock iOS already routes document import and encrypted backup selection/export through CardockCoreBridge and UIDocumentPickerViewController. It does not call FilePicker on iOS. Registering the upstream native plugin would pull in DKImagePickerController and photo/camera/location APIs even though these product features do not exist. Do not re-enable the plugin for iOS without a deliberate feature/privacy review.

The public Dart API and other platforms are preserved; this app worktree uses the dependency by relative path. Shared Pub caches must not be patched. Updates must recheck upstream hashes, Dart iOS routing tests, generated registration/SPM dependencies and the built Mach-O privacy boundary.
