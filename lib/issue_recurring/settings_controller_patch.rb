module IssueRecurring
  module SettingsControllerPatch
    SettingsController.class_eval do
      before_action :save_issue_recurring_settings, only: [:plugin],
        if: -> { params[:id] == 'issue_recurring' && request.post? }

      def save_issue_recurring_settings
        settings = {}

        author_id = params[:settings][:author_id].to_i
        settings[:author_id] = User.exists?(author_id) ? author_id : 0

        settings[:keep_assignee] = params[:settings][:keep_assignee] == 'true' ? true : false

        journal_mode = params[:settings][:journal_mode].to_sym
        settings[:journal_mode] = IssueRecurrence::JOURNAL_MODES.include?(journal_mode) ?
          journal_mode : IssueRecurrence::JOURNAL_MODES.first

        params[:settings] = settings
      end
    end
  end
end
