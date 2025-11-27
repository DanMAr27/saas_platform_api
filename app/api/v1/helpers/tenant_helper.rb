# app/api/v1/helpers/tenant_helper.rb

module V1
  module Helpers
    module TenantHelper
      # Obtener el tenant actual del contexto
      # @return [Tenant, nil]
      def current_tenant
        ActsAsTenant.current_tenant
      end

      # Verificar si hay un tenant en el contexto
      # @return [Boolean]
      def tenant_context?
        current_tenant.present?
      end

      # Forzar que haya un tenant en el contexto
      # Platform admins no necesitan tenant context
      def require_tenant!
        # Platform admins con contexto de plataforma no necesitan tenant
        return if current_user&.platform_admin? && platform_context?

        return if tenant_context?

        error!({
          success: false,
          error: {
            message: "Tenant context is required",
            status: 400,
            timestamp: Time.current.iso8601
          }
        }, 400)
      end

      # Verificar que el usuario tenga acceso al tenant actual
      # Platform admins siempre tienen acceso
      def verify_tenant_access!
        authenticate! # Primero asegurar que esté autenticado

        # Platform admins con contexto de plataforma tienen acceso a todo
        return if current_user.platform_admin? && platform_context?

        require_tenant! # Asegurar que haya tenant

        unless current_user.has_tenant_access?(current_tenant.id)
          error!({
            success: false,
            error: {
              message: "Access denied to this tenant",
              status: 403,
              timestamp: Time.current.iso8601
            }
          }, 403)
        end
      end

      # Obtener el rol del usuario actual en el tenant actual
      # @return [String, nil]
      def current_user_role
        return "platform_admin" if current_user&.platform_admin? && platform_context?
        return nil unless authenticated? && tenant_context?

        current_user.tenant_role(current_tenant.id)
      end

      # Verificar si el usuario es admin del tenant actual
      # @return [Boolean]
      def tenant_admin?
        return false if platform_context? # En contexto platform, no aplica tenant_admin
        return false unless authenticated? && tenant_context?

        current_user.tenant_admin?(current_tenant.id)
      end

      # Verificar si el usuario es manager del tenant actual
      # @return [Boolean]
      def tenant_manager?
        return false if platform_context?
        return false unless authenticated? && tenant_context?

        current_user.tenant_manager?(current_tenant.id)
      end

      # Verificar si el usuario es driver del tenant actual
      # @return [Boolean]
      def tenant_driver?
        return false if platform_context?
        return false unless authenticated? && tenant_context?

        current_user.tenant_driver?(current_tenant.id)
      end

      # Forzar que el usuario sea admin del tenant
      def require_tenant_admin!
        # En contexto platform, verificar platform_admin
        if platform_context?
          unless current_user&.platform_admin?
            error!({
              success: false,
              error: {
                message: "Platform admin role required",
                status: 403,
                timestamp: Time.current.iso8601
              }
            }, 403)
          end
          return
        end

        verify_tenant_access!

        unless tenant_admin?
          error!({
            success: false,
            error: {
              message: "Admin role required",
              status: 403,
              timestamp: Time.current.iso8601
            }
          }, 403)
        end
      end

      # Forzar que el usuario sea admin o manager del tenant
      def require_tenant_admin_or_manager!
        # En contexto platform, verificar platform_admin
        if platform_context?
          unless current_user&.platform_admin?
            error!({
              success: false,
              error: {
                message: "Platform admin role required",
                status: 403,
                timestamp: Time.current.iso8601
              }
            }, 403)
          end
          return
        end

        verify_tenant_access!

        unless tenant_admin? || tenant_manager?
          error!({
            success: false,
            error: {
              message: "Admin or Manager role required",
              status: 403,
              timestamp: Time.current.iso8601
            }
          }, 403)
        end
      end

      # Información del tenant actual para respuestas
      # @return [Hash]
      def current_tenant_info
        return nil unless tenant_context?

        {
          id: current_tenant.id,
          name: current_tenant.name,
          slug: current_tenant.slug,
          status: current_tenant.status,
          plan: current_tenant.plan
        }
      end

      # Establecer tenant manualmente (útil para platform admins)
      def set_tenant(tenant)
        ActsAsTenant.current_tenant = tenant
      end

      # Ejecutar bloque sin tenant context
      def without_tenant
        ActsAsTenant.without_tenant do
          yield
        end
      end

      # Obtener tenant desde parámetros o contexto
      # Útil para endpoints donde platform admins pueden especificar tenant_id
      def tenant_from_params_or_context
        if params[:tenant_id]
          ::Tenant.find(params[:tenant_id])
        else
          current_tenant
        end
      end

      # Validar acceso a un tenant específico
      def validate_tenant_access!(tenant)
        # Platform admins con contexto platform tienen acceso a todo
        return if current_user.platform_admin? && platform_context?

        unless current_user.has_tenant_access?(tenant.id)
          error!({
            success: false,
            error: {
              message: "Access denied to this tenant",
              status: 403,
              timestamp: Time.current.iso8601
            }
          }, 403)
        end
      end
    end
  end
end
