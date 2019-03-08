//
//  NetworkManager.swift
//  blfa
//
//  Created by Dale Low on 2/15/19.
//  Copyright © 2019 Dale Low. All rights reserved.
//

import AWSS3
import CoreLocation
import Foundation

public class NetworkManagerError: NSError {
    enum ErrorKind: Int {
        case networkGeneral = -1
        case networkBadHTTPStatus = -2
        case networkResponseMalformed = -3
        case networkJsonDecodeFailure = -4
        case dataTaskNullDataOrError = -5
        case imageUploadFailed = -6
        case missingServiceRequestId = -7
        case missingServiceRequestIdAndToken = -8
    }
    
    let kind: ErrorKind
    
    init(_ kind: ErrorKind, description: String? = nil, httpStatusCode: Int? = nil, domain: String? = nil, function: String = #function, line: Int = #line) {
        self.kind = kind
        
        var localizedDescription: String
        if let description = description {
            localizedDescription = "\(function):\(line) - \(description)"
        } else {
            localizedDescription = "\(function):\(line)"
        }
        
        var errorDomain: String
        if let domain = domain {
            errorDomain = domain
        } else {
            if UserDefaults.standard.bool(forKey: kUserDefaultsUsingDevServerKey) {
                errorDomain = "DevNetworkManagerError"
            } else {
                errorDomain = "NetworkManagerError"
            }
        }

        // use HTTP status as NSError code, otherwise use Kind
        var code: Int
        if let httpStatusCode = httpStatusCode {
            code = httpStatusCode
        } else {
            code = kind.rawValue
        }
        
        super.init(domain: errorDomain, code: code, userInfo: [NSLocalizedDescriptionKey: localizedDescription])
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class MockNetworkManagerError: NetworkManagerError {
    override init(_ kind: ErrorKind, description: String? = nil, httpStatusCode: Int? = nil, domain: String? = nil, function: String = #function, line: Int = #line) {
        super.init(kind, description: description, httpStatusCode: httpStatusCode, domain: "MockNetworkManagerError")
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class NetworkManager {
    let baseDomainDevelopment = "mobile311-dev.sfgov.org"
    let baseDomainProduction = "mobile311.sfgov.org"
    var mockUploadReportCount = -1

    static let shared = NetworkManager()
    var debugLastHttpPost: String?
    var uploadReportTaskId: UIBackgroundTaskIdentifier?
    var uploadReportCompletion: ((_ serviceRequestId: String?, _ token: String?, _ error: NetworkManagerError?) -> Void)?
    
    func updateTabBarStyleForCurrentServer(vc: UIViewController) {
        vc.tabBarController?.tabBar.barTintColor = UserDefaults.standard.bool(forKey: kUserDefaultsUsingDevServerKey) ? UIColor.red : UIColor.lightGray
        vc.tabBarController?.tabBar.unselectedItemTintColor = UIColor.black
        vc.tabBarController?.tabBar.tintColor = UIColor.blue
    }

    private func uploadImage(with data: Data, filename: String, completion: @escaping (Error?) -> Void) {
        let expression = AWSS3TransferUtilityUploadExpression()
//        expression.progressBlock = progressBlock
        
        let completionHandler: AWSS3TransferUtilityUploadCompletionHandlerBlock = { (task, error) -> Void in
            DispatchQueue.main.async(execute: {
                if let error = error {
                    print("completionHandler failed with error: \(error)")
                    completion(error)
                }
//                else if (self.progressView.progress != 1.0) {
//                    print("Error: Failed - Likely due to invalid region / filename")
//                }
                else {
                    print("completionHandler success")
                    completion(nil)
                }
            })
        }
        
        let transferUtility = AWSS3TransferUtility.s3TransferUtility(forKey: "USWest1S3TransferUtility")
        transferUtility.uploadData(
            data,
            bucket: "lane-breach",
            key: "311-sf/temp-images/\(filename).png",
            contentType: "image/png",
            expression: expression,
            completionHandler: completionHandler).continueWith { (task) -> AnyObject? in
                if let error = task.error {
                    print("uploadData failed with error: \(error)")
                    completion(error)
                }
                
                if let _ = task.result {
                    print("uploadData starting")
                    // Do something with uploadTask.
                }
                
                return nil;
        }
    }

    func getServiceRequestId(from token: String, completion: @escaping (String?, Error?) -> Void) {
        // now do a GET to translate the token into a service_request_id
        // ex: http://mobile311-dev.sfgov.org/open311/v2/tokens/5bc6c0f5ff031d6f5b335df0.json
        let baseDomain = UserDefaults.standard.bool(forKey: kUserDefaultsUsingDevServerKey) ? baseDomainDevelopment : baseDomainProduction;
        let url = URL(string: "http://\(baseDomain)/open311/v2/tokens/\(token).json")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {                                                 // check for fundamental networking error
                    completion(nil, NetworkManagerError(.networkGeneral, description: error != nil ? "error='\(error!)'" : "error='no data'"))
                    return
                }
                
                // check for 200
                if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 200 {           // check for http errors
                    print("statusCode should be 200, but is \(httpStatus.statusCode)")
                    print("response = \(httpStatus)")
                    completion(nil, NetworkManagerError(.networkBadHTTPStatus, httpStatusCode: httpStatus.statusCode))
                    return
                }
                
                if let responseString = String(data: data, encoding: .utf8) {
                    // looks like: responseString = [{"token":"5bc6c0f5ff031d6f5b335df0"}]
                    print("responseString2 = \(responseString)")
                    
                    let json = try? JSONSerialization.jsonObject(with: data, options: [])
                    if let dictionary = json as? [[String: Any]] {
                        if let serviceRequestId = dictionary[0]["service_request_id"] as? String {
                            print("serviceRequestId: \(serviceRequestId)")
                            completion(serviceRequestId, nil)
                        } else {
                            completion(nil, NetworkManagerError(.missingServiceRequestId))
                        }
                    } else {
                        completion(nil, NetworkManagerError(.networkJsonDecodeFailure))
                    }
                }
            }
        }
        task.resume()
    }

    func mockUploadReport(progressMessage: @escaping (String) -> Void,
                          completion: @escaping (_ serviceRequestId: String?, _ token: String?, _ error: NetworkManagerError?) -> Void) {
        
        if mockUploadReportCount == 7 {
            mockUploadReportCount = 0
        } else {
            mockUploadReportCount += 1
        }
        
        progressMessage("Uploading image")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if self.mockUploadReportCount == 0 {
                completion(nil, nil, MockNetworkManagerError(.imageUploadFailed, description: "error='mock image upload failed'"))
            } else {
                progressMessage("Uploading details")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    switch self.mockUploadReportCount {
                    case 1:
                        completion(nil, nil, MockNetworkManagerError(.dataTaskNullDataOrError, description: "error='mock error'"))
                    case 2:
                        completion(nil, nil, MockNetworkManagerError(.networkBadHTTPStatus, httpStatusCode: 400))
                    case 3:
                        completion(nil, nil, MockNetworkManagerError(.missingServiceRequestIdAndToken))
                    case 4:
                        completion(nil, nil, MockNetworkManagerError(.networkJsonDecodeFailure))
                    case 5:
                        completion(nil, nil, MockNetworkManagerError(.networkResponseMalformed))
                    case 6:
                        completion("123", nil, nil)
                    case 7:
                        completion(nil, "456", nil)
                    default:
                        assert(false)
                    }
                }
            }
        }
    }
    
    func beginUploadReportTask() {
        let taskId = UIApplication.shared.beginBackgroundTask(expirationHandler: {
            self.endUploadReportTask()
        })
        
        if taskId != UIBackgroundTaskInvalid {
            print("*** starting background task with ID \(taskId)")
            self.uploadReportTaskId = taskId
        } else {
            print("*** failed to start background task")
            self.uploadReportTaskId = nil
        }
    }
    
    func endUploadReportTask() {
        if let uploadReportTaskId = uploadReportTaskId {
            print("*** ending background task with ID \(uploadReportTaskId)")
            UIApplication.shared.endBackgroundTask(uploadReportTaskId)
            self.uploadReportTaskId = nil
        }
    }
    
    func reportCompletionAndEndUploadReportTask(_ serviceRequestId: String?, _ token: String?, _ error: NetworkManagerError?) {
        if let uploadReportCompletion = uploadReportCompletion {
            uploadReportCompletion(serviceRequestId, token, error)
            self.uploadReportCompletion = nil
        } else {
            assertionFailure()
        }
        
        self.endUploadReportTask()
    }
    
    func uploadReport(image: UIImage, filename: String, location: CLLocationCoordinate2D,
                      emailAddress: String?, fullName: String?, phoneNumber: String?,
                      category: String, description: String,
                      progressMessage: @escaping (String) -> Void,
                      completion: @escaping (_ serviceRequestId: String?, _ token: String?, _ error: NetworkManagerError?) -> Void) {
        
        if AppDelegate.getMockTestEnable(for: .useMockUpload) {
            mockUploadReport(progressMessage: progressMessage, completion: completion)
            return
        }
        
        uploadReportCompletion = completion
        beginUploadReportTask()
        progressMessage("Uploading image")
        self.uploadImage(with: UIImagePNGRepresentation(image)!, filename: filename) { (error) in
            print("\(Date().timeIntervalSince1970) start metadata upload")
            if let error = error {
                self.reportCompletionAndEndUploadReportTask(nil, nil, NetworkManagerError(.imageUploadFailed, description: "error='\(error)'"))
                return
            }
            
            // TODO - send the mediaUrl from uploadImage()
            let mediaUrl = "https://s3-us-west-1.amazonaws.com/lane-breach/311-sf/temp-images/\(filename).png"
            
            // concatenate category (if not "Other") with optional description when POSTing (ex: [category] <description>)
            var fullDescription: String = ((category != NewReportViewModel.defaultCategory) && (category.count != 0)) ?
                "[\(category)] " : ""
            fullDescription.append(contentsOf: (description.count) != 0 ? description : "Blocked bicycle lane")
            
            var parameters = [
                "api_key": UserDefaults.standard.bool(forKey: kUserDefaultsUsingDevServerKey) ? Keys.apiKey : Keys.apiKeyProduction,
                "service_code": "5a6b5ac2d0521c1134854b01",
                "lat": String(location.latitude),
                "long": String(location.longitude),
                "media_url": mediaUrl,
                "description": fullDescription,
                "attribute[Nature_of_request]": "Blocking_Bicycle_Lane"
            ]
            
            if let emailAddress = emailAddress, emailAddress.trimmingCharacters(in: .whitespaces).count > 0 {
                parameters["email"] = emailAddress.trimmingCharacters(in: .whitespaces)
            } else {
                parameters["email"] = "bikelanessf@gmail.com"
            }
            
            if let fullName = fullName, fullName.trimmingCharacters(in: .whitespaces).count > 0 {
                var components = fullName.components(separatedBy: " ")
                if components.count > 0 {
                    parameters["first_name"] = components.removeFirst()
                    parameters["last_name"] = components.joined(separator: " ").trimmingCharacters(in: .whitespaces)
                } else {
                    parameters["first_name"] = fullName
                    parameters["last_name"] = ""
                }
            }

            if let phoneNumber = phoneNumber, phoneNumber.trimmingCharacters(in: .whitespaces).count > 0 {
                parameters["phone"] = phoneNumber.trimmingCharacters(in: .whitespaces)
            }
            
            // create the form URL-encoded string for the params
            var postString: String = ""
            var first = true
            for (key, value) in parameters {
                let escapedString = value.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)!
                
                if first {
                    first = false
                } else {
                    postString += "&"
                }
                postString += "\(key)=\(escapedString)"
            }
            self.debugLastHttpPost = postString
            
            // POST it
            let baseDomain = UserDefaults.standard.bool(forKey: kUserDefaultsUsingDevServerKey) ? self.baseDomainDevelopment : self.baseDomainProduction;
            let url = URL(string: "http://\(baseDomain)/open311/v2/requests.json")!
            var request = URLRequest(url: url)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.httpBody = postString.data(using: .utf8)
            
            progressMessage("Uploading details")
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    guard let data = data, error == nil else {                                                 // check for fundamental networking error
                        self.reportCompletionAndEndUploadReportTask(nil, nil, NetworkManagerError(.dataTaskNullDataOrError, description: "error='\(String(describing: error))'"))
                        return
                    }
                    
                    // check for 201 CREATED
                    if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 201 {           // check for http errors
                        print("statusCode should be 201, but is \(httpStatus.statusCode)")
                        print("response = \(httpStatus)")
                        self.reportCompletionAndEndUploadReportTask(nil, nil, NetworkManagerError(.networkBadHTTPStatus, httpStatusCode: httpStatus.statusCode))
                        return
                    }
                    
                    if let responseString = String(data: data, encoding: .utf8) {
                        // looks like: responseString = [{"token":"5bc6c0f5ff031d6f5b335df0"}]
                        print("responseString = \(responseString)")
                        
                        // check if it's a token
                        let json = try? JSONSerialization.jsonObject(with: data, options: [])
                        if let dictionary = json as? [[String: Any]] {
                            if let serviceRequestId = dictionary[0]["service_request_id"] as? String {
                                print("serviceRequestId: \(serviceRequestId)")
                                self.reportCompletionAndEndUploadReportTask(serviceRequestId, nil, nil)
                            } else if let token = dictionary[0]["token"] as? String {
                                print("token: \(token)")
                                self.reportCompletionAndEndUploadReportTask(nil, token, nil)
                                
                                // need a delay to allow 311 to get a service request ID
                                // this never seems to succeed on dev or prod, so might as well complete faster and skip it
//                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//                                    self.getServiceRequestId(from: token, completion: { (serviceRequestId, error) in
//                                        // don't pass the error, if any, along cuz we've always got a token
//                                        self.reportCompletionAndEndUploadReportTask(serviceRequestId, token, nil)
//                                    })
//                                }
//                                return
                            } else {
                                self.reportCompletionAndEndUploadReportTask(nil, nil, NetworkManagerError(.missingServiceRequestIdAndToken))
                            }
                        } else {
                            self.reportCompletionAndEndUploadReportTask(nil, nil, NetworkManagerError(.networkJsonDecodeFailure))
                        }
                    } else {
                        self.reportCompletionAndEndUploadReportTask(nil, nil, NetworkManagerError(.networkResponseMalformed))
                    }
                    
                    print("\(Date().timeIntervalSince1970) done metadata upload")
                }
            }
            task.resume()
        }
    }
}
