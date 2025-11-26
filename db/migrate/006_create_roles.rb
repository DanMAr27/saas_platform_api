# frozen_string_literal: true

# Migración para crear la tabla de Roles
# Catálogo único de roles para todos los contextos (platform, tenant)

class CreateRoles < ActiveRecord::Migration[8.0]
  def change
    create_table :roles do |t|
      # ============================================
      # IDENTIFICACIÓN
      # ============================================
      t.string :name, null: false, limit: 100
      t.string :slug, null: false, limit: 100
      t.text :description

      # ============================================
      # CONTEXTO
      # ============================================
      # Contexto: 'platform', 'tenant'
      t.string :context, null: false, limit: 20

      # ============================================
      # CONFIGURACIÓN
      # ============================================
      # ¿Requiere scopes adicionales? (ej: nodos, vehículos)
      t.boolean :requires_scope, default: false, null: false

      # ¿Es un rol del sistema? (no se puede borrar)
      t.boolean :is_system, default: false, null: false

      # Nivel de prioridad (para ordenar roles)
      t.integer :priority, default: 0, null: false

      # ============================================
      # METADATA
      # ============================================
      t.jsonb :settings, default: {}

      # ============================================
      # TIMESTAMPS
      # ============================================
      t.timestamps
    end

    # ============================================
    # ÍNDICES
    # ============================================

    # Slug único
    add_index :roles, :slug, unique: true, name: 'index_roles_on_slug'

    # Búsqueda por contexto
    add_index :roles, :context, name: 'index_roles_on_context'

    # Solo roles del sistema
    add_index :roles, :is_system, name: 'index_roles_on_is_system'

    # Ordenar por prioridad
    add_index :roles, :priority, name: 'index_roles_on_priority'

    # Índice GIN para settings
    add_index :roles, :settings, using: :gin, name: 'index_roles_on_settings'
  end
end
