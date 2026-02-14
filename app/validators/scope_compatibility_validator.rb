# app/validators/scope_compatibility_validator.rb
# Validador para verificar compatibilidad entre roles y scopes
# Asegura que los scopes proporcionados sean válidos para el rol asignado

class ScopeCompatibilityValidator
  attr_reader :errors, :warnings

  def initialize(role:, node_scopes: nil, vehicle_scopes: nil)
    @role = role
    @node_scopes = normalize_scopes(node_scopes)
    @vehicle_scopes = normalize_scopes(vehicle_scopes)
    @errors = []
    @warnings = []
  end

  # ============================================
  # MÉTODO PRINCIPAL
  # ============================================
  def validate
    # Ejecutar todas las validaciones
    validate_scope_types_allowed
    validate_required_scopes_present
    validate_scope_exclusivity
    validate_scope_combinations
    validate_scope_conflicts

    # Retornar resultado estructurado
    {
      valid: @errors.empty?,
      errors: @errors,
      warnings: @warnings,
      summary: build_validation_summary
    }
  end

  # ============================================
  # Método de clase para validación rápida
  # ============================================
  def self.validate(role:, node_scopes: nil, vehicle_scopes: nil)
    new(role: role, node_scopes: node_scopes, vehicle_scopes: vehicle_scopes).validate
  end

  private

  # ============================================
  # VALIDACIONES PRINCIPALES
  # ============================================

  # Validar que los tipos de scope enviados estén permitidos por el rol
  def validate_scope_types_allowed
    # Si envían node_scopes pero el rol no lo permite
    if @node_scopes.any? && !@role.allows_node_scope?
      @errors << "Role '#{@role.name}' does not allow organizational node scopes"
    end

    # Si envían vehicle_scopes pero el rol no lo permite
    if @vehicle_scopes.any? && !@role.allows_vehicle_scope?
      @errors << "Role '#{@role.name}' does not allow vehicle scopes"
    end
  end

  # Validar que se proporcionen scopes si el rol los requiere
  def validate_required_scopes_present
    return unless @role.requires_any_scope?

    total_scopes = @node_scopes.size + @vehicle_scopes.size

    if total_scopes.zero?
      @errors << "Role '#{@role.name}' requires at least one scope (organizational nodes or vehicles)"
    end
  end

  # Validar exclusividad de scopes según el rol
  def validate_scope_exclusivity
    # Roles que solo permiten UN tipo de scope a la vez
    exclusive_roles = {
      "tenant_driver" => :vehicle_only,
      "tenant_admin" => :node_preferred,
      "tenant_manager" => :both_allowed
    }

    exclusivity_type = exclusive_roles[@role.slug]
    return unless exclusivity_type

    case exclusivity_type
    when :vehicle_only
      # Drivers solo pueden tener vehicle scopes
      if @node_scopes.any?
        @errors << "Role '#{@role.name}' (Driver) only allows vehicle scopes, not organizational nodes"
      end

    when :node_preferred
      # Admins deberían tener node scopes, vehicles es inusual
      if @vehicle_scopes.any? && @node_scopes.empty?
        @warnings << "Admin roles typically use organizational node scopes. Vehicle scopes are allowed but unusual."
      end

    when :both_allowed
      # Managers pueden tener ambos, pero es raro tener solo vehículos
      if @vehicle_scopes.any? && @node_scopes.empty?
        @warnings << "Manager roles typically use organizational node scopes. Consider adding node scopes for better access control."
      end
    end
  end

  # Validar combinaciones específicas de scopes
  def validate_scope_combinations
    # Si tiene ambos tipos de scope
    if @node_scopes.any? && @vehicle_scopes.any?
      # Verificar que el rol permita ambos
      unless @role.allows_node_scope? && @role.allows_vehicle_scope?
        @errors << "Role '#{@role.name}' does not allow both node and vehicle scopes simultaneously"
      else
        # Warning: tener ambos es válido pero puede ser redundante
        @warnings << "User has both node and vehicle scopes. Vehicle scopes may be redundant if nodes already cover those vehicles."
      end
    end
  end

  # Validar conflictos lógicos entre scopes
  def validate_scope_conflicts
    # Si solo tiene vehicle scopes sin node scopes
    if @vehicle_scopes.any? && @node_scopes.empty?
      # Verificar que no sea un rol que típicamente necesita node scopes
      if @role.slug.in?([ "tenant_admin", "tenant_manager" ])
        @warnings << "#{@role.name} typically requires organizational node scopes for proper access control"
      end
    end

    # Si tiene muchos vehicle scopes (>20), sugerir usar node scopes
    if @vehicle_scopes.size > 20
      @warnings << "Large number of vehicle scopes (#{@vehicle_scopes.size}). Consider using organizational node scopes instead for easier management."
    end
  end

  # ============================================
  # HELPERS
  # ============================================

  # Normalizar scopes a array de hashes
  def normalize_scopes(scopes)
    return [] if scopes.nil?
    return [] if scopes.empty?

    # Si ya es un array, devolverlo
    return scopes if scopes.is_a?(Array)

    # Si es un hash, convertirlo a array
    return [ scopes ] if scopes.is_a?(Hash)

    # Fallback
    []
  end

  # Construir resumen de la validación
  def build_validation_summary
    {
      role_name: @role.name,
      role_slug: @role.slug,
      role_config: {
        allows_node_scope: @role.allows_node_scope?,
        allows_vehicle_scope: @role.allows_vehicle_scope?,
        requires_any_scope: @role.requires_any_scope?
      },
      provided_scopes: {
        node_scopes_count: @node_scopes.size,
        vehicle_scopes_count: @vehicle_scopes.size,
        total_scopes: @node_scopes.size + @vehicle_scopes.size
      },
      validation_result: {
        is_valid: @errors.empty?,
        has_warnings: @warnings.any?,
        errors_count: @errors.size,
        warnings_count: @warnings.size
      }
    }
  end

  # ============================================
  # MÉTODOS PÚBLICOS ADICIONALES
  # ============================================

  public

  # Verificar si la combinación es válida (sin ejecutar validación completa)
  def valid?
    validate[:valid]
  end

  # Obtener solo los errores
  def error_messages
    validate[:errors]
  end

  # Obtener solo los warnings
  def warning_messages
    validate[:warnings]
  end

  # Verificar si hay warnings
  def has_warnings?
    validate[:warnings].any?
  end

  # Obtener explicación detallada de por qué es válido/inválido
  def detailed_explanation
    result = validate

    explanation = []
    explanation << "Role: #{@role.name} (#{@role.slug})"
    explanation << "Allows node scopes: #{@role.allows_node_scope? ? 'Yes' : 'No'}"
    explanation << "Allows vehicle scopes: #{@role.allows_vehicle_scope? ? 'Yes' : 'No'}"
    explanation << "Requires scopes: #{@role.requires_any_scope? ? 'Yes' : 'No'}"
    explanation << ""
    explanation << "Provided:"
    explanation << "- Node scopes: #{@node_scopes.size}"
    explanation << "- Vehicle scopes: #{@vehicle_scopes.size}"
    explanation << ""

    if result[:valid]
      explanation << "✅ Validation passed"
    else
      explanation << "❌ Validation failed"
      explanation << ""
      explanation << "Errors:"
      result[:errors].each { |error| explanation << "  - #{error}" }
    end

    if result[:warnings].any?
      explanation << ""
      explanation << "⚠️  Warnings:"
      result[:warnings].each { |warning| explanation << "  - #{warning}" }
    end

    explanation.join("\n")
  end
end
