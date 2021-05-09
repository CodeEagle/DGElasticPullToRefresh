/*

The MIT License (MIT)

Copyright (c) 2015 Danil Gontovnik

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

import UIKit

// MARK: -
// MARK: DGElasticPullToRefreshState

public enum DGElasticPullToRefreshState: Int {
    case stopped
    case dragging
    case animatingBounce
    case loading
    case animatingToStopped
    
    func isAnyOf(_ values: [DGElasticPullToRefreshState]) -> Bool {
        return values.contains(self)
    }
}

// MARK: -
// MARK: DGElasticPullToRefreshView


private var progressImpactGeneratorKey: Void?
private var releaseImpactGeneratorKey: Void?

extension DGElasticPullToRefreshView {
    public struct FeedbackPolicy: RawRepresentable, OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        
        public static let nope = FeedbackPolicy([])
        public static let pull = FeedbackPolicy(rawValue: 1)
        public static let release = FeedbackPolicy(rawValue: 1 << 1)
        public static let all = FeedbackPolicy(rawValue: 1 << 2)
        
        public var isPullEnabled: Bool { rawValue & FeedbackPolicy.pull.rawValue != 0 }
        public var isReleaseEnabled: Bool { rawValue & FeedbackPolicy.release.rawValue != 0 }
    }
    
    private var progressImpactGenerator: UIImpactFeedbackGenerator? {
        var impact: UIImpactFeedbackGenerator
        if let value = objc_getAssociatedObject(self, &progressImpactGeneratorKey) as? UIImpactFeedbackGenerator {
            impact = value
        } else {
            impact = UIImpactFeedbackGenerator(style: UIImpactFeedbackGenerator.FeedbackStyle.light)
            objc_setAssociatedObject(self, &progressImpactGeneratorKey, impact, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        impact.prepare()
        return impact
    }
    
    private var releaseImpactGenerator: UIImpactFeedbackGenerator? {
        var impact: UIImpactFeedbackGenerator
        if let value = objc_getAssociatedObject(self, &releaseImpactGeneratorKey) as? UIImpactFeedbackGenerator {
            impact = value
        } else {
            impact = UIImpactFeedbackGenerator(style: UIImpactFeedbackGenerator.FeedbackStyle.heavy)
            objc_setAssociatedObject(self, &releaseImpactGeneratorKey, impact, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return impact
    }
    
    func handleStateChange() {
        guard feedbackPolicy.isReleaseEnabled else { return }
        switch _state {
        case .dragging: releaseImpactGenerator?.prepare()
        case .animatingBounce: releaseImpactGenerator?.impactOccurred()
        default: break
        }
    }

    func handleProgressChange() {
        guard feedbackPolicy.isPullEnabled else { return }
        progressImpactGenerator?.impactOccurred()
    }
}

public final class DGElasticPullToRefreshView: UIView {
    
    // MARK: -
    // MARK: Vars
    private var _state: DGElasticPullToRefreshState = .stopped
    public private(set) var state: DGElasticPullToRefreshState {
        get { return _state }
        set {
            let previousValue = state
            _state = newValue
            if #available(iOS 10.0, *) { handleStateChange() }
            if previousValue == .dragging, newValue == .animatingBounce {
                loadingView?.startAnimating()
                animateBounce()
            } else if previousValue == .stopped, newValue == .animatingBounce {
                loadingView?.setPullProgress(1.0)
                loadingView?.startAnimating()
                animateBounce()
            } else if newValue == .loading, let action = actionHandler {
                action()
            } else if newValue == .animatingToStopped {
                resetScrollViewContentInset(shouldAddObserverWhenFinished: true, animated: true, completion: { [weak self] () -> () in self?.state = .stopped })
            } else if newValue == .stopped {
                loadingView?.stopLoading()
            }
        }
    }
    
    private var originalContentInsetTop: CGFloat = 0.0 { didSet { layoutSubviews() } }
    private let shapeLayer = CAShapeLayer()
    private var lastProgress: CGFloat = 0
    
    private lazy var displayLink: CADisplayLink = {
        let displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkTick))
        displayLink.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
        displayLink.isPaused = true
        return displayLink
    }()
    
    private var actionHandler: (() -> Void)?
    
    private var loadingView: DGElasticPullToRefreshLoadingView? {
        willSet {
            loadingView?.removeFromSuperview()
            if let newValue = newValue {
                addSubview(newValue)
            }
        }
    }
    
    private weak var targetScrollView: UIScrollView? 
    
    /// Enabled pull to refresh
    public var isEnabled = true
    
    /// Generate Impact Feedback when pull
    public var feedbackPolicy: FeedbackPolicy = .release
    private var ignoreConentInset = false
    
    private lazy var observers: [String : NSKeyValueObservation] = [:]
    
    private var observing: Bool = false {
        didSet {
            guard let scrollView = targetScrollView else { return }
            if observing {
                addContentOffsetObserver(for: scrollView)
                addContentInsetObserver(for: scrollView)
                addFrameObserver(for: scrollView)
                addPanGestureRecognizerStateObserver(for: scrollView)
            } else {
                observers[DGElasticPullToRefreshConstants.KeyPaths.ContentOffset] = nil
                observers[DGElasticPullToRefreshConstants.KeyPaths.ContentInset] = nil
                observers[DGElasticPullToRefreshConstants.KeyPaths.Frame] = nil
                observers[DGElasticPullToRefreshConstants.KeyPaths.PanGestureRecognizerState] = nil
            }
        }
    }
    
    public var fillColor: UIColor = .clear { didSet { shapeLayer.fillColor = fillColor.cgColor } }
    
    // MARK: Views
    
    private let bounceAnimationHelperView = UIView()
    
    private let cControlPointView = UIView()
    private let l1ControlPointView = UIView()
    private let l2ControlPointView = UIView()
    private let l3ControlPointView = UIView()
    private let r1ControlPointView = UIView()
    private let r2ControlPointView = UIView()
    private let r3ControlPointView = UIView()
    
    // MARK: -
    // MARK: Constructors
    
    init(scrollView: UIScrollView) {
        super.init(frame: CGRect.zero)
        targetScrollView = scrollView
        scrollView.addSubview(self)
        
        shapeLayer.backgroundColor = UIColor.clear.cgColor
        shapeLayer.fillColor = UIColor.black.cgColor
        shapeLayer.actions = ["path" : NSNull(), "position" : NSNull(), "bounds" : NSNull()]
        layer.addSublayer(shapeLayer)
        
        addSubview(bounceAnimationHelperView)
        addSubview(cControlPointView)
        addSubview(l1ControlPointView)
        addSubview(l2ControlPointView)
        addSubview(l3ControlPointView)
        addSubview(r1ControlPointView)
        addSubview(r2ControlPointView)
        addSubview(r3ControlPointView)
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.applicationWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    // MARK: -
    
    /**
    Has to be called when the receiver is no longer required. Otherwise the main loop holds a reference to the receiver which in turn will prevent the receiver from being deallocated.
    */
    private func disassociateDisplayLink() {
        displayLink.invalidate()
    }
    
    deinit {
        observing = false
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: -
    // MARK: Notifications
    
    @objc func applicationWillEnterForeground() {
        guard state == .loading else { return }
        layoutSubviews()
    }
    
    // MARK: Methods (Private)
    
    private func isAnimating() -> Bool {
        return state.isAnyOf([.animatingBounce, .animatingToStopped])
    }
    
    private func actualContentOffsetY() -> CGFloat {
        guard let scrollView = targetScrollView else { return 0.0 }
        return max(-scrollView.contentInset.top - scrollView.contentOffset.y, 0)
    }
    
    private func currentHeight() -> CGFloat {
        guard let scrollView = targetScrollView else { return 0.0 }
        return max(-originalContentInsetTop - scrollView.contentOffset.y, 0)
    }
    
    private func currentWaveHeight() -> CGFloat {
        return min(bounds.height / 3.0 * 1.6, DGElasticPullToRefreshConstants.WaveMaxHeight)
    }
    
    private func currentPath() -> CGPath {
        let width: CGFloat = targetScrollView?.bounds.width ?? 0.0
        
        let bezierPath = UIBezierPath()
        let animating = isAnimating()
        
        bezierPath.move(to: CGPoint(x: 0.0, y: 0.0))
        bezierPath.addLine(to: CGPoint(x: 0.0, y: l3ControlPointView.dg_center(animating).y))
        bezierPath.addCurve(to: l1ControlPointView.dg_center(animating), controlPoint1: l3ControlPointView.dg_center(animating), controlPoint2: l2ControlPointView.dg_center(animating))
        bezierPath.addCurve(to: r1ControlPointView.dg_center(animating), controlPoint1: cControlPointView.dg_center(animating), controlPoint2: r1ControlPointView.dg_center(animating))
        bezierPath.addCurve(to: r3ControlPointView.dg_center(animating), controlPoint1: r1ControlPointView.dg_center(animating), controlPoint2: r2ControlPointView.dg_center(animating))
        bezierPath.addLine(to: CGPoint(x: width, y: 0.0))
        
        bezierPath.close()
        
        return bezierPath.cgPath
    }
    
    private func scrollViewDidChangeContentOffset(dragging: Bool) {
        let offsetY = actualContentOffsetY()
        
        if state == .stopped && dragging {
            state = .dragging
        } else if state == .dragging && dragging == false {
            if offsetY >= DGElasticPullToRefreshConstants.MinOffsetToPull {
                state = .animatingBounce
            } else {
                state = .stopped
            }
        } else if state.isAnyOf([.dragging, .stopped]) {
            let pullProgress: CGFloat = offsetY / DGElasticPullToRefreshConstants.MinOffsetToPull
            loadingView?.setPullProgress(pullProgress)
            if pullProgress - lastProgress >= 0.2, lastProgress <= 1, pullProgress <= 1 {
                lastProgress = pullProgress
                if #available(iOS 10.0, *) {
                    handleProgressChange()
                }
            } else if lastProgress - pullProgress >= 0 {
                lastProgress = pullProgress
            }
        }
    }
    
    private func resetScrollViewContentInset(shouldAddObserverWhenFinished: Bool, animated: Bool, completion: (() -> ())?) {
        guard let scrollView = targetScrollView else { return }
        
        var contentInset = scrollView.contentInset
        contentInset.top = originalContentInsetTop
        
        if state == .animatingBounce {
            contentInset.top += currentHeight()
        } else if state == .loading {
            contentInset.top += DGElasticPullToRefreshConstants.LoadingContentInset
        }
        observers[DGElasticPullToRefreshConstants.KeyPaths.ContentInset] = nil
        
        let animationBlock = {
            self.ignoreConentInset = true
            scrollView.contentInset = contentInset
            self.ignoreConentInset = false
        }
        let completionBlock = { () -> Void in
            if shouldAddObserverWhenFinished && self.observing {
                self.addContentInsetObserver(for: scrollView)
            }
            completion?()
        }
        
        if animated {
            startDisplayLink()
            UIView.animate(withDuration: 0.4, animations: animationBlock, completion: { _ in
                self.stopDisplayLink()
                completionBlock()
            })
        } else {
            animationBlock()
            completionBlock()
        }
    }
    
    private func animateBounce() {
        guard let scrollView = targetScrollView else { return }

        resetScrollViewContentInset(shouldAddObserverWhenFinished: false, animated: false, completion: nil)
        
        let centerY = DGElasticPullToRefreshConstants.LoadingContentInset
        let duration = 0.9
        
        scrollView.isScrollEnabled = false
        startDisplayLink()
        observers[DGElasticPullToRefreshConstants.KeyPaths.ContentOffset] = nil
        observers[DGElasticPullToRefreshConstants.KeyPaths.ContentInset] = nil
        UIView.animate(withDuration: duration, delay: 0.0, usingSpringWithDamping: 0.43, initialSpringVelocity: 0.0, options: [], animations: { [weak self] in
            self?.cControlPointView.center.y = centerY
            self?.l1ControlPointView.center.y = centerY
            self?.l2ControlPointView.center.y = centerY
            self?.l3ControlPointView.center.y = centerY
            self?.r1ControlPointView.center.y = centerY
            self?.r2ControlPointView.center.y = centerY
            self?.r3ControlPointView.center.y = centerY
            }, completion: { [weak self] _ in
                self?.stopDisplayLink()
                self?.resetScrollViewContentInset(shouldAddObserverWhenFinished: true, animated: false, completion: nil)
                if let strongSelf = self, let scrollView = strongSelf.targetScrollView {
                    strongSelf.addContentOffsetObserver(for: scrollView)
                    scrollView.isScrollEnabled = true
                }
                self?.state = .loading
            })
        
        bounceAnimationHelperView.center = CGPoint(x: 0.0, y: originalContentInsetTop + currentHeight())
        UIView.animate(withDuration: duration * 0.4, animations: { [weak self] in
            if let contentInsetTop = self?.originalContentInsetTop {
                self?.bounceAnimationHelperView.center = CGPoint(x: 0.0, y: contentInsetTop + DGElasticPullToRefreshConstants.LoadingContentInset)
            }
            }, completion: nil)
    }
    
    // MARK: -
    // MARK: CADisplayLink
    
    private func startDisplayLink() {
        displayLink.isPaused = false
    }
    
    private func stopDisplayLink() {
        displayLink.isPaused = true
    }
    
    @objc func displayLinkTick() {
        let width = bounds.width
        var height: CGFloat = 0.0
        
        if state == .animatingBounce {
            guard let scrollView = targetScrollView else { return }
            ignoreConentInset = true
            scrollView.contentInset.top = bounceAnimationHelperView.dg_center(isAnimating()).y
            ignoreConentInset = false
            scrollView.contentOffset.y = -scrollView.contentInset.top
            
            height = scrollView.contentInset.top - originalContentInsetTop
            
            frame = CGRect(x: 0.0, y: -height - 1.0, width: width, height: height)
        } else if state == .animatingToStopped {
            height = actualContentOffsetY()
        }

        shapeLayer.frame = CGRect(x: 0.0, y: 0.0, width: width, height: height)
        shapeLayer.path = currentPath()
        
        layoutLoadingView()
    }
    
    // MARK: -
    // MARK: Layout
    
    private func layoutLoadingView() {
        let width = bounds.width
        let height: CGFloat = bounds.height
        
        let loadingViewSize: CGFloat = DGElasticPullToRefreshConstants.LoadingViewSize
        let minOriginY = (DGElasticPullToRefreshConstants.LoadingContentInset - loadingViewSize) / 2.0
        let originY: CGFloat = max(min((height - loadingViewSize) / 2.0, minOriginY), 0.0)
        
        loadingView?.frame = CGRect(x: (width - loadingViewSize) / 2.0, y: originY, width: loadingViewSize, height: loadingViewSize)
        loadingView?.maskLayer.frame = convert(shapeLayer.frame, to: loadingView)
        loadingView?.maskLayer.path = shapeLayer.path
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        if let scrollView = targetScrollView , state != .animatingBounce {
            let width = scrollView.bounds.width
            let height = currentHeight()
            
            frame = CGRect(x: 0.0, y: -height, width: width, height: height)
            
            if state.isAnyOf([.loading, .animatingToStopped]) {
                cControlPointView.center = CGPoint(x: width / 2.0, y: height)
                l1ControlPointView.center = CGPoint(x: 0.0, y: height)
                l2ControlPointView.center = CGPoint(x: 0.0, y: height)
                l3ControlPointView.center = CGPoint(x: 0.0, y: height)
                r1ControlPointView.center = CGPoint(x: width, y: height)
                r2ControlPointView.center = CGPoint(x: width, y: height)
                r3ControlPointView.center = CGPoint(x: width, y: height)
            } else {
                let locationX = scrollView.panGestureRecognizer.location(in: scrollView).x
                
                let waveHeight = currentWaveHeight()
                let baseHeight = bounds.height - waveHeight
                
                let minLeftX = min((locationX - width / 2.0) * 0.28, 0.0)
                let maxRightX = max(width + (locationX - width / 2.0) * 0.28, width)
                
                let leftPartWidth = locationX - minLeftX
                let rightPartWidth = maxRightX - locationX
                
                cControlPointView.center = CGPoint(x: locationX , y: baseHeight + waveHeight * 1.36)
                l1ControlPointView.center = CGPoint(x: minLeftX + leftPartWidth * 0.71, y: baseHeight + waveHeight * 0.64)
                l2ControlPointView.center = CGPoint(x: minLeftX + leftPartWidth * 0.44, y: baseHeight)
                l3ControlPointView.center = CGPoint(x: minLeftX, y: baseHeight)
                r1ControlPointView.center = CGPoint(x: maxRightX - rightPartWidth * 0.71, y: baseHeight + waveHeight * 0.64)
                r2ControlPointView.center = CGPoint(x: maxRightX - (rightPartWidth * 0.44), y: baseHeight)
                r3ControlPointView.center = CGPoint(x: maxRightX, y: baseHeight)
            }
            
            shapeLayer.frame = CGRect(x: 0.0, y: 0.0, width: width, height: height)
            shapeLayer.path = currentPath()
            
            layoutLoadingView()
        }
    }
    
}
// MARK: - Add Observer
extension DGElasticPullToRefreshView {
    private func addContentOffsetObserver(for scrollView: UIScrollView) {
        let ob1 = scrollView.observe(\UIScrollView.contentOffset, options: .new, changeHandler: {[unowned self] (scrollView, result) in
            guard self.isEnabled else { return }
            guard let newContentOffsetY = result.newValue?.y else { return }
            if self.state.isAnyOf([.loading, .animatingToStopped]) && newContentOffsetY < -scrollView.contentInset.top {
                scrollView.contentOffset.y = -scrollView.contentInset.top
            } else {
                self.scrollViewDidChangeContentOffset(dragging: scrollView.isDragging)
            }
            self.layoutSubviews()
        })
        observers[DGElasticPullToRefreshConstants.KeyPaths.ContentOffset] = ob1
    }
    
    private func addContentInsetObserver(for scrollView: UIScrollView) {
        let ob = scrollView.observe(\UIScrollView.contentInset, options: .new, changeHandler: {[unowned self] (scrollView, result) in
            guard self.isEnabled else { return }
            guard self.ignoreConentInset == false else { return }
            if let newContentInsetTop = result.newValue?.top {
                self.originalContentInsetTop = newContentInsetTop
            }
        })
        observers[DGElasticPullToRefreshConstants.KeyPaths.ContentInset] = ob
    }
    
    private func addFrameObserver(for scrollView: UIScrollView) {
        let ob = scrollView.observe(\UIScrollView.frame, options: .new, changeHandler: {[unowned self] (scrollView, result) in
            guard self.isEnabled else { return }
            self.layoutSubviews()
        })
        observers[DGElasticPullToRefreshConstants.KeyPaths.Frame] = ob
    }
    
    private func addPanGestureRecognizerStateObserver(for scrollView: UIScrollView) {
        let ob = scrollView.observe(\UIScrollView.panGestureRecognizer.state, options: .new, changeHandler: {[unowned self] (scrollView, result) in
            guard self.isEnabled else { return }
            let gestureState = scrollView.panGestureRecognizer.state
            if gestureState.dg_isAnyOf([.ended, .cancelled, .failed]) {
                self.scrollViewDidChangeContentOffset(dragging: false)
            }
        })
        observers[DGElasticPullToRefreshConstants.KeyPaths.PanGestureRecognizerState] = ob
    }
}
// MARK: - Public
extension DGElasticPullToRefreshView {
    public func configActionHandler(_ actionHandler: @escaping () -> Void, loadingView: DGElasticPullToRefreshLoadingView?) {
        targetScrollView?.isMultipleTouchEnabled = false
        targetScrollView?.panGestureRecognizer.maximumNumberOfTouches = 1
        self.actionHandler = actionHandler
        self.loadingView = loadingView
        observing = true
    }
    
    public func remove() {
       disassociateDisplayLink()
       observing = false
       removeFromSuperview()
    }
    
    public func startLoading() {
        guard state == .stopped else { return }
        state = .animatingBounce
    }
    
    public func stopLoading() {
        guard state != .animatingToStopped, state != .stopped else { return }
        state = .animatingToStopped
    }
}
