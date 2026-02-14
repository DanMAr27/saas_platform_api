module Platform
  class TenantPolicy < ApplicationPolicy
    def index?
      super_admin?
    end

    def show?
      super_admin?
    end

    def create?
      super_admin?
    end

    def update?
      super_admin?
    end

    def destroy?
      super_admin?
    end

    def activate?
      super_admin?
    end

    def suspend?
      super_admin?
    end

    class Scope < ApplicationPolicy::Scope
      def resolve
        if user.super_admin?
          ::Tenant.all
        else
          ::Tenant.none
        end
      end
    end
  end
end
