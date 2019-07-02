# Changelog
All notable changes to this project will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.2.0 (1)
- twitter screen - added progress indicator when the screen is initially loading
- settings screen - added "How to use Lane Breach" action which takes the user to a web help screen; dismiss keyboard if user touches anywhere on the screen
- new report screen - make sure that we keep the picker in sync with the current category (this is only used after previously-uploaded report's category is reset)
- fix bug where the last character of a user-entered description would not be submitted to 311
- shrink images more than 500px wide to make 'em smaller for uploading
- added imageSourceCamera (true/false) and imageTimeDelta (natural log of time since the picture was taken in seconds) to NetworkManagerSuccess events
- added user notifications after a report is uploaded (including a new optional permission)
- new app icons

## 1.1.0 (1)
- permissions screen - new screen that replaces random permission popups during app launch and makes it easier (in theory) to recover from a revoked permission while the app is running
- new report screen - added 1/2/4X zoom function; added white shadows to black icons so they're easier to see at night; hide cursor on text field when category picker is showing; moved Other to the top of the list.
- twitter screen - new screen that shows @EverySF311Bike's feed with the user's reports marked with a star
- always prepend [Other] before submitted descriptions if a category is not picked
- switch to custom Fabric events to report successful report delivery to 311

## 1.0.0 (12)
- change deployment target to iOS 11 (from 11.4)
- new report screen - don't allow changing the flash mode if the device doesn't support it otherwise start with the flash off; (grudgingly) accept the 3rd location if our accuracy requirement isn't met as long as it's 100m or better.
- settings screen - change the server switch action to be long-press; tweak text/positions to look better on smaller screens.

## 1.0.0 (10)
- new report screen - update the location icon based on having captured a valid location or the image having a location

## 1.0.0 (9)
- updated map style to point to the latest iOS mapbox style
- settings screen - fixed bug where the fields were not updated unless the user pressed return after changing each one

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
