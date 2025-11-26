# app/api/v1/helpers/authorization_helper.rb

module V1
  module Helpers
    module AuthorizationHelper
      # Incluir Pundit
      include Pundit::Authorization

      # Usuario actual para Pundit (requerido por Pundit)
      def pundit_user
        current_user
      end

      # Autorizar acción con Pundit
      # @param record [Object] Registro a autorizar
      # @param query [Symbol] Acción a autorizar (ej: :show?, :create?)
      # @param policy_class [Class] Clase de política específica (opcional)
      def authorize!(record, query = nil, policy_class: nil)
        # Si no hay query, inferir desde el método HTTP
        query ||= infer_policy_query

        # Obtener la política
        policy_instance = if policy_class
          policy_class.new(pundit_user, record)
        else
          policy(record)
        end

        # Verificar autorización
        unless policy_instance.public_send(query)
          error!({
            success: false,
            error: {
              message: "You are not authorized to perform this action",
              status: 403,
              timestamp: Time.current.iso8601
            }
          }, 403)
        end

        true
      end

      # Autorizar scope (para index/list)
      # @param scope [ActiveRecord::Relation]
      # @param policy_scope_class [Class] Clase de policy scope específica (opcional)
      def policy_scope(scope, policy_scope_class: nil)
        if policy_scope_class
          policy_scope_class.new(pundit_user, scope).resolve
        else
          # Evitar conflictos con namespaces
          # Extraer el nombre de la clase modelo sin namespace
          model_class = scope.respond_to?(:model) ? scope.model : scope
          policy_class_name = "#{model_class.name}Policy"

          begin
            policy_class = policy_class_name.constantize
            policy_class::Scope.new(pundit_user, scope).resolve
          rescue NameError => e
            Rails.logger.error("[Pundit] Policy not found: #{policy_class_name}")
            raise Pundit::NotDefinedError, "unable to find policy `#{policy_class_name}` for `#{scope.inspect}`"
          end
        end
      end

      # Obtener política para un registro
      # @param record [Object]
      # @param policy_class [Class] Clase de política específica (opcional)
      # @return [Policy]
      def policy(record, policy_class: nil)
        if policy_class
          policy_class.new(pundit_user, record)
        else
          # Determinar la clase de la política basándose en el record
          model_class = record.is_a?(Class) ? record : record.class
          policy_class_name = "#{model_class.name}Policy"

          begin
            policy_class = policy_class_name.constantize
            policy_class.new(pundit_user, record)
          rescue NameError => e
            Rails.logger.error("[Pundit] Policy not found: #{policy_class_name}")
            raise Pundit::NotDefinedError, "unable to find policy `#{policy_class_name}` for `#{record.inspect}`"
          end
        end
      end

      # Verificar si está autorizado sin lanzar error
      # @param record [Object]
      # @param query [Symbol]
      # @return [Boolean]
      def authorized?(record, query = nil, policy_class: nil)
        query ||= infer_policy_query

        policy_instance = if policy_class
          policy_class.new(pundit_user, record)
        else
          policy(record)
        end

        policy_instance.public_send(query)
      rescue Pundit::NotAuthorizedError, Pundit::NotDefinedError
        false
      end

      # Helpers específicos de roles

      def require_super_admin!
        authenticate!

        unless current_user.super_admin?
          error!({
            success: false,
            error: {
              message: "Super Admin role required",
              status: 403,
              timestamp: Time.current.iso8601
            }
          }, 403)
        end
      end

      def require_platform_admin!
        authenticate!

        unless current_user.platform_admin?
          error!({
            success: false,
            error: {
              message: "Platform Admin role required",
              status: 403,
              timestamp: Time.current.iso8601
            }
          }, 403)
        end
      end

      def require_support_admin!
        authenticate!

        unless current_user.support_admin?
          error!({
            success: false,
            error: {
              message: "Support Admin role required",
              status: 403,
              timestamp: Time.current.iso8601
            }
          }, 403)
        end
      end

      private

      # Inferir query de política desde método HTTP
      def infer_policy_query
        case request.request_method
        when "GET"
          # Si es lista (sin ID en params) usar index?, sino show?
          params[:id].present? ? :show? : :index?
        when "POST"
          :create?
        when "PUT", "PATCH"
          :update?
        when "DELETE"
          :destroy?
        else
          :show? # Por defecto
        end
      end
    end
  end
end
