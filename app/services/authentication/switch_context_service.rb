# frozen_string_literal: true

module Services
  module Authentication
    # Servicio para cambiar de contexto sin hacer logout
    # Permite a usuarios con múltiples contextos cambiar entre ellos
    #
    # Uso:
    #   result = SwitchContextService.call(
    #     current_user: user,
    #     current_token: 'current_jwt_token',
    #     new_context_type: 'tenant',
    #     new_tenant_id: 2
    #   )
    #
    # Flujo:
    # 1. Valida que el usuario tenga acceso al nuevo contexto
    # 2. Revoca el token actual
    # 3. Genera nuevo token con el nuevo contexto

    class SwitchContextService
      include ServiceResultHelper

      attr_reader :current_user, :current_token, :new_context_type, :new_tenant_id

      def initialize(current_user:, current_token:, new_context_type:, new_tenant_id: nil)
        @current_user = current_user
        @current_token = current_token
        @new_context_type = new_context_type
        @new_tenant_id = new_tenant_id
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar parámetros
        return failure(errors: "User is required") unless current_user
        return failure(errors: "Current token is required") if current_token.blank?
        return failure(errors: "New context type is required") if new_context_type.blank?

        # Validar que el usuario esté activo
        unless current_user.active?
          return failure(errors: "User account is not active")
        end

        # Obtener contextos disponibles
        contexts_query = AvailableContextsQuery.new(current_user)
        available_contexts = contexts_query.call

        # Buscar el nuevo contexto solicitado
        new_context = find_requested_context(available_contexts)
        unless new_context
          return failure(
            errors: "Requested context is not available",
            meta: {
              available_contexts: available_contexts.map { |c|
                { type: c[:type], tenant_id: c[:tenant_id], display_name: c[:display_name] }
              }
            }
          )
        end

        # Validar que sea diferente al contexto actual
        if same_as_current_context?(new_context)
          return failure(errors: "Already in the requested context")
        end

        # Revocar token actual
        revoke_result = revoke_current_token
        if revoke_result.failure?
          Rails.logger.warn("[SwitchContext] Failed to revoke current token: #{revoke_result.errors}")
          # No bloqueamos si falla la revocación, pero lo registramos
        end

        # Generar nuevo token con el nuevo contexto
        new_token_data = JwtEncoder.encode_with_metadata(
          user: current_user,
          context: new_context[:context],
          tenant_id: new_context[:tenant_id]
        )

        # Actualizar tenant por defecto si es tenant context
        update_default_tenant(new_context) if new_context[:type] == "tenant"

        # Auditoría
        log_context_switch(new_context)

        # Retornar éxito
        success(
          data: {
            token: new_token_data[:token],
            token_type: new_token_data[:token_type],
            expires_at: new_token_data[:expires_at],
            expires_in: new_token_data[:expires_in],
            previous_context: current_context_info,
            new_context: build_context_response(new_context),
            user: user_data(new_context)
          },
          message: "Context switched successfully"
        )
      end

      private

      # Buscar el contexto solicitado
      def find_requested_context(available_contexts)
        case new_context_type
        when "platform"
          available_contexts.find { |c| c[:type] == "platform" }
        when "tenant"
          return nil if new_tenant_id.blank?
          available_contexts.find { |c| c[:type] == "tenant" && c[:tenant_id] == new_tenant_id.to_i }
        else
          nil
        end
      end

      # Verificar si es el mismo contexto actual
      def same_as_current_context?(new_context)
        current_payload = decode_current_token
        return false unless current_payload

        if new_context[:type] == "platform"
          current_payload[:context] == "platform"
        else
          current_payload[:context] == "tenant" &&
            current_payload[:tenant_id] == new_context[:tenant_id]
        end
      end

      # Decodificar token actual
      def decode_current_token
        result = JwtDecoder.decode(current_token)
        result.success? ? result.data : nil
      end

      # Obtener información del contexto actual
      def current_context_info
        payload = decode_current_token
        return nil unless payload

        {
          context: payload[:context],
          tenant_id: payload[:tenant_id]
        }
      end

      # Revocar token actual
      def revoke_current_token
        payload = decode_current_token
        return success(data: { revoked: false }) unless payload

        JwtBlacklist.create!(
          jti: payload[:jti],
          user_id: current_user.id,
          exp: Time.at(payload[:exp].to_i)
        )

        success(data: { revoked: true })
      rescue ActiveRecord::RecordInvalid => e
        # Si ya existe en blacklist, continuar
        if e.message.include?("Jti has already been taken")
          return success(data: { revoked: false })
        end

        failure(errors: "Failed to revoke current token")
      rescue StandardError => e
        Rails.logger.error("[SwitchContext] Error revoking token: #{e.message}")
        failure(errors: "Failed to revoke current token")
      end

      # Actualizar tenant por defecto
      def update_default_tenant(new_context)
        return unless new_context[:type] == "tenant"

        # Remover default de otras membresías
        current_user.tenant_memberships
                    .where(is_default: true)
                    .where.not(tenant_id: new_context[:tenant_id])
                    .update_all(is_default: false)

        # Establecer nuevo default
        membership = current_user.tenant_memberships
                                 .find_by(tenant_id: new_context[:tenant_id])
        membership&.update_column(:is_default, true)
      rescue StandardError => e
        Rails.logger.error("[SwitchContext] Error updating default tenant: #{e.message}")
        # No bloqueamos si falla esto
      end

      # Logging de auditoría
      def log_context_switch(new_context)
        Rails.logger.info(
          "[SwitchContext] User #{current_user.id} switched to " \
          "#{new_context[:type]}:#{new_context[:tenant_id] || 'platform'}"
        )

        # TODO: Crear registro de auditoría en tabla separada si se requiere
        # AuditLog.create!(
        #   user_id: current_user.id,
        #   action: 'context_switch',
        #   details: { to_context: new_context }
        # )
      end

      # Construir respuesta del contexto
      def build_context_response(context)
        {
          type: context[:type],
          context: context[:context],
          tenant_id: context[:tenant_id],
          tenant_name: context[:tenant_name],
          role: context[:role],
          role_name: context[:role_name],
          display_name: context[:display_name]
        }
      end

      # Datos del usuario para respuesta
      def user_data(context)
        {
          id: current_user.id,
          email: current_user.email,
          first_name: current_user.first_name,
          last_name: current_user.last_name,
          full_name: current_user.full_name,
          avatar_url: current_user.avatar_url,
          context: context[:context],
          tenant_id: context[:tenant_id],
          role: context[:role],
          role_name: context[:role_name]
        }
      end
    end
  end
end
