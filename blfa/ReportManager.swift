//
//  ReportManager.swift
//  blfa
//
//  Created by Dale Low on 2/15/19.
//  Copyright © 2019 Dale Low. All rights reserved.
//

import CoreLocation
import Foundation

class ReportManager {
    static let shared = ReportManager()
    
    func setMockReports() {
        var reports = [[String: Any]]()
        var coord = CLLocationCoordinate2D(latitude: 37.771285, longitude: -122.509315)
        var report = ["date": NSDate(),
                      "lat" : coord.latitude,
                      "long" : coord.longitude,
                      "description": "dutch windmill",
                      "category": "Uber"] as [String : Any]
        reports.append(report)
        coord = CLLocationCoordinate2D(latitude: 37.788052, longitude: -122.407393)
        report = ["date": NSDate(timeIntervalSinceNow: -84600),
                  "lat" : coord.latitude,
                  "long" : coord.longitude,
                  "description": "union square",
                  "category": "Lyft"] as [String : Any]
        reports.append(report)
        coord = CLLocationCoordinate2D(latitude: 37.740694, longitude: -122.443364)
        report = ["date": NSDate(timeIntervalSinceNow: -84600*2),
                  "lat" : coord.latitude,
                  "long" : coord.longitude,
                  "description": "glen park",
                  "category": "Lyft"] as [String : Any]
        reports.append(report)
        
        UserDefaults.standard.set(reports, forKey: "reports")
    }
    
    func addReport(location: CLLocationCoordinate2D, description: String, category: String,
                   serviceRequestId: String?, token: String?, httpPost: String?) {
        
        var reports = getReports()
        if reports == nil {
            reports = [[String: Any]]()
        }
        
        var report = ["date": NSDate(),
                  "lat" : location.latitude,
                  "long" : location.longitude,
                  "description": description,
                  "category": category] as [String : Any]
        
        // if we get a serviceRequestId and token, just save the former
        if let serviceRequestId = serviceRequestId {
            report["serviceRequestId"] = serviceRequestId
        } else if let token = token {
            report["token"] = token
        }

        // this is only needed for debugging:
//        if let httpPost = httpPost {
//            report["httpPost"] = httpPost
//        }

        reports?.append(report)
        
        UserDefaults.standard.set(reports, forKey: "reports")
    }
    
    func getReports() -> [[String: Any]]? {
        return UserDefaults.standard.array(forKey: "reports") as? [[String: Any]]
    }
    
    func clearReports() {
        return UserDefaults.standard.removeObject(forKey: "reports")
    }
}
