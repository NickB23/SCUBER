//
//  ViewController.swift
//  SCUBER
//
//  Created by Nick Bruinsma on 01/04/2019.
//  Copyright © 2019 appeeme. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation
import RevealingSplashView
import Firebase

enum AnnotationType {
    case pickup
    case destination
}

enum ButtonAction {
    case requestRide
    case getDirectionsToPassenger
    case getDirectionsToDestination
    case startTrip
    case endTrip
}

class HomeVC: UIViewController, Alertable {

    @IBOutlet weak var centerMapButton: UIButton!
    @IBOutlet weak var actionBtn: RoundedShadowButton!
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var destinationTextField: UITextField!
    @IBOutlet weak var destinationCircle: CircleView!
    @IBOutlet weak var cancelButton: UIButton!

    var delegate: CenterVCDelegate?
    var manager: CLLocationManager?
    var currentUserID: String?
    var regionRadius: CLLocationDistance = 1000
    var revealingSplashView = RevealingSplashView(iconImage: UIImage(named: "launchScreenIcon")!, iconInitialSize: CGSize(width: 80, height: 80), backgroundColor: UIColor.white)
    var matchingItems = [MKMapItem]()
    var route: MKRoute!
    var selectedItemPlacemark: MKPlacemark? = nil
    var actionForButton: ButtonAction = .requestRide
    var tableView = UITableView()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if currentUserID == nil {
            // Set arbitrary userID if userID is nil
            currentUserID = ACCOUNT_NOT_LOGGED_IN
        } else {
            currentUserID = Auth.auth().currentUser?.uid
        }
        

        DataService.instance.checkIfUserIsDriver(userKey: currentUserID!) { (isDriver) in
            if isDriver == true {
                self.setButtonsForDriver(hidden: true)
            }
        }

        DataService.instance.checkIfDriverIsOnTrip(driverKey: self.currentUserID!) { (isOnTrip, driverKey, tripKey) in
            if isOnTrip == true {
                DataService.instance.REF_TRIPS.observeSingleEvent(of: .value, with: { (tripSnapshot) in
                    if let tripSnapshot = tripSnapshot.children.allObjects as? [DataSnapshot] {
                        for trip in tripSnapshot {
                            if trip.childSnapshot(forPath: DRIVER_KEY).value as? String == self.currentUserID! {
                                let pickupCoordinateArray = trip.childSnapshot(forPath: USER_PICKUP_COORDINATE).value as! NSArray
                                let pickupCoordinate = CLLocationCoordinate2D(latitude: pickupCoordinateArray[0] as! CLLocationDegrees, longitude: pickupCoordinateArray[1] as! CLLocationDegrees)
                                let pickupPlacemark = MKPlacemark(coordinate: pickupCoordinate)
                                self.dropPinFor(placemark: pickupPlacemark)
                                self.searchMapKitForResultsWithPolyline(forOriginMapItem: nil, withDestinationMapItem: MKMapItem(placemark: pickupPlacemark))
                                self.setCustomRegion(forAnnotationType: .pickup, withCoordinate: pickupCoordinate)
                                self.actionForButton = .getDirectionsToPassenger
                                self.actionBtn.setTitle(MSG_GET_DIRECTIONS, for: .normal)
                                self.setButtonsForDriver(hidden: false)
                            }
                        }
                    }
                })
            }
        }

        DataService.instance.REF_TRIPS.observe(.childRemoved) { (removedTripSnapshot) in
            if let removedTripDict = removedTripSnapshot.value as? [String: AnyObject] {
                if removedTripDict[DRIVER_KEY] != nil {
                    DataService.instance.REF_DRIVERS.child(removedTripDict[DRIVER_KEY] as! String).updateChildValues([DRIVER_IS_ON_TRIP: false])
                }

                DataService.instance.checkIfUserIsDriver(userKey: self.currentUserID!, handler: { (isDriver) in
                    if isDriver == true {
                        // Remove overlays and annotations
                        // hide request ride button and cancel button
                        self.removeOverlaysAndAnnotations(forDrivers: false, forPassengers: true)
                    } else {

                        self.cancelButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
                        self.actionBtn.animateButton(shouldLoad: false, withMessage: MSG_REQUEST_RIDE)

                        self.destinationTextField.isUserInteractionEnabled = true
                        self.destinationTextField.text = ""
                        self.removeOverlaysAndAnnotations(forDrivers: false, forPassengers: true)
                        self.centerMapOnUserLocation()
                    }
                })
            }
        }

        connectUserAndDriverForTrip()

    }

    override func viewDidLoad() {
        super.viewDidLoad()

        currentUserID = Auth.auth().currentUser?.uid

        manager = CLLocationManager()
        manager?.delegate = self
        manager?.desiredAccuracy = kCLLocationAccuracyBest
        checkLocationAuthStatus()

        mapView.delegate = self
        destinationTextField.delegate = self

        cancelButton.alpha = 0.0

        centerMapOnUserLocation()

        DataService.instance.REF_DRIVERS.observe(.value) { (snapshot) in
            self.loadDriverAnnotationsFromFB()

            DataService.instance.checkIfPassengerIsOnTrip(passengerKey: self.currentUserID!, handler: { (isOnTrip, driverKey, tripKey) in
                if isOnTrip == true {
                    self.zoom(toFitAnnotationsFromMapview: self.mapView, forActiveTripWithDriver: true, withKey: driverKey)
                }
            })
        }

        self.view.addSubview(revealingSplashView)
        revealingSplashView.animationType = SplashAnimationType.heartBeat
        revealingSplashView.startAnimation()

        UpdateService.instance.observeTrips { (tripDict) in
            if let tripDict = tripDict {
                let pickupCoordinateArray = tripDict[USER_PICKUP_COORDINATE] as! NSArray
                let tripKey = tripDict[USER_PASSENGER_KEY] as! String
                let acceptanceStatus = tripDict[TRIP_IS_ACCEPTED] as! Bool

                if acceptanceStatus == false {
                    DataService.instance.checkIfDriverIsAvailable(key: self.currentUserID!, handler: { (available) in
                        if let available = available {
                            if available {
                                let storyboard = UIStoryboard(name: MAIN_STORYBOARD, bundle: Bundle.main)
                                let pickupVC = storyboard.instantiateViewController(withIdentifier: VC_PICKUP) as? PickupVC
                                pickupVC?.initData(coordinate: CLLocationCoordinate2D(latitude: pickupCoordinateArray[0] as! CLLocationDegrees, longitude: pickupCoordinateArray[1] as! CLLocationDegrees), passengerKey: tripKey)
                                self.present(pickupVC!, animated: true, completion: nil)
                            }
                        }
                    })
                }
            }
        }
    }

    func checkLocationAuthStatus() {
        if CLLocationManager.authorizationStatus() == .authorizedAlways {
            manager?.startUpdatingLocation()
        } else {
            manager?.requestAlwaysAuthorization()
            manager?.requestLocation()
        }
    }

    func setButtonsForDriver(hidden: Bool) {
        if hidden {
            self.actionBtn.fadeTo(alphaValue: 0.0, withDuration: 0.2)
            self.cancelButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
            self.centerMapButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
            self.actionBtn.isHidden = true
            self.cancelButton.isHidden = true
            self.centerMapButton.isHidden = true
        } else {
            self.actionBtn.fadeTo(alphaValue: 1.0, withDuration: 0.2)
            self.cancelButton.fadeTo(alphaValue: 1.0, withDuration: 0.2)
            self.centerMapButton.fadeTo(alphaValue: 1.0, withDuration: 0.2)
            self.actionBtn.isHidden = false
            self.cancelButton.isHidden = false
            self.centerMapButton.isHidden = false
        }
    }

    func loadDriverAnnotationsFromFB() {
        DataService.instance.REF_DRIVERS.observeSingleEvent(of: .value) { (snapshot) in

            if let driverSnapshot = snapshot.children.allObjects as? [DataSnapshot] {
                for driver in driverSnapshot {
                    if driver.hasChild(COORDINATE) {
                        if driver.childSnapshot(forPath: ACCOUNT_PICKUP_MODE_ENABLED).value as? Bool == true {
                            if let driverDict = driver.value as? Dictionary<String, AnyObject> {
                                let coordinateArray = driverDict[COORDINATE] as! NSArray
                                let driverCoordinate = CLLocationCoordinate2D(latitude: coordinateArray[0] as! CLLocationDegrees, longitude: coordinateArray[1] as! CLLocationDegrees)
                                let annotation = DriverAnnotation(coordinate: driverCoordinate, withKey: driver.key)

                                var driverIsVisible: Bool {
                                    return self.mapView.annotations.contains(where: { (annotation) -> Bool in
                                        if let driverAnnotation = annotation as? DriverAnnotation {
                                            if driverAnnotation.key == driver.key {
                                                driverAnnotation.update(annotationPostion: driverAnnotation, withCoordinate: driverCoordinate)
                                                return true
                                            }
                                        }
                                        return false
                                    })
                                }

                                if !driverIsVisible {
                                    self.mapView.addAnnotation(annotation)
                                }
                            }
                        } else {
                            for annotation in self.mapView.annotations {
                                if annotation.isKind(of: DriverAnnotation.self) {
                                    if let annotation = annotation as? DriverAnnotation {
                                        if annotation.key == driver.key {
                                            self.mapView.removeAnnotation(annotation)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // End Splash View animation
        revealingSplashView.heartAttack = true
    }

    func connectUserAndDriverForTrip() {
        DataService.instance.checkIfPassengerIsOnTrip(passengerKey: self.currentUserID!, handler: { (isOnTrip, driverKey, tripKey) in
            if isOnTrip == true {
                self.removeOverlaysAndAnnotations(forDrivers: false, forPassengers: true)

                DataService.instance.REF_TRIPS.child(tripKey!).observeSingleEvent(of: .value, with: { (tripSnapshot) in
                    let tripDict = tripSnapshot.value as? Dictionary<String, AnyObject>
                    let driverID = tripDict?[DRIVER_KEY] as! String

                    let pickupCoordinateArray = tripDict?[USER_PICKUP_COORDINATE] as! NSArray
                    let pickupCoordinate = CLLocationCoordinate2D(latitude: pickupCoordinateArray[0] as! CLLocationDegrees, longitude: pickupCoordinateArray[1] as! CLLocationDegrees)
                    let pickupPlacemark = MKPlacemark(coordinate: pickupCoordinate)
                    let pickupMapItem = MKMapItem(placemark: pickupPlacemark)

                    DataService.instance.REF_DRIVERS.child(driverID).child(COORDINATE).observeSingleEvent(of: .value, with: { (coordinateSnapshot) in
                        let coordinateSnapshot = coordinateSnapshot.value as! NSArray
                        let driverCoordinate = CLLocationCoordinate2D(latitude: coordinateSnapshot[0] as! CLLocationDegrees, longitude: coordinateSnapshot[1] as! CLLocationDegrees)
                        let driverPlacemark = MKPlacemark(coordinate: driverCoordinate)
                        let driverMapItem = MKMapItem(placemark: driverPlacemark)

                        let passengerAnnotation = PassengerAnnotation(coordinate: pickupCoordinate, key: self.currentUserID!)
                        self.mapView.addAnnotation(passengerAnnotation)

                        self.searchMapKitForResultsWithPolyline(forOriginMapItem: driverMapItem, withDestinationMapItem: pickupMapItem)
                        self.actionBtn.animateButton(shouldLoad: false, withMessage: MSG_DRIVER_COMING)
                        self.actionBtn.isUserInteractionEnabled = false
                    })

                    DataService.instance.REF_TRIPS.child(tripKey!).observeSingleEvent(of: .value, with: { (tripSnapshot) in
                        if tripDict?[TRIP_IN_PROGRESS] as? Bool == true {
                            self.removeOverlaysAndAnnotations(forDrivers: true, forPassengers: true)

                            let destinationCoordinateArray = tripDict?[USER_DESTINATION_COORDINATE] as! NSArray
                            let destinationCoordinate = CLLocationCoordinate2D(latitude: destinationCoordinateArray[0] as! CLLocationDegrees, longitude: destinationCoordinateArray[1] as! CLLocationDegrees)
                            let destinationPlacemark = MKPlacemark(coordinate: destinationCoordinate)

                            self.dropPinFor(placemark: destinationPlacemark)
                            self.searchMapKitForResultsWithPolyline(forOriginMapItem: pickupMapItem, withDestinationMapItem: MKMapItem(placemark: destinationPlacemark))

                            self.actionBtn.setTitle(MSG_ON_TRIP, for: .normal)
                        }
                    })

                })
            }
        })
    }

    func centerMapOnUserLocation() {
        let coordinateRegion = MKCoordinateRegion.init(center: mapView.userLocation.coordinate, latitudinalMeters: regionRadius * 2.0, longitudinalMeters: regionRadius * 2.0);
        mapView.setRegion(coordinateRegion, animated: true)
    }
    
    func resetDestinationSearchField() {
        destinationTextField.text = ""
        textFieldDidEndEditing(destinationTextField)
        textFieldShouldClear(destinationTextField)
    }

    @IBAction func actionBtnPressed(_ sender: Any) {
        if currentUserID != ACCOUNT_NOT_LOGGED_IN {
            buttonSelector(forAction: actionForButton)
        } else {
            showAlert("You need to create an account first before you can use this app. Tap the menu icon and sign up")
            resetDestinationSearchField()
        }
    }

    @IBAction func cancelButtonPressed(_ sender: Any) {
        DataService.instance.checkIfDriverIsOnTrip(driverKey: currentUserID!) { (isOnTrip, driverKey, tripKey) in
            if isOnTrip == true {
                UpdateService.instance.cancelTrip(withPassengerKey: tripKey!, forDriverKey: driverKey!)
            }
        }
        DataService.instance.checkIfPassengerIsOnTrip(passengerKey: currentUserID!) { (isOnTrip, driverKey, tripKey) in

            if isOnTrip == true {
                UpdateService.instance.cancelTrip(withPassengerKey: self.currentUserID!, forDriverKey: driverKey!)
            } else {
                UpdateService.instance.cancelTrip(withPassengerKey: self.currentUserID!, forDriverKey: nil)
            }
            self.actionBtn.isUserInteractionEnabled = true
        }
        resetDestinationSearchField()

    }
    @IBAction func menuBtnPressed(_ sender: Any) {
        delegate?.toggleLeftPanel()
    }

    func buttonSelector(forAction action: ButtonAction) {
        switch action {
        case .requestRide:
            if destinationTextField.text != "" {
                UpdateService.instance.updateTripsWithCoordinatesUponRequest()
                actionBtn.animateButton(shouldLoad: true, withMessage: nil)
                cancelButton.fadeTo(alphaValue: 1, withDuration: 0.2)

                self.view.endEditing(true)
                destinationTextField.isUserInteractionEnabled = false
            } else {
                showAlert(ERROR_MSG_TEXTFIELD_EMPTY)
            }
        case .getDirectionsToPassenger:
            //Get directions to passenger
            DataService.instance.checkIfDriverIsOnTrip(driverKey: currentUserID!) { (isOnTrip, driverKey, tripKey) in
                if isOnTrip == true {
                    DataService.instance.REF_TRIPS.child(tripKey!).observeSingleEvent(of: .value, with: { (tripSnapshot) in
                        let tripDict = tripSnapshot.value as? Dictionary<String, AnyObject>
                        let pickupCoordinateArray = tripDict?[USER_PICKUP_COORDINATE] as! NSArray
                        let pickupCoordinate = CLLocationCoordinate2D(latitude: pickupCoordinateArray[0] as! CLLocationDegrees, longitude: pickupCoordinateArray[1] as! CLLocationDegrees)
                        let pickupMapItem = MKMapItem(placemark: MKPlacemark(coordinate: pickupCoordinate))
                        pickupMapItem.name = MSG_PASSENGER_PICKUP
                        pickupMapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey:MKLaunchOptionsDirectionsModeDriving])
                    })
                }
            }
        case .startTrip:
            DataService.instance.checkIfDriverIsOnTrip(driverKey: self.currentUserID!) { (isOnTrip, driverKey, tripKey) in
                if isOnTrip == true {
                    self.removeOverlaysAndAnnotations(forDrivers: false, forPassengers: false)

                    DataService.instance.REF_TRIPS.child(tripKey!).updateChildValues([TRIP_IN_PROGRESS: true])

                    DataService.instance.REF_TRIPS.child(tripKey!).child(USER_DESTINATION_COORDINATE).observeSingleEvent(of: .value, with: { (coordinateSnapshot) in
                        let destinationCoordinateArray = coordinateSnapshot.value as! NSArray
                        let destinationCoordinate = CLLocationCoordinate2D(latitude: destinationCoordinateArray[0] as! CLLocationDegrees, longitude: destinationCoordinateArray[1] as! CLLocationDegrees)
                        let destinationPlacemark = MKPlacemark(coordinate: destinationCoordinate)

                        self.dropPinFor(placemark: destinationPlacemark)
                        self.searchMapKitForResultsWithPolyline(forOriginMapItem: nil, withDestinationMapItem: MKMapItem(placemark: destinationPlacemark))
                        self.setCustomRegion(forAnnotationType: .destination, withCoordinate: destinationCoordinate)

                        self.actionForButton = .getDirectionsToDestination
                        self.actionBtn.setTitle(MSG_GET_DIRECTIONS, for: .normal)
                    })
                }
            }
        case .getDirectionsToDestination:
            DataService.instance.checkIfDriverIsOnTrip(driverKey: self.currentUserID!) { (isOnTrip, driverKey, tripKey) in
                if isOnTrip == true {
                    DataService.instance.REF_TRIPS.child(tripKey!).child(USER_DESTINATION_COORDINATE).observeSingleEvent(of: .value, with: { (snapshot) in
                        let destinationCoordinateArray = snapshot.value as! NSArray
                        let destinationCoordinate = CLLocationCoordinate2D(latitude: destinationCoordinateArray[0] as! CLLocationDegrees, longitude: destinationCoordinateArray[1] as! CLLocationDegrees)
                        let destinationPlacemark = MKPlacemark(coordinate: destinationCoordinate)
                        let destinationMapItem = MKMapItem(placemark: destinationPlacemark)

                        destinationMapItem.name = MSG_PASSENGER_DESTINATION
                        destinationMapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey:MKLaunchOptionsDirectionsModeDriving])
                    })
                }
            }
        case .endTrip:
            DataService.instance.checkIfDriverIsOnTrip(driverKey: self.currentUserID!) { (isOnTrip, driverKey, tripKey) in
                if isOnTrip == true {
                    UpdateService.instance.cancelTrip(withPassengerKey: tripKey!, forDriverKey: driverKey!)
                    self.setButtonsForDriver(hidden: true)
                }
            }
        }
    }

    @IBAction func centerMapBtnPressed(_ sender: Any) {
        DataService.instance.REF_USERS.observeSingleEvent(of: .value) { (snapshot) in
            if let userSnapshot = snapshot.children.allObjects as? [DataSnapshot] {
                for user in userSnapshot {
                    if user.key == self.currentUserID {
                        if user.hasChild(TRIP_COORDINATE) {
                            self.zoom(toFitAnnotationsFromMapview: self.mapView, forActiveTripWithDriver: false, withKey: nil)
                            self.centerMapButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
                        } else {
                            self.centerMapOnUserLocation()
                            self.centerMapButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
                        }
                    }
                }
            }
        }

    }

}

extension HomeVC: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedAlways {
            mapView.showsUserLocation = true
            mapView.userTrackingMode = .follow
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        DataService.instance.checkIfDriverIsOnTrip(driverKey: currentUserID!) { (isOnTrip, driverKey, passengerKey) in
            if isOnTrip == true {
                if region.identifier == REGION_PICKUP {
                    self.actionBtn.setTitle(MSG_START_TRIP, for: .normal)
                    self.actionForButton = .startTrip
                } else if region.identifier == REGION_DESTINATION {
                    self.cancelButton.fadeTo(alphaValue: 0.0, withDuration: 0.2)
                    self.cancelButton.isHidden = true
                    self.actionBtn.setTitle(MSG_END_TRIP, for: .normal)
                    self.actionForButton = .endTrip
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        DataService.instance.checkIfDriverIsOnTrip(driverKey: currentUserID!) { (isOnTrip, driverKey, tripKey) in
            if isOnTrip == true {
                if region.identifier == REGION_PICKUP {
                    self.actionBtn.setTitle(MSG_START_TRIP, for: .normal)
                    self.actionBtn.setTitle(MSG_GET_DIRECTIONS, for: .normal)
                } else if region.identifier == REGION_DESTINATION {
                    self.actionForButton = .endTrip
                    self.actionBtn.setTitle(MSG_GET_DIRECTIONS, for: .normal)
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        checkLocationAuthStatus()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Error: \(error)")
    }
}

extension HomeVC: MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
        UpdateService.instance.updateUserLocation(withCoordinate: userLocation.coordinate)
        UpdateService.instance.updateDriverLocation(withCoordinate: userLocation.coordinate)

        DataService.instance.checkIfUserIsDriver(userKey: currentUserID!) { (isDriver) in
            if isDriver == true {
                DataService.instance.checkIfDriverIsOnTrip(driverKey: self.currentUserID!, handler: { (isOnTrip, driverKey, tripKey) in
                    if isOnTrip == true {
                        self.zoom(toFitAnnotationsFromMapview: self.mapView, forActiveTripWithDriver: true, withKey: driverKey)
                    } else {
                        self.centerMapOnUserLocation()
                    }
                })
            } else {
                DataService.instance.checkIfPassengerIsOnTrip(passengerKey: self.currentUserID!, handler: { (isOnTrip, driverKey, tripKey) in
                    if isOnTrip == true {
                        self.zoom(toFitAnnotationsFromMapview: self.mapView, forActiveTripWithDriver: true, withKey: driverKey)
                    } else {
                        self.centerMapOnUserLocation()
                    }
                })
            }
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let annotation = annotation as? DriverAnnotation {
            let identifier = "driver"
            let view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.image = UIImage(named: ANNO_DRIVER)
            return view
        } else if let annotation = annotation as? PassengerAnnotation {
            let identifier = "passenger"
            let view = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            view.image = UIImage(named: ANNO_PICKUP)
            return view
        } else if let annotation = annotation as? MKPointAnnotation {
            let identifier = "destination"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            } else {
                annotationView?.annotation = annotation
            }
            annotationView?.image = UIImage(named: ANNO_DESTINATION)
            return annotationView
        }
        return nil
    }

    func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        centerMapButton.fadeTo(alphaValue: 1.0, withDuration: 0.2)
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let lineRenderer = MKPolylineRenderer(overlay: self.route.polyline)
        lineRenderer.strokeColor = UIColor(red: 30/255, green: 217/255, blue: 161/255, alpha: 0.75)
        lineRenderer.lineWidth = 3
        shouldPresentLoadingView(false)
        return lineRenderer
    }

    func performSearch() {
        matchingItems.removeAll()
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destinationTextField.text
        request.region = mapView.region

        let search = MKLocalSearch(request: request)

        search.start { (response, error) in
            if error != nil {
                self.showAlert(error.debugDescription)
            } else if response!.mapItems.count == 0 {
                self.showAlert(ERROR_MSG_NO_SEARCH_RESULTS)
            } else {
                for mapItem in response!.mapItems {
                    self.matchingItems.append(mapItem as MKMapItem)
                    self.tableView.reloadData()

                    self.shouldPresentLoadingView(false)
                }
            }
        }
    }
    func dropPinFor(placemark: MKPlacemark) {
        selectedItemPlacemark = placemark

        for annotation in mapView.annotations {
            if annotation.isKind(of: MKPointAnnotation.self) {
                mapView.removeAnnotation(annotation)
            }

        }

        let annotation = MKPointAnnotation()
        annotation.coordinate = placemark.coordinate
        mapView.addAnnotation(annotation)
    }

    func searchMapKitForResultsWithPolyline(forOriginMapItem originMapItem: MKMapItem?, withDestinationMapItem destinationMapItem: MKMapItem) {
        let request = MKDirections.Request()

        if originMapItem == nil {
            request.source = MKMapItem.forCurrentLocation()
        } else {
            request.source = originMapItem
        }

        request.destination = destinationMapItem
        request.transportType = MKDirectionsTransportType.automobile

        let directions = MKDirections(request: request)

        directions.calculate { (response, error) in
            guard let response = response else {self.showAlert(ERROR_MSG_UNEXPECTED_ERROR); return}
            self.route = response.routes[0]

            self.mapView.addOverlay(self.route!.polyline)

            self.zoom(toFitAnnotationsFromMapview: self.mapView, forActiveTripWithDriver: false, withKey: nil)


            let delegate = AppDelegate.getAppDelegate()
            delegate.window?.rootViewController?.shouldPresentLoadingView(false)
        }
    }

    func zoom(toFitAnnotationsFromMapview mapView: MKMapView, forActiveTripWithDriver: Bool, withKey key: String?) {
        if mapView.annotations.count == 0 {
            return
        }

        var topLeftCoordinate = CLLocationCoordinate2D(latitude: -90, longitude: 180)
        var bottomRightCoordinate = CLLocationCoordinate2D(latitude: 90, longitude: -180)

        if forActiveTripWithDriver {
            for annotation in mapView.annotations {
                if let annotation = annotation as? DriverAnnotation {
                    if annotation.key == key {

                        topLeftCoordinate.longitude = fmin(topLeftCoordinate.longitude, annotation.coordinate.longitude)
                        topLeftCoordinate.latitude = fmax(topLeftCoordinate.latitude, annotation.coordinate.latitude)
                        bottomRightCoordinate.longitude = fmax(bottomRightCoordinate.longitude, annotation.coordinate.longitude)
                        bottomRightCoordinate.latitude = fmin(bottomRightCoordinate.latitude, annotation.coordinate.latitude)
                    }
                } else {

                    topLeftCoordinate.longitude = fmin(topLeftCoordinate.longitude, annotation.coordinate.longitude)
                    topLeftCoordinate.latitude = fmax(topLeftCoordinate.latitude, annotation.coordinate.latitude)
                    bottomRightCoordinate.longitude = fmax(bottomRightCoordinate.longitude, annotation.coordinate.longitude)
                    bottomRightCoordinate.latitude = fmin(bottomRightCoordinate.latitude, annotation.coordinate.latitude)
                }
            }
        }

        for annotation in mapView.annotations where !annotation.isKind(of: DriverAnnotation.self) {
            topLeftCoordinate.longitude = fmin(topLeftCoordinate.longitude, annotation.coordinate.longitude)
            topLeftCoordinate.latitude = fmax(topLeftCoordinate.latitude, annotation.coordinate.latitude)
            bottomRightCoordinate.longitude = fmax(bottomRightCoordinate.longitude, annotation.coordinate.longitude)
            bottomRightCoordinate.latitude = fmin(bottomRightCoordinate.latitude, annotation.coordinate.latitude)
        }

        var region = MKCoordinateRegion(center: CLLocationCoordinate2DMake(topLeftCoordinate.latitude - (topLeftCoordinate.latitude - bottomRightCoordinate.latitude) * 0.5, topLeftCoordinate.longitude + (bottomRightCoordinate.longitude - topLeftCoordinate.longitude) * 0.5), span: MKCoordinateSpan(latitudeDelta: fabs(topLeftCoordinate.latitude - bottomRightCoordinate.latitude) * 2.0, longitudeDelta: fabs(bottomRightCoordinate.longitude - topLeftCoordinate.longitude) * 2.0))

        region = mapView.regionThatFits(region)
        mapView.setRegion(region, animated: true)
    }

    func removeOverlaysAndAnnotations(forDrivers: Bool?, forPassengers: Bool?) {
        for annotation in mapView.annotations {
            if let annotation = annotation as? MKPointAnnotation {
                mapView.removeAnnotation(annotation)
            }

            if forPassengers! {
                if let annotation = annotation as? PassengerAnnotation {
                    mapView.removeAnnotation(annotation)
                }
            }

            if forDrivers! {
                if let annotation = annotation as? DriverAnnotation {
                    mapView.removeAnnotation(annotation)
                }
            }

            for overlay in mapView.overlays {
                if overlay is MKPolyline {
                    mapView.removeOverlay(overlay)
                }
            }
        }
    }

    func setCustomRegion(forAnnotationType type: AnnotationType, withCoordinate coordinate: CLLocationCoordinate2D) {
        if type == .pickup {
            let pickupRegion = CLCircularRegion(center: coordinate, radius: 250, identifier: REGION_PICKUP)
            manager?.startMonitoring(for: pickupRegion)
        } else if type == .destination {
            let destinationRegion = CLCircularRegion(center: coordinate, radius: 250, identifier: REGION_DESTINATION)
            manager?.startMonitoring(for: destinationRegion)
        }
    }
}

extension HomeVC: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        if textField == destinationTextField {
            tableView.frame = CGRect(x: 20, y: view.frame.height, width: view.frame.width - 40, height: view.frame.height - 200)
            tableView.layer.cornerRadius = 5.0
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: CELL_LOCATION)

            tableView.delegate = self
            tableView.dataSource = self

            // Arbitrary number to identify the tableView
            tableView.tag = 18
            tableView.rowHeight = 60

            view.addSubview(tableView)
            animateTableView(shouldShow: true)

            UIView.animate(withDuration: 0.2) {
                self.destinationCircle.backgroundColor = UIColor.red
                self.destinationCircle.borderColor = UIColor.init(red: 199/255, green: 0/255, blue: 0/255, alpha: 1.0)
            }
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == destinationTextField {
            performSearch()

            shouldPresentLoadingView(true)
            view.endEditing(true)
        }
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if textField == destinationTextField {
            if destinationTextField.text == "" {
                UIView.animate(withDuration: 0.2) {
                    self.destinationCircle.backgroundColor = UIColor.lightGray
                    self.destinationCircle.borderColor = UIColor.darkGray
                }
            }
        }
    }

    func textFieldShouldClear(_ textField: UITextField) -> Bool {
        matchingItems = []
        tableView.reloadData()

        mapView.removeOverlays(mapView.overlays)
        DataService.instance.REF_USERS.child(currentUserID!).child(TRIP_COORDINATE).removeValue()
        for annotation in mapView.annotations {
            if let annotation = annotation as? MKPointAnnotation {
                mapView.removeAnnotation(annotation)
            } else if annotation.isKind(of: PassengerAnnotation.self) {
                mapView.removeAnnotation(annotation)
            }
        }

        centerMapOnUserLocation()
        return true
    }

    func animateTableView(shouldShow: Bool) {
        if shouldShow {
            UIView.animate(withDuration: 0.2) {
                self.tableView.frame = CGRect(x: 20, y: 200, width: self.view.frame.width - 40, height: self.view.frame.height - 200)
            }
        } else {
            UIView.animate(withDuration: 0.2, animations: {

                self.tableView.frame = CGRect(x: 20, y: self.view.frame.height, width: self.view.frame.width - 40, height: self.view.frame.height - 200)
            }) { (finished) in
                for subview in self.view.subviews {
                    if subview.tag == 18 {
                        subview.removeFromSuperview()
                    }
                }
            }
        }
    }
}

extension HomeVC: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: CELL_LOCATION)
        let mapItem = matchingItems[indexPath.row]
        cell.textLabel?.text = mapItem.name
        cell.detailTextLabel?.text = mapItem.placemark.title
        return cell
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return matchingItems.count
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        shouldPresentLoadingView(true)

        let passengerCoordinate = manager?.location?.coordinate

        let passengerAnnotation = PassengerAnnotation(coordinate: passengerCoordinate!, key: currentUserID!)
        mapView.addAnnotation(passengerAnnotation)

        destinationTextField.text = tableView.cellForRow(at: indexPath)?.textLabel?.text

        let selectedMapItem = matchingItems[indexPath.row]

        DataService.instance.REF_USERS.child(currentUserID!).updateChildValues([TRIP_COORDINATE: [selectedMapItem.placemark.coordinate.latitude, selectedMapItem.placemark.coordinate.longitude]])

        dropPinFor(placemark: selectedMapItem.placemark)

        searchMapKitForResultsWithPolyline(forOriginMapItem: nil, withDestinationMapItem: selectedMapItem)

        animateTableView(shouldShow: false)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        if destinationTextField.text == "" {
            animateTableView(shouldShow: false)
        }
    }
}
