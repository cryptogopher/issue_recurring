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

  enum delay_mode: {
    day: 0,
    week: 1,
    month: 2
  }

  validates :issue, presence: true, associated: true
  validate { errors.add(:issue, :insufficient_privileges) unless self.editable? }
  validates :last_issue, associated: true
  validates :count, numericality: {greater_than_or_equal: 0, only_integer: true}
  validates :creation_mode, inclusion: creation_modes.keys
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
  validates :mode, inclusion: modes.keys
  validates :multiplier, numericality: {greater_than: 0, only_integer: true}
  validates :delay_mode, inclusion: delay_modes.keys
  validates :delay_multiplier, numericality: {greater_than_or_equal_to: 0, only_integer: true}
  validates :include_subtasks, inclusion: [true, false]
  validates :date_limit, absence: {if: "count_limit.present?"}
  validates :count_limit, absence: {if: "date_limit.present?"},
    numericality: {allow_nil: true, only_integer: true}

  after_initialize do
    if new_record?
      self.count = 0
      self.creation_mode ||= :copy_first
      self.anchor_mode ||= :first_issue_fixed
      self.mode ||= :monthly_day_from_first
      self.multiplier ||= 1
      self.delay_mode ||= :day
      self.delay_multiplier ||= 0
      self.include_subtasks = false if self.include_subtasks.nil?
    end
  end
  before_destroy :valid?

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

    ref_dates = self.reference_dates
    ref_modifiers = Hash.new('')
    unless ref_dates.nil?
      ref_dates.each do |label, date|
        unless date.nil?
          days_to_eom = (date.end_of_month.mday - date.mday + 1).to_i
          values = {
            days_from_bom: date.mday.ordinalize,
            days_to_eom: days_to_eom.ordinalize,
            day_of_week: date.strftime("%A"),
            dows_from_bom: ((date.mday - 1) / 7 + 1).ordinalize,
            dows_to_eom: (((date.end_of_month.mday - date.mday).to_i / 7) + 1).ordinalize,
            # TODO
            wdays_from_bom: '',
            wdays_to_eom: ''
          }
          ref_modifiers[label] = "#{label.to_s}" \
            " #{l("#{s}.mode_modifiers.#{self.mode}", values)}"
        end
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
      " #{ref_modifiers.values.to_sentence}" \
      " #{l("#{s}.relative_to")}" \
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

    return nil if self.date_limit.present? && (dates[:start] || dates[:due]) > self.date_limit

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

  # Delay 'dates' according to delay mode.
  def delay(**dates)
    dates if (self.delay_multiplier == 0) || (self.count > 0)
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

  # Create next recurrence issue. Assumes that 'advance' will return valid date.
  def create(dates, as_user)
    ref_issue = (self.creation_mode.to_sym == :copy_last) ? self.last_issue : self.issue

    prev_user = User.current
    User.current = as_user || ref_issue.author
    ref_issue.init_journal(User.current, l(:journal_recurrence))

    new_issue = (self.creation_mode.to_sym == :in_place) ? self.issue :
      ref_issue.copy(nil, subtasks: self.include_subtasks)
    new_issue.save!

    if self.include_subtasks
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

  # Return reference dates for next recrrence or nil if no suitable dates found.
  def reference_dates
    ref_dates = nil
    case self.anchor_mode.to_sym
    when :first_issue_fixed
      ref_dates = {start: self.issue.start_date, due: self.issue.due_date}
      if logger && ref_dates.values.compact.empty?
        logger.warn("Issue ##{self.issue.id} has no dates to allow for recurrence renewal.") 
        ref_dates = nil
      end
      self.delay(ref_dates)
    when :last_issue_fixed
      ref_issue = self.last_issue || self.issue
      ref_dates = {start: ref_issue.start_date, due: ref_issue.due_date}
      if logger && ref_dates.values.compact.empty?
        logger.warn("Issue ##{ref_issue.id} has no dates to allow for recurrence renewal.") 
        ref_dates = nil
      end
      self.delay(ref_dates)
    when :last_issue_flexible, :last_issue_flexible_on_delay
      ref_issue = self.last_issue || self.issue
      if ref_issue.closed?
        closed_date = ref_issue.closed_on.to_date
        ref_dates = {start: ref_issue.start_date, due: ref_issue.due_date}
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
      end
    end
    ref_dates
  end

  # Return predicted next recurrence dates or nils.
  def next
    ref_dates = self.reference_dates
    return {} if ref_dates.nil?
    dates = self.advance(ref_dates)
    return {} if dates.nil?
    dates
  end

  def renew(as_user)
    case self.anchor_mode.to_sym
    when :first_issue_fixed
      ref_dates = self.reference_dates
      return if ref_dates.nil?
      prev_dates = self.advance(-1, ref_dates)
      while (prev_dates[:start] || prev_dates[:due]) < Date.tomorrow
        new_dates = self.advance(ref_dates)
        break if new_dates.nil?
        self.create(new_dates, as_user)
        prev_dates = new_dates
      end
    when :last_issue_fixed
      ref_dates = self.reference_dates
      return if ref_dates.nil?
      while (ref_dates[:start] || ref_dates[:due]) < Date.tomorrow
        new_dates = self.advance(ref_dates)
        break if new_dates.nil?
        self.create(new_dates, as_user)
        ref_dates = new_dates
      end
    when :last_issue_flexible, :last_issue_flexible_on_delay
      ref_dates = self.reference_dates
      return if ref_dates.nil?
      new_dates = self.advance(ref_dates)
      return if new_dates.nil?
      self.create(new_dates, as_user)
    end
  end

  def self.renew_all(**options)
    as_user = options[:as] && User.find_by(name: options[:as])
    IssueRecurrence.all.each do |r|
      r.renew(as_user)
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
