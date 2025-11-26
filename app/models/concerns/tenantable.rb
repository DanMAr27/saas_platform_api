# frozen_string_literal: true

# Concern para modelos con scope de Tenant (multitenancy)
# Automáticamente filtra registros por tenant_id usando ActsAsTenant
#
# Uso:
#   class Vehicle < ApplicationRecord
#     include Tenantable
#   end
#
# Automáticamente:
# - Filtra por tenant_id en queries
# - Valida que tenant_id esté presente
# - Asigna tenant_id automáticamente al crear
#
# Características:
# - Integración con ActsAsTenant
# - Validaciones automáticas
# - Scopes útiles para queries cross-tenant (solo para admins)

module Tenantable
  extend ActiveSupport::Concern

  included do
    # Habilitar ActsAsTenant en el modelo
    acts_as_tenant(:tenant)

    # Relación con Tenant
    belongs_to :tenant, optional: false

    # Validaciones
    validates :tenant_id, presence: true, unless: -> { skip_tenant_validation? }

    # Callback antes de validación para asignar tenant actual
    before_validation :set_current_tenant, on: :create, if: -> { tenant_id.blank? }

    # Índice recomendado (agregar en migración)
    # add_index :table_name, :tenant_id
  end

  # Métodos de instancia
  module InstanceMethods
    # Verificar si el registro pertenece al tenant actual
    def belongs_to_current_tenant?
      tenant_id == ActsAsTenant.current_tenant&.id
    end

    # Verificar si el registro pertenece a un tenant específico
    def belongs_to_tenant?(tenant_or_id)
      tenant_id_to_check = tenant_or_id.is_a?(Tenant) ? tenant_or_id.id : tenant_or_id
      tenant_id == tenant_id_to_check
    end

    # Obtener el tenant del registro (con cache)
    def current_tenant
      tenant
    end

    private

    # Asignar el tenant actual automáticamente
    def set_current_tenant
      self.tenant_id = ActsAsTenant.current_tenant&.id if ActsAsTenant.current_tenant.present?
    end

    # Permitir skip de validación en casos específicos (ej: seeds, migrations)
    def skip_tenant_validation?
      # En tests o seeds podemos querer skipear la validación
      Rails.env.test? && ActsAsTenant.current_tenant.blank?
    end
  end

  # Métodos de clase
  module ClassMethods
    # Ejecutar query en contexto de un tenant específico
    # Uso: Vehicle.in_tenant(tenant) { Vehicle.all }
    def in_tenant(tenant)
      ActsAsTenant.with_tenant(tenant) do
        yield
      end
    end

    # Obtener registros de todos los tenants (solo para SuperAdmin)
    # CUIDADO: Esto omite el filtrado automático de tenant
    def cross_tenant
      unscoped
    end

    # Obtener registros de múltiples tenants específicos
    def for_tenants(*tenant_ids)
      unscoped.where(tenant_id: tenant_ids.flatten)
    end

    # Contar registros por tenant
    def count_by_tenant
      unscoped.group(:tenant_id).count
    end

    # Verificar si un tenant tiene registros
    def tenant_has_records?(tenant_or_id)
      tenant_id_to_check = tenant_or_id.is_a?(Tenant) ? tenant_or_id.id : tenant_or_id
      unscoped.exists?(tenant_id: tenant_id_to_check)
    end

    # Estadísticas por tenant (útil para dashboards de admin)
    def tenant_stats
      unscoped
        .group(:tenant_id)
        .select("tenant_id, COUNT(*) as count, MAX(created_at) as last_created")
    end
  end

  # Incluir los métodos
  include InstanceMethods
  extend ClassMethods

  # Validaciones adicionales a nivel de concern
  class_methods do
    # Validar que no se cambie el tenant_id después de crear
    def prevent_tenant_id_change
      validate :tenant_id_cannot_change, on: :update
    end
  end

  private

  # Validación: prevenir cambio de tenant_id
  def tenant_id_cannot_change
    if tenant_id_changed? && persisted?
      errors.add(:tenant_id, "cannot be changed after creation")
    end
  end
end
