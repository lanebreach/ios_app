//
//  NewReportViewModel.swift
//  blfa
//
//  Created by Dale Low on 2/15/19.
//  Copyright © 2019 Dale Low. All rights reserved.
//

import CoreLocation
import Foundation
import ReactiveCocoa
import ReactiveSwift
import Result

enum PendingImageType {
    case none
    case libraryPhoto
    case cameraPhoto
}

class NewReportViewModel {
    static let defaultCategory: String = "Other"
    
    let emailAddress: MutableProperty<String?>
    let fullName: MutableProperty<String?>
    let phoneNumber: MutableProperty<String?>
    
    let category: MutableProperty<String>
    let description: MutableProperty<String>
    let haveImage: MutableProperty<PendingImageType>
    let imageLocation: MutableProperty<CLLocationCoordinate2D?>
    let imageSourceCamera: MutableProperty<Bool?>
    let imageDate: MutableProperty<Date?>
    
    var categorySignal: Signal<String, NoError>
    var descriptionSignal: Signal<String, NoError>
    var okToSendSignal: Signal<Bool, NoError>
    var locationStatusSignal: Signal<Bool, NoError>
    
    //  TODO/FUTURE - let user enter optional text to replace "other"?
    let categories: [String] = [defaultCategory, "Private vehicle", "Delivery truck", "Moving truck", "FedEx", "UPS", "USPS", "Bus",
                                "Commuter Shuttle", "Uber", "Lyft", "Uber/Lyft"]
    
    init() {
        self.emailAddress = MutableProperty(nil)
        self.fullName = MutableProperty(nil)
        self.phoneNumber = MutableProperty(nil)
        
        self.description = MutableProperty("")
        self.category = MutableProperty("")
        self.haveImage = MutableProperty(.none)
        self.imageLocation = MutableProperty(nil)
        self.imageSourceCamera = MutableProperty(nil)
        self.imageDate = MutableProperty(nil)
        
        self.categorySignal = self.category.signal
        self.descriptionSignal = self.description.signal
        
        // output true if the email address has 3+ chars and we have a valid category/image/location
        self.okToSendSignal = Signal.combineLatest(self.category.signal, self.haveImage.signal, self.imageLocation.signal)
            .map { (arg) -> Bool in
                
                let (category, haveImage, imageLocation) = arg
                
                print("category=\(category), haveImage=\(haveImage), imageLocation=\(String(describing: imageLocation))")
                return (category.count > 1) && (haveImage != .none) && (imageLocation != nil)
        }
        
        self.locationStatusSignal = self.imageLocation.signal
            .map { (imageLocation) -> Bool in
                return imageLocation != nil
        }
        
        DispatchQueue.main.async {
            // set this after configuring categorySignal so that this gets tracked as a change
            // do this async so that binding code executing immediately after we are constructed will complete first
            self.reset()
        }
    }
    
    // note: this does not reset the user properties (email/name/phone)
    func reset() {
        self.haveImage.value = .none
        self.imageLocation.value = nil
        self.imageSourceCamera.value = nil
        self.imageDate.value = nil
        self.category.value = NewReportViewModel.defaultCategory
        self.description.value = ""
    }
}
