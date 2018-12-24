//
//  NewReportViewController.swift
//  blfa
//
//  Created by Dale Low on 10/3/18.
//  Copyright © 2018 Dale Low. All rights reserved.
//

import AWSS3
import CoreLocation
import JGProgressHUD
import ReactiveCocoa
import ReactiveSwift
import Result
import UIKit

class NewReportViewModel {
    let emailAddress: MutableProperty<String>
    let description: MutableProperty<String>
    let category: MutableProperty<String>
    let haveImage: MutableProperty<Bool>
    let currentLocation: MutableProperty<CLLocationCoordinate2D?>
    
    var categorySignal: Signal<String, NoError>
    var descriptionSignal: Signal<String, NoError>
    var okToSendSignal: Signal<Bool, NoError>
    var locationStatusSignal: Signal<Bool, NoError>
    
    let categories: [String] = ["Delivery truck", "Moving truck", "FedEx", "UPS", "USPS",
                                "Bus",
                                "Uber", "Lyft", "Uber/Lyft",
                                "Other"]    //  TODO - let user enter optional text to replace "other"?
    
    init() {
        self.emailAddress = MutableProperty("")
        self.description = MutableProperty("")
        self.category = MutableProperty("")
        self.haveImage = MutableProperty(false)
        self.currentLocation = MutableProperty(nil)
        
        self.categorySignal = self.category.signal
        self.descriptionSignal = self.description.signal
        
        // output true if the email address has 3+ chars and we have a valid category/image/location
        self.okToSendSignal = Signal.combineLatest(self.category.signal, self.haveImage.signal, self.currentLocation.signal)
            .map { (arg) -> Bool in
                
                let (category, haveImage, currentLocation) = arg
                
                print("category=\(category), haveImage=\(haveImage), currentLocation=\(String(describing: currentLocation))")
                return (category.count > 1) && haveImage && (currentLocation != nil)
        }
        
        self.locationStatusSignal = self.currentLocation.signal
            .map { (currentLocation) -> Bool in
                return currentLocation != nil
        }
    }
}

class NewReportViewController: UIViewController, CLLocationManagerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate,
    UITextFieldDelegate, UIPickerViewDataSource, UIPickerViewDelegate {

    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var takePictureButton: UIButton!
    @IBOutlet weak var categoryTextField: UITextField!
    @IBOutlet weak var descriptionTextField: UITextField!
    @IBOutlet weak var locationButton: UIButton!
    @IBOutlet weak var postReportButton: UIButton!
    
    var viewModel: NewReportViewModel!
    var locationManager = CLLocationManager()
    var keyboardHeight: CGFloat = 0
    var hud: JGProgressHUD?
    
    //MARK:- Internal methods    
    func uploadImage(with data: Data, filename: String, completion: @escaping (Error?) -> Void) {
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
    
    // credit: https://stackoverflow.com/questions/5427656/ios-uiimagepickercontroller-result-image-orientation-after-upload
    func fixOrientation(img: UIImage) -> UIImage? {
        let result: UIImage?
        if img.imageOrientation == .up {
            result = img
        } else {
            result = autoreleasepool { () -> UIImage? in
                UIGraphicsBeginImageContextWithOptions(img.size, false, img.scale)
                let rect = CGRect(x: 0, y: 0, width: img.size.width, height: img.size.height)
                img.draw(in: rect)
                
                let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                
                return normalizedImage
            }
        }
        
        return result
    }
    
    //MARK:- Lifecycle
    override func viewDidLoad() {
        // Uncomment the line below to get a demo image
        //self.imageView.image = UIImage.init(imageLiteralResourceName: "block_example")
        
        // can't take pics using the sim
        #if (targetEnvironment(simulator))
            self.takePictureButton.isEnabled = false
        #endif
        
        self.descriptionTextField.delegate = self
        
        // model
        viewModel = NewReportViewModel()
        
        // react to model changes
        self.categoryTextField.reactive.text <~ self.viewModel.categorySignal
        self.descriptionTextField.reactive.text <~ self.viewModel.descriptionSignal
        self.viewModel.locationStatusSignal.observeValues { value in
            print("locationStatusSignal: \(value)")
            self.locationButton.setImage(UIImage(named: value ? "location_good" : "location_bad"), for: UIControlState.normal)
        }
        
        self.postReportButton.reactive.isEnabled <~ self.viewModel.okToSendSignal
        // this is a hack to get the initial state without getting the viewmodel to do it somehow
        self.postReportButton.isEnabled = false
                
        // category picker/toolbar
        let picker = UIPickerView.init()
        picker.dataSource = self
        picker.delegate = self
        picker.showsSelectionIndicator = true
        self.categoryTextField.inputView = picker
        
        let toolBar = UIToolbar()
        toolBar.barStyle = UIBarStyle.default
        toolBar.isTranslucent = true
        toolBar.sizeToFit()
        
        let spaceButton = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "Done", style: UIBarButtonItemStyle.plain,
                                         target: self, action: #selector(NewReportViewController.donePicker(_:)))
        
        toolBar.setItems([spaceButton, doneButton], animated: false)
        toolBar.isUserInteractionEnabled = true
        
        self.categoryTextField.inputAccessoryView = toolBar
        NotificationCenter.default.addObserver(self, selector: #selector(NewReportViewController.keyboardWillShow), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(NewReportViewController.keyboardWillHide), name: NSNotification.Name.UIKeyboardWillHide, object: nil)

        // assume no location
        locationButton.setImage(UIImage(named: "location_bad"), for: UIControlState.normal)
        
        super.viewDidLoad()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        // TODO - also make sure that this handles app foregrounding
        
        // update the email addr
        self.viewModel.emailAddress.value = UserDefaults.standard.string(forKey: "com.blfa.email") ?? ""
        
        // get a new location
        self.viewModel.currentLocation.value = nil
        
        // TODO - this gets called after an image is selected too, so we probably want to disable that
        // TODO - chek if we're outside of San Francisco!
        if CLLocationManager.locationServicesEnabled() == true {
            if CLLocationManager.authorizationStatus() == .restricted || CLLocationManager.authorizationStatus() == .denied ||  CLLocationManager.authorizationStatus() == .notDetermined {
                self.locationManager.requestWhenInUseAuthorization()
            }
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
            self.locationManager.delegate = self
            self.locationManager.startUpdatingLocation()
        } else {
            AppDelegate.showSimpleAlertWithOK(vc: self, "Please turn on location services to post a new report")
        }
    }
    
    //MARK:- Event Handlers
    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue {
            if self.view.frame.origin.y == 0 {
                // TODO - this should depend on the y-pos of the text field
                self.keyboardHeight = keyboardSize.height
                self.view.frame.origin.y -= self.keyboardHeight
            }
        }
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        if let _ = (notification.userInfo?[UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue {
            if self.view.frame.origin.y != 0 {
                // use our stored value cuz the height might have changed
                self.view.frame.origin.y += self.keyboardHeight
            }
        }
    }
    
    @IBAction func takePicureAction(sender: UIButton) {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.allowsEditing = false
        vc.delegate = self
        present(vc, animated: true)
    }
    
    @IBAction func photoLibraryAction(sender: UIButton) {
        let vc = UIImagePickerController()
        vc.sourceType = .photoLibrary
        vc.allowsEditing = false
        vc.delegate = self
        present(vc, animated: true)
    }
    
    @objc func donePicker(_ sender: Any) {
        self.categoryTextField.resignFirstResponder()
    }
    
    @IBAction func locationButtonPressed(sender: UIButton) {
        AppDelegate.showSimpleAlertWithOK(vc: self, self.viewModel.currentLocation.value != nil ?
            "Current location found. You may now SEND a new report to 311 as long as you have taken a picture and selected a category." :
            "Cannot determine your location - make sure that Location Services are enabled for this app in Settings.")
    }

    @IBAction func postReportButtonPressed(sender: UIButton) {
        guard let image = self.imageView.image else {
            return
        }
        
        // this func should not get called if we don't have a currentLocation
        guard let currentLocation = self.viewModel.currentLocation.value else {
            assert(false)
            return
        }
        
        // TODO: probably move into model
        let filename = UUID().uuidString
        
        hud = JGProgressHUD(style: .dark)
        if let hud = hud {
            hud.textLabel.text = "Uploading image"
            hud.show(in: self.view)
        }

        self.uploadImage(with: UIImagePNGRepresentation(image)!, filename: filename) { (error) in
            guard error == nil else {
                self.hud?.dismiss()
                AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: uploading the image failed with \(error!)")
                return
            }

            // TODO - send the mediaUrl from uploadImage()
            let mediaUrl = "https://s3-us-west-1.amazonaws.com/lane-breach/311-sf/temp-images/\(filename).png"
            
            // concatenate category with optional description when POSTing (ex: [category] <description>)
            var description: String = self.viewModel.category.value.count != 0 ? "[\(self.viewModel.category.value)] " : ""
            description.append(contentsOf: (self.viewModel.description.value.count) != 0 ? self.viewModel.description.value : "Blocked bicycle lane")
            
            let parameters = [
                "api_key": Keys.apiKey,
                "service_code": "5a6b5ac2d0521c1134854b01",
                "lat": String(currentLocation.latitude),
                "long": String(currentLocation.longitude),
                "email": (self.viewModel.emailAddress.value.count != 0) ? self.viewModel.emailAddress.value : "bikelanessf@gmail.com",
                "media_url": mediaUrl,
                "description": description,
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
            
            // POST it
            let url = URL(string: "http://mobile311-dev.sfgov.org/open311/v2/requests.json")!
            var request = URLRequest(url: url)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.httpBody = postString.data(using: .utf8)
            
            self.hud?.textLabel.text = "Uploading details"
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    guard let data = data, error == nil else {                                                 // check for fundamental networking error
                        print(error != nil ? "error=\(error!)" : "no data")
                        
                        self.hud?.dismiss()
                        AppDelegate.showSimpleAlertWithOK(vc: self, error != nil ? "ERROR: \(error!)" : "ERROR: no data in server response")
                        return
                    }
                    
                    // check for 201 CREATED
                    if let httpStatus = response as? HTTPURLResponse, httpStatus.statusCode != 201 {           // check for http errors
                        print("statusCode should be 201, but is \(httpStatus.statusCode)")
                        print("response = \(httpStatus)")
                        
                        self.hud?.dismiss()
                        AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: bad HTTP response code: \(httpStatus.statusCode)")
                        return
                    }
                    
                    self.hud?.dismiss()
                    if let responseString = String(data: data, encoding: .utf8) {
                        // looks like: responseString = [{"token":"5bc6c0f5ff031d6f5b335df0"}]
                        print("responseString = \(responseString)")
                        
                        // check if it's a token
                        let json = try? JSONSerialization.jsonObject(with: data, options: [])
                        if let dictionary = json as? [[String: Any]] {
                            if let serviceRequestId = dictionary[0]["service_request_id"] as? String {
                                print("serviceRequestId: \(serviceRequestId)")
                                #if DEBUG
                                AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311 with service request ID \(serviceRequestId)")
                                #else
                                AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311!")
                                #endif
                            } else if let token = dictionary[0]["token"] as? String {
                                #if DEBUG
                                AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311 with token \(token)")
                                #else
                                AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311!")
                                #endif
                            } else {
                                #if DEBUG
                                AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311, but we didn't get a service request ID or token")
                                #else
                                AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311, but we didn't get the right confirmation back. Hopefully it worked!")
                                #endif
                            }
                        } else {
                            #if DEBUG
                            AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311 but the response was malformed")
                            #else
                            AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311, but we didn't get the right confirmation back. Hopefully it worked!")
                            #endif
                        }
                    }
                    
                    // reset for the next submission
                    self.imageView.image = nil
                    self.viewModel.haveImage.value = false
                    self.viewModel.category.value = ""
                    self.viewModel.description.value = ""
                }
            }
            task.resume()
        }
    }
    
    //MARK:- CLLocationManager delegate methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if locations.count > 0 {
            let location = locations[0]
            // TOOD - what's a reasonble requirement for accuracy?
            if location.horizontalAccuracy < 50 {
                print("got location \(location.coordinate)")
                self.viewModel.currentLocation.value = location.coordinate
                self.locationManager.stopUpdatingLocation()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        AppDelegate.showSimpleAlertWithOK(vc: self, "Unable to access your current location")
    }
    
    //MARK:- UIImagePickerControllerDelegate delegate methods
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true)
        
        // note: could use UIImagePickerControllerEditedImage if allowsEditing == true
        guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
            AppDelegate.showSimpleAlertWithOK(vc: self, "Error capturing image (no original image)")
            return
        }
        
        guard let fixedImage = fixOrientation(img: image) else {
            AppDelegate.showSimpleAlertWithOK(vc: self, "Error capturing image (failed to fix orientation)")
            return
        }

        self.imageView.image = fixedImage
        
        // tell the model that we have an image
        self.viewModel.haveImage.value = true
    }
    
    //MARK:- UIPickerViewDataSource methods
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return self.viewModel.categories.count
    }
    
    //MARK:- UIPickerViewDelegate methods
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return self.viewModel.categories[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.viewModel.category.value = self.viewModel.categories[row]
    }

    //MARK:- UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        self.viewModel.description.value = textField.text ?? ""
        return true
    }
}

