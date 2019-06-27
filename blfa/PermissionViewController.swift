//
//  PermissionViewController.swift
//  blfa
//
//  Created by Dale Low on 4/4/19.
//  Copyright © 2019 Dale Low. All rights reserved.
//

import AVFoundation
import CoreLocation
import Foundation
import Photos
import UIKit
import UserNotifications

enum PermissionButtonType {
    case gotoSettings
    case cameraPermission
    case photosPermission
    case locationPermission
    case notificationsPermission
}

class PermissionViewController: UIViewController, CLLocationManagerDelegate {
    @IBOutlet weak var permissionLabel: UILabel!
    @IBOutlet weak var permissionImageView: UIImageView!
    @IBOutlet weak var permissionButton: UIButton!

    var permissionButtonType: PermissionButtonType?
    var locationManager = CLLocationManager()

    //MARK:- Lifecycle
    override func viewDidLoad() {
        assert(PermissionViewController.needOneOrMorePermissions(includeOptional: true))
        
        permissionButton.backgroundColor = UIColor.white
        permissionButton.layer.cornerRadius = 10
        permissionButton.clipsToBounds = true

        askForPermissionIfNeeded(includeOptional: true)

        // when we foregound, recheck the needed permissions
        NotificationCenter.default.addObserver(forName: NSNotification.Name.UIApplicationWillEnterForeground, object: nil, queue: nil) { (_) in
            self.askForPermissionIfNeeded(includeOptional: true)
        }
    }
    
    //MARK:- Internal methods
    class func getPermissionStatus(includeOptional: Bool) -> (cameraStatus: Bool, photosStatus: Bool, locationStatus: Bool, notificationStatus: Bool) {
        // AVCaptureDevice
//        case notDetermined
//        Explicit user permission is required for media capture, but the user has not yet granted or denied such permission.
//        case restricted
//        The user is not allowed to access media capture devices.
//        case denied
//        The user has explicitly denied permission for media capture.
//        case authorized

        // PHPhotoLibrary
//        case notDetermined
//        Explicit user permission is required for photo library access, but the user has not yet granted or denied such permission.
//        case restricted
//        Your app is not authorized to access the photo library, and the user cannot grant such permission.
//        case denied
//        The user has explicitly denied your app access to the photo library.
//        case authorized
//        The user has explicitly granted your app access to the photo library.

        // CLLocationManager
//        case CLLocationManager
//        The user has not yet made a choice regarding whether this app can use location services.
//        case restricted
//        This app is not authorized to use location services.
//        case denied
//        The user explicitly denied the use of location services for this app or location services are currently disabled in Settings.
//        case authorizedAlways
//        This app is authorized to start location services at any time.
//        case authorizedWhenInUse
        
        // UNUserNotificationCenter - OPTIONAL
//        case notDetermined
//        The user hasn't yet made a choice about whether the app is allowed to schedule notifications.
//        case denied
//        The app isn't authorized to schedule or receive notifications.
//        case authorized
//        The app is authorized to schedule or receive notifications.
//        case provisional
//        The application is provisionally authorized to post noninterruptive user notifications.

        var userNotificationsAuthorized = false
        
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        UNUserNotificationCenter.current().getNotificationSettings { (settings) in
            userNotificationsAuthorized = (settings.authorizationStatus == .authorized)
            dispatchGroup.leave()
        }
        
        dispatchGroup.wait()
        return (AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
            PHPhotoLibrary.authorizationStatus() == PHAuthorizationStatus.authorized,
            CLLocationManager.locationServicesEnabled() == true && (CLLocationManager.authorizationStatus() == .authorizedAlways ||
                CLLocationManager.authorizationStatus() == .authorizedWhenInUse),
            includeOptional ? userNotificationsAuthorized : true    /* user notifs are optional */
        )
    }
    
    // stop when we find something that we need
    func askForPermissionIfNeeded(includeOptional: Bool) {
        let (cameraStatus, photosStatus, locationStatus, notificationStatus) = PermissionViewController.getPermissionStatus(includeOptional: includeOptional)

        let labelTitle = "Welcome to Lane Breach!"
        let labelPrefix = labelTitle + "\n\nLane Breach makes it easy to report bike lane blockages to San Francisco's 311 service."
        let labelDeniedSuffix = "\n\nYou need to enable access for this app in Settings."
        let labelRestrictedSuffix = "\n\nUsage of this function is disabled on your device. Check restrictions or parental controls in Settings."
        
        var hint: String?
        defer {
            if let hint = hint {
                let attributedHint = NSMutableAttributedString(string: hint)
                if let titleRange = hint.range(of: labelTitle) {
                    attributedHint.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 24), range: NSRange(titleRange, in: hint))
                }
                permissionLabel.attributedText = attributedHint
            }
        }
        
        // default button action
        permissionButtonType = .gotoSettings
        permissionButton.setTitle("Go to Settings", for: UIControlState.normal)

        if !cameraStatus {
            hint = labelPrefix + "\n\nWe use your camera to allow you to take pictures of lane blockages."

            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                assertionFailure()
            case .notDetermined:
                permissionButtonType = .cameraPermission
                permissionButton.setTitle("Grant Camera Access", for: UIControlState.normal)
            case .denied:
                hint! += labelDeniedSuffix
            case .restricted:
                hint! += labelRestrictedSuffix
            }
            
            permissionImageView.image = UIImage(named: "camera_icon")
            return
        }

        if !photosStatus {
            hint = labelPrefix + "\n\nWe allow importing photos from your library and save photos that you take to the camera roll."
            
            switch PHPhotoLibrary.authorizationStatus() {
            case .authorized:
                assertionFailure()
            case .notDetermined:
                permissionButtonType = .photosPermission
                permissionButton.setTitle("Grant Access to Photos", for: UIControlState.normal)
            case .denied:
                hint! += labelDeniedSuffix
            case .restricted:
                hint! += labelRestrictedSuffix
            }
            
            permissionImageView.image = UIImage(named: "library_icon")
            return
        }

        if !locationStatus {
            hint = labelPrefix + "\n\nWe need your location to post the lane blockage report to SF 311."
            if !CLLocationManager.locationServicesEnabled() {
                hint! += "\n\nYou need to turn on Location Services. Go to Settings, tap back, then go to Privacy."
            } else {
                switch CLLocationManager.authorizationStatus() {
                case .authorizedAlways, .authorizedWhenInUse:
                    assertionFailure()
                case .notDetermined:
                    permissionButtonType = .locationPermission
                    permissionButton.setTitle("Allow location monitoring", for: UIControlState.normal)
                case .denied:
                    hint! += labelDeniedSuffix
                case .restricted:
                    hint! += labelRestrictedSuffix
                }
            }
            
            permissionImageView.image = UIImage(named: "location_icon")
            return
        }
        
        if !notificationStatus {
            hint = labelPrefix + "\n\nWe use notifications to inform you when reports have been uploaded. This is optional."
            
            var authorizationStatus: UNAuthorizationStatus = .denied
            let dispatchGroup = DispatchGroup()
            dispatchGroup.enter()
            UNUserNotificationCenter.current().getNotificationSettings { (settings) in
                authorizationStatus = settings.authorizationStatus
                dispatchGroup.leave()
            }
            
            dispatchGroup.wait()

            switch authorizationStatus {
            case .authorized:
                assertionFailure()
            case .notDetermined, .provisional:
                permissionButtonType = .notificationsPermission
                permissionButton.setTitle("Allow notifications", for: UIControlState.normal)
            case .denied:
                hint! += labelDeniedSuffix
            }
            
            /* user notifs are optional */
            if authorizationStatus != .denied {
                permissionImageView.image = UIImage(named: "notifications_icon")
                return
            }
        }

        // all done!
        self.dismiss(animated: true)
    }

    class func needOneOrMorePermissions(includeOptional: Bool) -> Bool {
        let (p1, p2, p3, p4) = getPermissionStatus(includeOptional: includeOptional)

        return !p1 || !p2 || !p3 || !p4
    }

    //MARK:- Event Handlers
    @IBAction func permissionButtonPressed() {
        guard let permissionButtonType = permissionButtonType else {
            assertionFailure()
            return
        }
        
        switch permissionButtonType {
        case .cameraPermission:
            AVCaptureDevice.requestAccess(for: .video) { success in
                DispatchQueue.main.async {
                    self.askForPermissionIfNeeded(includeOptional: true)
                }
            }
        case .locationPermission:
            locationManager.requestWhenInUseAuthorization()
            locationManager.delegate = self
        case .photosPermission:
            PHPhotoLibrary.requestAuthorization { (status) in
                DispatchQueue.main.async {
                    self.askForPermissionIfNeeded(includeOptional: true)
                }
            }
        case .notificationsPermission:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { (result, error) in
                DispatchQueue.main.async {
                    self.askForPermissionIfNeeded(includeOptional: true)
                }
            }
        case .gotoSettings:
            AppDelegate.gotoAppSettings()
        }
    }

    //MARK:- CLLocationManagerDelegate methods
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        self.askForPermissionIfNeeded(includeOptional: true)
    }
}
