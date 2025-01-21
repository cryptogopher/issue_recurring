module IssueRecurring
  module IssueRelationPatch
    IssueRelation.class_eval do
      TYPE_RECURS_IN      = "recurs_in"
      TYPE_RECURRENCE_OF  = "recurrence_of"
      TYPE_ORDER_MAX      = IssueRelation::TYPES.values.map { |v| v[:order] }.max

      TYPES = remove_const(:TYPES).merge({
        TYPE_RECURS_IN =>     {:name => :label_recurs_in,
                               :sym_name => :label_recurrence_of,
                               :order => TYPE_ORDER_MAX + 1,
                               :sym => TYPE_RECURRENCE_OF},
        TYPE_RECURRENCE_OF => {:name => :label_recurrence_of,
                               :sym_name => :label_recurs_in,
                               :order => TYPE_ORDER_MAX + 2,
                               :sym => TYPE_RECURS_IN, :reverse => TYPE_RECURS_IN}
      }).freeze

      skip_callback :validate, :before,
        IssueRelation.validators_on(:relation_type).find { |v| v.kind == :inclusion }
      validates_inclusion_of :relation_type, :in => TYPES.keys
    end
  end
end
