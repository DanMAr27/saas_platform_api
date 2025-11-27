# db/migrate/XXXXXX_create_organizational_node_closures.rb
# Tabla de closure para queries eficientes de ancestros/descendientes

class CreateOrganizationalNodeClosures < ActiveRecord::Migration[8.0]
  def change
    create_table :organizational_node_closures do |t|
      t.bigint :ancestor_id, null: false
      t.bigint :descendant_id, null: false
      t.integer :depth, null: false, default: 0

      t.timestamps
    end

    # Índices
    add_index :organizational_node_closures, [ :ancestor_id, :descendant_id ],
              unique: true,
              name: 'index_org_node_closures_on_ancestor_and_descendant'
    add_index :organizational_node_closures, :ancestor_id
    add_index :organizational_node_closures, :descendant_id
    add_index :organizational_node_closures, :depth

    # Foreign keys
    add_foreign_key :organizational_node_closures, :organizational_nodes,
                    column: :ancestor_id, on_delete: :cascade
    add_foreign_key :organizational_node_closures, :organizational_nodes,
                    column: :descendant_id, on_delete: :cascade
  end
end
