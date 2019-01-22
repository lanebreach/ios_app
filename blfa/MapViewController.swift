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
    @IBOutlet weak var mapView: MKMapView!
    var hud: JGProgressHUD?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // hide the old map view since we're not using it right now
        self.mapView.isHidden = true
        
        let url = URL(string: "mapbox://styles/agaesser/cjn5lb26b0gty2rnr3laj0ljd")
        let mapView = MGLMapView(frame: view.bounds, styleURL: url)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        view.addSubview(mapView)

        DispatchQueue.main.async {
            // set the center to Twin Peaks
            // note: setting the center doesn't seem to work after MGLMapView construction
            mapView.setCenter(CLLocationCoordinate2D(latitude: 37.759108, longitude: -122.450577), zoomLevel: 11, animated: true)
        }
        
        // add Twin Peaks to the map for, well, fun
//        let twinPeaks = MGLPointAnnotation()
//        twinPeaks.coordinate = CLLocationCoordinate2D(latitude: 37.759108, longitude: -122.450577)
//        twinPeaks.title = "Twin Peaks"
//        twinPeaks.subtitle = "The best place to see the City"
//        mapView.addAnnotation(twinPeaks)
        
        hud = JGProgressHUD(style: .dark)
        if let hud = hud {
            hud.textLabel.text = "Loading"
            hud.show(in: self.view)
        }
    }
    
    func mapView(_ mapView: MGLMapView, didFinishLoading style: MGLStyle) {
        print("didFinishLoading")
        
        hud?.dismiss()
    }
    
    func mapView(_ mapView: MGLMapView, annotationCanShowCallout annotation: MGLAnnotation) -> Bool {
        // Always allow callouts to popup when annotations are tapped.
        return true
    }
}
