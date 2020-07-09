class ConvertAuthorIdSettingToAuthorLogin <
  (Rails::VERSION::MAJOR < 5 ? ActiveRecord::Migration : ActiveRecord::Migration[4.2])

  def up
    settings = Setting.plugin_issue_recurring
    settings[:author_login] = User.find_by(id: settings.delete('author_id')).try(:login)
    Setting.plugin_issue_recurring = settings
  end

  def down
    settings = Setting.plugin_issue_recurring
    settings['author_id'] = User.find_by(login: settings.delete(:author_login)).try(:id) || 0
    Setting.plugin_issue_recurring = settings
  end
end

