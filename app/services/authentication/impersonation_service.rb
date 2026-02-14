# app/services/authentication/impersonation_service.rb

module Authentication
  class ImpersonationService
    include ServiceResultHelper

    attr_reader :support_user, :target_user, :reason

    def initialize(support_user:, target_user:, reason:)
      @support_user = support_user
      @target_user = target_user
      @reason = reason
    end

    def self.call(**args)
      new(**args).call
    end

    def call
      # Validate inputs
      return failure(errors: [ "Support user is required" ]) if support_user.blank?
      return failure(errors: [ "Target user is required" ]) if target_user.blank?
      return failure(errors: [ "Reason is required" ]) if reason.blank?

      # Ensure support admin has impersonation privileges
      unless support_admin_can_impersonate?
        return failure(errors: [ "Not authorized to impersonate" ])
      end

      # Generate a session token suitable for context selection (step 2)
      session_token = generate_session_token(target_user, support_user)

      Rails.logger.info "[Impersonation] Support User #{support_user.id} (#{support_user.email}) is impersonating Target User #{target_user.id} (#{target_user.email}). Reason: #{reason}"

      success(
        data: { token: session_token },
        message: "Impersonation session started"
      )
    end

    private

    def support_admin_can_impersonate?
      support_user.support_admin? && support_user.platform_membership&.can_impersonate?
    end

    def generate_session_token(user, impersonator)
      payload = {
        user_id: user.id,
        impersonator_id: impersonator.id,
        email: user.email,
        purpose: "context_selection",
        exp: 5.minutes.from_now.to_i,
        iat: Time.current.to_i
      }

      JWT.encode(payload, session_secret, "HS256")
    end

    def session_secret
      Rails.application.credentials.dig(:session_secret_key) ||
        ENV.fetch("SESSION_SECRET_KEY", Rails.application.credentials.secret_key_base)
    end
  end
end
