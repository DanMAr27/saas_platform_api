# app/api/v1/driver/profile_api.rb

module V1
  module Driver
    class ProfileApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::AuthorizationHelper

      namespace :driver do
        # ============================================
        # DRIVER PROFILE
        # ============================================
        desc "Get driver profile",
              tags: [ "Driver - Profile" ],
              success: { code: 200 }
        get :profile do
          authenticate!

          # Driver specific logic will go here
          # For now just return current user
          present current_user, with: Entities::UserEntity
        end
      end
    end
  end
end
