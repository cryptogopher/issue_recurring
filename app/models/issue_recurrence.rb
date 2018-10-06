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
    last_issue_flexible: 2,
    last_issue_flexible_on_delay: 3
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
  validates :count, numericality: {greater_than_or_equal: 0, only_integer: true}
  validates :creation_mode, inclusion: {in: creation_modes.keys}
  validates :anchor_mode,
    inclusion: {
      in: anchor_modes.keys,
      if: "(issue.start_date || issue.due_date).present?"
    }
  validates :anchor_mode,
    inclusion: {
    in: [:last_issue_flexible, :last_issue_flexible_on_delay],
      if: "(issue.start_date || issue.due_date).blank? || (creation_mode == :in_place)",
      message: "has to be 'last_issue_flexible{_on_delay}'" \
        " if issue has no start/due date set or creation mode is 'in_place'"
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

  # Advance 'dates' according to recurrence mode and adjustment (+/- # of periods).
  # Return advanced 'dates' or nil if recurrence limit reached.
  def advance(adj=0, **dates)
    shift = self.anchor_mode.to_sym == :first_issue_fixed ?
      self.multiplier*(self.count + 1 + adj) : self.multiplier*(1 + adj)

    dates.each do |label, date|
      next if date.nil?
      dates[label] =
        case self.mode.to_sym
        when :daily
          date + shift.days
        when :weekly
          date + shift.weeks
        when :monthly_day_from_first
          date + shift.months
        when :monthly_day_to_last
          days_to_last = date.end_of_month - date
          (date + shift.months).end_of_month - days_to_last
        when :monthly_dow_from_first
          source_dow = date.days_to_week_start
          target_bom = (date + shift.months).beginning_of_month
          target_bom_dow = target_bom.days_to_week_start
          week = ((date.mday - 1) / 7) + ((source_dow >= target_bom_dow) ? 0 : 1)
          target_bom + week.weeks + source_dow - target_bom_dow
        when :monthly_dow_to_last
          source_dow = date.days_to_week_start
          target_eom = (date + shift.months).end_of_month
          target_eom_dow = target_eom.days_to_week_start
          week = ((date.end_of_month - date).to_i / 7) +
            ((source_dow > target_eom_dow) ? 1 : 0)
          target_eom - week.weeks + source_dow - target_eom_dow
        when :monthly_wday_from_first
          source_wdays = date.beginning_of_month.step(date.end_of_month).select do |d|
            (1..5).include?(d.wday)
          end
          wday = source_wdays.bsearch_index { |d| d >= date } || source_wdays.length-1
          target_date = date + shift.months
          target_wdays = target_date.beginning_of_month
            .step(target_date.end_of_month).select do |d|
            (1..5).include?(d.wday)
          end
          target_wdays[wday] || target_wdays.last
        when :monthly_wday_to_last
          source_wdays = date.beginning_of_month.step(date.end_of_month).select do |d|
            (1..5).include?(d.wday)
          end
          wday = source_wdays.reverse.bsearch_index { |d| d <= date } || 0
          target_date = date + shift.months
          target_wdays = target_date.beginning_of_month
            .step(target_date.end_of_month).select do |d|
            (1..5).include?(d.wday)
          end
          target_wdays.reverse[wday] || target_wdays.first
        when :yearly
          date + shift.years unless date.nil?
        end
    end

    dates
  end

  # Offset 'dates' so date with 'label' is equal (or closest to) 'target'.
  # Return offset 'dates' or nil if 'dates' does not include 'label'.
  def offset(target_date, target_label=:due, **dates)
    nil unless dates.has_key?(target_label) && dates[target_label].present?
    dates.each do |label, date|
      next if date.nil?
      dates[label] =
        if label == target_label
          target_date
        else
          target_label == :due ?
            target_date-(dates[:due]-date) : target_date+(date-dates[:start])
        end
    end
  end

  def create(dates, as_user)
    ref_issue = (self.creation_mode.to_sym == :copy_last) ? self.last_issue : self.issue

    prev_user = User.current
    User.current = as_user || ref_issue.author
    ref_issue.init_journal(User.current, l(:journal_recurrence))

    new_issue = (self.creation_mode.to_sym == :in_place) ? self.issue :
      ref_issue.copy(nil, subtasks: self.include_children)
    new_issue.save!

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
    case self.anchor_mode.to_sym
    when :first_issue_fixed
      ref_dates = {start: self.issue.start_date, due: self.issue.due_date}
      if logger && ref_dates.values.compact.empty?
        logger.warn("Issue ##{self.issue.id} has no dates to allow for recurrence renewal.") 
        return
      end
      prev_dates = self.advance(-1, ref_dates)
      while (prev_dates[:start] || prev_dates[:end]) < Date.tomorrow
        new_dates = self.advance(ref_dates)
        break if new_dates.nil?
        self.create(new_dates, as_user)
        prev_dates = new_dates
      end
    when :last_issue_fixed
      ref_issue = self.last_issue || self.issue
      ref_dates = {start: ref_issue.start_date, due: ref_issue.due_date}
      if logger && ref_dates.values.compact.empty?
        logger.warn("Issue ##{ref_issue.id} has no dates to allow for recurrence renewal.") 
        return
      end
      while (ref_dates[:start] || ref_dates[:end]) < Date.tomorrow
        new_dates = self.advance(ref_dates)
        break if new_dates.nil?
        self.create(new_dates, as_user)
        ref_dates = new_dates
      end
    when :last_issue_flexible, :last_issue_flexible_on_delay
      ref_issue = self.last_issue || self.issue
      ref_dates = {start: ref_issue.start_date, due: ref_issue.due_date}
      if ref_issue.closed?
        closed_date = ref_issue.closed_on.to_date
        if ref_dates.values.compact.present?
          unless (self.anchor_mode.to_sym == :last_issue_flexible_on_delay) &&
              ((ref_dates[:due] || ref_dates[:start]) >= closed_date)
            ref_label = ref_issue.due_date.present? ? :due : :start
            offset_dates = self.offset(closed_date, ref_label, ref_dates) 
            return if offset_dates.nil?
            ref_dates = offset_dates
          end
        else
          ref_dates[:due] = closed_date
        end
        new_dates = self.advance(ref_dates)
        return if new_dates.nil?
        self.create(new_dates, as_user)
      end
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
      self.count = 0
      self.creation_mode ||= :copy_first
      self.anchor_mode ||= :first_issue_fixed
      self.mode ||= :monthly_day_from_first
      self.multiplier ||= 1
      self.include_children ||= true
    end
  end

  private

  class Date < ::Date
    def self.today
      # Due to its nature, Date.today may sometimes be equal to Date.yesterday/tomorrow.
      # https://rails.lighthouseapp.com/projects/8994-ruby-on-rails/tickets
      # /6410-dateyesterday-datetoday
      # For this reason WE SHOULD NOT USE Date.today anywhere in the code and use
      # Date.current instead.
      raise "Date.today should not be called!"
    end
  end
end
