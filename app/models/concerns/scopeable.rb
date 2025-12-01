# app/models/concerns/scopeable.rb
# Concern para gestionar la lógica de scopes según roles
# Define qué tipos de scopes requiere/permite cada rol

module Scopeable
  extend ActiveSupport::Concern

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Verificar si el rol permite node scopes
  def allows_node_scope?
    allows_node_scope == true
  end

  # Verificar si el rol permite vehicle scopes
  def allows_vehicle_scope?
    allows_vehicle_scope == true
  end

  # Verificar si el rol requiere algún tipo de scope
  def requires_any_scope?
    requires_any_scope == true
  end

  # Obtener el tipo de scope que permite este rol
  # Retorna: 'node', 'vehicle', o nil
  def scope_type
    return nil unless requires_any_scope?
    return "node" if allows_node_scope?
    return "vehicle" if allows_vehicle_scope?
    nil
  end

  # Obtener todos los tipos de scope permitidos (array)
  # Útil para roles futuros que puedan permitir múltiples tipos
  def allowed_scope_types
    types = []
    types << "node" if allows_node_scope?
    types << "vehicle" if allows_vehicle_scope?
    types
  end

  # Verificar si un scope es compatible con este rol
  def compatible_with_scope?(scope_type)
    case scope_type.to_s
    when "node"
      allows_node_scope?
    when "vehicle"
      allows_vehicle_scope?
    else
      false
    end
  end

  # Validar que los scopes proporcionados sean compatibles con el rol
  # Params:
  #   node_scopes: array de hashes con node scope data
  #   vehicle_scopes: array de hashes con vehicle scope data
  # Returns: { valid: true/false, errors: [] }
  def validate_scope_compatibility(node_scopes: nil, vehicle_scopes: nil)
    errors = []

    # Si el rol no requiere scopes
    unless requires_any_scope?
      if node_scopes.present? || vehicle_scopes.present?
        errors << "Role '#{name}' does not require or accept scopes"
      end
      return { valid: errors.empty?, errors: errors }
    end

    # Si el rol requiere scopes, debe tener al menos uno
    if node_scopes.blank? && vehicle_scopes.blank?
      errors << "Role '#{name}' requires at least one scope assignment"
      return { valid: false, errors: errors }
    end

    # Validar node scopes
    if node_scopes.present?
      unless allows_node_scope?
        errors << "Role '#{name}' does not accept node scopes"
      end
    end

    # Validar vehicle scopes
    if vehicle_scopes.present?
      unless allows_vehicle_scope?
        errors << "Role '#{name}' does not accept vehicle scopes"
      end
    end

    # Si el rol requiere un tipo específico, verificar que esté presente
    if allows_node_scope? && node_scopes.blank?
      errors << "Role '#{name}' requires at least one node scope"
    end

    if allows_vehicle_scope? && vehicle_scopes.blank?
      errors << "Role '#{name}' requires at least one vehicle scope"
    end

    { valid: errors.empty?, errors: errors }
  end

  # Descripción legible de los scopes requeridos
  def scope_requirements_description
    return "No scopes required (full access)" unless requires_any_scope?

    types = []
    types << "node access" if allows_node_scope?
    types << "vehicle access" if allows_vehicle_scope?

    "Requires: #{types.join(' or ')}"
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  class_methods do
    # Obtener roles que requieren node scopes
    def requiring_node_scopes
      where(allows_node_scope: true, requires_any_scope: true)
    end

    # Obtener roles que requieren vehicle scopes
    def requiring_vehicle_scopes
      where(allows_vehicle_scope: true, requires_any_scope: true)
    end

    # Obtener roles sin scopes (acceso total)
    def without_scope_requirements
      where(requires_any_scope: false)
    end

    # Obtener roles que requieren algún tipo de scope
    def with_scope_requirements
      where(requires_any_scope: true)
    end

    # Estadísticas de distribución de scopes
    def scope_distribution
      {
        total: count,
        requiring_scopes: with_scope_requirements.count,
        without_scopes: without_scope_requirements.count,
        node_scope_roles: requiring_node_scopes.count,
        vehicle_scope_roles: requiring_vehicle_scopes.count
      }
    end
  end

  # ============================================
  # VALIDACIONES
  # ============================================

  included do
    # Validar exclusividad: un rol no puede permitir ambos tipos simultáneamente
    # (según tu modelo de negocio: 1 rol = 1 tipo de scope)
    validate :validate_scope_exclusivity, if: :requires_any_scope?

    # Validar coherencia: si requiere scopes, debe permitir al menos un tipo
    validate :validate_scope_coherence, if: :requires_any_scope?
  end

  private

  def validate_scope_exclusivity
    if allows_node_scope? && allows_vehicle_scope?
      errors.add(:base, "Role cannot allow both node and vehicle scopes simultaneously")
    end
  end

  def validate_scope_coherence
    unless allows_node_scope? || allows_vehicle_scope?
      errors.add(:base, "Role requires scopes but doesn't allow any scope type")
    end
  end
end
