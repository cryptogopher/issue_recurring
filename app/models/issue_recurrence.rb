class IssueRecurrence < ActiveRecord::Base
  include Redmine::Utils::DateCalculation

  belongs_to :issue, validate: true
  belongs_to :last_issue, class_name: 'Issue', validate: true

  enum creation_mode: {
    copy_first: 0,
    copy_last: 1,
    reopen: 2
  }

  enum anchor_mode: {
    first_issue_fixed: 0,
    last_issue_fixed: 1,
    last_issue_flexible: 2,
    last_issue_flexible_on_delay: 3, # TODO: rename to _flexible_if_late ?
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
    days: 0,
    weeks: 1,
    months: 2
  }

  JOURNAL_MODES = [:never, :always, :on_reopen]
  AHEAD_MODES = [:days, :weeks, :months, :years]

  # Don't check privileges on :renew
  validate on: [:create, :update] do
    errors.add(:issue, :insufficient_privileges) unless editable?
  end
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
    conditions: -> { lock.reopen.where.not(anchor_mode: :date_fixed_after_close) },
    if: -> {
      ['last_issue_flexible',
       'last_issue_flexible_on_delay',
       'last_issue_fixed_after_close'].include?(anchor_mode)
    },
    message: :only_one_reopen
  }
  validates :anchor_mode, inclusion: anchor_modes.keys
  validates :anchor_mode, exclusion: {
    in: FLEXIBLE_ANCHORS,
    if: -> { delay_multiplier > 0 },
    message: :delay_requires_fixed_anchor
  }
  # reopen only allowed for schemes that disallow multiple open recurrences
  validates :anchor_mode, inclusion: {
    in: ['last_issue_flexible', 'last_issue_flexible_on_delay',
         'last_issue_fixed_after_close', 'date_fixed_after_close'],
    if: -> { creation_mode == 'reopen' },
    message: :reopen_requires_close_date_based
  }
  validates :anchor_to_start, inclusion: [true, false]
  validates :anchor_date, absence: {unless: -> { anchor_mode == 'date_fixed_after_close' }},
    presence: {if: -> { anchor_mode == 'date_fixed_after_close' }}
  # Validates Issue attributes that may become invalid during IssueRecurrence lifetime.
  # Besides being checked on IssueRecurrence validation, they should be checked
  # every time new recurrence has to be provided.
  validate :validate_base_dates
  def validate_base_dates
    issue, base = self.base_dates
    date_required = ['last_issue_flexible',
                     'last_issue_flexible_on_delay',
                     'date_fixed_after_close'].exclude?(anchor_mode)
    if date_required && (base[:start] || base[:due]).blank?
      errors.add(:anchor_mode, :blank_issue_dates_require_reopen)
    end
    if anchor_to_start && base[:start].blank? && base[:due].present?
      errors.add(:anchor_to_start, :start_mode_requires_date)
    end
    if !anchor_to_start && base[:start].present? && base[:due].blank?
      errors.add(:anchor_to_start, :due_mode_requires_date)
    end
    if (creation_mode == 'reopen') && !include_subtasks && issue.dates_derived?
      errors.add(:creation_mode, :derived_dates_reopen_requires_subtasks)
    end
  end
  validates :mode, inclusion: modes.keys
  validates :multiplier, numericality: {greater_than: 0, only_integer: true}
  validates :delay_mode, inclusion: delay_modes.keys
  validates :delay_multiplier, numericality: {greater_than_or_equal_to: 0, only_integer: true}
  validates :include_subtasks, inclusion: [true, false]
  validates :date_limit, absence: {if: -> { count_limit.present? } }
  validate if: -> { date_limit.present? && date_fixed_after_close? } do
    errors.add(:date_limit, :not_after_anchor_date) unless anchor_date < date_limit
  end
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
      self.delay_mode ||= :days
      self.delay_multiplier ||= 0
      self.include_subtasks = false if self.include_subtasks.nil?
    end

    @journal_notes = ''
  end
  before_destroy :editable?

  attr_reader :journal_notes

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

    *, ref_dates = self.reference_dates(assume_closed_at = Date.current)
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
      " #{l("#{s}.issue")}" \
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

  def limit_mode
    return case
      when self.date_limit.present?
        :date_limit
      when self.count_limit.present?
        :count_limit
      else
        :no_limit
      end
  end

  def initialize_dup(other)
    self.last_issue = nil
    self.count = 0
    super
  end

  # TODO: make methods private as appropriate

  # Advance 'dates' according to recurrence mode and adjustment (+/- # of periods).
  # Return advanced 'dates' or nil if recurrence limit reached.
  # TODO: change internals so that adj == -1 is never used and [adj -1 -> adj 0].
  # Current choice is not intuitive.
  def advance(adj=0, **dates)
    adj_count = self.count + adj
    adj_count = [self.count, adj_count].min if self.date_fixed_after_close?
    return nil if self.count_limit.present? && adj_count >= self.count_limit

    shift = if self.first_issue_fixed? || self.date_fixed_after_close?
              self.multiplier*(self.count + 1 + adj)
            else
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

    case self.anchor_mode.to_sym
    when :first_issue_fixed, :date_fixed_after_close
      dates = self.delay(dates) if self.count + 1 + adj > 0
    when :last_issue_fixed, :last_issue_fixed_after_close
      dates = self.delay(dates) if self.count + adj == 0
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

  # Delay 'dates' according to delay mode.
  def delay(dates)
    return dates if self.delay_multiplier == 0
    delay = self.delay_multiplier.send(self.delay_mode)
    dates.map { |label, date| [label, date ? date + delay : date] }.to_h
  end

  # Create next recurrence issue at given dates.
  def create(dates)
    ref_issue = self.last_issue if self.copy_last?
    ref_issue ||= self.issue
    prev_dates = {start: ref_issue.start_date, due: ref_issue.due_date}

    prev_user = User.current
    author_login = Setting.plugin_issue_recurring[:author_login]
    author = User.find_by(login: author_login)
    User.current = author || ref_issue.author

    IssueRecurrence.transaction do
      if Setting.plugin_issue_recurring[:journal_mode] == :always ||
          (Setting.plugin_issue_recurring[:journal_mode] == :on_reopen && self.reopen?)
        # Setting journal on self.issue won't record copy if :copy_last is used
        ref_issue.init_journal(User.current)
      end

      new_issue = self.reopen? ? ref_issue :
        ref_issue.copy(nil, subtasks: self.include_subtasks, skip_recurrences: true)

      new_issue.start_date = dates[:start]
      new_issue.due_date = dates[:due]
      new_issue.parent = ref_issue.parent
      new_issue.done_ratio = 0
      new_issue.status = new_issue.tracker.default_status
      new_issue.recurrence_of = self.issue
      assignee = new_issue.assigned_to
      is_assignee_valid = assignee.blank? || new_issue.assignable_users.include?(assignee)
      keep_assignee = Setting.plugin_issue_recurring[:keep_assignee]
      unless keep_assignee && is_assignee_valid
        new_issue.default_reassign
      end
      new_issue.save!

      # Errors containing issue ID reported only after #save
      if keep_assignee && !is_assignee_valid
        log(:warning_keep_assignee, id: new_issue.id, login: assignee.login)
      end
      if author_login && !author
        log(:warning_author, id: new_issue.id, login: author_login)
      end

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
          assignee = child.assigned_to
          is_assignee_valid = assignee.blank? || child.assignable_users.include?(assignee)
          unless keep_assignee && is_assignee_valid
            child.default_reassign
          end
          child.save!

          # Errors containing issue ID reported only after #save
          if keep_assignee && !is_assignee_valid
            log(:warning_keep_assignee, id: child.id, login: assignee.login)
          end
        end
      end

      # Renewal should happen irrespective of author's (= User.current) privileges.
      # No user-assignable attribues are/should be changed.
      self.last_issue = new_issue
      self.count += 1
      self.save!(context: :renew)
    end

    User.current = prev_user
  end

  # Return reference issue and base dates used for calculation of reference dates.
  # Base dates are validated for start/due date availability according to anchor_to_start.
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

  # Return reference dates for next recurrence or nil if no suitable dates found.
  # Used by 'to_s' to display recurrence characteristics.
  # assume_closed_at gives you predicted reference_dates assuming issue has been
  # closed at given date.
  def reference_dates(assume_closed_at=nil)
    ref_issue, base_dates = self.base_dates
    ref_dates = nil

    self.validate_base_dates
    unless self.errors.empty?
      # Problems are always logged to master issue, so no need to refer to self.issue
      # Linking ref_issue though, as source of problems (lack of dates etc.) lies in it
      log(:warning_renew, id: ref_issue.id, errors: errors.messages.values.flatten.to_sentence)
      return nil
    end

    case self.anchor_mode.to_sym
    when :first_issue_fixed, :last_issue_fixed
      ref_dates = base_dates
    when :last_issue_flexible
      if ref_issue.closed? || assume_closed_at
        closed_date = assume_closed_at || ref_issue.closed_on.to_date
        ref_label = self.anchor_to_start ? :start : :due
        if (base_dates[:start] || base_dates[:due]).present?
          ref_dates = self.offset(closed_date, ref_label, base_dates)
        else
          ref_dates = base_dates.update(ref_label => closed_date)
        end
      end
    when :last_issue_flexible_on_delay
      if ref_issue.closed? || assume_closed_at
        closed_date = assume_closed_at || ref_issue.closed_on.to_date
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
      if ref_issue.closed? || assume_closed_at
        ref_dates = base_dates
      end
    when :date_fixed_after_close
      if ref_issue.closed? || assume_closed_at
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

  # Yield next recurrence dates (can yield multiple times for fixed schedules).
  # Does not yield nil.
  # Computing dates must assume that yield does not result in a call to 'create',
  # i.e. IssueRecurrence fields are unchanged after yield.
  # Dates can only be modified here by the 'advance' method. All other
  # delays/offsets have to be incorporated in 'reference_dates'.
  # If 'predict', return at most one future date. For close based recurrences assume
  # issue closed today if open or return nothing if already closed.
  def next_dates(predict)
    ref_issue, ref_dates = self.reference_dates(predict ? Date.current : nil)
    return if ref_dates.nil?

    case self.anchor_mode.to_sym
    when :first_issue_fixed, :last_issue_fixed
      settings = Setting.plugin_issue_recurring
      renew_ahead_to = Date.tomorrow + settings[:ahead_multiplier].send(settings[:ahead_mode])

      new_dates = self.first_issue_fixed? ? self.advance(-1, **ref_dates) : ref_dates
      adj = 0
      while (new_dates[:start] || new_dates[:due]) < renew_ahead_to
        new_dates = self.advance(adj, **ref_dates)
        break if new_dates.nil?
        yield(new_dates) unless predict
        ref_dates = new_dates if self.last_issue_fixed?
        adj += 1
      end
      predicted_dates = predict ? self.advance(adj, **ref_dates) : nil
      yield(predicted_dates) if predicted_dates
    when :last_issue_flexible, :last_issue_flexible_on_delay
      new_dates = self.advance(**ref_dates)
      yield(new_dates) unless new_dates.nil? || (predict && ref_issue.closed?)
    when :last_issue_fixed_after_close
      closed_date = predict ? Date.current : ref_issue.closed_on.to_date
      barrier_date = [closed_date, ref_dates[:start] || ref_dates[:due]].max
      while (ref_dates[:start] || ref_dates[:due]) <= barrier_date
        new_dates = self.advance(**ref_dates)
        break if new_dates.nil?
        ref_dates = new_dates
      end
      yield(ref_dates) unless new_dates.nil? || (predict && ref_issue.closed?)
    when :date_fixed_after_close
      closed_date = predict ? Date.current : ref_issue.closed_on.to_date
      barrier_date = [
        closed_date,
        ref_issue.start_date || ref_issue.due_date || ref_dates[:start] || ref_dates[:due]
      ].max
      adj = -1
      begin
        new_dates = self.advance(adj, **ref_dates)
        adj += 1
      end until new_dates.nil? || ((new_dates[:start] || new_dates[:due]) > barrier_date)
      yield(new_dates) unless new_dates.nil? || (predict && ref_issue.closed?)
    end
  end

  # Depending on 'predict':
  #  = false: give next recurrence dates for all issue schedules, where renewal is due NOW,
  #  = true: predict 1 recurrence ahead, assuming issue closed today for non-closed
  #    close based schedules.
  # Return hash: {r1 => dates_array1, r2 => dates_array2, ...}
  def self.issue_dates(issue, predict=false)
    reopen = nil
    result = Hash.new { |h,k| h[k] = [] }

    issue.recurrences.each do |r|
      r.next_dates(predict) do |dates|
        if r.reopen?
          current_date = dates[:start] || dates[:due]
          earliest_date = reopen[:dates][:start] || reopen[:dates][:due] if reopen
          reopen = {r: r, dates: dates} if reopen.nil? || (current_date < earliest_date)
        else
          result[r] << dates
        end
      end
    end

    result[reopen[:r]] << reopen[:dates] if reopen
    result
  end

  def self.recurrences_dates(rs, predict=false)
    issues = rs.map { |r| r.issue }.uniq
    issues.map! { |issue| self.issue_dates(issue, predict) }.reduce(:merge)
  end

  def self.renew_all(quiet=false)
    IssueRecurrence.select(:issue_id).distinct.includes(:issue).each do |r|
      self.issue_dates(r.issue).each do |recurrence, dates_list|
        puts "Recurring issue #{r.issue}" unless quiet
        dates_list.each do |dates|
          puts " - creating recurrence at #{dates}" unless quiet
          recurrence.create(dates)
        end
        puts "...done" unless quiet
      end

      # Problems are always logged to master issue, not recurrences (as opposed
      # to normal journal entries, which go to the ref_issues)
      journal_notes = r.issue.recurrences.map(&:journal_notes).join
      if journal_notes.present?
        prev_user = User.current
        author_login = Setting.plugin_issue_recurring[:author_login]
        User.current = User.find_by(login: author_login) || r.issue.author
        journal = r.issue.init_journal(User.current)
        journal.notes << journal_notes
        journal.save
        User.current = prev_user
      end
    end
  rescue Exception
    puts "...exception raised. Check output for errors. Either there is bug you may want" \
      " to report or your db is corrupted."
    raise
  end

  private

  def log(label, **args)
    @journal_notes << "#{l(label, args)}\r\n"
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
