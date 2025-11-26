# frozen_string_literal: true

# Query para obtener todos los contextos disponibles para un usuario
# Usado tanto en login como en endpoints que necesiten listar contextos
#
# Uso:
#   contexts = AvailableContextsQuery.new(user).call
#
# Retorna un array de hashes con:
# - Platform contexts: { type: 'platform', role: 'super_admin', ... }
# - Tenant contexts: { type: 'tenant', tenant_id: 1, tenant_name: '...', role: 'admin', ... }

class AvailableContextsQuery
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    contexts = []

    # Agregar contexto platform si existe
    if platform_context = get_platform_context
      contexts << platform_context
    end

    # Agregar contextos tenant
    contexts += get_tenant_contexts

    contexts
  end

  # Verificar si el usuario tiene múltiples contextos
  def multiple_contexts?
    call.size > 1
  end

  # Obtener contexto por defecto (si existe)
  def default_context
    # Si tiene platform membership, ese es el default
    return get_platform_context if user.platform_membership.present?

    # Si tiene un tenant default, ese es
    default_membership = user.tenant_memberships.find_by(is_default: true, status: "active")
    return build_tenant_context(default_membership) if default_membership

    # Si solo tiene uno, ese es el default
    contexts = call
    return contexts.first if contexts.size == 1

    nil
  end

  private

  # Obtener contexto de plataforma
  def get_platform_context
    return nil unless user.platform_membership.present?
    return nil if user.platform_membership.deleted?

    membership = user.platform_membership

    {
      type: "platform",
      role_id: membership.role_id,
      role: membership.role.slug,
      role_name: membership.role.name,
      context: "platform",
      tenant_id: nil,
      display_name: "Platform - #{membership.role.name}",
      is_default: true, # Platform siempre es default si existe
      created_at: membership.created_at.iso8601,
      # Metadata adicional
      can_impersonate: membership.can_impersonate?,
      mfa_required: membership.support_admin?
    }
  end

  # Obtener contextos de tenant
  def get_tenant_contexts
    user.tenant_memberships
        .active
        .kept
        .includes(:tenant, :role)
        .where(tenants: { deleted_at: nil }) # Solo tenants activos
        .map { |membership| build_tenant_context(membership) }
  end

  # Construir hash de contexto tenant
  def build_tenant_context(membership)
    {
      type: "tenant",
      tenant_id: membership.tenant_id,
      tenant_name: membership.tenant.name,
      tenant_slug: membership.tenant.slug,
      tenant_status: membership.tenant.status,
      role_id: membership.role_id,
      role: membership.role&.slug || membership.role, # Fallback a string si no hay role_id
      role_name: membership.role&.name || membership.role.titleize,
      is_primary_admin: membership.is_primary_admin?,
      is_default: membership.is_default?,
      membership_status: membership.status,
      context: "tenant",
      display_name: "#{membership.tenant.name} - #{membership.role&.name || membership.role.titleize}",
      created_at: membership.created_at.iso8601,
      # Metadata adicional
      tenant_trial: membership.tenant.trial?,
      tenant_trial_days_remaining: membership.tenant.trial? ? membership.tenant.trial_days_remaining : nil
    }
  end
end
