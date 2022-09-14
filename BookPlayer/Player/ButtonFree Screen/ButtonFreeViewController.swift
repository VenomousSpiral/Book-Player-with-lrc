//
//  ButtonFreeViewController.swift
//  BookPlayer
//
//  Created by gianni.carlo on 2/9/22.
//  Copyright © 2022 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import Combine
import Themeable
import UIKit

class ButtonFreeViewController: BaseViewController<ButtonFreeCoordinator, ButtonFreeViewModel> {

  private lazy var contentStackview: UIStackView = {
    let stackview = UIStackView()
    stackview.spacing = 12
    stackview.axis = .vertical
    stackview.translatesAutoresizingMaskIntoConstraints = false
    stackview.isUserInteractionEnabled = false
    return stackview
  }()

  private lazy var titleItem: UILabel = {
    let label = UILabel()
    label.font = UIFont.preferredFont(with: 16, style: .headline, weight: .semibold)
    label.text = Loc.ScreenGesturesTitle.string.capitalized
    label.numberOfLines = 0
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
  }()

  private lazy var tapItem: UIStackView = {
    return GestureItemRow(
      title: Loc.GestureTapTitle.string,
      systemImageName: "hand.tap"
    )
  }()

  private lazy var swipeLeftItem: UIStackView = {
    return GestureItemRow(
      title: Loc.GestureSwipeLeftTitle.string,
      systemImageName: "arrow.left"
    )
  }()

  private lazy var swipeRightItem: UIStackView = {
    return GestureItemRow(
      title: Loc.GestureSwipeRightTitle.string,
      systemImageName: "arrow.right"
    )
  }()

  private lazy var swipeVerticalItem: UIStackView = {
    return GestureItemRow(
      title: Loc.GestureSwipeVerticallyTitle.string,
      systemImageName: "arrow.up.arrow.down"
    )
  }()

  private lazy var containerMessageView: UIView = {
    let view = UIView()
    view.translatesAutoresizingMaskIntoConstraints = false
    view.alpha = 0
    return view
  }()

  private lazy var messageLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.numberOfLines = 0
    label.textAlignment = .center
    label.font = UIFont.preferredFont(with: 16, style: .headline, weight: .semibold)
    label.alpha = 0
    return label
  }()

  private var hideLabelJob: DispatchWorkItem?

  private var disposeBag = Set<AnyCancellable>()

  // MARK: - Init
  init(viewModel: ButtonFreeViewModel) {
    super.init(nibName: nil, bundle: nil)
    self.viewModel = viewModel
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    self.navigationItem.title = Loc.ButtonFreeTitle.string.capitalized

    self.navigationItem.leftBarButtonItem = UIBarButtonItem(
      image: UIImage(systemName: "xmark"),
      style: .plain,
      target: self,
      action: #selector(self.didPressClose)
    )

    addSubviews()
    addConstraints()

    addGestures()
    setUpTheming()
    bindObservers()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)

    viewModel.disableTimer(true)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)

    viewModel.disableTimer(false)
  }

  func addSubviews() {
    view.addSubview(contentStackview)
    view.addSubview(containerMessageView)
    containerMessageView.addSubview(messageLabel)
    contentStackview.addArrangedSubview(titleItem)
    contentStackview.addArrangedSubview(tapItem)
    contentStackview.addArrangedSubview(swipeLeftItem)
    contentStackview.addArrangedSubview(swipeRightItem)
    contentStackview.addArrangedSubview(swipeVerticalItem)
  }

  func addConstraints() {
    let safeAreaLayoutGuide = view.safeAreaLayoutGuide

    NSLayoutConstraint.activate([
      contentStackview.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 24),
      contentStackview.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 24),
      contentStackview.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -24),
      containerMessageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      containerMessageView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 24),
      containerMessageView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -24),
      messageLabel.topAnchor.constraint(equalTo: containerMessageView.topAnchor, constant: 8),
      messageLabel.leadingAnchor.constraint(equalTo: containerMessageView.leadingAnchor, constant: 24),
      messageLabel.trailingAnchor.constraint(equalTo: containerMessageView.trailingAnchor, constant: -24),
      messageLabel.bottomAnchor.constraint(equalTo: containerMessageView.bottomAnchor, constant: -8),
    ])
  }

  func bindObservers() {
    viewModel.eventPublisher.sink { [weak self] message in
      self?.handleMessage(message)
    }.store(in: &disposeBag)
  }

  func handleMessage(_ message: String) {
    scheduleHidejob()
    messageLabel.alpha = 0
    containerMessageView.alpha = 0
    messageLabel.text = message
    UIView.animate(withDuration: 0.3) { [weak self] in
      self?.messageLabel.alpha = 1
      self?.containerMessageView.alpha = 1
    }
  }

  func scheduleHidejob() {
    hideLabelJob?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      UIView.animate(withDuration: 0.3) {
        self?.messageLabel.alpha = 0
        self?.containerMessageView.alpha = 0
      }
    }
    hideLabelJob = workItem

    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: workItem)
  }

  func addGestures() {
    let tap = UITapGestureRecognizer(
      target: self,
      action: #selector(handleTapGesture)
    )
    view.addGestureRecognizer(tap)

    [
      UISwipeGestureRecognizer.Direction.left,
      UISwipeGestureRecognizer.Direction.up,
      UISwipeGestureRecognizer.Direction.right,
      UISwipeGestureRecognizer.Direction.down
    ].forEach {
      let swipe = UISwipeGestureRecognizer(
        target: self,
        action: #selector(handleSwipeGesture)
      )
      swipe.direction = $0
      view.addGestureRecognizer(swipe)
    }
  }

  @objc func didPressClose() {
    viewModel.dismiss()
  }

  @objc func handleTapGesture() {
    viewModel.playPause()
  }

  @objc func handleSwipeGesture(_ gesture: UISwipeGestureRecognizer) {
    switch gesture.direction {
    case .up, .down:
      viewModel.createBookmark()
    case .left:
      viewModel.rewind()
    case .right:
      viewModel.forward()
    default:
      break
    }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool {
    return true
  }
}

extension ButtonFreeViewController: Themeable {
  func applyTheme(_ theme: SimpleTheme) {
    self.view.backgroundColor = theme.systemBackgroundColor
    titleItem.textColor = theme.primaryColor
    messageLabel.textColor = theme.primaryColor
    containerMessageView.backgroundColor = theme.systemGroupedBackgroundColor

    self.overrideUserInterfaceStyle = theme.useDarkVariant
      ? UIUserInterfaceStyle.dark
      : UIUserInterfaceStyle.light
  }
}

/// Reference: https://stackoverflow.com/a/62687023/2105150
extension UIFont {
  static func preferredFont(with size: CGFloat, style: TextStyle, weight: Weight, italic: Bool = false) -> UIFont {
    // Get the font at the specified size and preferred weight
    var font = UIFont.systemFont(ofSize: size, weight: weight)
    if italic == true {
      font = font.with([.traitItalic])
    }

    // Setup the font to be auto-scalable
    let metrics = UIFontMetrics(forTextStyle: style)
    return metrics.scaledFont(for: font)
  }

  private func with(_ traits: UIFontDescriptor.SymbolicTraits...) -> UIFont {
    guard let descriptor = fontDescriptor.withSymbolicTraits(UIFontDescriptor.SymbolicTraits(traits).union(fontDescriptor.symbolicTraits)) else {
      return self
    }
    return UIFont(descriptor: descriptor, size: 0)
  }
}
