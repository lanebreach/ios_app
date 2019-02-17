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

public struct NetworkManagerError: LocalizedError {
    enum ErrorKind {
        case networkGeneral
        case networkBadHTTPStatus
        case networkResponseMalformed
        case networkJsonDecodeFailure
        case dataTaskNullData
        case imageUploadFailed
        case missingServiceRequestId
        case missingServiceRequestIdAndToken
    }
    
    let description: String?
    let kind: ErrorKind
    
    init(_ kind: ErrorKind, description: String?, function: String = #function, line: Int = #line) {
        self.kind = kind
        
        if let description = description {
            self.description = "\(function):\(line) - \(description)"
        } else {
            self.description = "\(function):\(line)"
        }
    }
    
    public var errorDescription: String? {
        return description
    }
}

class NetworkManager {
    let baseDomain = "mobile311-dev.sfgov.org"
    var mockUploadReportCount = -1

    static let shared = NetworkManager()
    var debugLastHttpPost: String?

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
        let url = URL(string: "http://\(baseDomain)/open311/v2/tokens/\(token).json")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {                                                 // check for fundamental networking error
                    completion(nil, NetworkManagerError(.networkGeneral, description: error != nil ? "error=\(error!)" : "no data"))
                    return
                }
                
                // check for 200
                if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 200 {           // check for http errors
                    print("statusCode should be 200, but is \(httpStatus.statusCode)")
                    print("response = \(httpStatus)")
                    completion(nil, NetworkManagerError(.networkBadHTTPStatus, description: "status=\(httpStatus.statusCode)"))
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
                            completion(nil, NetworkManagerError(.missingServiceRequestId, description: ""))
                        }
                    } else {
                        completion(nil, NetworkManagerError(.networkJsonDecodeFailure, description: ""))
                    }
                }
            }
        }
        task.resume()
    }

    func mockUploadReport(progressMessage: @escaping (String) -> Void,
                          completion: @escaping (_ serviceRequestId: String?, _ token: String?, _ error: Error?) -> Void) {
        
        if mockUploadReportCount == 7 {
            mockUploadReportCount = 0
        } else {
            mockUploadReportCount += 1
        }
        
        progressMessage("Uploading image")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if self.mockUploadReportCount == 0 {
                completion(nil, nil, NetworkManagerError(.imageUploadFailed, description: "error='mock image upload failed'"))
            } else {
                progressMessage("Uploading details")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    switch self.mockUploadReportCount {
                    case 1:
                        completion(nil, nil, NetworkManagerError(.dataTaskNullData, description: "error='mock error'"))
                    case 2:
                        completion(nil, nil, NetworkManagerError(.networkBadHTTPStatus, description: "status=mock error"))
                    case 3:
                        completion(nil, nil, NetworkManagerError(.missingServiceRequestIdAndToken, description: ""))
                    case 4:
                        completion(nil, nil, NetworkManagerError(.networkJsonDecodeFailure, description: ""))
                    case 5:
                        completion(nil, nil, NetworkManagerError(.networkResponseMalformed, description: ""))
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
    
    func uploadReport(image: UIImage, filename: String, currentLocation: CLLocationCoordinate2D,
                      emailAddress: String, category: String, description: String,
                      progressMessage: @escaping (String) -> Void,
                      completion: @escaping (_ serviceRequestId: String?, _ token: String?, _ error: Error?) -> Void) {
        
        if AppDelegate.getMockTestEnable(for: .useMockUpload) {
            mockUploadReport(progressMessage: progressMessage, completion: completion)
            return
        }
        
        progressMessage("Uploading image")
        self.uploadImage(with: UIImagePNGRepresentation(image)!, filename: filename) { (error) in
            print("\(Date().timeIntervalSince1970) start metadata upload")
            if let error = error {
                completion(nil, nil, NetworkManagerError(.imageUploadFailed, description: "error='\(error)'"))
                return
            }
            
            // TODO - send the mediaUrl from uploadImage()
            let mediaUrl = "https://s3-us-west-1.amazonaws.com/lane-breach/311-sf/temp-images/\(filename).png"
            
            // concatenate category (if not "Other") with optional description when POSTing (ex: [category] <description>)
            var fullDescription: String = ((category != NewReportViewModel.defaultCategory) && (category.count != 0)) ?
                "[\(category)] " : ""
            fullDescription.append(contentsOf: (description.count) != 0 ? description : "Blocked bicycle lane")
            
            let parameters = [
                "api_key": Keys.apiKey,
                "service_code": "5a6b5ac2d0521c1134854b01",
                "lat": String(currentLocation.latitude),
                "long": String(currentLocation.longitude),
                "email": (emailAddress.count != 0) ? emailAddress : "bikelanessf@gmail.com",
                "media_url": mediaUrl,
                "description": fullDescription,
                "attribute[Nature_of_request]": "Blocking_Bicycle_Lane"
            ]
            
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
            let url = URL(string: "http://\(self.baseDomain)/open311/v2/requests.json")!
            var request = URLRequest(url: url)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.httpBody = postString.data(using: .utf8)
            
            progressMessage("Uploading details")
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    guard let data = data, error == nil else {                                                 // check for fundamental networking error
                        completion(nil, nil, NetworkManagerError(.dataTaskNullData, description: "error='\(String(describing: error))'"))
                        return
                    }
                    
                    // check for 201 CREATED
                    if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 201 {           // check for http errors
                        print("statusCode should be 201, but is \(httpStatus.statusCode)")
                        print("response = \(httpStatus)")
                        completion(nil, nil, NetworkManagerError(.networkBadHTTPStatus, description: "status=\(httpStatus.statusCode)"))
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
                                completion(serviceRequestId, nil, nil)
                            } else if let token = dictionary[0]["token"] as? String {
                                // need a delay to allow 311 to get a service request ID
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    self.getServiceRequestId(from: token, completion: { (serviceRequestId, error) in
                                        completion(serviceRequestId, token, nil)
                                    })
                                }
                                return
                            } else {
                                completion(nil, nil, NetworkManagerError(.missingServiceRequestIdAndToken, description: ""))
                            }
                        } else {
                            completion(nil, nil, NetworkManagerError(.networkJsonDecodeFailure, description: ""))
                        }
                    } else {
                        completion(nil, nil, NetworkManagerError(.networkResponseMalformed, description: ""))
                    }
                    
                    print("\(Date().timeIntervalSince1970) done metadata upload")
                }
            }
            task.resume()
        }
    }
}
