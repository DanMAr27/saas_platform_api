module V1
  module Platform
    class UsersApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::AuthorizationHelper
      helpers Helpers::ApplicationHelper

      namespace :platform do
        namespace :users do
          # ============================================
          # BUSCAR USUARIOS (Global)
          # ============================================
          desc "Search or list users globally (SuperAdmin only)",
                tags: [ "Platform - Users" ]
          params do
            optional :search, type: String, desc: "Email or name to search"
            optional :page, type: Integer, default: 1
            optional :per_page, type: Integer, default: 25
          end
          get do
            authenticate!
            authorize!(::User, :index?, policy_class: ::Platform::UserPolicy)

            # Buscar usuarios globalmente
            users = ::User.kept
            users = users.search_by_name(params[:search]) if params[:search].present?
            users = users.page(params[:page]).per(params[:per_page])

            success_response(
              data: users.map { |u| Entities::UserEntity.represent(u) },
              meta: pagination_meta(users)
            )
          end

          # ============================================
          # IMPERSONATE USER
          # ============================================
          desc "Impersonate a user (Support Admin only)",
                tags: [ "Platform - Users" ]
          params do
            requires :id, type: Integer
            requires :reason, type: String
          end
          post ":id/impersonate" do
            # Verificar soporte y permisos
            require_support_admin!

            target_user = ::User.find(params[:id])

            # Verificar política
            authorize!(target_user, :impersonate?, policy_class: ::Platform::UserPolicy)

            # Ejecutar servicio de impersonation
            result = ::Authentication::ImpersonationService.call(
              support_user: current_user,
              target_user: target_user,
              reason: params[:reason]
            )

            if result.success?
              success_response(
                data: { token: result.data[:token] },
                message: "Impersonation started successfully"
              )
            else
              api_error(message: result.message, status: 422)
            end
          end

          # ============================================
          # UNLOCK USER
          # ============================================
          desc "Unlock user account",
                tags: [ "Platform - Users" ]
          params do
            requires :id, type: Integer
          end
          post ":id/unlock" do
            require_super_admin!

            user = ::User.find(params[:id])
            authorize!(user, :unlock?, policy_class: ::Platform::UserPolicy)

            if user.unlock_access!
              success_response(message: "User account unlocked")
            else
              api_error(message: "Failed to unlock user", status: 422)
            end
          end
        end
      end
    end
  end
end
