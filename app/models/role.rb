# frozen_string_literal: true

# Modelo de Role
# Catálogo de roles para todos los contextos del sistema
# Un rol define un conjunto de permisos en un contexto específico
# NUEVO: Con soporte para scope flags (allows_node_scope, allows_vehicle_scope, requires_any_scope)

class Role < ApplicationRecord
  # ============================================
  # CONCERNS
  # ============================================
  include Auditable  # PaperTrail para auditoría
  include Scopeable  # 🆕 NUEVO: Lógica de scopes

  # ============================================
  # CONSTANTES
  # ============================================

  # Contextos disponibles
  CONTEXTS = %w[platform tenant].freeze

  # Slugs de roles del sistema (no se pueden borrar)
  SYSTEM_ROLE_SLUGS = %w[
    super_admin
    support_admin
    tenant_admin
    tenant_manager
    tenant_driver
  ].freeze

  # ============================================
  # ASSOCIATIONS
  # ============================================

  has_many :platform_memberships, dependent: :restrict_with_error
  has_many :tenant_memberships, dependent: :restrict_with_error
  has_many :users, through: :platform_memberships

  # ============================================
  # VALIDATIONS
  # ============================================

  validates :name, presence: true, length: { maximum: 100 }
  validates :slug,
            presence: true,
            uniqueness: { case_sensitive: false },
            length: { maximum: 100 },
            format: {
              with: /\A[a-z0-9]+(?:_[a-z0-9]+)*\z/,
              message: "only allows lowercase letters, numbers, and underscores"
            }

  validates :context, presence: true, inclusion: { in: CONTEXTS }
  validates :priority, presence: true, numericality: { only_integer: true }

  # 🆕 NUEVO: Validaciones de scope (vienen del concern Scopeable)
  # - validate_scope_exclusivity
  # - validate_scope_coherence

  # Validación custom: no borrar roles del sistema
  validate :cannot_destroy_system_role, on: :destroy, if: :is_system?

  # ============================================
  # CALLBACKS
  # ============================================

  before_validation :generate_slug, if: -> { slug.blank? }
  before_destroy :prevent_system_role_deletion

  # ============================================
  # SCOPES
  # ============================================

  scope :platform_roles, -> { where(context: "platform") }
  scope :tenant_roles, -> { where(context: "tenant") }
  scope :system_roles, -> { where(is_system: true) }
  scope :custom_roles, -> { where(is_system: false) }

  # 🆕 DEPRECATED: Mantener por compatibilidad pero usar los del concern
  scope :requires_scope, -> { where(requires_any_scope: true) }

  scope :by_priority, -> { order(priority: :asc, name: :asc) }

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Verificar contexto
  def platform_role?
    context == "platform"
  end

  def tenant_role?
    context == "tenant"
  end

  # Verificar si es rol específico
  def super_admin?
    slug == "super_admin"
  end

  def support_admin?
    slug == "support_admin"
  end

  def tenant_admin?
    slug == "tenant_admin"
  end

  def tenant_manager?
    slug == "tenant_manager"
  end

  def tenant_driver?
    slug == "tenant_driver"
  end

  # 🆕 DEPRECATED: Mantener por compatibilidad pero usar requires_any_scope?
  def requires_scope?
    requires_any_scope?
  end

  # Display
  def display_name
    "#{name} (#{context})"
  end

  def to_s
    name
  end

  # 🆕 MEJORADO: Incluir info de scopes
  def full_description
    desc = "#{display_name}"
    desc += " - #{scope_requirements_description}" if tenant_role?
    desc
  end

  # Estadísticas
  def usage_count
    if platform_role?
      platform_memberships.count
    else
      tenant_memberships.count
    end
  end

  # 🆕 NUEVO: Información completa del rol para API
  def to_detail_hash
    {
      id: id,
      slug: slug,
      name: name,
      context: context,
      description: description,
      is_system: is_system?,
      priority: priority,
      scope_config: {
        requires_any_scope: requires_any_scope?,
        allows_node_scope: allows_node_scope?,
        allows_vehicle_scope: allows_vehicle_scope?,
        scope_type: scope_type,
        description: scope_requirements_description
      },
      usage_count: usage_count
    }
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  class << self
    # Encontrar rol por slug
    def find_by_slug!(slug)
      find_by!(slug: slug)
    end

    # Roles para un contexto específico
    def for_context(context)
      where(context: context).by_priority
    end

    # 🆕 MEJORADO: Estadísticas con info de scopes
    def stats
      base_stats = {
        total: count,
        platform: platform_roles.count,
        tenant: tenant_roles.count,
        system: system_roles.count,
        custom: custom_roles.count
      }

      # Agregar distribución de scopes
      base_stats.merge(scope_distribution)
    end

    # 🆕 NUEVO: Obtener roles disponibles para asignación
    # con información de sus requerimientos de scope
    def available_for_assignment(context:)
      for_context(context).map do |role|
        {
          slug: role.slug,
          name: role.name,
          requires_scopes: role.requires_any_scope?,
          allows_node_scope: role.allows_node_scope?,
          allows_vehicle_scope: role.allows_vehicle_scope?,
          description: role.scope_requirements_description
        }
      end
    end
  end

  private

  # ============================================
  # PRIVATE METHODS
  # ============================================

  # Generar slug desde el nombre
  def generate_slug
    return if name.blank?

    base_slug = name.parameterize.underscore
    generated_slug = base_slug
    counter = 1

    while Role.exists?(slug: generated_slug)
      generated_slug = "#{base_slug}_#{counter}"
      counter += 1
    end

    self.slug = generated_slug
  end

  # Prevenir eliminación de roles del sistema
  def prevent_system_role_deletion
    if is_system?
      errors.add(:base, "Cannot delete system role")
      throw :abort
    end
  end

  # Validación custom
  def cannot_destroy_system_role
    if is_system?
      errors.add(:base, "Cannot delete system role")
    end
  end
end
