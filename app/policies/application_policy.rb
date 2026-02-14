# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record, :context

  def initialize(user, record)
    @user = user
    @record = record
    @context = ActsAsTenant.current_tenant
  end

  # ============================================
  # MÉTODOS POR DEFECTO (RESTRICTIVOS)
  # ============================================

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  # ============================================
  # HELPERS DE AUTORIZACIÓN
  # ============================================

  # Verificar si el usuario es platform admin
  def platform_admin?
    user&.platform_admin?
  end

  # Verificar si el usuario es super admin
  def super_admin?
    user&.super_admin?
  end

  # Verificar si el usuario es support admin
  def support_admin?
    user&.support_admin?
  end

  # Verificar si el usuario tiene acceso al tenant del record
  def has_tenant_access?
    return true if platform_admin?
    return false unless record.respond_to?(:tenant_id)
    return false unless user

    user.has_tenant_access?(record.tenant_id)
  end

  # Verificar si el usuario es admin del tenant del record
  def tenant_admin?
    return true if platform_admin?
    return false unless context.present?
    return false unless user

    user.tenant_admin?(context.id)
  end

  # Verificar si el usuario es admin o manager del tenant
  def tenant_admin_or_manager?
    return true if platform_admin?
    return false unless context.present?
    return false unless user

    # CORREGIDO: usar tenant_admin? O tenant_manager?
    user.tenant_admin?(context.id) || user.tenant_manager?(context.id)
  end

  # Verificar si el usuario es el propietario del record
  def owner?
    return false unless record.respond_to?(:user_id)
    return false unless user

    record.user_id == user.id
  end

  # Verificar acceso basado en tenant del record (no en context)
  def has_record_tenant_access?
    return true if platform_admin?
    return false unless record.respond_to?(:tenant_id)
    return false unless user

    user.has_tenant_access?(record.tenant_id)
  end

  # ============================================
  # SCOPE
  # ============================================

  class Scope
    attr_reader :user, :scope, :context

    def initialize(user, scope)
      @user = user
      @scope = scope
      @context = ActsAsTenant.current_tenant
    end

    def resolve
      # Por defecto, no retornar nada (restrictivo)
      scope.none
    end

    private

    def platform_admin?
      user&.platform_admin?
    end

    def super_admin?
      user&.super_admin?
    end

    def support_admin?
      user&.support_admin?
    end
  end

  private

  # Extraer contexto del tenant actual
  def extract_context
    ActsAsTenant.current_tenant
  end
end
