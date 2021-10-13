// Created by eric_horacek on 9/16/21.
// Copyright © 2021 Airbnb Inc. All rights reserved.

import Combine
import SwiftUI

// MARK: - SwiftUIHostingViewReuseBehavior

/// The reuse behavior of an `EpoxySwiftUIHostingView`.
public enum SwiftUIHostingViewReuseBehavior: Hashable {
  /// Instances of a `EpoxySwiftUIHostingView` with `RootView`s of same type can be reused within
  /// the Epoxy container.
  ///
  /// This is the default reuse behavior.
  case reusable
  /// Instances of a `EpoxySwiftUIHostingView` with `RootView`s of same type can only reused within
  /// the Epoxy container when they have identical `reuseID`s.
  case unique(reuseID: AnyHashable)
}

// MARK: - CallbackContextEpoxyModeled

extension CallbackContextEpoxyModeled
  where
  Self: WillDisplayProviding & DidEndDisplayingProviding,
  CallbackContext: ViewProviding & AnimatedProviding
{
  /// Updates the appearance state of a `EpoxySwiftUIHostingView` in coordination with the
  /// `willDisplay` and `didEndDisplaying` callbacks of this `EpoxyableModel`.
  ///
  /// - Note: You should only need to call then from the implementation of a concrete
  ///   `EpoxyableModel` convenience vendor method, e.g. `SwiftUI.View.itemModel(…)`.
  public func linkDisplayLifecycle<RootView: View>() -> Self
    where
    CallbackContext.View == EpoxySwiftUIHostingView<RootView>
  {
    willDisplay { context in
      context.view.handleWillDisplay(animated: context.animated)
    }
    .didEndDisplaying { context in
      context.view.handleDidEndDisplaying(animated: context.animated)
    }
  }
}

// MARK: - EpoxySwiftUIHostingView

/// A `UIView` that hosts a SwiftUI view within an Epoxy container, e.g. an Epoxy `CollectionView`.
///
/// Wraps an `EpoxySwiftUIHostingController` and adds it as a child view controller to the next
/// ancestor view controller in the hierarchy.
///
/// There's a private API that accomplishes this same behavior without needing a `UIViewController`:
/// `_UIHostingView`, but we can't safely use it as 1) the behavior may change out from under us, 2)
/// the API is private and 3) the `_UIHostingView` doesn't not accept setting a new `View` instance.
///
/// - SeeAlso: `EpoxySwiftUIHostingController`
public final class EpoxySwiftUIHostingView<RootView: View>: UIView, EpoxyableView {

  // MARK: Lifecycle

  public init(style: Style) {
    // Ignore the safe area to ensure the view isn't laid out incorrectly when being sized while
    // overlapping the safe area.
    viewController = EpoxySwiftUIHostingController(
      rootView: .init(environment: epoxyEnvironment, content: style.initialContent.rootView),
      ignoreSafeArea: true)

    dataID = style.initialContent.dataID ?? DefaultDataID.noneProvided as AnyHashable

    super.init(frame: .zero)

    layoutMargins = .zero
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Public

  public struct Style: Hashable {
    public init(reuseBehavior: SwiftUIHostingViewReuseBehavior, initialContent: Content) {
      self.reuseBehavior = reuseBehavior
      self.initialContent = initialContent
    }

    public var reuseBehavior: SwiftUIHostingViewReuseBehavior
    public var initialContent: Content

    public static func == (lhs: Style, rhs: Style) -> Bool {
      lhs.reuseBehavior == rhs.reuseBehavior
    }

    public func hash(into hasher: inout Hasher) {
      hasher.combine(reuseBehavior)
    }
  }

  public struct Content: Equatable {
    public init(rootView: RootView, dataID: AnyHashable?) {
      self.rootView = rootView
      self.dataID = dataID
    }

    public var rootView: RootView
    public var dataID: AnyHashable?

    public static func == (lhs: Content, rhs: Content) -> Bool {
      // The content should never be equal since we need the `rootView` to be updated on every
      // content change.
      false
    }
  }

  public override func didMoveToWindow() {
    super.didMoveToWindow()

    // We'll only be able to discover a valid parent `viewController` once we're added to a window,
    // so we do so here in addition to the `handleWillDisplay(…)` method.
    if window != nil {
      addViewControllerIfNeeded()
    }
  }

  public func setContent(_ content: Content, animated: Bool) {
    viewController.rootView = .init(environment: epoxyEnvironment, content: content.rootView)
    dataID = content.dataID ?? DefaultDataID.noneProvided as AnyHashable

    // The view controller must be added to the view controller hierarchy to measure its content.
    if window != nil {
      addViewControllerIfNeeded()
    }

    /// This is required to ensure that views with new content are properly resized.
    viewController.view.invalidateIntrinsicContentSize()
  }

  public override func layoutMarginsDidChange() {
    super.layoutMarginsDidChange()

    let margins = layoutMargins
    switch effectiveUserInterfaceLayoutDirection {
    case .rightToLeft:
      epoxyEnvironment.layoutMargins = .init(
        top: margins.top,
        leading: margins.right,
        bottom: margins.bottom,
        trailing: margins.left)
    case .leftToRight:
      fallthrough
    @unknown default:
      epoxyEnvironment.layoutMargins = .init(
        top: margins.top,
        leading: margins.left,
        bottom: margins.bottom,
        trailing: margins.right)
    }

    // Allow the layout margins update to fully propagate through to the SwiftUI View before
    // invalidating the layout.
    DispatchQueue.main.async {
      self.viewController.view.invalidateIntrinsicContentSize()
    }
  }

  public func handleWillDisplay(animated: Bool) {
    guard state != .appeared, window != nil else { return }
    transition(to: .appearing(animated: animated))
    transition(to: .appeared)
  }

  public func handleDidEndDisplaying(animated: Bool) {
    guard state != .disappeared else { return }
    transition(to: .disappearing(animated: animated))
    transition(to: .disappeared)
  }

  // MARK: Private

  private let viewController: EpoxySwiftUIHostingController<EpoxyHostingWrapper<RootView>>
  private let epoxyEnvironment = EpoxyHostingEnvironment()
  private var dataID: AnyHashable
  private var state: AppearanceState = .disappeared

  /// Updates the appearance state of the `viewController`.
  private func transition(to state: AppearanceState) {
    guard state != self.state else { return }

    // See "Handling View-Related Notifications" section for the state machine diagram.
    // https://developer.apple.com/documentation/uikit/uiviewcontroller
    switch (to: state, from: self.state) {
    case (to: .appearing(let animated), from: .disappeared):
      viewController.beginAppearanceTransition(true, animated: animated)
      addViewControllerIfNeeded()
    case (to: .disappearing(let animated), from: .appeared):
      viewController.beginAppearanceTransition(false, animated: animated)
    case (to: .disappeared, from: .disappearing):
      removeViewControllerIfNeeded()
    case (to: .appeared, from: .appearing):
      viewController.endAppearanceTransition()
    case (to: .disappeared, from: .appeared):
      viewController.beginAppearanceTransition(false, animated: true)
      removeViewControllerIfNeeded()
    case (to: .appeared, from: .disappearing(let animated)):
      viewController.beginAppearanceTransition(true, animated: animated)
      viewController.endAppearanceTransition()
    case (to: .disappeared, from: .appearing(let animated)):
      viewController.beginAppearanceTransition(false, animated: animated)
      removeViewControllerIfNeeded()
    case (to: .appeared, from: .disappeared):
      viewController.beginAppearanceTransition(true, animated: false)
      addViewControllerIfNeeded()
      viewController.endAppearanceTransition()
    case (to: .appearing(let animated), from: .appeared):
      viewController.beginAppearanceTransition(false, animated: animated)
      viewController.beginAppearanceTransition(true, animated: animated)
    case (to: .appearing(let animated), from: .disappearing):
      viewController.beginAppearanceTransition(true, animated: animated)
    case (to: .disappearing(let animated), from: .disappeared):
      viewController.beginAppearanceTransition(true, animated: animated)
      addViewControllerIfNeeded()
      viewController.beginAppearanceTransition(false, animated: animated)
    case (to: .disappearing(let animated), from: .appearing):
      viewController.beginAppearanceTransition(false, animated: animated)
    case (to: .appearing, from: .appearing),
         (to: .appeared, from: .appeared),
         (to: .disappearing, from: .disappearing),
         (to: .disappeared, from: .disappeared):
      // This should never happen since we guard on identical states.
      EpoxyLogger.shared.assertionFailure("Impossible state change from \(self.state) to \(state)")
    }

    self.state = state
  }

  private func addViewControllerIfNeeded() {
    // This isn't great, and means that we're going to add this view controller as a child view
    // controller of a view controller somewhere else in the hierarchy, which the author of that
    // view controller may not be expecting. However there's not really a better pathway forward
    // here without requiring a view controller instance to be passed all the way through, which is
    // both burdensome and error-prone.
    guard let nextViewController = superview?.next(UIViewController.self) else {
      EpoxyLogger.shared.assertionFailure(
        """
        Unable to add a UIHostingController view, could not locate a UIViewController in the \
        responder chain for view with ID \(dataID) of type \(RootView.self).
        """)
      return
    }

    guard viewController.parent !== nextViewController else { return }

    // If in a different parent, we need to first remove from it before we add.
    if viewController.parent != nil {
      removeViewControllerIfNeeded()
    }

    addViewController(to: nextViewController)

    state = .appeared
  }

  private func addViewController(to parent: UIViewController) {
    viewController.willMove(toParent: parent)
    parent.addChild(viewController)
    addSubview(viewController.view)
    viewController.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      viewController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      viewController.view.topAnchor.constraint(equalTo: topAnchor),
      viewController.view.trailingAnchor.constraint(equalTo: trailingAnchor),
      viewController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    viewController.didMove(toParent: parent)
  }

  private func removeViewControllerIfNeeded() {
    guard viewController.parent != nil else { return }

    viewController.willMove(toParent: nil)
    viewController.view.removeFromSuperview()
    viewController.removeFromParent()
    viewController.didMove(toParent: nil)
  }
}

// MARK: - AppearanceState

/// The appearance state of a `EpoxySwiftUIHostingController` contained within a
/// `EpoxySwiftUIHostingView`.
private enum AppearanceState: Equatable {
  case appearing(animated: Bool)
  case appeared
  case disappearing(animated: Bool)
  case disappeared
}

// MARK: - UIResponder

extension UIResponder {
  /// Recursively traverses the responder chain upwards from this responder to its next responder
  /// until the a responder of the given type is located, else returns `nil`.
  @nonobjc
  fileprivate func next<ResponderType>(_ type: ResponderType.Type) -> ResponderType? {
    self as? ResponderType ?? next?.next(type)
  }
}

// MARK: - EpoxyHostingEnvironment

/// The object that is used to communicate values to SwiftUI views within an
/// `EpoxySwiftUIHostingController`, e.g. layout margins.
final class EpoxyHostingEnvironment: ObservableObject {
  @Published var layoutMargins = EdgeInsets()
}

// MARK: - EpoxyHostingWrapper

/// The wrapper view that is used to communicate values to SwiftUI views within an
/// `EpoxySwiftUIHostingController`, e.g. layout margins.
struct EpoxyHostingWrapper<Content: View>: View {
  @ObservedObject var environment: EpoxyHostingEnvironment
  var content: Content

  var body: some View {
    content.environment(\.epoxyLayoutMargins, environment.layoutMargins)
  }
}
