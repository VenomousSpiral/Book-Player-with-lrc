//
//  PlayerSettingsViewController.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 12/19/18.
//  Copyright © 2018 Tortuga Power. All rights reserved.
//

import BookPlayerKit
import Combine
import Themeable
import UIKit

class PlayerSettingsViewController: UITableViewController {
  @IBOutlet weak var smartRewindSwitch: UISwitch!
  @IBOutlet weak var boostVolumeSwitch: UISwitch!
  @IBOutlet weak var globalSpeedSwitch: UISwitch!
  @IBOutlet weak var rewindIntervalLabel: UILabel!
  @IBOutlet weak var forwardIntervalLabel: UILabel!
  @IBOutlet weak var playerListPreferenceLabel: UILabel!
  @IBOutlet weak var listImageView: UIImageView!
  @IBOutlet weak var remainingTimeSwitch: UISwitch!
  @IBOutlet weak var chapterTimeSwitch: UISwitch!

  let viewModel = PlayerSettingsViewModel()
  private var disposeBag = Set<AnyCancellable>()

  enum SettingsSection: Int {
    case intervals = 0, rewind, volume, speed, playerList, progressLabels
  }

  let playerListPreferencePath = IndexPath(row: 0, section: SettingsSection.playerList.rawValue)

  override func viewDidLoad() {
    super.viewDidLoad()

    setUpTheming()

    self.navigationItem.title = Loc.SettingsControlsTitle.string
    self.smartRewindSwitch.addTarget(self, action: #selector(self.rewindToggleDidChange), for: .valueChanged)
    self.boostVolumeSwitch.addTarget(self, action: #selector(self.boostVolumeToggleDidChange), for: .valueChanged)
    self.globalSpeedSwitch.addTarget(self, action: #selector(self.globalSpeedToggleDidChange), for: .valueChanged)

    // Set initial switch positions
    self.smartRewindSwitch.setOn(UserDefaults.standard.bool(forKey: Constants.UserDefaults.smartRewindEnabled.rawValue), animated: false)
    self.boostVolumeSwitch.setOn(UserDefaults.standard.bool(forKey: Constants.UserDefaults.boostVolumeEnabled.rawValue), animated: false)
    self.globalSpeedSwitch.setOn(UserDefaults.standard.bool(forKey: Constants.UserDefaults.globalSpeedEnabled.rawValue), animated: false)
    self.chapterTimeSwitch.setOn(self.viewModel.prefersChapterContext, animated: false)
    self.remainingTimeSwitch.setOn(self.viewModel.prefersRemainingTime, animated: false)

    // Retrieve initial skip values from PlayerManager
    self.rewindIntervalLabel.text = TimeParser.formatDuration(PlayerManager.rewindInterval)
    self.forwardIntervalLabel.text = TimeParser.formatDuration(PlayerManager.forwardInterval)

    bindObservers()
  }

  func bindObservers() {
    self.viewModel.$playerListPrefersBookmarks.sink { [weak self] prefersBookmarks in
      self?.playerListPreferenceLabel.text = self?.viewModel.getTitleForPlayerListPreference(prefersBookmarks)
    }
    .store(in: &disposeBag)

    self.remainingTimeSwitch.publisher(for: .valueChanged)
      .sink { [weak self] control in
        guard let switchControl = control as? UISwitch else { return }

        self?.viewModel.handlePrefersRemainingTime(switchControl.isOn)
      }
      .store(in: &disposeBag)

    self.chapterTimeSwitch.publisher(for: .valueChanged)
      .sink { [weak self] control in
        guard let switchControl = control as? UISwitch else { return }

        self?.viewModel.handlePrefersChapterContext(switchControl.isOn)
      }
      .store(in: &disposeBag)
  }

  func showPlayerListOptionAlert() {
    let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

    sheet.addAction(UIAlertAction(title: Loc.ChaptersTitle.string, style: .default) { [weak self] _ in
      self?.viewModel.handleOptionSelected(.chapters)
    })

    sheet.addAction(UIAlertAction(title: Loc.BookmarksTitle.string, style: .default) { [weak self] _ in
      self?.viewModel.handleOptionSelected(.bookmarks)
    })

    sheet.addAction(UIAlertAction(title: Loc.CancelButton.string, style: .cancel))

    self.present(sheet, animated: true)
  }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let viewController = segue.destination as? SkipDurationViewController else {
            return
        }

        if segue.identifier == "AdjustRewindIntervalSegue" {
            viewController.title = Loc.SettingsSkipRewindTitle.string
            viewController.selectedInterval = PlayerManager.rewindInterval
            viewController.didSelectInterval = { selectedInterval in
                PlayerManager.rewindInterval = selectedInterval

                self.rewindIntervalLabel.text = TimeParser.formatDuration(PlayerManager.rewindInterval)
            }
        }

        if segue.identifier == "AdjustForwardIntervalSegue" {
          viewController.title = Loc.SettingsSkipForwardTitle.string
            viewController.selectedInterval = PlayerManager.forwardInterval
            viewController.didSelectInterval = { selectedInterval in
                PlayerManager.forwardInterval = selectedInterval

                self.forwardIntervalLabel.text = TimeParser.formatDuration(PlayerManager.forwardInterval)
            }
        }
    }

    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        let header = view as? UITableViewHeaderFooterView
        header?.textLabel?.textColor = self.themeProvider.currentTheme.secondaryColor
    }

    override func tableView(_ tableView: UITableView, willDisplayFooterView view: UIView, forSection section: Int) {
        let footer = view as? UITableViewHeaderFooterView
        footer?.textLabel?.textColor = self.themeProvider.currentTheme.secondaryColor
    }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath as IndexPath, animated: true)

    if indexPath == playerListPreferencePath {
      self.showPlayerListOptionAlert()
    }
  }

  override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
    if section == SettingsSection.intervals.rawValue {
      return Loc.SettingsSkipTitle.string
    } else if section == SettingsSection.progressLabels.rawValue {
      return Loc.SettingsProgresslabelsTitle.string
    }

    return super.tableView(tableView, titleForHeaderInSection: section)
  }

  override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    guard let settingsSection = SettingsSection(rawValue: section) else {
      return super.tableView(tableView, titleForFooterInSection: section)
    }

    switch settingsSection {
    case .intervals:
      return Loc.SettingsSkipDescription.string
    case .rewind:
      return Loc.SettingsSmartrewindDescription.string
    case .volume:
      return Loc.SettingsBoostvolumeDescription.string
    case .speed:
      return Loc.SettingsGlobalspeedDescription.string
    case .progressLabels:
      return Loc.SettingsProgresslabelsDescription.string
    case .playerList:
      return Loc.SettingsPlayerinterfaceListDescription.string
    }
  }

    @objc func rewindToggleDidChange() {
        UserDefaults.standard.set(self.smartRewindSwitch.isOn, forKey: Constants.UserDefaults.smartRewindEnabled.rawValue)
    }

    @objc func boostVolumeToggleDidChange() {
      UserDefaults.standard.set(self.boostVolumeSwitch.isOn, forKey: Constants.UserDefaults.boostVolumeEnabled.rawValue)

      guard let playerManager = AppDelegate.shared?.playerManager else { return }

      playerManager.boostVolume = self.boostVolumeSwitch.isOn
    }

    @objc func globalSpeedToggleDidChange() {
        UserDefaults.standard.set(self.globalSpeedSwitch.isOn, forKey: Constants.UserDefaults.globalSpeedEnabled.rawValue)
    }
}

extension PlayerSettingsViewController: Themeable {
  func applyTheme(_ theme: SimpleTheme) {
    self.tableView.backgroundColor = theme.systemGroupedBackgroundColor
    self.tableView.separatorColor = theme.separatorColor
    self.tableView.reloadData()

    self.listImageView.tintColor = theme.secondaryColor
  }
}
