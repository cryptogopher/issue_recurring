class AddRenewAheadSettingsDefaults <
  (Rails::VERSION::MAJOR < 5 ? ActiveRecord::Migration : ActiveRecord::Migration[4.2])

  def up
    settings = Setting.plugin_issue_recurring
    return if settings == Setting.available_settings['plugin_issue_recurring']['default']
    settings[:ahead_multiplier] = 0
    settings[:ahead_mode] = :days
    Setting.plugin_issue_recurring = settings
  end

  def down
    settings = Setting.plugin_issue_recurring
    return if settings == Setting.available_settings['plugin_issue_recurring']['default']
    settings.delete(:ahead_multiplier)
    settings.delete(:ahead_mode)
    Setting.plugin_issue_recurring = settings
  end
end

