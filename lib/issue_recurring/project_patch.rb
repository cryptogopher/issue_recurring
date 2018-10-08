module IssueRecurring
  module ProjectPatch
    Project.class_eval do
      has_many :recurrences, class_name: 'IssueRecurrence', dependent: :destroy,
        through: :issues
    end
  end
end

