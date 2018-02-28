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
// MARK: (UIScrollView) Extension

public extension UIScrollView {

    // MARK: -
    // MARK: Vars

    fileprivate struct dg_associatedKeys {
        static var pullToRefreshView = "pullToRefreshView"
    }
    
    public var dgelastic: DGElasticPullToRefreshView {
        get {
            if let view = objc_getAssociatedObject(self, &dg_associatedKeys.pullToRefreshView) as? DGElasticPullToRefreshView {
                return view
            }
            let view = DGElasticPullToRefreshView(scrollView: self)
            view.fillColor = DGElasticPullToRefreshConstants.PullToRefreshFillColor
            view.backgroundColor = DGElasticPullToRefreshConstants.PullToRefreshBackgroundColor
            objc_setAssociatedObject(self, &dg_associatedKeys.pullToRefreshView, view, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return view
        }
        set {
            objc_setAssociatedObject(self, &dg_associatedKeys.pullToRefreshView, newValue, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: -
// MARK: (UIView) Extension

public extension UIView {
    func dg_center(_ usePresentationLayerIfPossible: Bool) -> CGPoint {
        if usePresentationLayerIfPossible, let presentationLayer = layer.presentation() {
            // Position can be used as a center, because anchorPoint is (0.5, 0.5)
            return presentationLayer.position
        }
        return center
    }
}

// MARK: -
// MARK: (UIPanGestureRecognizer) Extension

public extension UIPanGestureRecognizer {
    func dg_resign() {
        isEnabled = false
        isEnabled = true
    }
}

// MARK: -
// MARK: (UIGestureRecognizerState) Extension

public extension UIGestureRecognizerState {
    func dg_isAnyOf(_ values: [UIGestureRecognizerState]) -> Bool {
        return values.contains(self)
    }
}
