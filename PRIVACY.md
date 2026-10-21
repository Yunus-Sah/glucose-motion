# Privacy and local data

This source repository contains no participant glucose backups, patient identifiers, login tokens or passwords.

In the app, session and event records are saved locally. Cloud readings are cached for up to 30 days separately by shared profile; saved session readings remain until deleted. Login credentials use the iPhone Keychain. The password is not saved by the app. The optional cloud connection sends authentication requests directly to Abbott services. There is no project-operated backend.

Exported JSON backups and comparison images can contain sensitive health information and timestamps. Decide where to store or share them. Keep personal backups outside the source repository. Deleting the app can remove its local files; retain backups before changing installations.
