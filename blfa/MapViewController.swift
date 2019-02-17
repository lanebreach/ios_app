//
//  MapViewController.swift
//  blfa
//
//  Created by Dale Low on 10/3/18.
//  Copyright © 2018 Dale Low. All rights reserved.
//

import AWSDynamoDB
import UIKit
import JGProgressHUD
import MapKit
import Mapbox

class MapViewController: UIViewController, MGLMapViewDelegate {
    var mapView: MGLMapView?
    var hud: JGProgressHUD?
    var mapLoaded = false
    var viewVisible = false
    
    //MARK:- Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        let url = URL(string: "mapbox://styles/agaesser/cjn5lb26b0gty2rnr3laj0ljd")
        mapView = MGLMapView(frame: view.bounds, styleURL: url)
        guard let mapView = mapView else {
            return
        }
        
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        view.addSubview(mapView)

        DispatchQueue.main.async {
            // set the center to Twin Peaks
            // note: setting the center doesn't seem to work after MGLMapView construction
            mapView.setCenter(CLLocationCoordinate2D(latitude: 37.759108, longitude: -122.450577), zoomLevel: 11, animated: true)
        }
        
        hud = JGProgressHUD(style: .dark)
        if let hud = hud {
            hud.textLabel.text = "Loading"
            hud.show(in: self.view)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        viewVisible = false
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        viewVisible = true
        if mapLoaded {
            addReportAnnotations()
        }
    }
    
    //MARK:- Internal methods
    func addReportAnnotations() {
        guard let mapView = mapView else {
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "M/dd h:mma"
        
        // update all annotations of user-submitted reports
        if let annotations = mapView.annotations {
            mapView.removeAnnotations(annotations)
        }
        
        // add Twin Peaks to the map for, well, fun
        if AppDelegate.getMockTestEnable(for: .showTwinPeaks) {
            let twinPeaks = MGLPointAnnotation()
            twinPeaks.coordinate = CLLocationCoordinate2D(latitude: 37.759108, longitude: -122.450577)
            twinPeaks.title = "Twin Peaks"
            twinPeaks.subtitle = "The best place to see the City"
            mapView.addAnnotation(twinPeaks)
        }
        
        let kMaxDescriptionLen = 16
        if let reports = ReportManager.shared.getReports() {
            for report in reports {
                let reportAnnotation = MGLPointAnnotation()
                reportAnnotation.coordinate = CLLocationCoordinate2D(latitude: report["lat"] as! CLLocationDegrees,
                                                                     longitude: report["long"] as! CLLocationDegrees)
                
                var info = ""
                if let description = report["description"] as? String {
                    info = String(description.prefix(kMaxDescriptionLen))
                    if description.count > kMaxDescriptionLen {
                        info += "..."
                    }
                }
                if let category = report["category"] as? String {
                    info += ((info.count > 0) ? " " : "") + "(\(category))"
                }
                
                reportAnnotation.title = info
                
                if let date = report["date"] as? Date {
                    reportAnnotation.subtitle = dateFormatter.string(from: date)
                }
                
                mapView.addAnnotation(reportAnnotation)
            }
        }
    }

    //MARK:- MGLMapViewDelegate
    func mapView(_ mapView: MGLMapView, didFinishLoading style: MGLStyle) {
        print("didFinishLoading")
        
        hud?.dismiss()
        mapLoaded = true

        if viewVisible {
            addReportAnnotations()
        }
    }
    
    func mapView(_ mapView: MGLMapView, annotationCanShowCallout annotation: MGLAnnotation) -> Bool {
        // Always allow callouts to popup when annotations are tapped.
        return true
    }
}
