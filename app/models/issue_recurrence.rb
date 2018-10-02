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
  validates :anchor_mode, inclusion: {in: anchor_modes.keys}
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

  # Advance 'dates' (hash) evenly according to recurrence mode.
  # Return:
  #  - earliest 'dates' after 'after' or
  #  - next recurrence of 'dates' if 'after' is nil.
  # 'after' has to be later than earliest 'dates' member (if not nil)
  def advance(dates, after=nil)
    case self.mode
    when :daily
      base = dates.values.min
      periods = after.nil? ? 1 : ((after-base+1)/self.mode_multiplier).ceil
      dates.keys.map do |k|
        dates[k] += self.mode_multiplier*periods.days
      end
    end
  end

  def copy
    self.count += 1
  end

  # Renew has to take into account:
  # - addition/removal/modification of issue dates after IssueRecurrence is created
  def renew
    #reference_issue = case self.creation_mode
    #                  when :copy_first, :in_place
    #                    self.issue
    #                  when :copy_last
    #                    self.last_issue
    #                  end

    case self.anchor_mode
    when :first_issue_fixed
      case self.creation_mode
      when :copy_first
        ref_date = self.issue.start_date || self.issue.due_date
        while true
          new_date = self.advance(ref_date, self.last_date)
          break if new_date > Date.today
          self.copy(self.issue, new_date)
          self.last_date = new_date
        end
      when :copy_last
        ref_date = self.last_date || self.issue.start_date || self.issue.due_date
        while true
          new_date = self.advance(ref_date)
          break if new_date > Date.today
          self.copy(self.issue, new_date)
          ref_date = new_date
        end
        self.last_date = ref_date
        self.last_issue
      when :in_place
        #NOT SUPPORTED
      end
    end

    self.save!
  end

  def self.renew_all
    IssueRecurrence.all.each do |r|
      r.renew
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
    end
  end
end
