import UIKit

// :nodoc:
public class BannerDismissalViewController: UIViewController, Banner {
    
    var topBannerView: TopBannerView!
    
    var topPaddingView: TopPaddingView!
    
    var backButton: BackButton!
    
    // :nodoc:
    public var backTitle: String? {
        get {
            backButton.title(for: .normal)
        }
        set {
            backButton.setTitle(newValue, for: .normal)
        }
    }
    
    // :nodoc:
    public weak var delegate: BannerDismissalViewControllerDelegate?
    
    // MARK: - Banner properties
    
    // :nodoc:
    public let bannerConfiguration: BannerConfiguration
    
    // :nodoc:
    public init(_ bannerConfiguration: BannerConfiguration = BannerConfiguration(position: .topLeading, height: 70.0)) {
        self.bannerConfiguration = bannerConfiguration
        
        super.init(nibName: nil, bundle: nil)
        
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func commonInit() {
        view.backgroundColor = .clear
        
        setupParentView()
        setupBackButton()
        setupConstraints()
    }
    
    // MARK: - UIViewController lifecycle methods
    
    public override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    // MARK: - UIViewController setting-up methods
    
    func setupParentView() {
        topBannerView = .forAutoLayout()
        topBannerView.backgroundColor = .clear
        
        topPaddingView = .forAutoLayout()
        topPaddingView.backgroundColor = .clear
        
        let parentViews: [UIView] = [
            topBannerView,
            topPaddingView
        ]
        
        view.addSubviews(parentViews)
    }
    
    func setupBackButton() {
        let backButton = BackButton(type: .system)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        
        let backButtonTitle = NSLocalizedString("BACK",
                                                bundle: .mapboxNavigation,
                                                value: "BACK",
                                                comment: "Title of the back button.")
        
        backButton.setTitle(backButtonTitle, for: .normal)
        backButton.contentEdgeInsets = UIEdgeInsets(top: 0,
                                                    left: 25,
                                                    bottom: 0,
                                                    right: 15)
        backButton.sizeToFit()
        backButton.clipsToBounds = true
        backButton.addTarget(self, action: #selector(didTapDismissBannerButton), for: .touchUpInside)
        backButton.setImage(.backImage, for: .normal)
        backButton.imageView?.contentMode = .scaleAspectFit
        backButton.imageEdgeInsets = UIEdgeInsets(top: 10,
                                                  left: -10,
                                                  bottom: 10,
                                                  right: 15)
        topBannerView.addSubview(backButton)
        
        self.backButton = backButton
    }
    
    // MARK: - Event handlers
    
    @objc func didTapDismissBannerButton() {
        delegate?.didTapDismissBannerButton(self)
    }
}
