//
//  NewReportViewController.swift
//  blfa
//
//  Created by Dale Low on 10/3/18.
//  Copyright © 2018 Dale Low. All rights reserved.
//

import AVFoundation
import Crashlytics
import CoreLocation
import EasyTipView
import Fabric
import JGProgressHUD
import Photos
import ReactiveCocoa
import ReactiveSwift
import Result
import UIKit

class NewReportViewController: UIViewController, CLLocationManagerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate,
    AVCapturePhotoCaptureDelegate, UITextFieldDelegate, UIPickerViewDataSource, UIPickerViewDelegate, EasyTipViewDelegate {

    let controlViewToSafeAreaBottomDefault: CGFloat = 16
    #if DEBUG
    let showDebugMessages = true
    #else
    let showDebugMessages = false
    #endif

    @IBOutlet weak var locationImageView: UIImageView!
    @IBOutlet weak var flashImageView: UIImageView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var previewView: UIView!
    @IBOutlet weak var takePictureButton: UIButton!
    
    @IBOutlet weak var controlView: UIView!
    @IBOutlet weak var controlViewToSafeAreaBottomConstraint : NSLayoutConstraint!
    @IBOutlet weak var categoryTextField: UITextField!
    @IBOutlet weak var descriptionTextField: UITextField!
    @IBOutlet weak var cameraButtonsView: UIView!
    @IBOutlet weak var changePhotoButton: UIButton!
    @IBOutlet weak var postReportButton: UIButton!
    
    var viewModel: NewReportViewModel!
    
    // credit: https://medium.com/@rizwanm/https-medium-com-rizwanm-swift-camera-part-1-c38b8b773b2
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var capturePhotoOutput: AVCapturePhotoOutput?
    var flashSupported: Bool = false
    var flashMode: AVCaptureDevice.FlashMode = .auto
    
    var locationManager = CLLocationManager()
    var hud: JGProgressHUD?
    var tipViews: [TipIdentifier:EasyTipView] = [:]
    var currentLocation: (CLLocationCoordinate2D, Date)?
    var locationCount = 0
    var uploadAttempts = 0
    
    //MARK:- Internal methods
    func requestAuthorizationHandler(status: PHAuthorizationStatus) {
        if status != PHAuthorizationStatus.authorized {
            AppDelegate.showSimpleAlertWithOK(vc: self, "Please check to see if your device settings allows photo library access - this is needed to get the location from your photos when uploading a library image and to save pictures that you take to your camera roll.",
                                              button2title: "Settings") { (_) in
             
                self.gotoAppSettings()
            }
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
    
    func tipViewPreferences(verticalOffset: CGFloat = 5,
                            arrowPosition: EasyTipView.ArrowPosition = .bottom) -> EasyTipView.Preferences {
        
        var preferences = EasyTipView.Preferences()
        preferences.drawing.font = UIFont(name: "Futura-Medium", size: 15)!
        preferences.drawing.foregroundColor = UIColor.white
        preferences.drawing.backgroundColor = UIColor(hue:0.46, saturation:0.99, brightness:0.6, alpha:1)
        preferences.drawing.arrowHeight = verticalOffset
        preferences.drawing.arrowPosition = arrowPosition
        
        return preferences
    }
    
    func gotoAppSettings() {
        let settingsUrl = NSURL(string:UIApplicationOpenSettingsURLString)
        if let url = settingsUrl {
            UIApplication.shared.open(url as URL, options: [:], completionHandler: nil)
        }
    }
    
    func updateLocationIcon(found: Bool) {
        self.locationImageView.image = UIImage(named: found ? "ic_location_black" : "ic_location_bad_black")
    }
    
    func startUpdatingLocation(showAlertOnError: Bool) {
        locationCount = 0
        currentLocation = nil
        updateLocationIcon(found: false)
        
        if CLLocationManager.locationServicesEnabled() == true {
            if CLLocationManager.authorizationStatus() == .restricted || CLLocationManager.authorizationStatus() == .denied ||  CLLocationManager.authorizationStatus() == .notDetermined {
                self.locationManager.requestWhenInUseAuthorization()
            }
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
            self.locationManager.delegate = self
            self.locationManager.startUpdatingLocation()
        } else {
            if showAlertOnError {
                AppDelegate.showSimpleAlertWithOK(vc: self, "Please turn on location services to post a new report")
            }
        }
    }
    
    func locationIsInSanFrancisco(_ location: CLLocationCoordinate2D) -> Bool {
        let kMinLat: CLLocationDegrees = 37.683691
        let kMaxLat: CLLocationDegrees = 37.822322
        let kMinLong: CLLocationDegrees = -122.527336
        let kMaxLong: CLLocationDegrees = -122.335033

        if (location.latitude < kMinLat) || (location.latitude > kMaxLat) ||
            (location.longitude < kMinLong) || (location.longitude > kMaxLong) {
            
            return false
        }
        
        return true
    }
    
    // reset for the next submission
    func resetReport() {
        self.changePhotoAction(sender: nil)
    }
    
    //MARK:- Lifecycle
    override func viewDidLoad() {
        // this is the first screen that is shown, so let's update the tab bar style here
        NetworkManager.shared.updateTabBarStyleForCurrentServer(vc: self)
        
        // ask the user to access the photo library so we can get the location from photos
        if PHPhotoLibrary.authorizationStatus() != PHAuthorizationStatus.authorized {
            PHPhotoLibrary.requestAuthorization(requestAuthorizationHandler)
        }

        // model
        viewModel = NewReportViewModel()
        
        // react to model changes
        self.categoryTextField.reactive.text <~ self.viewModel.categorySignal
        self.descriptionTextField.reactive.text <~ self.viewModel.descriptionSignal
        self.viewModel.locationStatusSignal.observeValues { value in
            print("locationStatusSignal: \(value)")
            if !value {
                self.startUpdatingLocation(showAlertOnError: false)
            } else {
                self.locationManager.stopUpdatingLocation()
            }
        }
        
        self.postReportButton.reactive.isEnabled <~ self.viewModel.okToSendSignal
        
        // can't take pics using the sim
        #if (targetEnvironment(simulator))
            self.takePictureButton.isEnabled = false
        #endif

        // hide control view below the screen
        self.controlViewToSafeAreaBottomConstraint.constant = -self.controlView.frame.height
        self.controlView.layer.cornerRadius = 5
        self.cameraButtonsView.layer.cornerRadius = 5
        self.descriptionTextField.delegate = self
        
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

        // set up location icon/tap event handlers
        locationImageView.image = UIImage(named: "ic_location_bad_black")
        var tapper = UITapGestureRecognizer(target:self, action:#selector(self.locationButtonPressed(sender:)))
        tapper.numberOfTouchesRequired = 1
        locationImageView.isUserInteractionEnabled = true
        locationImageView.addGestureRecognizer(tapper)
        
        #if (!targetEnvironment(simulator))
        
            // preview image
            let captureDevice = AVCaptureDevice.default(for: .video)
            if let captureDevice = captureDevice {
                do {
                    let input = try AVCaptureDeviceInput(device: captureDevice)
                    captureSession = AVCaptureSession()
                    captureSession!.addInput(input)
                    
                    videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
                    videoPreviewLayer?.videoGravity = AVLayerVideoGravity.resizeAspectFill
                    videoPreviewLayer?.frame = view.layer.bounds
                    previewView.layer.addSublayer(videoPreviewLayer!)
                    
                    // Get an instance of ACCapturePhotoOutput class
                    capturePhotoOutput = AVCapturePhotoOutput()
                    
                    // Set the output on the capture session
                    if let capturePhotoOutput = capturePhotoOutput {
                        capturePhotoOutput.isHighResolutionCaptureEnabled = true

                        captureSession!.addOutput(capturePhotoOutput)
                        captureSession!.startRunning()

                        // allow changing flash modes if we support off/on/auto (must check after adding to captureSession)
                        if capturePhotoOutput.supportedFlashModes.count == 3 {
                            flashSupported = true
                        } else {
                            flashSupported = false
                        }
                    } else {
                        if showDebugMessages {
                            AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: AVCapturePhotoOutput() failed")
                        } else {
                            AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: could not enable your phone's camera")
                        }
                        Crashlytics.sharedInstance().recordError(NSError(domain: "AVCapturePhotoOutput error", code: 0, userInfo: nil))
                    }
                } catch {
                    if showDebugMessages {
                        AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: capture setup error: \(error)")
                    } else {
                        AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: could not enable your phone's camera")
                    }
                    Crashlytics.sharedInstance().recordError(NSError(domain: "AVCaptureDeviceInput error", code: 0,
                                                                     userInfo: ["error": error.localizedDescription]))
                }
            }
        
        #endif
        
        if flashSupported {
            // set up flash icon/tap event handlers - start with off (flashButtonPressed will toggle from .on --> .off)
            flashMode = .on
            flashButtonPressed(sender: nil)
            tapper = UITapGestureRecognizer(target:self, action:#selector(self.flashButtonPressed(sender:)))
            tapper.numberOfTouchesRequired = 1
            flashImageView.isUserInteractionEnabled = true
            flashImageView.addGestureRecognizer(tapper)
        } else {
            flashImageView.image = nil
        }

        super.viewDidLoad()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        
        self.locationManager.stopUpdatingLocation()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // TODO - also make sure that this handles app foregrounding
        
        NotificationCenter.default.addObserver(self, selector: #selector(NewReportViewController.keyboardWillShow), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(NewReportViewController.keyboardWillHide), name: NSNotification.Name.UIKeyboardWillHide, object: nil)

        // update the email/name/phone
        self.viewModel.emailAddress.value = UserDefaults.standard.string(forKey: kUserDefaultsEmailKey)
        self.viewModel.fullName.value = UserDefaults.standard.string(forKey: kUserDefaultsNameKey)
        self.viewModel.phoneNumber.value = UserDefaults.standard.string(forKey: kUserDefaultsPhoneKey)
        
        if self.viewModel.imageLocation.value == nil {
            // continuously get locations if we don't have an image or if we have a camera photo but still need a location
            startUpdatingLocation(showAlertOnError: true)
        }
        
        // add tips, if any
        var tipView: EasyTipView
        if tipViews[.newReportMain] == nil && AppDelegate.shouldShowTip(id: .newReportMain) {
            tipView = EasyTipView(text: "Welcome to Lane Breach!\n\nUse these buttons to take a picture of a bike lane blockage or to select an existing photo",
                                  preferences: tipViewPreferences(),
                                  delegate: self)
            tipView.tag = TipIdentifier.newReportMain.rawValue
            print("adding tipview \(tipView.tag)")
            tipView.show(forView: cameraButtonsView, withinSuperview: self.view)
            tipViews[.newReportMain] = tipView
        }
        
        if tipViews[.newReportLocation] == nil && AppDelegate.shouldShowTip(id: .newReportLocation) {
            tipView = EasyTipView(text: "This icon lets you know if the app has found your location",
                                  preferences: tipViewPreferences(arrowPosition: .top),
                                  delegate: self)
            tipView.tag = TipIdentifier.newReportLocation.rawValue
            print("adding tipview \(tipView.tag)")
            tipView.show(forView: locationImageView, withinSuperview: self.view)
            tipViews[.newReportLocation] = tipView
        }
        
        if flashSupported && tipViews[.newReportFlash] == nil && AppDelegate.shouldShowTip(id: .newReportFlash) {
            tipView = EasyTipView(text: "Touch this icon to change the camera's flash mode",
                                  preferences: tipViewPreferences(verticalOffset: 100, arrowPosition: .top),
                                  delegate: self)
            tipView.tag = TipIdentifier.newReportFlash.rawValue
            print("adding tipview \(tipView.tag)")
            tipView.show(forView: flashImageView, withinSuperview: self.view)
            tipViews[.newReportFlash] = tipView
        }
    }
    
    //MARK:- Event Handlers
    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue {
            if self.controlViewToSafeAreaBottomConstraint.constant == controlViewToSafeAreaBottomDefault {
                UIView.animate(withDuration: 0.25) {
                    self.controlViewToSafeAreaBottomConstraint.constant += keyboardSize.height
                    self.view.layoutIfNeeded()
                }
            }
        }
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        if let _ = (notification.userInfo?[UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.cgRectValue {
            if self.controlViewToSafeAreaBottomConstraint.constant != controlViewToSafeAreaBottomDefault {
                UIView.animate(withDuration: 0.25) {
                    self.controlViewToSafeAreaBottomConstraint.constant = self.controlViewToSafeAreaBottomDefault
                    self.view.layoutIfNeeded()
                }
            }
        }
    }
    
    @IBAction func takePicureAction(sender: UIButton) {
        for tipview in tipViews {
            tipview.value.dismiss()
        }
        
        // Make sure capturePhotoOutput is valid
        guard let capturePhotoOutput = self.capturePhotoOutput else { return }
        
        // Get an instance of AVCapturePhotoSettings class
        let photoSettings = AVCapturePhotoSettings()
        
        // Set photo settings for our need
        photoSettings.isAutoStillImageStabilizationEnabled = true
        photoSettings.flashMode = flashSupported ? flashMode : .off
        
        // Call capturePhoto method by passing our photo settings and a
        // delegate implementing AVCapturePhotoCaptureDelegate
        capturePhotoOutput.capturePhoto(with: photoSettings, delegate: self)
    }
    
    @IBAction func photoLibraryAction(sender: UIButton) {
        for tipview in tipViews {
            tipview.value.dismiss()
        }

        let vc = UIImagePickerController()
        vc.sourceType = .photoLibrary
        vc.allowsEditing = false
        vc.delegate = self
        present(vc, animated: true)
    }
    
    @IBAction func changePhotoAction(sender: UIButton?) {
        // reset model
        self.imageView.image = nil
        self.viewModel.reset()

        // hide keyboard, if any
        self.categoryTextField.resignFirstResponder()
        self.descriptionTextField.resignFirstResponder()
        
        // show the preview + photo buttons, slide down the control panel
        self.previewView.isHidden = false
        self.cameraButtonsView.isHidden = false
        UIView.animate(withDuration: 0.25) {
            self.controlViewToSafeAreaBottomConstraint.constant = -self.controlView.frame.height
            self.view.layoutIfNeeded()
        }
        
        captureSession?.startRunning()
    }
    
    @objc func locationButtonPressed(sender: UITapGestureRecognizer?) {
        self.categoryTextField.resignFirstResponder()
        self.descriptionTextField.resignFirstResponder()

        if self.currentLocation != nil || self.viewModel.imageLocation.value != nil {
            switch self.viewModel.haveImage.value {
            case .none:
                AppDelegate.showSimpleAlertWithOK(vc: self, "Current location found. You may now SEND a new report to 311 as long as you have taken a picture and selected a category. Or you can select a photo from your library that was captured with its location.")
            case .cameraPhoto:
                AppDelegate.showSimpleAlertWithOK(vc: self, "Current location found. You may now SEND a new report to 311 as long as you have selected a category.")
            case .libraryPhoto:
                AppDelegate.showSimpleAlertWithOK(vc: self, "Image location found. You may now SEND a new report to 311 as long as you have selected a category.")
            }
        } else {
            AppDelegate.showSimpleAlertWithOK(vc: self, "Cannot determine your location - make sure that Location Services are enabled for this app in Settings.",
                                              button2title: "Settings") { (_) in
                                                
                self.gotoAppSettings()
            }
        }
    }

    @objc func flashButtonPressed(sender: UITapGestureRecognizer?) {
        guard flashSupported else {
            return
        }
        
        switch flashMode {
        case .auto:
            flashMode = .on
            flashImageView.image = UIImage(named: "ic_flash_on_black")
        case .on:
            flashMode = .off
            flashImageView.image = UIImage(named: "ic_flash_off_black")
        case .off:
            flashMode = .auto
            flashImageView.image = UIImage(named: "ic_flash_auto_black")
        }
    }
    
    @IBAction func postReportButtonPressed(sender: UIButton) {
        self.categoryTextField.resignFirstResponder()
        self.descriptionTextField.resignFirstResponder()

        guard let image = self.imageView.image else {
            return
        }
        
        // this func should not get called if we don't have an imageLocation
        guard let imageLocation = self.viewModel.imageLocation.value else {
            assert(false)
            return
        }
        
        // we already checked a library image earlier
        if !locationIsInSanFrancisco(imageLocation) {
            AppDelegate.showSimpleAlertWithOK(vc: self, "Sorry, you appear to be outside San Francisco. This app is only used to report bike lane violations within SF.")
            return
        }
        
        // TODO: probably move into model
        let filename = UUID().uuidString
        
        self.hud = JGProgressHUD(style: .dark)
        if let hud = hud {
            hud.show(in: self.view)
        }

        print("\(Date().timeIntervalSince1970) start image upload")
  
        uploadAttempts += 1
        NetworkManager.shared.uploadReport(image: image,
                                           filename: filename,
                                           location: imageLocation,
                                           emailAddress: self.viewModel.emailAddress.value,
                                           fullName: self.viewModel.fullName.value,
                                           phoneNumber: self.viewModel.phoneNumber.value,
                                           category: self.viewModel.category.value,
                                           description: self.viewModel.description.value,
                                           progressMessage: { (message) in
                                            self.hud?.textLabel.text = message
        }) { (serviceRequestId, token, error) in
            self.hud?.dismiss()
            
            var addAndResetReport = false
            if let error = error {
                // report to crashlytics as non-fatal error
                Crashlytics.sharedInstance().recordError(error)
                
                var gotTransientError: Bool
                switch error.kind {
                case .imageUploadFailed, .dataTaskNullDataOrError:
                    gotTransientError = true
                case .networkBadHTTPStatus:
                    // note: we treat HTTP status codes 400-499 as permanent errors
                    gotTransientError = (error.code < 400) || (error.code > 499)
                default:
                    gotTransientError = false
                }
                
                if gotTransientError {
                    if error.kind == .imageUploadFailed {
                        AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: uploading the image failed. Please try again.")
                    } else {
                        if self.showDebugMessages {
                            AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: uploading the report failed with transient error: \(error)")
                        } else {
                            AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: uploading the report failed (code \(error.code)). Please try again.")
                        }
                    }
                } else {
                    if self.showDebugMessages {
                        AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: uploading the report failed with permanent error: \(error)")
                    } else {
                        AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311, but we didn't get the right confirmation back (code \(error.code)). Hopefully it worked!")
                    }
                    
                    addAndResetReport = true
                }
            } else {
                var errorDomain: String
                if AppDelegate.getMockTestEnable(for: .useMockUpload) {
                    errorDomain = "MockNetworkManagerSuccess"
                } else if UserDefaults.standard.bool(forKey: kUserDefaultsUsingDevServerKey) {
                    errorDomain = "DevNetworkManagerSuccess"
                } else {
                    errorDomain = "NetworkManagerSuccess"
                }
                
                // report successful upload to crashlytics as non-fatal error
                Crashlytics.sharedInstance().recordError(NSError(domain: errorDomain, code: 0,
                                                                 userInfo: ["uploadAttempts": self.uploadAttempts]))
                
                if self.showDebugMessages {
                    if let serviceRequestId = serviceRequestId {
                        AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311 with service request ID \(serviceRequestId)")
                    } else {
                        AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311 with token \(token ?? "(null)")")
                    }
                } else {
                    AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311!")
                }
                
                addAndResetReport = true
            }
            
            if addAndResetReport {
                ReportManager.shared.addReport(location: imageLocation,
                                               description: self.viewModel.description.value,
                                               category: self.viewModel.category.value,
                                               serviceRequestId: serviceRequestId,
                                               token: token,
                                               httpPost: NetworkManager.shared.debugLastHttpPost)
            
                self.resetReport()
            }
        }
    }
    
    //MARK:- CLLocationManagerDelegate methods
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let kLocationMinCount = 3
        let kLocationMinAccuracy = 50
        let kLocationAbsoluteMinAccuracy = 100
        
        if locations.count > 0 {
            let location = locations[0]
            
            if locationCount < kLocationMinCount {
                locationCount += 1
            }
            
            // accept this location if the accuracy is good enough or we've tried a few times (and prob aren't going to get anything better)
            if ((Int(location.horizontalAccuracy) <= kLocationMinAccuracy) || (locationCount == kLocationMinCount)) &&
                (Int(location.horizontalAccuracy) <= kLocationAbsoluteMinAccuracy) {
                
                print("got location \(location.coordinate)")
                self.currentLocation = (location.coordinate, Date())
                
                // if the user took a photo and we're just waiting for a location, store it now
                if self.viewModel.haveImage.value == .cameraPhoto && self.viewModel.imageLocation.value == nil {
                    self.viewModel.imageLocation.value = location.coordinate
                }

                updateLocationIcon(found: true)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // show location error
        locationButtonPressed(sender: nil)
    }
    
    //MARK:- AVCapturePhotoCaptureDelegate methods
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // Make sure we get some photo sample buffer
        guard error == nil else {
            if showDebugMessages {
                AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: photo capture failed, error: \(error!)")
            } else {
                AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: photo capture failed")
            }
            
            Crashlytics.sharedInstance().recordError(NSError(domain: "didFinishProcessingPhoto error", code: 0,
                                                             userInfo: ["error": error!.localizedDescription]))
            return
        }
        
        // Convert photo same buffer to a jpeg image data
        guard let imageData = photo.fileDataRepresentation() else {
            if showDebugMessages {
                AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: fileDataRepresentation() failed")
            } else {
                AppDelegate.showSimpleAlertWithOK(vc: self, "ERROR: photo capture failed")
            }
            Crashlytics.sharedInstance().recordError(NSError(domain: "fileDataRepresentation error", code: 0, userInfo: nil))
            return
        }

        captureSession?.stopRunning()
        
        // Initialise a UIImage with our image data
        guard let capturedImage = UIImage.init(data: imageData , scale: 1.0),
            let fixedImage = fixOrientation(img: capturedImage) else {
                
                AppDelegate.showSimpleAlertWithOK(vc: self, "Error capturing image (failed to fix orientation)")
                Crashlytics.sharedInstance().recordError(NSError(domain: "fixOrientation error", code: 0, userInfo: nil))
                return
        }
        
        // Save our captured image to photos album
        UIImageWriteToSavedPhotosAlbum(fixedImage, nil, nil, nil)
        
        // update the image, hide the preview + photo buttons, slide up the control panel
        self.imageView.image = fixedImage
        self.previewView.isHidden = true
        self.cameraButtonsView.isHidden = true
        UIView.animate(withDuration: 0.25) {
            self.controlViewToSafeAreaBottomConstraint.constant = self.controlViewToSafeAreaBottomDefault
            self.view.layoutIfNeeded()
        }
        
        // tell the model that we have an image and a location (maybe)
        self.viewModel.haveImage.value = .cameraPhoto
        if let currentLocation = self.currentLocation {
            let age = currentLocation.1.timeIntervalSinceNow
            print("location age: \(age)")
            if age > -30 {
                self.viewModel.imageLocation.value = currentLocation.0
            }
        }

        // if we don't have a location yet for this image, kick the location manager (in theory, this is not necessary)
        if self.viewModel.imageLocation.value == nil {
            print("kicking the location manager")
            self.locationManager.stopUpdatingLocation()
            self.startUpdatingLocation(showAlertOnError: false)
        }
        
        self.uploadAttempts = 0
    }
    
    //MARK:- UIImagePickerControllerDelegate methods
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        picker.dismiss(animated: true)
        
        // note: could use UIImagePickerControllerEditedImage if allowsEditing == true
        guard let image = info[UIImagePickerControllerOriginalImage] as? UIImage else {
            AppDelegate.showSimpleAlertWithOK(vc: self, "Error capturing image (no original image)")
            Crashlytics.sharedInstance().recordError(NSError(domain: "UIImagePickerControllerOriginalImage error", code: 0, userInfo: nil))
            return
        }
        
        guard let fixedImage = fixOrientation(img: image) else {
            AppDelegate.showSimpleAlertWithOK(vc: self, "Error capturing image (failed to fix orientation)")
            Crashlytics.sharedInstance().recordError(NSError(domain: "fixOrientation error", code: 0, userInfo: nil))
            return
        }

        guard let phAsset = info[UIImagePickerControllerPHAsset] as? PHAsset,
            let coordinate = phAsset.location?.coordinate else {
                AppDelegate.showSimpleAlertWithOK(vc: self, "The selected photo does not have location information or this app does not have access to your Photo Library.",
                                                  button2title: "Settings") { (_) in
                                                    
                    self.gotoAppSettings()
                }

                return
        }
        
        if !locationIsInSanFrancisco(coordinate) {
            AppDelegate.showSimpleAlertWithOK(vc: self, "Sorry, this photo doesn't appear to have been taken in San Francisco. This app is only used to report bike lane violations within SF.")
            return
        }
        
        captureSession?.stopRunning()

        // update the image, hide the preview + photo buttons, slide up the control panel
        self.imageView.image = fixedImage
        self.previewView.isHidden = true
        self.cameraButtonsView.isHidden = true
        UIView.animate(withDuration: 0.25) {
            self.controlViewToSafeAreaBottomConstraint.constant = self.controlViewToSafeAreaBottomDefault
            self.view.layoutIfNeeded()
        }
        
        // tell the model that we have an image
        self.viewModel.haveImage.value = .libraryPhoto
        self.viewModel.imageLocation.value = coordinate
        updateLocationIcon(found: true)
        self.uploadAttempts = 0
    }
    
    //MARK:- UIPickerViewDataSource/UIPickerViewDelegate methods
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return self.viewModel.categories.count
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return self.viewModel.categories[row]
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.viewModel.category.value = self.viewModel.categories[row]
    }
    
    @objc func donePicker(_ sender: Any) {
        if let picker = self.categoryTextField.inputView as? UIPickerView {
            // update the category even if the user didn't change the value (only applies when "Other" is initially selected)
            self.viewModel.category.value = self.viewModel.categories[picker.selectedRow(inComponent: 0)]
        }
        
        self.categoryTextField.resignFirstResponder()
    }

    //MARK:- UITextFieldDelegate
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // update the description AFTER we return
        DispatchQueue.main.async {
            self.viewModel.description.value = textField.text ?? ""
        }
        
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        return true
    }
    
    //MARK:- EasyTipViewDelegate
    func easyTipViewDidDismiss(_ tipView : EasyTipView) {
        if let tipId = TipIdentifier(rawValue: tipView.tag) {
            AppDelegate.hideTip(id: tipId)
            
            tipViews.removeValue(forKey: tipId)
            print("tipViews.count: \(tipViews.count)")
        }
    }
}

