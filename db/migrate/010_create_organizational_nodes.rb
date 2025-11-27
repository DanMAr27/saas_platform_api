# db/migrate/XXXXXX_create_organizational_nodes.rb
# Nodos de la estructura organizacional (sucursales, divisiones, departamentos)

class CreateOrganizationalNodes < ActiveRecord::Migration[8.0]
  def change
    create_table :organizational_nodes do |t|
      # Relación con tenant
      t.bigint :tenant_id, null: false

      # Nivel y jerarquía
      t.bigint :level_id, null: false
      t.bigint :parent_id # Nodo padre (null = raíz)

      # Identificación
      t.string :name, null: false, limit: 255
      t.string :code, limit: 50
      t.text :description

      # Ubicación física
      t.string :address, limit: 500
      t.string :city, limit: 100
      t.string :state, limit: 100
      t.string :postal_code, limit: 20
      t.string :country, limit: 2

      # Contacto
      t.string :phone, limit: 20
      t.string :email, limit: 255

      # Estado
      t.string :status, limit: 20, default: 'active', null: false

      # Metadata
      t.jsonb :metadata, default: {}

      # Auditoría
      t.bigint :created_by
      t.datetime :deleted_at
      t.bigint :deleted_by

      t.timestamps
    end
    # Índices
    add_index :organizational_nodes, :tenant_id
    add_index :organizational_nodes, :level_id
    add_index :organizational_nodes, :parent_id
    add_index :organizational_nodes, [ :tenant_id, :code ],
              unique: true,
              where: 'code IS NOT NULL AND deleted_at IS NULL'
    add_index :organizational_nodes, :status
    add_index :organizational_nodes, :deleted_at

    # Foreign keys
    add_foreign_key :organizational_nodes, :tenants, on_delete: :cascade
    add_foreign_key :organizational_nodes, :organizational_node_levels, column: :level_id, on_delete: :restrict
    add_foreign_key :organizational_nodes, :organizational_nodes, column: :parent_id, on_delete: :restrict
    add_foreign_key :organizational_nodes, :users, column: :created_by, on_delete: :nullify
  end
end
