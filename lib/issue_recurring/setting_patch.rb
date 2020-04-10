module IssueRecurring
  module SettingPatch
    def plugin_issue_recurring
      super.with_indifferent_access
    end
  end
end
