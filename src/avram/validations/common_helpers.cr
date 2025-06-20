module Avram::Validations::CommonHelpers
  # Common helper for range validation logic
  private def validate_range(
    attribute : Avram::Attribute(T),
    value : T?,
    min : Number?,
    max : Number?,
    min_message : String,
    max_message : String,
    allow_nil : Bool,
    &get_comparable_value : T -> (Int32 | Int64 | Float64)
  ) : Bool forall T
    no_errors = true

    # Validate min/max logic
    if !min.nil? && !max.nil? && min > max
      raise ImpossibleValidation.new(
        attribute: attribute.name,
        message: "value greater than #{min} but less than #{max}"
      )
    end

    # Handle nil values
    if value.nil?
      return true if allow_nil
      # Don't add error here, let the validation method handle it
      return false
    end

    comparable_value = get_comparable_value.call(value)

    # Check minimum
    if !min.nil? && comparable_value < min
      attribute.add_error(min_message % min)
      no_errors = false
    end

    # Check maximum
    if !max.nil? && comparable_value > max
      attribute.add_error(max_message % max)
      no_errors = false
    end

    no_errors
  end

  # Common helper for nil handling in validations
  private def handle_nil_value(
    attribute : Avram::Attribute(T),
    allow_nil : Bool,
    nil_message : Avram::Attribute::ErrorMessage,
  ) : Bool forall T
    if attribute.value.nil? && !allow_nil
      attribute.add_error(nil_message)
      return false
    end
    true
  end

  # Common helper for enumerable inclusion validation
  private def validate_value_in_enumerable(
    attribute : Avram::Attribute(T),
    value : T?,
    allowed_values : Enumerable(T),
    message : Avram::Attribute::ErrorMessage,
    allow_nil : Bool,
  ) : Bool forall T
    no_errors = true

    if value
      if !allowed_values.includes?(value)
        attribute.add_error(message)
        no_errors = false
      end
    else
      if !allow_nil
        attribute.add_error(message)
        no_errors = false
      end
    end

    no_errors
  end
end
