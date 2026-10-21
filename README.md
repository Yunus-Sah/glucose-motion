# Glucose Motion

An iPhone app that combines glucose readings with meals and exercise. It helps the user understand what happened before, during and after a workout.

Created by **Yunus Emre Sahin**, MSc Sports Technology student at KTH Royal Institute of Technology.

**Research question:** How can continuous glucose monitoring (CGM) data be turned into clear feedback for an athlete?

[References](REFERENCES.md) · [How the feedback works](docs/FEEDBACK.md) · [Privacy and data](PRIVACY.md)

## Main features

- View glucose graphs from the last 15 minutes up to 24 hours.
- Log meals, exercise and fasting with times and notes.
- Add glucose readings from a CSV file, paste them, or enter them by hand.
- Connect to LibreLinkUp to receive readings while the app is open. This connection is unofficial.
- Compare two workouts in one graph, with colours for each session and markers for meals and exercise.
- See start and end glucose, change, minimum, maximum and average.
- Get simple feedback about glucose changes during and after exercise.
- Save a comparison image for a poster and export backups.

## What this project adds

A glucose graph shows how readings change over time. This app also shows when the user ate and exercised. It then explains the observed pattern in words.

For example, it can describe a fall during the first part of a workout, a rise towards the end, or a larger drop after one session than another. It also explains when there is not enough data for a fair comparison.

For this student project, I collected data from two strength-training sessions on myself. This small study shows how the app works. It cannot prove that meal timing caused a difference or that one timing is best. Personal glucose data and login details are not included here.

## Open the app in Xcode

1. Download or clone this repository. Open `GlucoseMotion.xcodeproj` in Xcode.
2. Select the GlucoseMotion target. In Signing & Capabilities, choose your development team and a unique bundle identifier (the app's ID).
3. Select an iPhone with iOS 17 or later and click Run.
4. In Settings, add a demo session. You can also import readings or connect to LibreLinkUp.

The app uses SwiftUI and Swift Charts. It needs no extra Swift packages. This repository contains the Xcode project, not an App Store or TestFlight download.

**If you already have the app:** keep the same development team and app ID when updating it. Export a backup first. The public project has no development team selected.

## LibreLinkUp connection

Use the receiving account that can already see your shared glucose data in the official LibreLinkUp app. Complete any account steps requested by Abbott, then sign in and select your shared profile.

The connection uses Abbott's cloud service. It does not connect directly to the sensor. It is unofficial and may stop working if Abbott changes the service. Updates run while the app is open, not continuously in the background.

The app does not save your password. It stores the login token in the iPhone Keychain, Apple's secure storage. You can still import readings without this connection.

## Limits

This is an experimental app. It has not been medically validated.

It describes glucose measured in interstitial fluid, the fluid between cells. It does not give medical advice, recommend carbohydrate amounts, judge whether fasting is safe, or prove better sports performance.

The app keeps the original reading times. It does not move the readings to correct for sensor or cloud delay. Two sessions are not enough to show that meal timing caused a glucose change.

See the [references](REFERENCES.md) for the research behind the project. This is an independent student project. Abbott and KTH have not endorsed the app.

## Development

Version 1.4.1, build 10. The iPhone project built successfully during development. Checks covered the calculations, meal times, session selection and separation of different profiles. The comparison image was also checked. These checks do not prove that every action works on a real iPhone or that cloud updates are always reliable.

The app was developed with assistance from OpenAI codex.
