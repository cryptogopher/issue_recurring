class IssueRecurrence < ActiveRecord::Base
  belongs_to :issue
  belongs_to :last_issue, class_name: 'Issue'

  enum creation_mode: {
    copy_first: 0,
    copy_last: 1,
    in_place: 2
  }

  enum anchor_mode: {
    first_issue_fixed: 0,
    last_issue_fixed: 1,
    last_issue_flexible: 2
  }

  enum mode: {
    daily: 0,
    weekly: 1,
    monthly_day_from_first: 2,
    monthly_day_to_last: 3,
    monthly_dow_from_first: 4,
    monthly_dow_to_last: 5,
    monthly_wday_from_first: 6,
    monthly_wday_to_last: 7,
    yearly: 8
  }

  validates :issue, presence: true, associated: true
  validates :last_issue, associated: true
  validates :count, numericality: {greater_than: 0, only_integer: true}
  validates :creation_mode, inclusion: {in: creation_modes.keys}
  validates :anchor_mode,
    inclusion: {
      in: anchor_modes.keys,
      if: "(issue.start_date || issue.due_date).present?"
    },
    inclusion: {
      in: [:last_issue_flexible],
      if: "(issue.start_date || issue.due_date).blank? || (anchor_mode == :in_place)"
    }
  validates :mode, inclusion: {in: modes.keys}
  validates :multiplier, numericality: {greater_than: 0, only_integer: true}
  validates :date_limit, absence: {if: "count_limit.present?"}
  validates :count_limit, absence: {if: "date_limit.present?"},
    numericality: {allow_nil: true, only_integer: true}

  after_initialize :set_defaults

  def visible?
    self.issue.visible?
  end

  def deletable?
    self.visible? && User.current.allowed_to?(:manage_issue_recurrences, self.issue.project)
  end

  def to_s
  end

  # Advance 'dates' (hash) according to recurrence mode.
  # Return: advanced dates (hash) or nil if recurrence limit reached.
  def advance(**dates)
    case self.mode
    when :daily
      dates.keys.map do |k|
        dates[k] += (self.multiplier*(self.count+1)).days unless dates[k].nil?
      end
    end
  end

  def create(dates, as_user)
    ref_issue = (self.creation_mode == :copy_last) ? self.last_issue : self.issue

    prev_user = User.current
    User.current = as_user || ref_issue.author
    ref_issue.init_journal(User.current, t(:journal_recurrence))

    new_issue = (self.creation_mode == :in_place) ? self.issue :
      ref_issue.copy(nil, subtasks: self.include_children)

    if self.include_children
      new_issue.reload.descendants.each do |child|
        child_dates = self.advance(start: child.start_date, due: child.due_date)
        child.start_date = child_dates[:start] 
        child.due_date = child_dates[:due]
        child.done_ratio = 0
        child.status = child.tracker.default_status
        child.save!
      end
      new_issue.reload
    end

    new_issue.start_date = dates[:start]
    new_issue.due_date = dates[:due]
    new_issue.done_ratio = 0
    new_issue.status = new_issue.tracker.default_status
    new_issue.save!

    self.last_issue = new_issue
    self.count += 1
    self.save!

    User.current = prev_user
  end

  def renew(as_user)
    case self.anchor_mode
    when :first_issue_fixed
      dates = {start: self.issue.start_date, due: self.issue.due_date}
      while true
        break if (dates[:start] || dates[:end]) > Date.today
        new_dates = self.advance(dates)
        break if new_dates.nil?
        self.create(new_dates, as_user)
        dates = new_dates
      end
    when :last_issue_fixed
    when :last_issue_flexible
    end
  end

  def self.renew_all(**options)
    as_user = options[:as] && User.find_by(name: options[:as])
    IssueRecurrence.all.each do |r|
      r.renew(as_user)
    end
  end

  protected

  def set_defaults
    if new_record?
      self.count ||= 0
      self.creation_mode ||= :copy_first
      self.anchor_mode ||= :first_issue_fixed
      self.mode ||= :monthly_day_from_first
      self.multiplier ||= 1
      self.include_children ||= true
    end
  end
end
