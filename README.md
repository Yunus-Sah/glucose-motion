# Glucose Motion

### From wearable glucose data to understandable athlete feedback

A native iPhone prototype that brings glucose readings, meal timing and exercise into one journal. Built by **Yunus Emre Sahin**, MSc Sports Technology, KTH Royal Institute of Technology, for an exploratory N=1 project.

**Research question:** How can continuous glucose monitoring data be transformed into understandable feedback for an athlete?

[References](REFERENCES.md) · [How the feedback works](docs/FEEDBACK.md) · [Privacy and data](PRIVACY.md)

## What the app does

- Displays recent interstitial glucose readings, with graph ranges from 15 minutes to 24 hours.
- Records meals, exercise and fasting with timestamps and notes.
- Imports glucose using CSV, pasted readings or manual entry.
- Optionally receives cloud readings through an **unofficial LibreLinkUp connection** while the app is open.
- Compares two workouts on one timeline aligned to exercise start, with meal markers and a shared glucose scale.
- Calculates first/last exercise readings, change, minimum, maximum and arithmetic mean.
- Describes patterns during exercise and the available follow-up, then explains what can and cannot be inferred.
- Exports a complete comparison image for a research poster and supports local JSON backups.

## Contribution

The prototype adds recorded context and transparent interpretation to a glucose curve. It identifies which session had a rise or fall, when the meal occurred relative to exercise, and whether comparable follow-up data show different endpoint changes. It separates observed differences from hypotheses about their causes.

The exploratory evaluation used two strength-training sessions in one participant. This is a demonstration of the measurement-to-feedback workflow, not a validation of a meal-timing strategy. Personal glucose recordings and account credentials are not included in this repository.

## Run in Xcode

1. Clone or download this repository and open `GlucoseMotion.xcodeproj`.
2. Choose the GlucoseMotion target. Under Signing & Capabilities, select your own development team and a unique bundle identifier.
3. Select an iPhone running iOS 17 or later and Run.
4. Add a demo session in Settings, import readings, or optionally configure LibreLinkUp.

No third-party Swift packages are required. The app uses SwiftUI, Swift Charts, Foundation, Security and CryptoKit. It is an Xcode source project; an App Store/TestFlight release is not supplied.

**Existing installation:** preserve your original signing team and bundle identifier if updating your own installed copy. Back up your records first. The public project intentionally has no development team selected.

## Optional LibreLinkUp connection

Use the receiving account that already sees the shared profile in the official LibreLinkUp app. A valid sharing relationship and completion of any Abbott account steps are required. Select the shared profile after signing in.

This integration is unofficial, depends on Abbott's cloud service, and can stop working if the service changes. It is not direct sensor access, an official public Abbott SDK, or a continuous iOS background service. The password is used for sign-in and is not saved by the app; the session credential is stored in the iPhone Keychain. CSV/manual import remains available.

## Scope

Experimental prototype, not medically validated. Feedback describes recorded interstitial glucose. It does not diagnose, prescribe carbohydrate intake, establish fasting safety, or demonstrate performance optimisation. Recorded timestamps are not shifted to compensate for physiological or cloud delay. Two sessions cannot isolate meal timing as the cause of a difference.

See [References](REFERENCES.md) for the literature and technical sources supporting the project's background and limitations. This student project is not affiliated with or endorsed by Abbott or KTH.

## Development and validation

Version 1.4.1 (build 10). Generic unsigned iPhone build passed during development. Native report rendering and checks covered meal references, reversed selections, profile separation, feedback calculations and unchanged exercise statistics. Full device interaction and service reliability are not established by those checks.

The app was developed with assistance from OpenAI codex.
