//
//  File.swift
//
//
//  Created by Luke Zhao on 10/24/21.
//

import UIKit
import ScreenCorners
import BaseToolbox

public protocol Matchable {
  func matchedViewFor(transition: MatchModalTransition, otherViewController: UIViewController) -> UIView?
}

public class MatchModalTransition: Transition {
  lazy var panGR = UIPanGestureRecognizer(target: self, action: #selector(handlePan(gr:)))
  let foregroundContainerView = UIView()
  
  public override func animate() {
    guard let back = backgroundView, let front = foregroundView, let container = transitionContainer else {
      fatalError()
    }
    let matchDestination = findMatchable(viewController: foregroundViewController!)
    let matchSource = findMatchable(viewController: backgroundViewController!)
    let matchedDestinationView = matchDestination?.matchedViewFor(transition: self, otherViewController: backgroundViewController!)
    let matchedSourceView = matchSource?.matchedViewFor(transition: self, otherViewController: foregroundViewController!)

    let foregroundContainerView = self.foregroundContainerView
    foregroundContainerView.autoresizesSubviews = false
    foregroundContainerView.cornerRadius = UIScreen.main.displayCornerRadius
    foregroundContainerView.clipsToBounds = true
    foregroundContainerView.frame = container.bounds
    container.addSubview(foregroundContainerView)
    foregroundContainerView.addSubview(front)
    foregroundContainerView.backgroundColor = .red
    let dismissedFrame = matchedSourceView.map {
      container.convert($0.bounds, from: $0)
    } ?? container.bounds.insetBy(dx: 30, dy: 30)
    let presentedFrame = matchedDestinationView.map {
      container.convert($0.bounds, from: $0)
    } ?? container.bounds
    
    back.addOverlayView()
    let sourceViewPlaceholder = UIView()
    if let matchedSourceView = matchedSourceView {
      matchedSourceView.superview?.insertSubview(sourceViewPlaceholder, aboveSubview: matchedSourceView)
      foregroundContainerView.addSubview(matchedSourceView)
    }

    addDismissStateBlock {
      foregroundContainerView.cornerRadius = 0
      foregroundContainerView.frameWithoutTransform = dismissedFrame
      let scaledSize = presentedFrame.size.size(fill: dismissedFrame.size)
      let scale = scaledSize.width / container.bounds.width
      let sizeOffset = -(scaledSize - dismissedFrame.size) / 2
      let originOffset = -presentedFrame.minY * scale
      let offsetX = -(1 - scale) / 2 * container.bounds.width
      let offsetY = -(1 - scale) / 2 * container.bounds.height
      front.transform = .identity
        .translatedBy(x: offsetX + sizeOffset.width,
                      y: offsetY + sizeOffset.height + originOffset)
        .scaledBy(scale)
      matchedSourceView?.frameWithoutTransform = dismissedFrame.bounds
      matchedSourceView?.alpha = 1
      back.overlayView?.backgroundColor = .clear
    }
    addPresentStateBlock {
      foregroundContainerView.cornerRadius = UIScreen.main.displayCornerRadius
      foregroundContainerView.frameWithoutTransform = container.bounds
      front.transform = .identity
      matchedSourceView?.frameWithoutTransform = presentedFrame
      matchedSourceView?.alpha = 0
      back.overlayView?.backgroundColor = .black.withAlphaComponent(0.5)
    }
    addCompletionBlock { _ in
      back.removeOverlayView()
      container.addSubview(front)
      if let sourceSuperView = sourceViewPlaceholder.superview,
         sourceSuperView != container,
         let matchedSourceView = matchedSourceView {
        matchedSourceView.frameWithoutTransform = sourceSuperView.convert(dismissedFrame, from: container)
        sourceViewPlaceholder.superview?.insertSubview(matchedSourceView, belowSubview: sourceViewPlaceholder)
      }
      matchedSourceView?.alpha = 1
      sourceViewPlaceholder.removeFromSuperview()
      foregroundContainerView.removeFromSuperview()
    }
  }
  
  public override func animateTransition(using context: UIViewControllerContextTransitioning) {
    super.animateTransition(using: context)
    if isInteractive {
      pause(view: foregroundContainerView, animationForKey: "position")
    }
  }

  func findMatchable(viewController: UIViewController) -> Matchable? {
    if let viewController = viewController as? Matchable {
      return viewController
    } else {
      for child in viewController.children {
        if let matchable = findMatchable(viewController: child) {
          return matchable
        }
      }
    }
    return nil
  }
  
  public override func animationEnded(_ transitionCompleted: Bool) {
    if isPresenting, transitionCompleted {
      panGR.delegate = self
      foregroundView?.addGestureRecognizer(panGR)
    }
    super.animationEnded(transitionCompleted)
  }
  
  @objc func handlePan(gr: UIPanGestureRecognizer) {
    guard let view = gr.view else { return }
    func progressFrom(offset: CGPoint) -> CGFloat {
      let progress = (offset.x + offset.y) / ((view.bounds.height + view.bounds.width) / 4)
      return (isPresenting != isReversed ? -progress : progress)
    }
    switch gr.state {
    case .began:
      beginInteractiveTransition()
      if !isTransitioning {
        view.dismiss()
      }
    case .changed:
      guard isTransitioning, let container = transitionContainer else { return }
      let translation = gr.translation(in: view)
      let progress = progressFrom(offset: translation)
      foregroundContainerView.center = container.center + translation / 5
      fractionCompleted = (progress * 0.1).clamp(0, 1)
    default:
      guard isTransitioning else { return }
      let combinedOffset = gr.translation(in: view) + gr.velocity(in: view)
      let progress = progressFrom(offset: combinedOffset)
      let shouldFinish = progress > 0.5
      endInteractiveTransition(shouldFinish: shouldFinish)
    }
  }
}

extension MatchModalTransition: UIGestureRecognizerDelegate {
  public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    let velocity = panGR.velocity(in: nil)
    // only allow right and down swipe
    return velocity.x > abs(velocity.y) || velocity.y > abs(velocity.x)
  }
}
