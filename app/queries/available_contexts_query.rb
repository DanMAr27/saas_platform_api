# app/queries/available_contexts_query.rb

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
      # 🔥 NUEVO: ID único para platform
      id: "platform",
      type: "platform",
      context: "platform",

      # IDs relevantes
      membership_id: membership.id,
      tenant_id: nil,

      # Info del rol
      role_id: membership.role_id,
      role: membership.role.slug,
      role_name: membership.role.name,

      # Display
      display_name: "Platform - #{membership.role.name}",

      # Metadata
      is_default: true,
      created_at: membership.created_at.iso8601,
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
        .where(tenants: { deleted_at: nil })
        .map { |membership| build_tenant_context(membership) }
  end

  # Construir hash de contexto tenant
  def build_tenant_context(membership)
    {
      # 🔥 NUEVO: ID único basado en membership_id
      id: "membership_#{membership.id}",
      type: "tenant",
      context: "tenant",

      # IDs relevantes
      membership_id: membership.id,
      tenant_id: membership.tenant_id,

      # Info del tenant
      tenant_name: membership.tenant.name,
      tenant_slug: membership.tenant.slug,
      tenant_status: membership.tenant.status,
      tenant_logo: membership.tenant.logo_url, # Si existe este campo

      # Info del rol
      role_id: membership.role_id,
      role: membership.role.slug,
      role_name: membership.role.name,

      # Display
      display_name: "#{membership.tenant.name} - #{membership.role.name}",

      # Metadata
      is_primary_admin: membership.is_primary_admin?,
      is_default: membership.is_default?,
      membership_status: membership.status,
      created_at: membership.created_at.iso8601,

      # Info del tenant (plan/trial)
      tenant_trial: membership.tenant.trial?,
      tenant_trial_days_remaining: membership.tenant.trial? ? membership.tenant.trial_days_remaining : nil
    }
  end
end
