module IssueRecurring
  module SettingsControllerPatch
    SettingsController.class_eval do
      before_action :save_issue_recurring_settings, only: [:plugin],
        if: -> { params[:id] == 'issue_recurring' && request.post? }

      def save_issue_recurring_settings
        settings = {}

        # * Author is saved as (unique) :login to allow for better error reporting once
        # author is missing
        # * Author is retrieved from form by User.id. Cannot retrieve by :login, as
        # Anonymous.login == '' and we need empty value for 'author unchanged'
        # * User with :id == 0 (= author unchanged) doesn't exist and is mapped to nil login
        settings[:author_login] = User.find_by(id: params[:settings][:author_id].to_i)
          .try(:login)

        settings[:keep_assignee] = params[:settings][:keep_assignee] == 'true' ? true : false

        journal_mode = params[:settings][:journal_mode].to_sym
        settings[:journal_mode] = IssueRecurrence::JOURNAL_MODES.include?(journal_mode) ?
          journal_mode : IssueRecurrence::JOURNAL_MODES.first

        settings[:copy_recurrences] =
          params[:settings][:copy_recurrences] == 'true' ? true : false

        settings[:ahead_multiplier] = params[:settings][:ahead_multiplier].to_i.abs
        ahead_mode = params[:settings][:ahead_mode].to_sym
        settings[:ahead_mode] = IssueRecurrence::AHEAD_MODES.include?(ahead_mode) ?
          ahead_mode : IssueRecurrence::AHEAD_MODES.first

        params[:settings] = settings
      end
    end
  end
end
