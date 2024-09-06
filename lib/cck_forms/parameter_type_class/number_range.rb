# Represents a decimal range — two integer values.
#
# Has an extra_options (see base.rb): :ranges
# If passed, on each object save the intersection of the target range and :ranges will be calculated and saved into DB
# (denormalized) for easy finding later via where('some_field.ranged.300-600' => true).
#
class CckForms::ParameterTypeClass::NumberRange
  include CckForms::ParameterTypeClass::Base

  # {from: 500, to: 1000, ranges: {"300-600" => true, "601-900" => true, "901-1500" => false}}
  def mongoize
    value_from_form = value
    return nil if value_from_form.blank?

    from = normalize_number value_from_form.try(:[], 'from')
    till = normalize_number value_from_form.try(:[], 'till')

    db_representation = {
      from: from,
      till: till,
      ranges: {}
    }

    if @extra_options[:ranges].respond_to? :each
      @extra_options[:ranges].each do |range_string|
        low, high = range_string.split(range_string_delimiter)
        if normalize_number(high).to_s != high.to_s
          high = Integer::MAX_32BIT
        end
        low, high = normalize_number(low), normalize_number(high)

        #   -----
        # [ RANGE ]
        completely_in_range = (from >= low && till <= high)

        #       -------
        # [ RANGE ]
        #
        # ------
        #    [ RANGE ]
        intersects_range_partially = (from <= low && till >= low) || (from <= high && till >= high)

        # -----------
        #  [ RANGE ]
        contains_range = from < low && till > high

        db_representation[:ranges][range_string] = completely_in_range || intersects_range_partially || contains_range
      end
    end

    db_representation
  end

  # "from 10"
  # "till 20"
  # "10-20"
  #
  # options:
  #
  #   delimeter - instead of "-"
  def to_s(options = {})
    options ||= {}
    return '' if value.blank?

    delimiter = options[:delimeter].presence || default_number_range_delimiter

    from = normalize_number value.try(:[], 'from')
    till = normalize_number value.try(:[], 'till')

    return '' if from.zero? && till.zero?

    if from.zero?
      [I18n.t("cck_forms.#{self.class.code}.till"), till].join(' ')
    elsif till.zero?
      [I18n.t("cck_forms.#{self.class.code}.from"), from].join(' ')
    elsif from == till
      from.to_s
    else
      [from, till].join(delimiter)
    end
  end

  # If options[:for] == :search and options[:as] == :select, builds a SELECT with options from extra_options[:rages].
  # Otherwise, two inputs are built.
  #
  # options[:only/:except] are available if the former case.
  def build_form(form_builder, options)
    set_value_in_hash options
    if options.delete(:for) == :search
      build_search_form(form_builder, options)
    else
      build_for_admin_interface_form(form_builder, options)
    end
  end

  # Search with the help of extra_options[:ranges]
  def search(criteria, field, query)
    criteria.where("#{field}.ranges.#{query}" => true)
  end

  private

  def form_field(form_builder_field, field_name, options)
    default_style = {class: 'form-control input-small'}

    form_builder_field.number_field field_name, options.merge(value: value.try(:[], field_name.to_s)).reverse_merge(default_style)
  end

  def build_for_admin_interface_form(form_builder, options)
    delimiter = options[:delimeter].presence || ' — '
    disable_delimiter = options[:disable_delimiter] && ''
    parent_class = options[:parent_class]

    result = ["<div class='form-inline #{parent_class}'>"]
    form_builder.fields_for :value do |ff|
      from_field = form_field ff, :from, options
      till_field = form_field ff, :till, options
      result << [from_field, till_field].join(disable_delimiter || delimiter).html_safe
    end
    result << '</div>'
    result.join.html_safe
  end

  def build_search_form(form_builder, options)
    delimiter = options[:delimeter].presence || default_number_range_delimiter
    form_fields = []
    visual_representation = options.delete(:as)
    show_only = options.delete(:only)

    if visual_representation == :select
      klazz = options.delete :class
      form_fields << form_builder.select(:value, [['', '']] + humanized_number_ranges_for_select, options.merge(selected: options[:value]), {class: klazz} )
    else
      show_all_fields = !show_only

      if show_all_fields or show_only == :low
        form_fields << form_builder.text_field(:from, options.merge(index: 'value', value: value.try(:[], 'from')))
      end

      if show_all_fields or show_only == :high
        form_fields << form_builder.text_field(:till, options.merge(index: 'value', value: value.try(:[], 'till')))
      end
    end

    form_fields.join(delimiter).html_safe
  end

  def default_number_range_delimiter
    '–'
  end

  def humanized_number_ranges_for_select
    @extra_options[:ranges].map do |range_string|
      low, high = range_string.split(range_string_delimiter)
      if normalize_number(low).to_s != low.to_s
        option_text = [I18n.t("cck_forms.#{self.class.code}.less_than"), high].join(' ')
      elsif normalize_number(high).to_s != high.to_s
        option_text = [I18n.t("cck_forms.#{self.class.code}.more_than"), low].join(' ')
      else
        option_text = [low, high].join(default_number_range_delimiter)
      end
      [option_text, range_string]
    end
  end

  def range_string_delimiter
    /[-:\\]/
  end
end
