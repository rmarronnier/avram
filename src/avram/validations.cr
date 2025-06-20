require "./validations/callable_error_message"
require "./validations/common_helpers"

# A number of methods for validating Avram::Attributes
# All validation methods return `Bool`. `false` if any error is added, otherwise `true`
#
# This module is included in `Avram::Operation`, `Avram::SaveOperation`, and `Avram::DeleteOperation`
module Avram::Validations
  extend self
  include Avram::Validations::CommonHelpers

  macro included
    abstract def default_validations
  end

  # Defines an instance method that gets called
  # during validation of an operation. Define your default
  # validations inside of the block.
  # ```
  # default_validations do
  #   validate_required some_attribute
  # end
  # ```
  macro default_validations
    # :nodoc:
    def default_validations
      {% if @type.methods.map(&.name).includes?(:default_validations.id) %}
        previous_def
      {% else %}
        super
      {% end %}

      {{ yield }}
    end
  end

  # Validates that at most one attribute is filled
  #
  # If more than one attribute is filled it will mark all but the first filled
  # field invalid.
  def validate_at_most_one_filled(
    *attributes,
    message : Avram::Attribute::ErrorMessage = Avram.settings.i18n_backend.get(:validate_at_most_one_filled),
  ) : Bool
    no_errors = true
    present_attributes = attributes.reject(&.value.blank?)

    if present_attributes.size > 1
      present_attributes.skip(1).each do |attr|
        attr.add_error(message)
        no_errors = false
      end
    end

    no_errors
  end

  # Validates that at exactly one attribute is filled
  #
  # This validation is used by `Avram::Polymorphic.polymorphic` to ensure
  # that a required polymorphic association is set.
  #
  # If more than one attribute is filled it will mark all but the first filled
  # field invalid.
  #
  # If no field is filled, the first field will be marked as invalid.
  def validate_exactly_one_filled(
    *attributes,
    message : Avram::Attribute::ErrorMessage = Avram.settings.i18n_backend.get(:validate_exactly_one_filled),
  ) : Bool
    no_errors = validate_at_most_one_filled(*attributes)
    present_attributes = attributes.reject(&.value.blank?)

    if present_attributes.size.zero?
      attributes.first.add_error(message)
      no_errors = false
    end

    no_errors
  end

  # Validates that the passed in attributes have values
  #
  # You can pass in one or more attributes at a time. The attribute will be
  # marked as invalid if the value is `nil`, or "blank" (empty strings or strings with just whitespace)
  #
  # `false` is not considered invalid.
  #
  # ```
  # validate_required name, age, email
  # ```
  def validate_required(
    *attributes,
    message : Avram::Attribute::ErrorMessage = Avram.settings.i18n_backend.get(:validate_required),
  ) : Bool
    no_errors = true
    attributes.each do |attribute|
      if attribute.value.blank_for_validates_required? && !attribute.allow_blank?
        attribute.add_error(message)
        no_errors = false
      end
    end

    no_errors
  end

  # Validate whether an attribute was accepted (`true`)
  #
  # This validation is only for Boolean Attributes. The attribute will be marked
  # as invalid for any value other than `true`.
  def validate_acceptance_of(
    attribute : Avram::Attribute(Bool),
    message : Avram::Attribute::ErrorMessage = Avram.settings.i18n_backend.get(:validate_acceptance_of),
  ) : Bool
    no_errors = true
    if attribute.value != true
      attribute.add_error(message)
      no_errors = false
    end

    no_errors
  end

  # Validates that the values of two attributes are the same
  #
  # Takes two attributes and if the values are different the second attribute
  # (`with`/`confirmation_attribute`) will be marked as invalid
  #
  # Example:
  #
  # ```
  # validate_confirmation_of password, with: password_confirmation
  # ```
  #
  # If `password_confirmation` does not match, it will be marked invalid.
  def validate_confirmation_of(
    attribute : Avram::Attribute(T),
    with confirmation_attribute : Avram::Attribute(T),
    message : Avram::Attribute::ErrorMessage = Avram.settings.i18n_backend.get(:validate_confirmation_of),
  ) : Bool forall T
    no_errors = true
    if attribute.value != confirmation_attribute.value
      confirmation_attribute.add_error(message)
      no_errors = false
    end

    no_errors
  end

  # Validates that the attribute value is in a list of allowed values
  #
  # ```
  # validate_inclusion_of state, in: ["NY", "MA"]
  # ```
  #
  # This will mark `state` as invalid unless the value is `"NY"`, or `"MA"`.
  def validate_inclusion_of(
    attribute : Avram::Attribute(T),
    in allowed_values : Enumerable(T),
    message : Avram::Attribute::ErrorMessage = Avram.settings.i18n_backend.get(:validate_inclusion_of),
    allow_nil : Bool = false,
  ) : Bool forall T
    validate_value_in_enumerable(
      attribute: attribute,
      value: attribute.value,
      allowed_values: allowed_values,
      message: message,
      allow_nil: allow_nil
    )
  end

  # Validate the size of a `String` or `Array` is exactly a certain size
  #
  # ```
  # validate_size_of api_key, is: 32
  # validate_size_of theme_colors, is: 4
  # ```
  def validate_size_of(
    attribute : Avram::Attribute(String) | Avram::Attribute(Array(T)),
    *,
    is exact_size : Number,
    message : Avram::Attribute::ErrorMessage = Avram.settings.i18n_backend.get(:validate_exact_size_of),
    allow_nil : Bool = false,
  ) : Bool forall T
    no_errors = true
    size = attribute.value.try(&.size) || 0
    if size != exact_size
      if !(allow_nil && attribute.value.nil?)
        attribute.add_error(message % exact_size)
        no_errors = false
      end
    end

    no_errors
  end

  # Validate the size of a `String` or `Array` is within a `min` and/or `max`
  #
  # ```
  # validate_size_of feedback, min: 18, max: 100
  # validate_size_of password, min: 12
  # validate_size_of options, max: 10
  # ```
  # ameba:disable Metrics/CyclomaticComplexity
  def validate_size_of(
    attribute : Avram::Attribute(String) | Avram::Attribute(Array(T)),
    min : Number? = nil,
    max : Number? = nil,
    message : Avram::Attribute::ErrorMessage? = nil,
    allow_nil : Bool = false,
  ) : Bool forall T
    # Check for impossible validation first
    if !min.nil? && !max.nil? && min > max
      raise ImpossibleValidation.new(
        attribute: attribute.name,
        message: "size greater than #{min} but less than #{max}"
      )
    end

    # Handle nil case explicitly
    if attribute.value.nil? && !allow_nil
      if !min.nil? && min > 0
        attribute.add_error((message || Avram.settings.i18n_backend.get(:validate_min_size_of)) % min)
      elsif !max.nil?
        attribute.add_error((message || Avram.settings.i18n_backend.get(:validate_max_size_of)) % max)
      end
      return false
    end

    validate_range(
      attribute: attribute,
      value: attribute.value,
      min: min,
      max: max,
      min_message: message || Avram.settings.i18n_backend.get(:validate_min_size_of),
      max_message: message || Avram.settings.i18n_backend.get(:validate_max_size_of),
      allow_nil: allow_nil
    ) do |value|
      value.try(&.size) || 0
    end
  end

  # Validate a number is `at_least` and/or `no_more_than`
  #
  # ```
  # validate_numeric age, at_least: 18
  # validate_numeric count, at_least: 0, no_more_than: 1200
  # ```
  # ameba:disable Metrics/CyclomaticComplexity
  def validate_numeric(
    attribute : Avram::Attribute(Number),
    *,
    at_least = nil,
    no_more_than = nil,
    message = nil,
    allow_nil : Bool = false,
  ) : Bool
    # Special handling for nil numeric values
    if attribute.value.nil?
      return handle_nil_value(
        attribute: attribute,
        allow_nil: allow_nil,
        nil_message: Avram.settings.i18n_backend.get(:validate_numeric_nil)
      )
    end

    validate_range(
      attribute: attribute,
      value: attribute.value,
      min: at_least,
      max: no_more_than,
      min_message: message || Avram.settings.i18n_backend.get(:validate_numeric_min),
      max_message: message || Avram.settings.i18n_backend.get(:validate_numeric_max),
      allow_nil: allow_nil
    ) do |value|
      value.as(Number)
    end
  end

  # Validates that the passed in attributes matches the given regex
  #
  # ```
  # validate_format_of email, with: /[^@]+@[^\.]+\..+/
  # ```
  #
  # Alternatively, the `match` argument can be set to `false` to not match the
  # given regex.
  def validate_format_of(
    attribute : Avram::Attribute(String),
    with regex : Regex,
    match : Bool = true,
    message : Avram::Attribute::ErrorMessage = Avram.settings.i18n_backend.get(:validate_format_of),
    allow_nil : Bool = false,
  ) : Bool
    unless allow_nil && attribute.value.nil?
      matching = attribute.value.to_s.match(regex)

      if (match && !matching) || (!match && matching)
        attribute.add_error(message)
        return false
      end
    end

    true
  end

  def validate_url_format(
    attribute : Avram::Attribute(String),
    scheme : String = "https",
    message : Avram::Attribute::ErrorMessage = Avram.settings.i18n_backend.get(:validate_url_format),
  ) : Bool
    if url = attribute.value.presence
      uri = URI.parse(url)
      if uri.scheme != scheme || uri.host.presence.nil?
        attribute.add_error(message % scheme)
        return false
      end
    end

    true
  end
end
