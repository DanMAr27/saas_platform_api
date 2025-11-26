# frozen_string_literal: true

# Concern para Soft Delete usando gem 'discard'
# Permite "eliminar" registros sin borrarlos físicamente de la BD
#
# Uso:
#   class User < ApplicationRecord
#     include SoftDeletable
#   end
#
#   user.discard  # Soft delete
#   user.undiscard # Restaurar
#   User.kept # Solo registros no eliminados
#   User.discarded # Solo registros eliminados
#
# Características:
# - Usa deleted_at para marcar registros eliminados
# - Guarda deleted_by para auditoría
# - Proporciona scopes automáticos (kept, discarded)
# - Integración con PaperTrail para registrar eliminación

module SoftDeletable
  extend ActiveSupport::Concern

  included do
    # Habilitar discard (soft delete)
    include Discard::Model
    self.discard_column = :deleted_at

    # Validación: no permitir operaciones en registros eliminados
    # (a menos que se use unscoped)
    validate :prevent_operations_on_discarded, unless: :new_record?

    # Callback antes de discard para guardar quién eliminó
    before_discard :set_deleted_by

    # Callback antes de undiscard para limpiar deleted_by
    before_undiscard :clear_deleted_by
  end

  # Métodos de instancia
  module InstanceMethods
    # Soft delete con usuario que realiza la acción
    def discard_by(user)
      update_column(:deleted_by, user&.id) if respond_to?(:deleted_by)
      discard
    end

    # Restaurar registro eliminado
    def restore
      undiscard
    end

    # Verificar si está eliminado
    def deleted?
      discarded?
    end

    # Obtener usuario que eliminó el registro
    def deleted_by_user
      return nil unless respond_to?(:deleted_by) && deleted_by.present?

      User.unscoped.find_by(id: deleted_by)
    end

    # Información de eliminación para auditoría
    def deletion_info
      return nil unless deleted?

      {
        deleted_at: deleted_at,
        deleted_by: deleted_by_user&.email,
        can_restore: true
      }
    end

    private

    # Callback: guardar quién eliminó
    def set_deleted_by
      # Se setea desde el servicio usando current_user
      if respond_to?(:deleted_by=) && PaperTrail.request.whodunnit.present?
        self.deleted_by = PaperTrail.request.whodunnit
      end
    end

    # Callback: limpiar deleted_by al restaurar
    def clear_deleted_by
      self.deleted_by = nil if respond_to?(:deleted_by=)
    end

    # Validación: prevenir modificaciones en registros eliminados
    def prevent_operations_on_discarded
      if discarded? && !changes.keys.include?("deleted_at")
        errors.add(:base, "Cannot modify a deleted record")
      end
    end
  end

  # Métodos de clase
  module ClassMethods
    # Scope para obtener solo registros activos (alias de kept)
    def active
      kept
    end

    # Scope para obtener registros eliminados recientemente (últimas 24h)
    def recently_deleted(hours: 24)
      discarded.where("deleted_at > ?", hours.hours.ago)
    end

    # Restaurar múltiples registros
    def restore_all(ids)
      unscoped.where(id: ids).update_all(
        deleted_at: nil,
        deleted_by: nil
      )
    end

    # Eliminar permanentemente registros que fueron eliminados hace mucho tiempo
    # CUIDADO: Esto elimina físicamente de la BD
    def purge_deleted_older_than(days:)
      discarded
        .where("deleted_at < ?", days.days.ago)
        .destroy_all
    end
  end

  # Incluir los métodos
  include InstanceMethods
  extend ClassMethods
end
