# Changelog
All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.0 (8)
- disable token -> service request ID check since it never succeeds and just makes the user wait 2+ seconds more when submitting
- tweak map annotation
- use "background tasks" to improve uploading if the user backgrounds the app in the middle of the action
- treat HTTP 4xx errors as permanent fatal errors (since we get 400 if 311 detects a dupe POST even if we think that the first one failed)
- improve location collection algorithm
- better network error codes for showing to users
- report various stats to Crashlytics as non-fatal errors
- added Crashlytics to track app crashes

## 1.0.0 (7)
- one needs to talk to the prod server when using the prod key

## 1.0.0 (6)
- remember which hints are hidden and add way to restore 'em all. Also added "Commuter Shuttle" as a category.
- added prod API key and a super fancy way to switch between dev and prod
- update map style and add legend
- settings screen - added name/phone number (optional) fields to be submitted with the 311 report if supplied
- new report screen - fix bug where keyboard entry on the settings screen would screw up the vertical position of the data entry box on this screen.
