# frozen_string_literal: true

# Configuración de PaperTrail para auditoría de cambios
PaperTrail.config.tap do |config|
  # Habilitar PaperTrail
  config.enabled = true

  # Sin límite de versiones
  config.version_limit = nil

  # Usar JSON para serialización
  config.serializer = PaperTrail::Serializers::JSON
end

# Helper para registrar el contexto en PaperTrail
module PaperTrailHelper
  extend ActiveSupport::Concern

  class_methods do
    # Método para establecer el contexto en servicios
    def with_paper_trail_context(user: nil, tenant: nil, ip_address: nil, user_agent: nil)
      # Guardar whodunnit (quién hizo el cambio)
      PaperTrail.request.whodunnit = user&.id

      # Guardar metadata adicional en el campo JSONB
      PaperTrail.request.controller_info = {
        tenant_id: tenant&.id,
        ip_address: ip_address,
        user_agent: user_agent
      }.compact # Eliminar valores nil

      yield
    ensure
      # Limpiar contexto después de la operación
      PaperTrail.request.whodunnit = nil
      PaperTrail.request.controller_info = {}
    end
  end
end

# Incluir el helper en ActiveRecord para uso global
ActiveRecord::Base.extend(PaperTrailHelper)

# Configuración para consultas de auditoría
module PaperTrailQueries
  # Obtener todas las versiones de un modelo en un tenant
  def self.versions_for_tenant(model_class, tenant_id)
    PaperTrail::Version
      .where(item_type: model_class.name)
      .where("metadata->>'tenant_id' = ?", tenant_id.to_s)
      .order(created_at: :desc)
  end

  # Obtener versiones de un usuario específico
  def self.versions_by_user(user_id)
    PaperTrail::Version
      .where(whodunnit: user_id.to_s)
      .order(created_at: :desc)
  end

  # Obtener cambios recientes (últimas 24 horas)
  def self.recent_changes(hours: 24)
    PaperTrail::Version
      .where("created_at > ?", hours.hours.ago)
      .order(created_at: :desc)
  end
end
