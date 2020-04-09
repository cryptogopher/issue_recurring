module IssueRecurring
  module SettingsHelperPatch
    SettingsHelper.class_eval do
      def authors(default)
        options = options_for_select({t('.author_unchanged') => 0}, default)
        options << options_from_collection_for_select(User.active, :id, :name, default)
      end

      def journal_mode_options(default)
        modes = IssueRecurrence::JOURNAL_MODES
        options_for_select(modes.map { |jm| [t(".journal_modes.#{jm}"), jm] }, default)
      end
    end
  end
end

