# db/migrate/XXXXXX_create_organizational_node_levels.rb
# Niveles de la jerarquía organizacional (ej: branch, division, department)

class CreateOrganizationalNodeLevels < ActiveRecord::Migration[8.0]
  def change
    create_table :organizational_node_levels do |t|
      # Relación con tenant
      t.bigint :tenant_id, null: false

      # Identificación del nivel
      t.string :name, null: false, limit: 100
      t.string :slug, null: false, limit: 100
      t.text :description

      # Orden jerárquico (1 = nivel más alto, 2 = siguiente nivel, etc.)
      t.integer :level_order, null: false, default: 1

      # Configuración
      t.boolean :allows_vehicles, default: true, null: false
      t.boolean :allows_users, default: true, null: false
      t.boolean :is_system, default: false, null: false

      # Metadata
      t.jsonb :settings, default: {}

      # Auditoría
      t.bigint :created_by
      t.datetime :deleted_at
      t.bigint :deleted_by

      t.timestamps
    end

    # Índices
    add_index :organizational_node_levels, :tenant_id
    add_index :organizational_node_levels, [ :tenant_id, :slug ],
              unique: true,
              name: 'index_org_node_levels_on_tenant_and_slug',
              where: 'deleted_at IS NULL'
    add_index :organizational_node_levels, :level_order
    add_index :organizational_node_levels, :deleted_at

    # Foreign keys
    add_foreign_key :organizational_node_levels, :tenants, on_delete: :cascade
    add_foreign_key :organizational_node_levels, :users, column: :created_by, on_delete: :nullify
  end
end
