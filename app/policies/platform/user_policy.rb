module Platform
  class UserPolicy < ApplicationPolicy
    def index?
      super_admin? || support_admin?
    end

    def show?
      super_admin? # Para soporte: buscar user por ID/Email
    end

    def update?
      super_admin? # Para desbloqueo de cuenta / reset password global
    end

    # Crear/Borrar usuarios de tenants prohibido para SuperAdmin
    # Debe hacerse a través de la gestión del tenant
    def create?; false; end
    def destroy?; false; end

    # Acciones específicas de soporte
    def impersonate?
      support_admin? && user.platform_membership&.can_impersonate?
    end

    def unlock?
      super_admin?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        if user.super_admin?
          ::User.all
        else
          ::User.none
        end
      end
    end
  end
end
