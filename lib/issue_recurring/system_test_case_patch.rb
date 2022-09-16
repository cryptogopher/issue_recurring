module IssueRecurring
  module SystemTestCasePatch
    # NOTE: this patch is required for Rails > 6 to avoid browser preloading,
    # which causes errors if plugin uses different browser for testing than
    # Redmine
    def driven_by(*args, **kwargs)
      kwargs[:using] = :headless_firefox
      super
    end
  end
end
