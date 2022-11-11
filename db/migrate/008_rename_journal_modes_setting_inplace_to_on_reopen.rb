class RenameJournalModesSettingInplaceToOnReopen < ActiveRecord::Migration[4.2]
  def up
    settings = Setting.plugin_issue_recurring
    return if settings == Setting.available_settings['plugin_issue_recurring']['default']
    settings[:journal_mode] = :on_reopen if settings[:journal_mode] == :in_place
    Setting.plugin_issue_recurring = settings
  end

  def down
    settings = Setting.plugin_issue_recurring
    return if settings == Setting.available_settings['plugin_issue_recurring']['default']
    settings[:journal_mode] = :in_place if settings[:journal_mode] == :on_reopen
    Setting.plugin_issue_recurring = settings
  end
end

