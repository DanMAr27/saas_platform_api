# db/migrate/XXXXXX_create_user_vehicle_scopes.rb
# Scopes de acceso a vehículos específicos para usuarios

class CreateUserVehicleScopes < ActiveRecord::Migration[8.0]
  def change
    create_table :user_vehicle_scopes do |t|
      # Relación usuario-vehículo
      t.bigint :user_id, null: false
      t.bigint :vehicle_id, null: false
      t.bigint :tenant_id, null: false
      t.bigint :role_id # Optional

      # Tipo de acceso
      t.string :access_type, limit: 20, default: 'read', null: false # read, write, drive

      # Periodo de acceso (opcional)
      t.datetime :valid_from
      t.datetime :valid_until

      # Auditoría
      t.bigint :created_by
      t.datetime :deleted_at
      t.bigint :deleted_by

      t.timestamps
    end

    # Índices
    add_index :user_vehicle_scopes, :user_id
    add_index :user_vehicle_scopes, :vehicle_id
    add_index :user_vehicle_scopes, :tenant_id
    add_index :user_vehicle_scopes, :role_id
    add_index :user_vehicle_scopes, [ :user_id, :vehicle_id, :tenant_id, :role_id ],
              unique: true,
              name: 'index_user_vehicle_scopes_unique',
              where: 'deleted_at IS NULL'
    add_index :user_vehicle_scopes, :deleted_at
    add_index :user_vehicle_scopes, :valid_from
    add_index :user_vehicle_scopes, :valid_until

    # Foreign keys
    add_foreign_key :user_vehicle_scopes, :users, on_delete: :cascade
    add_foreign_key :user_vehicle_scopes, :vehicles, on_delete: :cascade
    add_foreign_key :user_vehicle_scopes, :tenants, on_delete: :cascade
    add_foreign_key :user_vehicle_scopes, :roles, on_delete: :nullify
    add_foreign_key :user_vehicle_scopes, :users, column: :created_by, on_delete: :nullify
  end
end
