//
//  MapViewController.swift
//  blfa
//
//  Created by Dale Low on 10/3/18.
//  Copyright © 2018 Dale Low. All rights reserved.
//

import UIKit
import AWSDynamoDB
import MapKit

class BikeLaneReport : AWSDynamoDBObjectModel, AWSDynamoDBModeling  {
    @objc var service_request_id:String?
    @objc var supervisor_district:String?
    @objc var updated_datetime:String?
    @objc var address:String?
    @objc var lat:String?
    @objc var long:String?
    
    class func dynamoDBTableName() -> String {
        return "BikeLaneReports"
    }
    
    class func hashKeyAttribute() -> String {
        return "service_request_id"
    }
}

//class MapPin : NSObject, MKAnnotation {
//    var coordinate: CLLocationCoordinate2D
//    var title: String?
//    var subtitle: String?
//
//    init(coordinate: CLLocationCoordinate2D, title: String, subtitle: String) {
//        self.coordinate = coordinate
//        self.title = title
//        self.subtitle = subtitle
//    }
//}

class MapViewController: UIViewController, MKMapViewDelegate {
    @IBOutlet weak var mapView: MKMapView!

    // credit: https://stackoverflow.com/questions/4680649/zooming-mkmapview-to-fit-annotation-pins/4681546
    func zoomMapFitAnnotations() {
        var zoomRect = MKMapRectNull
        for annotation in self.mapView.annotations {
            
            let annotationPoint = MKMapPointForCoordinate(annotation.coordinate)
            
            let pointRect = MKMapRectMake(annotationPoint.x, annotationPoint.y, 0, 0)
            
            if (MKMapRectIsNull(zoomRect)) {
                zoomRect = pointRect
            } else {
                zoomRect = MKMapRectUnion(zoomRect, pointRect)
            }
        }
        self.mapView.setVisibleMapRect(zoomRect, edgePadding: UIEdgeInsetsMake(50, 50, 50, 50), animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let dynamoDBObjectMapper = AWSDynamoDBObjectMapper.default()
        let resultsBlock = { (task: AWSTask<AWSDynamoDBPaginatedOutput>) -> Any? in
            if let error = task.error as NSError? {
                print("Error: \(error)")
                return nil
            } else if let paginatedOutput = task.result {
                DispatchQueue.main.async {
                    //print("paginatedOutput: \(paginatedOutput)")
                    for item in paginatedOutput.items as! [BikeLaneReport] {
                        print("ID \(item.service_request_id!) - date: \(item.updated_datetime!), addr: \(item.address ?? "Unknown"), loc \(item.lat ?? "Unknown"), \(item.long ?? "Unknown")")
                        
                        if let lat = item.lat,
                            let long = item.long,
                            let latitude = Double(lat),
                            let longitude = Double(long) {
                            
                            // TODO - better annotation, possibly including image
                            let annotation = MKPointAnnotation()
                            annotation.title = item.address ?? "Unknown"
                            annotation.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                            self.mapView.addAnnotation(annotation)
                        }
                    }
                    
                    let lastEvaluatedKey:[String : AWSDynamoDBAttributeValue]! = paginatedOutput.lastEvaluatedKey
                    if lastEvaluatedKey == nil {
                        print("nothing else to load")
                    } else {
                        // TODO - use this key as the "exclusiveStartKey" for a subsequent scan request
                        print("lastEvaluatedKey: \(lastEvaluatedKey!)")
                    }

                    self.zoomMapFitAnnotations()
                }
            }
            
            return nil
        }
        
#if true
        // (a) AWSDynamoDBScanExpression
        let scanExpression = AWSDynamoDBScanExpression()
        
        // this might cause a problem later is the result exceeds 1 MB
        scanExpression.limit = 9999

        /*
         Per https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Scan.html:
         
         The Scan operation returns one or more items and item attributes by accessing every item in a table or a secondary index.
         To have DynamoDB return fewer items, you can provide a FilterExpression operation.
         
         If the total number of scanned items exceeds the maximum data set size limit of 1 MB, the scan stops and results are returned
         to the user as a LastEvaluatedKey value to continue the scan in a subsequent operation. The results also include the number
         of items exceeding the limit. A scan can result in no table data meeting the filter criteria.
         */
        
        // example 1 (works):
//        scanExpression.filterExpression = "service_request_id > :val"
//        scanExpression.expressionAttributeValues = [":val": "9157514"]

        // example 2 (works):
        // fetch reports starting 4 weeks ago
        let date = Date(timeIntervalSinceNow: -28*86400)
        
        let RFC3339DateFormatter = DateFormatter()
        RFC3339DateFormatter.locale = Locale(identifier: "en_US_POSIX")
        RFC3339DateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let earliestReportDate = RFC3339DateFormatter.string(from: date)

        print("keeping reports newer than \(earliestReportDate)")
        scanExpression.filterExpression = "closed_date > :val"
        scanExpression.expressionAttributeValues = [":val": earliestReportDate]
        //scanExpression.exclusiveStartKey = returned LastEvaluatedKey  // TODO - to start at a specific point

        dynamoDBObjectMapper.scan(BikeLaneReport.self, expression: scanExpression).continueWith(block: resultsBlock)
#endif
        
#if false
        // (b) AWSDynamoDBQueryExpression
        let queryExpression = AWSDynamoDBQueryExpression()
        queryExpression.projectionExpression = "service_request_id, updated_datetime, address, lat, #long"
        queryExpression.expressionAttributeNames = ["#long": "long"]

        /*
         Per https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_Query.html:
         
         Use the KeyConditionExpression parameter to provide a specific value for the partition key.
         The Query operation will return all of the items from the table or index with that partition key value.
         You can optionally narrow the scope of the Query operation by specifying a sort key value and a
         comparison operator in KeyConditionExpression.
         */
        
        // TODO - this is a problem because we can only request a single item where service_request_id = X
        // fix by adding "Global Secondary Indexes (GSI)" or changing the primary partition key to "supervisor_district"
        queryExpression.keyConditionExpression = "service_request_id = :service_request_id"
        queryExpression.expressionAttributeValues = [":service_request_id": "9604347"]
        
        queryExpression.limit = 10

        dynamoDBObjectMapper.query(BikeLaneReport.self, expression: queryExpression).continueWith(block: resultsBlock)
#endif
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard annotation is MKPointAnnotation else { return nil }
        
        let identifier = "Annotation"
        var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
        
        if annotationView == nil {
            annotationView = MKPinAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView!.canShowCallout = true
        } else {
            annotationView!.annotation = annotation
        }
        
        return annotationView
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}
