# frozen_string_literal: true

module Platform
  module Tenants
    class CreateService
      include ServiceResultHelper

      attr_reader :params, :current_user

      def initialize(params:, current_user: nil)
        @params = params
        @current_user = current_user
      end

      def self.call(**args)
        new(**args).call
      end

      def call
        validation_result = validate_params
        return validation_result if validation_result.failure?

        ActiveRecord::Base.transaction do
          tenant = create_tenant
          return failure(errors: tenant.errors.full_messages) unless tenant.persisted?

          admin_user = find_or_create_admin_user
          return admin_user if admin_user.failure?

          membership = create_admin_membership(tenant, admin_user.data)
          return membership if membership.failure?

          set_paper_trail_context(admin_user.data)

          success(
            data: {
              tenant: tenant,
              admin: admin_user.data,
              membership: membership.data
            },
            message: "Tenant created successfully"
          )
        end
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      rescue StandardError => e
        Rails.logger.error("[CreateTenantService] Error: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n"))
        failure(errors: "Failed to create tenant")
      end

      private

      def validate_params
        required_fields = %i[name admin_email admin_first_name admin_last_name]
        missing_fields = required_fields.select { |f| params[f].blank? }
        return failure(errors: "Missing required fields: #{missing_fields.join(', ')}") if missing_fields.any?

        return failure(errors: "Invalid admin email format") unless params[:admin_email] =~ URI::MailTo::EMAIL_REGEXP
        if params[:admin_password].present? && params[:admin_password].length < 8
          return failure(errors: "Admin password must be at least 8 characters")
        end

        success(data: { valid: true })
      end

      def create_tenant
        tenant_params = {
          name: params[:name],
          slug: params[:slug],
          domain: params[:domain],
          legal_name: params[:legal_name],
          tax_id: params[:tax_id],
          address: params[:address],
          city: params[:city],
          state: params[:state],
          postal_code: params[:postal_code],
          country: params[:country] || "ES",
          timezone: params[:timezone] || "Europe/Madrid",
          locale: params[:locale] || "es",
          currency: params[:currency] || "EUR",
          status: params[:status] || "trial",
          plan: params[:plan] || "trial",
          created_by: current_user&.id
        }

        Tenant.create!(tenant_params.compact)
      end

      def find_or_create_admin_user
        existing_user = User.find_by(email: params[:admin_email])
        if existing_user
          return failure(errors: "Admin user account is deactivated") if existing_user.deleted?
          return success(data: existing_user)
        end

        user_params = {
          email: params[:admin_email],
          first_name: params[:admin_first_name],
          last_name: params[:admin_last_name],
          phone: params[:admin_phone],
          password: params[:admin_password] || generate_random_password,
          password_confirmation: params[:admin_password] || generate_random_password,
          email_verified_at: Time.current
        }

        user = User.create!(user_params)
        success(data: user)
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      end

      def create_admin_membership(tenant, admin_user)
        admin_role = Role.find_by!(slug: "tenant_admin")

        membership_params = {
          user: admin_user,
          tenant: tenant,
          role_id: admin_role.id,
          is_primary_admin: true,
          status: "active",
          is_default: true,
          created_by: current_user&.id
        }

        membership = TenantMembership.create!(membership_params)
        success(data: membership)
      rescue ActiveRecord::RecordInvalid => e
        failure(errors: e.record.errors.full_messages)
      end

      def generate_random_password
        SecureRandom.urlsafe_base64(12)
      end

      def set_paper_trail_context(user)
        PaperTrail.request.whodunnit = user.id
        PaperTrail.request.controller_info = {
          metadata: { performed_action: "create_tenant" }
        }
      end
    end
  end
end
