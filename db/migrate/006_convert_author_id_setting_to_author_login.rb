class ConvertAuthorIdSettingToAuthorLogin < ActiveRecord::Migration[4.2]
  def up
    settings = Setting.plugin_issue_recurring
    return if settings == Setting.available_settings['plugin_issue_recurring']['default']
    settings[:author_login] = User.find_by(id: settings.delete('author_id')).try(:login)
    Setting.plugin_issue_recurring = settings
  end

  def down
    settings = Setting.plugin_issue_recurring
    return if settings == Setting.available_settings['plugin_issue_recurring']['default']
    settings['author_id'] = User.find_by(login: settings.delete(:author_login)).try(:id) || 0
    Setting.plugin_issue_recurring = settings
  end
end

