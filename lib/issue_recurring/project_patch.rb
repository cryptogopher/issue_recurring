module IssueRecurring
  module ProjectPatch
    Project.class_eval do
      has_many :issue_recurrences, dependent: :destroy, through: :issues
    end
  end
end

