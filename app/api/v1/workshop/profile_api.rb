# app/api/v1/workshop/profile_api.rb

module V1
  module Workshop
    class ProfileApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::AuthorizationHelper

      namespace :workshop do
        # ============================================
        # WORKSHOP PROFILE
        # ============================================
        desc "Get workshop profile",
              tags: [ "Workshop - Profile" ],
              success: { code: 200 }
        get :profile do
          authenticate!

          # Workshop specific logic will go here
          # For now just return current user
          present current_user, with: Entities::UserEntity
        end
      end
    end
  end
end
