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
import UserNotifications

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
    @IBOutlet weak var zoomContainerView: UIView!
    @IBOutlet weak var zoomImageView: UIImageView!
    @IBOutlet weak var zoomFactorLabel: UILabel!
    
    @IBOutlet weak var controlView: UIView!
    @IBOutlet weak var controlViewToSafeAreaBottomConstraint : NSLayoutConstraint!
    @IBOutlet weak var categoryTextField: UITextField!
    @IBOutlet weak var licenseTextField: UITextField!
    @IBOutlet weak var descriptionTextField: UITextField!
    @IBOutlet weak var cameraButtonsView: UIView!
    @IBOutlet weak var changePhotoButton: UIButton!
    @IBOutlet weak var postReportButton: UIButton!
    
    lazy var viewModel = NewReportViewModel()
    
    // credit: https://medium.com/@rizwanm/https-medium-com-rizwanm-swift-camera-part-1-c38b8b773b2
    var captureDevice: AVCaptureDevice?
    var captureSession: AVCaptureSession?
    var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    var capturePhotoOutput: AVCapturePhotoOutput?
    var flashSupported: Bool = false
    var flashMode: AVCaptureDevice.FlashMode = .auto
    var currentZoomLevel = 1
    var maximumZoomLevel = 1
    
    lazy var categoryPicker = UIPickerView()
    var locationManager = CLLocationManager()
    var hud: JGProgressHUD?
    var tipViews: [TipIdentifier:EasyTipView] = [:]
    var currentLocation: (CLLocationCoordinate2D, Date)?
    var locationCount = 0
    var uploadAttempts = 0
    
    //MARK:- Internal methods
    func enableCamera() {
        #if (!targetEnvironment(simulator))
        
        guard captureDevice == nil else {
            return
        }
        
        // preview image
        captureDevice = AVCaptureDevice.default(for: .video)
        if let captureDevice = captureDevice {
            do {
                // set max zoom to be 4x, 2x or 1x
                maximumZoomLevel = (captureDevice.activeFormat.videoMaxZoomFactor >= 4) ? 4 :
                    ((captureDevice.activeFormat.videoMaxZoomFactor >= 2) ? 2 : 1)
                
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
            let tapper = UITapGestureRecognizer(target:self, action:#selector(self.flashButtonPressed(sender:)))
            tapper.numberOfTouchesRequired = 1
            flashImageView.isUserInteractionEnabled = true
            flashImageView.addGestureRecognizer(tapper)
        } else {
            flashImageView.image = nil
        }
    }
    
    func showControlPanel(_ show: Bool) {
        self.previewView.isHidden = show
        self.flashImageView.isHidden = show
        self.zoomContainerView.isHidden = show
        self.cameraButtonsView.isHidden = show
        UIView.animate(withDuration: 0.25) {
            self.controlViewToSafeAreaBottomConstraint.constant = show ? self.controlViewToSafeAreaBottomDefault : -self.controlView.frame.height
            self.view.layoutIfNeeded()
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
        preferences.drawing.backgroundColor = AppDelegate.brandColor(purpose: .main)
        preferences.drawing.arrowHeight = verticalOffset
        preferences.drawing.arrowPosition = arrowPosition
        
        return preferences
    }
    
    func updateLocationIcon(found: Bool) {
        self.locationImageView.image = UIImage(named: found ? "ic_location_black" : "ic_location_bad_black")
    }
    
    func startUpdatingLocation(showAlertOnError: Bool) {
        locationCount = 0
        currentLocation = nil
        updateLocationIcon(found: false)
        
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.delegate = self
        self.locationManager.startUpdatingLocation()
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
        
        // react to model changes
        self.categoryTextField.reactive.text <~ self.viewModel.categorySignal
        self.licenseTextField.reactive.text <~ self.viewModel.licenseSignal
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
        self.viewModel.categorySignal.observeValues { (value) in
            // make sure that the picker is in sync with the category
            // (this really only happens when the viewModel is reset)
            if let index = self.viewModel.categories.firstIndex(of: value),
                index < self.categoryPicker.numberOfRows(inComponent: 0) {
                
                if self.categoryPicker.selectedRow(inComponent: 0) != index {
                    self.categoryPicker.selectRow(index, inComponent: 0, animated: false)
                }
            }
        }
        
        // can't take pics using the sim
        #if (targetEnvironment(simulator))
            self.takePictureButton.isEnabled = false
        #endif

        // hide control view below the screen
        self.controlViewToSafeAreaBottomConstraint.constant = -self.controlView.frame.height
        self.controlView.layer.cornerRadius = 5
        self.cameraButtonsView.layer.cornerRadius = 5
        self.licenseTextField.delegate = self
        self.descriptionTextField.delegate = self
        
        // category picker/toolbar
        categoryPicker.dataSource = self
        categoryPicker.delegate = self
        categoryPicker.showsSelectionIndicator = true
        self.categoryTextField.inputView = categoryPicker
        self.categoryTextField.tintColor = .clear   // hides the cursor
        
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
        
        // set up zoom label/tap event handlers
        zoomFactorLabel.text = "\(currentZoomLevel)x"
        tapper = UITapGestureRecognizer(target:self, action:#selector(self.zoomButtonPressed(sender:)))
        tapper.numberOfTouchesRequired = 1
        zoomImageView.isUserInteractionEnabled = true
        zoomImageView.addGestureRecognizer(tapper)
        
        super.viewDidLoad()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        
        self.locationManager.stopUpdatingLocation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if !PermissionViewController.needOneOrMorePermissions(includeOptional: false) {
            enableCamera()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // TODO - also make sure that this handles app foregrounding

        if PermissionViewController.needOneOrMorePermissions(includeOptional: false) {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let controller = storyboard.instantiateViewController(withIdentifier: "PermissionViewController")
            self.present(controller, animated: true, completion: nil)
            return
        }
        
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
        self.licenseTextField.resignFirstResponder()
        self.descriptionTextField.resignFirstResponder()
        
        // show the preview + photo buttons, slide down the control panel
        showControlPanel(false)
        
        captureSession?.startRunning()
    }
    
    @objc func locationButtonPressed(sender: UITapGestureRecognizer?) {
        self.categoryTextField.resignFirstResponder()
        self.licenseTextField.resignFirstResponder()
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
                    
                AppDelegate.gotoAppSettings()
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
    
    @objc func zoomButtonPressed(sender: UITapGestureRecognizer?) {
        guard let captureDevice = captureDevice, (try? captureDevice.lockForConfiguration()) != nil else {
            return
        }

        currentZoomLevel *= 2
        if currentZoomLevel > maximumZoomLevel {
            currentZoomLevel = 1
        }
        
        zoomFactorLabel.text = "\(currentZoomLevel)x"
        captureDevice.videoZoomFactor = CGFloat(currentZoomLevel)
        captureDevice.unlockForConfiguration()
    }

    @IBAction func postReportButtonPressed(sender: UIButton) {
        self.categoryTextField.resignFirstResponder()
        self.licenseTextField.resignFirstResponder()
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
                                           license: self.viewModel.license.value,
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
                var eventDomain: String
                if AppDelegate.getMockTestEnable(for: .useMockUpload) {
                    eventDomain = "MockNetworkManagerSuccess"
                } else if UserDefaults.standard.bool(forKey: kUserDefaultsUsingDevServerKey) {
                    eventDomain = "DevNetworkManagerSuccess"
                } else {
                    eventDomain = "NetworkManagerSuccess"
                }
                
                // report successful upload to Fabric
                var customAttributes: [String: Any] = [ "uploadAttempts": self.uploadAttempts]
                if let imageSourceCamera = self.viewModel.imageSourceCamera.value {
                    customAttributes["imageSourceCamera"] = imageSourceCamera ? "true" : "false"
                }
                if let imageSourceDate = self.viewModel.imageDate.value {
                    // use logarithmic scale for time delta
                    //log(1.0 or 1 sec) = 0
                    //log(2.7 or 2 sec) = 1
                    //log(7.4 or 7 sec) = 2
                    //log(20.1 or 20 sec) = 3
                    //log(54.6 or 54 sec) = 4
                    //log(148.4 or 2.5 min) = 5
                    //log(403.4 or 6.7 min) = 6
                    //log(1096.6 or 18.3 min) = 7
                    //log(2981.0 or 49.7 min) = 8
                    //log(8103.1 or 2.3 hours) = 9
                    //log(22026.5 or 6.1 hours) = 10
                    //log(59874.1 or 16.6 hours) = 11
                    //log(162754.8 or 1.9 days) = 12
                    //log(442413.4 or 5.1 days) = 13
                    //log(1202604.3 or 13.9 days) = 14
                    //log(3269017.4 or 37.8 days) = 15
                    //log(8886110.5 or 102.8 days) = 16
                    //log(24154952.8 or 279.6 days) = 17
                    //log(65659969.1 or 760.0 days) = 18
                    //log(178482301.0 or 2065.8 days) = 19
                    let timeDelta = Date().timeIntervalSince(imageSourceDate)
                    if timeDelta > 0 {
                        customAttributes["imageTimeDelta"] = NSNumber(integerLiteral: Int(round(log(timeDelta + 1))))
                    }
                }
                Answers.logCustomEvent(withName: eventDomain, customAttributes: customAttributes)
                
                // (1) alert to user
                if self.showDebugMessages {
                    if let serviceRequestId = serviceRequestId {
                        AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311 with service request ID \(serviceRequestId)")
                    } else {
                        AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311 with token \(token ?? "(null)")")
                    }
                } else {
                    AppDelegate.showSimpleAlertWithOK(vc: self, "New request submitted to 311!")
                }
                
                // (2) post a user notification (if notifs are enabled)
                UNUserNotificationCenter.current().getNotificationSettings { (settings) in
                    guard settings.authorizationStatus == .authorized else { return }

                    let content = UNMutableNotificationContent()
                    content.title = "Upload successful"
                    content.body = "Your new report has been submitted to 311!"
                    
                    // show immediately
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval:0.1, repeats: false)
                    
                    let request = UNNotificationRequest(identifier: "ContentIdentifier", content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request) { (error) in
                        if error != nil {
                            print("error \(String(describing: error))")
                        }
                    }
                }

                addAndResetReport = true
            }
            
            if addAndResetReport {
                ReportManager.shared.addReport(location: imageLocation,
                                               description: self.viewModel.description.value,
                                               category: self.viewModel.category.value,
                                               license: self.viewModel.license.value,
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
        print("location error: \(error)")
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
        guard let capturedImage = UIImage(data: imageData , scale: 1.0),
            let fixedImage = fixOrientation(img: capturedImage) else {
                
                AppDelegate.showSimpleAlertWithOK(vc: self, "Error capturing image (failed to fix orientation)")
                Crashlytics.sharedInstance().recordError(NSError(domain: "fixOrientation error", code: 0, userInfo: nil))
                return
        }
        
        // Save our captured image to photos album
        UIImageWriteToSavedPhotosAlbum(fixedImage, nil, nil, nil)
        
        // update the image, hide the preview + photo buttons, slide up the control panel
        self.imageView.image = fixedImage
        showControlPanel(true)
        
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
        
        self.viewModel.imageSourceCamera.value = true
        self.viewModel.imageDate.value = Date()

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
                AppDelegate.showSimpleAlertWithOK(vc: self, "The selected photo does not have location information. Go to Location Services in Settings and make sure that the Camera and Photos apps have \"While Using\" enabled.",
                                                  button2title: "Settings") { (_) in
                         
                    AppDelegate.gotoAppSettings()
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
        showControlPanel(true)

        // tell the model that we have an image
        self.viewModel.haveImage.value = .libraryPhoto
        self.viewModel.imageLocation.value = coordinate
        self.viewModel.imageSourceCamera.value = false
        self.viewModel.imageDate.value = phAsset.creationDate   // might be nil
        
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
        print("selected category: \(self.viewModel.category.value)")
        self.categoryTextField.resignFirstResponder()
    }

    //MARK:- UITextFieldDelegate
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == self.descriptionTextField {
            self.viewModel.description.value = textField.text ?? ""
        } else if textField == self.licenseTextField {
            self.viewModel.license.value = textField.text ?? ""
        }
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

