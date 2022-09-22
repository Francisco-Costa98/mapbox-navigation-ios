import UIKit
import CoreLocation
import MapboxCoreNavigation
import MapboxMaps
import MapboxDirections

// :nodoc:
open class PreviewViewController: UIViewController {
    
    var previousState: State? = nil
    
    // :nodoc:
    public private(set) var state: State = .browsing {
        didSet {
            updateInternalComponents(to: state)
        }
    }
    
    var backButton: BackButton!
    
    // :nodoc:
    public var navigationView: NavigationView {
        view as! NavigationView
    }
    
    var finalDestinationAnnotation: PointAnnotation? = nil
    
    var pointAnnotationManager: PointAnnotationManager?
    
    var cameraModeFloatingButton: CameraModeFloatingButton!
    
    var styleManager: StyleManager!
    
    // TODO: Consider retrieving bottom banner view controller from actual view where it was embedded.
    var presentedBottomBannerViewController: Previewing?
    
    var topBannerContainerViewLayoutConstraints: [NSLayoutConstraint] = []
    
    var bottomBannerContainerViewLayoutConstraints: [NSLayoutConstraint] = []
    
    // :nodoc:
    public weak var delegate: PreviewViewControllerDelegate?
    
    deinit {
        unsubscribeFromNotifications()
    }
    
    // MARK: - UIViewController lifecycle methods
    
    open override func loadView() {
        view = setupNavigationView()
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        setupBackButton()
        setupFloatingButtons()
        setupTopBannerContainerView()
        setupBottomBannerContainerView()
        setupOrnaments()
        setupConstraints()
        
        setupStyleManager()
        setupGestureRecognizers()
        
        state = .browsing
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        setupPassiveLocationManager()
        setupNavigationViewportDataSource()
        subscribeForNotifications()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        setupBottomBannerContainerViewLayoutConstraints()
        
        // TODO: Implement public method that completely cleans-up `NavigationMapView`.
        navigationView.navigationMapView.removeRoutes()
        navigationView.navigationMapView.removeAlternativeRoutes()
        navigationView.navigationMapView.removeArrow()
        navigationView.navigationMapView.removeRouteDurations()
        navigationView.navigationMapView.removeContinuousAlternativesRoutes()
        navigationView.navigationMapView.removeContinuousAlternativeRoutesDurations()
        
        switch state {
        case .browsing:
            break
        case .destinationPreviewing:
            navigationView.bottomBannerContainerView.show()
        case .routesPreviewing(let routesPreviewOptions):
            showcase(routeResponse: routesPreviewOptions.routeResponse,
                     routeIndex: 0)
            fitCamera(to: routesPreviewOptions.routeResponse)
            navigationView.bottomBannerContainerView.show()
        }
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        unsubscribeFromNotifications()
    }
    
    open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        
        if previousTraitCollection?.verticalSizeClass != traitCollection.verticalSizeClass {
            setupBottomBannerContainerViewLayoutConstraints()
        }
    }
    
    open override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        
        setupTopBannerContainerViewLayoutConstraints()
    }
    
    // MARK: - UIViewController setting-up methods
    
    func setupNavigationView() -> NavigationView {
        let frame = parent?.view.bounds ?? UIScreen.main.bounds
        let navigationView = NavigationView(frame: frame)
        navigationView.navigationMapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        navigationView.navigationMapView.delegate = self
        // TODO: Move final destination annotation placement logic to `MapView` or `NavigationMapView`.
        navigationView.navigationMapView.mapView.mapboxMap.onNext(event: .styleLoaded) { [weak self] _ in
            guard let self = self else { return }
            self.pointAnnotationManager = self.navigationView.navigationMapView.mapView.annotations.makePointAnnotationManager()
            
            if let finalDestinationAnnotation = self.finalDestinationAnnotation,
               let pointAnnotationManager = self.pointAnnotationManager {
                pointAnnotationManager.annotations = [finalDestinationAnnotation]
                
                self.finalDestinationAnnotation = nil
            }
        }
        
        return navigationView
    }
    
    func setupBackButton() {
        let backButton = BackButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        // TODO: Add localization.
        backButton.setTitle("Back", for: .normal)
        backButton.clipsToBounds = true
        backButton.addTarget(self, action: #selector(didPressBackButton), for: .touchUpInside)
        backButton.setImage(.backImage, for: .normal)
        backButton.imageView?.contentMode = .scaleAspectFit
        backButton.imageEdgeInsets = UIEdgeInsets(top: 10,
                                                  left: 0,
                                                  bottom: 10,
                                                  right: 15)
        navigationView.addSubview(backButton)
        
        self.backButton = backButton
    }
    
    func setupFloatingButtons() {
        cameraModeFloatingButton = FloatingButton.rounded(imageEdgeInsets: UIEdgeInsets(floatLiteral: 12.0)) as CameraModeFloatingButton
        cameraModeFloatingButton.delegate = self
        
        navigationView.floatingButtons = [
            cameraModeFloatingButton
        ]
    }
    
    func setupTopBannerContainerView() {
        navigationView.topBannerContainerView.isHidden = false
        navigationView.topBannerContainerView.backgroundColor = .clear
    }
    
    func setupBottomBannerContainerView() {
        navigationView.bottomBannerContainerView.isHidden = true
        navigationView.bottomBannerContainerView.backgroundColor = .defaultBackgroundColor
    }
    
    // TODO: Implement the ability to set default positions for logo and attribution button.
    func setupOrnaments() {
        navigationView.navigationMapView.mapView.ornaments.options.compass.visibility = .hidden
    }
    
    func setupPassiveLocationManager() {
        let passiveLocationManager = PassiveLocationManager()
        let passiveLocationProvider = PassiveLocationProvider(locationManager: passiveLocationManager)
        navigationView.navigationMapView.mapView.location.overrideLocationProvider(with: passiveLocationProvider)
    }
    
    func setupNavigationViewportDataSource() {
        let navigationViewportDataSource = NavigationViewportDataSource(navigationView.navigationMapView.mapView,
                                                                        viewportDataSourceType: .passive)
        navigationView.navigationMapView.navigationCamera.viewportDataSource = navigationViewportDataSource
    }
    
    func setupStyleManager() {
        styleManager = StyleManager()
        styleManager.delegate = self
        // TODO: Provide the ability to set custom styles.
        styleManager.styles = [DayStyle(), NightStyle()]
    }
    
    // TODO: Implement the ability to remove gesture recognizers in case when `NavigationMapView` is reused.
    func setupGestureRecognizers() {
        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGestureRecognizer.name = "preview_long_press_gesture_recognizer"
        navigationView.addGestureRecognizer(longPressGestureRecognizer)
        
        // In case if map view is panned, rotated or pinched, camera state should be reset.
        for gestureRecognizer in navigationView.navigationMapView.mapView.gestureRecognizers ?? []
        where gestureRecognizer is UIPanGestureRecognizer
        || gestureRecognizer is UIRotationGestureRecognizer
        || gestureRecognizer is UIPinchGestureRecognizer {
            gestureRecognizer.addTarget(self, action: #selector(resetCameraState))
        }
    }
    
    // MARK: - Notifications observer methods
    
    func subscribeForNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didUpdatePassiveLocation(_:)),
                                               name: .passiveLocationManagerDidUpdate,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(orientationDidChange(_:)),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: nil)
    }
    
    func unsubscribeFromNotifications() {
        NotificationCenter.default.removeObserver(self,
                                                  name: .passiveLocationManagerDidUpdate,
                                                  object: nil)
        
        NotificationCenter.default.removeObserver(self,
                                                  name: UIDevice.orientationDidChangeNotification,
                                                  object: nil)
    }
    
    @objc func didUpdatePassiveLocation(_ notification: Notification) {
        guard let location = notification.userInfo?[PassiveLocationManager.NotificationUserInfoKey.locationKey] as? CLLocation else {
            return
        }
        
        // Update user puck to the most recent location.
        navigationView.navigationMapView.moveUserLocation(to: location, animated: true)
        
        // Update current speed limit. In case if speed limit is not available `SpeedLimitView` is hidden.
        navigationView.speedLimitView.signStandard = notification.userInfo?[PassiveLocationManager.NotificationUserInfoKey.signStandardKey] as? SignStandard
        navigationView.speedLimitView.speedLimit = notification.userInfo?[PassiveLocationManager.NotificationUserInfoKey.speedLimitKey] as? Measurement<UnitSpeed>
        
        // Update current road name. In case if road name is not available `WayNameView` is hidden.
        let roadNameFromStatus = notification.userInfo?[PassiveLocationManager.NotificationUserInfoKey.roadNameKey] as? String
        if let roadName = roadNameFromStatus?.nonEmptyString {
            let representation = notification.userInfo?[PassiveLocationManager.NotificationUserInfoKey.routeShieldRepresentationKey] as? VisualInstruction.Component.ImageRepresentation
            navigationView.wayNameView.label.updateRoad(roadName: roadName, representation: representation)
            navigationView.wayNameView.containerView.isHidden = false
        } else {
            navigationView.wayNameView.text = nil
            navigationView.wayNameView.containerView.isHidden = true
        }
        
        // Update camera options based on current location and camera mode.
        navigationView.navigationMapView.navigationCamera.update(to: cameraModeFloatingButton.cameraMode)
    }
    
    @objc func orientationDidChange(_ notification: Notification) {
        navigationView.navigationMapView.navigationCamera.update(to: cameraModeFloatingButton.cameraMode)
        
        // In case if routes are already shown and orientation changes - fit camera so that all
        // routes fit into available space.
        if case .routesPreviewing(let previewOptions) = state {
            fitCamera(to: previewOptions.routeResponse)
        }
    }
    
    func addDestinationAnnotation(_ coordinate: CLLocationCoordinate2D) {
        let destinationIdentifier = NavigationMapView.AnnotationIdentifier.finalDestinationAnnotation
        var destinationAnnotation = PointAnnotation(id: destinationIdentifier,
                                                    coordinate: coordinate)
        destinationAnnotation.image = .init(image: .defaultMarkerImage,
                                            name: "default_marker")
        
        // If `PointAnnotationManager` is available - add `PointAnnotation`, if not - remember it
        // and add it only after fully loading `MapView` style.
        if let pointAnnotationManager = self.pointAnnotationManager {
            pointAnnotationManager.annotations = [destinationAnnotation]
        } else {
            finalDestinationAnnotation = destinationAnnotation
        }
    }
    
    // :nodoc:
    public func preview(_ waypoint: Waypoint) {
        let destinationOptions = DestinationOptions(waypoint: waypoint)
        state = .destinationPreviewing(destinationOptions)
        
        addDestinationAnnotation(waypoint.coordinate)
        
        if let primaryText = destinationOptions.primaryText,
           let destinationPreviewViewController = presentedBottomBannerViewController as? DestinationPreviewViewController {
            let primaryAttributedString = NSAttributedString(string: primaryText)
            destinationPreviewViewController.destinationLabel.attributedText =
            delegate?.previewViewController(self,
                                            willPresent: primaryAttributedString,
                                            in: destinationPreviewViewController) ?? primaryAttributedString
        }
    }
    
    // :nodoc:
    public func preview(_ coordinate: CLLocationCoordinate2D) {
        preview(Waypoint(coordinate: coordinate))
    }
    
    // :nodoc:
    public func preview(_ routeResponse: RouteResponse,
                        routeIndex: Int = 0,
                        animated: Bool = false,
                        duration: TimeInterval = 1.0,
                        completion: NavigationMapView.AnimationCompletionHandler? = nil) {
        let routesPreviewOptions = RoutesPreviewOptions(routeResponse: routeResponse, routeIndex: routeIndex)
        state = .routesPreviewing(routesPreviewOptions)
        
        if let lastLeg = routesPreviewOptions.routeResponse.routes?.first?.legs.last,
           let destinationCoordinate = lastLeg.destination?.coordinate {
            addDestinationAnnotation(destinationCoordinate)
        }
        
        showcase(routeResponse: routeResponse,
                 routeIndex: routeIndex,
                 animated: animated,
                 duration: duration,
                 completion: completion)
    }
    
    func showcase(routeResponse: RouteResponse,
                  routeIndex: Int,
                  animated: Bool = false,
                  duration: TimeInterval = 1.0,
                  completion: NavigationMapView.AnimationCompletionHandler? = nil) {
        guard var routes = routeResponse.routes else { return }
        
        routes.insert(routes.remove(at: routeIndex), at: 0)
        
        let cameraOptions = navigationView.defaultRoutesPreviewCameraOptions()
        let routesPresentationStyle: RoutesPresentationStyle = .all(shouldFit: true,
                                                                    cameraOptions: cameraOptions)
        
        navigationView.navigationMapView.showcase(routes,
                                                  routesPresentationStyle: routesPresentationStyle,
                                                  animated: animated,
                                                  duration: duration,
                                                  completion: completion)
    }
    
    func fitCamera(to routeResponse: RouteResponse) {
        guard let routes = routeResponse.routes else { return }
        
        navigationView.navigationMapView.navigationCamera.stop()
        let cameraOptions = navigationView.defaultRoutesPreviewCameraOptions()
        navigationView.navigationMapView.fitCamera(to: routes,
                                                   routesPresentationStyle: .all(shouldFit: true,
                                                                                 cameraOptions: cameraOptions),
                                                   animated: true)
    }
    
    // TODO: Refactor bottom banner view controller creation logic.
    func updateBottomBannerContainerView(to state: State) {
        switch state {
        case .browsing:
            if let customBottomBannerViewController = delegate?.previewViewController(self,
                                                                                      bottomBannerFor: state) {
                navigationView.bottomBannerContainerView.isHidden = false
                embed(customBottomBannerViewController as! UIViewController, in: navigationView.bottomBannerContainerView)
                
                presentedBottomBannerViewController = customBottomBannerViewController
            } else {
                navigationView.bottomBannerContainerView.hide()
            }
        case .destinationPreviewing(let destinationOptions):
            navigationView.bottomBannerContainerView.subviews.forEach {
                $0.removeFromSuperview()
            }
            
            let destinationPreviewViewController: DestinationPreviewing
            if let customDestinationPreviewViewController = delegate?.previewViewController(self,
                                                                                            bottomBannerFor: state) {
                guard let customDestinationPreviewViewController = customDestinationPreviewViewController as? DestinationPreviewing else {
                    preconditionFailure("UIViewController should conform to DestinationPreviewing protocol.")
                }
                
                destinationPreviewViewController = customDestinationPreviewViewController
            } else {
                destinationPreviewViewController = DestinationPreviewViewController(destinationOptions)
                (destinationPreviewViewController as? DestinationPreviewViewController)?.delegate = self
            }
            
            presentedBottomBannerViewController = destinationPreviewViewController
            embed(destinationPreviewViewController as! UIViewController, in: navigationView.bottomBannerContainerView)
        case .routesPreviewing(let routesPreviewOptions):
            navigationView.bottomBannerContainerView.subviews.forEach {
                $0.removeFromSuperview()
            }
            
            let routesPreviewViewController: RoutesPreviewing
            if let customRoutesPreviewViewController = delegate?.previewViewController(self,
                                                                                       bottomBannerFor: state) {
                guard let customRoutesPreviewViewController = customRoutesPreviewViewController as? RoutesPreviewing else {
                    preconditionFailure("UIViewController should conform to RoutesPreviewing protocol.")
                }
                
                routesPreviewViewController = customRoutesPreviewViewController
            } else {
                routesPreviewViewController = RoutesPreviewViewController(routesPreviewOptions)
                (routesPreviewViewController as? RoutesPreviewViewController)?.delegate = self
            }
            
            presentedBottomBannerViewController = routesPreviewViewController
            embed(routesPreviewViewController as! UIViewController, in: navigationView.bottomBannerContainerView)
        }
    }
    
    func updateInternalComponents(to state: State) {
        delegate?.previewViewController(self, stateWillChangeTo: state)
        
        updateBottomBannerContainerView(to: state)
        
        switch state {
        case .browsing:
            navigationView.speedLimitView.show()
            navigationView.wayNameView.show()
            
            backButton.hide()
            navigationView.resumeButton.hide()
            
            pointAnnotationManager?.annotations = []
            cameraModeFloatingButton.cameraMode = .centered
        case .destinationPreviewing:
            backButton.show()
            navigationView.bottomBannerContainerView.show()
            
            navigationView.wayNameView.hide()
            navigationView.speedLimitView.hide()
        case .routesPreviewing:
            backButton.show()
            navigationView.bottomBannerContainerView.show()
            
            navigationView.wayNameView.hide()
            navigationView.speedLimitView.hide()
        }
        
        navigationView.navigationMapView.removeWaypoints()
        navigationView.navigationMapView.removeRoutes()
        
        delegate?.previewViewController(self, stateDidChangeTo: state)
    }
    
    // MARK: - Gesture recognizers
    
    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let passiveLocationProvider = navigationView.navigationMapView.mapView.location.locationProvider as? PassiveLocationProvider,
              let originCoordinate = passiveLocationProvider.locationManager.location?.coordinate else { return }
        
        let destinationCoordinate = navigationView.navigationMapView.mapView.mapboxMap.coordinate(for: gesture.location(in: navigationView.navigationMapView.mapView))
        let coordinates = [
            originCoordinate,
            destinationCoordinate,
        ]
        
        delegate?.previewViewController(self, didAddDestinationBetween: coordinates)
    }
    
    // MARK: - Event handlers
    
    @objc func didPressBackButton() {
        if case let .destinationPreviewing(destinationOptions) = previousState {
            previousState = nil
            preview(destinationOptions.waypoint)
        } else if case .destinationPreviewing = state {
            state = .browsing
        } else if case .routesPreviewing = state {
            state = .browsing
        }
    }
    
    @objc func resetCameraState() {
        if cameraModeFloatingButton.cameraMode == .idle { return }
        cameraModeFloatingButton.cameraMode = .idle
    }
}

// MARK: - NavigationMapViewDelegate methods

extension PreviewViewController: NavigationMapViewDelegate {
    
    public func navigationMapView(_ mapView: NavigationMapView, didSelect route: Route) {
        delegate?.previewViewController(self, didSelect: route)
    }
}

// MARK: - DestinationPreviewViewControllerDelegate and RoutesPreviewViewControllerDelegate methods

extension PreviewViewController: DestinationPreviewViewControllerDelegate, RoutesPreviewViewControllerDelegate {
    
    func willPreviewRoutes(_ destinationPreviewViewController: DestinationPreviewViewController) {
        previousState = state
        delegate?.previewViewControllerWillPreviewRoutes(self)
    }
    
    func willStartNavigation(_ destinationPreviewViewController: DestinationPreviewViewController) {
        delegate?.previewViewControllerWillBeginNavigation(self)
    }
    
    func willStartNavigation(_ routesPreviewViewController: RoutesPreviewViewController) {
        delegate?.previewViewControllerWillBeginNavigation(self)
    }
}

// MARK: - CameraModeFloatingButtonDelegate methods

extension PreviewViewController: CameraModeFloatingButtonDelegate {
    
    func cameraModeFloatingButton(_ cameraModeFloatingButton: CameraModeFloatingButton,
                                  cameraModeDidChangeTo cameraMode: CameraModeFloatingButton.CameraMode) {
        navigationView.navigationMapView.navigationCamera.move(to: cameraMode)
        
        switch cameraMode {
        case .idle:
            fallthrough
        case .centered:
            navigationView.navigationMapView.userLocationStyle = .puck2D()
        case .following:
            navigationView.navigationMapView.userLocationStyle = .courseView()
        }
    }
}

// MARK: - StyleManagerDelegate methods

extension PreviewViewController: StyleManagerDelegate {
    
    public func location(for styleManager: MapboxNavigation.StyleManager) -> CLLocation? {
        let passiveLocationProvider = navigationView.navigationMapView.mapView.location.locationProvider as? PassiveLocationProvider
        return passiveLocationProvider?.locationManager.location ?? CLLocationManager().location
    }
    
    public func styleManager(_ styleManager: MapboxNavigation.StyleManager,
                             didApply style: MapboxNavigation.Style) {
        if navigationView.navigationMapView.mapView.mapboxMap.style.uri?.rawValue != style.mapStyleURL.absoluteString {
            navigationView.navigationMapView.mapView.mapboxMap.style.uri = StyleURI(url: style.mapStyleURL)
        }
    }
}
