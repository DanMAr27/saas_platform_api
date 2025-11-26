# frozen_string_literal: true

module Auditable
  extend ActiveSupport::Concern

  included do
    # Habilitar PaperTrail en el modelo
    has_paper_trail(
      # Eventos que se registran
      on: %i[create update destroy],

      # Campos que NO se versionan (típicamente timestamps automáticos)
      ignore: %i[updated_at created_at],

      # Configuración de versionado
      versions: {
        class_name: "PaperTrail::Version",
        dependent: :destroy
      }
    )
  end

  # Métodos de instancia
  module InstanceMethods
    # Obtener todas las versiones del registro
    def audit_log
      versions.order(created_at: :desc)
    end

    # Obtener la última modificación
    def last_modification
      versions.last
    end

    # Obtener quién creó el registro
    def created_by_user
      return nil unless versions.any?

      User.find_by(id: versions.first.whodunnit)
    end

    # Obtener quién modificó el registro por última vez
    def last_modified_by_user
      return nil unless versions.any?

      User.find_by(id: versions.last.whodunnit)
    end

    # Verificar si el registro ha sido modificado
    def modified?
      versions.count > 1
    end

    # Obtener resumen de cambios para auditoría
    def audit_summary
      {
        created_at: created_at,
        created_by: created_by_user&.email,
        updated_at: updated_at,
        last_modified_by: last_modified_by_user&.email,
        total_changes: versions.count,
        last_change: last_modification&.created_at
      }
    end
  end

  # Métodos de clase
  module ClassMethods
    # Obtener todas las versiones de todos los registros de este modelo
    def audit_trail(limit: 100)
      PaperTrail::Version
        .where(item_type: name)
        .order(created_at: :desc)
        .limit(limit)
    end

    # Obtener cambios recientes (últimas X horas)
    def recent_changes(hours: 24)
      PaperTrail::Version
        .where(item_type: name)
        .where("created_at > ?", hours.hours.ago)
        .order(created_at: :desc)
    end

    # Obtener cambios por usuario
    def changes_by_user(user_id)
      PaperTrail::Version
        .where(item_type: name, whodunnit: user_id.to_s)
        .order(created_at: :desc)
    end
  end

  # Incluir los métodos
  include InstanceMethods
  extend ClassMethods
end
