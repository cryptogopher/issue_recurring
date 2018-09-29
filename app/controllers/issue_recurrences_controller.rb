class IssueRecurrencesController < ApplicationController
  before_filter :find_issue, only: [:create]
  before_filter :find_issue_recurrence, only: [:destroy]
  before_filter :authorize, only: [:create, :destroy]

  def create
    @recurrence = IssueRecurrence.new(recurrence_params)
    @recurrence.issue = @issue
    @recurrence.save
    @recurrences = @issue.reload.recurrences.select {|r| r.visible?}
  end

  def destroy
    @recurrence.destroy
  end

  private

  def recurrence_params
    params.require(:recurrence).permit(
      :is_fixed_schedule,
      :start_date,
      :due_date,
      :creation_mode,
      :mode,
      :mode_multiplier,
      :date_limit,
      :count_limit
    )
  end

  # :find_* methods are called before :authorize,
  # @project is required for :authorize to succeed
  def find_issue
    @issue = Issue.find(params[:issue_id])
    raise Unauthorized unless @issue.visible?
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_recurrence
    @recurrence = IssueRecurrence.find(params[:id])
    raise Unauthorized unless @recurrence.deletable?
    @issue = @recurrence.issue
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
