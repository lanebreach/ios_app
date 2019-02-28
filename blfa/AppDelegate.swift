//
//  AppDelegate.swift
//  blfa
//
//  Created by Dale Low on 10/3/18.
//  Copyright © 2018 Dale Low. All rights reserved.
//

import AWSDynamoDB
import AWSS3
import MapKit
import Mapbox
import UIKit

let kUserDefaultsEmailKey = "com.blfa.email"
let kUserDefaultsNameKey = "com.blfa.name"
let kUserDefaultsPhoneKey = "com.blfa.phone"
let kUserDefaultsUsingDevServerKey = "com.blfa.use-dev-server-key"

enum MockTestSetting {
    case setMockReports
    case useMockUpload
    case showTwinPeaks
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    // all settings below should be set to false for the production release
    class func getMockTestEnable(for setting: MockTestSetting) -> Bool {
        switch setting {
        case .setMockReports:   return false
        case .useMockUpload:    return false
        case .showTwinPeaks:    return false
        }
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
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
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
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
}

