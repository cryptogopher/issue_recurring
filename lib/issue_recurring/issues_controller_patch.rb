module IssueRecurring
  module IssuesControllerPatch
    IssuesController.class_eval do
      before_filter :prepare_recurrences, :only => [:show]

      private

      def prepare_recurrences
        @recurrences = @issue.recurrences.select {|r| r.visible?}
        @recurrence = IssueRecurrence.new
        @recurrence_copies = @issue.recurrence_copies
      end
    end
  end
end

