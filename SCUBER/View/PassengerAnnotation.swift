//
//  PassengerAnnotation.swift
//  SCUBER
//
//  Created by Nick Bruinsma on 03/04/2019.
//  Copyright © 2019 appeeme. All rights reserved.
//

import Foundation
import MapKit

class PassengerAnnotation: NSObject, MKAnnotation {
    dynamic var coordinate: CLLocationCoordinate2D
    var key: String
    
    init(coordinate: CLLocationCoordinate2D, key: String) {
        self.coordinate = coordinate
        self.key = key
        super.init()
    }
}
