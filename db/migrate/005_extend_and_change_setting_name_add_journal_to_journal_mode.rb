class ExtendAndChangeSettingNameAddJournalToJournalMode < ActiveRecord::Migration[4.2]
  def up
    settings = Setting.plugin_issue_recurring
    return if settings == Setting.available_settings['plugin_issue_recurring']['default']
    settings[:author_id] = settings.delete('author_id').to_i
    settings[:keep_assignee] = settings.delete('keep_assignee') == 'true'
    settings[:journal_mode] = settings.delete('add_journal') == 'true' ? :always : :never
    Setting.plugin_issue_recurring = settings
  end

  def down
    settings = Setting.plugin_issue_recurring
    return if settings == Setting.available_settings['plugin_issue_recurring']['default']
    settings['author_id'] = settings.delete(:author_id).to_s
    settings['keep_assignee'] = 'true' if settings.delete(:keep_assignee)
    settings['add_journal'] = 'true' if [:always, :inplace]
      .include?(settings.delete(:journal_mode))
    Setting.plugin_issue_recurring = settings
  end
end

