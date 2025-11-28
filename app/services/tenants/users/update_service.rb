# app/services/tenant/users/update_service.rb

module Tenants
  module Users
    class UpdateService
      include ServiceResultHelper

      attr_reader :user, :params, :current_user

      def initialize(user:, params:, current_user:)
        @user = user
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        # Validar parámetros
        validation_result = validate_params
        return validation_result if validation_result.failure?

        # Actualizar usuario
        update_params = params.slice(
          :first_name,
          :last_name,
          :phone,
          :avatar_url
        ).compact

        if user.update(update_params)
          success(
            data: user,
            message: "User updated successfully"
          )
        else
          failure(errors: user.errors.full_messages)
        end
      rescue StandardError => e
        Rails.logger.error("[UpdateUserService] Error: #{e.message}")
        failure(errors: "Failed to update user")
      end

      private

      def validate_params
        # Validar formato de teléfono si se proporciona
        if params[:phone].present?
          unless params[:phone] =~ /\A\+?[\d\s\-\(\)]+\z/
            return failure(errors: "Invalid phone format")
          end
        end

        success(data: { valid: true })
      end
    end
  end
end
