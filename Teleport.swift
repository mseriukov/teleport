import Foundation
import MapKit

enum Teleport {
    private enum Constants {
        // Nsk to Astana.
        static let offset = CLLocationOffset(latitude: -3.8178, longitude: -11.4692)
    }

    // Call me as early as possible. Something like:
    //    func application(
    //        _ application: UIApplication,
    //        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    //    ) -> Bool {
    //        Teleport.initialize()
    //        ...
    //    }
    static func initialize() {
        CLLocationManager.classInit
    }

    fileprivate static func patch(_ location: CLLocation?) -> CLLocation? {
        guard let location else { return nil }
        return location.applyingOffset(offset: Constants.offset)
    }

    fileprivate static func patch(_ region: CLRegion) -> CLRegion {
        guard let circularRegion = region as? CLCircularRegion else { return region }
        return circularRegion.applyingOffset(offset: Constants.offset)
    }

    fileprivate static func unpatch(_ region: CLRegion) -> CLRegion {
        guard let circularRegion = region as? CLCircularRegion else { return region }
        return circularRegion.removingOffset(offset: Constants.offset)
    }

    fileprivate static var teleport_delegates: [String: DelegateProxy] = [:]
}

private let swizzling: (AnyClass, Selector, Selector) -> () = { forClass, originalSelector, swizzledSelector in
    if let originalMethod = class_getInstanceMethod(forClass, originalSelector),
        let swizzledMethod = class_getInstanceMethod(forClass, swizzledSelector) {
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

private extension CLLocationManager {
    static let classInit: Void = {
        swizzling(
            CLLocationManager.self,
            #selector(setter: CLLocationManager.delegate),
            #selector(teleport_setDelegate)
        )
        swizzling(
            CLLocationManager.self,
            #selector(getter: CLLocationManager.location),
            #selector(teleport_getLocation)
        )
        swizzling(
            CLLocationManager.self,
            #selector(CLLocationManager.startMonitoring(for:)),
            #selector(teleport_startMonitoring(for:))
        )
        swizzling(
            CLLocationManager.self,
            #selector(CLLocationManager.stopMonitoring(for:)),
            #selector(teleport_stopMonitoring(for:))
        )
        swizzling(
            CLLocationManager.self,
            #selector(getter: CLLocationManager.monitoredRegions),
            #selector(teleport_monitoredRegions)
        )
    }()

    @objc func teleport_setDelegate(_ delegate: CLLocationManagerDelegate?) {
        let selfHandle = "\(Unmanaged.passUnretained(self).toOpaque())"
        guard let delegate else {
            if let oldDelegate = self.delegate {
                Teleport.teleport_delegates = Teleport.teleport_delegates.filter { $1 !== oldDelegate }
                perform(#selector(teleport_setDelegate), with: nil)
            }
            return
        }
        let proxy = DelegateProxy(orig: delegate)
        Teleport.teleport_delegates[selfHandle] = proxy
        perform(#selector(teleport_setDelegate), with: proxy)
    }

    @objc func teleport_getLocation() -> CLLocation? {
        if let result = perform(#selector(teleport_getLocation)) {
            let location = result.takeUnretainedValue() as! CLLocation
            return Teleport.patch(location)
        }
        return nil
    }

    @objc func teleport_startMonitoring(for region: CLRegion) {
        let region = Teleport.unpatch(region)
        perform(#selector(teleport_startMonitoring), with: region)
    }

    @objc func teleport_stopMonitoring(for region: CLRegion) {
        let region = Teleport.unpatch(region)
        perform(#selector(teleport_stopMonitoring), with: region)
    }

    @objc func teleport_monitoredRegions() -> [CLRegion] {
        if let result = perform(#selector(teleport_monitoredRegions)) {
            let regions = result.takeUnretainedValue() as? [CLRegion] ?? []
            return regions.compactMap { Teleport.patch($0) }
        }
        return []
    }
}

private final class DelegateProxy: NSObject, CLLocationManagerDelegate {
    private(set) var orig: CLLocationManagerDelegate

    init(orig: CLLocationManagerDelegate) {
        self.orig = orig
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        let locations = locations.compactMap { Teleport.patch($0) }
        orig.locationManager?(manager, didUpdateLocations: locations)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        orig.locationManager?(manager, didUpdateHeading: newHeading)
    }

    func locationManagerShouldDisplayHeadingCalibration(
        _ manager: CLLocationManager
    ) -> Bool {
        orig.locationManagerShouldDisplayHeadingCalibration?(manager) ?? false
    }

    func locationManager(
        _ manager: CLLocationManager,
        didDetermineState state: CLRegionState,
        for region: CLRegion
    ) {
        orig.locationManager?(manager, didDetermineState: state, for: region)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didRangeBeacons beacons: [CLBeacon],
        in region: CLBeaconRegion
    ) {
        orig.locationManager?(manager, didRangeBeacons: beacons, in: region)
    }

    func locationManager(
        _ manager: CLLocationManager,
        rangingBeaconsDidFailFor region: CLBeaconRegion,
        withError error: Error
    ) {
        orig.locationManager?(manager, rangingBeaconsDidFailFor: region, withError: error)
    }

    @available(iOS 13.0, *)
    func locationManager(
        _ manager: CLLocationManager,
        didRange beacons: [CLBeacon],
        satisfying beaconConstraint: CLBeaconIdentityConstraint
    ) {
        orig.locationManager?(manager, didRange: beacons, satisfying: beaconConstraint)
    }

    @available(iOS 13.0, *)
    func locationManager(
        _ manager: CLLocationManager,
        didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint,
        error: Error
    ) {
        orig.locationManager?(manager, didFailRangingFor: beaconConstraint, error: error)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        orig.locationManager?(manager, didEnterRegion: Teleport.patch(region))
    }

    func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        orig.locationManager?(manager, didExitRegion: Teleport.patch(region))
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        orig.locationManager?(manager, didFailWithError: error)
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: Error
    ) {
        var patchedRegion: CLRegion?
        if let region {
            patchedRegion = Teleport.patch(region)
        }
        orig.locationManager?(manager, monitoringDidFailFor: patchedRegion, withError: error)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        orig.locationManager?(manager, didChangeAuthorization: status)
    }

    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        orig.locationManagerDidChangeAuthorization?(manager)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didStartMonitoringFor region: CLRegion
    ) {
        orig.locationManager?(manager, didStartMonitoringFor: Teleport.patch(region))
    }

    func locationManagerDidPauseLocationUpdates(
        _ manager: CLLocationManager
    ) {
        orig.locationManagerDidPauseLocationUpdates?(manager)
    }

    func locationManagerDidResumeLocationUpdates(
        _ manager: CLLocationManager
    ) {
        orig.locationManagerDidResumeLocationUpdates?(manager)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFinishDeferredUpdatesWithError error: Error?
    ) {
        orig.locationManager?(manager, didFinishDeferredUpdatesWithError: error)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didVisit visit: CLVisit
    ) {
        orig.locationManager?(manager, didVisit: visit)
    }
}

private struct CLLocationOffset {
    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees

    var inverse: CLLocationOffset {
        .init(latitude: -latitude, longitude: -longitude)
    }
}

extension CLLocationCoordinate2D {
    fileprivate func applyingOffset(
        offset: CLLocationOffset
    ) -> CLLocationCoordinate2D {
        .init(
            latitude: self.latitude + offset.latitude,
            longitude: self.longitude + offset.longitude
        )
    }

    fileprivate func removingOffset(
        offset: CLLocationOffset
    ) -> CLLocationCoordinate2D {
        applyingOffset(offset: offset.inverse)
    }
}

extension CLLocation {
    fileprivate func applyingOffset(
        offset: CLLocationOffset
    ) -> CLLocation {
        .init(
            coordinate: self.coordinate.applyingOffset(offset: offset),
            altitude: self.altitude,
            horizontalAccuracy: self.horizontalAccuracy,
            verticalAccuracy: self.verticalAccuracy,
            course: self.course,
            speed: self.speed,
            timestamp: self.timestamp
        )
    }

    fileprivate func removingOffset(
        offset: CLLocationOffset
    ) -> CLLocation {
        applyingOffset(offset: offset.inverse)
    }
}

extension CLCircularRegion {
    fileprivate func applyingOffset(
        offset: CLLocationOffset
    ) -> CLCircularRegion {
        .init(
            center: self.center.applyingOffset(offset: offset),
            radius: self.radius,
            identifier: self.identifier
        )
    }

    fileprivate func removingOffset(
        offset: CLLocationOffset
    ) -> CLCircularRegion {
        applyingOffset(offset: offset.inverse)
    }
}
