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
    let description: MutableProperty<String>
    let category: MutableProperty<String>
    let haveImage: MutableProperty<PendingImageType>
    let currentLocation: MutableProperty<CLLocationCoordinate2D?>
    
    var categorySignal: Signal<String, NoError>
    var descriptionSignal: Signal<String, NoError>
    var okToSendSignal: Signal<Bool, NoError>
    var locationStatusSignal: Signal<Bool, NoError>
    
    let categories: [String] = ["Private vehicle", "Delivery truck", "Moving truck", "FedEx", "UPS", "USPS", "Bus",
                                "Commuter Shuttle", "Uber", "Lyft", "Uber/Lyft",
                                defaultCategory]    //  TODO/FUTURE - let user enter optional text to replace "other"?
    
    init(initialCategory: String) {
        self.emailAddress = MutableProperty(nil)
        self.fullName = MutableProperty(nil)
        self.phoneNumber = MutableProperty(nil)
        self.description = MutableProperty("")
        self.category = MutableProperty("")
        self.haveImage = MutableProperty(.none)
        self.currentLocation = MutableProperty(nil)
        
        self.categorySignal = self.category.signal
        self.descriptionSignal = self.description.signal
        
        // output true if the email address has 3+ chars and we have a valid category/image/location
        self.okToSendSignal = Signal.combineLatest(self.category.signal, self.haveImage.signal, self.currentLocation.signal)
            .map { (arg) -> Bool in
                
                let (category, haveImage, currentLocation) = arg
                
                print("category=\(category), haveImage=\(haveImage), currentLocation=\(String(describing: currentLocation))")
                return (category.count > 1) && (haveImage != .none) && (currentLocation != nil)
        }
        
        self.locationStatusSignal = self.currentLocation.signal
            .map { (currentLocation) -> Bool in
                return currentLocation != nil
        }
        
        DispatchQueue.main.async {
            // set this after configuring categorySignal so that this gets tracked as a change
            // do this async so that binding code executing immediately after we are constructed will complete first
            self.category.value = initialCategory
        }
    }
}
