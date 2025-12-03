# app/services/platform/tenants/create_service.rb

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
        validation = validate_params
        return validation if validation.failure?

        begin
          tenant = nil
          admin_user = nil
          membership = nil

          ActiveRecord::Base.transaction do
            tenant = create_tenant!
            admin_user = create_admin_user!
            membership = create_admin_membership!(tenant, admin_user)

            set_paper_trail_context(admin_user)
          end

          success(
            data: {
              tenant: tenant,
              admin: admin_user,
              membership: membership
            },
            message: "Tenant created successfully"
          )

        rescue ActiveRecord::RecordInvalid => e
          failure(errors: e.record.errors.full_messages)
        rescue StandardError => e
          Rails.logger.error("[CreateTenantService] Error: #{e.message}")
          Rails.logger.error(e.backtrace.join("\n"))
          failure(errors: "Failed to create tenant: #{e.message}")
        end
      end

      private

      # --------------------------------------------------
      # VALIDACIONES
      # --------------------------------------------------
      def validate_params
        required = %i[name admin_email admin_first_name admin_last_name]
        missing = required.select { |f| params[f].blank? }

        return failure(errors: "Missing required fields: #{missing.join(', ')}") if missing.any?

        unless params[:admin_email] =~ URI::MailTo::EMAIL_REGEXP
          return failure(errors: "Invalid admin email format")
        end

        if params[:admin_password].present? && params[:admin_password].length < 8
          return failure(errors: "Admin password must be at least 8 characters")
        end

        success(data: true)
      end

      # --------------------------------------------------
      # CREACIÓN DE TENANT
      # --------------------------------------------------
      def create_tenant!
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
        }.compact

        Tenant.create!(tenant_params)
      end

      # --------------------------------------------------
      # CREACIÓN DEL ADMIN USER
      # --------------------------------------------------
      def create_admin_user!
        existing_user = User.find_by(email: params[:admin_email])

        if existing_user
          raise ActiveRecord::RecordInvalid.new(existing_user),
                "Admin user account is deactivated" if existing_user.deleted?

          return existing_user
        end

        generated_pass = params[:admin_password].presence || generate_random_password

        user_params = {
          email: params[:admin_email],
          first_name: params[:admin_first_name],
          last_name: params[:admin_last_name],
          phone: params[:admin_phone],
          password: generated_pass,
          password_confirmation: generated_pass,
          email_verified_at: Time.current
        }

        User.create!(user_params)
      end

      # --------------------------------------------------
      # CREACIÓN MEMBERSHIP
      # --------------------------------------------------
      def create_admin_membership!(tenant, admin_user)
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

        TenantMembership.create!(membership_params)
      end

      # --------------------------------------------------
      # HELPERS
      # --------------------------------------------------
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
