class IssueRecurrencesController < ApplicationController
  include LoadIssueRecurrences

  before_action :find_project, only: [:index]
  before_action :find_issue, only: [:new, :create]
  before_action :find_recurrence, only: [:edit, :update, :destroy]
  before_action :authorize

  helper :issues

  def index
    @recurrences = @project.recurrences.select {|r| r.visible?}
    @next_dates = IssueRecurrence.recurrences_dates(@recurrences)
    @predicted_dates = IssueRecurrence.recurrences_dates(@recurrences, true)
  end

  def new
    @recurrence = IssueRecurrence.new(anchor_to_start:
      @issue.start_date.present? && @issue.due_date.blank?)
  end

  def create
    @recurrence = IssueRecurrence.new(recurrence_params)
    @recurrence.issue = @issue
    @recurrence.save
    raise Unauthorized if @recurrence.errors.added?(:issue, :insufficient_privileges)
    load_issue_recurrences(reload: true)
    flash.now[:notice] = t('.success')
  end

  def edit
    render :new
  end

  def update
    @recurrence.update(recurrence_params)
    raise Unauthorized if @recurrence.errors.added?(:issue, :insufficient_privileges)
    load_issue_recurrences(reload: true)
    flash.now[:notice] = t('.success')
    render :create
  end

  def destroy
    raise Unauthorized unless @recurrence.destroy
    load_issue_recurrences(reload: true)
    flash.now[:notice] = t('.success')
  end

  private

  def recurrence_params
    # In order of appearance on the form
    params.require(:recurrence).permit(
      :creation_mode,
      :include_subtasks,
      :multiplier,
      :mode,
      :anchor_to_start,
      :anchor_mode,
      :anchor_date,
      :delay_multiplier,
      :delay_mode,
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
