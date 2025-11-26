# app/api/helpers/application_helper.rb
# Helper base con métodos comunes

module API
  module Helpers
    module ApplicationHelper
      # NOTA: error_response y success_response ahora están definidos en BaseApi
      # para mantener consistencia en toda la API

      # Parsea parámetros de paginación
      def pagination_params
        {
          page: params[:page] || 1,
          per_page: params[:per_page] || 25
        }
      end

      # Metadata de paginación para respuestas
      def pagination_meta(collection)
        {
          current_page: collection.current_page,
          total_pages: collection.total_pages,
          total_count: collection.total_count,
          per_page: collection.limit_value
        }
      end

      # Método auxiliar para extraer información del request
      def request_info
        {
          ip: request.ip,
          user_agent: request.user_agent,
          path: request.path,
          method: request.request_method
        }
      end
    end
  end
end
