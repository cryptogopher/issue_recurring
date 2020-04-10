module IssueRecurring
  module SettingPatch
    # NOTE: this patch is required for Rails 4 only to assure that plugin
    # settings are returned as HashWithIndifferentAccess - remove afterwards.
    # There is difference between Rails 4 and 5 in how settings are returned due
    # to different implementation of params (ActionController::Parameters) from
    # which settings are directly saved and then restored.
    def plugin_issue_recurring
      super.with_indifferent_access
    end
  end
end
