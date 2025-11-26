# frozen_string_literal: true

# Migración para actualizar TenantMemberships con role_id
# Mantiene la columna 'role' como string por compatibilidad
# y agrega role_id como FK a la tabla roles

class UpdateTenantMembershipsWithRoleId < ActiveRecord::Migration[8.0]
  def change
    # Agregar columna role_id
    add_column :tenant_memberships, :role_id, :bigint

    # Agregar índice
    add_index :tenant_memberships, :role_id, name: 'index_tenant_memberships_on_role_id'

    # Agregar foreign key
    add_foreign_key :tenant_memberships, :roles, column: :role_id, on_delete: :restrict

    # Nota: No eliminamos la columna 'role' (string) para mantener compatibilidad
    # En el futuro, una vez migrados todos los datos, se puede eliminar
    # con otra migración
  end
end
