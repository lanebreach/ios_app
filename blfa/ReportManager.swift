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
    
    func addReport(location: CLLocationCoordinate2D, description: String, category: String, license: String,
                   serviceRequestId: String?, token: String?, httpPost: String?) {
        
        var reports = getReports()
        if reports == nil {
            reports = [[String: Any]]()
        }
        
        var report = ["date": NSDate(),
                  "lat" : location.latitude,
                  "long" : location.longitude,
                  "description": description,
                  "license": license,
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
    
    // convert tokens to service request IDs if possible
    func finalizeReportsIfNecessary(completion: @escaping () -> Void) {
        guard let reports = getReports() else {
            completion()
            return
        }
        
        // save for testing only:
        // UserDefaults.standard.set(reports, forKey: "savereports")
        
        var pendingWork = false
        var updateReports = false
        var updatedReports = [[String: Any]]()
        let dispatchGroup = DispatchGroup()
        for var report in reports {
            guard report["serviceRequestId"] == nil, let token = report["token"] as? String else {
                // nothing else to do if we already have a serviceRequestId or don't have a token
                updatedReports.append(report)
                continue
            }
        
            pendingWork = true
            dispatchGroup.enter()
            print("trying to convert token \(token)")
            NetworkManager.shared.getServiceRequestId(from: token) { (id, error) in
                dispatchGroup.leave()
                
                if let id = id {
                    // got it!
                    print("converted token \(token) to serviceRequestId \(id)")
                    report["serviceRequestId"] = id
                    updatedReports.append(report)
                    updateReports = true
                } else if let date = report["date"] as? NSDate, let error = error as? NetworkManagerError {
                    print("converting token \(token) failed with error \(error)")
                    if (date.timeIntervalSinceNow < -3600) &&
                        (error.kind == .missingServiceRequestId || (error.kind == .networkBadHTTPStatus && error.code == 404)) {
                        
                        // report is over an hour old and we just got a permanent error - so give up
                        report["serviceRequestId"] = "unknown"
                        updatedReports.append(report)
                        updateReports = true
                    }
                }
            }
        }
        
        if pendingWork {
            // wait until all requests are done (successfully or not)
            print("waiting for token conversion requests")
            dispatchGroup.notify(queue: .main) {
                print("done waiting for token conversion requests")
                if updateReports {
                    print("updatedReports: \(updatedReports)")
                    
                    UserDefaults.standard.set(updatedReports, forKey: "reports")
                }

                completion()
            }
        } else {
            completion()
        }
    }
}
