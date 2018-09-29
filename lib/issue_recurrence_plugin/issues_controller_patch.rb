module IssueRecurrencePlugin
  module IssuesControllerPatch
    IssuesController.class_eval do
      before_filter :prepare_recurrences, :only => [:show]

      private
      def prepare_recurrences
        @recurrences = @issue.recurrences.select {|r| r.visible?}
        @recurrence = IssueRecurrence.new
      end
    end
  end
end

