# app/api/authentication_api.rb

module V1
  # API de Autenticación
  # Maneja login, logout, refresh de tokens y validación
  class AuthenticationApi < Grape::API
    helpers Helpers::AuthenticationHelper

    resource :auth do
      # ============================================
      # LOGIN - PASO 1: VALIDAR CREDENCIALES
      # ============================================
      desc "User login - Step 1: Validate credentials",
            tags: [ "Authentication - Login" ],
            success: { code: 200, message: "Credentials validated" },
            failure: [
              { code: 401, message: "Invalid credentials" },
              { code: 422, message: "Validation error" }
            ],
            detail: "Validates credentials and returns available contexts. If user has multiple contexts, requires Step 2."
      params do
        requires :email,
                  type: String,
                  desc: "User email",
                  documentation: { example: "user@example.com" }
        requires :password,
                  type: String,
                  desc: "User password",
                  documentation: { example: "password123" }
      end
      post :login do
        result = Authentication::LoginStep1Service.call(
          email: params[:email],
          password: params[:password],
          request_info: request_info
        )

        if result.success?
          status 200
          success_response(
            data: result.data,
            message: result.message
          )
        else
          api_error(
            message: result.message || "Authentication failed",
            status: 401,
            errors: result.errors
          )
        end
      end

      # ============================================
      # LOGIN - PASO 2: SELECCIONAR CONTEXTO
      # ============================================
      desc "User login - Step 2: Select context",
            tags: [ "Authentication - Login" ],
            success: { code: 200, message: "Login successful" },
            failure: [
              { code: 401, message: "Invalid session token" },
              { code: 422, message: "Invalid context" }
            ],
            detail: "Selects a specific context by ID and returns JWT token"
      params do
        requires :session_token,
                  type: String,
                  desc: "Session token from Step 1"
        requires :context_id,
                  type: String,
                  desc: "Context ID (e.g., 'platform' or 'membership_123')",
                  documentation: { example: "membership_456" }
      end
      post "login/select-context" do
        result = Authentication::LoginStep2Service.call(
          session_token: params[:session_token],
          context_id: params[:context_id]
        )

        if result.success?
          status 200
          success_response(
            data: result.data,
            message: result.message
          )
        else
          api_error(
            message: result.message || "Context selection failed",
            status: 401,
            errors: result.errors
          )
        end
      end

      # ============================================
      # LOGIN - ACCESO DIRECTO (LEGACY/SIMPLIFICADO)
      # ============================================
      desc "Direct login with context (simplified)",
            tags: [ "Authentication - Login" ],
            success: { code: 200 },
            failure: [ { code: 401, message: "Invalid credentials" } ],
            detail: "Legacy endpoint: login directly with tenant_id. Use two-step flow for better UX."
      params do
        requires :email, type: String
        requires :password, type: String
        optional :tenant_id, type: Integer, desc: "Tenant ID for direct access"
      end
      post "login/direct" do
        # Paso 1: Validar credenciales
        step1_result = Authentication::LoginStep1Service.call(
          email: params[:email],
          password: params[:password],
          request_info: request_info
        )

        if step1_result.failure?
          api_error(
            message: step1_result.message || "Authentication failed",
            status: 401,
            errors: step1_result.errors
          )
        end

        # Determinar contexto automáticamente
        contexts = step1_result.data[:contexts]
        default_context = step1_result.data[:default_context]

        # Si tiene tenant_id, buscar ese contexto
        if params[:tenant_id]
          selected = contexts.find { |c| c[:type] == "tenant" && c[:tenant_id] == params[:tenant_id] }
          unless selected
            api_error(
              message: "Invalid tenant_id or no access",
              status: 403
            )
          end
        else
          # Usar contexto por defecto
          selected = default_context
          unless selected
            api_error(
              message: "Multiple contexts available. Use two-step login.",
              status: 400,
              errors: [ "Please use POST /auth/login and POST /auth/login/select-context" ]
            )
          end
        end

        # Paso 2: Generar token
        step2_result = Authentication::LoginStep2Service.call(
          session_token: step1_result.data[:session_token],
          context_type: selected[:type],
          tenant_id: selected[:tenant_id]
        )

        if step2_result.success?
          status 200
          success_response(
            data: step2_result.data,
            message: "Login successful"
          )
        else
          api_error(
            message: step2_result.message || "Token generation failed",
            status: 401,
            errors: step2_result.errors
          )
        end
      end

      # ============================================
      # LOGOUT
      # ============================================
      desc "User logout",
            tags: [ "Authentication - Tokens" ],
            success: { code: 200, message: "Logout successful" },
            failure: [
              { code: 401, message: "Authentication required" }
            ],
            headers: {
              "Authorization" => {
                description: "Bearer token",
                required: true
              }
            }
      delete :logout do
        authenticate!

        token = extract_token

        result = Authentication::LogoutService.call(
          token: token,
          user: current_user
        )

        if result.success?
          status 200
          success_response(
            data: result.data,
            message: result.message
          )
        else
          api_error(
            message: result.message || "Logout failed",
            status: 400,
            errors: result.errors
          )
        end
      end

      # ============================================
      # REFRESH TOKEN
      # ============================================
      desc "Refresh JWT token",
            tags: [ "Authentication - Tokens" ],
            success: { code: 200, message: "Token refreshed" },
            failure: [
              { code: 401, message: "Invalid or expired token" }
            ],
            headers: {
              "Authorization" => {
                description: "Bearer token",
                required: true
              }
            }
      post :refresh do
        token = extract_token

        unless token
          api_error(
            message: "Token is required",
            status: 401
          )
        end

        result = Authentication::RefreshTokenService.call(token: token)

        if result.success?
          status 200
          success_response(
            data: result.data,
            message: result.message
          )
        else
          api_error(
            message: result.message || "Token refresh failed",
            status: 401,
            errors: result.errors
          )
        end
      end

      # ============================================
      # VALIDATE TOKEN
      # ============================================
      desc "Validate JWT token",
            tags: [ "Authentication - Tokens" ],
            success: { code: 200, message: "Token is valid" },
            failure: [
              { code: 401, message: "Invalid token" }
            ],
            headers: {
              "Authorization" => {
                description: "Bearer token",
                required: true
              }
            }
      get :validate do
        authenticate!

        status 200
        success_response(
          data: {
            valid: true,
            user: {
              id: current_user.id,
              email: current_user.email,
              full_name: current_user.full_name,
              context: current_context,
              tenant_id: current_tenant_id
            },
            expires_at: Time.at(current_payload[:exp].to_i).iso8601
          },
          message: "Token is valid"
        )
      end

      # ============================================
      # ME (Current User Info)
      # ============================================
      desc "Get current user information",
            tags: [ "Authentication - User Info" ],
            success: { code: 200, message: "User information retrieved" },
            failure: [
              { code: 401, message: "Authentication required" }
            ],
            headers: {
              "Authorization" => {
                description: "Bearer token",
                required: true
              }
            }
      get :me do
        authenticate!

        status 200
        success_response(
          data: {
            id: current_user.id,
            email: current_user.email,
            first_name: current_user.first_name,
            last_name: current_user.last_name,
            full_name: current_user.full_name,
            phone: current_user.phone,
            avatar_url: current_user.avatar_url,
            email_verified: current_user.email_verified?,
            context: current_context,
            tenant_id: current_tenant_id,
            created_at: current_user.created_at.iso8601,
            last_login_at: current_user.last_login_at&.iso8601
          }
        )
      end

      # ============================================
      # CONTEXTOS DISPONIBLES
      # ============================================
      desc "Get available contexts for current user",
            tags: [ "Authentication - User Info" ],
            success: { code: 200 },
            failure: [ { code: 401, message: "Authentication required" } ],
            detail: "Returns all contexts (platform and tenants) the user has access to"
      get :contexts do
        authenticate!

        contexts = AvailableContextsQuery.new(current_user).call

        success_response(
          data: {
            contexts: contexts,
            total: contexts.size,
            has_multiple: contexts.size > 1
          }
        )
      end

      # ============================================
      # CAMBIAR CONTEXTO (SWITCH)
      # ============================================
      desc "Switch to a different context",
            tags: [ "Authentication - Context Switch" ],
            success: { code: 200, message: "Context switched successfully" },
            failure: [
              { code: 401, message: "Authentication required" },
              { code: 403, message: "Context not available" },
              { code: 422, message: "Invalid context" }
            ],
            detail: "Switch to a different available context without logging out. Old token is revoked and new token is issued.",
            headers: {
              "Authorization" => {
                description: "Current Bearer token",
                required: true
              }
            }
      params do
        requires :context_type,
                  type: String,
                  values: [ "platform", "tenant" ],
                  desc: "Type of context to switch to"
        optional :tenant_id,
                  type: Integer,
                  desc: "Tenant ID (required if context_type is tenant)"
      end
      post :switch_context do
        authenticate!

        # Extraer token actual del header
        current_token = extract_token

        unless current_token
          error_response(
            message: "Current token not found",
            status: 401
          )
        end

        # Ejecutar servicio de switch
        result = Authentication::SwitchContextService.call(
          current_user: current_user,
          current_token: current_token,
          new_context_type: params[:context_type],
          new_tenant_id: params[:tenant_id]
        )

        if result.success?
          status 200
          success_response(
            data: result.data,
            message: result.message
          )
        else
          error_response(
            message: result.message,
            errors: result.errors,
            status: result.meta && result.meta[:available_contexts] ? 403 : 422
          )
        end
      end
    end

    private

    def extract_token
      auth_header = headers["Authorization"] || headers["authorization"]
      return nil unless auth_header

      match = auth_header.match(/^Bearer\s+(.+)$/i)
      match ? match[1] : nil
    end
  end
end
