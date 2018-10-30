class IssueRecurrence < ActiveRecord::Base
  include Redmine::Utils::DateCalculation

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
  FIXED_MODES = anchor_modes.keys.select { |m| m.include?('_fixed') }
  FLEXIBLE_MODES = anchor_modes.keys.select { |m| m.include?('_flexible') }

  enum mode: {
    daily: 0,
    daily_wday: 1,
    weekly: 100,
    monthly_start_day_from_first: 200,
    monthly_due_day_from_first: 201,
    monthly_start_day_to_last: 210,
    monthly_due_day_to_last: 211,
    monthly_start_dow_from_first: 220,
    monthly_due_dow_from_first: 221,
    monthly_start_dow_to_last: 230,
    monthly_due_dow_to_last: 231,
    monthly_start_wday_from_first: 240,
    monthly_due_wday_from_first: 241,
    monthly_start_wday_to_last: 250,
    monthly_due_wday_to_last: 251,
    yearly: 300
  }
  WDAY_MODES = modes.keys.select { |m| m.include?('_wday') }
  START_MODES = modes.keys.select { |m| m.include?('_start_') }
  DUE_MODES = modes.keys.select { |m| m.include?('_due_') }
  MONTHLY_MODES = modes.keys.select { |m| m.include?('monthly_') }

  enum delay_mode: {
    day: 0,
    week: 1,
    month: 2
  }

  validates :issue, presence: true, associated: true
  validate on: :create do
    errors.add(:issue, :insufficient_privileges) unless editable?
  end
  validates :last_issue, associated: true
  validates :count, numericality: {greater_than_or_equal: 0, only_integer: true}
  validates :creation_mode, inclusion: creation_modes.keys
  validates :anchor_mode, inclusion: anchor_modes.keys
  validates :anchor_mode, inclusion: {
    in: FIXED_MODES,
    if: "delay_multiplier > 0",
    message: :delay_fixed_only
  }
  validates :anchor_mode, inclusion: {
    in: FLEXIBLE_MODES,
    if: "(issue.start_date || issue.due_date).blank?",
    message: :blank_dates_flexible_only
  }
  validates :anchor_mode, inclusion: {
    in: FLEXIBLE_MODES,
    if: "creation_mode == 'in_place'",
    message: :in_place_flexible_only
  }
  validates :mode, inclusion: modes.keys
  validates :mode, exclusion: {
    in: START_MODES,
    if: "issue.start_date.blank? && issue.due_date.present?",
    message: :start_mode_requires_date
  }
  validates :mode, exclusion: {
    in: DUE_MODES,
    if: "issue.due_date.blank? && issue.start_date.present?",
    message: :due_mode_requires_date
  }
  validates :multiplier, numericality: {greater_than: 0, only_integer: true}
  validates :delay_mode, inclusion: delay_modes.keys
  validates :delay_multiplier, numericality: {greater_than_or_equal_to: 0, only_integer: true}
  validates :include_subtasks, inclusion: [true, false]
  validates :date_limit, absence: {if: "count_limit.present?"}
  validate on: :create, if: "date_limit.present?" do
    errors.add(:date_limit, :not_in_future) unless Date.current < date_limit
  end
  validates :count_limit, absence: {if: "date_limit.present?"},
    numericality: {allow_nil: true, only_integer: true}

  after_initialize do
    if new_record?
      self.count = 0
      self.creation_mode ||= :copy_first
      self.anchor_mode ||= :first_issue_fixed
      self.mode ||= :monthly_start_day_from_first
      self.multiplier ||= 1
      self.delay_mode ||= :day
      self.delay_multiplier ||= 0
      self.include_subtasks = false if self.include_subtasks.nil?
    end
  end
  before_destroy :editable?

  def fixed?
    FIXED_MODES.include?(self.anchor_mode)
  end

  def flexible?
    FLEXIBLE_MODES.include?(self.anchor_mode)
  end

  def visible?
    self.issue.visible? &&
      User.current.allowed_to?(:view_issue_recurrences, self.issue.project)
  end

  def editable?
    self.visible? && 
      self.issue.attributes_editable?(User.current) &&
      User.current.allowed_to?(:manage_issue_recurrences, self.issue.project)
  end

  def to_s
    s = 'issues.recurrences.form'

    ref_dates = self.next_dates
    ref_description = ''
    if ref_dates.nil?
      ref_description = " #{l("#{s}.mode_descriptions.#{self.mode}")}"
    elsif MONTHLY_MODES.include?(self.mode)
      label = START_MODES.include?(self.mode) ? :start : :due
      date = ref_dates[label]
      unless date.nil?
        days_to_eom = (date.end_of_month.mday - date.mday + 1).to_i
        values = {
          days_from_bom: date.mday.ordinalize,
          days_to_eom: days_to_eom.ordinalize,
          day_of_week: date.strftime("%A"),
          dows_from_bom: ((date.mday - 1) / 7 + 1).ordinalize,
          dows_to_eom: ((days_to_eom - 1) / 7 + 1).ordinalize,
          wdays_from_bom: (working_days(date.beginning_of_month, date) + 1).ordinalize,
          wdays_to_eom: (working_days(date, date.end_of_month) + 1).ordinalize
        }
        ref_description = " #{l("#{s}.mode_modifiers.#{self.mode}", values)}"
      end
    end

    delay_info = self.delay_multiplier > 0 ?
      " #{l("#{s}.delayed_by")} <b>#{self.delay_multiplier}" \
      " #{l("#{s}.delay_intervals.#{self.delay_mode}").pluralize(self.delay_multiplier)}" \
      "</b>" : ''

    count_limit_info = self.count_limit.present? ? " #{"<b>#{self.count_limit}" \
        " #{l("#{s}.recurrence").pluralize(self.count_limit)}</b>."}" : ''

    "#{l("#{s}.creation_modes.#{self.creation_mode}")}" \
      " <b>#{l("#{s}.including_subtasks") if self.include_subtasks}</b>" \
      " #{l("#{s}.every")}" \
      " <b>#{self.multiplier}" \
      " #{l("#{s}.mode_intervals.#{self.mode}").pluralize(self.multiplier)}</b>," \
      "#{ref_description}" \
      " #{l("#{s}.based_on")}" \
      " #{l("#{s}.anchor_modes.#{self.anchor_mode}", ref_dates)}" \
      "#{delay_info}" \
      "#{"." if self.date_limit.nil? && self.count_limit.nil?}" \
      " #{l("#{s}.until") if self.date_limit.present? || self.count_limit.present?}" \
      " #{"<b>#{self.date_limit}</b>." if self.date_limit.present?}" \
      "#{count_limit_info}".html_safe
  end

  # Advance 'dates' according to recurrence mode and adjustment (+/- # of periods).
  # Return advanced 'dates' or nil if recurrence limit reached.
  def advance(adj=0, **dates)
    return nil if self.count_limit.present? && self.count >= self.count_limit

    shift = if self.anchor_mode == 'first_issue_fixed'
              self.delay(dates) if self.count + adj >= 0
              self.multiplier*(self.count + 1 + adj)
            else
              self.delay(dates) if self.count == 0
              self.multiplier
            end

    case self.mode.to_sym
    when :daily
      dates.each do |label, date|
        dates[label] = date + shift.days if date.present?
      end
    when :daily_wday
      dates.each do |label, date|
        dates[label] = add_working_days(date, shift) if date.present?
      end
    when :weekly
      dates.each do |label, date|
        dates[label] = date + shift.weeks if date.present?
      end
    when :monthly_start_day_from_first, :monthly_due_day_from_first
      label = START_MODES.include?(self.mode) ? :start : :due
      date = dates[label]
      target_date = date + shift.months
      dates = self.offset(target_date, label, dates)
    when :monthly_start_day_to_last, :monthly_due_day_to_last
      label = START_MODES.include?(self.mode) ? :start : :due
      date = dates[label]
      days_to_last = date.end_of_month - date
      target_eom = (date + shift.months).end_of_month
      target_date = target_eom - [days_to_last, target_eom.mday-1].min
      dates = self.offset(target_date, label, dates)
    when :monthly_start_dow_from_first, :monthly_due_dow_from_first
      label = START_MODES.include?(self.mode) ? :start : :due
      date = dates[label]
      source_dow = date.days_to_week_start
      target_bom = (date + shift.months).beginning_of_month
      target_bom_dow = target_bom.days_to_week_start
      week = ((date.mday - 1) / 7) + (source_dow >= target_bom_dow ? 0 : 1)
      target_bom_shift = week.weeks + (source_dow - target_bom_dow).days
      overflow = target_bom_shift > (target_bom.end_of_month.mday-1).days ? 1.week : 0
      target_date = target_bom + target_bom_shift - overflow
      dates = self.offset(target_date, label, dates)
    when :monthly_start_dow_to_last, :monthly_due_dow_to_last
      label = START_MODES.include?(self.mode) ? :start : :due
      date = dates[label]
      source_dow = date.days_to_week_start
      target_eom = (date + shift.months).end_of_month
      target_eom_dow = target_eom.days_to_week_start
      week = ((date.end_of_month - date).to_i / 7) + (source_dow > target_eom_dow ? 1 : 0)
      target_eom_shift = week.weeks + (target_eom_dow - source_dow).days
      overflow = target_eom_shift > (target_eom.mday-1).days ? 1.week : 0
      target_date = target_eom - target_eom_shift + overflow
      dates = self.offset(target_date, label, dates)
    when :monthly_start_wday_from_first, :monthly_due_wday_from_first
      label = START_MODES.include?(self.mode) ? :start : :due
      date = dates[label]
      source_wdays = date.beginning_of_month.step(date.end_of_month).reject do |d|
        non_working_week_days.include?(d.cwday)
      end
      wday = source_wdays.bsearch_index { |d| d >= date } || source_wdays.length-1
      target_date = date + shift.months
      target_wdays = target_date.beginning_of_month
        .step(target_date.end_of_month).reject do |d|
        non_working_week_days.include?(d.cwday)
      end
      target_wdate = target_wdays[wday] || target_wdays.last
      dates = self.offset(target_wdate, label, dates)
    when :monthly_start_wday_to_last, :monthly_due_wday_to_last
      label = START_MODES.include?(self.mode) ? :start : :due
      date = dates[label]
      source_wdays = date.beginning_of_month.step(date.end_of_month).reject do |d|
        non_working_week_days.include?(d.cwday)
      end
      wday = source_wdays.reverse.bsearch_index { |d| d <= date } || 0
      target_date = date + shift.months
      target_wdays = target_date.beginning_of_month
        .step(target_date.end_of_month).reject do |d|
        non_working_week_days.include?(d.cwday)
      end
      target_wdate = target_wdays.reverse[wday] || target_wdays.first
      dates = self.offset(target_wdate, label, dates)
    when :yearly
      dates.each do |label, date|
        dates[label] = date + shift.years if date.present?
      end
    end

    return nil if self.date_limit.present? && (dates[:start] || dates[:due]) > self.date_limit

    dates
  end

  # Offset 'dates' so date with 'label' is equal 'target'.
  # Return offset 'dates' or nil if 'dates' does not include 'label'.
  def offset(target_date, target_label=:due, dates)
    nil if dates[target_label].nil?
    dates.each do |label, date|
      next if (label == target_label) || date.nil?
      if WDAY_MODES.include?(self.mode)
        if date >= dates[target_label]
          timespan = working_days(dates[target_label], date)
          dates[label] = add_working_days(target_date, timespan)
        else
          timespan = working_days(date, dates[target_label])
          dates[label] = subtract_working_days(target_date, timespan)
        end
      else
        timespan = date - dates[target_label]
        dates[label] = target_date + timespan
      end
    end
    dates[target_label] = target_date
    dates
  end

  # Based on Redmine's add_working_days.
  def subtract_working_days(date, working_days)
    if working_days > 0
      weeks = working_days / (7 - non_working_week_days.size)
      result = weeks * 7
      days_left = working_days - weeks * (7 - non_working_week_days.size)
      cwday = date.cwday
      while days_left > 0
        cwday -= 1
        unless non_working_week_days.include?(((cwday - 1) % 7) + 1)
          days_left -= 1
        end
        result += 1
      end
      next_working_date(date - result)
    else
      date
    end
  end

  # Delay 'dates' in-place according to delay mode.
  def delay(dates)
    dates if self.delay_multiplier == 0
    dates.each do |label, date|
      next if date.nil?
      dates[label] +=
        case self.delay_mode.to_sym
        when :day
          self.delay_multiplier.days
        when :week
          self.delay_multiplier.weeks
        when :month
          self.delay_multiplier.months
        end
    end
  end

  # Create next recurrence issue. Assumes that 'advance' will return valid date
  # (so advance must be called first and checked for return value).
  def create(dates)
    ref_issue = self.last_issue if self.creation_mode == 'copy_last'
    ref_issue ||= self.issue
    prev_dates = {start: ref_issue.start_date, due: ref_issue.due_date}

    prev_user = User.current
    author_id = Setting.plugin_issue_recurring['author_id'].to_i
    User.current = User.find_by(id: author_id) || ref_issue.author

    IssueRecurrence.transaction do
      if Setting.plugin_issue_recurring['add_journal']
        # Setting journal on self.issue won't record copy if :copy_last is used
        ref_issue.init_journal(User.current)
      end

      new_issue = (self.creation_mode == 'in_place') ? ref_issue :
        ref_issue.copy(nil, subtasks: self.include_subtasks)

      new_issue.start_date = dates[:start]
      new_issue.due_date = dates[:due]
      new_issue.done_ratio = 0
      new_issue.status = new_issue.tracker.default_status
      new_issue.recurrence_of = self.issue
      new_issue.default_reassign unless Setting.plugin_issue_recurring['keep_assignee']

      new_issue.save!

      if self.include_subtasks
        target_label = MONTHLY_MODES.include?(self.mode) && DUE_MODES.include?(self.mode) ?
          :due : :start
        new_issue.children.each do |child|
          child_dates = self.offset(dates[target_label], :parent, 
            {parent: prev_dates[target_label], start: child.start_date, due: child.due_date})
          child.start_date = child_dates[:start] 
          child.due_date = child_dates[:due]
          child.done_ratio = 0
          child.status = child.tracker.default_status
          child.recurrence_of = self.issue
          child.default_reassign unless Setting.plugin_issue_recurring['keep_assignee']
          child.save!
        end
      end

      self.last_issue = new_issue
      self.count += 1
      self.save!
    end

    User.current = prev_user
  end

  # Return reference dates for next recrrence or nil if no suitable dates found.
  def reference_dates
    ref_issue = nil
    ref_dates = nil
    case self.anchor_mode.to_sym
    when :first_issue_fixed, :last_issue_fixed
      ref_issue = self.last_issue if self.anchor_mode == 'last_issue_fixed'
      ref_issue ||= self.issue
      ref_dates = {start: ref_issue.start_date, due: ref_issue.due_date}
      if (ref_dates[:start] || ref_dates[:due]).nil?
        log("issue ##{ref_issue.id} start and due dates are blank") 
        return nil
      end
    when :last_issue_flexible, :last_issue_flexible_on_delay
      ref_issue = self.last_issue || self.issue
      if ref_issue.closed?
        closed_date = ref_issue.closed_on.to_date
        ref_dates = {start: ref_issue.start_date, due: ref_issue.due_date}
        if (ref_dates[:start] || ref_dates[:due]).present?
          unless (self.anchor_mode == 'last_issue_flexible_on_delay') &&
              ((ref_dates[:due] || ref_dates[:start]) >= closed_date)
            ref_label = ref_issue.due_date.present? ? :due : :start
            offset_dates = self.offset(closed_date, ref_label, ref_dates) 
            return nil if offset_dates.nil?
            ref_dates = offset_dates
          end
        else
          if START_MODES.include?(self.mode)
            ref_dates[:start] = closed_date
          else
            ref_dates[:due] = closed_date
          end
        end
      end
    end

    if ref_dates && ref_dates[:start].nil? && START_MODES.include?(self.mode)
      log("issue ##{ref_issue.id} start date is blank")
      return nil
    end
    if ref_dates && ref_dates[:due].nil? && DUE_MODES.include?(self.mode)
      log("issue ##{ref_issue.id} due date is blank")
      return nil
    end

    ref_dates
  end

  # Return predicted next recurrence dates or nil.
  def next_dates
    ref_dates = self.reference_dates
    return nil if ref_dates.nil?
    self.advance(ref_dates)
  end

  # Estimate future recurrence dates.
  # Returns first 3 dates and last date if recurrence limited.
  #def estimate_schedule
  #  schedule = []
  #  saved_count = self.count
  #
  #  begin
  #    dates = self.next_dates
  #    schedule << dates if dates.present?
  #    self.count += 1
  #  end while dates.present? &&
  #    ((self.date_limit || self.count_limit).present? || (self.count - saved_count < 3))
  #
  #  self.count = saved_count
  #  schedule
  #end

  def renew
    case self.anchor_mode.to_sym
    when :first_issue_fixed
      ref_dates = self.reference_dates
      return if ref_dates.nil?
      prev_dates = self.advance(-1, ref_dates)
      while (prev_dates[:start] || prev_dates[:due]) < Date.tomorrow
        new_dates = self.advance(ref_dates)
        break if new_dates.nil?
        self.create(new_dates)
        prev_dates = new_dates
      end
    when :last_issue_fixed
      ref_dates = self.reference_dates
      return if ref_dates.nil?
      while (ref_dates[:start] || ref_dates[:due]) < Date.tomorrow
        new_dates = self.advance(ref_dates)
        break if new_dates.nil?
        self.create(new_dates)
        ref_dates = new_dates
      end
    when :last_issue_flexible, :last_issue_flexible_on_delay
      ref_dates = self.reference_dates
      return if ref_dates.nil?
      new_dates = self.advance(ref_dates)
      return if new_dates.nil?
      self.create(new_dates)
    end
  end

  def self.renew_all
    @@log_problems = true
    IssueRecurrence.all.map(&:renew)
    @@log_problems = false
  end

  private

  def log(msg)
    return unless @@log_problems

    prev_user = User.current
    author_id = Setting.plugin_issue_recurring['author_id'].to_i
    User.current = User.find_by(id: author_id) || self.issue.author
    self.issue.init_journal(User.current, l(:journal_warning, {msg: msg}))
    self.issue.save
    User.current = prev_user
  end

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
