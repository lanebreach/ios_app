//
//  AppDelegate.swift
//  blfa
//
//  Created by Dale Low on 10/3/18.
//  Copyright © 2018 Dale Low. All rights reserved.
//

import AWSDynamoDB
import AWSS3
import Crashlytics
import Fabric
import MapKit
import Mapbox
import UIKit

let kUserDefaultsEmailKey = "com.blfa.email"
let kUserDefaultsNameKey = "com.blfa.name"
let kUserDefaultsPhoneKey = "com.blfa.phone"
let kUserDefaultsUsingDevServerKey = "com.blfa.use-dev-server-key"
let kUserDefaultsHideTipNewReportMain = "com.blfa.hide-tip-newreport-main"
let kUserDefaultsHideTipNewReportLocation = "com.blfa.hide-tip-newreport-location"
let kUserDefaultsHideTipNewReportFlash = "com.blfa.hide-tip-newreport-flash"

enum TipIdentifier: Int {
    case newReportMain = 1
    case newReportLocation
    case newReportFlash
}

enum MockTestSetting {
    case setMockReports
    case useMockUpload
    case showTwinPeaks
}

enum BrandColorPurpose {
    case main
    case lightMain
    case communityFeedItems
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        Fabric.with([Crashlytics.self])
        
        // credit: https://stackoverflow.com/questions/32111029/download-secure-file-from-s3-server-using-accesskey-and-secretkey
        let credentialsProvider = AWSStaticCredentialsProvider(accessKey: Keys.accessKey, secretKey: Keys.secretKey)
        let configuration = AWSServiceConfiguration(region: .USWest2, credentialsProvider: credentialsProvider)
        AWSServiceManager.default().defaultServiceConfiguration = configuration

        // need a separate config for S3 since the lane-breach bucket is in a different region
        let configurationUSWest1 = AWSServiceConfiguration(region: .USWest1, credentialsProvider: credentialsProvider)
        AWSS3TransferUtility.register(with: configurationUSWest1!, forKey: "USWest1S3TransferUtility")
        
        MGLAccountManager.accessToken = Keys.mapboxKey
        
        if AppDelegate.getMockTestEnable(for: .setMockReports) {
            ReportManager.shared.setMockReports()
        }
        
        print("Using dev server: \(UserDefaults.standard.bool(forKey: kUserDefaultsUsingDevServerKey))")
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        if let _ = self.window?.rootViewController?.presentedViewController as? PermissionViewController {
            // nothing to do if already showing the permissions screen
            return
        }

        /*
            If permissions are needed, show this screen on top of the view hierarchy. This only happens
            when the user changes the permissions when the app is backgrounded (after initially granting
            them). Also, iOS usually kills the app if privacy settings change when the app is backgrounded.
            This code catches the case where it doesn't (this only seems to be the case for location revocation).
         */
        
        if PermissionViewController.needOneOrMorePermissions() {
            if let controller = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "PermissionViewController") as? PermissionViewController {
                if let window = self.window, let rootViewController = window.rootViewController {
                    var currentController = rootViewController
                    while let presentedController = currentController.presentedViewController {
                        currentController = presentedController
                    }
                    currentController.present(controller, animated: true, completion: nil)
                    window.makeKeyAndVisible()
                }
            }
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }
    
    // all settings below should be set to false for the production release
    class func getMockTestEnable(for setting: MockTestSetting) -> Bool {
        switch setting {
        case .setMockReports:   return false
        case .useMockUpload:    return false
        case .showTwinPeaks:    return false
        }
    }

    // helper function to show an alert with optional actions
    class func showSimpleAlertWithOK(vc: UIViewController, _ message: String, button2title: String? = nil,
        button2handler: ((UIAlertAction) -> Void)? = nil) {
        
        let alertFunc: () -> Void = {
            let alert = UIAlertController(title: "Alert", message: message, preferredStyle: UIAlertControllerStyle.alert)
            alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.default, handler: nil))
            if let button2title = button2title,
                let button2handler = button2handler {
                
                alert.addAction(UIAlertAction(title: button2title, style: UIAlertActionStyle.default, handler: button2handler))
            }
            vc.present(alert, animated: true, completion: nil)
        }
        
        if Thread.isMainThread {
            alertFunc()
        } else {
            DispatchQueue.main.async {
                alertFunc()
            }
        }
    }
    
    class func gotoAppSettings() {
        let settingsUrl = NSURL(string:UIApplicationOpenSettingsURLString)
        if let url = settingsUrl {
            UIApplication.shared.open(url as URL, options: [:], completionHandler: nil)
        }
    }

    class func shouldShowTip(id: TipIdentifier) -> Bool {
        switch id {
        case .newReportMain:
            return !UserDefaults.standard.bool(forKey: kUserDefaultsHideTipNewReportMain)
        case .newReportLocation:
            return !UserDefaults.standard.bool(forKey: kUserDefaultsHideTipNewReportLocation)
        case .newReportFlash:
            return !UserDefaults.standard.bool(forKey: kUserDefaultsHideTipNewReportFlash)
        }
    }
    
    class func hideTip(id: TipIdentifier) {
        switch id {
        case .newReportMain:
            UserDefaults.standard.set(true, forKey: kUserDefaultsHideTipNewReportMain)
        case .newReportLocation:
            UserDefaults.standard.set(true, forKey: kUserDefaultsHideTipNewReportLocation)
        case .newReportFlash:
            UserDefaults.standard.set(true, forKey: kUserDefaultsHideTipNewReportFlash)
        }
    }
    
    class func restoreAllTips() {
        UserDefaults.standard.set(false, forKey: kUserDefaultsHideTipNewReportMain)
        UserDefaults.standard.set(false, forKey: kUserDefaultsHideTipNewReportLocation)
        UserDefaults.standard.set(false, forKey: kUserDefaultsHideTipNewReportFlash)
    }
    
    class func brandColor(purpose: BrandColorPurpose) -> UIColor {
        switch purpose {
        case .main:
            return UIColor.fromHex(hex: 0x179876)
        case .lightMain:
            return UIColor.fromHex(hex: 0xdaefe9)
        case .communityFeedItems:
            return UIColor.fromHex(hex: 0x5a5b5d)
        }
    }
}

extension UIColor {
    class func fromHex(hex: UInt32) -> UIColor {
        return UIColor(red: CGFloat(hex >> 16)/255.0,
                       green: CGFloat((hex >> 8) & 0xFF)/255.0,
                       blue: CGFloat(hex & 0xFF)/255.0, alpha: 1.0)
    }
}
