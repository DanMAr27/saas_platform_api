# db/migrate/XXXXXX_create_user_node_scopes.rb
# Scopes de acceso a nodos organizacionales para usuarios

class CreateUserNodeScopes < ActiveRecord::Migration[8.0]
  def change
    create_table :user_node_scopes do |t|
      # Relación usuario-nodo
      t.bigint :user_id, null: false
      t.bigint :organizational_node_id, null: false
      t.bigint :tenant_id, null: false

      # Tipo de acceso
      t.string :access_type, limit: 20, default: 'read', null: false # read, write, admin

      # ¿Incluye nodos hijos?
      t.boolean :include_children, default: true, null: false

      # Auditoría
      t.bigint :created_by
      t.datetime :deleted_at
      t.bigint :deleted_by

      t.timestamps
    end

    # Índices
    add_index :user_node_scopes, :user_id
    add_index :user_node_scopes, :organizational_node_id
    add_index :user_node_scopes, :tenant_id
    add_index :user_node_scopes, [ :user_id, :organizational_node_id, :tenant_id ],
              unique: true,
              name: 'index_user_node_scopes_unique',
              where: 'deleted_at IS NULL'
    add_index :user_node_scopes, :deleted_at

    # Foreign keys
    add_foreign_key :user_node_scopes, :users, on_delete: :cascade
    add_foreign_key :user_node_scopes, :organizational_nodes, on_delete: :cascade
    add_foreign_key :user_node_scopes, :tenants, on_delete: :cascade
    add_foreign_key :user_node_scopes, :users, column: :created_by, on_delete: :nullify
  end
end
