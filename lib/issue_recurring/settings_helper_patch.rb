module IssueRecurring
  module SettingsHelperPatch
    SettingsHelper.class_eval do
      def authors(default_login)
        default_id = User.find_by(login: default_login).try(:id) || 0
        options = options_for_select({t('.author_unchanged') => 0}, default_id)
        users = User.active + [User.anonymous]
        options << options_from_collection_for_select(users, :id, :name, default_id)
      end

      def journal_mode_options(default)
        modes = IssueRecurrence::JOURNAL_MODES
        options_for_select(modes.map { |jm| [t(".journal_modes.#{jm}"), jm] }, default)
      end

      def ahead_mode_options(default)
        modes = IssueRecurrence::AHEAD_MODES
        options_for_select(
          modes.map { |am| [t("issues.recurrences.form.delay_modes.#{am}"), am] }, default
        )
      end
    end
  end
end

