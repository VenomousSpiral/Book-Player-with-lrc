//
//  ButtonFreeViewModel.swift
//  BookPlayer
//
//  Created by gianni.carlo on 2/9/22.
//  Copyright © 2022 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import Combine
import Foundation

class ButtonFreeViewModel: BaseViewModel<ButtonFreeCoordinator> {
  let playerManager: PlayerManagerProtocol
  let libraryService: LibraryServiceProtocol

  var eventPublisher = PassthroughSubject<String, Never>()

  init(
    playerManager: PlayerManagerProtocol,
    libraryService: LibraryServiceProtocol
  ) {
    self.playerManager = playerManager
    self.libraryService = libraryService
  }

  func disableTimer(_ flag: Bool) {
    // Disregard if it's already handled by setting
    guard !UserDefaults.standard.bool(forKey: Constants.UserDefaults.autolockDisabled.rawValue) else {
      return
    }

    UIApplication.shared.isIdleTimerDisabled = flag
  }

  func playPause() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    guard let currentItem = playerManager.currentItem else { return }

    let isPlaying = playerManager.isPlaying
    playerManager.playPause()
    let formattedTime = TimeParser.formatTime(currentItem.currentTime)

    let message = isPlaying
    ? "\(Loc.PauseTitle.string) (\(formattedTime))"
    : "\(Loc.PlayingTitle.string.capitalized) (\(formattedTime))"
    eventPublisher.send(message)
  }

  func rewind() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    playerManager.rewind()
    eventPublisher.send(Loc.SkippedBackTitle.string)
  }

  func forward() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    playerManager.forward()
    eventPublisher.send(Loc.SkippedForwardTitle.string)
  }

  func createBookmark() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    guard let currentItem = playerManager.currentItem else { return }

    if let bookmark = self.libraryService.getBookmark(
      at: currentItem.currentTime,
      relativePath: currentItem.relativePath,
      type: .user
    ) {
      let formattedTime = TimeParser.formatTime(bookmark.time)
      let message = Loc.BookmarkExistsTitle(formattedTime).string
      eventPublisher.send(message)
      return
    }

    if let bookmark = self.libraryService.createBookmark(
      at: currentItem.currentTime,
      relativePath: currentItem.relativePath,
      type: .user
    ) {
      let formattedTime = TimeParser.formatTime(bookmark.time)
      let message = Loc.BookmarkCreatedTitle(formattedTime).string
      eventPublisher.send(message)
    } else {
      eventPublisher.send(Loc.FileMissingTitle.string)
    }
  }
}
