class IssueRecurrencesController < ApplicationController
  before_filter :find_project, only: [:index]
  before_filter :find_issue, only: [:create]
  before_filter :find_recurrence, only: [:destroy]
  before_filter :authorize

  def index
  end

  def create
    @recurrence = IssueRecurrence.new(recurrence_params)
    @recurrence.issue = @issue
    @recurrence.save
    raise Unauthorized if @recurrence.errors.messages.has_key?(:issue)
    @recurrences = @issue.reload.recurrences.select {|r| r.visible?}
  end

  def destroy
    @recurrence.destroy
    raise Unauthorized if @recurrence.errors.messages.has_key?(:issue)
  end

  private

  def recurrence_params
    params.require(:recurrence).permit(
      :creation_mode,
      :include_subtasks,
      :anchor_mode,
      :mode,
      :multiplier,
      :date_limit,
      :count_limit
    )
  end

  # :find_* methods are called before :authorize,
  # @project is required for :authorize to succeed
  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_issue
    @issue = Issue.find(params[:issue_id])
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_recurrence
    @recurrence = IssueRecurrence.find(params[:id])
    @issue = @recurrence.issue
    @project = @issue.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
