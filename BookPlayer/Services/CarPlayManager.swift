//
//  CarPlayManager.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 8/12/19.
//  Copyright © 2019 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import Combine
import CarPlay

class CarPlayManager: NSObject {
  var interfaceController: CPInterfaceController?
  weak var recentTemplate: CPListTemplate?
  weak var libraryTemplate: CPListTemplate?

  private var disposeBag = Set<AnyCancellable>()
  /// Reference for updating boost volume title
  let boostVolumeItem = CPListItem(text: "", detailText: nil)

  override init() {
    super.init()

    self.bindObservers()
  }

  // MARK: - Lifecycle

  func connect(_ interfaceController: CPInterfaceController) {
    self.interfaceController = interfaceController
    self.interfaceController?.delegate = self
    self.setupNowPlayingTemplate()
    self.setRootTemplate()
    self.initializeDataIfNeeded()
  }

  func disconnect() {
    self.interfaceController = nil
    self.recentTemplate = nil
    self.libraryTemplate = nil
  }

  func initializeDataIfNeeded() {
    guard
      AppDelegate.shared?.dataManager == nil,
      SceneDelegate.shared == nil
    else { return }

    let dataInitializerCoordinator = DataInitializerCoordinator(alertPresenter: self)

    dataInitializerCoordinator.onFinish = { stack in
      let services = AppDelegate.shared?.createCoreServicesIfNeeded(from: stack)

      self.setRootTemplate()

      services?.watchService.startSession()
    }

    dataInitializerCoordinator.start()
  }

  func bindObservers() {
    NotificationCenter.default.publisher(for: .bookReady, object: nil)
      .sink(receiveValue: { [weak self] notification in
        guard
          let self = self,
          let loaded = notification.userInfo?["loaded"] as? Bool,
          loaded == true
        else {
          return
        }

        self.reloadRecentItems()

        self.setupNowPlayingTemplate()
      })
      .store(in: &disposeBag)

    NotificationCenter.default.publisher(for: .chapterChange, object: nil)
      .delay(for: .seconds(0.1), scheduler: RunLoop.main, options: .none)
      .sink(receiveValue: { [weak self] _ in
        self?.setupNowPlayingTemplate()
      })
      .store(in: &disposeBag)

    self.boostVolumeItem.handler = { [weak self] (_, completion) in
      let flag = UserDefaults.standard.bool(forKey: Constants.UserDefaults.boostVolumeEnabled.rawValue)

      NotificationCenter.default.post(
        name: .messageReceived,
        object: self,
        userInfo: [
          "command": Command.boostVolume.rawValue,
          "isOn": "\(!flag)"
        ]
      )

      let boostTitle = !flag
      ? "\(Loc.SettingsBoostvolumeTitle.string): \(Loc.ActiveTitle.string)"
      : "\(Loc.SettingsBoostvolumeTitle.string): \(Loc.SleepOffTitle.string)"

      self?.boostVolumeItem.setText(boostTitle)
      completion()
    }
  }

  func loadLibraryItems(at relativePath: String?) -> [SimpleLibraryItem] {
    guard
      let libraryService = AppDelegate.shared?.libraryService
    else { return [] }

    let items = libraryService.fetchContents(at: relativePath, limit: nil, offset: nil) ?? []
    return items.map({ SimpleLibraryItem(from: $0, themeAccent: .blue) })
  }

  func setupNowPlayingTemplate() {
    guard
      let libraryService = AppDelegate.shared?.libraryService,
      let playerManager = AppDelegate.shared?.playerManager
    else { return }

    let prevButton = self.getPreviousChapterButton()

    let nextButton = self.getNextChapterButton()

    let controlsButton = CPNowPlayingImageButton(image: UIImage(systemName: "dial.max")!) { [weak self] _ in
      self?.showPlaybackControlsTemplate()
    }

    let listButton = CPNowPlayingImageButton(image: UIImage(systemName: "list.bullet")!) { [weak self] _ in
      if UserDefaults.standard.bool(forKey: Constants.UserDefaults.playerListPrefersBookmarks.rawValue) {
        self?.showBookmarkListTemplate()
      } else {
        self?.showChapterListTemplate()
      }
    }

    let bookmarksButton = CPNowPlayingImageButton(image: UIImage(named: "toolbarIconBookmark")!) { [weak self, libraryService, playerManager] _ in
      guard
        let self = self,
        let currentItem = playerManager.currentItem
      else { return }

      let alertTitle: String

      if let bookmark = libraryService.createBookmark(
        at: currentItem.currentTime,
        relativePath: currentItem.relativePath,
        type: .user
      ) {
        let formattedTime = TimeParser.formatTime(bookmark.time)
        alertTitle = Loc.BookmarkCreatedTitle(formattedTime).string
      } else {
        alertTitle = Loc.FileMissingTitle.string
      }

      let okAction = CPAlertAction(title: Loc.OkButton.string, style: .default) { _ in
        self.interfaceController?.dismissTemplate(animated: true, completion: nil)
      }
      let alertTemplate = CPAlertTemplate(titleVariants: [alertTitle], actions: [okAction])

      self.interfaceController?.presentTemplate(alertTemplate, animated: true, completion: nil)
    }

    CPNowPlayingTemplate.shared.updateNowPlayingButtons([prevButton, controlsButton, bookmarksButton, listButton, nextButton])
  }

  /// Setup root Tab bar template with the Recent and Library tabs
  func setRootTemplate() {
    let recentTemplate = CPListTemplate(title: Loc.RecentTitle.string, sections: [])
    self.recentTemplate = recentTemplate
    recentTemplate.tabTitle = Loc.RecentTitle.string
    recentTemplate.tabImage = UIImage(systemName: "clock")
    let libraryTemplate = CPListTemplate(title: Loc.LibraryTitle.string, sections: [])
    self.libraryTemplate = libraryTemplate
    libraryTemplate.tabTitle = Loc.LibraryTitle.string
    libraryTemplate.tabImage = UIImage(systemName: "books.vertical")
    let tabTemplate = CPTabBarTemplate(templates: [recentTemplate, libraryTemplate])
    tabTemplate.delegate = self
    self.interfaceController?.setRootTemplate(tabTemplate, animated: false, completion: nil)
  }

  /// Reload content for the root library template
  func reloadLibraryList() {
    let items = getLibraryContents()
    let section = CPListSection(items: items)
    self.libraryTemplate?.updateSections([section])
  }

  /// Push new list template with the selected folder contents
  func pushLibraryList(at relativePath: String?, templateTitle: String) {
    let items = getLibraryContents(at: relativePath)
    let section = CPListSection(items: items)
    let listTemplate = CPListTemplate(title: templateTitle, sections: [section])
    self.interfaceController?.pushTemplate(listTemplate, animated: true, completion: nil)
  }

  /// Returns the library contents at a specified level
  func getLibraryContents(at relativePath: String? = nil) -> [CPListItem] {
    guard
      let libraryService = AppDelegate.shared?.libraryService
    else { return [] }

    let items = libraryService.fetchContents(at: relativePath, limit: nil, offset: nil) ?? []
    let simpleItems = items.map({ SimpleLibraryItem(from: $0, themeAccent: .blue) })

    return transformItems(simpleItems)
  }

  /// Transforms the interface `SimpleLibraryItem` into CarPlay items
  func transformItems(_ items: [SimpleLibraryItem]) -> [CPListItem] {
    return items.map { simpleItem -> CPListItem in
      let item = CPListItem(
        text: simpleItem.title,
        detailText: simpleItem.details,
        image: UIImage(contentsOfFile: ArtworkService.getCachedImageURL(for: simpleItem.relativePath).path)
      )
      item.playbackProgress = CGFloat(simpleItem.progress)
      item.handler = { [weak self, simpleItem] (selectableItem, completion) in
        switch simpleItem.type {
        case .book, .bound:
          self?.playItem(with: simpleItem.relativePath)
        case .folder:
          self?.pushLibraryList(at: simpleItem.relativePath, templateTitle: simpleItem.title)
        }
        completion()
      }

      return item
    }
  }

  /// Reloads the recent items tab
  func reloadRecentItems() {
    guard
      let libraryService = AppDelegate.shared?.libraryService
    else { return }

    let items = libraryService.getLastPlayedItems(limit: 20) ?? []
    let simpleItems = items.map({ SimpleLibraryItem(from: $0, themeAccent: .blue) })

    let cpitems = transformItems(simpleItems)

    cpitems.first?.isPlaying = true

    let section = CPListSection(items: cpitems)
    self.recentTemplate?.updateSections([section])
  }

  /// Handle playing the selected item
  func playItem(with relativePath: String) {
    AppDelegate.shared?.loadPlayer(
      relativePath,
      autoplay: true,
      showPlayer: { [weak self] in
        /// Avoid trying to show the now playing screen if it's already shown
        if self?.interfaceController?.topTemplate != CPNowPlayingTemplate.shared {
          self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
        }
      },
      alertPresenter: self
    )
  }

  func formatSpeed(_ speed: Float) -> String {
    return (speed.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(speed))" : "\(speed)") + "×"
  }
}

// MARK: - Skip Chapter buttons

extension CarPlayManager {
  func hasChapter(before chapter: PlayableChapter?) -> Bool {
    guard
      let playerManager = AppDelegate.shared?.playerManager,
      let chapter = chapter
    else { return false }

    return playerManager.currentItem?.hasChapter(before: chapter) ?? false
  }

  func hasChapter(after chapter: PlayableChapter?) -> Bool {
    guard
      let playerManager = AppDelegate.shared?.playerManager,
      let chapter = chapter
    else { return false }

    return playerManager.currentItem?.hasChapter(after: chapter) ?? false
  }

  func getPreviousChapterButton() -> CPNowPlayingImageButton {
    let prevChapterImageName = self.hasChapter(before: AppDelegate.shared?.playerManager?.currentItem?.currentChapter)
    ? "chevron.left"
    : "chevron.left.2"

    return CPNowPlayingImageButton(image: UIImage(systemName: prevChapterImageName)!) { _ in
      guard let playerManager = AppDelegate.shared?.playerManager else { return }

      if let currentChapter = playerManager.currentItem?.currentChapter,
         let previousChapter = playerManager.currentItem?.previousChapter(before: currentChapter) {
        playerManager.jumpTo(previousChapter.start, recordBookmark: false)
      } else {
        playerManager.playPreviousItem()
      }
    }
  }

  func getNextChapterButton() -> CPNowPlayingImageButton {
    let nextChapterImageName = self.hasChapter(after: AppDelegate.shared?.playerManager?.currentItem?.currentChapter)
    ? "chevron.right"
    : "chevron.right.2"

    return CPNowPlayingImageButton(image: UIImage(systemName: nextChapterImageName)!) { _ in
      guard let playerManager = AppDelegate.shared?.playerManager else { return }

      if let currentChapter = playerManager.currentItem?.currentChapter,
         let nextChapter = playerManager.currentItem?.nextChapter(after: currentChapter) {
        playerManager.jumpTo(nextChapter.start, recordBookmark: false)
      } else {
        playerManager.playNextItem(autoPlayed: false)
      }
    }
  }
}

// MARK: - Chapter List Template

extension CarPlayManager {
  func showChapterListTemplate() {
    guard
      let playerManager = AppDelegate.shared?.playerManager,
      let chapters = playerManager.currentItem?.chapters
    else { return }

    let chapterItems = chapters.enumerated().map({ [weak self, playerManager] (index, chapter) -> CPListItem in
      let chapterTitle = chapter.title == ""
      ? Loc.ChapterNumberTitle(index + 1).string
      : chapter.title

      let chapterDetail = Loc.ChaptersItemDescription(TimeParser.formatTime(chapter.start), TimeParser.formatTime(chapter.duration)).string

      let item = CPListItem(text: chapterTitle, detailText: chapterDetail)

      if let currentChapter = playerManager.currentItem?.currentChapter,
         currentChapter.index == chapter.index {
        item.isPlaying = true
      }

      item.handler = { [weak self] (_, completion) in
        NotificationCenter.default.post(
          name: .messageReceived,
          object: self,
          userInfo: [
            "command": Command.chapter.rawValue,
            "start": "\(chapter.start)"
          ]
        )
        completion()
        self?.interfaceController?.popTemplate(animated: true, completion: nil)
      }
      return item
    })

    let section = CPListSection(items: chapterItems)

    let listTemplate = CPListTemplate(title: Loc.ChaptersTitle.string, sections: [section])

    self.interfaceController?.pushTemplate(listTemplate, animated: true, completion: nil)
  }
}

// MARK: - Bookmark List Template

extension CarPlayManager {
  func createBookmarkCPItem(from bookmark: Bookmark, includeImage: Bool) -> CPListItem {
    let item = CPListItem(
      text: bookmark.note,
      detailText: TimeParser.formatTime(bookmark.time)
    )

    if includeImage {
      item.setAccessoryImage(UIImage(systemName: bookmark.getImageNameForType()!))
    }

    item.handler = { [weak self, bookmark] (_, completion) in
      NotificationCenter.default.post(
        name: .messageReceived,
        object: self,
        userInfo: [
          "command": Command.chapter.rawValue,
          "start": "\(bookmark.time)"
        ]
      )
      completion()
      self?.interfaceController?.popTemplate(animated: true, completion: nil)
    }

    return item
  }

  func showBookmarkListTemplate() {
    guard
      let playerManager = AppDelegate.shared?.playerManager,
      let libraryService = AppDelegate.shared?.libraryService,
      let currentItem = playerManager.currentItem
    else { return }

    let playBookmarks = libraryService.getBookmarks(of: .play, relativePath: currentItem.relativePath) ?? []
    let skipBookmarks = libraryService.getBookmarks(of: .skip, relativePath: currentItem.relativePath) ?? []

    let automaticBookmarks = (playBookmarks + skipBookmarks)
      .sorted(by: { $0.time < $1.time })

    let automaticItems = automaticBookmarks.compactMap { [weak self] bookmark -> CPListItem? in
      return self?.createBookmarkCPItem(from: bookmark, includeImage: true)
    }

    let userBookmarks = (libraryService.getBookmarks(of: .user, relativePath: currentItem.relativePath) ?? [])
      .sorted(by: { $0.time < $1.time })

    let userItems = userBookmarks.compactMap { [weak self] bookmark -> CPListItem? in
      return self?.createBookmarkCPItem(from: bookmark, includeImage: false)
    }

    let section1 = CPListSection(items: automaticItems, header: Loc.BookmarkTypeAutomaticTitle.string, sectionIndexTitle: nil)

    let section2 = CPListSection(items: userItems, header: Loc.BookmarkTypeUserTitle.string, sectionIndexTitle: nil)

    let listTemplate = CPListTemplate(title: Loc.BookmarksTitle.string, sections: [section1, section2])

    self.interfaceController?.pushTemplate(listTemplate, animated: true, completion: nil)
  }
}

// MARK: - Playback Controls

extension CarPlayManager {
  func showPlaybackControlsTemplate() {
    let boostTitle = UserDefaults.standard.bool(forKey: Constants.UserDefaults.boostVolumeEnabled.rawValue)
    ? "\(Loc.SettingsBoostvolumeTitle.string): \(Loc.ActiveTitle.string)"
    : "\(Loc.SettingsBoostvolumeTitle.string): \(Loc.SleepOffTitle.string)"

    boostVolumeItem.setText(boostTitle)

    let section1 = CPListSection(items: [boostVolumeItem])

    let currentSpeed = AppDelegate.shared?.playerManager?.currentSpeed ?? 1
    let formattedSpeed = formatSpeed(currentSpeed)

    let speedItems = self.getSpeedOptions()
      .map({ interval -> CPListItem in
        let item = CPListItem(text: formatSpeed(interval), detailText: nil)
        item.handler = { [weak self] (_, completion) in
          let roundedValue = round(interval * 100) / 100.0

          NotificationCenter.default.post(
            name: .messageReceived,
            object: self,
            userInfo: [
              "command": Command.speed.rawValue,
              "rate": "\(roundedValue)"
            ]
          )

          self?.interfaceController?.popTemplate(animated: true, completion: nil)
          completion()
        }
        return item
      })

    let section2 = CPListSection(items: speedItems, header: "\(Loc.PlayerSpeedTitle.string): \(formattedSpeed)", sectionIndexTitle: nil)

    let listTemplate = CPListTemplate(title: Loc.SettingsControlsTitle.string, sections: [section1, section2])

    self.interfaceController?.pushTemplate(listTemplate, animated: true, completion: nil)
  }

  public func getSpeedOptions() -> [Float] {
    return [
      0.5, 0.6, 0.7, 0.8, 0.9,
      1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9,
      2.0, 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9,
      3.0, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9,
      4.0
    ]
  }
}

extension CarPlayManager: CPInterfaceControllerDelegate {}

extension CarPlayManager: AlertPresenter {
  public func showAlert(_ title: String? = nil, message: String? = nil, completion: (() -> Void)? = nil) {
    let okAction = CPAlertAction(title: Loc.OkButton.string, style: .default) { _ in
      self.interfaceController?.dismissTemplate(animated: true, completion: nil)
      completion?()
    }

    var completeMessage = ""

    if let title = title {
      completeMessage += title
    }

    if let message = message {
      completeMessage += ": \(message)"
    }

    let alertTemplate = CPAlertTemplate(titleVariants: [completeMessage], actions: [okAction])

    self.interfaceController?.presentTemplate(alertTemplate, animated: true, completion: nil)
  }
}

extension CarPlayManager: CPTabBarTemplateDelegate {
  func tabBarTemplate(_ tabBarTemplate: CPTabBarTemplate, didSelect selectedTemplate: CPTemplate) {
    switch selectedTemplate {
    case selectedTemplate where selectedTemplate == self.recentTemplate:
      reloadRecentItems()
    case selectedTemplate where selectedTemplate == self.libraryTemplate:
      reloadLibraryList()
    default:
      break
    }
  }
}
