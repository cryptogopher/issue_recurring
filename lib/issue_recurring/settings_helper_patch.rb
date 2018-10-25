module IssueRecurring
  module SettingsHelperPatch
    SettingsHelper.class_eval do
      def authors(default)
        unchanged = options_for_select(
          {t('settings.issue_recurrences.author_unchanged') => 0}, default
        )
        unchanged << options_from_collection_for_select(User.all, :id, :name, default)
      end
    end
  end
end

