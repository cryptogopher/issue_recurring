class IssueRecurrence < ActiveRecord::Base
  include Redmine::Utils::DateCalculation

  belongs_to :issue
  belongs_to :last_issue, class_name: 'Issue'

  @@log_problems = false

  enum creation_mode: {
    copy_first: 0,
    copy_last: 1,
    in_place: 2
  }

  enum anchor_mode: {
    first_issue_fixed: 0,
    last_issue_fixed: 1,
    last_issue_flexible: 2,
    last_issue_flexible_on_delay: 3,
    last_issue_fixed_after_close: 4,
    date_fixed_after_close: 5,
  }
  FLEXIBLE_ANCHORS = anchor_modes.keys.select { |m| m.include?('_flexible') }

  enum mode: {
    daily: 0,
    daily_wday: 1,
    weekly: 100,
    monthly_day_from_first: 202,
    monthly_day_to_last: 212,
    monthly_dow_from_first: 222,
    monthly_dow_to_last: 232,
    monthly_wday_from_first: 242,
    monthly_wday_to_last: 252,
    yearly: 300
  }
  WDAY_MODES = modes.keys.select { |m| m.include?('_wday') }
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
  # Locking inside validator is an app level solution to ensuring partial
  # uniqueness of creation_mode. Partial indexes are currently not
  # supported by MySQL, so uniqueness cannot be assured by adding
  # unique index:
  #   add_index :issue_recurrences, [:issue_id, :creation_mode], unique: true,
  #     where: "creation_mode = 2"
  # Should work as long as validation and saving is in one transaction.
  validates :creation_mode, uniqueness: {
    scope: :issue_id,
    conditions: -> {
      lock.in_place.where.not(
        anchor_mode: IssueRecurrence.anchor_modes[:date_fixed_after_close]
      )
    },
    if: -> {
      ['last_issue_flexible',
       'last_issue_flexible_on_delay',
       'last_issue_fixed_after_close'].include?(self.anchor_mode)
    },
    message: :only_one_in_place
  }
  validates :anchor_mode, inclusion: anchor_modes.keys
  validates :anchor_mode, inclusion: {
    in: ['first_issue_fixed', 'last_issue_fixed', 'last_issue_fixed_after_close',
         'date_fixed_after_close'],
    if: -> { delay_multiplier > 0 },
    message: :close_anchor_no_delay
  }
  # in-place only allowed for schemes that disallow multiple open recurrences
  validates :anchor_mode, inclusion: {
    in: ['last_issue_flexible', 'last_issue_flexible_on_delay',
         'last_issue_fixed_after_close', 'date_fixed_after_close'],
    if: -> { creation_mode == 'in_place' },
    message: :in_place_closed_only
  }
  validates :anchor_mode, exclusion: {
    in: ['date_fixed_after_close'],
    if: -> { creation_mode != 'in_place' },
    message: :date_anchor_in_place_only
  }
  validates :anchor_to_start, inclusion: [true, false]
  validates :anchor_date, absence: {unless: -> { anchor_mode == 'date_fixed_after_close' }},
    presence: {if: -> { anchor_mode == 'date_fixed_after_close' }}
  validate :validate_base_dates
  def validate_base_dates
    issue, base = self.base_dates
    date_required = ['last_issue_flexible',
                     'last_issue_flexible_on_delay',
                     'date_fixed_after_close'].exclude?(self.anchor_mode)
    if date_required && (base[:start] || base[:due]).blank?
      errors.add(:anchor_mode, :issue_anchor_no_blank_dates)
    end
    if self.anchor_to_start && base[:start].blank? && base[:due].present?
      errors.add(:anchor_to_start, :start_mode_requires_date)
    end
    if !self.anchor_to_start && base[:start].present? && base[:due].blank?
      errors.add(:anchor_to_start, :due_mode_requires_date)
    end
  end
  validates :mode, inclusion: modes.keys
  validates :multiplier, numericality: {greater_than: 0, only_integer: true}
  validates :delay_mode, inclusion: delay_modes.keys
  validates :delay_multiplier, numericality: {greater_than_or_equal_to: 0, only_integer: true}
  validates :include_subtasks, inclusion: [true, false]
  validates :date_limit, absence: {if: -> { count_limit.present? } }
  validate on: :create, if: -> { date_limit.present? } do
    errors.add(:date_limit, :not_in_future) unless Date.current < date_limit
  end
  validates :count_limit, absence: {if: -> { date_limit.present? } },
    numericality: {allow_nil: true, only_integer: true}

  after_initialize do
    if new_record?
      self.count = 0
      self.creation_mode ||= :copy_first
      self.anchor_mode ||= :first_issue_fixed
      self.anchor_to_start = false if self.anchor_to_start.nil?
      self.mode ||= :monthly_day_from_first
      self.multiplier ||= 1
      self.delay_mode ||= :day
      self.delay_multiplier ||= 0
      self.include_subtasks = false if self.include_subtasks.nil?
    end
  end
  before_destroy :editable?

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
    if ref_dates.nil? || FLEXIBLE_ANCHORS.include?(self.anchor_mode)
      ref_description = " #{l("#{s}.mode_descriptions.#{self.mode}")}"
    elsif MONTHLY_MODES.include?(self.mode)
      label = self.anchor_to_start ? :start : :due
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
      "#{l("#{s}.delayed_by")} <b>#{self.delay_multiplier}" \
      " #{l("#{s}.delay_intervals.#{self.delay_mode}").pluralize(self.delay_multiplier)}" \
      "</b>" : ''

    count_limit_info = self.count_limit.present? ? " #{"<b>#{self.count_limit}" \
        " #{l("#{s}.recurrence").pluralize(self.count_limit)}</b>."}" : ''

    "#{l("#{s}.creation_modes.#{self.creation_mode}")}" \
    " <b>#{l("#{s}.include_subtasks.true") if self.include_subtasks}</b>" \
      " #{l("#{s}.every")}" \
      " <b>#{self.multiplier}" \
      " #{l("#{s}.mode_intervals.#{self.mode}").pluralize(self.multiplier)}</b>," \
      "#{ref_description}" \
      " #{l("#{s}.based_on")}" \
      " #{l("#{s}.anchor_to_start.#{self.anchor_to_start}")}" \
      " #{l("#{s}.anchor_modes.#{self.anchor_mode}", ref_dates)}" \
      "#{" <b>#{self.anchor_date}</b>" if self.anchor_date.present?}" \
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

    shift = if self.first_issue_fixed? || self.date_fixed_after_close?
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
    when :monthly_day_from_first
      label = self.anchor_to_start ? :start : :due
      date = dates[label]
      target_date = date + shift.months
      dates = self.offset(target_date, label, dates)
    when :monthly_day_to_last
      label = self.anchor_to_start ? :start : :due
      date = dates[label]
      days_to_last = date.end_of_month - date
      target_eom = (date + shift.months).end_of_month
      target_date = target_eom - [days_to_last, target_eom.mday-1].min
      dates = self.offset(target_date, label, dates)
    when :monthly_dow_from_first
      label = self.anchor_to_start ? :start : :due
      date = dates[label]
      source_dow = date.days_to_week_start
      target_bom = (date + shift.months).beginning_of_month
      target_bom_dow = target_bom.days_to_week_start
      week = ((date.mday - 1) / 7) + (source_dow >= target_bom_dow ? 0 : 1)
      target_bom_shift = week.weeks + (source_dow - target_bom_dow).days
      overflow = target_bom_shift > (target_bom.end_of_month.mday-1).days ? 1.week : 0
      target_date = target_bom + target_bom_shift - overflow
      dates = self.offset(target_date, label, dates)
    when :monthly_dow_to_last
      label = self.anchor_to_start ? :start : :due
      date = dates[label]
      source_dow = date.days_to_week_start
      target_eom = (date + shift.months).end_of_month
      target_eom_dow = target_eom.days_to_week_start
      week = ((date.end_of_month - date).to_i / 7) + (source_dow > target_eom_dow ? 1 : 0)
      target_eom_shift = week.weeks + (target_eom_dow - source_dow).days
      overflow = target_eom_shift > (target_eom.mday-1).days ? 1.week : 0
      target_date = target_eom - target_eom_shift + overflow
      dates = self.offset(target_date, label, dates)
    when :monthly_wday_from_first
      label = self.anchor_to_start ? :start : :due
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
    when :monthly_wday_to_last
      label = self.anchor_to_start ? :start : :due
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
      label = self.anchor_to_start ? :start : :due
      date = dates[label]
      target_date = date + shift.years
      dates = self.offset(target_date, label, dates)
    end

    return nil if self.date_limit.present? && (dates[:start] || dates[:due]) > self.date_limit

    dates
  end

  # Offset 'dates' so date with 'label' is equal 'target'.
  # Return offset 'dates' or nil if 'dates' does not include 'label'.
  def offset(target_date, target_label, dates)
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
        target_label = self.anchor_to_start ? :start : :due
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

  # Return reference issue and base dates for used for calculation of reference dates.
  def base_dates
    case self.anchor_mode.to_sym
    when :first_issue_fixed
      ref_issue = self.issue
      base_dates = {start: ref_issue.start_date, due: ref_issue.due_date}
    when :last_issue_fixed, :last_issue_flexible, :last_issue_flexible_on_delay,
         :last_issue_fixed_after_close
      ref_issue = self.last_issue || self.issue
      base_dates = {start: ref_issue.start_date, due: ref_issue.due_date}
    when :date_fixed_after_close
      ref_issue = self.last_issue || self.issue
      base_dates = {start: self.issue.start_date, due: self.issue.due_date}
    end
    [ref_issue, base_dates]
  end

  # Return reference dates for next recrrence or nil if no suitable dates found.
  def reference_dates
    ref_issue, base_dates = self.base_dates
    ref_dates = nil

    self.validate_base_dates
    unless self.errors.empty?
      log("issue ##{ref_issue.id}: #{self.errors.messages.values.to_sentence}")
      return nil
    end

    case self.anchor_mode.to_sym
    when :first_issue_fixed, :last_issue_fixed
      ref_dates = base_dates
    when :last_issue_flexible
      if ref_issue.closed?
        closed_date = ref_issue.closed_on.to_date
        ref_label = self.anchor_to_start ? :start : :due
        if (base_dates[:start] || base_dates[:due]).present?
          ref_dates = self.offset(closed_date, ref_label, base_dates)
        else
          ref_dates = base_dates.update(ref_label => closed_date)
        end
      end
    when :last_issue_flexible_on_delay
      if ref_issue.closed?
        closed_date = ref_issue.closed_on.to_date
        boundary_date = base_dates[:due] || base_dates[:start]
        ref_label = self.anchor_to_start ? :start : :due
        if boundary_date.present?
          if boundary_date < closed_date
            ref_dates = self.offset(closed_date, ref_label, base_dates)
          else
            ref_dates = base_dates
          end
        else
          ref_dates = base_dates.update(ref_label => closed_date)
        end
      end
    when :last_issue_fixed_after_close
      if ref_issue.closed?
        ref_dates = base_dates
      end
    when :date_fixed_after_close
      if ref_issue.closed?
        ref_label = self.anchor_to_start ? :start : :due
        if (base_dates[:start] || base_dates[:due]).present?
          ref_dates = self.offset(self.anchor_date, ref_label, base_dates)
        else
          ref_dates = base_dates.update(ref_label => self.anchor_date)
        end
      end
    end

    [ref_issue, ref_dates]
  end

  # Return predicted next recurrence dates or nil.
  def next_dates
    ref_issue, ref_dates = self.reference_dates
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
    ref_issue, ref_dates = self.reference_dates
    return if ref_dates.nil?

    case self.anchor_mode.to_sym
    when :first_issue_fixed
      new_dates = self.advance(-1, ref_dates)
      while (new_dates[:start] || new_dates[:due]) < Date.tomorrow
        new_dates = self.advance(ref_dates)
        break if new_dates.nil?
        yield(new_dates)
      end
    when :last_issue_fixed
      while (ref_dates[:start] || ref_dates[:due]) < Date.tomorrow
        new_dates = self.advance(ref_dates)
        break if new_dates.nil?
        yield(new_dates)
        ref_dates = new_dates
      end
    when :last_issue_flexible, :last_issue_flexible_on_delay
      new_dates = self.advance(ref_dates)
      yield(new_dates) unless new_dates.nil?
    when :last_issue_fixed_after_close
      closed_date = ref_issue.closed_on.to_date
      barrier_date = [closed_date, ref_dates[:start] || ref_dates[:due]].max
      while (ref_dates[:start] || ref_dates[:due]) <= barrier_date
        new_dates = self.advance(ref_dates)
        break if new_dates.nil?
        ref_dates = new_dates
      end
      yield(ref_dates) unless ref_dates.nil?
    when :date_fixed_after_close
      adj = 0
      closed_date = ref_issue.closed_on.to_date
      barrier_date = [
        closed_date,
        ref_issue.start_date || ref_issue.due_date || ref_dates[:start] || ref_dates[:due]
      ].max
      new_dates = self.advance(-1, ref_dates)
      while (new_dates[:start] || new_dates[:due]) <= barrier_date
        new_dates = self.advance(adj, ref_dates)
        break if new_dates.nil?
        adj += 1
      end
      yield(new_dates) unless new_dates.nil?
    end
  end

  def self.renew_all
    @@log_problems = true
    IssueRecurrence.all.group_by { |r| r.issue_id }.each do |*, rs|
      inplace = nil
      rs.select { |r| r.creation_mode == 'in_place' }.map do |r|
        r.renew do |dates|
          if inplace.nil? || ((dates[:start] || dates[:due]) <
                              (inplace[:dates][:start] || inplace[:dates][:due]))
            inplace = {r: r, dates: dates}
          end
        end
      end

      rs.map do |r|
        r.reload
        r.renew do |dates|
          if r.creation_mode == 'in_place'
            inplace[:r].create(inplace[:dates])
          else
            r.create(dates)
          end
        end
      end
    end
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
